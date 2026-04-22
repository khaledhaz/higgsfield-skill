#!/usr/bin/env python3
"""update_status.py — atomically rewrite the `status:` frontmatter field of a note.

Usage: update_status.py <note-path> <new-status>

Preserves everything else in the note verbatim (body, other frontmatter fields,
indentation, blank lines). Uses a line-by-line regex rather than YAML round-trip
because YAML round-trip would reformat the rest of the frontmatter.

Exits non-zero if:
- file missing
- no `status:` field in frontmatter
"""
import re
import sys
import tempfile
from pathlib import Path


STATUS_RE = re.compile(r"^(status\s*:\s*)(\S+.*)$")


def update(path: Path, new_status: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"note not found: {path}")

    text = path.read_text()
    lines = text.splitlines(keepends=True)

    in_frontmatter = False
    changed = False
    for i, line in enumerate(lines):
        stripped = line.rstrip("\n")
        if stripped == "---":
            if not in_frontmatter:
                in_frontmatter = True
                continue
            else:
                break
        if in_frontmatter:
            m = STATUS_RE.match(stripped)
            if m:
                lines[i] = f"{m.group(1)}{new_status}\n"
                changed = True
                break

    if not changed:
        raise ValueError(f"no status: field in frontmatter of {path}")

    tmp_fd, tmp_path = tempfile.mkstemp(dir=path.parent, prefix=".update_status_", suffix=".tmp")
    try:
        with open(tmp_fd, "w") as f:
            f.writelines(lines)
        Path(tmp_path).replace(path)
    except Exception:
        Path(tmp_path).unlink(missing_ok=True)
        raise


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: update_status.py <note-path> <new-status>", file=sys.stderr)
        return 2
    try:
        update(Path(sys.argv[1]), sys.argv[2])
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
