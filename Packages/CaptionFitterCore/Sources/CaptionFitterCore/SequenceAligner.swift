import Foundation

/// A recognised word (or character group) with its time range in seconds.
public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Fits known script lines onto recognised speech by aligning the two texts
/// character by character and reading the times off the recognised side.
public enum SequenceAligner {
    /// Characters used for comparison only: lowercased, half-width, Traditional and
    /// Simplified Chinese unified, punctuation and whitespace removed.
    public static func comparisonCharacters(_ text: String) -> [Character] {
        var value = text.lowercased()
        if let half = value.applyingTransform(.fullwidthToHalfwidth, reverse: false) { value = half }
        if let simplified = value.applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false) {
            value = simplified
        }
        return value.filter { $0.isLetter || $0.isNumber }
    }

    private struct TimedCharacter {
        var character: Character
        var start: Double
        var end: Double
    }

    public static func align(scriptLines: [String], words: [TimedWord], mediaDuration: Double? = nil) -> [SubtitleLine] {
        // Flatten both sides into comparable characters.
        var transcript: [TimedCharacter] = []
        for word in words {
            let characters = comparisonCharacters(word.text)
            guard !characters.isEmpty else { continue }
            let span = max(0, word.end - word.start)
            for (i, character) in characters.enumerated() {
                let count = Double(characters.count)
                transcript.append(TimedCharacter(
                    character: character,
                    start: word.start + span * Double(i) / count,
                    end: word.start + span * Double(i + 1) / count
                ))
            }
        }

        var script: [Character] = []
        var lineRanges: [Range<Int>] = []
        for line in scriptLines {
            let characters = comparisonCharacters(line)
            lineRanges.append(script.count..<(script.count + characters.count))
            script.append(contentsOf: characters)
        }

        let matches = alignCharacters(script: script, transcript: transcript.map(\.character))
        let typicalCharacterDuration = medianCharacterDuration(transcript)

        // First pass: time every line that has at least one aligned character.
        struct Draft {
            var start: Double?
            var end: Double?
            var confidence: LineConfidence = .interpolated
        }
        var drafts = [Draft](repeating: Draft(), count: scriptLines.count)

        for (lineIndex, range) in lineRanges.enumerated() where !range.isEmpty {
            var firstOffset: Int?
            var lastOffset: Int?
            var exact = 0
            for k in range {
                guard let match = matches[k] else { continue }
                if firstOffset == nil { firstOffset = k - range.lowerBound }
                lastOffset = k - range.lowerBound
                if match.exact { exact += 1 }
            }
            guard let firstOffset, let lastOffset, exact > 0,
                  let firstMatch = matches[range.lowerBound + firstOffset],
                  let lastMatch = matches[range.lowerBound + lastOffset] else { continue }

            // Extrapolate over leading / trailing characters that found no partner.
            let leading = Double(firstOffset)
            let trailing = Double(range.count - 1 - lastOffset)
            drafts[lineIndex].start = transcript[firstMatch.index].start - leading * typicalCharacterDuration
            drafts[lineIndex].end = transcript[lastMatch.index].end + trailing * typicalCharacterDuration
            let ratio = Double(exact) / Double(range.count)
            drafts[lineIndex].confidence = ratio >= 0.5 ? .good : .partial
        }

        // Second pass: interpolate runs of unmatched lines between their timed neighbours.
        let fallbackEnd = mediaDuration ?? transcript.last?.end ?? Double(scriptLines.count) * 3
        var i = 0
        while i < drafts.count {
            guard drafts[i].start == nil else { i += 1; continue }
            var j = i
            while j < drafts.count, drafts[j].start == nil { j += 1 }
            let gapStart = i > 0 ? (drafts[i - 1].end ?? 0) : 0
            let gapEnd = j < drafts.count ? (drafts[j].start ?? fallbackEnd) : fallbackEnd
            let weights = (i..<j).map { Double(max(1, lineRanges[$0].count)) }
            let total = weights.reduce(0, +)
            var cursor = gapStart
            let available = max(0, gapEnd - gapStart)
            // Do not stretch unmatched lines unreasonably across a long silent gap.
            let scale = min(1, (total * typicalCharacterDuration * 3) / max(available, 0.001))
            for (offset, lineIndex) in (i..<j).enumerated() {
                let span = available * scale * weights[offset] / total
                drafts[lineIndex].start = cursor
                drafts[lineIndex].end = cursor + span
                cursor += span
            }
            i = j
        }

        // Final pass: make times monotonic, non-overlapping and long enough to read.
        var result: [SubtitleLine] = []
        var previousEnd = 0.0
        for (index, text) in scriptLines.enumerated() {
            var start = max(drafts[index].start ?? previousEnd, previousEnd)
            var end = max(drafts[index].end ?? start, start)
            if let mediaDuration {
                start = min(start, mediaDuration)
                end = min(end, mediaDuration)
            }
            result.append(SubtitleLine(start: start, end: end, text: text, confidence: drafts[index].confidence))
            previousEnd = end
        }
        for index in result.indices {
            let nextStart = index + 1 < result.count ? result[index + 1].start : (mediaDuration ?? .infinity)
            // Hold the line a little after the last word, but never into the next line.
            var end = min(result[index].end + 0.25, nextStart)
            if nextStart - end < 0.3, nextStart.isFinite { end = nextStart }
            let minimumEnd = min(result[index].start + 0.5, nextStart)
            result[index].end = max(end, minimumEnd, result[index].start)
        }
        return result
    }

    // MARK: - Character alignment

    struct Match: Equatable {
        var index: Int
        var exact: Bool
    }

    /// Banded semi-global alignment. Extra recognised text before, after or between
    /// script lines is tolerated; every script character is either paired with a
    /// recognised character or left unpaired.
    static func alignCharacters(script: [Character], transcript: [Character]) -> [Match?] {
        let n = script.count
        let m = transcript.count
        guard n > 0 else { return [] }
        guard m > 0 else { return [Match?](repeating: nil, count: n) }

        let matchScore: Int32 = 2
        let mismatchScore: Int32 = -1
        let gapScore: Int32 = -1
        let negativeInfinity = Int32.min / 2

        // Keep memory bounded for long recordings by only exploring a band around the diagonal.
        let halfBand = max(3000, abs(n - m) + 3000)
        let width = min(m + 1, 2 * halfBand + 1)
        func lowerBound(_ row: Int) -> Int {
            let centre = Int(Double(row) * Double(m) / Double(n))
            return min(max(0, centre - width / 2), m + 1 - width)
        }

        // Trace codes: 0 = diagonal, 1 = up (script character unpaired), 2 = left (recognised character skipped).
        var trace = [UInt8](repeating: 2, count: (n + 1) * width)
        var previous = [Int32](repeating: 0, count: width)
        var current = [Int32](repeating: negativeInfinity, count: width)
        var previousLow = lowerBound(0)

        // Row 0: skipping recognised text before the script starts is free.
        for i in 1...n {
            let low = lowerBound(i)
            let lastRow = i == n
            for offset in 0..<width {
                let j = low + offset
                var best = negativeInfinity
                var code: UInt8 = 1

                let upOffset = j - previousLow
                if upOffset >= 0, upOffset < width, previous[upOffset] > negativeInfinity {
                    best = previous[upOffset] + gapScore
                    code = 1
                }
                if j > 0 {
                    let diagonalOffset = j - 1 - previousLow
                    if diagonalOffset >= 0, diagonalOffset < width, previous[diagonalOffset] > negativeInfinity {
                        let score = previous[diagonalOffset] + (script[i - 1] == transcript[j - 1] ? matchScore : mismatchScore)
                        if score > best {
                            best = score
                            code = 0
                        }
                    }
                    if offset > 0, current[offset - 1] > negativeInfinity {
                        // Trailing recognised text after the script ends is free.
                        let score = current[offset - 1] + (lastRow ? 0 : gapScore)
                        if score > best {
                            best = score
                            code = 2
                        }
                    }
                }
                current[offset] = best
                trace[i * width + offset] = code
            }
            swap(&previous, &current)
            previousLow = low
        }

        var result = [Match?](repeating: nil, count: n)
        var i = n
        var j = m
        while i > 0 {
            let offset = j - lowerBound(i)
            guard offset >= 0, offset < width else { break }
            switch trace[i * width + offset] {
            case 0:
                result[i - 1] = Match(index: j - 1, exact: script[i - 1] == transcript[j - 1])
                i -= 1
                j -= 1
            case 1:
                i -= 1
            default:
                if j == 0 { i -= 1 } else { j -= 1 }
            }
        }
        return result
    }

    private static func medianCharacterDuration(_ characters: [TimedCharacter]) -> Double {
        let durations = characters.map { $0.end - $0.start }.filter { $0 > 0 }.sorted()
        guard !durations.isEmpty else { return 0.2 }
        return min(max(durations[durations.count / 2], 0.05), 0.5)
    }
}
