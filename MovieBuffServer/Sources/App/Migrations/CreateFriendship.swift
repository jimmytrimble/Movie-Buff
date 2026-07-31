import Fluent

struct CreateFriendship: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("friendships")
            .id()
            .field("requester_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("addressee_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "requester_id", "addressee_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("friendships").delete()
    }
}
