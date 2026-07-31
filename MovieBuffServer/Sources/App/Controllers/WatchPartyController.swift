import Vapor
import Fluent

struct WatchPartyController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
            .grouped("watch-parties")

        protected.get(use: listPending)
        protected.post(use: start)
        protected.get(":partyID", use: get)
        protected.post(":partyID", "accept", use: accept)
        protected.post(":partyID", "decline", use: decline)
        protected.post(":partyID", "vote", use: vote)
        protected.post(":partyID", "continue", use: continueSwiping)
        protected.delete(":partyID", use: end)
    }

    // MARK: - Listing

    @Sendable
    func listPending(req: Request) async throws -> [WatchPartyDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        let parties = try await WatchParty.query(on: req.db)
            .group(.or) { or in
                or.filter(\.$initiator.$id == userID)
                or.filter(\.$recipient.$id == userID)
            }
            .filter(\.$status != WatchPartyStatus.ended.rawValue)
            .with(\.$initiator)
            .with(\.$recipient)
            .sort(\.$createdAt, .descending)
            .all()

        var out: [WatchPartyDTO] = []
        for party in parties {
            out.append(try await makeDTO(party, currentUserID: userID, on: req.db))
        }
        return out
    }

    // MARK: - Start

    @Sendable
    func start(req: Request) async throws -> WatchPartyDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let body = try req.content.decode(StartWatchPartyRequest.self)
        guard let sourceEnum = WatchPartySource(rawValue: body.source) else {
            throw Abort(.badRequest, reason: "Invalid source")
        }
        if sourceEnum == .genre, (body.genre ?? "").isEmpty {
            throw Abort(.badRequest, reason: "genre required when source == \"genre\"")
        }

        try await requireAcceptedFriendship(a: userID, b: body.recipientID, on: req.db)

        let deck = try await buildDeck(
            source: sourceEnum,
            genre: body.genre,
            initiatorID: userID,
            recipientID: body.recipientID,
            on: req
        )
        if deck.isEmpty {
            throw Abort(.badRequest, reason: "No movies available for this selection")
        }

        let encoded = try JSONEncoder().encode(deck)
        let party = WatchParty(
            initiatorID: userID,
            recipientID: body.recipientID,
            source: sourceEnum,
            genre: body.genre,
            deckJSON: String(data: encoded, encoding: .utf8) ?? "[]"
        )
        try await party.save(on: req.db)
        try await party.$initiator.load(on: req.db)
        try await party.$recipient.load(on: req.db)

        await PushService.sendWatchPartyInvite(
            recipientID: body.recipientID,
            senderDisplayName: user.displayName,
            partyID: try party.requireID(),
            on: req
        )

        return try await makeDTO(party, currentUserID: userID, on: req.db)
    }

    // MARK: - Get / accept / decline / end

    @Sendable
    func get(req: Request) async throws -> WatchPartyDTO {
        let (user, party) = try await loadParty(req)
        return try await makeDTO(party, currentUserID: try user.requireID(), on: req.db)
    }

    @Sendable
    func accept(req: Request) async throws -> WatchPartyDTO {
        let (user, party) = try await loadParty(req)
        let userID = try user.requireID()
        guard party.$recipient.id == userID else {
            throw Abort(.forbidden, reason: "Only the recipient can accept")
        }
        guard party.status == WatchPartyStatus.pending.rawValue else {
            throw Abort(.badRequest, reason: "Party is not pending")
        }
        party.status = WatchPartyStatus.active.rawValue
        try await party.save(on: req.db)
        return try await makeDTO(party, currentUserID: userID, on: req.db)
    }

    @Sendable
    func decline(req: Request) async throws -> HTTPStatus {
        let (user, party) = try await loadParty(req)
        let userID = try user.requireID()
        guard party.$recipient.id == userID else {
            throw Abort(.forbidden, reason: "Only the recipient can decline")
        }
        try await party.delete(on: req.db)
        return .noContent
    }

    @Sendable
    func end(req: Request) async throws -> HTTPStatus {
        let (user, party) = try await loadParty(req)
        let userID = try user.requireID()
        guard party.$initiator.id == userID || party.$recipient.id == userID else {
            throw Abort(.forbidden)
        }
        try await party.delete(on: req.db)
        return .noContent
    }

    // MARK: - Vote

    @Sendable
    func vote(req: Request) async throws -> WatchPartyVoteResult {
        let (user, party) = try await loadParty(req)
        let userID = try user.requireID()
        let body = try req.content.decode(WatchPartyVoteRequest.self)

        guard party.status == WatchPartyStatus.active.rawValue else {
            throw Abort(.badRequest, reason: "Party is not active")
        }
        guard party.$initiator.id == userID || party.$recipient.id == userID else {
            throw Abort(.forbidden)
        }

        let partyID = try party.requireID()

        // Idempotent upsert: if this user already voted on this movie, update the vote.
        let existing = try await WatchPartyVote.query(on: req.db)
            .filter(\.$party.$id == partyID)
            .filter(\.$user.$id == userID)
            .filter(\.$imdbID == body.imdbID)
            .first()
        if let existing {
            existing.vote = body.vote
            try await existing.save(on: req.db)
        } else {
            let vote = WatchPartyVote(
                partyID: partyID,
                userID: userID,
                imdbID: body.imdbID,
                vote: body.vote
            )
            try await vote.save(on: req.db)
        }

        var matchTriggered = false
        if body.vote {
            let opponentID = (party.$initiator.id == userID) ? party.$recipient.id : party.$initiator.id
            let opponentYes = try await WatchPartyVote.query(on: req.db)
                .filter(\.$party.$id == partyID)
                .filter(\.$user.$id == opponentID)
                .filter(\.$imdbID == body.imdbID)
                .filter(\.$vote == true)
                .first()
            if opponentYes != nil, party.matchedImdbID == nil {
                party.status = WatchPartyStatus.matched.rawValue
                party.matchedImdbID = body.imdbID
                party.initiatorWantsContinue = false
                party.recipientWantsContinue = false
                try await party.save(on: req.db)
                matchTriggered = true

                await PushService.sendWatchPartyMatch(
                    recipientID: opponentID,
                    senderDisplayName: user.displayName,
                    partyID: partyID,
                    imdbID: body.imdbID,
                    on: req
                )
            }
        }

        let dto = try await makeDTO(party, currentUserID: userID, on: req.db)
        return WatchPartyVoteResult(party: dto, matchTriggered: matchTriggered)
    }

    // MARK: - Continue after a match

    @Sendable
    func continueSwiping(req: Request) async throws -> WatchPartyDTO {
        let (user, party) = try await loadParty(req)
        let userID = try user.requireID()
        guard party.status == WatchPartyStatus.matched.rawValue else {
            throw Abort(.badRequest, reason: "Party is not in matched state")
        }

        if party.$initiator.id == userID { party.initiatorWantsContinue = true }
        else if party.$recipient.id == userID { party.recipientWantsContinue = true }
        else { throw Abort(.forbidden) }

        if party.initiatorWantsContinue && party.recipientWantsContinue {
            party.status = WatchPartyStatus.active.rawValue
            party.matchedImdbID = nil
            party.initiatorWantsContinue = false
            party.recipientWantsContinue = false
        }
        try await party.save(on: req.db)
        return try await makeDTO(party, currentUserID: userID, on: req.db)
    }

    // MARK: - Helpers

    private func loadParty(_ req: Request) async throws -> (User, WatchParty) {
        let user = try req.auth.require(User.self)
        guard let partyID = req.parameters.get("partyID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid partyID")
        }
        guard let party = try await WatchParty.query(on: req.db)
            .filter(\.$id == partyID)
            .with(\.$initiator)
            .with(\.$recipient)
            .first()
        else {
            throw Abort(.notFound)
        }
        let userID = try user.requireID()
        guard party.$initiator.id == userID || party.$recipient.id == userID else {
            throw Abort(.forbidden)
        }
        return (user, party)
    }

    private func requireAcceptedFriendship(a: User.IDValue, b: User.IDValue, on db: any Database) async throws {
        let friendship = try await Friendship.query(on: db)
            .filter(\.$status == .accepted)
            .group(.or) { or in
                or.group(.and) { g in
                    g.filter(\.$requester.$id == a)
                    g.filter(\.$addressee.$id == b)
                }
                or.group(.and) { g in
                    g.filter(\.$requester.$id == b)
                    g.filter(\.$addressee.$id == a)
                }
            }
            .first()
        if friendship == nil {
            throw Abort(.forbidden, reason: "You are not friends with this user")
        }
    }

    private func makeDTO(
        _ party: WatchParty,
        currentUserID: User.IDValue,
        on db: any Database
    ) async throws -> WatchPartyDTO {
        let deck: [WatchPartyDeckEntry] = (
            try? JSONDecoder().decode(
                [WatchPartyDeckEntry].self,
                from: Data(party.deckJSON.utf8)
            )
        ) ?? []

        let partyID = try party.requireID()
        let myVotes = try await WatchPartyVote.query(on: db)
            .filter(\.$party.$id == partyID)
            .filter(\.$user.$id == currentUserID)
            .all()

        return WatchPartyDTO(
            id: partyID,
            initiator: try UserDTO(party.initiator),
            recipient: try UserDTO(party.recipient),
            source: party.source,
            genre: party.genre,
            status: party.status,
            deck: deck,
            matchedImdbID: party.matchedImdbID,
            initiatorWantsContinue: party.initiatorWantsContinue,
            recipientWantsContinue: party.recipientWantsContinue,
            myVotedImdbIDs: myVotes.map(\.imdbID),
            createdAt: party.createdAt
        )
    }

    // MARK: - Deck generation

    private func buildDeck(
        source: WatchPartySource,
        genre: String?,
        initiatorID: User.IDValue,
        recipientID: User.IDValue,
        on req: Request
    ) async throws -> [WatchPartyDeckEntry] {
        switch source {
        case .shuffle:
            return try await shuffleDeck(initiatorID: initiatorID, recipientID: recipientID, on: req.db)
        case .genre:
            return try await browsedDeck(genre: genre, on: req)
        case .all:
            return try await browsedDeck(genre: nil, on: req)
        }
    }

    private func shuffleDeck(
        initiatorID: User.IDValue,
        recipientID: User.IDValue,
        on db: any Database
    ) async throws -> [WatchPartyDeckEntry] {
        let saved = try await SavedMovie.query(on: db)
            .group(.or) { or in
                or.filter(\.$user.$id == initiatorID)
                or.filter(\.$user.$id == recipientID)
            }
            .all()
        var seen = Set<String>()
        var entries: [WatchPartyDeckEntry] = []
        for movie in saved {
            if seen.insert(movie.imdbID).inserted {
                entries.append(WatchPartyDeckEntry(
                    imdbID: movie.imdbID,
                    title: movie.title,
                    year: movie.year,
                    type: nil,
                    poster: movie.posterURL
                ))
            }
        }
        entries.shuffle()
        return Array(entries.prefix(30))
    }

    private func browsedDeck(genre: String?, on req: Request) async throws -> [WatchPartyDeckEntry] {
        // Reuse the shared browse pipeline from MovieController.
        let response = try await MovieController.browseMovies(category: genre, page: 1, req: req)
        var entries = response.results.prefix(30).map {
            WatchPartyDeckEntry(
                imdbID: $0.imdbID,
                title: $0.title,
                year: $0.year,
                type: $0.type,
                poster: $0.poster
            )
        }
        entries.shuffle()
        return entries
    }
}
