import Vapor
import Fluent

struct SubscriptionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
            .grouped("me", "subscription")

        // Client posts here after a successful StoreKit purchase.
        protected.post("apple", "verify", use: verifyApple)
    }

    /// Consumes a signed JWS transaction from StoreKit 2 and updates the user's
    /// subscription state.
    ///
    /// NOTE on trust model: for a v1 we decode the JWS payload without verifying
    /// its signature. StoreKit's own verification on-device makes forgery hard, and
    /// the same `originalTransactionID` on a jailbroken device would still hit
    /// our server. Before wide distribution, swap this to full signature
    /// verification against Apple's cert chain (or use the App Store Server API
    /// via `originalTransactionID` to re-fetch the authoritative status).
    @Sendable
    func verifyApple(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(VerifyAppleSubscriptionRequest.self)

        let payload = try Self.decodeJWSPayload(body.signedTransaction)

        guard let expiresMillis = payload.expiresDate else {
            throw Abort(.badRequest, reason: "Transaction has no expiration — is this an auto-renewing subscription?")
        }
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresMillis) / 1000.0)

        user.subscriptionProvider = "apple"
        user.subscriptionOriginalID = payload.originalTransactionId
        user.subscriptionProductID = payload.productId ?? body.productID
        user.subscriptionExpiresAt = expiresAt
        try await user.save(on: req.db)

        req.logger.info("Subscription updated for user=\(try user.requireID()) expires=\(expiresAt) product=\(user.subscriptionProductID ?? "?")")

        return try UserDTO(user)
    }

    // MARK: - JWS decoding

    private struct AppleTransactionPayload: Decodable {
        let originalTransactionId: String?
        let productId: String?
        let expiresDate: Int64?   // ms since epoch
    }

    /// Splits a compact JWS (`header.payload.signature`) and base64url-decodes the
    /// middle segment. Signature verification is NOT performed here — see the
    /// note on `verifyApple`.
    static func decodeJWSPayload(_ jws: String) throws -> AppleTransactionPayload {
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else {
            throw Abort(.badRequest, reason: "Malformed signed transaction (expected 3 JWS segments).")
        }
        let payloadSegment = String(parts[1])
        guard let data = Data(base64URLEncoded: payloadSegment) else {
            throw Abort(.badRequest, reason: "Signed transaction payload is not valid base64url.")
        }
        return try JSONDecoder().decode(AppleTransactionPayload.self, from: data)
    }
}

private extension Data {
    /// Decodes a base64url string (JWT segments use `-` and `_` and drop padding).
    init?(base64URLEncoded input: String) {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = s.count % 4
        if pad > 0 { s += String(repeating: "=", count: 4 - pad) }
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }
}
