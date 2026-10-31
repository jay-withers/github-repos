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

# EVENTS_INGESTION_ENDPOINT and EVENTS_DCR_IMMUTABLE_ID for consumers with
# `send_events`. container-apps-deploy.yml posts its Deployments_CL row, and
# terraform-deploy.yml's drift check its OpsEvents_CL row, only when both are
# set, and each skips with a notice otherwise.
resource "github_actions_environment_variable" "events" {
  for_each = local.events_github_variables

  repository    = github_repository_environment.state[each.value.consumer].repository
  environment   = github_repository_environment.state[each.value.consumer].environment
  variable_name = each.value.name
  value         = each.value.value
}

# The operator's object ID, UPN and alert address as TF_VAR_* variables on
# each consumer that applies from its pipeline - see
# local.operator_github_variables.
resource "github_actions_environment_variable" "operator" {
  for_each = local.operator_github_variables

  repository    = github_repository_environment.state[each.value.consumer].repository
  environment   = github_repository_environment.state[each.value.consumer].environment
  variable_name = each.value.name
  value         = each.value.value
}

# This repo's own apply environment. cd-terraform's push plans and manual
# applies run here, as the apply identity; ci-terraform's pull request plans
# run in `dev` as the ordinary consumer identity. Deployments only from main,
# so a branch can neither log in as the apply identity (its federated
# credential trusts this environment's subject alone) nor read the
# TF_GITHUB_TOKEN secret set here, an admin PAT on every repo.
#
# That secret is set by hand (`gh secret set TF_GITHUB_TOKEN --env apply`),
# never here: a value Terraform sets is stored in its state.
resource "github_repository_environment" "apply" {
  repository  = github_repository.this["github-repos"].name
  environment = local.apply_environment

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "apply_main" {
  repository     = github_repository_environment.apply.repository
  environment    = github_repository_environment.apply.environment
  branch_pattern = "main"
}

resource "github_actions_environment_variable" "apply" {
  for_each = {
    AZURE_CLIENT_ID       = data.azurerm_user_assigned_identity.apply.client_id
    AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
    AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
  }

  repository    = github_repository_environment.apply.repository
  environment   = github_repository_environment.apply.environment
  variable_name = each.key
  value         = each.value
}
