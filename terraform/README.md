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
  that repo's GitHub Actions.
- `terraform_data.private_vulnerability_reporting` (`repository.tf`) — turns on
  private vulnerability reporting for every repo through the REST API on
  apply, since the provider can't manage it. Uses `gh api`, so it
  authenticates like the provider: `GITHUB_TOKEN`, else the `gh` login (admin).
- `azurerm_role_assignment.deploy` / `azurerm_role_assignment.deploy_reader`
  (`deploy.tf`) — for consumers whose pipeline applies, not just plans:
  Contributor on each of their `deploy_resource_groups`, and Reader on the
  subscription.
- `azurerm_resource_group.deploy` / `azurerm_role_assignment.deploy_rbac_admin`
  (`deploy.tf`, `imports.tf`) — for consumers with `create_resource_groups`:
  their `deploy_resource_groups` are created here (with `prevent_destroy`)
  rather than by a local first apply in the repo, and their pipeline gets
  Role Based Access Control Administrator on each, conditioned so it can
  assign any role except Owner, User Access Administrator and RBAC
  Administrator (Microsoft's "Allow most roles, but don't allow others to
  assign roles" example). That lets the repo's own pipeline apply the role
  assignments inside its group. A repo that created its group itself moves
  over with an `import` block here first, then `removed { lifecycle {
  destroy = false } }` in the repo.
- `azurerm_role_definition.container_app_environment_join` /
  `azurerm_role_assignment.deploy_join` (`deploy.tf`) — a custom role holding
  only `Microsoft.App/managedEnvironments/read` and `join/action`, assigned to
  each consumer on its `join_container_app_environments`. Writing a container
  app or job, by Terraform apply or image deploy, checks join on the
  environment, and the shared one belongs to azure-container-apps.
- `github_repository_environment.state` / `github_actions_environment_variable.state`
  (`actions.tf`) — a `dev` environment on each `var.state_consumers` repo,
  holding `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` as
  environment variables. The identity above is federated to that environment
  (`repo:<repo>:environment:dev`), so a job logs in to Azure only if it
  declares `environment: dev` — CI and CD alike. Every consumer must also be
  in `var.repos`.

  These are the only Azure-facing parts of this module; everything else
  above is GitHub. The account itself is created by
  `make bootstrap` (`../scripts/bootstrap-state.ps1`), not Terraform — see its
  header comment.

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
`make bootstrap` (`../scripts/bootstrap-state.ps1`), not Terraform — see its
header comment for why. Durability comes from the storage account's blob
versioning and 30-day soft-delete (also set up by that script), not from any
Terraform-side recovery mechanism — there's no `import` block anywhere in this module,
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
  also all `make bootstrap` (`../scripts/bootstrap-state.ps1`) needs — it
  shells out to the CLI rather than the Az PowerShell modules — plus
  PowerShell 7+ to run it.
- **CI**: OIDC, not a secret — `ci-terraform.yml`'s `plan` job is gated on
  the `AZURE_CLIENT_ID` repository variable, exactly like
  `terraform-root-aks`'s. **Until that variable (and `AZURE_TENANT_ID`/
  `AZURE_SUBSCRIPTION_ID`) is set, the entire `plan` job is skipped — GitHub-only
  changes included**, not just the Azure resources: `terraform init`
  initializes the whole configuration, backend included, in one step, so
  there's no way to plan just the GitHub side without Azure credentials once
  a real backend is configured. `make apply` sets all three on every state
  consumer's `dev` environment, this one included (`actions.tf`) — no manual
  `gh variable set` needed.

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
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |
| <a name="provider_github"></a> [github](#provider\_github) | ~> 6.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_state_naming"></a> [state\_naming](#module\_state\_naming) | Azure/naming/azurerm | ~> 0.4 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_federated_identity_credential.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_resource_group.deploy](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.deploy](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.deploy_join](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.deploy_rbac_admin](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.deploy_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.events_publisher](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.state_access](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.container_app_environment_join](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_definition) | resource |
| [azurerm_user_assigned_identity.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [github_actions_environment_variable.events](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_environment_variable) | resource |
| [github_actions_environment_variable.state](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_environment_variable) | resource |
| [github_repository.this](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_environment.state](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_environment) | resource |
| [github_repository_ruleset.main](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset) | resource |
| [github_repository_vulnerability_alerts.this](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_vulnerability_alerts) | resource |
| [terraform_data.private_vulnerability_reporting](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [azurerm_container_app_environment.join](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/container_app_environment) | data source |
| [azurerm_monitor_data_collection_endpoint.events](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/monitor_data_collection_endpoint) | data source |
| [azurerm_monitor_data_collection_rule.events](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/monitor_data_collection_rule) | data source |
| [azurerm_resource_group.deploy](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_resource_group.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_storage_account.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/storage_account) | data source |
| [azurerm_storage_container.consumer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/storage_container) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |
| [github_user.owner](https://registry.terraform.io/providers/integrations/github/latest/docs/data-sources/user) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_deploy_location"></a> [deploy\_location](#input\_deploy\_location) | Azure region for the resource groups this repo creates for consumers (`create_resource_groups`). Must be the shared Container Apps environment's region: a container app may sit in a different resource group from its environment, but not a different region. | `string` | `"northeurope"` | no |
| <a name="input_events_ingestion"></a> [events\_ingestion](#input\_events\_ingestion) | The platform's events data collection endpoint and rule (azure-container-apps' main.events.tf), looked up by name for consumers with `send_events`. Only read when at least one consumer sends events. | <pre>object({<br/>    resource_group = string<br/>    endpoint_name  = string<br/>    rule_name      = string<br/>  })</pre> | <pre>{<br/>  "endpoint_name": "dce-platform-dev",<br/>  "resource_group": "rg-platform-dev",<br/>  "rule_name": "dcr-platform-events-dev"<br/>}</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the identities this repo creates. See identities.tf. | `string` | `"westeurope"` | no |
| <a name="input_repos"></a> [repos](#input\_repos) | GitHub repositories to manage, keyed by repo name. | <pre>map(object({<br/>    description = optional(string, "")<br/>    topics      = optional(list(string), [])<br/>    # Repo to generate this one from via GitHub's template mechanism.<br/>    # Create-time only - see the template lifecycle.ignore_changes note in<br/>    # repository.tf.<br/>    generated_from_template = optional(string)<br/>    required_status_checks = optional(list(object({<br/>      context        = string<br/>      integration_id = optional(number)<br/>    })), [])<br/>    # Block merges into main on new CodeQL alerts at local.code_scanning_thresholds.<br/>    # Only for repos that actually run CodeQL (ci-codeql.yml calling<br/>    # jay-withers/workflows' codeql.yml): the rule waits for CodeQL results on<br/>    # the pull request, so turning it on for a repo with no analysis would<br/>    # leave every pull request unmergeable.<br/>    code_scanning = optional(bool, false)<br/>  }))</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The shared state resource group. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $ResourceGroupName. Changing this means changing the script and re-running it first. | `string` | `"rg-tfstate-shared"` | no |
| <a name="input_state_consumers"></a> [state\_consumers](#input\_state\_consumers) | One entry per consumer of the shared state storage account - repos that<br/>need state storage but aren't part of the azure-landingzone landing zone<br/>(that side has its own equivalent in azure-landingzone/terraform/bootstrap,<br/>which reuses landingzones' vended identities where one exists). Every<br/>entry here always gets a brand new identity, since none of these repos<br/>have one already.<br/><br/>The map key names the consumer and is also its container name - containers<br/>are created by scripts/bootstrap-state.ps1, so add the key to that<br/>script's containers.json (and re-run it) before adding it here, or the<br/>container data source lookup fails.<br/><br/>`deploy_resource_groups` lists the resource groups the consumer's<br/>pipeline may apply into: Contributor on each, plus Reader on the<br/>subscription so plans can resolve providers and other repos' resources<br/>by data source. Empty (the default) keeps the identity state-only.<br/><br/>`create_resource_groups` says who owns those groups. False (the default,<br/>for now) looks each one up: the consumer created it with a local first<br/>apply. True creates each one here, in var.deploy\_location, and also<br/>grants Role Based Access Control Administrator on it, conditioned so the<br/>pipeline can assign any role except Owner, User Access Administrator and<br/>RBAC Administrator. The consumer's pipeline can then apply its own role<br/>assignments, and a new repo needs no local first apply. A consumer that<br/>created its group itself moves over by an `import` block here, then a<br/>`removed { lifecycle { destroy = false } }` block in its own repo - in<br/>that order, so the group is never unmanaged.<br/><br/>`join_container_app_environments` lists Container Apps environments in<br/>other repos' resource groups that the consumer's apps and jobs run on.<br/>Writing a container app or job - a Terraform apply or an image deploy -<br/>needs `Microsoft.App/managedEnvironments/join/action` on its environment,<br/>which Contributor on the consumer's own resource group doesn't cover.<br/>Each entry gets the narrow custom role in deploy.tf on that environment.<br/><br/>`send_events` lets the consumer's pipeline and workloads write rows to the<br/>platform's Deployments\_CL and OpsEvents\_CL tables: Monitoring Metrics<br/>Publisher on the events data collection rule, plus<br/>EVENTS\_INGESTION\_ENDPOINT and EVENTS\_DCR\_IMMUTABLE\_ID on its environment,<br/>which jay-withers/workflows' container-apps-deploy.yml reads. The rule must<br/>already exist - azure-container-apps creates it. | <pre>map(object({<br/>    github_repo            = string<br/>    federated_subjects     = optional(map(string))<br/>    deploy_resource_groups = optional(list(string), [])<br/>    create_resource_groups = optional(bool, false)<br/>    join_container_app_environments = optional(list(object({<br/>      resource_group = string<br/>      name           = string<br/>    })), [])<br/>    send_events = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_storage_account_name"></a> [storage\_account\_name](#input\_storage\_account\_name) | The shared state storage account. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $StorageAccountName. Changing this means changing the script and re-running it first. | `string` | `"sttfsharedjw"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | HTML URL of every managed repository, keyed by name. |
| <a name="output_state_backend_config"></a> [state\_backend\_config](#output\_state\_backend\_config) | Per consumer: the azurerm backend block values for its own backend.tf. |
| <a name="output_state_github_secrets"></a> [state\_github\_secrets](#output\_state\_github\_secrets) | Environment variables set on each state consumer's dev environment by actions.tf. |
<!-- END_TF_DOCS -->
