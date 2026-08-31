variable "repos" {
  description = "GitHub repositories to manage, keyed by repo name."
  type = map(object({
    description = optional(string, "")
    topics      = optional(list(string), [])
    # Overrides local.repo_defaults.visibility ("public") for repos that need
    # to be private. Left null for every repo that should stay on the
    # default - see CLAUDE.md.
    visibility = optional(string)
    required_status_checks = optional(list(object({
      context        = string
      integration_id = optional(number)
    })), [])
  }))
  # No default - see terraform.tfvars for the actual repo list.
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

variable "state_consumers" {
  description = <<-DESCRIPTION
    One entry per consumer of the shared state storage account - repos that
    need state storage but aren't part of the azure-landingzone landing zone
    (that side has its own equivalent in azure-landingzone/terraform/bootstrap,
    which reuses landingzones' vended identities where one exists). Every
    entry here always gets a brand new identity, since none of these repos
    have one already.

    The map key names the consumer and is also its container name - containers
    are created by scripts/bootstrap-state.ps1, so add the key to that
    script's containers.json (and re-run it) before adding it here, or the
    container data source lookup fails.
  DESCRIPTION

  type = map(object({
    github_repo        = string
    federated_subjects = optional(map(string))
  }))

  default = {}
}
