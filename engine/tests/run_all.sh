#!/bin/bash
# run_all.sh — execute every test_*.sh in this directory, in order.
# Exits non-zero on first failure.

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for t in "$DIR"/test_*.sh; do
  echo ""
  echo "=== Running: $(basename "$t") ==="
  bash "$t"
done

echo ""
echo "=== All engine tests passed ==="
