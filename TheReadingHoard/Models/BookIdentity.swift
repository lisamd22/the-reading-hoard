import Foundation

/// How two library entries are judged to be the same book.
///
/// Tiered deliberately. The Open Library work key is NOT a tier: measured
/// 2026-08-27, `q=Fourth Wing` and `q=fourth+wing+yarros` return *different*
/// work keys for the same book, which is the exact failure such a tier exists
/// to prevent. It is stored for enrichment, never used to merge.
enum BookIdentity: Hashable, Codable, Sendable {
    /// Tier 1 — stable, and we already hold it from catalog resolution.
    case apple(Int)
    /// Tier 2 — edition-level.
    case isbn(String)
    /// Tier 3 — unresolved books only.
    case fuzzy(title: String, authorSurname: String?)
}

/// How confident the extraction was. Independent of catalog resolution:
/// a high-confidence extraction can still resolve to nothing.
enum Confidence: String, Codable, Sendable, Comparable, CaseIterable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// Whether we matched it to a real catalog record.
enum Resolution: String, Codable, Sendable {
    /// Grounded in evidence AND catalog score >= 0.75.
    case confirmed
    /// Grounded, but in the gray band or ambiguous — user confirms.
    case needsReview
    /// Grounded, no catalog hit anywhere. Kept, never discarded.
    case unresolved
}
