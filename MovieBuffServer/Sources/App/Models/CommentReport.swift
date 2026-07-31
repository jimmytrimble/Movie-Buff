import Vapor
import Fluent

final class CommentReport: Model, @unchecked Sendable {
    static let schema = "comment_reports"

    @ID(key: .id) var id: UUID?
    @Parent(key: "comment_id") var comment: Comment
    @Parent(key: "reporter_id") var reporter: User
    @Field(key: "reason") var reason: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(commentID: Comment.IDValue, reporterID: User.IDValue, reason: String) {
        self.$comment.id = commentID
        self.$reporter.id = reporterID
        self.reason = reason
    }
}
