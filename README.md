<p align="center">
    <img src="App/AppIcon.icon/Assets/CaptionFitter.png" width="128" alt="CaptionFitter app icon">
</p>

<h1 align="center">CaptionFitter</h1>

<center>**English** | [繁體中文](README.zh-TW.md)</center>

A macOS app that aligns a transcript to the voice in a video and turns it into subtitles. It works for both spoken-word videos and songs. Everything is processed on your Mac; your video is never uploaded.

## Features

- **Transcript sources**: paste a transcript, transcribe automatically (the model listens when you have no transcript), or search for lyrics (LRCLIB)
- **Selectable language** to improve recognition accuracy
- **Preview and subtitle editor**: edit text, adjust timing, split and merge lines, shift everything at once, with undo support
- **Export**: an SRT subtitle file, a new video with the subtitles burned in, or both
- **Model management**: download and delete on-device speech models, and choose which one to use
- **English and Traditional Chinese interface**: follows your Mac's language; any other language shows English. To pick one for this app only, go to System Settings › General › Language & Region › Applications

## Keyboard shortcuts

| Key | Action |
|---|---|
| Space | Play / pause |
| ⇧← / ⇧→ | Skip backward / forward (5 seconds by default; adjustable from 1 to 15 seconds in Settings) |
| ← / → | Previous frame / next frame |
| ⌘E | Export |
| ⌘, | Settings |

While you are typing subtitle text, the arrow keys move the cursor and select text instead of moving the playhead.

## Requirements

- macOS 26 or later, Apple Silicon
- Xcode 26 or later

## Building

Open `CaptionFitter.xcodeproj` in Xcode and run it, or:

```bash
xcodebuild -project CaptionFitter.xcodeproj -scheme CaptionFitter -configuration Debug -derivedDataPath .build/xcode build
```

Before first use, open Settings (⌘,) and download a speech model.

## Project structure

- `App/`: the SwiftUI interface
- `Packages/CaptionFitterCore/`: the core logic (alignment, transcript line breaking, lyrics search, model management, SRT, burn-in export). Its only third-party dependency is [WhisperKit](https://github.com/argmaxinc/WhisperKit)

## Testing

```bash
cd Packages/CaptionFitterCore && swift test
```

The core package includes a command-line tool for testing without opening the app:

```bash
cd Packages/CaptionFitterCore && swift run captionfitter-cli
```

## Export

After aligning and reviewing the subtitles, click Export (⌘E) in the toolbar and choose an SRT subtitle file, a video with subtitles, or both. Lines marked as not found in the audio (red dot) and lines with no text are not exported.

### SRT subtitle file

A plain-text subtitle file in UTF-8. The video itself is not modified, and most players and video platforms can read the file.

Each subtitle consists of a sequence number, start and end times (`hours:minutes:seconds,milliseconds`), and the text, with a blank line between subtitles:

```
1
00:00:11,700 --> 00:00:14,250
First subtitle line

2
00:00:14,250 --> 00:00:17,800
Second subtitle line
```

### Video with burned-in subtitles (MP4)

The subtitles are drawn directly onto the picture and saved as a new video file. The default file name is `<original name>-subtitled.mp4` (`<original name>-字幕.mp4` in the Chinese interface).

When exporting, you can choose the quality (original, 1080p, 720p, 480p) and frame rate (original, 60, 30 fps). Only options lower than the original video are listed; export never upscales the picture or interpolates frames.

The subtitle font, size, text and outline colors, shadow, and vertical position can be set under Subtitle Style. What the preview shows is what gets exported. Burned-in subtitles cannot be turned off or edited afterward; to change them, go back to the app and export again. This option is not available for audio-only files.
