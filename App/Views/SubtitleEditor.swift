import CaptionFitterCore
import SwiftUI

/// The subtitle list with timing and text editing.
struct SubtitleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(ModelManager.self) private var models
    @Environment(\.undoManager) private var undoManager
    @State private var showShift = false
    @State private var shiftSeconds = 0.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider()

            if model.document.lines.isEmpty, model.openRegions.isEmpty {
                ContentUnavailableView(
                    "No Subtitles Yet",
                    systemImage: "captions.bubble",
                    description: Text("Choose a file and a transcript on the left, then click Align Subtitles.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
                if let line = model.selectedLine {
                    Divider()
                    LineInspector(line: line)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    /// Buttons show their titles when there is room and only their icons when the pane is
    /// narrow, so the row never wraps (English titles are longer than Chinese ones).
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow.labelStyle(.titleAndIcon)
            toolbarRow.labelStyle(.iconOnly)
        }
    }

    private var toolbarRow: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Button {
                model.addLine(undoManager: undoManager)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .disabled(model.mediaURL == nil)
            .help("Add a subtitle line")

            Button {
                model.splitSelected(undoManager: undoManager)
            } label: {
                Label("Split", systemImage: "scissors")
            }
            .disabled(model.selection == nil)
            .help("Split the selected subtitle at the playhead, or in the middle when the playhead is outside it")

            Button {
                model.mergeSelectedWithNext(undoManager: undoManager)
            } label: {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .disabled(model.selection == nil)
            .help("Merge the selected subtitle with the next one")

            Button(role: .destructive) {
                model.deleteSelected(undoManager: undoManager)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(model.selection == nil)
            .help("Delete the selected subtitle")

            Divider().frame(height: 16)

            Button {
                showShift.toggle()
            } label: {
                Label("Shift All", systemImage: "arrow.left.and.right")
            }
            .disabled(model.document.lines.isEmpty)
            .help("Move All Subtitles Earlier or Later")
            .popover(isPresented: $showShift, arrowEdge: .bottom) { shiftPopover }

            Spacer(minLength: 8)

            if !model.document.lines.isEmpty {
                let lines = model.document.lines
                let doubtful = lines.filter { $0.confidence != .good && $0.confidence != .manual }.count
                Group {
                    if doubtful > 0 {
                        Text("\(lines.count) lines, \(doubtful) to review")
                    } else {
                        Text("\(lines.count) lines")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            Toggle("Follow Playback", isOn: $model.followPlayback)
                .toggleStyle(.checkbox)
                .brandTint()
                .fixedSize()
        }
        .lineLimit(1)
        .buttonStyle(.borderless)
    }

    private var shiftPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move All Subtitles Earlier or Later").font(.headline)
            HStack {
                TextField("Seconds", value: $shiftSeconds, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Text("seconds (negative is earlier)")
                Stepper("", value: $shiftSeconds, step: 0.1).labelsHidden()
            }
            HStack {
                Spacer()
                Button {
                    let delta = shiftSeconds
                    model.edit("Shift All", undoManager: undoManager) { $0.shiftAll(by: delta) }
                    showShift = false
                } label: {
                    BrandButtonLabel("Apply")
                }
                .keyboardShortcut(.defaultAction)
                .brandTint()
                .disabled(shiftSeconds == 0)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var list: some View {
        @Bindable var model = model
        let playingID = model.currentLine?.id
        return ScrollViewReader { proxy in
            List(selection: $model.selection) {
                ForEach(rows) { row in
                    switch row {
                    case .line(let index, let line):
                        SubtitleRow(index: index, line: line, isPlaying: line.id == playingID)
                            .tag(line.id)
                    case .region(let region):
                        UnscriptedRegionRow(region: region)
                            .selectionDisabled()
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: model.selection) { _, newValue in
                // Selecting a line jumps to it, unless playback itself is what moved us there.
                guard let newValue, let line = model.document.lines.first(where: { $0.id == newValue }) else { return }
                if !(line.start <= model.currentTime && model.currentTime < line.end) {
                    model.seek(to: line.start)
                }
            }
            .onChange(of: playingID) { _, newValue in
                guard model.followPlayback, model.isPlaying, let newValue else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
            }
            .onDeleteCommand { model.deleteSelected(undoManager: undoManager) }
        }
    }
}

/// One row of the list: a subtitle, or a hint about speech the script does not cover.
private enum EditorRow: Identifiable {
    case line(index: Int, SubtitleLine)
    case region(UnscriptedRegion)

    var id: UUID {
        switch self {
        case .line(_, let line): return line.id
        case .region(let region): return region.id
        }
    }
}

extension SubtitleEditor {
    /// Subtitles in order, with each hint placed where its passage falls in time.
    fileprivate var rows: [EditorRow] {
        var pending = model.openRegions.sorted { $0.range.lowerBound < $1.range.lowerBound }[...]
        var rows: [EditorRow] = []
        for (index, line) in model.document.lines.enumerated() {
            // Lines not found in the audio have no time of their own; keep them above the hint.
            while let region = pending.first, line.duration > 0, line.start >= region.range.lowerBound {
                rows.append(.region(region))
                pending.removeFirst()
            }
            rows.append(.line(index: index + 1, line))
        }
        rows.append(contentsOf: pending.map { .region($0) })
        return rows
    }
}

/// Tells the user about speech that is not in the script and offers to transcribe it.
private struct UnscriptedRegionRow: View {
    @Environment(AppModel.self) private var model
    @Environment(ModelManager.self) private var models
    @Environment(\.undoManager) private var undoManager
    let region: UnscriptedRegion

    /// The multicolour sweep commonly used to mark something as found or made by AI.
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.52, blue: 1.0),
            Color(red: 0.62, green: 0.36, blue: 0.98),
            Color(red: 0.98, green: 0.38, blue: 0.66),
            Color(red: 1.0, green: 0.62, blue: 0.3),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        let seconds = Int((region.range.upperBound - region.range.lowerBound).rounded())
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Self.gradient)
                .frame(width: 16)
            Text(verbatim: "\(TimeText.string(region.range.lowerBound)) → \(TimeText.string(region.range.upperBound))")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            // The row is tall enough for the sentence to wrap when the window is narrow.
            Text("\(seconds) seconds of speech here aren't in the transcript")
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            if model.fillingRegionID == region.id {
                ProgressView(value: model.workProgress)
                    .brandTint()
                    .frame(width: 80)
                Button("Cancel") { model.cancelWork() }
            } else {
                Button {
                    model.seek(to: region.range.lowerBound)
                    if !model.isPlaying { model.togglePlayback() }
                } label: {
                    Label("Play", systemImage: "play.circle")
                }
                .help("Jump to this passage and play it")
                Button {
                    model.fillRegion(region, using: models, undoManager: undoManager)
                } label: {
                    Label("Recognize", systemImage: "wand.and.stars")
                }
                .disabled(model.isWorking)
                .help("Recognize the speech in this passage and add it as subtitles. The result may contain mistakes, so check it.")
                Button {
                    model.dismissRegion(region.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .disabled(model.isWorking)
                .help("This passage doesn't need subtitles")
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .fixedSize(horizontal: false, vertical: true)
        // About three times the height of a subtitle row, so the hint stands apart from the lines around it.
        .frame(minHeight: 68)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Self.gradient.opacity(0.22))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Self.gradient.opacity(0.7), lineWidth: 1) }
                .padding(.horizontal, -6)
                .padding(.vertical, 2)
        }
    }
}

private struct SubtitleRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let index: Int
    let line: SubtitleLine
    let isPlaying: Bool
    @FocusState private var textFocused: Bool
    @State private var hovering = false
    @State private var hoveringMarker = false

    var body: some View {
        HStack(spacing: 10) {
            // The mark turns into a tick under the pointer: click to say the line has been checked.
            Group {
                if status != nil, hoveringMarker {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: isPlaying ? "play.fill" : "circle.fill")
                        .font(.system(size: isPlaying ? 9 : 7))
                        .foregroundStyle(isPlaying ? Color.brandGlyph : status?.color ?? .clear)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onHover { hoveringMarker = $0 }
            .onTapGesture {
                guard status != nil else { return }
                model.edit("Mark as Reviewed", undoManager: undoManager) { $0.markReviewed(line.id) }
            }
            .help(status == nil ? LocalizedStringKey("The timing matches the audio") : "Mark as reviewed")
            .accessibilityAddTraits(status == nil ? [] : .isButton)
            .accessibilityLabel(status == nil ? Text(verbatim: "") : Text("Mark as reviewed"))

            Text(verbatim: "\(index)")
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)

            Group {
                if line.duration == 0 {
                    Text("No timing yet")
                } else {
                    Text(verbatim: "\(TimeText.string(line.start)) → \(TimeText.string(line.end))")
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 150, alignment: .leading)

            TextField("Subtitle text", text: Binding(
                get: { line.text },
                set: { newValue in
                    model.edit("Edit Text", undoManager: undoManager, coalesceKey: "text-\(line.id)") {
                        $0.setText(newValue, for: line.id)
                    }
                }
            ))
            .textFieldStyle(.plain)
            .fontWeight(isPlaying ? .semibold : .regular)
            .focused($textFocused)
            // Clicking straight into the text also selects the row, so the timing controls follow.
            .onChange(of: textFocused) { _, focused in
                if focused, model.selection != line.id { model.selection = line.id }
            }
        }
        .monospacedDigit()
        .padding(.vertical, 2)
        // A faint wash marks lines that need attention; the selection highlight takes over when selected.
        .background {
            if let status, model.selection != line.id {
                RoundedRectangle(cornerRadius: 5)
                    .fill(status.color.opacity(0.1))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -1)
            }
        }
        // Pointing at a marked line says what the mark means.
        .overlay(alignment: .trailing) {
            if hovering, let status {
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(status.color, in: Capsule())
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering = $0 }
    }

    /// Colour and explanation for lines that deserve a look; nil for lines that are fine.
    private var status: (color: Color, label: LocalizedStringKey)? {
        switch line.confidence {
        case .good, .manual: return nil
        case .partial: return (.orange, "Needs review: the timing is uncertain; play it to check")
        case .interpolated: return (.red, "Not found: this line isn't in the audio and won't be exported until it has a time")
        case .transcribed: return (.blue, "Transcribed: not in the transcript, may contain mistakes")
        }
    }
}

/// Timing controls for the selected line.
private struct LineInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let line: SubtitleLine

    var body: some View {
        HStack(spacing: 18) {
            timeControls(
                title: "Start", value: line.start,
                set: { value in model.edit("Change Start Time", undoManager: undoManager) { $0.setStart(value, for: line.id) } }
            )
            timeControls(
                title: "End", value: line.end,
                set: { value in model.edit("Change End Time", undoManager: undoManager) { $0.setEnd(value, for: line.id) } }
            )
            Spacer()
            Button {
                model.seek(to: line.start)
                if !model.isPlaying { model.togglePlayback() }
            } label: {
                Label("Play This Line", systemImage: "play.circle")
            }
        }
        .buttonStyle(.borderless)
    }

    private func timeControls(title: LocalizedStringKey, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            TimeField(value: value, onCommit: set)
            Button { set(value - 0.1) } label: { Image(systemName: "minus") }
                .help("0.1 second earlier")
            Button { set(value + 0.1) } label: { Image(systemName: "plus") }
                .help("0.1 second later")
            Button { set(model.currentTime) } label: { Image(systemName: "scope") }
                .help("Set to the playhead position")
        }
    }
}

/// A text field for a time such as `1:23.45`; commits on Return or when focus leaves.
private struct TimeField: View {
    let value: Double
    let onCommit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: 84)
            .focused($focused)
            .onAppear { text = TimeText.string(value) }
            .onChange(of: value) { _, newValue in text = TimeText.string(newValue) }
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        if let parsed = TimeText.parse(text), abs(parsed - value) > 0.0005 {
            onCommit(parsed)
        }
        text = TimeText.string(value)
    }
}
