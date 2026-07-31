import Fluent

struct CreateDeviceToken: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("device_tokens")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("platform", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "token")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("device_tokens").delete()
    }
}
