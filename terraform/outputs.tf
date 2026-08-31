output "repository_urls" {
  description = "HTML URL of every managed repository, keyed by name."
  value       = { for name, repo in github_repository.this : name => repo.html_url }
}

# The values a state repo's own backend block needs - the one thing this
# module can't write for it, since it has to be in that repo's own source.
# Keyed by state target, so a multi-environment repo gets one entry per
# environment (that repo passes the right one with `-backend-config`). None of
# these are secret.
output "state_backend_config" {
  description = "Per state target: the azurerm backend block values for that repo's own versions.tf."

  value = {
    for key in keys(local.state_targets) : key => {
      resource_group_name  = data.azurerm_resource_group.state.name
      storage_account_name = data.azurerm_storage_account.state.name
      container_name       = azurerm_storage_container.state[key].name
      use_azuread_auth     = true
    }
  }
}

# The three values a state repo's GitHub Actions workflow needs - mirrors
# azure-landingzone's landingzones/bootstrap github_secrets output. Nothing
# has to act on this any more: actions.tf sets them on each repo (or GitHub
# environment) itself. Kept as an output because it is the one place the whole
# OIDC triple is visible at a glance when debugging a CI auth failure.
output "state_github_secrets" {
  description = "Actions variables set on each state target by actions.tf, for reference."

  value = {
    for key, target in local.state_targets : key => {
      repository            = "${var.github_owner}/${target.repo}"
      environment           = target.environment
      AZURE_CLIENT_ID       = azurerm_user_assigned_identity.state[key].client_id
      AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
      AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    }
  }
}
