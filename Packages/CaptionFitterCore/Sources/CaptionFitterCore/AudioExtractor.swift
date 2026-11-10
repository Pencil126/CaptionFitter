import AVFoundation
import Foundation

public enum AudioExtractor {
    public enum ExtractionError: LocalizedError {
        case noAudioTrack
        case readFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "這個檔案沒有音訊軌。"
            case .readFailed(let reason): return "無法讀取音訊：\(reason)"
            }
        }
    }

    public static let sampleRate: Double = 16_000

    public static func duration(of url: URL) async throws -> Double {
        let duration = try await AVURLAsset(url: url).load(.duration)
        return duration.seconds.isFinite ? duration.seconds : 0
    }

    /// Decodes the media's audio to 16 kHz mono Float32 samples, the format the speech model expects.
    public static func samples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ExtractionError.noAudioTrack }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw ExtractionError.readFailed("不支援的音訊格式") }
        reader.add(output)
        guard reader.startReading() else {
            throw ExtractionError.readFailed(reader.error?.localizedDescription ?? "未知錯誤")
        }

        var samples: [Float] = []
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            samples.reserveCapacity(Int(seconds * sampleRate) + 1024)
        }
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            let count = length / MemoryLayout<Float>.size
            let offset = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                    destination: raw.baseAddress!.advanced(by: offset * MemoryLayout<Float>.size)
                )
            }
        }
        if reader.status == .failed {
            throw ExtractionError.readFailed(reader.error?.localizedDescription ?? "未知錯誤")
        }
        return samples
    }
}
