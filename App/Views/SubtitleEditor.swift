import CaptionFitterCore
import SwiftUI

/// The subtitle list with timing and text editing.
struct SubtitleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var showShift = false
    @State private var shiftSeconds = 0.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider()

            if model.document.lines.isEmpty {
                ContentUnavailableView(
                    "還沒有字幕",
                    systemImage: "captions.bubble",
                    description: Text("在左側選擇檔案與文稿，然後按「對齊字幕」。")
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

    private var toolbar: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Button {
                model.addLine(undoManager: undoManager)
            } label: {
                Label("新增", systemImage: "plus")
            }
            .disabled(model.mediaURL == nil)

            Button {
                model.splitSelected(undoManager: undoManager)
            } label: {
                Label("分割", systemImage: "scissors")
            }
            .disabled(model.selection == nil)
            .help("在播放位置分割所選字幕；播放位置不在該行內時從中間分割")

            Button {
                model.mergeSelectedWithNext(undoManager: undoManager)
            } label: {
                Label("與下一行合併", systemImage: "arrow.triangle.merge")
            }
            .disabled(model.selection == nil)

            Button(role: .destructive) {
                model.deleteSelected(undoManager: undoManager)
            } label: {
                Label("刪除", systemImage: "trash")
            }
            .disabled(model.selection == nil)

            Divider().frame(height: 16)

            Button {
                showShift.toggle()
            } label: {
                Label("整體平移", systemImage: "arrow.left.and.right")
            }
            .disabled(model.document.lines.isEmpty)
            .popover(isPresented: $showShift, arrowEdge: .bottom) { shiftPopover }

            Spacer()

            if let report = model.report {
                let doubtful = report.partialLines + report.interpolatedLines
                Text(doubtful > 0 ? "\(report.totalLines) 行，\(doubtful) 行待檢查" : "\(model.document.lines.count) 行")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Toggle("跟隨播放", isOn: $model.followPlayback)
                .toggleStyle(.checkbox)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
    }

    private var shiftPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("將所有字幕提前或延後").font(.headline)
            HStack {
                TextField("秒", value: $shiftSeconds, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Text("秒（負數為提前）")
                Stepper("", value: $shiftSeconds, step: 0.1).labelsHidden()
            }
            HStack {
                Spacer()
                Button("套用") {
                    let delta = shiftSeconds
                    model.edit("整體平移", undoManager: undoManager) { $0.shiftAll(by: delta) }
                    showShift = false
                }
                .keyboardShortcut(.defaultAction)
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
                ForEach(Array(model.document.lines.enumerated()), id: \.element.id) { index, line in
                    SubtitleRow(index: index + 1, line: line, isPlaying: line.id == playingID)
                        .tag(line.id)
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

private struct SubtitleRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let index: Int
    let line: SubtitleLine
    let isPlaying: Bool
    @FocusState private var textFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isPlaying ? "play.fill" : "circle.fill")
                .font(.system(size: isPlaying ? 9 : 7))
                .foregroundStyle(isPlaying ? Color.accentColor : confidenceColor)
                .frame(width: 12)
                .help(confidenceHelp)

            Text("\(index)")
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)

            Text("\(TimeText.string(line.start)) → \(TimeText.string(line.end))")
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            TextField("字幕文字", text: Binding(
                get: { line.text },
                set: { newValue in
                    model.edit("修改文字", undoManager: undoManager, coalesceKey: "text-\(line.id)") {
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
    }

    private var confidenceColor: Color {
        switch line.confidence {
        case .good, .manual: return .clear
        case .partial: return .orange
        case .interpolated: return .red
        }
    }

    private var confidenceHelp: String {
        switch line.confidence {
        case .good: return "時間已對上聲音"
        case .manual: return "已手動調整"
        case .partial: return "不確定這一行的時間是否正確，建議播放檢查"
        case .interpolated: return "在聲音中找不到這一行。設定時間之前，它不會顯示也不會輸出"
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
                title: "開始", value: line.start,
                set: { value in model.edit("調整開始時間", undoManager: undoManager) { $0.setStart(value, for: line.id) } }
            )
            timeControls(
                title: "結束", value: line.end,
                set: { value in model.edit("調整結束時間", undoManager: undoManager) { $0.setEnd(value, for: line.id) } }
            )
            Spacer()
            Button {
                model.seek(to: line.start)
                if !model.isPlaying { model.togglePlayback() }
            } label: {
                Label("播放這一行", systemImage: "play.circle")
            }
        }
        .buttonStyle(.borderless)
    }

    private func timeControls(title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            TimeField(value: value, onCommit: set)
            Button { set(value - 0.1) } label: { Image(systemName: "minus") }
                .help("提前 0.1 秒")
            Button { set(value + 0.1) } label: { Image(systemName: "plus") }
                .help("延後 0.1 秒")
            Button { set(model.currentTime) } label: { Image(systemName: "scope") }
                .help("設為目前播放位置")
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
