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

### Phase 3.7 — Visual research (dispatch `visual-researcher`)

Between style injection and image generation, dispatch the `visual-researcher` subagent to enrich every shot's `concept_prompt` with real-world physical-accuracy details. The director decided WHAT to show (composition, technique, intent). The researcher makes sure every named element in the frame LOOKS CORRECT when NBP renders it — named buildings, specific weapon systems, country-specific people/attire, industrial equipment, landmark geography.

Dispatch the `visual-researcher` with `OUTPUT_DIR`, `SCRIPT_PATH`, `SKILL_ROOT`, `SLUG`. The agent reads every shot's `visual_concept` and `concept_prompt`, runs targeted web searches (max 20/project, max 3/element), and appends physical descriptors to the concept_prompt — without changing the composition, camera angle, cinematic technique, or editorial intent the director decided. For specific named landmarks/equipment/vehicles, it may also attach reference image URLs to `images.<role>.reference_urls` (JSON array) for the image-worker's optional use.

After DONE, the orchestrator verifies:
- Every `concept_prompt` is still ≤280 chars.
- No concept_prompt gained style/palette/grain vocabulary (style-bleed guard).
- No concept_prompt gained "no text / no logos / no flags" phrasing (that lives in `style_prompt`).
- `$OUTPUT_DIR/research_log.md` exists with a per-(shot, role) entry for human review.
- `visual_concept`, `cinematic_technique`, `director_intent`, `claim_summary_en`, `duration`, `technique` on every shot are unchanged (researcher never modifies director fields).

If any invariant is broken, the orchestrator reverts the offending shot's `concept_prompt` to the pre-research value and logs the revert before moving on. Phase 3.7 is additive-only; a partial enrichment (some shots got enriched, others didn't) is acceptable — the enriched concept_prompt is the primary accuracy mechanism, reference URLs are a bonus.

### Phase 4 — Images (dispatch workers + BATCH reviewer)

With the director's plan in hand, the orchestrator enumerates every image task: the list of `{shot_id, role}` pairs where `role ∈ {start, end}`. For a 6-shot plan with 2 `start_end` shots, that's 6 + 2 = 8 image tasks.

1. Distribute image tasks round-robin across workers (1 worker is usually enough — submissions are fast, server-side render is parallel). Each worker gets a `TASKS` array of `{shot_id, role}` objects.
2. Each worker submits every task on NBP 2K Unlimited, downloads to `shots/shotNN_<role>.png`, and records the Higgsfield asset UUID in `images.<role>.artifact_asset_id`.
3. **BATCH review**: dispatch ONE `image-reviewer` subagent in BATCH mode with all `{shot_id, role}` tasks. The reviewer reads every image and, for `start_end` shots, also judges morph coherence (start and end should share composition/camera/lighting, differ on one axis).
4. For each FAIL verdict with `images.<role>.attempts < retries_per_shot`:
   - Dispatch `prompt-writer` in RETRY mode with the reviewer's `reason` and `missing_elements`; path parameter = `images.<role>.prompt`.
   - Enqueue the single (shot_id, role) again by setting `images.<role>.status=queued`.
   - Re-submit and dispatch `image-reviewer` in SINGLE mode.
5. For any image that hits the cap with no PASS: escalate to `## Questions`, set `images.<role>.status=escalated`, pause.
6. When every image `status == pass`, update `<!-- engine:shots -->` and move on.

**Key artifact per image**: `images.<role>.artifact_asset_id` — Phase 5's priming flow depends on it.

### Phase 5 — Videos (FAST PATH: localStorage priming, with optional end-frame for start_end shots)

This phase uses the priming pattern documented in `agents/video-worker.md` (and `references/shortcuts.md`). Per-shot cost is ~5s of setup (prime localStorage + reload + preflight + Generate click).

1. Setup once: navigate to `/ai/video`, confirm Kling 3.0 selected, find the `flow-create-video-<date>` localStorage master key.
2. For each shot (serially — server renders parallelize automatically):
   a. Prime BOTH localStorage stores in one write:
      - `flow-create-video-*`: `prompt = shot.video_prompt`, `inputImage = shot.images.start.artifact_asset_id`, `endImage = shot.images.end.artifact_asset_id || null` (null for `start_only`, set for `start_end`), `modelVersion = "kling3_0"`.
      - `hf:video-kling-3-store:v2`: `duration = clamp(3, 15, round(shot.duration))`, `aspectRatio = <from frontmatter>`.
   b. Reload the page.
   c. Wait ~2s for re-hydration.
   d. Preflight (one `browser_evaluate`): verify start frame attached + matches asset UUID; for `start_end` also verify end frame attached + matches; prompt filled; model Kling 3.0; Generate cost = `kling_duration × 1.75`.
   e. If preflight passes → click Generate. If it fails → retry priming once; if still failing, fall back to the slow path (file_upload) for that shot.
3. After all submissions, wait for Kling renders (~60–180s each). Download MP4s.
4. Dispatch `video-reviewer` (BATCH) for motion + continuity verdict. For `start_end` clips, the reviewer additionally checks that the morph actually happened (end frame of the clip resembles the planned end image, not the start image).
5. Same retry loop as Phase 4 for FAIL verdicts.

Notes:
- Per-shot Kling duration is derived from float `shot.duration`, not hardcoded 6s. Long claims get long shots.
- Stitcher trims each clip to exact float `shot.duration` (passed via `manifest.clips[].duration`), so total video = total VO length exactly.
- NEVER add arbitrary waits between shot submissions. The form state is fully owned by localStorage priming; there's no UI race to wait on.
- Do NOT re-set model between shots — it persists.

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
