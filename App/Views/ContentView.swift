import CaptionFitterCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var showStyle = false

    var body: some View {
        @Bindable var model = model

        HSplitView {
            SetupPanel()
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)

            VSplitView {
                PlayerPanel()
                    .frame(minHeight: 220, idealHeight: 380)
                SubtitleEditor()
                    .frame(minHeight: 200)
            }
            .frame(minWidth: 520)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showStyle.toggle()
                } label: {
                    Label("Subtitle Style", systemImage: "textformat.size")
                }
                .popover(isPresented: $showStyle, arrowEdge: .bottom) {
                    StylePanel()
                }
                .help("Adjust how subtitles look in the preview and the exported video")

                Button {
                    model.showExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.document.lines.isEmpty || model.isWorking)
                .help("Export an SRT subtitle file, a video with subtitles, or both (⌘E)")
            }
        }
        .sheet(isPresented: $model.showExport) {
            ExportSheet()
                .environment(model)
        }
        .background {
            PlaybackKeys { key in
                guard model.mediaURL != nil else { return false }
                switch key {
                case .skipBack: model.skip(forward: false)
                case .skipForward: model.skip(forward: true)
                case .frameBack: model.stepFrame(forward: false)
                case .frameForward: model.stepFrame(forward: true)
                }
                return true
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.loadMedia(url) }
            }
            return true
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("No Speech Model Downloaded", isPresented: $model.needsModel) {
            Button("Manage Models") {
                SettingsTab.models.select()
                openSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Aligning subtitles needs a speech model. Download one in Settings first.")
        }
    }
}

/// Formatting shared by the player and the editor.
enum TimeText {
    /// `m:ss.cc`, or `h:mm:ss.cc` for long media.
    static func string(_ seconds: Double) -> String {
        let centis = Int((max(0, seconds) * 100).rounded())
        let (h, m, s, c) = (centis / 360_000, (centis / 6000) % 60, (centis / 100) % 60, centis % 100)
        return h > 0 ? String(format: "%d:%02d:%02d.%02d", h, m, s, c) : String(format: "%d:%02d.%02d", m, s, c)
    }

    /// Accepts `ss`, `m:ss` or `h:mm:ss`, each with an optional fraction.
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
