import CaptionFitterCore
import SwiftUI

/// Settings window: see, download and delete the speech models stored on this Mac.
struct ModelSettingsView: View {
    @Environment(ModelManager.self) private var models
    @State private var pendingDelete: SpeechModel?

    private let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("語音模型").font(.title3.bold())
                Text("模型在這台 Mac 上辨識語音，不會上傳影片。越大的模型越準確，但下載較久、處理較慢。標示「建議」的模型適合這台 Mac。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List {
                if !downloaded.isEmpty {
                    Section("已下載") {
                        ForEach(downloaded) { row($0) }
                    }
                }
                Section(downloaded.isEmpty ? "可下載" : "其他可下載的模型") {
                    if available.isEmpty {
                        if models.isLoading {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("正在取得模型清單…").foregroundStyle(.secondary)
                            }
                        } else {
                            Text("無法取得模型清單，請檢查網路連線後重新整理。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(available) { row($0) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }

            if let message = models.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已使用 \(sizeFormatter.string(fromByteCount: models.totalSize))")
                    Text(models.store.modelsFolder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("在 Finder 中顯示") { models.revealInFinder() }
                Button {
                    Task { await models.refresh() }
                } label: {
                    Label("重新整理", systemImage: "arrow.clockwise")
                }
                .disabled(models.isLoading)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .task { await models.refresh() }
        .confirmationDialog(
            "要刪除「\(pendingDelete?.displayName ?? "")」嗎？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { model in
            Button("刪除", role: .destructive) { models.delete(model.id) }
            Button("取消", role: .cancel) {}
        } message: { model in
            Text("會釋出 \(sizeFormatter.string(fromByteCount: model.sizeOnDisk ?? 0))。之後需要時可以重新下載。")
        }
    }

    private var downloaded: [SpeechModel] {
        models.models.filter { $0.state == .downloaded }
    }

    private var available: [SpeechModel] {
        models.models.filter { $0.state != .downloaded }
    }

    @ViewBuilder
    private func row(_ model: SpeechModel) -> some View {
        let progress = models.downloads[model.id]
        HStack(spacing: 10) {
            if model.state == .downloaded {
                let isDefault = models.activeModelID == model.id
                Button {
                    models.defaultModelID = model.id
                } label: {
                    Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isDefault ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isDefault ? "目前使用的模型" : "設為使用的模型")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                    if model.isDefaultForDevice {
                        badge("最適合這台 Mac", color: .green)
                    } else if model.isRecommended {
                        badge("建議", color: .blue)
                    }
                    if model.state == .incomplete, progress == nil {
                        badge("下載未完成", color: .orange)
                    }
                }
                Text(sizeText(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let progress {
                ProgressView(value: progress)
                    .frame(width: 110)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
                Button("取消") { models.cancelDownload(model.id) }
            } else {
                switch model.state {
                case .downloaded:
                    Button("刪除", role: .destructive) { pendingDelete = model }
                case .incomplete:
                    Button("繼續下載") { models.download(model.id) }
                    Button("刪除", role: .destructive) { pendingDelete = model }
                case .notDownloaded:
                    Button("下載") { models.download(model.id) }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func sizeText(_ model: SpeechModel) -> String {
        if let size = model.sizeOnDisk, model.state != .notDownloaded {
            return sizeFormatter.string(fromByteCount: size)
        }
        if let size = models.remoteSizes[model.id] {
            return "下載大小 " + sizeFormatter.string(fromByteCount: size)
        }
        return "大小未知"
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
