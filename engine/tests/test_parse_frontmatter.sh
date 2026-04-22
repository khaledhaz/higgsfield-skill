#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE="$SCRIPT_DIR/../parse_frontmatter.py"
FIX_DIR="$SCRIPT_DIR/fixtures"

mkdir -p "$FIX_DIR"

cat > "$FIX_DIR/note-basic.md" <<'EOF'
---
project: test-slug
status: inbox
aspect: 16:9
shots: []
---

## Script
Hello world.
EOF

actual=$(python3 "$PARSE" "$FIX_DIR/note-basic.md")

echo "$actual" | python3 -c "import json, sys; json.loads(sys.stdin.read())" || {
  echo "FAIL: output is not valid JSON: $actual"
  exit 1
}

project=$(echo "$actual" | python3 -c "import json, sys; print(json.loads(sys.stdin.read())['project'])")
status=$(echo "$actual" | python3 -c "import json, sys; print(json.loads(sys.stdin.read())['status'])")
[ "$project" = "test-slug" ] || { echo "FAIL: project=$project (expected test-slug)"; exit 1; }
[ "$status" = "inbox" ] || { echo "FAIL: status=$status (expected inbox)"; exit 1; }
echo "PASS test_parse_frontmatter basic"

cat > "$FIX_DIR/note-noframe.md" <<'EOF'
## Just a heading
No frontmatter.
EOF

if python3 "$PARSE" "$FIX_DIR/note-noframe.md" 2>/dev/null; then
  echo "FAIL: no-frontmatter note should have exited non-zero"
  exit 1
fi
echo "PASS test_parse_frontmatter no-frontmatter-errors"

if python3 "$PARSE" "/tmp/nonexistent-note-xyz.md" 2>/dev/null; then
  echo "FAIL: missing file should have exited non-zero"
  exit 1
fi
echo "PASS test_parse_frontmatter missing-file"

echo "ALL PASSED: parse_frontmatter"
