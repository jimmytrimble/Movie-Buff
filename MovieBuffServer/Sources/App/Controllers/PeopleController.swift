import Vapor

struct PeopleController: RouteCollection {
    private static let maxCreditsReturned = 40

    func boot(routes: any RoutesBuilder) throws {
        // Free tier: person search & filmographies are open to any signed-in user.
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
            .grouped("people")

        protected.get("search", use: search)
        protected.get(":tmdbID", "movies", use: filmography)
    }

    @Sendable
    func search(req: Request) async throws -> PersonSearchResponse {
        guard let query = req.query[String.self, at: "q"], !query.isEmpty else {
            throw Abort(.badRequest, reason: "Missing query parameter `q`")
        }
        let page = req.query[Int.self, at: "page"] ?? 1
        let service = try TMDbService.make(for: req)
        let response = try await service.searchPeople(query: query, page: page)

        // Filter to people who are relevant to filmmaking, sorted by popularity so
        // "Tom Hanks" surfaces the actor before some unrelated crew member.
        let dtos = response.results
            .filter { person in
                guard let dept = person.knownForDepartment?.lowercased() else { return true }
                return ["acting", "directing", "writing", "production"].contains(dept)
            }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(20)
            .map(PersonSummaryDTO.init(from:))

        return PersonSearchResponse(results: Array(dtos))
    }

    @Sendable
    func filmography(req: Request) async throws -> PersonMovieCreditsResponse {
        guard let tmdbID = req.parameters.get("tmdbID", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid tmdbID")
        }
        let service = try TMDbService.make(for: req)
        let credits = try await service.combinedCredits(personID: tmdbID)

        // De-dupe by (mediaType, tmdb id) — a person can appear as both cast and
        // crew on the same title. Cast entry wins so `character` shows before `job`.
        struct Key: Hashable { let mediaType: String; let id: Int }
        var byKey: [Key: TMDbCombinedCredit] = [:]
        for credit in credits.cast {
            byKey[Key(mediaType: credit.mediaType, id: credit.id)] = credit
        }
        for credit in credits.crew {
            let key = Key(mediaType: credit.mediaType, id: credit.id)
            if byKey[key] == nil { byKey[key] = credit }
        }

        // Sort by release/air date desc; undated entries sink to the bottom.
        // Cap the count so we don't hammer TMDb for people with 300+ credits.
        let sorted = byKey.values.sorted { a, b in
            (a.displayDate ?? "") > (b.displayDate ?? "")
        }
        let candidates = Array(sorted.prefix(Self.maxCreditsReturned))

        // Resolve tmdb→imdb concurrently so the client can use the same imdb-keyed
        // detail flow. Entries without an imdbID are silently dropped.
        let resolved: [PersonMovieCreditDTO] = await withTaskGroup(of: (Int, PersonMovieCreditDTO?).self) { group in
            for (index, credit) in candidates.enumerated() {
                group.addTask {
                    guard let imdbID = try? await service.externalIDs(
                        tmdbID: credit.id, mediaType: credit.mediaType
                    ).imdbID, !imdbID.isEmpty else {
                        return (index, nil)
                    }
                    let year: String? = credit.displayDate.flatMap {
                        $0.count >= 4 ? String($0.prefix(4)) : nil
                    }
                    let poster = credit.posterPath.map { "https://image.tmdb.org/t/p/w500\($0)" }
                    return (index, PersonMovieCreditDTO(
                        imdbID: imdbID,
                        title: credit.displayTitle,
                        year: year,
                        posterURL: poster,
                        character: credit.character,
                        job: credit.job,
                        mediaType: credit.mediaType
                    ))
                }
            }
            var indexed: [(Int, PersonMovieCreditDTO)] = []
            for await (index, dto) in group {
                if let dto { indexed.append((index, dto)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return PersonMovieCreditsResponse(results: resolved)
    }
}
