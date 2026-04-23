#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE="$SCRIPT_DIR/../update_region.py"
FIX_DIR="$SCRIPT_DIR/fixtures"

mkdir -p "$FIX_DIR"

# Case 1: existing region → replace content
cat > "$FIX_DIR/region-existing.md" <<'EOF'
# Note

Some text.

## Shots
<!-- engine:shots -->
OLD CONTENT
<!-- /engine:shots -->

## Footer
Trailing text.
EOF

echo "NEW CONTENT" | python3 "$UPDATE" "$FIX_DIR/region-existing.md" shots -
grep -q "NEW CONTENT" "$FIX_DIR/region-existing.md" || { echo "FAIL: new content not written"; exit 1; }
! grep -q "OLD CONTENT" "$FIX_DIR/region-existing.md" || { echo "FAIL: old content still present"; exit 1; }
grep -q "Trailing text." "$FIX_DIR/region-existing.md" || { echo "FAIL: footer clobbered"; exit 1; }
grep -q "<!-- engine:shots -->" "$FIX_DIR/region-existing.md" || { echo "FAIL: opening marker missing"; exit 1; }
grep -q "<!-- /engine:shots -->" "$FIX_DIR/region-existing.md" || { echo "FAIL: closing marker missing"; exit 1; }
echo "PASS test_update_region existing-replace"

# Case 2: region missing → append markers + content
cat > "$FIX_DIR/region-missing.md" <<'EOF'
# Note

Just a body, no markers.
EOF

echo "FRESH" | python3 "$UPDATE" "$FIX_DIR/region-missing.md" beats -
grep -q "<!-- engine:beats -->" "$FIX_DIR/region-missing.md" || { echo "FAIL: opening marker not appended"; exit 1; }
grep -q "FRESH" "$FIX_DIR/region-missing.md" || { echo "FAIL: content not appended"; exit 1; }
grep -q "<!-- /engine:beats -->" "$FIX_DIR/region-missing.md" || { echo "FAIL: closing marker not appended"; exit 1; }
echo "PASS test_update_region missing-append"

# Case 3: multiple regions → only target one modified
cat > "$FIX_DIR/region-multi.md" <<'EOF'
## Beats
<!-- engine:beats -->
BEATS CONTENT
<!-- /engine:beats -->

## Shots
<!-- engine:shots -->
SHOTS CONTENT
<!-- /engine:shots -->
EOF

echo "NEW SHOTS" | python3 "$UPDATE" "$FIX_DIR/region-multi.md" shots -
grep -q "BEATS CONTENT" "$FIX_DIR/region-multi.md" || { echo "FAIL: beats content clobbered"; exit 1; }
grep -q "NEW SHOTS" "$FIX_DIR/region-multi.md" || { echo "FAIL: new shots not written"; exit 1; }
! grep -q "SHOTS CONTENT" "$FIX_DIR/region-multi.md" || { echo "FAIL: old shots content still present"; exit 1; }
echo "PASS test_update_region multi-region-isolated"

# Case 4: malformed (only opening marker) → exit non-zero
cat > "$FIX_DIR/region-broken.md" <<'EOF'
# Note
<!-- engine:shots -->
no closer
EOF

if echo "X" | python3 "$UPDATE" "$FIX_DIR/region-broken.md" shots - 2>/dev/null; then
  echo "FAIL: broken region should have exited non-zero"
  exit 1
fi
echo "PASS test_update_region malformed-errors"

# Case 5: content from file argument (not stdin)
cat > "$FIX_DIR/region-filesrc.md" <<'EOF'
<!-- engine:shots -->
OLD
<!-- /engine:shots -->
EOF
echo "FILE CONTENT" > "$FIX_DIR/region-filesrc.content"
python3 "$UPDATE" "$FIX_DIR/region-filesrc.md" shots "$FIX_DIR/region-filesrc.content"
grep -q "FILE CONTENT" "$FIX_DIR/region-filesrc.md" || { echo "FAIL: file-source content not written"; exit 1; }
echo "PASS test_update_region file-source"

echo "ALL PASSED: update_region"
