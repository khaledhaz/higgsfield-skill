#!/bin/bash
# extract_frames.sh — extract last frame of clipA and first frame of clipB.
# Usage: extract_frames.sh <clipA> <clipB> <out-dir>
# Outputs: <out-dir>/clipA-last.png and <out-dir>/clipB-first.png

set -e

if [ $# -ne 3 ]; then
  echo "Usage: $0 <clipA> <clipB> <out-dir>" >&2
  exit 2
fi

clipA="$1"
clipB="$2"
outdir="$3"

[ -f "$clipA" ] || { echo "Error: clipA not found: $clipA" >&2; exit 1; }
[ -f "$clipB" ] || { echo "Error: clipB not found: $clipB" >&2; exit 1; }

mkdir -p "$outdir"

# Last frame of A: seek 0.1s before end of file
ffmpeg -y -sseof -0.1 -i "$clipA" -vframes 1 -q:v 2 "$outdir/clipA-last.png" 2>/dev/null

# First frame of B
ffmpeg -y -i "$clipB" -vframes 1 -q:v 2 "$outdir/clipB-first.png" 2>/dev/null

[ -f "$outdir/clipA-last.png" ] || { echo "Error: failed to write clipA-last.png" >&2; exit 1; }
[ -f "$outdir/clipB-first.png" ] || { echo "Error: failed to write clipB-first.png" >&2; exit 1; }
