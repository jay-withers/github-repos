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
- `azurerm_storage_container.state` / `azurerm_user_assigned_identity.state` /
  `azurerm_federated_identity_credential.state` /
  `azurerm_role_assignment.state_access` (`state.tf`, `identities.tf`) — the
  "shared" Terraform state storage account's consumer side: a container, and a
  container-scoped identity federated to GitHub Actions, for every repo with
  `remote_state = true` in `var.repos`. This is the only Azure-facing part of
  this module; everything else above is GitHub. The account itself (and this
  repo's own container — see State below) is created by
  `../scripts/bootstrap-state.ps1`, not Terraform.
- `github_actions_variable.state_oidc` /
  `github_actions_environment_variable.state_oidc` /
  `github_repository_environment.state` (`actions.tf`) — the GitHub side of
  that same OIDC wiring: `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/
  `AZURE_SUBSCRIPTION_ID` published to each repo, so the identity and the
  values pointing at it can't drift apart.

Settings common to every repo live once in `locals.tf` (`repo_defaults`,
`ruleset_defaults`), taken from `jay-withers/terraform-root-aks`'s live
configuration — the repo these were originally hand-set on. Only what
actually differs per repo (description, topics, required status checks)
lives in `var.repos`.

`terraform.tfvars` is committed (not gitignored) — unlike the usual
convention of using it for untracked, per-machine or secret values, here it
*is* the desired-state data for `var.repos`, so it belongs in version
control and goes through PR review like everything else.

### State repos and environments

A repo opts in with `remote_state = true`, and gets one container (named after
the repo), one identity federated on `pull_request` + `refs/heads/main`, and
the three `AZURE_*` values as **repository** variables.

A repo that deploys the same module several times adds
`environments = ["dev", ...]` instead. Everything above then becomes
per-environment: a container per `<repo>-<env>`, an identity per environment
federated on the `repo:<owner>/<repo>:environment:<env>` subject only, a GitHub
environment, and the three values as **environment** variables. Two
consequences worth knowing before turning it on:

- Every job in that repo's workflows must declare `environment: <env>` — that
  is what makes GitHub mint the subject the identity trusts, and what makes
  `vars.AZURE_CLIENT_ID` resolve. A job without it gets no credentials.
- The GitHub environments are created bare, with no reviewers or branch
  policies. Adding a protection rule is that repo's own call — and note that a
  required reviewer would start queueing its PR *plans* for approval too.

`terraform-root-aks` and `azure-landingzone` currently declare `dev` only; the
others are single-deployment or have no Terraform at all.

#### Immutable OIDC subjects

GitHub is part-way through a rollout that changes the `sub` claim Actions
mints from `repo:<owner>/<repo>:...` to an **immutable** form carrying numeric
IDs — `repo:jay-withers@288264678/github-repos@1345898182:...`. A federated
credential created for the old form simply never matches the new one, and the
failure is an `AADSTS700213: No matching federated identity record found`
during `terraform init`, quoting the subject it actually presented.

It lands per repository, not per account — as of this writing `github-repos`
and `azure-landingzone` mint the ID form while `terraform-root-aks` still
mints the legacy one. Check any repo with:

```bash
gh api repos/jay-withers/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
```

(`use_immutable_subject` can read `false` while `sub_claim_prefix` is already
the ID form; the prefix is what actually gets minted.)

So `identities.tf` declares **every credential twice**, once per form — only
the matching one is ever presented, the other is inert, and a repo migrating
mid-flight keeps working with no change here. Entra allows 20 credentials per
identity, so there's plenty of room. Drop the legacy half (the `form` loop in
`locals.tf`'s `state_federated_credentials`) once every repo reports an ID
prefix. `var.github_owner_id` holds the numeric owner ID, since the `github`
provider's user data source exposes the GraphQL node ID rather than this one.

## State

Remote: the `backend "azurerm"` block lives in `versions.tf` (not a separate
`backend.tf`), pointing at the "shared" storage account this module also
manages access to (see "What it manages" above) — `rg-tfstate-shared` /
`sttfsharedjw` / the `github-repos` container. That account is created by
`../scripts/bootstrap-state.ps1`, not Terraform — see its header comment for
why. Durability comes from the storage account's blob versioning and 30-day
soft-delete (also set up by that script), not from any Terraform-side
recovery mechanism.

Every other state repo's container is Terraform's
(`azurerm_storage_container.state`), but this repo's own can't be: the backend
block points at it before Terraform has ever run, so
`../scripts/bootstrap-state.ps1` creates it and `state.tf` adopts it with a
permanent `import` block. That is the only `import` in the module, and it is
deliberately not a recovery mechanism for anything else: every GitHub resource
here already exists in state, so plans diff against real state rather than
re-deriving it from live GitHub data.

`.terraform/` (the provider plugin cache) is gitignored, same as any local
`terraform.tfstate*` left over from before the backend was wired in.

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
  authenticated admin to see full settings. Unlike the Azure variables below,
  this one stays a manual `gh secret set TF_GITHUB_TOKEN` — Terraform could
  only set it by taking the PAT as an input and then storing it in plain text
  in state.

**Azure** — needed for `state.tf`/`identities.tf`/`data.tf`, and for
`terraform init` itself (the backend block in `versions.tf` is already active):

- **Local**: Azure CLI, logged in, with Owner or Contributor + User Access
  Administrator on the subscription, and `ARM_SUBSCRIPTION_ID` exported (the
  provider doesn't infer it from the `az` context). Export `ARM_TENANT_ID`
  too if your `az` default context is in a different tenant from the state
  subscription — without it the backend fails `init` with a bare
  `401 InvalidAuthenticationInfo`, which says nothing about tenants. That same `az` login is
  also all `../scripts/bootstrap-state.ps1` needs — it shells out to the CLI
  rather than the Az PowerShell modules — plus PowerShell 7+ to run it.
- **CI**: OIDC, not a secret — `ci-terraform.yml`'s `plan` job is gated on
  the `AZURE_CLIENT_ID` repository variable, exactly like
  `terraform-root-aks`'s. **Until that variable (and `AZURE_TENANT_ID`/
  `AZURE_SUBSCRIPTION_ID`) is set, the entire `plan` job is skipped — GitHub-only
  changes included**, not just the Azure resources: `terraform init`
  initializes the whole configuration, backend included, in one step, so
  there's no way to plan just the GitHub side without Azure credentials once
  a real backend is configured. All three are set by this module
  itself (`actions.tf`) on every repo with `remote_state = true`, so a `make
  apply` is all it takes — no `gh variable set` step.

  That is a one-time bootstrap loop, and only for this repo: the variables
  that let its own CI plan can themselves only be created by a local `make
  apply`. Every repo onboarded afterwards is just a `terraform.tfvars` entry.

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

Add an entry to `var.repos` in `terraform.tfvars` and open a PR. `ci-terraform`
plans it; after merging, run `make apply` locally to actually create the repo
and its ruleset.

If that repo has Terraform of its own, add `remote_state = true` (plus
`environments = [...]` if it deploys more than one) in the same entry — the
apply then also creates its state container, identity and `AZURE_*` Actions
variables, and `terraform output state_backend_config` gives you the backend
block to paste into that repo.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |
| <a name="provider_github"></a> [github](#provider\_github) | 6.13.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_state_naming"></a> [state\_naming](#module\_state\_naming) | Azure/naming/azurerm | ~> 0.4 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_federated_identity_credential.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.state_access](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_container.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_user_assigned_identity.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [github_actions_environment_variable.state_oidc](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_environment_variable) | resource |
| [github_actions_variable.state_oidc](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_repository.this](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_environment.state](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_environment) | resource |
| [github_repository_ruleset.main](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset) | resource |
| [azurerm_resource_group.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_storage_account.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/storage_account) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | GitHub account that owns every repo in var.repos. Used by the provider in versions.tf and to build the OIDC subjects in locals.tf, so the two can never disagree. | `string` | `"jay-withers"` | no |
| <a name="input_github_owner_id"></a> [github\_owner\_id](#input\_github\_owner\_id) | Numeric account ID of var.github\_owner, from `gh api users/<owner> --jq .id`. Needed for GitHub's immutable OIDC subjects - see locals.tf's state\_subject\_prefixes. Not derived from a data source: the github provider's user data source exposes the GraphQL node ID, not this. | `number` | `288264678` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the identities this repo creates. See identities.tf. | `string` | `"westeurope"` | no |
| <a name="input_repos"></a> [repos](#input\_repos) | GitHub repositories to manage, keyed by repo name.<br/><br/>`remote_state` opts a repo into the shared Terraform state storage<br/>account: it gets its own container, a container-scoped federated identity<br/>(identities.tf/state.tf) and the AZURE\_* Actions variables its own CI<br/>needs to use that identity (actions.tf). Leave it false for repos with no<br/>Terraform of their own - an unused identity and container is clutter, not<br/>a safe default.<br/><br/>`environments` scopes all of that per environment instead of per repo, for<br/>a repo that deploys the same module several times (dev/stg/prd). Each<br/>environment gets its own container (`<repo>-<env>`), its own identity, a<br/>GitHub environment, and the AZURE\_* values as *environment* variables<br/>rather than repository ones - so one environment's credentials can never<br/>plan or apply another's, and prd can later grow approval gates without<br/>touching dev. The cost is that every job in that repo's workflows must<br/>declare `environment: <env>`, because the identity is federated on the<br/>`...:environment:<env>` OIDC subject and nothing else. Leave it empty for<br/>a repo with a single deployment (this one) - it then gets one identity,<br/>one container and plain repository variables, federated on pull\_request<br/>and main. | <pre>map(object({<br/>    description  = optional(string, "")<br/>    topics       = optional(list(string), [])<br/>    remote_state = optional(bool, false)<br/>    environments = optional(set(string), [])<br/>    required_status_checks = optional(list(object({<br/>      context        = string<br/>      integration_id = optional(number)<br/>    })), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The shared state resource group. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $ResourceGroupName. Changing this means changing the script and re-running it first. | `string` | `"rg-tfstate-shared"` | no |
| <a name="input_storage_account_name"></a> [storage\_account\_name](#input\_storage\_account\_name) | The shared state storage account. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $StorageAccountName. Changing this means changing the script and re-running it first. | `string` | `"sttfsharedjw"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | HTML URL of every managed repository, keyed by name. |
| <a name="output_state_backend_config"></a> [state\_backend\_config](#output\_state\_backend\_config) | Per state target: the azurerm backend block values for that repo's own versions.tf. |
| <a name="output_state_github_secrets"></a> [state\_github\_secrets](#output\_state\_github\_secrets) | Actions variables set on each state target by actions.tf, for reference. |
<!-- END_TF_DOCS -->
