import CoreML
import Foundation
import WhisperKit

/// Aligns a known script by making the model "read" the script against the audio,
/// instead of transcribing freely and matching text afterwards.
///
/// At every decoding step the model may only produce the next script token.
/// Its attention over the audio while doing so gives each token a time. This keeps
/// working when free transcription fails (singing, music, noisy recordings), because
/// the model never has to guess the words.
extension WhisperRecognizer {
    /// - Parameter crossCheck: Also transcribe freely to find speech that is not in the script
    ///   and keep the script away from it. Roughly doubles the processing time.
    public func align(
        scriptLines: [String],
        samples: [Float],
        language: SpeechLanguage,
        crossCheck: Bool = true,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Alignment {
        let lines = scriptLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw AlignerError.emptyScript }
        guard let tokenizer = whisperKit.tokenizer else { throw AlignerError.noSpeechFound }

        let debug = ProcessInfo.processInfo.environment["CAPTIONFITTER_DEBUG"] != nil

        // Second opinion: what does the model hear when it is not told what to expect?
        var heard: Recognition?
        var barriers: [ClosedRange<Double>] = []
        if crossCheck {
            // No retries: retried passages are sampled at random, which makes nonsense look confident.
            var first = try await recognize(samples: samples, language: language, retries: 0) { progress($0 * 0.45) }
            // Without retries the model sometimes gives up on a passage (a long silence in the
            // text, or one word repeated endlessly). Listen to just those passages once more.
            let rate = AudioExtractor.sampleRate
            for span in CrossCheck.unheardSpans(in: first.segments, duration: Double(samples.count) / rate) {
                try Task.checkCancellation()
                let slice = Array(samples[Int(span.lowerBound * rate)..<min(samples.count, Int(span.upperBound * rate))])
                let again = try await recognize(samples: slice, language: language, retries: 0) { _ in }
                let recovered = again.segments.map { segment -> RecognizedSegment in
                    var moved = segment
                    moved.start += span.lowerBound
                    moved.end += span.lowerBound
                    moved.words = segment.words.map { TimedWord(text: $0.text, start: $0.start + span.lowerBound, end: $0.end + span.lowerBound) }
                    return moved
                }
                if debug { print(String(format: "listened again to %.2f-%.2f: %@", span.lowerBound, span.upperBound, recovered.map(\.text).joined(separator: " / "))) }
                first.segments.removeAll { span.contains(($0.start + $0.end) / 2) }
                first.segments.append(contentsOf: recovered)
            }
            first.segments.removeAll { CrossCheck.isRepetitive(SequenceAligner.comparisonCharacters($0.text)) }
            first.segments.sort { $0.start < $1.start }
            progress(0.5)
            heard = first
            barriers = CrossCheck.unscriptedRegions(in: first.segments, scriptLines: lines)
            if debug {
                for barrier in barriers { print(String(format: "unscripted speech %.2f-%.2f", barrier.lowerBound, barrier.upperBound)) }
            }
        }
        let heardWords = heard?.words ?? []
        let forcedProgress: @Sendable (Double) -> Void = { progress(crossCheck ? 0.5 + $0 * 0.5 : $0) }

        let sampleRate = AudioExtractor.sampleRate
        let duration = Double(samples.count) / sampleRate
        let windowSeconds = 30.0
        let special = tokenizer.specialTokens

        // Tokens for each line. Spaces next to CJK characters are layout, not speech.
        let lineTokens: [[Int]] = lines.map { line in
            let text = Self.speechText(line)
            let prefixed = (text.first?.isASCII ?? false) ? " " + text : text
            return tokenizer.encode(text: prefixed).filter { $0 < special.specialTokenBegin }
        }

        let filter = ForcedTokenFilter(endToken: special.endToken, noTimestampsToken: special.noTimestampsToken)
        let previousFilters = whisperKit.textDecoder.logitsFilters
        whisperKit.textDecoder.logitsFilters = [filter]
        defer { whisperKit.textDecoder.logitsFilters = previousFilters }

        let options = DecodingOptions(
            task: .transcribe,
            language: language.code,
            temperature: 0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: language.code == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: true,
            suppressBlank: false,
            compressionRatioThreshold: nil,
            logProbThreshold: nil,
            firstTokenLogProbThreshold: nil,
            noSpeechThreshold: nil,
            chunkingStrategy: ChunkingStrategy.none
        )

        /// What one window of audio gave for the script starting at a given line.
        struct Window {
            var placed: [(line: Int, subtitle: SubtitleLine, pace: Double)] = []
            var tokens = 0
            /// End of the last accepted token, relative to the window.
            var acceptedEnd: Double?
            var firstLineUnheard = false
            var firstTokenStart: Double?
            var offered = 0
            /// A line was squeezed into no time at all: more script than audio.
            var collapsed = false

            /// The first lines sit naturally: none missing, squeezed or stretched.
            var fitsNaturally: Bool {
                let leading = placed.prefix(3)
                guard !leading.isEmpty, leading.count >= min(3, offered) || !collapsed else { return false }
                guard placed.count >= 3 else { return !collapsed }
                let sorted = placed.map(\.pace).sorted()
                let typical = sorted[sorted.count / 2]
                return leading.allSatisfy { $0.pace >= typical * 0.4 && $0.pace <= typical * 2 }
            }
        }

        func decode(from firstLine: Int, position: Double, windowEnd: Double, final: Bool, maxTokens: Int) async throws -> Window {
            // The script offered to this window: as many upcoming lines as fit.
            var windowLines: [Int] = []
            var windowTokens: [Int] = []
            var candidate = firstLine
            while candidate < lines.count {
                let tokens = lineTokens[candidate]
                if !windowLines.isEmpty, windowTokens.count + tokens.count > maxTokens { break }
                windowLines.append(candidate)
                windowTokens.append(contentsOf: tokens.prefix(maxTokens))
                candidate += 1
            }

            let startSample = Int(position * sampleRate)
            let endSample = max(startSample, min(samples.count, Int(windowEnd * sampleRate)))
            let sliceSeconds = Double(endSample - startSample) / sampleRate

            filter.begin(script: windowTokens)
            let transcription: [TranscriptionResult] = try await whisperKit.transcribe(
                audioArray: Array(samples[startSample..<endSample]), decodeOptions: options
            )

            // Per-token times, in the order the tokens were produced.
            var tokenTimes: [(start: Double, end: Double)] = []
            for word in transcription.flatMap(\.segments).flatMap({ $0.words ?? [] }) {
                let tokens = word.tokens.filter { $0 < special.specialTokenBegin }
                guard !tokens.isEmpty else { continue }
                let span = Double(word.end - word.start) / Double(tokens.count)
                for i in tokens.indices {
                    tokenTimes.append((Double(word.start) + span * Double(i), Double(word.start) + span * Double(i + 1)))
                }
            }
            let produced = min(tokenTimes.count, filter.producedCount, windowTokens.count)

            // Accept whole lines that sit clear of the window's end. Script that does not fit in
            // the window piles up there with no real timing, so lines near the end are retried
            // in the next window, which starts right where the last accepted line ended.
            // Times come in 20 ms steps, so the last token may land a hair past the slice.
            let limit = final ? sliceSeconds + 0.05 : sliceSeconds - 5
            var window = Window()
            window.offered = windowLines.count
            window.firstTokenStart = produced > 0 ? tokenTimes[0].start : nil
            var offset = 0
            for line in windowLines {
                let count = min(lineTokens[line].count, maxTokens)
                guard count > 0 else { continue }
                guard offset + count <= produced else { break }
                var start = tokenTimes[offset].start
                var end = tokenTimes[offset + count - 1].end
                guard end <= limit else {
                    if debug { print(String(format: "  line %2d ends at %.2f, past the limit %.2f", line, end, limit)) }
                    break
                }
                // Too fast to be speech or singing: the line was squeezed in, not heard.
                if (end - start) / Double(count) < Self.fastestSecondsPerToken {
                    window.firstLineUnheard = window.placed.isEmpty
                    window.collapsed = true
                    if debug { print(String(format: "  line %2d collapsed: %.2f-%.2f", line, position + start, position + end)) }
                    break
                }
                // Silence or other sound before/after a line gets absorbed by its first/last token.
                // The caps follow the line's own pace, so slow singing keeps its long notes.
                let durations = (offset..<(offset + count)).map { tokenTimes[$0].end - tokenTimes[$0].start }.sorted()
                let typical = durations[durations.count / 2]
                start = max(start, tokenTimes[offset].end - min(max(typical * 2.5, 0.4), Self.longestTokenSeconds))
                end = min(end, tokenTimes[offset + count - 1].start + min(max(typical * 4, 0.6), Self.longestTokenSeconds))

                let probability = filter.meanProbability(offset..<(offset + count))
                let pace = (end - start) / Double(count)
                let trusted = probability >= 0.25 && pace <= 0.8
                window.placed.append((line, SubtitleLine(
                    start: position + start, end: position + end, text: lines[line],
                    confidence: trusted ? .good : .partial
                ), pace))
                if debug {
                    print(String(format: "  line %2d  %7.2f-%7.2f  p=%.2f pace=%.2f  %@", line, position + start, position + end, probability, pace, lines[line]))
                }
                window.acceptedEnd = tokenTimes[offset + count - 1].end
                offset += count
            }
            window.tokens = offset
            if debug {
                print(String(format: "window %.2f (+%.1fs) from line %d: offered %d lines / %d tokens, produced %d, accepted %d lines", position, sliceSeconds, firstLine, windowLines.count, windowTokens.count, produced, window.placed.count))
            }
            return window
        }

        /// How well the first lines of a window agree with what was heard there, 0...1.
        func agreement(_ window: Window) -> Double {
            var matched = 0
            var total = 0
            for item in window.placed.prefix(3) {
                let result = CrossCheck.agreement(line: item.subtitle.text, words: heardWords, start: item.subtitle.start, end: item.subtitle.end)
                matched += result.matched
                total += result.total
            }
            return total > 0 ? Double(matched) / Double(total) : 0
        }

        var result = [SubtitleLine?](repeating: nil, count: lines.count)
        var paces = [Double?](repeating: nil, count: lines.count)
        var lineIndex = 0
        var position = 0.0
        // How much script to offer per window: start generous, then follow the measured pace.
        var acceptedTokens = 0
        var acceptedSeconds = 0.0
        // At the start of the audio and after unscripted speech, the script may not continue
        // with the next line (an unsung verse, a skipped paragraph).
        var atSectionStart = true
        var guardCount = Int(duration / 0.5) + lines.count * 2 + 10

        while lineIndex < lines.count, position < duration - 0.3, guardCount > 0 {
            guardCount -= 1
            try Task.checkCancellation()
            forcedProgress(min(1, position / max(duration, 0.001)))

            // Never place script inside speech that is known not to be the script.
            if let barrier = barriers.first(where: { position >= $0.lowerBound - 0.3 && position < $0.upperBound }) {
                position = barrier.upperBound
                atSectionStart = true
                continue
            }
            // Lines without any tokens cannot be heard; leave them to be placed afterwards.
            if lineTokens[lineIndex].isEmpty { lineIndex += 1; continue }

            let nextBarrier = barriers.first(where: { $0.lowerBound > position })?.lowerBound
            let windowEnd = min(position + windowSeconds, nextBarrier ?? duration, duration)
            let isLastWindow = windowEnd >= duration - 0.001
            let endsAtBarrier = !isLastWindow && nextBarrier.map { windowEnd >= $0 } == true
            // Too little audio before the barrier to hold a line.
            if endsAtBarrier, windowEnd - position < 1.5 {
                position = windowEnd
                continue
            }

            var maxTokens = 110
            if acceptedSeconds > 20 {
                let tokensPerSecond = Double(acceptedTokens) / acceptedSeconds
                maxTokens = min(160, max(40, Int(tokensPerSecond * windowSeconds * 1.5)))
            }

            var window = try await decode(from: lineIndex, position: position, windowEnd: windowEnd, final: isLastWindow || endsAtBarrier, maxTokens: maxTokens)

            // Would the audio fit better if some lines were skipped? Only what was heard can tell.
            // The next line stays unless it sits badly and a later one both sits naturally and
            // is backed by the free transcription.
            if atSectionStart, heardWords.contains(where: { $0.start >= position && $0.end <= windowEnd }) {
                let baseline = agreement(window)
                if debug { print(String(format: "  section start at line %d: fits %@, agreement %.2f", lineIndex, window.fitsNaturally ? "yes" : "no", baseline)) }
                if !(window.fitsNaturally && baseline >= Self.skipMinimumAgreement) {
                    var candidate = lineIndex + 1
                    var tried = 0
                    while candidate < lines.count, tried < Self.skipCandidates {
                        defer { candidate += 1 }
                        guard !lineTokens[candidate].isEmpty else { continue }
                        tried += 1
                        try Task.checkCancellation()
                        let attempt = try await decode(from: candidate, position: position, windowEnd: windowEnd, final: isLastWindow || endsAtBarrier, maxTokens: maxTokens)
                        let score = agreement(attempt)
                        if debug { print(String(format: "  start at line %d instead: fits %@, agreement %.2f", candidate, attempt.fitsNaturally ? "yes" : "no", score)) }
                        if attempt.fitsNaturally, score >= Self.skipMinimumAgreement, score >= baseline + Self.skipMargin {
                            if debug { print("  skipping lines \(lineIndex)..<\(candidate): not heard here") }
                            lineIndex = candidate
                            window = attempt
                            break
                        }
                    }
                }
            }
            atSectionStart = false

            if let acceptedEnd = window.acceptedEnd {
                for item in window.placed {
                    result[item.line] = item.subtitle
                    paces[item.line] = item.pace
                }
                lineIndex = (window.placed.last?.line ?? lineIndex) + 1
                acceptedTokens += window.tokens
                acceptedSeconds += acceptedEnd
                position += max(0.5, acceptedEnd - 0.1)
            } else if endsAtBarrier {
                // Nothing fits before the unscripted speech; carry on after it.
                position = windowEnd
            } else if window.firstLineUnheard {
                // The window starts at this line and it still is not there: the audio does not
                // contain it (a skipped verse, say). Leave it untimed and try the next line here.
                if debug { print("  line \(lineIndex) not heard: \(lines[lineIndex])") }
                lineIndex += 1
            } else if isLastWindow {
                break
            } else if let firstTokenStart = window.firstTokenStart, firstTokenStart > 1.5 {
                // The next line starts late in this window; move the window up to it.
                position += min(firstTokenStart - 0.5, windowSeconds - 5)
            } else {
                position += 10
            }
        }
        forcedProgress(1)

        Self.review(&result, paces: paces, heard: heard)
        return Alignment(
            lines: Self.assemble(result, lines: lines, duration: duration),
            unscriptedRegions: barriers,
            heard: heard?.segments ?? []
        )
    }

    /// Transcribes one passage the script does not cover (see `Alignment.unscriptedRegions`)
    /// into subtitles, listening to it with the same care as a full transcription.
    public func transcribe(
        region: ClosedRange<Double>,
        samples: [Float],
        language: SpeechLanguage,
        maxWidth: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SubtitleLine] {
        let rate = AudioExtractor.sampleRate
        // A little audio on either side keeps the first and last words from being cut.
        let from = max(0, region.lowerBound - 0.5)
        let first = min(samples.count, Int(from * rate))
        let last = min(samples.count, Int((region.upperBound + 0.5) * rate))
        guard last > first else { return [] }
        let recognition = try await recognize(samples: Array(samples[first..<last]), language: language, progress: progress)
        return CaptionBuilder.transcribe(
            recognition, offset: from, within: region,
            maxWidth: maxWidth, traditionalChinese: language.prefersTraditionalChinese
        )
    }

    /// Marks lines whose timing deserves a look, and clears the mark where the free
    /// transcription independently confirms the line.
    static func review(_ lines: inout [SubtitleLine?], paces: [Double?], heard: Recognition?) {
        let known = paces.compactMap { $0 }.sorted()
        let typicalPace = known.isEmpty ? nil : known[known.count / 2]
        let words = heard?.words ?? []

        for index in lines.indices {
            guard var line = lines[index] else { continue }
            // Much slower than the rest: the line was stretched over something else.
            if let typicalPace, let pace = paces[index], pace > max(typicalPace * Self.stretchFactor, 0.3) {
                line.confidence = .partial
            }
            if !words.isEmpty {
                let match = CrossCheck.agreement(line: line.text, words: words, start: line.start, end: line.end)
                let share = match.total > 0 ? Double(match.matched) / Double(match.total) : 0
                if share >= 0.6, match.matched >= 3 {
                    line.confidence = line.confidence == .partial && isStretched(paces[index], typicalPace) ? .partial : .good
                }
            }
            lines[index] = line
        }
    }

    private static func isStretched(_ pace: Double?, _ typical: Double?) -> Bool {
        guard let pace, let typical else { return false }
        return pace > max(typical * stretchFactor, 0.3)
    }

    /// Lines this many times slower than the typical line are suspicious.
    static let stretchFactor = 3.0
    /// How many following lines to try as the start of a section.
    static let skipCandidates = 8
    static let skipMinimumAgreement = 0.2
    static let skipMargin = 0.1

    /// Fewer seconds per token than this cannot be real speech or singing.
    static let fastestSecondsPerToken = 0.06
    /// A single token lasting longer than this has swallowed silence or unrelated sound.
    static let longestTokenSeconds = 2.0

    /// Text as it would be spoken: spaces between CJK characters removed.
    static func speechText(_ line: String) -> String {
        let characters = Array(line)
        var text = ""
        for (index, character) in characters.enumerated() {
            if character == " " {
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                if !before.isASCII || !after.isASCII { continue }
            }
            text.append(character)
        }
        return text
    }

    /// Fills in lines that were never heard and makes the times safe to display.
    static func assemble(_ timed: [SubtitleLine?], lines: [String], duration: Double) -> [SubtitleLine] {
        var output: [SubtitleLine] = []
        var previousEnd = 0.0
        for (index, text) in lines.enumerated() {
            if var line = timed[index] {
                line.start = max(line.start, previousEnd)
                line.end = max(line.end, line.start)
                output.append(line)
                previousEnd = line.end
            } else {
                // Unheard lines are parked after the previous line with no duration, so they are
                // listed for review but never shown or exported until someone gives them a time.
                output.append(SubtitleLine(start: previousEnd, end: previousEnd, text: text, confidence: .interpolated))
            }
        }
        for index in output.indices where output[index].confidence != .interpolated {
            let nextStart = index + 1 < output.count ? output[index + 1].start : duration
            var end = min(output[index].end + 0.25, nextStart)
            if nextStart - end < 0.3 { end = nextStart }
            let minimumEnd = min(output[index].start + 0.5, max(nextStart, output[index].start))
            output[index].end = min(max(end, minimumEnd, output[index].start), max(duration, output[index].start))
        }
        return output
    }
}

/// Restricts decoding to the script's tokens, in order, and records how likely
/// the model itself found each script token (its confidence that the audio contains it).
final class ForcedTokenFilter: LogitsFiltering, @unchecked Sendable {
    private let endToken: Int
    private let noTimestampsToken: Int
    private var script: [Int] = []
    private var logProbabilities: [Float] = []
    private var finished = false
    private(set) var producedCount = 0

    init(endToken: Int, noTimestampsToken: Int) {
        self.endToken = endToken
        self.noTimestampsToken = noTimestampsToken
    }

    func begin(script: [Int]) {
        self.script = script
        logProbabilities = [Float](repeating: -.infinity, count: script.count)
        finished = false
        producedCount = 0
    }

    func meanProbability(_ range: Range<Int>) -> Double {
        guard !range.isEmpty else { return 0 }
        let values = range.map { Double(exp(logProbabilities[$0])) }
        return values.reduce(0, +) / Double(values.count)
    }

    func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        // Tokens after the prompt are the script tokens produced so far in this window.
        let promptEnd = tokens.lastIndex(of: noTimestampsToken) ?? (tokens.count - 1)
        let produced = tokens.count - 1 - promptEnd
        let vocabulary = logits.shape.last?.intValue ?? 0

        logits.withUnsafeMutableBufferPointer(ofType: FloatType.self) { pointer, strides in
            let stride = strides.last ?? 1
            var chosen = endToken
            if !finished, produced < script.count {
                let next = script[produced]
                // Log-probability of the script token among everything the model could have said.
                var maximum = -Float.infinity
                for i in 0..<vocabulary { maximum = max(maximum, Float(pointer[i * stride])) }
                var sum: Float = 0
                for i in 0..<vocabulary { sum += exp(Float(pointer[i * stride]) - maximum) }
                let nextLogit = Float(pointer[next * stride])
                logProbabilities[produced] = nextLogit - maximum - log(sum)

                // Always continue with the script. Letting the model stop when it "prefers" to
                // fails exactly where this matters: on audio it cannot transcribe by itself.
                chosen = next
                producedCount = max(producedCount, produced + 1)
            } else {
                finished = true
            }
            for i in 0..<vocabulary { pointer[i * stride] = -FloatType.infinity }
            pointer[chosen * stride] = 0
        }
        return logits
    }
}
