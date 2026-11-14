import CaptionFitterCore
import SwiftUI

/// The left column: pick the media, the language, the script, then align.
struct SetupPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(ModelManager.self) private var models
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        @Bindable var models = models

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("影片或音檔") { mediaSection }

                    section("辨識設定") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("語系")
                                Picker("語系", selection: $model.languageID) {
                                    ForEach(SpeechLanguage.all) { Text($0.displayName).tag($0.id) }
                                }
                                .labelsHidden()
                            }
                            GridRow {
                                Text("模型")
                                modelPicker
                            }
                        }
                        Text("選擇影片中實際說或唱的語言，辨識會更準確。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    section("逐字稿") {
                        Picker("逐字稿來源", selection: $model.source) {
                            ForEach(ScriptSource.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        switch model.source {
                        case .paste: pasteSection
                        case .transcribe: transcribeSection
                        case .lyrics: LyricsSearchSection()
                        }
                    }

                    if let report = model.report, report.hasWarnings {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()
            actionBar
                .padding(12)
        }
        .task { models.refreshLocal() }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    // MARK: Sections

    @ViewBuilder private var mediaSection: some View {
        if let url = model.mediaURL {
            HStack(spacing: 10) {
                Image(systemName: model.hasVideo ? "film" : "waveform")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if model.mediaDuration > 0 {
                        Text("長度 \(TimeText.duration(model.mediaDuration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("更換…") { model.chooseMedia() }
                    .disabled(model.isWorking)
            }
        } else {
            Button {
                model.chooseMedia()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down").font(.title)
                    Text("選擇檔案，或把檔案拖到視窗中")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var modelPicker: some View {
        @Bindable var models = models
        if models.downloadedModels.isEmpty {
            Button("下載語音模型…") {
                SettingsTab.models.select()
                openSettings()
            }
        } else {
            HStack {
                Picker("模型", selection: Binding(
                    get: { models.activeModelID ?? "" },
                    set: { models.defaultModelID = $0 }
                )) {
                    ForEach(models.downloadedModels) { Text($0.displayName).tag($0.id) }
                }
                .labelsHidden()
                Button {
                    SettingsTab.models.select()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("管理語音模型")
            }
        }
    }

    @ViewBuilder private var pasteSection: some View {
        @Bindable var model = model
        ScriptEditor(text: $model.pastedScript, placeholder: "在這裡貼上逐字稿…")
            .frame(minHeight: 200)

        Toggle("自動斷行", isOn: $model.autoWrap)
        if model.autoWrap {
            widthStepper
            Text("依標點與字數把整段文字切成字幕行。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("逐字稿的每一行會成為一行字幕。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !model.pastedScript.isEmpty {
            Text("共 \(model.scriptLines.count) 行字幕")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var transcribeSection: some View {
        Text("沒有逐字稿時，直接由語音模型聽寫出字幕。之後可在編輯器中修正錯字。")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        widthStepper
    }

    private var widthStepper: some View {
        @Bindable var model = model
        return Stepper(value: $model.maxLineWidth, in: 8...40, step: 1) {
            Text("每行最多 \(Int(model.maxLineWidth)) 個字")
        }
    }

    // MARK: Action bar

    @ViewBuilder private var actionBar: some View {
        if model.isWorking {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.workTitle).font(.callout)
                    if let progress = model.workProgress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                Button("取消") { model.cancelWork() }
            }
        } else {
            Button {
                model.align(using: models, undoManager: undoManager)
            } label: {
                Text(model.source == .transcribe ? "轉錄字幕" : "對齊字幕")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canAlign)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

/// A plain multi-line text box with a placeholder.
struct ScriptEditor: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary)
            }
    }
}

/// Search the open lyrics database and pick a version.
struct LyricsSearchSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("歌名")
                TextField("歌名", text: $model.trackName)
                    .onSubmit { model.searchLyrics() }
            }
            GridRow {
                Text("歌手")
                TextField("選填", text: $model.artistName)
                    .onSubmit { model.searchLyrics() }
            }
        }
        .textFieldStyle(.roundedBorder)

        HStack {
            Button("搜尋") { model.searchLyrics() }
                .disabled(model.trackName.trimmingCharacters(in: .whitespaces).isEmpty || model.isSearching)
            if model.isSearching { ProgressView().controlSize(.small) }
            Spacer()
            Text("資料來源：LRCLIB")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }

        if let message = model.searchMessage {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !model.searchResults.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.searchResults) { result in
                        resultRow(result)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 170)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }

            ScriptEditor(text: $model.lyricsText, placeholder: "選擇上方的版本後，歌詞會顯示在這裡")
                .frame(minHeight: 160)
            Text("可在對齊前修改。重複的段落唱幾次就要有幾次。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultRow(_ result: LyricsSearchResult) -> some View {
        let selected = result.id == model.selectedResultID
        return Button {
            model.selectResult(result.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.trackName).lineLimit(1)
                    Text([result.artistName, result.albumName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let duration = result.duration {
                        Text(TimeText.duration(duration)).monospacedDigit()
                        if model.mediaDuration > 0 {
                            let difference = duration - model.mediaDuration
                            Text(abs(difference) < 1 ? "長度相符" : String(format: "%+.0f 秒", difference))
                                .font(.caption)
                                .foregroundStyle(abs(difference) > 15 ? .red : abs(difference) > 5 ? .orange : .secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
