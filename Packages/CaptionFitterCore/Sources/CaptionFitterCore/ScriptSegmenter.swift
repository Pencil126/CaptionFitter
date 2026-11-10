import Foundation
import NaturalLanguage

/// Turns a pasted script into subtitle lines.
public enum ScriptSegmenter {
    public enum Mode: Equatable, Sendable {
        /// One subtitle per non-empty line of the script.
        case keepLineBreaks
        /// Break at sentence punctuation, then keep each subtitle within `maxWidth`
        /// (a CJK character counts as 1, a Latin letter as 0.5).
        case automatic(maxWidth: Double)
    }

    public static func segment(_ script: String, mode: Mode) -> [String] {
        let paragraphs = script
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        switch mode {
        case .keepLineBreaks:
            return paragraphs
        case .automatic(let maxWidth):
            let limit = max(4, maxWidth)
            return paragraphs
                .flatMap { splitSentences($0) }
                .flatMap { fit($0, limit: limit) }
                .map(trimTrailingPunctuation)
                .filter { !$0.isEmpty }
        }
    }

    public static func displayWidth(_ text: String) -> Double {
        text.reduce(0) { $0 + ($1.isASCII ? 0.5 : 1) }
    }

    // MARK: - Private

    private static let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "…"]
    private static let clauseBreaks: Set<Character> = ["，", "、", ",", "：", ":", "—"]
    private static let closers: Set<Character> = ["」", "』", "”", "’", "\"", "）", ")", "》"]

    private static func splitSentences(_ text: String) -> [String] {
        split(text) { characters, i in
            let character = characters[i]
            if sentenceEnders.contains(character) { return true }
            // An ASCII full stop ends a sentence only when followed by a space or the end,
            // so "3.5" and "e.g." stay intact.
            if character == "." {
                return i + 1 == characters.count || characters[i + 1] == " "
            }
            return false
        }
    }

    /// Splits after every character for which `isBreak` is true, keeping any closing
    /// quotes or repeated punctuation attached to the preceding piece.
    private static func split(_ text: String, isBreak: ([Character], Int) -> Bool) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var current = ""
        var i = 0
        while i < characters.count {
            current.append(characters[i])
            if isBreak(characters, i) {
                while i + 1 < characters.count,
                      closers.contains(characters[i + 1]) || sentenceEnders.contains(characters[i + 1]) {
                    i += 1
                    current.append(characters[i])
                }
                pieces.append(current)
                current = ""
            }
            i += 1
        }
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func fit(_ sentence: String, limit: Double) -> [String] {
        guard displayWidth(sentence) > limit else { return [sentence] }

        // Prefer breaking at clause punctuation, packing clauses greedily.
        let clauses = split(sentence) { characters, i in clauseBreaks.contains(characters[i]) }
        var lines: [String] = []
        var current = ""
        for clause in clauses {
            let joined = join(current, clause)
            if current.isEmpty || displayWidth(joined) <= limit {
                current = joined
            } else {
                lines.append(current)
                current = clause
            }
        }
        if !current.isEmpty { lines.append(current) }

        return lines.flatMap { displayWidth($0) > limit ? hardWrap($0, limit: limit) : [$0] }
    }

    /// Last resort for a clause with no punctuation: break between words, balancing the pieces so the last one is not a tiny leftover.
    private static func hardWrap(_ text: String, limit: Double) -> [String] {
        let pieceCount = max(2, Int((displayWidth(text) / limit).rounded(.up)))
        let target = displayWidth(text) / Double(pieceCount)

        // Break only between words, so "一個" or "subtitle" is never cut in half.
        var units: [String] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if cursor < range.lowerBound {
                // Punctuation and spaces between words stay attached to the preceding word.
                let between = String(text[cursor..<range.lowerBound])
                if units.isEmpty { units.append(between) } else { units[units.count - 1] += between }
            }
            units.append(String(text[range]))
            cursor = range.upperBound
            return true
        }
        if cursor < text.endIndex {
            let rest = String(text[cursor...])
            if units.isEmpty { units.append(rest) } else { units[units.count - 1] += rest }
        }

        // A single "word" wider than the limit (a long number, a URL) is cut by character.
        units = units.flatMap { displayWidth($0) > limit ? $0.map(String.init) : [$0] }

        var lines: [String] = []
        var current = ""
        for unit in units {
            if !current.isEmpty, lines.count < pieceCount - 1,
               displayWidth(current) + displayWidth(unit) / 2 >= target {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            current += unit
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(current.trimmingCharacters(in: .whitespaces))
        }
        return lines
    }

    private static func join(_ a: String, _ b: String) -> String {
        guard !a.isEmpty else { return b }
        let needsSpace = (a.last?.isASCII ?? false) && (b.first?.isASCII ?? false)
        return a + (needsSpace ? " " : "") + b
    }

    private static let trailingToTrim: Set<Character> = ["，", "。", "、", "；", ",", ";", "：", ":"]

    private static func trimTrailingPunctuation(_ text: String) -> String {
        var value = Substring(text)
        while let last = value.last, trailingToTrim.contains(last) || last == " " {
            value.removeLast()
        }
        // Keep an ASCII full stop off the end too, but never strip an ellipsis.
        if value.hasSuffix("."), !value.hasSuffix("..") { value.removeLast() }
        return String(value)
    }
}
