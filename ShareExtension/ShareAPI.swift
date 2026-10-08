import Foundation
import Security

// The extension runs in its own sandbox and can't import code from the app
// target, so it carries a minimal self-contained copy of the config, keychain
// read, and the API calls it needs (resolve titles, batch save). Titles are
// extracted on-device first (see TitleExtractor). Keep these in sync with
// Config.swift, AuthStore.swift, and the server's MovieController.

enum ShareConfig {
    nonisolated static let apiBaseURL = URL(string: "https://movie-buff-sm5m.onrender.com")!
    nonisolated static let keychainService = "com.moviebuff.auth"
    nonisolated static let keychainAccessGroup = "group.JJ.Movie-Buff"
    nonisolated static let tokenKey = "auth_token"
}

enum ShareKeychain {
    /// Reads the auth token the main app stored in the shared App Group keychain.
    /// Returns nil when the user has never signed in (or is in guest mode).
    static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ShareConfig.keychainService,
            kSecAttrAccount as String: ShareConfig.tokenKey,
            kSecAttrAccessGroup as String: ShareConfig.keychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A movie the server matched from the shared content. Mirrors the server's
/// OMDBSearchResult wire format (OMDB-style capitalized keys).
struct ExtractedMovie: Decodable, Identifiable, Sendable {
    let imdbID: String
    let title: String
    let year: String?
    let poster: String?

    var id: String { imdbID }

    /// OMDB uses the literal string "N/A" for missing posters.
    var posterURL: URL? {
        guard let poster, poster != "N/A" else { return nil }
        return URL(string: poster)
    }

    enum CodingKeys: String, CodingKey {
        case imdbID
        case title = "Title"
        case year = "Year"
        case poster = "Poster"
    }
}

struct ExtractResponse: Decodable, Sendable {
    let matches: [ExtractedMovie]
    let unmatched: [String]
}

enum ShareAPIError: LocalizedError {
    case notSignedIn
    case premiumRequired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to Movie Buff first, then try sharing again."
        case .premiumRequired:
            return "Saving movies requires a Movie Buff premium subscription."
        case .server(let message):
            return message
        }
    }
}

/// A title extracted on-device, sent to the server for OMDB resolution.
struct TitleGuess: Sendable {
    let title: String
    let year: String?
}

struct ShareAPI {
    let token: String

    func resolveTitles(_ titles: [TitleGuess]) async throws -> ExtractResponse {
        let payload: [String: Any] = [
            "titles": titles.map { guess -> [String: Any] in
                ["title": guess.title, "year": guess.year as Any]
            }
        ]
        return try await post(path: "/movies/resolve", body: payload)
    }

    func saveMovies(_ movies: [ExtractedMovie]) async throws {
        let payload: [String: Any] = [
            "movies": movies.map { movie in
                [
                    "imdbID": movie.imdbID,
                    "title": movie.title,
                    "year": movie.year as Any,
                    "posterURL": (movie.poster == "N/A" ? nil : movie.poster) as Any
                ]
            }
        ]
        let _: EmptyBody = try await post(path: "/me/movies/batch", body: payload)
    }

    private struct EmptyBody: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: ShareConfig.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareAPIError.server("Invalid response from server.")
        }
        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw ShareAPIError.notSignedIn
        case 402:
            throw ShareAPIError.premiumRequired
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["reason"] as? String }
            throw ShareAPIError.server(message ?? "Something went wrong (\(http.statusCode)).")
        }
    }
}
