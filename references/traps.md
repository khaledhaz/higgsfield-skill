# Higgsfield traps — 17 pitfalls that cost real credits/time

All traps observed first-hand in two end-to-end experiments (Apr 2026). When unsure, trust the `Generate` button label over any toggle or badge.

## Cost traps (these spend credits you didn't plan to)

### 1. `Generate ✨ N` means you WILL spend N credits
The "Unlimited" toggle being ON doesn't override the label. If you see a sparkle + number on Generate, credits get charged. Only `Generate [Unlimited]` (black badge, no sparkle number) is free.

### 2. FLUX.2 Pro's in-bar Unlimited toggle defaults OFF
Despite FLUX.2 Pro being in the 365 Unlimited roster, navigating to its page shows Unlimited toggle = OFF. Users who don't check before hitting Generate will spend credits on a model they thought was free. **Always verify the toggle state on FLUX.2 Pro before generating.**

### 3. Nano Banana Pro 4K always costs credits
Even with 365 Unlimited active, the 4K tier is paid. 1K and 2K are free. The Unlimited toggle doesn't cover 4K.

### 4. Cinema Studio 3.5 prompt costs 96 credits vs `/ai/video?model=seedance_2_0` costs 88
Same Seedance model, different UI, different cost. Use the direct `/ai/video` surface for plain Seedance video to save 8 credits/gen.

### 5. Top-up credits expire in 90 days
Credits you BUY (not plan-included monthly credits) die after 90 days per the Buy Credits modal footer. Plan credits roll forever. Don't stockpile purchased credits.

### 6. Minimax End Frame forces 768p+ resolution
A tooltip says "Minimax Start & End Frame is available only when using 768p-1080p quality." So adding an End frame bumps you off any lower (cheaper) tier.

<!-- auto-edit:traps category=cost -->

### 22. Nano Banana Pro Unlimited toggle is sticky across resolution changes
Switching NBP resolution (e.g., 4K → 2K via the resolution picker) does NOT auto-flip the Unlimited toggle. If the previous session had Unlimited=OFF (because you were at 4K), dropping to 2K leaves the toggle OFF and the button shows `Generate ✨ 2` instead of `Unlimited ✨`. Silent 2-credit surprise per gen.

**Workaround**: after any resolution change on NBP, explicitly check the Unlimited switch and flip it ON if it isn't already. Or verify the Generate button label shows `Unlimited ✨` (not `Generate ✨ N`) before clicking.

**Observed**: 2026-04-22 in the smoke-test Mode A run — first submit attempt was `Generate ✨ 2` at 2K, caught by the button-label rule, toggle flipped, re-submit was free.
<!-- /auto-edit:traps -->

## Session-state traps (these waste gens on wrong inputs)

### 7. Session state persists across video-model navigations
Navigating from Kling to Minimax preserves Start frame, prompt, duration. Upload a new file → lands in End slot because Start is still full. Result: a morph video you didn't ask for. **Clear Start frame explicitly before uploading.**

### 8. Minimax with two frames = morph interpolation, not prompt-driven
Kling's End frame is optional; leaving it empty = prompt animates Start frame. Minimax Hailuo 02 treats Start+End as interpolation targets — prompt becomes secondary. **For prompt-driven Minimax animation, leave End frame empty.**

### 9. Prompt textbox persists across sessions via localStorage
The image page's Lexical editor reads from `hf:image-form-upd.prompt` on mount. The `?prompt=` URL param is ignored. To pre-fill a prompt, either write the localStorage key directly or clear + paste in the editor.

### 10. Paste events in Lexical editors APPEND, don't replace
`dispatchEvent(new ClipboardEvent('paste'))` inserts at cursor position. If the textbox has old content, you'll get concatenation. **Clear first**: `document.execCommand('selectAll'); document.execCommand('delete');` then paste.

<!-- auto-edit:traps category=session-state -->
<!-- /auto-edit:traps -->

## UI discovery traps (these waste time hunting)

### 11. `document.querySelector('video')` returns the sidebar preset preview, not your generated video
Every video-model page has a left-sidebar preset card (GENERAL / <model>) that auto-plays a demo. That demo has a CDN URL matching the pattern of user gens. Filtering by `width > 200` isn't enough. **Get the canonical URL via `/asset/video/<asset-uuid>`** where the UUID comes from `<figure data-asset-id>` in the Assets grid.

### 12. Main video area doesn't auto-advance to new gens
A just-completed gen stays in the Assets library, but the main video page viewer keeps showing whatever was last played. Don't wait there — navigate to `/asset/video` or `/asset/all`.

### 13. Synthetic `PointerEvent` hover doesn't trigger CSS `:hover`
Dispatching `new PointerEvent('pointerenter')` does NOT reveal the 24×24 remove-X button on frame slots. Only Playwright's native `browser_hover` (real CDP mouse input) triggers the CSS `:hover` state. In browser automation, use native hover. In JS alone, the X button is still in the DOM but may need filtering by `getBoundingClientRect()`.

### 14. Clicking image thumbnails in Assets vs video thumbnails behave differently
Image thumbnails open a detail overlay on click. Video thumbnails often require a nested `<button>` click. For programmatic access: navigate directly to `/asset/video/<uuid>` or `/asset/image/<uuid>`.

### 15. `Animate` button on image detail often closes the panel instead of forwarding
Reported behavior inconsistent. If Animate doesn't pre-load the image on the video page, do it manually: drag-drop the image URL or write `flow-create-video-*.inputImage` with the asset UUID.

<!-- auto-edit:traps category=ui-discovery -->
<!-- /auto-edit:traps -->

## Submission traps (these silently drop your work)

### 18. Kling 2.5 Turbo Generate clicks silently drop from Claude Code (as of 2026-04-21)
When Kling 2.5 Turbo is driven through Claude Code (Playwright / JS click), the Generate button fires visually but no job is queued: no "Generating" indicator, no history entry, no error toast, no credit spend. Retries don't help. Observed on both `kling-v2-5-turbo` direct URL and via the Video nav.

**Workaround**: use **Kling 3.0** instead (720p/5s, ~8.75 credits with audio). The user will explicitly re-enable Kling 2.5 Turbo when the issue is fixed. Do not attempt Kling 2.5 Turbo from Claude Code until then.

**If the user asks for Kling 2.5 Turbo anyway**: tell them about this issue and confirm they want to try — don't silently substitute.

<!-- auto-edit:traps category=submission -->
<!-- /auto-edit:traps -->

## Eligibility & moderation traps (these stall indefinitely)

### 19. Seedance 2.0 content-eligibility check can stall on sensitive imagery
The "Checking content…" state on input images for Seedance 2.0 / Seedance Pro can hang indefinitely (observed on military/warship frames, >90s, never resolved). Not an error — just a silent deadlock.

**Workaround**: wait 90 seconds. If still checking, **reload the full page**, re-open the picker, re-select the image. Loop up to ~5 cycles. If still unresolved, stop and ask the user — do not swap models silently, and do not skip the check.

**Never bypass**: eligibility is a moderation rail. If an image comes back "Not eligible", stop and surface it to the user with the specific image that failed.

<!-- auto-edit:traps category=eligibility -->
<!-- /auto-edit:traps -->

## UI-commit traps (values appear set but don't stick)

### 21. Kling 3.0 duration slider — use the hidden `<input type=range>`, not role="slider"

**Major trap.** The "Choose duration" popup contains an outer element with `role="slider"` that looks like the control — **it is not**. That element is a React-aria group wrapper. The real control is a hidden `<input type="range" min="3" max="15" step="1">` inside the popup.

**What actually works** (React-compatible):
```js
const input = document.querySelector('input[type="range"][min="3"]');
const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
setter.call(input, '3');
input.dispatchEvent(new Event('input', { bubbles: true }));
input.dispatchEvent(new Event('change', { bubbles: true }));
```
After that, close the popup (click the Duration pill again or click the prompt textbox). Verify the pill on the bar now reads `3s`.

**What does NOT work reliably:**
- `[role="slider"]`-focused ArrowLeft/ArrowRight: updates `aria-valuenow` visually but doesn't propagate to React form state. The Duration pill on the bar stays at the old value, and the gen runs at the OLD duration.
- Pressing `Escape` to close: reverts the visible slider.
- Click-outside via a synthetic click on the prompt textbox alone: sometimes commits, often doesn't — unreliable.

**Range fact**: Kling 3.0 duration is **3s minimum to 15s maximum**, in 1s steps — 5s is just the default, not the minimum. (The outer red-herring slider reports max=5 because it's actually the Assets-panel gallery zoom slider.)

**Pricing**: ~1.75 credits per second of Kling 3.0 output. 3s = ✨5.25 credits, 5s = ✨8.75, 10s = ✨17.5. Check the Generate button label to confirm the new duration committed (if it dropped from 8.75 to 5.25, you're at 3s).

<!-- auto-edit:traps category=ui-commit -->
<!-- /auto-edit:traps -->

## Browser-automation traps (Claude Code / Playwright-specific)

### 20. Playwright MCP browser can deadlock on SingletonLock after long sessions
After extended Higgsfield sessions (>45 min of UI driving), the Playwright browser can become unreachable: `browser_navigate` returns `Target page, context or browser has been closed`, and subsequent calls return `Browser is already in use … use --isolated`. The Chrome process is still alive (its `SingletonLock` is held) but Playwright's page handle is gone.

**Recovery**:
```bash
pkill -f "mcp-chrome-<id>"        # id lives in the lock path
sleep 2
rm -f <user-data-dir>/SingletonLock <user-data-dir>/SingletonCookie
```
Then call `browser_navigate` again — it'll spawn fresh. Higgsfield cookies persist in the user-data-dir, so you stay logged in.

**When to pre-empt**: if you're about to drive multiple generations in a row (>6), consider a proactive restart between phases — cheaper than recovering mid-task.

<!-- auto-edit:traps category=browser-automation -->
<!-- /auto-edit:traps -->

## Label/naming traps (these confuse reproducibility)

### 16. Model names are inconsistent across surfaces
Same model, three labels: page header = "Minimax Hailuo 02", detail panel = "Minimax 2.0", PRE-RESEARCH = "Minimax Hailuo 2.3". All the same model. When citing a model in the skill, prefer the page header label.

### 17. "Enhance on" rewrites your prompt
Most video models default Enhance=ON. Your typed prompt is server-side expanded into a full cinematic brief. The Generate call uses the ENHANCED text; the detail view's PROMPT field shows the ENHANCED version. Your typed shorthand is not what got rendered.

**Implications:**
- For reproducibility: turn Enhance OFF or note the enhanced text from detail view.
- For quality: leave it ON — the enhancer is genuinely good.
- `Recreate` preserves the ENHANCED text, which is useful context.

<!-- auto-edit:traps category=label-naming -->
<!-- /auto-edit:traps -->

## Red flags that mean "stop and check"

- You're about to click Generate on FLUX.2 Pro — **confirm Unlimited toggle ON**
- Credit balance changed unexpectedly after a gen — **check if you hit 4K or a non-unlimited model**
- Your video came out as a morph between two scenes — **you had both Start and End frames; clear End for prompt-driven animation on Minimax**
- Your prompt got concatenated with old text — **you used paste without selectAll+delete first on Lexical**
- You can't find your just-generated video — **check `/asset/video`, not the /ai/video page's main area**

## Quick self-check before any generation

1. **Did I ask the user about style, aspect, duration, storyboard, transitions, and VO before starting?** If any is still ambiguous, stop and ask.
2. Is the model I picked on the 365 Unlimited roster? (If not, confirm the credit cost on the Generate button matches what I'm willing to spend.)
3. **Am I about to use Kling 2.5 Turbo from Claude Code?** If yes — STOP. It's silently broken. Use Kling 3.0 instead until user re-enables Kling 2.5 Turbo.
4. If on Kling 2.5 Turbo (only after user re-enables): resolution at 720p AND duration at 5s AND Unlimited toggle ON? (Else it costs credits.)
5. If on FLUX.2 Pro: Unlimited toggle explicitly ON? (Defaults OFF.)
6. If on Minimax with a single-subject prompt: End frame EMPTY? (Else it morphs.)
7. If on Seedance: has the input image's eligibility check resolved (Eligible or Not Eligible)? If still "Checking content…" past 90s, **reload the page** and wait another cycle.
8. If my prompt got concatenated: did I clear the Lexical editor before pasting?
