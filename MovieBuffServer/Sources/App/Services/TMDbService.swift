import Vapor

struct TMDbService {
    let client: any Client
    let apiKey: String

    private static let baseURL = "https://api.themoviedb.org/3"

    init(client: any Client, apiKey: String) {
        self.client = client
        self.apiKey = apiKey
    }

    static func make(for req: Request) throws -> TMDbService {
        guard let key = Environment.get("TMDB_API_KEY"), !key.isEmpty else {
            throw Abort(.internalServerError, reason: "TMDB_API_KEY is not configured")
        }
        return TMDbService(client: req.client, apiKey: key)
    }

    /// Returns all YouTube video IDs for a movie, ordered by preference:
    /// official Trailer → any Trailer → official Teaser → any Teaser.
    /// Caller is expected to walk the list and pick the first embeddable one.
    func trailerKeys(tmdbID: Int) async throws -> [String] {
        let uri = URI(string: "\(Self.baseURL)/movie/\(tmdbID)/videos")
        let response = try await client.get(uri) { req in
            try req.query.encode(["api_key": apiKey])
        }
        guard response.status == .ok else { return [] }
        let payload = try response.content.decode(TMDbVideosResponse.self)
        let youtube = payload.results.filter { $0.site == "YouTube" && !$0.key.isEmpty }
        let ranked = youtube.sorted { a, b in
            preferenceScore(a) > preferenceScore(b)
        }
        return ranked.map(\.key)
    }

    private func preferenceScore(_ v: TMDbVideo) -> Int {
        var score = 0
        if v.type == "Trailer" { score += 10 }
        else if v.type == "Teaser" { score += 5 }
        if v.official == true { score += 2 }
        return score
    }
}

struct TMDbVideosResponse: Content {
    let id: Int
    let results: [TMDbVideo]
}

struct TMDbVideo: Content {
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool?
}

/// 24h cache for TMDb trailer lookups, keyed by tmdbID. Nil results are cached too so we
/// don't hammer TMDb when a movie has no trailer. Each candidate is verified against
/// YouTube's oEmbed endpoint so we skip trailers whose owners disabled embedding.
actor TMDbTrailerCache {
    static let shared = TMDbTrailerCache()

    private struct Entry {
        let key: String?
        let expiresAt: Date
    }

    private var cache: [Int: Entry] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60

    func embeddableTrailerKey(
        for tmdbID: Int,
        using service: TMDbService,
        client: any Client
    ) async throws -> String? {
        if let entry = cache[tmdbID], entry.expiresAt > Date() {
            return entry.key
        }
        let candidates = try await service.trailerKeys(tmdbID: tmdbID)
        for key in candidates {
            if await Self.isEmbeddable(youtubeID: key, client: client) {
                cache[tmdbID] = Entry(key: key, expiresAt: Date().addingTimeInterval(ttl))
                return key
            }
        }
        // Cache the negative result so we don't retry a movie with only non-embeddable trailers.
        cache[tmdbID] = Entry(key: nil, expiresAt: Date().addingTimeInterval(ttl))
        return nil
    }

    /// YouTube's oEmbed endpoint returns 200 for embeddable videos, 401/403/404 otherwise.
    /// No API key required. Cheap and reliable.
    private static func isEmbeddable(youtubeID: String, client: any Client) async -> Bool {
        let uri = URI(string: "https://www.youtube.com/oembed")
        do {
            let response = try await client.get(uri) { req in
                try req.query.encode([
                    "url": "https://www.youtube.com/watch?v=\(youtubeID)",
                    "format": "json",
                ])
            }
            return response.status == .ok
        } catch {
            return false
        }
    }
}
