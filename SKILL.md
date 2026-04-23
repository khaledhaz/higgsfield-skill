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

### Phase 0 — Intake

When the user invokes "run `<slug>`":
1. Run `engine/preflight.sh` to clear any stale Chrome lock.
2. Run `engine/init_vault.sh` (idempotent).
3. Parse frontmatter of `$PWD/hf-projects/Projects/<slug>.md` with `engine/parse_frontmatter.py`.
4. Verify `status` is `active`, `inbox`, or `scheduled`. Set it to `active` via `engine/update_status.py`.
5. Ensure `$PWD/hf-outputs/<slug>/` exists; create if missing.

### Phase 1 — VO synthesis

Produce `vo.mp3` using Eleven v3 with the voice named in frontmatter. Overwrite existing if present. Cost: ~2 credits/minute. Log the result in the `<!-- engine:begin --> ... <!-- engine:end -->` block.

### Phase 2 — VO analysis (dispatch `vo-analyst`)

Write the script text from frontmatter's `vo.script` field to `$OUTPUT_DIR/script.txt`. Dispatch the `vo-analyst` subagent with `VAULT_DIR`, `OUTPUT_DIR`, `SCRIPT_PATH`. On `DONE`, read `beats.json`, render a markdown table, and update the note's `<!-- engine:beats -->` region via `engine/update_region.py`.

### Phase 3 — Director planning (dispatch `director`)

The `director` subagent (Opus-tier) plans the full montage: how many shots, how long each one runs, which shots use single-frame animation vs start→end morph, and the image+video prompts for each. This replaces the old mechanical `prompt-writer` INIT flow.

Dispatch the `director` with `OUTPUT_DIR`, `SCRIPT_PATH`, `BEATS_PATH`, `VO_DURATION`, `STYLE_NOTES`, `ASPECT`, `SKILL_ROOT`.

The director produces:
- `shots.json` — array of shot objects with per-shot `technique` (`start_only` or `start_end`), `images.start.prompt` (always), `images.end.prompt` (only if `start_end`), `video_prompt`, `director_intent`, float `duration`.
- `director_notes.md` — narrative rationale (arc, pacing, technique choices).

After DONE, read `shots.json` and render the shots-table region in the note. Save `director_notes.md` alongside it for the user to review.

**Invariants the orchestrator verifies**:
- `sum(shot.duration) === VO_DURATION` (±0.01s).
- Every beat covered by ≥ 1 shot (`beat_ids` unions tile the beats).
- Every shot has a non-empty `visual_concept` string.
- Every shot has a `cinematic_technique` from the allowed set (`synecdoche`, `juxtaposition`, `scale_contrast`, `negative_space`, `environmental_storytelling`, `visual_irony`, `literal`).
- In projects with 4+ shots, at least 2 distinct cinematic techniques are used (technique-variety rule).
- Every image has `images.start.concept_prompt` (<280 chars) and NO style/palette/grain vocabulary in it. `start_end` shots additionally have `images.end.concept_prompt`.
- `images.<role>.style_prompt` and `images.<role>.prompt` are `null` at this stage — they get populated in Phase 3.5 and Phase 4 respectively.

### Phase 3.5 — Style injection (orchestrator, not a subagent)

After the director returns `shots.json`, the orchestrator reads the project note's `## Style notes` section and builds a single `style_prompt` string:

```
<style vocabulary from ## Style notes>, <aspect ratio from frontmatter>, no text, no numbers, no logos, no readable flags
```

Then for every image entry in every shot, set `images.<role>.style_prompt` to this string:

```bash
python3 $SKILL_ROOT/engine/shot_state.py update "$OUTPUT_DIR/shots.json" <shot_id> "images.<role>.style_prompt=<built-style-string>"
```

This guarantees every image in the package shares identical rendering instructions regardless of which agent wrote the concept, and that retries on individual shots never drift the package's visual identity. The image-worker concatenates `concept_prompt + ", " + style_prompt` → `prompt` at submission time.

### Phase 3.7 — Visual research (parallel `visual-researcher` dispatches)

Between style injection and image generation, the `visual-researcher` subagent enriches every shot's `concept_prompt` with real-world physical-accuracy details. The director decided WHAT to show (composition, technique, intent). The researcher makes sure every named element in the frame LOOKS CORRECT when NBP renders it — named buildings, specific weapon systems, country-specific people/attire, industrial equipment, landmark geography.

**Parallel dispatch rule**:
- If `len(shots) >= 4`, dispatch TWO researchers concurrently (single message, two Agent tool calls) with disjoint shot ranges:
  - Researcher A: `SHOT_RANGE=[1, ceil(N/2)]`, `SEARCH_BUDGET=10`
  - Researcher B: `SHOT_RANGE=[ceil(N/2)+1, N]`, `SEARCH_BUDGET=10`
- If `len(shots) < 4`, dispatch a single researcher with no `SHOT_RANGE` and the default `SEARCH_BUDGET=20`.

Both researchers read and write the same `shots.json` — the dispatch is race-safe because each researcher only mutates shot IDs inside its assigned range, and `shot_state.py update` is atomic. Both append to the same `research_log.md` (append-only, no conflict).

Each dispatch receives: `OUTPUT_DIR`, `SCRIPT_PATH`, `SKILL_ROOT`, `SLUG`, and the optional `SHOT_RANGE` + `SEARCH_BUDGET`. The agent reads each in-range shot's `visual_concept` and `concept_prompt`, runs targeted web searches (max 3/element, `SEARCH_BUDGET` total), and appends physical descriptors to the concept_prompt — without changing composition, camera angle, cinematic technique, or editorial intent. For named landmarks/equipment/vehicles, it may attach reference image URLs to `images.<role>.reference_urls` (JSON array) for the image-worker's optional use.

After BOTH dispatches return DONE, the orchestrator verifies (across all shots):
- Every `concept_prompt` is still ≤280 chars.
- No concept_prompt gained style/palette/grain vocabulary (style-bleed guard).
- No concept_prompt gained "no text / no logos / no flags" phrasing (that lives in `style_prompt`).
- `$OUTPUT_DIR/research_log.md` exists with a per-(shot, role) entry for human review.
- `visual_concept`, `cinematic_technique`, `director_intent`, `claim_summary_en`, `duration`, `technique` on every shot are unchanged (researcher never modifies director fields).

If any invariant is broken, the orchestrator reverts the offending shot's `concept_prompt` to the pre-research value and logs the revert before moving on. Phase 3.7 is additive-only; a partial enrichment (some shots got enriched, others didn't) is acceptable.

### Phase 4 + Phase 5 — Images and Videos (pipelined, fire-and-forget, stream review)

These two phases DO NOT run sequentially. They interleave: the orchestrator submits all images in a fire-and-forget burst, reviews each image the moment it renders, and starts a shot's video submission as soon as its image(s) pass review — all while other shots are still rendering or being retried. This collapses what used to be ~12 minutes of serial Phase 4 → Phase 5 work into ~4 minutes of overlapping activity.

#### Worker allocation

- **Image-workers**: `min(total_image_tasks, 6)`. Each gets a roughly-equal slice of the `{shot_id, role}` task list, round-robin. For 8 image tasks → 6 workers, 2 of which get 2 tasks, 4 get 1 task.
- **Video-workers**: NO separate allocation up front. As each image-worker finishes (its last task is either `rendered` or `fail`), the orchestrator marks that worker's tab FREE and spawns a video-worker on the same tab index. Tab reuse ensures we never hold more than 6 Chrome tabs open concurrently.

#### Step-by-step orchestration

1. **Enumerate image tasks.** Build the list of `{shot_id, role}` pairs — one per image in `shots.json` where `images.<role>` is non-null. For a 10-shot plan with 2 `start_end` shots, that's 12 tasks.

2. **Dispatch image-workers (fire-and-forget).** Distribute tasks round-robin across up to 6 workers. Each worker runs `agents/image-worker.md`'s contract:
   - Phase A (rapid-fire): submit every assigned task in ~3s each, using Lexical verify-after-fill to guard against the silent prompt-fill race observed on the Mars run (see trap entry to come).
   - Phase B (batch poll): after all submissions, poll every 10s for completions and download as each finishes.
   - Each completion updates `images.<role>.status` to `rendered`, stores the CDN asset UUID in `images.<role>.artifact_asset_id`, and clears `images.<role>.submitted_at` back to null.

3. **Stream review (dispatch `image-reviewer` SINGLE mode per completion).** The orchestrator polls `shots.json` every ~5s watching for `images.<role>.status == "rendered"`. When one flips:
   - Dispatch `image-reviewer` in SINGLE mode for that single `(shot_id, role)`. These dispatches are cheap (~1s each) and they run concurrently if multiple images finish close together.
   - On PASS: set `images.<role>.status=pass`. Check whether this shot's OTHER image (for `start_end`) is also `pass`; if both are (or the shot is `start_only`), the shot is now video-ready — see step 5.
   - On FAIL with `images.<role>.attempts < retries_per_shot`: dispatch `prompt-writer` in RETRY mode to rewrite `images.<role>.concept_prompt`, reset `images.<role>.status=queued`, and hand the task back to ANY free image-worker (prefer the worker that was already idle) for a fresh Phase A+B cycle.
   - On FAIL with attempts at cap: escalate — append a numbered `### Q:` to the note's `## Questions`, set `images.<role>.status=escalated`, the shot's video stays blocked (can't proceed without this image).

   The key difference from BATCH review: retries can start within ~5s of a failure, overlapping with other shots' renders. The slowest shot no longer gates the review queue.

   **Exception** — if ALL images happen to complete within 5 seconds of each other (tight batch, e.g. when retry volume is zero and the server renders at uniform speed), the orchestrator MAY collapse to a single BATCH dispatch for lower context overhead. This is an optimization, not a requirement.

4. **Spawn video-workers as image-worker tabs free up.** An image-worker reports DONE (via its agent completion) when all its tasks are `rendered` or `fail`. At that point:
   - The orchestrator marks the worker's tab FREE.
   - If `next_video_ready` (the shot_state.py helper) returns a shot id, dispatch a `video-worker` on that tab index. The video-worker navigates to `/ai/video`, runs its localStorage-prime setup, and starts claiming from the shared queue.
   - If `next_video_ready` is empty right now but some images are still pending review or retry, the tab stays warmed (worker agent stays alive polling the queue every ~10s).

5. **Video-workers pull from the shared queue.** See `agents/video-worker.md`. Each video-worker repeatedly calls:
   ```bash
   NEXT=$(python3 $SKILL_ROOT/engine/shot_state.py next_video_ready "$OUTPUT_DIR/shots.json" "$TAB_INDEX")
   ```
   The engine helper atomically claims the lowest-id shot whose `video.status == "queued"` AND all required image roles have `status == "pass"`, marking it `claimed_<TAB_INDEX>` so no other worker races for it.

   For each claimed shot the worker primes both localStorage stores (`flow-create-video-<date>` for prompt + input/end images + `modelVersion=kling3_0`; `hf:video-kling-3-store:v2` for duration + aspect), reloads, runs the preflight checklist, and clicks Generate. No wait between submissions.

   **Kling duration derivation** (critical, last-shot rule):
   ```
   is_last = (shot.id == max_shot_id_in_project)
   tail_pad = 1 if is_last else 0
   kling_duration = max(3, min(15, round(shot.duration) + tail_pad))
   ```
   The +1s on the final shot provides tail material so the stitcher's freeze-frame pad doesn't land on a jump-cut to stillness.

6. **Video completion review (stream, same pattern).** As each video renders and downloads, dispatch `video-reviewer` in SINGLE mode. For `start_end` clips, the reviewer checks morph continuity (end frame of the clip should resemble the planned end image). Retries follow the same stream pattern — a failed video re-queues for its video-worker, fresh Kling render.

7. **Phase terminates** when every shot has `video.status in {"rendered","escalated"}` AND every image role has `status in {"pass","escalated"}`. At that point, update the `<!-- engine:shots -->` region in the note and proceed to Phase 6.

#### Rate-limit handling

If an image-worker reports `BLOCKED: suspected_rate_limit`, the orchestrator:
1. Pauses new image-worker dispatches.
2. Waits 30s.
3. Resumes with reduced parallelism (cut worker count in half, cap per-worker submissions to 2).
4. Logs the incident in `research_log.md` so the self-learning system (`auto-edit:traps`) can capture the NBP rate-limit pattern.

The same pattern applies for video-workers reporting rate-limit.

#### Key invariants preserved

- Every image still passes the image-reviewer rubric before its video is submitted — the stream review pattern does NOT skip review, it just runs per-image instead of per-batch.
- Retry count per shot is unchanged (`retries_per_shot` from frontmatter, default 5).
- Every video still passes the preflight checklist (start-frame UUID match, prompt match, model = Kling 3.0, expected credit cost) before Generate is clicked.
- Stitcher still trims non-last clips to exact float `shot.duration` and last clip still gets its +1s tail.
- No serial per-shot drag-drop — video always uses localStorage priming.

### Phase 6 — Stitch

Write `manifest.json`. Two important rules:

1. For **all non-last clips**, include `path` AND the exact float `duration` from `shots.json` — the stitcher trims with `-t $duration` so the final video track aligns to VO word timings precisely.
2. For the **LAST clip**, OMIT the `duration` field (or set to `null`) so the clip plays at its full natural Kling length. The last shot was rendered with an extra +1s of Kling duration specifically to provide tail material in case the VO runs past the stitched video.
3. Optionally set `vo.tail_pad` (default `1.0`). The stitcher forces the output duration to `vo_duration + tail_pad`:
   - If stitched video < target: freeze-frame pads the last frame to fill.
   - If stitched video > target: trims to target.
   - VO is silence-padded to target — the VO is NEVER truncated.

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
- Phase 3.7 with ≥4 shots → 2 `visual-researcher` dispatches, disjoint `SHOT_RANGE` (one message, two Agent calls).
- Phase 4+5 start: up to 6 `image-worker` dispatches (one message, N Agent calls, each owning a distinct `TAB_INDEX`).
- Phase 4+5 stream review: dispatch `image-reviewer`/`video-reviewer` (SINGLE mode) as each completion arrives — these go serial with respect to orchestrator polling, not parallel with each other (they're cheap).
- Anything else (director, vo-analyst, stitcher) → single dispatch.

The rule of thumb is: dispatch in parallel only when the tasks are truly independent AND the workers won't fight for shared state. Image-workers own disjoint tabs AND disjoint task lists; researchers own disjoint shot ranges — both safe. Reviewers are single-shot and serial-ok.

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
