resource "github_repository" "this" {
  for_each = var.repos

  name        = each.key
  description = each.value.description
  topics      = each.value.topics

  has_issues      = local.repo_defaults.has_issues
  has_projects    = local.repo_defaults.has_projects
  has_wiki        = local.repo_defaults.has_wiki
  has_discussions = local.repo_defaults.has_discussions

  visibility = local.repo_defaults.visibility

  # Derived from the name rather than a per-repo variable field: every repo
  # meant to be cloned/generated from (template-repo-base,
  # template-repo-terraform-root) already carries the "template-repo-"
  # prefix, so that naming convention is the single source of truth.
  is_template = startswith(each.key, "template-repo-")

  # Only present for a repo generated from another - see each.value's
  # generated_from_template description in variables.tf. Owner is always
  # this same account, matching the "github" provider block in versions.tf.
  dynamic "template" {
    for_each = each.value.generated_from_template != null ? [each.value.generated_from_template] : []
    content {
      owner      = "jay-withers"
      repository = template.value
    }
  }

  allow_squash_merge = local.repo_defaults.allow_squash_merge
  allow_merge_commit = local.repo_defaults.allow_merge_commit
  allow_rebase_merge = local.repo_defaults.allow_rebase_merge
  allow_auto_merge   = local.repo_defaults.allow_auto_merge

  delete_branch_on_merge      = local.repo_defaults.delete_branch_on_merge
  squash_merge_commit_title   = local.repo_defaults.squash_merge_commit_title
  squash_merge_commit_message = local.repo_defaults.squash_merge_commit_message

  lifecycle {
    ignore_changes = [
      # GitHub reports which template (if any) a repo was created from
      # forever, and the provider reads that back into this block on every
      # refresh even though it's create-time-only and unrelated to any
      # setting we manage - without this, every repo with template lineage
      # (e.g. terraform-root-aks, created from template-repo-terraform-root)
      # would show a permanent "remove template" diff.
      template,
    ]
  }
}
