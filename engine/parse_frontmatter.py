#!/usr/bin/env python3
"""parse_frontmatter.py — read a markdown note's YAML frontmatter and print it as JSON.

Usage: parse_frontmatter.py <path-to-note>

Exits non-zero if:
- file missing
- no frontmatter block present
- frontmatter is not valid YAML
"""
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)


def parse(path: Path) -> dict:
    if not path.is_file():
        raise FileNotFoundError(f"note not found: {path}")

    text = path.read_text()

    if not text.startswith("---\n"):
        raise ValueError(f"no frontmatter block at start of {path}")

    parts = text.split("\n---\n", 1)
    if len(parts) < 2:
        raise ValueError(f"unterminated frontmatter block in {path}")

    front = parts[0][4:]
    data = yaml.safe_load(front)
    if not isinstance(data, dict):
        raise ValueError(f"frontmatter is not a mapping in {path}")
    return data


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: parse_frontmatter.py <note-path>", file=sys.stderr)
        return 2
    try:
        data = parse(Path(sys.argv[1]))
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    print(json.dumps(data, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
