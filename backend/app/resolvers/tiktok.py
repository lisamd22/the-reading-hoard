"""TikTok: the platform's own mobile page hands over everything.

Verified 2026-09-13 against a real shared link: with an iPhone Safari UA the page
embeds `__UNIVERSAL_DATA_FOR_REHYDRATION__` -> `__DEFAULT_SCOPE__` ->
`webapp.reflow.video.detail` -> `itemInfo.itemStruct` with `desc`, `author`,
`video.playAddr` or `imagePost.images[]`. A Mac UA returns only a shell page.
Carousel images fetch with no cookie (388 KB, 1440x1920, 0.22 s each).
"""
from __future__ import annotations

import asyncio
import json
import re

import httpx

from app.canonical import Canonical
from app.resolvers.base import IPHONE_UA, MAX_MEDIA_BYTES, Media, MediaKind, ResolveError

_BLOB = re.compile(
    r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">(.*?)</script>',
    re.S,
)

# statusCode values observed / documented in yt-dlp's extractor.
_PRIVATE = {10216, 10222}
_REMOVED = {10204, 10205}


class TikTokPageResolver:
    name = "tiktok.page"

    def __init__(self, client: httpx.AsyncClient):
        self.client = client

    async def resolve(self, canonical: Canonical) -> Media:
        r = await self.client.get(
            canonical.url,
            headers={"User-Agent": IPHONE_UA, "Accept-Language": "en-US,en;q=0.9"},
            follow_redirects=True,
        )
        if r.status_code != 200:
            raise ResolveError("tiktok_page_status", f"HTTP {r.status_code}", retryable=r.status_code >= 500)

        m = _BLOB.search(r.text)
        if not m:
            raise ResolveError("tiktok_no_blob", "page had no rehydration blob (blocked?)", retryable=True)

        scope = json.loads(m.group(1)).get("__DEFAULT_SCOPE__", {})
        detail = scope.get("webapp.reflow.video.detail") or scope.get("webapp.video-detail")
        if not detail:
            raise ResolveError("tiktok_shell", "page was a shell, no video-detail", retryable=True)

        status = int(detail.get("statusCode", -1))
        if status in _PRIVATE:
            raise ResolveError("private", f"statusCode {status}")
        if status in _REMOVED:
            raise ResolveError("removed", f"statusCode {status}")
        if status != 0:
            raise ResolveError("tiktok_status", f"statusCode {status}", retryable=True)

        item = (detail.get("itemInfo") or {}).get("itemStruct") or {}
        caption = item.get("desc") or ""
        creator = (item.get("author") or {}).get("uniqueId") or canonical.creator
        comments = [c.get("text", "") for c in item.get("comments") or [] if c.get("text")]

        cookies = {k: v for k, v in r.cookies.items()}
        cdn_headers = {"User-Agent": IPHONE_UA, "Referer": "https://www.tiktok.com/"}

        image_post = item.get("imagePost")
        if image_post:
            urls = [
                (im.get("imageURL") or {}).get("urlList", [None])[0]
                for im in image_post.get("images", [])
            ]
            urls = [u for u in urls if u]
            if not urls:
                raise ResolveError("tiktok_no_images", "imagePost had no urls")
            # Slides are independent; fetch them concurrently (measured: 3.6 s
            # sequential for ten, ~0.5 s in parallel).
            async def fetch(u: str) -> bytes | None:
                ir = await self.client.get(u, headers=cdn_headers, cookies=cookies)
                return ir.content if ir.status_code == 200 and ir.content else None

            fetched = await asyncio.gather(*(fetch(u) for u in urls[:12]))
            images: list[bytes] = []
            total = 0
            for b in fetched:
                if b is None:
                    continue
                total += len(b)
                if total > MAX_MEDIA_BYTES:
                    break
                images.append(b)
            if not images:
                raise ResolveError("tiktok_images_failed", "no slide fetched", retryable=True)
            return Media(
                canonical=canonical, kind=MediaKind.IMAGES, caption=caption, creator=creator,
                comments=comments, image_bytes=images, image_mime="image/jpeg", resolver=self.name,
            )

        video = item.get("video") or {}
        play = video.get("playAddr") or video.get("downloadAddr")
        if not play:
            raise ResolveError("tiktok_no_play_addr", "itemStruct.video had no playAddr")
        vr = await self.client.get(play, headers=cdn_headers, cookies=cookies, follow_redirects=True)
        if vr.status_code != 200 or not vr.content:
            raise ResolveError("tiktok_video_fetch", f"HTTP {vr.status_code} on playAddr", retryable=True)
        if len(vr.content) > MAX_MEDIA_BYTES:
            raise ResolveError("too_large", f"{len(vr.content)} bytes")

        return Media(
            canonical=canonical, kind=MediaKind.VIDEO, caption=caption, creator=creator,
            comments=comments, duration_seconds=float(video.get("duration") or 0) or None,
            video_bytes=vr.content, video_mime="video/mp4", resolver=self.name,
        )
