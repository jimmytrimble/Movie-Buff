import Vapor

/// Who can see a given profile section. Combined with the overall `isPublic`
/// gate: a viewer must first be allowed to view the profile at all, then each
/// section is additionally filtered by its own visibility.
enum ProfileVisibility: String, Content, CaseIterable {
    case `private`   // only the owner
    case friends     // owner + accepted friends
    case `public`    // anyone who can view the profile

    /// Whether a viewer with the given relationship may see a section at this level.
    func allows(isSelf: Bool, isFriend: Bool) -> Bool {
        switch self {
        case .private: return isSelf
        case .friends: return isSelf || isFriend
        case .public:  return true
        }
    }

    static func parse(_ raw: String) -> ProfileVisibility {
        ProfileVisibility(rawValue: raw) ?? .friends
    }
}

/// A user's full profile: identity + bio + visibility (via `UserDTO`), plus the
/// content they've produced. Returned for the signed-in user and for other users
/// the caller is allowed to see (self, accepted friend, or a public profile).
struct ProfileDTO: Content {
    let user: UserDTO
    let isSelf: Bool
    let isFriend: Bool
    let savedCount: Int
    let commentCount: Int
    let savedMovies: [SavedMovieDTO]
    let comments: [ProfileCommentDTO]
    let ratings: [ProfileRatingDTO]
}

/// A comment the profile owner left on a movie/show.
struct ProfileCommentDTO: Content {
    let id: UUID
    let imdbID: String
    let content: String
    let isSpoiler: Bool
    let createdAt: Date?
}

/// A thumbs up/down the profile owner gave a trailer.
struct ProfileRatingDTO: Content {
    let imdbID: String
    let rating: String   // "up" | "down"
}

/// PATCH /profile/me — edit the general-profile fields. Both optional so the
/// client can update either independently.
struct UpdateProfileInfoRequest: Content {
    let bio: String?
    let isPublic: Bool?
    let savedVisibility: String?
    let commentsVisibility: String?
    let ratingsVisibility: String?
}

/// PUT /profile/me/avatar — the client downscales to ~256px JPEG and sends the
/// base64 bytes.
struct UploadAvatarRequest: Content {
    let imageBase64: String
}
