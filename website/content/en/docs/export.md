---
title: Export
description: Save an SRT subtitle file, a video with subtitles, or both.
order: 5
---

When you have reviewed the subtitles, click **Export** in the toolbar, or choose File › **Export…** (⌘E).

## Choose what to export

Under **Content**, choose:

- **SRT subtitle file**: a plain-text subtitle file in UTF-8. The video itself isn't changed, and most players and video platforms can read it.
- **Video with subtitles (MP4)**: a new video with the subtitles drawn onto the picture, using your subtitle style.
- **Both**

For an audio file, only an SRT subtitle file can be exported.

## Video quality and frame rate

For a video with subtitles, the **Video** section offers:

- **Resolution**: **Original**, 1080p, 720p, or 480p
- **Frame Rate**: **Original**, 60 fps, or 30 fps

Only options lower than the original video are listed. Export never upscales the picture or interpolates frames. The app remembers your choices.

## Save the files

Click **Export…**. A save dialog opens for each file: **Save SRT Subtitle File**, then **Save Video with Subtitles**. The first dialog opens in the original file's folder. The SRT file is named after the original, and the video gets `-subtitled` added to the name. If you cancel a dialog, nothing is written. The exported video can't replace the original.

The progress of a video export appears at the bottom of the left panel; click **Cancel** to stop it. When the export finishes, the file is shown in Finder.

Subtitles in an exported video are part of the picture and can't be turned off or edited afterward. To change them, edit them in CaptionFitter and export again.

## Lines that are skipped

These lines are left out of both the SRT file and the video:

- Lines marked **Not found** (red dot) that still have no time
- Lines with no text

To include a not-found line, give it a start and end time in the editor first.
