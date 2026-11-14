import Foundation

/// How well a subtitle line was matched against the recognised speech.
public enum LineConfidence: String, Codable, Sendable {
    /// Most of the line was found in the recognised speech.
    case good
    /// Only part of the line was found; timing is approximate.
    case partial
    /// Nothing matched; timing was interpolated from neighbouring lines.
    case interpolated
    /// The line was created or retimed by hand.
    case manual
    /// The line is not from the script: it was transcribed from speech the script does not cover.
    case transcribed
}

public struct SubtitleLine: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public var confidence: LineConfidence

    public init(id: UUID = UUID(), start: Double, end: Double, text: String, confidence: LineConfidence = .manual) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.confidence = confidence
    }

    public var duration: Double { max(0, end - start) }
}

/// An editable list of subtitle lines. All editing operations keep lines sorted by start time.
public struct SubtitleDocument: Equatable, Codable, Sendable {
    public static let minimumDuration: Double = 0.1

    public var lines: [SubtitleLine]

    public init(lines: [SubtitleLine] = []) {
        self.lines = lines
    }

    public func index(of id: SubtitleLine.ID) -> Int? {
        lines.firstIndex { $0.id == id }
    }

    /// The line that should be shown at `time`, if any.
    public func line(at time: Double) -> SubtitleLine? {
        lines.last { $0.start <= time && time < $0.end }
    }

    public mutating func setText(_ text: String, for id: SubtitleLine.ID) {
        guard let i = index(of: id) else { return }
        lines[i].text = text
    }

    public mutating func setStart(_ start: Double, for id: SubtitleLine.ID) {
        guard let i = index(of: id) else { return }
        let value = max(0, start)
        lines[i].start = value
        if lines[i].end < value + Self.minimumDuration {
            lines[i].end = value + Self.minimumDuration
        }
        lines[i].confidence = .manual
        sort()
    }

    public mutating func setEnd(_ end: Double, for id: SubtitleLine.ID) {
        guard let i = index(of: id) else { return }
        lines[i].end = max(lines[i].start + Self.minimumDuration, end)
        lines[i].confidence = .manual
    }

    public mutating func nudgeStart(by delta: Double, for id: SubtitleLine.ID) {
        guard let i = index(of: id) else { return }
        setStart(lines[i].start + delta, for: id)
    }

    public mutating func nudgeEnd(by delta: Double, for id: SubtitleLine.ID) {
        guard let i = index(of: id) else { return }
        setEnd(lines[i].end + delta, for: id)
    }

    /// Moves every line by `delta` seconds, clamping at zero.
    public mutating func shiftAll(by delta: Double) {
        for i in lines.indices {
            let duration = lines[i].duration
            lines[i].start = max(0, lines[i].start + delta)
            lines[i].end = lines[i].start + max(duration, Self.minimumDuration)
        }
    }

    /// Inserts an empty line after `id` (or at `time` when `id` is nil). Returns the new line's id.
    @discardableResult
    public mutating func insertLine(after id: SubtitleLine.ID?, at time: Double? = nil, defaultDuration: Double = 2) -> SubtitleLine.ID {
        var start = time ?? 0
        if time == nil, let id, let i = index(of: id) {
            start = lines[i].end
        }
        var end = start + defaultDuration
        if let next = lines.first(where: { $0.start > start }) {
            end = max(start + Self.minimumDuration, min(end, next.start))
        }
        let line = SubtitleLine(start: start, end: end, text: "", confidence: .manual)
        lines.append(line)
        sort()
        return line.id
    }

    /// Adds already timed lines, keeping the list in time order.
    public mutating func insert(_ newLines: [SubtitleLine]) {
        lines.append(contentsOf: newLines)
        sort()
    }

    /// Whether any visible subtitle sits inside `range`.
    public func hasLines(in range: ClosedRange<Double>) -> Bool {
        lines.contains { $0.duration > 0 && range.contains(($0.start + $0.end) / 2) }
    }

    /// Clears the "needs a look" state of a line the user has checked.
    public mutating func markReviewed(_ id: SubtitleLine.ID) {
        guard let i = index(of: id) else { return }
        lines[i].confidence = .manual
    }

    public mutating func delete(_ id: SubtitleLine.ID) {
        lines.removeAll { $0.id == id }
    }

    /// Splits a line in two at a character offset. The split time is proportional to the
    /// text length unless `time` (which must fall inside the line) is given.
    @discardableResult
    public mutating func split(_ id: SubtitleLine.ID, atCharacter offset: Int? = nil, time: Double? = nil) -> SubtitleLine.ID? {
        guard let i = index(of: id) else { return nil }
        let line = lines[i]
        let characters = Array(line.text)
        guard characters.count >= 2 else { return nil }
        let cut = min(max(offset ?? characters.count / 2, 1), characters.count - 1)
        let first = String(characters[..<cut]).trimmingCharacters(in: .whitespaces)
        let second = String(characters[cut...]).trimmingCharacters(in: .whitespaces)

        var splitTime = line.start + line.duration * Double(cut) / Double(characters.count)
        if let time, time > line.start + Self.minimumDuration, time < line.end - Self.minimumDuration {
            splitTime = time
        }
        lines[i].text = first
        lines[i].end = splitTime
        let newLine = SubtitleLine(start: splitTime, end: line.end, text: second, confidence: line.confidence)
        lines.insert(newLine, at: i + 1)
        return newLine.id
    }

    /// Merges a line with the one that follows it.
    public mutating func mergeWithNext(_ id: SubtitleLine.ID) {
        guard let i = index(of: id), i + 1 < lines.count else { return }
        let next = lines[i + 1]
        let needsSpace = (lines[i].text.last?.isASCII ?? false) && (next.text.first?.isASCII ?? false)
        lines[i].text += (needsSpace ? " " : "") + next.text
        lines[i].end = max(lines[i].end, next.end)
        if next.confidence != lines[i].confidence { lines[i].confidence = .manual }
        lines.remove(at: i + 1)
    }

    private mutating func sort() {
        lines.sort { ($0.start, $0.end) < ($1.start, $1.end) }
    }
}
