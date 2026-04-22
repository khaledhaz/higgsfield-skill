#!/bin/bash
# sweep.sh — Mode B scheduler sweep.
# Lists all notes with status:scheduled, parses schedule: field,
# emits the oldest-due slug to stdout. Exits 0 regardless.
#
# Env: HF_VAULT_DIR overrides the default vault path (for testing).

set -e

VAULT="${HF_VAULT_DIR:-$HOME/Obsidian/Higgsfield}"
PROJECTS="$VAULT/Projects"
ERRORS_LOG="$VAULT/_runs/sweep-errors.md"

[ -d "$PROJECTS" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$VAULT/_runs"

due_slug=""
due_epoch=""

shopt -s nullglob
for note in "$PROJECTS"/*.md; do
  json=$(python3 "$SCRIPT_DIR/parse_frontmatter.py" "$note" 2>/dev/null) || continue

  status=$(echo "$json" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('status',''))")
  [ "$status" = "scheduled" ] || continue

  schedule=$(echo "$json" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('schedule') or '')")
  if [ -z "$schedule" ] || [ "$schedule" = "None" ]; then
    continue
  fi

  slug=$(basename "$note" .md)

  set +e
  epoch=$(python3 - "$schedule" <<'PYEOF'
import sys, re, datetime as dt
s = sys.argv[1].strip()
now = dt.datetime.now()

try:
    d = dt.datetime.fromisoformat(s)
    print(int(d.timestamp()))
    sys.exit(0)
except ValueError:
    pass

m = re.match(r"every\s+(\d+)\s+(minute|minutes|hour|hours|day|days)$", s, re.I)
if m:
    n = int(m.group(1)); unit = m.group(2).lower()
    if unit.startswith("minute"): secs = n*60
    elif unit.startswith("hour"): secs = n*3600
    else: secs = n*86400
    print(int(now.timestamp()))
    sys.exit(0)

m = re.match(r"daily\s+at\s+(\d{1,2}):(\d{2})$", s, re.I)
if m:
    h, mi = int(m.group(1)), int(m.group(2))
    target = now.replace(hour=h, minute=mi, second=0, microsecond=0)
    if target <= now:
        print(int(target.timestamp()))
    else:
        print(int((target + dt.timedelta(days=1)).timestamp()))
    sys.exit(0)

sys.exit(1)
PYEOF
)
  py_exit=$?
  set -e

  if [ $py_exit -ne 0 ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $slug — unparseable schedule: \"$schedule\"" >> "$ERRORS_LOG"
    continue
  fi

  now_epoch=$(date +%s)
  if [ "$epoch" -gt "$now_epoch" ]; then
    continue
  fi

  if [ -z "$due_epoch" ] || [ "$epoch" -lt "$due_epoch" ]; then
    due_epoch="$epoch"
    due_slug="$slug"
  fi
done

[ -n "$due_slug" ] && echo "$due_slug"
exit 0
