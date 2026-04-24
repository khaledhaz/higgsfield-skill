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

**Fix**: the inner `[role="switch"]` element can silently swallow clicks. Click its **parent button** instead:

```js
() => {
  const sw = document.querySelector('[role="switch"]');
  const wrapper = sw?.closest('button[id^="react-aria"]') || sw?.parentElement;
  wrapper?.click();
}
```

Wait 300ms, re-read. If the label STILL shows a credit cost after the switch visually flips ON, that's trap-22 sticky state — `browser_navigate` same URL (reload), wait 2s, re-preflight from check 1.

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

1. Focus the editor via `browser_evaluate`: `document.querySelector('[contenteditable="true"][role="textbox"]').focus()`
2. `browser_press_key key="ControlOrMeta+a"`
3. `browser_press_key key="Backspace"`
4. `browser_type element="prompt textbox" ref=<from snapshot> text="$FULL_PROMPT" slowly=true`

Where `FULL_PROMPT` = `concept_prompt + ", " + style_prompt` loaded via:

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

If `REFS` parses to `[]`, skip this check — but ALSO remove any stale chips from a prior task:

```js
() => {
  const chips = Array.from(document.querySelectorAll('div.relative.rounded-xl.bg-neutral-surface-subtle.group.shrink-0.size-14'));
  chips.forEach(chip => chip.querySelector('button')?.click()); // first button in chip = remove-X
  return chips.length;
}
```

**Pass** (when `REFS` is non-empty): the number of chips equals `REFS.length`, AND the CDN UUID inside each `img[alt="object image"]` src matches a file we uploaded for this task. Since we can't deterministically know the server-assigned UUID beforehand, a lighter check is enough: chip count equals required count AND no chips predate this task's submission start. Track `ref_upload_ts` per chip: record the time we upload each file, and on re-preflight treat any chip older than the earliest current-task upload as stale.

**Fix — Remove stale chips** (chips NOT matching any path in the current `REFS`):

```js
(keepCount) => {
  const chips = Array.from(document.querySelectorAll('div.relative.rounded-xl.bg-neutral-surface-subtle.group.shrink-0.size-14'));
  // Keep the youngest `keepCount` chips (most recent uploads); remove the rest.
  // For the first task of the burst, `keepCount` is 0 (remove all from prior session) before any upload.
  const toRemove = chips.slice(0, Math.max(0, chips.length - keepCount));
  toRemove.forEach(chip => chip.querySelector('button')?.click());
  return { removed: toRemove.length, kept: chips.length - toRemove.length };
}
```

Before uploading, call this with `keepCount = 0` to clear the strip. After all uploads, you'll have exactly `REFS.length` chips.

**Fix — Attach new references**:

For each path in `REFS`:

1. Click the add-more button to open the file chooser:
   ```js
   () => {
     // The add-more button is at the end of the chip strip. It has class "size-full" and
     // wraps a <label><input type="file" accept="image/..."> — clicking triggers the
     // native file chooser. It's NOT inside any chip.
     const strip = document.querySelector('div.flex.items-center.gap-2.flex-wrap');
     const buttons = Array.from(strip?.querySelectorAll('button.size-full') || []);
     // The last size-full button that is NOT inside a chip is the add-more button
     const addMore = buttons.find(b => !b.closest('div.relative.rounded-xl.bg-neutral-surface-subtle.group.shrink-0.size-14'));
     if (!addMore) return { ok: false, reason: 'add-more button not found' };
     addMore.click();
     return { ok: true };
   }
   ```

2. `browser_file_upload paths=["<absolute path from REFS>"]` — Playwright intercepts the native file chooser and sets the file.

3. Wait 2s for upload to complete and the new chip to mount.

4. Verify chip count increased by 1 and the newest `img[alt="object image"]` has a CDN URL (not a blob: URL).

Repeat for each path. Total upload time scales with `REFS.length` — typically 1 file, ~2-3s per file.

## Control flow

```
INIT:
  browser_tabs action=select, name=image     # orchestrator named the tab "image"
  tasks = TASKS (from dispatch)
  submitted = []          # list of {shot_id, role, submit_ts}
  paused = null           # set to {shot_id, role, check, observed, attempts_log} on exhaustion

BURST SUBMIT LOOP:
  for task in tasks:
      attempts = {model:0, unlimited:0, aspect:0, prompt:0, refs:0}
      attempts_log = []
      while True:
          failures = run_preflight(task)     # returns list of (check, observed, expected)
          if failures is empty:
              # All 5 checks pass. Submit.
              ATT=$(python3 $SKILL_ROOT/engine/shot_state.py get "$SHOTS_PATH" $SHOT_ID "images.$ROLE.attempts")
              python3 $SKILL_ROOT/engine/shot_state.py update "$SHOTS_PATH" $SHOT_ID \
                  "images.$ROLE.attempts=$((ATT+1))" \
                  "images.$ROLE.status=submitting" \
                  "images.$ROLE.prompt=$FULL_PROMPT"
              # Click Generate
              browser_evaluate: document.getElementById('hf:image-form-submit').click()
              submit_ts = current ISO timestamp
              submitted.append({shot_id, role, submit_ts})
              python3 $SKILL_ROOT/engine/shot_state.py update "$SHOTS_PATH" $SHOT_ID \
                  "images.$ROLE.status=rendering" \
                  "images.$ROLE.submitted_at=$submit_ts"
              wait 1s   # lets NBP's server-queue accept before the next preflight
              break     # next task
          # preflight had at least one failure
          for fail in failures:
              attempts[fail.check] += 1
              attempts_log.append({check, observed, attempt})
              if attempts[fail.check] > PER_CHECK_RETRY_CAP:
                  paused = {shot_id, role, check: fail.check, observed: fail.observed, attempts_log}
                  break out of while AND for
              remediate(fail.check)
          if paused: break
      if paused: break

  if paused:
      # Skip poll phase; go directly to PAUSE handling below.

POLL & DOWNLOAD (if not paused):
  pending = set of submitted tasks
  start = now()
  budget = len(submitted) * POLL_TIMEOUT_S_PER_TASK
  while pending and (now - start) < budget:
      thumbs = browser_evaluate:
          () => Array.from(document.querySelectorAll('img[alt="image generation"]'))
              .map(img => {
                  const m = img.src.match(/hf_(\d{8}_\d{6})_([a-f0-9-]{36})_min\.webp/);
                  return m ? { src: img.src, ts: m[1], uuid: m[2] } : null;
              })
              .filter(Boolean);

      for thumb in thumbs ordered by ts ascending:
          # Match to earliest pending task whose submit_ts (converted to NBP's ts format) <= thumb.ts
          task = earliest pending task with submit_ts <= thumb.ts_as_iso
          if not task: continue

          NN=$(printf "%02d" ${task.shot_id})
          BASE=$(echo "$thumb.src" | sed -E 's|/hf_.+|/|')
          curl -sS -L --retry 3 -o "$OUTPUT_DIR/shots/shot${NN}_${task.role}.webp" "${BASE}hf_${thumb.ts}_${thumb.uuid}_min.webp"
          ffmpeg -v error -y -i "$OUTPUT_DIR/shots/shot${NN}_${task.role}.webp" "$OUTPUT_DIR/shots/shot${NN}_${task.role}.png"

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
  PROJECT_NOTE="$VAULT_DIR/Projects/${SLUG}.md"   # derive VAULT_DIR as the directory containing $OUTPUT_DIR's parent

  # Append the question block
  NN=$(printf "%02d" ${paused.shot_id})
  FINAL_PATH="$OUTPUT_DIR/shots/shot${NN}_${paused.role}.png"

  cat >> "$PROJECT_NOTE" <<EOF

### Q: Shot ${paused.shot_id} ${paused.role} preflight stuck on ${paused.check} after ${PER_CHECK_RETRY_CAP} attempts

Check: ${paused.check}
Expected: <expected value for this check>
Observed across attempts:
$(for att in paused.attempts_log; print "- attempt $att.attempt: $att.observed")

I've tried auto-remediation ${PER_CHECK_RETRY_CAP}× and the UI isn't cooperating. Please help by one of:
- **Fix it in the tab**, then reply \`### A: fixed <one-line description of what was wrong>\`
- **Generate shot ${paused.shot_id} ${paused.role} manually** and save PNG at \`$FINAL_PATH\`, then \`### A: accept $FINAL_PATH\`
- **Change the prompt**: \`### A: edit prompt: <new concept prompt>\`
- **Drop this shot**: \`### A: skip shot ${paused.shot_id}\`
EOF

  # Flip frontmatter status to paused
  python3 "$SKILL_ROOT/engine/update_status.py" "$PROJECT_NOTE" paused

REPORT:
  if paused:
      echo "PAUSED"
      echo "shot_id: ${paused.shot_id}"
      echo "role: ${paused.role}"
      echo "stuck_check: ${paused.check}"
      echo "submitted_before_pause: ${len(submitted)}"
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
- Never retry a preflight check beyond PER_CHECK_RETRY_CAP on a single task. Pausing (log + exit) is always the correct action at the cap.
- Never use `fill()` / `browser_type slowly=false` / `execCommand('delete')` / `innerHTML=''` to clear the Lexical editor — see trap #10b. Use `Ctrl+A` + `Backspace` + `browser_type slowly=true`.
- Never try to attach reference images via synthetic `DragEvent` or by setting `input.files` via JS — see trap #23. React Hook Form rejects both. Always use the click-add-more → `browser_file_upload` flow.
- Never download a thumbnail without matching its timestamp to a task in `submitted`. Stray thumbnails (from earlier sessions or the orchestrator's sanity-check submit) will mis-attribute.
- Never touch the Unlimited toggle mid-poll. Only during preflight for a specific task.
- Never modify shots you weren't given in TASKS.
- Never assume reference-image attachments persist across submits. Re-verify attached chip count on every task.
- Never write the `paused` state without flipping frontmatter `status: paused` via `update_status.py` — the orchestrator's resume intake relies on this.
- Never exit cleanly while `pending` still has entries AND budget isn't exhausted. Keep polling.
