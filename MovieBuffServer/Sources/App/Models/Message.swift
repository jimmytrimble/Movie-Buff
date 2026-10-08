import Vapor
import Fluent

/// A direct message between two users. Carries optional text and/or an optional
/// movie attachment (sending a movie recommendation). 1:1 only — conversations
/// are derived by grouping messages on the other participant.
final class Message: Model, @unchecked Sendable {
    static let schema = "messages"

    @ID(key: .id) var id: UUID?
    @Parent(key: "sender_id") var sender: User
    @Parent(key: "recipient_id") var recipient: User
    @OptionalField(key: "body") var body: String?

    // Optional movie attachment.
    @OptionalField(key: "movie_imdb_id") var movieImdbID: String?
    @OptionalField(key: "movie_title") var movieTitle: String?
    @OptionalField(key: "movie_year") var movieYear: String?
    @OptionalField(key: "movie_poster_url") var moviePosterURL: String?

    @Field(key: "is_read") var isRead: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        senderID: User.IDValue,
        recipientID: User.IDValue,
        body: String?,
        movieImdbID: String? = nil,
        movieTitle: String? = nil,
        movieYear: String? = nil,
        moviePosterURL: String? = nil
    ) {
        self.id = id
        self.$sender.id = senderID
        self.$recipient.id = recipientID
        self.body = body
        self.movieImdbID = movieImdbID
        self.movieTitle = movieTitle
        self.movieYear = movieYear
        self.moviePosterURL = moviePosterURL
        self.isRead = false
    }
}
