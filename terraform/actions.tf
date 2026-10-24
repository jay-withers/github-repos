# The GitHub environment each consumer's CI and CD jobs run in - see
# local.state_environment. Created here because the variables below can't be
# set on an environment that doesn't exist yet; no protection rules, since
# pull request plan jobs run in it too and a branch policy would block them.
# Keyed through github_repository.this so a consumer added alongside its repo
# gets the repo created first; every consumer must therefore also be in
# var.repos.
resource "github_repository_environment" "state" {
  for_each = var.state_consumers

  repository  = github_repository.this[split("/", each.value.github_repo)[1]].name
  environment = local.state_environment
}

# Sets the values from state_github_secrets (outputs.tf) on each consumer's
# environment directly, rather than leaving them to a manual
# `gh variable set --env` - the consumer's workflow reads them as
# vars.AZURE_CLIENT_ID etc. for azure/login.
resource "github_actions_environment_variable" "state" {
  for_each = local.state_github_variables

  repository    = github_repository_environment.state[each.value.consumer].repository
  environment   = github_repository_environment.state[each.value.consumer].environment
  variable_name = each.value.name
  value         = each.value.value
}
