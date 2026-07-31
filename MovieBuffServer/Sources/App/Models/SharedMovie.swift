import Vapor
import Fluent

final class SharedMovie: Model, @unchecked Sendable {
    static let schema = "shared_movies"

    @ID(key: .id) var id: UUID?
    @Parent(key: "sender_id") var sender: User
    @Parent(key: "recipient_id") var recipient: User
    @Field(key: "imdb_id") var imdbID: String
    @Field(key: "title") var title: String
    @OptionalField(key: "year") var year: String?
    @OptionalField(key: "poster_url") var posterURL: String?
    @OptionalField(key: "message") var message: String?
    @Field(key: "is_read") var isRead: Bool
    @Timestamp(key: "shared_at", on: .create) var sharedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        senderID: User.IDValue,
        recipientID: User.IDValue,
        imdbID: String,
        title: String,
        year: String?,
        posterURL: String?,
        message: String?
    ) {
        self.id = id
        self.$sender.id = senderID
        self.$recipient.id = recipientID
        self.imdbID = imdbID
        self.title = title
        self.year = year
        self.posterURL = posterURL
        self.message = message
        self.isRead = false
    }
}
