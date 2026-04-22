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
