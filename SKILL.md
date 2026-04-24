---
name: higgsfield
description: Use when the user asks about higgsfield.ai - generating images, generating videos, animating an image, Soul ID characters, Cinema Studio 3.5, Seedance, Kling, Veo, Minimax Hailuo, Wan, Nano Banana, Soul 2.0, Soul Cinema, Flux, Seedream, UGC Factory, Lipsync Studio, Marketing Studio, or saving credits / avoiding credit spend on the Creator plan.
---

# Higgsfield (Creator plan)

User is on the **Creator plan**: 24-month term at $5,976, 6,000 credits/month, renews 2026-01-26 (captured 2026-04-21; confirm on /me/settings/subscription if stale).

## Before any task — ASK, never predict

**At the very start of every Higgsfield task, confirm the unknowns out loud — do not infer.** Ask about:

- **Style / look** — cinematic moody, clean corporate, UGC handheld, animated, photoreal, stylized? If the user provided a reference image, confirm: "use this as style anchor?" — don't assume.
- **Aspect ratio + duration** — 16:9 vs 9:16 vs 1:1; total video length if multi-shot.
- **Storyboard** — ask whether a storyboard / shot list exists. **If yes, work from it and don't invent shots.** If no, propose a shot breakdown and confirm before generating.
- **Model preference** — if the user said "best quality" or "save credits", they may still have a specific model in mind.
- **Transitions** — cuts (hard) or Kling 3.0 seamless transitions between shots?
- **Voiceover** — is there a VO to drive the timing? If yes, generate/measure the VO first (it dictates total runtime).

During execution, if anything becomes ambiguous — a content-policy stall, a model switch, an unclear prompt — **stop and ask**, don't guess your way through.

## Engine mode (agentic execution via Obsidian project notes)

When asked to **run a project** (by slug, or "run the inbox", or "run X and Y in parallel", or a scheduler sweep), enter engine mode. The authoritative contract is in `docs/2026-04-22-agentic-obsidian-engine-design.md`. This section is the execution playbook.

### Intake rules
- The project note lives at `$PWD/hf-projects/Projects/<slug>.md`. The `status` frontmatter field is the lifecycle switch.
- Only edit the note inside `<!-- engine:begin -->`…`<!-- engine:end -->`, `## Questions`, `## Outputs`, `## Auto-edits made during this run`, and the `status`/`shots` frontmatter fields.
- Before starting, read `git log --oneline -20` inside `~/.claude/skills/higgsfield/` and scan for recently-learned traps/workflows that might apply to this project.

### Phase sequence
1. **Intake** — parse frontmatter (`python -c "import sys,yaml; ..."`), validate required fields, set `status: active`, append start line to execution log.
2. **VO** (if `vo.script` present) — navigate to `/audio`, set model + voice + script in composer. **Read the waveform's mm:ss label from the DOM before clicking Generate** — this gives a duration estimate to plan against. Click Generate. Download the mp3 to `$PWD/hf-outputs/<slug>/vo.mp3`. Run `engine/probe_duration.sh` to get the actual duration.
3. **Plan** — if `shots:` is empty in frontmatter, plan N shots + M transitions to fit the VO duration (or the explicit `duration:`). Write the plan into `shots:` frontmatter. If script has ambiguous beat count vs. target shot count, pause: append `### Q: <question>` under `## Questions`, set `status: paused`, return control to the user.
4. **Images** — lazy-spawn up to min(N, 6) worker tabs on `/ai/image?model=nano-banana-pro`. Each submits one shot image. Download + QC-loop each (§ QC loop below).
5. **Videos** — lazy-spawn up to min(N, 6) workers on `/ai/video` with Kling 3.0 selected. Each submits one shot animation. Download + QC-loop.
6. **Transitions** — for each seamless pair, run `engine/extract_frames.sh <shotA> <shotB> <tmp-dir>`, then submit a Kling 3.0 Start+End-frame job with duration=3s (see [W11](references/workflows.md) and trap #21 for the commit mechanism).
7. **Stitch** — build a manifest JSON from the clips+transitions+VO, call `engine/stitch.sh manifest.json`.
8. **Finalize** — set `status: done` (or `partial` if any artifact failed), fill `## Outputs` with wiki-links, archive the verbose run log to `$PWD/hf-projects/_runs/<timestamp>-<slug>.md`.

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

### Pause / resume via the note (exit-cleanly)
- **Pause**: append `### Q: <question>` under `## Questions`, set `status: paused`, `browser_close`, print a clear instruction to the user, exit the current orchestration. Do NOT poll.
- **Resume**: user adds `### A: <answer>` below the most recent `### Q:`, optionally edits other parts of the note, then re-invokes `run <slug>`. Intake detects `status: paused` + presence of `### A:`, clears back to `active`, continues from the point of pause.
- **Mode D cron**: does NOT auto-resume paused projects. User must flip `status: scheduled` (or `inbox`) manually after answering. This is intentional — avoids re-running projects whose question wasn't actually answered.

## Orchestrator playbook (Mode A runtime)

You (main Claude session) ARE the orchestrator. Your job is to dispatch subagents, gate phases, and keep the project note in sync.

**Round 2 architectural principle — maximize overlap.** The slow server-side operations (VO gen ~45s, NBP render ~60s, Kling render ~120s) are hard floors. Everything else — creative planning, style building, tab setup, research, reviews — must overlap them rather than stack serially. Target total time for a 6-shot project: ~5–6 min (vs ~19 min pre-optimization).

### Phase 0 — Intake + parallel precompute

When the user invokes "run `<slug>`":
1. Run `engine/preflight.sh` to clear any stale Chrome lock.
2. Run `engine/init_vault.sh` (idempotent).
3. Parse frontmatter of `$PWD/hf-projects/Projects/<slug>.md` with `engine/parse_frontmatter.py`.
4. Verify `status` is `active`, `inbox`, or `scheduled`. Set it to `active` via `engine/update_status.py`.
5. Ensure `$PWD/hf-outputs/<slug>/` exists; create if missing.

**Precompute during intake (so Phase 3.5 is instant later):**
6. Read the `## Style notes` section of the project note and build the `STYLE_PROMPT` string now, in-memory:
   ```
   <style vocabulary from ## Style notes>, <aspect ratio from frontmatter>, no text, no numbers, no logos, no readable flags
   ```
   Hold this string. When `shots.json` exists (Phase 3), injection is a 2s loop instead of a 5s re-read.

7. Write the script text from frontmatter's `vo.script` field to `$OUTPUT_DIR/script.txt` — needed by BOTH Phase 1 (audio page fill) and Phase 2.5 (creative-director input).

8. **Round 4**: open (or reuse) the single `image` Chrome tab — no N-tab pre-warm loop anymore. Navigate it to `https://higgsfield.ai/ai/image?model=nano-banana-pro`. Don't verify Unlimited/aspect yet; the image-worker's preflight handles that per task. One tab is enough because Round 4's image-worker submits sequentially in a burst, and server-side render parallelism doesn't depend on client-tab count.

### Phase 1 + Phase 2.5 — VO synthesis ∥ Creative Director (DISPATCH TOGETHER)

These two run concurrently. **Dispatch both in a single orchestrator turn** (one Agent tool call for the creative-director plus the browser_navigate/type/click sequence for VO — see the parallel-dispatch rules section).

**Phase 1 — VO synthesis** (server-side ~45s):
Navigate to `/audio`, verify Eleven v3 + voice from frontmatter, clear editor + fill script, click Generate. Do NOT wait for render yet — while it renders, Phase 2.5 is already executing.

**Phase 2.5 — Creative Director** (Opus ~40s):
Dispatch `creative-director` with `SCRIPT_PATH`, `STYLE_NOTES`, `ASPECT`, `SKILL_ROOT`. This agent reads ONLY the script text and produces `claims.json` with per-claim creative decisions: `visual_concept`, `cinematic_technique`, `technique` (start_only/start_end), `concept_prompt_start`, optional `concept_prompt_end`, `video_prompt`, `creative_intent`, `estimated_duration_class`, `groupable_with_next`.

Creative Director does NOT receive beats or VO_DURATION — those don't exist yet. All creative work that doesn't need timing is done here, in parallel with the VO render.

Both must DONE before proceeding. Typical wall clock: ~45s (VO is the long pole; Creative Director finishes first and waits).

**Invariants on `claims.json`** (verify when Creative Director returns):
- 3–8 claims (typical range; ≥4 triggers the technique-variety rule).
- Every claim has a non-empty `visual_concept`.
- Every claim has a `cinematic_technique` from the allowed set.
- If ≥4 claims: at least 2 distinct `cinematic_technique` values.
- Every `concept_prompt_start` (and `_end` if present) is ≤280 chars with no style/grain/palette/lighting vocabulary.

### Phase 2.6 — Visual research (runs DURING Whisper window, on claims.json)

**Round 3 structural move**: research now happens on `claims.json` — BEFORE shots.json exists — in the time window between claims.json completion (t=45) and Whisper completion (t=82). Research overlaps with Whisper entirely, eliminating the research→submission serial cascade that Round 2 still had.

As soon as the Creative Director reports DONE and claims.json is written:

1. Count claims. If `len(claims) ≥ 4`, dispatch TWO `visual-researcher` agents in parallel (one message, two Agent calls):
   - Researcher A: `CLAIM_RANGE=[1, ceil(N/2)]`, `SEARCH_BUDGET=10`
   - Researcher B: `CLAIM_RANGE=[ceil(N/2)+1, N]`, `SEARCH_BUDGET=10`
   If `len(claims) < 4`, dispatch a single researcher with no range and default budget 20.

2. Each researcher reads `concept_prompt_start` / `concept_prompt_end` from claims.json and writes enriched versions back in place. Also writes `reference_urls_start/end` and `research_notes_start/end` into the claim records.

3. Whisper (Phase 2) and research run CONCURRENTLY. Since Whisper is ~25s and parallel research is ~20-25s, both complete roughly together around t=70-82.

**No markers, no pending_research status**. By the time the Shot Planner runs in Phase 3, every claim's concept prompts are already accuracy-enriched. The Shot Planner copies them straight into `shots.json` with `images.<role>.status = "queued"` — images are immediately submittable.

### Phase 2 — VO analysis (dispatch `vo-analyst`)

After VO download + probe, dispatch `vo-analyst` with `VAULT_DIR`, `OUTPUT_DIR`, `SCRIPT_PATH`. On DONE, read `beats.json` and render the markdown table for `<!-- engine:beats -->`.

Typical wall clock: ~25s (Whisper medium locally). Research (Phase 2.6) runs in parallel during this window.

### Phase 3 — Shot Planner (dispatch `shot-planner` — fast Sonnet)

After BOTH Phase 2 (beats.json) AND Phase 2.6 (research-enriched claims.json) are complete, dispatch `shot-planner` with `CLAIMS_PATH`, `BEATS_PATH`, `VO_DURATION`, `SKILL_ROOT`.

The Shot Planner is pure constraint satisfaction:
- Fuzzy-matches each claim's `claim_ar` against the beat timings.
- Applies `groupable_with_next` hints where combined beat duration ≤15s.
- Splits any single claim that spans >15s of beats into multiple shots (all sharing the same visual concept).
- Assigns exact float durations so `sum(shot.duration) === VO_DURATION` (±0.01s).
- Honors the last-shot tail rule (`duration ≤14s` so +1s Kling pad stays ≤15s).
- Copies research-enriched `concept_prompt_start/end` plus `reference_urls_*` and `research_notes_*` from claims.json into `shots.json` image slots.
- Writes `shots.json` with `images.<role>.status = "queued"` (Round 3 — research already done) and `images.<role>.variants = []` (image-worker populates with 2 variants later).

Typical wall clock: ~15s (Sonnet, no creative thinking needed).

**Invariants the orchestrator verifies on `shots.json`**:
- `sum(shot.duration) === VO_DURATION` (±0.01s).
- Every beat covered by ≥1 shot.
- Every shot has non-empty `visual_concept` + `cinematic_technique` from the allowed set.
- Technique-variety rule holds.
- Last shot `duration ≤14s`.
- Every image has `concept_prompt` ≤280 chars, no style vocab, `style_prompt=null`, `prompt=null`, `status="queued"`, `variants=[]`, `selected_variant=null`.

### Phase 3.5 — Style injection (instant — string already built)

Phase 0 already built `STYLE_PROMPT`. Loop over every image slot and set `images.<role>.style_prompt=$STYLE_PROMPT` via `shot_state.py update`. ~2s total.

Also **pre-build the stitch manifest template** right here:
```json
{
  "output": ".../final.mp4",
  "resolution": [1280, 720],
  "fps": 24,
  "vo": {"path": ".../vo.mp3", "tail_pad": 1.0},
  "cut_xfade": 0,
  "clips": [
    {"type": "video", "path": null, "duration": 9.48},
    ...
    {"type": "video", "path": null}   // last clip, no duration (natural Kling length)
  ]
}
```
Save as `$OUTPUT_DIR/manifest_template.json`. Phase 5 will fill in clip paths as videos download; Phase 6 runs stitch without any extra setup.

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


### Phase 6 — Stitch (manifest already templated in Phase 3.5)

The manifest template was built in Phase 3.5 with all fields except clip paths. As each video downloaded in the pipelined block, the orchestrator filled in `manifest.clips[i].path`. By the time the last video is done, `manifest.json` is ready — rename `manifest_template.json` → `manifest.json` and run `engine/stitch.sh`.

Manifest conventions (for reference, already encoded by the template):
1. For non-last clips, `path` + exact float `duration` from `shots.json` — stitcher trims with `-t $duration`.
2. For the LAST clip, `duration` omitted (null) — plays at its natural Kling length; stitcher freeze-frame-pads if still short of target.
3. `vo.tail_pad` (default 1.0) forces output duration to `vo_duration + tail_pad`:
   - Shorter stitched video → freeze-frame pad the last frame to fill.
   - Longer stitched video → trim to target.
   - VO is silence-padded to target — NEVER truncated.

```json
{
  "output": ".../final.mp4",
  "resolution": [1280, 720],
  "fps": 24,
  "vo": {"path": ".../vo.mp3", "tail_pad": 1.0},
  "cut_xfade": 0,
  "clips": [
    {"type": "video", "path": ".../clips/clip01.mp4", "duration": 9.48},
    {"type": "video", "path": ".../clips/clip02.mp4", "duration": 12.92},
    {"type": "video", "path": ".../clips/clip03.mp4", "duration": 27.58},
    {"type": "video", "path": ".../clips/clip04.mp4"}
  ]
}
```

(Above: clip04 is the last shot — no `duration` set, so stitcher uses its natural Kling length, then freeze-frame-pads if still short of target.)

Run `engine/stitch.sh manifest.json`. Capture the printed duration; it should equal `vo_duration + tail_pad` (typically VO + 1.0s) exactly.

### Phase 7 — Finalize

Fill the `## Outputs` section with paths and credits. Set `status: done`. Commit any auto-learn discoveries from this run per the "Self-learning rules" section below.

### Pausing on escalation

When a shot escalates (retry cap hit), post a numbered question to `## Questions`, set the shot's `status.<stage>=escalated`, and reload the note every ~30s watching for a user reply. Accepted forms:
- `accept shot N attempt K` → use `shots/shotNN_kK.png` as final, mark `pass`
- `skip shot N` → remove from final cut, rebalance timings by stretching adjacent shots
- `edit prompt: <new prompt>` → update shot's `image_prompt` / `video_prompt`, reset `status=queued`, resume

### Agent dispatch template

When dispatching a subagent, include:
- `SKILL_ROOT=/Users/khaled/.claude/skills/higgsfield`
- `VAULT_DIR=$PWD/hf-projects`
- `OUTPUT_DIR=$PWD/hf-outputs/<slug>`
- Any agent-specific params (see `agents/<name>.md` for the exact Input section)

Always pass SKILL_ROOT so subagents can invoke engine scripts without path guessing.

**Parallel dispatch rules (when to send multiple tool calls in one message):**
- **Phase 1 + Phase 2.5**: dispatch VO synthesis (browser sequence) alongside `creative-director` (Agent call) in ONE orchestrator turn. Biggest Round 2 win — retained in Round 3.
- **Phase 2.6 (Round 3)**: as soon as claims.json is written, dispatch 2 `visual-researcher` agents in parallel with disjoint `CLAIM_RANGE`. Research now happens on claims.json (not shots.json), entirely hidden behind Whisper runtime.
- **Phase 4 image burst (Round 4)**: after Shot Planner, dispatch ONE `image-worker` with the full TASKS array. Worker loops submit-with-preflight sequentially across all tasks on a single tab, then polls+downloads until the gallery drains. No N-tab warmup.
- **BATCH_PICK review**: ONE `image-reviewer` dispatch reviews all images together (evaluates single variant per image, confirms pass/fail). Replaces stream SINGLE reviews.
- **BATCH_RETRY prompt rewrite**: if reviewer returns ≥1 failure, ONE `prompt-writer` dispatch in BATCH_RETRY mode rewrites all failed prompts in a single agent call.
- **Phase 5 video workers**: up to 6 `video-worker` subagents dispatched in ONE orchestrator message after ALL images pass (no pipelining with Phase 4 in Round 4).
- **Stream video reviews**: `video-reviewer` SINGLE dispatched per video completion (same as Round 3).
- **Single-dispatch phases**: `vo-analyst`, `shot-planner`, `prompt-writer` RETRY (legacy single-failure path), stitch.

The rule of thumb: dispatch in parallel when tasks are truly independent AND workers won't fight for shared state. Video-workers own disjoint tabs AND each gets a unique shot (no contention). Researchers own disjoint claim ranges. Creative-director + VO synth operate on completely different resources.

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
2. **Markers must exist before writing.** Before any auto-edit, re-read the target file and confirm both the opening and closing markers are present. If markers are missing, skip the write, append a one-line failure note to `$PWD/hf-projects/_runs/skill-edit-failures.md`, and continue.
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

## Current model availability (this session)

- **Kling 2.5 Turbo is OFF-LIMITS when driven from Claude Code** — Generate clicks silently drop (no error, no "Generating" indicator, no queued job). Unknown cause. Use **Kling 3.0** instead. User will explicitly re-enable Kling 2.5 Turbo when it's fixed.

<!-- auto-edit:skill section=availability -->
<!-- /auto-edit:skill -->

## The single rule that decides cost

**`Generate ✨ N` means N credits will be charged. `Generate [Unlimited]` (black badge, no sparkle number) means free.** Toggles and "unlimited" badges lie; the button label doesn't.

## 90% of cost-saving boils down to 4 facts

1. **Only ONE video tier is truly unlimited**: Kling 2.5 Turbo at **720p × 5s** with "Unlimited mode" toggle ON. Everything else video costs credits.
2. **Soul 2.0 / Soul Cinema use a separate 10,000 free-gens pool** (not credits). Default to these for photo/cinematic stills.
3. **Nano Banana Pro at 1K/2K is free via 365 Unlimited; 4K always pays.** Stay at 2K unless you need print.
4. **FLUX.2 Pro's in-bar Unlimited toggle defaults OFF** — the one image model where you MUST check before clicking Generate, or you spend credits on a 365-Unlimited model.

## Three speed plays (in order of preference)

1. **Recreate button** — on any past video (`/asset/video/<uuid>` → click Recreate) or Animate on any past image. Preloads model + enhanced prompt + Start frame + duration + resolution. **~10 seconds to generate.**
2. **localStorage priming + reload** — write `hf:image-form-upd` and model-specific key before first interaction. Sets prompt, aspect, resolution, batch, unlimited in one eval. **~15 seconds.**
3. **Drag-and-drop from URL** — `fetch(url)` → `File` → `DataTransfer` → `DragEvent('drop')`. Skips file picker, works with any CDN URL.

## Copy-paste helpers for the Kling 3.0 composer

These are the reliable UI driver snippets — proven in practice.

**Clear Start+End frames** (both X buttons at once):
```js
Array.from(document.querySelectorAll('button'))
  .filter(b => b.className.includes('-top-2') && b.className.includes('-right-2'))
  .forEach(b => b.click());
```

**Open Start-frame file picker** (then `browser_file_upload` the PNG):
```js
const label = Array.from(document.querySelectorAll('p')).find(p => p.textContent === 'Start frame');
(label.closest('div[class*="aspect"]') || label.parentElement.parentElement).click();
```
(Same for End frame — swap `'Start frame'` → `'End frame'`.)

**Commit a Kling 3.0 duration** (e.g. 3s — range is 3–15):
```js
// 1) Open the popup first by clicking the duration pill
Array.from(document.querySelectorAll('button')).find(b => /^\d+s$/.test(b.textContent.trim()))?.click();
// 2) Set the hidden range input directly
const input = document.querySelector('input[type="range"][min="3"]');
const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
setter.call(input, '3');
input.dispatchEvent(new Event('input', { bubbles: true }));
input.dispatchEvent(new Event('change', { bubbles: true }));
// 3) Close popup — click prompt textbox to commit
document.querySelector('[contenteditable="true"][role="textbox"]').click();
// Verify: Duration pill = "3s", Generate button = "Generate ✨ 5.25"
```

**Replace the Lexical prompt** (clear → type new):
```js
const ed = document.querySelector('[contenteditable="true"][role="textbox"]');
ed.focus();
const range = document.createRange(); range.selectNodeContents(ed);
const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
// then dispatch Delete (via browser_press_key) and use browser_type for the new text
```

## Model picker cheat sheet

| Want | Use |
|---|---|
| Best free image (photoreal) | Nano Banana Pro 1K/2K |
| Best free image (fashion/aesthetic) | Soul 2.0 |
| Best free image (film-still / cinematic) | Soul Cinema |
| Free 4K image | Seedream 4.5 (365 Unlimited) |
| Cheapest video | ~~Kling 2.5 Turbo 720p 5s Unlimited~~ **currently broken in Claude Code — use Kling 3.0 instead** |
| Fastest video for iteration | Wan 2.5 Fast via Lipsync Studio (9 credits) |
| Image → animated clip (default this session) | **Kling 3.0** at 720p/5s with audio (~8.75 credits) |
| Seamless transition between two clips | **Kling 3.0** Start=last-frame-A + End=first-frame-B, 3s @ ✨5.25 credits (4s @ ~7 if 3s feels abrupt). Duration range is actually 3–15s. See [W11](references/workflows.md) + trap #21. |
| Best narrative/long-form video | Cinema Studio 3.5 (96/gen) |
| Fastest talking-head | UGC Factory with Google Veo 3 Fast (3 free-gens promo) |
| Voiceover / TTS for narration timing | **Eleven v3** (Higgsfield Audio) — generate VO first, then measure its duration to drive shot count/length |
| User's most-used (heuristic) | Nano Banana Pro (306 gens), Google Veo 3.1 (57 gens), Higgsfield Angles (91 gens) |

## Load references when the task needs depth

- **Model catalog with costs, defaults, unlimited status, URL slugs** → [references/models.md](references/models.md)
- **21 documented traps** (Lexical editor, session-state bleed, Minimax morph, Kling 2.5 Turbo silent-drop, Seedance eligibility stall, Kling 3.0 slider commit, Playwright SingletonLock, etc.) → [references/traps.md](references/traps.md)
- **Speed shortcuts** (localStorage schemas, Recreate flow, drag-drop) → [references/shortcuts.md](references/shortcuts.md)
- **Workflow templates** (image gen, video from image, Cinema Studio project) → [references/workflows.md](references/workflows.md)

## Before recommending anything concrete

- "Current credits" or "my unlimited models" → read from `/me/settings` (don't cite cached numbers)
- Specific button clicks → be aware Higgsfield ships weekly; the Cinema Studio version may have advanced past 3.5
- Preset UUIDs in Kling/Seedance → these change; never hardcode in suggestions

## User's workflow signature

Defense/military themed production (folders: "Israel Iran Nuclear", "Modern Military Equipment", "Flight Deck Marine"; Male-Archive Soul ID character). Tailor examples toward that domain unless user specifies otherwise.

## Common tasks

- **"Generate an image"** → first ask about style/aspect, then default to Nano Banana Pro at 2K 1:1, Unlimited toggle ON. Fashion/aesthetic → Soul 2.0. Cinematic keyframe → Soul Cinema.
- **"Animate this image"** → click Animate on image detail if available. Default this session = **Kling 3.0** (not Kling 2.5 Turbo). See [W3 in workflows.md](references/workflows.md).
- **"Make a multi-shot video from a script"** → ask for storyboard; if none, propose shot breakdown and confirm. Consider VO-first timing ([W13](references/workflows.md)). For transitions, ask cuts vs. Kling 3.0 seamless ([W11](references/workflows.md)).
- **"Use Seedance"** → Seedance runs an eligibility check on each input image. Skill must wait until it's Eligible OR Not Eligible — **reload the page every 90s while waiting** ([W12](references/workflows.md)).
- **"Make a short film"** → Cinema Studio 3.5, set up project, load Soul ID characters as Elements, use @mentions in prompt.
- **"Add a voiceover"** → Higgsfield Audio → **Eleven v3**. Generate the VO first; its duration is the authoritative runtime the video must match ([W13](references/workflows.md)).
- **"Save credits"** → prefer 365-Unlimited image models. Avoid Seedance 2.0 (88/gen), Veo 3.1 (premium cost), Cinema Studio 3.5 video (96/gen) unless necessary. (Kling 2.5 Turbo free tier is the usual go-to here, but it's currently broken from Claude Code.)
