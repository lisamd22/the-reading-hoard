# Share-sheet payload matrix — SETTLED 2026-09-01

All four platforms probed on a physical iPhone. Every cell below is `[OBSERVED]`.

| Platform | Attachments | Registered types | Value | Media bytes? |
|---|---|---|---|---|
| **Instagram** | 1 | `public.url` | `https://www.instagram.com/reel/<code>/?igsi=<token>` | **No** |
| **TikTok** | 1 | `public.url` | `https://vm.tiktok.com/<slug>/` | **No** |
| **Pinterest** | **2** | `public.plain-text`, `public.url` | `" Take a look! 📌 "` (junk) + `https://pin.it/<slug>` | **No** |
| **YouTube** | 1 | **`public.plain-text` only** | bare URL, **no title** | **No** |
| **Photos** (screenshot preview) | 1 | **`public.png`** (not `public.image`) | file, 2.88 MB, `suggestedName` set | **Yes** |
| **Photos** (library grid) | 1 | **`public.png`** | file, 2.49 MB, **`suggestedName` nil**, `IMG_5204.PNG` | **Yes** |

## The four conclusions that drive the code

### 1. No platform hands over media. Confirmed on all four.
The braise ADR-001 finding is validated. Pixels come only from Photos — the platform's own
save button, or a screenshot. **The OCR path is the primary extractor, not a fallback.**

### 2. The activation rule MUST declare BOTH URL and Text.
YouTube registers **only** `public.plain-text` — no `public.url` at all. An extension
declaring only `NSExtensionActivationSupportsWebURLWithMaxCount` **would never appear in
YouTube's share sheet.** Both keys are mandatory:

```xml
<key>NSExtensionActivationSupportsWebURLWithMaxCount</key><integer>1</integer>
<key>NSExtensionActivationSupportsText</key><true/>
<key>NSExtensionActivationSupportsImageWithMaxCount</key><integer>1</integer>
<key>NSExtensionActivationSupportsMovieWithMaxCount</key><integer>1</integer>
```
(`NSExtensionActivationSupportsText` is Boolean — there is no `...WithMaxCount` variant.
That identifier was fabricated in early drafts and does not exist.)

### 3. Scan EVERY attachment, and run NSDataDetector over any plain text.
Pinterest sends two attachments with the useful one **second**. YouTube's URL exists *only*
inside a `public.plain-text` item. Reader order:

```
for each attachment:
    public.url         -> take it
    public.plain-text  -> NSDataDetector(.link) to extract a URL; ignore if none
    public.image       -> pixel path
    public.movie       -> pixel path
```
Never assume `attachments[0]`. Never assume a URL arrives as a URL.

### 3b. Match image/movie types by CONFORMANCE, never by string equality.
A screenshot registers the concrete type **`public.png`** — the literal string
`"public.image"` never appears in `registeredTypeIdentifiers`. Camera photos will be
`public.jpeg` or `public.heic`, videos `public.mpeg-4`. Code like
`registeredTypeIdentifiers.contains("public.image")` **silently fails on every real file.**

```swift
guard let ut = UTType(typeIdentifier) else { return }
if ut.conforms(to: .image) { /* pixel path */ }
if ut.conforms(to: .movie) { /* pixel path */ }
```
(The *activation rule* is fine either way — `NSExtensionActivationSupportsImageWithMaxCount`
matches on conformance. It is the reader that breaks.)

`openInPlace-capable` was **empty**, so the file must be copied into the App Group container
**inside** the completion handler — `NSItemProvider.h` deletes it when the handler returns.
At ~2.5–2.9 MB for one screenshot, always `loadFileRepresentation` + copy; never
`loadDataRepresentation`.

**`suggestedName` is unreliable.** The same screenshot shared from the screenshot *preview*
carries `Screenshot 2026-09-01 at 13.09.13.png`; shared from the Photos *library grid* it is
**nil** and the file is `IMG_5204.PNG`. Never depend on it — fall back to the file URL's
`lastPathComponent`, then to a generated name. (Photos also re-encodes: 2.88 MB vs 2.49 MB
for the same picture. Harmless for OCR, but we are not getting the byte-identical original.)

### 4. Allowlist query params. Do NOT denylist them.
Every observed tracking param differed from what desk research predicted:

| Platform | Predicted | **Observed** |
|---|---|---|
| Instagram | `igsh` / `igshid` | **`igsi`** |
| YouTube | `si` | **`is`** |

A denylist would have leaked both. Canonicalization must **keep only** the params we need
(`v`, `t` on YouTube) and drop everything else.

## Refuted predictions

- ❌ **"Instagram also vends `public.plain-text`."** Three source-code comments claimed it.
  Instagram registers `public.url` only.
- ❌ **"YouTube sends `Title\nhttps://…`."** Graded `[OBSERVED]` from braise ADR-001. The
  Short sent the **bare URL with no title**. YouTube gives us nothing free — title and
  description both require the Data API.
- ❌ **"Pinterest may hand over `public.image`."** It does not. Its plain-text is share
  boilerplate, not the pin description.
- ❌ **"`public.plain-text` carries the URL as a string."** True for YouTube, false for
  Pinterest (junk), absent for Instagram/TikTok.

## Per-platform reality after probing

| Platform | Free text available? | Path |
|---|---|---|
| **TikTok /video/** | ✅ Full caption + hashtags via oEmbed (after resolving the short link) | Strong |
| **TikTok /photo/** | ❌ oEmbed 400s on carousels | **Screenshot only** |
| **YouTube** | ⚠️ Nothing from the share; Data API gives title + description | Strong via API |
| **Pinterest** | ❌ oEmbed `title` is blank; only a thumbnail hash | Screenshot preferred (8× faster) |
| **Instagram** | ❌ Nothing at all | **Screenshot only** |

## The screenshot path is confirmed and is the universal fallback

Photos is the **only** source in the entire matrix that hands over pixels. It works for every
platform, on private accounts, when a creator disabled downloads, and on TikTok carousels
and Pinterest pins where no metadata path exists at all. Three of the five content types
above route through it as their *primary* path, not their fallback.
