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
  captionfitter-cli align <媒體檔> --script <文稿檔> [選項]   將文稿對齊成字幕
  captionfitter-cli transcribe <媒體檔> [選項]           無文稿，直接轉錄成字幕
  captionfitter-cli burn <媒體檔> --srt-lines <SRT> --out <MP4>

選項：
  --model <模型>     預設使用第一個已下載的模型
  --lang <語系>      zh-Hant（預設）、zh-Hans、yue、en、ja、ko、auto…
  --auto-wrap <寬度> 文稿自動斷行（每行字數上限）；未指定則保留原本換行
  --lyrics           以歌詞規則清理文稿（刪製作名單、段落標記、LRC 時間碼）
  --out <檔案>       輸出 SRT 路徑，預設與媒體檔同名
  --words            另外印出辨識到的逐字時間
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

let store = ModelStore(baseFolder: ModelStore.defaultBaseFolder())
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

    default:
        fail(usage)
    }
} catch {
    fail("錯誤：\(error.localizedDescription)")
}
