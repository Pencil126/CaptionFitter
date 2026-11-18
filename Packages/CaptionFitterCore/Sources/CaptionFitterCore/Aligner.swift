import Foundation
import WhisperKit

/// A spoken language the user can pick to improve recognition accuracy.
public struct SpeechLanguage: Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    /// Whisper language code; nil lets the model detect the language.
    public var code: String?
    /// Convert recognised text to Traditional Chinese (only affects auto-transcription).
    public var prefersTraditionalChinese: Bool

    public init(id: String, displayName: String, code: String?, prefersTraditionalChinese: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.code = code
        self.prefersTraditionalChinese = prefersTraditionalChinese
    }

    public static let all: [SpeechLanguage] = [
        SpeechLanguage(id: "zh-Hant", displayName: "中文（繁體）", code: "zh", prefersTraditionalChinese: true),
        SpeechLanguage(id: "zh-Hans", displayName: "中文（简体）", code: "zh"),
        SpeechLanguage(id: "yue", displayName: "粵語", code: "yue", prefersTraditionalChinese: true),
        SpeechLanguage(id: "en", displayName: "English", code: "en"),
        SpeechLanguage(id: "ja", displayName: "日本語", code: "ja"),
        SpeechLanguage(id: "ko", displayName: "한국어", code: "ko"),
        SpeechLanguage(id: "es", displayName: "Español", code: "es"),
        SpeechLanguage(id: "fr", displayName: "Français", code: "fr"),
        SpeechLanguage(id: "de", displayName: "Deutsch", code: "de"),
        SpeechLanguage(id: "auto", displayName: "Detect automatically", code: nil),
    ]

    public static let `default` = all[0]
}

public struct RecognizedSegment: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [TimedWord]
    /// How sure the model was of this text, 0...1 (mean probability of its words).
    public var confidence: Double

    public init(start: Double, end: Double, text: String, words: [TimedWord], confidence: Double = 1) {
        self.start = start
        self.end = end
        self.text = text
        self.words = words
        self.confidence = confidence
    }
}

public struct Recognition: Equatable, Sendable {
    public var segments: [RecognizedSegment]
    public var language: String

    public init(segments: [RecognizedSegment], language: String) {
        self.segments = segments
        self.language = language
    }

    public var words: [TimedWord] { segments.flatMap(\.words) }
}

/// The result of fitting a script to audio.
public struct Alignment: Equatable, Sendable {
    public var lines: [SubtitleLine]
    /// Passages of clear speech that are not in the script, and so have no subtitles.
    public var unscriptedRegions: [ClosedRange<Double>]
    /// What the model heard when listening freely, which the regions above were worked out
    /// from. Empty when the cross-check was off. Kept for diagnosing detection problems.
    public var heard: [RecognizedSegment]

    public init(lines: [SubtitleLine], unscriptedRegions: [ClosedRange<Double>] = [], heard: [RecognizedSegment] = []) {
        self.lines = lines
        self.unscriptedRegions = unscriptedRegions
        self.heard = heard
    }
}

/// Produces timed words from audio. Hidden behind a protocol so the alignment
/// strategy can be swapped without touching the rest of the app.
public protocol SpeechRecognizing: Sendable {
    func recognize(samples: [Float], language: SpeechLanguage, progress: @escaping @Sendable (Double) -> Void) async throws -> Recognition
}

public enum AlignerError: LocalizedError {
    case emptyScript
    case noSpeechFound

    public var errorDescription: String? {
        switch self {
        case .emptyScript: return "The transcript is empty."
        case .noSpeechFound: return "No voice was found in this file."
        }
    }
}

/// Speech recognition backed by a locally stored WhisperKit model.
public final class WhisperRecognizer: SpeechRecognizing, @unchecked Sendable {
    let whisperKit: WhisperKit

    /// - Parameters:
    ///   - modelFolder: Folder of an already downloaded model. Nothing is downloaded here except
    ///     the small tokenizer files, which are cached under `supportFolder`.
    public init(modelFolder: URL, supportFolder: URL) async throws {
        let config = WhisperKitConfig(
            downloadBase: supportFolder,
            modelFolder: modelFolder.path,
            tokenizerFolder: supportFolder,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        if let tokenizer = whisperKit.tokenizer {
            whisperKit.tokenizer = PerCharacterTokenizer(base: tokenizer)
        }
    }

    public func recognize(samples: [Float], language: SpeechLanguage, progress: @escaping @Sendable (Double) -> Void) async throws -> Recognition {
        try await recognize(samples: samples, language: language, retries: 5, progress: progress)
    }

    /// - Parameter retries: How often to retry a passage with more randomness when the result
    ///   looks poor. Zero gives the same output every time, with honest confidence values.
    func recognize(samples: [Float], language: SpeechLanguage, retries: Int, progress: @escaping @Sendable (Double) -> Void) async throws -> Recognition {
        let options = DecodingOptions(
            task: .transcribe,
            language: language.code,
            temperature: 0,
            temperatureFallbackCount: retries,
            usePrefillPrompt: true,
            detectLanguage: language.code == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let kit = whisperKit
        let poller = Task {
            while !Task.isCancelled {
                progress(min(max(kit.progress.fractionCompleted, 0), 1))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poller.cancel() }

        let cancelled = CancellationFlag()
        let results: [TranscriptionResult] = try await withTaskCancellationHandler {
            try await whisperKit.transcribe(audioArray: samples, decodeOptions: options) { _ in
                cancelled.value ? false : nil
            }
        } onCancel: {
            cancelled.value = true
        }
        try Task.checkCancellation()
        progress(1)

        var segments: [RecognizedSegment] = []
        for result in results {
            for segment in result.segments {
                let words = (segment.words ?? []).map {
                    TimedWord(text: $0.word, start: Double($0.start), end: Double($0.end))
                }
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let probabilities = (segment.words ?? []).map { Double($0.probability) }
                let confidence = probabilities.isEmpty
                    ? Double(exp(segment.avgLogprob))
                    : probabilities.reduce(0, +) / Double(probabilities.count)
                if ProcessInfo.processInfo.environment["CAPTIONFITTER_DEBUG"] != nil {
                    print(String(format: "free %7.2f-%7.2f  words=%.2f seg=%.2f nospeech=%.2f  %@", Double(segment.start), Double(segment.end), confidence, exp(segment.avgLogprob), segment.noSpeechProb, text))
                }
                segments.append(RecognizedSegment(
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: text,
                    // Fall back to the whole segment when the model returned no word timings.
                    words: words.isEmpty ? [TimedWord(text: text, start: Double(segment.start), end: Double(segment.end))] : words,
                    confidence: confidence
                ))
            }
        }
        segments.sort { $0.start < $1.start }
        return Recognition(segments: segments, language: results.first?.language ?? language.code ?? "")
    }
}

/// Makes word timings character-level for scripts written without spaces.
///
/// The stock tokenizer only does this when the text is detected as exactly "zh", "ja"…,
/// but the system detector reports Chinese as "zh-Hans"/"zh-Hant", so Chinese ends up
/// with one "word" per clause and the engine's long-word clean-up then distorts its timing.
private struct PerCharacterTokenizer: WhisperTokenizer {
    let base: any WhisperTokenizer

    var specialTokens: SpecialTokens { base.specialTokens }
    var allLanguageTokens: Set<Int> { base.allLanguageTokens }
    func encode(text: String) -> [Int] { base.encode(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }

    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let text = base.decode(tokens: tokenIds.filter { $0 < specialTokens.specialTokenBegin })
        guard text.unicodeScalars.contains(where: Self.isUnspacedScript) else {
            return base.splitToWordTokens(tokenIds: tokenIds)
        }
        // One entry per token, joining tokens that only form a character together.
        var words: [String] = []
        var wordTokens: [[Int]] = []
        var current: [Int] = []
        for token in tokenIds {
            current.append(token)
            let decoded = base.decode(tokens: current)
            if !decoded.contains("\u{FFFD}") {
                words.append(decoded)
                wordTokens.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            words.append(base.decode(tokens: current))
            wordTokens.append(current)
        }
        return (words, wordTokens)
    }

    /// Han, kana, Hangul is spaced so excluded; Thai, Lao and Burmese are unspaced.
    private static func isUnspacedScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true // CJK + kana
        case 0x0E00...0x0EFF, 0x1000...0x109F: return true // Thai, Lao, Burmese
        default: return false
        }
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}

/// Turns recognised speech into subtitles, with or without a known script.
public enum CaptionBuilder {
    /// Fits the given script lines onto the recognised speech.
    public static func align(scriptLines: [String], to recognition: Recognition, mediaDuration: Double?) throws -> [SubtitleLine] {
        let lines = scriptLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw AlignerError.emptyScript }
        guard !recognition.words.isEmpty else { throw AlignerError.noSpeechFound }
        return SequenceAligner.align(scriptLines: lines, words: recognition.words, mediaDuration: mediaDuration)
    }

    /// Uses the recognised speech itself as the subtitles.
    public static func transcribe(_ recognition: Recognition, maxWidth: Double, traditionalChinese: Bool, mediaDuration: Double?) throws -> [SubtitleLine] {
        guard !recognition.words.isEmpty else { throw AlignerError.noSpeechFound }
        var lines = recognition.segments.flatMap {
            ScriptSegmenter.segment($0.text, mode: .automatic(maxWidth: maxWidth))
        }
        if traditionalChinese {
            lines = lines.map(Self.toTraditionalChinese)
        }
        return SequenceAligner.align(scriptLines: lines, words: recognition.words, mediaDuration: mediaDuration)
    }

    /// Subtitles for the speech in one passage that the script does not cover.
    /// - Parameters:
    ///   - recognition: What was heard in an excerpt of the audio; its times count from `offset`.
    ///   - region: The passage to fill. Nothing is placed outside it.
    public static func transcribe(
        _ recognition: Recognition, offset: Double, within region: ClosedRange<Double>,
        maxWidth: Double, traditionalChinese: Bool
    ) -> [SubtitleLine] {
        guard let lines = try? transcribe(recognition, maxWidth: maxWidth, traditionalChinese: traditionalChinese, mediaDuration: nil) else { return [] }
        return lines.compactMap { line in
            guard line.confidence != .interpolated else { return nil }
            let start = max(line.start + offset, region.lowerBound)
            let end = min(line.end + offset, region.upperBound)
            guard end - start >= SubtitleDocument.minimumDuration else { return nil }
            return SubtitleLine(start: start, end: end, text: line.text, confidence: .transcribed)
        }
    }

    /// The model usually writes Chinese in Simplified characters with ASCII punctuation;
    /// convert both for Traditional Chinese subtitles.
    static func toTraditionalChinese(_ text: String) -> String {
        let converted = text.applyingTransform(StringTransform(rawValue: "Simplified-Traditional"), reverse: false) ?? text
        let punctuation: [Character: Character] = [",": "，", "?": "？", "!": "！", ":": "：", ";": "；"]
        let characters = Array(converted)
        var result = ""
        for (index, character) in characters.enumerated() {
            // Only swap punctuation that follows a non-ASCII character, leaving "3,000" or "a, b" alone.
            if let wide = punctuation[character], index > 0, !characters[index - 1].isASCII {
                result.append(wide)
            } else {
                result.append(character)
            }
        }
        return result
    }
}
