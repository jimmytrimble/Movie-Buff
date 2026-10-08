import Vapor

/// An optional movie attached to a message (a recommendation).
struct MessageMovieDTO: Content {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
}

struct MessageDTO: Content {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let body: String?
    let movie: MessageMovieDTO?
    let isRead: Bool
    let createdAt: Date?
    /// Whether the authenticated caller sent this message (for bubble alignment).
    let isMine: Bool

    init(_ message: Message, viewerID: UUID) throws {
        self.id = try message.requireID()
        self.senderID = message.$sender.id
        self.recipientID = message.$recipient.id
        self.body = message.body
        if let imdbID = message.movieImdbID, let title = message.movieTitle {
            self.movie = MessageMovieDTO(
                imdbID: imdbID,
                title: title,
                year: message.movieYear,
                posterURL: message.moviePosterURL
            )
        } else {
            self.movie = nil
        }
        self.isRead = message.isRead
        self.createdAt = message.createdAt
        self.isMine = message.$sender.id == viewerID
    }
}

/// One entry in the conversation list: the other participant + the latest
/// message + how many are unread (addressed to the caller).
struct ConversationDTO: Content {
    let user: UserDTO
    let lastMessage: MessageDTO
    let unreadCount: Int
}

/// POST /messages/with/:userID — send text and/or a movie. At least one required.
struct SendMessageRequest: Content {
    let body: String?
    let movie: MessageMovieDTO?
}

struct UnreadCountDTO: Content {
    let count: Int
}
