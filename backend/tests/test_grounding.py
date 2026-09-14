from app.grounding import ground


def _b(title, quote, ts="00:04", modality="spoken", author=None, conf="high", note=None):
    return {"title_verbatim": title, "author_verbatim": author, "confidence": conf,
            "is_recommended": True, "legibility_note": note,
            "evidence": [{"timestamp": ts, "modality": modality, "quote": quote}]}


def test_grounded_book_is_kept():
    kept, dropped = ground([_b("Fourth Wing", "the first one is fourth wing by rebecca yarros")],
                           duration_seconds=30, caption_spans={})
    assert [b["title_verbatim"] for b in kept] == ["Fourth Wing"] and not dropped


def test_quote_without_title_tokens_is_dropped():
    kept, dropped = ground([_b("A Court of Mist and Fury", "this one was okay I guess")],
                           duration_seconds=30, caption_spans={})
    assert not kept and dropped[0].reason.startswith("ungrounded")


def test_timestamp_outside_video_is_dropped():
    kept, dropped = ground([_b("Quicksilver", "quicksilver", ts="09:59")], duration_seconds=30, caption_spans={})
    assert not kept and dropped[0].reason == "no_valid_evidence"


def test_caption_span_id_resolves_to_real_text():
    kept, _ = ground([_b("Powerless", "[c0]", ts="00:00", modality="caption")],
                     duration_seconds=30, caption_spans={"[c0]": "powerless by lauren roberts is my fav"})
    assert kept and kept[0]["evidence"][0]["quote"].startswith("powerless")


def test_one_edit_ocr_damage_still_grounds():
    kept, _ = ground([_b("Quicksilver", "QUICKSIIVER", modality="on_screen_text")],
                     duration_seconds=30, caption_spans={})
    assert kept


def test_low_confidence_with_note_survives_partial_legibility():
    kept, _ = ground([_b("Iron Fl", "iron", conf="low", note="title card cut off")],
                     duration_seconds=30, caption_spans={})
    assert kept


def test_empty_author_becomes_none():
    kept, _ = ground([_b("Fourth Wing", "fourth wing", author="   ")], duration_seconds=30, caption_spans={})
    assert kept[0]["author_verbatim"] is None


def test_duplicates_collapse():
    kept, _ = ground([_b("Fourth Wing", "fourth wing"), _b("fourth wing", "fourth wing", ts="00:20")],
                     duration_seconds=30, caption_spans={})
    assert len(kept) == 1


def test_seen_set_dedupes_across_streamed_calls():
    seen = set()
    k1, _ = ground([_b("Heartbreak for Hire", "Heartbreak for Hire", ts="00:25")], duration_seconds=40, caption_spans={}, seen=seen)
    k2, _ = ground([_b("Heartbreak for Hire", "Heartbreak for Hire SONIA HARTL", ts="00:30")], duration_seconds=40, caption_spans={}, seen=seen)
    assert len(k1) == 1 and len(k2) == 0


def test_character_weighted_coverage_keeps_les_miserables():
    kept, _ = ground([_b("Les Misérables", "MISÉRABLES", modality="cover_visible")], duration_seconds=40, caption_spans={})
    assert kept
