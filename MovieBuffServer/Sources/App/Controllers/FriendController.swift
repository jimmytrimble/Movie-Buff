import Vapor
import Fluent

struct FriendController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes.grouped(UserToken.authenticator(), User.guardMiddleware())

        let friends = protected.grouped("friends")
        friends.get(use: list)
        friends.get("search", use: searchUsers)
        friends.post("requests", use: sendRequest)
        friends.post(":friendshipID", "accept", use: accept)
        friends.delete(":friendshipID", use: removeOrDecline)
        friends.get("users", ":userID", "movies", use: friendSavedMovies)
        friends.post("users", ":userID", "share", use: shareMovie)

        let shares = protected.grouped("shares")
        shares.get(use: listShares)
        shares.get("unread-count", use: unreadShareCount)
        shares.post(":shareID", "read", use: markShareRead)
    }

    // MARK: - Friend list & requests

    @Sendable
    func list(req: Request) async throws -> [FriendDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        let friendships = try await Friendship.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$requester.$id == userID)
                group.filter(\.$addressee.$id == userID)
            }
            .with(\.$requester)
            .with(\.$addressee)
            .all()

        let sorted = friendships.sorted { a, b in
            let aRank = Self.statusRank(a.status)
            let bRank = Self.statusRank(b.status)
            if aRank != bRank { return aRank < bRank }
            // Secondary: most recently updated first for ties.
            let aDate = a.updatedAt ?? a.createdAt ?? .distantPast
            let bDate = b.updatedAt ?? b.createdAt ?? .distantPast
            return aDate > bDate
        }

        return try sorted.map { friendship in
            let iAmRequester = friendship.$requester.id == userID
            let otherUser = iAmRequester ? friendship.addressee : friendship.requester
            return FriendDTO(
                friendshipID: try friendship.requireID(),
                user: try UserDTO(otherUser),
                status: friendship.status,
                direction: iAmRequester ? .outgoing : .incoming
            )
        }
    }

    private static func statusRank(_ status: FriendshipStatus) -> Int {
        switch status {
        case .accepted: return 0
        case .pending:  return 1
        case .blocked:  return 2
        }
    }

    @Sendable
    func searchUsers(req: Request) async throws -> [UserDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        guard let raw = req.query[String.self, at: "q"] else { return [] }
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        // Collect user IDs already tied to the caller (any friendship status) so we can hide them.
        let existing = try await Friendship.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$requester.$id == userID)
                group.filter(\.$addressee.$id == userID)
            }
            .all()

        var excludedIDs = Set<UUID>()
        excludedIDs.insert(userID)
        for friendship in existing {
            excludedIDs.insert(friendship.$requester.id)
            excludedIDs.insert(friendship.$addressee.id)
        }

        // SQLite LIKE is case-insensitive for ASCII, so `~~` gives contains-match on displayName + email.
        let matches = try await User.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$displayName ~~ query)
                group.filter(\.$email ~~ query.lowercased())
            }
            .limit(25)
            .all()

        let filtered = matches.filter {
            guard let id = $0.id else { return false }
            return !excludedIDs.contains(id)
        }

        return try filtered.map { try UserDTO($0) }
    }

    @Sendable
    func sendRequest(req: Request) async throws -> FriendDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let body = try req.content.decode(FriendRequestBody.self)
        let normalized = body.email.lowercased()

        if normalized == user.email {
            throw Abort(.badRequest, reason: "You cannot add yourself as a friend")
        }

        guard let target = try await User.query(on: req.db)
            .filter(\.$email == normalized)
            .first()
        else {
            throw Abort(.notFound, reason: "No user with that email")
        }
        let targetID = try target.requireID()

        let existing = try await Friendship.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$requester.$id == userID)
                    g.filter(\.$addressee.$id == targetID)
                }
                group.group(.and) { g in
                    g.filter(\.$requester.$id == targetID)
                    g.filter(\.$addressee.$id == userID)
                }
            }
            .first()
        if existing != nil {
            throw Abort(.conflict, reason: "A friendship or pending request already exists")
        }

        let friendship = Friendship(requesterID: userID, addresseeID: targetID, status: .pending)
        try await friendship.save(on: req.db)

        return FriendDTO(
            friendshipID: try friendship.requireID(),
            user: try UserDTO(target),
            status: friendship.status,
            direction: .outgoing
        )
    }

    @Sendable
    func accept(req: Request) async throws -> FriendDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let friendshipID = req.parameters.get("friendshipID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid friendshipID")
        }

        guard let friendship = try await Friendship.query(on: req.db)
            .filter(\.$id == friendshipID)
            .with(\.$requester)
            .with(\.$addressee)
            .first()
        else {
            throw Abort(.notFound)
        }

        guard friendship.$addressee.id == userID else {
            throw Abort(.forbidden, reason: "Only the addressee can accept a request")
        }
        guard friendship.status == .pending else {
            throw Abort(.badRequest, reason: "Friendship is not pending")
        }

        friendship.status = .accepted
        try await friendship.save(on: req.db)

        return FriendDTO(
            friendshipID: try friendship.requireID(),
            user: try UserDTO(friendship.requester),
            status: friendship.status,
            direction: .incoming
        )
    }

    @Sendable
    func removeOrDecline(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let friendshipID = req.parameters.get("friendshipID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid friendshipID")
        }

        guard let friendship = try await Friendship.find(friendshipID, on: req.db) else {
            throw Abort(.notFound)
        }
        guard friendship.$requester.id == userID || friendship.$addressee.id == userID else {
            throw Abort(.forbidden)
        }

        let requesterID = friendship.$requester.id
        let addresseeID = friendship.$addressee.id

        // Cascade: remove any shares between these two users (either direction).
        try await SharedMovie.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$sender.$id == requesterID)
                    g.filter(\.$recipient.$id == addresseeID)
                }
                group.group(.and) { g in
                    g.filter(\.$sender.$id == addresseeID)
                    g.filter(\.$recipient.$id == requesterID)
                }
            }
            .delete()

        try await friendship.delete(on: req.db)
        return .noContent
    }

    // MARK: - Friend's saved movies

    @Sendable
    func friendSavedMovies(req: Request) async throws -> [SavedMovieDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let friendID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid userID")
        }

        try await requireAcceptedFriendship(userID: userID, otherID: friendID, on: req.db)

        let movies = try await SavedMovie.query(on: req.db)
            .filter(\.$user.$id == friendID)
            .sort(\.$addedAt, .descending)
            .all()
        return try movies.map { try SavedMovieDTO($0) }
    }

    // MARK: - Sharing

    @Sendable
    func shareMovie(req: Request) async throws -> SharedMovieDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let recipientID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid userID")
        }
        let body = try req.content.decode(ShareMovieRequest.self)

        try await requireAcceptedFriendship(userID: userID, otherID: recipientID, on: req.db)

        // Dedupe: if the same movie was previously shared to this recipient, refresh the existing
        // row (updates sharedAt, resets isRead, refreshes message/poster) instead of inserting a
        // duplicate.
        if let existing = try await SharedMovie.query(on: req.db)
            .filter(\.$sender.$id == userID)
            .filter(\.$recipient.$id == recipientID)
            .filter(\.$imdbID == body.imdbID)
            .first()
        {
            existing.title = body.title
            existing.year = body.year
            existing.posterURL = body.posterURL
            existing.message = body.message
            existing.isRead = false
            existing.sharedAt = Date()
            try await existing.save(on: req.db)

            await PushService.sendShareNotification(
                recipientID: recipientID,
                senderDisplayName: user.displayName,
                movieTitle: existing.title,
                message: existing.message,
                imdbID: existing.imdbID,
                shareID: existing.id,
                on: req
            )

            return SharedMovieDTO(
                id: try existing.requireID(),
                fromUser: try UserDTO(user),
                imdbID: existing.imdbID,
                title: existing.title,
                year: existing.year,
                posterURL: existing.posterURL,
                message: existing.message,
                isRead: existing.isRead,
                sharedAt: existing.sharedAt
            )
        }

        let share = SharedMovie(
            senderID: userID,
            recipientID: recipientID,
            imdbID: body.imdbID,
            title: body.title,
            year: body.year,
            posterURL: body.posterURL,
            message: body.message
        )
        try await share.save(on: req.db)

        await PushService.sendShareNotification(
            recipientID: recipientID,
            senderDisplayName: user.displayName,
            movieTitle: share.title,
            message: share.message,
            imdbID: share.imdbID,
            shareID: share.id,
            on: req
        )

        return SharedMovieDTO(
            id: try share.requireID(),
            fromUser: try UserDTO(user),
            imdbID: share.imdbID,
            title: share.title,
            year: share.year,
            posterURL: share.posterURL,
            message: share.message,
            isRead: share.isRead,
            sharedAt: share.sharedAt
        )
    }

    @Sendable
    func listShares(req: Request) async throws -> [SharedMovieDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        let shares = try await SharedMovie.query(on: req.db)
            .filter(\.$recipient.$id == userID)
            .with(\.$sender)
            .sort(\.$sharedAt, .descending)
            .all()

        return try shares.map { share in
            SharedMovieDTO(
                id: try share.requireID(),
                fromUser: try UserDTO(share.sender),
                imdbID: share.imdbID,
                title: share.title,
                year: share.year,
                posterURL: share.posterURL,
                message: share.message,
                isRead: share.isRead,
                sharedAt: share.sharedAt
            )
        }
    }

    @Sendable
    func unreadShareCount(req: Request) async throws -> UnreadShareCountDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let count = try await SharedMovie.query(on: req.db)
            .filter(\.$recipient.$id == userID)
            .filter(\.$isRead == false)
            .count()
        return UnreadShareCountDTO(count: count)
    }

    @Sendable
    func markShareRead(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let shareID = req.parameters.get("shareID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid shareID")
        }
        guard let share = try await SharedMovie.find(shareID, on: req.db) else {
            throw Abort(.notFound)
        }
        guard share.$recipient.id == userID else {
            throw Abort(.forbidden)
        }
        share.isRead = true
        try await share.save(on: req.db)
        return .noContent
    }

    // MARK: - Helpers

    private func requireAcceptedFriendship(
        userID: User.IDValue,
        otherID: User.IDValue,
        on db: any Database
    ) async throws {
        let friendship = try await Friendship.query(on: db)
            .filter(\.$status == .accepted)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$requester.$id == userID)
                    g.filter(\.$addressee.$id == otherID)
                }
                group.group(.and) { g in
                    g.filter(\.$requester.$id == otherID)
                    g.filter(\.$addressee.$id == userID)
                }
            }
            .first()
        if friendship == nil {
            throw Abort(.forbidden, reason: "You are not friends with this user")
        }
    }
}
