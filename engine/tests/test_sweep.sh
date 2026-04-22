#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="$SCRIPT_DIR/../sweep.sh"
TEST_VAULT="$SCRIPT_DIR/tmp-vault-sweep"

rm -rf "$TEST_VAULT"
mkdir -p "$TEST_VAULT/Projects" "$TEST_VAULT/_runs"

cat > "$TEST_VAULT/Projects/due-now.md" <<'EOF'
---
project: due-now
status: scheduled
schedule: "2020-01-01T00:00:00"
---
EOF

cat > "$TEST_VAULT/Projects/due-future.md" <<'EOF'
---
project: due-future
status: scheduled
schedule: "2099-12-31T23:59:59"
---
EOF

cat > "$TEST_VAULT/Projects/inbox-only.md" <<'EOF'
---
project: inbox-only
status: inbox
---
EOF

cat > "$TEST_VAULT/Projects/already-done.md" <<'EOF'
---
project: already-done
status: done
---
EOF

actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ "$actual" = "due-now" ] || { echo "FAIL: expected 'due-now', got '$actual'"; exit 1; }
echo "PASS test_sweep emits-due-slug"

rm "$TEST_VAULT/Projects/due-now.md"
actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ -z "$actual" ] || { echo "FAIL: expected empty output, got '$actual'"; exit 1; }
echo "PASS test_sweep no-due-empty"

cat > "$TEST_VAULT/Projects/broken-schedule.md" <<'EOF'
---
project: broken-schedule
status: scheduled
schedule: "not a real date"
---
EOF
actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ -z "$actual" ] || { echo "FAIL: broken-schedule should not be emitted, got '$actual'"; exit 1; }
[ -f "$TEST_VAULT/_runs/sweep-errors.md" ] || {
  echo "FAIL: sweep-errors.md was not created for unparseable schedule"
  exit 1
}
grep -q "broken-schedule" "$TEST_VAULT/_runs/sweep-errors.md" || {
  echo "FAIL: sweep-errors.md does not mention broken-schedule"
  exit 1
}
echo "PASS test_sweep unparseable-logs-error"

rm -rf "$TEST_VAULT/Projects"
mkdir -p "$TEST_VAULT/Projects"
actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ -z "$actual" ] || { echo "FAIL: empty vault should give empty output"; exit 1; }
echo "PASS test_sweep empty-vault"

rm -rf "$TEST_VAULT"
echo "ALL PASSED: sweep"
