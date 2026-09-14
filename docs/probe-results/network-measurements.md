# Live endpoint measurements — 2026-09-01

Run from a Mac on wired/WiFi. Phone-on-cellular will be slower; these are floors.

## Short-link resolution (mandatory, on the critical path)

| Chain | Hops | Time | Result |
|---|---|---|---|
| `vm.tiktok.com/ZGdxo8VFD/` | 1 (301) | **0.32s** | `www.tiktok.com/@liv.book14/photo/7456017302081899808?_r=1&_t=...` |
| `pin.it/33Ms191Jr` | **3** (308 → 302 → 200) | **1.87s** | `de.pinterest.com/pin/698058011040681151/sent/?invite_code=...` |

- **`pin.it` is the single slowest step in the product** — 1.87s before any useful call.
  The plan budgeted 300–800ms for link resolution. Pinterest blows that by 2–6x.
- The Pinterest chain passes through `api.pinterest.com/url_shortener/<slug>/redirect/`
  and lands on a **locale host** (`de.pinterest.com`) with a `/sent/?invite_code=` suffix.
  Host-suffix matching handles the locale host; `^/pin/\d+` matches the `/sent/` path.

## TikTok oEmbed

| Input | HTTP | Notes |
|---|---|---|
| `vm.tiktok.com/...` (short) | **400** | Short links are rejected. Resolve first — not optional. |
| `.../@user/photo/<id>` | **400** | ⚠️ **Photo/slideshow posts are NOT supported by oEmbed.** |
| `.../@user/video/<id>` | **200** | Full caption **with hashtags**, `author_name`, `author_url`. |

Confirmed 200 payload shape:
`title` = `"Scramble up ur name & I'll try to guess it😍❤️ #foryoupage #petsoftiktok #aesthetic"`

**⚠️ New gap:** TikTok photo carousels have **no metadata path at all** — oEmbed 400s and
there are no pixels from the share sheet. The very post the developer first tested was a
`/photo/` post, which suggests BookTok uses carousels non-trivially. These fall through to
"screenshot it" like Instagram.

## Pinterest oEmbed

`GET https://www.pinterest.com/oembed.json?url=<canonical pin>` → **200 in 0.47s**

```
title:            " "            <- BLANK. Worse than the "SEO salad" prior research found.
author_name:      "Lisa D."      <- the PINNER, not the book's author. Useless for extraction.
thumbnail_url:    https://i.pinimg.com/236x/fe/8d/41/fe8d41a...jpg
thumbnail_width:  236
```

No `description`, no destination link — confirms the prior finding. **The only extractable
value in the whole response is the thumbnail hash.**

## Pinterest CDN size rewrite

Rewriting the `236x` path segment works, and is fast:

| Variant | HTTP | Bytes | Pixels | Time |
|---|---|---|---|---|
| `236x` | 200 | 18,961 | 236 × 419 | 0.06s |
| `474x` | 200 | 54,154 | 474 × 842 | 0.06s |
| `736x` | 200 | 64,571 | **576 × 1024** | 0.06s |
| `originals` | 200 | 64,571 | 576 × 1024 | 0.28s |

`736x` and `originals` are identical here because the pin's true original is 576×1024.
576×1024 is a workable OCR target for a list graphic; the sanctioned 236px thumbnail is not.

## Consequence: the two Pinterest paths

| Path | Steps | Total |
|---|---|---|
| **Automated** (share the pin) | pin.it resolve 1.87s + oEmbed 0.47s + CDN 0.06s + OCR ~0.2s | **~2.6s** |
| **Screenshot** (share a screenshot) | OCR only | **~0.3s** |

The screenshot path is roughly **8× faster**, needs no network at all, has no ToS
question, and gives full screen resolution instead of a 576px CDN copy.
