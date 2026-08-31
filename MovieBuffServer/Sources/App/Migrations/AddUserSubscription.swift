import Fluent

struct AddUserSubscription: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            // Provider-agnostic: "apple", "square", "admin_grant", etc. Nil = free tier.
            .field("subscription_provider", .string)
            // ISO 8601 date after which the subscription lapses. Nil = never premium.
            .field("subscription_expires_at", .datetime)
            // Apple's originalTransactionID (or a Square/other subscription ID).
            // Used to cross-reference webhooks with users.
            .field("subscription_original_id", .string)
            // The product identifier (e.g. "com.moviebuff.subscription.monthly").
            .field("subscription_product_id", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("subscription_provider")
            .deleteField("subscription_expires_at")
            .deleteField("subscription_original_id")
            .deleteField("subscription_product_id")
            .update()
    }
}
