locals {
  # Repository-level settings every managed repo is normalized to, taken from
  # the live configuration of jay-withers/terraform-root-aks - the one repo
  # that already had these set by hand. See CLAUDE.md.
  repo_defaults = {
    has_issues      = true
    has_projects    = true
    has_wiki        = true
    has_discussions = false

    visibility = "public"

    allow_squash_merge = true
    allow_merge_commit = false
    allow_rebase_merge = false
    allow_auto_merge   = true

    delete_branch_on_merge      = true
    squash_merge_commit_title   = "COMMIT_OR_PR_TITLE"
    squash_merge_commit_message = "COMMIT_MESSAGES"

    # Secret scanning, free on public repos. Scanning and push protection were
    # already on live but unmanaged; declaring them means a repo created here
    # can't start without them, and a plan shows anyone switching them off.
    #
    # Non-provider patterns (generic secrets: private keys, connection strings)
    # aren't declared at all. GitHub doesn't offer them on user-owned repos and
    # leaves the field out of most reads, so declaring any value, "disabled"
    # included, is a diff on every plan (github-repos#106, #109). repository.tf
    # ignores it for the few repos that still report it. Add it back if
    # the account moves to an org. Validity checks and AI detection aren't here
    # either: the provider has no field for the first, and the second is paid.
    secret_scanning                 = "enabled"
    secret_scanning_push_protection = "enabled"
  }

  # "Protect main" ruleset shape, likewise taken from terraform-root-aks.
  #
  # NOTE: the live ruleset also has require_extra_approval_for_unattributed_changes
  # = true, a newer GitHub PR-rule field the integrations/github provider does
  # not yet expose (checked against the resource schema at authoring time).
  # It's simply absent from this resource's config below rather than pinned to
  # false - Terraform never reads or writes it, so it's left exactly as
  # GitHub set it and won't show up as drift.
  ruleset_defaults = {
    allowed_merge_methods             = ["squash"]
    required_approving_review_count   = 0
    dismiss_stale_reviews_on_push     = true
    require_code_owner_review         = false
    require_last_push_approval        = false
    required_review_thread_resolution = true
  }

  # What a new CodeQL alert has to be to block a merge, on repos with
  # code_scanning = true. high_or_higher is where injection, path traversal
  # and SSRF land; medium and below still show on the pull request and in the
  # Security tab, but would block on too many judgement calls to be a gate.
  # `errors` is the same idea for CodeQL's non-security (quality) results.
  code_scanning_thresholds = {
    security_alerts = "high_or_higher"
    alerts          = "errors"
  }

  # Bypass actors on every ruleset: the repo Admin role, and the Renovate
  # GitHub App (id from `gh api apps/renovate --jq .id`). Both `always`. GitHub
  # only honours bypass_actors on organization-owned repos - jay-withers is a
  # User account, so this is currently inert here, but declaring it keeps this
  # repo's ruleset identical in shape to every other repo's, and it starts
  # working for free if the account ever moves to an org. See CLAUDE.md.
  admin_role_id   = 5
  renovate_app_id = 2740

  # The GitHub environment every consumer's CI (plan) and CD (apply) jobs run
  # in. Declaring `environment:` makes a job's OIDC subject the environment
  # rather than the ref, so one federated credential covers both, and the
  # Azure login variables live on the environment rather than the repo. A
  # second environment (prod) would need its own identity anyway, so this is
  # a single value, not a list.
  state_environment = "dev"

  # This repo's own applies run in a second environment, restricted to main,
  # as an identity azure-landingzone's governance component creates and
  # grants (Contributor + User Access Administrator on the subscription). Pull
  # request plans stay in state_environment as this repo's ordinary consumer
  # identity, so branch code never holds those rights.
  apply_environment   = "apply"
  apply_identity_name = "uai-github-repos-apply-${local.state_environment}"

  # Federated credential names must be unique per identity and cannot contain
  # the ":" and "/" that appear in a subject, so the map key supplies the name
  # and the value supplies the subject. The key is never parsed back apart
  # anywhere, so a plain "-" join (not "--") is fine even though both halves
  # can themselves contain hyphens.
  # One entry per consumer and resource group it deploys into, keyed
  # "<consumer>-<resource group>" for the same reason as above.
  deploy_resource_groups = merge([
    for key, c in var.state_consumers : {
      for rg in c.deploy_resource_groups : "${key}-${rg}" => {
        consumer       = key
        resource_group = rg
        create         = c.create_resource_groups
      }
    }
  ]...)

  # Split by who owns the group (`create_resource_groups`), then joined back
  # into one id per entry so the grants in deploy.tf don't care which.
  created_resource_groups   = { for k, v in local.deploy_resource_groups : k => v if v.create }
  looked_up_resource_groups = { for k, v in local.deploy_resource_groups : k => v if !v.create }

  deploy_resource_group_ids = merge(
    { for k, _ in local.created_resource_groups : k => azurerm_resource_group.deploy[k].id },
    { for k, _ in local.looked_up_resource_groups : k => data.azurerm_resource_group.deploy[k].id },
  )

  # Microsoft's "Allow most roles, but don't allow others to assign roles"
  # example, verbatim apart from whitespace: any role may be assigned or
  # removed except Owner, RBAC Administrator and User Access Administrator, in
  # that GUID order (built-in role IDs, the same in every tenant). Both halves
  # are needed: `write` is checked against the request, `delete` against the
  # existing assignment, so neither granting nor removing an admin role works.
  # Microsoft's caveat: a custom role carrying roleAssignments/write would get
  # through. The pipeline can't create one (Contributor excludes
  # Microsoft.Authorization/*/Write), and this repo's only custom role
  # (deploy.tf) carries read and join.
  privileged_role_ids  = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635, f58310d9-a9f6-439a-9e8d-f62e7b41a168, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"
  rbac_admin_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
     )
    )
  EOT

  deploy_consumers = toset([for key, c in var.state_consumers : key if length(c.deploy_resource_groups) > 0])

  event_consumers = toset([for key, c in var.state_consumers : key if c.send_events])

  pipeline_event_repos = toset([for key, p in var.pipeline_environments : key if p.send_events])

  # One entry per pipeline environment and variable, keyed
  # "<repo>-<variable>", the same shape as state_github_variables.
  pipeline_github_variables = merge([
    for key, p in var.pipeline_environments : {
      for name, value in merge(
        {
          AZURE_CLIENT_ID       = data.azurerm_user_assigned_identity.pipeline[key].client_id
          AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
          AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
        },
        p.send_events ? {
          EVENTS_INGESTION_ENDPOINT = data.azurerm_monitor_data_collection_endpoint.events[0].logs_ingestion_endpoint
          EVENTS_DCR_IMMUTABLE_ID   = data.azurerm_monitor_data_collection_rule.events[0].immutable_id
        } : {},
        p.operator_variables ? local.operator_variables : {}
        ) : "${key}-${name}" => {
        repo  = key
        name  = name
        value = value
      }
    }
  ]...)

  join_container_app_environments = merge([
    for key, c in var.state_consumers : {
      for env in c.join_container_app_environments : "${key}-${env.resource_group}-${env.name}" => {
        consumer       = key
        resource_group = env.resource_group
        name           = env.name
      }
    }
  ]...)

  # The default subject uses GitHub's immutable form,
  # repo:<owner>@<owner id>/<repo>@<repo id>, which every consumer's token
  # carries (`use_immutable_subject` in
  # `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`). The
  # readable repo:<owner>/<repo> form never matches such a token, and Entra
  # rejects the login with AADSTS700213.
  state_federated_credentials = merge([
    for key, c in var.state_consumers : {
      for name, subject in coalesce(c.federated_subjects, {
        (local.state_environment) = format(
          "repo:%s@%s/%s@%s:environment:%s",
          data.github_user.owner.login,
          data.github_user.owner.id,
          github_repository.this[split("/", c.github_repo)[1]].name,
          github_repository.this[split("/", c.github_repo)[1]].repo_id,
          local.state_environment,
        )
        }) : "${key}-${name}" => {
        consumer = key
        subject  = subject
      }
    }
  ]...)

  # The environment variables a consumer's workflow logs in to Azure with -
  # one entry per consumer and variable, keyed "<consumer>-<variable>" for the
  # same reason as above. None of these are secret, so they're Actions
  # variables (vars.*), not secrets.
  state_github_variables = merge([
    for key, c in var.state_consumers : {
      for name, value in {
        AZURE_CLIENT_ID       = azurerm_user_assigned_identity.state[key].client_id
        AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
        AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
        } : "${key}-${name}" => {
        consumer = key
        name     = name
        value    = value
      }
    }
  ]...)

  # Where a consumer with `send_events` posts its rows. Kept apart from the
  # Azure login variables above so that a consumer without it never needs the
  # platform's rule to exist at plan time.
  events_github_variables = merge([
    for key in local.event_consumers : {
      for name, value in {
        EVENTS_INGESTION_ENDPOINT = data.azurerm_monitor_data_collection_endpoint.events[0].logs_ingestion_endpoint
        EVENTS_DCR_IMMUTABLE_ID   = data.azurerm_monitor_data_collection_rule.events[0].immutable_id
        } : "${key}-${name}" => {
        consumer = key
        name     = name
        value    = value
      }
    }
  ]...)

  # The operator's identifiers, under the variable names the consumers'
  # roots declare, for every consumer that applies from its own pipeline.
  # jay-withers/workflows' terraform-deploy.yml (v1.20.0+) exports TF_VAR_*
  # variables to Terraform, which ignores any a root doesn't declare, so one
  # set covers them all. Lists and objects are JSON, which Terraform accepts
  # as HCL.
  operator_variables = {
    TF_VAR_KEY_VAULT_ADMINISTRATOR_OBJECT_IDS = jsonencode([var.operator.object_id])
    TF_VAR_ADMINISTRATOR_OBJECT_ID            = var.operator.object_id
    TF_VAR_ALERT_EMAIL_ADDRESS                = var.operator.email
    TF_VAR_POSTGRES_ENTRA_ADMINISTRATOR = jsonencode({
      object_id      = var.operator.object_id
      principal_name = var.operator.principal_name
    })
  }

  operator_github_variables = merge([
    for key, c in var.state_consumers : {
      for name, value in local.operator_variables : "${key}-${name}" => {
        consumer = key
        name     = name
        value    = value
      }
    } if length(c.deploy_resource_groups) > 0
  ]...)
}
