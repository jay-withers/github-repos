# The set of repositories this module manages, and the catalogue of what each
# one is for. To add a new repo: add an entry here and open a PR - this file is
# the only list of every repository, and Terraform applies `description` and
# `topics` to GitHub, so the catalogue cannot drift from what actually exists.
#
# `required_status_checks` must match the exact status-check context each repo's
# CI reports - see CLAUDE.md's note on this (a reusable-workflow call reports as
# `<caller job id> / <reusable job name>`, not the bare job id), and confirm with
# `gh pr checks` against that repo.
#
# The grouping below is for readers only; a map has no order as far as Terraform
# is concerned.
repos = {
  # ---------------------------------------------------------------------------
  # Azure estate. The landing zone and the shared infrastructure deployed into
  # it. Apply order runs downwards: nothing below stands alone.
  # ---------------------------------------------------------------------------

  "azure-landingzone" = {
    description = "Terraform for a single-subscription Azure landing zone, built as a home lab on a Visual Studio subscription's $150/month credit"
    topics      = ["azure", "terraform", "landing-zone"]
    # The root of the estate. Its `connectivity` component owns the hub VNet and
    # the private DNS zones, and its `landingzones` component vends resource
    # groups and identities to the spokes. Both must be applied before any spoke
    # can deploy. Also the home of the `allowed-locations-dev` policy assignment
    # that confines everything else to westeurope/northeurope.
    # `terraform / Terraform` comes from the shared workflow and `terraform-plan`
    # from the credentialled plan job the repo keeps locally — the same half-shared
    # split as market-agent and repo-agent.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
      { context = "terraform-plan" },
    ]
  }

  "terraform-root-aks" = {
    description = "Private AKS cluster with Flux GitOps, VNet, Key Vault, Loki log storage and a jump box, deployed as an application landing zone spoke"
    topics      = ["azure", "terraform", "aks", "kubernetes", "flux"]
    # A spoke of azure-landingzone rather than a standalone root module: the
    # resource group and identity are vended to it, so there is no `location`
    # variable and the cluster's identity cannot create resource groups. It
    # creates both halves of the hub peering, since one side alone stays
    # Initiated.
    #
    # `changes`/`validate` (ci-gitops.yml) are deliberately absent - that
    # workflow's own comment says only `ci-gitops` is meant to be required:
    # `changes` is an internal detection leg and `validate` skips conditionally
    # with no `if: always()` wrapper around it, so requiring it directly would
    # leave a non-GitOps PR pending for ever. `ci-gitops` is the always-running
    # gate over both, same shape as this repo's own `ci-terraform`.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
      { context = "ci-gitops" },
    ]
  }

  "azure-container-apps" = {
    description = "Shared Azure Container Apps environment every project deploys onto, plus the Log Analytics workspace and alerting behind it"
    topics      = ["azure", "terraform", "container-apps"]
    # One environment for every project, rather than one per project. It holds
    # only what is genuinely shared - the Container Apps environment, the Log
    # Analytics workspace, Application Insights and the job-failure alert - and
    # no Key Vault, identity or workload. Those belong to whichever project needs
    # them. Consumers resolve it by name with a data source rather than
    # `terraform_remote_state`, so no repo needs access to another's state.
    #
    # The environment carries no `workload_profile` block, which is what keeps it
    # free at idle; the Log Analytics daily quota is now shared, so exhausting it
    # stops ingestion for every project at once.
    #
    # Read literally off `gh pr checks` on azure-container-apps#2, not inferred
    # from the workflow files. `terraform-plan` is the always-reporting gate over
    # the local plan legs; it is `if: always()` and treats a skipped plan as
    # success, so a PR touching no Terraform still reports it.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
      { context = "terraform-plan" },
    ]
  }

  # ---------------------------------------------------------------------------
  # Workloads. Applications with their own Terraform, image and CD.
  # ---------------------------------------------------------------------------

  "market-agent" = {
    description             = "AI paper-trading experiment: an LLM recommends BUY/SELL/HOLD, a deterministic risk engine decides what is permitted, and simulated trades run against a paper broker. No real money"
    topics                  = ["azure", "terraform", "python", "llm", "fintech"]
    generated_from_template = "template-repo-terraform-root"
    # Infrastructure, the Python package behind it and a React dashboard, all in
    # one repo. Still runs its own Container Apps environment, Log Analytics and
    # Application Insights rather than the shared ones in azure-container-apps -
    # migrating it is deliberately deferred until the shared environment has
    # proven itself, because a new environment means its workloads get recreated
    # and the dashboard's custom domain re-bound.
    #
    # Its PostgreSQL Flexible Server is the only thing in the estate that bills
    # meaningfully while idle, at roughly GBP 13/month, and that SKU was forced
    # rather than chosen - see that repo's CLAUDE.md on the region trap.
    #
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
    # ci-container-build's two `build (...)` contexts are deliberately absent.
    # That workflow *is* filtered on its trigger (paths: apps/**), so on a
    # Terraform-only PR it never runs and never reports - and a required check
    # that never reports leaves the PR pending for ever rather than failing it.
    # `Layout` (ci-dashboard.yml) runs unconditionally on every PR, unlike the
    # build jobs above, so it doesn't share that failure mode - read off
    # `gh pr checks` on market-agent#68.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "test / Test" },
      { context = "terraform / Terraform" },
      { context = "terraform-plan" },
      { context = "Layout" },
    ]
  }

  "repo-agent" = {
    description = "Scheduled agent that scans every jay-withers repository for improvements and checks Renovate is working, then emails a digest"
    topics      = ["azure", "python", "github-app", "renovate"]
    # The first tenant of azure-container-apps, and the proof that the
    # shared-environment split works: it owns its own resource group, Key Vault,
    # identity and job, and reaches the environment by name.
    #
    # Reads GitHub as a read-only GitHub App and holds no state, so a repeat
    # finding is re-derived from GitHub timestamps each week rather than
    # remembered. Its checks are what keep the entries in this file honest - a
    # missing description or topic list shows up in the weekly digest.
    #
    # Read literally off `gh pr checks` on repo-agent#2, not inferred from the
    # workflow files.
    #
    # ci-container-build's `build (repoagent)` is deliberately absent: that
    # workflow is filtered on its trigger (paths: src/**, Dockerfile, ...), so a
    # docs-only PR never runs it and never reports, and a required check that
    # never reports leaves the PR pending for ever rather than failing it.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "test / Test" },
      { context = "terraform / Terraform" },
      { context = "terraform-plan" },
    ]
  }

  "gym-log" = {
    description = "Twice-weekly full-body training log with progression suggestions, replacing a spreadsheet, on the shared Container Apps environment"
    topics      = ["azure", "python", "fastapi", "container-apps"]
    # The second tenant of azure-container-apps, and the first `container app`
    # on it rather than a scheduled job — so it is also the first thing there
    # with ingress, scale-to-zero replicas and a URL. Owns its own resource
    # group, Key Vault, identity and storage account; reaches the environment
    # by name.
    #
    # Its blob holds training history that nothing reconstructs, which is why
    # that storage account is the one resource in the estate carrying
    # `prevent_destroy`.
    #
    # Read literally off `gh pr checks` on gym-log#17, not inferred from the
    # workflow files. `terraform / Validate (...)`/`terraform / Test (...)` and
    # `build / Build gymlog` are deliberately absent, same reasoning as
    # repo-agent's `build` context: the matrix legs only run conditionally and
    # ci-container-build's build job is path-filtered, so a required check that
    # never reports on some PRs would leave those pending for ever.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "test / Test" },
      { context = "terraform / Terraform" },
    ]
  }

  "finances" = {
    description             = "Personal finance tracker, on the shared Container Apps environment"
    topics                  = ["azure", "container-apps", "finance"]
    generated_from_template = "template-repo-terraform-root"
    # A third tenant of azure-container-apps, same shape as gym-log: its own
    # resource group, Key Vault, identity and storage account, reaching the
    # shared environment by name rather than running its own.
    #
    # Read literally off `gh pr checks` on finances#12, not inferred from the
    # workflow files. `terraform / Validate (...)`/`terraform / Test (...)` and
    # `build / Build finances` are deliberately absent, same reasoning as
    # gym-log's: the matrix legs only run conditionally and ci-container-build's
    # build job is path-filtered, so a required check that never reports on
    # some PRs would leave those pending for ever.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "test / Test" },
      { context = "terraform / Terraform" },
    ]
  }

  # ---------------------------------------------------------------------------
  # Shared tooling. Consumed by nearly every repo above, so a change here is a
  # change everywhere - which is the point of them existing.
  # ---------------------------------------------------------------------------

  "github-repos" = {
    description = "Terraform that creates and manages every jay-withers GitHub repository, including this one"
    topics      = ["github", "terraform"]
    # This repo, and the catalogue you are reading. It is the single source of
    # truth for which repositories exist, their descriptions, topics and branch
    # protection, plus the shared Terraform state storage account and the OIDC
    # identities that let each repo plan against it.
    #
    # It plans in CI but never applies: a change takes effect when someone runs
    # `make apply` against remote state. Because that reads local tfvars, it can
    # be run from a branch - which is how a required check that nothing reports
    # gets unstuck without an admin bypass.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
    ]
  }

  "workflows" = {
    description = "Reusable GitHub Actions workflows - terraform, pre-commit, python, docker and release - called by every other repository via workflow_call"
    topics      = ["github-actions", "ci-cd", "reusable-workflows"]
    # Every ci-/cd- workflow in every repo above is a thin caller of something
    # here, pinned by commit SHA with the tag as a comment. A change to how a job
    # *works* belongs here so every consuming repo picks it up; only what is
    # specific to a repo stays in that repo.
    #
    # This is also why the contexts throughout this file are namespaced: a
    # reusable-workflow call reports as `<caller job id> / <reusable job name>`.
    #
    # Its README still calls the repo `template-pipelines`, from before the
    # rename.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
    ]
  }

  "renovate" = {
    description = "Centralised Renovate configuration presets that every repository extends, so dependency-update policy is changed in one place"
    topics      = ["renovate", "dependencies", "automation"]
    # Renamed from `template-renovate`. Consumers must extend
    # `github>jay-withers/renovate`: the old name resolves only through GitHub's
    # rename redirect, which disappears the moment anything is created at the old
    # path, and would break preset resolution in every repo at once with nothing
    # to announce it. Its own README still documents the old name.
    #
    # "validate" is reported by an app integration rather than a plain
    # Actions job - see gh api repos/jay-withers/renovate/rulesets.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "validate", integration_id = 15368 },
    ]
  }

  "dev-containers" = {
    description = "Multi-arch VS Code dev container images - base, terraform and k8s - built from a shared base and published to ghcr.io for any repo to reference"
    topics      = ["devcontainer", "docker", "ghcr", "azure"]
    # Referenced by tag from each repo's .devcontainer/devcontainer.json, so
    # nothing is built locally and every repo gets the same tool versions CI has.
    # Tooling that belongs to everyone goes in `base`; anything Terraform- or
    # Kubernetes-specific goes in the image above it.
    #
    # `base (...)`/`leaves (...)` (ci-container-build.yml) are deliberately
    # absent: that workflow's own `changes` job path-filters them to `images/**`,
    # so a docs-only PR never runs them and a required check on either would be
    # pending for ever. `changes` itself runs unconditionally - read off
    # `gh pr checks` on dev-containers#73.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "changes" },
    ]
  }

  "toolchain" = {
    description = "Bootstrap script that installs the Azure, Kubernetes and Terraform toolchain on a fresh WSL or macOS machine"
    topics      = ["bootstrap", "macos", "wsl", "azure"]
    # The bare-metal counterpart to dev-containers: what you run on a new laptop
    # before any repo is cloned. The dev container images cover everything after
    # that, so these two should stay roughly in step on tool choice.
    #
    # `linux`/`macos` (test-install.yml) are deliberately absent: they skip
    # conditionally (only when `src/**` changes) with no always()-gate wrapping
    # them, so requiring either directly would leave a docs-only PR pending for
    # ever. `changes`, the detection job feeding them, runs unconditionally on
    # every PR and is safe to require - read off `gh pr checks` on toolchain#40.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "changes" },
    ]
  }

  "template-repo-base" = {
    description = "Language-agnostic repository template: dev container, pre-commit hooks, CI workflows, Renovate and Conventional Commits, with no application code"
    topics      = ["template", "scaffolding"]
    # The floor every new repo starts from. `generated_from_template` elsewhere
    # in this file records which repos came from a template, but GitHub applies
    # it only at creation - changing it later does nothing, so a template change
    # never propagates to repos already made from it.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
    ]
  }

  "template-repo-terraform-root" = {
    description = "Repository template for an Azure Terraform root configuration: template-repo-base plus Terraform pre-commit hooks, tflint, terraform-docs and checkov"
    topics      = ["template", "scaffolding", "terraform", "azure"]
    # The starting point for every Terraform repo above; market-agent is the one
    # recorded as generated from it. Note the name is the only thing template
    # about it - it is a plain repo, and its own CI runs against the scaffold.
    required_status_checks = [
      { context = "pre-commit / Pre-commit" },
      { context = "terraform / Terraform" },
    ]
  }

  # ---------------------------------------------------------------------------
  # Standalone. Not part of the estate and not consumed by anything.
  # ---------------------------------------------------------------------------

  "git-demo" = {
    description = "A hands-on git walkthrough for someone who has never used it, with pre-commit hooks switched on deliberately so some commits get rejected"
    topics      = ["git", "learning", "tutorial"]
    # Teaching material rather than infrastructure. It carries no CI workflows
    # and no renovate.json on purpose, so it will show up in repo-agent's digest
    # as missing both - expected, not a defect, and the reason that agent reports
    # rather than enforces.
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

  "gym-log" = {
    github_repo = "jay-withers/gym-log"
  }

  "finances" = {
    github_repo = "jay-withers/finances"
  }
}
