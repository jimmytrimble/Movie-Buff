import SwiftUI
#if os(iOS)
import WebKit
#endif

struct MovieDetailView: View {
    let imdbID: String

    enum SourcesState {
        case loading
        case loaded([StreamingSource])
        case failed
    }

    @Environment(AuthStore.self) private var auth

    @State private var detail: MovieDetail?
    @State private var sourcesState: SourcesState = .loading
    @State private var isLoading = true
    @State private var isSaved = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    @State private var showingReviews = false
    @State private var showingGuestPrompt = false
    @State private var showingPaywall = false
    @State private var showingTrailer = false

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
                        if premiumGate() { showingReviews = true }
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        if premiumGate() { showingShareSheet = true }
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
        .alert("Sign in required", isPresented: $showingGuestPrompt) {
            Button("Sign In") { auth.exitGuestMode() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Create a free account to unlock premium features.")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(reason: "Unlock the full Movie Buff experience.")
        }
        #if os(iOS)
        .sheet(isPresented: $showingTrailer) {
            if let detail {
                if let key = detail.trailerYouTubeKey, !key.isEmpty {
                    TrailerPlayerSheet(source: .youTubeKey(key))
                } else {
                    let query = "\(detail.title) \(detail.year ?? "") trailer"
                    TrailerPlayerSheet(source: .search(query: query))
                }
            }
        }
        #endif
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
                if auth.isGuest {
                    showingGuestPrompt = true
                } else if !auth.isPremium {
                    showingPaywall = true
                } else {
                    Task { await toggleSave() }
                }
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

            trailerButton(for: detail)

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
    private func trailerButton(for detail: MovieDetail) -> some View {
        Button {
            showingTrailer = true
        } label: {
            HStack {
                Image(systemName: "play.circle.fill")
                Text("View Trailer")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.gold)
            .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.gold.opacity(0.6), lineWidth: 1)
            )
        }
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
            let loaded = try await service.detail(imdbID: imdbID)
            detail = loaded
            sourcesState = .loaded(loaded.streaming ?? [])
        } catch {
            errorMessage = error.localizedDescription
            sourcesState = .failed
        }
        // Saved-list check is premium-only; only ask the server when it'd succeed.
        if auth.isPremium, let saved = try? await service.savedMovies() {
            isSaved = saved.contains { $0.imdbID == imdbID }
        }
    }

    /// Routes non-premium users to the right upsell. Returns true if the caller
    /// can proceed with the premium action.
    private func premiumGate() -> Bool {
        if auth.isGuest {
            showingGuestPrompt = true
            return false
        }
        if !auth.isPremium {
            showingPaywall = true
            return false
        }
        return true
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
#if os(iOS)
enum TrailerSource {
    case youTubeKey(String)
    case search(query: String)
}

private struct TrailerPlayerSheet: View {
    let source: TrailerSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrailerWebView(source: source)
                .ignoresSafeArea(edges: .bottom)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .accessibilityLabel("Close")
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Trailer")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

/// Renders a YouTube trailer inline. For a known video key we use the IFrame Player API
/// (autoplay with sound). When we only have a search query, we load YouTube's mobile
/// results page so the user can tap a result — still fully in-app.
private struct TrailerWebView: UIViewRepresentable {
    let source: TrailerSource

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // Some YouTube surfaces refuse to render unless the User-Agent looks like Safari.
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        switch source {
        case .youTubeKey(let key):
            webView.scrollView.isScrollEnabled = false
            webView.loadHTMLString(embedHTML(videoID: key),
                                   baseURL: URL(string: "https://www.youtube-nocookie.com"))
        case .search(let query):
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://m.youtube.com/results?search_query=\(escaped)") {
                webView.load(URLRequest(url: url))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func embedHTML(videoID: String) -> String {
        // IFrame Player API — autoplay is user-initiated (they tapped View Trailer),
        // so we start with sound on.
        """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
              .wrap { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
                      width: 100vw; height: 100vh; }
              #player { width: 100%; height: 100%; border: 0; }
            </style>
          </head>
          <body>
            <div class="wrap"><div id="player"></div></div>
            <script src="https://www.youtube.com/iframe_api"></script>
            <script>
              function onYouTubeIframeAPIReady() {
                window.mbPlayer = new YT.Player('player', {
                  height: '100%',
                  width: '100%',
                  videoId: '\(videoID)',
                  host: 'https://www.youtube-nocookie.com',
                  playerVars: {
                    autoplay: 1, playsinline: 1, controls: 1,
                    modestbranding: 1, rel: 0, enablejsapi: 1
                  }
                });
              }
            </script>
          </body>
        </html>
        """
    }
}
#endif

