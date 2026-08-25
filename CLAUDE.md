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
make protect-branch    # configure GitHub repo settings (auto-merge, branch protection) — see scripts/protect-branch.sh; override BRANCH/CHECKS to match your repo's checks
make lint              # run all pre-commit hooks against every file
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

## CI

Workflows are prefixed `ci-` (pull-request checks) or `cd-` (post-merge delivery):

- **ci-lint** (`.github/workflows/ci-lint.yml`): runs all linters
  on PRs to `main` via the `pre-commit` job, which calls the reusable workflow
  `jay-withers/template-pipelines/.github/workflows/pre-commit.yml` (pinned by
  commit SHA, with the tag as a comment) rather than inlining the steps. Because
  it's a reusable-workflow call, the status-check context it reports on a PR is
  `pre-commit / Pre-commit` (`<caller job id> / <reusable job name>`), not the
  bare `pre-commit` job id — see the `CHECKS` note under GitHub repo settings.
  The reusable workflow's `terraform` input defaults to `false` and is left
  unset here.
- **cd-tag** (`.github/workflows/cd-tag.yml`): auto-creates a semver tag (and a
  matching GitHub release) on every merge to `main` from the Conventional
  Commits since the last release, via the shared
  `jay-withers/template-pipelines/.github/workflows/release.yml` reusable
  workflow (default bump: patch).
- **ci-terraform** (`.github/workflows/ci-terraform.yml`): a `changes` job
  (`dorny/paths-filter`) gates a `plan` job (`terraform plan` on `terraform/`)
  so it runs only when a PR touches Terraform, behind a `ci-terraform` gate
  job that always runs and is the check required in the ruleset — same shape
  as `terraform-root-aks`'s `ci-terraform`, except auth is a PAT
  (`TF_GITHUB_TOKEN` secret) rather than Azure OIDC, since the GitHub
  provider has no OIDC federation. Plan-only: nothing applies in CI (see
  Terraform below), so every plan starts from empty state and always shows
  each resource as "to import" first — expected, not a failure.

## Renovate

`renovate.json` extends the shared preset
`github>jay-withers/template-renovate` (see that repo for the policy: batched
Monday schedule, automerge of non-major dev deps/pins/digests via
`platformAutomerge` — which needs repo-level auto-merge, see
`make protect-branch` — dependency dashboard, semantic commits, and the
`pre-commit` manager that keeps frozen hook revisions in
`.pre-commit-config.yaml` up to date), plus a local `autoApprove: true` so
those low-risk updates can clear the branch-protection review requirement.
Docker/GitHub Actions/Terraform/npm groupings are included in the shared
preset and activate automatically if a derived repo adds those ecosystems.

## GitHub repo settings

`scripts/protect-branch.sh` (run via `make protect-branch`, args: `BRANCH=<name>`
default `main`, `CHECKS="<newline-separated contexts>"` defaulting to this
template's single check `pre-commit / Pre-commit` — see the script's usage
comment; override for a consuming repo whose CI workflows differ. Newline-,
not space-, separated because a context name can itself contain spaces, e.g.
the reusable-workflow context above) sets the platform settings that can't live
in files: repo-level auto-merge (required for `renovate.json`'s
`platformAutomerge`), delete-branch-on-merge, and a ruleset on the target branch
requiring the given status checks and some number of approving reviews
(`APPROVALS_REQUIRED` to override; default 1 on org-owned repos, 0 on user-owned
repos — see next paragraph), with the Renovate GitHub App (looked up via `gh api
apps/renovate`) and the repo Admin role (built-in `RepositoryRole` actor_id 5)
exempted as `bypass_mode: always` bypass actors on both rules. It deletes every
ruleset already on the repo before creating this one, so re-runs replace rather
than accumulate — it uses `gh api` and is otherwise idempotent (safe to re-run
after renaming the repo or reinstalling Renovate).

GitHub only honours ruleset `bypass_actors` (the Renovate app entry) on repos
owned by an **organisation**. On a personal (User-owned) repo that entry is
accepted by the API but silently has no effect, so a required-review rule would
block Renovate's own PRs forever (Renovate can't review its own PR and nothing
else is exempted). The script therefore looks up the owner type (`gh api
users/<owner>`) and defaults `APPROVALS_REQUIRED` to 0 on user-owned repos and 1
on orgs. Status checks are still required and direct pushes to the branch are
still blocked on both; only the "someone else must approve" step is dropped for
personal repos. Override with `APPROVALS_REQUIRED=<n>` if you add collaborators
and want human review enforced (Renovate's PRs will then need a separate
auto-approve app, e.g. Mend's renovate-approve, to merge).

This script is still what a **brand-new** repo created from this template
runs once, by hand, before it exists anywhere else. For any repo listed in
`terraform/terraform.tfvars`'s `var.repos` (every jay-withers repo as of this
writing), `terraform/ruleset.tf` is the source of truth instead — don't run
`make protect-branch` against one of those, since a manual ruleset change
would just get reverted (or fought over) on the next `terraform apply`. Add a
new repo here only after it's been created and, ideally, once it's about to
be folded into `var.repos`.

## Terraform

`terraform/` creates and manages every jay-withers GitHub repository, this
one included, via the `integrations/github` provider — see
`terraform/README.md` for the module itself (what it manages, state, auth)
and `make init`/`fmt`/`validate`/`plan`/`apply`/`destroy` above. It
normalizes every repo onto the settings `terraform-root-aks` had configured
by hand (squash-only merge methods, delete-branch-on-merge, the same
"Protect main" ruleset shape), overriding only each repo's description,
topics, and required status checks. State is **local and gitignored, never
committed** — no remote backend. `imports.tf`'s `import` blocks make that
safe: losing state just means the next plan/apply re-imports every resource
from live GitHub data first. The tradeoff is no CI apply — `ci-terraform`
only plans; run `make apply` locally after merging a Terraform change. See
`terraform/README.md` for the full reasoning.
