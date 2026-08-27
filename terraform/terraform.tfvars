# The set of repositories this module manages. To add a new repo: add an
# entry here (a brand new repo doesn't need an `existing_ruleset_ids` entry in
# locals.tf - only repos that already have a ruleset to import do) and open a
# PR. `required_status_checks` must match the exact status-check context each
# repo's CI reports - see CLAUDE.md's note on this (a reusable-workflow call
# reports as `<caller job id> / <reusable job name>`, not the bare job id),
# and confirm with `gh pr checks` against that repo.
repos = {
  "github-repos" = {
    description = "Terraform that creates and manages every jay-withers GitHub repository, including this one"
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "ci-terraform" },
    ]
  }

  "terraform-root-aks" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "ci-terraform" },
    ]
  }

  "azure-landingzone" = {
    description = "Terraform for a single-subscription Azure landing zone, built as a home lab on a Visual Studio subscription's $150/month credit"
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "ci-terraform" },
    ]
  }

  "template-repo-terraform-root" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "ci-terraform" },
    ]
  }

  "template-repo-base" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
    ]
  }

  "dev-containers" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
    ]
  }

  "toolchain" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
    ]
  }

  "workflows" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
    ]
  }

  "renovate" = {
    # "validate" is reported by an app integration rather than a plain
    # Actions job - see gh api repos/jay-withers/renovate/rulesets.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "validate", integration_id = 15368 },
    ]
  }
}
