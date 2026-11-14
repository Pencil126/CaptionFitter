import CaptionFitterCore
import Foundation

/// Records what happened in each alignment as a text file in the app's Logs folder, so a run
/// that went wrong can be compared with one that went right. Nothing leaves this Mac.
enum AlignmentLog {
    struct Run {
        /// 1 for the first alignment since the app was opened.
        var ordinal: Int
        /// Whether the speech model had to be loaded for this run.
        var loadedModel: Bool
        var modelID: String
        var mediaName: String
        var sampleCount: Int
        /// Sum of the absolute sample values: the same audio always gives the same number.
        var audioChecksum: Double
        var language: String
        var scriptLines: [String]
        var seconds: Double
        var alignment: Alignment
    }

    private static let keep = 30

    static var folder: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/CaptionFitter", isDirectory: true)
    }

    static func write(_ run: Run) {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        #if DEBUG
        let build = "Debug"
        #else
        let build = "Release"
        #endif

        var text = """
        time: \(Date())
        build: \(build)
        alignment since launch: \(run.ordinal)
        model: \(run.modelID)\(run.loadedModel ? " (loaded for this run)" : " (already loaded)")
        media: \(run.mediaName)
        audio: \(run.sampleCount) samples, checksum \(String(format: "%.3f", run.audioChecksum))
        language: \(run.language)
        took: \(String(format: "%.1f", run.seconds)) s

        """
        text += "\n== unscripted regions (\(run.alignment.unscriptedRegions.count))\n"
        for region in run.alignment.unscriptedRegions {
            text += String(format: "%.2f-%.2f\n", region.lowerBound, region.upperBound)
        }
        text += "\n== heard (\(run.alignment.heard.count) segments)\n"
        for segment in run.alignment.heard {
            text += String(format: "%7.2f-%7.2f  conf=%.2f  %@\n", segment.start, segment.end, segment.confidence, segment.text)
        }
        text += "\n== subtitles (\(run.alignment.lines.count))\n"
        for line in run.alignment.lines {
            text += String(format: "%7.2f-%7.2f  %@  %@\n", line.start, line.end, line.confidence.rawValue, line.text)
        }
        text += "\n== script (\(run.scriptLines.count) lines)\n" + run.scriptLines.joined(separator: "\n") + "\n"

        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: folder.appendingPathComponent("align-\(stamp.string(from: Date())).txt"), atomically: true, encoding: .utf8)
            // Keep only the most recent runs.
            let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("align-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in files.dropFirst(keep) { try? manager.removeItem(at: old) }
        } catch {
            // A diagnostic aid; never get in the way of the alignment itself.
        }
    }
}
