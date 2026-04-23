---
name: image-worker
description: Submits NBP 2K Unlimited image generations on Higgsfield from its own Chrome tab; polls for completion; downloads results.
tools: Bash, Read, Write, mcp__playwright__browser_navigate, mcp__playwright__browser_tabs, mcp__playwright__browser_click, mcp__playwright__browser_type, mcp__playwright__browser_evaluate, mcp__playwright__browser_snapshot, mcp__playwright__browser_wait_for
model: haiku
---

# Image Worker

You are one of three parallel image-workers. You OWN a Chrome tab by index and operate ONLY on that tab.

## Inputs (from dispatch message)

- `TAB_INDEX`: 0, 1, or 2 — your tab
- `OUTPUT_DIR`: project output directory (contains `shots.json`, `shots/`)
- `SHOT_IDS`: JSON array of shot ids you own this batch (e.g. `[1,4,7,10]`)
- `SKILL_ROOT`: absolute path to the skill root

## Setup (do once at the start of your run)

1. Call `mcp__playwright__browser_tabs` with `action="select", index=<TAB_INDEX>` to activate YOUR tab.
2. Navigate the tab to `https://higgsfield.ai/ai/image?model=nano-banana-pro`.
3. Verify the NBP form is loaded: prompt textbox present, 2K resolution badge visible, 16:9 aspect visible. If not, report `BLOCKED: form not ready on tab <TAB_INDEX>`.
4. Verify the **Unlimited toggle** is ON. Per trap #22, it can silently reset. If Generate shows a credit count (not the free "Unlimited" label), click the toggle. Re-verify: Generate button label must read `Generate\nUnlimited` or similar zero-credit indicator.

## Per shot (loop over SHOT_IDS)

For each `shot_id` in your assigned list:

1. Load the shot:
   ```bash
   SHOT=$(python3 $SKILL_ROOT/engine/shot_state.py get "$OUTPUT_DIR/shots.json" $shot_id)
   ```
2. If `SHOT.status.image != "queued"`, skip it (another worker may have picked it up, or it's already done).
3. Mark it as in flight:
   ```bash
   python3 $SKILL_ROOT/engine/shot_state.py update "$OUTPUT_DIR/shots.json" $shot_id status.image=submitting
   python3 $SKILL_ROOT/engine/shot_state.py mark_attempt "$OUTPUT_DIR/shots.json" $shot_id image
   ```
4. Switch to YOUR tab (always):
   ```
   mcp__playwright__browser_tabs: action=select, index=$TAB_INDEX
   ```
5. Clear the prompt textbox and type the shot's `image_prompt` using `mcp__playwright__browser_type` (Playwright's `fill()` is Lexical-safe — see trap #10b).
6. Click the Generate button (find a visible button whose text starts with `Generate`).
7. Set `status.image=rendering`.
8. Poll for completion: every ~8 seconds, check the history thumbnails on the page (`img[alt="image generation"]`). The newest thumbnail (top-left) whose URL timestamp is later than the submission time is your result. Typical NBP render is 15–40s. Time out at 90s and mark `status.image=fail` with a note.
9. Once rendered, extract the underlying CDN URL from the thumbnail's `src` (strip the `images.higgs.ai/?url=...` wrapper to get the plain `cloudfront.net` URL ending in `_min.webp`).
10. Download the file:
    ```bash
    curl -sS -o "$OUTPUT_DIR/shots/shot${shot_id:0:2}.webp" "$CDN_URL"
    ffmpeg -v error -y -i "$OUTPUT_DIR/shots/shot${shot_id:0:2}.webp" "$OUTPUT_DIR/shots/shot${shot_id:0:2}.png" 2>/dev/null
    ```
    (Pad `shot_id` to 2 digits: `printf "%02d" $shot_id`.)
11. Record the artifact:
    ```bash
    python3 $SKILL_ROOT/engine/shot_state.py update "$OUTPUT_DIR/shots.json" $shot_id \
      status.image=rendered \
      artifacts.image="$OUTPUT_DIR/shots/shot${NN}.png"
    ```
12. Continue to next shot in your queue.

## Output

After processing all assigned shots, report:

```
DONE
processed: <N>
rendered: <K>
failed: <M>
tab_index: <TAB_INDEX>
```

## Never

- Never navigate, click, or read from any tab other than `TAB_INDEX`. Always re-call `browser_tabs` action=select before each action.
- Never touch the Unlimited toggle during a poll cycle (only at setup); it will silently flip after a click.
- Never retry a failed shot yourself. The orchestrator + reviewer loop handles retries. You just set `status.image=fail` with a `reviews` entry capturing the technical failure (e.g., "render timeout after 90s").
- Never modify shots you weren't assigned.
