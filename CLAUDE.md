# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

A language-agnostic GitHub repository template. It provides a dev container,
generic pre-commit hooks, PR/merge CI workflows (linting via a shared reusable
workflow, and auto-tagging on merge), Renovate dependency updates, Conventional
Commits enforcement, and Makefile + branch-protection scaffolding. It ships no
application code on purpose — a repo created from it adds its own source and
layers project-specific hooks/CI on top of this baseline.

## Dev container

The repo is built around the dev container at `.devcontainer/devcontainer.json`,
which uses the image `ghcr.io/jay-withers/dev-containers/base:latest` and runs
`make install` on creation to wire up the pre-commit hooks. Prefer working
inside the container so tooling versions match CI.

## Commands

`make` with no target prints the self-documenting help (the default goal).

```bash
make install           # install pre-commit hooks (run once after cloning)
make protect-branch    # configure GitHub repo settings (auto-merge, branch protection) — see scripts/protect-branch.sh; override BRANCH/CHECKS to match your repo's checks
make lint              # run all pre-commit hooks against every file
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
