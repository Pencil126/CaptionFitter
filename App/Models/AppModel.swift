import AppKit
import AVFoundation
import CaptionFitterCore
import Observation
import UniformTypeIdentifiers

enum ScriptSource: String, CaseIterable, Identifiable {
    case paste, transcribe, lyrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: return "貼上逐字稿"
        case .transcribe: return "自動轉錄"
        case .lyrics: return "搜尋歌詞"
        }
    }
}

/// What the Export sheet can write.
enum ExportContent: String, CaseIterable, Identifiable {
    case srt, video, both

    var id: String { rawValue }
}

/// A passage of speech that is not in the script and has no subtitles yet.
struct UnscriptedRegion: Identifiable, Equatable {
    let id = UUID()
    var range: ClosedRange<Double>
}

/// State for the main window: the media, the script, the resulting subtitles and long-running work.
@MainActor
@Observable
final class AppModel {
    // MARK: Media

    private(set) var mediaURL: URL?
    private(set) var mediaDuration: Double = 0
    private(set) var hasVideo = false
    /// Picture size and frame rate; nil for audio-only media.
    private(set) var videoInfo: VideoInfo?
    let player = AVPlayer()
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    // MARK: Script

    var languageID: String {
        didSet { UserDefaults.standard.set(languageID, forKey: "languageID") }
    }
    var source: ScriptSource = .paste
    var pastedScript = ""
    var autoWrap = false
    var maxLineWidth: Double = 16

    var trackName = ""
    var artistName = ""
    private(set) var searchResults: [LyricsSearchResult] = []
    private(set) var selectedResultID: Int?
    private(set) var isSearching = false
    private(set) var searchMessage: String?
    /// The cleaned text of the chosen search result; editable before aligning.
    var lyricsText = ""

    // MARK: Subtitles

    private(set) var document = SubtitleDocument()
    var selection: SubtitleLine.ID?
    private(set) var report: AlignmentReport?
    /// Speech found while aligning that the script does not cover.
    private(set) var unscriptedRegions: [UnscriptedRegion] = []
    /// The region being transcribed right now.
    private(set) var fillingRegionID: UnscriptedRegion.ID?
    var followPlayback = true
    var style: SubtitleStyle {
        didSet {
            if let data = try? JSONEncoder().encode(style) { UserDefaults.standard.set(data, forKey: "subtitleStyle") }
        }
    }

    // MARK: Work

    private(set) var isWorking = false
    private(set) var workTitle = ""
    /// nil while the amount of work is unknown.
    private(set) var workProgress: Double?
    var errorMessage: String?
    var showExport = false
    /// Set when aligning was attempted without a downloaded model.
    var needsModel = false

    private var workTask: Task<Void, Never>?
    private var recognizer: (modelID: String, engine: WhisperRecognizer)?
    private var lastCoalesceKey: String?
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?

    init() {
        languageID = UserDefaults.standard.string(forKey: "languageID") ?? SpeechLanguage.default.id
        if let data = UserDefaults.standard.data(forKey: "subtitleStyle"),
           let saved = try? JSONDecoder().decode(SubtitleStyle.self, from: data) {
            style = saved
        } else {
            style = SubtitleStyle()
        }

        FontCatalog.preload()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds.isFinite else { return }
                self.currentTime = time.seconds
            }
        }
        rateObservation = player.observe(\.rate) { [weak self] player, _ in
            let playing = player.rate != 0
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    var language: SpeechLanguage {
        SpeechLanguage.all.first { $0.id == languageID } ?? .default
    }

    var selectedLine: SubtitleLine? {
        selection.flatMap { id in document.lines.first { $0.id == id } }
    }

    /// Unscripted passages that still have no subtitles. A passage drops out once it has
    /// lines (and comes back if they are removed or undone).
    var openRegions: [UnscriptedRegion] {
        unscriptedRegions.filter { !document.hasLines(in: $0.range) }
    }

    /// The subtitle under the playhead.
    var currentLine: SubtitleLine? {
        document.line(at: currentTime)
    }

    // MARK: - Media

    func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio]
        panel.allowsMultipleSelection = false
        panel.message = "選擇要加上字幕的影片或音檔"
        if panel.runModal() == .OK, let url = panel.url {
            loadMedia(url)
        }
    }

    func loadMedia(_ url: URL) {
        guard !isWorking else { return }
        player.pause()
        mediaURL = url
        mediaDuration = 0
        hasVideo = false
        videoInfo = nil
        document = SubtitleDocument()
        selection = nil
        report = nil
        unscriptedRegions = []
        errorMessage = nil
        lastCoalesceKey = nil
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        currentTime = 0

        if trackName.isEmpty {
            trackName = url.deletingPathExtension().lastPathComponent
        }
        Task {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            let info = await VideoInfo.load(from: url)
            guard mediaURL == url else { return }
            mediaDuration = duration.isFinite ? duration : 0
            hasVideo = !videoTracks.isEmpty
            videoInfo = info
        }
    }

    func togglePlayback() {
        guard mediaURL != nil else { return }
        if isPlaying {
            player.pause()
        } else {
            if mediaDuration > 0, currentTime >= mediaDuration - 0.05 { seek(to: 0) }
            player.play()
        }
    }

    func seek(to time: Double) {
        let clamped = min(max(0, time), max(mediaDuration, 0))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seconds the skip buttons and ⇧← / ⇧→ move by; set in Settings.
    static let skipSecondsKey = "skipSeconds"
    static let skipSecondsRange = 1...15
    static var skipSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: skipSecondsKey)
        return stored == 0 ? 5 : min(max(stored, skipSecondsRange.lowerBound), skipSecondsRange.upperBound)
    }

    func skip(forward: Bool) {
        guard mediaURL != nil else { return }
        seek(to: currentTime + Double(forward ? Self.skipSeconds : -Self.skipSeconds))
    }

    /// Moves one video frame (1/30 s for audio) and stops there.
    func stepFrame(forward: Bool) {
        guard mediaURL != nil else { return }
        player.pause()
        let rate = videoInfo.map(\.frameRate).flatMap { $0 > 1 ? $0 : nil } ?? 30
        seek(to: currentTime + (forward ? 1 : -1) / rate)
    }

    // MARK: - Lyrics search

    func searchLyrics() {
        let track = trackName.trimmingCharacters(in: .whitespaces)
        guard !track.isEmpty, !isSearching else { return }
        isSearching = true
        searchMessage = nil
        let artist = artistName
        let duration = mediaDuration > 0 ? mediaDuration : nil
        Task {
            defer { isSearching = false }
            do {
                let found = try await LRCLIBClient().search(track: track, artist: artist)
                searchResults = LRCLIBClient.rank(found, mediaDuration: duration)
                if searchResults.isEmpty {
                    searchMessage = "找不到符合的歌詞。可以改用其他關鍵字，或改用「貼上逐字稿」。"
                    selectedResultID = nil
                } else if let first = searchResults.first {
                    // Preselect the version closest in length; the user can pick another.
                    selectResult(first.id)
                }
            } catch {
                searchResults = []
                searchMessage = "搜尋失敗：\(error.localizedDescription)"
            }
        }
    }

    func selectResult(_ id: Int) {
        guard let result = searchResults.first(where: { $0.id == id }) else { return }
        selectedResultID = id
        lyricsText = LyricsCleaner.clean(result.lyricsText ?? "").joined(separator: "\n")
    }

    private var selectedResult: LyricsSearchResult? {
        searchResults.first { $0.id == selectedResultID }
    }

    // MARK: - Aligning

    var canAlign: Bool {
        guard mediaURL != nil, !isWorking else { return false }
        switch source {
        case .paste: return !pastedScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .transcribe: return true
        case .lyrics: return !lyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The subtitle lines the current script would produce.
    var scriptLines: [String] {
        switch source {
        case .paste:
            // Pasted LRC keeps its line structure; its time tags are dropped and re-aligned.
            if LyricsCleaner.isLRC(pastedScript) {
                return LyricsCleaner.parseLRC(pastedScript).map(\.text).filter { !$0.isEmpty }
            }
            return ScriptSegmenter.segment(pastedScript, mode: autoWrap ? .automatic(maxWidth: maxLineWidth) : .keepLineBreaks)
        case .lyrics:
            return ScriptSegmenter.segment(lyricsText, mode: .keepLineBreaks)
        case .transcribe:
            return []
        }
    }

    func align(using models: ModelManager, undoManager: UndoManager?) {
        guard canAlign, let url = mediaURL else { return }
        guard let modelID = models.activeModelID else {
            needsModel = true
            return
        }
        let store = models.store
        let language = language
        let source = source
        let lines = scriptLines
        let maxWidth = maxLineWidth
        let scriptDuration = source == .lyrics ? selectedResult?.duration : nil
        let previous = document

        player.pause()
        isWorking = true
        errorMessage = nil
        workProgress = nil

        workTask = Task {
            defer {
                isWorking = false
                workTask = nil
            }
            do {
                let engine = try await loadEngine(modelID, from: store)
                try Task.checkCancellation()

                workTitle = "讀取音訊…"
                let samples = try await Task.detached { try await AudioExtractor.samples(from: url) }.value
                try Task.checkCancellation()

                let duration = mediaDuration > 0 ? mediaDuration : nil
                let reportProgress: @Sendable (Double) -> Void = { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isWorking else { return }
                        self.workProgress = fraction
                    }
                }
                workProgress = 0
                let result: [SubtitleLine]
                var regions: [ClosedRange<Double>] = []
                switch source {
                case .transcribe:
                    workTitle = "辨識語音…"
                    let recognition = try await engine.recognize(samples: samples, language: language, progress: reportProgress)
                    result = try CaptionBuilder.transcribe(recognition, maxWidth: maxWidth, traditionalChinese: language.prefersTraditionalChinese, mediaDuration: duration)
                case .paste, .lyrics:
                    // The model reads the script against the audio, which also works for
                    // singing and noisy recordings where free transcription gets the words wrong.
                    workTitle = "對齊字幕…"
                    let alignment = try await engine.align(scriptLines: lines, samples: samples, language: language, progress: reportProgress)
                    result = alignment.lines
                    regions = alignment.unscriptedRegions
                }
                try Task.checkCancellation()

                document = SubtitleDocument(lines: result)
                unscriptedRegions = regions.map { UnscriptedRegion(range: $0) }
                selection = nil
                lastCoalesceKey = nil
                report = AlignmentReport(lines: result, mediaDuration: duration, scriptDuration: scriptDuration)
                if !previous.lines.isEmpty {
                    registerUndo(previous, name: "對齊字幕", undoManager: undoManager)
                }
            } catch is CancellationError {
                // Cancelled by the user; keep whatever was there before.
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelWork() {
        workTask?.cancel()
    }

    private func loadEngine(_ modelID: String, from store: ModelStore) async throws -> WhisperRecognizer {
        if let recognizer, recognizer.modelID == modelID { return recognizer.engine }
        workTitle = "載入語音模型…"
        recognizer = nil
        let engine = try await WhisperRecognizer(modelFolder: store.folder(for: modelID), supportFolder: store.baseFolder)
        recognizer = (modelID, engine)
        return engine
    }

    // MARK: - Speech outside the script

    /// Transcribes an unscripted passage and adds the result as subtitles.
    func fillRegion(_ region: UnscriptedRegion, using models: ModelManager, undoManager: UndoManager?) {
        guard !isWorking, let url = mediaURL else { return }
        guard let modelID = models.activeModelID else {
            needsModel = true
            return
        }
        let store = models.store
        let language = language
        let maxWidth = maxLineWidth

        player.pause()
        isWorking = true
        fillingRegionID = region.id
        errorMessage = nil
        workProgress = nil

        workTask = Task {
            defer {
                isWorking = false
                fillingRegionID = nil
                workTask = nil
            }
            do {
                let engine = try await loadEngine(modelID, from: store)
                try Task.checkCancellation()

                workTitle = "聽寫這一段講話…"
                let samples = try await Task.detached { try await AudioExtractor.samples(from: url) }.value
                try Task.checkCancellation()
                workProgress = 0
                let lines = try await engine.transcribe(region: region.range, samples: samples, language: language, maxWidth: maxWidth) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isWorking else { return }
                        self.workProgress = fraction
                    }
                }
                try Task.checkCancellation()

                guard !lines.isEmpty else {
                    errorMessage = "這一段沒有聽寫出文字，可以改用「新增」手動加上字幕。"
                    return
                }
                edit("補上字幕", undoManager: undoManager) { $0.insert(lines) }
            } catch is CancellationError {
                // Cancelled by the user; nothing was added.
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    /// Hides the hint for a passage the user does not want subtitles for.
    func dismissRegion(_ id: UnscriptedRegion.ID) {
        unscriptedRegions.removeAll { $0.id == id }
    }

    // MARK: - Editing

    /// Applies a change to the subtitles and makes it undoable. Changes sharing a
    /// `coalesceKey` (typing in one line) collapse into a single undo step.
    func edit(_ name: String, undoManager: UndoManager?, coalesceKey: String? = nil, _ change: (inout SubtitleDocument) -> Void) {
        let before = document
        change(&document)
        guard before != document else { return }
        if let coalesceKey, coalesceKey == lastCoalesceKey { return }
        lastCoalesceKey = coalesceKey
        registerUndo(before, name: name, undoManager: undoManager)
    }

    private func registerUndo(_ snapshot: SubtitleDocument, name: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let current = model.document
                model.document = snapshot
                model.lastCoalesceKey = nil
                if let selection = model.selection, model.document.index(of: selection) == nil {
                    model.selection = nil
                }
                model.registerUndo(current, name: name, undoManager: undoManager)
            }
        }
        undoManager.setActionName(name)
    }

    func addLine(undoManager: UndoManager?) {
        var newID: SubtitleLine.ID?
        edit("新增字幕", undoManager: undoManager) { document in
            if let selection {
                newID = document.insertLine(after: selection)
            } else {
                newID = document.insertLine(after: nil, at: currentTime)
            }
        }
        if let newID { selection = newID }
    }

    func deleteSelected(undoManager: UndoManager?) {
        guard let id = selection, let index = document.index(of: id) else { return }
        edit("刪除字幕", undoManager: undoManager) { $0.delete(id) }
        let lines = document.lines
        selection = lines.isEmpty ? nil : lines[min(index, lines.count - 1)].id
    }

    /// Splits the selected line at the playhead when it is inside the line, otherwise in the middle.
    func splitSelected(undoManager: UndoManager?) {
        guard let id = selection else { return }
        let time = currentTime
        edit("分割字幕", undoManager: undoManager) { $0.split(id, time: time) }
    }

    func mergeSelectedWithNext(undoManager: UndoManager?) {
        guard let id = selection else { return }
        edit("合併字幕", undoManager: undoManager) { $0.mergeWithNext(id) }
    }

    // MARK: - Export

    /// Asks where to save, then writes the subtitle file, the video, or both.
    func export(_ content: ExportContent, options: VideoExportOptions) {
        guard !document.lines.isEmpty, !isWorking, let mediaURL else { return }
        let wantsVideo = content != .srt && hasVideo
        let baseName = mediaURL.deletingPathExtension().lastPathComponent
        var directory = mediaURL.deletingLastPathComponent()

        // Collect every destination first, so cancelling halfway writes nothing.
        var subtitleURL: URL?
        if content != .video || !hasVideo {
            let type = UTType(filenameExtension: "srt") ?? .plainText
            guard let url = askDestination(type: type, name: baseName + ".srt", directory: directory, title: "儲存 SRT 字幕檔") else { return }
            subtitleURL = url
            directory = url.deletingLastPathComponent()
        }
        var videoURL: URL?
        if wantsVideo {
            guard let url = askDestination(type: .mpeg4Movie, name: baseName + "-字幕.mp4", directory: directory, title: "儲存含字幕的影片") else { return }
            guard url.standardizedFileURL != mediaURL.standardizedFileURL else {
                errorMessage = "輸出檔不能與原始影片相同。"
                return
            }
            videoURL = url
        }

        if let subtitleURL {
            do {
                try SRTWriter.write(document.lines, to: subtitleURL)
            } catch {
                errorMessage = "無法儲存 SRT：\(error.localizedDescription)"
                return
            }
        }
        guard let videoURL else {
            if let subtitleURL { NSWorkspace.shared.activateFileViewerSelecting([subtitleURL]) }
            return
        }

        let lines = document.lines
        let style = style
        player.pause()
        isWorking = true
        errorMessage = nil
        workTitle = "輸出影片…"
        workProgress = 0

        workTask = Task {
            defer {
                isWorking = false
                workTask = nil
            }
            do {
                try await SubtitleBurner.burn(lines: lines, style: style, source: mediaURL, destination: videoURL, options: options) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isWorking else { return }
                        self.workProgress = fraction
                    }
                }
                NSWorkspace.shared.activateFileViewerSelecting([videoURL])
            } catch is CancellationError {
                // Cancelled by the user; the partial file has been removed.
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    private func askDestination(type: UTType, name: String, directory: URL, title: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = title
        panel.allowedContentTypes = [type]
        panel.directoryURL = directory
        panel.nameFieldStringValue = name
        return panel.runModal() == .OK ? panel.url : nil
    }
}
