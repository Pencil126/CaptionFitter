import AppKit
import CaptionFitterCore
import Observation

/// App-level state for the speech models stored on this Mac.
@MainActor
@Observable
final class ModelManager {
    private static let defaultModelKey = "defaultModelID"

    let store = ModelStore(baseFolder: ModelStore.defaultBaseFolder())

    private(set) var models: [SpeechModel] = []
    private(set) var isLoading = false
    /// Download progress (0…1) for models being downloaded.
    private(set) var downloads: [String: Double] = [:]
    /// Download sizes fetched from the repository.
    private(set) var remoteSizes: [String: Int64] = [:]
    private(set) var totalSize: Int64 = 0
    var errorMessage: String?

    var defaultModelID: String? {
        didSet { UserDefaults.standard.set(defaultModelID, forKey: Self.defaultModelKey) }
    }

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    init() {
        defaultModelID = UserDefaults.standard.string(forKey: Self.defaultModelKey)
        refreshLocal()
    }

    var downloadedModels: [SpeechModel] {
        models.filter { $0.state == .downloaded }
    }

    /// The model to use: the chosen default if it is still on disk, otherwise any downloaded model.
    var activeModelID: String? {
        if let defaultModelID, store.isDownloaded(defaultModelID) { return defaultModelID }
        return downloadedModels.first?.id
    }

    func isDownloaded(_ id: String) -> Bool {
        store.isDownloaded(id)
    }

    /// Updates states and sizes from disk only (no network).
    func refreshLocal() {
        let local = Dictionary(uniqueKeysWithValues: store.localModels().map { ($0.id, $0) })
        if models.isEmpty {
            models = local.values.sorted { $0.id < $1.id }
        } else {
            models = models.map { model in
                var updated = model
                updated.state = local[model.id]?.state ?? .notDownloaded
                updated.sizeOnDisk = local[model.id]?.sizeOnDisk
                return updated
            }
        }
        totalSize = store.totalSizeOnDisk()
        if let defaultModelID, !store.isDownloaded(defaultModelID) {
            self.defaultModelID = downloadedModels.first?.id
        } else if defaultModelID == nil {
            defaultModelID = downloadedModels.first?.id
        }
    }

    /// Reloads the full list, including models that can be downloaded.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let store = store
        models = await store.allModels()
        refreshLocal()

        // Fetch download sizes in the background for models not on disk yet.
        let missing = models.filter { $0.state != .downloaded && remoteSizes[$0.id] == nil }.map(\.id)
        await withTaskGroup(of: (String, Int64?).self) { group in
            for id in missing {
                group.addTask { (id, await store.downloadSize(of: id)) }
            }
            for await (id, size) in group {
                if let size { remoteSizes[id] = size }
            }
        }
    }

    func download(_ id: String) {
        guard downloadTasks[id] == nil else { return }
        downloads[id] = 0
        errorMessage = nil
        let store = store
        downloadTasks[id] = Task { [weak self] in
            do {
                try await store.download(id) { fraction in
                    Task { @MainActor in
                        guard let self, self.downloads[id] != nil else { return }
                        self.downloads[id] = fraction
                    }
                }
            } catch is CancellationError {
                // Stopped by the user; partial files stay so the download can resume.
            } catch {
                if !Task.isCancelled {
                    self?.errorMessage = String(localized: "Can't download \(id): \(CoreMessages.message(for: error))")
                }
            }
            self?.downloads[id] = nil
            self?.downloadTasks[id] = nil
            self?.refreshLocal()
        }
    }

    func cancelDownload(_ id: String) {
        downloadTasks[id]?.cancel()
    }

    func delete(_ id: String) {
        cancelDownload(id)
        do {
            try store.delete(id)
        } catch {
            errorMessage = String(localized: "Can't delete \(id): \(error.localizedDescription)")
        }
        refreshLocal()
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: store.modelsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.modelsFolder])
    }
}
