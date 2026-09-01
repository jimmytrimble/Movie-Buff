import Vapor

struct PersonSummaryDTO: Content {
    let tmdbID: Int
    let name: String
    let profileURL: String?
    let knownFor: String?

    init(from person: TMDbPerson) {
        self.tmdbID = person.id
        self.name = person.name
        self.profileURL = person.profilePath.map { "https://image.tmdb.org/t/p/w500\($0)" }
        self.knownFor = person.knownForDepartment
    }
}

struct PersonSearchResponse: Content {
    let results: [PersonSummaryDTO]
}

/// A single credit in a person's filmography (movie OR TV), already resolved
/// to imdbID so the client can route into the existing detail flow.
struct PersonMovieCreditDTO: Content {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
    let character: String?
    let job: String?
    let mediaType: String   // "movie" or "tv"
}

struct PersonMovieCreditsResponse: Content {
    let results: [PersonMovieCreditDTO]
}
