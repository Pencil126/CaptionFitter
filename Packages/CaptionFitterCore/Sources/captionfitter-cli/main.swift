import CaptionFitterCore
import Foundation

// A small command-line front end to the core library, for testing alignment without the app.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let usage = """
用法：
  captionfitter-cli models                              列出模型
  captionfitter-cli download <模型>                     下載模型
  captionfitter-cli delete <模型>                       刪除已下載的模型
  captionfitter-cli align <媒體檔> --script <逐字稿檔> [選項]   將逐字稿對齊成字幕
  captionfitter-cli transcribe <媒體檔> [選項]           無逐字稿，直接轉錄成字幕
  captionfitter-cli burn <影片檔> --srt <SRT> --out <MP4>      把字幕燒入影片
      [--height 480|720|1080] [--fps 30|60] [--shadow none|soft|strong] [--position 0…1]

選項：
  --model <模型>     預設使用第一個已下載的模型
  --lang <語系>      zh-Hant（預設）、zh-Hans、yue、en、ja、ko、auto…
  --auto-wrap <寬度> 逐字稿自動斷行（每行字數上限）；未指定則保留原本換行
  --lyrics           以歌詞規則清理逐字稿（刪製作名單、段落標記、LRC 時間碼）
  --out <檔案>       輸出 SRT 路徑，預設與媒體檔同名
  --words            另外印出辨識到的逐字時間
  --match            align 改用「先轉錄再比對文字」的舊做法
  --no-cross-check   align 不做自由轉錄的交叉檢查（較快，但逐字稿以外的講話可能被配上字幕）
  --fill-unscripted  align 把偵測到的「逐字稿以外的講話」自動轉錄並補成字幕
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
    guard let model = requested ?? downloaded.first?.id else { fail("尚未下載任何模型，請先執行 download。") }
    guard store.isDownloaded(model) else { fail("模型 \(model) 尚未下載。") }
    print("載入模型 \(model)…")
    return try await WhisperRecognizer(modelFolder: store.folder(for: model), supportFolder: store.baseFolder)
}

func recognize(_ media: URL, model: String?, language: SpeechLanguage) async throws -> (Recognition, Double) {
    let engine = try await recognizer(model: model)
    let duration = try await AudioExtractor.duration(of: media)
    let samples = try await AudioExtractor.samples(from: media)
    print(String(format: "音訊長度 %.1f 秒，辨識中…", duration))
    let started = Date()
    let recognition = try await engine.recognize(samples: samples, language: language) { _ in }
    print(String(format: "辨識完成，耗時 %.1f 秒（%.1f 倍速）", Date().timeIntervalSince(started), duration / max(Date().timeIntervalSince(started), 0.001)))
    return (recognition, duration)
}

func printSummary(_ lines: [SubtitleLine], duration: Double) {
    let report = AlignmentReport(lines: lines, mediaDuration: duration)
    print("共 \(report.totalLines) 行：對上 \(report.goodLines)、部分 \(report.partialLines)、內插 \(report.interpolatedLines)")
    for warning in report.warnings { print("⚠️ \(warning)") }
}

do {
    switch command {
    case "models":
        for model in await store.allModels() {
            let state: String
            switch model.state {
            case .downloaded: state = "已下載 " + formatter.string(fromByteCount: model.sizeOnDisk ?? 0)
            case .incomplete: state = "未完成"
            case .notDownloaded: state = "未下載"
            }
            let marks = (model.isDefaultForDevice ? " ★預設" : "") + (model.isRecommended ? " 建議" : "")
            print("\(model.id)  [\(state)]\(marks)")
        }
        print("儲存位置：\(store.baseFolder.path)")

    case "download":
        guard let model = arguments.first else { fail(usage) }
        let folder = try await store.download(model) { fraction in
            print(String(format: "\r下載中 %3d%%", Int(fraction * 100)), terminator: "")
            fflush(stdout)
        }
        print("")
        print("完成：\(folder.path)")

    case "delete":
        guard let model = arguments.first else { fail(usage) }
        try store.delete(model)
        print("已刪除 \(model)")

    case "align", "transcribe":
        let model = option("--model")
        let languageID = option("--lang") ?? SpeechLanguage.default.id
        let scriptPath = option("--script")
        let wrap = option("--auto-wrap").flatMap(Double.init)
        let out = option("--out")
        let asLyrics = flag("--lyrics")
        let showWords = flag("--words")
        guard let mediaPath = arguments.first else { fail(usage) }
        guard let language = SpeechLanguage.all.first(where: { $0.id == languageID }) else { fail("不支援的語系：\(languageID)") }

        let media = URL(fileURLWithPath: mediaPath)
        let forced = !flag("--match")
        if command == "align", forced {
            // Default: forced alignment (the model reads the script against the audio).
            guard let scriptPath else { fail("align 需要 --script") }
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
                print("第 \(round) 次：逐字稿以外的講話 \(regions.isEmpty ? "無" : regions.joined(separator: "、"))")
            }
            let alignment = try await engine.align(scriptLines: scriptLines, samples: samples, language: language, crossCheck: crossCheck) { _ in }
            print(String(format: "對齊完成，耗時 %.1f 秒", Date().timeIntervalSince(started)))
            var document = SubtitleDocument(lines: alignment.lines)
            for region in alignment.unscriptedRegions {
                print(String(format: "逐字稿以外的講話：%.1f–%.1f 秒", region.lowerBound, region.upperBound))
                guard fill else { continue }
                let fillStarted = Date()
                let added = try await engine.transcribe(region: region, samples: samples, language: language, maxWidth: wrap ?? 16) { _ in }
                document.insert(added)
                print(String(format: "  補上 %d 行，耗時 %.1f 秒", added.count, Date().timeIntervalSince(fillStarted)))
                for line in added { print(String(format: "  %7.2f %7.2f  %@", line.start, line.end, line.text)) }
            }
            let lines = document.lines
            let destination = out.map { URL(fileURLWithPath: $0) } ?? media.deletingPathExtension().appendingPathExtension("srt")
            try SRTWriter.write(lines, to: destination)
            printSummary(lines, duration: duration)
            print("已輸出：\(destination.path)")
            exit(0)
        }
        let (recognition, duration) = try await recognize(media, model: model, language: language)
        if showWords {
            for word in recognition.words { print(String(format: "%7.2f %7.2f  %@", word.start, word.end, word.text)) }
        }

        let lines: [SubtitleLine]
        if command == "align" {
            guard let scriptPath else { fail("align 需要 --script") }
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
        print("已輸出：\(destination.path)")

    case "burn":
        guard let srtPath = option("--srt"), let out = option("--out"), let mediaPath = arguments.first else { fail(usage) }
        let lines = SRTWriter.parse(try String(contentsOfFile: srtPath, encoding: .utf8))
        print("燒入 \(lines.count) 行字幕…")
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
        print("已輸出：\(out)")

    default:
        fail(usage)
    }
} catch {
    fail("錯誤：\(error.localizedDescription)")
}
