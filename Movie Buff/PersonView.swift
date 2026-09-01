import SwiftUI

struct PersonView: View {
    let person: PersonSummary

    @State private var credits: [PersonMovieCredit] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = PeopleService()
    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if isLoading && credits.isEmpty {
                        ProgressView().tint(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.horizontal)
                    } else if credits.isEmpty {
                        Text("No films found.")
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.footnote)
                            .padding(.horizontal)
                    } else {
                        Text("Filmography")
                            .font(.sectionTitle)
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(credits) { credit in
                                NavigationLink(value: credit.summary) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        MoviePosterCard(movie: credit.summary)
                                        if let role = credit.character ?? credit.job, !role.isEmpty {
                                            Text(role)
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.55))
                                                .lineLimit(1)
                                                .padding(.horizontal, 2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(person.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: MovieSummary.self) { movie in
            MovieDetailView(imdbID: movie.imdbID)
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            AsyncImage(url: person.profileImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Theme.surface
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.gold.opacity(0.4), lineWidth: 1))
            .shadow(color: Theme.gold.opacity(0.2), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(person.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                if let knownFor = person.knownFor, !knownFor.isEmpty {
                    Text(knownFor)
                        .font(.footnote)
                        .foregroundStyle(Theme.gold.opacity(0.85))
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            credits = try await service.filmography(tmdbID: person.tmdbID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Compact row used in the "People" segment of search results.
struct PersonRow: View {
    let person: PersonSummary

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: person.profileImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Theme.surface
                        Image(systemName: "person.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if let knownFor = person.knownFor, !knownFor.isEmpty {
                    Text(knownFor)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        )
    }
}
