# The Reading Hoard

Share a link from Instagram, TikTok, YouTube or Pinterest and the books in the video land
in your library. Native SwiftUI, iOS 17+, no third-party packages. A small backend
watches the video so the phone never has to.

## What it does

1. **Share or paste a link.** The share extension (`TheReadingHoardShare`) appears in the
   share sheet of all four platforms. It writes the link to the App Group inbox first, posts
   it to the backend with a 2.5 s cap, shows one line and dismisses. Pasting into the
   Import tab does the same without the sheet.
2. **The backend fetches the video and Gemini watches it** — frames and audio in one call —
   and returns every book spoken, shown on screen or held up on a cover, each with a
   timestamp and the verbatim text it was read from. A grounding gate drops anything the
   model cannot point to in the video. Books stream back over SSE as each one closes.
3. **Each book is resolved against Apple Books on device** (author, cover, edition) and saved
   to the library with its source and evidence. Nothing waits for review; the library fills
   as the books arrive.

Every shared link shows its status on the Library and Import tabs — queued, reading,
done, or why it failed, with *Try again*. A link never disappears silently.

Measured on real links: a TikTok carousel gives 15 books in ~10 s, an Instagram reel whose
caption named no books gives all 10 from the video, a YouTube Short 8 in ~4 s.

## Layout

| Path | What |
| --- | --- |
| `TheReadingHoard/` | The app. `Features/Import` (link import, status section), `Features/Library`, `Services/Import` (`HoardAPI` SSE client, `RemoteImporter`), `Services/Catalog` (Apple Books resolution and scorer), `Persistence/LibraryStore` (atomic JSON), `Models/BookRecommendation` (v2: optional author, `sources[]`, `evidence[]`). |
| `TheReadingHoardShare/` | The share extension. A courier only: it never fetches, plays or shows media. |
| `TheReadingHoard/Shared/` | `AppGroup` and `PendingImport`, compiled into both targets. The install id, API base URL and the import inbox live in the App Group `group.com.lisamd22.TheReadingHoard`. |
| `backend/` | `hoard-api`: FastAPI, Python 3.12, Gemini. Per-platform resolvers, chunked parallel watching, SQLite caches, per-install rate limit, host allow-list. See [`backend/README.md`](backend/README.md). |
| `docs/probe-results/` | What each platform's share sheet actually hands over, measured on a physical iPhone (only ever a URL — never media). |

## Run it

1. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set
   `HOARD_APP_KEY` to the backend's `APP_KEY`. The file is gitignored and flows into both
   Info.plists as `HoardAppKey`.
2. Open `TheReadingHoard.xcodeproj` in Xcode 15 or later. Both targets need the App Group
   `group.com.lisamd22.TheReadingHoard` under your team.
3. Run the `TheReadingHoard` scheme on a simulator or device. The app talks to the deployed
   backend by default; point it elsewhere with `-hoard-api <url>` (see below).

For a local backend, follow [`backend/README.md`](backend/README.md) and launch the app with
`-hoard-api http://<your-mac>:8080`. Info.plist allows local networking.

## Launch arguments

| Argument | Effect |
| --- | --- |
| `-hoard-import <url>` | Open the Import tab with the link filled in and start the import |
| `-hoard-api <url>` | Use this backend instead of the default. Persists in App Group defaults — remove it afterwards |
| `-hoard-demo` | Skip onboarding and seed an ephemeral sample shelf (nothing is persisted) |
| `-hoard-skip-intro` | Go straight to the app |
| `-hoard-force-intro` | Play the intro even after it has been seen |
| `-hoardIntroFreeze <seconds>` | Hold the intro on one frame while tuning it |
| `-hoardIntroSpeed <rate>` | Run the intro at a fraction of normal speed |

## Tests

- iOS: the `TheReadingHoardTests` target — book identity (title normalisation, author matching, Apple track ids), library merge rules, platform detection, URL validation.
- Backend: `cd backend && .venv/bin/pytest` — canonical ids, grounding gate, stream parser.

## First-launch intro

The very first launch is a shot built on the key art. `the-reading-hoard-design-base-photo.png`
is the scene; the dragon glides in out of the foreground, the camera tracks it to the
castle, the doors part, and the camera carries on through them into the light while the
library resolves out of the stardust.

Nothing is redrawn. The painting is split into two assets so the dragon can move:

- `Assets.xcassets/IntroPlate` — the art with the dragon removed, the hole behind it
  filled by cloning masonry, mountain and terrace from elsewhere in the frame.
- `Assets.xcassets/IntroDragon` — the dragon alone, cut out with an eroded matte.
- `Assets.xcassets/IntroBackdrop` — the untouched original.

The dragon flies as the cutout over the plate. It lands back into exactly the pose it was
cut from, at which point plate + cutout *is* the painting again, so the shot cross-fades
to the untouched original and finishes on it. The matte and the fill live in
`scratchpad/plate.swift` (see git history) and were driven from `dragon-poly.txt`.

`IntroBackdrop.swift` holds the camera, the flight path, and a map of features measured
off the artwork in image pixels — the doorway at (462, 930), its wooden doors spanning
y 944–998 and splitting at x 462, the dragon's resting anchor at (716, 806), the waterline
at y 1098. `IntroRenderer.swift` composites the plates and animates what the painting
implies is moving: water shimmer, the dragon's breath and embers, lamp flicker, star
twinkle, the doors parting and the light beyond them.

It records that it has played in `UserDefaults` and is skipped when Reduce Motion is on.

### Resolution and the two-asset shortcut

The base painting is 941 x 1672. Filling a 3x phone screen already upscales it 1.28x, so
the push-in is capped at roughly 2x. Two things would lift this considerably, both on the
art side rather than the code side:

1. A larger render of the same scene (~2500px wide) — drop it in at
   `Assets.xcassets/IntroBackdrop.imageset/backdrop.png` and the whole shot sharpens.
2. **The scene rendered twice: once with no dragon, once with the dragon alone.** That
   removes the matte and the cloned fill entirely, and with a dragon rendered in a flying
   pose the landing would be a real flight rather than a glide of a perched pose.

## Product plan

[`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) is the original milestone roadmap
from the build specification; the link import above replaces its "mocked Reel import".
