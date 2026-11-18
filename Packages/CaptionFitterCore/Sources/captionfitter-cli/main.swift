import CaptionFitterCore
import Foundation

// A small command-line front end to the core library, for testing alignment without the app.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let usage = """
Usage:
  captionfitter-cli models                              List models
  captionfitter-cli download <model>                    Download a model
  captionfitter-cli delete <model>                      Delete a downloaded model
  captionfitter-cli align <media> --script <transcript> [options]   Align a transcript into subtitles
  captionfitter-cli transcribe <media> [options]         Transcribe into subtitles without a transcript
  captionfitter-cli burn <video> --srt <SRT> --out <MP4>       Burn subtitles into a video
      [--height 480|720|1080] [--fps 30|60] [--shadow none|soft|strong] [--position 0…1]

Options:
  --model <model>    Defaults to the first downloaded model
  --lang <language>  zh-Hant (default), zh-Hans, yue, en, ja, ko, auto…
  --auto-wrap <width> Break the transcript into lines automatically (max characters per line); otherwise keep its line breaks
  --lyrics           Clean the transcript as lyrics (drop credits, section labels, LRC timestamps)
  --out <file>       SRT output path; defaults to the media file's name
  --words            Also print the recognized word timings
  --match            For align, use the older transcribe-then-match approach
  --no-cross-check   For align, skip the free-transcription cross-check (faster, but speech outside the transcript may get subtitles)
  --fill-unscripted  For align, transcribe detected speech outside the transcript and add it as subtitles
"""

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
arguments.removeFirst()

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

// CAPTIONFITTER_MODELS points the tool at another model folder, e.g. the app's sandbox container.
let store = ModelStore(baseFolder: ProcessInfo.processInfo.environment["CAPTIONFITTER_MODELS"].map { URL(fileURLWithPath: $0) } ?? ModelStore.defaultBaseFolder())
let formatter = ByteCountFormatter()

func recognizer(model requested: String?) async throws -> WhisperRecognizer {
    let downloaded = store.localModels().filter { $0.state == .downloaded }
    guard let model = requested ?? downloaded.first?.id else { fail("No model downloaded yet. Run download first.") }
    guard store.isDownloaded(model) else { fail("Model \(model) is not downloaded.") }
    print("Loading model \(model)…")
    return try await WhisperRecognizer(modelFolder: store.folder(for: model), supportFolder: store.baseFolder)
}

func recognize(_ media: URL, model: String?, language: SpeechLanguage) async throws -> (Recognition, Double) {
    let engine = try await recognizer(model: model)
    let duration = try await AudioExtractor.duration(of: media)
    let samples = try await AudioExtractor.samples(from: media)
    print(String(format: "Audio is %.1f s long, recognizing…", duration))
    let started = Date()
    let recognition = try await engine.recognize(samples: samples, language: language) { _ in }
    print(String(format: "Recognized in %.1f s (%.1f× real time)", Date().timeIntervalSince(started), duration / max(Date().timeIntervalSince(started), 0.001)))
    return (recognition, duration)
}

func describe(_ warning: AlignmentReport.Warning) -> String {
    switch warning {
    case let .mostLinesUnmatched(doubtful, total):
        return "Most lines (\(doubtful)/\(total)) don't match the audio. The transcript may not match the video, or the language may be wrong."
    case let .someLinesUncertain(doubtful, total):
        return "\(doubtful)/\(total) lines have uncertain timing."
    case let .endsEarly(percent):
        return "The subtitles end at \(percent)% of the media. The transcript may be incomplete."
    case let .lyricsLengthMismatch(seconds, likelyDifferentVersion):
        return "The lyrics differ in length from the media by \(seconds) s" + (likelyDifferentVersion ? ", probably a different version." : ".")
    }
}

func printSummary(_ lines: [SubtitleLine], duration: Double) {
    let report = AlignmentReport(lines: lines, mediaDuration: duration)
    print("\(report.totalLines) lines: \(report.goodLines) matched, \(report.partialLines) partial, \(report.interpolatedLines) interpolated")
    for warning in report.warnings { print("⚠️ \(describe(warning))") }
}

do {
    switch command {
    case "models":
        for model in await store.allModels() {
            let state: String
            switch model.state {
            case .downloaded: state = "downloaded " + formatter.string(fromByteCount: model.sizeOnDisk ?? 0)
            case .incomplete: state = "incomplete"
            case .notDownloaded: state = "not downloaded"
            }
            let marks = (model.isDefaultForDevice ? " ★default" : "") + (model.isRecommended ? " recommended" : "")
            print("\(model.id)  [\(state)]\(marks)")
        }
        print("Stored in: \(store.baseFolder.path)")

    case "download":
        guard let model = arguments.first else { fail(usage) }
        let folder = try await store.download(model) { fraction in
            print(String(format: "\rDownloading %3d%%", Int(fraction * 100)), terminator: "")
            fflush(stdout)
        }
        print("")
        print("Done: \(folder.path)")

    case "delete":
        guard let model = arguments.first else { fail(usage) }
        try store.delete(model)
        print("Deleted \(model)")

    case "align", "transcribe":
        let model = option("--model")
        let languageID = option("--lang") ?? SpeechLanguage.default.id
        let scriptPath = option("--script")
        let wrap = option("--auto-wrap").flatMap(Double.init)
        let out = option("--out")
        let asLyrics = flag("--lyrics")
        let showWords = flag("--words")
        guard let mediaPath = arguments.first else { fail(usage) }
        guard let language = SpeechLanguage.all.first(where: { $0.id == languageID }) else { fail("Unsupported language: \(languageID)") }

        let media = URL(fileURLWithPath: mediaPath)
        let forced = !flag("--match")
        if command == "align", forced {
            // Default: forced alignment (the model reads the script against the audio).
            guard let scriptPath else { fail("align needs --script") }
            let script = try String(contentsOfFile: scriptPath, encoding: .utf8)
            let scriptLines = asLyrics
                ? LyricsCleaner.clean(script)
                : ScriptSegmenter.segment(script, mode: wrap.map { .automatic(maxWidth: $0) } ?? .keepLineBreaks)
            let engine = try await recognizer(model: model)
            let duration = try await AudioExtractor.duration(of: media)
            let samples = try await AudioExtractor.samples(from: media)
            let started = Date()
            let fill = flag("--fill-unscripted")
            let crossCheck = !flag("--no-cross-check")
            // Diagnostic: align again in the same process, to compare a first run with later ones.
            for round in 1..<(option("--repeat").flatMap(Int.init) ?? 1) {
                let extra = try await engine.align(scriptLines: scriptLines, samples: samples, language: language, crossCheck: crossCheck) { _ in }
                let regions = extra.unscriptedRegions.map { String(format: "%.1f–%.1f", $0.lowerBound, $0.upperBound) }
                print("Round \(round): speech outside the transcript: \(regions.isEmpty ? "none" : regions.joined(separator: ", "))")
            }
            let alignment = try await engine.align(scriptLines: scriptLines, samples: samples, language: language, crossCheck: crossCheck) { _ in }
            print(String(format: "Aligned in %.1f s", Date().timeIntervalSince(started)))
            var document = SubtitleDocument(lines: alignment.lines)
            for region in alignment.unscriptedRegions {
                print(String(format: "Speech outside the transcript: %.1f–%.1f s", region.lowerBound, region.upperBound))
                guard fill else { continue }
                let fillStarted = Date()
                let added = try await engine.transcribe(region: region, samples: samples, language: language, maxWidth: wrap ?? 16) { _ in }
                document.insert(added)
                print(String(format: "  Added %d lines in %.1f s", added.count, Date().timeIntervalSince(fillStarted)))
                for line in added { print(String(format: "  %7.2f %7.2f  %@", line.start, line.end, line.text)) }
            }
            let lines = document.lines
            let destination = out.map { URL(fileURLWithPath: $0) } ?? media.deletingPathExtension().appendingPathExtension("srt")
            try SRTWriter.write(lines, to: destination)
            printSummary(lines, duration: duration)
            print("Saved: \(destination.path)")
            exit(0)
        }
        let (recognition, duration) = try await recognize(media, model: model, language: language)
        if showWords {
            for word in recognition.words { print(String(format: "%7.2f %7.2f  %@", word.start, word.end, word.text)) }
        }

        let lines: [SubtitleLine]
        if command == "align" {
            guard let scriptPath else { fail("align needs --script") }
            let script = try String(contentsOfFile: scriptPath, encoding: .utf8)
            let scriptLines: [String]
            if asLyrics {
                scriptLines = LyricsCleaner.clean(script)
            } else {
                scriptLines = ScriptSegmenter.segment(script, mode: wrap.map { .automatic(maxWidth: $0) } ?? .keepLineBreaks)
            }
            lines = try CaptionBuilder.align(scriptLines: scriptLines, to: recognition, mediaDuration: duration)
        } else {
            lines = try CaptionBuilder.transcribe(recognition, maxWidth: wrap ?? 18, traditionalChinese: language.prefersTraditionalChinese, mediaDuration: duration)
        }

        let destination = out.map { URL(fileURLWithPath: $0) } ?? media.deletingPathExtension().appendingPathExtension("srt")
        try SRTWriter.write(lines, to: destination)
        printSummary(lines, duration: duration)
        print("Saved: \(destination.path)")

    case "burn":
        guard let srtPath = option("--srt"), let out = option("--out"), let mediaPath = arguments.first else { fail(usage) }
        let lines = SRTWriter.parse(try String(contentsOfFile: srtPath, encoding: .utf8))
        print("Burning in \(lines.count) subtitle lines…")
        var style = SubtitleStyle()
        if let name = option("--shadow"), let shadow = SubtitleStyle.Shadow(rawValue: name) { style.shadow = shadow }
        if let position = option("--position").flatMap(Double.init) { style.verticalPosition = position }
        let options = VideoExportOptions(
            resolution: option("--height").flatMap(Int.init).flatMap(VideoExportOptions.Resolution.init) ?? .original,
            frameRate: option("--fps").flatMap(Int.init).flatMap(VideoExportOptions.FrameRate.init) ?? .original
        )
        try await SubtitleBurner.burn(
            lines: lines, style: style,
            source: URL(fileURLWithPath: mediaPath), destination: URL(fileURLWithPath: out), options: options
        ) { _ in }
        print("Saved: \(out)")

    default:
        fail(usage)
    }
} catch {
    fail("Error: \(error.localizedDescription)")
}
