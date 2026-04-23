# higgsfield-skill

A Claude Code skill for agentic video/image generation on [higgsfield.ai](https://higgsfield.ai), orchestrated through Obsidian project notes.

## What it does

Write a project spec as an Obsidian note (script, style, voice, aspect). Say "run `<slug>`". The skill:

1. Generates the voiceover on Eleven v3 (if specified).
2. **Runs Whisper word-level transcription** on the VO and aligns it to the script to produce per-claim timestamps (`beats.json`).
3. **Dispatches a prompt-writer subagent** to produce image+video prompts per beat with strict visual-journalism rules.
4. **Dispatches 3 parallel image-worker subagents** (each owns a Chrome tab) to generate hero images on Nano Banana Pro 2K Unlimited.
5. **Dispatches a vision-enabled image-reviewer subagent** per shot. Failures feed back into prompt-writer for up to 5 retries, then escalate to the user.
6. **Dispatches 3 parallel video-worker subagents** to animate approved images on Kling 3.0 (720p, 6s).
7. **Dispatches a video-reviewer subagent** to check motion + continuity per clip; same 5-retry loop.
8. Stitches the final MP4 with ffmpeg.
9. Writes every step back into the same Obsidian note as a live log.

Four invocation modes:

- **A** — `run <slug>` (single project)
- **B** — `run the inbox` (queue processing)
- **C** — `run X, Y, Z in parallel` (up to 3 concurrent projects, shared worker pool)
- **D** — `status: scheduled` + cron fires every 15 min (unattended batch)

## Install

Drop this directory into `~/.claude/skills/higgsfield/`. Claude Code picks up skills from that path automatically.

Bootstrap the Obsidian vault:
```bash
bash engine/init_vault.sh
# creates $PWD/hf-projects/{Projects,_templates,_runs}
```

## Requirements

- macOS or Linux with `/bin/bash`
- Python 3 + `pip install -r requirements.txt`
- `ffmpeg` + `ffprobe` (`brew install ffmpeg`)
- `jq` (`brew install jq`)
- Claude Code with Playwright MCP + the `higgsfield.ai` Creator plan account logged in

## Architecture

- **`SKILL.md`** — main skill instructions + Engine mode playbook + Self-learning rules
- **`references/`** — model catalog, 22 documented traps, workflow templates
- **`engine/`** — 8 deterministic shell/python helpers (frame extraction, ffmpeg stitching, YAML parsing, status updates, scheduler sweep, preflight)
- **`docs/`** — design specs and implementation plans

## Testing

```bash
bash engine/tests/run_all.sh
```

Runs all 8 engine test suites.

## License

Personal tooling. No license — ask before reusing.
