#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PORT=$((RANDOM % 1000 + 19000))
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; [[ -n "${SRV_PID:-}" ]] && kill $SRV_PID 2>/dev/null || true' EXIT

python3 ./reference_server.py $PORT &
SRV_PID=$!
sleep 0.3

out1=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.png" "$TMP/c1")
[[ -f "$out1" ]] || { echo "FAIL: png not saved"; exit 1; }
[[ "$out1" == *.png ]] || { echo "FAIL: wrong extension ($out1)"; exit 1; }
[[ "$(stat -f%z "$out1" 2>/dev/null || stat -c%s "$out1")" -gt 50 ]] || { echo "FAIL: png too small"; exit 1; }

out2=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.jpg" "$TMP/c2")
[[ "$out2" == *.jpg ]] || { echo "FAIL: wrong extension for jpg ($out2)"; exit 1; }

if python3 ../reference_downloader.py "http://127.0.0.1:$PORT/missing" "$TMP/c3" 2>/dev/null; then
    echo "FAIL: 404 should have exit nonzero"; exit 1
fi

if python3 ../reference_downloader.py "http://127.0.0.1:$PORT/wrong_type" "$TMP/c4" 2>/dev/null; then
    echo "FAIL: wrong content-type should have exit nonzero"; exit 1
fi
[[ -z "$(ls "$TMP/c4" 2>/dev/null)" ]] || { echo "FAIL: wrote file despite wrong content-type"; exit 1; }

out5a=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.png" "$TMP/c5")
out5b=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.png" "$TMP/c5")
[[ "$out5a" == "$out5b" ]] || { echo "FAIL: nondeterministic path"; exit 1; }

echo "PASS: reference_downloader"
