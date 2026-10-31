# This repo's own state container: its backend (versions.tf). Not a consumer,
# since this repo plans and applies only as azure-landingzone's apply identity,
# which holds its own grant on this container. Moved out of the consumer map
# when the `dev` environment and its identity went, so nothing touches it.
resource "azurerm_storage_container" "self" {
  #checkov:skip=CKV2_AZURE_21:Blob logging is an account setting, and the account is scripts/bootstrap-state.ps1's, not this module's.
  name                  = "github-repos"
  storage_account_id    = data.azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

moved {
  from = azurerm_storage_container.consumer["github-repos"]
  to   = azurerm_storage_container.self
}

# One container per consumer, created here rather than by
# scripts/bootstrap-state.ps1, so adding a consumer is one tfvars entry. With
# storage_account_id set, azurerm creates the container through the
# Microsoft.Storage control plane, the same route as the script's
# `az storage container-rm`, so the apply identity's Contributor is enough and
# no data-plane role on the account is needed. The script still creates the
# github-repos container itself: this repo's backend has to exist before its
# first `terraform init`.
#
# prevent_destroy because each one holds another repo's state: dropping a
# consumer from var.state_consumers must not delete it. Remove the container
# from state (a `removed` block) and delete it by hand if that is really meant.
resource "azurerm_storage_container" "consumer" {
  #checkov:skip=CKV2_AZURE_21:Blob logging is an account setting, and the account is scripts/bootstrap-state.ps1's, not this module's.
  for_each = var.state_consumers

  name                  = each.key
  storage_account_id    = data.azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# Container-scoped, not account-scoped - each consumer can read and write
# only its own state, never another consumer's. The account-wide grant that
# `terraform init`/`apply` itself needs to run at all (for this repo's own
# migration into the account) is created by scripts/bootstrap-state.ps1 for
# the human operator, not here.
#
# principal_type is set explicitly. Without it azurerm looks the principal up
# in Entra, which fails intermittently on a just-created identity that has
# not finished replicating - same reasoning as azure-landingzone's
# landingzones/main.rbac.tf.
resource "azurerm_role_assignment" "state_access" {
  for_each = var.state_consumers

  scope                = azurerm_storage_container.consumer[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.state[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
