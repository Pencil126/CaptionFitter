import Foundation

/// A summary of how trustworthy an alignment is, with warnings worth showing the user.
public struct AlignmentReport: Equatable, Sendable {
    public var totalLines: Int
    public var goodLines: Int
    public var partialLines: Int
    public var interpolatedLines: Int
    public var warnings: [String]

    public var hasWarnings: Bool { !warnings.isEmpty }

    public init(lines: [SubtitleLine], mediaDuration: Double?, scriptDuration: Double? = nil) {
        totalLines = lines.count
        goodLines = lines.filter { $0.confidence == .good }.count
        partialLines = lines.filter { $0.confidence == .partial }.count
        interpolatedLines = lines.filter { $0.confidence == .interpolated }.count

        var warnings: [String] = []
        if totalLines > 0 {
            let doubtful = partialLines + interpolatedLines
            let share = Double(doubtful) / Double(totalLines)
            if share >= 0.6 {
                warnings.append("大部分字幕（\(doubtful)／\(totalLines) 行）在聲音中對不上，文稿可能與影片內容不符，或語系選擇有誤。")
            } else if share >= 0.25 {
                warnings.append("有 \(doubtful)／\(totalLines) 行字幕的時間不確定，已在列表中標示，建議逐一檢查。")
            }
        }
        if let mediaDuration, mediaDuration > 0, let last = lines.last, last.end < mediaDuration * 0.6 {
            warnings.append("字幕在影片的 \(Int(last.end / mediaDuration * 100))% 處就結束了，文稿可能不完整（例如重複的段落只寫了一次）。")
        }
        if let mediaDuration, let scriptDuration {
            let difference = abs(mediaDuration - scriptDuration)
            if difference > 15 {
                warnings.append("所選歌詞版本的長度與影片相差 \(Int(difference)) 秒，可能是不同版本。")
            } else if difference > 5 {
                warnings.append("所選歌詞版本的長度與影片相差 \(Int(difference)) 秒。")
            }
        }
        self.warnings = warnings
    }
}
