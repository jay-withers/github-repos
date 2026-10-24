# What lets a consumer's pipeline apply, not just keep state: Contributor on
# each resource group it owns, and Reader on the subscription. Reader is what
# a plan needs to check resource provider registration and to resolve other
# repos' resources by data source (a tenant looking up the shared Container
# Apps environment, say). Contributor cannot create role assignments, so a
# configuration that grants roles still needs a local apply for those.
#
# principal_type is set explicitly for the same reason as state.tf.
resource "azurerm_role_assignment" "deploy" {
  for_each = local.deploy_resource_groups

  scope                = data.azurerm_resource_group.deploy[each.key].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.state[each.value.consumer].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deploy_reader" {
  for_each = local.deploy_consumers

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.state[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
