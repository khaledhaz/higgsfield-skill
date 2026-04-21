# Higgsfield model catalog (Creator plan, captured 2026-04-21)

> **Status flags (check before picking):**
> - **Kling 2.5 Turbo** — DO NOT USE from Claude Code. Generate silently drops. Use Kling 3.0 until the user confirms it's fixed.
> - **Seedance 2.0 / Seedance Pro** — require per-input content-eligibility check. Skill must wait/reload until resolved (see workflows W12).
> - **Default image model**: Nano Banana Pro at 2K.
> - **Default video animation (this session)**: Kling 3.0 at 720p/5s with audio.
> - **Default audio/VO model**: Eleven v3.

## Complete model roster (at a glance)

**Image models (19):** Nano Banana Pro · Nano Banana 2 · Nano Banana (v1) · Higgsfield Soul 2.0 · Higgsfield Soul Cinema · Higgsfield Soul (v1) · Seedream 5.0 Lite · Seedream 4.5 · Seedream 4.0 · GPT Image 1.5 · GPT Image (older) · FLUX.2 Pro · Flux Kontext · Grok Imagine · Reve · Z-Image · Higgsfield Popcorn (storyboard) · Higgsfield Face Swap · Wan 2.2 Image · Kling O1 Image · Topaz (upscaler).

**Video models (15):** Seedance 2.0 · Seedance 1.5 Pro · Kling 3.0 · Kling 3.0 Motion Control · ~~Kling 2.5 Turbo (broken from Claude Code)~~ · Kling O1 Edit · Sora 2 · Google Veo 3.1 · Google Veo 3.1 Lite · Google Veo 3 Fast (via UGC Factory) · Grok Imagine (video) · Wan 2.7 · Wan 2.5 Fast (via Lipsync Studio) · Minimax Hailuo 02 · Higgsfield DoP.

**Audio models (4+):** **Eleven v3 (default for VO)** · MiniMax Speech 2.8 HD · Seed Speech (ByteDance, new) · VibeVoice · plus lipsync-specific: Infiniti Talk, Higgsfield Speak.

**Special surfaces:** Cinema Studio 3.5 · Marketing Studio · UGC Factory · Lipsync Studio · Higgsfield Popcorn (storyboard).

Details, costs, and slugs below.


## Image models — by URL slug

All reached via `/ai/image?model=<slug>`. Shared bar: prompt (Lexical editor), "+" attachment, model selector, aspect ratio (11 options), resolution, batch (1-4), Unlimited toggle, Draw button, Generate.

| Model | Slug | 365 Unlimited? | Default aspect | Default res | Cost at defaults | Bar specials |
|---|---|---|---|---|---|---|
| Nano Banana Pro | `nano-banana-pro` | ✅ 1K/2K; 4K paid | 3:4 | 1K | 2 credits (paid res); **0 at 1K/2K unlimited** | Draw button |
| Nano Banana 2 | `nano-banana-2` | — | — | — | — | (standard) |
| Nano Banana (v1) | `nano_banana` | ✅ | — | — | — | (standard) |
| Higgsfield Soul 2.0 | `soul-v2` | separate **10,000 free-gens pool** | 3:4 | 2k | 0 within pool | Character slot, Color Transfer, Off toggle, "10000 free gens left" label |
| Higgsfield Soul Cinema | `soul-cinematic` | shares Soul 2.0 pool | 16:9 | 2k | 0 within pool | Character slot, Color Transfer, On toggle |
| Higgsfield Soul (v1) | `soul` | ✅ | — | — | — | — |
| Seedream 5.0 lite | `seedream_v5_lite` | ✅ | 3:4 | 2K | ✨1 | (standard) |
| Seedream 4.5 | `seedream` or similar | ✅ | — | — | — | 4K-capable |
| Seedream 4.0 | `seedream` (older) | ✅ | — | — | — | — |
| GPT Image 1.5 | `openai_hazel` | ✅ | 1:1 | Low | ✨2 | "Low/Medium/High" quality labels (not K-suffix) |
| GPT Image (older) | `gpt` | — | — | — | — | — |
| FLUX.2 Pro | `flux_2` | ✅ **but Unlimited toggle defaults OFF** | 3:4 | 1K | ✨1 | **⚠ Check toggle before Generate — surprise-spend risk** |
| Flux Kontext | `kontext` | ✅ | — | — | — | Editing-focused |
| Grok Imagine | `grok_image` | NEW (not 365) | — | — | — | — |
| Reve | `reve` | ✅ | — | — | — | Image editing model |
| Z-Image | `z-image` | ✅ | — | — | — | Instant lifelike portraits |
| Higgsfield Popcorn | (via Image dropdown) | ✅ | — | — | — | Storyboard flow |
| Higgsfield Face Swap | (via /app/face-swap) | ✅ | — | — | — | App-flow, not bar |
| Wan 2.2 Image | `wan2` | — | — | — | — | — |
| Topaz | (via /upscale) | — | — | — | — | Upscaler, own page |
| Kling O1 Image | `?` | ✅ | — | — | — | — |
| Auto | (meta router) | — | — | — | — | Routes to best-of-N |

**Aspect ratio options** (NBP verified; other models may have subsets): Auto, 1:1, 3:4, 4:3, 2:3, 3:2, 9:16, 16:9, 5:4, 4:5, 21:9.

**Soul 2.0 / Soul Cinema pool**: 10,000 free gens/month on Creator. Not credits. Resets — reset cadence unconfirmed.

## Video models — by URL slug

All reached via `/ai/video?model=<slug>`. Shared UI: **left-sidebar composer** (3 sub-modes: Create Video / Edit Video / Motion Control), right history/onboarding area. **NO video model has 365 Unlimited** — every video gen costs credits EXCEPT Kling 2.5 Turbo at 720p×5s with Unlimited mode toggle ON.

### Confirmed working slugs
- `seedance_2_0` — Seedance 2.0 (underscores!)
- `seedance_pro` — Seedance Pro
- `kling-v2-5-turbo` — Kling 2.5 Turbo (hyphens!)
- `kling-v2-1-master` — Kling 2.1 Master
- `veo-3-preview` — Google Veo 3 (older)
- `minimax` — Minimax Hailuo 02

### Non-working / unverified slugs
- ❌ `kling-v3` — falls back to no-model
- ❌ `veo-3-1` — falls back
- ❌ `kling-3` — falls back
- Use the **Video dropdown in top nav** to navigate, not guessed URLs.

| Model | Slug | Default duration | Default res | Cost | Notes |
|---|---|---|---|---|---|
| Seedance 2.0 | `seedance_2_0` | 8s | 1080p | **88** (discounted from 96) | Most expensive premium video; TOP badge |
| Kling 3.0 | (nav only) | — | — | — | Cinematic with audio |
| Kling 3.0 Motion Control | (nav only) | — | — | — | NEW; transfer motion from ref video |
| Kling 2.5 Turbo | `kling-v2-5-turbo` | 5s | 1080p → 720p unlimited | **6** at 1080p / **0** at 720p Unlimited | **ONLY UNLIMITED VIDEO TIER**; 720p×5s only |
| Kling O1 Edit | (nav only) | — | — | — | Video editing |
| Sora 2 | (`/sora2-ai-video` intro) | — | — | — | May be winding down |
| Google Veo 3.1 Lite | (nav only) | — | — | — | NEW; fast |
| Google Veo 3.1 | (nav only) | — | — | — | Advanced; user's top video model (57 gens) |
| Google Veo 3 Fast | (via UGC Factory) | — | — | promo: 3 free-gens | Default UGC Factory model |
| Grok Imagine (video) | (nav only) | — | — | — | — |
| Wan 2.7 | (nav only) | — | — | — | NEW; first+end frame control |
| Wan 2.5 Fast | (via Lipsync Studio) | — | — | **9** | Cheapest video-adjacent gen |
| Minimax Hailuo 02 | `minimax` | 6s | 768p | **6** | 2-frame input = **morph interpolation** (not prompt-driven) |
| Seedance 1.5 Pro | `seedance_pro` | — | — | 28-49 | Older; cheaper than 2.0 |
| Higgsfield DoP | (nav only) | 3.4s (81 frames) | — | — | VFX and camera control |

## 365 Unlimited roster (from /me/settings/subscription, 2026-04-21)

**15 image models always free** via 365-Unlimited auto-renewing:
1. Kling 2.5 Turbo Unlimited (Jan 2026 → Jan 2027, explicit dates)
2. FLUX.2 Pro (auto-renew)
3. Nano Banana Pro Exclusive (auto-renew)
4. Higgsfield Soul (auto-renew)
5. GPT Image (auto-renew)
6. Z Image (auto-renew)
7. Reve (auto-renew)
8. Seedream 4.5 (auto-renew)
9. Kling O1 Image (auto-renew)
10. Flux Kontext (auto-renew)
11. Higgsfield Popcorn (auto-renew)
12. Nano Banana (auto-renew)
13. Seedream 4.0 (auto-renew)
14. Higgsfield Face Swap (auto-renew)
15. Seedream V5 Lite (auto-renew)

## Audio models

**Surface**: `/audio` — NOT `/ai/audio`. (Unlike Image/Video, the audio route drops the `/ai/` prefix.)

Top-nav "Audio" opens a hover menu with two columns: **Features** (Voiceover / Change Voice / Translation) and **Models** (listed below).

- **Eleven v3 — DEFAULT for VO / narration.** Expressive AI voice with emotion control. Use this when the user asks for a voiceover and hasn't specified a model.
- **MiniMax Speech 2.8 HD** — Studio-quality TTS (alternative to Eleven v3 if the user wants a different timbre).
- **Seed Speech** [NEW] — ByteDance multilingual TTS.
- **VibeVoice** — Long-form expressive voice synthesis.
- Also used in Lipsync Studio: **Infiniti Talk**, **Higgsfield Speak** (lipsync-specific models not visible elsewhere).

**VO workflow note**: when the user wants narration, generate the VO *first*, then measure its duration with ffprobe — the VO length is the authoritative total runtime the video must match. See [workflows W13](workflows.md).

## Special surfaces

- **Lipsync Studio** (`/lipsync-studio`) — Wan 2.5 Fast default, 9 credits. Also has "UGC Factory" tab (`?ugc-studio=true`) with Google Veo 3 Fast + 6-step wizard (Template → Image → Action → Audio text → Audio settings → Background).
- **Cinema Studio 3.5** (`/cinema-studio?autoSelectFolder=true`) — project-scoped with UUID in URL. Elements system: Characters + Props + Locations, Project (shared) vs Personal (private) scopes. `@`-mention in prompt to reference Elements. AI Director floating button. 96 credits/gen default.
- **Marketing Studio** (`/marketing-studio`) — ads workspace with PRODUCT + AVATAR slots. Format presets: Hyper Motion, Unboxing, UGC. ~40 credits default (discounted).
- **UGC Factory** — wizard for ad-style talking-head content.

## Concurrency on Creator plan

Base: **8 videos, 8 images, 6 characters**.

Extra Concurrent bundles (purchase add-ons, prices not captured):
- Nano Banana Bundle (covers NBP + Nano Banana 2): +4, +8, +12, +16 concurrent tiers
- Kling Bundle (covers Kling 3.0 + Kling 2.6): +4, +8, +12, +16 tiers

## Sources in findings/ for verification
- `findings/subscription/plan-details.md` — full plan breakdown, unlimited roster table
- `findings/models/image/_shared-image-generation-bar.md` — bar controls, per-model specials
- `findings/models/video/_shared-video-generation-page.md` — sidebar composer, sub-modes, slug gotchas
