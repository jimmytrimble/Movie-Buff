import Vapor
import Fluent

/// Profiles are a **general** feature — authenticated but not premium-gated.
/// Handles the signed-in user's own profile (bio, visibility, avatar) and
/// viewing other users' profiles subject to their privacy setting.
struct ProfileController: RouteCollection {
    private let listLimit = 100

    func boot(routes: any RoutesBuilder) throws {
        let protected = routes.grouped(UserToken.authenticator(), User.guardMiddleware())
        let profile = protected.grouped("profile")

        profile.get("me", use: myProfile)
        profile.patch("me", use: updateMyProfile)
        // Avatar uploads exceed the global 1 MB body cap, so collect up to 4 MB here.
        profile.on(.PUT, "me", "avatar", body: .collect(maxSize: "4mb"), use: uploadAvatar)
        profile.delete("me", "avatar", use: deleteAvatar)
        profile.get("search", use: search)
        profile.get(":userID", use: profileByID)
    }

    // MARK: - Own profile

    @Sendable
    func myProfile(req: Request) async throws -> ProfileDTO {
        let user = try req.auth.require(User.self)
        return try await buildProfile(for: user, viewer: user, isFriend: false, on: req.db)
    }

    @Sendable
    func updateMyProfile(req: Request) async throws -> ProfileDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(UpdateProfileInfoRequest.self)

        if let bio = body.bio {
            let trimmed = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= 300 else {
                throw Abort(.badRequest, reason: "Bio must be 300 characters or fewer")
            }
            user.bio = trimmed.isEmpty ? nil : trimmed
        }
        if let isPublic = body.isPublic {
            user.isPublic = isPublic
        }

        try await user.save(on: req.db)
        return try await buildProfile(for: user, viewer: user, isFriend: false, on: req.db)
    }

    @Sendable
    func uploadAvatar(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(UploadAvatarRequest.self)

        guard let data = Data(base64Encoded: body.imageBase64), !data.isEmpty else {
            throw Abort(.badRequest, reason: "Invalid image data")
        }
        // Belt-and-suspenders cap even though the client downscales first.
        guard data.count <= 3 * 1024 * 1024 else {
            throw Abort(.payloadTooLarge, reason: "Avatar is too large")
        }

        user.avatarData = data
        user.avatarContentType = "image/jpeg"
        try await user.save(on: req.db)
        return try UserDTO(user)
    }

    @Sendable
    func deleteAvatar(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        user.avatarData = nil
        user.avatarContentType = nil
        try await user.save(on: req.db)
        return try UserDTO(user)
    }

    // MARK: - Discovery

    @Sendable
    func search(req: Request) async throws -> [UserDTO] {
        let user = try req.auth.require(User.self)
        let selfID = try user.requireID()

        guard let raw = req.query[String.self, at: "q"] else { return [] }
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        // Only public profiles are discoverable; never surface the caller.
        let matches = try await User.query(on: req.db)
            .filter(\.$isPublic == true)
            .filter(\.$displayName ~~ query)
            .limit(25)
            .all()

        return try matches
            .filter { (try? $0.requireID()) != selfID }
            .map { try UserDTO($0) }
    }

    // MARK: - Viewing another user

    @Sendable
    func profileByID(req: Request) async throws -> ProfileDTO {
        let viewer = try req.auth.require(User.self)
        let viewerID = try viewer.requireID()
        guard let targetID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid userID")
        }

        if targetID == viewerID {
            return try await buildProfile(for: viewer, viewer: viewer, isFriend: false, on: req.db)
        }

        guard let target = try await User.find(targetID, on: req.db) else {
            throw Abort(.notFound)
        }

        let isFriend = try await acceptedFriendshipExists(viewerID, targetID, on: req.db)
        guard target.isPublic || isFriend else {
            throw Abort(.forbidden, reason: "This profile is private")
        }

        return try await buildProfile(for: target, viewer: viewer, isFriend: isFriend, on: req.db)
    }

    // MARK: - Helpers

    private func buildProfile(
        for owner: User,
        viewer: User,
        isFriend: Bool,
        on db: any Database
    ) async throws -> ProfileDTO {
        let ownerID = try owner.requireID()
        let viewerID = try viewer.requireID()

        let saved = try await SavedMovie.query(on: db)
            .filter(\.$user.$id == ownerID)
            .sort(\.$addedAt, .descending)
            .limit(listLimit)
            .all()

        let comments = try await Comment.query(on: db)
            .filter(\.$user.$id == ownerID)
            .sort(\.$createdAt, .descending)
            .limit(listLimit)
            .all()

        let ratings = try await ReelRating.query(on: db)
            .filter(\.$user.$id == ownerID)
            .sort(\.$ratedAt, .descending)
            .limit(listLimit)
            .all()

        return ProfileDTO(
            user: try UserDTO(owner),
            isSelf: ownerID == viewerID,
            isFriend: isFriend,
            savedCount: saved.count,
            commentCount: comments.count,
            savedMovies: try saved.map { try SavedMovieDTO($0) },
            comments: try comments.map {
                ProfileCommentDTO(
                    id: try $0.requireID(),
                    imdbID: $0.imdbID,
                    content: $0.content,
                    isSpoiler: $0.isSpoiler,
                    createdAt: $0.createdAt
                )
            },
            ratings: ratings.map { ProfileRatingDTO(imdbID: $0.imdbID, rating: $0.rating) }
        )
    }

    private func acceptedFriendshipExists(
        _ a: User.IDValue,
        _ b: User.IDValue,
        on db: any Database
    ) async throws -> Bool {
        try await Friendship.query(on: db)
            .filter(\.$status == .accepted)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$requester.$id == a)
                    g.filter(\.$addressee.$id == b)
                }
                group.group(.and) { g in
                    g.filter(\.$requester.$id == b)
                    g.filter(\.$addressee.$id == a)
                }
            }
            .first() != nil
    }
}
