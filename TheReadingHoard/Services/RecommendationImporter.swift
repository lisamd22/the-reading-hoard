import Foundation

protocol RecommendationImporting: Sendable {
    func importRecommendation(from url: URL) async throws -> BookRecommendation
}

enum RecommendationImportError: LocalizedError, Equatable {
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "Paste a public Instagram Reel link to continue."
        }
    }
}

struct MockRecommendationImporter: RecommendationImporting {
    func importRecommendation(from url: URL) async throws -> BookRecommendation {
        guard Self.isSupported(url) else {
            throw RecommendationImportError.unsupportedURL
        }

        try await Task.sleep(for: .milliseconds(900))

        return BookRecommendation(
            title: "The Very Secret Society of Irregular Witches",
            author: "Sangu Mandanna",
            recommendationSummary: "Recommended as a warm found-family fantasy with gentle magic, a cozy house, and a slow-burn romance.",
            sources: [ImportSource(platform: .detect(host: url.host), canonicalURL: url, originalURL: url)],
            confidence: .high,
            resolution: .confirmed
        )
    }

    static func isSupported(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "instagram.com" || host.hasSuffix(".instagram.com") else {
            return false
        }

        return url.pathComponents.contains("reel") || url.pathComponents.contains("reels")
    }
}
