import CoreGraphics
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
        #expect(report.warnings == [
            .mostLinesUnmatched(doubtful: 2, total: 3),
            .endsEarly(percent: 3),
            .lyricsLengthMismatch(seconds: 20, likelyDifferentVersion: true),
        ])

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

@Suite struct CrossCheckTests {
    private let script = ["習慣說沒事 不只一天兩天", "沒對錯的答案 用一生諒解", "總覺得做什麼都錯", "習慣地想找人求救"]

    private func segment(_ start: Double, _ end: Double, _ text: String, _ confidence: Double) -> RecognizedSegment {
        RecognizedSegment(start: start, end: end, text: text, words: [TimedWord(text: text, start: start, end: end)], confidence: confidence)
    }

    /// Clearly heard talk between two sung passages.
    private var talk: [RecognizedSegment] {
        [
            segment(20.0, 21.0, "大家好今天很開心", 0.5),          // fast but unsure: joins the talk
            segment(21.2, 22.4, "可以不要去懷疑自己", 0.9),
            segment(22.8, 24.0, "或者每一個選擇", 0.8),
            segment(24.3, 25.0, "你們做什麼都錯", 0.7),            // quotes the script
            segment(25.4, 26.9, "可以去相信你們自己", 0.9),
            segment(27.2, 28.4, "這首歌希望你們會喜歡", 0.8),
        ]
    }

    @Test func findsTalkThatIsNotInTheScript() {
        let sung = [
            segment(10, 13, "习惯说每次不是一千两千", 0.9),            // mis-heard, but it is the script
            segment(13.5, 18, "从这代理想爱我才喜欢的世界", 0.9),      // confident nonsense at a singing pace
            segment(30, 34, "我愁着有谁难受我", 0.5),
        ]
        let regions = CrossCheck.unscriptedRegions(in: sung + talk, scriptLines: script)
        #expect(regions.count == 1)
        #expect(regions.first?.lowerBound == 20.0)
        #expect(regions.first?.upperBound == 28.4)
    }

    @Test func aShortRemarkIsNotEnough() {
        let remark = [segment(20, 21.5, "謝謝大家今天來", 0.95)]
        #expect(CrossCheck.unscriptedRegions(in: remark, scriptLines: script).isEmpty)
    }

    @Test func speechFollowingTheScriptIsNotARegion() {
        let read = [
            segment(0, 2, "習慣說沒事不只一天兩天", 0.95),
            segment(2.2, 4, "沒對錯的答案用一生諒解", 0.95),
            segment(4.2, 5.5, "總覺得做什麼都錯", 0.95),
            segment(5.7, 7, "習慣地想找人求救", 0.95),
        ]
        #expect(CrossCheck.unscriptedRegions(in: read, scriptLines: script).isEmpty)
    }

    @Test func repeatedNonsenseIsIgnored() {
        let loop = [segment(5, 25, String(repeating: "作曲", count: 60), 0.9)]
        #expect(CrossCheck.unscriptedRegions(in: loop, scriptLines: script).isEmpty)
        #expect(CrossCheck.isRepetitive(Array(String(repeating: "烟", count: 30))))
        #expect(!CrossCheck.isRepetitive(Array("可以不要去懷疑自己或者每一個選擇")))
    }

    @Test func chanceOverlapDoesNotCountAsScript() {
        let lines = script.map(SequenceAligner.comparisonCharacters)
        #expect(!CrossCheck.resemblesScript(SequenceAligner.comparisonCharacters("相信你們自己"), script: lines))
        #expect(CrossCheck.resemblesScript(SequenceAligner.comparisonCharacters("习惯说每次不是一千两千"), script: lines))
    }

    @Test func unheardSpansCoverGapsAndLoops() {
        let segments = [
            segment(9, 12, "習慣說沒事", 0.8),
            segment(12.5, 40, String(repeating: "作曲", count: 60), 0.9),
            segment(41, 44, "總覺得做什麼都錯", 0.8),
        ]
        let spans = CrossCheck.unheardSpans(in: segments, duration: 47)
        #expect(spans == [0.0...9.0, 12.0...41.0])
    }

    @Test func agreementLooksOnlyNearTheLine() {
        let words = [
            TimedWord(text: "习惯说每次", start: 10, end: 12),
            TimedWord(text: "总觉得做什么都错", start: 40, end: 43),
        ]
        let near = CrossCheck.agreement(line: "習慣說沒事 不只一天兩天", words: words, start: 10, end: 13)
        #expect(near.matched == 3)
        #expect(near.total == 11)
        let far = CrossCheck.agreement(line: "總覺得做什麼都錯", words: words, start: 10, end: 13)
        #expect(far.matched == 0)
    }

    @Test func reviewFlagsStretchedLinesAndTrustsConfirmedOnes() {
        var lines: [SubtitleLine?] = [
            SubtitleLine(start: 0, end: 2, text: "習慣說沒事", confidence: .partial),
            SubtitleLine(start: 2, end: 4, text: "沒對錯的答案", confidence: .good),
            SubtitleLine(start: 4, end: 20, text: "總覺得做什麼都錯", confidence: .good),
            nil,
        ]
        let heard = Recognition(segments: [segment(0, 2, "习惯说没事", 0.9)], language: "zh")
        WhisperRecognizer.review(&lines, paces: [0.4, 0.4, 2.0, nil], heard: heard)
        #expect(lines[0]?.confidence == .good)      // the free transcription heard the same words
        #expect(lines[1]?.confidence == .good)
        #expect(lines[2]?.confidence == .partial)   // five times slower than the others
        #expect(lines[3] == nil)
    }
}

@Suite struct UnscriptedSpeechTests {
    private func recognition(_ text: String, start: Double, step: Double = 0.2) -> Recognition {
        let words = text.enumerated().map { index, character in
            TimedWord(text: String(character), start: start + Double(index) * step, end: start + Double(index + 1) * step)
        }
        return Recognition(segments: [RecognizedSegment(start: start, end: start + Double(text.count) * step, text: text, words: words)], language: "zh")
    }

    @Test func transcribedLinesAreShiftedAndMarked() {
        let lines = CaptionBuilder.transcribe(
            recognition("大家好谢谢你们", start: 1), offset: 100, within: 100...110, maxWidth: 16, traditionalChinese: true
        )
        #expect(lines.map(\.text) == ["大家好謝謝你們"])
        #expect(abs(lines[0].start - 101) < 0.01)
        // The last word ends at 102.4; a line may linger briefly after it.
        #expect(lines[0].end >= 102.39 && lines[0].end <= 103)
        #expect(lines[0].confidence == .transcribed)
    }

    @Test func transcribedLinesStayInsideTheRegion() {
        // Heard at 99.5–100.9 and 111–112.4; the region is 100–110.
        let early = CaptionBuilder.transcribe(recognition("大家好谢谢你们", start: 0.5), offset: 99, within: 100...110, maxWidth: 16, traditionalChinese: false)
        #expect(early.count == 1)
        #expect(early[0].start == 100)
        let late = CaptionBuilder.transcribe(recognition("大家好谢谢你们", start: 12), offset: 99, within: 100...110, maxWidth: 16, traditionalChinese: false)
        #expect(late.isEmpty)
    }

    @Test func nothingHeardGivesNoLines() {
        let empty = Recognition(segments: [], language: "zh")
        #expect(CaptionBuilder.transcribe(empty, offset: 0, within: 0...10, maxWidth: 16, traditionalChinese: false).isEmpty)
    }

    @Test func insertedLinesAreSortedAndFound() {
        var document = SubtitleDocument(lines: [
            SubtitleLine(start: 0, end: 2, text: "a", confidence: .good),
            SubtitleLine(start: 2, end: 2, text: "missing", confidence: .interpolated),
            SubtitleLine(start: 20, end: 22, text: "b", confidence: .good),
        ])
        #expect(!document.hasLines(in: 1.5...12))
        document.insert([SubtitleLine(start: 6, end: 8, text: "y", confidence: .transcribed), SubtitleLine(start: 4, end: 6, text: "x", confidence: .transcribed)])
        #expect(document.lines.map(\.text) == ["a", "missing", "x", "y", "b"])
        #expect(document.hasLines(in: 3...12))
    }
}

@Suite struct ExportOptionTests {
    @Test func resolutionFollowsTheShortSideAndKeepsTheShape() {
        let landscape = VideoInfo(size: CGSize(width: 1920, height: 1080), frameRate: 60)
        #expect(VideoExportOptions(resolution: .p720).renderSize(for: landscape) == CGSize(width: 1280, height: 720))
        #expect(VideoExportOptions(resolution: .p480).renderSize(for: landscape) == CGSize(width: 854, height: 480))
        let upright = VideoInfo(size: CGSize(width: 1080, height: 1920), frameRate: 30)
        #expect(VideoExportOptions(resolution: .p720).renderSize(for: upright) == CGSize(width: 720, height: 1280))
    }

    @Test func neverEnlargesOrAddsFrames() {
        let small = VideoInfo(size: CGSize(width: 1280, height: 720), frameRate: 29.97)
        #expect(VideoExportOptions(resolution: .p1080).renderSize(for: small) == small.size)
        #expect(VideoExportOptions(resolution: .p720).renderSize(for: small) == small.size)
        #expect(!VideoExportOptions.applies(.p720, to: small))
        #expect(VideoExportOptions.applies(.p480, to: small))
        #expect(VideoExportOptions(frameRate: .fps60).framesPerSecond(for: small) == nil)
        #expect(VideoExportOptions(frameRate: .fps30).framesPerSecond(for: small) == nil)
        let fast = VideoInfo(size: small.size, frameRate: 59.94)
        #expect(VideoExportOptions(frameRate: .fps30).framesPerSecond(for: fast) == 30)
    }

    @Test func styleSavedByAnEarlierVersionStillLoads() throws {
        let old = #"{"fontName":"Helvetica","fontScale":0.08,"textColor":{"red":1,"green":1,"blue":0,"alpha":1},"outlineColor":{"red":0,"green":0,"blue":0,"alpha":1},"outlineScale":0.1,"position":"top","marginScale":0.1}"#
        let style = try JSONDecoder().decode(SubtitleStyle.self, from: Data(old.utf8))
        #expect(style.fontName == "Helvetica")
        #expect(style.shadow == .none)
        #expect(abs(style.verticalPosition - 0.9) < 0.0001)
        let again = try JSONDecoder().decode(SubtitleStyle.self, from: JSONEncoder().encode(style))
        #expect(again == style)
    }

    @Test func subtitleStaysInsideThePicture() throws {
        let size = CGSize(width: 1280, height: 720)
        for position in [0.0, 0.5, 1.0] {
            let style = SubtitleStyle(shadow: .strong, verticalPosition: position)
            let rendered = try #require(SubtitleRenderer.render(text: "測試字幕", style: style, videoSize: size))
            #expect(rendered.frame.minY >= 0 && rendered.frame.maxY <= size.height)
        }
        let low = try #require(SubtitleRenderer.render(text: "測試", style: SubtitleStyle(verticalPosition: 0.1), videoSize: size))
        let high = try #require(SubtitleRenderer.render(text: "測試", style: SubtitleStyle(verticalPosition: 0.9), videoSize: size))
        #expect(high.frame.midY > low.frame.midY)
    }

    /// Each platform hands Core Text its own font and color classes; both have to be honoured.
    @Test func textIsDrawnInTheStyleColors() throws {
        let style = SubtitleStyle(
            textColor: RGBAColor(red: 1, green: 0, blue: 0),
            outlineColor: RGBAColor(red: 0, green: 0, blue: 1),
            outlineScale: 0.1
        )
        let image = try #require(SubtitleRenderer.render(text: "測試", style: style, videoSize: CGSize(width: 1280, height: 720))).image
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        var red = 0, blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 200 {
            if pixels[index] > 200 && pixels[index + 2] < 60 { red += 1 }
            if pixels[index + 2] > 200 && pixels[index] < 60 { blue += 1 }
        }
        #expect(red > 100)
        #expect(blue > 100)
    }
}

@Suite struct ReviewTests {
    @Test func markingALineReviewedClearsItsState() {
        var document = SubtitleDocument(lines: [
            SubtitleLine(start: 0, end: 2, text: "a", confidence: .partial),
            SubtitleLine(start: 2, end: 2, text: "b", confidence: .interpolated),
        ])
        document.markReviewed(document.lines[0].id)
        #expect(document.lines.map(\.confidence) == [.manual, .interpolated])
        #expect(document.lines[0].start == 0 && document.lines[0].end == 2)
    }
}

@Suite struct FontFaceTests {
    @Test func facesAreUprightAndOrderedByWeight() {
        let faces = FontFaces.faces(ofFamily: "Helvetica Neue")
        #expect(faces.count >= 4)
        #expect(faces.map(\.weight) == faces.map(\.weight).sorted())
        #expect(!faces.contains { $0.postScriptName.contains("Italic") || $0.postScriptName.contains("Condensed") })
    }

    @Test func picksTheChosenFaceOrTheNearestWeight() {
        #expect(FontFaces.resolve(family: "Helvetica Neue", weight: 9, face: nil)?.postScriptName == "HelveticaNeue-Bold")
        #expect(FontFaces.resolve(family: "Helvetica Neue", weight: 9, face: "HelveticaNeue-Light")?.postScriptName == "HelveticaNeue-Light")
        // A face from another family is ignored; the weight decides.
        #expect(FontFaces.resolve(family: "Helvetica Neue", weight: 5, face: "ArialMT")?.postScriptName == "HelveticaNeue")
        // PingFang has no bold; the heaviest it has is used.
        #expect(FontFaces.resolve(family: "PingFang TC", weight: 9, face: nil)?.postScriptName == "PingFangTC-Semibold")
        #expect(FontFaces.resolve(family: "No Such Family", weight: 9, face: nil) == nil)
    }

    #if os(macOS)
    /// Other platforms list faces through Core Text, which has to agree with what the Mac shows.
    @Test func coreTextListingMatchesAppKit() {
        for family in ["Helvetica Neue", "PingFang TC", "Arial", "No Such Family"] {
            #expect(FontFaces.uprightFaces(FontFaces.coreTextMembers(ofFamily: family)) == FontFaces.faces(ofFamily: family))
        }
    }
    #endif

    @Test func styleUsesTheChosenWeight() {
        let light = SubtitleStyle(fontName: "Helvetica Neue", fontWeight: 3).font(videoHeight: 720)
        let bold = SubtitleStyle(fontName: "Helvetica Neue").font(videoHeight: 720)
        #expect(light.fontName != bold.fontName)
        #expect(bold.fontName == "HelveticaNeue-Bold")
    }
}
