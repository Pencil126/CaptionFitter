import AVFoundation
import CaptionFitterCore
import SwiftUI

/// Video preview with the current subtitle drawn on top, plus transport controls.
struct PlayerPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppModel.skipSecondsKey) private var skipSeconds = 5

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
                model.skip(forward: false)
            } label: {
                skipLabel("gobackward")
            }
            .help("倒退 \(skipSeconds) 秒（⇧←）")

            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("播放／暫停（空白鍵）")

            Button {
                model.skip(forward: true)
            } label: {
                skipLabel("goforward")
            }
            .help("快進 \(skipSeconds) 秒（⇧→）")

            Slider(
                value: Binding(get: { model.currentTime }, set: { model.seek(to: $0) }),
                in: 0...max(model.mediaDuration, 0.1)
            )

            Text("\(TimeText.string(model.currentTime)) / \(TimeText.string(model.mediaDuration))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(model.mediaURL == nil)
    }
}

extension PlayerPanel {
    /// The system has numbered skip icons for a few amounts only; others get the number beside a plain icon.
    @ViewBuilder fileprivate func skipLabel(_ symbol: String) -> some View {
        if [5, 10, 15].contains(skipSeconds) {
            Image(systemName: "\(symbol).\(skipSeconds)")
        } else {
            HStack(spacing: 1) {
                Image(systemName: symbol)
                Text("\(skipSeconds)").font(.caption2).monospacedDigit()
            }
        }
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
    @State private var showFonts = false

    var body: some View {
        @Bindable var model = model
        let faces = FontFaces.faces(ofFamily: model.style.fontName)

        Form {
            LabeledContent("字型") {
                Button {
                    showFonts.toggle()
                } label: {
                    HStack {
                        Text(FontCatalog.displayName(for: model.style.fontName))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .popover(isPresented: $showFonts, arrowEdge: .leading) {
                    FontPicker(selection: $model.style.fontName)
                }
            }
            // Only for fonts that come in more than one weight.
            if faces.count > 1 {
                Picker("字重", selection: face(among: faces)) {
                    ForEach(faces) { Text(FontCatalog.weightLabel($0.styleName)).tag($0.postScriptName) }
                }
            }
            LabeledContent("大小") {
                slider($model.style.fontScale, in: 0.03...0.12, value: percent(model.style.fontScale, digits: 1))
            }
            .help("字體高度占畫面高度的比例")
            ColorPicker("文字顏色", selection: color(\.textColor), supportsOpacity: false)
            ColorPicker("描邊顏色", selection: color(\.outlineColor), supportsOpacity: false)
            LabeledContent("描邊粗細") {
                slider($model.style.outlineScale, in: 0...0.2, value: percent(model.style.outlineScale, digits: 0))
            }
            .help("描邊寬度占字體大小的比例，0% 為不描邊")
            Picker("陰影", selection: $model.style.shadow) {
                Text("無").tag(SubtitleStyle.Shadow.none)
                Text("柔和").tag(SubtitleStyle.Shadow.soft)
                Text("明顯").tag(SubtitleStyle.Shadow.strong)
            }
            .pickerStyle(.segmented)
            LabeledContent("高度") {
                slider($model.style.verticalPosition, in: 0...1, value: percent(model.style.verticalPosition, digits: 0))
            }
            .help("字幕在畫面中的高度：0% 貼齊底部，100% 貼齊頂部")
            LabeledContent("") {
                HStack(spacing: 6) {
                    Button("底部") { model.style.verticalPosition = SubtitleStyle().verticalPosition }
                    Button("中間") { model.style.verticalPosition = 0.5 }
                    Button("頂部") { model.style.verticalPosition = 1 - SubtitleStyle().verticalPosition }
                }
                .controlSize(.small)
            }
            HStack {
                Spacer()
                Button("還原預設值") { model.style = SubtitleStyle() }
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    /// The face in use, by PostScript name. Choosing one also records its weight, so the
    /// closest weight carries over when the font is changed.
    private func face(among faces: [FontFaces.Face]) -> Binding<String> {
        Binding(
            get: {
                let style = model.style
                return FontFaces.resolve(family: style.fontName, weight: style.fontWeight, face: style.fontFace)?.postScriptName ?? ""
            },
            set: { name in
                guard let face = faces.first(where: { $0.postScriptName == name }) else { return }
                model.style.fontFace = face.postScriptName
                model.style.fontWeight = face.weight
            }
        )
    }

    /// A slider with its current value shown beside it.
    private func slider(_ binding: Binding<Double>, in range: ClosedRange<Double>, value: String) -> some View {
        HStack(spacing: 8) {
            Slider(value: binding, in: range)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private func percent(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f%%", value * 100)
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
