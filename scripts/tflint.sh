#!/usr/bin/env bash
# Runs tflint against terraform/ with terraform.tfvars applied, so rules that
# depend on concrete variable values (naming, tags, region-specific checks)
# are evaluated against what's actually deployed, not unresolved variables.
#
# Adapted from jay-withers/template-repo-terraform-root's
# scripts/tflint-per-env.sh - that repo loops this over
# terraform/environments/*.tfvars because it deploys the same module to
# several environments; this repo has exactly one deployment and one
# terraform.tfvars, so the loop and the per-directory module discovery both
# collapse to a single invocation.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
tf_dir="$repo_root/terraform"

tflint --init --chdir="$tf_dir"
tflint --chdir="$tf_dir" --var-file=terraform.tfvars
