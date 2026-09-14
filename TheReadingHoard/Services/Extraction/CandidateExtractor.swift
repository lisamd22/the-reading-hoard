import Foundation

/// A title/author guess pulled out of raw text before any catalog lookup.
struct BookCandidateGuess: Sendable, Equatable {
    var title: String
    var author: String?
    /// IDs of the evidence spans this came from.
    var evidenceIDs: [String]
}

/// Deterministic, offline first pass over OCR or caption text.
///
/// This is not a substitute for the LLM reconstruction step — measured OCR output
/// like `ARAH J. MAAS` / `COURT / THORNS / ROSES` will not survive it. It exists to
/// catch the clean cases for free, so the common list-graphic never needs a network
/// call at all.
enum CandidateExtractor {

    /// Lines that are decoration, not content.
    private static let noisePatterns: [String] = [
        "save this", "save for later", "follow for more", "follow me",
        "part 1", "part 2", "link in bio", "comment", "like and", "share this",
        "my favourite", "my favorite", "tbr", "booktok", "bookstagram",
        "swipe", "read more", "tap in", "spoiler"
    ]

    static func candidates(from spans: [EvidenceSpan], limit: Int = 8) -> [BookCandidateGuess] {
        var out: [BookCandidateGuess] = []
        var seen = Set<String>()

        for span in spans {
            for guess in candidates(in: span.text, evidenceID: span.id) {
                let key = TitleNormalizer.key(guess.title)
                guard key.count >= 3, !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(guess)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    static func candidates(in raw: String, evidenceID: String) -> [BookCandidateGuess] {
        var out: [BookCandidateGuess] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let cleaned = clean(String(line))
            guard isPlausibleTitle(cleaned) else { continue }

            if let (title, author) = splitTitleBy(cleaned) {
                out.append(BookCandidateGuess(title: title, author: author, evidenceIDs: [evidenceID]))
            } else {
                out.append(BookCandidateGuess(title: cleaned, author: nil, evidenceIDs: [evidenceID]))
            }
        }
        return out
    }

    /// "Fourth Wing by Rebecca Yarros" / "Fourth Wing - Rebecca Yarros"
    static func splitTitleBy(_ line: String) -> (String, String)? {
        for separator in [" by ", " BY ", " — ", " – ", " - "] {
            guard let range = line.range(of: separator) else { continue }
            let title = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let author = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard title.count >= 3, author.count >= 3, author.count <= 60,
                  // An author is a couple of words, not a sentence.
                  author.split(separator: " ").count <= 4 else { continue }
            return (title, author)
        }
        return nil
    }

    /// Strip list markers, emoji, quotes, trailing ratings.
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Leading list markers: "1.", "1)", "•", "-", "*", "#1"
        while let first = s.first, "•*-–—#".contains(first) {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if let match = s.range(of: #"^\d{1,2}\s*[\.\):]\s*"#, options: .regularExpression) {
            s = String(s[match.upperBound...])
        }

        // Star ratings and stray symbols.
        s = s.replacingOccurrences(of: #"[★☆⭐️✨💫🔥😭🥹📚💕]"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’.,:;"))
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isPlausibleTitle(_ s: String) -> Bool {
        guard s.count >= 3, s.count <= 90 else { return false }
        // Needs letters.
        guard s.rangeOfCharacter(from: .letters) != nil else { return false }
        // Not a handle or a hashtag.
        guard !s.hasPrefix("@"), !s.hasPrefix("#") else { return false }
        // Not a URL.
        guard !s.lowercased().contains("http"), !s.lowercased().contains("www.") else { return false }
        // Not obvious decoration.
        let lower = s.lowercased()
        guard !noisePatterns.contains(where: { lower.contains($0) }) else { return false }
        // Not a wall of prose.
        guard s.split(separator: " ").count <= 12 else { return false }
        // Not the graphic's own header: "5 ROMANTASY BOOKS", "10 books that wrecked me",
        // "3 fantasy reads". These are the single most common OCR false positive on a
        // list graphic, and each one costs a wasted catalogue lookup.
        if s.range(of: #"^\d{1,2}\b.*\b(books?|reads?|recs?|recommendations?|series)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil { return false }
        return true
    }
}
