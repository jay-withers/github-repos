variable "repos" {
  description = "GitHub repositories to manage, keyed by repo name."
  type = map(object({
    description = optional(string, "")
    topics      = optional(list(string), [])
    required_status_checks = list(object({
      context        = string
      integration_id = optional(number)
    }))
  }))
  # No default - see terraform.tfvars for the actual repo list.
}
