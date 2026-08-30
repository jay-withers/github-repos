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

  # GitHub is part-way through a rollout of "immutable" OIDC subjects, which
  # carry the numeric owner and repo IDs (repo:owner@288264678/name@1345898182)
  # rather than plain names - and it lands per repo, not per account: at the
  # time of writing github-repos and azure-landingzone mint the ID form while
  # terraform-root-aks still mints the legacy one. `gh api
  # repos/<owner>/<repo>/actions/oidc/customization/sub` reports which, in
  # sub_claim_prefix (note that use_immutable_subject can read false while the
  # prefix is already the ID form - the prefix is what actually gets minted).
  #
  # So rather than track that per repo and break a repo the day it migrates,
  # every credential is declared in BOTH forms below. Only the matching one is
  # ever presented; the other sits unused and costs nothing (Entra allows 20
  # per identity). Drop the legacy half once every repo reports an ID prefix.
  state_subject_prefixes = {
    for name, _ in local.state_repos : name => {
      legacy    = "repo:${var.github_owner}/${name}"
      immutable = "repo:${var.github_owner}@${var.github_owner_id}/${name}@${github_repository.this[name].repo_id}"
    }
  }

  # What each target's workflows actually present: the plan-on-PR /
  # apply-on-merge pair for a single-deployment repo - same shape as
  # azure-landingzone's landingzones and bootstrap components - or, for an
  # environment target, the environment alone. A job that declares
  # `environment: <env>` presents that subject whatever the ref or event, so
  # the one claim covers its plans and its applies alike, and no other
  # environment's workflow can present it.
  state_target_claims = {
    for key, target in local.state_targets : key => (
      target.environment == null
      ? { "pull-request" = "pull_request", "main" = "ref:refs/heads/main" }
      : { "environment" = "environment:${target.environment}" }
    )
  }

  # Federated credential names must be unique per identity and cannot contain
  # the ":" and "/" that appear in a subject, so the map key supplies the name
  # and the value supplies the subject. The key is never parsed back apart
  # anywhere, so a plain "-" join (not "--") is fine even though every half can
  # itself contain hyphens. The legacy form keeps the bare name so the
  # credentials that already exist stay put.
  state_federated_credentials = merge(flatten([
    for key, claims in local.state_target_claims : [
      for form, prefix in local.state_subject_prefixes[local.state_targets[key].repo] : {
        for claim_name, claim in claims :
        "${key}-${claim_name}${form == "immutable" ? "-immutable" : ""}" => {
          target  = key
          subject = "${prefix}:${claim}"
        }
      }
    ]
  ])...)

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
