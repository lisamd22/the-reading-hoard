"""The Reading Hoard API.

POST /v1/jobs            -> 202 {jobID, platform, canonicalID, cached}
GET  /v1/jobs/{id}/events -> SSE, honours Last-Event-ID, replays the log
GET  /v1/jobs/{id}        -> JSON snapshot (polling fallback)
GET  /v1/status           -> health
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field

from app.gemini import GeminiExtractor
from app.jobs import Runner
from app.store import Store

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
log = logging.getLogger("hoard")

DB_PATH = os.environ.get("DB_PATH", "./hoard.db")
APP_KEY = os.environ.get("APP_KEY", "")          # Phase 1 static key; App Attest in Phase 5
DAILY_PER_INSTALL = int(os.environ.get("DAILY_PER_INSTALL", "20"))


@asynccontextmanager
async def lifespan(app: FastAPI):
    store = Store(DB_PATH)
    await store.open()
    client = httpx.AsyncClient(timeout=20, follow_redirects=False,
                               limits=httpx.Limits(max_connections=32))
    extractor = None
    if os.environ.get("GEMINI_API_KEY"):
        extractor = GeminiExtractor()
    else:
        log.warning("GEMINI_API_KEY not set - jobs will fail at the extract stage")
    runner = Runner(store, client, extractor)
    runner.start()
    app.state.store, app.state.client, app.state.runner = store, client, runner
    try:
        yield
    finally:
        await runner.stop()
        await client.aclose()
        await store.close()


app = FastAPI(title="hoard-api", lifespan=lifespan)


class JobIn(BaseModel):
    url: str = Field(min_length=8, max_length=2048)
    clientJobID: str = Field(min_length=8, max_length=64)
    storefront: str | None = None
    locale: str | None = None


def _auth(x_app_key: str | None, x_install_id: str | None) -> str:
    if APP_KEY and x_app_key != APP_KEY:
        raise HTTPException(401, "bad app key")
    if not x_install_id or len(x_install_id) < 8:
        raise HTTPException(400, "X-Install-ID required")
    return x_install_id


@app.post("/v1/jobs", status_code=202)
async def create_job(body: JobIn, request: Request,
                     x_app_key: str | None = Header(default=None),
                     x_install_id: str | None = Header(default=None)):
    install = _auth(x_app_key, x_install_id)
    store: Store = request.app.state.store
    count = await store.bump_install(install, time.strftime("%Y-%m-%d"))
    if count > DAILY_PER_INSTALL:
        raise HTTPException(429, "daily limit", headers={"Retry-After": "3600"})
    try:
        return await request.app.state.runner.submit(
            url=body.url, client_job_id=body.clientJobID, install_id=install)
    except ValueError:
        raise HTTPException(422, "unsupported link")


@app.get("/v1/jobs/{job_id}")
async def get_job(job_id: str, request: Request):
    store: Store = request.app.state.store
    job = await store.get_job(job_id)
    if not job:
        raise HTTPException(404)
    events = await store.events_after(job_id, 0)
    books = [p for _, t, p in events if t == "book"]
    done = next((p for _, t, p in events if t == "done"), None)
    failed = next((p for _, t, p in events if t == "failed"), None)
    return {**job, "books": books, "done": done, "failed": failed}


@app.get("/v1/jobs/{job_id}/events")
async def job_events(job_id: str, request: Request,
                     last_event_id: str | None = Header(default=None)):
    store: Store = request.app.state.store
    if not await store.get_job(job_id):
        raise HTTPException(404)
    since = int(last_event_id) if last_event_id and last_event_id.isdigit() else 0

    async def gen():
        seq = since
        idle = 0.0
        while True:
            if await request.is_disconnected():
                return
            events = await store.events_after(job_id, seq)
            for s, t, p in events:
                seq = s
                yield f"id: {s}\nevent: {t}\ndata: {json.dumps(p)}\n\n"
                if t in ("done", "failed"):
                    return
            if events:
                idle = 0.0
            else:
                await asyncio.sleep(0.25)
                idle += 0.25
                if idle >= 15:
                    yield ": ping\n\n"
                    idle = 0.0

    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@app.get("/v1/status")
async def status(request: Request):
    r: Runner = request.app.state.runner
    return {"ok": True, "gemini": r.extractor is not None, "queued": r.queue.qsize(),
            "geminiCallsToday": r.gemini_calls_today,
            "vendors": {"scrapecreators": bool(os.environ.get("SCRAPECREATORS_API_KEY")),
                        "youtube": bool(os.environ.get("YOUTUBE_API_KEY"))}}


@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception):
    log.exception("unhandled")
    return JSONResponse(500, {"error": "internal"})
