#!/bin/bash
# Slow integration test; skip if SKIP_SLOW=1 or if openai-whisper is not installed.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VA="$SCRIPT_DIR/../vo_analyze.py"
FIX_DIR="$SCRIPT_DIR/fixtures"

mkdir -p "$FIX_DIR"

if [ "$SKIP_SLOW" = "1" ]; then
  echo "SKIP test_vo_analyze_e2e (SKIP_SLOW=1)"
  exit 0
fi

python3 -c "import whisper" 2>/dev/null || {
  echo "SKIP test_vo_analyze_e2e (openai-whisper not installed)"
  exit 0
}

WAV="$FIX_DIR/vo-tiny.wav"
if [ ! -f "$WAV" ]; then
  ffmpeg -y -f lavfi -i "sine=frequency=440:duration=5" -f lavfi -i "anullsrc=duration=5" \
    -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" -c:a pcm_s16le "$WAV" >/dev/null 2>&1
fi

cat > "$FIX_DIR/vo-tiny-script.txt" <<'EOF'
Hello world. This is a test.
EOF

BEATS_OUT="$FIX_DIR/vo-tiny-beats.json"
rm -f "$BEATS_OUT"

HF_WHISPER_MODEL="tiny" python3 "$VA" "$WAV" "$FIX_DIR/vo-tiny-script.txt" "$BEATS_OUT"

[ -f "$BEATS_OUT" ] || { echo "FAIL: beats.json not written"; exit 1; }
python3 -c "import json; d=json.load(open('$BEATS_OUT')); assert isinstance(d, list), 'not a list'" \
  || { echo "FAIL: beats.json malformed"; exit 1; }
echo "PASS test_vo_analyze_e2e beats-json-valid"

echo "ALL PASSED: vo_analyze_e2e"
