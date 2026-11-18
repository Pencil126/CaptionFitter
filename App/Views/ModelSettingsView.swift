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
                Text("Speech Models").font(.title3.bold())
                Text("Models recognize speech on this Mac; your video is never uploaded. Larger models are more accurate but take longer to download and run. Models marked Recommended suit this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List {
                if !downloaded.isEmpty {
                    Section("Downloaded") {
                        ForEach(downloaded) { row($0) }
                    }
                }
                Section(downloaded.isEmpty ? LocalizedStringKey("Available") : "Other Available Models") {
                    if available.isEmpty {
                        if models.isLoading {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Getting the list of models…").foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Can't get the list of models. Check your internet connection, then click Refresh.")
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
                    Text("\(sizeFormatter.string(fromByteCount: models.totalSize)) used")
                    Text(models.store.modelsFolder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Show in Finder") { models.revealInFinder() }
                Button {
                    Task { await models.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(models.isLoading)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .task { await models.refresh() }
        .confirmationDialog(
            "Delete “\(pendingDelete?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { model in
            Button("Delete", role: .destructive) { models.delete(model.id) }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("This frees \(sizeFormatter.string(fromByteCount: model.sizeOnDisk ?? 0)). You can download it again later if you need it.")
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
                        .foregroundStyle(isDefault ? Color.brandGlyph : .secondary)
                }
                .buttonStyle(.plain)
                .help(isDefault ? LocalizedStringKey("The model in use") : "Use this model")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                    if model.isDefaultForDevice {
                        badge("Best for This Mac", color: .green)
                    } else if model.isRecommended {
                        badge("Recommended", color: .blue)
                    }
                    if model.state == .incomplete, progress == nil {
                        badge("Download Incomplete", color: .orange)
                    }
                }
                Text(sizeText(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let progress {
                ProgressView(value: progress)
                    .brandTint()
                    .frame(width: 110)
                Text(verbatim: "\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
                Button("Cancel") { models.cancelDownload(model.id) }
            } else {
                switch model.state {
                case .downloaded:
                    Button("Delete", role: .destructive) { pendingDelete = model }
                case .incomplete:
                    Button("Resume Download") { models.download(model.id) }
                    Button("Delete", role: .destructive) { pendingDelete = model }
                case .notDownloaded:
                    Button("Download") { models.download(model.id) }
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
            return String(localized: "Download size: \(sizeFormatter.string(fromByteCount: size))")
        }
        return String(localized: "Size unknown")
    }

    private func badge(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
