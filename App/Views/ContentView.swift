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
                    Label("字幕樣式", systemImage: "textformat.size")
                }
                .popover(isPresented: $showStyle, arrowEdge: .bottom) {
                    StylePanel()
                }
                .help("調整預覽與輸出影片的字幕外觀")

                Button {
                    model.exportSRT()
                } label: {
                    Label("輸出 SRT", systemImage: "square.and.arrow.up")
                }
                .disabled(model.document.lines.isEmpty)
                .help("將字幕儲存為 SRT 檔")

                Button {
                    model.exportVideo()
                } label: {
                    Label("輸出影片", systemImage: "film")
                }
                .disabled(model.document.lines.isEmpty || !model.hasVideo || model.isWorking)
                .help("把字幕燒入影片，另存為 MP4")
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
        .alert("發生錯誤", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("尚未下載語音模型", isPresented: $model.needsModel) {
            Button("開啟模型管理") { openSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("對齊字幕需要語音模型。請先在設定中下載一個模型。")
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
