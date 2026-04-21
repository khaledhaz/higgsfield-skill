# Higgsfield speed shortcuts — from 3-5min click-setup to ~15s automated

## The three plays ranked

| # | Play | Use when | Time |
|---|---|---|---|
| 1 | **Recreate button** | Repeating a past gen, tweaking one thing | ~10s |
| 2 | **localStorage priming + reload** | Fresh run with a specific plan (aspect, model, prompt) | ~15s |
| 3 | **Drag-drop from URL** | Uploading image without local file / picker | ~3s |

## Play 1 — Recreate (fastest)

Navigate to any past asset detail:
- Video: `/asset/video/<uuid>`
- Image: `/asset/image/<uuid>`

Click the big yellow button:
- **Recreate** (on video detail) → model + enhanced prompt + Start frame + end frame + duration + resolution auto-set
- **Animate** (on image detail) → jumps to video page with that image as Start frame
- **Reference** (on image detail) → loads image into reference slot on image page

Asset UUIDs come from `<figure data-asset-id="<uuid>">` in Assets grid, OR from the filename pattern `hf_<timestamp>_<uuid>.png|mp4`.

**Recreate preserves the ENHANCED prompt** (not your shorthand). If you want to iterate on cinematography language, Recreate is the best starting point.

## Play 2 — localStorage priming

All form state lives in `localStorage` under known keys. Write JSON, reload, everything is set.

### Image page master pattern

```js
// Prompt + global image settings (shared across image models)
localStorage.setItem('hf:image-form-upd', JSON.stringify({
  prompt: '<YOUR PROMPT>',
  enhance: true,
  withPrompt: true,
  seed: 42  // or null for random
}));

// Model-specific settings (example: Nano Banana Pro / Nano Banana 2)
localStorage.setItem('hf:nano-banana-2-image-form-3', JSON.stringify({
  batch_size: 1,          // 1-4
  aspect_ratio: '16:9',   // Auto | 1:1 | 3:4 | 4:3 | 2:3 | 3:2 | 9:16 | 16:9 | 5:4 | 4:5 | 21:9
  quality: '1k',          // '1k' | '2k' | '4k' (4k costs credits even on 365 Unlimited)
  use_unlimited: true,    // false = spend credits even if available
  use_seedream_bonus: false
}));

location.reload();
```

### Video page master pattern

The master key is **`flow-create-video-<date-suffix>`** (currently `flow-create-video-2025-10-04T17` but date rotates). Check the current key with:
```js
Object.keys(localStorage).find(k => k.startsWith('flow-create-video-'));
```

Schema:
```js
localStorage.setItem('flow-create-video-2025-10-04T17', JSON.stringify({
  type: 'video',
  seedAuto: true,
  enhance: true,
  prompt: '<YOUR MOTION PROMPT>',
  motionIds: [],       // preset UUIDs — empty for GENERAL
  motionStrengths: [],
  inputImage: null,    // asset UUID or null to clear Start frame
  endImage: null,      // asset UUID or null to clear End frame
  frames: 81,          // ~3.4s at 24fps; 120 ≈ 5s
  seed: null,
  steps: 30,
  modelVersion: 'kling-v2-5-turbo',
  guideScale: null, guideScale2: null, guideEnd: null, sampleShift: null, strength: null,
  minimaxQuality: null,
  isDraw: false, drawImage: null, negativePrompt: null, use_lightx: null, boundary: null
}));

// Per-model keys control resolution/duration/unlimited, but are RESET on mount
// (write them if you want, but they may not stick — prefer UI clicks for these 3)
localStorage.setItem('hf:create:video:kling-v2', JSON.stringify({
  preset_id: '',
  negative_prompt: '',
  cfg_scale: 0.5,
  camera_control: null,
  duration: 5,
  is_camera_control_enabled: false,
  resolution: '720p',    // may revert to '1080p' on mount
  use_unlim: true,        // may revert to false on mount
  isPresetFlf: false
}));

location.reload();
```

**What flow-create-video actually persists across reload**:
- ✅ prompt, inputImage, endImage, modelVersion, motionIds, seed

**What gets reset**:
- ❌ resolution, use_unlim (per-model; need UI click after reload)

### Per-model localStorage keys

| Model / surface | localStorage key | Key fields |
|---|---|---|
| Kling 2.5 Turbo | `hf:create:video:kling-v2` | preset_id, duration, resolution, use_unlim, is_camera_control_enabled |
| Minimax Hailuo 02 | `hf:create:video:minimax` | presetId, quality ('512'/'768'), duration |
| Seedance 2.0 | `hf:video-seedance-2-0-store:v1` | presetId, duration, batchSize, aspectRatio, resolution, generateAudio, enhancePrompt |
| Higgsfield DoP | `hf:create:video:hf` | frames, steps, seed, motionIds, strength |
| Cinema Studio 3.5 video | `hf:video-cinematic-studio-3-5-store:v1` | duration, aspectRatio, resolution, genre, speedramp, cameraModelV35, cameraLensV..., promptVideoV35, promptItemsV35, colorGrading, stylePrompt |
| Kling Omni (shared prompt) | `hf:video-kling-omni-store` | prompt, imageFirstFrameId, imageLastFrameId, use_unlimited, resolution |
| NBP / NB 2 | `hf:nano-banana-2-image-form-3` | batch_size, aspect_ratio, quality, use_unlimited |
| Soul 2.0 | `hf:soul-v2-form-01-dev-upd` | (large) |
| Soul 1.0 | `hf:soul-form-09-13` | styleId, styleStrength, styleMode, characterStyleId, seed, seedConfig, ... |
| Cinema Studio image | `hf:cinematic-studio-image-v3.53` | (3316 bytes, rich) |
| Photodump | `hf:photodump-v2` | — |
| Image master | `hf:image-form-upd` | prompt, enhance, withPrompt, seed |

## Play 3 — drag-drop from URL (no file picker)

```js
async function dropImage(url) {
  const resp = await fetch(url);
  const blob = await resp.blob();
  const file = new File([blob], 'x.png', { type: 'image/png' });

  const dt = new DataTransfer();
  dt.items.add(file);

  // Find the file input, walk up to the drop zone
  const input = document.querySelector('input[type="file"][accept*="png"]');
  const slot = input.closest('div[class*="cursor"]') || input.parentElement;

  ['dragenter', 'dragover', 'drop'].forEach(t => 
    slot.dispatchEvent(new DragEvent(t, {
      bubbles: true, cancelable: true, dataTransfer: dt
    }))
  );
}
```

**Behavior**: lands in first empty slot (Start first, then End). If Start is full, drop goes to End — intended for morph-target workflows.

**Drawbacks vs Recreate**: no prompt / settings forwarding, just the image.

## URL shortcuts that work

### Image page
- `?model=<slug>` — switch model
- `?aspect=16:9` — set aspect ratio (verified)
- Modal flags: `?modal-photo-dump=true`, `?modal-fashion-factory=true`, `?skip-preview=true`

### Video page
- `?model=<slug>` — works for confirmed slugs only
- Modal flags: `?image-inpaint=true`, `?video-inpaint=true&generationType=video`

### Cinema Studio
- `?autoSelectFolder=true` — auto-pick latest project
- `?mode=image|video|audio` — pre-select mode tab
- `?cinematic-project-id=<uuid>&workflow-project-id=<uuid>` — load specific project

### Lipsync / UGC
- `/lipsync-studio` — Lipsync Studio
- `/lipsync-studio?ugc-studio=true` — UGC Factory tab

## URL shortcuts that DO NOT work

- `?prompt=<text>` — ignored (Lexical loads from localStorage)
- `?resolution=<value>` — ignored
- `?batch=<N>` — ignored
- `?unlimited=true` — ignored
- `?duration=<s>` — ignored

## Keyboard shortcuts

**None tested positive.** Higgsfield has basically no global keyboard shortcuts:
- ❌ Cmd+K / Ctrl+K — no command palette
- ❌ `/` — no search shortcut
- ❌ `?` — no help overlay
- ❌ Cmd+Enter — doesn't submit prompt

## The remove-X on filled slots

Frame slots (Start, End) have a 24×24 X button at top-right, shown only on **real browser hover** (CSS `:hover`). In browser automation:
- ✅ Playwright's `browser_hover` (CDP real mouse) works
- ❌ Synthetic `PointerEvent` dispatch does NOT trigger :hover
- **Alternative**: the button is in the DOM even when CSS-hidden. Filter `document.querySelectorAll('button')` by bounding rect matching "top-right corner of slot" and click it directly.

## Composable templates

### Template A — fresh image, zero-click setup

```js
localStorage.setItem('hf:image-form-upd', JSON.stringify({
  prompt: '<PROMPT>', enhance: true, withPrompt: true, seed: null
}));
localStorage.setItem('hf:nano-banana-2-image-form-3', JSON.stringify({
  batch_size: 1, aspect_ratio: '16:9', quality: '2k', use_unlimited: true, use_seedream_bonus: false
}));
location.reload();
// Human click: just "Generate". 5 seconds.
```

### Template B — animate a URL image with Kling 2.5 Turbo

```js
// 1. Prime the flow
localStorage.setItem('flow-create-video-2025-10-04T17', JSON.stringify({
  type: 'video', seedAuto: true, enhance: true,
  prompt: '<MOTION PROMPT>',
  motionIds: [], motionStrengths: [],
  inputImage: null, endImage: null,
  frames: 120, seed: null, steps: 30,
  modelVersion: 'kling-v2-5-turbo',
  guideScale: null, guideScale2: null, guideEnd: null, sampleShift: null, strength: null,
  minimaxQuality: null, isDraw: false, drawImage: null, negativePrompt: null, use_lightx: null, boundary: null
}));
location.reload();

// 2. Drop image into Start frame (after reload)
const resp = await fetch('<IMAGE-URL>');
const file = new File([await resp.blob()], 'x.png', {type:'image/png'});
const dt = new DataTransfer(); dt.items.add(file);
const slot = document.querySelector('input[type="file"][accept*="png"]').closest('div[class*="cursor"]');
['dragenter','dragover','drop'].forEach(t => slot.dispatchEvent(new DragEvent(t, {bubbles:true, cancelable:true, dataTransfer:dt})));

// 3. Human clicks: resolution → 720p, then Unlimited toggle ON (per-model keys reset on mount)
// 4. Click Generate. Total: ~15s.
```

### Template C — Recreate a past gen

1. `/asset/video/<uuid>` → click **Recreate**
2. (Optional) edit prompt textarea, swap Start frame via hover-remove + drag-drop
3. Click Generate

Total: ~10s.

## Verifying what persists

If a localStorage write didn't take effect, check:
1. Did the page reload fully? (`location.reload()` is sync-triggering async React remount)
2. Is the key exactly right? (case-sensitive, date-suffix rotates)
3. Is it a per-model key that gets reset on mount? (prompt and inputImage in `flow-create-video-*` persist; resolution in `hf:create:video:kling-v2` often doesn't)
4. Clear `localStorage` completely and re-prime — some stale state can leak across writes
