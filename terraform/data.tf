# The "shared" Terraform state storage account - for repos that need state
# storage but aren't part of the azure-landingzone landing zone. Created by
# scripts/bootstrap-state.ps1, not Terraform - see that script's header
# comment for why (shared account keys are disabled, so a plain Terraform
# resource would need a data-plane role on the account before it could create
# anything inside it, and the account doesn't exist yet to hold a role on).
# This file only ever looks it up.
data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "state" {
  name = var.resource_group_name
}

data "azurerm_storage_account" "state" {
  name                = var.storage_account_name
  resource_group_name = data.azurerm_resource_group.state.name
}

data "azurerm_storage_container" "consumer" {
  for_each = var.state_consumers

  name               = each.key
  storage_account_id = data.azurerm_storage_account.state.id
}

# Resource groups a consumer's pipeline applies into, for consumers that
# still create their own with a local first apply. Groups this repo creates
# (`create_resource_groups`) are resources in deploy.tf instead.
data "azurerm_resource_group" "deploy" {
  for_each = local.looked_up_resource_groups

  name = each.value.resource_group
}

# Container Apps environments a consumer's workloads run on, owned by another
# repo (azure-container-apps). Looked up, never created.
data "azurerm_container_app_environment" "join" {
  for_each = local.join_container_app_environments

  name                = each.value.name
  resource_group_name = each.value.resource_group
}

# The owner's numeric ID, for OIDC subjects - see local.state_federated_credentials.
data "github_user" "owner" {
  username = "jay-withers"
}

# The platform's events endpoint and rule (azure-container-apps), for
# consumers with `send_events`. Looked up only when there is one, so a plan
# without any never depends on the platform having been applied.
data "azurerm_monitor_data_collection_endpoint" "events" {
  count = length(local.event_consumers) > 0 ? 1 : 0

  name                = var.events_ingestion.endpoint_name
  resource_group_name = var.events_ingestion.resource_group
}

data "azurerm_monitor_data_collection_rule" "events" {
  count = length(local.event_consumers) > 0 ? 1 : 0

  name                = var.events_ingestion.rule_name
  resource_group_name = var.events_ingestion.resource_group
}
