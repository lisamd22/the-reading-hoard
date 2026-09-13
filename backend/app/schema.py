"""Response schema. Only keywords Gemini accepts - measured 2026-09-13 against
gemini-3.5-flash-lite: `minItems`/`maxItems` are REJECTED (400), union types like
["string","null"] are fine. Cardinality is enforced by the grounding gate instead.
`books` is first so the incremental parser can emit a card the moment each one
closes, before the summary is generated."""

MODALITIES = ["spoken", "on_screen_text", "cover_visible", "caption", "comment"]

RESPONSE_SCHEMA = {
    "type": "object",
    "required": ["books", "summary", "language"],
    "properties": {
        "books": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["title_verbatim", "author_verbatim", "evidence",
                             "confidence", "is_recommended", "legibility_note"],
                "properties": {
                    "title_verbatim": {"type": "string"},
                    "author_verbatim": {"type": ["string", "null"]},
                    "series_or_edition_verbatim": {"type": ["string", "null"]},
                    "evidence": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "required": ["timestamp", "modality", "quote"],
                            "properties": {
                                "timestamp": {"type": "string", "description": "MM:SS"},
                                "modality": {"type": "string", "enum": MODALITIES},
                                "quote": {"type": "string"},
                            },
                        },
                    },
                    "confidence": {"type": "string", "enum": ["high", "medium", "low"]},
                    "is_recommended": {"type": "boolean"},
                    "legibility_note": {"type": ["string", "null"]},
                },
            },
        },
        "summary": {"type": "string", "description": "One sentence under 200 characters."},
        "language": {"type": "string", "description": "BCP-47"},
    },
}
