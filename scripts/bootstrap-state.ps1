#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Idempotently creates (or corrects) this repo's Terraform remote-state
    storage account: resource group, storage account, blob versioning/soft-
    delete, this repo's own github-repos container, and the operator's own
    data-plane RBAC grant. Every other consumer's container is Terraform's
    (terraform/state.tf), created when it is added to var.state_consumers.

    It also creates this repo's CI apply identity, uai-github-repos-apply-dev:
    its federated credential for the main-only `apply` environment,
    Contributor + User Access Administrator on the subscription, and Storage
    Blob Data Contributor on the github-repos container. With -BudgetAmount,
    it also creates a monthly subscription budget. Both need an Owner of the
    subscription, which is why they're here and not in Terraform: no apply of
    this repo, running as that identity, can change its own rights.

.DESCRIPTION
    This is deliberately NOT Terraform. With shared storage-account keys
    disabled, a Terraform-created storage account needs the applier's own
    identity to already hold a data-plane role on the account before it can
    create anything inside it (a container, a role assignment written via
    `terraform init`'s state write) — but the account doesn't exist yet, so
    there's nothing to hold a role on. A stateless, idempotent script sidesteps
    that entirely: it has no backend of its own to bootstrap, and every step
    below checks what already exists before creating anything, so it's safe
    to re-run. Adding a consumer no longer needs it.

    PowerShell is only the scripting shell here — every Azure call shells out
    to the `az` CLI (from mise via jay-withers/toolchain; no Az
    PowerShell modules required) via the Invoke-Az helper below. az CLI only
    signals failure through its process exit code, not a real exception the
    way Az PowerShell cmdlets do, so Invoke-Az checks that exit code itself
    on every call and throws with az's own stderr text attached — relying on
    $ErrorActionPreference alone here would either miss native-command
    failures entirely or (via $PSNativeCommandUseErrorActionPreference)
    surface only a generic "non-zero exit code" with the real reason lost.

    The github-repos container is created via `az storage container-rm`
    (the ARM/control-plane command group), not the data-plane
    `az storage container` commands — Contributor covers control plane, so
    no RBAC grant is needed just to create a container. Terraform creates
    the others the same way. Only github-repos' own is here, because this
    repo's backend must exist before its first `terraform init`.

    Once this script has run, Terraform only needs to *look up* the account
    (a data source), never create it — see terraform/variables.tf's
    resource_group_name/storage_account_name/location defaults and
    terraform/state.tf/identities.tf for the consuming side.

    Resource group, storage account name, and location are hardcoded below
    rather than taken as parameters: this script bootstraps one specific
    account — the "shared" account this repo's terraform/backend.tf points at
    and terraform/variables.tf's defaults must match. A different account
    (e.g. azure-landingzone's "platform" account) is a separate copy of this
    script with those three values changed — see that repo.

.PARAMETER OperatorPrincipalId
    Identity (object ID, UPN, or service principal app ID — anything `az
    role assignment create --assignee` accepts) to grant Storage Blob Data
    Contributor at account scope, so the signed-in operator can run
    `terraform init`/`apply` against this backend at all — without storage
    keys, everything (including Terraform's own state writes) goes through
    RBAC. Defaults to whichever identity `az login` is currently signed in
    as.

.PARAMETER BudgetAmount
    Monthly subscription budget, in the billing currency. 0 (the default)
    leaves budgets alone: in a tenant with azure-landingzone, its
    `governance` component owns the subscription budget. Set it where there
    is no landing zone, above all on pay-as-you-go, where nothing else stops
    spend.

.PARAMETER BudgetEmails
    Who the budget notifies: at 80% of actual spend, and at 100% of forecast.
    Required with -BudgetAmount.

.EXAMPLE
    # Uses the hardcoded account identity.
    ./scripts/bootstrap-state.ps1

.EXAMPLE
    # A tenant without the landing zone: also a 50/month subscription budget.
    ./scripts/bootstrap-state.ps1 -BudgetAmount 50 -BudgetEmails you@example.com
#>
[CmdletBinding()]
param(
    [string]$OperatorPrincipalId = (az account show --query user.name -o tsv),
    [int]$BudgetAmount = 0,
    [string[]]$BudgetEmails = @()
)

if ($BudgetAmount -gt 0 -and $BudgetEmails.Count -eq 0) {
    throw "-BudgetAmount needs -BudgetEmails: a budget nobody hears from does nothing."
}

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

# This script bootstraps exactly one account - the "shared" state account
# terraform/backend.tf and terraform/variables.tf's defaults point at. A
# different account is a different copy of this script with these three
# changed - see the header comment.
$ResourceGroupName = "rg-tfstate-shared"
$StorageAccountName = "sttfsharedjw"
$Location = "westeurope"

# This repo's own backend container (versions.tf). Every other consumer's
# container is created by terraform/state.tf.
$Container = "github-repos"

# The CI apply identity. Its name must match terraform/locals.tf's
# apply_identity_name, which actions.tf looks up. The subject is the OIDC
# subject of this repo's `apply` environment, in GitHub's immutable form
# (owner and repo IDs from `gh api repos/jay-withers/github-repos --jq
# '{id, owner: .owner.id}'`). The readable repo:<owner>/<repo> form never
# matches its tokens (AADSTS700213). Neither changes with the Azure tenant.
$ApplyIdentityName = "uai-github-repos-apply-dev"
$ApplySubject = "repo:jay-withers@288264678/github-repos@1345898182:environment:apply"
$BudgetName = "budget-subscription-monthly"

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

# 4. This repo's backend container — via the ARM-based `container-rm` command
# group, control plane only, so ordinary Contributor is enough to create it.
$existing = Invoke-Az storage container-rm exists --storage-account $StorageAccountName --resource-group $ResourceGroupName `
    --name $Container --query exists -o tsv
if ($existing -ne "true") {
    Write-Host "Creating container $Container..."
    Invoke-Az storage container-rm create --storage-account $StorageAccountName --resource-group $ResourceGroupName `
        --name $Container --public-access off --output none | Out-Null
}
else {
    Write-Host "Container $Container already exists."
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

# 6. The CI apply identity and its federated credential. Effectively Owner,
# which makes it the exception to "keep grants targeted": github-repos creates
# every other pipeline identity's grants, including Role Based Access Control
# Administrator and a custom role at subscription scope, and that takes
# Contributor plus User Access Administrator. What keeps it to merged code:
# the credential trusts only the `apply` environment, which github-repos
# restricts to main.
$idJson = Invoke-Az identity show --resource-group $ResourceGroupName --name $ApplyIdentityName -AllowFailure
if ($LastAzExitCode -ne 0) {
    Write-Host "Creating identity $ApplyIdentityName..."
    $idJson = Invoke-Az identity create --resource-group $ResourceGroupName --name $ApplyIdentityName `
        --location $Location --tags "owner=jay" "component=identity" "managed-by=bootstrap-state.ps1"
}
else {
    Write-Host "Identity $ApplyIdentityName already exists."
}
$applyIdentity = $idJson | ConvertFrom-Json

$credJson = Invoke-Az identity federated-credential show --resource-group $ResourceGroupName `
    --identity-name $ApplyIdentityName --name "github-repos-apply" -AllowFailure
if ($LastAzExitCode -ne 0 -or ($credJson | ConvertFrom-Json).subject -ne $ApplySubject) {
    Write-Host "Setting federated credential github-repos-apply ($ApplySubject)..."
    $credVerb = if ($LastAzExitCode -ne 0) { "create" } else { "update" }
    Invoke-Az identity federated-credential $credVerb --resource-group $ResourceGroupName `
        --identity-name $ApplyIdentityName --name "github-repos-apply" `
        --issuer "https://token.actions.githubusercontent.com" --subject $ApplySubject `
        --audiences "api://AzureADTokenExchange" --output none | Out-Null
}
else {
    Write-Host "Federated credential github-repos-apply is current."
}

# 7. Its grants. principal-type is always given: without it the CLI looks the
# principal up in Entra, which fails intermittently on a just-created identity.
$subscriptionScope = "/subscriptions/$(Invoke-Az account show --query id -o tsv)"
$containerScope = "$($sa.id)/blobServices/default/containers/$Container"
$grants = @(
    @{ Role = "Contributor"; Scope = $subscriptionScope },
    @{ Role = "User Access Administrator"; Scope = $subscriptionScope },
    # Owner and User Access Administrator grant no blob data access, and the
    # account has shared keys off. Its own container only.
    @{ Role = "Storage Blob Data Contributor"; Scope = $containerScope }
)
foreach ($grant in $grants) {
    $found = Invoke-Az role assignment list --assignee $applyIdentity.principalId --role $grant.Role `
        --scope $grant.Scope -o json | ConvertFrom-Json
    if ($found.Count -eq 0) {
        Write-Host "Granting $($grant.Role) to $ApplyIdentityName on $($grant.Scope)..."
        Invoke-Az role assignment create --assignee-object-id $applyIdentity.principalId `
            --assignee-principal-type ServicePrincipal --role $grant.Role --scope $grant.Scope `
            --output none | Out-Null
    }
    else {
        Write-Host "$ApplyIdentityName already has $($grant.Role) on $($grant.Scope)."
    }
}

# 8. Optional subscription budget, through the REST API: `az consumption
# budget` can't set notifications. A budget only notifies; nothing in Azure
# stops spend. An existing budget keeps its start date, because the API
# refuses to move it.
if ($BudgetAmount -gt 0) {
    $budgetUrl = "https://management.azure.com$subscriptionScope/providers/Microsoft.Consumption/budgets/$($BudgetName)?api-version=2023-05-01"
    $existingBudget = Invoke-Az rest --method get --url $budgetUrl -AllowFailure
    $startDate = if ($LastAzExitCode -eq 0) {
        ($existingBudget | ConvertFrom-Json).properties.timePeriod.startDate
    }
    else {
        (Get-Date -Day 1).ToString("yyyy-MM-01T00:00:00Z")
    }
    $body = @{
        properties = @{
            category      = "Cost"
            amount        = $BudgetAmount
            timeGrain     = "Monthly"
            timePeriod    = @{ startDate = $startDate }
            notifications = @{
                actual80      = @{ enabled = $true; operator = "GreaterThan"; threshold = 80; thresholdType = "Actual"; contactEmails = $BudgetEmails }
                forecasted100 = @{ enabled = $true; operator = "GreaterThan"; threshold = 100; thresholdType = "Forecasted"; contactEmails = $BudgetEmails }
            }
        }
    } | ConvertTo-Json -Depth 6
    $bodyFile = New-TemporaryFile
    try {
        Set-Content -Path $bodyFile -Value $body
        Write-Host "Setting subscription budget $BudgetName to $BudgetAmount a month..."
        Invoke-Az rest --method put --url $budgetUrl --body "@$bodyFile" --output none | Out-Null
    }
    finally {
        Remove-Item $bodyFile
    }
}

Write-Host "Done. $StorageAccountName is ready with container $Container, and $ApplyIdentityName is granted."
