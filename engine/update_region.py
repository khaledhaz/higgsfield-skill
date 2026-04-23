#!/usr/bin/env python3
"""update_region.py — rewrite content between <!-- engine:X --> markers in a markdown note.

Usage: update_region.py <note-path> <region-name> <content-source>

<content-source> may be a path to a file, or "-" to read from stdin.

If the opening and closing markers are both present, replaces content between them.
If both markers are absent, appends them (with the new content) to the end of the file.
If only one marker is present (malformed), exits non-zero.

Exits non-zero if:
- note file missing
- content-source is a path that doesn't exist
- region markers are malformed (only one present)
"""
import re
import sys
import tempfile
from pathlib import Path


def _markers(region: str) -> tuple[str, str]:
    return f"<!-- engine:{region} -->", f"<!-- /engine:{region} -->"


def update(note_path: Path, region: str, content: str) -> None:
    if not note_path.is_file():
        raise FileNotFoundError(f"note not found: {note_path}")

    text = note_path.read_text()
    open_marker, close_marker = _markers(region)

    has_open = open_marker in text
    has_close = close_marker in text

    if has_open != has_close:
        raise ValueError(f"malformed region '{region}' in {note_path}: only one marker found")

    content_rstripped = content.rstrip("\n")

    if open_marker in content_rstripped or close_marker in content_rstripped:
        raise ValueError(
            f"content contains region markers for '{region}'; refusing to write"
        )

    if has_open:
        # Replace content between the two markers (first occurrence only)
        pattern = re.compile(
            re.escape(open_marker) + r".*?" + re.escape(close_marker),
            flags=re.DOTALL,
        )
        replacement = f"{open_marker}\n{content_rstripped}\n{close_marker}"
        new_text = pattern.sub(replacement, text, count=1)
    else:
        # Append a new region block at end of file
        suffix = "" if text.endswith("\n") else "\n"
        new_text = f"{text}{suffix}\n{open_marker}\n{content_rstripped}\n{close_marker}\n"

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=note_path.parent, prefix=".update_region_", suffix=".tmp")
    try:
        with open(tmp_fd, "w") as f:
            f.write(new_text)
        Path(tmp_path).replace(note_path)
    except Exception:
        Path(tmp_path).unlink(missing_ok=True)
        raise


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: update_region.py <note-path> <region-name> <content-source>", file=sys.stderr)
        return 2

    note_path = Path(sys.argv[1])
    region = sys.argv[2]
    content_source = sys.argv[3]

    try:
        if content_source == "-":
            content = sys.stdin.read()
        else:
            src = Path(content_source)
            if not src.is_file():
                print(f"Error: content-source not found: {src}", file=sys.stderr)
                return 1
            content = src.read_text()
        update(note_path, region, content)
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
