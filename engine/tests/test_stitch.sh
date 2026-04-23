#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STITCH="$SCRIPT_DIR/../stitch.sh"
FIX_DIR="$SCRIPT_DIR/fixtures"
TMP_DIR="$SCRIPT_DIR/tmp-stitch"

mkdir -p "$FIX_DIR"
rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"

# Generate 3 tiny test clips (2s each) + a silent audio
gen_clip() {
  local out="$1"; local hue="$2"
  if [ ! -f "$out" ]; then
    ffmpeg -y \
      -f lavfi -i "testsrc=size=320x180:rate=24:duration=2" \
      -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
      -shortest \
      -vf "hue=s=1:h=$hue" -c:v libx264 -pix_fmt yuv420p \
      -c:a aac -b:a 128k "$out" 2>/dev/null
  fi
}
gen_clip "$FIX_DIR/clip-red.mp4" 0
gen_clip "$FIX_DIR/clip-green.mp4" 120
gen_clip "$FIX_DIR/clip-blue.mp4" 240

# Generate a 6s silent audio file for VO overlay
if [ ! -f "$FIX_DIR/silent-6s.mp3" ]; then
  ffmpeg -y -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
    -t 6 -c:a libmp3lame -q:a 4 "$FIX_DIR/silent-6s.mp3" 2>/dev/null
fi

# Test 1: simple concat — three shots, no VO, all cuts
cat > "$TMP_DIR/manifest1.json" <<EOF
{
  "output": "$TMP_DIR/out1.mp4",
  "resolution": [1920, 1080],
  "fps": 24,
  "clips": [
    {"path": "$FIX_DIR/clip-red.mp4", "type": "shot"},
    {"path": null, "type": "cut"},
    {"path": "$FIX_DIR/clip-green.mp4", "type": "shot"},
    {"path": null, "type": "cut"},
    {"path": "$FIX_DIR/clip-blue.mp4", "type": "shot"}
  ],
  "cut_xfade": 0
}
EOF

"$STITCH" "$TMP_DIR/manifest1.json"

[ -f "$TMP_DIR/out1.mp4" ] || { echo "FAIL test_stitch concat: out1.mp4 missing"; exit 1; }
dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TMP_DIR/out1.mp4")
awk -v a="$dur" 'BEGIN { exit (a >= 5.8 && a <= 6.2) ? 0 : 1 }' || {
  echo "FAIL test_stitch concat: expected duration ~6s, got $dur"
  exit 1
}
echo "PASS test_stitch concat ($dur s)"

# Test 2: concat with VO overlay
cat > "$TMP_DIR/manifest2.json" <<EOF
{
  "output": "$TMP_DIR/out2.mp4",
  "resolution": [1920, 1080],
  "fps": 24,
  "clips": [
    {"path": "$FIX_DIR/clip-red.mp4", "type": "shot"},
    {"path": null, "type": "cut"},
    {"path": "$FIX_DIR/clip-green.mp4", "type": "shot"},
    {"path": null, "type": "cut"},
    {"path": "$FIX_DIR/clip-blue.mp4", "type": "shot"}
  ],
  "vo": {"path": "$FIX_DIR/silent-6s.mp3", "mode": "overlay"},
  "cut_xfade": 0
}
EOF

"$STITCH" "$TMP_DIR/manifest2.json"

[ -f "$TMP_DIR/out2.mp4" ] || { echo "FAIL test_stitch vo: out2.mp4 missing"; exit 1; }
# Verify there's an audio stream in the output
has_audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of default=nw=1:nk=1 "$TMP_DIR/out2.mp4" 2>/dev/null || true)
[ "$has_audio" = "audio" ] || { echo "FAIL test_stitch vo: no audio stream in output"; exit 1; }
echo "PASS test_stitch vo-overlay"

# Test 3: per-clip duration trimming (each source clip is 2s; trim to 1.3s so
# total ≈ 3 × 1.3 = 3.9s instead of 6s)
cat > "$TMP_DIR/manifest3.json" <<EOF
{
  "output": "$TMP_DIR/out3.mp4",
  "resolution": [1920, 1080],
  "fps": 24,
  "clips": [
    {"path": "$FIX_DIR/clip-red.mp4",   "type": "shot", "duration": 1.3},
    {"path": "$FIX_DIR/clip-green.mp4", "type": "shot", "duration": 1.3},
    {"path": "$FIX_DIR/clip-blue.mp4",  "type": "shot", "duration": 1.3}
  ],
  "cut_xfade": 0
}
EOF

"$STITCH" "$TMP_DIR/manifest3.json"

[ -f "$TMP_DIR/out3.mp4" ] || { echo "FAIL test_stitch trim: out3.mp4 missing"; exit 1; }
dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TMP_DIR/out3.mp4")
awk -v a="$dur" 'BEGIN { exit (a >= 3.7 && a <= 4.1) ? 0 : 1 }' || {
  echo "FAIL test_stitch trim: expected ~3.9s total (3 × 1.3), got $dur"
  exit 1
}
echo "PASS test_stitch per-clip-duration ($dur s)"

# Cleanup
rm -rf "$TMP_DIR"
echo "ALL PASSED: stitch"
