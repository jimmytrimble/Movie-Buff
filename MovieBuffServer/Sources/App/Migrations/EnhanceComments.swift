import Fluent

/// Adds parent_id to comments (for replies), plus creates likes + reports tables.
struct EnhanceComments: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("comments")
            .field("parent_id", .uuid, .references("comments", "id", onDelete: .cascade))
            .update()

        try await database.schema("comment_likes")
            .id()
            .field("comment_id", .uuid, .required, .references("comments", "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "comment_id", "user_id")
            .create()

        try await database.schema("comment_reports")
            .id()
            .field("comment_id", .uuid, .required, .references("comments", "id", onDelete: .cascade))
            .field("reporter_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("reason", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("comment_reports").delete()
        try await database.schema("comment_likes").delete()
        try await database.schema("comments")
            .deleteField("parent_id")
            .update()
    }
}
