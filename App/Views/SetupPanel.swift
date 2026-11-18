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
                    section("Video or Audio") { mediaSection }

                    section("Recognition") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Language")
                                Picker("Language", selection: $model.languageID) {
                                    ForEach(SpeechLanguage.all) { Text(CoreMessages.languageName($0)).tag($0.id) }
                                }
                                .labelsHidden()
                            }
                            GridRow {
                                Text("Model")
                                modelPicker
                            }
                        }
                        Text("Choose the language actually spoken or sung in the video for more accurate recognition.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    section("Transcript") {
                        Picker("Transcript Source", selection: $model.source) {
                            ForEach(ScriptSource.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .brandTint()

                        switch model.source {
                        case .paste: pasteSection
                        case .transcribe: transcribeSection
                        case .lyrics: LyricsSearchSection()
                        }
                    }

                    if let report = model.report, report.hasWarnings {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.warnings, id: \.self) { warning in
                                Label(CoreMessages.text(for: warning), systemImage: "exclamationmark.triangle.fill")
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

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
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
                        Text("Length \(TimeText.duration(model.mediaDuration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Change…") { model.chooseMedia() }
                    .disabled(model.isWorking)
            }
        } else {
            Button {
                model.chooseMedia()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down").font(.title)
                    Text("Choose a file, or drag one into the window")
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
            Button("Download a Speech Model…") {
                SettingsTab.models.select()
                openSettings()
            }
        } else {
            HStack {
                Picker("Model", selection: Binding(
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
                .help("Manage speech models")
            }
        }
    }

    @ViewBuilder private var pasteSection: some View {
        @Bindable var model = model
        ScriptEditor(text: $model.pastedScript, placeholder: "Paste the transcript here…")
            .frame(minHeight: 200)

        Toggle("Break Lines Automatically", isOn: $model.autoWrap)
            .brandTint()
        if model.autoWrap {
            widthStepper
            Text("Splits the text into subtitle lines by punctuation and length.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Each line of the transcript becomes one subtitle line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !model.pastedScript.isEmpty {
            Text("\(model.scriptLines.count) subtitle lines")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var transcribeSection: some View {
        Text("Without a transcript, the speech model writes the subtitles from what it hears. You can fix mistakes in the editor afterward.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        widthStepper
    }

    private var widthStepper: some View {
        @Bindable var model = model
        return Stepper(value: $model.maxLineWidth, in: 8...40, step: 1) {
            Text("Up to \(Int(model.maxLineWidth)) characters per line")
        }
    }

    // MARK: Action bar

    @ViewBuilder private var actionBar: some View {
        if model.isWorking {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.workTitle).font(.callout)
                    Group {
                        if let progress = model.workProgress {
                            ProgressView(value: progress)
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                    }
                    .brandTint()
                }
                Button("Cancel") { model.cancelWork() }
            }
        } else {
            Button {
                model.align(using: models, undoManager: undoManager)
            } label: {
                BrandButtonLabel(model.source == .transcribe ? LocalizedStringKey("Transcribe Subtitles") : "Align Subtitles")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .brandTint()
            .disabled(!model.canAlign)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

/// A plain multi-line text box with a placeholder.
struct ScriptEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey

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
                Text("Song")
                TextField("Song", text: $model.trackName)
                    .onSubmit { model.searchLyrics() }
            }
            GridRow {
                Text("Artist")
                TextField("Optional", text: $model.artistName)
                    .onSubmit { model.searchLyrics() }
            }
        }
        .textFieldStyle(.roundedBorder)

        HStack {
            Button("Search") { model.searchLyrics() }
                .disabled(model.trackName.trimmingCharacters(in: .whitespaces).isEmpty || model.isSearching)
            if model.isSearching { ProgressView().controlSize(.small) }
            Spacer()
            Text("Source: LRCLIB")
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

            ScriptEditor(text: $model.lyricsText, placeholder: "Choose a version above and its lyrics appear here")
                .frame(minHeight: 160)
            Text("You can edit them before aligning. Write out a repeated section as many times as it's sung.")
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
                    .foregroundStyle(selected ? Color.brandGlyph : .secondary)
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
                            Group {
                                if abs(difference) < 1 {
                                    Text("Same length")
                                } else {
                                    Text("\(String(format: "%+.0f", difference)) s", comment: "How much longer or shorter the lyrics are, e.g. +3 s")
                                }
                            }
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
