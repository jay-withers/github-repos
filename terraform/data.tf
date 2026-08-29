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
