#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Idempotently creates (or corrects) this repo's Terraform remote-state
    storage account: resource group, storage account, blob versioning/soft-
    delete, this repo's own state container, and the operator's own data-plane
    RBAC grant.

.DESCRIPTION
    This is deliberately NOT Terraform. With shared storage-account keys
    disabled, a Terraform-created storage account needs the applier's own
    identity to already hold a data-plane role on the account before it can
    create anything inside it (a container, a role assignment written via
    `terraform init`'s state write) — but the account doesn't exist yet, so
    there's nothing to hold a role on. A stateless, idempotent script sidesteps
    that entirely: it has no backend of its own to bootstrap, and every step
    below checks what already exists before creating anything, so it's safe
    to re-run at any time.

    It creates exactly ONE container — the one this repo's own backend block
    (terraform/versions.tf) points at, which has to exist before `terraform
    init` can run at all. Every other state repo's container is Terraform's
    (terraform/state.tf, driven by var.repos' remote_state), so onboarding a
    repo needs no run of this script; that container is created here only
    because nothing else can create it first.

    PowerShell is only the scripting shell here — every Azure call shells out
    to the `az` CLI (already on PATH in the dev container image; no Az
    PowerShell modules required) via the Invoke-Az helper below. az CLI only
    signals failure through its process exit code, not a real exception the
    way Az PowerShell cmdlets do, so Invoke-Az checks that exit code itself
    on every call and throws with az's own stderr text attached — relying on
    $ErrorActionPreference alone here would either miss native-command
    failures entirely or (via $PSNativeCommandUseErrorActionPreference)
    surface only a generic "non-zero exit code" with the real reason lost.

    That container is created via `az storage container-rm` (the ARM/control-
    plane command group), not the data-plane `az storage container` commands
    — Contributor covers control plane, so no RBAC grant is needed just to
    create a container. This is the same mechanism Terraform's own AVM
    storage-account module uses internally, and the same one
    terraform/state.tf's azurerm_storage_container uses via
    `storage_account_id`, for the same reason.

    Once this script has run, Terraform only needs to *look up* the account
    (a data source), never create it — see terraform/variables.tf's
    resource_group_name/storage_account_name/location defaults and
    terraform/state.tf/identities.tf for the consuming side.

    Resource group, storage account name, container and location are hardcoded
    below rather than taken as parameters: this script bootstraps one specific
    account — the "shared" account this repo's backend block in
    terraform/versions.tf points at and terraform/variables.tf's defaults must
    match. A different account (e.g. azure-landingzone's "platform" account)
    is a separate copy of this script with those values changed — see that
    repo.

.PARAMETER OperatorPrincipalId
    Identity (object ID, UPN, or service principal app ID — anything `az
    role assignment create --assignee` accepts) to grant Storage Blob Data
    Contributor at account scope, so the signed-in operator can run
    `terraform init`/`apply` against this backend at all — without storage
    keys, everything (including Terraform's own state writes) goes through
    RBAC. Defaults to whichever identity `az login` is currently signed in
    as.

.EXAMPLE
    # Uses the hardcoded account identity; safe to re-run.
    ./scripts/bootstrap-state.ps1

.EXAMPLE
    # Granting a second operator (e.g. a break-glass account) state access.
    ./scripts/bootstrap-state.ps1 -OperatorPrincipalId someone@example.com
#>
[CmdletBinding()]
param(
    [string]$OperatorPrincipalId = (az account show --query user.name -o tsv)
)

$ErrorActionPreference = "Stop"

# Runs `az`, returning its stdout (joined into one string - most calls here
# either read one JSON document or one `-o tsv` scalar). On a non-zero exit,
# throws with az's own stderr attached, so a failure is loud and says why -
# see the header comment for why this exists instead of relying on
# $ErrorActionPreference/$PSNativeCommandUseErrorActionPreference alone.
# -AllowFailure is for a deliberate does-this-exist probe: check
# $script:LastAzExitCode afterwards instead of treating non-zero as fatal.
#
# Deliberately NOT an advanced function - no [CmdletBinding()], and
# -AllowFailure has no [Parameter()] attribute - either one would make
# PowerShell auto-add the common parameters (-OutVariable, -ErrorAction, ...)
# and then try to bind az's own short flags against them: `-o` (for
# `--output`) partial-matches both -OutVariable and -OutBuffer and blows up
# with "'o' is ambiguous" before az ever runs. Staying a simple function
# means az's arguments land untouched in $args.
function Invoke-Az {
    param([switch]$AllowFailure)

    $raw = & az @args 2>&1
    $script:LastAzExitCode = $LASTEXITCODE
    $stdout = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderr = @($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() })

    if ($script:LastAzExitCode -ne 0 -and -not $AllowFailure) {
        # ($args | ForEach-Object { $_ }), not $args directly - a nested
        # array argument (e.g. -Tags) renders as the literal text
        # "System.Object[]" under a plain -join; piping it through
        # ForEach-Object first flattens it into its actual string elements.
        $flatArgs = $args | ForEach-Object { $_ }
        throw "az $($flatArgs -join ' ') failed (exit $script:LastAzExitCode):`n$($stderr -join "`n")"
    }
    return ($stdout -join "`n")
}

# Same tag shape as azure-landingzone's resource groups (environment/owner/
# component/managed-by - see `az group list --query "[].tags"`). `environment`
# specifically is enforced by this subscription's "require-env-tag-dev" policy
# assignment (any resource group missing it is denied outright); the rest are
# just kept consistent. managed-by names this script rather than "terraform"
# since, unlike those other resource groups, this one deliberately isn't.
$Tags = @("environment=dev", "owner=jay", "component=state", "managed-by=bootstrap-state.ps1")

# This script bootstraps exactly one account - the "shared" state account the
# backend block in terraform/versions.tf and terraform/variables.tf's defaults
# point at. A different account is a different copy of this script with these
# changed - see the header comment. $BootstrapContainer must match that
# backend block's container_name: it is this repo's own state container, the
# only one this script creates.
$ResourceGroupName = "rg-tfstate-shared"
$StorageAccountName = "sttfsharedjw"
$BootstrapContainer = "github-repos"
$Location = "westeurope"

# 1. Resource group.
$rgExists = Invoke-Az group exists --name $ResourceGroupName -o tsv
if ($rgExists -ne "true") {
    Write-Host "Creating resource group $ResourceGroupName..."
    Invoke-Az group create --name $ResourceGroupName --location $Location --tags $Tags --output none | Out-Null
}
else {
    Write-Host "Resource group $ResourceGroupName already exists."
}

# 2. Storage account. No shared keys, TLS 1.2 minimum, no public blob access —
# RBAC is the only door in, matching Loki's storage account in
# terraform-root-aks/terraform/main.loki.tf. Public NETWORK access stays
# enabled: GitHub-hosted runners have no static egress and there's no
# self-hosted runner in this lab, so there is no private-networking option
# here — AAD-only auth plus per-container RBAC is the security boundary.
$saJson = Invoke-Az storage account show --resource-group $ResourceGroupName --name $StorageAccountName -AllowFailure
if ($LastAzExitCode -ne 0) {
    Write-Host "Creating storage account $StorageAccountName..."
    $saJson = Invoke-Az storage account create --resource-group $ResourceGroupName --name $StorageAccountName `
        --location $Location --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 `
        --allow-shared-key-access false --allow-blob-public-access false --tags $Tags
}
else {
    Write-Host "Storage account $StorageAccountName already exists — checking for drift..."
    $sa = $saJson | ConvertFrom-Json
    if ($sa.allowSharedKeyAccess -ne $false -or $sa.minimumTlsVersion -ne "TLS1_2") {
        Write-Host "Correcting drift on $StorageAccountName (shared keys / TLS version)..."
        $saJson = Invoke-Az storage account update --resource-group $ResourceGroupName --name $StorageAccountName `
            --allow-shared-key-access false --min-tls-version TLS1_2
    }
}
$sa = $saJson | ConvertFrom-Json

# 3. Blob versioning + soft delete. State files are exactly the case where
# this earns its keep — cheap (a handful of small JSON blobs), and the actual
# defence against losing state, not account replication.
Write-Host "Ensuring blob versioning and soft-delete retention on $StorageAccountName..."
Invoke-Az storage account blob-service-properties update --resource-group $ResourceGroupName --account-name $StorageAccountName `
    --enable-versioning true --enable-delete-retention true --delete-retention-days 30 `
    --enable-restore-policy false --output none | Out-Null

# 4. This repo's own state container — via the ARM-based `container-rm`
# command group, control plane only, so ordinary Contributor is enough to
# create it. Only this one: every other state repo's container is Terraform's
# (terraform/state.tf). This one can't be, because terraform/versions.tf's
# backend block already points at it before Terraform has run once.
$containerExists = Invoke-Az storage container-rm exists --storage-account $StorageAccountName --resource-group $ResourceGroupName `
    --name $BootstrapContainer --query exists -o tsv
if ($containerExists -ne "true") {
    Write-Host "Creating container $BootstrapContainer..."
    Invoke-Az storage container-rm create --storage-account $StorageAccountName --resource-group $ResourceGroupName `
        --name $BootstrapContainer --public-access off --output none | Out-Null
}
else {
    Write-Host "Container $BootstrapContainer already exists."
}

# 5. Operator RBAC. Without this, `terraform init`/`apply` against this
# backend cannot write the state blob at all — there are no keys, so this
# grant is the only way in for the human running Terraform.
$scope = $sa.id
$existingAssignments = Invoke-Az role assignment list --assignee $OperatorPrincipalId --role "Storage Blob Data Contributor" `
    --scope $scope -o json | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    Write-Host "Granting Storage Blob Data Contributor to $OperatorPrincipalId on $StorageAccountName..."
    Invoke-Az role assignment create --assignee $OperatorPrincipalId --role "Storage Blob Data Contributor" `
        --scope $scope --output none | Out-Null
}
else {
    Write-Host "$OperatorPrincipalId already has Storage Blob Data Contributor on $StorageAccountName."
}

Write-Host "Done. $StorageAccountName is ready, with container $BootstrapContainer."
