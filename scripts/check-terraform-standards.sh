#!/usr/bin/env bash
# Enforces this repo's Terraform file-layout standards (see terraform/*.tf
# for the reference layout this encodes):
#   - data/locals/variable/output blocks each live in a dedicated,
#     predictably-named file (data.tf or data.<name>.tf, and likewise for
#     locals/variables/outputs) - and that file carries no other block type.
#   - terraform{}/provider{} blocks (and the backend block nested inside
#     terraform{}) all live together in one file, versions.tf - the name
#     HashiCorp's own "Standard Module Structure" doc uses for the
#     terraform{}/required_providers block, extended here to the provider
#     blocks too since this repo already keeps all three together.
# Wired in as a local pre-commit hook in .pre-commit-config.yaml.
#
# Block detection is a plain unindented-line grep, not a real HCL parse -
# `terraform fmt` always writes top-level blocks flush left, so this is
# reliable for files that pass that hook (which runs before this one).
set -euo pipefail

# One dedicated-file rule per block type: "<block type>:<glob> <glob> ...".
DEDICATED_RULES=(
    "data:data.tf data.*.tf"
    "locals:locals.tf locals.*.tf"
    "variable:variables.tf variables.*.tf"
    "output:outputs.tf outputs.*.tf"
)
# terraform/provider share a single, fixed file rather than a name pattern.
SHARED_FILE="versions.tf"
SHARED_TYPES="terraform provider"

status=0

# Word-splitting $2 into individual glob patterns is intentional here.
# shellcheck disable=SC2053
matches_any_pattern() {
    local name=$1 pattern
    for pattern in $2; do
        [[ "$name" == "$pattern" ]] && return 0
    done
    return 1
}

for file in "$@"; do
    base=$(basename "$file")
    types=$(grep -oE '^(data|locals|resource|module|variable|output|terraform|provider) ' "$file" | awk '{print $1}' | sort -u || true)

    for rule in "${DEDICATED_RULES[@]}"; do
        block_type=${rule%%:*}
        patterns=${rule#*:}

        if grep -qx "$block_type" <<<"$types" && ! matches_any_pattern "$base" "$patterns"; then
            echo "$file: has a '$block_type' block but isn't named ${patterns// / or }" >&2
            status=1
        fi

        if matches_any_pattern "$base" "$patterns"; then
            other_types=$(grep -vx "$block_type" <<<"$types" | grep -v '^$' || true)
            if [[ -n "$other_types" ]]; then
                echo "$file: named for '$block_type' blocks but also has: $(tr '\n' ' ' <<<"$other_types")- split it" >&2
                status=1
            fi
        fi
    done

    for block_type in $SHARED_TYPES; do
        if grep -qx "$block_type" <<<"$types" && [[ "$base" != "$SHARED_FILE" ]]; then
            echo "$file: has a '$block_type' block but isn't named $SHARED_FILE" >&2
            status=1
        fi
    done

    if [[ "$base" == "$SHARED_FILE" ]]; then
        other_types=$(grep -vE '^(terraform|provider)$' <<<"$types" | grep -v '^$' || true)
        if [[ -n "$other_types" ]]; then
            echo "$file: is $SHARED_FILE but also has: $(tr '\n' ' ' <<<"$other_types")- split it" >&2
            status=1
        fi
    fi
done

exit $status
