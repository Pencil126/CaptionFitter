import Foundation

public struct LyricsSearchResult: Identifiable, Equatable, Decodable, Sendable {
    public var id: Int
    public var trackName: String
    public var artistName: String
    public var albumName: String?
    public var duration: Double?
    public var instrumental: Bool
    public var plainLyrics: String?
    public var syncedLyrics: String?

    public init(id: Int, trackName: String, artistName: String, albumName: String? = nil, duration: Double? = nil,
                instrumental: Bool = false, plainLyrics: String? = nil, syncedLyrics: String? = nil) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    enum CodingKeys: String, CodingKey {
        case id, trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        trackName = try container.decodeIfPresent(String.self, forKey: .trackName) ?? ""
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName) ?? ""
        albumName = try container.decodeIfPresent(String.self, forKey: .albumName)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        instrumental = try container.decodeIfPresent(Bool.self, forKey: .instrumental) ?? false
        plainLyrics = try container.decodeIfPresent(String.self, forKey: .plainLyrics)
        syncedLyrics = try container.decodeIfPresent(String.self, forKey: .syncedLyrics)
    }

    /// The text to hand to the cleaner: plain lyrics when available, otherwise the timed version.
    public var lyricsText: String? {
        if let plainLyrics, !plainLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return plainLyrics }
        if let syncedLyrics, !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return syncedLyrics }
        return nil
    }
}

/// Client for the open LRCLIB lyrics database (https://lrclib.net). No API key needed.
public struct LRCLIBClient: Sendable {
    public enum ClientError: LocalizedError {
        case badResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "The lyrics database returned an error (HTTP \(code))."
            }
        }
    }

    public var baseURL = URL(string: "https://lrclib.net/api")!
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(track: String, artist: String? = nil) async throws -> [LyricsSearchResult] {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "track_name", value: track)]
        if let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("CaptionFitter/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClientError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode([LyricsSearchResult].self, from: data)
    }

    /// Drops instrumentals and entries without lyrics, then puts the versions whose
    /// length is closest to the media first. The database's own relevance order breaks ties.
    public static func rank(_ results: [LyricsSearchResult], mediaDuration: Double?) -> [LyricsSearchResult] {
        let usable = results.filter { !$0.instrumental && $0.lyricsText != nil }
        guard let mediaDuration else { return usable }
        return usable.enumerated()
            .sorted { a, b in
                let da = a.element.duration.map { abs($0 - mediaDuration) } ?? .infinity
                let db = b.element.duration.map { abs($0 - mediaDuration) } ?? .infinity
                return da == db ? a.offset < b.offset : da < db
            }
            .map(\.element)
    }
}
