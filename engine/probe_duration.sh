#!/bin/bash
# probe_duration.sh — emit media duration in seconds
# Usage: probe_duration.sh <path-to-audio-or-video>
# Exits non-zero if file missing or ffprobe fails.

set -e

if [ $# -ne 1 ]; then
  echo "Usage: $0 <media-file>" >&2
  exit 2
fi

file="$1"
if [ ! -f "$file" ]; then
  echo "Error: file not found: $file" >&2
  exit 1
fi

ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$file"
