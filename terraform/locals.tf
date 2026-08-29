locals {
  # Repository-level settings every managed repo is normalized to, taken from
  # the live configuration of jay-withers/terraform-root-aks - the one repo
  # that already had these set by hand. See CLAUDE.md.
  repo_defaults = {
    has_issues      = true
    has_projects    = true
    has_wiki        = true
    has_discussions = false

    visibility = "public"

    allow_squash_merge = true
    allow_merge_commit = false
    allow_rebase_merge = false
    allow_auto_merge   = true

    delete_branch_on_merge      = true
    squash_merge_commit_title   = "COMMIT_OR_PR_TITLE"
    squash_merge_commit_message = "COMMIT_MESSAGES"
  }

  # "Protect main" ruleset shape, likewise taken from terraform-root-aks.
  #
  # NOTE: the live ruleset also has require_extra_approval_for_unattributed_changes
  # = true, a newer GitHub PR-rule field the integrations/github provider does
  # not yet expose (checked against the resource schema at authoring time).
  # It's simply absent from this resource's config below rather than pinned to
  # false - Terraform never reads or writes it, so it's left exactly as
  # GitHub set it and won't show up as drift.
  ruleset_defaults = {
    allowed_merge_methods             = ["squash"]
    required_approving_review_count   = 0
    dismiss_stale_reviews_on_push     = true
    require_code_owner_review         = false
    require_last_push_approval        = false
    required_review_thread_resolution = true
  }

  # Bypass actors on every ruleset: the repo Admin role, and the Renovate
  # GitHub App (id from `gh api apps/renovate --jq .id`). Both `always`. GitHub
  # only honours bypass_actors on organization-owned repos - jay-withers is a
  # User account, so this is currently inert here, but declaring it keeps this
  # repo's ruleset identical in shape to every other repo's, and it starts
  # working for free if the account ever moves to an org. See CLAUDE.md.
  admin_role_id   = 5
  renovate_app_id = 2740

  # This repo's own state container, created by scripts/bootstrap-state.ps1
  # rather than Terraform because versions.tf's backend block already points at
  # it before Terraform has ever run. Must match that block's container_name.
  # See the import block in state.tf.
  bootstrap_container = "github-repos"

  # Every repo that opted into the shared state account (var.repos'
  # remote_state).
  state_repos = { for name, repo in var.repos : name => repo if repo.remote_state }

  # One state "target" per thing that needs its own container, identity and
  # credentials: the repo itself when it has a single deployment, or one per
  # environment when it declares any. This map is the for_each for the whole
  # Azure side - container, identity, federated credentials, RBAC - and its
  # key is the container name, so a repo is onboarded or removed by the one
  # remote_state flag and a single-deployment repo's key stays the bare repo
  # name.
  state_targets = merge([
    for name, repo in local.state_repos :
    length(repo.environments) == 0 ? {
      (name) = { repo = name, environment = null }
      } : {
      for env in repo.environments : "${name}-${env}" => { repo = name, environment = env }
    }
  ]...)

  # Federated credential names must be unique per identity and cannot contain
  # the ":" and "/" that appear in a subject, so the map key supplies the name
  # and the value supplies the subject. The key is never parsed back apart
  # anywhere, so a plain "-" join (not "--") is fine even though both halves
  # can themselves contain hyphens.
  #
  # A single-deployment repo gets the plan-on-PR / apply-on-merge pair - same
  # shape as azure-landingzone's landingzones and bootstrap components. An
  # environment target gets exactly one credential instead: a job that
  # declares `environment: <env>` always presents the
  # `...:environment:<env>` subject whatever the ref or event, so that one
  # subject covers its plans and its applies alike, and no other environment's
  # workflow can present it.
  state_federated_credentials = merge([
    for key, target in local.state_targets :
    target.environment == null ? {
      "${key}-pull-request" = { target = key, subject = "repo:${var.github_owner}/${target.repo}:pull_request" }
      "${key}-main"         = { target = key, subject = "repo:${var.github_owner}/${target.repo}:ref:refs/heads/main" }
      } : {
      "${key}-environment" = { target = key, subject = "repo:${var.github_owner}/${target.repo}:environment:${target.environment}" }
    }
  ]...)

  # The same three values the state_github_secrets output reports, flattened
  # to one entry per Actions variable so a single for_each in actions.tf
  # covers every target. `repository` is the bare repo name, not owner/repo -
  # that is what the github_actions_*variable resources take, and the owner is
  # already fixed by the provider block in versions.tf. A null `environment`
  # means a repository-level variable; anything else is scoped to that GitHub
  # environment.
  state_actions_variables = merge([
    for key, target in local.state_targets : {
      for variable, value in {
        AZURE_CLIENT_ID       = azurerm_user_assigned_identity.state[key].client_id
        AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
        AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
        } : "${key}-${variable}" => {
        target      = key
        repository  = target.repo
        environment = target.environment
        name        = variable
        value       = value
      }
    }
  ]...)
}
