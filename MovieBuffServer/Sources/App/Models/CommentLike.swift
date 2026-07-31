import Vapor
import Fluent

final class CommentLike: Model, @unchecked Sendable {
    static let schema = "comment_likes"

    @ID(key: .id) var id: UUID?
    @Parent(key: "comment_id") var comment: Comment
    @Parent(key: "user_id") var user: User
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(commentID: Comment.IDValue, userID: User.IDValue) {
        self.$comment.id = commentID
        self.$user.id = userID
    }
}
