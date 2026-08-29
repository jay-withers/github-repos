#!/usr/bin/env bash
# Runs checkov against terraform/ with terraform.tfvars applied, so checks
# that depend on concrete variable values are evaluated against what's
# actually deployed, not unresolved variables.
#
# Adapted from jay-withers/template-repo-terraform-root's
# scripts/checkov-per-env.sh - that repo loops this over
# terraform/environments/*.tfvars because it deploys the same module to
# several environments; this repo has exactly one deployment and one
# terraform.tfvars, so the loop collapses to a single invocation.
#
# Not passing --download-external-modules: same reasoning as that repo's
# script - Azure/naming/azurerm has no resources of its own to scan, so
# resolving it is pure cost (checkov's own graph-building overhead) for zero
# benefit. Expect a "Failed to download module" warning; it's harmless.
#
# --skip-check CKV_GIT_1 ("repository should be private"): every repo this
# module manages is deliberately public (repo_defaults.visibility in
# locals.tf) - that's the point of the account, not a gap to fix.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
tf_dir="$repo_root/terraform"

checkov -d "$tf_dir" --var-file "$tf_dir/terraform.tfvars" --quiet --compact --skip-check CKV_GIT_1
