#!/usr/bin/env python3
"""shot_state.py — read/write and mutate shots.json atomically.

Subcommands:
  init <path> <shots-json-array>
  update <path> <shot_id> <field=value>...   # supports dot-paths like status.image=pass
  add_review <path> <shot_id> <stage> <verdict> <reason>
  next_queued <path> <stage>                  # prints shot_id or empty
  next_video_ready <path> <worker_tag>        # atomically claims the lowest-id shot whose
                                              #   video.status == "queued" AND all required
                                              #   image roles have status == "pass".
                                              #   Marks video.status = "claimed_<worker_tag>"
                                              #   and prints the shot id. Prints nothing if
                                              #   no shot is ready.
  attempts <path> <shot_id> <stage>           # prints current attempt count
  mark_attempt <path> <shot_id> <stage>       # increments attempts.<stage>
  get <path> <shot_id> [<dot-path>]           # prints field value or whole shot JSON

All file writes are atomic (tempfile + replace).
"""
import json
import sys
import tempfile
from pathlib import Path
from datetime import datetime, timezone


def _load(path: Path) -> list:
    if not path.is_file():
        raise FileNotFoundError(f"shots.json not found: {path}")
    return json.loads(path.read_text())


def _save(path: Path, shots: list) -> None:
    tmp_fd, tmp_path = tempfile.mkstemp(dir=path.parent, prefix=".shot_state_", suffix=".tmp")
    try:
        with open(tmp_fd, "w") as f:
            json.dump(shots, f, indent=2, ensure_ascii=False)
            f.write("\n")
        Path(tmp_path).replace(path)
    except Exception:
        Path(tmp_path).unlink(missing_ok=True)
        raise


def _find(shots: list, shot_id: int) -> dict:
    for s in shots:
        if int(s["id"]) == shot_id:
            return s
    raise KeyError(f"shot id {shot_id} not found")


def _set_dot(obj: dict, dot_path: str, value) -> None:
    keys = dot_path.split(".")
    cur = obj
    for k in keys[:-1]:
        if k not in cur or not isinstance(cur[k], dict):
            cur[k] = {}
        cur = cur[k]
    last = keys[-1]
    if isinstance(cur.get(last), dict) and not isinstance(value, dict):
        raise ValueError(f"refusing to overwrite dict field '{dot_path}' with scalar")
    cur[last] = value


def _get_dot(obj, dot_path: str):
    keys = dot_path.split(".")
    cur = obj
    for k in keys:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            raise KeyError(f"dot-path '{dot_path}' not found")
    return cur


def cmd_init(path: Path, shots_json: str) -> int:
    shots = json.loads(shots_json)
    if not isinstance(shots, list):
        print("Error: shots-json must be a JSON array", file=sys.stderr)
        return 1
    _save(path, shots)
    return 0


def cmd_update(path: Path, shot_id: int, assignments: list) -> int:
    shots = _load(path)
    shot = _find(shots, shot_id)
    for a in assignments:
        if "=" not in a:
            print(f"Error: assignment must be field=value, got '{a}'", file=sys.stderr)
            return 2
        field, raw = a.split("=", 1)
        # Values are stored as strings. Numeric counters are mutated via mark_attempt, not update.
        _set_dot(shot, field, raw)
    _save(path, shots)
    return 0


def cmd_add_review(path: Path, shot_id: int, stage: str, verdict: str, reason: str) -> int:
    if stage not in ("image", "video"):
        print(f"Error: stage must be image or video, got '{stage}'", file=sys.stderr)
        return 2
    if verdict not in ("pass", "fail"):
        print(f"Error: verdict must be pass or fail, got '{verdict}'", file=sys.stderr)
        return 2
    shots = _load(path)
    shot = _find(shots, shot_id)
    reviews = shot.setdefault("reviews", {}).setdefault(stage, [])
    attempt_num = shot.get("attempts", {}).get(stage, 0)
    reviews.append({
        "attempt": attempt_num,
        "verdict": verdict,
        "reason": reason,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    })
    _save(path, shots)
    return 0


def cmd_next_queued(path: Path, stage: str) -> int:
    if stage not in ("image", "video"):
        print(f"Error: stage must be image or video, got '{stage}'", file=sys.stderr)
        return 2
    shots = _load(path)
    for s in sorted(shots, key=lambda x: int(x["id"])):
        status = s.get("status", {}).get(stage, "queued")
        if status == "queued":
            print(s["id"])
            return 0
    # No queued shot; print nothing, exit 0
    return 0


def cmd_next_video_ready(path: Path, worker_tag: str) -> int:
    """Atomically find the lowest-id shot whose video can be submitted NOW.

    A shot is 'video-ready' iff:
      - video.status == "queued"
      - images.start.status == "pass"
      - if technique == "start_end": images.end.status == "pass"

    On match, atomically set video.status = f"claimed_{worker_tag}" and print the shot id.
    On no match, print nothing (exit 0).
    """
    shots = _load(path)
    for s in sorted(shots, key=lambda x: int(x["id"])):
        video_status = s.get("video", {}).get("status", "queued")
        if video_status != "queued":
            continue
        images = s.get("images", {}) or {}
        start_img = images.get("start") or {}
        if start_img.get("status") != "pass":
            continue
        if s.get("technique") == "start_end":
            end_img = images.get("end") or {}
            if end_img.get("status") != "pass":
                continue
        # Claim atomically
        s.setdefault("video", {})["status"] = f"claimed_{worker_tag}"
        _save(path, shots)
        print(s["id"])
        return 0
    # No ready shot; print nothing
    return 0


def cmd_attempts(path: Path, shot_id: int, stage: str) -> int:
    shots = _load(path)
    shot = _find(shots, shot_id)
    print(shot.get("attempts", {}).get(stage, 0))
    return 0


def cmd_mark_attempt(path: Path, shot_id: int, stage: str) -> int:
    shots = _load(path)
    shot = _find(shots, shot_id)
    attempts = shot.setdefault("attempts", {})
    attempts[stage] = attempts.get(stage, 0) + 1
    _save(path, shots)
    return 0


def cmd_get(path: Path, shot_id: int, dot_path) -> int:
    shots = _load(path)
    shot = _find(shots, shot_id)
    if dot_path is None:
        print(json.dumps(shot, ensure_ascii=False))
    else:
        val = _get_dot(shot, dot_path)
        if isinstance(val, (str, int, float, bool)) or val is None:
            print(val)
        else:
            print(json.dumps(val, ensure_ascii=False))
    return 0


def main() -> int:
    argv = sys.argv[1:]
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv[0]
    path = Path(argv[1])
    try:
        if cmd == "init":
            return cmd_init(path, argv[2])
        if cmd == "update":
            return cmd_update(path, int(argv[2]), argv[3:])
        if cmd == "add_review":
            return cmd_add_review(path, int(argv[2]), argv[3], argv[4], argv[5])
        if cmd == "next_queued":
            return cmd_next_queued(path, argv[2])
        if cmd == "next_video_ready":
            return cmd_next_video_ready(path, argv[2])
        if cmd == "attempts":
            return cmd_attempts(path, int(argv[2]), argv[3])
        if cmd == "mark_attempt":
            return cmd_mark_attempt(path, int(argv[2]), argv[3])
        if cmd == "get":
            return cmd_get(path, int(argv[2]), argv[3] if len(argv) > 3 else None)
    except (FileNotFoundError, KeyError, ValueError, IndexError, AttributeError, TypeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    print(f"Error: unknown command '{cmd}'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
