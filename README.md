# The Reading Hoard

The Reading Hoard is a native iOS reading companion that turns book recommendations from Instagram Reels into a calm, organized to-be-read library.

## Current milestone

The first vertical slice includes:

- SwiftUI app foundation for iOS 17+
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

## Product plan

See [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) for the step-by-step roadmap derived from the build specification.
