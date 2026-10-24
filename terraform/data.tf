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

# Resource groups a consumer's pipeline applies into. Looked up, never
# created: each repo owns its own resource group, and creates it with a local
# apply before its pipeline takes over.
data "azurerm_resource_group" "deploy" {
  for_each = local.deploy_resource_groups

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
