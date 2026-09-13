"""The one AI call. Video (or images, or a YouTube URI) + text -> streamed JSON.

Books are emitted one at a time as each closes in the stream, so the phone shows
the first card in seconds while the model is still watching the rest. Long videos
are split into inline-sized chunks and watched in parallel - the Files API is
never used (measured: 11.6 s of server-side processing wait on a 22 MB reel).
"""
from __future__ import annotations

import asyncio
import json
import os
import time
from dataclasses import dataclass, field
from typing import AsyncIterator

from google import genai
from google.genai import types

from app.media import Chunk, split_for_inline
from app.prompt import SYSTEM, caption_spans, user_text
from app.resolvers.base import CHUNK_TARGET_BYTES, INLINE_LIMIT_BYTES, Media, MediaKind
from app.schema import RESPONSE_SCHEMA

# Pin dated versions in production. These are the plan's defaults; E3 decides.
PRIMARY_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")
HEDGE_MODEL = os.environ.get("GEMINI_HEDGE_MODEL", "gemini-3.8-flash")


@dataclass
class Usage:
    model: str
    chunks: int = 1
    ttft_ms: int = 0
    total_ms: int = 0
    prompt_tokens: int = 0
    output_tokens: int = 0
    thinking_tokens: int = 0


class GeminiExtractor:
    def __init__(self, api_key: str | None = None, model: str = PRIMARY_MODEL):
        key = api_key or os.environ.get("GEMINI_API_KEY", "")
        if not key:
            raise RuntimeError("GEMINI_API_KEY not set")
        self.client = genai.Client(api_key=key)
        self.model = model

    # -- public ---------------------------------------------------------------

    async def stream(self, media: Media, *, fps: float | None = None) -> AsyncIterator[tuple[str, object]]:
        """Yields ("book", dict) per closed book, then ("done", {"json", "usage", "raw"})."""
        if media.kind is MediaKind.VIDEO and media.video_bytes and len(media.video_bytes) > CHUNK_TARGET_BYTES:
            chunks = await split_for_inline(media.video_bytes, max_bytes=INLINE_LIMIT_BYTES,
                                            duration_seconds=media.duration_seconds,
                                            target_bytes=CHUNK_TARGET_BYTES)
            async for ev in self._stream_parallel(media, chunks, fps=fps):
                yield ev
        else:
            async for ev in self._stream_one(media, self._media_parts(media, None, fps), offset=0.0):
                yield ev

    # -- one call -------------------------------------------------------------

    def _media_parts(self, media: Media, chunk: Chunk | None, fps: float | None) -> list[types.Part]:
        parts: list[types.Part] = []
        if media.kind is MediaKind.VIDEO:
            data = chunk.data if chunk else media.video_bytes
            if data:
                p = types.Part.from_bytes(data=data, mime_type=media.video_mime)
                if fps:
                    p.video_metadata = types.VideoMetadata(fps=fps)
                parts.append(p)
        elif media.kind is MediaKind.REMOTE_VIDEO_URI and media.remote_uri:
            p = types.Part.from_uri(file_uri=media.remote_uri, mime_type="video/mp4")
            if fps:
                p.video_metadata = types.VideoMetadata(fps=fps)
            parts.append(p)
        elif media.kind is MediaKind.IMAGES:
            for b in media.image_bytes:
                parts.append(types.Part.from_bytes(data=b, mime_type=media.image_mime))
        # TEXT_ONLY: the caption is the whole input.
        return parts

    def _text_part(self, media: Media, duration: float | None) -> types.Part:
        return types.Part.from_text(text=user_text(
            platform=media.canonical.platform.value, creator=media.creator,
            duration_seconds=duration, caption_spans=caption_spans(media.caption),
            comments=media.comments))

    def _config(self) -> types.GenerateContentConfig:
        thinking = types.ThinkingConfig(thinking_level=types.ThinkingLevel.MINIMAL) \
            if "lite" in self.model else types.ThinkingConfig(thinking_level=types.ThinkingLevel.LOW)
        # media_resolution is CONFIG-level on this endpoint (per-part is a 400).
        # HIGH is documented as required "when the use case involves reading dense
        # text" - title cards and covers. minItems/maxItems are rejected in the
        # schema; cardinality is enforced by the grounding gate instead.
        return types.GenerateContentConfig(
            system_instruction=SYSTEM,
            response_mime_type="application/json",
            response_json_schema=RESPONSE_SCHEMA,
            temperature=0,
            max_output_tokens=2048,
            thinking_config=thinking,
            media_resolution=types.MediaResolution.MEDIA_RESOLUTION_HIGH,
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
        )

    async def _stream_one(self, media: Media, media_parts: list[types.Part], *, offset: float,
                          duration: float | None = None) -> AsyncIterator[tuple[str, object]]:
        usage = Usage(model=self.model)
        t0 = time.monotonic()
        first = None
        buf = ""
        emitted = 0
        parser = _IncrementalBooks()
        parts = media_parts + [self._text_part(media, duration if duration is not None else media.duration_seconds)]

        async for chunk in await self.client.aio.models.generate_content_stream(
            model=self.model, contents=[types.Content(role="user", parts=parts)], config=self._config(),
        ):
            text = chunk.text or ""
            if text and first is None:
                first = time.monotonic()
                usage.ttft_ms = int((first - t0) * 1000)
            buf += text
            for book in parser.feed(text):
                emitted += 1
                yield ("book", _shift(book, offset))
            um = getattr(chunk, "usage_metadata", None)
            if um:
                usage.prompt_tokens = um.prompt_token_count or usage.prompt_tokens
                usage.output_tokens = um.candidates_token_count or usage.output_tokens
                usage.thinking_tokens = getattr(um, "thoughts_token_count", 0) or usage.thinking_tokens

        usage.total_ms = int((time.monotonic() - t0) * 1000)
        try:
            full = json.loads(buf) if buf.strip() else {"books": [], "summary": "", "language": "und"}
        except json.JSONDecodeError:
            full = {"books": parser.books, "summary": "", "language": "und", "_malformed": True}
        for book in full.get("books", [])[emitted:]:
            yield ("book", _shift(book, offset))
        yield ("done", {"json": full, "usage": usage, "raw": buf})

    # -- parallel chunks ------------------------------------------------------

    async def _stream_parallel(self, media: Media, chunks: list[Chunk], *, fps: float | None
                               ) -> AsyncIterator[tuple[str, object]]:
        """Run every chunk concurrently; emit books from whichever finishes a book
        first. `done` carries aggregated usage."""
        queue: asyncio.Queue[tuple[int, str, object] | None] = asyncio.Queue()

        async def run(i: int, c: Chunk):
            try:
                parts = self._media_parts(media, c, fps)
                async for kind, payload in self._stream_one(media, parts, offset=c.start_seconds,
                                                            duration=c.duration_seconds):
                    await queue.put((i, kind, payload))
            except Exception as e:
                await queue.put((i, "error", e))
            finally:
                await queue.put(None)

        tasks = [asyncio.create_task(run(i, c)) for i, c in enumerate(chunks)]
        t0 = time.monotonic()
        finished = 0
        agg = Usage(model=self.model, chunks=len(chunks))
        agg.ttft_ms = 0
        errors: list[Exception] = []
        merged_json: dict = {"books": [], "summary": "", "language": "und"}
        try:
            while finished < len(tasks):
                item = await queue.get()
                if item is None:
                    finished += 1
                    continue
                i, kind, payload = item
                if kind == "book":
                    if agg.ttft_ms == 0:
                        agg.ttft_ms = int((time.monotonic() - t0) * 1000)
                    yield ("book", payload)
                elif kind == "done":
                    u: Usage = payload["usage"]
                    agg.prompt_tokens += u.prompt_tokens
                    agg.output_tokens += u.output_tokens
                    agg.thinking_tokens += u.thinking_tokens
                    j = payload["json"]
                    merged_json["books"] += [_shift(b, chunks[i].start_seconds) for b in j.get("books", [])]
                    merged_json["summary"] = merged_json["summary"] or j.get("summary", "")
                    merged_json["language"] = j.get("language") or merged_json["language"]
                elif kind == "error":
                    errors.append(payload)
        finally:
            for t in tasks:
                t.cancel()
        if errors and len(errors) == len(chunks):
            raise errors[0]
        agg.total_ms = int((time.monotonic() - t0) * 1000)
        if errors:
            merged_json["_partial"] = len(errors)
        yield ("done", {"json": merged_json, "usage": agg, "raw": ""})


def _shift(book: dict, offset: float) -> dict:
    """Chunk-relative MM:SS -> whole-video MM:SS."""
    if not offset:
        return book
    b = dict(book)
    ev = []
    for e in b.get("evidence") or []:
        ts = str(e.get("timestamp") or "")
        if len(ts) == 5 and ts[2] == ":" and ts[:2].isdigit() and ts[3:].isdigit():
            secs = int(ts[:2]) * 60 + int(ts[3:]) + int(round(offset))
            e = {**e, "timestamp": f"{secs // 60:02d}:{secs % 60:02d}"}
        ev.append(e)
    b["evidence"] = ev
    return b


class _IncrementalBooks:
    """Finds complete objects inside the streaming `books` array by tracking
    brace depth. Robust to any chunking; ignores braces inside strings."""

    def __init__(self):
        self.books: list[dict] = []
        self._in_books = False
        self._depth = 0
        self._cur: list[str] = []
        self._in_str = False
        self._esc = False
        self._prefix = ""

    def feed(self, text: str) -> list[dict]:
        out: list[dict] = []
        for ch in text:
            if not self._in_books:
                self._prefix += ch
                if '"books"' in self._prefix and self._prefix.rstrip().endswith("["):
                    self._in_books = True
                    self._prefix = ""
                elif len(self._prefix) > 200:
                    self._prefix = self._prefix[-50:]
                continue
            if self._depth == 0:
                if ch == "{":
                    self._depth = 1
                    self._cur = [ch]
                elif ch == "]":
                    self._in_books = False
                continue
            self._cur.append(ch)
            if self._in_str:
                if self._esc:
                    self._esc = False
                elif ch == "\\":
                    self._esc = True
                elif ch == '"':
                    self._in_str = False
                continue
            if ch == '"':
                self._in_str = True
            elif ch == "{":
                self._depth += 1
            elif ch == "}":
                self._depth -= 1
                if self._depth == 0:
                    try:
                        book = json.loads("".join(self._cur))
                        self.books.append(book)
                        out.append(book)
                    except json.JSONDecodeError:
                        pass
                    self._cur = []
        return out
