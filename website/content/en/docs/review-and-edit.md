---
title: Review and edit
description: What the marks in the subtitle list mean, and how to fix text and timing.
order: 3
---

After aligning, the subtitles appear in the editor below the preview. Selecting a line moves the playhead to its start. Turn on **Follow Playback** to keep the playing line in view. Above the list, a count shows how many lines there are and how many still need review.

## Line marks

Lines that deserve a look have a colored dot and a faint background in the same color. Point at a line to see what its mark means.

| Mark       | Label        | Meaning                                                                                                                           |
| ---------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| No dot     |              | The timing matches the audio.                                                                                                     |
| Orange dot | Needs review | The timing is uncertain; play the line to check it.                                                                               |
| Red dot    | Not found    | The line isn't in the audio. It shows **No timing yet**, isn't shown in the preview, and isn't exported until you give it a time. |
| Blue dot   | Transcribed  | Not in the transcript; it was recognized from speech and may contain mistakes.                                                    |

The line that is playing shows a play symbol and bold text.

### Mark a line as reviewed

Point at a line's dot; it turns into a check mark. Click it to mark the line as reviewed, which removes the mark. Changing a line's start or end time also counts as reviewed.

### Speech that isn't in the transcript

When aligning finds speech that your transcript doesn't cover, a highlighted row appears in the list at that point, for example "12 seconds of speech here aren't in the transcript". On that row:

- **Play** jumps to the passage and plays it.
- **Recognize** transcribes the passage and adds it as subtitles, marked as transcribed.
- **×** hides the hint if the passage doesn't need subtitles.

### Warnings

If something looks wrong with the whole result, a warning appears in the left panel, for example when most lines don't match the audio or the subtitles end well before the video does.

## Edit subtitles

- **Text**: click a line's text and type.
- **Timing**: select a line. Below the list, **Start** and **End** each have a time field (type a time such as `1:23.45`, then press Return), buttons to move the time 0.1 second earlier or later, and a button to set it to the playhead position. **Play This Line** plays the selected line.
- **Add** inserts an empty line after the selected one, or at the playhead when nothing is selected.
- **Split** splits the selected line at the playhead, or in the middle when the playhead is outside it. The text is divided in the middle.
- **Merge** joins the selected line with the next one.
- **Delete** removes the selected line. You can also press ⌫.
- **Shift All** moves every subtitle earlier or later. Enter the number of seconds (negative is earlier) and click **Apply**.

When the editor is narrow, these buttons show only their icons.

To give a not-found line a time, select it and set **Start** and **End**.

## Undo

Every change can be undone with Edit › Undo (⌘Z) and redone with ⇧⌘Z. Typing in one line counts as a single step. Aligning again over existing subtitles can be undone too.

Opening another video or audio file starts over with an empty list, so export your subtitles first.
