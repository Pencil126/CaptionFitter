import Foundation

/// A summary of how trustworthy an alignment is, with warnings worth showing the user.
public struct AlignmentReport: Equatable, Sendable {
    /// Something the user should know about the result. The wording is left to the caller,
    /// so the app can show it in the user's language.
    public enum Warning: Hashable, Sendable {
        /// Most lines could not be matched to the audio: the transcript or the language is probably wrong.
        case mostLinesUnmatched(doubtful: Int, total: Int)
        /// A noticeable share of lines have uncertain timing.
        case someLinesUncertain(doubtful: Int, total: Int)
        /// The subtitles stop well before the media does, at this percentage of its length.
        case endsEarly(percent: Int)
        /// The chosen lyrics differ in length from the media by this many seconds.
        case lyricsLengthMismatch(seconds: Int, likelyDifferentVersion: Bool)
    }

    public var totalLines: Int
    public var goodLines: Int
    public var partialLines: Int
    public var interpolatedLines: Int
    public var warnings: [Warning]

    public var hasWarnings: Bool { !warnings.isEmpty }

    public init(lines: [SubtitleLine], mediaDuration: Double?, scriptDuration: Double? = nil) {
        totalLines = lines.count
        goodLines = lines.filter { $0.confidence == .good }.count
        partialLines = lines.filter { $0.confidence == .partial }.count
        interpolatedLines = lines.filter { $0.confidence == .interpolated }.count

        var warnings: [Warning] = []
        if totalLines > 0 {
            let doubtful = partialLines + interpolatedLines
            let share = Double(doubtful) / Double(totalLines)
            if share >= 0.6 {
                warnings.append(.mostLinesUnmatched(doubtful: doubtful, total: totalLines))
            } else if share >= 0.25 {
                warnings.append(.someLinesUncertain(doubtful: doubtful, total: totalLines))
            }
        }
        if let mediaDuration, mediaDuration > 0, let last = lines.last, last.end < mediaDuration * 0.6 {
            warnings.append(.endsEarly(percent: Int(last.end / mediaDuration * 100)))
        }
        if let mediaDuration, let scriptDuration {
            let difference = abs(mediaDuration - scriptDuration)
            if difference > 5 {
                warnings.append(.lyricsLengthMismatch(seconds: Int(difference), likelyDifferentVersion: difference > 15))
            }
        }
        self.warnings = warnings
    }
}
