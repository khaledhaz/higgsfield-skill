# Higgsfield workflow templates

Concrete step-by-step flows for the most common tasks. Copy and adapt.

## W1 — Generate a free photoreal image

**Goal**: One 1K or 2K image, zero credit spend.
**Model**: Nano Banana Pro (user's #1, 306 lifetime gens).

1. Navigate: `/ai/image?model=nano-banana-pro`
2. Verify top-right badge shows **UNLIMITED** on the model card when the picker is open (confirms 365 access active)
3. Settings at bottom bar:
   - Model: Nano Banana Pro
   - Aspect: pick from Auto/1:1/3:4/4:3/2:3/3:2/9:16/16:9/5:4/4:5/21:9
   - Resolution: **1K** (fastest, fully unlimited) or 2K (still unlimited, better detail)
   - Batch: 1-4
   - **Unlimited toggle: ON** (default ON for NBP)
4. Type prompt in the Lexical editor (or prime via localStorage — see shortcuts)
5. Click Generate. Button should say `Generate` with no sparkle-number at 1K/2K+Unlimited. If it says `✨ N`, abort and check the toggle.
6. ~15-25s to complete. Result appears top-left of History grid.

## W2 — Generate a fashion/aesthetic image with Soul 2.0 or Soul Cinema

**Goal**: Free cinematic-quality image using the 10,000 free-gens pool.
**Model**: Soul 2.0 (fashion) or Soul Cinema (film-still).

1. Navigate: `/ai/image?model=soul-v2` (fashion) or `/ai/image?model=soul-cinematic` (cinematic)
2. Defaults (don't fight these unless needed):
   - Soul 2.0: 3:4 aspect, 2k resolution
   - Soul Cinema: 16:9 aspect, 2k resolution
3. Optional: attach a Soul ID character via the Character slot. Click "Change" to swap or pick from library. Empty slot is fine too.
4. Color Transfer [NEW] option: upload a reference image to drive color palette (untested — experimental).
5. On/Off toggle's purpose is unclear (film-grain? enhance?); defaults OK.
6. Click Generate. Button shows `Generate · 10000 free gens left` — free within pool.
7. Pool decrements per gen. Reset cadence unconfirmed (likely monthly).

## W3 — Animate an image for zero credits (Kling 2.5 Turbo 720p Unlimited)

**Goal**: 5-second video animation of a still image, 0 credits.
**Model**: Kling 2.5 Turbo — the only truly unlimited video tier.

1. If the image is already a Higgsfield asset, click its **Animate** button on `/asset/image/<uuid>`. If Animate works, skip to step 4.
2. If Animate didn't carry forward, manually: `/ai/video?model=kling-v2-5-turbo`
3. Clear any leftover Start/End frames: **real browser hover** over the slot → click the 24×24 X button at top-right. Repeat for End frame if populated.
4. Upload image to Start frame:
   - Fastest: drag-drop (see shortcuts.md)
   - Standard: click Start slot → pick file
5. Settings:
   - Duration: **5s** (the only duration that enables Unlimited)
   - Resolution: click pill → pick **720p** (1080p costs 6 credits; only 720p+5s is Unlimited)
   - The "**Unlimited mode**" switch appears after you pick 720p; flip it ON
6. Verify Generate button label: `Generate [Unlimited]` (black badge, no sparkle). If it says `Generate ✨ 4` or similar, you haven't flipped the toggle.
7. Write a motion prompt in the textarea. Keep it focused on motion (waves crashing, clouds drifting, camera push-in).
8. Click Generate. **~3-4 min** processing.
9. Video appears in `/asset/video` with play button; the `/ai/video` main area may NOT auto-show it.

## W4 — Animate an image for cheap (Minimax Hailuo 02 at 512p or 768p)

**Goal**: 6-second video animation. Cheaper than Seedance (~6 credits vs 88).
**Model**: Minimax Hailuo 02.

**Key trap**: Minimax interprets Start + End frames as **morph interpolation targets**. Leave End empty for a prompt-driven animation of Start.

1. Navigate: `/ai/video?model=minimax`
2. Explicitly clear leftover Start frame + End frame (hover each, click X). **Do this first** — session state bleeds.
3. Upload your image to Start frame (drag-drop or file picker).
4. **Leave End frame empty** unless you specifically want a morph.
5. Defaults: 6s, 768p, 6 credits.
   - For End frame morph: need at least 768p (512p is blocked when End frame is set).
6. Write motion prompt. Enhance ON will rewrite it into a cinematic brief (expected behavior).
7. Click Generate. ~3 min processing.
8. Result in `/asset/video`.

## W5 — Short cinematic film with Cinema Studio 3.5

**Goal**: Multi-shot cinematic sequence with character and location consistency.

1. Navigate: `/cinema-studio?autoSelectFolder=true`
2. A project is auto-selected (or `+` in left rail creates a new one).
3. Click **Elements** tab:
   - Soul ID characters auto-appear under Personal Elements
   - Click **Create Element** to add Props (e.g., a specific weapon, car, artifact) or Locations (e.g., a rooftop at sunset)
   - Scope: Personal (only you) or Project (shared with team)
4. Back to **Generations** tab. In the prompt:
   - Use `@` to @-mention an Element (character/prop/location): `@Male-Archive stands on @rooftop-sunset`
   - Pick **Genre** / **Style** / **Camera** pills for creative constraints
5. Model: leave as "Cinema Studio 3.5" (it's a meta-router). Duration 8s, resolution 1080p default.
6. Click Generate. **96 credits per 8s clip** (base) — expensive. Can also use Image mode for cinematic stills.
7. AI Director floating button (bottom-right) opens a chat helper for prompt refinement.

**Cost-saving**: for long-form, generate shots individually in cheaper tiers (e.g., stills in Nano Banana Pro free, then animate in Kling 2.5 Turbo 720p free), then stitch externally.

## W6 — Voiceover / lipsync for a character portrait

**Goal**: Character photo → talking video with TTS-generated voice.
**Surface**: Lipsync Studio.

1. Navigate: `/lipsync-studio`
2. Upload the character image.
3. Audio section has two tabs:
   - **Audio text** — type what the character should say, TTS-generate
   - **Generate Audio** — (alternate flow, presumably for AI speech generation)
4. Optional prompt: describe scene details.
5. Model selector: **Wan 2.5 Fast** default (9 credits). Others available: Infiniti Talk, Higgsfield Speak, Google Veo3, Kling.
6. Duration/Resolution pills.
7. Click Generate. ~1-2 min.

## W7 — UGC-style ad with Google Veo 3 Fast (3 free gens)

**Goal**: Creator-archetype talking-head ad (selfie, unboxing, selling).
**Surface**: UGC Factory (inside Lipsync Studio).

1. Navigate: `/lipsync-studio?ugc-studio=true` — opens as a wizard modal
2. Wizard steps (sidebar):
   1. **Template** — pick archetype (General, Selfie, Selling, podcast, driver, beauty)
   2. **Image** — character photo
   3. **Action** — what they do
   4. **Audio text** — what they say
   5. **Audio settings** — voice parameters
   6. **Background** — scene backdrop
3. Model defaults to **Google Veo 3 Fast** with a **3 free-gens** promo
4. Click Next through steps, then Generate on final.

## W8 — Batch-generate variations with one prompt

**Goal**: 4 variants of the same prompt at once.

1. Any image page supports batch size 1-4 via the `-/+` pill on the bar.
2. Set batch to 4. Each variant gets a separate seed.
3. Click Generate — all 4 produced in parallel (within Creator's 8-image concurrency).
4. Cost scales linearly (if not Unlimited). E.g., NBP 4K × 4 = 8 credits.

## W9 — Save + reuse a successful prompt

**Goal**: After one gen lands well, keep iterating on that template.

1. From the asset detail panel: click **Copy** next to the PROMPT field to get the enhanced version.
2. Or click **Recreate** (video) / **Animate** / **Reference** (image) to jump into a new gen with everything pre-loaded.
3. For iteration, Recreate is fastest — it preserves the Enhance-expanded prompt which is usually richer than your original.

## W10 — Quick credit audit

**Where to check**:
- Credit balance: top-right of `/me/settings` OR in the avatar menu
- Spend log: `/me/settings/credits-usage` (data horizon: Feb 7, 2026)
- Plan benefits: `/me/settings/subscription`
- Unlimited access history: `/me/settings/team/unlimited-access-history`

**What to look for**:
- Has spending been disproportionate on 4K NBP or Veo 3.1? Consider downgrading.
- Is the "Extra Concurrent" bundle marketplace showing a new bundle for your most-used model?
- Is Upcoming Invoice unexpectedly high?

## W11 — Seamless transition between two shots (Kling 3.0)

**Goal**: Smooth, non-sci-fi transition clip that bridges the end of clip A into the beginning of clip B. Used to link shots in a narrative.

**Model**: Kling 3.0 (Start + End frame mode).
**Duration**: **3s preferred**, 4s if pacing needs more breathing room. Never longer — it reads as a scene in itself.
**Cost**: ~8.75 credits per transition (same as a normal Kling 3.0 clip).

**Steps**:

1. **Before starting — ask**: cuts or seamless transitions? If cuts, stitch with ffmpeg (see W15) and skip this workflow.
2. Extract the last frame of clip A and the first frame of clip B as PNGs.

   **Tested one-liner** (works with any mp4):
   ```bash
   ffmpeg -y -sseof -0.1 -i clipA.mp4 -vframes 1 -q:v 2 clipA-last.png
   ffmpeg -y -i clipB.mp4 -vframes 1 -q:v 2 clipB-first.png
   ```
   `-sseof -0.1` seeks 0.1s before the end; `-vframes 1` grabs one frame; `-q:v 2` is high-quality JPEG-tier (safe for PNG).
3. Navigate: Video → pick **Kling 3.0** from the nav (the `kling-v3` URL slug doesn't resolve; use the Video dropdown).
4. Start frame slot = **last frame of clip A**. End frame slot = **first frame of clip B**.
5. Duration pill: **3s** (bump to 4s only if 3s feels abrupt). Kling 3.0 duration range is actually **3s–15s** — 5s is just the default. Commit via the hidden `<input type="range">` (see trap #21 for the exact JS). Verify the Duration pill shows `3s` AND the Generate button shows `✨5.25` (not 8.75) before continuing — the label confirms the commit landed.
6. Prompt: keep it plain, "smooth seamless transition between the two frames, no cuts, no flashes, no sci-fi effects, steady camera motion, consistent lighting and atmosphere." Avoid sparkles, portals, morphs, glitches — anything that signals "effect".

   **Hollywood-level patterns that work** (tested, these prompts generate invisible seams):
   - *Fog dissolve*: "Continuous single-take cinematic camera descent from [scene A view] through a rolling fog bank that sweeps right-to-left across the frame, and as the fog parts the scene has changed to [scene B view]. Smooth, steady camera motion, no cuts, no flashes, no sci-fi effects. Consistent teal-and-amber cinematic grade, matching fog density. Hollywood match-dissolve through the fog layer."
   - *Camera-motion dissolve*: "Cinematic continuous single-take camera pull-back. The camera rises and retreats from [scene A], and the frame gradually transitions across [bridging element, e.g., open ocean] toward [scene B]. Smooth, steady camera motion, no cuts, no flashes, no sci-fi effects. Consistent [color grade] grade, gradual light shift from [A lighting] to [B lighting]. Hollywood-grade time-and-space dissolve."
   - *Match-cut*: "Camera glides forward through [shared element between A and B, e.g., water / smoke / architecture]. Motion continues from [A] and arrives at [B] without any flash, cut, or shift in camera speed. Same color grade, same atmosphere."

   **Always include**: "no cuts, no flashes, no sci-fi effects" as an anti-prompt. "Hollywood-grade" or "Hollywood match-dissolve" signals the intended craft level. Always reference both scenes by concrete description, not just "scene A / scene B".
7. Click Generate. Wait for completion, then download.
8. Stitch: `ffmpeg -i clipA.mp4 -i transition.mp4 -i clipB.mp4` with concat demuxer (no xfade on top — the transition clip IS the fade).

**Sanity check on output**: the first frame of the transition should visibly match the last frame of clip A; the last frame should match the first frame of clip B. If it drifts, regenerate with a more constrained prompt or accept a cut instead.

<!-- auto-edit:workflow w=W11 section=patterns -->
<!-- /auto-edit:workflow -->

## W12 — Seedance with eligibility-check wait loop

**Goal**: Use Seedance 2.0 (or Seedance Pro) on an input image that must pass Higgsfield's content-eligibility check. This check can stall on military/political/sensitive imagery.

**The rule**: the skill **must wait** until the input is either Eligible (proceed) or Not Eligible (stop and tell the user). Never guess. Never skip it.

**Steps**:

1. Navigate: `/ai/video?model=seedance_2_0` (or `seedance_pro`).
2. Open the image picker → Image Generations → click the image you want as input.
3. Watch the image tile. One of three states will render: **"Checking content…"**, **eligible** (no label, just selected), or **"Not eligible"** / **"Check eligibility"** remains as a rejection.
4. **While the tile shows "Checking content…":**
   - Wait up to 90 seconds.
   - If still checking at 90s: **reload the page** (full browser reload, not soft-nav), re-open the picker, re-select the same image. Repeat the 90s wait.
   - Loop until state resolves. Expected hard cap: ~5 reload cycles (~7.5 min). If still checking after that, stop and ask the user whether to continue waiting, switch to a different Seedance tier, or swap to a different model.
5. If Eligible: proceed with prompt + Generate.
6. If Not Eligible: stop, report back to the user with the specific image that failed. Do not try to bypass by swapping models silently — the user decides.

**Why the reload**: the check can deadlock client-side. Reload forces a fresh request to Higgsfield's moderation service.

<!-- auto-edit:workflow w=W12 section=patterns -->
<!-- /auto-edit:workflow -->

## W13 — VO-driven narrative video (Eleven v3 as the timing source)

**Goal**: Build a multi-shot video whose total length is dictated by a voiceover narration, not by a fixed shot count.

**Surface (URL matters)**: Higgsfield Audio lives at `/audio` (NOT `/ai/audio`, unlike Image and Video). Page title: "Higgsfield Audio - AI Voice Over & Voice Translation Tool".

**Composer anatomy (bottom bar):**
- **Use-case dial** (left): Voiceover / Change Voice / Translate — pick Voiceover for TTS.
- **Text field** (center): paste the script. Multilingual supported (Arabic, English, etc.).
- **Voice Preset** pill: e.g., "TALLULAH" — click to pick a named voice. Confirm with user; don't guess.
- **Model** pill: e.g., "Eleven v3". Click to switch models.
- **Generate** button: shows credit cost (Eleven v3 ≈ 1.35 credits for ~41s ≈ 0.033 credits/sec — very cheap).

**Layout (rest of page):**
- Left sidebar: project folders (Audio has its own project structure, separate from /asset/all).
- Main area: live waveform **with a duration label (mm:ss)** that renders BEFORE you generate — use this to plan shot count without spending credits.
- "+ New project" at bottom-left to start a fresh audio project.

**Flow (VO first, video second):**

1. **Ask the user** for: the script text, the language, the voice preset (or ask them to pick from the UI if they don't know), and which audio model (default Eleven v3, see models.md). Do not pick a voice for them.
2. Navigate to `/audio`. Set use-case dial to **Voiceover**, model to **Eleven v3**, paste script, pick voice.
3. **Read the waveform's mm:ss label without generating** — this is the estimated duration at the chosen voice speed. Use it to plan the shot breakdown before spending any credits.
4. Confirm the shot breakdown with the user based on the estimated duration: "The VO reads at ~41s; I can map that to 6 × 5s Kling 3.0 clips + 2 × 3s transitions = 36s of video, so we'll either tighten the script or add a buffer shot. Which?"
5. Once approved, click Generate to create the VO. Download the audio.
6. Verify actual duration with `ffprobe -v error -show_entries format=duration -of default=nw=1 vo.mp3` — occasionally differs from the preview estimate by 1–2 seconds.
7. Generate the shots (see W3 for single animation, W11 for transitions).
8. Stitch with ffmpeg: normalize each clip to 1920×1080@24fps, concatenate (with xfade if cuts or concat-only if using Kling transitions), **then overlay the VO as the final audio track**. Ask the user first whether to replace clip audio or mix with it.

**Key rules**:
- Read the waveform duration label BEFORE generating the VO — saves credits and lets the shot plan be right on the first try.
- Do not decide the number of shots, the shot length, or the transition style until you know the VO duration AND have the user's approval of the shot breakdown.
- If the user has prior audio projects visible in the left sidebar (e.g., "Israel Iran Nuclear", "Modern Military Explorer"), ask whether they want to continue in one of those or start a "+ New project".

<!-- auto-edit:workflow w=W13 section=patterns -->
<!-- /auto-edit:workflow -->

## W14 — Storyboard-first generation

**Goal**: The user has a storyboard (shot list, reference panels, or written beats). Follow it exactly rather than inventing.

**Steps**:

1. **Ask the user**: "Do you have a storyboard or shot list for this?" This should be one of the first questions, before any model selection.
2. If yes: have them provide it (text, images, or Figma/PDF link). Parse each shot panel into:
   - Shot number
   - Visual description
   - Duration (if specified)
   - Camera movement / motion notes
   - Audio or VO cue
3. Repeat the parsed storyboard back to the user and confirm before generating.
4. Generate each shot in storyboard order. Do not add, reorder, or skip shots without asking.
5. If a shot is ambiguous in the storyboard, **stop and ask** — don't fill in from imagination.

**If no storyboard exists**: propose a shot breakdown based on the script / brief and get approval **before** generating. Treat the approved breakdown as the storyboard from that point on.

**Higgsfield Popcorn**: if the user wants to build a storyboard inside Higgsfield, point them at Popcorn (image dropdown → Higgsfield Popcorn) — it's the native storyboard flow. Behavior and cost not yet captured in depth; confirm defaults before committing to it.

## W15 — Stitching final video with ffmpeg (cuts vs. Kling transitions)

**Goal**: Combine N generated clips into one deliverable MP4.

**Two modes — ask first which one the user wants**:

**A) Hard cuts (fast, free, abrupt)**
- Normalize each clip to the same resolution/fps: `scale=1920:1080:force_original_aspect_ratio=decrease,pad=...,setsar=1,fps=24`.
- Concatenate with xfade video + acrossfade audio (0.3–0.4s) for a soft cut that isn't jarring. This is what "cuts with a small fade" looks like.
- Or, concat demuxer for true hard cuts.

**B) Kling 3.0 seamless transitions**
- Generate transition clips between each pair (W11).
- Normalize all clips + transitions to matching specs.
- Concat demuxer only — don't xfade on top of a Kling transition or it will double-blend.
- VO, if present, is overlaid on the full timeline after concat.

**Always ask which mode** before spending credits on transition clips — they add ~8.75 credits each.

<!-- auto-edit:workflow w=W15 section=patterns -->
<!-- /auto-edit:workflow -->

## Gotcha cheat sheet (minimal form)

| If | Then |
|---|---|
| Video URL slug doesn't resolve | Use top-nav Video dropdown instead of hand-constructing URLs |
| Generate shows ✨N despite Unlimited toggle ON | You're at wrong resolution/duration — check the unlimited conditions |
| Your gen isn't in the main video viewer | Navigate to `/asset/video` — main viewer doesn't auto-advance |
| Lexical editor kept old prompt | `selectAll + delete` before paste, OR write `hf:image-form-upd.prompt` directly + reload |
| Minimax output morphed instead of animated | Remove End frame — Minimax Start+End = morph |
| Can't find the remove-X on a frame slot | Real mouse hover required; Playwright `browser_hover`, NOT synthetic JS |
