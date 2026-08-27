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

  # Existing "Protect main" ruleset IDs, one per already-protected repo -
  # gh api repos/jay-withers/<repo>/rulesets --jq '.[].id'. `github-repos` is
  # deliberately absent: it has no ruleset yet, so its
  # github_repository_ruleset is created fresh instead of imported.
  existing_ruleset_ids = {
    "terraform-root-aks"           = 20476862
    "azure-landingzone"            = 20476824
    "template-repo-terraform-root" = 18814850
    "template-repo-base"           = 18687006
    "dev-containers"               = 18813027
    "toolchain"                    = 18812587
    "workflows"                    = 18587890
    "renovate"                     = 18686686
  }
}
