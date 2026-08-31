import Vapor

struct OMDBSearchResult: Content {
    let imdbID: String
    let title: String
    let year: String?
    let type: String?
    let poster: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdbID"
        case title = "Title"
        case year = "Year"
        case type = "Type"
        case poster = "Poster"
    }
}

struct OMDBSearchResponse: Content {
    let results: [OMDBSearchResult]
    let totalResults: String?

    enum CodingKeys: String, CodingKey {
        case results = "Search"
        case totalResults
    }
}

struct OMDBMovieDetail: Content {
    let imdbID: String
    let title: String
    let year: String?
    let rated: String?
    let released: String?
    let runtime: String?
    let genre: String?
    let director: String?
    let writer: String?
    let actors: String?
    let plot: String?
    let language: String?
    let country: String?
    let awards: String?
    let poster: String?
    let imdbRating: String?

    enum CodingKeys: String, CodingKey {
        case imdbID
        case title = "Title"
        case year = "Year"
        case rated = "Rated"
        case released = "Released"
        case runtime = "Runtime"
        case genre = "Genre"
        case director = "Director"
        case writer = "Writer"
        case actors = "Actors"
        case plot = "Plot"
        case language = "Language"
        case country = "Country"
        case awards = "Awards"
        case poster = "Poster"
        case imdbRating
    }
}

struct StreamingOption: Content {
    let name: String
    let type: String
    let price: Double?
    let format: String?
    let webURL: String?
    let iosURL: String?

    init?(from source: WatchModeSource) {
        self.name = source.name
        self.type = Self.normalize(type: source.type)
        self.price = source.price
        self.format = source.format
        self.webURL = source.webURL
        self.iosURL = source.iosURL
    }

    private static func normalize(type raw: String) -> String {
        switch raw.lowercased() {
        case "sub":                     return "subscription"
        case "free":                    return "free"
        case "rent", "purchase":        return "rent"
        case "buy":                     return "buy"
        case "tve":                     return "tve"
        default:                        return raw.lowercased()
        }
    }
}

struct MovieDetailResponse: Content {
    let imdbID: String
    let title: String
    let year: String?
    let rated: String?
    let released: String?
    let runtime: String?
    let genre: String?
    let director: String?
    let writer: String?
    let actors: String?
    let plot: String?
    let language: String?
    let country: String?
    let awards: String?
    let poster: String?
    let imdbRating: String?
    let streaming: [StreamingOption]
    let genres: [String]
    let trailerYouTubeKey: String?

    enum CodingKeys: String, CodingKey {
        case imdbID
        case title       = "Title"
        case year        = "Year"
        case rated       = "Rated"
        case released    = "Released"
        case runtime     = "Runtime"
        case genre       = "Genre"
        case director    = "Director"
        case writer      = "Writer"
        case actors      = "Actors"
        case plot        = "Plot"
        case language    = "Language"
        case country     = "Country"
        case awards      = "Awards"
        case poster      = "Poster"
        case imdbRating
        case streaming
        case genres
        case trailerYouTubeKey
    }

    init(
        from omdb: OMDBMovieDetail,
        streaming: [StreamingOption],
        genres: [String],
        trailerYouTubeKey: String? = nil
    ) {
        self.imdbID = omdb.imdbID
        self.title = omdb.title
        self.year = omdb.year
        self.rated = omdb.rated
        self.released = omdb.released
        self.runtime = omdb.runtime
        self.genre = omdb.genre
        self.director = omdb.director
        self.writer = omdb.writer
        self.actors = omdb.actors
        self.plot = omdb.plot
        self.language = omdb.language
        self.country = omdb.country
        self.awards = omdb.awards
        self.poster = omdb.poster
        self.imdbRating = omdb.imdbRating
        self.streaming = streaming
        self.genres = genres
        self.trailerYouTubeKey = trailerYouTubeKey
    }
}

struct SaveMovieRequest: Content {
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
}

struct SavedMovieDTO: Content {
    let id: UUID
    let imdbID: String
    let title: String
    let year: String?
    let posterURL: String?
    let addedAt: Date?

    init(_ movie: SavedMovie) throws {
        self.id = try movie.requireID()
        self.imdbID = movie.imdbID
        self.title = movie.title
        self.year = movie.year
        self.posterURL = movie.posterURL
        self.addedAt = movie.addedAt
    }
}
