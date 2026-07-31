import Vapor
import Fluent

struct CommentController: RouteCollection {
    private let pageSize = 25

    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())

        let movieComments = protected.grouped("movies", ":imdbID", "comments")
        movieComments.get(use: list)
        movieComments.post(use: create)
        movieComments.delete(":commentID", use: delete)
        movieComments.post(":commentID", "like", use: toggleLike)
        movieComments.post(":commentID", "report", use: report)
        movieComments.get(":commentID", "replies", use: listReplies)
    }

    // MARK: - List (top-level, paginated)

    @Sendable
    func list(req: Request) async throws -> CommentPage {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let imdbID = req.parameters.get("imdbID"), !imdbID.isEmpty else {
            throw Abort(.badRequest, reason: "Missing imdbID")
        }
        let filter = req.query[String.self, at: "filter"] ?? "all"
        let beforeID = req.query[UUID.self, at: "before"]

        var query = Comment.query(on: req.db)
            .filter(\.$imdbID == imdbID)
            .filter(\.$parent.$id == nil)      // top-level only
            .with(\.$user)
            .sort(\.$createdAt, .descending)

        if filter == "friends" {
            let visible = try await friendUserIDs(for: userID, on: req.db) + [userID]
            query = query.filter(\.$user.$id ~~ visible)
        }
        if let beforeID, let ref = try await Comment.find(beforeID, on: req.db),
           let refDate = ref.createdAt {
            query = query.filter(\.$createdAt < refDate)
        }

        let fetched = try await query.limit(pageSize + 1).all()
        let hasMore = fetched.count > pageSize
        let page = Array(fetched.prefix(pageSize))
        let dtos = try await makeDTOs(page, currentUserID: userID, on: req.db)
        return CommentPage(comments: dtos, hasMore: hasMore)
    }

    // MARK: - Replies (flat list under one parent)

    @Sendable
    func listReplies(req: Request) async throws -> [CommentDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let commentID = req.parameters.get("commentID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid commentID")
        }
        let replies = try await Comment.query(on: req.db)
            .filter(\.$parent.$id == commentID)
            .with(\.$user)
            .sort(\.$createdAt, .ascending)   // oldest → newest for reply threads
            .all()
        return try await makeDTOs(replies, currentUserID: userID, on: req.db)
    }

    // MARK: - Create (top-level or reply)

    @Sendable
    func create(req: Request) async throws -> CommentDTO {
        try CreateCommentRequest.validate(content: req)
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let imdbID = req.parameters.get("imdbID"), !imdbID.isEmpty else {
            throw Abort(.badRequest, reason: "Missing imdbID")
        }
        let body = try req.content.decode(CreateCommentRequest.self)
        let text = body.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw Abort(.badRequest, reason: "Comment cannot be empty")
        }

        // Only allow one level of nesting: if `parentID` refers to a reply, hoist to its parent.
        var effectiveParentID: Comment.IDValue? = nil
        if let claimedParent = body.parentID {
            guard let parent = try await Comment.find(claimedParent, on: req.db),
                  parent.imdbID == imdbID
            else {
                throw Abort(.badRequest, reason: "Parent comment not found for this movie")
            }
            let parentID = try parent.requireID()
            effectiveParentID = parent.$parent.id ?? parentID
        }

        let comment = Comment(
            imdbID: imdbID,
            userID: userID,
            content: text,
            parentID: effectiveParentID,
            isSpoiler: body.isSpoiler ?? false
        )
        try await comment.save(on: req.db)

        return CommentDTO(
            id: try comment.requireID(),
            author: try UserDTO(user),
            content: comment.content,
            createdAt: comment.createdAt,
            parentID: effectiveParentID,
            replyCount: 0,
            likeCount: 0,
            isLiked: false,
            isMine: true,
            isSpoiler: comment.isSpoiler
        )
    }

    // MARK: - Delete

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let commentID = req.parameters.get("commentID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid commentID")
        }
        guard let comment = try await Comment.find(commentID, on: req.db) else {
            throw Abort(.notFound)
        }
        guard comment.$user.id == userID else {
            throw Abort(.forbidden, reason: "You can only delete your own comments")
        }
        try await comment.delete(on: req.db)   // cascade drops likes + replies
        return .noContent
    }

    // MARK: - Toggle like

    @Sendable
    func toggleLike(req: Request) async throws -> LikeResult {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let commentID = req.parameters.get("commentID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid commentID")
        }
        guard try await Comment.find(commentID, on: req.db) != nil else {
            throw Abort(.notFound)
        }

        let existing = try await CommentLike.query(on: req.db)
            .filter(\.$comment.$id == commentID)
            .filter(\.$user.$id == userID)
            .first()

        let isLiked: Bool
        if let existing {
            try await existing.delete(on: req.db)
            isLiked = false
        } else {
            try await CommentLike(commentID: commentID, userID: userID).save(on: req.db)
            isLiked = true
        }

        let count = try await CommentLike.query(on: req.db)
            .filter(\.$comment.$id == commentID)
            .count()

        return LikeResult(likeCount: count, isLiked: isLiked)
    }

    // MARK: - Report

    @Sendable
    func report(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let commentID = req.parameters.get("commentID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid commentID")
        }
        guard try await Comment.find(commentID, on: req.db) != nil else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(ReportCommentRequest.self)
        let reason = body.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.count <= 100 else {
            throw Abort(.badRequest, reason: "Invalid reason")
        }

        try await CommentReport(commentID: commentID, reporterID: userID, reason: reason)
            .save(on: req.db)

        return .noContent
    }

    // MARK: - Helpers

    private func friendUserIDs(for userID: User.IDValue, on db: any Database) async throws -> [User.IDValue] {
        let friendships = try await Friendship.query(on: db)
            .filter(\.$status == .accepted)
            .group(.or) { or in
                or.filter(\.$requester.$id == userID)
                or.filter(\.$addressee.$id == userID)
            }
            .all()
        return friendships.map { $0.$requester.id == userID ? $0.$addressee.id : $0.$requester.id }
    }

    /// Batch-compute likeCount / isLiked / replyCount for a page of comments to avoid N+1 queries.
    private func makeDTOs(
        _ comments: [Comment],
        currentUserID: User.IDValue,
        on db: any Database
    ) async throws -> [CommentDTO] {
        guard !comments.isEmpty else { return [] }
        let ids = try comments.map { try $0.requireID() }

        // Likes: fetch all rows for these comments in one query.
        let allLikes = try await CommentLike.query(on: db)
            .filter(\.$comment.$id ~~ ids)
            .all()
        var likeCounts: [Comment.IDValue: Int] = [:]
        var myLikes: Set<Comment.IDValue> = []
        for like in allLikes {
            likeCounts[like.$comment.id, default: 0] += 1
            if like.$user.id == currentUserID {
                myLikes.insert(like.$comment.id)
            }
        }

        // Reply counts.
        var replyCounts: [Comment.IDValue: Int] = [:]
        let replies = try await Comment.query(on: db)
            .filter(\.$parent.$id ~~ ids)
            .field(\.$parent.$id)
            .all()
        for reply in replies {
            if let parentID = reply.$parent.id {
                replyCounts[parentID, default: 0] += 1
            }
        }

        return try comments.map { c in
            let cid = try c.requireID()
            return CommentDTO(
                id: cid,
                author: try UserDTO(c.user),
                content: c.content,
                createdAt: c.createdAt,
                parentID: c.$parent.id,
                replyCount: replyCounts[cid, default: 0],
                likeCount: likeCounts[cid, default: 0],
                isLiked: myLikes.contains(cid),
                isMine: c.$user.id == currentUserID,
                isSpoiler: c.isSpoiler
            )
        }
    }
}
