import Foundation

/// Uses a free transcription of the audio as a second opinion on forced alignment.
///
/// Forced alignment places the script wherever it is told to, even over speech that has
/// nothing to do with the script. A free transcription shows what was actually said: where
/// it is clear, spoken at a talking pace and unrelated to the script, the script does not
/// belong there.
public enum CrossCheck {
    /// Speech the model heard clearly that does not appear in the script
    /// (a spoken introduction, talking between songs, an ad-lib…).
    public static func unscriptedRegions(in segments: [RecognizedSegment], scriptLines: [String]) -> [ClosedRange<Double>] {
        let script = scriptLines.map(SequenceAligner.comparisonCharacters).filter { !$0.isEmpty }
        let ordered = segments.filter { $0.end > $0.start }.sorted { $0.start < $1.start }

        enum Kind { case clear, likely, other }
        let kinds: [Kind] = ordered.map { segment in
            let characters = SequenceAligner.comparisonCharacters(segment.text)
            guard characters.count >= 2, !isRepetitive(characters) else { return .other }
            guard !resemblesScript(characters, script: script) else { return .other }
            // Talking is faster than singing. Sung passages the model cannot follow often come
            // out as fluent, confident nonsense, but at a singing pace.
            let rate = spokenLength(characters) / (segment.end - segment.start)
            if segment.confidence >= clearConfidence, rate >= clearSpeechRate { return .clear }
            // Fast, less certain text next to clear speech is most likely more of the same talk.
            return rate >= speechRate ? .likely : .other
        }

        var regions: [ClosedRange<Double>] = []
        var index = 0
        while index < ordered.count {
            guard kinds[index] != .other else { index += 1; continue }
            // Extend the run. A phrase or two that does not qualify is tolerated in the middle
            // (the speaker quoting the script, a mumbled word) as long as the talk goes on.
            var last = index
            var next = index + 1
            while next < ordered.count, ordered[next].start - ordered[next - 1].end <= maxGap {
                if kinds[next] != .other {
                    last = next
                } else if next - last > 2 || ordered[next].end - ordered[last].end > maxBridgeSeconds {
                    break
                }
                next += 1
            }
            let run = index...last
            let clearSeconds = run.filter { kinds[$0] == .clear }.reduce(0.0) { $0 + ordered[$1].end - ordered[$1].start }
            if clearSeconds >= minimumClearSeconds {
                regions.append(ordered[index].start...max(ordered[index].start, ordered[last].end))
            }
            index = last + 1
        }
        return regions
    }

    /// Passages where the transcription has nothing usable: long stretches without text,
    /// and text that is one thing repeated over and over.
    public static func unheardSpans(in segments: [RecognizedSegment], duration: Double) -> [ClosedRange<Double>] {
        let usable = segments
            .filter { $0.end > $0.start && !isRepetitive(SequenceAligner.comparisonCharacters($0.text)) }
            .sorted { $0.start < $1.start }
        var spans: [ClosedRange<Double>] = []
        var cursor = 0.0
        for segment in usable where segment.start < duration {
            if segment.start - cursor >= minimumUnheardSeconds { spans.append(cursor...segment.start) }
            cursor = max(cursor, segment.end)
        }
        if duration - cursor >= minimumUnheardSeconds { spans.append(cursor...duration) }
        return spans
    }

    /// How much of `line` shows up in the free transcription between `start` and `end`, 0...1.
    public static func agreement(line: String, words: [TimedWord], start: Double, end: Double) -> (matched: Int, total: Int) {
        let target = SequenceAligner.comparisonCharacters(line)
        guard !target.isEmpty else { return (0, 0) }
        let heard = words
            .filter { ($0.start + $0.end) / 2 >= start - agreementSlack && ($0.start + $0.end) / 2 <= end + agreementSlack }
            .flatMap { SequenceAligner.comparisonCharacters($0.text) }
        return (commonSubsequence(target, heard), target.count)
    }

    /// Whether a heard phrase could be a (possibly mis-heard) part of the script.
    static func resemblesScript(_ characters: [Character], script: [[Character]]) -> Bool {
        guard !characters.isEmpty else { return false }
        var best = 0
        for index in script.indices {
            // A spoken phrase may run across a line break.
            let stretch = index + 1 < script.count ? script[index] + script[index + 1] : script[index]
            best = max(best, commonSubsequence(characters, stretch))
            if best == characters.count { break }
        }
        // Two shared characters happen by chance in any short phrase.
        return best >= 3 && Double(best) / Double(characters.count) >= matchThreshold
    }

    /// The model stuck in a loop ("la la la la…") rather than hearing words.
    static func isRepetitive(_ characters: [Character]) -> Bool {
        characters.count >= 12 && Double(Set(characters).count) / Double(characters.count) < 0.4
    }

    /// Length of the longest common subsequence.
    static func commonSubsequence(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = previous
        for x in a {
            for (j, y) in b.enumerated() {
                current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Length in syllable-like units: a Latin letter counts for much less than a Han character.
    static func spokenLength(_ characters: [Character]) -> Double {
        characters.reduce(0) { $0 + ($1.isASCII ? 0.35 : 1) }
    }

    /// Below this share of matching characters, a phrase is not from the script.
    static let matchThreshold = 0.3
    static let clearConfidence = 0.6
    /// Clear speech slower than this (characters per second) is more likely singing.
    static let clearSpeechRate = 4.0
    /// Characters per second typical of talking rather than singing.
    static let speechRate = 5.0
    static let maxGap = 1.5
    static let maxBridgeSeconds = 4.0
    /// A region needs at least this much clearly heard unscripted speech.
    static let minimumClearSeconds = 4.0
    static let agreementSlack = 0.5
    /// A stretch without usable text this long is worth a second listen.
    static let minimumUnheardSeconds = 8.0
}
