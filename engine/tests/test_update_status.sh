#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE="$SCRIPT_DIR/../update_status.py"
FIX_DIR="$SCRIPT_DIR/fixtures"

mkdir -p "$FIX_DIR"

cat > "$FIX_DIR/note-update.md" <<'EOF'
---
project: test-slug
status: inbox
aspect: 16:9
shots: []
---

## Script
Preserved body content.
EOF

python3 "$UPDATE" "$FIX_DIR/note-update.md" active

actual_status=$(grep "^status:" "$FIX_DIR/note-update.md" | awk '{print $2}')
[ "$actual_status" = "active" ] || { echo "FAIL: status not updated, got $actual_status"; exit 1; }

grep -q "Preserved body content" "$FIX_DIR/note-update.md" || {
  echo "FAIL: body content was lost"
  exit 1
}

grep -q "^project: test-slug" "$FIX_DIR/note-update.md" || {
  echo "FAIL: project field was lost"
  exit 1
}
echo "PASS test_update_status basic"

python3 "$UPDATE" "$FIX_DIR/note-update.md" active
actual_status=$(grep "^status:" "$FIX_DIR/note-update.md" | awk '{print $2}')
[ "$actual_status" = "active" ] || { echo "FAIL: idempotent update changed status"; exit 1; }
echo "PASS test_update_status idempotent"

if python3 "$UPDATE" "/tmp/nonexistent-note-xyz.md" done 2>/dev/null; then
  echo "FAIL: missing file should have exited non-zero"
  exit 1
fi
echo "PASS test_update_status missing-file"

cat > "$FIX_DIR/note-nostatus.md" <<'EOF'
---
project: test
---
body
EOF
if python3 "$UPDATE" "$FIX_DIR/note-nostatus.md" active 2>/dev/null; then
  echo "FAIL: missing status field should have exited non-zero"
  exit 1
fi
echo "PASS test_update_status missing-status-field"

rm -f "$FIX_DIR/note-update.md" "$FIX_DIR/note-nostatus.md"
echo "ALL PASSED: update_status"
