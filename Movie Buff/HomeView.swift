import SwiftUI

enum Theme {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.03)
    static let surface = Color(red: 0.11, green: 0.10, blue: 0.10)
    static let gold = Color(red: 0.94, green: 0.72, blue: 0.10)
    static let goldSoft = Color(red: 0.78, green: 0.58, blue: 0.08)
    static let accent = gold

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.05, blue: 0.05),
            Color(red: 0.02, green: 0.02, blue: 0.02)
        ],
        startPoint: .top, endPoint: .bottom
    )
}

extension Font {
    /// Section-header title (e.g. "Popular Movies", "Saved", "Friends").
    static var sectionTitle: Font { .system(.title3, design: .default).weight(.black) }
    /// Small marquee-style all-caps label above headlines.
    static var marqueeLabel: Font { .caption2.weight(.heavy) }
}

struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var notifications = NotificationsStore()

    var body: some View {
        TabView {
            NavigationStack { BrowseView() }
                .tabItem { Label("Browse", systemImage: "film.circle") }
                .toolbarBackground(Theme.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            NavigationStack { ReelsView() }
                .tabItem { Label("Reels", systemImage: "play.house") }
                .toolbarBackground(Theme.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            NavigationStack { SavedView() }
                .tabItem { Label("Saved", systemImage: "bookmark.fill") }
                .toolbarBackground(Theme.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            NavigationStack { FriendsView() }
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .toolbarBackground(Theme.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .badge(notifications.unreadCount)
        }
        .tint(Theme.accent)
        .environment(notifications)
        .task {
            if !auth.isGuest { await notifications.refresh() }
        }
    }
}

struct BrowseView: View {
    @Environment(AuthStore.self) private var auth

    @State private var showingProfile = false
    @State private var browseMovies: [MovieSummary] = []
    @State private var searchResults: [MovieSummary] = []
    @State private var categories: [String] = []
    @State private var selectedCategory: String? = nil
    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = true
    @State private var searchQuery = ""

    @State private var isLoadingBrowse = false
    @State private var isLoadingMore = false
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let service = MovieService()
    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isSearchingMode: Bool { !trimmedQuery.isEmpty }
    private var displayedMovies: [MovieSummary] {
        isSearchingMode ? searchResults : browseMovies
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !isSearchingMode {
                        heroBanner
                        if !categories.isEmpty {
                            categoryFilter
                        }
                    }
                    sectionHeader
                    content
                    if isLoadingMore {
                        ProgressView().tint(Theme.accent).padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 32)
            }
            .refreshable { await reloadBrowse() }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchQuery, prompt: "Search movies")
        .task { await loadCategoriesIfNeeded() }
        .task(id: trimmedQuery) { await runSearch() }
        .task(id: selectedCategory) { await reloadBrowse() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("MovieBuffClear")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 100)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingProfile = true
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView().environment(auth)
        }
        .navigationDestination(for: MovieSummary.self) { movie in
            MovieDetailView(imdbID: movie.imdbID)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView().environment(auth)
        }
    }

    private var heroBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOW SHOWING")
                .font(.marqueeLabel)
                .foregroundStyle(Theme.gold)
                .tracking(4)
            Text("Discover your next favorite")
                .font(.system(.title2, design: .default).weight(.black))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var categoryFilter: some View {
        HStack(spacing: 0) {
            categoryMenu
                .padding(.leading, 16)
                .padding(.trailing, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(label: "All", isSelected: selectedCategory == nil) {
                        if selectedCategory != nil { selectedCategory = nil }
                    }
                    ForEach(categories, id: \.self) { category in
                        CategoryChip(label: category, isSelected: selectedCategory == category) {
                            if selectedCategory != category { selectedCategory = category }
                        }
                    }
                }
                .padding(.trailing, 16)
            }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                if selectedCategory != nil { selectedCategory = nil }
            } label: {
                if selectedCategory == nil {
                    Label("All", systemImage: "checkmark")
                } else {
                    Text("All")
                }
            }
            Divider()
            ForEach(categories, id: \.self) { category in
                Button {
                    if selectedCategory != category { selectedCategory = category }
                } label: {
                    if selectedCategory == category {
                        Label(category, systemImage: "checkmark")
                    } else {
                        Text(category)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .padding(8)
                .background(.white.opacity(0.08), in: Circle())
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text(sectionTitle)
                .font(.sectionTitle)
                .foregroundStyle(.white)
            if isSearching || (isLoadingBrowse && browseMovies.isEmpty) {
                ProgressView().tint(.white.opacity(0.6)).scaleEffect(0.8)
            }
            Spacer()
            if !displayedMovies.isEmpty {
                Text("\(displayedMovies.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal)
    }

    private var sectionTitle: String {
        if isSearchingMode { return "Results" }
        if let category = selectedCategory { return category }
        return "Movie Recs"
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            errorState(errorMessage)
        } else if displayedMovies.isEmpty {
            if isSearchingMode && !isSearching {
                emptyResults(message: "No movies found for \u{201C}\(trimmedQuery)\u{201D}")
            } else if !isSearchingMode && !isLoadingBrowse {
                emptyResults(message: "No movies to show in this category.")
            } else {
                loadingState
            }
        } else {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(displayedMovies) { movie in
                    NavigationLink(value: movie) {
                        MoviePosterCard(movie: movie)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if !isSearchingMode,
                           hasMore,
                           !isLoadingMore,
                           movie.id == browseMovies.last?.id {
                            await loadMoreBrowse()
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.accent)
            Text("Loading movies…")
                .foregroundStyle(.white.opacity(0.5))
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func emptyResults(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "list.and.film")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.3))
            Text(message)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
            Text(message)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func loadCategoriesIfNeeded() async {
        guard categories.isEmpty else { return }
        do {
            categories = try await service.categories()
        } catch {
            // Categories are optional — fall back to just "All".
        }
    }

    private func reloadBrowse() async {
        errorMessage = nil
        currentPage = 1
        hasMore = true
        isLoadingBrowse = true
        defer { isLoadingBrowse = false }
        do {
            let response = try await service.browse(category: selectedCategory, page: 1)
            guard !Task.isCancelled else { return }
            browseMovies = response.movies
            hasMore = !response.movies.isEmpty
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            browseMovies = []
        }
    }

    private func loadMoreBrowse() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let nextPage = currentPage + 1
        do {
            let response = try await service.browse(category: selectedCategory, page: nextPage)
            let newMovies = response.movies
            if newMovies.isEmpty {
                hasMore = false
            } else {
                let existingIDs = Set(browseMovies.map(\.id))
                let deduped = newMovies.filter { !existingIDs.contains($0.id) }
                browseMovies.append(contentsOf: deduped)
                currentPage = nextPage
                if deduped.isEmpty { hasMore = false }
            }
        } catch {
            // Silent — user can pull to refresh to retry.
        }
    }

    private func runSearch() async {
        let query = trimmedQuery
        errorMessage = nil
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await service.search(query: query)
            guard !Task.isCancelled else { return }
            searchResults = response.movies
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Theme.accent : Color.white.opacity(0.08))
                )
                .foregroundStyle(isSelected ? .black : .white)
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.clear : Color.white.opacity(0.15),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

struct SavedView: View {
    @Environment(AuthStore.self) private var auth
    @State private var movies: [SavedMovie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = MovieService()
    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                if auth.isGuest {
                    GuestSignInPrompt(
                        title: "Sign in to save movies",
                        message: "Your saved list stays with your account so it's there whenever you sign in."
                    )
                } else if isLoading && movies.isEmpty {
                    ProgressView().padding(.top, 100).tint(Theme.accent)
                } else if movies.isEmpty {
                    VStack(spacing: 14) {
                        Image("MovieBuffIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .opacity(0.85)
                        Text("Your list is empty")
                            .font(.sectionTitle)
                            .foregroundStyle(.white)
                        Text("Tap the bookmark on a movie to save it here.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(movies) { saved in
                            NavigationLink(value: saved.summary) {
                                MoviePosterCard(movie: saved.summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                if let error = errorMessage {
                    Text(error).foregroundStyle(.red).padding()
                }
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image("MovieBuffIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 22)
                    Text("Saved")
                        .font(.sectionTitle)
                        .foregroundStyle(.white)
                }
            }
        }
        .refreshable {
            if !auth.isGuest { await load() }
        }
        .navigationDestination(for: MovieSummary.self) { movie in
            MovieDetailView(imdbID: movie.imdbID)
        }
        .task {
            if !auth.isGuest { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            movies = try await service.savedMovies()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuestSignInPrompt: View {
    @Environment(AuthStore.self) private var auth
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.gold)
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                auth.exitGuestMode()
            } label: {
                Text("Sign In or Create Account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}

struct MoviePosterCard: View {
    let movie: MovieSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                case .failure:
                    ZStack {
                        Theme.surface
                        Image(systemName: "film")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.4))
                    }.aspectRatio(2/3, contentMode: .fill)
                case .empty:
                    ZStack {
                        Theme.surface
                        ProgressView().tint(.white.opacity(0.5))
                    }.aspectRatio(2/3, contentMode: .fill)
                @unknown default:
                    Theme.surface.aspectRatio(2/3, contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let year = movie.year, !year.isEmpty {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(Theme.gold.opacity(0.75))
                }
            }
        }
    }
}
