---
project: higgsfield-skill
doc_type: design-spec
version: 2
date: 2026-04-23
status: approved
supersedes: 2026-04-22-runtime-orchestrator-design.md
---

# Agentic Orchestrator v2 — Design Spec

## Motivation

v1 ran end-to-end successfully on `oil-hormuz-news` (2026-04-23) but two structural gaps surfaced:

1. **No VO timing ground truth.** v1 divided VO duration evenly across N shots. Beats rarely landed on the claims they depicted. Shot 6 ("container ship attack") could play while the VO is still talking about stockpiles.
2. **Prompts were cinematic wallpaper, not visual journalism.** Prompt-writer worked from the *theme* of the script, not the *specific claims*. "Weathered oil drum on dock grating" is mood; the claim "prices rose more than $3" needs literal visual evidence, not vibes. No per-shot review existed to catch the mismatch.

v2 fixes both with word-level VO alignment and a strict reviewer in the loop.

## User-approved decisions (this conversation)

| Decision | Choice |
|---|---|
| Review strictness | Strict visual accuracy — reviewer rejects unless the specific claim is visible |
| VO timing | Word-level Whisper transcription (local `openai-whisper`, medium model) |
| Reviewer mechanism | Claude vision, free-form judgment from claim text + image |
| Retry budget | 5 attempts per shot, autonomous (no user prompt between retries) |
| Pause gates | Pause only on exhausted-retry failure or ambiguity; no per-phase gates |
| Scope | Full redesign — replace current orchestrator playbook; obsoletes hand-written `shots:` YAML |
| Parallelism | 3 parallel image-workers and 3 parallel video-workers, one Chrome tab each |
| Whisper flavor | Local `openai-whisper` medium model (free, handles Arabic) |

## Architecture overview

### Agent roster

| Agent | Model | Role | Tool access |
|---|---|---|---|
| **orchestrator** | main session (Opus) | reads note, dispatches subagents, gates phases, rewrites note regions | all |
| **vo-analyst** | Sonnet subagent | runs `engine/vo_analyze.py`, segments transcript into claims, emits `beats.json` | Bash, Read, Write |
| **prompt-writer** | Opus subagent | `beats.json` + script → `shots.json` (image_prompt + video_prompt per beat); also rewrites prompts on reviewer feedback during retries | Read, Write |
| **image-worker** ×3 | Haiku subagent | each owns one Chrome tab (by index), pulls assigned shot ids from queue, submits NBP 2K Unlimited, polls for completion, downloads result | browser_* (tab-scoped), Bash, Read, Write |
| **image-reviewer** | Sonnet subagent, vision-enabled | `{claim_ar, claim_en, image.png}` → `{verdict: pass\|fail, reason: "...", missing_elements: [...]}` | Read (image files) |
| **video-worker** ×3 | Haiku subagent | each owns one Chrome tab, pulls assigned shots, submits Kling 3.0 720p animations, downloads MP4 | browser_*, Bash, Read, Write |
| **video-reviewer** | Sonnet subagent, vision-enabled | samples 3 frames from clip (start/mid/end), judges motion quality + semantic continuity with image | Read, Bash (for ffmpeg frame sampling) |
| **stitcher** | deterministic shell | unchanged `engine/stitch.sh` | — |

### Phase flow

```
Phase 0  intake             orchestrator
Phase 1  VO synthesis       orchestrator (Eleven v3)         → vo.mp3
Phase 2  VO analysis        vo-analyst subagent              → beats.json
Phase 3  prompt planning    prompt-writer subagent           → shots.json
Phase 4  image generation   image-worker ×3 + image-reviewer → shots/shotNN.png (all approved)
Phase 5  video generation   video-worker ×3 + video-reviewer → clips/clipNN.mp4 (all approved)
Phase 6  stitch             stitcher script                  → final.mp4
Phase 7  finalize           orchestrator                     → status=done
```

Phases 4 and 5 have internal retry loops; everything else is linear.

## Artifact schemas

### `beats.json`

Emitted by `vo-analyst` after running Whisper on `vo.mp3`.

```json
[
  {
    "id": 1,
    "claim_ar": "ارتفعت أسعار النفط بأكثر من 3 دولارات اليوم الأربعاء",
    "claim_en": "Oil prices rose more than $3 today, Wednesday",
    "start": 0.00,
    "end": 8.42,
    "duration": 8.42,
    "word_count": 8,
    "confidence": 0.94
  },
  {
    "id": 2,
    "claim_ar": "بعد بيانات أشارت إلى انخفاض مفاجئ في مخزونات البنزين...",
    "claim_en": "after data showed a surprise drop in US gasoline/distillate stockpiles",
    "start": 8.42,
    "end": 22.15,
    "duration": 13.73,
    ...
  }
]
```

**Segmentation rule:** claims are split on sentence or strong-clause boundaries in the Arabic source; Whisper word timings define exact start/end. A beat > 10s gets split into two shots downstream (prompt-writer's job).

### `shots.json`

Emitted by `prompt-writer` from `beats.json` + script. Persisted and mutated throughout Phases 4–5.

```json
[
  {
    "id": 1,
    "beat_id": 1,
    "start": 0.00,
    "end": 8.42,
    "duration": 8.42,
    "image_prompt": "Wide cinematic aerial shot of an oil refinery...",
    "video_prompt": "Slow aerial parallax over the refinery...",
    "claim_summary_en": "Oil prices rose more than $3 today",
    "status": {"image": "queued", "video": "queued"},
    "attempts": {"image": 0, "video": 0},
    "artifacts": {"image": null, "video": null, "image_asset_id": null, "video_asset_id": null},
    "reviews": {
      "image": [
        {"attempt": 1, "verdict": "fail", "reason": "Only one ship visible; claim requires multiple", "timestamp": "..."},
        {"attempt": 2, "verdict": "pass", "reason": "Shows 3+ damaged ships in open sea", "timestamp": "..."}
      ],
      "video": []
    }
  }
]
```

**Status values:** `queued`, `submitting`, `rendering`, `rendered`, `reviewing`, `pass`, `fail`, `escalated`.

### `workers.json`

Orchestrator's concurrent-worker bookkeeping. Rewritten on every dispatch.

```json
{
  "phase": "image",
  "workers": [
    {"worker_id": 0, "tab_index": 0, "status": "idle", "current_shot": null, "queue": [1, 4, 7]},
    {"worker_id": 1, "tab_index": 1, "status": "busy", "current_shot": 2, "queue": [5, 8]},
    {"worker_id": 2, "tab_index": 2, "status": "idle", "current_shot": null, "queue": [3, 6]}
  ]
}
```

## Obsidian note schema (new)

### Frontmatter

```yaml
---
project: oil-hormuz-news
status: active
aspect: 16:9
duration: vo-driven
style_reference: null
vo:
  script: |
    (full script text)
  model: eleven-v3
  voice: TALLULAH
retries_per_shot: 5
parallelism: 3
schedule: null
---
```

**Breaking change from v1:** `shots:` key is no longer user-input. It becomes the output of the `prompt-writer` subagent, rendered into the note body as a live region.

### Body regions

Orchestrator maintains three auto-rewritten regions delimited by `<!-- engine:X -->` markers, plus the existing execution log:

```markdown
## Script
(same as v1)

## Style notes
(same as v1)

## Beats
<!-- engine:beats -->
| # | Start | End | Dur | Claim (EN) |
|---|-------|-----|-----|-----------|
| 1 | 0.00  | 8.42 | 8.42 | Oil prices rose more than $3 today |
| 2 | 8.42  | 22.15 | 13.73 | Surprise drop in US gasoline/distillate stockpiles |
<!-- /engine:beats -->

## Shots
<!-- engine:shots -->
| # | Beat | Status | Attempts (img/vid) | Image | Video |
|---|------|--------|--------------------|-------|-------|
| 1 | 1    | ✅ done | 1 / 1 | `shots/shot01.png` | `clips/clip01.mp4` |
| 2 | 2a   | ⏳ img rendering | 0 / 0 | — | — |
<!-- /engine:shots -->

## Review log
<!-- engine:reviews -->
- [x] 2026-04-23T16:12Z Shot 6 img attempt 1: **FAIL** — "Only 1 container ship visible; claim says 3+"
- [x] 2026-04-23T16:13Z Shot 6 img attempt 2: **PASS** — "Shows 3 damaged container ships with visible smoke"
<!-- /engine:reviews -->

## Execution log
<!-- engine:begin -->
... (phase-level entries, unchanged from v1) ...
<!-- engine:end -->

## Questions
(orchestrator writes here when a shot escalates)

## Outputs
- VO: ...
- Final: ...
```

## Chrome tab coordination

**Constraint:** Playwright MCP = single Chrome instance. Subagents share the browser.

**Solution:** orchestrator opens 3 tabs before dispatching workers, assigns each worker a tab index (0/1/2). Each worker's prompt includes:

> Before every browser action, call `mcp__playwright__browser_tabs` with `action="select", index=<your_tab_index>` to activate your tab. Never touch other tabs. If you find the page is on the wrong URL (another worker's session), re-navigate.

Authentication shares state across tabs (same profile), so Higgsfield stays logged in everywhere.

**Round-robin assignment** for N shots across 3 workers:
- Worker 0: shots 1, 4, 7, 10, ...
- Worker 1: shots 2, 5, 8, 11, ...
- Worker 2: shots 3, 6, 9, 12, ...

**Reviewer is serial** (single subagent, no browser, just reads image files) — no contention concerns.

## Retry loop mechanics

Per shot, per stage (image or video), state machine:

```
QUEUED
  ↓ worker picks up
SUBMITTING
  ↓ Generate clicked successfully
RENDERING
  ↓ poll for completion (worker watches its tab)
RENDERED (artifact downloaded)
  ↓ orchestrator dispatches reviewer
REVIEWING
  ↓ verdict returned
  ├─ PASS → DONE (mark shot stage complete, free worker)
  └─ FAIL → attempts++
      ├─ attempts < 5: dispatch prompt-writer with
      │                {original_prompt, claim, reviewer_reason, missing_elements}
      │                → new prompt → enqueue → QUEUED
      └─ attempts >= 5: ESCALATED
                        orchestrator writes to note's Questions section,
                        pauses phase, waits for user response:
                          - "accept shot N attempt K" → DONE using that artifact
                          - "skip shot N" → drop the shot, rebalance timings
                          - "edit prompt: <new>" → resubmit with user's prompt
```

**Escalation UX:** orchestrator posts to `## Questions` section with a numbered list and each time reloads the note to check for a user reply before proceeding. (Same polling model as v1's schedule sweep.)

## Reviewer prompts (critical)

### image-reviewer

Input: `{claim_ar, claim_en, claim_summary_en, image_path}`.

```
You are reviewing a still image intended to visualize a specific claim from an Arabic news broadcast.

Claim (English): {claim_summary_en}
Claim (full Arabic): {claim_ar}

Look at the image and decide: does it visualize this claim strictly enough that a news viewer who HEARD the claim and then SAW this image would feel the image is showing them what the claim describes?

Strict mode:
- "3 ships" means the image must show 3+ ships, not 1
- "stockpiles dropping" means visible inventory/storage context, not just industrial imagery
- "talks stalled" means a visual of absence/stoppage (empty seats, closed door), not just a fancy room

Return STRICT JSON:
{
  "verdict": "pass" | "fail",
  "reason": "<one sentence: what you saw and why it matches/fails>",
  "missing_elements": ["<what's needed but absent>"],
  "suggestion": "<optional: specific visual change that would pass>"
}
```

### video-reviewer

Input: sampled frames (start/mid/end) + `video_prompt`. Judges motion quality, continuity with source image, no jarring artifacts, and that the stated motion ("slow push-in") actually occurs.

## Cost/time estimate

For a 60s Arabic news VO (~8 claims):

| Phase | Time | Cost |
|---|---|---|
| 1. VO (Eleven v3) | 10s | ~2 cr |
| 2. VO analysis (Whisper medium local, MPS) | 20s | 0 |
| 3. Prompt planning (Opus subagent) | 15s | API tokens |
| 4. Images (NBP 2K Unlimited, 8 shots × 1.3 avg retry) | 60s | 0 cr |
| 5. Image review (Sonnet vision × ~10 calls) | 30s | API tokens |
| 6. Videos (Kling 3.0 × 8 shots × 1.2 retry, 10.5 cr each) | 180s | ~100 cr |
| 7. Video review (Sonnet vision × ~10 sampled frames) | 30s | API tokens |
| 8. Stitch | 15s | 0 |
| **Total** | **~6 min** | **~102 cr + ~$0.50 API** |

## File-level scope

### New files

- `agents/vo-analyst.md` — subagent prompt
- `agents/prompt-writer.md` — subagent prompt (handles both initial plan and retry rewrites)
- `agents/image-worker.md` — subagent prompt (with tab-coordination rules)
- `agents/image-reviewer.md` — subagent prompt (with reviewer rubric above)
- `agents/video-worker.md` — subagent prompt
- `agents/video-reviewer.md` — subagent prompt
- `engine/vo_analyze.py` — Python script invoking `openai-whisper`, emits `beats.json`
- `engine/update_region.py` — rewrites `<!-- engine:X -->...<!-- /engine:X -->` blocks in a markdown file
- `engine/shot_state.py` — read/write `shots.json`, state transitions, retry accounting
- `engine/tests/test_vo_analyze.sh` — TDD fixture using a known Arabic WAV
- `engine/tests/test_update_region.sh` — TDD fixture
- `engine/tests/test_shot_state.sh` — TDD fixture
- `docs/2026-04-23-agentic-orchestrator-v2-design.md` — this file

### Modified files

- `SKILL.md` — rewrite "Orchestrator runtime procedure" section; add "Agent roster" reference; update template link
- `_templates/new-project.md` — remove `shots:` from YAML, add `retries_per_shot: 5`, `parallelism: 3`, add engine region placeholders in body

### Unchanged files

- `engine/init_vault.sh`
- `engine/preflight.sh`
- `engine/parse_frontmatter.py`
- `engine/update_status.py`
- `engine/stitch.sh`
- `engine/extract_frames.sh`
- `engine/probe_duration.sh`
- `engine/sweep.sh`
- `references/models.md`
- `references/traps.md` (still gets auto-edits during runs)
- `references/shortcuts.md`
- `references/workflows.md`

## Dependencies added

- Python package: `openai-whisper` (pip)
- Python packages: `torch` + `torchaudio` (Whisper dependency; MPS-accelerated on Apple Silicon)
- System: `ffmpeg` (already required for v1)

Install step: `pip install -r requirements.txt` — update `requirements.txt` to include whisper.

## Backward compatibility

**None.** v2 is a full break. Notes created under v1 (with hand-written `shots:`) will not run on v2. User confirmed this is acceptable.

The v1 design doc `2026-04-22-runtime-orchestrator-design.md` is superseded by this one. Keep it in `docs/` for historical reference.

## Open questions (resolved inline)

- Q: How does prompt-writer know when to split a long beat (>10s) into 2 shots?
  - A: Hardcoded rule: if `beat.duration > 10s`, create 2 shots covering `[start, mid]` and `[mid, end]`. Each gets a distinct image_prompt focused on a different visual facet of the same claim. Reviewer judges each independently.

- Q: How is VO script (Arabic) matched to Whisper output (which may misspell proper nouns)?
  - A: vo-analyst uses the user's `vo.script` frontmatter as the source of truth for claim text (Arabic), and Whisper's transcript only for word-level timings. Alignment: fuzzy match between Whisper tokens and script tokens (Python `rapidfuzz`), then assign each word its Whisper start/end. Falls back to proportional timing if match fails.

- Q: What happens if a worker's Chrome tab crashes mid-job?
  - A: Worker reports BLOCKED. Orchestrator reruns `preflight.sh`, re-assigns the shot to a different worker, increments its attempt counter (not retry counter — separate concern). Escalation threshold is still 5 semantic retries.

- Q: Does the video-reviewer check that the motion actually happens (e.g. "slow push-in")?
  - A: Yes. video-reviewer samples 3 frames and verifies the described camera move is evident (start frame vs end frame composition diff). Static clips when motion was requested = FAIL.

## Risks

1. **Whisper Arabic accuracy** — medium model may mis-segment on fast speech. Mitigation: use the user's script as ground truth for claim text; Whisper only provides timings.
2. **Reviewer false negatives** — strict mode could reject images that a human would accept. Mitigation: 5-retry budget + escalation; user can override on escalation.
3. **Tab coordination drift** — a worker's tab could accidentally navigate away. Mitigation: every worker re-navigates to its target URL at the start of each action, idempotent.
4. **Kling 3.0 render failures** — server-side render can fail; needs timeout + resubmit. Mitigation: video-worker includes a 180s render timeout; failure = treat as semantic fail (counts against retry budget).
