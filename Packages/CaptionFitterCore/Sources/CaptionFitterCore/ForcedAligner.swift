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
    public func align(
        scriptLines: [String],
        samples: [Float],
        language: SpeechLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SubtitleLine] {
        let lines = scriptLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw AlignerError.emptyScript }
        guard let tokenizer = whisperKit.tokenizer else { throw AlignerError.noSpeechFound }

        let sampleRate = AudioExtractor.sampleRate
        let duration = Double(samples.count) / sampleRate
        let windowSeconds = 30.0
        let special = tokenizer.specialTokens
        let debug = ProcessInfo.processInfo.environment["CAPTIONFITTER_DEBUG"] != nil

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

        var result = [SubtitleLine?](repeating: nil, count: lines.count)
        var lineIndex = 0
        var position = 0.0
        // How much script to offer per window: start generous, then follow the measured pace.
        var acceptedTokens = 0
        var acceptedSeconds = 0.0
        var guardCount = Int(duration / 0.5) + lines.count * 2 + 10

        while lineIndex < lines.count, position < duration - 0.3, guardCount > 0 {
            guardCount -= 1
            try Task.checkCancellation()
            progress(min(1, position / max(duration, 0.001)))

            // Lines without any tokens cannot be heard; leave them to be placed afterwards.
            if lineTokens[lineIndex].isEmpty { lineIndex += 1; continue }

            var maxTokensPerWindow = 110
            if acceptedSeconds > 20 {
                let tokensPerSecond = Double(acceptedTokens) / acceptedSeconds
                maxTokensPerWindow = min(160, max(40, Int(tokensPerSecond * windowSeconds * 1.5)))
            }

            // The script offered to this window: as many upcoming lines as fit.
            var windowLines: [Int] = []
            var windowTokens: [Int] = []
            var candidate = lineIndex
            while candidate < lines.count {
                let tokens = lineTokens[candidate]
                if !windowLines.isEmpty, windowTokens.count + tokens.count > maxTokensPerWindow { break }
                windowLines.append(candidate)
                windowTokens.append(contentsOf: tokens.prefix(maxTokensPerWindow))
                candidate += 1
            }

            let startSample = Int(position * sampleRate)
            let endSample = min(samples.count, startSample + Int(windowSeconds * sampleRate))
            let sliceSeconds = Double(endSample - startSample) / sampleRate
            let isLastWindow = endSample == samples.count

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
            let limit = isLastWindow ? sliceSeconds : sliceSeconds - 5
            var offset = 0
            var acceptedEnd: Double?
            var accepted = 0
            var firstLineUnheard = false
            for line in windowLines {
                let count = min(lineTokens[line].count, maxTokensPerWindow)
                guard offset + count <= produced else { break }
                var start = tokenTimes[offset].start
                var end = tokenTimes[offset + count - 1].end
                guard end <= limit else { break }
                // Too fast to be speech or singing: the line was squeezed in, not heard.
                let collapsed = (end - start) / Double(count) < Self.fastestSecondsPerToken
                if collapsed {
                    firstLineUnheard = accepted == 0
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
                result[line] = SubtitleLine(
                    start: position + start, end: position + end, text: lines[line],
                    confidence: trusted ? .good : .partial
                )
                if debug {
                    print(String(format: "  line %2d  %7.2f-%7.2f  p=%.2f pace=%.2f  %@", line, position + start, position + end, probability, pace, lines[line]))
                }
                acceptedEnd = tokenTimes[offset + count - 1].end
                accepted += 1
                offset += count
            }

            if debug {
                print(String(format: "window %.2f (+%.1fs): offered %d lines / %d tokens, produced %d, accepted %d lines", position, sliceSeconds, windowLines.count, windowTokens.count, produced, accepted))
            }

            if let acceptedEnd {
                lineIndex += accepted
                acceptedTokens += offset
                acceptedSeconds += acceptedEnd
                position += max(0.5, acceptedEnd - 0.1)
            } else if firstLineUnheard {
                // The window starts at this line and it still is not there: the audio does not
                // contain it (a skipped verse, say). Leave it untimed and try the next line here.
                if debug { print("  line \(lineIndex) not heard: \(lines[lineIndex])") }
                lineIndex += 1
            } else if isLastWindow {
                break
            } else if produced > 0, tokenTimes[0].start > 1.5 {
                // The next line starts late in this window; move the window up to it.
                position += min(tokenTimes[0].start - 0.5, windowSeconds - 5)
            } else {
                position += 10
            }
        }
        progress(1)

        return Self.assemble(result, lines: lines, duration: duration)
    }

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
