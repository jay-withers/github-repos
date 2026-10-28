# What lets a consumer's pipeline apply, not just keep state: Contributor on
# each resource group it owns, and Reader on the subscription. Reader is what
# a plan needs to check resource provider registration and to resolve other
# repos' resources by data source (a tenant looking up the shared Container
# Apps environment, say). Contributor cannot create role assignments: with
# `create_resource_groups` the conditioned RBAC Administrator below covers
# those inside the group; without it they still need a local apply.
#
# principal_type is set explicitly for the same reason as state.tf.
resource "azurerm_role_assignment" "deploy" {
  for_each = local.deploy_resource_groups

  scope                = local.deploy_resource_group_ids[each.key]
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.state[each.value.consumer].principal_id
  principal_type       = "ServicePrincipal"
}

# Consumer resource groups owned here (`create_resource_groups`), so a repo's
# pipeline can apply from its very first run. Same tags as the groups the
# repos used to create, so importing one shows no diff.
#
# prevent_destroy because deleting a group deletes every app, vault and
# storage account in it: dropping a consumer, or turning its
# create_resource_groups off, fails the plan until this is lifted or the
# group is moved out of state on purpose.
resource "azurerm_resource_group" "deploy" {
  for_each = local.created_resource_groups

  name     = each.value.resource_group
  location = var.deploy_location
  tags = {
    environment = local.state_environment
    managed-by  = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Role assignments inside the consumer's own group (its Key Vault, its storage
# containers) from its pipeline, so a change that adds one applies in CD
# rather than locally. Conditioned so the pipeline can grant any role but the
# three that grant roles: see local.rbac_admin_condition. Only for groups
# owned here; a looked-up group's repo still applies role assignments locally.
resource "azurerm_role_assignment" "deploy_rbac_admin" {
  for_each = local.created_resource_groups

  scope                = azurerm_resource_group.deploy[each.key].id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.state[each.value.consumer].principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.rbac_admin_condition
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

# Lets a consumer's deploy workflow and workloads write Deployments_CL and
# OpsEvents_CL rows through the platform's events rule. Granted here, beside
# the identity, because it is a role assignment and no pipeline identity may
# create one - including azure-container-apps', which owns the rule.
resource "azurerm_role_assignment" "events_publisher" {
  for_each = local.event_consumers

  scope                = data.azurerm_monitor_data_collection_rule.events[0].id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.state[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
