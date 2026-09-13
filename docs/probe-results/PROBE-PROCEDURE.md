# Share-sheet payload probe (PR-1)

**Throwaway diagnostic target. Never merge to `main`. Never ship.**

It uses `NSExtensionActivationRule = TRUEPREDICATE`, which is an automatic App Store
rejection — the build emits a warning saying exactly that. Maximum permissiveness is the
point: we want to appear in every share sheet so we can see what each app actually sends.

## Why this exists

Every claim about what Instagram, TikTok, YouTube and Pinterest hand to a share extension
is inference. None of the four document it, there are no public vendor UTIs to declare, and
the payload changes between app versions without notice. The only public first-hand artifact
that exists (braise ADR-001) covers three of the four platforms and says:

> "No platform passes a video file, audio file, or caption text to the share extension."

Pinterest is untested by anyone, publicly. This probe settles all of it in one sitting.

## Running it — ~15 minutes

1. **Use a physical iPhone.** None of the four apps can be installed in the Simulator.
   Install all four from the App Store and sign in.
2. In Xcode: **Product ▸ Scheme ▸ TheReadingHoardProbe**, leave the host as
   **"Ask On Launch"**, then Run and pick the host app when prompted. Xcode attaches when
   you invoke the extension from that app's UI.
   - First device build will prompt to register the App Group
     `group.com.lisamd22.TheReadingHoard`. Automatic signing handles it; you must be signed
     into the developer account for team `TRHU3U42X6`.
3. **`print()` is useless here** — the appex is launched by the system, not Xcode, so nothing
   forwards stdout. The probe uses `Logger` with `privacy: .public`. Open **Console.app**,
   select the device, and enable **Action ▸ Include Debug Messages**. Filter on
   subsystem `com.lisamd22.TheReadingHoard`, category `probe`.
4. The report also renders on screen (screenshot it) and is written incrementally to the
   App Group container, so a jetsam kill still leaves a usable dump.

## What to run

For each row, share the item and record every `registeredTypeIdentifiers` line.

| # | App | Action |
|---|-----|--------|
| 1 | Instagram | Reel → paper-plane → Share to… → More |
| 2 | Instagram | Feed post (`/p/`) → same |
| 3 | TikTok | Video → Share → third-party |
| 4 | TikTok | Photo/slideshow post → Share |
| 5 | YouTube | Short → Share → **More (⋯)** |
| 6 | YouTube | Regular video → Share → **More** |
| 7 | **Pinterest** | **Image pin → Share → More apps** ← the highest-value unknown |
| 8 | **Pinterest** | **Video pin → Share** |
| 9 | **Pinterest** | **Board → Share** (if offered at all) |
| 10 | Photos | A saved video → Share |
| 11 | Photos | A screenshot → Share |
| 12 | Safari | Any of the four sites → Share |

## What we are trying to learn

1. **Does any app attach a `public.image` or `public.movie`?** Current evidence says no for
   Instagram/TikTok/YouTube; Pinterest is genuinely unknown. If Pinterest attaches the
   bitmap, its whole path needs zero network calls and zero ToS surface.
2. **Is `public.plain-text` present alongside `public.url`, and does it carry the caption
   or just the URL again?** Three source comments assert the former; zero logged payloads
   confirm it. This is graded `[INFERRED]`, not `[OBSERVED]`.
3. **What exact URL form arrives?** TikTok is expected to send a `vm.`/`vt.` short link with
   **no video ID in the string**. YouTube is expected to send `"Title\nhttps://…"` as text.
4. **Does `attributedContentText` or `userInfo` carry anything useful?** Never dumped publicly.

## Record results here

| App | Action | `registeredTypeIdentifiers` | Loaded value | Media bytes? |
|-----|--------|------------------------------|--------------|--------------|
| Instagram | Reel → Share → More | `public.url` **only** | `https://www.instagram.com/reel/<code>/?igsi=<token>` | **No** |
| Pinterest | Pin → Share → More apps | `public.plain-text` + `public.url` (2 attachments) | `" Take a look! 📌 "` and `https://pin.it/<slug>` | **No** |

### Confirmed 2026-09-01 — Instagram

- **`public.url` is the *only* registered type.** No `public.plain-text`. This **refutes** the
  `[INFERRED]` claim (three source-code comments, zero logged payloads) that Instagram also
  vends the URL as text. Do not write a plain-text branch for Instagram.
- `attributedTitle` and `attributedContentText` are both **nil** — no caption anywhere.
- `openInPlace-capable` is **empty**.
- One attachment, one item. Probe completed in 0.0s (no provider stall).
- **Tracking param is `igsi`, not `igsh`/`igshid`** as prior research assumed. The
  canonicalizer must strip `igsi` — safest is to drop any param matching `^igs` plus `utm_*`.
- Raw dump: [`results/instagram-reel.txt`](results/instagram-reel.txt)

### Confirmed 2026-09-01 — Pinterest  ⚠️ NEGATIVE RESULT

- **No `public.image`.** Pinterest does *not* hand over the bitmap. This kills the
  intended primary path (share → image → OCR, zero network, zero ToS surface) and
  promotes the fallback chain: `pin.it` → resolve → oEmbed → thumbnail hash →
  CDN size-rewrite → fetch → OCR. That chain carries exactly the network surface
  the image path existed to avoid. Flagged in the plan as 🔴 D-1; now settled.
- **Two attachments in one item**, and the useful one is second. The reader must scan
  *all* attachments and must not assume `attachments[0]`.
- **`public.plain-text` is present but worthless** — a 17-char share boilerplate
  `" Take a look! 📌 "`, not the pin title or description. Note this also refutes the
  general claim that plain-text carries the URL as a string: here it carries junk.
- `attributedContentText` is the same boilerplate. No pin metadata anywhere.
- **The URL is a `pin.it` short link**, so redirect resolution is mandatory and on the
  critical path. Detect failure by matching the final URL against `^/pin/\d+` — **never
  by status code**: a bad code 302s to the Pinterest homepage and returns 200.
- Raw dump: [`results/pinterest-pin.txt`](results/pinterest-pin.txt)

## After it runs

Fill in the table, update the payload matrix in the plan, then **delete this target** —
remove the `TheReadingHoardProbe` group, target, and build configs from `project.pbxproj`,
and delete this directory. The real share extension (PR-8) uses a dictionary activation
rule, never a predicate.
