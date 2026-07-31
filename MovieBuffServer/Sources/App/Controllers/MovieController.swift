import Vapor
import Fluent

struct MovieController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes.grouped(UserToken.authenticator(), User.guardMiddleware())

        let movies = protected.grouped("movies")
        movies.get("search", use: search)
        movies.get("browse", use: browse)
        movies.get("categories", use: categories)
        movies.get(":imdbID", use: detail)

        let myMovies = protected.grouped("me", "movies")
        myMovies.get(use: list)
        myMovies.post(use: save)
        myMovies.delete(":imdbID", use: unsave)
    }

    @Sendable
    func search(req: Request) async throws -> OMDBSearchResponse {
        guard let query = req.query[String.self, at: "q"], !query.isEmpty else {
            throw Abort(.badRequest, reason: "Missing query parameter `q`")
        }
        let page = req.query[Int.self, at: "page"] ?? 1
        let service = try OMDBService.make(for: req)
        return try await service.search(query: query, page: page)
    }

    @Sendable
    func browse(req: Request) async throws -> OMDBSearchResponse {
        let page = max(req.query[Int.self, at: "page"] ?? 1, 1)
        let category = req.query[String.self, at: "category"]
        return try await Self.browseMovies(category: category, page: page, req: req)
    }

    /// Shared browse pipeline used by both `/movies/browse` and `WatchPartyController`.
    /// Tries WatchMode genre match first; falls back to OMDB text search.
    /// When called without a category, produces a personalized+shuffled "smart popular" feed.
    static func browseMovies(category: String?, page: Int, req: Request) async throws -> OMDBSearchResponse {
        if let category, !category.isEmpty {
            do {
                if let genreID = try await resolveGenreID(named: category, req: req) {
                    do {
                        return try await browseByGenre(genreID: genreID, page: page, req: req)
                    } catch {
                        req.logger.error("Browse: WatchMode list-titles failed for genre \(genreID), falling back to text search: \(String(reflecting: error))")
                    }
                } else {
                    req.logger.warning("Browse: category '\(category)' did NOT match any WatchMode genre — falling back to text search")
                }
            } catch {
                req.logger.error("Browse: WatchMode genre lookup failed, falling back to text search: \(String(reflecting: error))")
            }
            return try await browseByTextSearch(category: category, page: page, req: req)
        }
        return try await smartPopular(page: page, req: req)
    }

    /// Personalized popular feed. Blends the current user's top-3 saved genres with WatchMode's
    /// global popular list. Page 1 is shuffled for variety across sessions; deeper pages keep the
    /// natural popularity ordering so pagination remains stable during a single scroll.
    private static func smartPopular(page: Int, req: Request) async throws -> OMDBSearchResponse {
        let watchmode = try WatchModeService.make(for: req)
        let omdb = try OMDBService.make(for: req)
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        let personalGenreIDs = await topGenreIDs(userID: userID, watchmode: watchmode, omdb: omdb, on: req)

        var pool: [String] = []
        for genreID in personalGenreIDs.prefix(3) {
            if let list = try? await WatchModeCache.shared.listTitles(genreID: genreID, page: page, using: watchmode) {
                pool.append(contentsOf: list.titles.compactMap(\.imdbID))
            }
        }
        if let popular = try? await WatchModeCache.shared.popularTitles(page: page, using: watchmode) {
            pool.append(contentsOf: popular.titles.compactMap(\.imdbID))
        }

        var seen = Set<String>()
        let candidates = pool.filter { seen.insert($0).inserted }.prefix(60)

        var results: [OMDBSearchResult] = []
        for id in candidates {
            if results.count >= 30 { break }
            if let detail = try? await OMDBDetailCache.shared.detail(for: id, using: omdb) {
                results.append(OMDBSearchResult(
                    imdbID: detail.imdbID,
                    title: detail.title,
                    year: detail.year,
                    type: "movie",
                    poster: detail.poster
                ))
            }
        }

        // Shuffle page 1 for freshness across app opens / logins.
        // Leave subsequent pages in natural popularity order to keep pagination consistent.
        if page == 1 {
            results.shuffle()
        }

        req.logger.info("Smart popular — page=\(page), personalGenres=\(personalGenreIDs.count), returned=\(results.count)")
        return OMDBSearchResponse(results: results, totalResults: String(results.count))
    }

    /// Compute this user's most-saved genres, mapped to WatchMode genre IDs (top 3).
    /// Returns [] if the user has no saved movies or no genre resolves cleanly.
    private static func topGenreIDs(
        userID: User.IDValue,
        watchmode: WatchModeService,
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

    private static func resolveGenreID(named name: String, req: Request) async throws -> Int? {
        let service = try WatchModeService.make(for: req)
        let genres = try await WatchModeCache.shared.genres(using: service)
        req.logger.info("Browse: WatchMode catalog has \(genres.count) genres: \(genres.map(\.name).joined(separator: ", "))")
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let match = genres.first { $0.name.lowercased() == target }
        if match == nil {
            req.logger.warning("Browse: no exact match for '\(name)' among WatchMode genres")
        }
        return match?.id
    }

    private static func browseByGenre(genreID: Int, page: Int, req: Request) async throws -> OMDBSearchResponse {
        let watchmode = try WatchModeService.make(for: req)
        let list = try await WatchModeCache.shared.listTitles(genreID: genreID, page: page, using: watchmode)

        // Take up to 30 titles that have an IMDb ID, in the order WatchMode returned them.
        let imdbIDs = list.titles.compactMap(\.imdbID).prefix(30)

        let omdbService = try OMDBService.make(for: req)
        let results: [OMDBSearchResult] = await withTaskGroup(of: (Int, OMDBSearchResult?).self) { group in
            for (index, id) in imdbIDs.enumerated() {
                group.addTask {
                    do {
                        let detail = try await OMDBDetailCache.shared.detail(for: id, using: omdbService)
                        return (index, OMDBSearchResult(
                            imdbID: detail.imdbID,
                            title: detail.title,
                            year: detail.year,
                            type: "movie",
                            poster: detail.poster
                        ))
                    } catch {
                        req.logger.warning("OMDB detail failed for \(id) during browse: \(error)")
                        return (index, nil)
                    }
                }
            }
            var indexed: [(Int, OMDBSearchResult)] = []
            for await (index, result) in group {
                if let result { indexed.append((index, result)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let total = list.totalPages.map { String($0 * 30) }
        return OMDBSearchResponse(results: results, totalResults: total)
    }

    private static func browseByTextSearch(category: String?, page: Int, req: Request) async throws -> OMDBSearchResponse {
        let searchTerm = BrowseCategories.searchTerm(for: category)
        let service = try OMDBService.make(for: req)

        // OMDB returns 10 results per page. Fetch 3 pages to get up to 30 items per client page.
        let startPage = (page - 1) * 3 + 1
        var combined: [OMDBSearchResult] = []
        var totalResults: String?

        for omdbPage in startPage..<(startPage + 3) {
            do {
                let response = try await service.search(query: searchTerm, page: omdbPage)
                combined.append(contentsOf: response.results)
                if totalResults == nil { totalResults = response.totalResults }
            } catch {
                break
            }
        }

        combined.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return OMDBSearchResponse(results: combined, totalResults: totalResults)
    }

    @Sendable
    func categories(req: Request) async throws -> [String] {
        do {
            let service = try WatchModeService.make(for: req)
            let genres = try await WatchModeCache.shared.genres(using: service)
            return genres.map(\.name).sorted()
        } catch {
            req.logger.warning("WatchMode genres fetch failed, falling back to hardcoded: \(error)")
            return BrowseCategories.all
        }
    }

    @Sendable
    func detail(req: Request) async throws -> MovieDetailResponse {
        guard let imdbID = req.parameters.get("imdbID"), !imdbID.isEmpty else {
            throw Abort(.badRequest, reason: "Missing imdbID")
        }
        let omdbService = try OMDBService.make(for: req)

        async let omdb = omdbService.detail(imdbID: imdbID)
        async let watchmode = Self.fetchWatchMode(imdbID: imdbID, req: req)

        let detail = try await omdb
        let (streaming, genres) = await watchmode
        return MovieDetailResponse(from: detail, streaming: streaming, genres: genres)
    }

    private static func fetchWatchMode(imdbID: String, req: Request) async -> (streaming: [StreamingOption], genres: [String]) {
        do {
            let service = try WatchModeService.make(for: req)
            let data = try await WatchModeCache.shared.titleData(for: imdbID, using: service)
            req.logger.info("WatchMode returned \(data.sources.count) sources, \(data.details.genreNames?.count ?? 0) genres for \(imdbID)")

            let options = data.sources.compactMap(StreamingOption.init)
            var seen = Set<String>()
            var deduped: [StreamingOption] = []
            for option in options {
                let key = "\(option.name)|\(option.type)"
                if seen.insert(key).inserted { deduped.append(option) }
            }

            let genres = data.details.genreNames ?? []
            req.logger.info("WatchMode: \(deduped.count) deduped options for \(imdbID)")
            return (deduped, genres)
        } catch {
            req.logger.error("WatchMode fetch failed for \(imdbID): \(String(reflecting: error))")
            return ([], [])
        }
    }

    @Sendable
    func list(req: Request) async throws -> [SavedMovieDTO] {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let movies = try await SavedMovie.query(on: req.db)
            .filter(\.$user.$id == userID)
            .sort(\.$addedAt, .descending)
            .all()
        return try movies.map { try SavedMovieDTO($0) }
    }

    @Sendable
    func save(req: Request) async throws -> SavedMovieDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let body = try req.content.decode(SaveMovieRequest.self)

        let existing = try await SavedMovie.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$imdbID == body.imdbID)
            .first()
        if let existing {
            return try SavedMovieDTO(existing)
        }

        let movie = SavedMovie(
            userID: userID,
            imdbID: body.imdbID,
            title: body.title,
            year: body.year,
            posterURL: body.posterURL
        )
        try await movie.save(on: req.db)
        return try SavedMovieDTO(movie)
    }

    @Sendable
    func unsave(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        guard let imdbID = req.parameters.get("imdbID") else {
            throw Abort(.badRequest, reason: "Missing imdbID")
        }
        try await SavedMovie.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$imdbID == imdbID)
            .delete()
        return .noContent
    }
}
