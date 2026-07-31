import Vapor
import Fluent

final class User: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @Field(key: "email") var email: String
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "display_name") var displayName: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    @Children(for: \.$user) var savedMovies: [SavedMovie]
    @Children(for: \.$user) var tokens: [UserToken]

    init() {}

    init(id: UUID? = nil, email: String, passwordHash: String, displayName: String) {
        self.id = id
        self.email = email.lowercased()
        self.passwordHash = passwordHash
        self.displayName = displayName
    }

    func generateToken() throws -> UserToken {
        try UserToken(
            value: [UInt8].random(count: 32).base64,
            userID: self.requireID()
        )
    }
}

extension User: ModelAuthenticatable {
    static let usernameKey = \User.$email
    static let passwordHashKey = \User.$passwordHash

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}
