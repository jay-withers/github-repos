# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Started as a language-agnostic GitHub repository template (dev container,
generic pre-commit hooks, PR/merge CI workflows, Renovate, Conventional
Commits enforcement, Makefile + branch-protection scaffolding) and now also
carries this account's own application: a `terraform/` root module, in
`terraform/`, that creates and manages every repository under
`github.com/jay-withers` — including this one — via the
`integrations/github` provider. See `terraform/README.md` for the module
itself; the rest of this file still covers the template baseline it's built
on.

## Dev container

The repo is built around the dev container at `.devcontainer/devcontainer.json`,
which uses the `ghcr.io/jay-withers/dev-containers/terraform` image (the same
one `terraform-root-aks` uses — installs `terraform`/`tfenv`, `tflint`,
`terraform-docs` and `checkov` on top of the generic `base` image) and runs
`make install` on creation to wire up the pre-commit hooks. Prefer working
inside the container so tooling versions match CI. **Editing
`devcontainer.json` doesn't affect an already-running container** — rebuild
it (VS Code: "Dev Containers: Rebuild Container") to pick up an image change.

## Commands

`make` with no target prints the self-documenting help (the default goal).

```bash
make install           # install pre-commit hooks (run once after cloning)
make lint               # run all pre-commit hooks against every file
make init/fmt/validate/plan/apply/destroy  # terraform/ — see terraform/README.md for required auth
```

## Commit messages

Commits must follow [Conventional Commits](https://www.conventionalcommits.org/) — enforced by commitlint at commit-msg time. Examples: `feat: add health check endpoint`, `fix: correct retry backoff`, `chore: bump dependency`.

## Pre-commit config

Hooks are in `.pre-commit-config.yaml` at the repo root, all pinned by commit
SHA with the tag as a frozen comment. They're intentionally language-agnostic:
`pre-commit/pre-commit-hooks` basics (large-file / case-conflict /
merge-conflict / symlink / YAML / EOF / whitespace / line-ending / shebang
checks, and `no-commit-to-branch` which blocks direct commits to `main`),
`gitleaks` (secret scanning), `actionlint` (GitHub Actions linting),
`shellcheck` (shell scripts), and `commitlint` (Conventional Commits, at the
`commit-msg` stage). When a repo derived from this template gains a language,
add its formatter/linter hooks here rather than replacing these.

On top of that language-agnostic baseline, this repo's own `terraform/`
application adds `antonbabenko/pre-commit-terraform`'s `terraform_fmt`/
`terraform_validate`/`terraform_docs` (the latter appends a generated
Requirements/Providers/Modules/Resources/Inputs/Outputs block to the bottom
of `terraform/README.md`, between `<!-- BEGIN_TF_DOCS -->`/`<!-- END_TF_DOCS
-->` markers, on every hook run - the hand-written prose above those markers
is never touched), plus three local, unpinned hooks aligned with
[jay-withers/template-repo-terraform-root](https://github.com/jay-withers/template-repo-terraform-root/blob/main/.pre-commit-config.yaml)'s
own (see each script's header comment for exactly what's copied vs. adapted):

- `scripts/check-tf-file-layout.sh` - this repo's file-layout house rules:
  `data`/`locals`/`variable`/`output` blocks each live in their own dedicated
  file (`data.tf`, `locals.tf`, `variables.tf`, `outputs.tf`, or a
  `<block-type>.<name>.tf` variant, e.g. `data.state.tf`), and
  `terraform{}`/`provider{}` blocks share a single `versions.tf`. The
  `data`/`terraform`/`provider` rules are this repo's own addition on top of
  the template's (which only covers `locals`/`variable`/`output`).
- `scripts/tflint.sh` / `scripts/checkov.sh` - run against `terraform/` with
  `terraform.tfvars` applied (`terraform/.tflint.hcl` enables the `azurerm`
  ruleset plugin), replacing `pre-commit-terraform`'s own
  `terraform_tflint`/`terraform_checkov` hooks entirely. The template repo
  loops this per `terraform/environments/*.tfvars` file since it deploys the
  same module to several environments; this repo has exactly one deployment
  and one `terraform.tfvars`, so the loop collapses to a single invocation.
  `checkov.sh` skips `CKV_GIT_1` ("repository should be private") -
  `repo_defaults.visibility` in `locals.tf` deliberately makes every managed
  repo public, so that finding is by design, not a gap.

## CI

Workflows are prefixed `ci-` (pull-request checks) or `cd-` (post-merge delivery):

- **ci-lint** (`.github/workflows/ci-lint.yml`): runs all linters
  on PRs to `main` via the `pre-commit` job, which calls the reusable workflow
  `jay-withers/workflows/.github/workflows/pre-commit.yml` (pinned by
  commit SHA, with the tag as a comment) rather than inlining the steps. Because
  it's a reusable-workflow call, the status-check context it reports on a PR is
  `pre-commit / Pre-commit` (`<caller job id> / <reusable job name>`), not the
  bare `pre-commit` job id — see the note on `required_status_checks` under
  GitHub repo settings. The reusable workflow's `terraform` input defaults to
  `false` but is set to `true` here, since `.pre-commit-config.yaml` runs
  `terraform_fmt`/`terraform_validate` against `terraform/` and those hooks
  need a real Terraform binary on the runner (without this the job fails with
  "Neither Terraform nor OpenTofu binary could be found").
- **cd-tag** (`.github/workflows/cd-tag.yml`): auto-creates a semver tag (and a
  matching GitHub release) on every merge to `main` from the Conventional
  Commits since the last release, via the shared
  `jay-withers/workflows/.github/workflows/release.yml` reusable
  workflow (default bump: patch).
- **ci-terraform** (`.github/workflows/ci-terraform.yml`): a `changes` job
  (`dorny/paths-filter`) gates a `plan` job (`terraform plan` on `terraform/`)
  so it runs only when a PR touches Terraform, behind a `ci-terraform` gate
  job that always runs and is the check required in the ruleset — same shape
  as `terraform-root-aks`'s `ci-terraform`, except it authenticates twice:
  Azure OIDC for the `azurerm` provider (gated on the `AZURE_CLIENT_ID`
  repository variable — see terraform/README.md's Auth section), and a PAT
  (`TF_GITHUB_TOKEN` secret) for the `github` provider, since that provider
  has no OIDC federation of its own. Plan-only: nothing applies in CI (see
  Terraform below).

## Renovate

`renovate.json` extends the shared preset
`github>jay-withers/template-renovate` (see that repo for the policy: batched
Monday schedule, automerge of non-major dev deps/pins/digests via
`platformAutomerge` — which needs repo-level auto-merge, set by `terraform/`
(see GitHub repo settings below) — dependency dashboard, semantic commits,
and the `pre-commit` manager that keeps frozen hook revisions in
`.pre-commit-config.yaml` up to date), plus a local `autoApprove: true` so
those low-risk updates can clear the branch-protection review requirement.
Docker/GitHub Actions/Terraform/npm groupings are included in the shared
preset and activate automatically if a derived repo adds those ecosystems.

## GitHub repo settings

`terraform/repository.tf` and `terraform/ruleset.tf` (see `## Terraform`
below) are the sole mechanism for the platform settings that can't live in
files: repo-level auto-merge (required for `renovate.json`'s
`platformAutomerge`), delete-branch-on-merge, and a "Protect main" ruleset on
`main` requiring each repo's status checks (`required_status_checks` in
`terraform/terraform.tfvars`'s `var.repos`) and 0 approving reviews, with the
Renovate GitHub App (looked up via `gh api apps/renovate`) and the repo Admin
role (built-in `RepositoryRole` actor_id 5) exempted as `bypass_mode: always`
bypass actors on the ruleset.

GitHub only honours ruleset `bypass_actors` on repos owned by an
**organisation** — on this personal (User-owned) account those entries are
accepted by the API but silently have no effect. That's fine here:
`required_approving_review_count` is fixed at 0 for every repo, so there's no
review requirement for the (currently inert) bypass actors to unblock in the
first place — a working exemption for the Renovate app only starts to matter
if the account ever moves to an org and reviews get required, which is why
the bypass actors are declared anyway. Status checks are still required and
direct pushes to `main` are still blocked.

Every jay-withers repo, this one included, is already listed in
`terraform/terraform.tfvars`'s `var.repos`, so this is the only mechanism —
there's no separate one-time bootstrap step anymore. A genuinely new repo
(not yet in `var.repos`) simply has GitHub's default settings until it's
added there and `make apply` is run.

## Terraform

`terraform/` creates and manages every jay-withers GitHub repository, this
one included, via the `integrations/github` provider — see
`terraform/README.md` for the module itself (what it manages, state, auth)
and `make init`/`fmt`/`validate`/`plan`/`apply`/`destroy` above. It
normalizes every repo onto the settings `terraform-root-aks` had configured
by hand (squash-only merge methods, delete-branch-on-merge, the same
"Protect main" ruleset shape), overriding only each repo's description,
topics, and required status checks. State is **remote**, in the "shared"
Terraform state storage account this module also manages access to (backend
block in `versions.tf`) — durability comes from that account's blob
versioning and soft-delete, not from any import/recovery mechanism in the
module itself. The tradeoff is no CI apply — `ci-terraform` only plans; run
`make apply` locally after merging a Terraform change. See
`terraform/README.md` for the full reasoning.
