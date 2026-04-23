#!/bin/bash
# stitch.sh — concatenate clips per manifest, optionally overlay VO.
# Usage: stitch.sh <manifest.json>
# Prints output duration to stdout.
#
# Per-clip `duration` (seconds, float) in the manifest is honored: each clip
# is trimmed to that exact duration before concat. Omit the field to use the
# clip's natural length.

set -e

if [ $# -ne 1 ]; then
  echo "Usage: $0 <manifest.json>" >&2
  exit 2
fi

manifest="$1"
[ -f "$manifest" ] || { echo "Error: manifest not found: $manifest" >&2; exit 1; }
command -v jq >/dev/null || { echo "Error: jq is required" >&2; exit 1; }

# Parse manifest
output=$(jq -r .output "$manifest")
res_w=$(jq -r '.resolution[0]' "$manifest")
res_h=$(jq -r '.resolution[1]' "$manifest")
fps=$(jq -r .fps "$manifest")
vo_path=$(jq -r '.vo.path // empty' "$manifest")
cut_xfade=$(jq -r '.cut_xfade // 0' "$manifest")

# Build list of real (non-cut) clips as path|duration pairs using while-read
# (bash 3.2 compatible; mapfile/readarray requires bash 4+, which is not the
# macOS system default). Use "|" as separator; duration is empty string if
# the manifest omits the field.
clip_paths=()
clip_durations=()
while IFS= read -r line; do
  p="${line%%|*}"
  d="${line#*|}"
  [ "$d" = "$p" ] && d=""
  clip_paths+=("$p")
  clip_durations+=("$d")
done < <(jq -r '.clips[] | select(.type != "cut") | "\(.path)|\(.duration // "")"' "$manifest")

if [ "${#clip_paths[@]}" -eq 0 ]; then
  echo "Error: manifest has no clips" >&2
  exit 1
fi

# Normalize each clip to target resolution/fps (and trim to duration if set)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

normalized=()
for i in "${!clip_paths[@]}"; do
  clip="${clip_paths[$i]}"
  dur="${clip_durations[$i]}"
  [ -f "$clip" ] || { echo "Error: clip not found: $clip" >&2; exit 1; }
  norm="$tmpdir/norm-$i.mp4"
  trim_flag=""
  if [ -n "$dur" ] && [ "$dur" != "null" ]; then
    trim_flag="-t $dur"
  fi
  ffmpeg -y -i "$clip" $trim_flag \
    -vf "scale=${res_w}:${res_h}:force_original_aspect_ratio=decrease,pad=${res_w}:${res_h}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=${fps},format=yuv420p" \
    -c:v libx264 -crf 18 -preset medium \
    -c:a aac -b:a 192k -ar 48000 -ac 2 \
    "$norm" 2>/dev/null
  normalized+=("$norm")
done

# Concat via concat demuxer
concat_list="$tmpdir/concat.txt"
: > "$concat_list"
for f in "${normalized[@]}"; do
  printf "file '%s'\n" "$f" >> "$concat_list"
done

stitched="$tmpdir/stitched.mp4"
ffmpeg -y -f concat -safe 0 -i "$concat_list" -c copy "$stitched" 2>/dev/null

# Overlay VO if specified
if [ -n "$vo_path" ]; then
  [ -f "$vo_path" ] || { echo "Error: VO not found: $vo_path" >&2; exit 1; }
  ffmpeg -y -i "$stitched" -i "$vo_path" \
    -map 0:v -map 1:a \
    -c:v copy -c:a aac -b:a 192k -ar 48000 -ac 2 \
    -shortest \
    -movflags +faststart \
    "$output" 2>/dev/null
else
  cp "$stitched" "$output"
fi

# Emit final duration
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$output"
