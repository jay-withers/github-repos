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

# Joining a Container Apps environment is a linked permission: writing a
# container app or job checks `Microsoft.App/managedEnvironments/join/action`
# on its environment as well as write on the app itself, and fails with
# LinkedAuthorizationFailed without it. No built-in role grants join without
# also granting write on the environment, which belongs to
# azure-container-apps, so this custom role carries join and read and
# nothing else.
resource "azurerm_role_definition" "container_app_environment_join" {
  count = length(local.join_container_app_environments) > 0 ? 1 : 0

  name        = "Container Apps Environment Joiner"
  scope       = data.azurerm_subscription.current.id
  description = "Run container apps and jobs on a Container Apps environment without changing it. Managed by jay-withers/github-repos."

  permissions {
    actions = [
      "Microsoft.App/managedEnvironments/read",
      "Microsoft.App/managedEnvironments/join/action",
    ]
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

resource "azurerm_role_assignment" "deploy_join" {
  for_each = local.join_container_app_environments

  scope              = data.azurerm_container_app_environment.join[each.key].id
  role_definition_id = azurerm_role_definition.container_app_environment_join[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.state[each.value.consumer].principal_id
  principal_type     = "ServicePrincipal"
}
