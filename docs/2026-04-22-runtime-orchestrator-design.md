# Design: Runtime Orchestrator (Flavor 1)

**Date:** 2026-04-22
**Status:** Approved (pending user spec review)
**Parent:** `docs/2026-04-22-agentic-obsidian-engine-design.md`
**Scope:** Extends §5–§9 of the parent design with the concrete runtime wiring that makes Mode A run unattended and Mode B run from cron.

## 1. What this spec adds

The parent design spec describes the engine-mode contract: Obsidian vault layout, phase pipeline, QC loop, self-learning rules, and four invocation modes. It does NOT describe the runtime — the concrete procedure Claude executes when told "run X" and the mechanism by which cron fires a scheduler sweep.

This document adds:
- The Mode A orchestrator procedure (deterministic, Claude-executable).
- Subagent dispatch patterns for parallel local work (vision QC, ffmpeg, file I/O).
- The Mode B cron wiring (CronCreate setup + sweep script).
- Browser lifecycle rules (open/close per project; SingletonLock pre-flight).
- Crash recovery / resume-from-log semantics.
- Pause semantics (exit cleanly; re-invoke after answer).

## 2. Parallelism model (confirmed: Flavor 1)

Claude Code's Playwright MCP owns one Chrome profile at `~/Library/Caches/ms-playwright/mcp-chrome-81eef6c`. Only one driver can act on the browser at a time.

**Flavor 1 model:**
- The main Claude session owns the browser and drives it sequentially across N browser tabs.
- Server-side parallelism at Higgsfield is the dominant speedup — once 6 jobs are submitted, they render in parallel server-side.
- Parallel `Agent` subagents are used ONLY for local work that does not touch the browser: vision QC on downloaded frames, ffmpeg frame extraction, ffmpeg stitching, file downloads.

**Critical path** for a 6-shot + 3-transition video with VO (unchanged from parent spec):
- Phase 1 VO: ~60s
- Phase 2 plan: ~instant
- Phase 3 images: ~3 min (6 submits × 30s browser time, all rendering parallel server-side)
- Phase 4 videos: ~5 min (6 submits × 30s browser time + slowest-gen wait)
- Phase 5 transitions: ~5 min (3 submits × 30s + slowest gen)
- Phase 6 stitch: ~30s (local ffmpeg, parallelizable but bottlenecked by final concat)
- Phase 7 finalize: ~instant
- **Total critical path: ~14 min** (same as parent spec estimate)

## 3. Mode A orchestrator procedure

When Claude is invoked with "run <slug>" or similar, the procedure below executes. The procedure is written into `SKILL.md` as a numbered playbook; Claude reads it top-to-bottom.

### 3.1 Pre-flight (before any Higgsfield action)

```bash
# Clean stale SingletonLock that can deadlock playwright-mcp (trap #20)
bash ~/.claude/skills/higgsfield/engine/preflight.sh
```

`preflight.sh` checks for `~/Library/Caches/ms-playwright/mcp-chrome-81eef6c/SingletonLock`. If present AND no Chrome process holds it (`pgrep -f mcp-chrome-81eef6c` returns empty), removes it. Exits 0 either way.

### 3.2 Intake (Phase 0)

1. Resolve slug to path: `~/Obsidian/Higgsfield/Projects/<slug>.md`.
2. Parse frontmatter: `python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]).read().split("---")[1]))' <path>`.
3. Read current `status`:
   - `inbox` → flip to `active`, proceed.
   - `active` → crashed run detected. Read execution log; find last `[x]` line; resume from next phase.
   - `paused` → check Questions section for a `### A:` answer. If present, clear status back to `active` and resume. If not, exit with a message.
   - `done` / `failed` → exit with a message ("already complete — move back to inbox to re-run").
   - `scheduled` → refuse; user should wait for cron.
4. Read `git log --oneline -20` in `~/.claude/skills/higgsfield/` and include the last 20 auto-learn commits in context (self-learning rule from parent §8).
5. Append `[x] <timestamp> Phase 0 intake ✅` to execution log.

### 3.3 VO (Phase 1) — only if `vo.script` present

1. Navigate to `/audio`.
2. Via `browser_evaluate`: set the composer to use-case=Voiceover, model=Eleven v3 (or `vo.model`), voice=`vo.voice`, paste `vo.script` into text input.
3. Read the waveform mm:ss estimate from the DOM (pre-gen).
4. Click Generate.
5. Poll completion by watching for the audio file in DOM history.
6. Download MP3 via `curl` to `~/Higgsfield-out/<slug>/vo.mp3`.
7. Run `engine/probe_duration.sh vo.mp3` → actual duration.
8. If `|actual - estimate| > 0.5s`, log the drift; actual duration wins.
9. Log: `[x] <timestamp> Phase 1 VO ✅ · <model>/<voice> · <actual>s · <cost> cr`.

### 3.4 Plan (Phase 2)

1. If `shots:` already has entries, skip (respect pre-populated plan).
2. Otherwise, Claude plans N shots + M transitions to fit the VO duration (or explicit `duration:`). Rules:
   - Aim for 5s shots (Kling 3.0 floor that's not abrupt).
   - Match shot count to script beats.
   - Add transitions per `transitions.mode` (all-cuts / all-seamless / half-half / custom).
3. If script has ambiguous beat count vs. target shot count → pause: write `### Q: <question>` under `## Questions`, set `status: paused`, exit.
4. Otherwise write plan into `shots:` frontmatter.
5. Log: `[x] Phase 2 plan: <N> shots + <M> transitions, total <seconds>s`.

### 3.5 Images (Phase 3) — parallel

1. Determine worker count: `min(N, 6)`.
2. Spawn that many Playwright tabs via `browser_tabs action=new` for `/ai/image?model=nano-banana-pro`.
3. For each tab (sequential driver — one at a time):
   - Select that tab.
   - Clear leftover state (reference images, prompt).
   - Set aspect = frontmatter `aspect`, resolution = `2K` (free), batch = 1.
   - Verify Unlimited toggle ON (per trap #22). If button label says `Generate ✨ N`, flip the toggle.
   - Type shot prompt.
   - Click Generate; verify a new history row appeared.
4. Wait for all N jobs to complete (poll `/asset/image` or wait for history rows to have CDN URLs).
5. Download all N images via parallel `Agent` subagents:
   ```
   Agent(description="Download shot 1-3 images",
         subagent_type="general-purpose", model="haiku",
         prompt="curl -sL <url-1> -o shot1.png; curl -sL <url-2> -o shot2.png; ...")
   Agent(description="Download shot 4-6 images", ...)
   ```
   (Two parallel agents, 3 downloads each; deterministic work.)
6. Run QC via parallel `Agent` subagents (one per shot):
   ```
   Agent(description="QC shot 1 image",
         subagent_type="general-purpose", model="haiku",
         prompt="Read ~/Higgsfield-out/<slug>/shot1.png. The prompt was: '<prompt>'. Check ≥4 of: <top-priority elements>. Report PASS or FAIL with reason.")
   ```
   Up to 6 parallel subagents dispatched in ONE message.
7. Collect results. For each FAIL → retry attempt (up to 3 per shot):
   - Tighten prompt (Claude rewrites in-context).
   - Re-submit to that tab.
   - Re-QC.
   - After 3 attempts, log `[!]` and continue.
8. Log per shot: `[x] Phase 3 shot <n> image ✅ (attempt <k>) · <model> 2k · <cost> cr`.

### 3.6 Videos (Phase 4) — parallel

Same shape as Phase 3 but:
- Tabs on `/ai/video` with Kling 3.0 selected.
- Upload each shot's PNG to its tab's Start frame.
- Set duration per shot (from `shots[].duration`, default 5s) via the hidden `<input type="range">` helper (trap #21).
- Type motion prompt.
- Click Generate.
- Parallel download + QC via Agent subagents (vision check on first/mid/last frames).

### 3.7 Transitions (Phase 5) — parallel

For each `transitions.seamless_pairs[]`:
1. Run `engine/extract_frames.sh shot<A>.mp4 shot<B>.mp4 /tmp/transitions-<slug>/` (parallel via Agent).
2. For each pair, dispatch to a Kling 3.0 tab: upload Start = `shot<A>-last.png`, End = `shot<B>-first.png`, duration 3s, prompt from `workflows.md` W11 Hollywood patterns.
3. Generate, wait, download.
4. QC each transition via subagent (check seam continuity at frame boundaries).

### 3.8 Stitch (Phase 6)

1. Build manifest.json (in-context Claude task; small JSON blob).
2. Call `engine/stitch.sh manifest.json`.
3. Verify output MP4 exists + has expected duration.
4. Log: `[x] Phase 6 stitch ✅ · final <seconds>s · <MB>`.

### 3.9 Finalize (Phase 7)

1. Set `status: done` (or `partial` if any `[!]` in log).
2. Fill `## Outputs` with wiki-links.
3. Archive verbose run log to `~/Obsidian/Higgsfield/_runs/<slug>-<timestamp>.md`.
4. If any auto-edits landed during the run, append their commit hashes to `## Auto-edits made during this run`.
5. Close the browser:
   ```js
   // browser_close in Playwright MCP
   ```
6. Print completion summary to the user.

## 4. Parallel subagent dispatch patterns

Three canonical patterns Claude uses during Mode A:

### 4.1 Batch download

After all N video gens complete, parallel-download them:

```
Agent(description="Download shots 1-3", model="haiku",
      prompt="bash -c 'curl -sL <url1> -o shot1.mp4 && curl -sL <url2> -o shot2.mp4 && curl -sL <url3> -o shot3.mp4'")
Agent(description="Download shots 4-6", model="haiku",
      prompt="bash -c 'curl -sL <url4> -o shot4.mp4 && curl -sL <url5> -o shot5.mp4 && curl -sL <url6> -o shot6.mp4'")
```

Both dispatched in a single message → run in parallel. ~2 sec total instead of 10 sec serial.

### 4.2 Vision QC fan-out

After all N images downloaded, parallel-QC each:

```
Agent(description="QC shot 1", model="haiku",
      prompt="Vision-check ~/Higgsfield-out/<slug>/shot1.png against this prompt: <prompt>.
              Look for: <5 head-noun elements>.
              Report {status: PASS|FAIL, missing_elements: [...], suggestion: <prompt rewrite if FAIL>}.")
# ...repeat for shots 2-6, all in one message
```

Up to 6 parallel subagents per batch. Each runs for ~15-30s. Total ~30s vs. 3 min serial.

### 4.3 Frame extraction fan-out (Phase 5 prep)

For M transitions, extract M pairs of frames in parallel:

```
Agent(description="Extract frames for T1 and T2", model="haiku",
      prompt="bash ~/.claude/skills/higgsfield/engine/extract_frames.sh shot1.mp4 shot2.mp4 /tmp/t1/;
              bash ~/.claude/skills/higgsfield/engine/extract_frames.sh shot2.mp4 shot3.mp4 /tmp/t2/")
Agent(description="Extract frames for T3", ...)
```

Deterministic, fast, safe to parallelize.

## 5. Mode B cron wiring

### 5.1 One-time setup

User tells Claude: "Set up the Higgsfield scheduler."

Claude invokes:

```
CronCreate(
  schedule: "*/15 * * * *",   // every 15 minutes
  prompt: "higgsfield scheduler sweep"
)
```

That's it. The trigger is created; user can inspect via `CronList`, remove via `CronDelete`.

### 5.2 Sweep execution (each cron fire)

When cron fires with prompt "higgsfield scheduler sweep", Claude runs:

```bash
bash ~/.claude/skills/higgsfield/engine/preflight.sh
bash ~/.claude/skills/higgsfield/engine/sweep.sh
```

`sweep.sh`:
1. Lists all notes in `~/Obsidian/Higgsfield/Projects/` where `status: scheduled`.
2. For each, parses the `schedule:` field into a next-run time (use `python3 -c` with `dateparser` or built-in datetime).
3. Filters to projects where `next_run <= now`.
4. Prints the oldest-matching slug to stdout (one per sweep; single-threaded cron mode).
5. Exits 0 if no projects due; 1 if error.

If `sweep.sh` emits a slug, Claude dispatches Mode A on that slug (uses the §3 playbook). If it emits nothing, Claude exits without running anything.

### 5.3 schedule: field semantics

Supported values for `schedule:`:
- `"every 2 hours"` / `"every 30 minutes"` / `"every day"` → recurring
- `"daily at 09:00"` → recurring at specific time
- `"2026-04-25T14:00"` → one-shot

On project completion:
- If recurring → set `status: scheduled` again, update internal `next_run` tracking (stored in a hidden frontmatter field `_next_run:`).
- If one-shot → set `status: done`.

**Unparseable `schedule:` field**: `sweep.sh` skips that project and appends a one-line error to `~/Obsidian/Higgsfield/_runs/sweep-errors.md` (slug + raw schedule value + parse error). Does not set `status: failed` — the user fixes the field manually. Next sweep re-tries parse.

## 6. Crash recovery / resume

When Claude enters Mode A on a project with `status: active` and no live session:
1. Parse execution log between `<!-- engine:begin -->` and `<!-- engine:end -->`.
2. Find the last line with `[x]` prefix (completed phase). If NO `[x]` lines exist (crashed before Phase 0 could log anything), start from Phase 0.
3. Identify the first phase NOT marked `[x]` → resume there.
4. Respect existing `shots:` frontmatter (don't re-plan).
5. Skip any sub-steps whose outputs exist on disk (`~/Higgsfield-out/<slug>/shot*.mp4`).
6. Log a resume marker: `[x] <timestamp> RESUME from <phase> (prior session crashed)`.

## 7. Pause semantics

When orchestrator writes a `### Q:` block:
1. Set `status: paused`.
2. Save partial state (all completed phases stay logged).
3. Print a clear message to the user: "Paused on <question>. Answer in the note's Questions section with ### A:, then re-invoke with 'run <slug>'."
4. Exit. Do NOT poll the note.

User edits `### A: <answer>` → user re-invokes `run <slug>`. Intake detects `status: paused` + answer present → clears status to `active`, reads the answer, continues.

If user doesn't answer: the note stays paused forever until someone acts. Mode B cron skips paused projects (doesn't reschedule them).

## 8. Browser lifecycle

- **Start of Mode A**: `preflight.sh` cleans stale SingletonLock. Then `browser_navigate` — Playwright MCP spawns Chrome if not running, or re-uses existing.
- **During Mode A**: tabs are spawned/reused across phases as needed. Navigation-heavy — don't optimize tab count below the 6-worker cap.
- **End of Mode A (any status: done/partial/failed/paused)**: call `browser_close`. Frees Chrome memory. Ensures next run starts from a clean slate.
- **Cron mode**: same lifecycle per sweep — each sweep is a fresh Mode A run that opens + closes Chrome.

## 9. New / modified files

### New scripts (engine/)
- `engine/preflight.sh` — SingletonLock cleanup
- `engine/sweep.sh` — scheduler sweep (prints due-slug or nothing)
- `engine/parse_frontmatter.py` — extract YAML frontmatter as JSON (reused across phases)
- `engine/update_status.py` — atomic frontmatter status update

### New SKILL.md section
- `## Orchestrator playbook (Mode A runtime)` — the §3 procedure converted to a Claude-readable numbered list with specific tool calls

### New SKILL.md subsection
- Under "Engine mode": a "Subagent dispatch patterns" block showing the three canonical parallel patterns (§4)

### Updates to existing SKILL.md
- "Engine mode" section gets links to the new playbook.
- Current "Pause / resume via the note" subsection updated to match the exit-cleanly semantics (§7).

### No changes
- Spec doc (this file + parent) — standalone
- Tests — existing engine tests keep passing; the new orchestrator scripts get their own tests in `engine/tests/`
- References `traps.md`, `workflows.md`, `models.md` — unchanged (auto-edit continues to land here during runs)

## 10. Out of scope (stays for later)

- **True parallel browser profiles (Flavor 2).** Not in this spec.
- **GUI dashboard.** The Obsidian note IS the dashboard. No separate UI.
- **Multi-user / remote execution.** Local-only.
- **Prompt caching for subagents.** Let each subagent cold-start; they're stateless and ephemeral.
- **Auto-commit of Obsidian vault.** The vault is local; no git in the vault itself (the skill dir has its own git, that's separate).

## 11. Implementation phasing (high-level)

The `writing-plans` skill will turn this spec into bite-sized tasks. Expected phasing:
1. Write `engine/preflight.sh` + test.
2. Write `engine/sweep.sh` + test.
3. Write `engine/parse_frontmatter.py` + test.
4. Write `engine/update_status.py` + test.
5. Add "Orchestrator playbook" section to SKILL.md.
6. Add "Subagent dispatch patterns" subsection to SKILL.md.
7. Update existing "Pause / resume" subsection for exit-cleanly semantics.
8. Document CronCreate setup in SKILL.md's Mode D section.
9. Smoke test: run smoke-test through the orchestrator playbook (re-validate Mode A end-to-end).
10. Smoke test: Mode B — mark a project `status: scheduled`, wait 15 min, verify cron picked it up.
11. Crash-resume test: kill a run mid-Phase-4, re-invoke, verify resume works from log.

---

*End of runtime spec.*
