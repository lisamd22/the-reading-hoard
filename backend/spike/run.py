"""Phase 0 spike: run the real pipeline on the real links and measure.

    cd backend && set -a && source .env && set +a
    .venv/bin/python spike/run.py [--model gemini-3.8-flash] [url ...]

Prints, per link: resolver used, media kind and size, Gemini TTFT, total time,
tokens, and every book with its evidence. Writes spike/RESULTS.md.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import httpx

from app.canonical import canonicalise, needs_resolution, resolve_short_link
from app.gemini import GeminiExtractor
from app.grounding import ground
from app.jobs import Runner
from app.resolvers.base import MediaKind
from app.store import Store

# The four real links from the device probe, plus one known-good TikTok video.
DEFAULT_LINKS = [
    "https://vm.tiktok.com/ZGdxo8VFD/",                               # TikTok photo carousel
    "https://www.tiktok.com/@scout2015/video/6718335390845095173",    # TikTok video (public, oEmbed-verified)
    "https://pin.it/33Ms191Jr",                                       # Pinterest video pin
    "https://youtube.com/shorts/4-vP5OCmqWA",                         # YouTube Short
    "https://www.instagram.com/reel/DbOYmimJhWZ/",                    # Instagram reel (caption floor unless vendor key)
]


async def run_one(url: str, runner: Runner, extractor: GeminiExtractor) -> dict:
    out = {"url": url}
    t0 = time.monotonic()
    resolved = await resolve_short_link(url, runner.client) if needs_resolution(url) else url
    can = canonicalise(resolved)
    out["platform"], out["id"] = can.platform.value, can.item_id
    t1 = time.monotonic()

    from types import SimpleNamespace
    job = SimpleNamespace(canonical=can, id="spike", url=url, install_id="spike")
    media, err = await runner._resolve(job)
    t2 = time.monotonic()
    if media is None:
        out["error"] = f"{err.code}: {err.detail}" if err else "resolve failed"
        return out
    out.update(resolver=media.resolver, kind=media.kind.value, degraded=media.degraded,
               resolve_s=round(t1 - t0, 2), fetch_s=round(t2 - t1, 2),
               bytes=len(media.video_bytes or b"") + sum(len(b) for b in media.image_bytes),
               caption=media.caption[:120])

    spans = {f"[c{i}]": ln for i, ln in enumerate(ln.strip() for ln in media.caption.splitlines() if ln.strip())}
    books, dropped, usage = [], [], None
    seen: set[str] = set()
    t3 = time.monotonic()
    first_book = None
    try:
        async for kind, payload in extractor.stream(media):
            if kind == "book":
                if first_book is None:
                    first_book = round(time.monotonic() - t3, 2)
                kept, drop = ground([payload], duration_seconds=media.duration_seconds, caption_spans=spans, seen=seen)
                books += kept; dropped += drop
            elif kind == "done":
                usage = payload["usage"]
                if payload["json"].get("_malformed"):
                    out["malformed"] = True
    except Exception as e:
        out["gemini_error"] = f"{type(e).__name__}: {str(e)[:200]}"
        return out
    out.update(first_book_s=first_book, chunks=usage.chunks, ttft_ms=usage.ttft_ms, total_ms=usage.total_ms,
               prompt_tokens=usage.prompt_tokens, output_tokens=usage.output_tokens,
               thinking_tokens=usage.thinking_tokens,
               books=[{"title": b["title_verbatim"], "author": b.get("author_verbatim"),
                       "confidence": b["confidence"], "rec": b["is_recommended"],
                       "evidence": [f"{e['timestamp']} {e['modality']}: {e['quote'][:60]}" for e in b["evidence"]]}
                      for b in books],
               dropped=[f"{d.title} ({d.reason})" for d in dropped])
    return out


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite"))
    ap.add_argument("urls", nargs="*")
    a = ap.parse_args()
    if not os.environ.get("GEMINI_API_KEY"):
        sys.exit("GEMINI_API_KEY not set. Put it in backend/.env and `set -a; source .env; set +a`.")

    extractor = GeminiExtractor(model=a.model)
    store = Store(":memory:"); await store.open()
    try:
        async with httpx.AsyncClient(timeout=25, follow_redirects=False) as client:
            runner = Runner(store, client, extractor)
            results = []
            for u in (a.urls or DEFAULT_LINKS):
                print(f"... {u}", file=sys.stderr, flush=True)
                results.append(await run_one(u, runner, extractor))
    finally:
        # aiosqlite's worker thread is not a daemon; an unclosed store keeps the
        # process alive forever after main() returns.
        await store.close()

    print(json.dumps(results, indent=2, ensure_ascii=False))
    lines = [f"# Spike results - {time.strftime('%Y-%m-%d %H:%M')} - model `{a.model}`\n"]
    for r in results:
        lines.append(f"## {r['platform']} `{r.get('id')}`")
        if "error" in r or "gemini_error" in r:
            lines.append(f"- FAILED: {r.get('error') or r.get('gemini_error')}\n"); continue
        lines.append(f"- {r['resolver']} -> {r['kind']} {r['bytes']/1e6:.2f} MB, resolve {r['resolve_s']}s, fetch {r['fetch_s']}s")
        lines.append(f"- Gemini: {r.get('chunks',1)} chunk(s), first book {r.get('first_book_s')}s, TTFT {r['ttft_ms']} ms, total {r['total_ms']} ms, "
                     f"tokens in {r['prompt_tokens']} / out {r['output_tokens']} / think {r['thinking_tokens']}")
        lines.append(f"- **{len(r['books'])} books**" + (f", {len(r['dropped'])} dropped by grounding" if r['dropped'] else ""))
        for b in r["books"]:
            lines.append(f"  - **{b['title']}** — {b['author'] or '_no author seen_'} [{b['confidence']}]")
            for e in b["evidence"]:
                lines.append(f"    - {e}")
        lines.append("")
    open(os.path.join(os.path.dirname(__file__), "RESULTS.md"), "w").write("\n".join(lines))
    print("\nwrote spike/RESULTS.md")


asyncio.run(main())
