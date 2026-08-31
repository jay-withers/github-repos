# One identity per state target - a repo that opted into the shared state
# storage account (var.repos' remote_state), or one per environment where it
# declares any; see locals.tf's state_targets. Always a new identity here,
# since (unlike azure-landingzone/terraform/bootstrap) nothing in this repo
# already has an Azure identity to reuse.
module "state_naming" {
  #checkov:skip=CKV_TF_1:Registry-sourced module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"

  for_each = local.state_targets

  suffix = [each.key, "state"]
}

# A user-assigned managed identity rather than an app registration: no Entra
# app-registration rights are needed to create one, and it is an ordinary
# Azure resource so azurerm manages it and its federated credentials
# directly. Same reasoning as azure-landingzone's landingzones/main.tf.
resource "azurerm_user_assigned_identity" "state" {
  for_each = local.state_targets

  name                = module.state_naming[each.key].user_assigned_identity.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.state.name
  tags = {
    owner     = "jay"
    component = "state"
  }
}

# Federating to GitHub means the consuming pipeline holds no secret - it
# exchanges an Actions OIDC token for an Azure token. The subject pins which
# repo, and which ref or environment within it, may do so - see locals.tf's
# state_federated_credentials for the two shapes.
resource "azurerm_federated_identity_credential" "state" {
  for_each = local.state_federated_credentials

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.state[each.value.target].id

  audience = ["api://AzureADTokenExchange"]
  issuer   = "https://token.actions.githubusercontent.com"
  subject  = each.value.subject
}
