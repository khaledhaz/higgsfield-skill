# Design: Agentic Higgsfield Engine with Obsidian Orchestration

**Date:** 2026-04-22
**Status:** Approved
**Supersedes:** none
**Related skills:** `higgsfield` (this skill), `superpowers:writing-plans` (next step)

## 1. Purpose

Turn the `higgsfield` skill from a single-tab, manually-driven script runner into an agentic engine that:

- Reads a project spec from an Obsidian note, executes it end-to-end, and writes results back into the same note.
- Uses up to 6 concurrent browser tabs so a multi-shot video completes in ~14 min instead of ~50 min.
- Treats the voiceover (VO) duration as authoritative when a VO exists — never guesses runtime.
- Pauses only on spec-level ambiguity (via a Q/A block in the note); retries silently on technical failures up to 3× per artifact.
- Teaches itself: when it discovers a novel UI behavior, prompt pattern, or model quirk during a run, it writes the fix back into its own skill files (version-controlled via git).

## 2. Goals and non-goals

**Goals**
- Unattended completion of a typical multi-shot narrative video in under 15 minutes of wall-clock time.
- One Obsidian note = one project = single source of truth for spec + execution log + outputs.
- Four invocation modes (single, queue, parallel, scheduled) all route to the same engine.
- Self-learning: skill files stay current as Higgsfield's UI and content policies evolve.
- Bounded retry policy (3 per artifact) — prevents runaway credit spend on stuck gens.

**Non-goals**
- Full video NLE functionality. Final stitching is ffmpeg concat + optional crossfade only.
- Cloud / remote execution. Everything runs on the local Mac.
- Real-time collaboration on a vault. Single user, local vault.
- Obsidian plugin development. We use the vault's filesystem; Obsidian itself doesn't need customization.
- Replacing the user's judgment. The user remains the final arbiter on style, voice choice, and creative pauses.

## 3. Architecture

```
                    ┌──────────────────────────────────┐
                    │  Obsidian Vault (local)          │
                    │  ~/Obsidian/Higgsfield/          │
                    │  ├─ Projects/     (.md files)    │
                    │  │   (status frontmatter field   │
                    │  │    controls lifecycle)        │
                    │  ├─ _templates/                  │
                    │  └─ _runs/        (verbose logs) │
                    └────────────┬─────────────────────┘
                                 │ read spec / write log
                                 ▼
     ┌──────────────────────────────────────────────────────────────┐
     │  higgsfield engine (the skill, plus engine/ scripts)         │
     │                                                               │
     │   parse spec ─► plan DAG ─► execute DAG ─► QC loop ─► stitch │
     │                                    │                          │
     │                                    ▼                          │
     │                         multi-tab dispatcher                 │
     │                         (Playwright MCP, up to 6 workers)    │
     └────────────────────────────┬─────────────────────────────────┘
                                  │
                                  ▼
            ┌─────────────────────────────────────────┐
            │  Higgsfield (web)     local ffmpeg      │
            │  • Audio   /audio     • frame extract   │
            │  • Video   /ai/video  • normalize       │
            │  • Image   /ai/image  • concat          │
            └─────────────────────────────────────────┘
```

**Single source of truth**: the project note. The engine reads it on start, continuously writes progress back, and the final MP4 link lives inside it.

**Four invocation modes** all dispatch to the same phase pipeline:
- **A** — Fire-and-forget: run one named project.
- **B** — Inbox queue: process all `status: inbox` projects sequentially.
- **C** — Parallel scratchpad: up to 3 projects running simultaneously, sharing a pool of 6 worker tabs.
- **D** — Scheduled: projects marked `status: scheduled` with a `schedule:` field fire on their own cadence.

## 4. Obsidian vault structure

**Vault path**: `~/Obsidian/Higgsfield/` (created by `engine/init_vault.sh`; user may symlink into iCloud or Dropbox after creation).

**Flat folder layout** — status is tracked in frontmatter, not folders:

```
~/Obsidian/Higgsfield/
├── Projects/         all project notes; status field determines lifecycle
├── _templates/       Templater-compatible project template
│   └── new-project.md
└── _runs/            verbose per-run logs for debugging (auto-gc after 30 days)
```

**Large binaries live outside the vault**: under `~/Higgsfield-out/<project-slug>/`. The vault stores only the `.md` spec + wiki-links to assets. Keeps the vault fast and keeps Obsidian sync services happy.

**Project note template** (`~/Obsidian/Higgsfield/_templates/new-project.md`):

```markdown
---
project: example-slug
status: inbox                    # inbox | scheduled | active | paused | done | failed | partial
aspect: 16:9
duration: vo-driven              # "vo-driven" (use VO length) or explicit "30s"
style_reference: ~/path/to/ref.png   # optional, any local image path
vo:
  script: |
    (paste the narration script here)
  model: eleven-v3
  voice: TALLULAH                # specific voice name, or "ask" to pause for user pick
transitions:
  mode: half-half                # all-cuts | all-seamless | half-half | custom
  seamless_pairs: []             # engine fills this if mode=half-half; you override if custom
retries_per_shot: 3              # per-artifact retry budget (see §7)
schedule: null                   # only used when status=scheduled, see §8
shots: []                         # engine fills this in Phase 2; you can pre-fill to override
---

## Script
(human-readable script)

## Style notes
(free-form direction, references, tone)

## Execution log
<!-- engine:begin -->
(engine writes timestamped entries here — NEVER edit this block by hand)
<!-- engine:end -->

## Questions
<!-- engine writes blocking questions here when it pauses -->

## Outputs
- VO: (linked when ready)
- Final: (linked when ready)

## Auto-edits made during this run
(engine lists any skill self-edits it made while running this project, with commit hashes)
```

**Lifecycle via the `status` frontmatter field**:
- `inbox` — created, not yet started.
- `scheduled` — waiting for a `schedule:` cron cadence to fire.
- `active` — engine is currently driving it.
- `paused` — engine hit a spec-level ambiguity; waiting for a `### A:` answer in the Questions section.
- `done` — finished successfully, final MP4 linked.
- `failed` — retries exhausted or hard error; project did not complete. Manually resumable by setting status back to `inbox`.
- `partial` — completed with some shots/transitions failed; final MP4 stitched from best-available attempts.

**Engine edit scope inside the note**:
- Only writes inside `<!-- engine:begin -->`…`<!-- engine:end -->`, the `## Questions` section, the `## Outputs` section, the `## Auto-edits made during this run` section, and the `status` + `shots` frontmatter fields. Everything else is human-owned.

**Pause / resume mechanism**:
- On pause, engine writes a `### Q: <question>` block under `## Questions` and sets `status: paused`.
- User edits `### A: <answer>` directly below and saves.
- An engine watcher (polls the note's mtime every 30s during Mode A/C, or re-checks on the next cron fire in Mode D) detects the `### A:` and resumes by flipping status back to `active`.

## 5. Execution pipeline (the DAG)

**Core rule — VO-first timing**: when `vo.script` is set and `duration: vo-driven`, the VO's measured duration is authoritative. Shot count and per-shot length are derived from it. Without a VO, `duration:` is taken literally.

**Seven phases**:

| # | Phase | Shape | What it does |
|---|---|---|---|
| 0 | Intake | serial | Parse frontmatter, validate required fields, set `status: active`, log start |
| 1 | VO | serial | Submit VO on `/audio`; read waveform duration estimate; after gen, ffprobe actual duration |
| 2 | Plan | serial | Plan N shots + M transitions to fit VO duration; write into `shots:` frontmatter; pause if script has ambiguous beat count |
| 3 | Images | **parallel (min(N, 6) workers)** | Generate N shot hero images on NBP; QC-loop each (see §7) |
| 4 | Videos | **parallel (min(N, 6) workers)** | Animate each image on Kling 3.0; QC-loop each |
| 5 | Transitions | **parallel (min(M, 6) workers)** | Extract last frame of clip A + first frame of clip B; generate M Kling 3.0 transitions; QC-loop |
| 6 | Stitch | serial | ffmpeg normalize + concat; overlay VO audio |
| 7 | Finalize | serial | Set `status: done` (or `partial` if any shot failed), write Outputs section, archive run log |

**VO-first mechanics (Phase 1 + 2 interplay)**:

1. Phase 1 navigates to `/audio`, sets voice + model + script in the composer.
2. Before clicking Generate: engine reads the waveform's `mm:ss` duration estimate from the DOM.
3. Phase 2 starts planning against that estimate (shot count, per-shot length) while Phase 1's generation runs.
4. When the VO file is downloaded, `engine/probe_duration.sh vo.mp3` returns the actual duration.
5. If actual vs. estimate is within **±0.5s**, the plan stands.
6. If divergence exceeds 0.5s, engine re-plans shots to fit the actual duration and logs the adjustment in the execution log. No pause.

**Ambiguity pauses in Phase 2** (one canonical example):
- VO is 41s, engine wants 6 shots averaging ~6s.
- Script has 5 distinct beats + a filler sentence → not a clean 6-way split.
- Engine writes to Questions:
  ```markdown
  ### Q: Script has 5 distinct beats but the 41s VO wants 6 shots.
  (1) double-beat shot 3 (the raid description)
  (2) add a closing beat not in the script
  (3) make shot 3 longer (~11s), keep 5 shots
  Edit "### A: 1|2|3" below.
  ```
- Status flips to `paused`; engine returns. On resume, reads A, applies, continues.

**Parallelism bounds**:
- Up to 6 worker tabs per project.
- Higgsfield Creator plan's server-side cap is 8 concurrent video jobs. Exceeding this by spawning more tabs just queues server-side — no speedup past 6 driver tabs.
- Chrome memory is ~300MB per tab. 6 workers + main + audio + monitor = ~2.7GB. Comfortable.

**Throughput targets** (6-shot video, 3 transitions, VO):
- Old approach (single tab, serial submit): ~50 min.
- This design: critical path ~**14 min**, dominated by the slowest single Kling 3.0 gen.

## 6. Multi-tab dispatch

Claude Code's Playwright driver is single-threaded: only one tab is being *acted on* at a time. Multi-tab parallelism here means **submit across N tabs in sequence, then let N server-side jobs run in parallel while the driver moves on**.

**Tab roles** (lazy-spawned, up to the cap):

| Tab | Purpose | Pinned URL |
|---|---|---|
| `main` | driver's primary; intake, planning, stitching dispatch | varies |
| `audio` | VO gen + re-gen | `/audio` |
| `monitor` | polling generations by URL | `/asset/video` |
| `workers` (up to 6) | Kling 3.0 composer tabs for shots + transitions | `/ai/video` (Kling 3.0 selected) |

Workers are **recycled across phases**: a worker that animated Shot 1 in Phase 4 is reused for Transition 1 in Phase 5, then torn down in Phase 7.

**Per-worker dispatch sequence** (one Kling 3.0 animation):

```
1. browser_tabs select=worker_n
2. browser_evaluate: clear Start + End frames (X buttons)
3. browser_evaluate: click Start frame label (opens file picker)
4. browser_file_upload: shot-N-start.png
5. (if transition) browser_evaluate: click End frame label
6. (if transition) browser_file_upload: shot-N-end.png
7. browser_evaluate: set Kling 3.0 duration via hidden <input type="range"> (see traps.md #21)
8. browser_type: prompt into Lexical editor
9. browser_evaluate: click Generate; verify "Generating" appeared
10. Record job reference in project note
```

Driver then selects the next worker and repeats. When all submits are in, driver moves to a "collect" pass:

```
for each shot in batch:
  browser_tabs select=worker_n
  wait for job status == done (poll every 15s)
  browser_evaluate: extract CDN URL from DOM
  download MP4 to ~/Higgsfield-out/<slug>/shot-N.mp4
  update project note with ✅ + thumbnail link
```

**Cross-project worker sharing (Mode C)**:
- Projects in Phase 3/4/5 compete for worker tabs.
- Round-robin allocation: if project A has 6 pending submits and project B has 3, the 6 workers are split 4/2 first come, first served.
- When a tab's current job finishes (collect pass), it flips to whichever project has the oldest pending submit.
- Engine does not pre-allocate tabs per project; it's a pure pool.

**Failure handling in a worker**:
- Tab dies (SingletonLock) → engine runs the established recovery (`pkill` + unlink `SingletonLock` + respawn) and re-submits the pending job. Retry counter increments.
- Gen returns content-rejection → engine softens specific flagged terms (e.g., `warship` → `naval vessel`, `raid` → `boarding operation`) and re-submits as attempt 2.
- QC fails after download → see §7.

## 7. QC loop (retry ladder)

After each artifact downloads, Claude runs a vision check on it:

| Artifact | Check | Pass criteria |
|---|---|---|
| VO (.mp3) | ffprobe duration + first/last 0.5s spectral | file exists, duration ≥ 50% of estimate, not silent |
| Shot image (PNG) | Claude reads the PNG | ≥4 of the prompt's 5 top-priority elements present (priority = head-nouns like "tanker", "warship", "fog", plus explicit color-grade cues); aspect ratio matches spec |
| Shot animation (MP4) | Claude reads first/mid/last frame | same elements as source image; motion implied by prompt present |
| Transition (MP4) | Claude reads transition's first frame vs. clip-A's last frame AND transition's last frame vs. clip-B's first frame | visual continuity — no flash, no jump, matching color grade |

**Retry ladder (3 attempts per artifact)**:

1. **Attempt 1**: original planned prompt.
2. **Attempt 2**: Claude rewrites — keeps creative intent, adds missing elements, adds anti-prompts for visible errors ("no flash", "no cut", "keep warship visible right-third").
3. **Attempt 3**: Claude simplifies aggressively — removes secondary subjects, boosts atmosphere keywords, re-specifies camera motion.

**After 3 failed attempts**:
- **Spec ambiguity** (QC reports "prompt was vague about subject identity") → pause with `### Q:` in Questions section. Status: `paused`.
- **Technical quality** (consistent seams or subject drift) → mark artifact with ❌ in the execution log, keep the best-ranked attempt, continue with the rest of the project. At Phase 6, engine decides: use the failed attempt, or replace a failed transition with a hard cut.

**No global credit ceiling** (per user preference). The per-artifact 3-retry cap is the only bound.

**Execution log format during QC** (inside `<!-- engine:begin -->`…`<!-- engine:end -->`):

```
- [x] 14:02 VO generated · 42.3s · eleven-v3/TALLULAH · 1.35 cr
- [x] 14:05 Plan: 6 shots × 5s + 3 seamless, total 42s
- [x] 14:07 Shot 1 image ✅ (attempt 1) · nano-banana-pro 2k
- [→] 14:09 Shot 3 image: attempt 1 ❌ (missing: helicopter rotors; too dark)
  - [→] 14:10 Shot 3 image: attempt 2 (tightened: "rotors clearly visible")
- [x] 14:11 Shot 3 image ✅ (attempt 2)
- [!] 14:26 T2 transition ❌ after 3 attempts — will hard-cut at stitch
```

`[x]` = success, `[→]` = in-flight, `[!]` = final failure, `[?]` = paused for user.

## 8. Self-learning (skill auto-edit)

When the engine discovers a new fact during a run — a UI behavior, a prompt pattern that works, a model quirk — it writes that fact back into the skill files so future runs handle it natively.

**Triggers** (what counts as a discovery worth recording):
- A UI control behaves differently than the skill predicted (type, position, commit mechanism).
- A repeatable prompt-rewrite pattern that unblocked a QC failure.
- A new model parameter or cost datum observed.
- A recurring browser-automation glitch.
- A content-policy rewording rule that consistently passes.

**Non-triggers** (not recorded automatically):
- Anything already documented in the skill.
- One-off content rejections where the root cause is unclear.
- User-specific style preferences (those go to the memory system, not the skill).

**Destination routing by discovery type**:

| Discovery | File | Block |
|---|---|---|
| UI behavior / hidden control | `references/traps.md` | `<!-- auto-edit:traps category=<name> -->` |
| Prompt-rewrite pattern | `references/workflows.md` | `<!-- auto-edit:workflow w=<W-id> section=patterns -->` |
| Model parameter / cost | `references/models.md` | `<!-- auto-edit:model m=<model-id> -->` |
| Session-wide rule | `SKILL.md` "Current model availability" | `<!-- auto-edit:skill section=availability -->` |
| User preference (mid-run) | memory system | `~/.claude/projects/.../memory/<type>_<topic>.md` + MEMORY.md index update |

**Guardrails**:
1. **Append-only by default.** New entries are added; existing text is not rewritten unless the new finding directly contradicts old text — in which case the old line gets a `<!-- superseded by auto-edit <date> -->` comment appended, not deleted.
2. **Marker-locked writes.** The engine writes only between `<!-- auto-edit:... -->` and `<!-- /auto-edit:... -->` markers. Before any write, the engine re-reads the file and confirms both markers are present; if not, the write is skipped and logged to `_runs/skill-edit-failures.md`.
3. **Rate limit: 5 auto-edits per run.** Prevents a single bad run from flooding the skill with commits.
4. **Git-backed rollback.** `~/.claude/skills/higgsfield/.git/` exists. Each auto-edit is a single commit with format:
   ```
   auto-learn: <one-line summary>
   Spec: <project-slug>
   Run: <ISO timestamp>
   Source event: <what triggered the discovery>
   ```
   Recovery: `git revert <hash>` in the skill dir undoes a bad edit.
5. **Per-run changelog surfaced in project note.** Final Done note includes an `## Auto-edits made during this run` section listing every commit hash + one-line summary.

**Pre-run context load**: at the start of every engine invocation, `git log --oneline -20` in the skill dir is read and included in Claude's context. Prevents re-discovering the same thing and re-committing it.

## 9. Invocation modes (4 entry points, one engine)

**Mode A — Fire-and-forget (single project)**

Natural language trigger: `"Run <project-slug>"`. Engine locates `~/Obsidian/Higgsfield/Projects/<slug>.md`, executes phases 0→7 end-to-end.

**Mode B — Inbox queue**

Natural language trigger: `"Run the inbox"`. Engine:
1. Lists notes in `Projects/` where `status: inbox`.
2. Sorts oldest-first by file mtime.
3. Runs each in turn; each completes (or pauses/fails) before the next starts.

No cross-project parallelism in Mode B. Intended for "process this backlog while I do other things".

**Mode C — Parallel scratchpad**

Natural language trigger: `"Run X, Y, Z in parallel"` (up to 3 projects). Engine:
1. Opens one `main` + one `audio` tab per project.
2. Shares 1 `monitor` tab and a pool of up to 6 worker tabs across all active projects.
3. Worker tabs allocated round-robin to whichever project has the oldest pending submit.

Server-side contention: Higgsfield's 8-slot queue is shared, so 3 projects each with 6 pending video jobs fills a 18-deep queue and each project runs at ~1/3 speed. Acceptable — still faster than serial.

**Mode D — Scheduled projects**

Per user preference, projects opt in individually via frontmatter:

```yaml
status: scheduled
schedule: "every 2 hours"          # natural-language cadence
# or
schedule: "daily at 09:00"
# or
schedule: "2026-04-25T14:00"       # one-shot
```

Setup (once): `"Set up the Higgsfield scheduler"` — creates a `CronCreate` trigger that fires every 15 minutes with the prompt `"higgsfield scheduler sweep"`. Each sweep:

1. Lists notes where `status: scheduled`.
2. For each, parses `schedule:` into a next-run time.
3. If next-run ≤ now:
   - Set `status: active`.
   - Run the project through phases 0→7.
   - On completion, if `schedule:` is recurring → set `status: scheduled` and log run time; if one-shot → set `status: done`.
4. Paused projects: skipped on this sweep; picked up next sweep if their `### A:` has appeared.

**Mode picker for ambiguous natural language**:

| User says | Mode picked |
|---|---|
| "run X" (one name) | A |
| "run the inbox" | B |
| "run X, Y, Z" / "X and Y in parallel" | C |
| "schedule X" / "set up the scheduler" | D setup |
| "scheduler sweep" (cron-triggered) | D execute |
| anything ambiguous | engine asks the user **conversationally** (in the current chat turn, not via a note) before dispatching |

## 10. Skill file layout

**New files**

```
~/.claude/skills/higgsfield/
├── docs/
│   └── 2026-04-22-agentic-obsidian-engine-design.md   (this file)
├── engine/
│   ├── README.md
│   ├── init_vault.sh
│   ├── extract_frames.sh
│   ├── stitch.sh
│   └── probe_duration.sh
└── .git/                                 (git init, for auto-edit rollback)
```

**Edits to existing files**

| File | Change |
|---|---|
| `SKILL.md` | Add "Engine mode" section (~200 lines) with phase-by-phase playbook, tab-allocation rules, pause format, QC loop, mode dispatch. Add "Self-learning rules" section (~80 lines). Add `<!-- auto-edit:skill section=availability -->` markers. |
| `references/traps.md` | Add `<!-- auto-edit:traps category=<name> -->` markers at end of each category. |
| `references/workflows.md` | Add `<!-- auto-edit:workflow w=<W-id> section=patterns -->` markers inside each W-section's patterns block. |
| `references/models.md` | Add `<!-- auto-edit:model m=<model-id> -->` markers per model row. |
| `references/shortcuts.md` | Unchanged. |

**Scripts — purpose and signatures**

- `engine/init_vault.sh` — idempotent. Creates `~/Obsidian/Higgsfield/{Projects,_templates,_runs}`. Writes default project template into `_templates/new-project.md`.
- `engine/extract_frames.sh <clipA.mp4> <clipB.mp4> <out-dir>` — writes `<out-dir>/clipA-last.png` and `<out-dir>/clipB-first.png`. Uses `ffmpeg -sseof -0.1 … -vframes 1`.
- `engine/stitch.sh <manifest.json>` — reads JSON manifest of clips with per-clip `{path, type: shot|transition|cut-here, duration}`, normalizes each to 1920×1080@24fps, concatenates (Kling transitions = no xfade; cuts = optional 0.4s xfade per config), overlays VO audio if manifest specifies. Output path also from manifest.
- `engine/probe_duration.sh <audio-or-video-file>` — ffprobe wrapper, emits duration in seconds to stdout.

**Inline Claude tasks** (no separate script needed; small enough to execute via Bash from skill prompts):
- YAML frontmatter parsing (`python -c "import yaml, sys; print(yaml.safe_load(sys.stdin))"`)
- Appending to the engine-log block (Edit tool)
- Updating `status:` frontmatter (Edit tool or small Python helper)
- Watching a note's mtime for `### A:` resume (Bash `stat` in a loop)

**Optional: slash commands** (in `~/.claude/skills/` — Claude Code loads automatically):
- `/hf-run <slug>` → Mode A
- `/hf-inbox` → Mode B
- `/hf-parallel <slug1> <slug2>…` → Mode C
- `/hf-scheduler-sweep` → Mode D execute (same prompt the cron fires)
- `/hf-init-vault` → run `engine/init_vault.sh`

## 11. Implementation phasing (high-level)

The next step is `superpowers:writing-plans` turning this spec into an executable plan. Expected phase breakdown the plan will cover:

1. **Git-init the skill directory** — single commit "baseline" of current state so later auto-edits are diffable.
2. **One-time vault bootstrap** — write `engine/init_vault.sh`, run it, verify vault exists.
3. **Engine deterministic scripts** — write `stitch.sh`, `extract_frames.sh`, `probe_duration.sh`. Unit-test each against the Iran oil clips already on disk.
4. **Add marker blocks to reference files** — non-destructive edits to `traps.md`, `workflows.md`, `models.md`, `SKILL.md`.
5. **Write SKILL.md engine mode section** — the phase-by-phase playbook.
6. **Write SKILL.md self-learning section** — auto-edit rules and guardrails.
7. **Smoke test (Mode A, single-shot)** — create a tiny single-shot project in the vault, run it end-to-end, verify final MP4 + note log + zero auto-edits needed.
8. **Full test (Mode A, multi-shot)** — rerun the Iran oil project from a fresh Obsidian note; compare output to the manually-built final MP4 from the previous session.
9. **Mode B test** — queue 2 small projects in inbox, run.
10. **Mode C test** — run 2 projects in parallel, observe worker allocation.
11. **Mode D setup** — mark one project `status: scheduled`, cron it for 5 min from now, verify sweep fires and runs it.
12. **Self-learning smoke test** — deliberately break a prompt (trigger a known-fixable content rejection), verify engine softens, succeeds, and commits an auto-edit to `workflows.md` or `traps.md`.

## 12. Appendices

### A. Example project note — complete

```markdown
---
project: iran-oil-tiffany-raid
status: inbox
aspect: 16:9
duration: vo-driven
style_reference: ~/Downloads/Images/HeyFriends/hf_20260414_134458_a347b0fd-0767-4158-87d1-65109cd51edd.png
vo:
  script: |
    الغضب الاقتصادي الأميركي يستمر في حصد السفن الإيرانية في المياه الدولية...
    فبعد السيطرة على سفينة توسكا التجارية... أعلنت القيادة الأميركية مداهمة السفينة
    "أم تي تيفاني" المرتبطة بإيران بمنطقة المحيطين الهندي والهادئ...
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
(full Arabic script, possibly with English translation below)

## Style notes
Cinematic dusk/dawn, teal-and-rust grade, heavy volumetric fog. Defense/geopolitical tone.

## Execution log
<!-- engine:begin -->
<!-- engine:end -->

## Questions

## Outputs
- VO:
- Final:

## Auto-edits made during this run
```

### B. Cron setup (Mode D)

One-time, via Claude Code's `CronCreate`:
```
schedule: "every 15 minutes"
prompt: "higgsfield scheduler sweep"
```

To inspect or remove: `CronList` / `CronDelete`.

### C. Marker block reference

All auto-edit destinations use HTML comment markers:

```html
<!-- auto-edit:traps category=session-state -->
<!-- /auto-edit:traps -->
```

```html
<!-- auto-edit:workflow w=W11 section=patterns -->
<!-- /auto-edit:workflow -->
```

```html
<!-- auto-edit:model m=kling-3.0 -->
<!-- /auto-edit:model -->
```

```html
<!-- auto-edit:skill section=availability -->
<!-- /auto-edit:skill -->
```

Engine writes only between opening and closing markers. Outside markers = human-owned.

### D. ffmpeg manifest schema (for stitch.sh)

```json
{
  "output": "~/Higgsfield-out/iran-oil-tiffany-raid/final.mp4",
  "resolution": [1920, 1080],
  "fps": 24,
  "clips": [
    {"path": "...shot1.mp4", "type": "shot", "duration": 5.04},
    {"path": "...T1.mp4",    "type": "transition", "duration": 3.04},
    {"path": "...shot2.mp4", "type": "shot", "duration": 5.04},
    {"path": null,           "type": "cut"},
    {"path": "...shot3.mp4", "type": "shot", "duration": 5.04}
  ],
  "vo": {
    "path": "...vo.mp3",
    "mode": "overlay"
  },
  "cut_xfade": 0.4
}
```

`cut` entries indicate a hard cut between adjacent shots (optionally with a soft 0.4s xfade). Transitions are concatenated with no additional blending (the Kling transition IS the blend).

---

*End of design document.*
