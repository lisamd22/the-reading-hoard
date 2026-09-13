"""YouTube: no download at all.

Gemini ingests public YouTube URLs directly as a video part (documented; no charge
for the fetch; public videos only). We use the Data API only for the description
and privacy status - 1 quota unit of 10,000/day. Shorts are normalised to
watch?v= by the canonicaliser because that is the form the Gemini doc shows.
"""
from __future__ import annotations

import os

import httpx

from app.canonical import Canonical
from app.resolvers.base import Media, MediaKind, ResolveError


class YouTubeResolver:
    name = "youtube.dataapi"

    def __init__(self, client: httpx.AsyncClient, api_key: str | None = None):
        self.client = client
        self.api_key = api_key or os.environ.get("YOUTUBE_API_KEY", "")

    async def resolve(self, canonical: Canonical) -> Media:
        if not canonical.item_id:
            raise ResolveError("youtube_no_id", "could not find an 11-char video id")

        caption, creator, duration, degraded = "", canonical.creator, None, False
        if self.api_key:
            r = await self.client.get(
                "https://www.googleapis.com/youtube/v3/videos",
                params={"part": "snippet,contentDetails,status", "id": canonical.item_id, "key": self.api_key},
                timeout=10,
            )
            if r.status_code == 200:
                items = r.json().get("items") or []
                if not items:
                    raise ResolveError("removed", "videos.list returned no items")
                v = items[0]
                if (v.get("status") or {}).get("privacyStatus") not in (None, "public", "unlisted"):
                    raise ResolveError("private", v["status"]["privacyStatus"])
                sn = v.get("snippet") or {}
                caption = "\n".join(x for x in (sn.get("title"), sn.get("description")) if x)
                creator = sn.get("channelTitle") or creator
                duration = _iso8601_seconds((v.get("contentDetails") or {}).get("duration"))
            elif r.status_code == 403:
                degraded = True  # quota - still let Gemini watch it
            else:
                degraded = True
        else:
            degraded = True

        if duration and duration > 60 * 60:
            raise ResolveError("too_long", f"{duration:.0f}s")

        return Media(
            canonical=canonical, kind=MediaKind.REMOTE_VIDEO_URI, caption=caption, creator=creator,
            duration_seconds=duration, remote_uri=canonical.url, resolver=self.name, degraded=degraded,
        )


def _iso8601_seconds(s: str | None) -> float | None:
    """PT1H2M3S -> seconds."""
    if not s or not s.startswith("PT"):
        return None
    total, num = 0.0, ""
    for ch in s[2:]:
        if ch.isdigit() or ch == ".":
            num += ch
        else:
            if num:
                total += float(num) * {"H": 3600, "M": 60, "S": 1}.get(ch, 0)
            num = ""
    return total or None
