# The GitHub half of the OIDC wiring. identities.tf federates each identity to
# a repo's Actions; these publish the three values that repo's workflows need
# in order to actually use it, so the identity and the variables pointing at it
# can never drift apart. Onboarding is then one terraform.tfvars entry plus an
# apply, with no manual `gh variable set` step to forget.
#
# Variables, not secrets, for two reasons: none of the three is sensitive (a
# client/tenant/subscription ID is useless without a federated subject GitHub
# will only issue a token for), and only `vars.*` can be read from a job-level
# `if:` - ci-terraform.yml's plan job gates on `vars.AZURE_CLIENT_ID != ''`,
# which is impossible with `secrets.*`.
#
# The GitHub PAT (the TF_GITHUB_TOKEN secret) is deliberately NOT managed
# here: unlike these, it is a real secret, and Terraform could only set it by
# taking the value as an input and writing it in plain text to state. It stays
# a one-off `gh secret set` - see README.md's Auth section.

# A GitHub environment per environment target, so the variables below have
# something to hang off. Deliberately bare: no reviewers, no wait timer, no
# branch policy. Those are a per-repo decision about that repo's release
# process, not something this module should impose - and a protection rule
# here would silently start queueing that repo's PR plans for approval.
resource "github_repository_environment" "state" {
  for_each = { for key, target in local.state_targets : key => target if target.environment != null }

  repository  = each.value.repo
  environment = each.value.environment
}

# Single-deployment repos: plain repository variables, visible to every
# workflow in the repo.
resource "github_actions_variable" "state_oidc" {
  for_each = { for key, variable in local.state_actions_variables : key => variable if variable.environment == null }

  repository    = each.value.repository
  variable_name = each.value.name
  value         = each.value.value
}

# Multi-environment repos: the same three names, scoped to one environment
# each, so `vars.AZURE_CLIENT_ID` in a job that declares `environment: dev`
# resolves to the dev identity and cannot resolve to any other.
resource "github_actions_environment_variable" "state_oidc" {
  for_each = { for key, variable in local.state_actions_variables : key => variable if variable.environment != null }

  repository    = each.value.repository
  environment   = github_repository_environment.state[each.value.target].environment
  variable_name = each.value.name
  value         = each.value.value
}
