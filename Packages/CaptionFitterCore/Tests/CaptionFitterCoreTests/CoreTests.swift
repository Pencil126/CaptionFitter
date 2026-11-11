import Foundation
import Testing
@testable import CaptionFitterCore

/// Builds one-character-per-word timings, `step` seconds apart, starting at `start`.
private func words(_ text: String, start: Double = 0, step: Double = 0.5) -> [TimedWord] {
    text.filter { !$0.isWhitespace }.enumerated().map { index, character in
        TimedWord(text: String(character), start: start + Double(index) * step, end: start + Double(index + 1) * step)
    }
}

@Suite struct SequenceAlignerTests {
    @Test func exactScriptGetsRecognisedTimes() {
        let lines = SequenceAligner.align(scriptLines: ["今天天氣", "真的很好"], words: words("今天天氣真的很好"))
        #expect(lines.map(\.confidence) == [.good, .good])
        #expect(lines[0].start == 0)
        #expect(lines[1].start == 2)
        #expect(abs(lines[1].end - 4.25) < 0.001)
        #expect(lines[0].end <= lines[1].start)
    }

    @Test func traditionalScriptMatchesSimplifiedRecognition() {
        let lines = SequenceAligner.align(scriptLines: ["聽見風聲", "愛過這個國"], words: words("听见风声爱过这个国"))
        #expect(lines.map(\.confidence) == [.good, .good])
        #expect(lines[1].start == 2)
    }

    @Test func toleratesMisrecognisedAndExtraText() {
        // Leading noise, one wrong character in line 1, and an ad-lib between the lines.
        let recognised = words("啊啊今天天器真的喔喔喔很好", start: 10)
        let lines = SequenceAligner.align(scriptLines: ["今天天氣", "真的很好"], words: recognised)
        #expect(lines[0].start == 11) // skips "啊啊"
        #expect(lines[0].confidence == .good)
        #expect(lines[1].start == 13)
        #expect(lines[1].end >= 16.5)
    }

    @Test func unmatchedLineIsInterpolatedBetweenNeighbours() {
        let recognised = words("第一句話") + words("第三句話", start: 10)
        let lines = SequenceAligner.align(scriptLines: ["第一句話", "完全不同內容", "第三句話"], words: recognised)
        #expect(lines[1].confidence == .interpolated)
        #expect(lines[1].start >= lines[0].end)
        #expect(lines[1].end <= lines[2].start)
        #expect(lines[2].confidence == .good)
    }

    @Test func repeatedLinesMapToSuccessiveOccurrences() {
        let recognised = words("啦啦啦啦") + words("中間一段", start: 5) + words("啦啦啦啦", start: 10)
        let lines = SequenceAligner.align(scriptLines: ["啦啦啦啦", "中間一段", "啦啦啦啦"], words: recognised)
        #expect(lines[0].start == 0)
        #expect(lines[1].start == 5)
        #expect(lines[2].start == 10)
    }

    @Test func englishIgnoresCaseAndPunctuation() {
        let recognised = [
            TimedWord(text: " hello", start: 1, end: 1.5), TimedWord(text: " world", start: 1.5, end: 2),
            TimedWord(text: " Good", start: 3, end: 3.4), TimedWord(text: " morning.", start: 3.4, end: 4),
        ]
        let lines = SequenceAligner.align(scriptLines: ["Hello, World!", "good morning"], words: recognised)
        #expect(lines[0].start == 1)
        #expect(lines[1].start == 3)
        #expect(lines.allSatisfy { $0.confidence == .good })
    }

    @Test func timesAreMonotonicAndWithinMedia() {
        let recognised = words("甲乙丙丁戊己庚辛", step: 0.2)
        let lines = SequenceAligner.align(scriptLines: ["甲乙", "不存在", "丙丁", "也不存在", "庚辛"], words: recognised, mediaDuration: 2)
        for (previous, next) in zip(lines, lines.dropFirst()) {
            #expect(previous.start <= previous.end)
            #expect(previous.end <= next.start)
        }
        #expect(lines.last!.end <= 2)
    }

    @Test func emptyRecognitionStillReturnsEveryLine() {
        let lines = SequenceAligner.align(scriptLines: ["一", "二"], words: [], mediaDuration: 10)
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.confidence == .interpolated })
    }
}

@Suite struct ScriptSegmenterTests {
    @Test func keepsLineBreaksAndDropsBlankLines() {
        let lines = ScriptSegmenter.segment("第一行\n\n  第二行  \n", mode: .keepLineBreaks)
        #expect(lines == ["第一行", "第二行"])
    }

    @Test func splitsSentencesAndTrimsTrailingPunctuation() {
        let lines = ScriptSegmenter.segment("大家好，我是主持人。今天要談什麼？一起來看看！", mode: .automatic(maxWidth: 20))
        #expect(lines == ["大家好，我是主持人", "今天要談什麼？", "一起來看看！"])
    }

    @Test func longSentenceBreaksAtClauses() {
        let lines = ScriptSegmenter.segment("首先我們要了解背景，然後再討論解決的方法，最後做個總結。", mode: .automatic(maxWidth: 12))
        #expect(lines == ["首先我們要了解背景", "然後再討論解決的方法", "最後做個總結"])
        #expect(lines.allSatisfy { ScriptSegmenter.displayWidth($0) <= 12 })
    }

    @Test func unpunctuatedTextIsWrappedEvenly() {
        let lines = ScriptSegmenter.segment("一二三四五六七八九十一二三四五六七八九十一", mode: .automatic(maxWidth: 10))
        #expect(lines.count == 3)
        #expect(lines.joined() == "一二三四五六七八九十一二三四五六七八九十一")
        #expect(lines.allSatisfy { $0.count >= 6 })
    }

    @Test func englishWrapsBetweenWordsAndKeepsDecimals() {
        let lines = ScriptSegmenter.segment("Version 3.5 is out. It is a really big release with many improvements", mode: .automatic(maxWidth: 15))
        #expect(lines.first == "Version 3.5 is out")
        #expect(lines.dropFirst().joined(separator: " ") == "It is a really big release with many improvements")
    }
}

@Suite struct LyricsCleanerTests {
    @Test func removesCreditsAndSectionMarkers() {
        let text = """
        作詞：某某
        作曲: 某某
        Lyrics by: Someone
        [副歌]
        【Verse 1】
        故事的小黃花

        (Chorus x2)
        從出生那年就飄著
        (Oh yeah)
        """
        #expect(LyricsCleaner.clean(text) == ["故事的小黃花", "從出生那年就飄著", "(Oh yeah)"])
    }

    @Test func expandsRepeatedLRCLinesInSungOrder() {
        let lrc = """
        [ar:歌手]
        [ti:歌名]
        [00:10.00]第一句
        [00:20.00][01:00.50]副歌
        [00:30.00]第二句
        [00:40.00]
        """
        let parsed = LyricsCleaner.parseLRC(lrc)
        #expect(parsed.map(\.text) == ["第一句", "副歌", "第二句", "", "副歌"])
        #expect(parsed.last?.time == 60.5)
        #expect(LyricsCleaner.clean(lrc) == ["第一句", "副歌", "第二句", "副歌"])
    }

    @Test func detectsLRC() {
        #expect(LyricsCleaner.isLRC("[00:12.34]歌詞"))
        #expect(!LyricsCleaner.isLRC("[副歌]\n歌詞"))
    }
}

@Suite struct LRCLIBTests {
    @Test func decodesAndRanksByDuration() throws {
        let json = """
        [
          {"id":1,"trackName":"歌","artistName":"甲","albumName":null,"duration":300,"instrumental":false,"plainLyrics":"a","syncedLyrics":null},
          {"id":2,"trackName":"歌","artistName":"甲","duration":241.5,"instrumental":false,"plainLyrics":null,"syncedLyrics":"[00:01.00]b"},
          {"id":3,"trackName":"歌 (Instrumental)","artistName":"甲","duration":240,"instrumental":true,"plainLyrics":null,"syncedLyrics":null},
          {"id":4,"trackName":"歌","artistName":"乙","duration":239,"instrumental":false,"plainLyrics":"","syncedLyrics":null}
        ]
        """
        let results = try JSONDecoder().decode([LyricsSearchResult].self, from: Data(json.utf8))
        #expect(results.count == 4)
        let ranked = LRCLIBClient.rank(results, mediaDuration: 240)
        #expect(ranked.map(\.id) == [2, 1]) // instrumental and empty entries dropped, closest first
        #expect(ranked[0].lyricsText == "[00:01.00]b")
        #expect(LRCLIBClient.rank(results, mediaDuration: nil).map(\.id) == [1, 2])
    }
}

@Suite struct SRTWriterTests {
    @Test func formatsTimestamps() {
        #expect(SRTWriter.timestamp(0) == "00:00:00,000")
        #expect(SRTWriter.timestamp(3661.0409) == "01:01:01,041")
        #expect(SRTWriter.timestamp(59.9996) == "00:01:00,000")
    }

    @Test func writesNumberedBlocksSkippingEmptyLines() {
        let lines = [
            SubtitleLine(start: 1, end: 2.5, text: "第一句"),
            SubtitleLine(start: 3, end: 4, text: "  "),
            SubtitleLine(start: 5, end: 6, text: "第二句"),
        ]
        #expect(SRTWriter.string(from: lines) == "1\n00:00:01,000 --> 00:00:02,500\n第一句\n\n2\n00:00:05,000 --> 00:00:06,000\n第二句\n\n")
    }
}

@Suite struct SRTRoundTripTests {
    @Test func parsesWhatItWrites() {
        let original = [
            SubtitleLine(start: 1.25, end: 2.5, text: "第一句"),
            SubtitleLine(start: 3661.041, end: 3662, text: "two\nlines"),
        ]
        let parsed = SRTWriter.parse(SRTWriter.string(from: original))
        #expect(parsed.map(\.text) == ["第一句", "two\nlines"])
        #expect(parsed.map(\.start) == [1.25, 3661.041])
        #expect(parsed.map(\.end) == [2.5, 3662])
        #expect(SRTWriter.parse("garbage\n\n1\nnot a time\ntext").isEmpty)
    }
}

@Suite struct SubtitleDocumentTests {
    private func document() -> SubtitleDocument {
        SubtitleDocument(lines: [
            SubtitleLine(start: 0, end: 2, text: "第一句話"),
            SubtitleLine(start: 2, end: 4, text: "第二句話"),
            SubtitleLine(start: 6, end: 8, text: "third line"),
        ])
    }

    @Test func splitDividesTextAndTime() {
        var doc = document()
        let id = doc.lines[0].id
        doc.split(id, atCharacter: 1)
        #expect(doc.lines.count == 4)
        #expect(doc.lines[0].text == "第")
        #expect(doc.lines[1].text == "一句話")
        #expect(doc.lines[0].end == 0.5)
        #expect(doc.lines[1].start == 0.5)
        #expect(doc.lines[1].end == 2)
    }

    @Test func mergeJoinsTextAndSpansBothLines() {
        var doc = document()
        doc.mergeWithNext(doc.lines[0].id)
        #expect(doc.lines.count == 2)
        #expect(doc.lines[0].text == "第一句話第二句話")
        #expect(doc.lines[0].end == 4)
    }

    @Test func shiftAllClampsAtZeroAndKeepsDurations() {
        var doc = document()
        doc.shiftAll(by: -1)
        #expect(doc.lines.map(\.start) == [0, 1, 5])
        #expect(doc.lines.map(\.duration) == [2, 2, 2])
    }

    @Test func retimingKeepsOrderAndMinimumDuration() {
        var doc = document()
        let first = doc.lines[0].id
        doc.setStart(5, for: first)
        #expect(doc.lines.map(\.text) == ["第二句話", "第一句話", "third line"])
        #expect(doc.lines[1].end >= 5 + SubtitleDocument.minimumDuration)
        doc.setEnd(0, for: first)
        #expect(doc.lines[1].duration >= SubtitleDocument.minimumDuration - 0.0001)
        #expect(doc.lines[1].confidence == .manual)
    }

    @Test func insertAndDelete() {
        var doc = document()
        let new = doc.insertLine(after: doc.lines[1].id)
        #expect(doc.index(of: new) == 2)
        #expect(doc.lines[2].start == 4)
        #expect(doc.lines[2].end == 6)
        doc.delete(new)
        #expect(doc.lines.count == 3)
    }

    @Test func findsLineAtTime() {
        let doc = document()
        #expect(doc.line(at: 2.5)?.text == "第二句話")
        #expect(doc.line(at: 5) == nil)
    }
}

@Suite struct AlignmentReportTests {
    @Test func warnsWhenManyLinesAreDoubtfulOrScriptEndsEarly() {
        let lines = [
            SubtitleLine(start: 0, end: 1, text: "a", confidence: .good),
            SubtitleLine(start: 1, end: 2, text: "b", confidence: .interpolated),
            SubtitleLine(start: 2, end: 3, text: "c", confidence: .partial),
        ]
        let report = AlignmentReport(lines: lines, mediaDuration: 100, scriptDuration: 80)
        #expect(report.interpolatedLines == 1)
        #expect(report.warnings.count == 3)

        let clean = AlignmentReport(lines: [SubtitleLine(start: 0, end: 90, text: "a", confidence: .good)], mediaDuration: 100)
        #expect(!clean.hasWarnings)
    }
}

@Suite struct ForcedAlignerHelperTests {
    @Test func speechTextDropsLayoutSpacesButKeepsWordSpaces() {
        #expect(WhisperRecognizer.speechText("如果那麼痛 能不能讓我放手") == "如果那麼痛能不能讓我放手")
        #expect(WhisperRecognizer.speechText("準備幾個Plan B") == "準備幾個Plan B")
        #expect(WhisperRecognizer.speechText("hello world") == "hello world")
    }

    @Test func unheardLinesAreParkedAndFlagged() {
        let timed: [SubtitleLine?] = [
            nil,
            SubtitleLine(start: 12, end: 14, text: "b", confidence: .good),
            nil,
            SubtitleLine(start: 20, end: 22, text: "d", confidence: .good),
        ]
        let lines = WhisperRecognizer.assemble(timed, lines: ["a", "b", "c", "d"], duration: 30)
        #expect(lines.map(\.confidence) == [.interpolated, .good, .interpolated, .good])
        #expect(lines[0].start == 0)
        #expect(lines[0].duration == 0)      // not shown until given a time
        #expect(lines[2].duration == 0)
        #expect(!SRTWriter.string(from: lines).contains("\na\n"))
        #expect(lines[1].start == 12)
        #expect(lines[2].start >= lines[1].end)
        #expect(lines[2].end <= 20)
        #expect(lines[3].end <= 30)
        for (a, b) in zip(lines, lines.dropFirst()) { #expect(a.end <= b.start) }
    }
}
