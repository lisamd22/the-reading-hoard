from app.canonical import Platform, canonicalise, detect, is_allowed_host


def test_observed_share_payloads_canonicalise():
    c = canonicalise("https://www.instagram.com/reel/DbOYmimJhWZ/?igsi=c2Fyd2ZpMnJ1amkx")
    assert (c.platform, c.item_id, c.url) == (Platform.INSTAGRAM, "DbOYmimJhWZ", "https://www.instagram.com/reel/DbOYmimJhWZ/")

    c = canonicalise("https://www.tiktok.com/@liv.book14/photo/7456017302081899808?_r=1&_t=ZG-99")
    assert (c.platform, c.item_id, c.kind, c.creator) == (Platform.TIKTOK, "7456017302081899808", "photo", "liv.book14")

    c = canonicalise("https://youtube.com/shorts/4-vP5OCmqWA?is=YN292DCMWt5J-RW7")
    assert c.url == "https://www.youtube.com/watch?v=4-vP5OCmqWA"

    c = canonicalise("https://de.pinterest.com/pin/698058011040681151/sent/?invite_code=e6df&sender=1")
    assert (c.platform, c.item_id, c.url) == (Platform.PINTEREST, "698058011040681151", "https://www.pinterest.com/pin/698058011040681151/")


def test_youtube_keeps_t_drops_tracking():
    c = canonicalise("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42&si=abc&feature=share")
    assert c.url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42"


def test_allowlist_is_suffix_matched_and_rejects_lookalikes():
    assert detect("vm.tiktok.com") is Platform.TIKTOK
    assert detect("m.youtube.com") is Platform.YOUTUBE
    assert detect("www.pinterest.de") is Platform.PINTEREST     # measured redirect target
    assert detect("de.pinterest.com") is Platform.PINTEREST
    assert detect("pinterest.co.uk") is Platform.PINTEREST
    assert detect("pinterest.com.evil.io") is Platform.UNKNOWN
    assert detect("notpinterest.com") is Platform.UNKNOWN
    assert not is_allowed_host("example.com")
