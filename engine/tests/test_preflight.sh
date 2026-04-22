#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/../preflight.sh"
TEST_DIR="$SCRIPT_DIR/tmp-preflight"

rm -rf "$TEST_DIR" && mkdir -p "$TEST_DIR"

touch "$TEST_DIR/SingletonLock"

HF_CHROME_DIR="$TEST_DIR" HF_CHROME_PATTERN="nonexistent-process-abc123" "$PREFLIGHT"
[ ! -f "$TEST_DIR/SingletonLock" ] || { echo "FAIL: stale lock was not removed"; exit 1; }
echo "PASS test_preflight stale-lock-removed"

HF_CHROME_DIR="$TEST_DIR" HF_CHROME_PATTERN="nonexistent-process-abc123" "$PREFLIGHT"
echo "PASS test_preflight no-lock-noop"

touch "$TEST_DIR/SingletonLock"
# Use 'sleep' as an active process pattern (guaranteed to exist and cross-platform)
sleep 300 &
SLEEP_PID=$!
trap "kill $SLEEP_PID 2>/dev/null" EXIT
HF_CHROME_DIR="$TEST_DIR" HF_CHROME_PATTERN="sleep" "$PREFLIGHT"
kill $SLEEP_PID 2>/dev/null || true
[ -f "$TEST_DIR/SingletonLock" ] || { echo "FAIL: active lock was incorrectly removed"; exit 1; }
echo "PASS test_preflight active-lock-preserved"

rm -rf "$TEST_DIR"
echo "ALL PASSED: preflight"
