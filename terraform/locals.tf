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

  # What a new CodeQL alert has to be to block a merge, on repos with
  # code_scanning = true. high_or_higher is where injection, path traversal
  # and SSRF land; medium and below still show on the pull request and in the
  # Security tab, but would block on too many judgement calls to be a gate.
  # `errors` is the same idea for CodeQL's non-security (quality) results.
  code_scanning_thresholds = {
    security_alerts = "high_or_higher"
    alerts          = "errors"
  }

  # Bypass actors on every ruleset: the repo Admin role, and the Renovate
  # GitHub App (id from `gh api apps/renovate --jq .id`). Both `always`. GitHub
  # only honours bypass_actors on organization-owned repos - jay-withers is a
  # User account, so this is currently inert here, but declaring it keeps this
  # repo's ruleset identical in shape to every other repo's, and it starts
  # working for free if the account ever moves to an org. See CLAUDE.md.
  admin_role_id   = 5
  renovate_app_id = 2740

  # Federated credential names must be unique per identity and cannot contain
  # the ":" and "/" that appear in a subject, so the map key supplies the name
  # and the value supplies the subject. The default is a single `dev` GitHub
  # environment subject: CI (plan) and CD (apply) jobs both declare
  # `environment: dev`, which makes the OIDC subject the environment rather
  # than the ref, so one credential covers both. The key is never parsed back apart anywhere, so
  # a plain "-" join (not "--") is fine even though both halves can
  # themselves contain hyphens.
  # One entry per consumer and resource group it deploys into, keyed
  # "<consumer>-<resource group>" for the same reason as above.
  deploy_resource_groups = merge([
    for key, c in var.state_consumers : {
      for rg in c.deploy_resource_groups : "${key}-${rg}" => {
        consumer       = key
        resource_group = rg
      }
    }
  ]...)

  deploy_consumers = toset([for key, c in var.state_consumers : key if length(c.deploy_resource_groups) > 0])

  state_federated_credentials = merge([
    for key, c in var.state_consumers : {
      for name, subject in coalesce(c.federated_subjects, {
        "dev" = "repo:${c.github_repo}:environment:dev"
        }) : "${key}-${name}" => {
        consumer = key
        subject  = subject
      }
    }
  ]...)

  # The repository variables a consumer's workflow logs in to Azure with -
  # one entry per consumer and variable, keyed "<consumer>-<variable>" for the
  # same reason as above. None of these are secret, so they're Actions
  # variables (vars.*), not secrets.
  state_github_variables = merge([
    for key, c in var.state_consumers : {
      for name, value in {
        AZURE_CLIENT_ID       = azurerm_user_assigned_identity.state[key].client_id
        AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
        AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
        } : "${key}-${name}" => {
        repository = split("/", c.github_repo)[1]
        name       = name
        value      = value
      }
    }
  ]...)
}
