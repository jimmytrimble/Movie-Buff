import Fluent

struct CreateSavedMovie: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("saved_movies")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("imdb_id", .string, .required)
            .field("title", .string, .required)
            .field("year", .string)
            .field("poster_url", .string)
            .field("added_at", .datetime)
            .unique(on: "user_id", "imdb_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("saved_movies").delete()
    }
}
