---
title: Transcript sources
description: Paste a transcript, transcribe automatically, or search lyrics, and choose the language.
order: 2
---

Choose where the subtitle text comes from under **Transcript** in the left panel: **Paste**, **Transcribe**, or **Lyrics**.

## Paste a transcript

Choose **Paste** and paste your text into the box.

- With **Break Lines Automatically** off (the default), each line of the transcript becomes one subtitle line.
- With it on, the text is split into subtitle lines by punctuation and length. Set the limit with **Up to 16 characters per line**: 16 by default, adjustable from 8 to 40.

The number of subtitle lines the transcript will produce is shown below the box.

If the text carries LRC time tags such as `[01:23.45]`, the tags are removed and each line is aligned again from the audio.

Your transcript is used exactly as written. It isn't converted between Simplified and Traditional Chinese.

## Transcribe automatically

If you don't have a transcript, choose **Transcribe**. The speech model writes the subtitles from what it hears, and you can fix mistakes in the editor afterward. Set the maximum line length with the characters-per-line control.

The button at the bottom of the panel changes to **Transcribe Subtitles**. When **Language** is 中文（繁體） or 粵語, the recognized text is converted to Traditional Chinese.

## Search lyrics

Choose **Lyrics** to search LRCLIB, an open lyrics database. Searching needs an internet connection.

1. Enter the **Song** name. When you open a file and this field is empty, it is filled with the file name. **Artist** is optional.
2. Click **Search** or press Return.
3. Each result shows the title, artist, album, and length, plus how much longer or shorter it is than your file (**Same length**, or for example `+3 s`). Differences over 5 seconds are orange and over 15 seconds red. The result closest in length is selected for you; click another to switch.
4. The chosen version appears in the box below. Credit lines and section markers are removed.
5. Edit the text if needed before aligning. Write out a repeated section as many times as it's sung.

If nothing is found, try other keywords or paste a transcript instead. After aligning, a warning appears if the chosen lyrics differ in length from the video, since they may be a different version.

## Choose the language

Under **Recognition**, set **Language** to the language actually spoken or sung in the video; recognition is more accurate that way. The options are 中文（繁體）, 中文（简体）, 粵語, English, 日本語, 한국어, Español, Français, Deutsch, and **Detect Automatically**. Your choice is remembered.

If most subtitles don't match the audio after aligning, the app warns you: the transcript may not match the video, or the wrong language may be selected.

The **Model** menu next to it chooses the speech model. See the Speech models page.
