# The Reading Hoard

The Reading Hoard is a native iOS reading companion that turns book recommendations from Instagram Reels into a calm, organized to-be-read library.

## Current milestone

The first vertical slice includes:

- SwiftUI app foundation for iOS 17+
- a first-launch flight into the castle key art
- genre, trope, and format onboarding
- a warm castle-library visual system
- a TBR library with duplicate-safe insertion
- a mocked Instagram Reel import flow ready to be replaced by the production pipeline
- unit tests for duplicate handling and import validation

## Open the project

1. Open `TheReadingHoard.xcodeproj` in Xcode 15 or later.
2. Select an iPhone simulator.
3. Run the `TheReadingHoard` scheme.

The mocked importer works offline. Paste any valid Instagram Reel URL to see a detected recommendation added to the library.

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

A recording is in [`Documentation/first-launch-intro.mp4`](Documentation/first-launch-intro.mp4)
(half-size copy: `first-launch-intro-compact.mp4`).

### Resolution and the two-asset shortcut

The base painting is 941 x 1672. Filling a 3x phone screen already upscales it 1.28x, so
the push-in is capped at roughly 2x. Two things would lift this considerably, both on the
art side rather than the code side:

1. A larger render of the same scene (~2500px wide) — drop it in at
   `Assets.xcassets/IntroBackdrop.imageset/backdrop.png` and the whole shot sharpens.
2. **The scene rendered twice: once with no dragon, once with the dragon alone.** That
   removes the matte and the cloned fill entirely, and with a dragon rendered in a flying
   pose the landing would be a real flight rather than a glide of a perched pose.

Launch arguments for working on it:

| Argument | Effect |
| --- | --- |
| `-hoard-force-intro` | Play the intro even after it has been seen |
| `-hoard-skip-intro` | Go straight to the app |
| `-hoard-demo` | Skip onboarding and seed a sample shelf |
| `-hoardIntroFreeze <seconds>` | Hold the shot on one frame while tuning it |
| `-hoardIntroSpeed <rate>` | Run the shot at a fraction of normal speed |

## Product plan

See [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) for the step-by-step roadmap derived from the build specification.
