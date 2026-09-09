import Fluent

struct CreateReelRating: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("reel_ratings")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("imdb_id", .string, .required)
            .field("rating", .string, .required)
            .field("genres", .string, .required)
            .field("rated_at", .datetime)
            .unique(on: "user_id", "imdb_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("reel_ratings").delete()
    }
}
