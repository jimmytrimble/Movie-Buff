import Fluent

struct AddProfileSectionVisibility: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("saved_visibility", .string, .required, .sql(.default("friends")))
            .field("comments_visibility", .string, .required, .sql(.default("friends")))
            .field("ratings_visibility", .string, .required, .sql(.default("friends")))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("saved_visibility")
            .deleteField("comments_visibility")
            .deleteField("ratings_visibility")
            .update()
    }
}
