import Vapor
import Fluent

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case blocked
}

final class Friendship: Model, @unchecked Sendable {
    static let schema = "friendships"

    @ID(key: .id) var id: UUID?
    @Parent(key: "requester_id") var requester: User
    @Parent(key: "addressee_id") var addressee: User
    @Enum(key: "status") var status: FriendshipStatus
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        requesterID: User.IDValue,
        addresseeID: User.IDValue,
        status: FriendshipStatus = .pending
    ) {
        self.id = id
        self.$requester.id = requesterID
        self.$addressee.id = addresseeID
        self.status = status
    }
}
