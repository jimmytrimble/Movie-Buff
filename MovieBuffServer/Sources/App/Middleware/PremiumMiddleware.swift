import Vapor

/// Blocks the request with 402 Payment Required when the authenticated user
/// doesn't have an active premium subscription. Attach this AFTER the
/// authenticator + `User.guardMiddleware()` so we know a user is on the request.
struct PremiumMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let user = try request.auth.require(User.self)
        guard user.isPremium else {
            throw Abort(
                .paymentRequired,
                reason: "This feature requires a Movie Buff premium subscription."
            )
        }
        return try await next.respond(to: request)
    }
}
