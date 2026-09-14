"""URL classification and canonicalisation.

Every rule here comes from a measured share-sheet payload (see
TheReadingHoardProbe/results/). Query params are ALLOWLISTED, never denylisted:
both observed tracking params (Instagram `igsi`, YouTube `is`) differed from what
desk research predicted, so a denylist would have leaked both.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

import httpx


class Platform(str, Enum):
    INSTAGRAM = "instagram"
    TIKTOK = "tiktok"
    YOUTUBE = "youtube"
    PINTEREST = "pinterest"
    UNKNOWN = "unknown"


# Host allow-list. Suffix-matched so www/m/vm/vt and every localised host
# (de.pinterest.com, m.youtube.com) pass without a code change. Nothing outside
# this list is ever fetched: the backend is not a generic downloader.
_HOSTS: dict[Platform, tuple[str, ...]] = {
    Platform.INSTAGRAM: ("instagram.com", "instagr.am"),
    Platform.TIKTOK: ("tiktok.com",),
    Platform.YOUTUBE: ("youtube.com", "youtu.be", "youtube-nocookie.com"),
    Platform.PINTEREST: ("pinterest.com", "pin.it"),
}

# Pinterest uses BOTH {cc}.pinterest.com AND pinterest.{cc} - measured: pin.it
# 302'd to www.pinterest.de. Match the ccTLD family explicitly.
_PINTEREST_CCTLD = re.compile(r"^(?:[a-z0-9-]+\.)*pinterest\.[a-z]{2,3}(?:\.[a-z]{2})?$")

_SHORT_HOSTS = {"vm.tiktok.com", "vt.tiktok.com", "pin.it", "youtu.be"}

_KEEP_QUERY: dict[Platform, frozenset[str]] = {
    Platform.YOUTUBE: frozenset({"v", "t"}),
}

_IPHONE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
)


def detect(host: str | None) -> Platform:
    if not host:
        return Platform.UNKNOWN
    h = host.lower()
    for platform, domains in _HOSTS.items():
        if any(h == d or h.endswith("." + d) for d in domains):
            return platform
    if _PINTEREST_CCTLD.match(h):
        return Platform.PINTEREST
    return Platform.UNKNOWN


def is_allowed_host(host: str | None) -> bool:
    return detect(host) is not Platform.UNKNOWN


@dataclass(frozen=True)
class Canonical:
    platform: Platform
    url: str
    """Stable per-post id: TikTok numeric id, IG shortcode, YT 11-char id, pin id."""
    item_id: str | None
    """TikTok only: 'video' or 'photo'. Carousels have no metadata path."""
    kind: str | None = None
    creator: str | None = None


_TT_VIDEO = re.compile(r"/@([^/]+)/(video|photo)/(\d+)")
_IG_POST = re.compile(r"/(?:reel|reels|p|tv)/([A-Za-z0-9_-]+)")
_YT_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_PIN_ID = re.compile(r"/pin/(\d+)")


def canonicalise(url: str) -> Canonical:
    """Pure. Never touches the network. Call `resolve_short_link` first for
    vm./vt./pin.it/youtu.be links."""
    p = urlparse(url.strip())
    platform = detect(p.hostname)
    host = (p.hostname or "").lower()
    path = p.path or "/"

    if platform is Platform.TIKTOK:
        m = _TT_VIDEO.search(path)
        if m:
            creator, kind, vid = m.groups()
            return Canonical(platform, f"https://www.tiktok.com/@{creator}/{kind}/{vid}", vid, kind, creator)
        return Canonical(platform, _strip(p, platform), None)

    if platform is Platform.INSTAGRAM:
        m = _IG_POST.search(path)
        if m:
            code = m.group(1)
            return Canonical(platform, f"https://www.instagram.com/reel/{code}/", code)
        return Canonical(platform, _strip(p, platform), None)

    if platform is Platform.YOUTUBE:
        vid: str | None = None
        if host == "youtu.be":
            vid = path.strip("/").split("/")[0] or None
        elif "/shorts/" in path:
            vid = path.split("/shorts/", 1)[1].split("/")[0] or None
        elif path.startswith("/watch"):
            vid = parse_qs(p.query).get("v", [None])[0]
        if vid and _YT_ID.match(vid):
            # Gemini's YouTube ingestion is documented for watch?v=; normalise Shorts to it.
            t = parse_qs(p.query).get("t", [None])[0]
            q = f"?v={vid}" + (f"&t={t}" if t else "")
            return Canonical(platform, f"https://www.youtube.com/watch{q}", vid)
        return Canonical(platform, _strip(p, platform), None)

    if platform is Platform.PINTEREST:
        m = _PIN_ID.search(path)
        if m:
            pid = m.group(1)
            return Canonical(platform, f"https://www.pinterest.com/pin/{pid}/", pid)
        return Canonical(platform, _strip(p, platform), None)

    return Canonical(Platform.UNKNOWN, url, None)


def _strip(p, platform: Platform) -> str:
    keep = _KEEP_QUERY.get(platform, frozenset())
    q = {k: v for k, v in parse_qs(p.query).items() if k in keep}
    return urlunparse((p.scheme or "https", p.netloc, p.path, "", urlencode(q, doseq=True), ""))


def needs_resolution(url: str) -> bool:
    host = (urlparse(url).hostname or "").lower()
    return host in _SHORT_HOSTS


async def resolve_short_link(url: str, client: httpx.AsyncClient, max_hops: int = 4) -> str:
    """Follow redirects hop by hop, refusing to leave the allow-list.

    Measured: vm.tiktok.com is one 301 (0.32s). pin.it is 308 -> 302 -> 200 (1.87s)
    and lands on a LOCALE host with /sent/?invite_code=. A bad pin.it code 302s to
    the homepage with a 200, so failure is detected by canonicalise() finding no
    item_id - never by status code.
    """
    current = url
    for _ in range(max_hops):
        if not needs_resolution(current) and canonicalise(current).item_id:
            return current
        r = await client.head(current, follow_redirects=False, headers={"User-Agent": _IPHONE_UA})
        loc = r.headers.get("location")
        if not loc or r.status_code not in (301, 302, 303, 307, 308):
            return current
        nxt = httpx.URL(current).join(loc)
        if not is_allowed_host(nxt.host):
            raise ValueError(f"redirect left the allow-list: {nxt.host}")
        current = str(nxt)
    return current
