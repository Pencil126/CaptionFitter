import Foundation
import WhisperKit

/// A speech model that can be used on this Mac, downloaded or not.
public struct SpeechModel: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case notDownloaded
        /// A download was interrupted; files are on disk but the model is not usable.
        case incomplete
        case downloaded
    }

    /// The model's folder name in the repository, e.g. `openai_whisper-large-v3`.
    public var id: String
    public var state: State
    /// Bytes on disk (downloaded / incomplete models only).
    public var sizeOnDisk: Int64?
    /// Suggested for this Mac by the model publisher.
    public var isRecommended: Bool
    /// The publisher's default choice for this Mac.
    public var isDefaultForDevice: Bool

    public var displayName: String {
        var name = id
        for prefix in ["openai_whisper-", "distil-whisper_"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return name.replacingOccurrences(of: "_", with: " ")
    }
}

/// Lists, downloads and deletes the speech models stored on this Mac.
public struct ModelStore: Sendable {
    public static let repository = "argmaxinc/whisperkit-coreml"
    private static let completionMarker = ".captionfitter-complete"

    /// Root folder for everything the speech engine stores.
    public let baseFolder: URL

    public init(baseFolder: URL) {
        self.baseFolder = baseFolder
    }

    /// `~/Library/Application Support/CaptionFitter/Models` (inside the container when sandboxed).
    public static func defaultBaseFolder() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("CaptionFitter/Models", isDirectory: true)
    }

    /// Where model folders live, following the layout the downloader uses.
    public var modelsFolder: URL {
        baseFolder.appendingPathComponent("models/\(Self.repository)", isDirectory: true)
    }

    public func folder(for modelID: String) -> URL {
        modelsFolder.appendingPathComponent(modelID, isDirectory: true)
    }

    // MARK: - Listing

    /// Models found on disk. Works offline.
    public func localModels() -> [SpeechModel] {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(
            at: modelsFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        return folders.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let complete = manager.fileExists(atPath: url.appendingPathComponent(Self.completionMarker).path)
            return SpeechModel(
                id: url.lastPathComponent,
                state: complete ? .downloaded : .incomplete,
                sizeOnDisk: Self.directorySize(url),
                isRecommended: false,
                isDefaultForDevice: false
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// Local models merged with the list of models available for this Mac.
    /// Falls back to a built-in list when offline.
    public func allModels() async -> [SpeechModel] {
        let support = await WhisperKit.recommendedRemoteModels(from: Self.repository, downloadBase: baseFolder)
        let remote = (try? await WhisperKit.fetchAvailableModels(from: Self.repository, downloadBase: baseFolder)) ?? []
        let local = Dictionary(uniqueKeysWithValues: localModels().map { ($0.id, $0) })

        let disabled = Set(support.disabled)
        let recommended = Set(support.supported)
        var ids = remote.filter { !disabled.contains($0) }
        for id in local.keys where !ids.contains(id) { ids.append(id) }

        return ids.map { id in
            SpeechModel(
                id: id,
                state: local[id]?.state ?? .notDownloaded,
                sizeOnDisk: local[id]?.sizeOnDisk,
                isRecommended: recommended.contains(id),
                isDefaultForDevice: id == support.default
            )
        }
    }

    public func totalSizeOnDisk() -> Int64 {
        Self.directorySize(baseFolder)
    }

    // MARK: - Download / delete

    /// Size of the model's files in the repository, in bytes, or nil if it cannot be determined.
    public func downloadSize(of modelID: String) async -> Int64? {
        struct Entry: Decodable {
            var type: String
            var size: Int64?
        }
        guard let encoded = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/api/models/\(Self.repository)/tree/main/\(encoded)?recursive=true")
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        let total = entries.filter { $0.type == "file" }.compactMap(\.size).reduce(0, +)
        return total > 0 ? total : nil
    }

    /// Downloads a model, reporting progress from 0 to 1. Cancelling the task stops the
    /// download and leaves the model marked incomplete; downloading again resumes it.
    @discardableResult
    public func download(_ modelID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: baseFolder, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(
            variant: modelID,
            downloadBase: baseFolder,
            from: Self.repository
        ) { value in
            progress(value.fractionCompleted)
        }
        try Task.checkCancellation()
        FileManager.default.createFile(atPath: folder.appendingPathComponent(Self.completionMarker).path, contents: Data())
        return folder
    }

    public func delete(_ modelID: String) throws {
        let url = folder(for: modelID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func isDownloaded(_ modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: modelID).appendingPathComponent(Self.completionMarker).path)
    }

    // MARK: - Helpers

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
