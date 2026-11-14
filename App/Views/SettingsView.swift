import SwiftUI

/// The tabs of the Settings window.
enum SettingsTab: String {
    case general, models

    static let key = "settingsTab"

    /// Makes this the tab shown the next time Settings opens.
    func select() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}

struct SettingsView: View {
    @AppStorage(SettingsTab.key) private var tab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("一般", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)
            ModelSettingsView()
                .tabItem { Label("語音模型", systemImage: "waveform") }
                .tag(SettingsTab.models.rawValue)
        }
    }
}

/// Playback preferences and the list of keyboard shortcuts.
struct GeneralSettingsView: View {
    @AppStorage(AppModel.skipSecondsKey) private var skipSeconds = 5

    var body: some View {
        Form {
            Section("播放") {
                LabeledContent("快進／倒退") {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(get: { Double(skipSeconds) }, set: { skipSeconds = Int($0.rounded()) }),
                            in: Double(AppModel.skipSecondsRange.lowerBound)...Double(AppModel.skipSecondsRange.upperBound),
                            step: 1
                        )
                        Text("\(skipSeconds) 秒")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("快捷鍵") {
                shortcut("空白鍵", "播放／暫停")
                shortcut("⇧←", "倒退 \(skipSeconds) 秒")
                shortcut("⇧→", "快進 \(skipSeconds) 秒")
                shortcut("←　→", "前一格／後一格")
                shortcut("⌘E", "輸出")
                Text("正在輸入字幕文字時，方向鍵用來移動游標與選取文字，不會移動播放位置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // Same size as the models tab, so the window does not jump when switching.
        .frame(width: 640, height: 520)
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        LabeledContent(action) {
            Text(keys).monospaced().foregroundStyle(.secondary)
        }
    }
}
