import Fluent

struct CreateWatchParty: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("watch_parties")
            .id()
            .field("initiator_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("recipient_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("source", .string, .required)      // "shuffle" | "genre" | "all"
            .field("genre", .string)                  // only when source == "genre"
            .field("deck_json", .string, .required)   // JSON [{imdbID,title,year,poster,type}]
            .field("status", .string, .required)      // pending | active | matched | ended
            .field("matched_imdb_id", .string)
            .field("initiator_wants_continue", .bool, .required, .sql(.default(false)))
            .field("recipient_wants_continue", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema("watch_party_votes")
            .id()
            .field("party_id", .uuid, .required, .references("watch_parties", "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("imdb_id", .string, .required)
            .field("vote", .bool, .required)          // true = yes / true = right swipe
            .field("created_at", .datetime)
            .unique(on: "party_id", "user_id", "imdb_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("watch_party_votes").delete()
        try await database.schema("watch_parties").delete()
    }
}
