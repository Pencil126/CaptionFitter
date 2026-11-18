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
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)
            ModelSettingsView()
                .tabItem { Label("Speech Models", systemImage: "waveform") }
                .tag(SettingsTab.models.rawValue)
        }
    }
}

/// Playback preferences and the list of keyboard shortcuts.
struct GeneralSettingsView: View {
    @AppStorage(AppModel.skipSecondsKey) private var skipSeconds = 5

    var body: some View {
        Form {
            Section("Playback") {
                LabeledContent("Skip Forward/Back") {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(get: { Double(skipSeconds) }, set: { skipSeconds = Int($0.rounded()) }),
                            in: Double(AppModel.skipSecondsRange.lowerBound)...Double(AppModel.skipSecondsRange.upperBound),
                            step: 1
                        )
                        .brandTint()
                        Text("\(skipSeconds) s", comment: "Seconds, abbreviated")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("Keyboard Shortcuts") {
                shortcut(String(localized: "Space", comment: "The space bar"), "Play/Pause")
                shortcut("⇧←", "Back \(skipSeconds) Seconds")
                shortcut("⇧→", "Forward \(skipSeconds) Seconds")
                shortcut("←　→", "Previous/Next Frame")
                shortcut("⌘E", "Export")
                Text("While you're typing subtitle text, the arrow keys move the cursor and select text instead of moving the playhead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // Same size as the models tab, so the window does not jump when switching.
        .frame(width: 640, height: 520)
    }

    private func shortcut(_ keys: String, _ action: LocalizedStringKey) -> some View {
        LabeledContent(action) {
            Text(keys).monospaced().foregroundStyle(.secondary)
        }
    }
}
