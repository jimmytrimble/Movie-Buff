import Fluent

struct AddCommentSpoilerFlag: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("comments")
            .field("is_spoiler", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("comments")
            .deleteField("is_spoiler")
            .update()
    }
}
