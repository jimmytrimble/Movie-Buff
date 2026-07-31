import Vapor
import Fluent

enum DevicePlatform: String, Codable {
    case ios
    case android
}

final class DeviceToken: Model, @unchecked Sendable {
    static let schema = "device_tokens"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "token") var token: String
    @Field(key: "platform") var platform: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: User.IDValue,
        token: String,
        platform: String
    ) {
        self.id = id
        self.$user.id = userID
        self.token = token
        self.platform = platform
    }
}
