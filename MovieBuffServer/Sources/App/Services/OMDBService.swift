import Vapor

struct OMDBService {
    let client: any Client
    let apiKey: String

    private static let baseURL = "https://www.omdbapi.com/"

    init(client: any Client, apiKey: String) {
        self.client = client
        self.apiKey = apiKey
    }

    static func make(for req: Request) throws -> OMDBService {
        guard let key = Environment.get("OMDB_API_KEY"), !key.isEmpty else {
            throw Abort(.internalServerError, reason: "OMDB_API_KEY is not configured")
        }
        return OMDBService(client: req.client, apiKey: key)
    }

    func search(query: String, page: Int = 1) async throws -> OMDBSearchResponse {
        let response = try await client.get(URI(string: Self.baseURL)) { req in
            try req.query.encode([
                "apikey": apiKey,
                "s": query,
                "page": String(page),
            ])
        }
        try validateResponse(response)
        return try response.content.decode(OMDBSearchResponse.self)
    }

    func detail(imdbID: String) async throws -> OMDBMovieDetail {
        let response = try await client.get(URI(string: Self.baseURL)) { req in
            try req.query.encode([
                "apikey": apiKey,
                "i": imdbID,
                "plot": "full",
            ])
        }
        try validateResponse(response)
        return try response.content.decode(OMDBMovieDetail.self)
    }

    private func validateResponse(_ response: ClientResponse) throws {
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "OMDB responded with \(response.status.code)")
        }
        if let errorPayload = try? response.content.decode(OMDBError.self), errorPayload.response == "False" {
            throw Abort(.notFound, reason: errorPayload.error ?? "OMDB returned no results")
        }
    }

    private struct OMDBError: Content {
        let response: String
        let error: String?

        enum CodingKeys: String, CodingKey {
            case response = "Response"
            case error = "Error"
        }
    }
}
