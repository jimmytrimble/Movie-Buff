import Vapor
import Fluent

struct EmailOrDisplayNameAuthenticator: AsyncBasicAuthenticator {
    func authenticate(basic: BasicAuthorization, for request: Request) async throws {
        let identifier = basic.username
        let normalizedEmail = identifier.lowercased()

        let user = try await User.query(on: request.db)
            .group(.or) { or in
                or.filter(\.$email == normalizedEmail)
                or.filter(\.$displayName == identifier)
            }
            .first()

        guard let user, try user.verify(password: basic.password) else {
            return
        }
        request.auth.login(user)
    }
}

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.grouped(EmailOrDisplayNameAuthenticator()).post("login", use: login)
        auth.post("forgot-password", use: forgotPassword)
        auth.post("reset-password", use: resetPassword)

        let tokenProtected = auth.grouped(UserToken.authenticator(), User.guardMiddleware())
        tokenProtected.get("me", use: me)
        tokenProtected.post("logout", use: logout)
        tokenProtected.patch("me", use: updateProfile)
    }

    @Sendable
    func register(req: Request) async throws -> LoginResponse {
        try RegisterRequest.validate(content: req)
        let body = try req.content.decode(RegisterRequest.self)

        let normalizedEmail = body.email.lowercased()
        let existing = try await User.query(on: req.db)
            .filter(\.$email == normalizedEmail)
            .first()
        if existing != nil {
            throw Abort(.conflict, reason: "An account with that email already exists")
        }

        let user = User(
            email: normalizedEmail,
            passwordHash: try Bcrypt.hash(body.password),
            displayName: body.displayName
        )
        try await user.save(on: req.db)

        let token = try user.generateToken()
        try await token.save(on: req.db)

        return LoginResponse(token: token.value, user: try UserDTO(user))
    }

    @Sendable
    func login(req: Request) async throws -> LoginResponse {
        let user = try req.auth.require(User.self)
        let token = try user.generateToken()
        try await token.save(on: req.db)
        return LoginResponse(token: token.value, user: try UserDTO(user))
    }

    @Sendable
    func me(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        return try UserDTO(user)
    }

    @Sendable
    func updateProfile(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(UpdateProfileRequest.self)

        if let rawEmail = body.email {
            let newEmail = rawEmail.lowercased()
            if newEmail != user.email {
                guard newEmail.contains("@") else {
                    throw Abort(.badRequest, reason: "Invalid email")
                }
                if try await User.query(on: req.db)
                    .filter(\.$email == newEmail)
                    .first() != nil
                {
                    throw Abort(.conflict, reason: "Email already in use")
                }
                user.email = newEmail
            }
        }

        if let name = body.displayName {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...50).contains(trimmed.count) else {
                throw Abort(.badRequest, reason: "Display name must be 1–50 characters")
            }
            user.displayName = trimmed
        }

        if let newPassword = body.newPassword {
            guard let currentPassword = body.currentPassword else {
                throw Abort(.badRequest, reason: "Current password required to change password")
            }
            guard try Bcrypt.verify(currentPassword, created: user.passwordHash) else {
                throw Abort(.unauthorized, reason: "Current password is incorrect")
            }
            guard newPassword.count >= 8 else {
                throw Abort(.badRequest, reason: "New password must be at least 8 characters")
            }
            user.passwordHash = try Bcrypt.hash(newPassword)
        }

        try await user.save(on: req.db)
        return try UserDTO(user)
    }

    @Sendable
    func forgotPassword(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(ForgotPasswordRequest.self)
        let normalizedEmail = body.email.lowercased()

        // Always return 204 so we don't leak whether the email is registered.
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == normalizedEmail)
            .first()
        else {
            return .noContent
        }
        let userID = try user.requireID()

        // Invalidate any prior unused tokens for this user.
        try await PasswordResetToken.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$used == false)
            .delete()

        let code = String(format: "%06d", Int.random(in: 0...999_999))
        let expiration = Date().addingTimeInterval(30 * 60)  // 30 minutes
        let token = PasswordResetToken(userID: userID, token: code, expiresAt: expiration)
        try await token.save(on: req.db)

        // TODO: wire up SMTP / SendGrid. For now the code is only logged for dev.
        req.logger.notice("PASSWORD RESET — email=\(user.email) code=\(code) expires=\(expiration)")

        return .noContent
    }

    @Sendable
    func resetPassword(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(ResetPasswordRequest.self)
        guard body.newPassword.count >= 8 else {
            throw Abort(.badRequest, reason: "New password must be at least 8 characters")
        }
        let normalizedEmail = body.email.lowercased()

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == normalizedEmail)
            .first()
        else {
            throw Abort(.badRequest, reason: "Invalid code or email")
        }
        let userID = try user.requireID()

        guard let token = try await PasswordResetToken.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$token == body.code)
            .filter(\.$used == false)
            .first(),
            token.expiresAt > Date()
        else {
            throw Abort(.badRequest, reason: "Invalid or expired code")
        }

        user.passwordHash = try Bcrypt.hash(body.newPassword)
        try await user.save(on: req.db)

        token.used = true
        try await token.save(on: req.db)

        // Invalidate all active sessions after a password reset.
        try await UserToken.query(on: req.db)
            .filter(\.$user.$id == userID)
            .delete()

        return .noContent
    }

    @Sendable
    func logout(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let bearer = req.headers.bearerAuthorization else {
            throw Abort(.unauthorized)
        }
        try await UserToken.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$value == bearer.token)
            .delete()
        return .noContent
    }
}
