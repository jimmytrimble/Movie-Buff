import Foundation

enum BrowseCategories {
    static let all: [String] = [
        "Action",
        "Comedy",
        "Thriller",
        "Horror",
        "Drama",
        "Romance",
        "Sci-Fi",
        "Fantasy",
        "Animation",
        "Documentary",
        "Adventure",
        "Mystery",
    ]

    static func searchTerm(for category: String?) -> String {
        guard let raw = category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return "movie"
        }

        switch raw.lowercased() {
        case "action":      return "action"
        case "comedy":      return "comedy"
        case "thriller":    return "thriller"
        case "horror":      return "horror"
        case "drama":       return "drama"
        case "romance":     return "love"
        case "sci-fi",
             "scifi",
             "science fiction":
                            return "space"
        case "fantasy":     return "fantasy"
        case "animation":   return "animation"
        case "documentary": return "documentary"
        case "adventure":   return "adventure"
        case "mystery":     return "mystery"
        default:            return raw
        }
    }
}
