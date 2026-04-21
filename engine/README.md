# Higgsfield engine scripts

Deterministic helpers called by the higgsfield skill during project execution. Each script is invoked by Claude Code from the skill's engine-mode workflow (see `../SKILL.md` "Engine mode" section).

| Script | Purpose | Input | Output |
|---|---|---|---|
| `probe_duration.sh` | ffprobe wrapper returning media duration in seconds | path to audio/video file | seconds on stdout (e.g. `42.34`) |
| `extract_frames.sh` | Extract last frame of clip A + first frame of clip B for transitions | `<clipA> <clipB> <out-dir>` | writes `<out-dir>/clipA-last.png` and `<out-dir>/clipB-first.png` |
| `stitch.sh` | Normalize + concatenate clips into a final MP4 per JSON manifest | path to manifest JSON | writes output MP4 at `manifest.output`, prints its duration to stdout |
| `init_vault.sh` | Idempotent bootstrap of `~/Obsidian/Higgsfield/` vault | none | creates vault structure + template; exits 0 |

## Testing

Each script has a sibling test under `tests/test_<name>.sh`. Run all: `bash tests/run_all.sh`

## Dependencies

- `ffmpeg` + `ffprobe` (brew install ffmpeg)
- Bash 4+ (macOS default `/bin/bash` 3.2 is fine; all scripts use POSIX-compatible features)
- `jq` for JSON manifest parsing in `stitch.sh` (brew install jq)
- `python3` with `yaml` (for frontmatter parsing in SKILL.md workflows, not in engine/ scripts)
