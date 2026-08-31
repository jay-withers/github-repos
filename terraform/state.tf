# One container per state repo, named after the repo. Managed here rather
# than by scripts/bootstrap-state.ps1 so onboarding a repo is a single
# remote_state flag in terraform.tfvars plus an apply - the script now only
# bootstraps the account itself, which genuinely can't be Terraform (see its
# header comment).
#
# storage_account_id, not the deprecated storage_account_name: that selects
# azurerm 4.x's control-plane (ARM) implementation of this resource, the same
# API `az storage container-rm` uses. The data-plane variant would need the
# applier to hold a data-plane role on the account first, which is exactly the
# chicken-and-egg the bootstrap script exists to avoid.
resource "azurerm_storage_container" "state" {
  # Storage logging for blob reads is a diagnostic setting on the ACCOUNT, and
  # the account is bootstrap-script territory, not Terraform's - there is
  # nothing this resource could set to satisfy this check. Read auditing on a
  # personal lab's state blobs also buys nothing: the identities that can read
  # them are exactly the ones declared below.
  #checkov:skip=CKV2_AZURE_21:Blob read logging is an account-level diagnostic setting; this account is created by scripts/bootstrap-state.ps1, not Terraform.
  for_each = local.state_targets

  name                  = each.key
  storage_account_id    = data.azurerm_storage_account.state.id
  container_access_type = "private"

  # These hold Terraform state. Removing a repo's remote_state flag (or an
  # environment from its list) should never quietly delete the state that goes
  # with it - offboarding is deliberate enough to be worth also deleting this
  # block first.
  lifecycle {
    prevent_destroy = true
  }
}

# Container-scoped, not account-scoped - each repo can read and write only its
# own state, never another's. The account-wide grant that `terraform init`/
# `apply` itself needs to run at all (for this repo's own migration into the
# account) is created by scripts/bootstrap-state.ps1 for the human operator,
# not here.
#
# principal_type is set explicitly. Without it azurerm looks the principal up
# in Entra, which fails intermittently on a just-created identity that has
# not finished replicating - same reasoning as azure-landingzone's
# landingzones/main.rbac.tf.
resource "azurerm_role_assignment" "state_access" {
  for_each = local.state_targets

  scope                = azurerm_storage_container.state[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.state[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# This repo's own container is the one exception to "Terraform creates the
# containers": scripts/bootstrap-state.ps1 has to create it before `terraform
# init` can talk to the backend at all (versions.tf's backend block points
# straight at it). So Terraform adopts it rather than creating it. This is
# permanent, not a one-off migration step - on any rebuild of the account that
# container is again the one thing that exists before Terraform runs.
# The key has to be a literal - an import block's `to` takes only constant
# indexes, no variables - so it repeats local.bootstrap_container rather than
# referencing it. Keep the two in step.
import {
  to = azurerm_storage_container.state["github-repos"]
  id = "${data.azurerm_storage_account.state.id}/blobServices/default/containers/${local.bootstrap_container}"
}
