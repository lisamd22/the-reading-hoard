import json

from app.gemini import _IncrementalBooks

DOC = {"books": [
    {"title_verbatim": "Fourth Wing", "evidence": [{"quote": "with a } brace and \"quotes\""}]},
    {"title_verbatim": "Onyx Storm", "evidence": []},
], "summary": "two"}


def test_books_emitted_regardless_of_chunking():
    text = json.dumps(DOC)
    for n in (1, 3, 7, 50, len(text)):
        p = _IncrementalBooks()
        got = []
        for i in range(0, len(text), n):
            got += p.feed(text[i:i + n])
        assert [b["title_verbatim"] for b in got] == ["Fourth Wing", "Onyx Storm"], f"chunk={n}"


def test_summary_after_books_is_ignored():
    p = _IncrementalBooks()
    got = p.feed(json.dumps({"books": [{"title_verbatim": "X", "evidence": []}], "summary": "{not a book}"}))
    assert len(got) == 1


def test_shift_offsets_timestamps_into_whole_video_time():
    from app.gemini import _shift
    b = _shift({"title_verbatim": "X", "evidence": [{"timestamp": "00:15", "modality": "spoken", "quote": "x"}]}, 69.6)
    assert b["evidence"][0]["timestamp"] == "01:25"
    assert _shift({"evidence": [{"timestamp": "00:15"}]}, 0)["evidence"][0]["timestamp"] == "00:15"
