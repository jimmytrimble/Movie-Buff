import Vapor
import Fluent

struct DeviceTokenController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
            .grouped("me", "device-tokens")

        protected.post(use: register)
        protected.delete(":token", use: unregister)
    }

    @Sendable
    func register(req: Request) async throws -> HTTPStatus {
        try RegisterDeviceTokenRequest.validate(content: req)
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let body = try req.content.decode(RegisterDeviceTokenRequest.self)

        // Reassign any existing row with this token value to the current user.
        // Handles: same device changed accounts, or the OS reissued the token.
        if let existing = try await DeviceToken.query(on: req.db)
            .filter(\.$token == body.token)
            .first()
        {
            existing.$user.id = userID
            existing.platform = body.platform
            try await existing.save(on: req.db)
            return .noContent
        }

        let device = DeviceToken(
            userID: userID,
            token: body.token,
            platform: body.platform
        )
        try await device.save(on: req.db)
        return .noContent
    }

    @Sendable
    func unregister(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing token")
        }
        try await DeviceToken.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$token == token)
            .delete()
        return .noContent
    }
}
