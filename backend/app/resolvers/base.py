"""The seam every platform sits behind.

A resolver turns a canonical post URL into `Media`: the caption/text the platform
gives away for free, plus either video bytes, image bytes, or a URI Gemini can
ingest directly (YouTube). Each platform has a primary and a fallback resolver and
a caption-only floor, so a platform break degrades the product rather than
killing it.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Protocol

from app.canonical import Canonical


class MediaKind(str, Enum):
    VIDEO = "video"
    IMAGES = "images"
    """Gemini ingests the URL itself; we hold no bytes."""
    REMOTE_VIDEO_URI = "remote_video_uri"
    """Caption only - the platform gave us no media. Still worth an LLM pass."""
    TEXT_ONLY = "text_only"


class ResolveError(Exception):
    """Mapped to a user-facing message by the job runner. `code` is stable."""

    def __init__(self, code: str, detail: str = "", *, retryable: bool = False):
        super().__init__(detail or code)
        self.code = code
        self.detail = detail
        self.retryable = retryable


@dataclass
class Media:
    canonical: Canonical
    kind: MediaKind
    caption: str = ""
    creator: str | None = None
    duration_seconds: float | None = None
    """Creator's own comments on their post - titles are often pinned here."""
    comments: list[str] = field(default_factory=list)
    video_bytes: bytes | None = None
    video_mime: str = "video/mp4"
    image_bytes: list[bytes] = field(default_factory=list)
    image_mime: str = "image/jpeg"
    remote_uri: str | None = None
    """Which resolver produced this - surfaced in telemetry and degraded copy."""
    resolver: str = ""
    degraded: bool = False


class Resolver(Protocol):
    name: str

    async def resolve(self, canonical: Canonical) -> Media: ...


IPHONE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
)

# Hard sanity cap on what we will hold in memory for one post. Measured: a 147 s
# Instagram reel at 720p is 22.3 MB, so real content routinely exceeds Gemini's
# 20 MB inline limit. The Gemini layer chooses inline vs. Files API by size; this
# cap only guards against pathological inputs.
MAX_MEDIA_BYTES = 100 * 1024 * 1024
# Gemini's inline ceiling is 20 MB. Nothing is ever sent above this.
INLINE_LIMIT_BYTES = 19 * 1024 * 1024
# Chunk target for long videos. Time-to-first-book scales ~linearly with tokens per
# call (measured: 6k tokens -> 1.5 s, 22k -> 10.5 s), so smaller parallel chunks
# cut latency directly at the cost of a little overlap. ~8 MB is ~50 s at 720p.
CHUNK_TARGET_BYTES = int(__import__("os").environ.get("CHUNK_TARGET_BYTES", str(8 * 1024 * 1024)))
