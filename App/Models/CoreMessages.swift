import CaptionFitterCore
import Foundation

/// User-facing wording for what the core package reports. The core package returns
/// structured values and English fallbacks; the sentences shown in the app live here, so
/// every translation is in the app's string catalog.
enum CoreMessages {
    static func text(for warning: AlignmentReport.Warning) -> String {
        switch warning {
        case let .mostLinesUnmatched(doubtful, total):
            return String(localized: "Most subtitles (\(doubtful) of \(total) lines) don't match the audio. The transcript may not match the video, or the wrong language may be selected.")
        case let .someLinesUncertain(doubtful, total):
            return String(localized: "The timing of \(doubtful) of \(total) subtitle lines is uncertain. They're marked in the list; check them one by one.")
        case let .endsEarly(percent):
            return String(localized: "The subtitles end at \(percent)% of the video. The transcript may be incomplete (for example, a repeated section written only once).")
        case let .lyricsLengthMismatch(seconds, likelyDifferentVersion):
            return likelyDifferentVersion
                ? String(localized: "The chosen lyrics differ in length from the video by \(seconds) seconds and may be a different version.")
                : String(localized: "The chosen lyrics differ in length from the video by \(seconds) seconds.")
        }
    }

    /// The message for an error, in the user's language. Errors from the system are
    /// already localized by macOS and pass through unchanged.
    static func message(for error: Error) -> String {
        switch error {
        case let error as AlignerError:
            switch error {
            case .emptyScript: return String(localized: "The transcript is empty.")
            case .noSpeechFound: return String(localized: "No voice was found in this file.")
            }
        case let error as AudioExtractor.ExtractionError:
            switch error {
            case .noAudioTrack: return String(localized: "This file has no audio track.")
            case .unsupportedFormat: return String(localized: "Can't read the audio: the format isn't supported.")
            case .readFailed(let reason?): return String(localized: "Can't read the audio: \(reason)")
            case .readFailed(nil): return String(localized: "Can't read the audio.")
            }
        case let error as SubtitleBurner.BurnError:
            switch error {
            case .noVideoTrack: return String(localized: "This file has no video track, so subtitles can't be burned in.")
            case .cannotExport: return String(localized: "Can't start exporting the video.")
            case .exportFailed(let reason): return String(localized: "Video export failed: \(reason)")
            }
        case let error as LRCLIBClient.ClientError:
            switch error {
            case .badResponse(let code): return String(localized: "The lyrics database returned an error (HTTP \(code)).")
            }
        default:
            return error.localizedDescription
        }
    }

    /// Language names are shown in their own language, so only "auto" needs translating.
    static func languageName(_ language: SpeechLanguage) -> String {
        language.id == "auto" ? String(localized: "Detect Automatically", comment: "Speech language option") : language.displayName
    }
}
