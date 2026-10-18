import Foundation

/// A parsed CSS-style color, components in 0...1.
struct ParsedColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

/// Decides whether a text payload is plain text, code, or a color literal.
enum ContentClassifier {
    // MARK: Public API

    static func classify(text: String, sourceBundleID: String?) -> ClipKind {
        if parseColor(text) != nil { return .color }
        if let bundleID = sourceBundleID, Constants.codeBundleIDs.contains(bundleID) { return .code }
        if looksLikeCode(text) { return .code }
        return .text
    }

    /// Builds the single-line preview shown in list rows.
    static func makePreview(from text: String) -> String {
        // Only look at the head of very large payloads — collapsing whitespace over megabytes is wasteful.
        let head = String(text.prefix(Constants.previewLength * 4))
        let collapsed = head
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(Constants.previewLength))
    }

    // MARK: Colors

    private static let hexRegex = try! NSRegularExpression(
        pattern: #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
    )
    private static let rgbRegex = try! NSRegularExpression(
        pattern: #"^rgba?\(\s*(\d{1,3}(?:\.\d+)?)\s*[,\s]\s*(\d{1,3}(?:\.\d+)?)\s*[,\s]\s*(\d{1,3}(?:\.\d+)?)\s*(?:[,/]\s*((?:\d*\.)?\d+%?)\s*)?\)$"#,
        options: [.caseInsensitive]
    )
    private static let hslRegex = try! NSRegularExpression(
        pattern: #"^hsla?\(\s*((?:\d*\.)?\d+)(?:deg)?\s*[,\s]\s*((?:\d*\.)?\d+)%\s*[,\s]\s*((?:\d*\.)?\d+)%\s*(?:[,/]\s*((?:\d*\.)?\d+%?)\s*)?\)$"#,
        options: [.caseInsensitive]
    )

    static func parseColor(_ raw: String) -> ParsedColor? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cheap length gate before touching regexes — color literals are short.
        guard !text.isEmpty, text.count <= 48 else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        if hexRegex.firstMatch(in: text, range: range) != nil {
            return parseHex(String(text.dropFirst()))
        }
        if let match = rgbRegex.firstMatch(in: text, range: range) {
            let parts = captures(match, in: text)
            guard parts.count >= 3,
                  let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) else { return nil }
            let alpha = parts.count > 3 ? parseAlpha(parts[3]) : 1
            return ParsedColor(red: min(r, 255) / 255, green: min(g, 255) / 255, blue: min(b, 255) / 255, alpha: alpha)
        }
        if let match = hslRegex.firstMatch(in: text, range: range) {
            let parts = captures(match, in: text)
            guard parts.count >= 3,
                  let h = Double(parts[0]), let s = Double(parts[1]), let l = Double(parts[2]) else { return nil }
            let alpha = parts.count > 3 ? parseAlpha(parts[3]) : 1
            let (r, g, b) = hslToRGB(h: h.truncatingRemainder(dividingBy: 360) / 360, s: min(s, 100) / 100, l: min(l, 100) / 100)
            return ParsedColor(red: r, green: g, blue: b, alpha: alpha)
        }
        return nil
    }

    private static func captures(_ match: NSTextCheckingResult, in text: String) -> [String] {
        (1..<match.numberOfRanges).compactMap { index in
            let r = match.range(at: index)
            guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func parseAlpha(_ raw: String) -> Double {
        if raw.hasSuffix("%"), let value = Double(raw.dropLast()) { return min(max(value / 100, 0), 1) }
        if let value = Double(raw) { return min(max(value, 0), 1) }
        return 1
    }

    private static func parseHex(_ hex: String) -> ParsedColor? {
        var digits = Array(hex)
        if digits.count == 3 || digits.count == 4 {
            digits = digits.flatMap { [$0, $0] }
        }
        guard digits.count == 6 || digits.count == 8 else { return nil }
        func channel(_ offset: Int) -> Double? {
            guard let value = UInt8(String(digits[offset..<offset + 2]), radix: 16) else { return nil }
            return Double(value) / 255
        }
        guard let r = channel(0), let g = channel(2), let b = channel(4) else { return nil }
        let a = digits.count == 8 ? (channel(6) ?? 1) : 1
        return ParsedColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func hue(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return (hue(h + 1 / 3), hue(h), hue(h - 1 / 3))
    }

    // MARK: Code heuristics

    private static let codeSymbols: Set<Character> = ["{", "}", "[", "]", "(", ")", ";", "=", "<", ">", "\\", "|", "&", "$", "#", "@", "*", "+", "~", "^", "%", "`"]
    private static let keywordRegex = try! NSRegularExpression(
        pattern: #"(?m)(^|\s)(func|def|class|struct|enum|interface|import|from|return|const|let|var|val|public|private|protected|static|void|int|float|double|bool|string|if|else|elif|for|while|switch|case|try|catch|except|throw|async|await|fn|impl|package|export|function|lambda|yield|new|self|this|nil|null|true|false|=>|->|#include|#import|::)(\s|$|\(|\{|:)"#
    )
    private static let urlRegex = try! NSRegularExpression(pattern: #"^[a-z][a-z0-9+.-]*://\S+$"#, options: [.caseInsensitive])

    /// Language-agnostic heuristic: symbol density, indentation, line terminators and keyword hits.
    static func looksLikeCode(_ raw: String) -> Bool {
        let text = String(raw.prefix(4_000)) // enough signal; keeps the cost bounded for huge payloads
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        if urlRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { return false }

        let lines = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var symbolCount = 0
        var visibleCount = 0
        for character in trimmed where !character.isWhitespace {
            visibleCount += 1
            if codeSymbols.contains(character) { symbolCount += 1 }
        }
        let density = visibleCount > 0 ? Double(symbolCount) / Double(visibleCount) : 0

        let indented = nonEmptyLines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") || $0.hasPrefix("  ") }.count
        let indentRatio = nonEmptyLines.isEmpty ? 0 : Double(indented) / Double(nonEmptyLines.count)

        let terminated = nonEmptyLines.filter {
            let last = $0.trimmingCharacters(in: .whitespaces).last
            return last == ";" || last == "{" || last == "}" || last == ":" || last == ")"
        }.count
        let terminatedRatio = nonEmptyLines.isEmpty ? 0 : Double(terminated) / Double(nonEmptyLines.count)

        let keywordHits = keywordRegex.numberOfMatches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))

        var score = 0
        if density >= 0.12 { score += 2 } else if density >= 0.07 { score += 1 }
        if nonEmptyLines.count >= 3 && indentRatio >= 0.3 { score += 2 }
        if nonEmptyLines.count >= 2 && terminatedRatio >= 0.5 { score += 1 }
        if keywordHits >= 2 { score += 1 }
        if keywordHits >= 5 { score += 1 }
        if trimmed.contains("{") && trimmed.contains("}") { score += 1 }
        if trimmed.contains("(") && trimmed.contains(")") && trimmed.contains("=") { score += 1 }
        // Prose signal: many ordinary sentences with few symbols — pull the score back down.
        let sentenceEnders = trimmed.filter { $0 == "." || $0 == "!" || $0 == "?" }.count
        if density < 0.05 && sentenceEnders >= 2 { score -= 2 }

        return score >= 3
    }
}
