import AVFoundation
import CaptionFitterCore
import SwiftUI

/// Video preview with the current subtitle drawn on top, plus transport controls.
struct PlayerPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if model.mediaURL == nil {
                    Text("尚未選擇影片或音檔")
                        .foregroundStyle(.secondary)
                } else {
                    if !model.hasVideo {
                        Image(systemName: "waveform")
                            .font(.system(size: 56))
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                    PlayerSurface(player: model.player, text: model.currentLine?.text ?? "", style: model.style)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.togglePlayback() }

            transport
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("播放／暫停（空白鍵）")

            Button {
                model.seek(to: model.currentTime - 3)
            } label: {
                Image(systemName: "gobackward.5")
            }
            .help("倒退 3 秒")

            Slider(
                value: Binding(get: { model.currentTime }, set: { model.seek(to: $0) }),
                in: 0...max(model.mediaDuration, 0.1)
            )

            Text("\(TimeText.string(model.currentTime)) / \(TimeText.duration(model.mediaDuration))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(model.mediaURL == nil)
    }
}

/// Hosts the player layer and the subtitle image, drawn by the same renderer as the export.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    let text: String
    let style: SubtitleStyle

    func makeNSView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerSurfaceView, context: Context) {
        view.update(text: text, style: style)
    }
}

final class PlayerSurfaceView: NSView {
    let playerLayer = AVPlayerLayer()
    private let subtitleHost = CALayer()
    private var text = ""
    private var style = SubtitleStyle()
    private var renderedKey = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        layer?.addSublayer(subtitleHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Let clicks fall through to SwiftUI so tapping the video toggles playback.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        render()
    }

    func update(text: String, style: SubtitleStyle) {
        self.text = text
        self.style = style
        render()
    }

    private func render() {
        // Draw inside the displayed video frame; audio-only media uses the whole view.
        var frame = playerLayer.videoRect
        if frame.isEmpty || frame.width.isNaN || frame.isInfinite { frame = bounds }
        let key = "\(text)|\(frame)|\(style)"
        guard key != renderedKey else { return }
        renderedKey = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        subtitleHost.frame = frame
        subtitleHost.sublayers?.forEach { $0.removeFromSuperlayer() }
        let scale = window?.backingScaleFactor ?? 2
        if let rendered = SubtitleRenderer.render(text: text, style: style, videoSize: frame.size, scale: scale) {
            let line = CALayer()
            line.contents = rendered.image
            line.contentsScale = scale
            line.frame = rendered.frame
            subtitleHost.addSublayer(line)
        }
        CATransaction.commit()
    }
}

/// Appearance controls shared by the preview and the burned-in export.
struct StylePanel: View {
    @Environment(AppModel.self) private var model

    private static let families: [String] = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }

    var body: some View {
        @Bindable var model = model

        Form {
            Picker("字型", selection: $model.style.fontName) {
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("大小") {
                Slider(value: $model.style.fontScale, in: 0.03...0.12)
            }
            ColorPicker("文字顏色", selection: color(\.textColor), supportsOpacity: false)
            ColorPicker("描邊顏色", selection: color(\.outlineColor), supportsOpacity: false)
            LabeledContent("描邊粗細") {
                Slider(value: $model.style.outlineScale, in: 0...0.2)
            }
            Picker("位置", selection: $model.style.position) {
                Text("底部").tag(SubtitleStyle.Position.bottom)
                Text("頂部").tag(SubtitleStyle.Position.top)
            }
            .pickerStyle(.segmented)
            LabeledContent("邊距") {
                Slider(value: $model.style.marginScale, in: 0...0.3)
            }
            HStack {
                Spacer()
                Button("還原預設值") { model.style = SubtitleStyle() }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func color(_ keyPath: WritableKeyPath<SubtitleStyle, RGBAColor>) -> Binding<Color> {
        Binding(
            get: {
                let value = model.style[keyPath: keyPath]
                return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
            },
            set: { newValue in
                guard let converted = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                model.style[keyPath: keyPath] = RGBAColor(
                    red: converted.redComponent, green: converted.greenComponent, blue: converted.blueComponent
                )
            }
        )
    }
}
