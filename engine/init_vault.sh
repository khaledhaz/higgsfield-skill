#!/bin/bash
# init_vault.sh — idempotent Obsidian vault bootstrap for Higgsfield projects.
# Default vault path: ~/Obsidian/Higgsfield
# Override with: HF_VAULT_DIR=/some/path init_vault.sh

set -e

VAULT="${HF_VAULT_DIR:-$HOME/Obsidian/Higgsfield}"

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
transitions:
  mode: half-half
  seamless_pairs: []
retries_per_shot: 3
schedule: null
shots: []
---

## Script

## Style notes

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
