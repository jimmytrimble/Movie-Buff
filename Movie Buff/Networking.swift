import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decoding(Error)
    case server(status: Int, message: String?)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .invalidResponse: return "Invalid response from server."
        case .decoding(let e): return "Failed to decode response: \(e.localizedDescription)"
        case .server(_, let message): return message ?? "Server error."
        case .network(let e): return e.localizedDescription
        }
    }
}

struct EmptyResponse: Codable {}

private struct AnyEncodable: Encodable {
    let wrapped: any Encodable
    func encode(to encoder: Encoder) throws {
        try wrapped.encode(to: encoder)
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?

    init(baseURL: URL = Config.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        headers: [String: String] = [:],
        authorized: Bool = false
    ) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authorized, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(wrapped: body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = extractErrorMessage(from: data)
            throw APIError.server(status: http.statusCode, message: message)
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        do {
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            print("APIClient decode failure for \(T.self): \(error)\nbody: \(preview)")
            #endif
            throw APIError.decoding(error)
        }
    }

    /// Shared decoder that tolerates Vapor's default numeric date encoding *and* ISO 8601
    /// strings, so backend date encoding changes don't crash the client.
    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            if let string = try? container.decode(String.self) {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: string) { return date }
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: string) { return date }
                // Try RFC-3339-ish without timezone / with space (Fluent SQLite sometimes emits this).
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                               "yyyy-MM-dd'T'HH:mm:ssZ",
                               "yyyy-MM-dd HH:mm:ss",
                               "yyyy-MM-dd"] {
                    df.dateFormat = format
                    if let date = df.date(from: string) { return date }
                }
            }
            if let double = try? container.decode(Double.self) {
                // Vapor's default `.deferredToDate` uses seconds since 2001-01-01.
                return Date(timeIntervalSinceReferenceDate: double)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format"
            )
        }
        return decoder
    }()

    private func extractErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["reason", "error", "message"] {
                if let value = json[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }
}

struct AuthService {
    let client: APIClient

    init(client: APIClient = .shared) { self.client = client }

    func register(email: String, password: String, displayName: String) async throws -> AuthResponse {
        try await client.request(
            path: "/auth/register",
            method: "POST",
            body: RegisterRequest(email: email, password: password, displayName: displayName)
        )
    }

    func login(identifier: String, password: String) async throws -> AuthResponse {
        let credentials = Data("\(identifier):\(password)".utf8).base64EncodedString()
        return try await client.request(
            path: "/auth/login",
            method: "POST",
            headers: ["Authorization": "Basic \(credentials)"]
        )
    }

    func me() async throws -> User {
        try await client.request(path: "/auth/me", authorized: true)
    }

    func logout() async throws {
        let _: EmptyResponse = try await client.request(
            path: "/auth/logout",
            method: "POST",
            authorized: true
        )
    }

    func updateProfile(_ request: UpdateProfileRequest) async throws -> User {
        try await client.request(
            path: "/auth/me",
            method: "PATCH",
            body: request,
            authorized: true
        )
    }

    func forgotPassword(email: String) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/auth/forgot-password",
            method: "POST",
            body: ForgotPasswordRequest(email: email)
        )
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/auth/reset-password",
            method: "POST",
            body: ResetPasswordRequest(email: email, code: code, newPassword: newPassword)
        )
    }
}

struct MovieService {
    let client: APIClient

    init(client: APIClient = .shared) { self.client = client }

    func search(query: String, page: Int = 1) async throws -> MovieSearchResponse {
        try await client.request(
            path: "/movies/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(page))
            ],
            authorized: true
        )
    }

    func browse(category: String?, page: Int) async throws -> MovieSearchResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "page", value: String(page))]
        if let category, !category.isEmpty {
            query.append(URLQueryItem(name: "category", value: category))
        }
        return try await client.request(
            path: "/movies/browse",
            query: query,
            authorized: true
        )
    }

    func categories() async throws -> [String] {
        try await client.request(path: "/movies/categories", authorized: true)
    }

    func detail(imdbID: String) async throws -> MovieDetail {
        try await client.request(path: "/movies/\(imdbID)", authorized: true)
    }

    func savedMovies() async throws -> [SavedMovie] {
        try await client.request(path: "/me/movies", authorized: true)
    }

    func save(_ request: SaveMovieRequest) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/me/movies",
            method: "POST",
            body: request,
            authorized: true
        )
    }

    func unsave(imdbID: String) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/me/movies/\(imdbID)",
            method: "DELETE",
            authorized: true
        )
    }
}

struct FriendService {
    let client: APIClient

    init(client: APIClient = .shared) { self.client = client }

    func list() async throws -> [FriendDTO] {
        try await client.request(path: "/friends", authorized: true)
    }

    func sendRequest(email: String) async throws -> FriendDTO {
        try await client.request(
            path: "/friends/requests",
            method: "POST",
            body: FriendRequestBody(email: email),
            authorized: true
        )
    }

    func searchUsers(query: String) async throws -> [UserDTO] {
        try await client.request(
            path: "/friends/search",
            query: [URLQueryItem(name: "q", value: query)],
            authorized: true
        )
    }

    func unreadCount() async throws -> Int {
        let response: UnreadCountResponse = try await client.request(
            path: "/shares/unread-count",
            authorized: true
        )
        return response.count
    }

    func accept(friendshipID: UUID) async throws -> FriendDTO {
        try await client.request(
            path: "/friends/\(friendshipID.uuidString)/accept",
            method: "POST",
            authorized: true
        )
    }

    func removeOrDecline(friendshipID: UUID) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/friends/\(friendshipID.uuidString)",
            method: "DELETE",
            authorized: true
        )
    }

    func friendMovies(userID: UUID) async throws -> [SavedMovie] {
        try await client.request(
            path: "/friends/users/\(userID.uuidString)/movies",
            authorized: true
        )
    }

    func shareMovie(userID: UUID, request: ShareMovieRequest) async throws -> SharedMovieDTO {
        try await client.request(
            path: "/friends/users/\(userID.uuidString)/share",
            method: "POST",
            body: request,
            authorized: true
        )
    }

    func inbox() async throws -> [SharedMovieDTO] {
        try await client.request(path: "/shares", authorized: true)
    }

    func markShareRead(shareID: UUID) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/shares/\(shareID.uuidString)/read",
            method: "POST",
            authorized: true
        )
    }

    func registerDeviceToken(token: String, platform: String = "ios") async throws {
        let _: EmptyResponse = try await client.request(
            path: "/me/device-tokens",
            method: "POST",
            body: RegisterDeviceTokenRequest(token: token, platform: platform),
            authorized: true
        )
    }

    func unregisterDeviceToken(token: String) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/me/device-tokens/\(token)",
            method: "DELETE",
            authorized: true
        )
    }
}

struct WatchPartyService {
    let client: APIClient
    init(client: APIClient = .shared) { self.client = client }

    func listPending() async throws -> [WatchPartyDTO] {
        try await client.request(path: "/watch-parties", authorized: true)
    }

    func start(recipientID: UUID, source: WatchPartySource, genre: String?) async throws -> WatchPartyDTO {
        try await client.request(
            path: "/watch-parties",
            method: "POST",
            body: StartWatchPartyRequest(
                recipientID: recipientID,
                source: source.rawValue,
                genre: genre
            ),
            authorized: true
        )
    }

    func get(_ partyID: UUID) async throws -> WatchPartyDTO {
        try await client.request(path: "/watch-parties/\(partyID.uuidString)", authorized: true)
    }

    func accept(_ partyID: UUID) async throws -> WatchPartyDTO {
        try await client.request(
            path: "/watch-parties/\(partyID.uuidString)/accept",
            method: "POST",
            authorized: true
        )
    }

    func decline(_ partyID: UUID) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/watch-parties/\(partyID.uuidString)/decline",
            method: "POST",
            authorized: true
        )
    }

    func end(_ partyID: UUID) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/watch-parties/\(partyID.uuidString)",
            method: "DELETE",
            authorized: true
        )
    }

    func vote(_ partyID: UUID, imdbID: String, vote: Bool) async throws -> WatchPartyVoteResult {
        try await client.request(
            path: "/watch-parties/\(partyID.uuidString)/vote",
            method: "POST",
            body: WatchPartyVoteRequest(imdbID: imdbID, vote: vote),
            authorized: true
        )
    }

    func continueSwiping(_ partyID: UUID) async throws -> WatchPartyDTO {
        try await client.request(
            path: "/watch-parties/\(partyID.uuidString)/continue",
            method: "POST",
            authorized: true
        )
    }
}

struct ReelsService {
    let client: APIClient
    init(client: APIClient = .shared) { self.client = client }

    func feed(page: Int = 1) async throws -> [ReelEntry] {
        try await client.request(
            path: "/reels",
            query: [URLQueryItem(name: "page", value: String(page))],
            authorized: true
        )
    }
}

struct CommentService {
    let client: APIClient
    init(client: APIClient = .shared) { self.client = client }

    func page(imdbID: String, filter: CommentFilter, before: UUID? = nil) async throws -> CommentPage {
        var query: [URLQueryItem] = [URLQueryItem(name: "filter", value: filter.rawValue)]
        if let before {
            query.append(URLQueryItem(name: "before", value: before.uuidString))
        }
        return try await client.request(
            path: "/movies/\(imdbID)/comments",
            query: query,
            authorized: true
        )
    }

    func replies(imdbID: String, commentID: UUID) async throws -> [CommentDTO] {
        try await client.request(
            path: "/movies/\(imdbID)/comments/\(commentID.uuidString)/replies",
            authorized: true
        )
    }

    func post(imdbID: String, content: String, parentID: UUID? = nil, isSpoiler: Bool = false) async throws -> CommentDTO {
        try await client.request(
            path: "/movies/\(imdbID)/comments",
            method: "POST",
            body: CreateCommentRequest(content: content, parentID: parentID, isSpoiler: isSpoiler),
            authorized: true
        )
    }

    func delete(imdbID: String, commentID: UUID) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/movies/\(imdbID)/comments/\(commentID.uuidString)",
            method: "DELETE",
            authorized: true
        )
    }

    func toggleLike(imdbID: String, commentID: UUID) async throws -> LikeResult {
        try await client.request(
            path: "/movies/\(imdbID)/comments/\(commentID.uuidString)/like",
            method: "POST",
            authorized: true
        )
    }

    func report(imdbID: String, commentID: UUID, reason: String) async throws {
        let _: EmptyResponse = try await client.request(
            path: "/movies/\(imdbID)/comments/\(commentID.uuidString)/report",
            method: "POST",
            body: ReportCommentRequest(reason: reason),
            authorized: true
        )
    }
}
