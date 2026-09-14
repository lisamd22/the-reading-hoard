"""Job runner: canonicalise -> cache check -> resolve -> Gemini -> ground -> events.

One process, in-process queue, N workers. Every stage appends to the job's event
log so a reconnecting phone replays exactly what it missed.
"""
from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from dataclasses import dataclass

import httpx

from app import copy
from app.canonical import Canonical, Platform, canonicalise, needs_resolution, resolve_short_link
from app.gemini import GeminiExtractor
from app.grounding import ground
from app.prompt import caption_spans
from app.resolvers.base import Media, MediaKind, ResolveError, Resolver
from app.resolvers.instagram import InstagramPageResolver, ScrapeCreatorsInstagramResolver
from app.resolvers.pinterest import PinterestPageResolver
from app.resolvers.tiktok import ScrapeCreatorsTikTokResolver, TikTokPageResolver
from app.resolvers.youtube import YouTubeResolver
from app.store import Store

log = logging.getLogger("hoard.jobs")

PIPELINE_VERSION = os.environ.get("PIPELINE_VERSION", "v1")
JOB_TIMEOUT = float(os.environ.get("JOB_TIMEOUT", "60"))
FETCH_TIMEOUT = float(os.environ.get("FETCH_TIMEOUT", "20"))
# Managed vendors can take longer than a direct page fetch (one call measured >20 s).
VENDOR_FETCH_TIMEOUT = float(os.environ.get("VENDOR_FETCH_TIMEOUT", "35"))
# From a datacenter IP TikTok serves a shell page every time (measured on Fly iad),
# so there the vendor goes first and the free page path is the fallback.
TIKTOK_VENDOR_FIRST = os.environ.get("TIKTOK_VENDOR_FIRST", "0") == "1"
WORKERS = int(os.environ.get("WORKERS", "4"))
DAILY_BUDGET = int(os.environ.get("DAILY_GEMINI_CALLS", "2000"))


@dataclass
class Job:
    id: str
    url: str
    canonical: Canonical
    install_id: str


class Runner:
    def __init__(self, store: Store, client: httpx.AsyncClient, extractor: GeminiExtractor | None):
        self.store = store
        self.client = client
        self.extractor = extractor
        self.queue: asyncio.Queue[Job] = asyncio.Queue()
        self.workers: list[asyncio.Task] = []
        self.gemini_calls_today = 0
        self._day = time.strftime("%Y-%m-%d")
        # Primary -> fallback per platform. The page resolvers are free; the
        # vendor is the fallback (or primary, for Instagram, where the page gives
        # only the caption).
        tiktok: list[Resolver] = [TikTokPageResolver(client), ScrapeCreatorsTikTokResolver(client)]
        if TIKTOK_VENDOR_FIRST:
            tiktok.reverse()
        self.chains: dict[Platform, list[Resolver]] = {
            Platform.TIKTOK: tiktok,
            Platform.PINTEREST: [PinterestPageResolver(client)],
            Platform.YOUTUBE: [YouTubeResolver(client)],
            Platform.INSTAGRAM: [ScrapeCreatorsInstagramResolver(client), InstagramPageResolver(client)],
        }

    def start(self):
        for _ in range(WORKERS):
            self.workers.append(asyncio.create_task(self._worker()))

    async def stop(self):
        for w in self.workers:
            w.cancel()

    # -- submission -----------------------------------------------------------

    async def submit(self, *, url: str, client_job_id: str, install_id: str) -> dict:
        """Returns the 202 body. Fast path: cache hit replays immediately."""
        resolved = url
        try:
            if needs_resolution(url):
                resolved = await asyncio.wait_for(resolve_short_link(url, self.client), 6)
        except Exception as e:
            log.info("short-link resolve failed for %s: %s", url, e)
        canonical = canonicalise(resolved)
        if canonical.platform is Platform.UNKNOWN:
            raise ValueError("unsupported")

        job_id, created = await self.store.create_job(
            job_id=uuid.uuid4().hex[:12], client_job_id=client_job_id, install_id=install_id,
            url=url, platform=canonical.platform.value, canonical_id=canonical.item_id, state="queued")
        if not created:
            job = await self.store.get_job(job_id)
            return {"jobID": job_id, "platform": canonical.platform.value,
                    "canonicalID": canonical.item_id, "cached": job["state"] == "done", "duplicate": True}
        key = self._cache_key(canonical)
        cached = await self.store.get_result(key) if canonical.item_id else None

        if cached:
            await self.store.set_state(job_id, "done")
            await self._emit(job_id, "accepted", {"platform": canonical.platform.value,
                                                   "canonicalID": canonical.item_id, "cached": True,
                                                   "message": copy.STAGE["cached"]})
            for b in cached.get("books", []):
                await self._emit(job_id, "book", b)
            await self._emit(job_id, "done", {**cached.get("done", {}), "cached": True})
            return {"jobID": job_id, "platform": canonical.platform.value,
                    "canonicalID": canonical.item_id, "cached": True}

        neg = await self.store.get_negative(key) if canonical.item_id else None
        if neg:
            await self.store.set_state(job_id, "failed")
            await self._emit(job_id, "accepted", {"platform": canonical.platform.value, "canonicalID": canonical.item_id})
            await self._emit(job_id, "failed", {"stage": "resolve", "code": neg,
                                                 "userMessage": copy.failed_message(neg, canonical.platform.value)})
            return {"jobID": job_id, "platform": canonical.platform.value, "canonicalID": canonical.item_id, "cached": False}

        await self._emit(job_id, "accepted", {"platform": canonical.platform.value,
                                               "canonicalID": canonical.item_id, "cached": False,
                                               "message": copy.STAGE["accepted"]})
        await self.queue.put(Job(job_id, url, canonical, install_id))
        return {"jobID": job_id, "platform": canonical.platform.value, "canonicalID": canonical.item_id, "cached": False}

    # -- worker ---------------------------------------------------------------

    async def _worker(self):
        while True:
            job = await self.queue.get()
            try:
                await asyncio.wait_for(self._run(job), JOB_TIMEOUT)
            except asyncio.TimeoutError:
                await self._fail(job, "timeout", "run")
            except Exception as e:  # never let one job kill the worker
                log.exception("job %s crashed", job.id)
                await self._fail(job, "model_failed", "run", detail=str(e))
            finally:
                self.queue.task_done()

    async def _run(self, job: Job):
        await self.store.set_state(job.id, "running")
        platform = job.canonical.platform
        await self._emit(job.id, "media.fetching",
                         {"message": copy.STAGE["media.fetching"].get(platform.value, "Fetching.")})

        media, err = await self._resolve(job)
        if media is None:
            code = err.code if err else "all_failed"
            if code in ("private", "removed"):
                await self.store.put_negative(self._cache_key(job.canonical), code)
            await self._fail(job, code if code in copy.FAILED else "all_failed", "resolve",
                             detail=err.detail if err else "")
            return

        # Caption books first, so something is on screen at ~1.5 s.
        spans = {f"[c{i}]": ln for i, ln in enumerate(
            ln.strip() for ln in media.caption.splitlines() if ln.strip())}
        await self._emit(job.id, "caption", {"spans": spans, "resolver": media.resolver,
                                              "degraded": media.degraded})

        if self.extractor is None:
            await self._fail(job, "model_failed", "extract", detail="GEMINI_API_KEY not set")
            return
        if not self._budget_ok():
            await self._fail(job, "budget", "extract")
            return

        await self._emit(job.id, "media.reading", {"message": copy.STAGE["media.reading"],
                                                    "kind": media.kind.value})
        self.gemini_calls_today += 1
        books_out: list[dict] = []
        seen: set[str] = set()
        usage = None
        try:
            async for kind, payload in self.extractor.stream(media):
                if kind == "book":
                    kept, _ = ground([payload], duration_seconds=media.duration_seconds,
                                     caption_spans=spans, seen=seen)
                    for b in kept:
                        card = self._card(b, media)
                        books_out.append(card)
                        await self._emit(job.id, "book", card)
                elif kind == "done":
                    usage = payload["usage"]
        except Exception as e:
            log.exception("gemini failed for job %s", job.id)
            await self._fail(job, "model_failed", "extract", detail=str(e), partial=books_out)
            return

        done = {
            "count": len(books_out),
            "message": self._done_message(len(books_out)),
            "resolver": media.resolver, "degraded": media.degraded,
            "usage": {"model": usage.model, "ttftMs": usage.ttft_ms, "totalMs": usage.total_ms,
                      "promptTokens": usage.prompt_tokens, "outputTokens": usage.output_tokens,
                      "thinkingTokens": usage.thinking_tokens} if usage else None,
        }
        await self._emit(job.id, "done", done)
        await self.store.set_state(job.id, "done")
        if job.canonical.item_id:
            await self.store.put_result(self._cache_key(job.canonical), {"books": books_out, "done": done})

    async def _resolve(self, job: Job) -> tuple[Media | None, ResolveError | None]:
        last: ResolveError | None = None
        floor: Media | None = None
        for r in self.chains.get(job.canonical.platform, []):
            try:
                cap = VENDOR_FETCH_TIMEOUT if "scrapecreators" in r.name else FETCH_TIMEOUT
                m = await asyncio.wait_for(r.resolve(job.canonical), cap)
                if m.kind is MediaKind.TEXT_ONLY:
                    floor = floor or m
                    continue          # keep trying for real media
                return m, None
            except ResolveError as e:
                last = e
                if e.code in ("private", "removed", "too_long"):
                    return None, e    # definitive - stop the chain
                log.info("resolver %s failed on %s: %s", r.name, job.canonical.url, e)
            except asyncio.TimeoutError:
                log.info("resolver %s timed out on %s", r.name, job.canonical.url)
                last = ResolveError("resolver_timeout", r.name, retryable=True)
            except Exception as e:
                last = ResolveError("resolver_error", f"{r.name}: {e}", retryable=True)
        if floor:
            return floor, None
        return None, last

    # -- helpers --------------------------------------------------------------

    def _card(self, b: dict, media: Media) -> dict:
        """Shape a grounded book for the phone. Evidence maps onto EvidenceSpan."""
        chan = {"spoken": "spokenAudio", "on_screen_text": "onScreenText",
                "cover_visible": "onScreenText", "caption": "caption", "comment": "caption"}
        return {
            "title": b["title_verbatim"],
            "authorHint": b.get("author_verbatim"),
            "series": b.get("series_or_edition_verbatim"),
            "confidence": b.get("confidence", "medium"),
            "isRecommended": bool(b.get("is_recommended", True)),
            "legibilityNote": b.get("legibility_note"),
            "evidence": [{
                "id": f"{e['modality'][0]}{i}",
                "channel": chan.get(e["modality"], "onScreenText"),
                "text": e["quote"],
                "startSeconds": e.get("_seconds"),
                "modality": e["modality"],
            } for i, e in enumerate(b.get("evidence", []))],
            "source": {"platform": media.canonical.platform.value, "itemID": media.canonical.item_id,
                       "canonicalURL": media.canonical.url, "creatorHandle": media.creator},
        }

    async def _fail(self, job: Job, code: str, stage: str, *, detail: str = "", partial: list | None = None):
        await self.store.set_state(job.id, "failed")
        await self._emit(job.id, "failed", {
            "stage": stage, "code": code, "detail": detail[:300],
            "userMessage": copy.failed_message(code, job.canonical.platform.value, bool(partial)),
            "partialCount": len(partial or []),
        })

    async def _emit(self, job_id: str, type_: str, payload: dict):
        await self.store.append_event(job_id, type_, payload)

    def _cache_key(self, c: Canonical) -> str:
        return f"{c.platform.value}:{c.item_id}:{PIPELINE_VERSION}"

    def _budget_ok(self) -> bool:
        today = time.strftime("%Y-%m-%d")
        if today != self._day:
            self._day, self.gemini_calls_today = today, 0
        return self.gemini_calls_today < DAILY_BUDGET

    @staticmethod
    def _done_message(n: int) -> str:
        if n == 0:
            return "The library watched the whole reel and found no book it could name."
        if n == 1:
            return "One book remembered."
        return f"{n} books remembered."
