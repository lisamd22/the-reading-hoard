import Foundation

struct BookRecommendation: Identifiable, Codable, Equatable, Sendable {
    static let schemaVersion = 2

    /// KEEP these raw values. BookCard renders `status.rawValue.uppercased()`, so
    /// dropping them yields "TOBEREAD" and silently changes the on-disk encoding.
    enum ReadingStatus: String, Codable, CaseIterable {
        case toBeRead = "To be read"
        case reading = "Reading"
        case finished = "Finished"
    }

    let id: UUID
    var title: String
    /// Optional by necessity. A title card routinely names a book and no author;
    /// a non-optional field forces us either to invent one — violating the
    /// "never invent a recommendation" bar — or to discard a valid find.
    var author: String?
    var recommendationSummary: String
    /// Replaces the old single `sourceURL`. The same book resurfacing across
    /// creators is the product's whole premise; the old merge discarded it.
    var sources: [ImportSource]
    var evidence: [EvidenceSpan]
    var confidence: Confidence
    var resolution: Resolution

    // Catalog identity, filled in by resolution.
    var appleTrackID: Int?
    var appleStoreURL: URL?
    var isbn13: String?
    /// Stored for enrichment. NOT a merge tier — see BookIdentity.
    var openLibraryWorkKey: String?
    var coverURL: URL?
    var genres: [String]

    let detectedAt: Date
    var status: ReadingStatus

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        recommendationSummary: String,
        sources: [ImportSource] = [],
        evidence: [EvidenceSpan] = [],
        confidence: Confidence = .medium,
        resolution: Resolution = .unresolved,
        appleTrackID: Int? = nil,
        appleStoreURL: URL? = nil,
        isbn13: String? = nil,
        openLibraryWorkKey: String? = nil,
        coverURL: URL? = nil,
        genres: [String] = [],
        detectedAt: Date = .now,
        status: ReadingStatus = .toBeRead
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.recommendationSummary = recommendationSummary
        self.sources = sources
        self.evidence = evidence
        self.confidence = confidence
        self.resolution = resolution
        self.appleTrackID = appleTrackID
        self.appleStoreURL = appleStoreURL
        self.isbn13 = isbn13
        self.openLibraryWorkKey = openLibraryWorkKey
        self.coverURL = coverURL
        self.genres = genres
        self.detectedAt = detectedAt
        self.status = status
    }

    /// Ordered identity claims, strongest first.
    var identities: [BookIdentity] {
        var result: [BookIdentity] = []
        if let appleTrackID { result.append(.apple(appleTrackID)) }
        if let isbn13, !isbn13.isEmpty { result.append(.isbn(isbn13)) }
        result.append(.fuzzy(title: TitleNormalizer.key(title),
                             authorSurname: TitleNormalizer.authorSurname(author)))
        return result
    }

    var displayAuthor: String { author ?? "Author unknown" }
}

// MARK: - Merging

extension BookRecommendation {
    /// Union sources and evidence, fill in nil identity fields, take the better
    /// cover, keep the higher-confidence summary. Never downgrades `status`,
    /// never discards a source.
    func absorbing(_ other: BookRecommendation) -> BookRecommendation {
        var merged = self

        let knownSources = Set(sources.map(\.id))
        merged.sources.append(contentsOf: other.sources.filter { !knownSources.contains($0.id) })

        let knownSpans = Set(evidence.map(\.id))
        merged.evidence.append(contentsOf: other.evidence.filter { !knownSpans.contains($0.id) })

        merged.appleTrackID = appleTrackID ?? other.appleTrackID
        merged.appleStoreURL = appleStoreURL ?? other.appleStoreURL
        merged.isbn13 = isbn13 ?? other.isbn13
        merged.openLibraryWorkKey = openLibraryWorkKey ?? other.openLibraryWorkKey
        merged.coverURL = coverURL ?? other.coverURL
        merged.author = author ?? other.author

        if merged.genres.isEmpty { merged.genres = other.genres }

        // A better-resolved incoming record upgrades ours.
        if other.confidence > confidence {
            merged.confidence = other.confidence
            merged.recommendationSummary = other.recommendationSummary
        }
        if resolution != .confirmed, other.resolution == .confirmed {
            merged.resolution = .confirmed
            merged.title = other.title
        }

        // Reading progress is the user's, and only ever moves forward.
        if status == .toBeRead, other.status != .toBeRead { merged.status = other.status }

        return merged
    }
}

struct MergeResult: Sendable {
    var library: [BookRecommendation]
    var merged: [(existing: UUID, absorbed: BookRecommendation)] = []
    var needsUserDecision: [(existing: BookRecommendation, incoming: BookRecommendation)] = []
}

enum RecommendationLibrary {

    enum Relation: Equatable { case same, distinct, ambiguous }

    /// Title similarity above which two entries are the same book, given a
    /// matching or absent author.
    static let sameTitleThreshold = 0.94
    /// Below `sameTitleThreshold` but above this, ask the user.
    static let ambiguousTitleThreshold = 0.87

    static func relation(_ a: BookRecommendation, _ b: BookRecommendation) -> Relation {
        // Tier 1 and 2: a hard catalog identity settles it outright.
        if let x = a.appleTrackID, let y = b.appleTrackID { return x == y ? .same : .distinct }
        if let x = a.isbn13, let y = b.isbn13, !x.isEmpty, !y.isEmpty {
            return x == y ? .same : .distinct
        }

        // Tier 3: fuzzy.
        let ka = TitleNormalizer.key(a.title), kb = TitleNormalizer.key(b.title)
        guard !ka.isEmpty, !kb.isEmpty else { return .distinct }

        let sa = TitleNormalizer.authorSurname(a.author)
        let sb = TitleNormalizer.authorSurname(b.author)
        // Two known, different authors mean two different books even on an
        // identical title — "Haunting Adeline" is genuinely two books.
        if let sa, let sb, sa != sb { return .distinct }

        if ka == kb { return .same }

        // Similarity alone is not enough. Jaro-Winkler's shared-prefix bonus scores
        // short, same-prefix strings deceptively high — "bookone" vs "booktwo" lands
        // at 0.886 despite being three edits apart. Real OCR damage is 1-2 edits
        // ("quicksiiver", "nigth"), so gate on an edit budget as well.
        let similarity = StringSimilarity.jaroWinkler(ka, kb)
        let edits = StringSimilarity.levenshtein(ka, kb)
        guard edits <= editBudget(forLength: max(ka.count, kb.count)) else { return .distinct }

        if similarity >= sameTitleThreshold {
            // Near-identical titles with no author on either side are the case
            // most likely to be two different books, so make the user decide.
            return (sa == nil && sb == nil) ? .ambiguous : .same
        }
        if similarity >= ambiguousTitleThreshold { return .ambiguous }
        return .distinct
    }

    /// Edits we will forgive, scaled to title length. Always at least 1 so short
    /// titles tolerate a single OCR slip.
    static func editBudget(forLength length: Int) -> Int {
        max(1, Int((Double(length) * 0.15).rounded(.up)))
    }

    static func merging(current: [BookRecommendation],
                        incoming: [BookRecommendation]) -> MergeResult {
        var result = MergeResult(library: current)

        for candidate in incoming {
            if let index = result.library.firstIndex(where: { relation($0, candidate) == .same }) {
                let absorbed = result.library[index].absorbing(candidate)
                result.library[index] = absorbed
                result.merged.append((existing: absorbed.id, absorbed: candidate))
                continue
            }
            if let existing = result.library.first(where: { relation($0, candidate) == .ambiguous }) {
                result.needsUserDecision.append((existing: existing, incoming: candidate))
                continue
            }
            result.library.append(candidate)
        }
        return result
    }
}
