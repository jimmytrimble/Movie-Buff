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

    // MARK: - People

    /// Free-text search for actors, directors, etc. Returns up to 20 matches per page.
    func searchPeople(query: String, page: Int = 1) async throws -> TMDbPersonSearchResponse {
        let uri = URI(string: "\(Self.baseURL)/search/person")
        let response = try await client.get(uri) { req in
            try req.query.encode([
                "api_key": apiKey,
                "query": query,
                "page": String(page),
                "include_adult": "false",
            ])
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "TMDb search/person responded with \(response.status.code)")
        }
        return try response.content.decode(TMDbPersonSearchResponse.self)
    }

    /// A person's acting credits. Filter out uncredited / very small parts client-side.
    func movieCredits(personID: Int) async throws -> TMDbMovieCreditsResponse {
        let uri = URI(string: "\(Self.baseURL)/person/\(personID)/movie_credits")
        let response = try await client.get(uri) { req in
            try req.query.encode(["api_key": apiKey])
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "TMDb movie_credits responded with \(response.status.code)")
        }
        return try response.content.decode(TMDbMovieCreditsResponse.self)
    }

    /// Fetches a movie's external IDs (we care about `imdb_id` — needed to route into
    /// the existing OMDB-keyed detail flow).
    func externalIDs(movieTmdbID: Int) async throws -> TMDbExternalIDs {
        let uri = URI(string: "\(Self.baseURL)/movie/\(movieTmdbID)/external_ids")
        let response = try await client.get(uri) { req in
            try req.query.encode(["api_key": apiKey])
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "TMDb external_ids responded with \(response.status.code)")
        }
        return try response.content.decode(TMDbExternalIDs.self)
    }

    // MARK: - Trailers

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

struct TMDbPersonSearchResponse: Content {
    let page: Int
    let results: [TMDbPerson]
    let totalResults: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case results
        case totalResults = "total_results"
        case totalPages = "total_pages"
    }
}

struct TMDbPerson: Content {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case popularity
    }
}

struct TMDbMovieCreditsResponse: Content {
    let cast: [TMDbMovieCredit]
    let crew: [TMDbMovieCredit]
}

struct TMDbMovieCredit: Content {
    let id: Int
    let title: String?
    let originalTitle: String?
    let releaseDate: String?
    let posterPath: String?
    let character: String?
    let job: String?
    let voteAverage: Double?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case character
        case job
        case voteAverage = "vote_average"
        case popularity
    }
}

struct TMDbExternalIDs: Content {
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
    }
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
