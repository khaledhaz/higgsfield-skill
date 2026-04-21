#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/../probe_duration.sh"
FIXTURE="$SCRIPT_DIR/fixtures/tone-2.5s.mp3"

# Generate fixture on demand (idempotent)
mkdir -p "$(dirname "$FIXTURE")"
if [ ! -f "$FIXTURE" ]; then
  ffmpeg -y -f lavfi -i "sine=frequency=440:duration=2.5" -c:a libmp3lame -q:a 4 "$FIXTURE" 2>/dev/null
fi

# Test 1: returns duration close to 2.5
actual=$("$PROBE" "$FIXTURE")
awk_pass=$(awk -v a="$actual" 'BEGIN { exit (a >= 2.4 && a <= 2.6) ? 0 : 1 }') || {
  echo "FAIL test_probe_duration basic: expected ~2.5, got $actual"
  exit 1
}
echo "PASS test_probe_duration basic ($actual)"

# Test 2: missing file exits non-zero
if "$PROBE" "/tmp/nonexistent-file-xyz.mp3" 2>/dev/null; then
  echo "FAIL test_probe_duration missing-file: expected non-zero exit"
  exit 1
fi
echo "PASS test_probe_duration missing-file"

echo "ALL PASSED: probe_duration"
