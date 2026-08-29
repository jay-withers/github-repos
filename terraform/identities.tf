# One identity per consumer of the shared state storage account - always a
# new one here, since (unlike azure-landingzone/terraform/bootstrap) nothing
# in this repo already has an Azure identity to reuse.
module "state_naming" {
  #checkov:skip=CKV_TF_1:Registry-sourced module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"

  for_each = var.state_consumers

  suffix = [each.key, "state"]
}

# A user-assigned managed identity rather than an app registration: no Entra
# app-registration rights are needed to create one, and it is an ordinary
# Azure resource so azurerm manages it and its federated credentials
# directly. Same reasoning as azure-landingzone's landingzones/main.tf.
resource "azurerm_user_assigned_identity" "state" {
  for_each = var.state_consumers

  name                = module.state_naming[each.key].user_assigned_identity.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.state.name
  tags = {
    owner     = "jay"
    component = "state"
  }
}

# Federating to GitHub means the consumer's pipeline holds no secret - it
# exchanges an Actions OIDC token for an Azure token. The subject pins which
# repo and which ref may do so.
resource "azurerm_federated_identity_credential" "state" {
  for_each = local.state_federated_credentials

  name      = each.key
  parent_id = azurerm_user_assigned_identity.state[each.value.consumer].id

  resource_group_name = data.azurerm_resource_group.state.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = each.value.subject
}
