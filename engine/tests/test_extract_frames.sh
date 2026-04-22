#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT="$SCRIPT_DIR/../extract_frames.sh"
FIX_DIR="$SCRIPT_DIR/fixtures"
OUT_DIR="$SCRIPT_DIR/tmp-extract"

mkdir -p "$FIX_DIR"

# Generate fixtures: two distinct 3-second test videos
# Clip A: red gradient, Clip B: blue gradient (so last-frame-A != first-frame-B)
if [ ! -f "$FIX_DIR/clipA.mp4" ]; then
  ffmpeg -y -f lavfi -i "testsrc=size=320x180:rate=24:duration=3" \
    -vf "hue=s=1:h=0" -c:v libx264 -pix_fmt yuv420p "$FIX_DIR/clipA.mp4" 2>/dev/null
fi
if [ ! -f "$FIX_DIR/clipB.mp4" ]; then
  ffmpeg -y -f lavfi -i "testsrc=size=320x180:rate=24:duration=3" \
    -vf "hue=s=1:h=120" -c:v libx264 -pix_fmt yuv420p "$FIX_DIR/clipB.mp4" 2>/dev/null
fi

rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"

"$EXTRACT" "$FIX_DIR/clipA.mp4" "$FIX_DIR/clipB.mp4" "$OUT_DIR"

[ -f "$OUT_DIR/clipA-last.png" ] || { echo "FAIL: clipA-last.png missing"; exit 1; }
[ -f "$OUT_DIR/clipB-first.png" ] || { echo "FAIL: clipB-first.png missing"; exit 1; }

# Size check — PNGs should be at least 1KB (not zero-byte)
size_a=$(stat -f%z "$OUT_DIR/clipA-last.png" 2>/dev/null || stat -c%s "$OUT_DIR/clipA-last.png")
size_b=$(stat -f%z "$OUT_DIR/clipB-first.png" 2>/dev/null || stat -c%s "$OUT_DIR/clipB-first.png")
[ "$size_a" -gt 1000 ] || { echo "FAIL: clipA-last.png too small ($size_a)"; exit 1; }
[ "$size_b" -gt 1000 ] || { echo "FAIL: clipB-first.png too small ($size_b)"; exit 1; }

echo "PASS extract_frames basic"

# Cleanup
rm -rf "$OUT_DIR"

echo "ALL PASSED: extract_frames"
