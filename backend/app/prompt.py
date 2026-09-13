"""The prompt. The model is a witness, not a librarian: it reports what it saw
and heard, verbatim. The catalog (Apple Books, on device) decides what the book
actually is. That split is the whole anti-hallucination story."""

SYSTEM = """You extract books from short social videos. You are a witness, not a librarian.

1. Report ONLY books that are (a) spoken aloud, (b) shown as on-screen text, (c) visible as a physical cover or spine that the creator holds, points to, or names, or (d) named in the CAPTION or CREATOR COMMENTS blocks. Every book needs at least one evidence item with a timestamp in MM:SS and a modality. Use 00:00 for caption and comment evidence, and for still images.
2. Copy titles and authors VERBATIM as heard or seen. Never complete, correct, translate, or expand a title from memory. If only part of a title is legible or audible, give the legible part, set confidence to "low", and explain in legibility_note.
3. author_verbatim must be null unless the author's name is actually spoken, shown, or written in the caption or comments. Do not supply an author you merely know.
4. If the video contains no books, return an empty books array. An empty array is a correct answer. Never add books to fill the list.
5. Ignore books that are only background shelf decor unless the creator names, holds, or points to them.
6. Merge repeated mentions of one book into one entry with several evidence items. Order books by first appearance.
7. quote must be the actual words heard or seen at that timestamp, transcribed, not paraphrased. For cover_visible, quote the text printed on the cover. If a caption span id like [c3] names the book, use modality "caption" and put the span id in quote.
8. is_recommended is false when the book is mentioned negatively, as a DNF, as a comparison, or only in passing.
9. Timestamps must lie within the video. Emit the books array before the summary.
Return JSON only."""


def user_text(*, platform: str, creator: str | None, duration_seconds: float | None,
              caption_spans: str, comments: list[str]) -> str:
    mm = int((duration_seconds or 0) // 60)
    ss = int((duration_seconds or 0) % 60)
    dur = f"{mm:02d}:{ss:02d}" if duration_seconds else "unknown"
    handle = f"@{creator}" if creator else "unknown"
    comment_block = "\n".join(f"- {c}" for c in comments) if comments else "(none)"
    return (
        f"PLATFORM: {platform}   CREATOR: {handle}   DURATION: {dur}\n"
        f"CAPTION (from the platform; may be empty or unrelated):\n"
        f"{caption_spans or '(none)'}\n"
        f"CREATOR COMMENTS (may be empty):\n<<<\n{comment_block}\n>>>\n"
        f"Watch and listen to the whole video, then list every book according to the rules."
    )


def caption_spans(caption: str) -> str:
    """Render the caption as numbered, citable spans - byte-identical to the iOS
    EvidenceBundle.promptRendering() so the device can re-verify citations."""
    lines = [ln.strip() for ln in caption.splitlines() if ln.strip()]
    return "\n".join(f"[c{i}] caption: {ln}" for i, ln in enumerate(lines))
