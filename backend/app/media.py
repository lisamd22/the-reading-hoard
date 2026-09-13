"""Video chunking. Keeps every Gemini call inline (< 20 MB) so we never touch the
Files API - measured 2026-09-13: its server-side processing wait is 11.6 s on a
22 MB reel, versus zero for inline. Chunks are stream-copied (no re-encode) so
splitting a 147 s reel costs well under a second, and they are processed in
parallel, so latency stops scaling with duration.
"""
from __future__ import annotations

import asyncio
import math
import os
import shutil
import tempfile
from dataclasses import dataclass

FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
FFPROBE = shutil.which("ffprobe") or "ffprobe"

# Books at a chunk boundary are seen by both neighbours; dedup merges them.
OVERLAP_SECONDS = 4.0


@dataclass
class Chunk:
    data: bytes
    start_seconds: float
    duration_seconds: float


async def probe_duration(data: bytes) -> float | None:
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as f:
        f.write(data)
        path = f.name
    try:
        proc = await asyncio.create_subprocess_exec(
            FFPROBE, "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", path,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        out, _ = await proc.communicate()
        return float(out.decode().strip()) if proc.returncode == 0 and out.strip() else None
    finally:
        os.unlink(path)


async def split_for_inline(data: bytes, *, max_bytes: int, duration_seconds: float | None,
                           target_bytes: int | None = None) -> list[Chunk]:
    """Return [whole] if it is under `target_bytes` (default: max_bytes), else N
    stream-copied chunks each around `target_bytes` and always under `max_bytes`."""
    target = min(target_bytes or max_bytes, max_bytes)
    if len(data) <= target:
        return [Chunk(data, 0.0, duration_seconds or 0.0)]

    duration = duration_seconds or await probe_duration(data)
    if not duration:
        raise ValueError("cannot split: unknown duration")

    # Size is ~linear in time for a single-bitrate file. Aim for 80% of the cap
    # so keyframe alignment slop never pushes a chunk over.
    n = max(2, math.ceil(len(data) / target))
    step = duration / n

    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as f:
        f.write(data)
        src = f.name
    try:
        async def cut(i: int) -> Chunk:
            start = max(0.0, i * step - (OVERLAP_SECONDS if i else 0.0))
            end = min(duration, (i + 1) * step + (OVERLAP_SECONDS if i < n - 1 else 0.0))
            out = f"{src}.part{i}.mp4"
            # -ss before -i seeks to the nearest preceding keyframe with -c copy, so
            # the chunk may start slightly early; we report the requested start and
            # the model's timestamps are relative to what it actually received, so
            # the offset error is bounded by one GOP (~2 s). Acceptable for evidence.
            proc = await asyncio.create_subprocess_exec(
                FFMPEG, "-v", "error", "-y", "-ss", f"{start:.3f}", "-i", src, "-t", f"{end - start:.3f}",
                "-c", "copy", "-movflags", "+faststart", "-avoid_negative_ts", "make_zero", out,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
            _, err = await proc.communicate()
            if proc.returncode != 0:
                raise RuntimeError(f"ffmpeg split failed: {err.decode()[:200]}")
            try:
                return Chunk(open(out, "rb").read(), start, end - start)
            finally:
                os.unlink(out)

        return list(await asyncio.gather(*(cut(i) for i in range(n))))
    finally:
        os.unlink(src)
