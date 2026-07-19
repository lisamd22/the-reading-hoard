# The Reading Hoard — iOS implementation plan

This plan translates version 0.3 of the build specification into small, testable milestones. The product remains fast and useful first; atmosphere stays subtle and supports reading.

## Product and technical decisions

- Native iOS app using SwiftUI, targeting iOS 17 and later.
- Local-first library so saved books remain available without a network connection.
- Replaceable service boundaries for Reel ingestion, transcription, OCR, book detection, and summaries.
- AI processing runs through a backend; API credentials never ship in the app.
- The castle begins complete and beautiful. Personal visual details are earned through inferred reading tastes, never points or achievement popups.

## Milestone 1 — runnable foundation

Status: in progress

- Create the Xcode project and app architecture.
- Establish the castle-library color, type, spacing, and surface tokens.
- Build onboarding for genres, tropes, and reading formats.
- Build the TBR library and book cards.
- Add a mocked Reel import that exercises the complete user flow in seconds.
- Prevent duplicate recommendations.
- Add unit tests for the core model and mock service.

Acceptance: a new user can finish onboarding, paste a Reel URL, see a detected book with a concise “why it was recommended” summary, and find it in the library.

## Milestone 2 — production import pipeline

- Create a secure backend ingestion endpoint.
- Validate supported Instagram Reel URLs and create import jobs.
- Retrieve permitted media or accept a user-provided share/upload flow that complies with platform rules.
- Run speech-to-text and sampled-frame OCR.
- Combine transcript and OCR evidence to detect books.
- Resolve title/author metadata against a book catalog.
- Generate grounded recommendation summaries with evidence and confidence.
- Stream job progress and recover cleanly from partial failures.

Acceptance: real imports return traceable book matches without exposing service credentials or inventing recommendations.

## Milestone 3 — durable personal library

- Persist books and imports with SwiftData.
- Add cover images, notes, filters, priority, and reading status.
- Add duplicate review and merge behavior for uncertain matches.
- Support accessibility, Dynamic Type, VoiceOver, reduced motion, and offline states.

Acceptance: the TBR remains useful at scale and all primary flows are accessible.

## Milestone 4 — quiet personalization

- Infer taste signals from saved books and explicit onboarding choices.
- Introduce restrained castle details such as tea, blankets, ravens, fairy lights, or a dragon statue.
- Show the librarian dragon only during meaningful guidance or milestones.
- Never add points, streaks, competitive mechanics, achievement alerts, or attention-seeking notifications.

Acceptance: personalization feels discovered rather than announced and never slows the core workflow.

## Milestone 5 — expansion and release

- Add TikTok and YouTube import adapters behind the same service contract.
- Add privacy controls, data export/deletion, analytics consent, and production observability.
- Complete App Store assets, privacy disclosures, beta testing, and release QA.

## Questions to resolve before Milestone 2

- Which backend host and AI providers should be used?
- Should the first real import use the iOS share sheet, a pasted link, a user-uploaded video, or a combination?
- Which regions and languages must the first release support?
- Is account sync required for V1, or should V1 remain device-local?
