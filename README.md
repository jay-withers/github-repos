# github-repos

Terraform that creates and manages every repository under
`github.com/jay-withers`, this one included, through the
[`integrations/github`](https://registry.terraform.io/providers/integrations/github/latest/docs)
provider. It also owns each repo's Azure-facing plumbing: its container in
the shared Terraform state account, the OIDC identity its pipeline uses, the
role assignments that identity gets, and the GitHub environment variables
that point the pipeline at it.

[`terraform/README.md`](terraform/README.md) covers the module in detail:
what each resource does, state, and auth.

## What it manages

- **Every repo's settings** (`repository.tf`, `ruleset.tf`): visibility,
  squash-only merges, delete-branch-on-merge, auto-merge, private
  vulnerability reporting, and a "Protect main" ruleset requiring a PR and
  that repo's status checks. Settings common to every repo live once in
  `locals.tf`; only the description, topics and required checks differ per
  repo, in `var.repos`.
- **Terraform state for the other repos** (`state.tf`, `identities.tf`): one
  container in `sttfsharedjw` and one container-scoped identity per entry in
  `var.state_consumers`, federated to that repo's `dev` environment.
- **Deploy permissions** (`deploy.tf`): for repos whose pipeline applies,
  Contributor on their resource groups (optionally created here), conditioned
  RBAC Administrator, join on the shared Container Apps environment, and a
  lock-creator role that can add a `CanNotDelete` lock but never remove one.
- **Environment variables** (`actions.tf`): `AZURE_CLIENT_ID`,
  `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` and the operator's `TF_VAR_*`
  values on each consumer's `dev` environment.

`terraform/terraform.tfvars` is committed: it *is* the desired state, and its
comments are the estate's catalogue (grouping, apply order, dependencies).

## Adding or changing a repo

1. Edit `terraform/terraform.tfvars`: a `var.repos` entry for the repo
   (description, topics, required status checks), plus a `state_consumers`
   entry if it keeps Terraform state or deploys to Azure.
2. Open a PR. `ci-terraform` validates it; PRs get no credentialled plan,
   because the only credentials that can read everything here are the apply
   ones, kept on `main`.
3. Merge. `cd-terraform` plans and opens a `terraform-pending` issue with the
   plan. Read it, then **Actions → cd-terraform → Run workflow** applies it.

A repo not yet in `var.repos` has GitHub's default settings until that apply.

## Getting started

Once per machine, set up the tools with
[jay-withers/toolchain](https://github.com/jay-withers/toolchain), which
installs [mise](https://mise.jdx.dev). Then, in this repo:

```bash
mise trust && make install   # mise install, then the pre-commit and commit-msg hooks
```

A local plan needs both credentials described in
[`terraform/README.md`](terraform/README.md#auth): `GITHUB_TOKEN` (an admin
PAT) and an `az login` with `ARM_SUBSCRIPTION_ID` exported, plus the
operator JSON as `TF_VAR_operator`.

## Commands

Run `make` (or `make help`) to list the targets:

```bash
make install     # install mise tools and pre-commit hooks (run once after cloning)
make lint        # run all pre-commit hooks against every file
make init        # terraform init (remote state: needs az login)
make fmt         # terraform fmt -recursive
make validate    # terraform init + validate
make plan        # terraform init + plan
make apply       # break-glass only: cd-terraform applies
make destroy     # terraform destroy (never run as routine)
make bootstrap   # create/update the shared state account and the apply identity (Owner, PowerShell 7+)
```

`make apply` locally is for when an apply has broken the `apply` environment
or its identity, or a required check nothing reports. `make bootstrap` runs
`scripts/bootstrap-state.ps1`, which creates the `sttfsharedjw` state
account, this repo's own container and the `uai-github-repos-apply-dev`
identity outside Terraform; see its header comment.

## Pre-commit hooks

Hooks live in `.pre-commit-config.yaml`, pinned by commit SHA with the tag as
a frozen comment:

- `pre-commit/pre-commit-hooks`: large-file, case-conflict, merge-conflict,
  symlink, YAML, end-of-file, trailing-whitespace, line-ending, shebang and
  submodule checks, plus `no-commit-to-branch` (blocks direct commits to
  `main`)
- `gitleaks` (secrets), `actionlint` (workflows), `shellcheck` (shell
  scripts), and `commitlint` ([Conventional
  Commits](https://www.conventionalcommits.org/), at the `commit-msg` stage)
- `terraform_fmt`, `terraform_validate` and `terraform_docs` (which
  regenerates the block at the bottom of `terraform/README.md`)
- local hooks: `check-tf-standards` (the estate's Terraform file layout,
  copied verbatim from template-repo-terraform-root), and `tflint` and
  `checkov` run against `terraform/` with `terraform.tfvars`

## CI/CD

Workflows are prefixed `ci-` (pull-request checks), `cd-` (post-merge
delivery), `schedule-` or `manual-`. All but `manual-remove-lock` call a
shared workflow in [jay-withers/workflows](https://github.com/jay-withers/workflows),
pinned by SHA.

- **ci-lint**: every pre-commit hook, with Terraform installed. Check:
  `pre-commit / Pre-commit`.
- **ci-terraform**: credential-free validate. Checks: `terraform / Terraform`
  and the `terraform-plan` gate.
- **ci-codeql**: CodeQL code scanning of the workflows.
- **cd-terraform**: plans each merge touching Terraform and opens a
  `terraform-pending` issue; run by hand, it applies. Both run in the
  main-only `apply` environment, as `uai-github-repos-apply-dev` with the
  `TF_GITHUB_TOKEN` environment secret.
- **cd-tag**: a semver tag and release on every merge to `main`.
- **schedule-drift**: a nightly plan in `apply` that records drift and never
  applies.
- **manual-terraform-unlock**: releases a stuck state lock, given the lock ID
  from an "Error acquiring the state lock" message.
- **manual-remove-lock**: removes one management lock from a consumer's
  resource group (only those in `deploy_resource_groups`). Consumer pipelines
  can create locks but not delete them, so this is how a store-of-record lock
  comes off. Dry run by default; afterwards remove the repo's
  `azurerm_management_lock`, or its next plan recreates it.

## Renovate

`renovate.json` extends the shared preset
[`github>jay-withers/renovate`](https://github.com/jay-withers/renovate)
(Monday schedule, auto-merge once checks pass, the `pre-commit` and `mise`
managers), plus `autoApprove: true`. Auto-merge works because this repo's
Terraform turns on repo-level auto-merge everywhere.

## Commit messages

Commits must follow [Conventional Commits](https://www.conventionalcommits.org/),
enforced by commitlint at commit-msg time. The type drives the version bump
on merge: `feat: add the cloudflare repo`, `fix: require the plan gate on
career`, `chore: bump the github provider`.

## Structure

```text
mise.toml                  # pinned tool versions, used locally and in CI
terraform/
  terraform.tfvars         # every repo and state consumer: the desired state
  repository.tf ruleset.tf # repo settings and the "Protect main" ruleset
  state.tf identities.tf   # state containers and per-repo identities
  deploy.tf                # resource groups and role assignments for pipelines that apply
  actions.tf               # GitHub environments and their variables
  data.tf locals.tf variables.tf outputs.tf versions.tf
  README.md                # the module, state and auth; terraform-docs block below
scripts/
  bootstrap-state.ps1      # make bootstrap: state account + apply identity
  check-tf-standards.sh    # pre-commit: Terraform file layout
  tflint.sh checkov.sh     # pre-commit: lint terraform/ with terraform.tfvars
.github/workflows/         # ci-lint, ci-terraform, ci-codeql, cd-terraform, cd-tag,
                           # schedule-drift, manual-terraform-unlock, manual-remove-lock
.pre-commit-config.yaml
commitlint.config.js
renovate.json
CLAUDE.md
Makefile
```
