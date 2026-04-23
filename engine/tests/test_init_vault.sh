#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT="$SCRIPT_DIR/../init_vault.sh"
TEST_VAULT="$SCRIPT_DIR/tmp-vault"

# Clean slate
rm -rf "$TEST_VAULT"

# Test 1: first run creates structure
HF_VAULT_DIR="$TEST_VAULT" "$INIT"

[ -d "$TEST_VAULT/Projects" ] || { echo "FAIL: Projects/ missing"; exit 1; }
[ -d "$TEST_VAULT/_templates" ] || { echo "FAIL: _templates/ missing"; exit 1; }
[ -d "$TEST_VAULT/_runs" ] || { echo "FAIL: _runs/ missing"; exit 1; }
[ -f "$TEST_VAULT/_templates/new-project.md" ] || { echo "FAIL: template missing"; exit 1; }

# Template should contain required frontmatter keys
grep -q "^project:" "$TEST_VAULT/_templates/new-project.md" || { echo "FAIL: template missing project: field"; exit 1; }
grep -q "^status:" "$TEST_VAULT/_templates/new-project.md" || { echo "FAIL: template missing status: field"; exit 1; }
grep -q "engine:begin" "$TEST_VAULT/_templates/new-project.md" || { echo "FAIL: template missing engine:begin marker"; exit 1; }

echo "PASS test_init_vault first-run"

# Test 2: idempotent (re-running doesn't error or clobber)
touch "$TEST_VAULT/_templates/new-project.md.userMod"
HF_VAULT_DIR="$TEST_VAULT" "$INIT"
[ -f "$TEST_VAULT/_templates/new-project.md.userMod" ] || { echo "FAIL: idempotent run clobbered user file"; exit 1; }

echo "PASS test_init_vault idempotent"

# v2 template shape
grep -q "retries_per_shot: 5" "$TEST_VAULT/_templates/new-project.md" \
  || { echo "FAIL: template missing retries_per_shot"; exit 1; }
grep -q "parallelism: 3" "$TEST_VAULT/_templates/new-project.md" \
  || { echo "FAIL: template missing parallelism"; exit 1; }
grep -q "<!-- engine:beats -->" "$TEST_VAULT/_templates/new-project.md" \
  || { echo "FAIL: template missing beats region"; exit 1; }
grep -q "<!-- engine:shots -->" "$TEST_VAULT/_templates/new-project.md" \
  || { echo "FAIL: template missing shots region"; exit 1; }
grep -q "<!-- engine:reviews -->" "$TEST_VAULT/_templates/new-project.md" \
  || { echo "FAIL: template missing reviews region"; exit 1; }
if grep -q "^shots: \[\]" "$TEST_VAULT/_templates/new-project.md"; then
  echo "FAIL: v1 'shots: []' placeholder still present"
  exit 1
fi
echo "PASS test_init_vault v2-schema"

# Cleanup
rm -rf "$TEST_VAULT"
echo "ALL PASSED: init_vault"
