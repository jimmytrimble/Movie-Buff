import Fluent

struct CreateComment: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("comments")
            .id()
            .field("imdb_id", .string, .required)
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("content", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("comments").delete()
    }
}
