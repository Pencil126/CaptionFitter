import AppKit
import AVFoundation
import CoreImage
import CoreText

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
    public enum Shadow: String, Codable, CaseIterable, Sendable {
        case none, soft, strong
    }

    public var fontName: String
    /// How heavy the letters are, on AppKit's 0–15 scale (5 is regular, 9 is bold).
    /// The family's closest weight is used.
    public var fontWeight: Int
    /// PostScript name of the exact face chosen. Used while it belongs to `fontName`;
    /// after switching family, `fontWeight` picks the nearest face instead.
    public var fontFace: String?
    /// Font size as a fraction of the video height.
    public var fontScale: Double
    public var textColor: RGBAColor
    public var outlineColor: RGBAColor
    /// Outline thickness as a fraction of the font size (0 disables the outline).
    public var outlineScale: Double
    public var shadow: Shadow
    /// Where the subtitle sits between the bottom (0) and the top (1) of the picture.
    /// The text stays inside the frame at either end.
    public var verticalPosition: Double

    public init(fontName: String = "PingFang TC", fontWeight: Int = 9, fontFace: String? = nil,
                fontScale: Double = 0.05, textColor: RGBAColor = .white,
                outlineColor: RGBAColor = .black, outlineScale: Double = 0, shadow: Shadow = .none,
                verticalPosition: Double = 0.08) {
        self.fontName = fontName
        self.fontWeight = fontWeight
        self.fontFace = fontFace
        self.fontScale = fontScale
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineScale = outlineScale
        self.shadow = shadow
        self.verticalPosition = verticalPosition
    }

    private enum CodingKeys: String, CodingKey {
        case fontName, fontWeight, fontFace, fontScale, textColor, outlineColor, outlineScale, shadow, verticalPosition
        // Written by earlier versions: an edge and a distance from it.
        case position, marginScale
    }

    public init(from decoder: Decoder) throws {
        let defaults = SubtitleStyle()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try values.decodeIfPresent(String.self, forKey: .fontName) ?? defaults.fontName
        fontWeight = try values.decodeIfPresent(Int.self, forKey: .fontWeight) ?? defaults.fontWeight
        fontFace = try values.decodeIfPresent(String.self, forKey: .fontFace)
        fontScale = try values.decodeIfPresent(Double.self, forKey: .fontScale) ?? defaults.fontScale
        textColor = try values.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? defaults.textColor
        outlineColor = try values.decodeIfPresent(RGBAColor.self, forKey: .outlineColor) ?? defaults.outlineColor
        outlineScale = try values.decodeIfPresent(Double.self, forKey: .outlineScale) ?? defaults.outlineScale
        shadow = try values.decodeIfPresent(Shadow.self, forKey: .shadow) ?? defaults.shadow
        if let position = try values.decodeIfPresent(Double.self, forKey: .verticalPosition) {
            verticalPosition = min(max(position, 0), 1)
        } else if let margin = try values.decodeIfPresent(Double.self, forKey: .marginScale) {
            let top = try values.decodeIfPresent(String.self, forKey: .position) == "top"
            verticalPosition = min(max(top ? 1 - margin : margin, 0), 1)
        } else {
            verticalPosition = defaults.verticalPosition
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fontName, forKey: .fontName)
        try values.encode(fontWeight, forKey: .fontWeight)
        try values.encodeIfPresent(fontFace, forKey: .fontFace)
        try values.encode(fontScale, forKey: .fontScale)
        try values.encode(textColor, forKey: .textColor)
        try values.encode(outlineColor, forKey: .outlineColor)
        try values.encode(outlineScale, forKey: .outlineScale)
        try values.encode(shadow, forKey: .shadow)
        try values.encode(verticalPosition, forKey: .verticalPosition)
    }

    /// Blur, drop and opacity of the shadow, the first two as fractions of the font size.
    var shadowMetrics: (blur: Double, offset: Double, alpha: Double)? {
        switch shadow {
        case .none: return nil
        case .soft: return (0.12, 0.04, 0.65)
        case .strong: return (0.05, 0.08, 0.9)
        }
    }

    /// `fontName` may be a family name ("PingFang TC") or a PostScript name.
    public func font(videoHeight: CGFloat) -> NSFont {
        let size = max(8, videoHeight * fontScale)
        if let face = FontFaces.resolve(family: fontName, weight: fontWeight, face: fontFace),
           let font = NSFont(name: face.postScriptName, size: size) {
            return font
        }
        return NSFont(name: fontName, size: size) ?? .boldSystemFont(ofSize: size)
    }

    /// The styled text for one drawing pass. The outline pass strokes the glyph edges and is
    /// drawn underneath the fill pass, so the outline grows outwards and never thins the glyphs.
    func attributedString(_ text: String, videoHeight: CGFloat, outlinePass: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(videoHeight: videoHeight),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor(cgColor: textColor.cgColor) ?? .white,
        ]
        if outlinePass {
            attributes[.strokeColor] = NSColor(cgColor: outlineColor.cgColor) ?? .black
            // A positive width strokes only. It is a percentage of the font size and the stroke is
            // centred on the glyph edge, so double it to get the requested thickness outside.
            attributes[.strokeWidth] = outlineScale * 200
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

/// The weights a font family comes in.
public enum FontFaces {
    public struct Face: Equatable, Identifiable, Sendable {
        public var postScriptName: String
        /// The face's own name for its style, e.g. "Semibold".
        public var styleName: String
        /// AppKit's 0–15 scale (5 is regular, 9 is bold).
        public var weight: Int
        public var id: String { postScriptName }
    }

    /// The upright faces of a family, lightest first. Italic and condensed variants are
    /// left out unless the family has nothing else.
    public static func faces(ofFamily family: String) -> [Face] {
        cache.faces(family)
    }

    /// The face to draw with: `face` if the family has it, otherwise the closest weight.
    public static func resolve(family: String, weight: Int, face: String?) -> Face? {
        let faces = faces(ofFamily: family)
        if let face, let exact = faces.first(where: { $0.postScriptName == face }) { return exact }
        // Ties go to the heavier face, which reads better over video.
        return faces.min { (abs($0.weight - weight), -$0.weight) < (abs($1.weight - weight), -$1.weight) }
    }

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var known: [String: [Face]] = [:]

        func faces(_ family: String) -> [Face] {
            lock.lock()
            defer { lock.unlock() }
            if let faces = known[family] { return faces }
            let faces = Self.load(family)
            known[family] = faces
            return faces
        }

        private static func load(_ family: String) -> [Face] {
            struct Member {
                var face: Face
                var traits: Int
                /// Core Text's finer weight (-1…1), which tells apart faces AppKit ranks the same.
                var fineWeight: Double
            }
            let members: [Member] = (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { entry in
                guard entry.count >= 4, let name = entry[0] as? String, let style = entry[1] as? String,
                      let weight = entry[2] as? Int, let traits = entry[3] as? Int else { return nil }
                let descriptor = NSFontDescriptor(name: name, size: 12)
                let fine = ((descriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? Double) ?? 0
                return Member(face: Face(postScriptName: name, styleName: style, weight: weight), traits: traits, fineWeight: fine)
            }
            let italic = Int(NSFontTraitMask.italicFontMask.rawValue)
            let squeezed = Int(NSFontTraitMask.narrowFontMask.rawValue | NSFontTraitMask.expandedFontMask.rawValue
                | NSFontTraitMask.condensedFontMask.rawValue | NSFontTraitMask.compressedFontMask.rawValue)
            var chosen = members.filter { $0.traits & (italic | squeezed) == 0 }
            if chosen.isEmpty { chosen = members.filter { $0.traits & italic == 0 } }
            if chosen.isEmpty { chosen = members }
            return chosen
                .sorted { ($0.face.weight, $0.fineWeight) < ($1.face.weight, $1.fineWeight) }
                .map { $0.face }
        }
    }
}

/// Draws one subtitle to an image. The preview and the burned-in export both use this,
/// so what is shown while editing is what ends up in the video.
public enum SubtitleRenderer {
    public struct Rendered {
        public var image: CGImage
        /// Where the image goes in a video frame whose origin is at the bottom-left, in points.
        public var frame: CGRect
    }

    /// - Parameter scale: pixels per point (1 for export, the screen's backing scale for preview).
    public static func render(text: String, style: SubtitleStyle, videoSize: CGSize, scale: CGFloat = 1) -> Rendered? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, videoSize.width > 1, videoSize.height > 1 else { return nil }

        let fill = style.attributedString(text, videoHeight: videoSize.height, outlinePass: false)
        let maxWidth = videoSize.width * 0.9
        let fillSetter = CTFramesetterCreateWithAttributedString(fill)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
            fillSetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
        )
        // Room around the text for the outline and the shadow.
        let fontSize = max(8, videoSize.height * style.fontScale)
        let shadow = style.shadowMetrics
        let pad = ceil(fontSize * (style.outlineScale + (shadow.map { $0.blur + $0.offset } ?? 0))) + 2
        let width = ceil(textSize.width) + pad * 2
        let height = ceil(textSize.height) + pad * 2

        guard let context = CGContext(
            data: nil, width: Int(ceil(width * scale)), height: Int(ceil(height * scale)),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setLineJoin(.round)

        let path = CGPath(rect: CGRect(x: pad, y: pad, width: ceil(textSize.width), height: ceil(textSize.height)), transform: nil)
        if let shadow {
            // One shadow for outline and fill together. Shadow sizes are in pixels, not points.
            context.setShadow(
                offset: CGSize(width: 0, height: -fontSize * shadow.offset * scale),
                blur: fontSize * shadow.blur * scale,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shadow.alpha)
            )
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if style.outlineScale > 0 {
            let outline = style.attributedString(text, videoHeight: videoSize.height, outlinePass: true)
            let outlineSetter = CTFramesetterCreateWithAttributedString(outline)
            CTFrameDraw(CTFramesetterCreateFrame(outlineSetter, CFRange(location: 0, length: 0), path, nil), context)
        }
        CTFrameDraw(CTFramesetterCreateFrame(fillSetter, CFRange(location: 0, length: 0), path, nil), context)
        if shadow != nil { context.endTransparencyLayer() }

        guard let image = context.makeImage() else { return nil }
        let y = max(0, videoSize.height - height) * min(max(style.verticalPosition, 0), 1)
        return Rendered(image: image, frame: CGRect(x: (videoSize.width - width) / 2, y: y, width: width, height: height))
    }
}

/// Picture size and frame rate of a video.
public struct VideoInfo: Equatable, Sendable {
    /// As displayed, with any rotation applied.
    public var size: CGSize
    public var frameRate: Double

    public init(size: CGSize, frameRate: Double) {
        self.size = size
        self.frameRate = frameRate
    }

    /// The "p" number: 1080 for both 1920×1080 and an upright 1080×1920.
    public var shortSide: Double { min(size.width, size.height) }

    public static func load(from url: URL) async -> VideoInfo? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (natural, transform, rate) = try? await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        else { return nil }
        let size = natural.applying(transform)
        return VideoInfo(size: CGSize(width: abs(size.width), height: abs(size.height)), frameRate: Double(rate))
    }
}

/// Picture quality of an exported video. Neither setting ever goes above the source.
public struct VideoExportOptions: Equatable, Sendable {
    public enum Resolution: Int, CaseIterable, Identifiable, Sendable {
        case original = 0, p480 = 480, p720 = 720, p1080 = 1080
        public var id: Int { rawValue }
    }

    public enum FrameRate: Int, CaseIterable, Identifiable, Sendable {
        case original = 0, fps30 = 30, fps60 = 60
        public var id: Int { rawValue }
    }

    public var resolution: Resolution
    public var frameRate: FrameRate

    public init(resolution: Resolution = .original, frameRate: FrameRate = .original) {
        self.resolution = resolution
        self.frameRate = frameRate
    }

    /// Whether this resolution would shrink the video (enlarging is never done).
    public static func applies(_ resolution: Resolution, to info: VideoInfo) -> Bool {
        resolution == .original || Double(resolution.rawValue) < info.shortSide - 0.5
    }

    /// Whether this frame rate would lower the video's (frames are never invented).
    public static func applies(_ frameRate: FrameRate, to info: VideoInfo) -> Bool {
        frameRate == .original || Double(frameRate.rawValue) < info.frameRate - 0.5
    }

    /// The exported picture size: the short side becomes the chosen resolution, the shape is
    /// kept, and both sides are even as video encoders require.
    public func renderSize(for info: VideoInfo) -> CGSize {
        guard resolution != .original, Self.applies(resolution, to: info) else { return info.size }
        let scale = Double(resolution.rawValue) / info.shortSide
        func even(_ value: Double) -> Double { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(info.size.width), height: even(info.size.height))
    }

    /// The exported frame rate, or nil to keep the source's.
    public func framesPerSecond(for info: VideoInfo) -> Int? {
        frameRate != .original && Self.applies(frameRate, to: info) ? frameRate.rawValue : nil
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
        options: VideoExportOptions = VideoExportOptions(),
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let info = await VideoInfo.load(from: source) else { throw BurnError.noVideoTrack }
        let duration = try await asset.load(.duration).seconds
        let renderSize = options.renderSize(for: info)
        let frame = CGRect(origin: .zero, size: renderSize)

        // Composite the subtitle for each frame's time. Only the line on screen is rendered
        // (and cached), so memory stays flat however long the video is.
        let overlay = OverlayProvider(lines: lines, style: style, duration: duration)
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            var image = request.sourceImage
            // Fit the picture to the output size first, so the subtitle is drawn at full sharpness.
            let extent = image.extent
            if abs(extent.width - renderSize.width) > 0.5 || abs(extent.height - renderSize.height) > 0.5 {
                image = image
                    .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                    .applyingFilter("CILanczosScaleTransform", parameters: [
                        kCIInputScaleKey: renderSize.height / extent.height,
                        kCIInputAspectRatioKey: (renderSize.width / extent.width) / (renderSize.height / extent.height),
                    ])
            }
            if let subtitle = overlay.image(at: request.compositionTime.seconds, videoSize: renderSize) {
                image = subtitle.composited(over: image)
            }
            request.finish(with: image.cropped(to: frame), context: nil)
        }
        composition.renderSize = renderSize
        if let rate = options.framesPerSecond(for: info) {
            composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(rate))
            // Otherwise frames keep the source track's timing and the setting above is ignored.
            composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        }

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
}

/// Finds and renders the subtitle for a given time; safe to call from the export queue.
private final class OverlayProvider: @unchecked Sendable {
    private let lines: [SubtitleLine]
    private let style: SubtitleStyle
    private let lock = NSLock()
    private var cachedID: SubtitleLine.ID?
    private var cachedImage: CIImage?

    init(lines: [SubtitleLine], style: SubtitleStyle, duration: Double) {
        self.lines = lines.filter { $0.end > $0.start && $0.start < duration }.sorted { $0.start < $1.start }
        self.style = style
    }

    func image(at time: Double, videoSize: CGSize) -> CIImage? {
        // Latest line that has started and not yet ended, matching the preview.
        guard let line = lines.last(where: { $0.start <= time && time < $0.end }) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if cachedID == line.id { return cachedImage }
        cachedID = line.id
        cachedImage = SubtitleRenderer.render(text: line.text, style: style, videoSize: videoSize).map { rendered in
            CIImage(cgImage: rendered.image)
                .transformed(by: CGAffineTransform(
                    scaleX: rendered.frame.width / CGFloat(rendered.image.width),
                    y: rendered.frame.height / CGFloat(rendered.image.height)
                ))
                .transformed(by: CGAffineTransform(translationX: rendered.frame.minX, y: rendered.frame.minY))
        }
        return cachedImage
    }
}
