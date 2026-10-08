import Vapor
import Fluent

final class User: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @Field(key: "email") var email: String
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "display_name") var displayName: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    // Subscription state — provider-agnostic. `subscriptionProvider` distinguishes
    // Apple/Square/admin-granted so future providers can plug in without a schema change.
    @OptionalField(key: "subscription_provider") var subscriptionProvider: String?
    @OptionalField(key: "subscription_expires_at") var subscriptionExpiresAt: Date?
    @OptionalField(key: "subscription_original_id") var subscriptionOriginalID: String?
    @OptionalField(key: "subscription_product_id") var subscriptionProductID: String?

    // Profile — a general (non-premium) feature.
    @OptionalField(key: "bio") var bio: String?
    /// When true, the user can be found in profile search and their profile is
    /// viewable by anyone. When false, only the user and accepted friends can view it.
    @Field(key: "is_public") var isPublic: Bool
    /// Per-section visibility: "private" (only me), "friends", or "public".
    @Field(key: "saved_visibility") var savedVisibility: String
    @Field(key: "comments_visibility") var commentsVisibility: String
    @Field(key: "ratings_visibility") var ratingsVisibility: String
    /// Avatar stored as resized JPEG bytes (client downscales before upload), so it
    /// survives Render's ephemeral filesystem without external object storage.
    @OptionalField(key: "avatar_data") var avatarData: Data?
    @OptionalField(key: "avatar_content_type") var avatarContentType: String?

    @Children(for: \.$user) var savedMovies: [SavedMovie]
    @Children(for: \.$user) var tokens: [UserToken]

    /// True when the user has an unexpired premium subscription.
    var isPremium: Bool {
        guard let expiry = subscriptionExpiresAt else { return false }
        return expiry > Date()
    }

    init() {}

    init(id: UUID? = nil, email: String, passwordHash: String, displayName: String) {
        self.id = id
        self.email = email.lowercased()
        self.passwordHash = passwordHash
        self.displayName = displayName
        self.isPublic = false
        self.savedVisibility = ProfileVisibility.friends.rawValue
        self.commentsVisibility = ProfileVisibility.friends.rawValue
        self.ratingsVisibility = ProfileVisibility.friends.rawValue
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
