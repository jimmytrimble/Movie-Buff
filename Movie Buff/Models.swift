import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: UUID?
    let email: String
    let displayName: String?
    let isPremium: Bool?
    let subscriptionExpiresAt: Date?
    let subscriptionProvider: String?
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let displayName: String
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct SavedMovie: Codable, Identifiable, Hashable {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?

    var id: String { imdbID }

    var posterAsURL: URL? {
        guard let posterURL, posterURL != "N/A" else { return nil }
        return URL(string: posterURL)
    }

    var summary: MovieSummary {
        MovieSummary(
            title: title,
            year: year,
            imdbID: imdbID,
            type: nil,
            poster: posterURL
        )
    }
}

struct SaveMovieRequest: Codable {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
}

struct UserDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let displayName: String?
}

enum FriendshipStatus: String, Codable, Hashable {
    case pending
    case accepted
    case blocked
}

enum FriendDirection: String, Codable, Hashable {
    case incoming
    case outgoing
}

struct FriendDTO: Codable, Identifiable, Hashable {
    let friendshipID: UUID
    let user: UserDTO
    let status: FriendshipStatus
    let direction: FriendDirection

    var id: UUID { friendshipID }

    var displayLabel: String {
        if let name = user.displayName, !name.isEmpty { return name }
        return user.email
    }
}

struct FriendRequestBody: Codable {
    let email: String
}

struct ShareMovieRequest: Codable {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
    let message: String?
}

struct SharedMovieDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let fromUser: UserDTO
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
    let message: String?
    let isRead: Bool
}

struct UnreadCountResponse: Codable {
    let count: Int
}

struct RegisterDeviceTokenRequest: Codable {
    let token: String
    let platform: String
}

struct UpdateProfileRequest: Codable {
    let email: String?
    let displayName: String?
    let currentPassword: String?
    let newPassword: String?
}

struct ForgotPasswordRequest: Codable {
    let email: String
}

struct ResetPasswordRequest: Codable {
    let email: String
    let code: String
    let newPassword: String
}

// MARK: - Watch Party (Movie Match)

enum WatchPartySource: String, Codable {
    case shuffle
    case genre
    case all
}

enum WatchPartyStatus: String, Codable {
    case pending
    case active
    case matched
    case ended
}

struct WatchPartyDeckEntry: Codable, Identifiable, Hashable {
    let imdbID: String
    let title: String
    let year: String?
    let type: String?
    let poster: String?

    var id: String { imdbID }
    var posterURL: URL? {
        guard let poster, poster != "N/A", let url = URL(string: poster) else { return nil }
        return url
    }
}

struct WatchPartyDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let initiator: UserDTO
    let recipient: UserDTO
    let source: String
    let genre: String?
    let status: String
    let deck: [WatchPartyDeckEntry]
    let matchedImdbID: String?
    let initiatorWantsContinue: Bool
    let recipientWantsContinue: Bool
    let myVotedImdbIDs: [String]
    let createdAt: Date?

    var statusEnum: WatchPartyStatus { WatchPartyStatus(rawValue: status) ?? .ended }
    var sourceEnum: WatchPartySource { WatchPartySource(rawValue: source) ?? .shuffle }

    func isInitiator(_ userID: UUID) -> Bool { initiator.id == userID }
    func isRecipient(_ userID: UUID) -> Bool { recipient.id == userID }

    func other(than userID: UUID) -> UserDTO {
        isInitiator(userID) ? recipient : initiator
    }
}

// MARK: - Comments

enum CommentFilter: String, Codable {
    case all
    case friends
}

struct CommentDTO: Codable, Identifiable, Hashable {
    let id: UUID
    let author: UserDTO
    let content: String
    let createdAt: Date?
    let parentID: UUID?
    let replyCount: Int
    let likeCount: Int
    let isLiked: Bool
    let isMine: Bool
    let isSpoiler: Bool
}

struct CommentPage: Codable {
    let comments: [CommentDTO]
    let hasMore: Bool
}

struct CreateCommentRequest: Codable {
    let content: String
    let parentID: UUID?
    let isSpoiler: Bool?
}

struct LikeResult: Codable {
    let likeCount: Int
    let isLiked: Bool
}

struct ReportCommentRequest: Codable {
    let reason: String
}

struct StartWatchPartyRequest: Codable {
    let recipientID: UUID
    let source: String
    let genre: String?
}

struct WatchPartyVoteRequest: Codable {
    let imdbID: String
    let vote: Bool
}

struct WatchPartyVoteResult: Codable {
    let party: WatchPartyDTO
    let matchTriggered: Bool
}

// MARK: - Reels

struct ReelEntry: Codable, Identifiable, Hashable {
    let imdbID: String
    let title: String
    let year: String?
    let poster: String?
    let trailer: String
    let trailerThumbnail: String?
    let genres: [String]

    var id: String { imdbID }

    /// Extract the YouTube video ID from a variety of URL shapes.
    var youtubeID: String? {
        // youtu.be/<id>
        if let host = URL(string: trailer)?.host, host.contains("youtu.be") {
            return URL(string: trailer)?.lastPathComponent
        }
        // youtube.com/watch?v=<id>
        if let items = URLComponents(string: trailer)?.queryItems,
           let v = items.first(where: { $0.name == "v" })?.value {
            return v
        }
        // youtube.com/embed/<id>
        if let path = URL(string: trailer)?.path, path.contains("/embed/") {
            return URL(string: trailer)?.lastPathComponent
        }
        return nil
    }

    var thumbnailURL: URL? {
        if let t = trailerThumbnail, let url = URL(string: t) { return url }
        if let poster, poster != "N/A", let url = URL(string: poster) { return url }
        return nil
    }
}

struct StreamingSource: Codable, Hashable, Identifiable {
    let name: String
    let type: String
    let price: Double?
    let format: String?
    let webURL: String?
    let iosURL: String?

    var id: String { "\(name)|\(type)|\(format ?? "")" }

    var bestURL: URL? {
        if let webURL, let url = URL(string: webURL) { return url }
        if let iosURL, let url = URL(string: iosURL) { return url }
        return nil
    }

    var displayType: String {
        switch type.lowercased() {
        case "subscription", "sub": return "Stream"
        case "free":                return "Free"
        case "tve", "tv":           return "TV"
        case "rent":                return "Rent"
        case "buy":                 return "Buy"
        default:                    return type.capitalized
        }
    }

    var typeSortRank: Int {
        switch type.lowercased() {
        case "subscription", "sub": return 0
        case "free":                return 1
        case "tve", "tv":           return 2
        case "rent":                return 3
        case "buy":                 return 4
        default:                    return 5
        }
    }
}

struct MovieSummary: Codable, Identifiable, Hashable {
    let title: String
    let year: String?
    let imdbID: String
    let type: String?
    let poster: String?

    var id: String { imdbID }

    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case year = "Year"
        case imdbID
        case type = "Type"
        case poster = "Poster"
    }

    var posterURL: URL? {
        guard let poster, poster != "N/A", let url = URL(string: poster) else { return nil }
        return url
    }
}

struct MovieSearchResponse: Codable {
    let search: [MovieSummary]?
    let totalResults: String?
    let response: String?

    enum CodingKeys: String, CodingKey {
        case search = "Search"
        case totalResults
        case response = "Response"
    }

    var movies: [MovieSummary] { search ?? [] }
}

struct MovieDetail: Codable, Identifiable, Hashable {
    let title: String
    let year: String?
    let rated: String?
    let released: String?
    let runtime: String?
    let genre: String?
    let director: String?
    let writer: String?
    let actors: String?
    let plot: String?
    let poster: String?
    let imdbRating: String?
    let imdbID: String
    let streaming: [StreamingSource]?
    let genres: [String]?
    let trailerYouTubeKey: String?

    var id: String { imdbID }

    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case year = "Year"
        case rated = "Rated"
        case released = "Released"
        case runtime = "Runtime"
        case genre = "Genre"
        case director = "Director"
        case writer = "Writer"
        case actors = "Actors"
        case plot = "Plot"
        case poster = "Poster"
        case imdbRating
        case imdbID
        case streaming
        case genres
        case trailerYouTubeKey
    }

    var posterURL: URL? {
        guard let poster, poster != "N/A", let url = URL(string: poster) else { return nil }
        return url
    }

    var summary: MovieSummary {
        MovieSummary(title: title, year: year, imdbID: imdbID, type: nil, poster: poster)
    }
}
// MARK: - People

struct PersonSummary: Codable, Identifiable, Hashable {
    let tmdbID: Int
    let name: String
    let profileURL: String?
    let knownFor: String?

    var id: Int { tmdbID }
    var profileImageURL: URL? { profileURL.flatMap(URL.init(string:)) }
}

struct PersonSearchResponse: Codable {
    let results: [PersonSummary]
}

struct PersonMovieCredit: Codable, Identifiable, Hashable {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
    let character: String?
    let job: String?
    let mediaType: String?   // "movie" or "tv" — nil-safe for older responses

    var id: String { imdbID }
    var isTV: Bool { mediaType == "tv" }

    var summary: MovieSummary {
        MovieSummary(title: title, year: year, imdbID: imdbID, type: nil, poster: posterURL)
    }
}

struct PersonMovieCreditsResponse: Codable {
    let results: [PersonMovieCredit]
}

