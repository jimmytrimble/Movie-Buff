import SwiftUI

struct MovieDetailView: View {
    let imdbID: String

    enum SourcesState {
        case loading
        case loaded([StreamingSource])
        case failed
    }

    @State private var detail: MovieDetail?
    @State private var sourcesState: SourcesState = .loading
    @State private var isLoading = true
    @State private var isSaved = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    @State private var showingReviews = false

    private let service = MovieService()

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                if let detail {
                    content(for: detail)
                } else if isLoading {
                    ProgressView().padding(.top, 100).tint(Theme.accent)
                } else if let error = errorMessage {
                    Text(error).foregroundStyle(.red).padding()
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if detail != nil {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingReviews = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showingReviews) {
            if let detail {
                CommentsView(imdbID: detail.imdbID, movieTitle: detail.title)
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let detail {
                ShareMovieSheet(
                    movieID: detail.imdbID,
                    title: detail.title,
                    year: detail.year,
                    posterURL: detail.poster.flatMap { $0 == "N/A" ? nil : $0 }
                )
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(for detail: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AsyncImage(url: detail.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    Color.gray.opacity(0.3).aspectRatio(2/3, contentMode: .fit)
                }
            }
            .frame(maxWidth: 260)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 12)
            .frame(maxWidth: .infinity)

            Text(detail.title)
                .font(.title.bold())
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                if let rating = detail.imdbRating, rating != "N/A" {
                    Label(rating, systemImage: "star.fill").foregroundStyle(.yellow)
                }
                if let year = detail.year, !year.isEmpty {
                    Text(year).foregroundStyle(.white.opacity(0.7))
                }
                if let runtime = detail.runtime, runtime != "N/A" {
                    Text(runtime).foregroundStyle(.white.opacity(0.7))
                }
            }
            .font(.subheadline)

            Button {
                Task { await toggleSave() }
            } label: {
                HStack {
                    if isMutating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    }
                    Text(isSaved ? "Saved" : "Add to Saved List")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSaved ? Color.gray.opacity(0.3) : Theme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isMutating)

            streamingSection

            if let genre = detail.genre, genre != "N/A" {
                InfoRow(label: "Genre", value: genre)
            }
            if let director = detail.director, director != "N/A" {
                InfoRow(label: "Director", value: director)
            }
            if let actors = detail.actors, actors != "N/A" {
                InfoRow(label: "Cast", value: actors)
            }
            if let plot = detail.plot, plot != "N/A" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Plot").font(.headline).foregroundStyle(.white.opacity(0.8))
                    Text(plot).foregroundStyle(.white)
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var streamingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Where to Watch")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            switch sourcesState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().tint(.white.opacity(0.6)).scaleEffect(0.8)
                    Text("Looking for streaming options\u{2026}")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.vertical, 4)

            case .loaded(let sources) where sources.isEmpty:
                emptySourcesState

            case .loaded(let sources):
                let groups = groupedSources(from: sources)
                ForEach(groups, id: \.type) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.type)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(1)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(section.sources) { source in
                                    SourcePill(source: source)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

            case .failed:
                emptySourcesState
            }
        }
        .padding(.vertical, 4)
    }

    private var emptySourcesState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tv.slash")
                .foregroundStyle(.white.opacity(0.4))
            Text("Not currently available on streaming.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    private struct SourceGroup {
        let type: String
        let sources: [StreamingSource]
    }

    private func groupedSources(from sources: [StreamingSource]) -> [SourceGroup] {
        var seen = Set<String>()
        let deduped = sources.filter { source in
            let key = "\(source.name.lowercased())|\(source.type.lowercased())"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        let sorted = deduped.sorted { $0.typeSortRank < $1.typeSortRank }
        let grouping = Dictionary(grouping: sorted, by: { $0.displayType })
        let orderedTypes = ["Stream", "Free", "TV", "Rent", "Buy"]
        var result: [SourceGroup] = []
        for type in orderedTypes {
            if let items = grouping[type], !items.isEmpty {
                result.append(SourceGroup(type: type, sources: items))
            }
        }
        for (type, items) in grouping where !orderedTypes.contains(type) {
            result.append(SourceGroup(type: type, sources: items))
        }
        return result
    }

    private func load() async {
        isLoading = true
        sourcesState = .loading
        defer { isLoading = false }
        do {
            async let detailTask = service.detail(imdbID: imdbID)
            async let savedTask = service.savedMovies()
            let (loaded, saved) = try await (detailTask, savedTask)
            detail = loaded
            isSaved = saved.contains { $0.imdbID == imdbID }
            sourcesState = .loaded(loaded.streaming ?? [])
        } catch {
            errorMessage = error.localizedDescription
            sourcesState = .failed
        }
    }

    private func toggleSave() async {
        guard let detail else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            if isSaved {
                try await service.unsave(imdbID: detail.imdbID)
                isSaved = false
            } else {
                let request = SaveMovieRequest(
                    imdbID: detail.imdbID,
                    title: detail.title,
                    year: detail.year,
                    posterURL: detail.poster == "N/A" ? nil : detail.poster
                )
                try await service.save(request)
                isSaved = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SourcePill: View {
    let source: StreamingSource
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = source.bestURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let format = source.format, !format.isEmpty {
                        Text(format.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    if let price = source.price, price > 0 {
                        Text(String(format: "$%.2f", price))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 100, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(source.bestURL == nil)
        .opacity(source.bestURL == nil ? 0.5 : 1)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(value).foregroundStyle(.white)
        }
    }
}
