import Vapor
import Fluent

/// Direct messaging + sending movies — a **premium** feature (gated by
/// `PremiumMiddleware`). Both participants must be accepted friends. Delivery is
/// polling + APNs push (no persistent socket).
struct MessageController: RouteCollection {
    private let threadLimit = 200

    func boot(routes: any RoutesBuilder) throws {
        let premium = routes.grouped(
            UserToken.authenticator(),
            User.guardMiddleware(),
            PremiumMiddleware()
        )
        let messages = premium.grouped("messages")
        messages.get("conversations", use: conversations)
        messages.get("unread-count", use: unreadCount)
        messages.get("with", ":userID", use: thread)
        messages.post("with", ":userID", use: send)
    }

    // MARK: - Conversation list

    @Sendable
    func conversations(req: Request) async throws -> [ConversationDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        let all = try await Message.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$sender.$id == userID)
                group.filter(\.$recipient.$id == userID)
            }
            .with(\.$sender)
            .with(\.$recipient)
            .sort(\.$createdAt, .descending)
            .all()

        // Walk newest→oldest: the first message seen for each other-participant is
        // the latest; tally unread messages addressed to the caller along the way.
        var order: [UUID] = []
        var latest: [UUID: Message] = [:]
        var unread: [UUID: Int] = [:]
        var others: [UUID: User] = [:]

        for message in all {
            let iAmSender = message.$sender.id == userID
            let other = iAmSender ? message.recipient : message.sender
            let otherID = try other.requireID()

            if latest[otherID] == nil {
                latest[otherID] = message
                others[otherID] = other
                order.append(otherID)
            }
            if !iAmSender && !message.isRead {
                unread[otherID, default: 0] += 1
            }
        }

        return try order.map { otherID in
            ConversationDTO(
                user: try UserDTO(others[otherID]!),
                lastMessage: try MessageDTO(latest[otherID]!, viewerID: userID),
                unreadCount: unread[otherID] ?? 0
            )
        }
    }

    @Sendable
    func unreadCount(req: Request) async throws -> UnreadCountDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let count = try await Message.query(on: req.db)
            .filter(\.$recipient.$id == userID)
            .filter(\.$isRead == false)
            .count()
        return UnreadCountDTO(count: count)
    }

    // MARK: - Thread

    @Sendable
    func thread(req: Request) async throws -> [MessageDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let otherID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid userID")
        }

        let messages = try await Message.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$sender.$id == userID)
                    g.filter(\.$recipient.$id == otherID)
                }
                group.group(.and) { g in
                    g.filter(\.$sender.$id == otherID)
                    g.filter(\.$recipient.$id == userID)
                }
            }
            .sort(\.$createdAt, .descending)
            .limit(threadLimit)
            .all()

        // Mark the ones addressed to the caller as read.
        let toMark = messages.filter { $0.$recipient.id == userID && !$0.isRead }
        if !toMark.isEmpty {
            for message in toMark { message.isRead = true }
            try await req.db.transaction { db in
                for message in toMark { try await message.save(on: db) }
            }
        }

        // Return oldest→newest for natural chat order.
        return try messages.reversed().map { try MessageDTO($0, viewerID: userID) }
    }

    // MARK: - Send

    @Sendable
    func send(req: Request) async throws -> MessageDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let recipientID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid userID")
        }
        guard recipientID != userID else {
            throw Abort(.badRequest, reason: "You can't message yourself")
        }

        let body = try req.content.decode(SendMessageRequest.self)
        let trimmedText = body.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = (trimmedText?.isEmpty == false)
        guard hasText || body.movie != nil else {
            throw Abort(.badRequest, reason: "Message must have text or a movie")
        }

        try await requireAcceptedFriendship(userID: userID, otherID: recipientID, on: req.db)

        let message = Message(
            senderID: userID,
            recipientID: recipientID,
            body: hasText ? trimmedText : nil,
            movieImdbID: body.movie?.imdbID,
            movieTitle: body.movie?.title,
            movieYear: body.movie?.year,
            moviePosterURL: body.movie?.posterURL
        )
        try await message.save(on: req.db)

        await PushService.sendMessageNotification(
            recipientID: recipientID,
            senderID: userID,
            senderDisplayName: user.displayName,
            preview: message.body ?? message.movieTitle.map { "Shared \($0)" } ?? "Sent a movie",
            on: req
        )

        return try MessageDTO(message, viewerID: userID)
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
            throw Abort(.forbidden, reason: "You can only message friends")
        }
    }
}
