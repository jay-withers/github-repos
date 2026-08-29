output "repository_urls" {
  description = "HTML URL of every managed repository, keyed by name."
  value       = { for name, repo in github_repository.this : name => repo.html_url }
}

# The values a consumer's own backend.tf needs. None of these are secret.
output "state_backend_config" {
  description = "Per consumer: the azurerm backend block values for its own backend.tf."

  value = {
    for key in keys(var.state_consumers) : key => {
      resource_group_name  = data.azurerm_resource_group.state.name
      storage_account_name = data.azurerm_storage_account.state.name
      container_name       = key
      use_azuread_auth     = true
    }
  }
}

# The three values a consumer's GitHub Actions workflow needs - mirrors
# azure-landingzone's landingzones/bootstrap github_secrets output.
output "state_github_secrets" {
  description = "Repository variables to set on each state consumer's repo."

  value = {
    for key, c in var.state_consumers : c.github_repo => {
      AZURE_CLIENT_ID       = azurerm_user_assigned_identity.state[key].client_id
      AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
      AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    }
  }
}
