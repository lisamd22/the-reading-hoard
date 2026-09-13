import Foundation

/// Normalisation for INTERNAL comparison keys only.
///
/// Do NOT feed the output of `key(_:)` to a catalog query. Measured 2026-08-27:
/// Open Library returns `numFound: 0` for "Butcher and Blackbird" where the raw
/// "Butcher & Blackbird" is the only form with any chance. Query catalogs with the
/// raw extracted string; normalise only when comparing two strings we already hold.
enum TitleNormalizer {

    /// `en_US_POSIX` deliberately, never `.current` — under a Turkish locale
    /// `"I".lowercased()` becomes a dotless ı and every title containing an I
    /// stops matching itself.
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let leadingArticles = ["the ", "a ", "an "]

    /// Trailing volume markers: "book 1", "#1", "vol 1", "volume 1", ", 1"
    private static let volumeSuffix = try! NSRegularExpression(
        pattern: #"[\s,]*(?:#\d+|(?:book|vol|volume|part)\s*\.?\s*\d+|\d+)\s*$"#,
        options: [.caseInsensitive]
    )

    /// Full normalisation: fold, lowercase, expand `&`, drop subtitle, drop leading
    /// article, drop trailing volume marker, collapse whitespace.
    static func normalize(_ raw: String) -> String {
        var s = raw.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: posix)
            .lowercased(with: posix)

        s = s.replacingOccurrences(of: "&", with: " and ")
        s = stripSubtitle(s)
        s = collapse(s)

        for article in leadingArticles where s.hasPrefix(article) {
            s = String(s.dropFirst(article.count))
            break
        }

        let range = NSRange(s.startIndex..., in: s)
        s = volumeSuffix.stringByReplacingMatches(in: s, range: range, withTemplate: "")

        return collapse(s)
    }

    /// Folded and lowercased, but WITHOUT subtitle stripping. Used to tell a clean
    /// edition from a heavily annotated or translated one — "Quicksilver" against
    /// "Quicksilver - Tochter des Silbers. Gefangene der Schatten".
    static func fullKey(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: posix)
            .lowercased(with: posix)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// The comparison key: normalised, with every non-alphanumeric removed.
    static func key(_ raw: String) -> String {
        normalize(raw).unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// A surname for author disambiguation. Handles "Yarros, Rebecca" as well as
    /// "Rebecca Yarros", and ignores trailing initials.
    static func authorSurname(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let cleaned = raw.folding(options: [.diacriticInsensitive], locale: posix)
            .lowercased(with: posix)

        if let comma = cleaned.firstIndex(of: ",") {
            let surname = collapse(String(cleaned[..<comma]))
            if !surname.isEmpty { return surname }
        }
        let parts = collapse(cleaned)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && $0 != "jr" && $0 != "sr" }
        return parts.last
    }

    /// Everything before a `:` or an opening bracket — "Fourth Wing (The Empyrean, 1)"
    /// and "Zodiac Academy: The Awakening" both reduce to their leading title.
    private static func stripSubtitle(_ s: String) -> String {
        var cut = s.endIndex
        for delimiter in [":", "(", "[", " - ", " – ", " — "] {
            if let r = s.range(of: delimiter), r.lowerBound < cut, r.lowerBound != s.startIndex {
                cut = r.lowerBound
            }
        }
        return String(s[..<cut])
    }

    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
