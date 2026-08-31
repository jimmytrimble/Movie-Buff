import Vapor

struct WatchModeService {
    let client: any Client
    let apiKey: String

    private static let baseURL = "https://api.watchmode.com/v1"

    init(client: any Client, apiKey: String) {
        self.client = client
        self.apiKey = apiKey
    }

    static func make(for req: Request) throws -> WatchModeService {
        guard let key = Environment.get("WATCHMODE_API_KEY"), !key.isEmpty else {
            throw Abort(.internalServerError, reason: "WATCHMODE_API_KEY is not configured")
        }
        return WatchModeService(client: req.client, apiKey: key)
    }

    // Fetches WatchMode's title details (which accepts an IMDb ID) to discover the
    // internal integer id, then fetches sources using that integer id. WatchMode's
    // /sources/ endpoint only returns data for internal ids, not IMDb ids.
    func titleData(imdbID: String, region: String = "US") async throws -> WatchModeTitleData {
        let detailsURI = URI(string: "\(Self.baseURL)/title/\(imdbID)/details/")
        let detailsResponse = try await client.get(detailsURI) { req in
            try req.query.encode(["apiKey": apiKey])
        }
        guard detailsResponse.status == .ok else {
            throw Abort(.badGateway, reason: "WatchMode details responded with \(detailsResponse.status.code)")
        }
        let details = try detailsResponse.content.decode(WatchModeDetails.self)

        let sourcesURI = URI(string: "\(Self.baseURL)/title/\(details.id)/sources/")
        let sourcesResponse = try await client.get(sourcesURI) { req in
            try req.query.encode([
                "apiKey": apiKey,
                "regions": region,
            ])
        }
        guard sourcesResponse.status == .ok else {
            throw Abort(.badGateway, reason: "WatchMode sources responded with \(sourcesResponse.status.code)")
        }
        let sources = try sourcesResponse.content.decode([WatchModeSource].self)

        return WatchModeTitleData(details: details, sources: sources)
    }

    /// Details-only fetch. Cheaper than `titleData` because it skips the /sources/ round-trip,
    /// which frequently returns 404 for titles that aren't on any streaming service.
    func details(imdbID: String) async throws -> WatchModeDetails {
        let uri = URI(string: "\(Self.baseURL)/title/\(imdbID)/details/")
        let response = try await client.get(uri) { req in
            try req.query.encode(["apiKey": apiKey])
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "WatchMode details responded with \(response.status.code)")
        }
        return try response.content.decode(WatchModeDetails.self)
    }

    func genres() async throws -> [WatchModeGenre] {
        let uri = URI(string: "\(Self.baseURL)/genres/")
        let response = try await client.get(uri) { req in
            try req.query.encode(["apiKey": apiKey])
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "WatchMode genres responded with \(response.status.code)")
        }
        return try response.content.decode([WatchModeGenre].self)
    }

    func listTitles(genreID: Int? = nil, page: Int = 1, sortBy: String = "popularity_desc") async throws -> WatchModeListTitlesResponse {
        let uri = URI(string: "\(Self.baseURL)/list-titles/")
        let response = try await client.get(uri) { req in
            var params: [String: String] = [
                "apiKey": apiKey,
                "types": "movie",
                "page": String(page),
                "sort_by": sortBy,
            ]
            if let genreID {
                params["genres"] = String(genreID)
            }
            try req.query.encode(params)
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "WatchMode list-titles responded with \(response.status.code)")
        }
        return try response.content.decode(WatchModeListTitlesResponse.self)
    }
}

struct WatchModeDetails: Content {
    let id: Int
    let tmdbID: Int?
    let genres: [Int]?
    let genreNames: [String]?
    let trailer: String?
    let trailerThumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tmdbID = "tmdb_id"
        case genres
        case genreNames = "genre_names"
        case trailer
        case trailerThumbnail = "trailer_thumbnail"
    }
}

struct WatchModeGenre: Content {
    let id: Int
    let name: String
}

struct WatchModeListTitle: Content {
    let id: Int
    let title: String
    let year: Int?
    let imdbID: String?
    let tmdbID: Int?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case imdbID = "imdb_id"
        case tmdbID = "tmdb_id"
        case type
    }
}

struct WatchModeListTitlesResponse: Content {
    let titles: [WatchModeListTitle]
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case titles
        case totalPages = "total_pages"
    }
}

struct WatchModeTitleData: Sendable {
    let details: WatchModeDetails
    let sources: [WatchModeSource]
}

struct WatchModeSource: Content {
    let sourceID: Int?
    let name: String
    let type: String
    let region: String?
    let iosURL: String?
    let androidURL: String?
    let webURL: String?
    let format: String?
    let price: Double?

    enum CodingKeys: String, CodingKey {
        case sourceID   = "source_id"
        case name
        case type
        case region
        case iosURL     = "ios_url"
        case androidURL = "android_url"
        case webURL     = "web_url"
        case format
        case price
    }
}

actor WatchModeCache {
    static let shared = WatchModeCache()

    private struct TitleEntry {
        let data: WatchModeTitleData
        let expiresAt: Date
    }

    private struct GenresEntry {
        let genres: [WatchModeGenre]
        let expiresAt: Date
    }

    private struct ListEntry {
        let response: WatchModeListTitlesResponse
        let expiresAt: Date
    }

    private struct DetailsEntry {
        let details: WatchModeDetails
        let expiresAt: Date
    }

    private var titles: [String: TitleEntry] = [:]
    private var detailsOnly: [String: DetailsEntry] = [:]
    private var genresEntry: GenresEntry?
    private var lists: [String: ListEntry] = [:]

    private let titleTTL: TimeInterval = 24 * 60 * 60          // 24 hours
    private let genresTTL: TimeInterval = 7 * 24 * 60 * 60     // 7 days
    private let listTTL: TimeInterval = 6 * 60 * 60            // 6 hours

    func titleData(for imdbID: String, using service: WatchModeService) async throws -> WatchModeTitleData {
        if let entry = titles[imdbID], entry.expiresAt > Date() {
            return entry.data
        }
        let fresh = try await service.titleData(imdbID: imdbID)
        titles[imdbID] = TitleEntry(data: fresh, expiresAt: Date().addingTimeInterval(titleTTL))
        // Piggy-back the details in the details-only cache too.
        detailsOnly[imdbID] = DetailsEntry(details: fresh.details, expiresAt: Date().addingTimeInterval(titleTTL))
        return fresh
    }

    func details(for imdbID: String, using service: WatchModeService) async throws -> WatchModeDetails {
        if let entry = detailsOnly[imdbID], entry.expiresAt > Date() {
            return entry.details
        }
        if let entry = titles[imdbID], entry.expiresAt > Date() {
            return entry.data.details
        }
        let fresh = try await service.details(imdbID: imdbID)
        detailsOnly[imdbID] = DetailsEntry(details: fresh, expiresAt: Date().addingTimeInterval(titleTTL))
        return fresh
    }

    func genres(using service: WatchModeService) async throws -> [WatchModeGenre] {
        if let entry = genresEntry, entry.expiresAt > Date() {
            return entry.genres
        }
        let fresh = try await service.genres()
        genresEntry = GenresEntry(genres: fresh, expiresAt: Date().addingTimeInterval(genresTTL))
        return fresh
    }

    func listTitles(genreID: Int, page: Int, using service: WatchModeService) async throws -> WatchModeListTitlesResponse {
        let key = "\(genreID)|\(page)"
        if let entry = lists[key], entry.expiresAt > Date() {
            return entry.response
        }
        let fresh = try await service.listTitles(genreID: genreID, page: page)
        lists[key] = ListEntry(response: fresh, expiresAt: Date().addingTimeInterval(listTTL))
        return fresh
    }

    func popularTitles(page: Int, using service: WatchModeService) async throws -> WatchModeListTitlesResponse {
        let key = "popular|\(page)"
        if let entry = lists[key], entry.expiresAt > Date() {
            return entry.response
        }
        let fresh = try await service.listTitles(genreID: nil, page: page)
        lists[key] = ListEntry(response: fresh, expiresAt: Date().addingTimeInterval(listTTL))
        return fresh
    }
}
