import Vapor

struct RegisterRequest: Content {
    let email: String
    let password: String
    let displayName: String
}

extension RegisterRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
        validations.add("displayName", as: String.self, is: .count(1...50))
    }
}

struct LoginResponse: Content {
    let token: String
    let user: UserDTO
}

struct UserDTO: Content {
    let id: UUID
    let email: String
    let displayName: String
    let isPremium: Bool
    let subscriptionExpiresAt: Date?
    let subscriptionProvider: String?
    let bio: String?
    let isPublic: Bool
    /// Avatar as a base64 JPEG (small, client-downscaled). Delivered inline to
    /// avoid authenticated-image-URL handling on the client.
    let avatarBase64: String?
    // Per-section visibility ("private" | "friends" | "public"), for the editor.
    let savedVisibility: String
    let commentsVisibility: String
    let ratingsVisibility: String

    init(_ user: User) throws {
        self.id = try user.requireID()
        self.email = user.email
        self.displayName = user.displayName
        self.isPremium = user.isPremium
        self.subscriptionExpiresAt = user.subscriptionExpiresAt
        self.subscriptionProvider = user.subscriptionProvider
        self.bio = user.bio
        self.isPublic = user.isPublic
        self.avatarBase64 = user.avatarData?.base64EncodedString()
        self.savedVisibility = user.savedVisibility
        self.commentsVisibility = user.commentsVisibility
        self.ratingsVisibility = user.ratingsVisibility
    }
}

/// Sent by the iOS client after a successful StoreKit purchase. Carries the
/// signed JWS transaction produced by StoreKit 2 so the server can extract
/// and persist the subscription's expiration.
struct VerifyAppleSubscriptionRequest: Content {
    let signedTransaction: String
    let productID: String
}

/// The body Apple POSTs to our App Store Server Notifications V2 webhook.
/// See https://developer.apple.com/documentation/appstoreservernotifications/responsebodyv2
struct AppleNotificationBody: Content {
    let signedPayload: String
}

struct UpdateProfileRequest: Content {
    let email: String?
    let displayName: String?
    let currentPassword: String?
    let newPassword: String?
}

struct ForgotPasswordRequest: Content {
    let email: String
}

struct ResetPasswordRequest: Content {
    let email: String
    let code: String
    let newPassword: String
}
