import Vapor

struct WatchPartyDeckEntry: Content, Codable {
    let imdbID: String
    let title: String
    let year: String?
    let type: String?
    let poster: String?
}

struct StartWatchPartyRequest: Content {
    let recipientID: UUID
    let source: String        // "shuffle" | "genre" | "all"
    let genre: String?        // required when source == "genre"
}

struct WatchPartyDTO: Content {
    let id: UUID
    let initiator: UserDTO
    let recipient: UserDTO
    let source: String
    let genre: String?
    let status: String
    let deck: [WatchPartyDeckEntry]
    let matchedImdbID: String?
    let initiatorWantsContinue: Bool
    let recipientWantsContinue: Bool
    /// Which imdbIDs the *current* user has already voted on (so client can resume).
    let myVotedImdbIDs: [String]
    let createdAt: Date?
}

struct WatchPartyVoteRequest: Content {
    let imdbID: String
    let vote: Bool     // true = yes / right swipe
}

struct WatchPartyVoteResult: Content {
    /// The freshly updated session.
    let party: WatchPartyDTO
    /// True if this vote created the match (opponent had also voted yes).
    let matchTriggered: Bool
}
