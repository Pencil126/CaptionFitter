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
            Text("Export").font(.title3.bold())
                .padding([.horizontal, .top], 20)

            Form {
                Picker("Content", selection: content) {
                    Text("SRT subtitle file").tag(ExportContent.srt)
                    Text("Video with subtitles (MP4)").tag(ExportContent.video)
                    Text("Both").tag(ExportContent.both)
                }
                .pickerStyle(.radioGroup)
                .brandTint()
                .disabled(!model.hasVideo)

                if let info = model.videoInfo, model.hasVideo {
                    Section {
                        Picker("Resolution", selection: resolution(info)) {
                            Text("Original (\(Int(info.size.width))×\(Int(info.size.height)))").tag(VideoExportOptions.Resolution.original)
                            ForEach([VideoExportOptions.Resolution.p1080, .p720, .p480].filter { VideoExportOptions.applies($0, to: info) }) {
                                Text(verbatim: "\($0.rawValue)p").tag($0)
                            }
                        }
                        Picker("Frame Rate", selection: frameRate(info)) {
                            Text("Original (\(Self.rate(info.frameRate)) fps)").tag(VideoExportOptions.FrameRate.original)
                            ForEach([VideoExportOptions.FrameRate.fps60, .fps30].filter { VideoExportOptions.applies($0, to: info) }) {
                                Text("\($0.rawValue) fps").tag($0)
                            }
                        }
                    } header: {
                        Text("Video")
                    }
                    .disabled(content.wrappedValue == .srt)
                } else {
                    Text("This file has no picture, so only an SRT subtitle file can be exported.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let chosen = content.wrappedValue
                    let options = options
                    dismiss()
                    // Let the sheet close before the save dialog opens.
                    DispatchQueue.main.async { model.export(chosen, options: options) }
                } label: {
                    BrandButtonLabel("Export…")
                }
                .keyboardShortcut(.defaultAction)
                .brandTint()
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
