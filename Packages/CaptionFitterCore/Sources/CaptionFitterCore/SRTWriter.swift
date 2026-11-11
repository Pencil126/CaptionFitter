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
            // Lines without text or without a duration (not found in the audio) are left out.
            guard !text.isEmpty, line.end > line.start else { continue }
            output += "\(number)\n\(timestamp(line.start)) --> \(timestamp(line.end))\n\(text)\n\n"
            number += 1
        }
        return output
    }

    public static func write(_ lines: [SubtitleLine], to url: URL) throws {
        try string(from: lines).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reads SRT text back into subtitle lines. Malformed blocks are skipped.
    public static func parse(_ text: String) -> [SubtitleLine] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        var lines: [SubtitleLine] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let rows = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = rows.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = rows[timingIndex].components(separatedBy: "-->")
            guard times.count == 2, let start = seconds(times[0]), let end = seconds(times[1]) else { continue }
            let content = rows[(timingIndex + 1)...].joined(separator: "\n")
            guard !content.isEmpty else { continue }
            lines.append(SubtitleLine(start: start, end: max(start, end), text: content, confidence: .manual))
        }
        return lines
    }

    private static func seconds(_ timestamp: String) -> Double? {
        let parts = timestamp.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}
