import Foundation

public enum SRTWriter {
    /// `HH:MM:SS,mmm`
    public static func timestamp(_ seconds: Double) -> String {
        let totalMillis = Int((max(0, seconds) * 1000).rounded())
        let millis = totalMillis % 1000
        let totalSeconds = totalMillis / 1000
        return String(format: "%02d:%02d:%02d,%03d", totalSeconds / 3600, (totalSeconds / 60) % 60, totalSeconds % 60, millis)
    }

    public static func string(from lines: [SubtitleLine]) -> String {
        var output = ""
        var number = 1
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            output += "\(number)\n\(timestamp(line.start)) --> \(timestamp(line.end))\n\(text)\n\n"
            number += 1
        }
        return output
    }

    public static func write(_ lines: [SubtitleLine], to url: URL) throws {
        try string(from: lines).write(to: url, atomically: true, encoding: .utf8)
    }
}
