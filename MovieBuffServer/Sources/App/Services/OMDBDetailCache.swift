import Vapor

actor OMDBDetailCache {
    static let shared = OMDBDetailCache()

    private struct Entry {
        let detail: OMDBMovieDetail
        let expiresAt: Date
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60 // 24 hours

    func detail(for imdbID: String, using service: OMDBService) async throws -> OMDBMovieDetail {
        if let entry = cache[imdbID], entry.expiresAt > Date() {
            return entry.detail
        }
        let fresh = try await service.detail(imdbID: imdbID)
        cache[imdbID] = Entry(detail: fresh, expiresAt: Date().addingTimeInterval(ttl))
        return fresh
    }
}
