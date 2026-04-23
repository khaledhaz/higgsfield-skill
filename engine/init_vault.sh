#!/bin/bash
# init_vault.sh — idempotent per-project vault bootstrap for Higgsfield.
# Default vault path: $PWD/hf-projects  (i.e., inside whatever folder you run the skill from)
# Override with: HF_VAULT_DIR=/some/path init_vault.sh

set -e

VAULT="${HF_VAULT_DIR:-$PWD/hf-projects}"

mkdir -p "$VAULT/Projects"
mkdir -p "$VAULT/_templates"
mkdir -p "$VAULT/_runs"

template="$VAULT/_templates/new-project.md"
if [ ! -f "$template" ]; then
  cat > "$template" <<'TEMPLATE'
---
project: example-slug
status: inbox
aspect: 16:9
duration: vo-driven
style_reference: null
vo:
  script: |
    (paste the narration script here)
  model: eleven-v3
  voice: TALLULAH
retries_per_shot: 5
parallelism: 3
schedule: null
---

## Script

## Style notes

## Beats
<!-- engine:beats -->
<!-- /engine:beats -->

## Shots
<!-- engine:shots -->
<!-- /engine:shots -->

## Review log
<!-- engine:reviews -->
<!-- /engine:reviews -->

## Execution log
<!-- engine:begin -->
<!-- engine:end -->

## Questions

## Outputs
- VO:
- Final:

## Auto-edits made during this run
TEMPLATE
  echo "Created template: $template"
else
  echo "Template exists, skipping: $template"
fi

echo "Vault ready: $VAULT"
