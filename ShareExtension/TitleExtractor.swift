import Foundation
import FoundationModels

// Structured output for guided generation: the model fills these in directly,
// so we never parse free-form text.

@Generable
struct ExtractedTitleList {
    @Guide(description: "Every distinct movie or TV show the post is actually about or recommending.")
    let movies: [ExtractedTitleGuess]
}

@Generable
struct ExtractedTitleGuess {
    @Guide(description: "The exact movie or TV show title only — no year, ranking, or extra words.")
    let title: String

    @Guide(description: "The 4-digit release year if the post states or clearly implies it, otherwise an empty string.")
    let year: String
}

/// Extracts movie/TV titles from shared post text using Apple's on-device
/// Foundation Models. Runs entirely on-device — no API key, no network, private.
struct TitleExtractor {
    enum Unavailable {
        case notEligible
        case notEnabled
        case notReady
        case other

        var message: String {
            switch self {
            case .notEligible:
                return "Finding movies in posts needs Apple Intelligence, which this device doesn't support."
            case .notEnabled:
                return "Turn on Apple Intelligence in Settings to find movies in shared posts."
            case .notReady:
                return "Apple Intelligence is still getting ready. Try again in a little while."
            case .other:
                return "Apple Intelligence isn't available right now. Try again later."
            }
        }
    }

    /// Returns nil when the on-device model is ready, or a reason to show the
    /// user when it isn't.
    static func availability() -> Unavailable? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .notEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .notReady
        case .unavailable:
            return .other
        }
    }

    func extractTitles(from text: String) async throws -> [TitleGuess] {
        let session = LanguageModelSession(instructions: Instructions("""
        You extract movie and TV show titles from social media content (post captions \
        and text recognized from screenshots). The text may be noisy — hashtags, emoji, \
        usernames, OCR artifacts, ranking numbers. Identify every distinct movie or TV \
        show the content is actually about or recommending. Include the release year only \
        when the text states or clearly implies it. Do not invent titles that aren't \
        referenced, and do not include actors, directors, or franchises mentioned only in \
        passing. If the text mentions no movies or shows, return an empty list.
        """))

        // Social posts are short; OCR can be noisy but bounded. Cap the input so
        // a huge shared document can't blow past the model's context window.
        let clipped = String(text.prefix(6000))
        let response = try await session.respond(
            to: "Post content:\n\(clipped)",
            generating: ExtractedTitleList.self
        )
        return response.content.movies
            .map { TitleGuess(title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                              year: $0.year.isEmpty ? nil : $0.year) }
            .filter { !$0.title.isEmpty }
    }
}
