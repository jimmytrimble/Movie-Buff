import Vapor
import Fluent

final class PasswordResetToken: Model, @unchecked Sendable {
    static let schema = "password_reset_tokens"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "token") var token: String
    @Field(key: "expires_at") var expiresAt: Date
    @Field(key: "used") var used: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(userID: User.IDValue, token: String, expiresAt: Date) {
        self.$user.id = userID
        self.token = token
        self.expiresAt = expiresAt
        self.used = false
    }
}
