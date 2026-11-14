import SwiftUI

@main
struct CaptionFitterApp: App {
    @State private var model = AppModel()
    @State private var modelManager = ModelManager()

    var body: some Scene {
        Window("CaptionFitter", id: "main") {
            ContentView()
                .environment(model)
                .environment(modelManager)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開啟影片或音檔…") { model.chooseMedia() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Button("輸出…") { model.showExport = true }
                    .keyboardShortcut("e")
                    .disabled(model.document.lines.isEmpty || model.isWorking)
            }
        }

        Settings {
            SettingsView()
                .environment(modelManager)
        }
    }
}
