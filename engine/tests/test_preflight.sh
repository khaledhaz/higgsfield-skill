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
# Spawn a uniquely-named long-running process to simulate a live Chrome.
# Unique name guarantees pgrep -f matches ONLY this process.
TAG="hf-preflight-test-$$-$RANDOM"
# Use perl select() so we can embed the tag in argv without running an external loop
perl -e "\$0 = '$TAG'; select(undef, undef, undef, 300);" &
GUARD_PID=$!
# Give perl a moment to set $0
sleep 0.5 2>/dev/null || sleep 1

HF_CHROME_DIR="$TEST_DIR" HF_CHROME_PATTERN="$TAG" "$PREFLIGHT"

# Tear down the guard process silently — redirect job-control output to /dev/null
{ kill "$GUARD_PID" 2>/dev/null; wait "$GUARD_PID" 2>/dev/null; } >/dev/null 2>&1 || true

[ -f "$TEST_DIR/SingletonLock" ] || { echo "FAIL: active lock was incorrectly removed"; exit 1; }
echo "PASS test_preflight active-lock-preserved"

rm -rf "$TEST_DIR"
echo "ALL PASSED: preflight"
exit 0
