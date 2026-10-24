variable "repos" {
  description = "GitHub repositories to manage, keyed by repo name."
  type = map(object({
    description = optional(string, "")
    topics      = optional(list(string), [])
    # Repo to generate this one from via GitHub's template mechanism.
    # Create-time only - see the template lifecycle.ignore_changes note in
    # repository.tf.
    generated_from_template = optional(string)
    required_status_checks = optional(list(object({
      context        = string
      integration_id = optional(number)
    })), [])
    # Block merges into main on new CodeQL alerts at local.code_scanning_thresholds.
    # Only for repos that actually run CodeQL (ci-codeql.yml calling
    # jay-withers/workflows' codeql.yml): the rule waits for CodeQL results on
    # the pull request, so turning it on for a repo with no analysis would
    # leave every pull request unmergeable.
    code_scanning = optional(bool, false)
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

    `deploy_resource_groups` lists the resource groups the consumer's
    pipeline may apply into: Contributor on each, plus Reader on the
    subscription so plans can resolve providers and other repos' resources
    by data source. Empty (the default) keeps the identity state-only. Each
    group must already exist - create it with a local apply first.

    `join_container_app_environments` lists Container Apps environments in
    other repos' resource groups that the consumer's apps and jobs run on.
    Writing a container app or job - a Terraform apply or an image deploy -
    needs `Microsoft.App/managedEnvironments/join/action` on its environment,
    which Contributor on the consumer's own resource group doesn't cover.
    Each entry gets the narrow custom role in deploy.tf on that environment.
  DESCRIPTION

  type = map(object({
    github_repo            = string
    federated_subjects     = optional(map(string))
    deploy_resource_groups = optional(list(string), [])
    join_container_app_environments = optional(list(object({
      resource_group = string
      name           = string
    })), [])
  }))

  default = {}
}
