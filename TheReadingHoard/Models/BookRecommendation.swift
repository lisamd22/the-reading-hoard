import Foundation

struct BookRecommendation: Identifiable, Codable, Equatable {
    enum ReadingStatus: String, Codable, CaseIterable {
        case toBeRead = "To be read"
        case reading = "Reading"
        case finished = "Finished"
    }

    let id: UUID
    let title: String
    let author: String
    let recommendationSummary: String
    let sourceURL: URL?
    let detectedAt: Date
    var status: ReadingStatus

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        recommendationSummary: String,
        sourceURL: URL? = nil,
        detectedAt: Date = .now,
        status: ReadingStatus = .toBeRead
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.recommendationSummary = recommendationSummary
        self.sourceURL = sourceURL
        self.detectedAt = detectedAt
        self.status = status
    }
}

enum RecommendationLibrary {
    static func merging(
        current: [BookRecommendation],
        new incoming: [BookRecommendation]
    ) -> [BookRecommendation] {
        var seen = Set(current.map(deduplicationKey))
        var result = current

        for recommendation in incoming where seen.insert(deduplicationKey(recommendation)).inserted {
            result.append(recommendation)
        }

        return result
    }

    private static func deduplicationKey(_ recommendation: BookRecommendation) -> String {
        [recommendation.title, recommendation.author]
            .map { value in
                value
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .components(separatedBy: .alphanumerics.inverted)
                    .joined()
            }
            .joined(separator: "|")
    }
}
