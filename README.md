# github-repos

Started from a language-agnostic GitHub repository template (dev container,
generic pre-commit hooks, PR/merge CI workflows, Renovate dependency updates,
Conventional Commits enforcement, branch-protection scaffolding) and now also
this account's own application: a `terraform/` module that creates and
manages every repository under `github.com/jay-withers`, this one included.
See [`terraform/README.md`](terraform/README.md) for that module; the rest of
this document covers the template baseline it's built on.

## Getting started

1. Create a repo from this template (**Use this template** on GitHub, or `gh
   repo create --template`).
2. Open it in the dev container (VS Code: **Reopen in Container**, or GitHub
   Codespaces). The container runs `make install` on creation to wire up the
   pre-commit hooks.
3. Outside a dev container, install the hooks manually:

   ```bash
   make install
   ```

4. Configure the GitHub-side settings that can't be templated as files (see
   [Configuring GitHub](#configuring-github-for-a-repo-created-from-this-template)):

   ```bash
   make protect-branch
   ```

## Commands

Run `make` (or `make help`) to list the available targets:

```bash
make install           # install pre-commit hooks (run once after cloning)
make protect-branch    # configure GitHub repo settings (auto-merge, branch protection) — override CHECKS if your repo's checks differ
make lint              # run all pre-commit hooks against every file
make plan / apply      # terraform/ — see terraform/README.md for required auth
```

## Pre-commit hooks

Hooks live in `.pre-commit-config.yaml`, pinned by commit SHA with the tag as a
frozen comment. They're deliberately language-agnostic:

- `pre-commit/pre-commit-hooks` — large-file, case-conflict, merge-conflict,
  symlink, YAML, end-of-file, trailing-whitespace, line-ending and shebang
  checks, plus `no-commit-to-branch` (blocks direct commits to `main`)
- `gitleaks` — secret scanning
- `actionlint` — GitHub Actions workflow linting
- `shellcheck` — shell scripts
- `commitlint` — [Conventional Commits](https://www.conventionalcommits.org/),
  at the `commit-msg` stage

As your repo gains a language, add its formatter/linter hooks here — don't
remove these. Renovate keeps the frozen hook revisions up to date.

## Commit messages

Commits must follow [Conventional Commits](https://www.conventionalcommits.org/),
enforced by commitlint at commit-msg time. The commit type drives the automatic
version bump on merge (see below). Examples:

```text
feat: add health check endpoint
fix: correct retry backoff
chore: bump dependency
```

## CI/CD

Workflows are prefixed `ci-` (pull-request checks) or `cd-` (post-merge delivery):

- **`.github/workflows/ci-lint.yml`** — runs all pre-commit hooks on PRs
  to `main`, by calling the shared reusable workflow
  `jay-withers/template-pipelines/.github/workflows/pre-commit.yml`. Its status
  check reports as `pre-commit / Pre-commit`.
- **`.github/workflows/cd-tag.yml`** — on every merge to `main`, creates a
  semver tag and matching GitHub release from the Conventional Commits since the
  last release (default bump: patch), via
  `jay-withers/template-pipelines/.github/workflows/release.yml`.
- **`.github/workflows/ci-terraform.yml`** — plans `terraform/` on PRs that
  touch it (no CI apply — see [`terraform/README.md`](terraform/README.md)).

Both `ci-lint`/`cd-tag` pin the reusable workflow by commit SHA with the tag
as a comment. Add your own `ci-*` workflows (build, test, etc.) as you add
code, and require their checks in branch protection (below) — or, for a repo
managed by `terraform/`, in `var.repos` there instead.

## Renovate

`renovate.json` extends `config:recommended` on a weekly schedule with
auto-approve and automerge. `platformAutomerge` needs repo-level auto-merge to
be enabled — `make protect-branch` does that. The `pre-commit` manager updates
the frozen hook revisions in `.pre-commit-config.yaml`; add language/ecosystem
managers as your repo grows.

## Configuring GitHub for a repo created from this template

Some settings can't be templated as files and need to be set once per repo via
the GitHub API. Run, with the [`gh` CLI](https://cli.github.com) authenticated
as an account with admin rights on the new repo:

```bash
make protect-branch
```

This is for a repo **not yet** managed by `terraform/` (see below) — running
it against one of the repos listed in `terraform/terraform.tfvars`'s `var.repos`
fights the next `terraform apply`. It runs `scripts/protect-branch.sh` and is
idempotent (safe to re-run). It:

- Enables repository **auto-merge**, which `renovate.json`'s `platformAutomerge`
  depends on — without it, Renovate's PRs sit fully green forever with nothing
  to merge them.
- Enables **delete branch on merge**, so merged Renovate branches don't pile up.
- Deletes every ruleset currently on the repo, then creates a fresh one on the
  target branch (default `main`, override with `BRANCH=<name>`) requiring the
  given status checks and 1 approving review (override with
  `APPROVALS_REQUIRED`), with the Renovate GitHub App and the repo **Admin**
  role exempted as bypass actors on both. Because it clears existing rulesets
  first, re-runs replace rather than accumulate — don't run it against a repo
  that has unrelated rulesets you want to keep.

`CHECKS` defaults to this template's single required status-check context,
`pre-commit / Pre-commit`. It's a **newline-separated** list (not space, since a
context name can itself contain spaces, like the reusable-workflow context
above) — override it as you add CI workflows:

```bash
make protect-branch CHECKS="$(printf 'pre-commit / Pre-commit\nbuild\ntest')"
```

The `pre-commit` job calls a reusable workflow, so its context is
`<caller job id> / <reusable job name>` = `pre-commit / Pre-commit`, **not** the
bare `pre-commit` — requiring the bare name leaves the check "Expected" forever.
Confirm the exact context names for your repo's workflows with `gh pr checks`.

## Managing GitHub repos with Terraform

`terraform/` creates and manages every jay-withers GitHub repository —
including this one — via the `integrations/github` provider, normalizing
each onto the settings `terraform-root-aks` had configured by hand. State is
local, gitignored, and never committed; applying is local-only for now (CI
only plans). See [`terraform/README.md`](terraform/README.md) for what it
manages, the state/auth tradeoffs, and the PAT it needs.

## Structure

```text
.devcontainer/
  devcontainer.json    # dev container (ghcr.io/jay-withers/dev-containers/terraform)
.github/
  workflows/
    ci-lint.yml        # lints all files on PRs to main (reusable workflow)
    cd-tag.yml         # auto-tags + releases on merge to main (semver, conventional commits)
    ci-terraform.yml   # plans terraform/ on PRs that touch it (no CI apply)
.editorconfig          # baseline editor settings (aligned with pre-commit hooks)
.gitattributes         # git-level LF normalization
.pre-commit-config.yaml
commitlint.config.js   # commitlint (Conventional Commits) config
renovate.json          # automated dependency updates
scripts/
  protect-branch.sh    # one-time GitHub settings for a repo not yet in terraform/
terraform/              # manages every jay-withers GitHub repo (see terraform/README.md)
CLAUDE.md              # guidance for Claude Code
LICENSE
Makefile
```
