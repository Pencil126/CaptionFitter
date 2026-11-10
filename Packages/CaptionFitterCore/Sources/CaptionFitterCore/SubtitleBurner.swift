import AppKit
import AVFoundation
import QuartzCore

public struct RGBAColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// Appearance of subtitles, shared by the on-screen preview and the burned-in export.
/// Sizes are fractions of the video height so the look is the same at any resolution.
public struct SubtitleStyle: Equatable, Codable, Sendable {
    public enum Position: String, Codable, CaseIterable, Sendable {
        case bottom, top
    }

    public var fontName: String
    /// Font size as a fraction of the video height.
    public var fontScale: Double
    public var textColor: RGBAColor
    public var outlineColor: RGBAColor
    /// Outline thickness as a fraction of the font size (0 disables the outline).
    public var outlineScale: Double
    public var position: Position
    /// Distance from the edge as a fraction of the video height.
    public var marginScale: Double

    public init(fontName: String = "PingFang TC", fontScale: Double = 0.06, textColor: RGBAColor = .white,
                outlineColor: RGBAColor = .black, outlineScale: Double = 0.08, position: Position = .bottom,
                marginScale: Double = 0.06) {
        self.fontName = fontName
        self.fontScale = fontScale
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineScale = outlineScale
        self.position = position
        self.marginScale = marginScale
    }

    /// `fontName` may be a family name ("PingFang TC") or a PostScript name.
    public func font(videoHeight: CGFloat) -> NSFont {
        let size = max(8, videoHeight * fontScale)
        if let font = NSFontManager.shared.font(withFamily: fontName, traits: .boldFontMask, weight: 9, size: size) {
            return font
        }
        return NSFont(name: fontName, size: size) ?? .boldSystemFont(ofSize: size)
    }

    /// The styled text. Drawn twice by callers (outline pass underneath, fill pass on top)
    /// so the outline grows outwards and never thins the glyphs.
    public func attributedString(_ text: String, videoHeight: CGFloat, outlinePass: Bool) -> NSAttributedString {
        let font = font(videoHeight: videoHeight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor(cgColor: textColor.cgColor) ?? .white,
        ]
        if outlinePass {
            let outline = NSColor(cgColor: outlineColor.cgColor) ?? .black
            attributes[.foregroundColor] = outline
            attributes[.strokeColor] = outline
            // Stroke width is a percentage of the font size; the stroke is centred on the
            // glyph edge, so double it to get the requested thickness outside the glyph.
            attributes[.strokeWidth] = outlineScale * 200
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

/// Renders subtitles permanently into a copy of the video.
public enum SubtitleBurner {
    public enum BurnError: LocalizedError {
        case noVideoTrack
        case cannotExport
        case exportFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "這個檔案沒有影像軌，無法燒入字幕。"
            case .cannotExport: return "無法建立影片輸出工作。"
            case .exportFailed(let reason): return "影片輸出失敗：\(reason)"
            }
        }
    }

    public static func burn(
        lines: [SubtitleLine],
        style: SubtitleStyle,
        source: URL,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw BurnError.noVideoTrack }
        let duration = try await asset.load(.duration).seconds

        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        let size = composition.renderSize

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: size)
        let overlay = overlayLayer(lines: lines, style: style, size: size, duration: duration)
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        parent.addSublayer(videoLayer)
        parent.addSublayer(overlay)
        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parent
        )

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw BurnError.cannotExport
        }
        export.videoComposition = composition
        try? FileManager.default.removeItem(at: destination)

        let poller = Task {
            for await state in export.states(updateInterval: 0.25) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
                if Task.isCancelled { break }
            }
        }
        defer { poller.cancel() }

        do {
            try await export.export(to: destination, as: .mp4)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw CancellationError() }
            throw BurnError.exportFailed(error.localizedDescription)
        }
        progress(1)
    }

    /// One container layer per subtitle, each visible only during its time range.
    static func overlayLayer(lines: [SubtitleLine], style: SubtitleStyle, size: CGSize, duration: Double) -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: size)
        guard duration > 0 else { return overlay }

        for line in lines {
            guard line.end > line.start, line.start < duration,
                  let container = lineLayer(text: line.text, style: style, size: size) else { continue }
            container.opacity = 0

            let start = max(0, line.start) / duration
            let end = min(duration, line.end) / duration
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0, 1, 0, 0]
            animation.keyTimes = [0, NSNumber(value: start), NSNumber(value: end), 1]
            animation.calculationMode = .discrete
            animation.duration = duration
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            container.add(animation, forKey: "visibility")

            overlay.addSublayer(container)
        }
        return overlay
    }

    /// The layer for one subtitle, laid out for a video frame of `size` whose origin is at the
    /// bottom-left. Used both for the burned-in export and the live preview so they look alike.
    public static func lineLayer(text: String, style: SubtitleStyle, size: CGSize, contentsScale: CGFloat = 2) -> CALayer? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, size.width > 0, size.height > 0 else { return nil }

        let maxWidth = size.width * 0.9
        let margin = size.height * style.marginScale
        let fill = style.attributedString(text, videoHeight: size.height, outlinePass: false)
        let bounds = fill.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let pad = size.height * style.fontScale * max(style.outlineScale, 0.05) * 2
        let height = ceil(bounds.height) + pad * 2
        let y = style.position == .bottom ? margin : size.height - margin - height
        let frame = CGRect(x: (size.width - maxWidth) / 2, y: y, width: maxWidth, height: height)

        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)

        var passes: [NSAttributedString] = [fill]
        if style.outlineScale > 0 {
            passes.insert(style.attributedString(text, videoHeight: size.height, outlinePass: true), at: 0)
        }
        for pass in passes {
            let layer = CATextLayer()
            layer.string = pass
            layer.isWrapped = true
            layer.alignmentMode = .center
            layer.contentsScale = contentsScale
            layer.frame = frame
            container.addSublayer(layer)
        }
        return container
    }
}
