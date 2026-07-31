import Vapor

struct FriendRequestBody: Content {
    let email: String
}

struct FriendDTO: Content {
    let friendshipID: UUID
    let user: UserDTO
    let status: FriendshipStatus
    let direction: Direction

    enum Direction: String, Content {
        case outgoing
        case incoming
    }
}

struct ShareMovieRequest: Content {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
    let message: String?
}

struct SharedMovieDTO: Content {
    let id: UUID
    let fromUser: UserDTO
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
    let message: String?
    let isRead: Bool
    let sharedAt: Date?
}

struct UnreadShareCountDTO: Content {
    let count: Int
}
