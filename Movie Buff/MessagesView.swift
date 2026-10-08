import SwiftUI

/// Polling-based store for the conversation list + unread badge. Messaging is a
/// premium feature; calls are premium-gated server-side.
@Observable
@MainActor
final class MessagesStore {
    var conversations: [ConversationDTO] = []
    var unreadCount = 0

    private let service = MessageService()

    func refresh() async {
        async let convosTask: [ConversationDTO]? = { try? await service.conversations() }()
        async let countTask: Int? = { try? await service.unreadCount() }()
        let (convos, count) = await (convosTask, countTask)
        if let convos { conversations = convos }
        if let count { unreadCount = count }
    }

    func refreshUnread() async {
        if let count = try? await service.unreadCount() { unreadCount = count }
    }
}

// MARK: - Conversation list

struct MessagesView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var store = MessagesStore()
    @State private var showingNew = false

    private let friendService = FriendService()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if !auth.isPremium {
                    ScrollView {
                        PremiumUpsell(
                            title: auth.isGuest ? "Sign in to message friends" : "Premium unlocks Messages",
                            message: "Chat with friends and send each other movies you love."
                        )
                    }
                } else if store.conversations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.conversations) { convo in
                                NavigationLink(value: convo.user) {
                                    ConversationRow(conversation: convo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Messages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
                if auth.isPremium {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingNew = true } label: {
                            Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .navigationDestination(for: UserDTO.self) { user in
                ChatView(otherUser: user)
            }
            .sheet(isPresented: $showingNew) {
                NewMessageSheet { user in
                    showingNew = false
                }
            }
            .task { if auth.isPremium { await store.refresh() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56)).foregroundStyle(.white.opacity(0.3))
            Text("No messages yet").font(.sectionTitle).foregroundStyle(.white)
            Text("Start a conversation with a friend.")
                .font(.footnote).foregroundStyle(.white.opacity(0.5))
            Button { showingNew = true } label: {
                Label("New message", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }
}

private struct ConversationRow: View {
    let conversation: ConversationDTO

    private var preview: String {
        if let body = conversation.lastMessage.body, !body.isEmpty { return body }
        if let movie = conversation.lastMessage.movie { return "🎬 \(movie.title)" }
        return "Sent a movie"
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(imageData: conversation.user.avatarImageData,
                          label: conversation.user.displayLabel, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.user.displayLabel)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(preview)
                    .font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.caption2.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Pick a friend to start/continue a conversation with.
private struct NewMessageSheet: View {
    let onPick: (UserDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var friends: [FriendDTO] = []
    @State private var navUser: UserDTO?
    private let service = FriendService()

    private var accepted: [FriendDTO] { friends.filter { $0.status == .accepted } }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                if accepted.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.slash").font(.system(size: 44)).foregroundStyle(.white.opacity(0.3))
                        Text("Add friends to start messaging.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 100)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(accepted) { friend in
                                NavigationLink(value: friend.user) {
                                    HStack(spacing: 12) {
                                        ProfileAvatar(imageData: friend.user.avatarImageData,
                                                      label: friend.displayLabel, size: 40)
                                        Text(friend.displayLabel).foregroundStyle(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote).foregroundStyle(.white.opacity(0.3))
                                    }
                                    .padding(12)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("New Message")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
            }
            .navigationDestination(item: $navUser) { user in
                ChatView(otherUser: user)
            }
            .task { friends = (try? await service.list()) ?? [] }
        }
    }
}

// MARK: - Chat thread

struct ChatView: View {
    let otherUser: UserDTO

    @State private var messages: [MessageDTO] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showingMoviePicker = false

    private let service = MessageService()

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await load() }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                inputBar
            }
        }
        .navigationTitle(otherUser.displayLabel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    PublicProfileView(userID: otherUser.id, preloadedName: otherUser.displayLabel)
                } label: {
                    Image(systemName: "person.crop.circle").foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingMoviePicker) {
            MoviePickerSheet { movie in
                showingMoviePicker = false
                Task { await send(body: nil, movie: movie) }
            }
        }
        .task { await load() }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { showingMoviePicker = true } label: {
                Image(systemName: "film").font(.title3).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(isSending)

            TextField("", text: $draft,
                      prompt: Text("Message").foregroundColor(.gray), axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.white)

            Button {
                let text = draft
                draft = ""
                Task { await send(body: text, movie: nil) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(canSend ? Theme.accent : .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
        }
        .padding(12)
        .background(Theme.background)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() async {
        do {
            messages = try await service.thread(userID: otherUser.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send(body: String?, movie: MessageMovieDTO?) async {
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed?.isEmpty == false) || movie != nil else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await service.send(userID: otherUser.id, body: trimmed, movie: movie)
            messages.append(message)
        } catch {
            errorMessage = error.localizedDescription
            if let trimmed, movie == nil { draft = trimmed }  // restore on failure
        }
    }
}

private struct MessageBubble: View {
    let message: MessageDTO

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let movie = message.movie {
                    NavigationLink(value: MovieSummary(title: movie.title, year: movie.year,
                                                       imdbID: movie.imdbID, type: nil,
                                                       poster: movie.posterURL)) {
                        movieCard(movie)
                    }
                    .buttonStyle(.plain)
                }
                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(message.isMine ? .black : .white)
                }
            }
            .padding(10)
            .background(
                message.isMine ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: 14)
            )
            if !message.isMine { Spacer(minLength: 40) }
        }
    }

    private func movieCard(_ movie: MessageMovieDTO) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: movie.posterAsURL) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(2/3, contentMode: .fill)
                default: ZStack { Color.black.opacity(0.2); Image(systemName: "film").foregroundStyle(.white.opacity(0.4)) }
                }
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.isMine ? .black : .white)
                    .lineLimit(2)
                if let year = movie.year, year != "N/A" {
                    Text(year).font(.caption2).foregroundStyle(message.isMine ? .black.opacity(0.7) : .white.opacity(0.6))
                }
            }
            .frame(maxWidth: 160, alignment: .leading)
        }
    }
}

/// Lightweight movie search used to attach a movie to a message.
private struct MoviePickerSheet: View {
    let onPick: (MessageMovieDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MovieSummary] = []
    @State private var isSearching = false

    private let service = MovieService()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { movie in
                            Button {
                                onPick(MessageMovieDTO(
                                    imdbID: movie.imdbID,
                                    title: movie.title,
                                    year: movie.year,
                                    posterURL: movie.poster
                                ))
                            } label: {
                                HStack(spacing: 12) {
                                    ProfilePoster(posterURL: movie.posterURL, title: movie.title)
                                        .frame(width: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(movie.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        if let year = movie.year {
                                            Text(year).font(.caption).foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Send a Movie")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
            }
            .searchable(text: $query, prompt: "Search movies & shows")
            .task(id: query) { await runSearch() }
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { results = []; return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        if let response = try? await service.search(query: trimmed) {
            results = response.movies
        }
    }
}
