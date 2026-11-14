import CaptionFitterCore
import SwiftUI

/// Chooses what to export and, for video, at what quality.
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("exportContent") private var contentRaw = ExportContent.srt.rawValue
    @AppStorage("exportResolution") private var resolutionRaw = VideoExportOptions.Resolution.original.rawValue
    @AppStorage("exportFrameRate") private var frameRateRaw = VideoExportOptions.FrameRate.original.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("輸出").font(.title3.bold())
                .padding([.horizontal, .top], 20)

            Form {
                Picker("內容", selection: content) {
                    Text("SRT 字幕檔").tag(ExportContent.srt)
                    Text("含字幕的影片（MP4）").tag(ExportContent.video)
                    Text("兩者都要").tag(ExportContent.both)
                }
                .pickerStyle(.radioGroup)
                .disabled(!model.hasVideo)

                if let info = model.videoInfo, model.hasVideo {
                    Section {
                        Picker("畫質", selection: resolution(info)) {
                            Text("原始（\(Int(info.size.width))×\(Int(info.size.height))）").tag(VideoExportOptions.Resolution.original)
                            ForEach([VideoExportOptions.Resolution.p1080, .p720, .p480].filter { VideoExportOptions.applies($0, to: info) }) {
                                Text("\($0.rawValue)p").tag($0)
                            }
                        }
                        Picker("幀率", selection: frameRate(info)) {
                            Text("原始（\(Self.rate(info.frameRate)) 格／秒）").tag(VideoExportOptions.FrameRate.original)
                            ForEach([VideoExportOptions.FrameRate.fps60, .fps30].filter { VideoExportOptions.applies($0, to: info) }) {
                                Text("\($0.rawValue) 格／秒").tag($0)
                            }
                        }
                    } header: {
                        Text("影片")
                    }
                    .disabled(content.wrappedValue == .srt)
                } else {
                    Text("這個檔案沒有影像，只能輸出 SRT 字幕檔。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("輸出…") {
                    let chosen = content.wrappedValue
                    let options = options
                    dismiss()
                    // Let the sheet close before the save dialog opens.
                    DispatchQueue.main.async { model.export(chosen, options: options) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }

    private var content: Binding<ExportContent> {
        Binding(
            get: { model.hasVideo ? ExportContent(rawValue: contentRaw) ?? .srt : .srt },
            set: { contentRaw = $0.rawValue }
        )
    }

    /// The remembered choice, falling back to "original" when it does not apply to this video.
    private func resolution(_ info: VideoInfo) -> Binding<VideoExportOptions.Resolution> {
        Binding(
            get: {
                let saved = VideoExportOptions.Resolution(rawValue: resolutionRaw) ?? .original
                return VideoExportOptions.applies(saved, to: info) ? saved : .original
            },
            set: { resolutionRaw = $0.rawValue }
        )
    }

    private func frameRate(_ info: VideoInfo) -> Binding<VideoExportOptions.FrameRate> {
        Binding(
            get: {
                let saved = VideoExportOptions.FrameRate(rawValue: frameRateRaw) ?? .original
                return VideoExportOptions.applies(saved, to: info) ? saved : .original
            },
            set: { frameRateRaw = $0.rawValue }
        )
    }

    private var options: VideoExportOptions {
        guard let info = model.videoInfo else { return VideoExportOptions() }
        return VideoExportOptions(resolution: resolution(info).wrappedValue, frameRate: frameRate(info).wrappedValue)
    }

    private static func rate(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.005 ? String(Int(value.rounded())) : String(format: "%.2f", value)
    }
}
