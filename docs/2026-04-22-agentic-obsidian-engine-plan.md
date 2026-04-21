# Agentic Higgsfield Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `higgsfield` skill into an agentic engine driven by Obsidian project notes, with multi-tab parallelism, VO-first timing, bounded QC retries, four invocation modes, and git-backed skill self-editing.

**Architecture:** Deterministic shell/ffmpeg helpers in `engine/`, orchestration logic in `SKILL.md`, auto-edit scope enforced by HTML-comment marker blocks, git repo in the skill dir for rollback. Claude Code (with Playwright MCP) is the runtime driver.

**Tech Stack:** Bash, ffmpeg/ffprobe, Python (for YAML frontmatter), Playwright MCP, Claude Code skill system, git.

**Spec:** `docs/2026-04-22-agentic-obsidian-engine-design.md`

**Working directory for all relative paths:** `~/.claude/skills/higgsfield/`

---

## Task 1: Create `engine/` directory with README

**Files:**
- Create: `engine/README.md`
- Create: `engine/tests/.gitkeep`

- [ ] **Step 1: Verify skill dir is a git repo**

Run: `cd ~/.claude/skills/higgsfield && git log --oneline | head -1`
Expected: at least one commit exists (the baseline spec commit `8ed8c9f` or later).

If no commits exist, run `git init` and make an empty baseline commit first.

- [ ] **Step 2: Create the engine directory**

```bash
mkdir -p ~/.claude/skills/higgsfield/engine/tests
touch ~/.claude/skills/higgsfield/engine/tests/.gitkeep
```

- [ ] **Step 3: Write `engine/README.md`**

Path: `~/.claude/skills/higgsfield/engine/README.md`

```markdown
# Higgsfield engine scripts

Deterministic helpers called by the higgsfield skill during project execution. Each script is invoked by Claude Code from the skill's engine-mode workflow (see `../SKILL.md` "Engine mode" section).

| Script | Purpose | Input | Output |
|---|---|---|---|
| `probe_duration.sh` | ffprobe wrapper returning media duration in seconds | path to audio/video file | seconds on stdout (e.g. `42.34`) |
| `extract_frames.sh` | Extract last frame of clip A + first frame of clip B for transitions | `<clipA> <clipB> <out-dir>` | writes `<out-dir>/clipA-last.png` and `<out-dir>/clipB-first.png` |
| `stitch.sh` | Normalize + concatenate clips into a final MP4 per JSON manifest | path to manifest JSON | writes output MP4 at `manifest.output`, prints its duration to stdout |
| `init_vault.sh` | Idempotent bootstrap of `~/Obsidian/Higgsfield/` vault | none | creates vault structure + template; exits 0 |

## Testing

Each script has a sibling test under `tests/test_<name>.sh`. Run all: `bash tests/run_all.sh`

## Dependencies

- `ffmpeg` + `ffprobe` (brew install ffmpeg)
- Bash 4+ (macOS default `/bin/bash` 3.2 is fine; all scripts use POSIX-compatible features)
- `jq` for JSON manifest parsing in `stitch.sh` (brew install jq)
- `python3` with `yaml` (for frontmatter parsing in SKILL.md workflows, not in engine/ scripts)
```

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/README.md engine/tests/.gitkeep
git commit -m "engine: scaffold engine/ directory with README"
```

---

## Task 2: Implement `engine/probe_duration.sh`

**Files:**
- Create: `engine/probe_duration.sh`
- Create: `engine/tests/test_probe_duration.sh`

- [ ] **Step 1: Write the failing test**

Path: `~/.claude/skills/higgsfield/engine/tests/test_probe_duration.sh`

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/../probe_duration.sh"
FIXTURE="$SCRIPT_DIR/fixtures/tone-2.5s.mp3"

# Generate fixture on demand (idempotent)
mkdir -p "$(dirname "$FIXTURE")"
if [ ! -f "$FIXTURE" ]; then
  ffmpeg -y -f lavfi -i "sine=frequency=440:duration=2.5" -c:a libmp3lame -q:a 4 "$FIXTURE" 2>/dev/null
fi

# Test 1: returns duration close to 2.5
actual=$("$PROBE" "$FIXTURE")
awk_pass=$(awk -v a="$actual" 'BEGIN { exit (a >= 2.4 && a <= 2.6) ? 0 : 1 }') || {
  echo "FAIL test_probe_duration basic: expected ~2.5, got $actual"
  exit 1
}
echo "PASS test_probe_duration basic ($actual)"

# Test 2: missing file exits non-zero
if "$PROBE" "/tmp/nonexistent-file-xyz.mp3" 2>/dev/null; then
  echo "FAIL test_probe_duration missing-file: expected non-zero exit"
  exit 1
fi
echo "PASS test_probe_duration missing-file"

echo "ALL PASSED: probe_duration"
```

- [ ] **Step 2: Make the test executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_probe_duration.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_probe_duration.sh
```

Expected: fails with `probe_duration.sh: No such file or directory` or equivalent.

- [ ] **Step 3: Write the implementation**

Path: `~/.claude/skills/higgsfield/engine/probe_duration.sh`

```bash
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
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/probe_duration.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_probe_duration.sh
```

Expected: `ALL PASSED: probe_duration`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/probe_duration.sh engine/tests/test_probe_duration.sh
git commit -m "engine: add probe_duration.sh (ffprobe wrapper) + test"
```

---

## Task 3: Implement `engine/extract_frames.sh`

**Files:**
- Create: `engine/extract_frames.sh`
- Create: `engine/tests/test_extract_frames.sh`

- [ ] **Step 1: Write the failing test**

Path: `~/.claude/skills/higgsfield/engine/tests/test_extract_frames.sh`

```bash
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
```

- [ ] **Step 2: Make the test executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_extract_frames.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_extract_frames.sh
```

Expected: fails with `extract_frames.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Path: `~/.claude/skills/higgsfield/engine/extract_frames.sh`

```bash
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
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/extract_frames.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_extract_frames.sh
```

Expected: `ALL PASSED: extract_frames`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/extract_frames.sh engine/tests/test_extract_frames.sh
git commit -m "engine: add extract_frames.sh + test"
```

---

## Task 4: Implement `engine/stitch.sh`

**Files:**
- Create: `engine/stitch.sh`
- Create: `engine/tests/test_stitch.sh`

**Manifest schema reminder** (from spec §12 appendix D):

```json
{
  "output": "/path/to/final.mp4",
  "resolution": [1920, 1080],
  "fps": 24,
  "clips": [
    {"path": "shot1.mp4", "type": "shot"},
    {"path": "T1.mp4",    "type": "transition"},
    {"path": "shot2.mp4", "type": "shot"},
    {"path": null,        "type": "cut"},
    {"path": "shot3.mp4", "type": "shot"}
  ],
  "vo": {"path": "vo.mp3", "mode": "overlay"},
  "cut_xfade": 0.4
}
```

`cut` entries are markers — the script inserts an xfade of `cut_xfade` seconds between the adjacent shots. `transition` entries are concatenated as-is (no xfade on top).

- [ ] **Step 1: Write the failing test**

Path: `~/.claude/skills/higgsfield/engine/tests/test_stitch.sh`

```bash
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

# Cleanup
rm -rf "$TMP_DIR"
echo "ALL PASSED: stitch"
```

- [ ] **Step 2: Make the test executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_stitch.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_stitch.sh
```

Expected: fails with `stitch.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Path: `~/.claude/skills/higgsfield/engine/stitch.sh`

```bash
#!/bin/bash
# stitch.sh — concatenate clips per manifest, optionally overlay VO.
# Usage: stitch.sh <manifest.json>
# Prints output duration to stdout.

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

# Build list of real (non-cut) clips
mapfile -t clip_paths < <(jq -r '.clips[] | select(.type != "cut") | .path' "$manifest")

if [ "${#clip_paths[@]}" -eq 0 ]; then
  echo "Error: manifest has no clips" >&2
  exit 1
fi

# Normalize each clip to target resolution/fps
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

normalized=()
for i in "${!clip_paths[@]}"; do
  clip="${clip_paths[$i]}"
  [ -f "$clip" ] || { echo "Error: clip not found: $clip" >&2; exit 1; }
  norm="$tmpdir/norm-$i.mp4"
  ffmpeg -y -i "$clip" \
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
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/stitch.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_stitch.sh
```

Expected: `ALL PASSED: stitch`.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/stitch.sh engine/tests/test_stitch.sh
git commit -m "engine: add stitch.sh (manifest-driven concat + VO overlay) + test"
```

---

## Task 5: Implement `engine/init_vault.sh`

**Files:**
- Create: `engine/init_vault.sh`
- Create: `engine/tests/test_init_vault.sh`

- [ ] **Step 1: Write the failing test**

Path: `~/.claude/skills/higgsfield/engine/tests/test_init_vault.sh`

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT="$SCRIPT_DIR/../init_vault.sh"
TEST_VAULT="$SCRIPT_DIR/tmp-vault"

# Clean slate
rm -rf "$TEST_VAULT"

# Test 1: first run creates structure
HF_VAULT_DIR="$TEST_VAULT" "$INIT"

[ -d "$TEST_VAULT/Projects" ] || { echo "FAIL: Projects/ missing"; exit 1; }
[ -d "$TEST_VAULT/_templates" ] || { echo "FAIL: _templates/ missing"; exit 1; }
[ -d "$TEST_VAULT/_runs" ] || { echo "FAIL: _runs/ missing"; exit 1; }
[ -f "$TEST_VAULT/_templates/new-project.md" ] || { echo "FAIL: template missing"; exit 1; }

# Template should contain required frontmatter keys
grep -q "^project:" "$TEST_VAULT/_templates/new-project.md" || { echo "FAIL: template missing project: field"; exit 1; }
grep -q "^status:" "$TEST_VAULT/_templates/new-project.md" || { echo "FAIL: template missing status: field"; exit 1; }
grep -q "engine:begin" "$TEST_VAULT/_templates/new-project.md" || { echo "FAIL: template missing engine:begin marker"; exit 1; }

echo "PASS test_init_vault first-run"

# Test 2: idempotent (re-running doesn't error or clobber)
touch "$TEST_VAULT/_templates/new-project.md.userMod"
HF_VAULT_DIR="$TEST_VAULT" "$INIT"
[ -f "$TEST_VAULT/_templates/new-project.md.userMod" ] || { echo "FAIL: idempotent run clobbered user file"; exit 1; }

echo "PASS test_init_vault idempotent"

# Cleanup
rm -rf "$TEST_VAULT"
echo "ALL PASSED: init_vault"
```

- [ ] **Step 2: Make the test executable and verify it fails**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/test_init_vault.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_init_vault.sh
```

Expected: fails with `init_vault.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Path: `~/.claude/skills/higgsfield/engine/init_vault.sh`

```bash
#!/bin/bash
# init_vault.sh — idempotent Obsidian vault bootstrap for Higgsfield projects.
# Default vault path: ~/Obsidian/Higgsfield
# Override with: HF_VAULT_DIR=/some/path init_vault.sh

set -e

VAULT="${HF_VAULT_DIR:-$HOME/Obsidian/Higgsfield}"

mkdir -p "$VAULT/Projects"
mkdir -p "$VAULT/_templates"
mkdir -p "$VAULT/_runs"

template="$VAULT/_templates/new-project.md"
if [ ! -f "$template" ]; then
  cat > "$template" <<'TEMPLATE'
---
project: example-slug
status: inbox
aspect: 16:9
duration: vo-driven
style_reference: null
vo:
  script: |
    (paste the narration script here)
  model: eleven-v3
  voice: TALLULAH
transitions:
  mode: half-half
  seamless_pairs: []
retries_per_shot: 3
schedule: null
shots: []
---

## Script

## Style notes

## Execution log
<!-- engine:begin -->
<!-- engine:end -->

## Questions

## Outputs
- VO:
- Final:

## Auto-edits made during this run
TEMPLATE
  echo "Created template: $template"
else
  echo "Template exists, skipping: $template"
fi

echo "Vault ready: $VAULT"
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/init_vault.sh
bash ~/.claude/skills/higgsfield/engine/tests/test_init_vault.sh
```

Expected: `ALL PASSED: init_vault`.

- [ ] **Step 5: Bootstrap the real vault**

```bash
bash ~/.claude/skills/higgsfield/engine/init_vault.sh
ls ~/Obsidian/Higgsfield/
```

Expected output includes `Projects`, `_runs`, `_templates`.

- [ ] **Step 6: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/init_vault.sh engine/tests/test_init_vault.sh
git commit -m "engine: add init_vault.sh (idempotent vault bootstrap) + test"
```

---

## Task 6: Add a single test runner

**Files:**
- Create: `engine/tests/run_all.sh`

- [ ] **Step 1: Write the runner**

Path: `~/.claude/skills/higgsfield/engine/tests/run_all.sh`

```bash
#!/bin/bash
# run_all.sh — execute every test_*.sh in this directory, in order.
# Exits non-zero on first failure.

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for t in "$DIR"/test_*.sh; do
  echo ""
  echo "=== Running: $(basename "$t") ==="
  bash "$t"
done

echo ""
echo "=== All engine tests passed ==="
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x ~/.claude/skills/higgsfield/engine/tests/run_all.sh
bash ~/.claude/skills/higgsfield/engine/tests/run_all.sh
```

Expected: each test prints `ALL PASSED:` and finally `=== All engine tests passed ===`.

- [ ] **Step 3: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add engine/tests/run_all.sh
git commit -m "engine: add tests/run_all.sh runner"
```

---

## Task 7: Add auto-edit marker blocks to `references/traps.md`

**Files:**
- Modify: `references/traps.md`

The spec identifies six categories in `traps.md`: Cost traps, Session-state traps, UI discovery traps, UI-commit traps, Submission traps, Eligibility & moderation traps, Browser-automation traps, Label/naming traps. Each needs marker blocks at the end of its category.

- [ ] **Step 1: Read current structure**

```bash
grep -n "^## " ~/.claude/skills/higgsfield/references/traps.md
```

Expected output: a list of `## Cost traps (...)`, `## Session-state traps (...)`, etc.

- [ ] **Step 2: Append a marker block before each top-level category break (and before "Quick self-check")**

Use the Edit tool to add, at the END of each category section (right before the next `## ` heading), a block like:

```markdown

<!-- auto-edit:traps category=cost -->
<!-- /auto-edit:traps -->
```

Category slugs (use exactly these lowercase keys — machine-readable):
- After "Cost traps (…)" → `category=cost`
- After "Session-state traps (…)" → `category=session-state`
- After "UI discovery traps (…)" → `category=ui-discovery`
- After "UI-commit traps (…)" → `category=ui-commit`
- After "Submission traps (…)" → `category=submission`
- After "Eligibility & moderation traps (…)" → `category=eligibility`
- After "Browser-automation traps (…)" → `category=browser-automation`
- After "Label/naming traps (…)" → `category=label-naming`

Do NOT add a marker at the bottom of the file (after "Quick self-check"); that section is for human consumption only.

- [ ] **Step 3: Verify all 8 markers exist**

```bash
grep -c "auto-edit:traps category=" ~/.claude/skills/higgsfield/references/traps.md
```

Expected: `16` (8 opening + 8 closing markers, each `auto-edit:traps category=` appears twice per block — once in open, once in close... actually the close is `/auto-edit:traps` without the category suffix, so just 8 matches).

Let me re-verify: the closing marker is `<!-- /auto-edit:traps -->` (no category). So `grep -c "auto-edit:traps category="` returns **8** (openings only). Confirm that.

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add references/traps.md
git commit -m "traps: add auto-edit marker blocks per category"
```

---

## Task 8: Add auto-edit marker blocks to `references/workflows.md`

**Files:**
- Modify: `references/workflows.md`

The spec calls for markers inside each W-section's "Hollywood patterns" block (where applicable). Key W-sections to mark: W11 (seamless transitions), W12 (Seedance eligibility), W13 (VO-driven), W14 (storyboard), W15 (stitching).

- [ ] **Step 1: Read current structure**

```bash
grep -n "^## W" ~/.claude/skills/higgsfield/references/workflows.md
```

Expected: list of W1-W15 section headings.

- [ ] **Step 2: Add marker block at the end of W11, W12, W13, W15**

Inside each of these sections, at the end of the section body (right before the next `## ` heading), insert:

```markdown

<!-- auto-edit:workflow w=W11 section=patterns -->
<!-- /auto-edit:workflow -->
```

Use `w=W11`, `w=W12`, `w=W13`, `w=W15` for the respective sections. Skip W14 (storyboard) — no prompt-craft content there.

- [ ] **Step 3: Verify markers exist**

```bash
grep -c "auto-edit:workflow w=" ~/.claude/skills/higgsfield/references/workflows.md
```

Expected: `4` (4 opening markers).

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add references/workflows.md
git commit -m "workflows: add auto-edit markers to W11, W12, W13, W15"
```

---

## Task 9: Add auto-edit marker blocks to `references/models.md`

**Files:**
- Modify: `references/models.md`

The spec calls for per-model marker blocks. Key models to mark: nano-banana-pro, kling-3.0, kling-2.5-turbo, seedance-2.0, eleven-v3.

- [ ] **Step 1: Find each model's row**

```bash
grep -n "^|" ~/.claude/skills/higgsfield/references/models.md | head -30
```

Expected: table rows listing each model.

- [ ] **Step 2: Append a marker block below each model's table, near its detail paragraph**

Since models.md uses tables (not per-model sections), place markers below each model's table, labeled with the model id:

```markdown

<!-- auto-edit:model m=nano-banana-pro -->
<!-- /auto-edit:model -->
```

Add markers below the tables discussing: `m=nano-banana-pro`, `m=kling-3.0`, `m=kling-2.5-turbo`, `m=seedance-2.0`, `m=eleven-v3`.

- [ ] **Step 3: Verify markers exist**

```bash
grep -c "auto-edit:model m=" ~/.claude/skills/higgsfield/references/models.md
```

Expected: `5`.

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add references/models.md
git commit -m "models: add auto-edit markers for top 5 models"
```

---

## Task 10: Add auto-edit marker block to `SKILL.md`

**Files:**
- Modify: `SKILL.md`

- [ ] **Step 1: Read the "Current model availability" section**

```bash
grep -n "^## Current model availability" ~/.claude/skills/higgsfield/SKILL.md
```

- [ ] **Step 2: Append the marker block at the end of that section**

Right before the next `## ` heading after "Current model availability", insert:

```markdown

<!-- auto-edit:skill section=availability -->
<!-- /auto-edit:skill -->
```

- [ ] **Step 3: Verify marker exists**

```bash
grep -c "auto-edit:skill section=" ~/.claude/skills/higgsfield/SKILL.md
```

Expected: `1`.

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add SKILL.md
git commit -m "skill: add auto-edit marker to 'Current model availability' section"
```

---

## Task 11: Write SKILL.md "Engine mode" section

**Files:**
- Modify: `SKILL.md`

Add a new top-level section after "Before any task — ASK, never predict" and before "Current model availability". This section is the phase-by-phase playbook Claude follows during engine-mode runs.

- [ ] **Step 1: Edit SKILL.md to add the Engine mode section**

Use the Edit tool. Insert the following markdown after the "Before any task — ASK, never predict" section ends (i.e., after `don't guess your way through.`) and before `## Current model availability (this session)`:

```markdown
## Engine mode (agentic execution via Obsidian project notes)

When asked to **run a project** (by slug, or "run the inbox", or "run X and Y in parallel", or a scheduler sweep), enter engine mode. The authoritative contract is in `docs/2026-04-22-agentic-obsidian-engine-design.md`. This section is the execution playbook.

### Intake rules
- The project note lives at `~/Obsidian/Higgsfield/Projects/<slug>.md`. The `status` frontmatter field is the lifecycle switch.
- Only edit the note inside `<!-- engine:begin -->`…`<!-- engine:end -->`, `## Questions`, `## Outputs`, `## Auto-edits made during this run`, and the `status`/`shots` frontmatter fields.
- Before starting, read `git log --oneline -20` inside `~/.claude/skills/higgsfield/` and scan for recently-learned traps/workflows that might apply to this project.

### Phase sequence
1. **Intake** — parse frontmatter (`python -c "import sys,yaml; ..."`), validate required fields, set `status: active`, append start line to execution log.
2. **VO** (if `vo.script` present) — navigate to `/audio`, set model + voice + script in composer. **Read the waveform's mm:ss label from the DOM before clicking Generate** — this gives a duration estimate to plan against. Click Generate. Download the mp3 to `~/Higgsfield-out/<slug>/vo.mp3`. Run `engine/probe_duration.sh` to get the actual duration.
3. **Plan** — if `shots:` is empty in frontmatter, plan N shots + M transitions to fit the VO duration (or the explicit `duration:`). Write the plan into `shots:` frontmatter. If script has ambiguous beat count vs. target shot count, pause: append `### Q: <question>` under `## Questions`, set `status: paused`, return control to the user.
4. **Images** — lazy-spawn up to min(N, 6) worker tabs on `/ai/image?model=nano-banana-pro`. Each submits one shot image. Download + QC-loop each (§ QC loop below).
5. **Videos** — lazy-spawn up to min(N, 6) workers on `/ai/video` with Kling 3.0 selected. Each submits one shot animation. Download + QC-loop.
6. **Transitions** — for each seamless pair, run `engine/extract_frames.sh <shotA> <shotB> <tmp-dir>`, then submit a Kling 3.0 Start+End-frame job with duration=3s (see [W11](references/workflows.md) and trap #21 for the commit mechanism).
7. **Stitch** — build a manifest JSON from the clips+transitions+VO, call `engine/stitch.sh manifest.json`.
8. **Finalize** — set `status: done` (or `partial` if any artifact failed), fill `## Outputs` with wiki-links, archive the verbose run log to `~/Obsidian/Higgsfield/_runs/<timestamp>-<slug>.md`.

### Tab allocation (lazy-spawn, reuse across phases)
- `main` — driver's primary. Not a composer.
- `audio` — pinned to `/audio` during Phase 2.
- `monitor` — pinned to `/asset/video` for polling results.
- `workers` — 1..6 Kling 3.0 composer tabs, spawned only as needed by Phase 4/5/6.

Cap on worker tabs is 6 regardless of shot count. If shot count > 6, batch submissions in waves of 6.

### QC loop (per artifact, max 3 attempts)
After each artifact downloads, run a vision check:
- **Image**: Read the PNG; compare top-priority prompt elements (head nouns, color-grade cues).
- **Video**: Read first/mid/last frames as images; compare to source image + implied motion.
- **Transition**: Read transition's first frame vs. clip-A's last frame, AND transition's last frame vs. clip-B's first frame; check continuity.

If check passes → log `[x]`, move on. If fails → attempt 2 with tightened prompt (keep intent, add missing elements, add anti-prompts like "no flash"); attempt 3 with simplified prompt. After 3 failures:
- Spec ambiguity → pause with `### Q:`.
- Technical quality → log `[!]`, keep best-ranked attempt, continue.

### Mode dispatch
- One slug name → Mode A: single project.
- "run the inbox" → Mode B: all `status: inbox` projects, sequential.
- Multiple slugs → Mode C: up to 3 in parallel, shared worker pool.
- "scheduler sweep" (cron-triggered or manual) → Mode D: iterate `status: scheduled` projects whose `schedule:` next-run has passed.

When natural-language intent is ambiguous, ask the user conversationally before dispatching.

### Pause / resume via the note
- Pause: append `### Q: <question>` under `## Questions`, set `status: paused`, stop.
- Resume: user adds `### A: <answer>` below the Q. In Mode A/C, the engine polls the note's mtime every 30s while paused (up to 30 minutes). In Mode D, the next cron sweep picks up any `A:`-populated Paused projects.
```

- [ ] **Step 2: Verify the section was inserted cleanly**

```bash
grep -n "^## Engine mode" ~/.claude/skills/higgsfield/SKILL.md
grep -n "^## Current model availability" ~/.claude/skills/higgsfield/SKILL.md
```

Expected: Engine mode line number < Current model availability line number.

- [ ] **Step 3: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add SKILL.md
git commit -m "skill: add 'Engine mode' section (agentic execution playbook)"
```

---

## Task 12: Write SKILL.md "Self-learning rules" section

**Files:**
- Modify: `SKILL.md`

Add a new top-level section after "Engine mode" and before "Current model availability".

- [ ] **Step 1: Edit SKILL.md to add the Self-learning section**

Use the Edit tool. Insert the following markdown after the Engine mode section ends and before `## Current model availability`:

```markdown
## Self-learning rules (skill auto-edit)

During engine-mode runs, when you discover a new fact about Higgsfield's behavior (UI quirk, prompt pattern, content-policy rule, model parameter), write it back into the skill so the next run handles it natively.

### What counts as a discovery worth recording
- A UI control behaves differently than this skill documented (type, commit mechanism, default value, range).
- A prompt-rewrite pattern that unblocked a QC failure (e.g., "adding 'no flash' anti-prompt fixed 80% of seam failures").
- A new model parameter observed (e.g., duration range, aspect options, cost datum).
- A recurring browser-automation glitch and its fix.
- A content-policy rewording that consistently passes (e.g., "warship" → "naval vessel").

### Non-triggers (do not auto-record)
- Anything already documented in this skill.
- One-off content rejections without a clear pattern.
- User-specific style preferences (those go to the memory system under `~/.claude/projects/.../memory/`).
- Your own creative choices about framing or composition.

### Destination routing

| Discovery type | File | Marker block |
|---|---|---|
| UI behavior, hidden control, commit mechanism | `references/traps.md` | `<!-- auto-edit:traps category=<name> -->` |
| Prompt-rewrite pattern | `references/workflows.md` | `<!-- auto-edit:workflow w=<W-id> section=patterns -->` |
| Model parameter or cost datum | `references/models.md` | `<!-- auto-edit:model m=<model-id> -->` |
| Session-wide rule | `SKILL.md` "Current model availability" | `<!-- auto-edit:skill section=availability -->` |
| User preference revealed mid-run | memory system | new file under `memory/` + MEMORY.md index |

### Guardrails (strict — never bypass)
1. **Append-only inside markers.** New content goes between the opening and closing marker tags. You do NOT delete or rewrite existing text. If a new finding directly contradicts an old statement, append a comment `<!-- superseded by auto-edit <YYYY-MM-DD> -->` to the old line — keep the old text for audit.
2. **Markers must exist before writing.** Before any auto-edit, re-read the target file and confirm both the opening and closing markers are present. If markers are missing, skip the write, append a one-line failure note to `~/Obsidian/Higgsfield/_runs/skill-edit-failures.md`, and continue.
3. **Rate limit: 5 auto-edits per project run.** Count writes per run. On the 6th attempted write, log the remaining finding to `_runs/skill-edit-deferred.md` instead of writing.
4. **One commit per edit.** Commit format:
   ```
   auto-learn: <one-line summary>

   Spec: <project-slug>
   Run: <ISO timestamp>
   Source event: <what triggered the discovery>
   ```
5. **Surface in the project note.** At finalize time, append every auto-edit commit (hash + one-line summary) to the project note's `## Auto-edits made during this run` section.

### Pre-run context load
At the start of every engine run, run `git log --oneline -20` in the skill dir and include the results in your own context. This prevents re-discovering the same thing and committing duplicate fixes.
```

- [ ] **Step 2: Verify section ordering**

```bash
grep -n "^## " ~/.claude/skills/higgsfield/SKILL.md
```

Expected order: `Before any task — ASK` → `Engine mode` → `Self-learning rules` → `Current model availability` → ... (rest unchanged).

- [ ] **Step 3: Commit**

```bash
cd ~/.claude/skills/higgsfield
git add SKILL.md
git commit -m "skill: add 'Self-learning rules' section (auto-edit policy)"
```

---

## Task 13: Smoke test — run the engine tests end-to-end

**Files:**
- No file changes. This task verifies the suite passes together.

- [ ] **Step 1: Run the full engine test suite**

```bash
bash ~/.claude/skills/higgsfield/engine/tests/run_all.sh
```

Expected: every test prints `ALL PASSED:` and the runner ends with `=== All engine tests passed ===`.

If anything fails, fix the underlying script (not the test) and re-run.

- [ ] **Step 2: Verify the vault was bootstrapped**

```bash
ls -la ~/Obsidian/Higgsfield/
cat ~/Obsidian/Higgsfield/_templates/new-project.md | head -30
```

Expected: directories `Projects`, `_templates`, `_runs` exist; template has the full frontmatter skeleton with `project:`, `status: inbox`, `engine:begin`.

- [ ] **Step 3: Verify marker blocks are in place**

```bash
cd ~/.claude/skills/higgsfield
echo "traps:" && grep -c "auto-edit:traps category=" references/traps.md
echo "workflows:" && grep -c "auto-edit:workflow w=" references/workflows.md
echo "models:" && grep -c "auto-edit:model m=" references/models.md
echo "skill:" && grep -c "auto-edit:skill section=" SKILL.md
```

Expected: `traps: 8`, `workflows: 4`, `models: 5`, `skill: 1`.

- [ ] **Step 4: Verify the git history is clean and sensible**

```bash
cd ~/.claude/skills/higgsfield
git log --oneline
```

Expected: a sequence of conventional-style commits like:
```
<hash> skill: add 'Self-learning rules' section (auto-edit policy)
<hash> skill: add 'Engine mode' section (agentic execution playbook)
<hash> skill: add auto-edit marker to 'Current model availability' section
<hash> models: add auto-edit markers for top 5 models
<hash> workflows: add auto-edit markers to W11, W12, W13, W15
<hash> traps: add auto-edit marker blocks per category
<hash> engine: add tests/run_all.sh runner
<hash> engine: add init_vault.sh (idempotent vault bootstrap) + test
<hash> engine: add stitch.sh (manifest-driven concat + VO overlay) + test
<hash> engine: add extract_frames.sh + test
<hash> engine: add probe_duration.sh (ffprobe wrapper) + test
<hash> engine: scaffold engine/ directory with README
<hash> design: agentic Obsidian-orchestrated engine for higgsfield skill
```

No further commit needed — this task is a verification pass only.

---

## Task 14: End-to-end smoke test — single-shot Mode A project

**Files:**
- Create: `~/Obsidian/Higgsfield/Projects/smoke-test.md` (and read it back via engine mode)

This task validates that the engine playbook in SKILL.md is actually executable. It uses a **deliberately tiny project** (1 shot, no VO, no transitions) to minimize credit spend and run time.

- [ ] **Step 1: Create a minimal project note**

```bash
cat > ~/Obsidian/Higgsfield/Projects/smoke-test.md <<'EOF'
---
project: smoke-test
status: inbox
aspect: 16:9
duration: 5s
style_reference: null
vo: null
transitions:
  mode: all-cuts
  seamless_pairs: []
retries_per_shot: 3
schedule: null
shots:
  - n: 1
    beat: "A single slow zoom on an empty beach at dusk"
    prompt: "Wide cinematic slow zoom on an empty golden-hour beach, small waves, a distant silhouette of a freighter on the horizon, warm light, steady camera"
    image_model: nano-banana-pro
    video_model: kling-3.0
    duration: 5
---

## Script
N/A — no VO for smoke test

## Style notes
Warm, calm. Testing engine plumbing only.

## Execution log
<!-- engine:begin -->
<!-- engine:end -->

## Questions

## Outputs
- Final:

## Auto-edits made during this run
EOF
```

- [ ] **Step 2: Invoke engine mode on the smoke-test project**

In a fresh chat turn, tell Claude:

> "Run smoke-test"

The skill should:
1. Read `~/Obsidian/Higgsfield/Projects/smoke-test.md` and parse the frontmatter.
2. Set `status: active`.
3. Skip Phase 1 (no VO) and Phase 2 (shots pre-populated).
4. Phase 3: generate 1 image on Nano Banana Pro.
5. Phase 4: animate on Kling 3.0 (5s duration).
6. Skip Phase 5 (no transitions).
7. Phase 6: stitch (single clip — this should pass through cleanly).
8. Phase 7: set `status: done`, fill Outputs section.

**Expected credits spent**: ~2 credits image + ~8.75 credits video = ~11 credits total.

**Expected duration**: 6-10 minutes.

- [ ] **Step 3: Verify outputs**

```bash
cat ~/Obsidian/Higgsfield/Projects/smoke-test.md
ls ~/Higgsfield-out/smoke-test/
```

Expected:
- `status: done` in frontmatter.
- `## Execution log` has entries for Phase 3 → done, Phase 4 → done, Phase 7 → done.
- `## Outputs > Final:` links to `~/Higgsfield-out/smoke-test/final.mp4`.
- The MP4 plays and is 5 seconds long.

- [ ] **Step 4: Commit any auto-learn edits**

The smoke test may have triggered self-learning commits. Check:

```bash
cd ~/.claude/skills/higgsfield
git log --oneline -5
```

If new `auto-learn:` commits appeared, they are already committed. Verify via:

```bash
git diff HEAD~3..HEAD -- references/ SKILL.md
```

If any auto-edit looks wrong, roll back with `git revert <hash>`.

---

## Self-review checklist (for the plan writer)

**Spec coverage:**
- §3 Architecture → covered conceptually; engine scripts + SKILL.md sections implement it (Tasks 2-5, 11-12).
- §4 Vault structure → Task 5 implements init_vault.sh which creates the exact structure and template.
- §5 Execution pipeline → Task 11 "Engine mode" section documents all 7 phases.
- §6 Multi-tab dispatch → Task 11 documents tab allocation in SKILL.md.
- §7 QC loop → Task 11 documents the 3-retry ladder.
- §8 Self-learning → Task 12 "Self-learning rules" + Tasks 7-10 add the marker blocks.
- §9 Invocation modes → Task 11 documents mode dispatch.
- §10 File layout → Tasks 1-12 produce exactly the layout described.

**Placeholders:** searched this plan for "TBD", "TODO", "implement later", "handle edge cases", "similar to" — none present.

**Type consistency:** script names (`probe_duration.sh`, `extract_frames.sh`, `stitch.sh`, `init_vault.sh`) match the spec §10 exactly. Marker block names match across plan and spec §12 appendix C.

**Scope:** single implementation plan, no subsystem decomposition needed.

---

*End of implementation plan.*
