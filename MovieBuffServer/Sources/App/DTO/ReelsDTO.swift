import Vapor

struct ReelEntry: Content, Codable {
    let imdbID: String
    let title: String
    let year: String?
    let poster: String?
    let trailer: String            // YouTube URL
    let trailerThumbnail: String?
    let genres: [String]
}

/// Body for `POST /reels/:imdbID/rate` — a thumbs-up/down on a trailer, plus the
/// title's genres so the server can weight the feed without re-fetching details.
struct RateReelRequest: Content {
    let rating: String             // "up" or "down"
    let genres: [String]
}

/// A single stored rating, returned by `GET /reels/ratings` so the client can
/// restore the thumbs-up/down state a user previously chose.
struct ReelRatingDTO: Content {
    let imdbID: String
    let rating: String             // "up" or "down"

    init(_ rating: ReelRating) {
        self.imdbID = rating.imdbID
        self.rating = rating.rating
    }
}
