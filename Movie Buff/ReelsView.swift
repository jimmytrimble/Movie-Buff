import SwiftUI
#if os(iOS)
import WebKit
#endif

struct ReelsView: View {
    @State private var reels: [ReelEntry] = []
    @State private var page: Int = 1
    @State private var hasMore: Bool = true
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?
    @State private var activeID: String?
    @State private var isMuted: Bool = true

    private let service = ReelsService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if reels.isEmpty {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let errorMessage {
                    errorState(errorMessage)
                } else {
                    emptyState
                }
            } else {
                pager
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationBarHidden(true)
        .task {
            if reels.isEmpty { await loadFirstPage() }
        }
    }

    private var pager: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(reels) { reel in
                    TrailerCard(
                        reel: reel,
                        isActive: activeID == reel.imdbID,
                        isMuted: isMuted,
                        onToggleMute: { isMuted.toggle() }
                    )
                    .containerRelativeFrame(.vertical)
                    .id(reel.imdbID)
                    .task {
                        if reel.imdbID == reels.last?.imdbID, hasMore, !isLoadingMore {
                            await loadMore()
                        }
                    }
                }
                if isLoadingMore {
                    ProgressView().tint(.white).padding(24)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $activeID)
        .background(Color.black)
        .onAppear {
            if activeID == nil { activeID = reels.first?.imdbID }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("MovieBuffIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .opacity(0.85)
            Text("No trailers right now")
                .font(.sectionTitle)
                .foregroundStyle(.white)
            Button("Try again") {
                Task { await loadFirstPage() }
            }
            .foregroundStyle(Theme.accent)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            Text(message)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await loadFirstPage() }
            }
            .foregroundStyle(Theme.accent)
        }
    }

    private func loadFirstPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fresh = try await service.feed(page: 1)
            reels = fresh.filter { $0.youtubeID != nil }
            page = 1
            hasMore = !fresh.isEmpty
            activeID = reels.first?.imdbID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await service.feed(page: page + 1)
            let filtered = next.filter { $0.youtubeID != nil }
            let existing = Set(reels.map(\.imdbID))
            let deduped = filtered.filter { !existing.contains($0.imdbID) }
            reels.append(contentsOf: deduped)
            page += 1
            if deduped.isEmpty { hasMore = false }
        } catch {
            hasMore = false
        }
    }
}

// MARK: - Trailer card

private struct TrailerCard: View {
    let reel: ReelEntry
    let isActive: Bool
    let isMuted: Bool
    let onToggleMute: () -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var showOverlay = true
    @State private var isSaved = false
    @State private var isSaving = false
    @State private var navToDetail = false
    @State private var playbackFailed = false
    @State private var showingComments = false

    private let movieService = MovieService()

    var body: some View {
        ZStack {
            Color.black
            #if os(iOS)
            if let id = reel.youtubeID, !playbackFailed {
                YouTubePlayerView(
                    videoID: id,
                    isActive: isActive,
                    isMuted: isMuted,
                    onError: { playbackFailed = true }
                )
                .allowsHitTesting(false)
            } else {
                thumbnailFallback
                if playbackFailed {
                    playbackFailedOverlay
                }
            }
            #else
            thumbnailFallback
            #endif

            // Full-card tap catcher (double-tap logic below)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showOverlay.toggle()
                    }
                }

            if showOverlay { overlay }
        }
        .clipped()
        .task { await checkSaved() }
        .navigationDestination(isPresented: $navToDetail) {
            MovieDetailView(imdbID: reel.imdbID)
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(imdbID: reel.imdbID, movieTitle: reel.title)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }

    private var thumbnailFallback: some View {
        AsyncImage(url: reel.thumbnailURL) { phase in
            switch phase {
            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
            default: Color.black
            }
        }
        .overlay(Color.black.opacity(0.35))
    }

    private var playbackFailedOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text("Trailer can't play here")
                .font(.headline)
                .foregroundStyle(.white)
            Text("The uploader has embed disabled for this video.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let url = URL(string: reel.trailer) {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Watch on YouTube")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var overlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reel.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
                    HStack(spacing: 8) {
                        if let year = reel.year, !year.isEmpty {
                            Text(year)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        ForEach(reel.genres.prefix(2), id: \.self) { g in
                            Text(g)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.15), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Button {
                        navToDetail = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("See details")
                            Image(systemName: "chevron.right")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                VStack(spacing: 18) {
                    actionButton(
                        icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        tint: .white,
                        loading: false,
                        action: onToggleMute
                    )
                    actionButton(
                        icon: "bubble.left.and.bubble.right.fill",
                        tint: .white,
                        loading: false
                    ) {
                        showingComments = true
                    }
                    actionButton(
                        icon: isSaved ? "bookmark.fill" : "bookmark",
                        tint: isSaved ? Theme.accent : .white,
                        loading: isSaving
                    ) {
                        Task { await toggleSave() }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 90) // clear the tab bar
        }
        .background(
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .allowsHitTesting(true)
        .transition(.opacity)
    }

    private func actionButton(icon: String, tint: Color, loading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.35))
                    .frame(width: 48, height: 48)
                if loading {
                    ProgressView().tint(tint)
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    private func checkSaved() async {
        do {
            let saved = try await movieService.savedMovies()
            isSaved = saved.contains { $0.imdbID == reel.imdbID }
        } catch {
            // silent
        }
    }

    private func toggleSave() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if isSaved {
                try await movieService.unsave(imdbID: reel.imdbID)
                isSaved = false
            } else {
                let request = SaveMovieRequest(
                    imdbID: reel.imdbID,
                    title: reel.title,
                    year: reel.year,
                    posterURL: (reel.poster == "N/A" || reel.poster == nil) ? nil : reel.poster
                )
                try await movieService.save(request)
                isSaved = true
            }
        } catch {
            // silent — the button will just stay in its previous state
        }
    }
}

// MARK: - YouTube player (WKWebView bridge)

#if os(iOS)
private struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let isActive: Bool
    let isMuted: Bool
    let onError: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "playerEvent")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // Some embeds refuse to play unless the User-Agent looks like a real Safari.
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        // Serve the embed under the youtube-nocookie.com origin — designed for iframe embedding.
        webView.loadHTMLString(embedHTML(videoID: videoID), baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let playPause = isActive
            ? "if (window.mbPlayer && window.mbPlayer.playVideo) window.mbPlayer.playVideo();"
            : "if (window.mbPlayer && window.mbPlayer.pauseVideo) window.mbPlayer.pauseVideo();"
        let audio = isMuted
            ? "if (window.mbPlayer && window.mbPlayer.mute) window.mbPlayer.mute();"
            : "if (window.mbPlayer && window.mbPlayer.unMute) window.mbPlayer.unMute();"
        webView.evaluateJavaScript(playPause + audio, completionHandler: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playerEvent")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onError: () -> Void
        private var hasReportedError = false
        init(onError: @escaping () -> Void) { self.onError = onError }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "playerEvent" else { return }
            // Body is a dict from JS. Any "error" key means the player failed.
            if let dict = message.body as? [String: Any], dict["event"] as? String == "onError" {
                if !hasReportedError {
                    hasReportedError = true
                    Task { @MainActor in self.onError() }
                }
            }
        }
    }

    private func embedHTML(videoID: String) -> String {
        // Uses youtube-nocookie.com + IFrame Player API so we can catch onError from the player.
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
                    autoplay: 1, mute: 1, playsinline: 1, controls: 0,
                    modestbranding: 1, rel: 0, loop: 1, playlist: '\(videoID)',
                    enablejsapi: 1
                  },
                  events: {
                    onError: function(e) {
                      try {
                        window.webkit.messageHandlers.playerEvent.postMessage({event: 'onError', code: e.data});
                      } catch (err) {}
                    }
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
