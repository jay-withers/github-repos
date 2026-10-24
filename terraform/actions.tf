# Sets the values from state_github_secrets (outputs.tf) on each consumer's
# repo directly, rather than leaving them to a manual `gh variable set` - the
# consumer's workflow reads them as vars.AZURE_CLIENT_ID etc. for azure/login.
# Keyed through github_repository.this so a consumer added alongside its repo
# gets the repo created first; every consumer must therefore also be in
# var.repos.
resource "github_actions_variable" "state" {
  for_each = local.state_github_variables

  repository    = github_repository.this[each.value.repository].name
  variable_name = each.value.name
  value         = each.value.value
}
