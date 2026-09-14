"""User-facing strings, in the library's calm voice. No exclamation marks."""

FAILED = {
    "private": "This post is private. The library can only read what the creator shares with everyone.",
    "removed": "That link leads nowhere now. The post may have been removed.",
    "too_long": "Videos longer than an hour are more than the library can watch.",
    "too_large": "That video is larger than the library can hold at once.",
    "unsupported": "The library doesn't recognise that link. It reads Instagram, TikTok, YouTube and Pinterest.",
    "budget": "The library has read a great deal today. It will pick this up tomorrow.",
    "timeout": "This is taking longer than it should. The library will keep at it and tell you.",
    "model_failed": "The library couldn't read this one today.",
    "all_failed": "The library could not reach this post. A screenshot of the list will do.",
}

PLATFORM_BLOCKED = {
    "instagram": "Instagram is holding the film back right now.",
    "tiktok": "TikTok is holding the video back right now.",
    "youtube": "YouTube is holding the video back right now.",
    "pinterest": "Pinterest is holding the pin back right now.",
}

STAGE = {
    "accepted": "The library has the link.",
    "media.fetching": {
        "instagram": "Fetching the reel.",
        "tiktok": "Fetching the video.",
        "youtube": "Fetching the video.",
        "pinterest": "Fetching the pin.",
    },
    "media.reading": "Watching, and listening.",
    "cached": "The library has read this one before.",
}


def failed_message(code: str, platform: str | None = None, has_caption_books: bool = False) -> str:
    if code in FAILED:
        return FAILED[code]
    blocked = PLATFORM_BLOCKED.get(platform or "", "The platform is holding this one back right now.")
    if has_caption_books:
        return f"{blocked} These are the books the caption names."
    return f"{blocked} The library has kept the link and will try again."
