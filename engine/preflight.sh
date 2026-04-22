#!/bin/bash
# preflight.sh — clean stale playwright-mcp SingletonLock.
# Safe to run at the start of every Mode A orchestration.
# Env vars (for testability):
#   HF_CHROME_DIR      — playwright user-data-dir (default: playwright-mcp cache)
#   HF_CHROME_PATTERN  — pgrep pattern to detect live Chrome (default: the chrome profile id)

set -e

DIR="${HF_CHROME_DIR:-$HOME/Library/Caches/ms-playwright/mcp-chrome-81eef6c}"
PATTERN="${HF_CHROME_PATTERN:-mcp-chrome-81eef6c}"
LOCK="$DIR/SingletonLock"

if [ ! -f "$LOCK" ]; then
  exit 0
fi

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
  exit 0
fi

rm -f "$LOCK" "$DIR/SingletonCookie" "$DIR/SingletonSocket"
