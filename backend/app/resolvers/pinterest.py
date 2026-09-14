"""Pinterest: the public pin page carries the media URLs.

Verified 2026-09-13: a plain GET of pinterest.com/pin/{id}/ returns 200 (1.1 MB)
with a direct MP4 at v1.pinimg.com/videos/.../expMp4/..._t4.mp4 (1.6 MB, 19 s,
1.2 s fetch, no auth) for video pins, and i.pinimg.com/{size}/... for image pins.
oEmbed is useless here - its `title` is literally blank.
"""
from __future__ import annotations

import html
import json
import re

import httpx

from app.canonical import Canonical
from app.resolvers.base import IPHONE_UA, MAX_MEDIA_BYTES, Media, MediaKind, ResolveError

_MP4 = re.compile(r'https://v1\.pinimg\.com/videos/[^"\\\s]+?\.mp4')
_IMG_736 = re.compile(r'https://i\.pinimg\.com/736x/[^"\\\s]+?\.(?:jpg|jpeg|png|webp)')
_IMG_ANY = re.compile(r'https://i\.pinimg\.com/(?:originals|1200x|736x|564x|474x)/[^"\\\s]+?\.(?:jpg|jpeg|png|webp)')
_LDJSON = re.compile(r'<script type="application/ld\+json">(.*?)</script>', re.S)
_OG_DESC = re.compile(r'property="og:description" content="([^"]*)"')
_OG_TITLE = re.compile(r'property="og:title" content="([^"]*)"')


class PinterestPageResolver:
    name = "pinterest.page"

    def __init__(self, client: httpx.AsyncClient):
        self.client = client

    async def resolve(self, canonical: Canonical) -> Media:
        r = await self.client.get(
            canonical.url, headers={"User-Agent": IPHONE_UA}, follow_redirects=True,
        )
        if r.status_code == 404:
            raise ResolveError("removed", "pin 404")
        if r.status_code != 200:
            raise ResolveError("pinterest_page_status", f"HTTP {r.status_code}", retryable=r.status_code >= 500)
        page = r.text

        caption = ""
        for m in _LDJSON.finditer(page):
            try:
                d = json.loads(m.group(1))
                caption = d.get("articleBody") or d.get("description") or d.get("headline") or caption
                if caption:
                    break
            except json.JSONDecodeError:
                continue
        if not caption:
            m = _OG_DESC.search(page) or _OG_TITLE.search(page)
            caption = html.unescape(m.group(1)) if m else ""

        mp4s = _MP4.findall(page)
        if mp4s:
            # Prefer the smallest rendition that still reads. Pinterest names them
            # _t1.._t4; higher is larger. Take the last unique one (largest available)
            # and cap by size - a 19 s pin was 1.6 MB, well inside the inline limit.
            url = sorted(set(mp4s))[-1]
            vr = await self.client.get(url, headers={"User-Agent": IPHONE_UA})
            if vr.status_code == 200 and vr.content and len(vr.content) <= MAX_MEDIA_BYTES:
                return Media(
                    canonical=canonical, kind=MediaKind.VIDEO, caption=caption,
                    video_bytes=vr.content, video_mime="video/mp4", resolver=self.name,
                )

        img = _IMG_736.search(page) or _IMG_ANY.search(page)
        if img:
            url = img.group(0)
            ir = await self.client.get(url, headers={"User-Agent": IPHONE_UA})
            if ir.status_code == 200 and ir.content:
                mime = "image/png" if url.endswith(".png") else "image/webp" if url.endswith(".webp") else "image/jpeg"
                return Media(
                    canonical=canonical, kind=MediaKind.IMAGES, caption=caption,
                    image_bytes=[ir.content], image_mime=mime, resolver=self.name,
                )

        if caption:
            return Media(canonical=canonical, kind=MediaKind.TEXT_ONLY, caption=caption,
                         resolver=self.name, degraded=True)
        raise ResolveError("pinterest_no_media", "no mp4, image, or caption on page", retryable=True)
