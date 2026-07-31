import Vapor
import Fluent

enum WatchPartySource: String, Codable {
    case shuffle
    case genre
    case all
}

enum WatchPartyStatus: String, Codable {
    case pending
    case active
    case matched
    case ended
}

final class WatchParty: Model, @unchecked Sendable {
    static let schema = "watch_parties"

    @ID(key: .id) var id: UUID?
    @Parent(key: "initiator_id") var initiator: User
    @Parent(key: "recipient_id") var recipient: User
    @Field(key: "source") var source: String
    @OptionalField(key: "genre") var genre: String?
    @Field(key: "deck_json") var deckJSON: String
    @Field(key: "status") var status: String
    @OptionalField(key: "matched_imdb_id") var matchedImdbID: String?
    @Field(key: "initiator_wants_continue") var initiatorWantsContinue: Bool
    @Field(key: "recipient_wants_continue") var recipientWantsContinue: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(
        initiatorID: User.IDValue,
        recipientID: User.IDValue,
        source: WatchPartySource,
        genre: String?,
        deckJSON: String
    ) {
        self.$initiator.id = initiatorID
        self.$recipient.id = recipientID
        self.source = source.rawValue
        self.genre = genre
        self.deckJSON = deckJSON
        self.status = WatchPartyStatus.pending.rawValue
        self.initiatorWantsContinue = false
        self.recipientWantsContinue = false
    }
}

final class WatchPartyVote: Model, @unchecked Sendable {
    static let schema = "watch_party_votes"

    @ID(key: .id) var id: UUID?
    @Parent(key: "party_id") var party: WatchParty
    @Parent(key: "user_id") var user: User
    @Field(key: "imdb_id") var imdbID: String
    @Field(key: "vote") var vote: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(partyID: WatchParty.IDValue, userID: User.IDValue, imdbID: String, vote: Bool) {
        self.$party.id = partyID
        self.$user.id = userID
        self.imdbID = imdbID
        self.vote = vote
    }
}
