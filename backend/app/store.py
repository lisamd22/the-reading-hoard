"""SQLite on the Fly volume. Results are a cache - the library lives on the phone.

Tables: results (30 d), negative (1 h for private/removed), events (24 h, the
per-job SSE log so a reconnecting phone can replay), installs (daily counter).
Media bytes are never written here.
"""
from __future__ import annotations

import json
import time

import aiosqlite

_SCHEMA = """
CREATE TABLE IF NOT EXISTS results (
  key TEXT PRIMARY KEY, json TEXT NOT NULL, created REAL NOT NULL, touched REAL NOT NULL);
CREATE TABLE IF NOT EXISTS negative (
  key TEXT PRIMARY KEY, code TEXT NOT NULL, until REAL NOT NULL);
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY, client_job_id TEXT UNIQUE, install_id TEXT, url TEXT NOT NULL,
  platform TEXT, canonical_id TEXT, state TEXT NOT NULL, created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS events (
  job_id TEXT NOT NULL, seq INTEGER NOT NULL, type TEXT NOT NULL, json TEXT NOT NULL,
  created REAL NOT NULL, PRIMARY KEY (job_id, seq));
CREATE TABLE IF NOT EXISTS installs (
  install_id TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (install_id, day));
CREATE INDEX IF NOT EXISTS events_job ON events(job_id, seq);
"""

RESULT_TTL = 30 * 24 * 3600
NEGATIVE_TTL = 3600
EVENT_TTL = 24 * 3600


class Store:
    def __init__(self, path: str):
        self.path = path
        self.db: aiosqlite.Connection | None = None

    async def open(self):
        self.db = await aiosqlite.connect(self.path)
        await self.db.execute("PRAGMA journal_mode=WAL")
        await self.db.executescript(_SCHEMA)
        await self.db.commit()

    async def close(self):
        if self.db:
            await self.db.close()

    # -- results --------------------------------------------------------------

    async def get_result(self, key: str) -> dict | None:
        async with self.db.execute("SELECT json, created FROM results WHERE key=?", (key,)) as c:
            row = await c.fetchone()
        if not row:
            return None
        if time.time() - row[1] > RESULT_TTL:
            await self.db.execute("DELETE FROM results WHERE key=?", (key,)); await self.db.commit()
            return None
        await self.db.execute("UPDATE results SET touched=? WHERE key=?", (time.time(), key))
        await self.db.commit()
        return json.loads(row[0])

    async def put_result(self, key: str, value: dict):
        now = time.time()
        await self.db.execute(
            "INSERT OR REPLACE INTO results(key,json,created,touched) VALUES(?,?,?,?)",
            (key, json.dumps(value), now, now))
        await self.db.commit()

    async def get_negative(self, key: str) -> str | None:
        async with self.db.execute("SELECT code, until FROM negative WHERE key=?", (key,)) as c:
            row = await c.fetchone()
        if row and row[1] > time.time():
            return row[0]
        return None

    async def put_negative(self, key: str, code: str):
        await self.db.execute("INSERT OR REPLACE INTO negative(key,code,until) VALUES(?,?,?)",
                              (key, code, time.time() + NEGATIVE_TTL))
        await self.db.commit()

    # -- jobs + events --------------------------------------------------------

    async def create_job(self, *, job_id: str, client_job_id: str, install_id: str, url: str,
                         platform: str, canonical_id: str | None, state: str) -> tuple[str, bool]:
        """Idempotent on client_job_id. Returns (job_id, created). A repeat
        submission must NOT re-run the job - the caller returns the existing id."""
        async with self.db.execute("SELECT id FROM jobs WHERE client_job_id=?", (client_job_id,)) as c:
            row = await c.fetchone()
        if row:
            return row[0], False
        await self.db.execute(
            "INSERT INTO jobs(id,client_job_id,install_id,url,platform,canonical_id,state,created) "
            "VALUES(?,?,?,?,?,?,?,?)",
            (job_id, client_job_id, install_id, url, platform, canonical_id, state, time.time()))
        await self.db.commit()
        return job_id, True

    async def set_state(self, job_id: str, state: str):
        await self.db.execute("UPDATE jobs SET state=? WHERE id=?", (state, job_id))
        await self.db.commit()

    async def get_job(self, job_id: str) -> dict | None:
        async with self.db.execute(
            "SELECT id,client_job_id,url,platform,canonical_id,state,created FROM jobs WHERE id=?", (job_id,)) as c:
            row = await c.fetchone()
        if not row:
            return None
        return dict(zip(("id", "clientJobID", "url", "platform", "canonicalID", "state", "created"), row))

    async def append_event(self, job_id: str, type_: str, payload: dict) -> int:
        async with self.db.execute("SELECT COALESCE(MAX(seq),0)+1 FROM events WHERE job_id=?", (job_id,)) as c:
            seq = (await c.fetchone())[0]
        await self.db.execute("INSERT INTO events(job_id,seq,type,json,created) VALUES(?,?,?,?,?)",
                              (job_id, seq, type_, json.dumps(payload), time.time()))
        await self.db.commit()
        return seq

    async def events_after(self, job_id: str, seq: int) -> list[tuple[int, str, dict]]:
        async with self.db.execute(
            "SELECT seq,type,json FROM events WHERE job_id=? AND seq>? ORDER BY seq", (job_id, seq)) as c:
            rows = await c.fetchall()
        return [(r[0], r[1], json.loads(r[2])) for r in rows]

    # -- rate limit -----------------------------------------------------------

    async def bump_install(self, install_id: str, day: str) -> int:
        await self.db.execute(
            "INSERT INTO installs(install_id,day,count) VALUES(?,?,1) "
            "ON CONFLICT(install_id,day) DO UPDATE SET count=count+1", (install_id, day))
        await self.db.commit()
        async with self.db.execute("SELECT count FROM installs WHERE install_id=? AND day=?", (install_id, day)) as c:
            return (await c.fetchone())[0]

    async def sweep(self):
        now = time.time()
        await self.db.execute("DELETE FROM results WHERE created<?", (now - RESULT_TTL,))
        await self.db.execute("DELETE FROM negative WHERE until<?", (now,))
        await self.db.execute("DELETE FROM events WHERE created<?", (now - EVENT_TTL,))
        await self.db.commit()
