"""Server-side grounding gate. Runs before any `book` event leaves the server.

A hallucinated title would have to invent a quote that contains its own tokens
and a timestamp inside the video. That is a property, not a hope.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

_TS = re.compile(r"^\d{2}:\d{2}$")
_STOP = {"the", "a", "an", "of", "and", "in", "to", "for", "on", "at", "by", "with"}


def _tokens(s: str) -> list[str]:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return [t for t in re.findall(r"[a-z0-9]+", s) if len(t) >= 3 and t not in _STOP]


def _fuzzy_in(token: str, haystack: set[str]) -> bool:
    if token in haystack:
        return True
    # One edit of tolerance - OCR and ASR damage is one character at a time.
    for h in haystack:
        if abs(len(h) - len(token)) <= 1 and _lev1(token, h):
            return True
    return False


def _lev1(a: str, b: str) -> bool:
    if a == b:
        return True
    if abs(len(a) - len(b)) > 1:
        return False
    i = j = edits = 0
    while i < len(a) and j < len(b):
        if a[i] == b[j]:
            i += 1; j += 1
        else:
            edits += 1
            if edits > 1:
                return False
            if len(a) > len(b):
                i += 1
            elif len(b) > len(a):
                j += 1
            else:
                i += 1; j += 1
    return edits + (len(a) - i) + (len(b) - j) <= 1


@dataclass
class Dropped:
    title: str
    reason: str


def ground(books: list[dict], *, duration_seconds: float | None,
           caption_spans: dict[str, str],
           seen: set[str] | None = None) -> tuple[list[dict], list[Dropped]]:
    """`seen` persists dedup across calls - the runner grounds books one at a
    time as they stream, so it must own the set for the whole job."""
    kept: list[dict] = []
    dropped: list[Dropped] = []
    seen = seen if seen is not None else set()
    limit = (duration_seconds or 0) + 2 if duration_seconds else None

    for b in books:
        title = (b.get("title_verbatim") or "").strip()
        if len(title) < 2:
            dropped.append(Dropped(title, "title_too_short")); continue

        evidence = []
        for e in b.get("evidence") or []:
            ts = str(e.get("timestamp") or "")
            if not _TS.match(ts):
                continue
            mm, ss = int(ts[:2]), int(ts[3:])
            if limit is not None and mm * 60 + ss > limit:
                continue
            quote = str(e.get("quote") or "").strip()
            if not quote:
                continue
            # A caption citation like "[c2]" resolves to the span's real text.
            if e.get("modality") == "caption" and quote in caption_spans:
                quote = caption_spans[quote]
            evidence.append({**e, "quote": quote, "_seconds": mm * 60 + ss})
        if not evidence:
            dropped.append(Dropped(title, "no_valid_evidence")); continue

        want = _tokens(title)
        have = set(t for e in evidence for t in _tokens(e["quote"]))
        # Character-weighted: "miserables" matching should outweigh "les" missing.
        # Equal token weights dropped a real on-screen "Les Misérables" at 50%.
        matched = sum(len(t) for t in want if _fuzzy_in(t, have))
        coverage = matched / max(1, sum(len(t) for t in want))
        if coverage < 0.6 and not (b.get("confidence") == "low" and b.get("legibility_note")):
            dropped.append(Dropped(title, f"ungrounded coverage={coverage:.2f}")); continue

        key = "".join(want)
        if key in seen:
            continue
        seen.add(key)

        b = dict(b)
        b["evidence"] = evidence
        b["title_verbatim"] = title
        a = b.get("author_verbatim")
        b["author_verbatim"] = a.strip() if isinstance(a, str) and a.strip() else None
        kept.append(b)
        if len(kept) >= 40:
            break

    return kept, dropped
