# The set of repositories this module manages. To add a new repo: add an
# entry here and open a PR. `required_status_checks` must match the exact
# status-check context each repo's CI reports - see CLAUDE.md's note on this
# (a reusable-workflow call reports as `<caller job id> / <reusable job
# name>`, not the bare job id), and confirm with `gh pr checks` against that
# repo.
repos = {
  "github-repos" = {
    description = "Terraform that creates and manages every jay-withers GitHub repository, including this one"
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
    ]
  }

  "terraform-root-aks" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
    ]
  }

  "azure-landingzone" = {
    description = "Terraform for a single-subscription Azure landing zone, built as a home lab on a Visual Studio subscription's $150/month credit"
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
    ]
  }

  "template-repo-terraform-root" = {
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
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

  "git-demo" = {}

  "azure-container-apps" = {
    description = "Shared Azure Container Apps environment every project deploys onto, plus the Log Analytics workspace and alerting behind it"
    topics      = ["azure", "terraform", "container-apps"]
    # Empty on purpose for the first apply. This repo has no CI history yet, so
    # there is no `gh pr checks` output to copy a context from - and applying a
    # context nothing reports leaves every PR pending for ever rather than
    # failing it, which is exactly what once blocked this repo's own PRs.
    # Fill in after the first PR there reports:
    #   pre-commit / Pre-commit, terraform / Terraform, terraform-plan
    required_status_checks = []
  }

  "repo-agent" = {
    description = "Scheduled agent that scans every jay-withers repository for improvements and checks Renovate is working, then emails a digest"
    topics      = ["azure", "python", "github-app", "renovate"]
    # Empty for the first apply, same reasoning as above. Expected contexts once
    # its CI has run:
    #   pre-commit / Pre-commit, test / Test, terraform / Terraform, terraform-plan
    #
    # ci-container-build's `build (repoagent)` is deliberately not on that list:
    # that workflow is filtered on its trigger (paths: src/**, Dockerfile, ...),
    # so a docs-only PR never runs it and never reports.
    required_status_checks = []
  }

  "market-agent" = {
    generated_from_template = "template-repo-terraform-root"
    # Every workflow in that repo is a thin caller of a reusable workflow in
    # jay-withers/workflows, so all but one of these contexts is namespaced
    # `<caller job id> / <reusable job name>` rather than the bare job id -
    # `test / Test` is the Python suite via python.yml, `terraform / Terraform`
    # the credential-free validate via terraform.yml.
    #
    # Terraform takes two contexts, not one. `terraform / Terraform` is the
    # shared workflow's own gate and can only see the jobs inside it, and
    # market-agent keeps its `plan` job locally - that repo is a single
    # self-contained root module that plans cleanly, unlike the landing-zone
    # repos terraform.yml was written for, where a plan against a
    # not-yet-applied dependency fails for something that is not a defect.
    # `terraform-plan` is the always-reporting gate over those plan legs.
    # Dropping either context silently stops guarding half of the Terraform CI.
    #
    # Replaced `ci-terraform`, which no longer exists as a context. A required
    # check that never reports leaves every PR pending rather than failing it,
    # so this needs applying for merges over there to work at all.
    #
    # ci-container-build's two `build (...)` contexts are deliberately absent.
    # That workflow *is* filtered on its trigger (paths: apps/**), so on a
    # Terraform-only PR it never runs and never reports - and a required check
    # that never reports leaves the PR pending for ever rather than failing it.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "test / Test" },
      { context = "terraform / Terraform" },
      { context = "terraform-plan" },
    ]
  }
}

# The "shared" Terraform state storage account this repo creates access to —
# see state.tf/identities.tf, and scripts/bootstrap-state.ps1 for how the
# account itself is created. To add a consumer: add its container name to
# scripts/containers.json and re-run that script, then add an entry here.
state_consumers = {
  "github-repos" = {
    github_repo = "jay-withers/github-repos"
  }

  "azure-container-apps" = {
    github_repo = "jay-withers/azure-container-apps"
  }

  "repo-agent" = {
    github_repo = "jay-withers/repo-agent"
  }
}
