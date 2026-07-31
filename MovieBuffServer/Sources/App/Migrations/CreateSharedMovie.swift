import Fluent

struct CreateSharedMovie: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("shared_movies")
            .id()
            .field("sender_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("recipient_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("imdb_id", .string, .required)
            .field("title", .string, .required)
            .field("year", .string)
            .field("poster_url", .string)
            .field("message", .string)
            .field("is_read", .bool, .required)
            .field("shared_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("shared_movies").delete()
    }
}
