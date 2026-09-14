import Foundation

/// Hand-rolled string metrics. Deliberately dependency-free — the whole of this
/// file is cheaper than adding an SPM package to a project that has none.
enum StringSimilarity {

    /// Classic Levenshtein edit distance.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }

        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)

        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1,        // deletion
                                 current[j - 1] + 1,     // insertion
                                 previous[j - 1] + cost) // substitution
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }

    /// Jaro similarity, 0…1.
    static func jaro(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return 0 }

        let window = max(max(x.count, y.count) / 2 - 1, 0)
        var xFlags = [Bool](repeating: false, count: x.count)
        var yFlags = [Bool](repeating: false, count: y.count)
        var matches = 0

        for i in 0..<x.count {
            let lo = max(0, i - window)
            let hi = min(i + window + 1, y.count)
            guard lo < hi else { continue }
            for j in lo..<hi where !yFlags[j] && x[i] == y[j] {
                xFlags[i] = true
                yFlags[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }

        var transpositions = 0
        var k = 0
        for i in 0..<x.count where xFlags[i] {
            while !yFlags[k] { k += 1 }
            if x[i] != y[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        return (m / Double(x.count) + m / Double(y.count) + (m - Double(transpositions) / 2) / m) / 3
    }

    /// Jaro-Winkler, 0…1. The shared-prefix bonus matches how OCR actually fails —
    /// tails garble more than heads — so it is the right metric for title matching.
    static func jaroWinkler(_ a: String, _ b: String, scalingFactor: Double = 0.1) -> Double {
        let j = jaro(a, b)
        guard j > 0.7 else { return j }
        let x = Array(a), y = Array(b)
        var prefix = 0
        for i in 0..<min(4, min(x.count, y.count)) {
            if x[i] == y[i] { prefix += 1 } else { break }
        }
        return j + Double(prefix) * scalingFactor * (1 - j)
    }

    /// True when two tokens are the same allowing `maxDistance` edits.
    /// Used by the grounding gate, where OCR noise otherwise over-rejects.
    static func tokensMatch(_ a: String, _ b: String, maxDistance: Int = 1) -> Bool {
        if a == b { return true }
        if abs(a.count - b.count) > maxDistance { return false }
        return levenshtein(a, b) <= maxDistance
    }
}
