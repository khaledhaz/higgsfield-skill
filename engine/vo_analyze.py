#!/usr/bin/env python3
"""vo_analyze.py — run openai-whisper on an audio file and emit beats.json.

Usage: vo_analyze.py <audio-path> <script-path> <beats-out>
  (CLI wired up in Task 5; this file currently exposes align() as a library.)

align(whisper_segments, script_text, beat_splits=None) -> list[beat]
  Produces per-beat timing by matching the script's sentence boundaries to
  Whisper's word-level timestamps via rapidfuzz fuzzy matching.

A "beat" in beats.json:
  {
    "id": int (1-indexed),
    "claim_ar": str,
    "claim_en": "",          # English translation left empty; prompt-writer handles
    "start": float (seconds),
    "end": float (seconds),
    "duration": float,
    "word_count": int,
    "confidence": float      # mean Whisper word probability in this beat
  }
"""
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

try:
    from rapidfuzz import fuzz
except ImportError:
    fuzz = None  # only needed for fuzzy fallback; exact-match path works without it


SENTENCE_SPLIT_RE = re.compile(r"[.?؟!۔؛]|\s{3,}")


def _split_script(script_text: str) -> list:
    """Split script into claim-level chunks on sentence/clause boundaries."""
    text = script_text.strip()
    parts = SENTENCE_SPLIT_RE.split(text)
    return [p.strip() for p in parts if p.strip()]


def _flatten_words(segments: list) -> list:
    """Flatten Whisper segments into a single word list (skip punctuation-only tokens)."""
    words = []
    for seg in segments:
        for w in seg.get("words", []):
            tok = w.get("word", "").strip()
            if not tok:
                continue
            if re.fullmatch(r"[\.\,\!\?\؟\۔\؛\:\;۔]+", tok):
                continue
            words.append({
                "word": tok,
                "start": float(w["start"]),
                "end": float(w["end"]),
                "prob": float(w.get("probability", 1.0)),
            })
    return words


def _match_claim_to_words(claim: str, words: list, start_from: int) -> tuple:
    """Find the best contiguous word-span in `words` starting at start_from whose
    concatenation best matches `claim`. Returns (begin_idx, end_idx_exclusive)."""
    claim_tokens = [t for t in re.split(r"\s+", claim) if t]
    if not claim_tokens:
        return start_from, start_from

    target_len = len(claim_tokens)
    min_len = max(1, int(target_len * 0.7))
    max_len = min(len(words) - start_from, int(target_len * 1.5) + 3)

    best_end = start_from + min_len
    best_score = -1.0

    for n in range(min_len, max_len + 1):
        end = start_from + n
        if end > len(words):
            break
        span_text = " ".join(w["word"] for w in words[start_from:end])
        if fuzz is not None:
            # Use ratio (not partial_ratio) so score peaks at the exact-length match
            # and drops when we over-consume words from the next beat.
            score = fuzz.ratio(claim, span_text)
        else:
            claim_set = set(claim_tokens)
            span_set = set(span_text.split())
            score = 100.0 * len(claim_set & span_set) / max(1, len(claim_set))
        if score > best_score:
            best_score = score
            best_end = end

    return start_from, best_end


def align(whisper_segments: list, script_text: str, beat_splits: list = None) -> list:
    """Align Whisper word-level timings to script sentence boundaries.

    Returns a list of beat dicts as described in the module docstring.
    """
    words = _flatten_words(whisper_segments)
    if not words:
        return []

    if beat_splits is None:
        claims = _split_script(script_text)
    else:
        claims = []
        prev = 0
        for off in beat_splits:
            chunk = script_text[prev:off].strip()
            if chunk:
                claims.append(chunk)
            prev = off
        tail = script_text[prev:].strip()
        if tail:
            claims.append(tail)

    beats = []
    cursor = 0
    for idx, claim in enumerate(claims, start=1):
        begin, end_excl = _match_claim_to_words(claim, words, cursor)
        if end_excl <= begin:
            remaining_claims = len(claims) - (idx - 1)
            remaining_words = len(words) - cursor
            span = max(1, remaining_words // remaining_claims)
            begin = cursor
            end_excl = min(len(words), cursor + span)

        span_words = words[begin:end_excl]
        if span_words:
            start_t = span_words[0]["start"]
            end_t = span_words[-1]["end"]
            mean_conf = sum(w["prob"] for w in span_words) / len(span_words)
            beats.append({
                "id": idx,
                "claim_ar": claim,
                "claim_en": "",
                "start": round(start_t, 3),
                "end": round(end_t, 3),
                "duration": round(end_t - start_t, 3),
                "word_count": len(span_words),
                "confidence": round(mean_conf, 3),
            })
            cursor = end_excl
        else:
            anchor = beats[-1]["end"] if beats else 0.0
            print(f"vo_analyze: claim {idx} had no audio words", file=sys.stderr)
            beats.append({
                "id": idx,
                "claim_ar": claim,
                "claim_en": "",
                "start": round(anchor, 3),
                "end": round(anchor, 3),
                "duration": 0.0,
                "word_count": 0,
                "confidence": 0.0,
            })

    # Defensive: re-sequence ids so gaps (from any future logic) don't break consumers.
    for i, b in enumerate(beats, start=1):
        b["id"] = i
    return beats


def run_whisper(audio_path: Path, model_name: str = "medium") -> list:
    """Invoke openai-whisper and return its segments list (with word timestamps)."""
    import whisper as _whisper  # lazy import: slow to load
    model = _whisper.load_model(model_name)
    result = model.transcribe(str(audio_path), word_timestamps=True, verbose=False)
    return result.get("segments", [])


def analyze(audio_path: Path, script_path: Path, beats_out_path: Path,
            model_name: str = None) -> int:
    if not audio_path.is_file():
        raise FileNotFoundError(f"audio not found: {audio_path}")
    if not script_path.is_file():
        raise FileNotFoundError(f"script not found: {script_path}")
    model_name = model_name or os.environ.get("HF_WHISPER_MODEL", "medium")

    t0 = time.time()
    segments = run_whisper(audio_path, model_name=model_name)
    script_text = script_path.read_text()
    beats = align(segments, script_text)
    elapsed = time.time() - t0

    tmp_fd, tmp_path = tempfile.mkstemp(dir=beats_out_path.parent,
                                        prefix=".vo_analyze_", suffix=".tmp")
    try:
        with open(tmp_fd, "w") as f:
            json.dump(beats, f, indent=2, ensure_ascii=False)
            f.write("\n")
        Path(tmp_path).replace(beats_out_path)
    except Exception:
        Path(tmp_path).unlink(missing_ok=True)
        raise

    print(f"OK {len(beats)} beats in {elapsed:.1f}s")
    return 0


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: vo_analyze.py <audio-path> <script-path> <beats-out-path>", file=sys.stderr)
        return 2
    try:
        return analyze(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
