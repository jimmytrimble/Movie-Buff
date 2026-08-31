import Vapor
import Fluent

struct ReelsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let premium = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware(), PremiumMiddleware())
            .grouped("reels")

        premium.get(use: feed)
    }

    @Sendable
    func feed(req: Request) async throws -> [ReelEntry] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let page = max(req.query[Int.self, at: "page"] ?? 1, 1)

        return try await buildFeed(userID: userID, page: page, on: req)
    }

    private func buildFeed(userID: UUID, page: Int, on req: Request) async throws -> [ReelEntry] {
        let watchmode = try WatchModeService.make(for: req)
        let omdb = try OMDBService.make(for: req)
        let tmdb = try TMDbService.make(for: req)

        // Personalization: which WatchMode genre IDs align with the user's saved list?
        let personalGenreIDs = await topGenreIDs(for: userID, using: watchmode, omdb: omdb, on: req)

        // Pool of candidate titles — heavily weight personal genres, then fill with popular.
        // We preserve the full WatchModeListTitle so we get both imdbID (for OMDB + save) and tmdbID (for TMDb trailer lookup).
        var pool: [WatchModeListTitle] = []
        for genreID in personalGenreIDs.prefix(3) {
            if let list = try? await WatchModeCache.shared.listTitles(genreID: genreID, page: page, using: watchmode) {
                pool.append(contentsOf: list.titles)
            }
        }
        if pool.count < 30 {
            if let popular = try? await WatchModeCache.shared.popularTitles(page: page, using: watchmode) {
                pool.append(contentsOf: popular.titles)
            }
        }

        // Dedupe by imdbID, cap the candidate set.
        var seen = Set<String>()
        let candidates = pool.filter { title in
            guard let imdbID = title.imdbID else { return false }
            return seen.insert(imdbID).inserted
        }.prefix(60)

        var reels: [ReelEntry] = []
        var noTrailerCount = 0
        var missingTmdbCount = 0
        var tmdbFailCount = 0
        var omdbFailCount = 0
        for title in candidates {
            if reels.count >= 20 { break }
            guard let imdbID = title.imdbID else { continue }
            guard let tmdbID = title.tmdbID else {
                missingTmdbCount += 1
                continue
            }

            let trailerKey: String?
            do {
                trailerKey = try await TMDbTrailerCache.shared.embeddableTrailerKey(
                    for: tmdbID,
                    using: tmdb,
                    client: req.client
                )
            } catch {
                tmdbFailCount += 1
                continue
            }
            guard let trailerKey else {
                noTrailerCount += 1
                continue
            }

            guard let omdbDetail = try? await OMDBDetailCache.shared.detail(for: imdbID, using: omdb) else {
                omdbFailCount += 1
                continue
            }

            let genres = (omdbDetail.genre ?? "")
                .components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            reels.append(ReelEntry(
                imdbID: omdbDetail.imdbID,
                title: omdbDetail.title,
                year: omdbDetail.year,
                poster: omdbDetail.poster,
                trailer: "https://www.youtube.com/watch?v=\(trailerKey)",
                trailerThumbnail: "https://img.youtube.com/vi/\(trailerKey)/hqdefault.jpg",
                genres: genres
            ))
        }

        req.logger.info("Reels feed built — candidates=\(candidates.count), returned=\(reels.count), noTrailer=\(noTrailerCount), missingTmdb=\(missingTmdbCount), tmdbFail=\(tmdbFailCount), omdbFail=\(omdbFailCount)")
        reels.shuffle()
        return reels
    }

    /// Compute the user's most-saved genres, then map their names to WatchMode genre IDs.
    private func topGenreIDs(
        for userID: UUID,
        using watchmode: WatchModeService,
        omdb: OMDBService,
        on req: Request
    ) async -> [Int] {
        let saved = (try? await SavedMovie.query(on: req.db)
            .filter(\.$user.$id == userID)
            .all()) ?? []
        guard !saved.isEmpty else { return [] }

        var counts: [String: Int] = [:]
        for movie in saved {
            guard let detail = try? await OMDBDetailCache.shared.detail(for: movie.imdbID, using: omdb) else { continue }
            let names = (detail.genre ?? "")
                .components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for name in names {
                counts[name.lowercased(), default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return [] }

        let ranked = counts.sorted { $0.value > $1.value }.map(\.key)
        let allGenres = (try? await WatchModeCache.shared.genres(using: watchmode)) ?? []

        var ids: [Int] = []
        for name in ranked {
            if let match = allGenres.first(where: { $0.name.lowercased() == name }) {
                ids.append(match.id)
            }
            if ids.count >= 3 { break }
        }
        return ids
    }
}
