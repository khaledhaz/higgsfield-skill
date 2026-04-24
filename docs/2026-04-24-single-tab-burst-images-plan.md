# Round 4 — Single-Tab Burst Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Round 3's N-parallel-tabs image phase with a single-tab burst worker that runs a 5-item preflight checklist before every Generate click, auto-remediates with per-check retry caps, and pauses-for-help with self-learning when stuck. Adds multimodal reference-image attachments via Creative Director → Visual Researcher → image-worker chain.

**Architecture:** One `image-worker` subagent (Haiku) owns the single NBP tab. It loops {preflight → fix → submit → next}, then polls the gallery and records variants. Orchestrator batch-reviews at end, dispatches prompt-writer BATCH_RETRY for failures, and pauses cleanly on preflight exhaustion (5× per check) with a self-learning hook.

**Tech Stack:** Bash + Python 3 (engine helpers), Markdown (agent prompts + playbook), Playwright MCP (browser automation against `higgsfield.ai`).

**Spec:** `docs/2026-04-24-single-tab-burst-images-design.md` (commit `daf2de1`). Read it end-to-end before starting.

**Skill root:** `/Users/khaled/.claude/skills/higgsfield/` — all paths below are relative to this directory unless absolute.

---

## File Structure

### Created

- `engine/reference_downloader.py` — CLI helper. Takes a URL + target dir, downloads the image with content-type validation, writes a deterministic filename, prints the local path. Single responsibility: URL → file on disk.
- `engine/tests/test_reference_downloader.sh` — integration test invoking the CLI against a local fixture HTTP server.
- `engine/tests/fixtures/reference_server.py` — tiny `http.server` that serves a PNG and a JPG from a fixtures dir; used by the test.

### Modified

- `agents/creative-director.md` — add `reference_images` field to claim schema + decision guidance.
- `agents/visual-researcher.md` — replace URL-collection step with URL-collection + download via new helper; schema extension.
- `agents/shot-planner.md` — copy `reference_images` from claim into both `start` and `end` image slots.
- `agents/image-worker.md` — full rewrite for single-tab burst mode with preflight checklist, per-check retry counters, pause-and-exit.
- `SKILL.md` — Phase 0 (remove tab pre-warm), Phase 4 (rewrite for single-tab burst), parallel-dispatch rules, timeline, self-learning routing table.
- `references/traps.md` — add new marker block `<!-- auto-edit:traps category=nbp-multimodal -->` and populate with smoke-test findings.

### Out of scope for this plan

- Video phase (Phase 5). Unchanged except that it no longer pipelines with image review.
- Stitch (Phase 6) and finalize (Phase 7). Unchanged.
- `engine/shot_state.py` — existing `update` supports arbitrary dot-paths including `images.start.reference_images`, so no change needed.

---

## Task 1: Smoke-test NBP multimodal UI and record findings

**Why first:** the image-worker's attach/detach logic depends on the exact DOM shape of NBP's attachment UI. Every later task that touches attachments needs these answers. If it turns out NBP doesn't support attachments cleanly, the plan collapses to a smaller version (skip Tasks 3-5, simplify Task 6's check 5).

**Files:**
- Modify: `references/traps.md` — add new marker block and populate with findings.

This task is a discovery task, not TDD. The engineer drives a real NBP tab via Playwright MCP, inspects, records. No unit tests.

- [ ] **Step 1: Open an NBP tab and snapshot**

Run these via Playwright MCP (user must be logged in):

```
browser_navigate url=https://higgsfield.ai/ai/image?model=nano-banana-pro
browser_wait_for time=2
browser_snapshot
```

Confirm you see the composer: prompt textbox, Generate button, Unlimited switch, model picker, resolution picker.

- [ ] **Step 2: Locate the attach-image entry point**

Look for any of these in the snapshot:
- A paperclip-style icon button near the prompt textbox
- A "+" or "attach" button
- A drop-zone hint like "Drag image here"
- A file-input like `<input type="file">` anywhere on the page

Record the selector(s). If none exist, stop — **NBP may not support attachments in the current UI**; skip to Step 7 and note "no attachment UI found; reference-images capability not feasible".

- [ ] **Step 3: Attach a single test image via drag-drop**

Pick a test PNG at `/tmp/ref_test_1024.png` (create with `ffmpeg -f lavfi -i color=red:size=1024x1024 -frames:v 1 /tmp/ref_test_1024.png` if needed).

Via `browser_evaluate`:

```js
async () => {
  const buf = await fetch('file:///tmp/ref_test_1024.png').then(r => r.blob()).catch(() => null);
  // If file:// is blocked, note that and fall back to: copy /tmp/ref_test_1024.png into a page /static path, or use a data URI.
  return buf ? buf.size : 'blocked';
}
```

If `file://` is blocked, use `browser_file_upload` on the discovered `<input type="file">` instead. Record which mechanism works.

- [ ] **Step 4: Record the attached-file chip list selector**

After Step 3 succeeds, `browser_snapshot` again. Find the new DOM node that represents the attached file (likely a chip / thumbnail / list item near the prompt). Record:
- Chip container selector (e.g., `ul[data-testid="attachments"]` or similar)
- Per-chip filename text selector
- Per-chip remove-X button selector

- [ ] **Step 5: Test second-attach, clear, and persistence**

- Attach a second file (different filename). Verify chip count = 2.
- Click one chip's X button. Verify chip count = 1 and the correct file was removed.
- Click Generate. Wait for the result to appear. Then check: does the remaining attachment persist in the composer for the next submit, or does it auto-clear?
- Record: "persists" or "auto-clears".

- [ ] **Step 6: Test that the reference actually affects the render**

Run two submits with the same prompt, one with an attached red square reference, one without. Compare the outputs visually. If the red square's composition/color vocabulary shows up only with the reference attached, reference is effective. If indistinguishable, NBP may need a prompt cue like `"Use the attached image as style reference"`.

Record: "effective" / "needs cue" / "no visible effect".

- [ ] **Step 7: Add the traps.md marker and fill in findings**

Append to `references/traps.md` — find the end of the existing marker blocks (search for the last `<!-- /auto-edit:traps -->` line) and insert:

```markdown
## NBP multimodal attachments

### 23. NBP reference-image attachments — mechanism and behavior
Observed 2026-04-24 during Round 4 smoke test.

**Attach mechanism**: <drag-drop on composer | file-input on paperclip button | other — fill from step 2/3>
**Chip list selector**: `<selector from step 4>`
**Remove-X selector**: `<selector from step 4>`
**Persistence across submits**: <persists | auto-clears — from step 5>
**Effect on render**: <effective | needs cue "<exact cue text>" | no visible effect — from step 6>
**Max concurrent attachments tested**: <N from step 5>
**Supported formats tested**: PNG <yes|no>, JPG <yes|no>, WebP <yes|no>
**File-size ceiling tested**: <largest size that worked>

<!-- auto-edit:traps category=nbp-multimodal -->
<!-- /auto-edit:traps -->
```

- [ ] **Step 8: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add references/traps.md
git commit -m "docs(traps): NBP multimodal attachment smoke-test findings"
```

---

## Task 2: Add `engine/reference_downloader.py`

**Files:**
- Create: `engine/reference_downloader.py`
- Create: `engine/tests/fixtures/reference_server.py`
- Create: `engine/tests/test_reference_downloader.sh`
- Modify: `engine/tests/run_all.sh` — add the new test to the batch.

- [ ] **Step 1: Write the failing test (fixture server)**

Create `engine/tests/fixtures/reference_server.py`:

```python
#!/usr/bin/env python3
"""Tiny HTTP server for reference_downloader tests.

Serves a 200 PNG at /ok.png, a 200 JPG at /ok.jpg, a 404 at /missing,
and a 200 text/html at /wrong_type (to exercise content-type rejection).
Run: python3 reference_server.py <port>
"""
import http.server
import socketserver
import sys
import io
import struct
import zlib

def tiny_png():
    # 1x1 red PNG, generated inline — no Pillow dependency.
    sig = b"\x89PNG\r\n\x1a\n"
    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    raw = b"\x00" + bytes([255, 0, 0])
    idat = chunk(b"IDAT", zlib.compress(raw))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend

def tiny_jpg():
    # Minimal JPEG magic; body doesn't need to decode correctly for our tests.
    return b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/ok.png":
            b = tiny_png()
            self.send_response(200); self.send_header("Content-Type", "image/png"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        elif self.path == "/ok.jpg":
            b = tiny_jpg()
            self.send_response(200); self.send_header("Content-Type", "image/jpeg"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        elif self.path == "/wrong_type":
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers(); self.wfile.write(b"<html>")
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a, **kw): pass

if __name__ == "__main__":
    port = int(sys.argv[1])
    with socketserver.TCPServer(("127.0.0.1", port), H) as srv:
        srv.serve_forever()
```

Create `engine/tests/test_reference_downloader.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PORT=$((RANDOM % 1000 + 19000))
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; [[ -n "${SRV_PID:-}" ]] && kill $SRV_PID 2>/dev/null || true' EXIT

python3 fixtures/reference_server.py $PORT &
SRV_PID=$!
sleep 0.3

# Case 1: happy-path PNG
out1=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.png" "$TMP/c1")
[[ -f "$out1" ]] || { echo "FAIL: png not saved"; exit 1; }
[[ "$out1" == *.png ]] || { echo "FAIL: wrong extension ($out1)"; exit 1; }
[[ "$(stat -f%z "$out1" 2>/dev/null || stat -c%s "$out1")" -gt 50 ]] || { echo "FAIL: png too small"; exit 1; }

# Case 2: happy-path JPG
out2=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.jpg" "$TMP/c2")
[[ "$out2" == *.jpg ]] || { echo "FAIL: wrong extension for jpg ($out2)"; exit 1; }

# Case 3: 404 returns nonzero
if python3 ../reference_downloader.py "http://127.0.0.1:$PORT/missing" "$TMP/c3" 2>/dev/null; then
    echo "FAIL: 404 should have exit nonzero"; exit 1
fi

# Case 4: wrong content-type returns nonzero, no file written
if python3 ../reference_downloader.py "http://127.0.0.1:$PORT/wrong_type" "$TMP/c4" 2>/dev/null; then
    echo "FAIL: wrong content-type should have exit nonzero"; exit 1
fi
[[ -z "$(ls "$TMP/c4" 2>/dev/null)" ]] || { echo "FAIL: wrote file despite wrong content-type"; exit 1; }

# Case 5: deterministic filename — same URL downloaded twice yields same path
out5a=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.png" "$TMP/c5")
out5b=$(python3 ../reference_downloader.py "http://127.0.0.1:$PORT/ok.png" "$TMP/c5")
[[ "$out5a" == "$out5b" ]] || { echo "FAIL: nondeterministic path"; exit 1; }

echo "PASS: reference_downloader"
```

Make it executable: `chmod +x engine/tests/test_reference_downloader.sh`.

- [ ] **Step 2: Run test — expect failure (helper doesn't exist yet)**

Run: `bash engine/tests/test_reference_downloader.sh`
Expected: nonzero exit, stderr mentions "No such file or directory" for `reference_downloader.py`.

- [ ] **Step 3: Implement `engine/reference_downloader.py`**

Create `engine/reference_downloader.py`:

```python
#!/usr/bin/env python3
"""reference_downloader.py — fetch an image URL to disk, validated.

Usage: reference_downloader.py <url> <target_dir>

Exits 0 on success and prints the absolute path of the saved file.
Exits 1 on any error (non-2xx HTTP, wrong content-type, write failure).

Filename is deterministic: <sha1(url)[:12]><ext> so re-running on the same URL
is idempotent — the caller can safely re-invoke without creating duplicates.
"""
import hashlib
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path

CONTENT_TYPE_TO_EXT = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/webp": ".webp",
}

def download(url: str, target_dir: Path) -> Path:
    target_dir.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "higgsfield-reference-downloader/1"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            ct = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            if ct not in CONTENT_TYPE_TO_EXT:
                raise ValueError(f"unsupported content-type: {ct!r}")
            body = resp.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} for {url}") from e
    if len(body) < 50:
        raise ValueError(f"response body too small ({len(body)} bytes) — likely error page")
    ext = CONTENT_TYPE_TO_EXT[ct]
    name = hashlib.sha1(url.encode("utf-8")).hexdigest()[:12] + ext
    dest = target_dir / name
    tmp = dest.with_suffix(ext + ".tmp")
    tmp.write_bytes(body)
    tmp.rename(dest)
    return dest

def main() -> int:
    if len(sys.argv) != 3:
        print("usage: reference_downloader.py <url> <target_dir>", file=sys.stderr)
        return 2
    url, target_dir = sys.argv[1], Path(sys.argv[2]).resolve()
    try:
        path = download(url, target_dir)
    except Exception as e:
        print(f"reference_downloader: {e}", file=sys.stderr)
        return 1
    print(path)
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

Make it executable: `chmod +x engine/reference_downloader.py`.

- [ ] **Step 4: Run test — expect pass**

Run: `bash engine/tests/test_reference_downloader.sh`
Expected: stdout `PASS: reference_downloader`, exit 0.

- [ ] **Step 5: Register in run_all.sh**

Read `engine/tests/run_all.sh`. Append a new test line following the existing pattern. If the file contains something like:

```bash
bash test_shot_state.sh
```

Add after the existing lines:

```bash
bash test_reference_downloader.sh
```

Run `bash engine/tests/run_all.sh` and confirm all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add engine/reference_downloader.py engine/tests/test_reference_downloader.sh engine/tests/fixtures/reference_server.py engine/tests/run_all.sh
git commit -m "feat(engine): reference_downloader helper for fetching reference images"
```

---

## Task 3: Extend `visual-researcher` agent to download reference images

**Files:**
- Modify: `agents/visual-researcher.md`

This agent is a prompt, not Python. No TDD — verification is by dispatching the agent against a small fixture.

- [ ] **Step 1: Locate the reference-URL collection block**

In `agents/visual-researcher.md`, find Step 3, sub-step 3 — the paragraph starting with `3. **Reference image URL collection**`. It lives around line 71-76 of the current file.

- [ ] **Step 2: Replace that sub-step with a URL-collection + download step**

Use `Edit` to replace the block:

OLD (exact match):

```markdown
3. **Reference image URL collection** (ONLY when the element is a specific named thing). From WebSearch result snippets, extract URLs that point to news-agency / official-source / satellite-imagery / well-known-photography pages. You can optionally `WebFetch` a candidate page to verify it's a real photo page.

   Do NOT collect reference URLs for generic elements ("a government corridor", "an industrial facility"). Only for NAMED specifics.

   Do NOT use random social media images. If the source is unclear or shady, skip.
```

NEW:

```markdown
3. **Reference image URL collection + download** (ONLY when the element is a specific named thing).

   (a) From WebSearch result snippets, extract URLs that point to news-agency / official-source / satellite-imagery / well-known-photography pages. You can optionally `WebFetch` a candidate page to verify it's a real photo page.

   (b) For each candidate URL that looks like a direct image (ends `.png`/`.jpg`/`.jpeg`/`.webp`, or a photo-hosting CDN known to serve raw images), download it using the engine helper:

   ```bash
   OUTPUT_DIR=$(dirname "$CLAIMS_PATH")
   REF_DIR="$OUTPUT_DIR/references/claim_$CLAIM_ID"
   LOCAL_PATH=$(python3 "$SKILL_ROOT/engine/reference_downloader.py" "$URL" "$REF_DIR" 2>/dev/null) || LOCAL_PATH=""
   ```

   Collect the **local paths** (not URLs) where the downloads succeeded. Skip URLs that failed — they're most likely HTML pages or blocked.

   Do NOT collect reference URLs for generic elements ("a government corridor", "an industrial facility"). Only for NAMED specifics.

   Do NOT use random social media images. If the source is unclear or shady, skip.

   Target 1–3 downloaded references per named element. Stop after 3 successful downloads for that element.
```

- [ ] **Step 3: Extend the schema documentation block**

Find the "Write results back into claims.json" block — it lists `reference_urls_start` and `reference_urls_end` fields. Use `Edit` to add two more fields.

OLD (exact match):

```python
        c["reference_urls_start"] = url_list_start  # list of strings, may be empty
        if c.get("technique") == "start_end":
            c["reference_urls_end"] = url_list_end
```

NEW:

```python
        c["reference_urls_start"] = url_list_start  # list of strings, may be empty — source URLs for audit
        c["reference_images_start"] = local_paths_start  # list of absolute paths to downloaded files
        if c.get("technique") == "start_end":
            c["reference_urls_end"] = url_list_end
            c["reference_images_end"] = local_paths_end
```

- [ ] **Step 4: Update the "How your output gets used downstream" section**

Find the paragraph near the end that says "It also copies `reference_urls_start` / `reference_urls_end` into `images.<role>.reference_urls` and `research_notes_start` / `research_notes_end` into `images.<role>.research_notes`."

OLD (exact match):

```markdown
The Shot Planner (Sonnet, runs after Whisper) reads `claims.json` and copies your enriched `concept_prompt_start` / `concept_prompt_end` directly into `shots.json` image slots. It also copies `reference_urls_start` / `reference_urls_end` into `images.<role>.reference_urls` and `research_notes_start` / `research_notes_end` into `images.<role>.research_notes`.
```

NEW:

```markdown
The Shot Planner (Sonnet, runs after Whisper) reads `claims.json` and copies your enriched `concept_prompt_start` / `concept_prompt_end` directly into `shots.json` image slots. It also copies `reference_urls_start` / `reference_urls_end` into `images.<role>.reference_urls`, `research_notes_start` / `research_notes_end` into `images.<role>.research_notes`, and `reference_images_start` / `reference_images_end` into `images.<role>.reference_images`. The Creative Director's subsequent `reference_images` field (if present in the claim — added in Round 4) supersedes the researcher's list per claim; see creative-director.md for the promotion rules.
```

- [ ] **Step 5: Update the DONE report format**

OLD (exact match):

```
reference_urls_found: <count>
```

NEW:

```
reference_urls_found: <count>
reference_images_downloaded: <count of files successfully written>
```

- [ ] **Step 6: Add a rule to the Rules section**

Find the "## Rules" section (near the end). Insert this as a new bullet right before the LAST rule ("NEVER write outside your `CLAIM_RANGE`..."):

```markdown
- NEVER delete a reference image that's already on disk — the downloader is idempotent by URL hash, so re-runs are safe. If a download fails, just leave the existing files alone and append new ones.
```

- [ ] **Step 7: Verify file is parseable as markdown**

Run: `head -1 agents/visual-researcher.md` (expect `---` frontmatter) and check that the file still starts with valid YAML frontmatter and the `# Visual Researcher` heading.

- [ ] **Step 8: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add agents/visual-researcher.md
git commit -m "feat(visual-researcher): download candidate reference images into project"
```

---

## Task 4: Extend `creative-director` agent to emit `reference_images` per claim

**Files:**
- Modify: `agents/creative-director.md`

- [ ] **Step 1: Add a new decision section #8 after "Per-claim video prompt"**

Find the heading `### 6. Per-claim video prompt` and its body. After that section ends (and before `### 7. Pacing hints for the Shot Planner`), insert a new section. Use `Edit` to replace the boundary:

OLD (exact match):

```markdown
For `start_end`: describe the TRANSITION, not the endpoints.

### 7. Pacing hints for the Shot Planner
```

NEW:

```markdown
For `start_end`: describe the TRANSITION, not the endpoints.

### 7. Per-claim reference-image selection (Round 4)

The Visual Researcher has (or will have) downloaded candidate reference images for each claim into `$OUTPUT_DIR/references/claim_<id>/*.{png,jpg,webp}`. You decide which (if any) are appropriate to attach to the NBP multimodal generation for that claim.

Rules:
- **Default: none.** Leave `reference_images: []` unless there's a specific accuracy reason to attach one. Burst submission is faster and simpler without attachments.
- **Attach when the claim's visual_concept names a specific real-world thing** whose appearance is load-bearing for the claim: a named building, an identifiable military vehicle/weapon class, a specific geographic location. The downloaded reference gives NBP a visual anchor for that thing.
- **Cap: 1 reference per claim** in the first Round 4 implementation. If the smoke test reveals NBP supports N>1 cleanly (see trap #23), this cap may be raised later.
- **Reject references that would bias the composition**. If the researcher downloaded a heroic low-angle shot of a warship but your composition is overhead-drone, don't attach — the reference would fight the composition.
- **Check that the file exists.** List `$OUTPUT_DIR/references/claim_<id>/` via `Bash` before picking. If the researcher's list in `claim.reference_images_start` contains a path, verify the file is actually there; skip paths that aren't on disk.

Output: set `reference_images: ["<absolute path>", ...]` on the claim (0 or 1 entries). For `start_end` claims, use the SAME reference_images list for both endpoints of the morph (consistency across the morph requires consistent anchor).

If no appropriate reference exists, set `reference_images: []` — this is the correct answer most of the time.

### 8. Pacing hints for the Shot Planner
```

Note the renumber: the old section 7 becomes section 8.

- [ ] **Step 2: Update the example claim schema**

Find the JSON example around line 141-154 starting with `"claim_id": 3`. Use `Edit` to add the `reference_images` field.

OLD (exact match — tail of the example):

```json
  "estimated_duration_class": "long",
  "groupable_with_next": false
}
```

NEW:

```json
  "estimated_duration_class": "long",
  "groupable_with_next": false,
  "reference_images": []
}
```

- [ ] **Step 3: Update the DONE report format**

OLD (exact match):

```
cinematic_technique_distribution: {"synecdoche": 2, "juxtaposition": 1, "literal": 3, ...}
total_images_to_gen: <sum of image slots>
```

NEW:

```
cinematic_technique_distribution: {"synecdoche": 2, "juxtaposition": 1, "literal": 3, ...}
total_images_to_gen: <sum of image slots>
claims_with_references: <count of claims where reference_images is non-empty>
```

- [ ] **Step 4: Add a "Never" rule about references**

Find the "## Never" section. Append a new bullet at the end of the list:

```markdown
- Never attach a reference image that isn't actually on disk. The Visual Researcher's `reference_images_start` list may contain paths that failed to download — verify each with `[[ -f "$PATH" ]]` before adding to your output.
- Never attach more than 1 reference per claim in Round 4. Raise this cap only after `traps.md #23` is updated with a verified multi-attach mechanism.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add agents/creative-director.md
git commit -m "feat(creative-director): per-claim reference_images selection (Round 4)"
```

---

## Task 5: Extend `shot-planner` to copy `reference_images` into image slots

**Files:**
- Modify: `agents/shot-planner.md`

- [ ] **Step 1: Update the JSON example in Step 5 to include `reference_images`**

Find the example at line 74-107 starting with `"id": 1`. Use `Edit` on the image slot body:

OLD (exact match):

```json
  "images": {
    "start": {
      "concept_prompt": "<same as claim.concept_prompt_start — already research-enriched>",
      "style_prompt": null,
      "prompt": null,
      "reference_urls": "<same as claim.reference_urls_start, or [] if missing>",
      "research_notes": "<same as claim.research_notes_start, or empty string>",
      "variants": [],
      "selected_variant": null,
      "status": "queued",
      "attempts": 0,
      "reviews": []
    }
  },
```

NEW:

```json
  "images": {
    "start": {
      "concept_prompt": "<same as claim.concept_prompt_start — already research-enriched>",
      "style_prompt": null,
      "prompt": null,
      "reference_urls": "<same as claim.reference_urls_start, or [] if missing>",
      "research_notes": "<same as claim.research_notes_start, or empty string>",
      "reference_images": "<same as claim.reference_images, or [] if missing — CD-picked files, NOT the researcher's candidate list>",
      "variants": [],
      "selected_variant": null,
      "status": "queued",
      "attempts": 0,
      "reviews": []
    }
  },
```

- [ ] **Step 2: Update the `start_end` note**

Find the paragraph immediately after the JSON example starting with `For \`start_end\` shots, \`images\` has both \`start\` and \`end\` keys`. Use `Edit`:

OLD (exact match):

```markdown
For `start_end` shots, `images` has both `start` and `end` keys. Each carries its own `concept_prompt` (from the matching claim field) + `reference_urls` + `research_notes` + an empty `variants` array.
```

NEW:

```markdown
For `start_end` shots, `images` has both `start` and `end` keys. Each carries its own `concept_prompt` (from the matching claim field) + `reference_urls` + `research_notes` + an empty `variants` array. **Both `start` and `end` share the same `reference_images` list** — a morph needs a consistent visual anchor at both endpoints. Copy `claim.reference_images` into BOTH image slots unchanged.
```

- [ ] **Step 3: Add a "Never" rule**

Find the "## Never" section at the bottom. Append a new bullet:

```markdown
- Never split `claim.reference_images` unevenly across a morph's `start` and `end` slots. Both must carry the same list.
```

- [ ] **Step 4: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add agents/shot-planner.md
git commit -m "feat(shot-planner): copy reference_images from claim to both image slots"
```

---

## Task 6: Rewrite `image-worker` for single-tab burst with preflight checklist

**Files:**
- Modify: `agents/image-worker.md` (full rewrite — replaces existing content entirely except frontmatter)

This is the largest task. The new worker is a full replacement of the Round 3 worker. The old file is 265 lines; the new one will be similar.

- [ ] **Step 1: Back up the old frontmatter**

Read the first 6 lines of `agents/image-worker.md` (YAML frontmatter). You'll replace the `description` and keep everything else.

- [ ] **Step 2: Write the new file**

Use the `Write` tool to replace the entire file contents with:

````markdown
---
name: image-worker
description: Single-tab burst image submission. Owns the `image` tab. Loops {preflight → fix → submit} across the whole image task list, per-check retry counters capped at 5, pause-and-exit on exhaustion. Polls the gallery after burst to download renders. Round 4.
tools: Bash, Read, Write, mcp__playwright__browser_navigate, mcp__playwright__browser_tabs, mcp__playwright__browser_evaluate, mcp__playwright__browser_snapshot, mcp__playwright__browser_wait_for, mcp__playwright__browser_press_key, mcp__playwright__browser_type, mcp__playwright__browser_file_upload
model: haiku
---

# Image Worker (Round 4 — single tab, burst, preflight checklist)

You OWN the single `image` Chrome tab. The orchestrator navigated it to `/ai/image?model=nano-banana-pro` and verified baseline state. You receive the full list of queued image tasks for the project. You loop through them, running a 5-item preflight checklist before each Generate click, auto-remediating failures with per-check retry counts capped at 5, then pausing with a diagnostic if any check stays stuck. After all submits are in-flight, you poll the gallery, download each render as it lands, and record it as a single-entry `variants` array with `selected_variant=0`.

You do NOT review, retry-rewrite, or spawn other workers. That's the orchestrator + reviewer + prompt-writer's job.

## Inputs (from dispatch message)

- `OUTPUT_DIR`: project output dir (absolute)
- `SHOTS_PATH`: absolute path to `shots.json`
- `TASKS`: JSON array of `{shot_id, role}` pairs for all image slots with `status=queued` (in shot-id then role-sorted order)
- `PROJECT_ASPECT`: `"16:9"` / `"9:16"` / `"1:1"` (from frontmatter)
- `SKILL_ROOT`: `/Users/khaled/.claude/skills/higgsfield`
- `SLUG`: project slug (for log tags)

## Constants

```
PER_CHECK_RETRY_CAP = 5
POLL_INTERVAL_S = 10
POLL_TIMEOUT_S_PER_TASK = 120
```

## Preflight checklist (per task, before Generate)

Five checks, executed in order. Each has an independent retry counter (counted per task). If any check hits the cap, pause-and-exit for that task.

### Check 1 — Model

**Pass**: `window.location.pathname === '/ai/image'` AND `URLSearchParams(window.location.search).get('model') === 'nano-banana-pro'`.

**Fix**: `browser_navigate url=https://higgsfield.ai/ai/image?model=nano-banana-pro` then `browser_wait_for time=2`.

### Check 2 — Unlimited

**Pass** (both must hold):
- `document.querySelector('[role="switch"]').getAttribute('data-state') === 'on'`
- `document.getElementById('hf:image-form-submit').textContent.includes('Unlimited')` (the label reads `Unlimited ✨` — not `Generate ✨ N`)

**Fix**: click the switch, wait 300ms, re-read. If the label STILL shows a credit cost after the switch visually flips ON, that's trap-22 sticky state — `browser_navigate` same URL (reload), wait 2s, re-preflight from check 1.

### Check 3 — Aspect ratio

**Pass**: `JSON.parse(localStorage.getItem('hf:nano-banana-2-image-form-3')).aspect_ratio === PROJECT_ASPECT`.

**Fix** (reload-required — this is why aspect runs before prompt and refs):

```js
(aspect) => {
  const k = 'hf:nano-banana-2-image-form-3';
  const cur = JSON.parse(localStorage.getItem(k) || '{}');
  cur.aspect_ratio = aspect;
  cur.quality = '2k';
  cur.use_unlimited = true;
  cur.batch_size = 1;
  cur.use_seedream_bonus = false;
  localStorage.setItem(k, JSON.stringify(cur));
  return true;
}
```

Then `browser_navigate` same URL, `browser_wait_for time=2`, re-preflight from check 1 (aspect fix clobbers prompt and any attached refs — later checks must re-run).

### Check 4 — Prompt

**Pass**: `document.querySelector('[contenteditable="true"][role="textbox"]').textContent.slice(0, 80)` head-matches the expected prompt's first 80 chars (ignoring trailing whitespace).

**Fix** (trap #10b — use native fill, not `execCommand` or `innerHTML=''`):

1. Focus the editor: `browser_evaluate` → `document.querySelector('[contenteditable="true"][role="textbox"]').focus()`
2. `browser_press_key key="ControlOrMeta+a"`
3. `browser_press_key key="Backspace"`
4. `browser_type element=<editor selector> text=<FULL_PROMPT> slowly=true`

Where FULL_PROMPT = `concept_prompt + ", " + style_prompt` loaded via:

```bash
CONCEPT=$(python3 "$SKILL_ROOT/engine/shot_state.py" get "$SHOTS_PATH" $SHOT_ID "images.$ROLE.concept_prompt")
STYLE=$(python3 "$SKILL_ROOT/engine/shot_state.py" get "$SHOTS_PATH" $SHOT_ID "images.$ROLE.style_prompt")
FULL_PROMPT="$CONCEPT, $STYLE"
```

Re-verify after fill.

### Check 5 — Reference images (skip if empty)

Load the required set:

```bash
REFS=$(python3 "$SKILL_ROOT/engine/shot_state.py" get "$SHOTS_PATH" $SHOT_ID "images.$ROLE.reference_images")
# REFS is a JSON array of absolute paths, possibly []
```

If `REFS == "[]"`, skip this check entirely — also run a "no stale" check: if the attached-chip list is non-empty, remove all chips. Then proceed to Generate.

**Pass**: the composer's attached-file set (by filename) equals the basename-set of `REFS`.

**Fix** (exact selectors from `references/traps.md` #23 — fill in after smoke test):

For each chip whose filename isn't in the required set → click its remove-X:

```js
// TEMPLATE — replace CHIP_SELECTOR and REMOVE_BTN_SELECTOR with values from trap #23
(requiredBasenames) => {
  const chips = Array.from(document.querySelectorAll('<CHIP_SELECTOR>'));
  for (const chip of chips) {
    const name = chip.querySelector('<FILENAME_SELECTOR>')?.textContent?.trim();
    if (!name || !requiredBasenames.includes(name)) {
      chip.querySelector('<REMOVE_BTN_SELECTOR>')?.click();
    }
  }
  return Array.from(document.querySelectorAll('<CHIP_SELECTOR>')).length;
}
```

For each required path not yet attached → attach via the mechanism recorded in trap #23:

```js
// TEMPLATE — if trap #23 says drag-drop into DROP_ZONE
async (path, bytes_b64, mime) => {
  const buf = Uint8Array.from(atob(bytes_b64), c => c.charCodeAt(0));
  const file = new File([buf], path.split('/').pop(), { type: mime });
  const dt = new DataTransfer();
  dt.items.add(file);
  const dropZone = document.querySelector('<DROP_ZONE_SELECTOR>');
  dropZone.dispatchEvent(new DragEvent('dragenter', { dataTransfer: dt, bubbles: true }));
  dropZone.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true }));
  await new Promise(r => setTimeout(r, 400));
  return true;
}
```

(If trap #23 says file-input is the mechanism, use `browser_file_upload` on the `<input type="file">` selector instead — simpler.)

Bytes are loaded via `base64 < $PATH` in the bash call that invokes `browser_evaluate`.

Re-verify chip list after all attaches.

## Control flow

```
INIT:
  browser_tabs action=select, name=image     # or index, whichever the orchestrator set up
  tasks = TASKS (from dispatch)
  submitted = []          # list of {shot_id, role, submit_ts}
  paused = null           # set to {shot_id, role, check, observed, attempts} on exhaustion

BURST SUBMIT LOOP:
  for task in tasks:
      attempts = {model:0, unlimited:0, aspect:0, prompt:0, refs:0}
      while True:
          failures = run_preflight(task)     # returns list of (check, observed, expected)
          if failures is empty:
              # All checks pass. Submit.
              record attempt:
                python3 $SKILL_ROOT/engine/shot_state.py update "$SHOTS_PATH" $SHOT_ID \
                    "images.$ROLE.attempts=$((ATT+1))" \
                    "images.$ROLE.status=submitting"
              click Generate via browser_evaluate:
                  document.getElementById('hf:image-form-submit').click()
              submit_ts = ISO timestamp at click
              submitted.append({shot_id, role, submit_ts})
              python3 $SKILL_ROOT/engine/shot_state.py update "$SHOTS_PATH" $SHOT_ID \
                  "images.$ROLE.status=rendering" \
                  "images.$ROLE.submitted_at=$submit_ts"
              wait 1s   # lets NBP's server-queue accept before the next preflight
              break     # next task
          # preflight had at least one failure
          for fail in failures:
              attempts[fail.check] += 1
              append engine log:
                "{timestamp} shot={shot_id} role={role} check={fail.check} attempt={attempts[fail.check]} observed={fail.observed}"
              if attempts[fail.check] > PER_CHECK_RETRY_CAP:
                  paused = {shot_id, role, check: fail.check, observed: fail.observed, attempts_log: [...]}
                  break out of everything — jump to PAUSE
              remediate(fail.check)
          if paused: break

  if paused:
      # Skip poll phase; go directly to PAUSE handling.

POLL & DOWNLOAD (if not paused):
  pending = submitted (as a set)
  start = now()
  budget = len(submitted) * POLL_TIMEOUT_S_PER_TASK
  while pending and (now - start) < budget:
      # Query gallery for thumbnails with ts >= earliest pending submit_ts
      thumbs = browser_evaluate:
          () => Array.from(document.querySelectorAll('img[alt="image generation"]'))
              .map(img => {
                  const m = img.src.match(/hf_(\\d{8}_\\d{6})_([a-f0-9-]{36})_min\\.webp/);
                  return m ? { src: img.src, ts: m[1], uuid: m[2] } : null;
              })
              .filter(Boolean);

      for each thumb (ordered by ts ascending):
          # Match thumb to earliest pending task whose submit_ts <= thumb.ts
          task = pending.find(t => t.submit_ts <= thumb.ts_as_iso)
          if not task: continue
          # Download full-res asset
          NN=$(printf "%02d" ${task.shot_id})
          BASE=$(echo "$thumb.src" | sed -E 's|/hf_.+|/|')
          curl -sS -L --retry 3 -o "$OUTPUT_DIR/shots/shot${NN}_${task.role}.webp" "${BASE}hf_${thumb.ts}_${thumb.uuid}_min.webp"
          ffmpeg -v error -y -i "$OUTPUT_DIR/shots/shot${NN}_${task.role}.webp" "$OUTPUT_DIR/shots/shot${NN}_${task.role}.png"
          # Record single-entry variants with selected_variant=0
          python3 - <<PY
          import json, pathlib
          p = pathlib.Path("$SHOTS_PATH")
          shots = json.loads(p.read_text())
          for s in shots:
              if s["id"] == ${task.shot_id}:
                  img = s["images"]["${task.role}"]
                  img["variants"] = [{"artifact_path": "$OUTPUT_DIR/shots/shot${NN}_${task.role}.png", "artifact_asset_id": "${thumb.uuid}"}]
                  img["selected_variant"] = 0
                  img["status"] = "rendered"
                  img["submitted_at"] = None
                  break
          tmp = p.with_suffix(".tmp")
          tmp.write_text(json.dumps(shots, indent=2, ensure_ascii=False))
          tmp.rename(p)
          PY
          pending.remove(task)
      sleep POLL_INTERVAL_S

PAUSE (if paused is set):
  # Write ### Q: to project note. Set status=paused in frontmatter.
  # The orchestrator passes the project note path as an implicit — derive it:
  PROJECT_NOTE="$(dirname $(dirname "$OUTPUT_DIR"))/hf-projects/Projects/${SLUG}.md"

  # Append under ## Questions using the existing update_region pattern — or use a direct append if no helper exists.
  cat >> "$PROJECT_NOTE" <<EOF

### Q: Shot ${paused.shot_id} ${paused.role} preflight stuck on ${paused.check} after ${PER_CHECK_RETRY_CAP} attempts

Check: ${paused.check}
Expected: <expected value for this check>
Observed across attempts:
$(format attempts_log as bullet list)

I've tried auto-remediation ${PER_CHECK_RETRY_CAP}× and the UI isn't cooperating. Please help by one of:
- **Fix it in the tab**, then reply \`### A: fixed <one-line description of what was wrong>\`
- **Generate shot ${paused.shot_id} ${paused.role} manually** and save PNG at \`$OUTPUT_DIR/shots/shot$(printf %02d ${paused.shot_id})_${paused.role}.png\`, then \`### A: accept <path>\`
- **Change the prompt**: \`### A: edit prompt: <new concept prompt>\`
- **Drop this shot**: \`### A: skip shot ${paused.shot_id}\`
EOF

  # Flip status in frontmatter via the existing update_status.py helper:
  python3 "$SKILL_ROOT/engine/update_status.py" "$PROJECT_NOTE" paused

REPORT:
  if paused:
      echo "PAUSED"
      echo "shot_id: ${paused.shot_id}"
      echo "role: ${paused.role}"
      echo "stuck_check: ${paused.check}"
      echo "submitted_before_pause: $(wc -l <<< submitted)"
  else:
      echo "DONE"
      echo "mode: burst"
      echo "submitted: ${len(TASKS)}"
      echo "rendered: ${len(TASKS) - len(pending)}"
      echo "timed_out: ${len(pending)}"
      echo "elapsed_s: $(elapsed)"
```

## Never

- Never click Generate without running ALL 5 preflight checks. The checklist is the point of Round 4 — skipping it reverts to Round 3 failure modes.
- Never retry a preflight check beyond PER_CHECK_RETRY_CAP on a single task. Paul-ing (pause + log) is always the correct action at the cap.
- Never use `fill()` / `browser_type slowly=false` / `execCommand('delete')` / `innerHTML=''` to clear the Lexical editor — see trap #10b. Use `Ctrl+A` + `Backspace` + `browser_type slowly=true`.
- Never change the prompt via paste-event dispatch — use native Playwright type.
- Never download a thumbnail without matching its timestamp to a task in `submitted`. Stray thumbnails (from earlier sessions or the orchestrator's sanity-check submit) will mis-attribute.
- Never touch the Unlimited toggle mid-poll. Only during preflight for a specific task.
- Never modify shots you weren't given in TASKS.
- Never assume reference-image attachments persist across submits. Re-verify attached set on every task.
- Never write the `paused` state without flipping frontmatter `status: paused` via `update_status.py` — the orchestrator's resume intake relies on this.
- Never exit cleanly while `pending` still has entries AND budget isn't exhausted. Keep polling.
````

- [ ] **Step 3: Run a smoke parse of the file**

`head -6 agents/image-worker.md` should show valid YAML frontmatter. `grep -c "^## " agents/image-worker.md` should return a plausible section count (≥3).

- [ ] **Step 4: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add agents/image-worker.md
git commit -m "feat(image-worker): Round 4 single-tab burst with preflight checklist"
```

---

## Task 7: Update SKILL.md Phase 0 — remove tab pre-warm

**Files:**
- Modify: `SKILL.md` (Phase 0 section around line 97-114)

- [ ] **Step 1: Locate the Phase 0 section**

Open SKILL.md. Phase 0 starts at `### Phase 0 — Intake + parallel precompute`. The tab pre-warm is referenced in the "Tab pre-warming" subsection around line 207-220 (inside Phase 4), NOT in Phase 0 directly. Phase 0 just says "kicks off tab pre-warming for that many tabs, capped at 10". Find that phrasing:

- [ ] **Step 2: Remove pre-warm bullet from Phase 0**

Use `Edit`:

OLD (exact match):

```markdown
7. Write the script text from frontmatter's `vo.script` field to `$OUTPUT_DIR/script.txt` — needed by BOTH Phase 1 (audio page fill) and Phase 2.5 (creative-director input).
```

NEW:

```markdown
7. Write the script text from frontmatter's `vo.script` field to `$OUTPUT_DIR/script.txt` — needed by BOTH Phase 1 (audio page fill) and Phase 2.5 (creative-director input).

8. **Round 4**: open (or reuse) the single `image` Chrome tab — no N-tab pre-warm loop anymore. Navigate it to `https://higgsfield.ai/ai/image?model=nano-banana-pro`. Don't verify Unlimited/aspect yet; the image-worker's preflight handles that per task. One tab is enough because Round 4's image-worker submits sequentially in a burst, and server-side render parallelism doesn't depend on client-tab count.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add SKILL.md
git commit -m "feat(skill): Phase 0 — single image tab, drop N-tab pre-warm"
```

---

## Task 8: Rewrite SKILL.md Phase 4 for single-tab burst

**Files:**
- Modify: `SKILL.md` — Phase 4 section (from `### Phase 4 — Image burst + BATCH_PICK review + BATCH_RETRY (Round 3)` to the start of `### Phase 6 — Stitch`)

This is a large section replacement. Phase 4 runs from roughly line 203 to line 340 (where `### Phase 6 — Stitch` begins — note Phase 5 is currently folded into Phase 4's pipelined block in the current doc).

- [ ] **Step 1: Read the existing Phase 4 block**

Run `Read` with offset=203, limit=140 to see the full current section.

- [ ] **Step 2: Replace the Phase 4 + embedded Phase 5 section**

Use `Edit` with the OLD block being the entire section from `### Phase 4 — Image burst + BATCH_PICK review + BATCH_RETRY (Round 3)` up to (but NOT including) `### Phase 6 — Stitch (manifest already templated in Phase 3.5)`.

NEW content:

````markdown
### Phase 4 — Single-tab burst images + BATCH_PICK review + BATCH_RETRY (Round 4)

Round 4 collapses Phase 4 into a single NBP tab driven by ONE burst worker (Haiku). The worker runs a 5-item preflight checklist before each Generate click (model, unlimited, aspect, prompt, reference_images), auto-remediates failures with per-check retry counts capped at 5, and pauses with a self-learning hook on exhaustion. The reviewer still runs in BATCH_PICK mode, but `batch_size=1` means each submission produces exactly one variant — BATCH_PICK just confirms pass/fail across the set.

#### Step-by-step orchestration

1. **Dispatch one `image-worker` (Haiku)** with the full task list:
   - `TASKS` = all `(shot_id, role)` pairs where `images.<role>.status == "queued"`, sorted by shot_id then role (start before end).
   - `OUTPUT_DIR`, `SHOTS_PATH`, `PROJECT_ASPECT` (from frontmatter), `SKILL_ROOT`, `SLUG`.
   - Worker attaches to the pre-opened `image` tab, loops submit-with-preflight across all tasks, then polls+downloads until the gallery drains.

2. **Wait for worker DONE or PAUSED.**

   **On PAUSED**: the worker has already appended `### Q:` to the project note and flipped `status: paused`. Surface the question to the user as a plain message ("Phase 4 paused on shot N preflight failure — check project note"), exit the orchestration turn cleanly. User re-invokes `run <slug>` after writing `### A: ...`; intake re-dispatches the burst worker for remaining queued tasks. Self-learn hook fires on resume if `### A: fixed <reason>` (see Self-learning routing table in § "Self-learning rules" below).

   **On DONE**: continue.

3. **Dispatch one BATCH_PICK `image-reviewer`** across all rendered tasks (same as Round 3). It evaluates each single variant against the rubric and flips `status=pass` or `status=fail` per image.

4. **If any images failed**: dispatch ONE `prompt-writer` in BATCH_RETRY mode to rewrite all failed concept_prompts in one agent call. Reset failed images to `status=queued`, `variants=[]`, `selected_variant=null`. Then re-dispatch a fresh burst worker with only the failed tasks. Repeat up to `retries_per_shot` times; cap-hit → escalate via `## Questions`.

   Usually the first burst clears most images. Retries are 0-2 shots.

5. **Manifest filling** (unchanged): as video clips download later, fill in `manifest_template.json`'s clip paths in place.

#### Phase 5 — Videos (simplified from Round 3 — no stream pipelining with Phase 4)

In Round 4, videos wait until ALL Phase 4 images are reviewed (all `status=pass`). No more "start video-worker as each image passes individually" — that pipelining added ~15-20s of overlap but required a polling pattern that Round 4 deliberately avoids.

After Phase 4 reports all images `pass`:

1. Dispatch up to 6 `video-worker` subagents in one message (one per shot), each owning a Kling 3.0 composer tab. Each worker reads its shot's selected variant's asset UUID:

   ```bash
   START_UUID=$(python3 $SKILL_ROOT/engine/shot_state.py selected_variant "$SHOTS_PATH" <id> start artifact_asset_id)
   END_UUID=$(python3 $SKILL_ROOT/engine/shot_state.py selected_variant "$SHOTS_PATH" <id> end artifact_asset_id)  # if start_end
   ```

2. Video flow identical to Round 3: localStorage priming (`flow-create-video-<date>` + `hf:video-kling-3-store:v2`), reload, preflight, Generate.

3. Stream review per completion (unchanged — video-reviewer dispatches per video as clips finish).

4. Retries follow the same pattern as Round 3.

#### Timeline for a 6-shot / 8-image project (Round 4)

```
t=0    Intake + style string + script.txt + single image tab opened    5s
t=5    VO gen (45s)                                         ──┐
t=5    Creative Director (40s)                              ──┤ PARALLEL
t=5    (no N-tab warmup anymore — single tab ready at t=5)    ┘
t=45   Creative Director DONE → claims.json
t=45   Research A + B dispatched (parallel on claims.json)  ─┐
                                                              │ PARALLEL
t=50   VO downloaded                                          │
t=57   Whisper starts                                         │
t=70   Research DONE → claims.json enriched (+ ref images)   ─┘
t=82   Whisper DONE → beats.json
t=82   Shot Planner (15s)
t=97   shots.json + style injected + manifest template ready
─────────────────────── BURST IMAGES ────────────────────────
t=97   Image-worker dispatched with TASKS array
t=100  First preflight passes, Generate clicked
t=102  Second preflight + Generate
t=104  ...
t=124  All 8 submits in-flight (8 × ~3s = 24s)
t=124  Render phase (server-side parallel)                    ~60-90s
t=200  All 8 variants downloaded
t=200  BATCH_PICK reviewer dispatched
t=218  Review DONE — 6 passed, 2 failed
─────────────────────── RETRY (if needed) ──────────────────
t=218  BATCH_RETRY prompt-writer rewrites 2 prompts           ~10s
t=228  2 retry tasks sent in new burst wave                   ~8s
t=236  2 retry renders                                         ~60-90s
t=290  BATCH_PICK on retries                                   ~5s
t=295  All images passed
─────────────────────── VIDEOS ──────────────────────────────
t=295  6 video-workers dispatched in parallel
t=300  6 videos rendering                                      ~120s
t=420  Stream video reviews running
t=440  All videos DONE + reviewed
t=440  Manifest fill → stitch (15s)
t=455  DONE (≈7.6 min)
```

Without retries: ~5.8 min. Hard floor (VO + Whisper + NBP + Kling + burst sequential submits + dispatch overhead) is ~4.8 min.

Round 4 is ~15-20s slower than Round 3 on the happy path. The tradeoff is single-tab simplicity, per-shot preflight validation, and built-in pause-and-self-learn for UI drift.

#### Rate-limit handling

If the burst worker reports `BLOCKED: suspected_rate_limit` on Generate click, it pauses for 30s, then resumes. If the block persists for >3 consecutive submissions, it exits with PAUSED and surfaces the rate-limit to the user.

#### Status vocabulary (Round 4 — unchanged from Round 3)

`images.<role>.status` values in order:
1. `queued` — ready for the burst worker to submit
2. `submitting` — worker is clicking Generate
3. `rendering` — Generate clicked, server-side render in progress
4. `rendered` — variant downloaded, awaiting reviewer
5. `pass` — reviewer PASS, `selected_variant` set (always 0 with `batch_size=1`)
6. `fail` — reviewer FAIL; retry (→ `queued`) or escalate
7. `escalated` — retry cap hit

`video.status` values: `queued` / `claimed_<TAB_INDEX>` / `submitting` / `rendering` / `rendered` / `pass` / `fail` / `escalated` (unchanged).

Each `images.<role>` also has:
- `variants`: `[{artifact_path, artifact_asset_id}]` — single-entry array populated by worker.
- `selected_variant`: `0` — pre-set by worker (nothing to pick between at `batch_size=1`).
- `reference_images`: array of absolute paths (from CD via shot-planner). May be empty.

#### Key invariants preserved

- Every image still passes the image-reviewer rubric before its video is submitted.
- Retry count per shot is unchanged (`retries_per_shot` from frontmatter, default 5).
- Every video still passes the preflight checklist before Generate is clicked.
- Stitcher still trims non-last clips to exact float `shot.duration` and last clip still gets its +1s tail.
- Shot durations still sum to VO_DURATION exactly.
- Technique-variety rule still enforced (Creative Director side).
- No "no text / no logos" in concept_prompts.
````

- [ ] **Step 3: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add SKILL.md
git commit -m "feat(skill): Phase 4 — single-tab burst + simplified Phase 5 (Round 4)"
```

---

## Task 9: Update SKILL.md parallel-dispatch rules, self-learning routing, and prose

**Files:**
- Modify: `SKILL.md` — "Parallel dispatch rules" subsection + "Self-learning rules" routing table + "Round 3 architectural principle" prose update.

- [ ] **Step 1: Update the "Parallel dispatch rules" bullets**

Find the section containing these bullets (around line 394-405). Use `Edit` on the Phase 4 bullet:

OLD (exact match):

```markdown
- **Phase 4 image burst (Round 3 flagship)**: after Shot Planner, dispatch N image-workers (N = total_image_tasks, up to 10) in ONE orchestrator message. Each worker owns its own pre-warmed tab and one image task. All N click Generate within ~4s of each other → true parallel renders.
- **BATCH_PICK review**: ONE `image-reviewer` dispatch reviews all N images together (evaluates both variants per image, picks best). Replaces stream SINGLE reviews.
- **BATCH_RETRY prompt rewrite**: if reviewer returns ≥2 failures, ONE `prompt-writer` dispatch in BATCH_RETRY mode rewrites all failed prompts in a single agent call.
- **Stream video reviews**: `video-reviewer` SINGLE dispatched per video completion (same as Round 2).
- **Tab pre-warming**: kicked off during Phase 0 as background work. Count tabs to `min(total_image_tasks, 10)`. Not a subagent dispatch — direct browser commands.
```

NEW:

```markdown
- **Phase 4 burst (Round 4)**: ONE `image-worker` dispatch with the full TASKS array. The worker owns the single `image` tab and loops submit-with-preflight sequentially. No more N-workers-in-parallel dispatch. Orchestrator is free during the ~100s the worker runs.
- **BATCH_PICK review**: ONE `image-reviewer` dispatch across all rendered tasks (with `batch_size=1`, it confirms pass/fail per image rather than picking between variants).
- **BATCH_RETRY prompt rewrite**: if reviewer returns ≥1 failure, ONE `prompt-writer` dispatch in BATCH_RETRY mode rewrites all failed prompts. Orchestrator then re-dispatches a burst worker with only the failed tasks.
- **Stream video reviews**: `video-reviewer` SINGLE dispatched per video completion (unchanged).
- **Tab pre-warming**: removed. Single `image` tab opened during Phase 0 intake.
```

- [ ] **Step 2: Update the "Round 2 architectural principle" prose**

Find the paragraph starting with "**Round 2 architectural principle — maximize overlap.**". Use `Edit`:

OLD (exact match):

```markdown
**Round 2 architectural principle — maximize overlap.** The slow server-side operations (VO gen ~45s, NBP render ~60s, Kling render ~120s) are hard floors. Everything else — creative planning, style building, tab setup, research, reviews — must overlap them rather than stack serially. Target total time for a 6-shot project: ~5–6 min (vs ~19 min pre-optimization).
```

NEW:

```markdown
**Architectural principle — maximize overlap (carried forward from Round 2).** The slow server-side operations (VO gen ~45s, NBP render ~60s, Kling render ~120s) are hard floors. Everything else — creative planning, style building, research, reviews — must overlap them rather than stack serially. Round 4 additionally runs preflight per submission to catch UI drift (wrong model page, Unlimited toggle flipped off, aspect ratio reverted, stale prompt, missing reference) before it costs a wasted render or a silent miscount. Target total time for a 6-shot project with clean preflights: ~5.5–6 min (Round 3: ~5.3–6 min; Round 4 trades ~15s of parallelism for per-submit validation + pause-and-learn).
```

- [ ] **Step 3: Extend the self-learning routing table**

Find the "## Self-learning rules (skill auto-edit)" section, then the "### Destination routing" subsection with the routing table.

Use `Edit` to append rows to the table:

OLD (exact match):

```markdown
| Session-wide rule | `SKILL.md` "Current model availability" | `<!-- auto-edit:skill section=availability -->` |
| User preference revealed mid-run | memory system | new file under `memory/` + MEMORY.md index |
```

NEW:

```markdown
| Session-wide rule | `SKILL.md` "Current model availability" | `<!-- auto-edit:skill section=availability -->` |
| User preference revealed mid-run | memory system | new file under `memory/` + MEMORY.md index |
| Preflight `model` failure resolved | `references/traps.md` | `<!-- auto-edit:traps category=ui-discovery -->` |
| Preflight `unlimited` failure resolved | `references/traps.md` | `<!-- auto-edit:traps category=cost -->` |
| Preflight `aspect` failure resolved | `references/traps.md` | `<!-- auto-edit:traps category=ui-commit -->` |
| Preflight `prompt` failure resolved | `references/traps.md` | `<!-- auto-edit:traps category=session-state -->` |
| Preflight `refs` failure resolved | `references/traps.md` | `<!-- auto-edit:traps category=nbp-multimodal -->` |
```

- [ ] **Step 4: Update the "Pause / resume via the note" section**

Find the paragraph that currently handles pause-and-resume (inside "Engine mode" → "Mode dispatch" area, around line 82-90 or similar). Verify the existing pause protocol covers preflight exhaustion; if it doesn't mention preflight explicitly, add a sentence. Use `Edit`:

Find:

```markdown
- **Pause**: append `### Q: <question>` under `## Questions`, set `status: paused`, `browser_close`, print a clear instruction to the user, exit the current orchestration. Do NOT poll.
```

Replace with:

```markdown
- **Pause**: append `### Q: <question>` under `## Questions`, set `status: paused`, `browser_close`, print a clear instruction to the user, exit the current orchestration. Do NOT poll. Round 4 adds a new pause trigger: the image-worker's preflight checklist hitting its per-check retry cap; the answer format `### A: fixed <reason>` additionally triggers the self-learning routing table (writing a new trap entry to `references/traps.md`).
```

- [ ] **Step 5: Commit**

```bash
cd /Users/khaled/.claude/skills/higgsfield
git add SKILL.md
git commit -m "docs(skill): Round 4 parallel-dispatch rules + self-learning routing"
```

---

## Task 10: End-to-end smoke run against a small project

**Files:**
- Create: a minimal test project in `$PWD/hf-projects/Projects/round4-smoke.md`
- No code changes — this is the final verification.

- [ ] **Step 1: Bootstrap the Obsidian vault if not already**

```bash
cd "$PWD"
bash /Users/khaled/.claude/skills/higgsfield/engine/init_vault.sh
```

- [ ] **Step 2: Create a small test project**

Write `hf-projects/Projects/round4-smoke.md`:

```markdown
---
slug: round4-smoke
status: inbox
aspect: 16:9
shots: []
vo:
  model: eleven-v3
  voice: Adam
  script: "The F-15 Eagle takes off at dawn. It climbs above the clouds. Mission complete."
retries_per_shot: 5
schedule: null
---

## Style notes
cinematic moody, warm sunrise palette, shallow DOF, photoreal, no text, no numbers, no logos

## Questions

<!-- engine:begin -->
<!-- engine:end -->

## Outputs

## Auto-edits made during this run
```

- [ ] **Step 3: Invoke the engine on the smoke project**

In Claude Code, type: `run round4-smoke`

The orchestrator should:
1. Intake — parse frontmatter, flip to `active`.
2. Dispatch VO + Creative Director in parallel.
3. Research (likely 0-1 references for this simple script).
4. Whisper + Shot Planner → 3 shots.
5. Open the single image tab.
6. Dispatch ONE burst worker with 3 TASKS (assuming all `start_only`).
7. Worker preflight → submit → preflight → submit → preflight → submit (~10s).
8. Poll gallery ~60-90s.
9. Download + record 3 variants.
10. BATCH_PICK reviewer.
11. If pass → Phase 5.
12. End-to-end to `final.mp4`.

- [ ] **Step 4: Verify expected artifacts**

After the run (or at pause), check:

```bash
# All three image variants exist
ls hf-outputs/round4-smoke/shots/shot0{1,2,3}_start.png

# shots.json has status=pass for all 3
python3 -c "import json; shots=json.load(open('hf-outputs/round4-smoke/shots.json')); print([(s['id'], s['images']['start']['status']) for s in shots])"
# Expected: [(1, 'pass'), (2, 'pass'), (3, 'pass')] or similar with possible 'rendered' if reviewer hadn't run yet

# No N-worker dispatch log
grep -c "image-worker" hf-projects/_runs/*-round4-smoke.md
# Expected: small number (1-2 dispatches, not 3+)
```

- [ ] **Step 5: Verify no regressions elsewhere**

Run the engine test suite:

```bash
bash /Users/khaled/.claude/skills/higgsfield/engine/tests/run_all.sh
```

Expected: all tests pass (including the new `test_reference_downloader.sh`).

- [ ] **Step 6: Commit the smoke-project evidence (optional)**

If the run produced a useful `_runs/` log showing the Round 4 flow, add a one-line note in the skill's CHANGELOG section of SKILL.md or leave uncommitted (the project note is user data, not part of the skill repo).

---

## Self-review (plan author — after writing)

### Spec coverage

- [x] § 1 Architecture + tab lifecycle → Task 7 (Phase 0 pre-warm removal) + Task 6 (single-tab worker) + Task 8 (Phase 4 rewrite)
- [x] § 2 Preflight checklist → Task 6 (all 5 checks in image-worker)
- [x] § 3 Worker control flow → Task 6
- [x] § 4 Pause / resume semantics → Task 6 (PAUSE section) + Task 9 (SKILL.md pause prose)
- [x] § 5 Self-learning hook → Task 9 (routing table additions)
- [x] § 6 Reference-image attachment mechanism → Task 1 (smoke test) + Task 2 (downloader) + Task 3 (researcher) + Task 4 (CD) + Task 5 (shot-planner) + Task 6 (worker check 5)
- [x] § 7 Orchestrator / Phase 4 changes → Tasks 7 + 8 + 9
- [x] "Timing" table — reflected in Task 8's new timeline block
- [x] "Non-goals" — Task 8's Phase 5 section explicitly removes stream pipelining

### Placeholder scan

- [x] No "TBD" in the plan itself (Task 6 references selectors "TBD until trap #23 fill-in", which is correct — the smoke test IS Task 1 and fills those in; Task 6 explicitly says "fill in after smoke test").
- [x] No "TODO" or "implement later" or "add error handling" — every step has concrete commands or code.

### Type / name consistency

- [x] `reference_images` (plural) used consistently across CD, researcher, shot-planner, image-worker, shots.json schema.
- [x] `reference_images_start` / `reference_images_end` used on the claim side (researcher's output, CD consumes) → `reference_images` (no suffix) used on the shot image slot (per-role).
- [x] `PER_CHECK_RETRY_CAP` constant in image-worker matches the "5×" in the design doc and SKILL.md prose.
- [x] `batch_size=1` consistent across worker (single variant write), reviewer (BATCH_PICK confirms not picks), shot-planner (initializes `variants=[]`).
- [x] All `$SKILL_ROOT/engine/shot_state.py` invocations use existing subcommands (`get`, `update`, `selected_variant`) — no new subcommands introduced.
- [x] Phase numbering: Phase 0, 1, 2, 2.5, 2.6, 3, 3.5, 4, 5, 6, 7 — preserved; Round 4 touches 0, 4, 5 only.

### Scope

- [x] Single implementation plan. All tasks touch the image phase + its feeding agents + SKILL.md playbook. No unrelated subsystems.

---

**Plan complete and saved to `docs/2026-04-24-single-tab-burst-images-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for a plan this size (10 tasks, several large markdown edits).

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Uses main session (Opus) for all tasks, including cheap ones.

**Which approach?**
