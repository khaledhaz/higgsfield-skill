# higgsfield-skill

A Claude Code skill for agentic video/image generation on [higgsfield.ai](https://higgsfield.ai), orchestrated through Obsidian project notes.

## What it does

Write a project spec as an Obsidian note (script, style, voice, aspect). Say "run `<slug>`". The skill:

1. Generates the voiceover on Eleven v3 (if specified).
2. Plans shots to fit the VO's measured duration.
3. Generates hero images (Nano Banana Pro), animates them (Kling 3.0), builds seamless Hollywood-style transitions where requested.
4. Stitches the final MP4 with ffmpeg.
5. Writes every step back into the same Obsidian note as a live log.

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
# creates ~/Obsidian/Higgsfield/{Projects,_templates,_runs}
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
