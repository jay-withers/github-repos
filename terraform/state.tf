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

  scope                = data.azurerm_storage_container.consumer[each.key].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.state[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
