import Foundation
import CoreGraphics

/// The on-device image path: pixels in, books out, no network except the keyless
/// catalog lookup. This is the primary extractor — measured on all four platforms,
/// Photos is the only source that hands over pixels at all.
struct ScreenshotImporter: Sendable {

    enum Stage: String, Sendable {
        case readingTheText = "Reading the text"
        case checkingTheCatalogue = "Checking the catalogue"

        var label: String { rawValue }
    }

    struct Outcome: Sendable {
        var books: [BookRecommendation]
        var spans: [EvidenceSpan]
        /// Candidates we read but could not place in any catalogue. Kept so the
        /// review screen can offer them rather than silently dropping them.
        var unresolved: [BookCandidateGuess]
        var ocrLineCount: Int
    }

    var ocr = OCREngine()
    var catalog: any CatalogResolving = AppleBooksCatalog()

    func run(image: CGImage,
             source: ImportSource,
             customWords: [String] = [],
             onStage: @Sendable (Stage) -> Void = { _ in }) async throws -> Outcome {

        onStage(.readingTheText)
        var options = OCREngine.Options.default
        options.customWords = customWords
        let lines = try await ocr.recognize(image, options: options).inReadingOrder()

        let spans = lines.enumerated().map { index, line in
            EvidenceSpan(id: "o\(index)",
                         channel: .onScreenText,
                         text: line.text,
                         engineConfidence: Double(line.confidence))
        }

        let guesses = CandidateExtractor.candidates(from: spans)
        guard !guesses.isEmpty else {
            return Outcome(books: [], spans: spans, unresolved: [], ocrLineCount: lines.count)
        }

        onStage(.checkingTheCatalogue)
        var books: [BookRecommendation] = []
        var unresolved: [BookCandidateGuess] = []

        // Resolve concurrently — these are independent keyless GETs.
        let resolved = await withTaskGroup(of: (BookCandidateGuess, CatalogMatch?).self) { group in
            for guess in guesses {
                group.addTask {
                    let match = try? await catalog.resolve(title: guess.title, author: guess.author)
                    return (guess, match?.best)
                }
            }
            var out: [(BookCandidateGuess, CatalogMatch?)] = []
            for await pair in group { out.append(pair) }
            return out
        }

        for (guess, match) in resolved {
            guard let match, match.score >= CatalogScorer.reviewFloor else {
                unresolved.append(guess)
                continue
            }
            let cited = spans.filter { guess.evidenceIDs.contains($0.id) }
            books.append(BookRecommendation(
                title: match.title,
                author: match.authors.first ?? guess.author,
                recommendationSummary: Self.summary(for: cited, source: source),
                sources: [source],
                evidence: cited,
                confidence: match.score >= CatalogScorer.autoAcceptFloor ? .high : .medium,
                resolution: CatalogScorer.resolution(for: match.score),
                appleTrackID: match.appleTrackID,
                appleStoreURL: match.appleStoreURL,
                coverURL: match.coverURL,
                genres: match.genres
            ))
        }

        books.sort { $0.confidence > $1.confidence }
        return Outcome(books: books, spans: spans, unresolved: unresolved, ocrLineCount: lines.count)
    }

    /// Until the LLM tier exists, the "why" is the source text verbatim — free,
    /// instant, and unhallucinatable by construction, since you cannot invent a
    /// reason that is literally a quotation.
    private static func summary(for cited: [EvidenceSpan], source: ImportSource) -> String {
        let quoted = cited.map(\.text).joined(separator: " · ")
        let origin = source.platform == .unknown ? "a screenshot" : "a \(source.platform.displayName) screenshot"
        return quoted.isEmpty
            ? "Read from \(origin)."
            : "Read from \(origin): “\(quoted)”"
    }
}
