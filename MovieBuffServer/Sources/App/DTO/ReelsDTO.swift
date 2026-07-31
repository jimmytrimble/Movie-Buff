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
