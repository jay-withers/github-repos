#!/usr/bin/env bash
# Enforces that `locals`, `variable`, `output`, and `data` blocks live in a
# file whose name starts with the matching keyword — locals.tf, variables.tf,
# outputs.tf, data.tf, or a topic-scoped variant of any of them (e.g.
# outputs.network.tf, data.state.tf). TFLint's terraform_standard_module_structure
# rule covers variables.tf/outputs.tf but hardcodes those exact filenames (no
# topic-scoped variants, no locals/data support), so this replaces it
# entirely. Copied from jay-withers/template-repo-terraform-root's
# scripts/check-tf-file-layout.sh - see that repo for the canonical version -
# with two additions specific to this repo: `data` (this module has real
# Azure data-source lookups; the template doesn't), and `terraform`/`provider`
# blocks being required in versions.tf (this repo's own house rule, on top of
# the template's).
set -euo pipefail

violations=0

check_block() {
  local file=$1 keyword=$2 pattern=$3
  local base
  base=$(basename "$file")
  if [[ ! "$base" =~ ^${keyword}(\..+)?\.tf$ ]] && grep -qE "$pattern" "$file"; then
    echo "error: ${keyword%s} block found in $file — move it to ${keyword}.tf (or ${keyword}.<topic>.tf)" >&2
    violations=1
  fi
}

while IFS= read -r -d '' file; do
  check_block "$file" locals '^locals[[:space:]]*\{'
  check_block "$file" variables '^variable[[:space:]]+"[^"]+"[[:space:]]*\{'
  check_block "$file" outputs '^output[[:space:]]+"[^"]+"[[:space:]]*\{'
  check_block "$file" data '^data[[:space:]]+"[^"]+"[[:space:]]+"[^"]+"[[:space:]]*\{'
  check_block "$file" versions '^terraform[[:space:]]*\{'
  check_block "$file" versions '^provider[[:space:]]+"[^"]+"[[:space:]]*\{'
done < <(find . -type d -name '.?*' -prune -o -type f -name '*.tf' -print0)

exit "$violations"
