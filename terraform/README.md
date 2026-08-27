# terraform

Manages every repository under `github.com/jay-withers` — including this one
— via the [`integrations/github`](https://registry.terraform.io/providers/integrations/github/latest/docs)
provider.

## What it manages

- `github_repository.this` — one per entry in `var.repos` (declared in
  `variables.tf`, populated in `terraform.tfvars`): visibility,
  issues/projects/wiki/discussions, and merge-method settings.
- `github_repository_ruleset.main` — a "Protect main" ruleset per repo,
  requiring a PR (squash-only, no approvals needed on this personal account,
  thread resolution required) and each repo's status checks.
- `azurerm_user_assigned_identity.state` / `azurerm_federated_identity_credential.state`
  / `azurerm_role_assignment.state_access` (`identities.tf`, `state.tf`) — the
  "shared" Terraform state storage account's consumer side: one
  container-scoped identity per entry in `var.state_consumers`, federated to
  that repo's GitHub Actions. This is the only Azure-facing part of this
  module; everything else above is GitHub. The account itself is created by
  `../scripts/bootstrap-state.ps1`, not Terraform — see its header comment.

Settings common to every repo live once in `locals.tf` (`repo_defaults`,
`ruleset_defaults`), taken from `jay-withers/terraform-root-aks`'s live
configuration — the repo these were originally hand-set on. Only what
actually differs per repo (description, topics, required status checks)
lives in `var.repos`.

`terraform.tfvars` is committed (not gitignored) — unlike the usual
convention of using it for untracked, per-machine or secret values, here it
*is* the desired-state data for `var.repos`, so it belongs in version
control and goes through PR review like everything else.

## State

Until the migration below, state is **local and never committed** — no
remote backend, and `terraform.tfstate` is gitignored. That means:

- It only ever exists on whichever machine ran `terraform apply` last. Losing
  it (a fresh clone, a wiped devcontainer) is not a disaster: `imports.tf`'s
  `import` blocks cover every resource, so the next `terraform plan`/`apply`
  just re-imports everything from live GitHub data before computing a diff.
  Expect a from-scratch plan to always list every resource as "to import" —
  that's this recovering state, not drift.
- No locking, and no CI apply (see below) — so don't run `make apply` from
  two places at once.
- `.terraform/` (the provider plugin cache) is also gitignored.

**Migrating to remote state**: `backend.tf` is already committed, pointing at
the "shared" storage account this module also manages access to (see "What
it manages" above) — but adding it here does not switch anything over by
itself. The one-time move is: run `../scripts/bootstrap-state.ps1` (creates
the account — see its header comment for why that's not Terraform), `make
apply` once against local state so this repo's own identity and RBAC grant
exist, then `terraform -chdir=terraform init -migrate-state`. That one
command carries every existing GitHub-managed resource's state, plus the new
Azure resources, into the account together — everything above about
re-importing from live GitHub data on a lost state file no longer applies
once this has run.

Applying is **local-only** for now: `ci-terraform` only plans on PRs (see
below), nothing runs `terraform apply` in CI. Run `make apply` yourself after
merging a change to `terraform/`.

## Auth

Two unrelated credentials, because this module now spans two providers:

**GitHub** — the provider reads `GITHUB_TOKEN` from the environment (no
token is ever written into these files). It needs to authenticate as an
account with **Administration: read and write** on every repo in
`var.repos` — in practice, a PAT belonging to `jay-withers`, so it also gets
the ruleset's Admin `bypass_actors` exemption:

- **Local**: create a fine-grained PAT (or classic `repo`-scope PAT), export
  it as `GITHUB_TOKEN` in your shell before running any `make` target below.
- **CI**: the same kind of PAT, stored as the repo secret `TF_GITHUB_TOKEN`
  (not `GITHUB_TOKEN` — GitHub reserves that secret name), mapped to the
  `GITHUB_TOKEN` env var for `ci-terraform`'s plan job. Read-only in effect
  (CI never applies), but the ruleset/repository read endpoints still need an
  authenticated admin to see full settings.

**Azure** — needed for `state.tf`/`identities.tf`, and (once `backend.tf` is
active) for `terraform init` itself:

- **Local**: Azure CLI, logged in, with Owner or Contributor + User Access
  Administrator on the subscription, and `ARM_SUBSCRIPTION_ID` exported (the
  provider doesn't infer it from the `az` context). That same `az` login is
  also all `../scripts/bootstrap-state.ps1` needs — it shells out to the CLI
  rather than the Az PowerShell modules — plus PowerShell 7+ to run it.
- **CI**: OIDC, not a secret — `ci-terraform.yml`'s `plan` job is gated on
  the `AZURE_CLIENT_ID` repository variable, exactly like
  `terraform-root-aks`'s. **Until that variable (and `AZURE_TENANT_ID`/
  `AZURE_SUBSCRIPTION_ID`) is set, the entire `plan` job is skipped — GitHub-only
  changes included**, not just the Azure resources: `terraform init`
  initializes the whole configuration, backend included, in one step, so
  there's no way to plan just the GitHub side without Azure credentials once
  a real backend is configured. Set the three variables from this repo's own
  `state_github_secrets` output once the migration above has run.

Never paste either credential into chat, commits, or these files —
`gitleaks` (pre-commit and CI) is only a backstop, not a substitute for care.

## Commands

```bash
make init      # terraform init
make fmt       # terraform fmt -recursive
make validate  # terraform init + validate
make plan      # terraform init + plan
make apply     # terraform init + apply
```

## Adding a repository

Add an entry to `var.repos` in `terraform.tfvars` (a brand-new repo needs no
entry in `locals.existing_ruleset_ids` — that's only for repos with a
ruleset to import) and open a PR. `ci-terraform` plans it; after merging,
run `make apply` locally to actually create the repo and its ruleset.
