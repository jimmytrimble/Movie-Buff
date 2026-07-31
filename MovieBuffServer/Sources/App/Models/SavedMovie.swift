import Vapor
import Fluent

final class SavedMovie: Model, @unchecked Sendable {
    static let schema = "saved_movies"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "imdb_id") var imdbID: String
    @Field(key: "title") var title: String
    @OptionalField(key: "year") var year: String?
    @OptionalField(key: "poster_url") var posterURL: String?
    @Timestamp(key: "added_at", on: .create) var addedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: User.IDValue,
        imdbID: String,
        title: String,
        year: String?,
        posterURL: String?
    ) {
        self.id = id
        self.$user.id = userID
        self.imdbID = imdbID
        self.title = title
        self.year = year
        self.posterURL = posterURL
    }
}
