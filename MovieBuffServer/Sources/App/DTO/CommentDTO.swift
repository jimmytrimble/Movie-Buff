import Vapor

struct CommentDTO: Content {
    let id: UUID
    let author: UserDTO
    let content: String
    let createdAt: Date?
    let parentID: UUID?
    let replyCount: Int
    let likeCount: Int
    let isLiked: Bool
    let isMine: Bool
    let isSpoiler: Bool
}

struct CommentPage: Content {
    let comments: [CommentDTO]
    let hasMore: Bool
}

struct CreateCommentRequest: Content {
    let content: String
    let parentID: UUID?
    let isSpoiler: Bool?
}

extension CreateCommentRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("content", as: String.self, is: .count(1...500))
    }
}

struct LikeResult: Content {
    let likeCount: Int
    let isLiked: Bool
}

struct ReportCommentRequest: Content {
    let reason: String
}
