import Vapor
import Fluent

final class Comment: Model, @unchecked Sendable {
    static let schema = "comments"

    @ID(key: .id) var id: UUID?
    @Field(key: "imdb_id") var imdbID: String
    @Parent(key: "user_id") var user: User
    @OptionalParent(key: "parent_id") var parent: Comment?
    @Field(key: "content") var content: String
    @Field(key: "is_spoiler") var isSpoiler: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(
        imdbID: String,
        userID: User.IDValue,
        content: String,
        parentID: Comment.IDValue? = nil,
        isSpoiler: Bool = false
    ) {
        self.imdbID = imdbID
        self.$user.id = userID
        self.content = content
        self.$parent.id = parentID
        self.isSpoiler = isSpoiler
    }
}
