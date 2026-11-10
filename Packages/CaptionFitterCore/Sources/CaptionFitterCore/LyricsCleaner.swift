import Foundation

/// Clean-up that only applies to song lyrics (search results and LRC files):
/// credits, section markers and LRC time tags are not sung, so they must not be aligned.
public enum LyricsCleaner {
    public struct TimedLine: Equatable, Sendable {
        public var time: Double
        public var text: String
    }

    /// True when the text carries LRC time tags such as `[01:23.45]`.
    public static func isLRC(_ text: String) -> Bool {
        text.range(of: #"\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]"#, options: .regularExpression) != nil
    }

    /// Returns the lines to align, in sung order.
    public static func clean(_ text: String) -> [String] {
        let lines = isLRC(text) ? parseLRC(text).map(\.text) : text.components(separatedBy: .newlines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isCredit($0) && !isSectionMarker($0) }
    }

    /// Parses LRC, expanding lines that carry several time tags (repeated choruses)
    /// into one entry per tag and sorting everything by time.
    public static func parseLRC(_ text: String) -> [TimedLine] {
        guard let tag = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#) else { return [] }
        var result: [(order: Int, line: TimedLine)] = []
        var order = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            var times: [Double] = []
            var position = 0
            // Only tags at the very start of the line count as timing.
            while let match = tag.firstMatch(in: rawLine, range: NSRange(location: position, length: line.length - position)),
                  match.range.location == position {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let digits = line.substring(with: match.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                times.append(minutes * 60 + seconds + fraction)
                position = match.range.location + match.range.length
                while position < line.length, line.character(at: position) == 0x20 { position += 1 }
            }
            guard !times.isEmpty else { continue } // metadata such as [ar:…] or untimed text
            let content = line.substring(from: position).trimmingCharacters(in: .whitespaces)
            for time in times {
                result.append((order, TimedLine(time: time, text: content)))
                order += 1
            }
        }
        return result
            .sorted { ($0.line.time, $0.order) < ($1.line.time, $1.order) }
            .map(\.line)
    }

    // MARK: - Private

    private static let creditPattern: NSRegularExpression? = {
        let roles = [
            "作詞", "作词", "填詞", "填词", "詞", "词", "作曲", "曲", "編曲", "编曲", "製作人", "制作人", "製作", "制作",
            "監製", "监制", "演唱", "原唱", "翻唱", "主唱", "和聲", "和声", "合聲", "合声", "混音", "錄音", "录音",
            "母帶", "母带", "吉他", "貝斯", "贝斯", "鼓", "鋼琴", "钢琴", "鍵盤", "键盘", "弦樂", "弦乐", "出品", "發行", "发行",
            "OP", "SP", "ISRC",
            "Lyrics(?: by)?", "Lyricist", "Words(?: by)?", "Music(?: by)?", "Composer", "Composed by", "Written by",
            "Arranger", "Arranged by", "Arrangement", "Producer", "Produced by", "Mixed by", "Mastered by", "Vocals?",
        ]
        return try? NSRegularExpression(
            pattern: "^(?:" + roles.joined(separator: "|") + #")\s*[:：]"#,
            options: [.caseInsensitive]
        )
    }()

    private static func isCredit(_ line: String) -> Bool {
        guard let creditPattern else { return false }
        return creditPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    private static let sectionWords = [
        "主歌", "副歌", "導歌", "导歌", "前奏", "間奏", "间奏", "尾奏", "橋段", "桥段", "過門", "过门", "口白", "獨白", "独白", "重複", "重复",
        "verse", "chorus", "pre-chorus", "prechorus", "post-chorus", "bridge", "intro", "outro", "interlude",
        "hook", "refrain", "instrumental", "solo", "rap", "music", "repeat",
    ]

    /// A whole line that is only a bracketed label, e.g. `[副歌]`, `【Verse 1】`, `(Chorus x2)`.
    private static func isSectionMarker(_ line: String) -> Bool {
        let pairs: [(Character, Character)] = [("[", "]"), ("【", "】"), ("(", ")"), ("（", "）"), ("<", ">"), ("〈", "〉")]
        guard let first = line.first, let last = line.last,
              pairs.contains(where: { $0.0 == first && $0.1 == last }) else { return false }
        let inner = line.dropFirst().dropLast().lowercased().trimmingCharacters(in: .whitespaces)
        if inner.isEmpty { return true }
        return sectionWords.contains { inner.hasPrefix($0) }
    }
}
