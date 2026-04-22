# Runtime Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the runtime that makes the agentic higgsfield engine actually run — pre-flight lock cleanup, frontmatter I/O, Mode B cron sweep, and the Mode A orchestrator playbook inside SKILL.md.

**Architecture:** Four deterministic scripts (`preflight.sh`, `parse_frontmatter.py`, `update_status.py`, `sweep.sh`) plus three SKILL.md edits (new Orchestrator playbook section, Subagent dispatch patterns subsection, Pause/resume rewrite). Claude reads the playbook and executes it against the existing engine scripts.

**Tech Stack:** Bash (POSIX-compatible for macOS `/bin/bash` 3.2), Python 3 (PyYAML), git, Claude Code `Agent` and `CronCreate` tools, Playwright MCP.

**Spec:** `docs/2026-04-22-runtime-orchestrator-design.md`
**Parent spec:** `docs/2026-04-22-agentic-obsidian-engine-design.md`

**Working directory for all relative paths:** `~/.claude/skills/higgsfield/`

---

## Task 1: Implement `engine/preflight.sh`

**Files:**
- Create: `engine/preflight.sh`
- Create: `engine/tests/test_preflight.sh`

Cleans a stale playwright-mcp SingletonLock. The lock is stale if it exists AND no Chrome process owns the user-data-dir. Used as the first step of every Mode A run to avoid trap #20.

- [ ] **Step 1: Write the failing test at `engine/tests/test_preflight.sh`**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/../preflight.sh"
TEST_DIR="$SCRIPT_DIR/tmp-preflight"

rm -rf "$TEST_DIR" && mkdir -p "$TEST_DIR"

# Simulate a stale lock in an isolated test dir.
# The script accepts a directory path via env var for testability.
touch "$TEST_DIR/SingletonLock"

# Test 1: stale lock is removed when no process owns it
HF_CHROME_DIR="$TEST_DIR" HF_CHROME_PATTERN="nonexistent-process-abc123" "$PREFLIGHT"
[ ! -f "$TEST_DIR/SingletonLock" ] || { echo "FAIL: stale lock was not removed"; exit 1; }
echo "PASS test_preflight stale-lock-removed"

# Test 2: no lock → no-op, exits 0
HF_CHROME_DIR="$TEST_DIR" HF_CHROME_PATTERN="nonexistent-process-abc123" "$PREFLIGHT"
echo "PASS test_preflight no-lock-noop"

# Test 3: active lock (simulated by passing a pattern that matches current shell) is NOT removed
touch "$TEST_DIR/SingletonLock"
HF_CHROME_DIR="$TEST_DIR" HF_CHROME_PATTERN="bash" "$PREFLIGHT"
[ -f "$TEST_DIR/SingletonLock" ] || { echo "FAIL: active lock was incorrectly removed"; exit 1; }
echo "PASS test_preflight active-lock-preserved"

rm -rf "$TEST_DIR"
echo "ALL PASSED: preflight"
```

- [ ] **Step 2: Make the test executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_preflight.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_preflight.sh
```

Expected: fails with `preflight.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation at `engine/preflight.sh`**

```bash
#!/bin/bash
# preflight.sh — clean stale playwright-mcp SingletonLock.
# Safe to run at the start of every Mode A orchestration.
# Env vars (for testability):
#   HF_CHROME_DIR      — playwright user-data-dir (default: playwright-mcp cache)
#   HF_CHROME_PATTERN  — pgrep pattern to detect live Chrome (default: the chrome profile id)

set -e

DIR="${HF_CHROME_DIR:-$HOME/Library/Caches/ms-playwright/mcp-chrome-81eef6c}"
PATTERN="${HF_CHROME_PATTERN:-mcp-chrome-81eef6c}"
LOCK="$DIR/SingletonLock"

if [ ! -f "$LOCK" ]; then
  exit 0
fi

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
  # Chrome is alive; the lock belongs to it. Don't touch.
  exit 0
fi

# Lock present but no Chrome process → stale. Remove it.
rm -f "$LOCK" "$DIR/SingletonCookie" "$DIR/SingletonSocket"
```

- [ ] **Step 4: Make executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/preflight.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_preflight.sh
```

Expected: `ALL PASSED: preflight`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/preflight.sh engine/tests/test_preflight.sh
git commit -m "engine: add preflight.sh (stale SingletonLock cleanup) + test"
```

---

## Task 2: Implement `engine/parse_frontmatter.py`

**Files:**
- Create: `engine/parse_frontmatter.py`
- Create: `engine/tests/test_parse_frontmatter.sh`

Reads a markdown note with YAML frontmatter and emits the frontmatter as JSON on stdout. Used by `sweep.sh` and by the Mode A intake phase.

- [ ] **Step 1: Write the failing test at `engine/tests/test_parse_frontmatter.sh`**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE="$SCRIPT_DIR/../parse_frontmatter.py"
FIX_DIR="$SCRIPT_DIR/fixtures"

mkdir -p "$FIX_DIR"

# Fixture: a minimal note with frontmatter
cat > "$FIX_DIR/note-basic.md" <<'EOF'
---
project: test-slug
status: inbox
aspect: 16:9
shots: []
---

## Script
Hello world.
EOF

actual=$(python3 "$PARSE" "$FIX_DIR/note-basic.md")

# Verify valid JSON
echo "$actual" | python3 -c "import json, sys; json.loads(sys.stdin.read())" || {
  echo "FAIL: output is not valid JSON: $actual"
  exit 1
}

# Verify key fields
project=$(echo "$actual" | python3 -c "import json, sys; print(json.loads(sys.stdin.read())['project'])")
status=$(echo "$actual" | python3 -c "import json, sys; print(json.loads(sys.stdin.read())['status'])")
[ "$project" = "test-slug" ] || { echo "FAIL: project=$project (expected test-slug)"; exit 1; }
[ "$status" = "inbox" ] || { echo "FAIL: status=$status (expected inbox)"; exit 1; }
echo "PASS test_parse_frontmatter basic"

# Fixture: no frontmatter → error exit
cat > "$FIX_DIR/note-noframe.md" <<'EOF'
## Just a heading
No frontmatter.
EOF

if python3 "$PARSE" "$FIX_DIR/note-noframe.md" 2>/dev/null; then
  echo "FAIL: no-frontmatter note should have exited non-zero"
  exit 1
fi
echo "PASS test_parse_frontmatter no-frontmatter-errors"

# Fixture: missing file → error exit
if python3 "$PARSE" "/tmp/nonexistent-note-xyz.md" 2>/dev/null; then
  echo "FAIL: missing file should have exited non-zero"
  exit 1
fi
echo "PASS test_parse_frontmatter missing-file"

echo "ALL PASSED: parse_frontmatter"
```

- [ ] **Step 2: Make executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_parse_frontmatter.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_parse_frontmatter.sh
```

Expected: fails because `parse_frontmatter.py` doesn't exist.

- [ ] **Step 3: Write the implementation at `engine/parse_frontmatter.py`**

```python
#!/usr/bin/env python3
"""parse_frontmatter.py — read a markdown note's YAML frontmatter and print it as JSON.

Usage: parse_frontmatter.py <path-to-note>

Exits non-zero if:
- file missing
- no frontmatter block present
- frontmatter is not valid YAML
"""
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)


def parse(path: Path) -> dict:
    if not path.is_file():
        raise FileNotFoundError(f"note not found: {path}")

    text = path.read_text()

    if not text.startswith("---\n"):
        raise ValueError(f"no frontmatter block at start of {path}")

    # Split on the second "---" line
    parts = text.split("\n---\n", 1)
    if len(parts) < 2:
        raise ValueError(f"unterminated frontmatter block in {path}")

    front = parts[0][4:]  # strip leading "---\n"
    data = yaml.safe_load(front)
    if not isinstance(data, dict):
        raise ValueError(f"frontmatter is not a mapping in {path}")
    return data


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: parse_frontmatter.py <note-path>", file=sys.stderr)
        return 2
    try:
        data = parse(Path(sys.argv[1]))
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    print(json.dumps(data, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Make executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/parse_frontmatter.py
bash ~/.claude/skills/higgsfield/engine/tests/test_parse_frontmatter.sh
```

Expected: `ALL PASSED: parse_frontmatter`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/parse_frontmatter.py engine/tests/test_parse_frontmatter.sh
git commit -m "engine: add parse_frontmatter.py (YAML→JSON) + test"
```

---

## Task 3: Implement `engine/update_status.py`

**Files:**
- Create: `engine/update_status.py`
- Create: `engine/tests/test_update_status.sh`

Atomically rewrites the `status:` field in a note's frontmatter while preserving everything else (indentation, comments, body).

- [ ] **Step 1: Write the failing test at `engine/tests/test_update_status.sh`**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE="$SCRIPT_DIR/../update_status.py"
FIX_DIR="$SCRIPT_DIR/fixtures"

mkdir -p "$FIX_DIR"

# Test 1: basic status flip
cat > "$FIX_DIR/note-update.md" <<'EOF'
---
project: test-slug
status: inbox
aspect: 16:9
shots: []
---

## Script
Preserved body content.
EOF

python3 "$UPDATE" "$FIX_DIR/note-update.md" active

actual_status=$(grep "^status:" "$FIX_DIR/note-update.md" | awk '{print $2}')
[ "$actual_status" = "active" ] || { echo "FAIL: status not updated, got $actual_status"; exit 1; }

# Verify body preserved
grep -q "Preserved body content" "$FIX_DIR/note-update.md" || {
  echo "FAIL: body content was lost"
  exit 1
}

# Verify other frontmatter preserved
grep -q "^project: test-slug" "$FIX_DIR/note-update.md" || {
  echo "FAIL: project field was lost"
  exit 1
}
echo "PASS test_update_status basic"

# Test 2: idempotent (same status twice)
python3 "$UPDATE" "$FIX_DIR/note-update.md" active
actual_status=$(grep "^status:" "$FIX_DIR/note-update.md" | awk '{print $2}')
[ "$actual_status" = "active" ] || { echo "FAIL: idempotent update changed status"; exit 1; }
echo "PASS test_update_status idempotent"

# Test 3: missing file → error exit
if python3 "$UPDATE" "/tmp/nonexistent-note-xyz.md" done 2>/dev/null; then
  echo "FAIL: missing file should have exited non-zero"
  exit 1
fi
echo "PASS test_update_status missing-file"

# Test 4: note with no status field → error exit
cat > "$FIX_DIR/note-nostatus.md" <<'EOF'
---
project: test
---
body
EOF
if python3 "$UPDATE" "$FIX_DIR/note-nostatus.md" active 2>/dev/null; then
  echo "FAIL: missing status field should have exited non-zero"
  exit 1
fi
echo "PASS test_update_status missing-status-field"

rm -f "$FIX_DIR/note-update.md" "$FIX_DIR/note-nostatus.md"
echo "ALL PASSED: update_status"
```

- [ ] **Step 2: Make executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_update_status.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_update_status.sh
```

Expected: fails because `update_status.py` doesn't exist.

- [ ] **Step 3: Write the implementation at `engine/update_status.py`**

```python
#!/usr/bin/env python3
"""update_status.py — atomically rewrite the `status:` frontmatter field of a note.

Usage: update_status.py <note-path> <new-status>

Preserves everything else in the note verbatim (body, other frontmatter fields,
indentation, blank lines). Uses a line-by-line regex rather than YAML round-trip
because YAML round-trip would reformat the rest of the frontmatter.

Exits non-zero if:
- file missing
- no `status:` field in frontmatter
"""
import re
import sys
import tempfile
from pathlib import Path


STATUS_RE = re.compile(r"^(status\s*:\s*)(\S+.*)$")


def update(path: Path, new_status: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"note not found: {path}")

    text = path.read_text()
    lines = text.splitlines(keepends=True)

    # Find the frontmatter block: lines between the first two "---" lines
    in_frontmatter = False
    changed = False
    for i, line in enumerate(lines):
        stripped = line.rstrip("\n")
        if stripped == "---":
            if not in_frontmatter:
                in_frontmatter = True
                continue
            else:
                break  # end of frontmatter
        if in_frontmatter:
            m = STATUS_RE.match(stripped)
            if m:
                lines[i] = f"{m.group(1)}{new_status}\n"
                changed = True
                break

    if not changed:
        raise ValueError(f"no status: field in frontmatter of {path}")

    # Atomic write via tempfile in the same directory
    tmp_fd, tmp_path = tempfile.mkstemp(dir=path.parent, prefix=".update_status_", suffix=".tmp")
    try:
        with open(tmp_fd, "w") as f:
            f.writelines(lines)
        Path(tmp_path).replace(path)
    except Exception:
        Path(tmp_path).unlink(missing_ok=True)
        raise


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: update_status.py <note-path> <new-status>", file=sys.stderr)
        return 2
    try:
        update(Path(sys.argv[1]), sys.argv[2])
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Make executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/update_status.py
bash ~/.claude/skills/higgsfield/engine/tests/test_update_status.sh
```

Expected: `ALL PASSED: update_status`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/update_status.py engine/tests/test_update_status.sh
git commit -m "engine: add update_status.py (atomic status rewrite) + test"
```

---

## Task 4: Implement `engine/sweep.sh`

**Files:**
- Create: `engine/sweep.sh`
- Create: `engine/tests/test_sweep.sh`

Mode B scheduler sweep: lists `status: scheduled` projects, parses their `schedule:` field to compute next-run time, emits the oldest-due slug to stdout. Exits 0 with no output if nothing is due.

- [ ] **Step 1: Write the failing test at `engine/tests/test_sweep.sh`**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="$SCRIPT_DIR/../sweep.sh"
TEST_VAULT="$SCRIPT_DIR/tmp-vault-sweep"

rm -rf "$TEST_VAULT"
mkdir -p "$TEST_VAULT/Projects" "$TEST_VAULT/_runs"

# Fixture 1: scheduled project due NOW (past time)
cat > "$TEST_VAULT/Projects/due-now.md" <<'EOF'
---
project: due-now
status: scheduled
schedule: "2020-01-01T00:00:00"
---
EOF

# Fixture 2: scheduled project due in the future
cat > "$TEST_VAULT/Projects/due-future.md" <<'EOF'
---
project: due-future
status: scheduled
schedule: "2099-12-31T23:59:59"
---
EOF

# Fixture 3: not scheduled (should be ignored)
cat > "$TEST_VAULT/Projects/inbox-only.md" <<'EOF'
---
project: inbox-only
status: inbox
---
EOF

# Fixture 4: done (ignored)
cat > "$TEST_VAULT/Projects/already-done.md" <<'EOF'
---
project: already-done
status: done
---
EOF

# Test 1: emits the due slug
actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ "$actual" = "due-now" ] || { echo "FAIL: expected 'due-now', got '$actual'"; exit 1; }
echo "PASS test_sweep emits-due-slug"

# Test 2: remove the due project; now only future-dated exists → no output
rm "$TEST_VAULT/Projects/due-now.md"
actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ -z "$actual" ] || { echo "FAIL: expected empty output, got '$actual'"; exit 1; }
echo "PASS test_sweep no-due-empty"

# Test 3: unparseable schedule → logs error to _runs/sweep-errors.md, skips project
cat > "$TEST_VAULT/Projects/broken-schedule.md" <<'EOF'
---
project: broken-schedule
status: scheduled
schedule: "not a real date"
---
EOF
actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ -z "$actual" ] || { echo "FAIL: broken-schedule should not be emitted, got '$actual'"; exit 1; }
[ -f "$TEST_VAULT/_runs/sweep-errors.md" ] || {
  echo "FAIL: sweep-errors.md was not created for unparseable schedule"
  exit 1
}
grep -q "broken-schedule" "$TEST_VAULT/_runs/sweep-errors.md" || {
  echo "FAIL: sweep-errors.md does not mention broken-schedule"
  exit 1
}
echo "PASS test_sweep unparseable-logs-error"

# Test 4: empty vault (no Projects/*.md) → no output, no error
rm -rf "$TEST_VAULT/Projects"
mkdir -p "$TEST_VAULT/Projects"
actual=$(HF_VAULT_DIR="$TEST_VAULT" "$SWEEP")
[ -z "$actual" ] || { echo "FAIL: empty vault should give empty output"; exit 1; }
echo "PASS test_sweep empty-vault"

rm -rf "$TEST_VAULT"
echo "ALL PASSED: sweep"
```

- [ ] **Step 2: Make executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_sweep.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_sweep.sh
```

Expected: fails because `sweep.sh` doesn't exist.

- [ ] **Step 3: Write the implementation at `engine/sweep.sh`**

```bash
#!/bin/bash
# sweep.sh — Mode B scheduler sweep.
# Lists all notes with status:scheduled, parses schedule: field,
# emits the oldest-due slug to stdout. Exits 0 regardless of whether anything was emitted.
#
# Env: HF_VAULT_DIR overrides the default vault path (for testing).

set -e

VAULT="${HF_VAULT_DIR:-$HOME/Obsidian/Higgsfield}"
PROJECTS="$VAULT/Projects"
ERRORS_LOG="$VAULT/_runs/sweep-errors.md"

[ -d "$PROJECTS" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$VAULT/_runs"

# Collect (next_run_epoch, slug) pairs for scheduled projects whose schedule is in the past.
# Emit oldest.
due_slug=""
due_epoch=""

shopt -s nullglob
for note in "$PROJECTS"/*.md; do
  # Parse frontmatter via parse_frontmatter.py
  json=$(python3 "$SCRIPT_DIR/parse_frontmatter.py" "$note" 2>/dev/null) || continue

  status=$(echo "$json" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('status',''))")
  [ "$status" = "scheduled" ] || continue

  schedule=$(echo "$json" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('schedule') or '')")
  if [ -z "$schedule" ] || [ "$schedule" = "None" ]; then
    continue
  fi

  slug=$(basename "$note" .md)

  # Parse schedule into epoch seconds via Python. Supports:
  #  - ISO 8601 one-shot: "2026-04-25T14:00"
  #  - "every N minutes|hours|days"
  #  - "daily at HH:MM"
  epoch=$(python3 - "$schedule" <<'PYEOF'
import sys, re, datetime as dt
s = sys.argv[1].strip()
now = dt.datetime.now()

# ISO 8601 (one-shot or full)
try:
    d = dt.datetime.fromisoformat(s)
    print(int(d.timestamp()))
    sys.exit(0)
except ValueError:
    pass

# "every N (minutes|hours|days)"
m = re.match(r"every\s+(\d+)\s+(minute|minutes|hour|hours|day|days)$", s, re.I)
if m:
    n = int(m.group(1)); unit = m.group(2).lower()
    if unit.startswith("minute"): secs = n*60
    elif unit.startswith("hour"): secs = n*3600
    else: secs = n*86400
    # "due" means recurring: treat as due now (the cron cadence already throttles)
    print(int(now.timestamp()))
    sys.exit(0)

# "daily at HH:MM"
m = re.match(r"daily\s+at\s+(\d{1,2}):(\d{2})$", s, re.I)
if m:
    h, mi = int(m.group(1)), int(m.group(2))
    target = now.replace(hour=h, minute=mi, second=0, microsecond=0)
    # Due if target is in the past today
    if target <= now:
        print(int(target.timestamp()))
    else:
        print(int((target + dt.timedelta(days=1)).timestamp()))
    sys.exit(0)

# Unparseable
sys.exit(1)
PYEOF
) || {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $slug — unparseable schedule: \"$schedule\"" >> "$ERRORS_LOG"
    continue
  }

  # Skip if not yet due (epoch > now)
  now_epoch=$(date +%s)
  if [ "$epoch" -gt "$now_epoch" ]; then
    continue
  fi

  # Track oldest due
  if [ -z "$due_epoch" ] || [ "$epoch" -lt "$due_epoch" ]; then
    due_epoch="$epoch"
    due_slug="$slug"
  fi
done

[ -n "$due_slug" ] && echo "$due_slug"
exit 0
```

- [ ] **Step 4: Make executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/sweep.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_sweep.sh
```

Expected: `ALL PASSED: sweep`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/sweep.sh engine/tests/test_sweep.sh
git commit -m "engine: add sweep.sh (Mode B scheduler sweep) + test"
```

---

## Task 5: Verify full engine test suite still passes

**Files:**
- No file changes. This is a regression-check pass.

- [ ] **Step 1: Run the full engine test suite**

```bash
bash ~/.claude/skills/higgsfield/engine/tests/run_all.sh
```

Expected: every `test_*.sh` passes (probe_duration, extract_frames, stitch, init_vault, preflight, parse_frontmatter, update_status, sweep — 8 test files), ending with `=== All engine tests passed ===`.

If any test fails, fix the underlying script (not the test) and re-run.

No commit; verification only.

---

## Task 6: Add "Orchestrator playbook" section to `SKILL.md`

**Files:**
- Modify: `SKILL.md`

Insert a new top-level section `## Orchestrator playbook (Mode A runtime)` immediately after the existing `## Engine mode` section and before `## Self-learning rules`.

- [ ] **Step 1: Confirm insertion point**

```bash
grep -n "^## " ~/.claude/skills/higgsfield/SKILL.md | head -6
```

Expected: order is `Before any task`, `Engine mode`, `Self-learning rules`, `Current model availability`. The new section goes between `Engine mode` and `Self-learning rules`.

- [ ] **Step 2: Use the Edit tool to insert the new section**

Between the end of the `## Engine mode` section and the `## Self-learning rules` heading, insert this markdown block. One blank line above the new `## ` heading, one blank line after the section before the next `## `.

```markdown
## Orchestrator playbook (Mode A runtime)

This is the concrete procedure Claude executes when told "run <slug>" (or when a scheduler sweep emits a slug). Follow these steps in order. Each step is one action.

### Pre-flight
1. `bash ~/.claude/skills/higgsfield/engine/preflight.sh` — cleans stale SingletonLock (trap #20).
2. `cd ~/.claude/skills/higgsfield && git log --oneline -20` — include recently-learned auto-edits in your working context.

### Phase 0 — Intake
1. Resolve slug: `NOTE=~/Obsidian/Higgsfield/Projects/<slug>.md`.
2. Parse frontmatter: `python3 ~/.claude/skills/higgsfield/engine/parse_frontmatter.py "$NOTE"`.
3. Branch on `status`:
   - `inbox` → proceed.
   - `active` → crash detected. Read execution log; find the last line with `[x]`; resume from the first non-done phase. If no `[x]` lines exist, start from Phase 0.
   - `paused` → read `## Questions` section; if a `### A:` answer follows the last `### Q:`, proceed (treat the answer as current-turn input). Otherwise exit with a message.
   - `done` / `failed` → refuse (explain how to restart).
   - `scheduled` → refuse (wait for cron).
4. Flip status: `python3 ~/.claude/skills/higgsfield/engine/update_status.py "$NOTE" active`.
5. Create output dir: `mkdir -p ~/Higgsfield-out/<slug>`.
6. Append to log: `[x] <ISO-timestamp> Phase 0 intake: status=active, output=<dir>`.

### Phase 1 — VO (skip if `vo` is null)
1. `browser_navigate` to `/audio`.
2. Set Voiceover use-case, model = `vo.model` (default `eleven-v3`), voice = `vo.voice`, paste `vo.script`.
3. Read waveform `mm:ss` estimate from DOM (pre-gen).
4. Click Generate.
5. Wait until audio is ready; extract MP3 CDN URL.
6. `curl -sL -o ~/Higgsfield-out/<slug>/vo.mp3 <url>`.
7. `ACTUAL=$(bash ~/.claude/skills/higgsfield/engine/probe_duration.sh ~/Higgsfield-out/<slug>/vo.mp3)`.
8. If `|actual - estimate| > 0.5`, log the drift.
9. Append to log: `[x] Phase 1 VO ✅ · <model>/<voice> · <actual>s · <cost>cr`.

### Phase 2 — Plan
1. If `shots:` frontmatter is non-empty → skip (respect pre-populated plan).
2. Otherwise, plan N shots to fit the VO duration (default 5s shots) + M transitions per `transitions.mode`.
3. If shot-count ambiguity detected:
   - Append `### Q: <question>` under `## Questions`.
   - `python3 ... update_status.py "$NOTE" paused`.
   - Append to log and exit with a message.
4. Write the plan back into `shots:` frontmatter (edit the note file).
5. Append to log: `[x] Phase 2 plan: N shots + M transitions, total Ns`.

### Phase 3 — Images (parallel)
1. Worker count = `min(len(shots), 6)`.
2. For each shot, in turn (sequential driver):
   - `browser_tabs action=new` → tab on `/ai/image?model=nano-banana-pro`.
   - Via `browser_evaluate`: clear leftover state, set aspect=frontmatter `aspect`, resolution=`2K`, batch=1, **verify Unlimited toggle ON** (trap #22).
   - Type shot prompt.
   - Click Generate; verify new history row appeared.
3. Wait for all N jobs to complete (poll history rows for CDN URLs).
4. Fan out downloads using parallel `Agent` subagents (up to 6 in one message) — see "Subagent dispatch patterns" below.
5. Fan out vision QC using parallel `Agent` subagents (one per shot).
6. On QC FAIL → retry up to 3 attempts per shot (tighten prompt → re-submit → re-QC).
7. Log per shot: `[x] Phase 3 shot <n> image ✅ (attempt <k>) · ...`.

### Phase 4 — Videos (parallel, Kling 3.0)
Same shape as Phase 3, but:
- Tabs on Kling 3.0 video composer.
- Upload each shot's PNG to Start frame.
- Set duration per shot via the hidden `<input type="range">` helper (trap #21).
- Type motion prompt.
- Generate → download → QC-loop (vision-check first/mid/last frame against source image + implied motion).

### Phase 5 — Transitions (parallel, only if `transitions.seamless_pairs`)
1. For each pair `(A, B)`, fan out frame extraction: `Agent` → `bash .../extract_frames.sh shotA.mp4 shotB.mp4 /tmp/t-<i>/`.
2. For each extracted pair, dispatch a Kling 3.0 Start+End-frame job (duration 3s, Hollywood pattern from W11).
3. Download + QC each transition.

### Phase 6 — Stitch
1. Build `manifest.json` in-context (Claude writes JSON). Schema from parent spec §12 App D.
2. `bash ~/.claude/skills/higgsfield/engine/stitch.sh ~/Higgsfield-out/<slug>/manifest.json`.
3. Verify final MP4 exists and duration is within tolerance of planned total.
4. Log: `[x] Phase 6 stitch ✅ · final <s>s · <MB>`.

### Phase 7 — Finalize
1. Any `[!]` in log → `partial`; otherwise → `done`. `python3 ... update_status.py "$NOTE" <final>`.
2. Fill `## Outputs` section with wiki-links to shot PNGs, shot MP4s, transitions, final MP4.
3. Archive verbose run log: `cp $NOTE ~/Obsidian/Higgsfield/_runs/<slug>-<timestamp>.md`.
4. If any auto-edits landed during the run, append commit hashes + summaries to `## Auto-edits made during this run`.
5. `browser_close` — free Chrome.
6. Print completion summary.

### Subagent dispatch patterns

Use parallel `Agent` subagents for LOCAL work only (they cannot safely share the browser). Cap fan-out at 6 per batch. Prefer model=`haiku` for mechanical work.

**Batch download** (after all N video CDN URLs are known):
```
Agent(description="Download shots 1-3", model="haiku",
      subagent_type="general-purpose",
      prompt="Run: curl -sL <url1> -o shot1.mp4; curl -sL <url2> -o shot2.mp4; curl -sL <url3> -o shot3.mp4. Report downloaded filenames + sizes.")
Agent(description="Download shots 4-6", model="haiku", ...)
```
Two dispatches in one message → parallel.

**Vision QC fan-out** (after all downloads):
```
Agent(description="QC shot 1", model="haiku",
      subagent_type="general-purpose",
      prompt="Read ~/Higgsfield-out/<slug>/shot1.png. Prompt was: <prompt>. Check ≥4 of these elements are visible: <top-5 head-nouns + color-grade cues>. Report {status: PASS|FAIL, missing: [...], suggested_retry_prompt: <text if FAIL>}.")
# ... one per shot, up to 6 parallel
```

**Frame extraction fan-out** (Phase 5 prep):
```
Agent(description="Extract frames for transitions 1-2", model="haiku",
      subagent_type="general-purpose",
      prompt="Run: bash ~/.claude/skills/higgsfield/engine/extract_frames.sh shot1.mp4 shot2.mp4 /tmp/t1/; bash ... shot2.mp4 shot3.mp4 /tmp/t2/. Report OK/ERR per extraction.")
```

### Browser lifecycle
- Pre-flight `preflight.sh` at run start.
- Keep browser alive across phases of the same project.
- `browser_close` at the end of every project (done, partial, failed, or paused).

### Pause / resume (exit-cleanly semantics)
- When a phase detects spec ambiguity → write `### Q:` block → `update_status.py paused` → `browser_close` → print a clear instruction ("Pause on <reason>. Answer with `### A:` in the Questions section of `<note>`, then re-invoke 'run <slug>'") → exit the current orchestration.
- The session does NOT poll the note for an answer. User re-invokes when ready.
- Mode D cron sweeps skip paused projects until their `### A:` has been added AND status has been manually flipped back to `scheduled` (user's deliberate action — the cron does not auto-resume paused projects).
```

- [ ] **Step 3: Verify section ordering**

```bash
grep -n "^## " ~/.claude/skills/higgsfield/SKILL.md | head -6
```

Expected order (line numbers may differ):
1. `Before any task — ASK, never predict`
2. `Engine mode (agentic execution via Obsidian project notes)`
3. `Orchestrator playbook (Mode A runtime)`  ← NEW
4. `Self-learning rules (skill auto-edit)`
5. `Current model availability (this session)`
6. (rest)

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add SKILL.md
git commit -m "skill: add 'Orchestrator playbook' section (Mode A runtime procedure)"
```

---

## Task 7: Update "Engine mode" section's Pause/resume subsection

**Files:**
- Modify: `SKILL.md`

The existing `### Pause / resume via the note` subsection inside `## Engine mode` describes polling. Replace it with the exit-cleanly semantics from the spec.

- [ ] **Step 1: Find the exact current text**

```bash
grep -n "Pause / resume via the note" ~/.claude/skills/higgsfield/SKILL.md
```

Expected: a `### Pause / resume via the note` subsection exists somewhere inside the "Engine mode" section.

- [ ] **Step 2: Replace the subsection body**

Use the Edit tool to replace the existing subsection content with this exact text:

**Old text** (will be replaced — the current version says polling):
```markdown
### Pause / resume via the note
- Pause: append `### Q: <question>` under `## Questions`, set `status: paused`, stop.
- Resume: user adds `### A: <answer>` below the Q. In Mode A/C, the engine polls the note's mtime every 30s while paused (up to 30 minutes). In Mode D, the next cron sweep picks up any `A:`-populated Paused projects.
```

**New text**:
```markdown
### Pause / resume via the note (exit-cleanly)
- **Pause**: append `### Q: <question>` under `## Questions`, set `status: paused`, `browser_close`, print a clear instruction to the user, exit the current orchestration. Do NOT poll.
- **Resume**: user adds `### A: <answer>` below the most recent `### Q:`, optionally edits other parts of the note, then re-invokes `run <slug>`. Intake detects `status: paused` + presence of `### A:`, clears back to `active`, continues from the point of pause.
- **Mode D cron**: does NOT auto-resume paused projects. User must flip `status: scheduled` (or `inbox`) manually after answering. This is intentional — avoids re-running projects whose question wasn't actually answered.
```

- [ ] **Step 3: Verify the replacement**

```bash
grep -A 4 "Pause / resume" ~/.claude/skills/higgsfield/SKILL.md
```

Expected: output shows "exit-cleanly" in the heading and the new bullets.

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add SKILL.md
git commit -m "skill: rewrite Pause/resume to exit-cleanly semantics"
```

---

## Task 8: Flesh out Mode D cron setup language in SKILL.md

**Files:**
- Modify: `SKILL.md`

The existing "Mode dispatch" subsection mentions Mode D conceptually but doesn't specify the `CronCreate` call. Add concrete setup instructions inside the "Engine mode" section's Mode dispatch subsection.

- [ ] **Step 1: Find the Mode dispatch subsection**

```bash
grep -n "### Mode dispatch" ~/.claude/skills/higgsfield/SKILL.md
```

- [ ] **Step 2: Add a new subsection right after Mode dispatch**

Use the Edit tool to insert this markdown block immediately after the `### Mode dispatch` bullet list (and before the next `### ` subsection):

```markdown
### Setting up Mode D (one-time)
When the user says "Set up the Higgsfield scheduler" (or similar), invoke:

```
CronCreate(
  schedule: "*/15 * * * *",
  prompt: "higgsfield scheduler sweep"
)
```

When that cron fires, Claude Code runs the "scheduler sweep" procedure:
1. `bash ~/.claude/skills/higgsfield/engine/preflight.sh`
2. `DUE=$(bash ~/.claude/skills/higgsfield/engine/sweep.sh)`
3. If `$DUE` is empty → exit.
4. If `$DUE` is a slug → run the Orchestrator playbook (Mode A) on that slug.

The user can manage the cron via `CronList` / `CronDelete` (builtin tools).
```

- [ ] **Step 3: Verify**

```bash
grep -A 15 "Setting up Mode D" ~/.claude/skills/higgsfield/SKILL.md
```

Expected: the new subsection appears with the `CronCreate` block and the sweep procedure.

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add SKILL.md
git commit -m "skill: document Mode D cron setup with CronCreate invocation"
```

---

## Task 9: Smoke test — rerun `smoke-test` via the orchestrator playbook

**Files:**
- Modify: `~/Obsidian/Higgsfield/Projects/smoke-test.md` (reset + rerun)

Validate that the playbook in SKILL.md is actually executable end-to-end using the new scripts.

- [ ] **Step 1: Reset the existing smoke-test note to inbox**

```bash
python3 ~/.claude/skills/higgsfield/engine/update_status.py \
  ~/Obsidian/Higgsfield/Projects/smoke-test.md inbox

# Clear the execution log (between engine:begin and engine:end) for a clean re-run.
# Keep the rest of the note intact.
python3 - <<'PYEOF'
from pathlib import Path
p = Path.home() / "Obsidian/Higgsfield/Projects/smoke-test.md"
text = p.read_text()
import re
text = re.sub(r"<!-- engine:begin -->.*?<!-- engine:end -->", "<!-- engine:begin -->\n<!-- engine:end -->", text, count=1, flags=re.DOTALL)
p.write_text(text)
PYEOF

# Also clear the old outputs so we can verify they're recreated
rm -rf ~/Higgsfield-out/smoke-test
```

- [ ] **Step 2: Invoke the orchestrator playbook**

In a fresh chat turn, tell Claude: **"Run smoke-test using the Orchestrator playbook"**.

Claude should follow the pre-flight → Phase 0 → Phase 3 → Phase 4 → (skip 5) → Phase 6 → Phase 7 sequence from SKILL.md, using the new scripts:
- `preflight.sh` at start
- `parse_frontmatter.py` on intake
- `update_status.py` for status transitions
- `probe_duration.sh`, `extract_frames.sh`, `stitch.sh` as in the original run

Expected credits: ~8.75 credits (image at 2K unlimited = 0, video at Kling 3.0 5s = 8.75).
Expected wall time: 6–10 minutes.

- [ ] **Step 3: Verify outputs**

```bash
# Note status + body sanity
python3 ~/.claude/skills/higgsfield/engine/parse_frontmatter.py \
  ~/Obsidian/Higgsfield/Projects/smoke-test.md

# File existence
ls -la ~/Higgsfield-out/smoke-test/
bash ~/.claude/skills/higgsfield/engine/probe_duration.sh \
  ~/Higgsfield-out/smoke-test/final.mp4
```

Expected:
- frontmatter shows `status: done`
- `~/Higgsfield-out/smoke-test/` has `shot1.png`, `shot1.mp4`, `manifest.json`, `final.mp4`
- `final.mp4` duration is ~5.0 seconds

- [ ] **Step 4: No commit** — this is a runtime smoke test; any auto-edits get their own commits automatically.

---

## Task 10: Mode B smoke test — schedule a project and wait for sweep

**Files:**
- Create: `~/Obsidian/Higgsfield/Projects/cron-smoke.md`

Validate that Mode B cron picks up a scheduled project on the next fire. Requires waiting up to 15 minutes.

- [ ] **Step 1: Create a scheduled project with a past `schedule:`**

```bash
cat > ~/Obsidian/Higgsfield/Projects/cron-smoke.md <<'EOF'
---
project: cron-smoke
status: scheduled
aspect: 16:9
duration: 5s
style_reference: null
vo: null
transitions:
  mode: all-cuts
  seamless_pairs: []
retries_per_shot: 3
schedule: "2020-01-01T00:00:00"
shots:
  - n: 1
    beat: "A still silent mountain landscape at dawn"
    prompt: "Wide cinematic shot of a silent mountain valley at first dawn light, low mist in the valley floor, pale blue sky above"
    image_model: nano-banana-pro
    video_model: kling-3.0
    duration: 5
---

## Script
N/A — Mode B smoke test.

## Style notes
Peaceful, quiet. Validating the scheduler picks this up.

## Execution log
<!-- engine:begin -->
<!-- engine:end -->

## Questions

## Outputs

## Auto-edits made during this run
EOF
```

- [ ] **Step 2: Set up the cron (if not already set up)**

Tell Claude: **"Set up the Higgsfield scheduler"**.

Claude should invoke `CronCreate(schedule: "*/15 * * * *", prompt: "higgsfield scheduler sweep")`.

Verify with `CronList`.

- [ ] **Step 3: Verify `sweep.sh` identifies the due project**

```bash
bash ~/.claude/skills/higgsfield/engine/sweep.sh
```

Expected output: `cron-smoke` (emitted to stdout).

- [ ] **Step 4: Wait up to 15 minutes for the next cron fire**

The cron fires Claude with prompt "higgsfield scheduler sweep". When it fires, Claude should:
1. Run `preflight.sh`
2. Run `sweep.sh`, get `cron-smoke`
3. Dispatch the Orchestrator playbook on `cron-smoke`
4. Complete the project → `status: done`

Monitor:
```bash
# Poll the note's status until it changes
while true; do
  STATUS=$(python3 ~/.claude/skills/higgsfield/engine/parse_frontmatter.py \
    ~/Obsidian/Higgsfield/Projects/cron-smoke.md | \
    python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('status',''))")
  echo "$(date +%H:%M:%S) status=$STATUS"
  [ "$STATUS" = "done" ] || [ "$STATUS" = "failed" ] && break
  sleep 30
done
```

- [ ] **Step 5: Verify outputs**

```bash
ls -la ~/Higgsfield-out/cron-smoke/
python3 ~/.claude/skills/higgsfield/engine/parse_frontmatter.py \
  ~/Obsidian/Higgsfield/Projects/cron-smoke.md
```

Expected: `status: done` in the note; final MP4 exists.

- [ ] **Step 6: Optionally tear down the cron**

If you don't want to keep the scheduler running, tell Claude: **"Remove the Higgsfield scheduler"** — Claude invokes `CronDelete` on the trigger.

- [ ] **Step 7: No commit** — this is an end-to-end live test.

---

## Task 11: Crash-resume test

**Files:**
- Modify: `~/Obsidian/Higgsfield/Projects/crash-test.md`

Simulate a crash mid-run and verify the orchestrator resumes from the execution log.

- [ ] **Step 1: Create a 2-shot project**

```bash
cat > ~/Obsidian/Higgsfield/Projects/crash-test.md <<'EOF'
---
project: crash-test
status: inbox
aspect: 16:9
duration: 10s
style_reference: null
vo: null
transitions:
  mode: all-cuts
  seamless_pairs: []
retries_per_shot: 3
schedule: null
shots:
  - n: 1
    beat: "Shot A"
    prompt: "Wide cinematic shot of a silent pine forest with morning mist, cool blue-green palette"
    image_model: nano-banana-pro
    video_model: kling-3.0
    duration: 5
  - n: 2
    beat: "Shot B"
    prompt: "Wide cinematic shot of a still mountain lake at golden hour, warm amber palette"
    image_model: nano-banana-pro
    video_model: kling-3.0
    duration: 5
---

## Script
N/A — crash resume test.

## Execution log
<!-- engine:begin -->
<!-- engine:end -->

## Questions

## Outputs

## Auto-edits made during this run
EOF
```

- [ ] **Step 2: Simulate a run that crashed after Phase 3 Shot 1**

```bash
# Manually inject a partial log that looks like a crashed run mid-Phase-3
python3 - <<'PYEOF'
from pathlib import Path
p = Path.home() / "Obsidian/Higgsfield/Projects/crash-test.md"
text = p.read_text()
# Insert fake history between engine markers
text = text.replace(
    "<!-- engine:begin -->\n<!-- engine:end -->",
    "<!-- engine:begin -->\n"
    "- [x] 2026-04-22T20:00:00Z Phase 0 intake: status=active\n"
    "- [x] 2026-04-22T20:00:01Z Phase 1 VO: skipped (vo: null)\n"
    "- [x] 2026-04-22T20:00:02Z Phase 2 plan: skipped (2 shots pre-populated)\n"
    "- [x] 2026-04-22T20:01:15Z Phase 3 shot 1 image ✅ (attempt 1)\n"
    "<!-- engine:end -->"
)
p.write_text(text)
PYEOF

# Set status to active (simulating in-flight run)
python3 ~/.claude/skills/higgsfield/engine/update_status.py \
  ~/Obsidian/Higgsfield/Projects/crash-test.md active

# Pre-create the expected Shot 1 output on disk so the orchestrator knows to skip it
mkdir -p ~/Higgsfield-out/crash-test
# Use a tiny real PNG fixture
ffmpeg -y -f lavfi -i "color=c=blue:size=320x180:duration=1" -vframes 1 \
  ~/Higgsfield-out/crash-test/shot1.png 2>/dev/null
```

- [ ] **Step 3: Invoke Mode A**

In a fresh chat turn: **"Run crash-test"**.

Per the playbook's Phase 0 resume rule, Claude should:
1. See `status: active` with no live session → detect crash.
2. Read the execution log → last `[x]` is "Phase 3 shot 1 image ✅".
3. Identify next phase: Phase 3 shot 2 (not yet done).
4. Also verify `shot1.png` exists on disk → skip regenerating it.
5. Generate shot 2 image + proceed through Phase 4/6/7 normally.

- [ ] **Step 4: Verify resume happened**

```bash
cat ~/Obsidian/Higgsfield/Projects/crash-test.md
```

Expected execution log includes:
- The 4 original `[x]` lines (preserved)
- A new `[x] RESUME from Phase 3 shot 2` marker
- Subsequent phases completing normally
- Final `status: done`

- [ ] **Step 5: Cleanup + no commit**

```bash
rm -rf ~/Higgsfield-out/crash-test
rm ~/Obsidian/Higgsfield/Projects/crash-test.md
```

(Optional — the smoke test artifacts can stay for audit.)

---

## Self-review checklist (for the plan writer)

**Spec coverage:**
- §3.1 pre-flight → Task 1 (preflight.sh) + Task 6 playbook references it.
- §3.2 intake → Task 2 (parse_frontmatter.py) + Task 3 (update_status.py) + Task 6 playbook.
- §3.3 VO, §3.4 plan, §3.5 images, §3.6 videos, §3.7 transitions, §3.8 stitch, §3.9 finalize → all documented in Task 6 playbook.
- §4 subagent patterns → Task 6 playbook subsection.
- §5 Mode B cron → Task 8 (cron setup language) + Task 4 (sweep.sh) + Task 10 (smoke test).
- §6 crash recovery → Task 6 playbook §Phase 0 + Task 11 (smoke test).
- §7 pause semantics → Task 7 (SKILL.md Pause/resume rewrite) + Task 6 playbook.
- §8 browser lifecycle → Task 6 playbook §Browser lifecycle.
- §9 new/modified files → Tasks 1-8 produce exactly that set.

**Placeholder scan:** no TBD, no "implement later", no "similar to", no incomplete code blocks. Tests have full fixtures inline. Every step has either a code block or an exact shell command.

**Type consistency:** script filenames used consistently (`preflight.sh`, `parse_frontmatter.py`, `update_status.py`, `sweep.sh`). `HF_VAULT_DIR` env override used in both `init_vault.sh` (existing) and `sweep.sh` (new). `HF_CHROME_DIR` / `HF_CHROME_PATTERN` env override used only in `preflight.sh`, named consistently.

**Scope:** 8 code/edit tasks + 3 smoke tests = 11 total. All single-commit, all ≤5 steps. Suitable for subagent-driven execution.

---

*End of implementation plan.*
