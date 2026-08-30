variable "repos" {
  description = <<-DESCRIPTION
    GitHub repositories to manage, keyed by repo name.

    `remote_state` opts a repo into the shared Terraform state storage
    account: it gets its own container, a container-scoped federated identity
    (identities.tf/state.tf) and the AZURE_* Actions variables its own CI
    needs to use that identity (actions.tf). Leave it false for repos with no
    Terraform of their own - an unused identity and container is clutter, not
    a safe default.

    `environments` scopes all of that per environment instead of per repo, for
    a repo that deploys the same module several times (dev/stg/prd). Each
    environment gets its own container (`<repo>-<env>`), its own identity, a
    GitHub environment, and the AZURE_* values as *environment* variables
    rather than repository ones - so one environment's credentials can never
    plan or apply another's, and prd can later grow approval gates without
    touching dev. The cost is that every job in that repo's workflows must
    declare `environment: <env>`, because the identity is federated on the
    `...:environment:<env>` OIDC subject and nothing else. Leave it empty for
    a repo with a single deployment (this one) - it then gets one identity,
    one container and plain repository variables, federated on pull_request
    and main.
  DESCRIPTION

  type = map(object({
    description  = optional(string, "")
    topics       = optional(list(string), [])
    remote_state = optional(bool, false)
    environments = optional(set(string), [])
    required_status_checks = optional(list(object({
      context        = string
      integration_id = optional(number)
    })), [])
  }))
  # No default - see terraform.tfvars for the actual repo list.

  validation {
    condition     = alltrue([for repo in var.repos : repo.remote_state if length(repo.environments) > 0])
    error_message = "environments only applies to a repo with remote_state = true."
  }

  # Repo and environment names become the state container name, and Azure
  # container names are 3-63 lowercase alphanumerics and hyphens. Caught here
  # rather than as an opaque azurerm error on apply.
  validation {
    condition = alltrue(flatten([
      for name, repo in var.repos : [
        for suffix in(length(repo.environments) > 0 ? [for env in repo.environments : "${name}-${env}"] : [name]) :
        can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", suffix))
      ] if repo.remote_state
    ]))
    error_message = "A remote_state repo's name (plus each environment) must be a valid storage container name: 3-63 lowercase alphanumerics or hyphens."
  }
}

variable "github_owner" {
  description = "GitHub account that owns every repo in var.repos. Used by the provider in versions.tf and to build the OIDC subjects in locals.tf, so the two can never disagree."
  type        = string
  default     = "jay-withers"
}

variable "github_owner_id" {
  description = "Numeric account ID of var.github_owner, from `gh api users/<owner> --jq .id`. Needed for GitHub's immutable OIDC subjects - see locals.tf's state_subject_prefixes. Not derived from a data source: the github provider's user data source exposes the GraphQL node ID, not this."
  type        = number
  default     = 288264678
}

variable "location" {
  description = "Azure region for the identities this repo creates. See identities.tf."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "The shared state resource group. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $ResourceGroupName. Changing this means changing the script and re-running it first."
  type        = string
  default     = "rg-tfstate-shared"
}

variable "storage_account_name" {
  description = "The shared state storage account. Created by scripts/bootstrap-state.ps1, not Terraform - must match that script's hardcoded $StorageAccountName. Changing this means changing the script and re-running it first."
  type        = string
  default     = "sttfsharedjw"
}
