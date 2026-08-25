resource "github_repository_ruleset" "main" {
  for_each = var.repos

  name        = "Protect main"
  repository  = github_repository.this[each.key].name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/heads/main"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = local.renovate_app_id
    actor_type  = "Integration"
    bypass_mode = "always"
  }

  bypass_actors {
    actor_id    = local.admin_role_id
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  rules {
    pull_request {
      allowed_merge_methods             = local.ruleset_defaults.allowed_merge_methods
      required_approving_review_count   = local.ruleset_defaults.required_approving_review_count
      dismiss_stale_reviews_on_push     = local.ruleset_defaults.dismiss_stale_reviews_on_push
      require_code_owner_review         = local.ruleset_defaults.require_code_owner_review
      require_last_push_approval        = local.ruleset_defaults.require_last_push_approval
      required_review_thread_resolution = local.ruleset_defaults.required_review_thread_resolution
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      dynamic "required_check" {
        for_each = each.value.required_status_checks
        content {
          context        = required_check.value.context
          integration_id = required_check.value.integration_id
        }
      }
    }
  }
}
