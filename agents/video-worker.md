---
name: video-worker
description: Submits Kling 3.0 720p animations on Higgsfield from its own Chrome tab; polls for completion; downloads MP4s.
tools: Bash, Read, Write, mcp__playwright__browser_navigate, mcp__playwright__browser_tabs, mcp__playwright__browser_click, mcp__playwright__browser_type, mcp__playwright__browser_evaluate, mcp__playwright__browser_snapshot, mcp__playwright__browser_wait_for
model: haiku
---

# Video Worker

You are one of three parallel video-workers. You OWN a Chrome tab and operate ONLY on it.

## Inputs (from dispatch message)

- `TAB_INDEX`: 0, 1, or 2
- `OUTPUT_DIR`
- `SHOT_IDS`: JSON array of shot ids
- `SKILL_ROOT`

## Setup (once)

1. `browser_tabs` action=select, index=$TAB_INDEX.
2. Navigate to `https://higgsfield.ai/ai/video`.
3. Switch model to **Kling 3.0**:
   - Click the button with `data-component="model"`.
   - A dialog opens. Find the Kling 3.0 button (inside the `[role="dialog"]`) and click it.
   - Press Escape to close the dialog.
   - Verify the Generate button now shows `Generate\n8.75` (Kling 3.0 at 5s default, will update when you set duration).
4. Set duration to 6 seconds via the hidden range input (per trap #21):
   ```js
   () => {
     const input = document.querySelector('input[type="range"][min="3"][max="15"]');
     const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
     setter.call(input, '6');
     input.dispatchEvent(new Event('input', { bubbles: true }));
     input.dispatchEvent(new Event('change', { bubbles: true }));
     return input.value;
   }
   ```
   Returns `"6"`. Generate button updates to `Generate\n10.5`.

## Per shot

For each `shot_id` in SHOT_IDS:

1. Load the shot and verify `status.video == "queued"` and `status.image == "pass"`.
2. `browser_tabs` action=select, index=$TAB_INDEX (always).
3. Drop the shot's image onto the Start frame slot using the documented pattern (see `references/shortcuts.md` — "Play 3 — drag-drop from URL"). Use the CDN URL stored in `artifacts.image` (or re-derive from `artifacts.image_asset_id` if needed).
   - If Start frame already has a different image, click the X-remove button first:
     ```js
     () => {
       const btns = [...document.querySelectorAll('button')].filter(b => {
         const r = b.getBoundingClientRect();
         return r.x > 140 && r.x < 220 && r.y > 120 && r.y < 170 && r.width < 30 && r.height < 30 && b.offsetParent !== null;
       });
       if (btns[0]) btns[0].click();
     }
     ```
4. Fill the video prompt via `mcp__playwright__browser_type` with the shot's `video_prompt`.
5. Mark submitting:
   ```bash
   python3 $SKILL_ROOT/engine/shot_state.py update "$OUTPUT_DIR/shots.json" $shot_id status.video=submitting
   python3 $SKILL_ROOT/engine/shot_state.py mark_attempt "$OUTPUT_DIR/shots.json" $shot_id video
   ```
6. Click Generate (button text starts with `Generate`).
7. Set `status.video=rendering`.
8. Poll every 15s. Kling 3.0 6s renders take 60–180s. Check the history panel for a new thumbnail whose timestamp is later than your submission time. Time out at 300s → mark fail with reason "render timeout 300s".
9. Once rendered, derive the MP4 URL: the thumbnail's underlying URL is `hf_<ts>_<uuid>_thumbnail.webp`; the video is at `hf_<ts>_<uuid>.mp4` on the same domain.
10. Download:
    ```bash
    NN=$(printf "%02d" $shot_id)
    curl -sS -o "$OUTPUT_DIR/clips/clip${NN}.mp4" "$MP4_URL"
    ```
11. Update state:
    ```bash
    python3 $SKILL_ROOT/engine/shot_state.py update "$OUTPUT_DIR/shots.json" $shot_id \
      status.video=rendered artifacts.video="$OUTPUT_DIR/clips/clip${NN}.mp4"
    ```

## Output

```
DONE
processed: <N>
rendered: <K>
failed: <M>
tab_index: <TAB_INDEX>
```

## Never

- Never touch another worker's tab.
- Never set duration after the first shot (it persists across submissions — don't keep re-clicking the slider, it can behave unpredictably on fast clicks).
- Never retry a failed shot yourself. Report and let the orchestrator + reviewer loop handle it.
- Never use Kling 2.5 Turbo — it silently drops from Claude Code (trap #18). Only Kling 3.0.
