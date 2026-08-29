# The "shared" Terraform state storage account - for repos that need state
# storage but aren't part of the azure-landingzone landing zone. The account
# and its resource group are created by scripts/bootstrap-state.ps1, not
# Terraform - see that script's header comment for why (this configuration's
# own backend lives in that account, so it has to exist before `terraform
# init` can run at all). This file only ever looks them up; everything inside
# the account - containers included - is Terraform's, in state.tf.
data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "state" {
  name = var.resource_group_name
}

data "azurerm_storage_account" "state" {
  name                = var.storage_account_name
  resource_group_name = data.azurerm_resource_group.state.name
}
