---
project: higgsfield-skill
doc_type: design-spec
version: round-4
date: 2026-04-24
status: approved
supersedes: Phase 4 image generation section of 2026-04-23-agentic-orchestrator-v2-design.md (Round 3 parallel-tabs variant)
---

# Round 4 — Single-tab burst image generation with preflight checklist

## Motivation

Round 3 used N parallel Chrome tabs (up to 10) with one image-worker subagent per tab, each submitting exactly one image so all N could click Generate within ~4s of each other. It works, but it carries three costs:

1. **Tab orchestration overhead.** Pre-warming N tabs in Phase 0, distributing task assignments, and dispatching N subagents in one message is a lot of moving parts for a gain that the server-side render parallelism gives us "for free" regardless of submission shape.
2. **Recovery is awkward when one tab drifts.** If one pre-warmed tab lands on the wrong model / loses the Unlimited toggle / has a stale prompt, it fails differently than the others and the batch-pick reviewer has to absorb it. There's no single place to run verification before each click.
3. **No multimodal attachments.** NBP accepts reference pictures alongside the text prompt. Round 3 has no mechanism for per-shot attachments, no mechanism for clearing stale ones between shots, and no CD/researcher plumbing to decide when to use them.

Round 4 collapses Phase 4 into a single tab driven by one burst worker. Before every Generate click the worker runs a preflight checklist (model, unlimited, aspect, prompt, reference images). Failures are auto-remediated, retried per-check up to 5 times, then escalated via the standard pause mechanism so the user can fix the underlying issue and have the skill record it as a new trap.

The user has confirmed NBP accepts rapid sequential submissions in a single tab (Q1 of this brainstorm, 2026-04-24), which is the assumption the entire approach depends on.

## User-approved decisions (this brainstorm)

| Decision | Choice |
|---|---|
| Who drives the tab | One `image-worker` subagent (Haiku), Approach A |
| Review timing | Batch review after all renders complete (BATCH_PICK mode) — trade ~15–20s of pipeline overlap for architectural simplicity |
| Reference-image origin | Visual-researcher downloads candidates into the project; Creative Director picks per claim; worker attaches (option D of Q4) |
| Failure handling | Log every failure; auto-fix; retry per-check up to 5×; then pause with a diagnostic `### Q:` so the user can inspect and resolve |
| Self-learning | On pause resolution, record the root-cause as a new entry under the appropriate auto-edit marker in `references/traps.md`, following the existing self-learning rules |
| Pre-warmed tabs | Removed. Only one image tab is used — opened fresh at Phase 4 entry |

## Architecture overview

### Tab roles after Round 4

| Tab | Purpose | Lifetime |
|---|---|---|
| `main` | Orchestrator's primary — not a composer | whole run |
| `audio` | VO synthesis on `/audio` | Phase 1 only, can be reused / closed after |
| `monitor` | `/asset/video` polling for video completions | Phase 5 |
| `image` | **New.** Single NBP composer tab for Phase 4 burst | Phase 4 only |
| `video-workers` ×N | Kling 3.0 composer tabs | Phase 5 only (up to 6, unchanged from Round 3) |

There is no more `N × image-worker tabs`. Phase 0's tab pre-warm loop goes away.

### Agent roster changes

| Agent | Round 3 behavior | Round 4 behavior |
|---|---|---|
| `image-worker` | One worker per image task; single-task primary flow + multi-task fallback | **One worker for the whole burst.** Takes full list of `(shot_id, role)` tasks. Loops submit-with-preflight, then polls the gallery, then records downloads. No `TASKS` fallback (burst IS the loop). |
| `image-reviewer` | BATCH_PICK or SINGLE; after burst, batch reviews all variants | Unchanged interface. Always called in BATCH_PICK mode across all rendered images at end of burst. |
| `creative-director` | Emits `concept_prompt_start` / `concept_prompt_end` per claim | **Extended:** also emits `reference_images: [file_path, ...]` per claim (0..N paths), chosen from files in `$OUTPUT_DIR/references/claim_<id>/`. |
| `visual-researcher` | Enriches concept prompts; writes `reference_urls_*` text fields | **Extended:** also downloads images at those URLs into `$OUTPUT_DIR/references/claim_<id>/<slug>.png` so CD has real files to pick from. |
| `prompt-writer` BATCH_RETRY | Rewrites failed concept prompts | Unchanged. |

## Preflight checklist

Five items, run before every Generate click. Order is load-bearing — items whose fix requires a page reload run first, so later items aren't clobbered.

### 1. Model

**Pass**: the current URL is `https://higgsfield.ai/ai/image?model=nano-banana-pro`.
**Fix**: `browser_navigate` to the correct URL, wait 2s for hydration.
**Why first**: navigation discards all page state — prompt, toggles, attachments.

### 2. Unlimited toggle

**Pass**: both of —
- `document.querySelector('[role="switch"]').getAttribute('data-state') === 'on'`
- Generate button label reads `Unlimited ✨` (not `Generate ✨ N`). The label is the single source of truth (trap #1, trap #22).

**Fix**: click the switch, re-read. If label still shows a credit cost after the toggle visually flips ON, that's a trap #22-style sticky-across-resolution state — fix = reload the page once and re-verify.

### 3. Aspect ratio

**Pass**: `JSON.parse(localStorage['hf:nano-banana-2-image-form-3']).aspect_ratio === shot.aspect_ratio`.
**Fix**: write the correct value + `browser_navigate` same URL (reload). **This is the only fix that clears prompt AND attachments**, so items 4 and 5 are always re-verified after an aspect fix fires.

### 4. Prompt

**Pass**: `document.querySelector('[contenteditable="true"][role="textbox"]').textContent.slice(0, 80)` head-matches the shot's concatenated `concept_prompt + ", " + style_prompt` head.
**Fix**: `browser_press_key Ctrl+A` → `browser_press_key Backspace` → `browser_type slowly=true` the full prompt. (Trap #10b: `fill()` / `execCommand('delete')` don't work; native `pressSequentially` does.)

### 5. Reference images (conditional — skip if `shot.images.<role>.reference_images` is empty)

**Schema location**: CD emits `reference_images: [path, ...]` per claim. Shot-planner copies the claim's list into BOTH `images.start.reference_images` and `images.end.reference_images` of each derived shot — a morph pair uses the same character/place anchor at both endpoints. If the claim's list is empty, both roles get `[]` and check 5 is skipped.

**Pass**: the composer's attached files list equals the per-role set. Match by filename (selector for the attachment chip list is TBD — smoke test in implementation plan).
**Fix**:
- For each attached file not in the required set → click its remove X.
- For each required file not yet attached → attach via drag-drop of a `File` object injected into the composer's drop zone (see § "Attachment mechanism — smoke test").

**Never use** the URL-paste shortcut for attachments — even if NBP accepts it, the file UUID the server assigns is different and we lose traceability to the reference file on disk.

## Attachment mechanism — smoke test

Since the current skill has no documented attachment code, the implementation plan's first step is a 30-minute smoke test to pin down:

1. **Drop target selector**. Is the drop zone the whole composer, or a specific file-input proxy? Inspect `/ai/image?model=nano-banana-pro` DOM.
2. **Chip list selector**. How are attached files displayed — as chips next to the prompt, or in a sidebar? What's the remove-X selector?
3. **File type + size limits**. NBP likely accepts JPG/PNG/WebP; size cap unknown. Test at 512×512, 1024×1024, 2048×2048.
4. **Persistence across submits**. After clicking Generate, do attached files stay staged for the next submit (session-state trap class)? If yes, clear-stale logic runs every shot. If no, attach-for-each runs every shot.
5. **Multimodal effect**. Does adding a reference actually change the render, or is it silently ignored unless a specific prompt cue is used? If the latter, the CD agent needs to learn a cue pattern (e.g., `"Use the attached image as style reference"`).

The smoke test output becomes a section of `references/traps.md` under a new marker `<!-- auto-edit:traps category=nbp-multimodal -->`, and also drives the exact JS in the worker's attach/detach helper.

## Worker control flow

```
INIT:
  browser_tabs action=select tab=image
  load tasks from shots.json (all entries with images.<role>.status == "queued")
  sort tasks by shot_id, then role (start before end)

BURST SUBMIT LOOP:
  for task in tasks:
      attempts = {model:0, unlimited:0, aspect:0, prompt:0, refs:0}
      while True:
          failures = preflight(task)            # list of failing checks + observed values
          if failures is empty:
              click Generate
              record submit_ts in-memory
              update shots.json: status=rendering, submitted_at=<ts>, attempts=<n>
              break
          for fail in failures:
              if attempts[fail.name] >= 5:
                  pause_and_exit(task, fail)    # writes ### Q:, sets status=paused, returns PAUSED
              attempts[fail.name] += 1
              append_engine_log(task, fail, attempt=attempts[fail.name])
              remediate(fail)
          # re-enter while True — re-run preflight

POLL & DOWNLOAD LOOP:
  pending = set of submitted tasks
  start = now()
  while pending and (now - start) < (len(tasks) * 120s):
      thumbnails = query all img[alt="image generation"] src with hf_<ts>_<uuid>_min.webp
      for thumbnail in thumbnails whose ts >= earliest pending submit_ts:
          task = match thumbnail to a pending task (by submit_ts ordering)
          download thumbnail bytes (or full-res via asset URL)
          save to shots/shotNN_<role>.png
          update shots.json: variants=[{path,uuid}], selected_variant=0, status=rendered
          pending.remove(task)
      sleep 10s

REPORT:
  DONE
  mode: burst
  submitted: <N>
  rendered: <M>
  paused_shot: <id or none>
  elapsed_s: <n>
```

## Pause and resume

### Pause

When a check hits the 5-retry cap on a specific shot:

1. Worker captures context (shot id, check name, last 5 observed values, any last error screenshot).
2. Append under `## Questions`:
   ```
   ### Q: Shot <N> preflight stuck on <check_name> after 5 attempts

   Check: <check_name>
   Expected: <expected>
   Observed across attempts:
   - attempt 1: <observed>
   - attempt 2: <observed>
   - ...

   I've tried auto-remediation 5× and the UI isn't cooperating. Please help by one of:

   - **Fix it in the tab**, then reply `### A: fixed <one-line description of what was wrong>`
   - **Generate shot <N> manually** and save PNG at `<$OUTPUT_DIR/shots/shotNN_role.png>`, then `### A: accept <path>`
   - **Change the prompt**: `### A: edit prompt: <new concept prompt>`
   - **Drop this shot**: `### A: skip shot <N>` (durations will be rebalanced across remaining shots)
   ```
3. Update frontmatter: `status: paused`.
4. Worker reports `PAUSED`, exits. Submitted-but-still-rendering shots continue server-side and will be pickable on resume.

### Resume

User re-invokes `run <slug>` after writing `### A: ...`:

1. Intake detects `status: paused` + most recent `### A:` present → flip to `active`.
2. Parse the answer:
   - `fixed <description>` → trigger self-learn (§ below), re-dispatch burst worker with remaining queued tasks.
   - `accept <path>` → copy PNG into shot's expected filename, write `variants=[{path, uuid:null}]`, `selected_variant=0`, `status=pass`. Continue with remaining tasks.
   - `edit prompt: <new>` → update `images.<role>.concept_prompt`, reset `status=queued`, re-dispatch burst.
   - `skip shot <N>` → remove from shot list, rebalance timings, continue.
3. Drain any renders that completed server-side during the pause (gallery thumbnails with submit_ts from before the pause).

## Self-learning hook

On resume from a preflight-induced pause answered with `### A: fixed <description>`, the orchestrator:

1. Looks up the failed check in a routing table:
   | Check | Destination marker |
   |---|---|
   | `model` | `<!-- auto-edit:traps category=ui-discovery -->` |
   | `unlimited` | `<!-- auto-edit:traps category=cost -->` |
   | `aspect` | `<!-- auto-edit:traps category=ui-commit -->` |
   | `prompt` | `<!-- auto-edit:traps category=session-state -->` |
   | `refs` | `<!-- auto-edit:traps category=nbp-multimodal -->` (new marker, added by smoke test) |

2. Appends an entry to the matching marker in `references/traps.md`:
   ```markdown
   ### N. <one-line title>
   Observed <date> in <slug>: <user's description>. Auto-remediation tried <5× clicks/reloads/etc> and did not converge. User intervention: <what they did>.

   **Workaround (provisional)**: <what future runs should do>.
   ```

3. Commits with message:
   ```
   auto-learn: preflight <check> trap — <one-line title>

   Spec: <slug>
   Run: <ISO timestamp>
   Source event: <check> failed 5× in burst worker
   ```

4. Appends the commit hash + one-liner to the project note's `## Auto-edits made during this run`.

All existing self-learning guardrails apply unchanged:
- Markers must exist before writing (skip with note to `_runs/skill-edit-failures.md` if missing).
- Rate limit 5 auto-edits per project run.
- Append-only inside markers.
- One commit per edit.

## Orchestrator Phase 4 changes

### What's deleted

- Phase 0 tab pre-warm loop (`N_tabs = min(total_images, 10)` and the per-tab `browser_navigate` + Unlimited verify).
- Phase 4 step 1 (N-worker dispatch-in-one-message).
- Multi-task fallback section of `agents/image-worker.md` (no longer used — burst IS the loop).

### What's added

- Phase 4 entry: orchestrator opens / reuses the `image` tab, navigates to `/ai/image?model=nano-banana-pro`, verifies Unlimited + aspect + 2K once (sanity check; the worker re-verifies per shot).
- Phase 4 step 1: dispatch ONE `image-worker` with the full queued-task list.
- Phase 4 step 2: on worker DONE → dispatch one BATCH_PICK `image-reviewer` across all rendered images (unchanged).
- Phase 4 step 3: on worker PAUSED → surface pause message, exit orchestration cleanly. (Existing pattern in SKILL.md's "Pausing on escalation" section.)

### What's unchanged

- Shot-planner, creative-director (with the `reference_images` extension), visual-researcher (with the download extension), prompt-writer.
- Video phase, stitcher, finalize.
- Self-learning rules framework.
- Pause/resume semantics for shots — Round 4 just adds a new class of pause trigger (preflight exhaustion).

## Timing

For a 6-shot / 8-image project:

| Phase | Round 3 | Round 4 |
|---|---|---|
| Phase 0 + tab pre-warm | 20s | 5s |
| Phase 1 + 2.5 (VO ∥ CD) | 45s | 45s |
| Phase 2.6 research (now also downloads refs) | ~25s | ~30s |
| Phase 2 Whisper | ~25s | ~25s |
| Phase 3 shot-planner | 15s | 15s |
| Phase 3.5 style injection | 2s | 2s |
| **Phase 4 submissions** | **~4s (parallel)** | **~25s (sequential burst)** |
| Phase 4 renders (server-side) | ~60–90s | ~60–90s |
| Phase 4 batch review | 15–20s | 15–20s |
| Phase 5 videos | ~130s | ~130s |
| Phase 6 stitch | 15s | 15s |

Net: Round 4 ≈ Round 3 + 15–20s. Within budget.

The savings on Phase 0 (no pre-warm) roughly offset the added time in submissions, so total wall clock is essentially flat.

## Non-goals

- **No stream video pipelining.** Videos still wait for Phase 4 batch review. Round 3 pipelined start-video-worker-as-each-image-passes; that's gone in Round 4. Explicitly accepted in brainstorm — the complexity cost of orchestrator-polling-shots.json was not worth the ~15–20s of overlap.
- **No multi-tab fallback if a single shot stalls.** If the single image tab itself becomes unreachable (SingletonLock, trap #20), the worker reports failure via the standard pause mechanism — user can restart the browser and resume.
- **No support for >1 reference image per shot in the first implementation**, unless the smoke test reveals NBP has a multi-attach UI. If it does, extend CD's schema to `reference_images: [...]` (already an array).
- **No change to Kling 3.0 phase** — Round 3's pipeline for videos persists (except for the upstream change that videos now kick off after batch review, not stream).

## Open questions to resolve in the implementation plan

1. The five sub-questions of the attachment smoke test (§ "Attachment mechanism — smoke test").
2. Exact selector + DOM shape of NBP's attachment chip list and remove-X button.
3. Does `status: paused` due to preflight need a new CLI verb or does the existing resume intake cover it? (Expected: existing intake covers it.)
4. Whether `visual-researcher` needs credentials / API keys to download images (depends on source — Google image search URLs may require cookies; user-provided URLs should be simple GETs).
5. Whether CD should emit an explicit cue in `concept_prompt` when `reference_images` is non-empty (e.g., prepend `"Based on the attached reference image, "`), depending on smoke-test finding #5.
