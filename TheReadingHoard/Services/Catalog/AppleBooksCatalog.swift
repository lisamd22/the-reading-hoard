import Foundation

struct CatalogMatch: Codable, Sendable, Equatable, Hashable {
    var title: String
    var authors: [String]
    var appleTrackID: Int?
    var appleStoreURL: URL?
    var coverURL: URL?
    var genres: [String]
    var releaseYear: Int?
    var ratingCount: Int?
    var score: Double = 0
}

protocol CatalogResolving: Sendable {
    func resolve(title: String, author: String?) async throws
        -> (best: CatalogMatch?, alternates: [CatalogMatch])
}

/// Apple Books via the public iTunes Search API. No key, no quota registration.
///
/// Chosen over Google Books and Open Library on measured evidence: Open Library
/// returned `numFound: 0` for "Butcher & Blackbird" in three query forms, took
/// 1.6-4.2s per query, and returned different work keys for the same book depending
/// on query phrasing.
struct AppleBooksCatalog: CatalogResolving {

    var session: URLSession = .shared
    var country: String = Locale.current.region?.identifier ?? "US"

    func resolve(title: String, author: String?) async throws
        -> (best: CatalogMatch?, alternates: [CatalogMatch]) {

        var seen: [CatalogMatch] = []

        // 1. Title + author.
        if let author, !author.isEmpty {
            seen += try await search("\(title) \(author)")
        }
        // 2. Title only. NOT an optimisation — measured: "Quicksilver Callle Hart"
        //    returns 0 results, while "Quicksiiver" alone returns the correct book
        //    at rank 1. One bad OCR token annihilates a perfect title match.
        if seen.isEmpty {
            seen += try await search(title)
        }
        // 3. Subtitle stripped.
        if seen.isEmpty {
            let trimmed = TitleNormalizer.normalize(title)
            if trimmed != title.lowercased(), !trimmed.isEmpty {
                seen += try await search(trimmed)
            }
        }
        guard !seen.isEmpty else { return (nil, []) }

        let scored = seen
            .map { CatalogScorer.scored($0, wantedTitle: title, wantedAuthor: author) }
            .sorted { $0.score > $1.score }

        let best = scored.first
        let alternates = Array(scored.dropFirst().prefix(3))
        return (best.flatMap { $0.score >= CatalogScorer.reviewFloor ? $0 : nil } ?? best,
                alternates)
    }

    private func search(_ term: String) async throws -> [CatalogMatch] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "term", value: term),
            .init(name: "media", value: "ebook"),
            .init(name: "limit", value: "10"),
            .init(name: "country", value: country)
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode(ITunesResponse.self, from: data))?.results
            .compactMap(\.asMatch) ?? []
    }

    // MARK: - Wire format

    private struct ITunesResponse: Decodable { let results: [Item] }

    private struct Item: Decodable {
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let trackViewUrl: String?
        let artworkUrl100: String?
        let genres: [String]?
        let releaseDate: String?
        let userRatingCount: Int?

        var asMatch: CatalogMatch? {
            guard let trackName else { return nil }
            return CatalogMatch(
                title: trackName,
                authors: artistName.map { [$0] } ?? [],
                appleTrackID: trackId,
                appleStoreURL: trackViewUrl.flatMap(URL.init(string:)),
                coverURL: Self.cover(from: artworkUrl100),
                genres: genres ?? [],
                releaseYear: releaseDate.flatMap { Int($0.prefix(4)) },
                ratingCount: userRatingCount
            )
        }

        /// Measured: `400x400bb.webp` is 27KB against 69KB for the jpg — 61% smaller,
        /// natively decodable by ImageIO, and served with a ~177-day cache header.
        /// BookCard's slot is 72x106pt = 216x318px @3x, so 400px is the right size.
        static func cover(from artworkUrl100: String?) -> URL? {
            guard let artworkUrl100 else { return nil }
            let rewritten = artworkUrl100.replacingOccurrences(of: "100x100bb.jpg",
                                                               with: "400x400bb.webp")
            return URL(string: rewritten)
        }
    }
}

/// Deterministic weighted score. Never trust rank 1 — measured, `Iron Flame` returns
/// a German edition at rank 4 and study guides from Snap Read / Turbo-Learning /
/// PageCraft Summaries. Publisher name is NOT a reliable signal; genre is.
enum CatalogScorer {

    static let autoAcceptFloor = 0.75
    static let reviewFloor = 0.45

    private static let studyAidGenres: Set<String> = ["Study Aids", "Reference"]
    private static let summaryPrefixes = [
        "summary of", "summary and analysis of", "study guide", "analysis of",
        "conversation starters", "key takeaways"
    ]
    private static let foreignEditionMarkers = [
        "version francaise", "version française", "edicion espanola", "edición española",
        "deutsche ausgabe", "italiano", "português", "flammengeküsst", "flammengekusst"
    ]

    static func scored(_ match: CatalogMatch, wantedTitle: String, wantedAuthor: String?) -> CatalogMatch {
        var m = match
        var score = 0.0

        let want = TitleNormalizer.key(wantedTitle)
        let got = TitleNormalizer.key(match.title)

        if want == got {
            score += 0.45
        } else if StringSimilarity.jaroWinkler(want, got) >= 0.92 {
            score += 0.35
        } else {
            score += 0.15 * StringSimilarity.jaroWinkler(want, got)
        }

        if let surname = TitleNormalizer.authorSurname(wantedAuthor) {
            let candidateAuthors = match.authors.joined(separator: " ").lowercased()
            if candidateAuthors.contains(surname) { score += 0.30 }
        }

        let lowerTitle = match.title.lowercased()
        if !studyAidGenres.isDisjoint(with: match.genres) { score -= 0.50 }
        if summaryPrefixes.contains(where: { lowerTitle.hasPrefix($0) }) { score -= 0.50 }
        if foreignEditionMarkers.contains(where: { lowerTitle.contains($0) }) { score -= 0.35 }
        if lowerTitle.contains("boxed set") || lowerTitle.contains("box set") { score -= 0.25 }

        if let year = match.releaseYear,
           let current = Calendar.current.dateComponents([.year], from: .now).year,
           current - year <= 3 { score += 0.05 }
        if let count = match.ratingCount, count > 100 { score += 0.05 }

        // Title tightness. Measured 2026-09-01: on a DE storefront, "Quicksilver
        // Callie Hart" ranks the German edition ("Quicksilver - Tochter des Silbers.
        // Gefangene der Schatten") FIRST and the English edition second, while US and
        // GB rank English first. Subtitle stripping makes both look like exact
        // matches, so without this the storefront's language silently decides which
        // edition the reader gets.
        let wantFull = TitleNormalizer.fullKey(wantedTitle)
        let gotFull = TitleNormalizer.fullKey(match.title)
        if wantFull == gotFull {
            score += 0.12
        } else if gotFull.count > wantFull.count * 2 {
            score -= 0.12
        }

        m.score = max(0, min(1, score))
        return m
    }

    static func resolution(for score: Double) -> Resolution {
        if score >= autoAcceptFloor { return .confirmed }
        if score >= reviewFloor { return .needsReview }
        return .unresolved
    }
}
