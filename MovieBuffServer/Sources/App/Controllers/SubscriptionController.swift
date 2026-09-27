import Vapor
import Fluent
import AppStoreServerLibrary

struct SubscriptionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
            .grouped("me", "subscription")

        // Client posts here after a successful StoreKit purchase.
        protected.post("apple", "verify", use: verifyApple)

        // App Store Server Notifications V2 webhook. Apple's servers call this
        // directly, so it must be PUBLIC (no user auth) — the JWS signature is the
        // authentication. Configure this URL in App Store Connect.
        routes.post("subscription", "apple", "notifications", use: appleNotifications)
    }

    /// Consumes a signed JWS transaction from StoreKit 2, verifies it against
    /// Apple's certificate chain, and updates the user's subscription state.
    @Sendable
    func verifyApple(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(VerifyAppleSubscriptionRequest.self)

        let iap = try AppleIAPService.make(req)
        let transaction = try await iap.verifyTransaction(body.signedTransaction)

        try applyTransaction(transaction, fallbackProductID: body.productID, to: user, strict: true)
        try await user.save(on: req.db)

        let userID = try user.requireID()
        req.logger.info("Subscription verified for user=\(userID) expires=\(user.subscriptionExpiresAt.map(String.init(describing:)) ?? "nil") product=\(user.subscriptionProductID ?? "?")")
        return try UserDTO(user)
    }

    /// App Store Server Notifications V2. Keeps subscription state fresh for events
    /// that happen outside the app: renewals, expirations, refunds, and revocations.
    @Sendable
    func appleNotifications(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(AppleNotificationBody.self)
        let iap = try AppleIAPService.make(req)
        let payload = try await iap.verifyNotification(body.signedPayload)

        let type = payload.notificationType
        req.logger.info("App Store notification: \(payload.rawNotificationType ?? "?") / \(payload.rawSubtype ?? "-")")

        // A few notification types (e.g. TEST) carry no transaction — just acknowledge.
        guard let signedTransactionInfo = payload.data?.signedTransactionInfo else {
            return .ok
        }

        let transaction = try await iap.verifyTransaction(signedTransactionInfo)

        guard let originalID = transaction.originalTransactionId,
              let user = try await User.query(on: req.db)
                  .filter(\.$subscriptionOriginalID == originalID)
                  .first()
        else {
            // No matching user yet (e.g. purchase not yet synced by the app). Ack so
            // Apple doesn't retry indefinitely; the client's own verify call will catch up.
            req.logger.warning("App Store notification \(payload.rawNotificationType ?? "?") — no user for originalTransactionId=\(transaction.originalTransactionId ?? "nil")")
            return .ok
        }

        // Non-strict: webhook must always return 200, even for transactions without an
        // expiry, so Apple doesn't keep retrying.
        try applyTransaction(transaction, fallbackProductID: user.subscriptionProductID, to: user, strict: false, notificationType: type)
        try await user.save(on: req.db)

        let userID = try user.requireID()
        req.logger.info("Subscription updated from notification for user=\(userID) type=\(payload.rawNotificationType ?? "?") expires=\(user.subscriptionExpiresAt.map(String.init(describing:)) ?? "nil")")
        return .ok
    }

    // MARK: - Applying a transaction to a user

    /// Writes a verified transaction onto the user. A refund/revocation expires the
    /// subscription immediately; otherwise the expiration date is taken from the
    /// transaction. When `strict`, a transaction without an expiration throws (used
    /// for the client verify call); the webhook passes `strict: false`.
    private func applyTransaction(
        _ transaction: DecodedTransaction,
        fallbackProductID: String?,
        to user: User,
        strict: Bool,
        notificationType: NotificationTypeV2? = nil
    ) throws {
        let isRevoked = transaction.revocationDate != nil
            || notificationType == .refund
            || notificationType == .revoke

        if isRevoked {
            // Expire now (or at the revocation instant) so `isPremium` becomes false.
            user.subscriptionExpiresAt = transaction.revocationDate ?? Date()
        } else if let expiresDate = transaction.expiresDate {
            user.subscriptionExpiresAt = expiresDate
        } else if strict {
            throw Abort(.badRequest, reason: "Transaction has no expiration — is this an auto-renewing subscription?")
        }
        // else: non-strict + no expiry → leave the existing expiry untouched.

        user.subscriptionProvider = "apple"
        user.subscriptionOriginalID = transaction.originalTransactionId ?? user.subscriptionOriginalID
        user.subscriptionProductID = transaction.productId ?? fallbackProductID
    }
}
