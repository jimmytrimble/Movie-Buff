import Fluent

struct CreateWatchedMovie: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("watched_movies")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("imdb_id", .string, .required)
            .field("title", .string, .required)
            .field("year", .string)
            .field("poster_url", .string)
            .field("watched_at", .datetime)
            .unique(on: "user_id", "imdb_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("watched_movies").delete()
    }
}
