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

4. Add the new repo to `terraform/terraform.tfvars`'s `var.repos` and run
   `make apply` (see [Managing GitHub repos with
   Terraform](#managing-github-repos-with-terraform)) to pick up the
   settings that can't be templated as files — auto-merge, branch
   protection, required status checks. Until then, the repo just has
   GitHub's defaults.

## Commands

Run `make` (or `make help`) to list the available targets:

```bash
make install           # install pre-commit hooks (run once after cloning)
make lint               # run all pre-commit hooks against every file
make plan / apply       # terraform/ — see terraform/README.md for required auth
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
  `jay-withers/workflows/.github/workflows/pre-commit.yml`. Its status
  check reports as `pre-commit / Pre-commit`.
- **`.github/workflows/cd-tag.yml`** — on every merge to `main`, creates a
  semver tag and matching GitHub release from the Conventional Commits since the
  last release (default bump: patch), via
  `jay-withers/workflows/.github/workflows/release.yml`.
- **`.github/workflows/ci-terraform.yml`** — plans `terraform/` on PRs that
  touch it (no CI apply — see [`terraform/README.md`](terraform/README.md)).

Both `ci-lint`/`cd-tag` pin the reusable workflow by commit SHA with the tag
as a comment. Add your own `ci-*` workflows (build, test, etc.) as you add
code, and require their checks by adding them to the repo's
`required_status_checks` in `terraform/terraform.tfvars`'s `var.repos` (see
below).

## Renovate

`renovate.json` extends `config:recommended` on a weekly schedule with
auto-approve and automerge. `platformAutomerge` needs repo-level auto-merge to
be enabled — Terraform does that once a repo is added to `var.repos` (see
below). The `pre-commit` manager updates the frozen hook revisions in
`.pre-commit-config.yaml`; add language/ecosystem managers as your repo grows.

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
terraform/              # manages every jay-withers GitHub repo (see terraform/README.md)
CLAUDE.md              # guidance for Claude Code
LICENSE
Makefile
```
