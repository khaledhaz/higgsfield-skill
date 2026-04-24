#!/usr/bin/env python3
"""reference_downloader.py — fetch an image URL to disk, validated.

Usage: reference_downloader.py <url> <target_dir>

Exits 0 on success and prints the absolute path of the saved file.
Exits 1 on any error (non-2xx HTTP, wrong content-type, write failure).

Filename is deterministic: <sha1(url)[:12]><ext> so re-running on the same URL
is idempotent — the caller can safely re-invoke without creating duplicates.
"""
import hashlib
import sys
import urllib.request
import urllib.error
from pathlib import Path

CONTENT_TYPE_TO_EXT = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/webp": ".webp",
}

def download(url: str, target_dir: Path) -> Path:
    target_dir.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "higgsfield-reference-downloader/1"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            ct = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            if ct not in CONTENT_TYPE_TO_EXT:
                raise ValueError(f"unsupported content-type: {ct!r}")
            body = resp.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} for {url}") from e
    if len(body) < 50:
        raise ValueError(f"response body too small ({len(body)} bytes) — likely error page")
    ext = CONTENT_TYPE_TO_EXT[ct]
    name = hashlib.sha1(url.encode("utf-8")).hexdigest()[:12] + ext
    dest = target_dir / name
    tmp = dest.with_suffix(ext + ".tmp")
    tmp.write_bytes(body)
    tmp.rename(dest)
    return dest

def main() -> int:
    if len(sys.argv) != 3:
        print("usage: reference_downloader.py <url> <target_dir>", file=sys.stderr)
        return 2
    url, target_dir = sys.argv[1], Path(sys.argv[2]).resolve()
    try:
        path = download(url, target_dir)
    except Exception as e:
        print(f"reference_downloader: {e}", file=sys.stderr)
        return 1
    print(path)
    return 0

if __name__ == "__main__":
    sys.exit(main())
