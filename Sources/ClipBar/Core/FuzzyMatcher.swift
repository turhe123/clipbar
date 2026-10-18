import Foundation

/// Tiny, allocation-light fuzzy matcher: exact substring hits rank highest, then
/// in-order subsequence matches scored by adjacency and word-boundary bonuses.
enum FuzzyMatcher {
    struct Query {
        let raw: String
        let lowercased: String
        let scalars: [Unicode.Scalar]

        init(_ raw: String) {
            self.raw = raw
            self.lowercased = raw.lowercased()
            self.scalars = Array(self.lowercased.unicodeScalars)
        }

        var isEmpty: Bool { scalars.isEmpty }
    }

    /// Returns a relevance score, or nil when `text` does not match. `text` must already be lower-cased.
    static func score(_ query: Query, in text: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        if let range = text.range(of: query.lowercased) {
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            let atWordStart = offset == 0 || text[text.index(before: range.lowerBound)].isWhitespace
            return 10_000 - min(offset, 2_000) + (atWordStart ? 500 : 0)
        }
        return subsequenceScore(query.scalars, in: text)
    }

    private static func subsequenceScore(_ needle: [Unicode.Scalar], in text: String) -> Int? {
        // Fuzzy matching only looks at the head of the payload; substring search above covers the rest.
        var score = 0
        var needleIndex = 0
        var previousMatched = false
        var previousScalar: Unicode.Scalar = " "
        var position = 0

        for scalar in text.unicodeScalars {
            if position >= 512 { break }
            if scalar == needle[needleIndex] {
                score += 10
                if previousMatched { score += 15 }
                if previousScalar == " " || previousScalar == "_" || previousScalar == "-" || previousScalar == "." || previousScalar == "/" {
                    score += 12
                }
                needleIndex += 1
                previousMatched = true
                if needleIndex == needle.count { return score - position / 4 }
            } else {
                previousMatched = false
            }
            previousScalar = scalar
            position += 1
        }
        return nil
    }
}
