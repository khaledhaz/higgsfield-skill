#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VA="$SCRIPT_DIR/../vo_analyze.py"
FIX_DIR="$SCRIPT_DIR/fixtures"
mkdir -p "$FIX_DIR"

# Fixture: a synthetic Whisper output + matching script
cat > "$FIX_DIR/whisper-ar.json" <<'EOF'
{
  "segments": [
    {
      "start": 0.0, "end": 5.2,
      "words": [
        {"word": "ارتفعت", "start": 0.10, "end": 0.50, "probability": 0.95},
        {"word": "أسعار", "start": 0.50, "end": 0.95, "probability": 0.97},
        {"word": "النفط", "start": 0.95, "end": 1.40, "probability": 0.98},
        {"word": "بأكثر", "start": 1.40, "end": 1.90, "probability": 0.92},
        {"word": "من", "start": 1.90, "end": 2.05, "probability": 0.99},
        {"word": "3", "start": 2.05, "end": 2.30, "probability": 0.90},
        {"word": "دولارات", "start": 2.30, "end": 3.00, "probability": 0.94},
        {"word": ".", "start": 3.00, "end": 3.05, "probability": 0.99}
      ]
    },
    {
      "start": 5.2, "end": 10.0,
      "words": [
        {"word": "ونواتج", "start": 5.30, "end": 5.80, "probability": 0.91},
        {"word": "التقطير", "start": 5.80, "end": 6.40, "probability": 0.93},
        {"word": "في", "start": 6.40, "end": 6.55, "probability": 0.99},
        {"word": "الولايات", "start": 6.55, "end": 7.20, "probability": 0.95},
        {"word": "المتحدة", "start": 7.20, "end": 7.80, "probability": 0.96},
        {"word": ".", "start": 7.80, "end": 7.85, "probability": 0.99}
      ]
    }
  ]
}
EOF

cat > "$FIX_DIR/script-ar.txt" <<'EOF'
ارتفعت أسعار النفط بأكثر من 3 دولارات. ونواتج التقطير في الولايات المتحدة.
EOF

OUTPUT=$(python3 - "$VA" "$FIX_DIR/whisper-ar.json" "$FIX_DIR/script-ar.txt" <<'PYEOF'
import sys, json, importlib.util
spec = importlib.util.spec_from_file_location("va", sys.argv[1])
va = importlib.util.module_from_spec(spec); spec.loader.exec_module(va)
whisper_data = json.load(open(sys.argv[2]))
script = open(sys.argv[3]).read()
beats = va.align(whisper_data["segments"], script)
print(json.dumps(beats, ensure_ascii=False))
PYEOF
)

echo "$OUTPUT" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert len(d)==2, f'got {len(d)} beats'" || { echo "FAIL: beat count"; exit 1; }
echo "PASS test_vo_analyze_align beat-count"

first_start=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['start'])")
first_end=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['end'])")
[ "$first_start" = "0.1" ] || { echo "FAIL: first_start=$first_start (expected 0.1)"; exit 1; }
awk -v v="$first_end" 'BEGIN{ if (v+0 >= 2.95 && v+0 <= 3.10) exit 0; exit 1 }' || { echo "FAIL: first_end=$first_end (expected ~3.0)"; exit 1; }
echo "PASS test_vo_analyze_align first-beat-timing"

second_claim=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[1]['claim_ar'])")
echo "$second_claim" | grep -q "التقطير" || { echo "FAIL: second beat claim_ar missing expected token: '$second_claim'"; exit 1; }
echo "PASS test_vo_analyze_align second-beat-claim-text"

# Case 4: more claims than Whisper words → every claim still gets a beat
# (3-claim script, single-word Whisper output — fallback covers the rest)
cat > "$FIX_DIR/whisper-short.json" <<'EOF'
{
  "segments": [
    { "start": 0.0, "end": 1.0,
      "words": [
        {"word": "ارتفعت", "start": 0.1, "end": 0.5, "probability": 0.9},
        {"word": ".", "start": 0.5, "end": 0.55, "probability": 0.99}
      ]
    }
  ]
}
EOF
cat > "$FIX_DIR/script-short.txt" <<'EOF'
ارتفعت أسعار النفط. زيادة في الطلب. مخاوف من النقص.
EOF
OUTPUT=$(python3 - "$VA" "$FIX_DIR/whisper-short.json" "$FIX_DIR/script-short.txt" <<'PYEOF'
import sys, json, importlib.util
spec = importlib.util.spec_from_file_location("va", sys.argv[1])
va = importlib.util.module_from_spec(spec); spec.loader.exec_module(va)
whisper_data = json.load(open(sys.argv[2]))
script = open(sys.argv[3]).read()
beats = va.align(whisper_data["segments"], script)
print(json.dumps(beats, ensure_ascii=False))
PYEOF
)
count=$(echo "$OUTPUT" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))")
[ "$count" = "3" ] || { echo "FAIL: expected 3 beats (one per claim), got $count"; exit 1; }
# Last beat must have sequential id (no gaps) and zero or small duration
last_id=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[-1]['id'])")
[ "$last_id" = "3" ] || { echo "FAIL: expected last id=3, got $last_id"; exit 1; }
echo "PASS test_vo_analyze_align more-claims-than-words"

echo "ALL PASSED: vo_analyze_align"
