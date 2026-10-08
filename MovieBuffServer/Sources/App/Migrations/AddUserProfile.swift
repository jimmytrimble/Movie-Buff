import Fluent

struct AddUserProfile: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("bio", .string)
            // Private by default so enabling discovery is an explicit opt-in.
            .field("is_public", .bool, .required, .sql(.default(false)))
            .field("avatar_data", .data)
            .field("avatar_content_type", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("bio")
            .deleteField("is_public")
            .deleteField("avatar_data")
            .deleteField("avatar_content_type")
            .update()
    }
}
