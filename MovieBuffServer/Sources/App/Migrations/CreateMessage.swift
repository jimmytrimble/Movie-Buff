import Fluent

struct CreateMessage: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("messages")
            .id()
            .field("sender_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("recipient_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("body", .string)
            .field("movie_imdb_id", .string)
            .field("movie_title", .string)
            .field("movie_year", .string)
            .field("movie_poster_url", .string)
            .field("is_read", .bool, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("messages").delete()
    }
}
