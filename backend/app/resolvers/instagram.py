"""Instagram: managed resolver primary, public page caption as the floor.

Instagram has no official path to another creator's reel: tokenless oEmbed returns
400 "Media Not Found" (measured), and the reel page loads video via JS/GraphQL.
Verified 2026-09-13: a plain GET of /reel/{code}/ returns 200 with NO login wall
and the full caption in og:description (from a residential IP - datacenter is
VERIFY FIRST E4). That caption is the floor; ScrapeCreators is the primary for the
video itself.
"""
from __future__ import annotations

import html
import os
import re

import httpx

from app.canonical import Canonical
from app.resolvers.base import IPHONE_UA, MAX_MEDIA_BYTES, Media, MediaKind, ResolveError

_OG_DESC = re.compile(r'property="og:description" content="([^"]*)"')
_LOGIN = re.compile(r"/accounts/login")
# og:description looks like: `4,337 likes, 37 comments - handle on July 25, 2026: "caption"`
_OG_SHAPE = re.compile(r'^(?:[\d,.]+[KM]? likes?, )?(?:[\d,.]+[KM]? comments? - )?(?P<handle>[\w.]+) on [^:]+: [“"](?P<caption>.*)[”"]\.?\s*$', re.S)


def _parse_og(desc: str) -> tuple[str, str | None]:
    text = html.unescape(desc).strip()
    m = _OG_SHAPE.match(text)
    if m:
        return m.group("caption").strip(), m.group("handle")
    return text, None


class InstagramPageResolver:
    """Caption-only floor. Never returns video."""
    name = "instagram.page"

    def __init__(self, client: httpx.AsyncClient):
        self.client = client

    async def resolve(self, canonical: Canonical) -> Media:
        r = await self.client.get(
            canonical.url, headers={"User-Agent": IPHONE_UA, "Accept-Language": "en-US,en;q=0.9"},
            follow_redirects=True,
        )
        if r.status_code == 404:
            raise ResolveError("removed", "reel 404")
        if r.status_code != 200:
            raise ResolveError("instagram_page_status", f"HTTP {r.status_code}", retryable=r.status_code >= 500)
        if _LOGIN.search(str(r.url)):
            raise ResolveError("instagram_login_wall", "redirected to login", retryable=True)
        m = _OG_DESC.search(r.text)
        if not m:
            raise ResolveError("instagram_no_caption", "no og:description", retryable=True)
        caption, handle = _parse_og(m.group(1))
        return Media(
            canonical=canonical, kind=MediaKind.TEXT_ONLY, caption=caption,
            creator=handle or canonical.creator, resolver=self.name, degraded=True,
        )


class ScrapeCreatorsInstagramResolver:
    """Primary. Docs (verified): GET /v1/instagram/post?url=...&trim=true returns
    `video_url`, `is_video`, `video_duration`, caption under
    `edge_media_to_caption`, carousel under `edge_sidecar_to_children`, and the
    creator's own comments under `edge_media_to_parent_comment`."""
    name = "instagram.scrapecreators"
    base = "https://api.scrapecreators.com"

    def __init__(self, client: httpx.AsyncClient, api_key: str | None = None):
        self.client = client
        self.api_key = api_key or os.environ.get("SCRAPECREATORS_API_KEY", "")

    async def resolve(self, canonical: Canonical) -> Media:
        if not self.api_key:
            raise ResolveError("vendor_unconfigured", "SCRAPECREATORS_API_KEY not set")
        r = await self.client.get(
            f"{self.base}/v1/instagram/post",
            params={"url": canonical.url, "trim": "true"},
            headers={"x-api-key": self.api_key},
            timeout=25,
        )
        if r.status_code == 404:
            raise ResolveError("removed", "vendor 404")
        if r.status_code in (401, 403):
            raise ResolveError("vendor_auth", f"HTTP {r.status_code}")
        if r.status_code == 429:
            raise ResolveError("vendor_rate_limited", "429", retryable=True)
        if r.status_code != 200:
            raise ResolveError("vendor_status", f"HTTP {r.status_code}", retryable=r.status_code >= 500)

        d = r.json()
        # Measured shape: {success, credits_remaining, credits_charged, xdt_shortcode_media}
        post = d.get("xdt_shortcode_media") or (d.get("data") or {}).get("xdt_shortcode_media") or {}
        if not post or not post.get("shortcode"):
            raise ResolveError("vendor_empty", "no post in response", retryable=True)

        caption = ""
        edges = (post.get("edge_media_to_caption") or {}).get("edges") or []
        if edges:
            caption = (edges[0].get("node") or {}).get("text") or ""
        creator = (post.get("owner") or {}).get("username") or canonical.creator
        comments = [
            ((e.get("node") or {}).get("text") or "")
            for e in ((post.get("edge_media_to_parent_comment") or {}).get("edges") or [])
            if ((e.get("node") or {}).get("owner") or {}).get("username") == creator
        ]
        comments = [c for c in comments if c]

        if post.get("is_video") and post.get("video_url"):
            vr = await self.client.get(post["video_url"], headers={"User-Agent": IPHONE_UA}, follow_redirects=True)
            if vr.status_code == 200 and vr.content and len(vr.content) <= MAX_MEDIA_BYTES:
                return Media(
                    canonical=canonical, kind=MediaKind.VIDEO, caption=caption, creator=creator,
                    comments=comments, duration_seconds=post.get("video_duration"),
                    video_bytes=vr.content, video_mime="video/mp4", resolver=self.name,
                )
            raise ResolveError("instagram_cdn_fetch", f"HTTP {vr.status_code} on video_url", retryable=True)

        # Carousel or single image.
        urls: list[str] = []
        children = (post.get("edge_sidecar_to_children") or {}).get("edges") or []
        for e in children:
            n = e.get("node") or {}
            u = n.get("video_url") if n.get("is_video") else n.get("display_url")
            if u:
                urls.append(u)
        if not urls and post.get("display_url"):
            urls.append(post["display_url"])
        images: list[bytes] = []
        for u in urls[:12]:
            ir = await self.client.get(u, headers={"User-Agent": IPHONE_UA}, follow_redirects=True)
            if ir.status_code == 200 and ir.content:
                images.append(ir.content)
        if images:
            return Media(
                canonical=canonical, kind=MediaKind.IMAGES, caption=caption, creator=creator,
                comments=comments, image_bytes=images, image_mime="image/jpeg", resolver=self.name,
            )
        if caption:
            return Media(canonical=canonical, kind=MediaKind.TEXT_ONLY, caption=caption,
                         creator=creator, comments=comments, resolver=self.name, degraded=True)
        raise ResolveError("instagram_no_media", "vendor returned no media or caption")
