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

  # True for repos meant to be cloned from, e.g. template-repo-base.
  is_template = startswith(each.key, "template-repo-")

  # Set only for a repo generated from another - see generated_from_template
  # in variables.tf.
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

# Dependabot alerts only - update PRs stay with Renovate, whose security
# updates read these alerts and are blind to CVEs without them.
resource "github_repository_vulnerability_alerts" "this" {
  for_each = github_repository.this

  repository = each.value.name
  enabled    = true
}

# Private vulnerability reporting: a "Report a vulnerability" button on each
# repo's Security tab, so someone who finds a hole can tell the owner in a
# private draft advisory instead of a public issue. These repos are public and
# several front live apps.
#
# The integrations/github provider has no resource or attribute for it (6.x
# exposes only the security_and_analysis secret-scanning settings), so this
# calls the REST endpoint on apply. PUT is idempotent, and terraform_data
# re-runs it for a new repository, or a renamed one. It goes through `gh api`
# rather than curl so it authenticates exactly as the provider does:
# GITHUB_TOKEN when set, otherwise the `gh auth login` session. A bare curl
# with $GITHUB_TOKEN sent no token at all for anyone relying on the login,
# and every call failed 401. Needs admin on the repos. Turning reporting off
# again is a manual `DELETE` on the same endpoint.
resource "terraform_data" "private_vulnerability_reporting" {
  for_each = github_repository.this

  triggers_replace = [each.value.full_name]

  provisioner "local-exec" {
    command = "gh api --silent --method PUT repos/${each.value.full_name}/private-vulnerability-reporting"
  }
}
