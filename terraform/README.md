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

Remote: the `backend "azurerm"` block lives in `versions.tf` (not a separate
`backend.tf`), pointing at the "shared" storage account this module also
manages access to (see "What it manages" above) — `rg-tfstate-shared` /
`sttfsharedjw` / the `github-repos` container. That account is created by
`../scripts/bootstrap-state.ps1`, not Terraform — see its header comment for
why. Durability comes from the storage account's blob versioning and 30-day
soft-delete (also set up by that script), not from any Terraform-side
recovery mechanism — there's no `import` block anywhere in this module,
deliberately: every resource it manages already exists in state, so plans
diff against real state rather than trying to re-derive it from live GitHub
data.

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
  authenticated admin to see full settings.

**Azure** — needed for `state.tf`/`identities.tf`/`data.tf`, and for
`terraform init` itself (the backend block in `versions.tf` is already active):

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
  `state_github_secrets` output (`terraform output state_github_secrets`,
  after `make apply` has created this repo's identity — see "What it
  manages" above) via `gh variable set`/`gh secret set`.

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
| [azurerm_user_assigned_identity.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [github_repository.this](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_ruleset.main](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset) | resource |
| [azurerm_resource_group.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_storage_account.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/storage_account) | data source |
| [azurerm_storage_container.consumer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/storage_container) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the identities this repo creates. See identities.tf. | `string` | `"westeurope"` | no |
| <a name="input_repos"></a> [repos](#input\_repos) | GitHub repositories to manage, keyed by repo name. | <pre>map(object({<br/>    description = optional(string, "")<br/>    topics      = optional(list(string), [])<br/>    # Overrides local.repo_defaults.visibility ("public") for repos that need<br/>    # to be private. Left null for every repo that should stay on the<br/>    # default - see CLAUDE.md.<br/>    visibility = optional(string)<br/>    required_status_checks = optional(list(object({<br/>      context        = string<br/>      integration_id = optional(number)<br/>    })), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The shared state resource group. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $ResourceGroupName. Changing this means changing the script and re-running it first. | `string` | `"rg-tfstate-shared"` | no |
| <a name="input_state_consumers"></a> [state\_consumers](#input\_state\_consumers) | One entry per consumer of the shared state storage account - repos that<br/>need state storage but aren't part of the azure-landingzone landing zone<br/>(that side has its own equivalent in azure-landingzone/terraform/bootstrap,<br/>which reuses landingzones' vended identities where one exists). Every<br/>entry here always gets a brand new identity, since none of these repos<br/>have one already.<br/><br/>The map key names the consumer and is also its container name - containers<br/>are created by scripts/bootstrap-state.ps1, so add the key to that<br/>script's containers.json (and re-run it) before adding it here, or the<br/>container data source lookup fails. | <pre>map(object({<br/>    github_repo        = string<br/>    federated_subjects = optional(map(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_storage_account_name"></a> [storage\_account\_name](#input\_storage\_account\_name) | The shared state storage account. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $StorageAccountName. Changing this means changing the script and re-running it first. | `string` | `"sttfsharedjw"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | HTML URL of every managed repository, keyed by name. |
| <a name="output_state_backend_config"></a> [state\_backend\_config](#output\_state\_backend\_config) | Per consumer: the azurerm backend block values for its own backend.tf. |
| <a name="output_state_github_secrets"></a> [state\_github\_secrets](#output\_state\_github\_secrets) | Repository variables to set on each state consumer's repo. |
<!-- END_TF_DOCS -->
