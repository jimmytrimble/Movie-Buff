import Vapor
import Fluent

/// A user's thumbs-up / thumbs-down feedback on a trailer in the Reels feed.
/// The rating shapes future feeds: up-rated genres are boosted, down-rated genres
/// are suppressed, and down-rated titles are excluded from the feed entirely.
final class ReelRating: Model, @unchecked Sendable {
    static let schema = "reel_ratings"

    /// Whether the user liked ("up") or disliked ("down") the trailer.
    enum Value: String, Codable {
        case up
        case down
    }

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "imdb_id") var imdbID: String
    @Field(key: "rating") var rating: String
    /// Genres of the rated title, stored pipe-separated so we can weight the feed
    /// without re-fetching OMDB details for every rating.
    @Field(key: "genres") var genresRaw: String
    @Timestamp(key: "rated_at", on: .create) var ratedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: User.IDValue,
        imdbID: String,
        rating: Value,
        genres: [String]
    ) {
        self.id = id
        self.$user.id = userID
        self.imdbID = imdbID
        self.rating = rating.rawValue
        self.genresRaw = Self.encode(genres)
    }

    var value: Value? { Value(rawValue: rating) }

    var genres: [String] {
        genresRaw
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func encode(_ genres: [String]) -> String {
        genres
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }
}
