import SwiftUI

@Observable
@MainActor
final class NotificationsStore {
    var shares: [SharedMovieDTO] = []
    var friends: [FriendDTO] = []
    var watchParties: [WatchPartyDTO] = []
    var isLoadingShares = false
    private var storedUnreadCount: Int?
    private let partyService = WatchPartyService()

    func refreshWatchParties() async {
        if let loaded = try? await partyService.listPending() { watchParties = loaded }
    }

    var unreadCount: Int {
        storedUnreadCount ?? shares.filter { !$0.isRead }.count
    }
    var acceptedFriends: [FriendDTO] { friends.filter { $0.status == .accepted } }

    private let service = FriendService()

    /// Lightweight: fetches friends list + unread badge count + open watch parties.
    /// Full inbox is only pulled when the user opens the shares sheet.
    func refresh() async {
        async let friendsTask: [FriendDTO]? = { try? await service.list() }()
        async let countTask: Int? = { try? await service.unreadCount() }()
        async let partiesTask: [WatchPartyDTO]? = { try? await partyService.listPending() }()
        let (loadedFriends, count, loadedParties) = await (friendsTask, countTask, partiesTask)
        if let loadedFriends { friends = loadedFriends }
        if let count { storedUnreadCount = count }
        if let loadedParties { watchParties = loadedParties }
    }

    func refreshShares() async {
        isLoadingShares = true
        defer { isLoadingShares = false }
        if let loaded = try? await service.inbox() {
            shares = loaded
            storedUnreadCount = nil  // now derived from shares
        }
    }

    func refreshFriends() async {
        if let loaded = try? await service.list() { friends = loaded }
    }

    func refreshUnreadCount() async {
        if let count = try? await service.unreadCount() {
            storedUnreadCount = count
        }
    }

    func markRead(_ shareID: UUID) async {
        try? await service.markShareRead(shareID: shareID)
        if let idx = shares.firstIndex(where: { $0.id == shareID }) {
            let old = shares[idx]
            guard !old.isRead else { return }
            shares[idx] = SharedMovieDTO(
                id: old.id,
                fromUser: old.fromUser,
                imdbID: old.imdbID,
                title: old.title,
                year: old.year,
                posterURL: old.posterURL,
                message: old.message,
                isRead: true
            )
        }
        if let stored = storedUnreadCount {
            storedUnreadCount = max(0, stored - 1)
        }
    }
}

struct FriendsView: View {
    @Environment(NotificationsStore.self) private var notifications
    @Environment(AuthStore.self) private var auth
    #if os(iOS)
    @Environment(PushCoordinator.self) private var push
    #endif

    @State private var searchQuery = ""
    @State private var searchResults: [UserDTO] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var showingInbox = false
    @State private var activeParty: WatchPartyDTO?

    private let service = FriendService()

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var incoming: [FriendDTO] {
        notifications.friends.filter { $0.status == .pending && $0.direction == .incoming }
    }
    private var accepted: [FriendDTO] {
        notifications.friends.filter { $0.status == .accepted }
    }
    private var outgoing: [FriendDTO] {
        notifications.friends.filter { $0.status == .pending && $0.direction == .outgoing }
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if !auth.isPremium {
                ScrollView {
                    PremiumUpsell(
                        title: auth.isGuest ? "Sign in to add friends" : "Premium unlocks Friends",
                        message: "Share movies, get recommendations, and start watch parties with friends."
                    )
                }
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if os(iOS)
                    notificationPermissionBanner
                    #endif

                    searchSection

                    if let infoMessage {
                        banner(text: infoMessage, color: .green)
                    }
                    if let errorMessage {
                        banner(text: errorMessage, color: .red)
                    }

                    if !notifications.watchParties.isEmpty, let uid = auth.user?.id {
                        section(title: "Watch Parties", count: notifications.watchParties.count) {
                            VStack(spacing: 10) {
                                ForEach(notifications.watchParties) { party in
                                    WatchPartyInviteRow(
                                        party: party,
                                        currentUserID: uid,
                                        onOpen: { activeParty = $0 }
                                    )
                                }
                            }
                        }
                    }

                    if !incoming.isEmpty {
                        section(title: "Requests", count: incoming.count) {
                            VStack(spacing: 10) {
                                ForEach(incoming) { friend in
                                    IncomingRequestRow(
                                        friend: friend,
                                        onAccept: { await accept(friend) },
                                        onDecline: { await removeOrDecline(friend) }
                                    )
                                }
                            }
                        }
                    }

                    if !accepted.isEmpty {
                        section(title: "Friends", count: accepted.count) {
                            VStack(spacing: 10) {
                                ForEach(accepted) { friend in
                                    NavigationLink(value: friend) {
                                        FriendRow(friend: friend)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !outgoing.isEmpty {
                        section(title: "Sent", count: outgoing.count) {
                            VStack(spacing: 10) {
                                ForEach(outgoing) { friend in
                                    SentRequestRow(
                                        friend: friend,
                                        onCancel: { await removeOrDecline(friend) }
                                    )
                                }
                            }
                        }
                    }

                    if notifications.friends.isEmpty {
                        emptyState
                    }
                }
                .padding()
            }
            .refreshable { await notifications.refresh() }
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
                    Text("Friends")
                        .font(.sectionTitle)
                        .foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingInbox = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                        if notifications.unreadCount > 0 {
                            Text("\(notifications.unreadCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingInbox) {
            SharesInboxView()
                .environment(notifications)
        }
        .navigationDestination(for: FriendDTO.self) { friend in
            FriendMoviesView(friend: friend)
        }
        .navigationDestination(item: $activeParty) { party in
            if let uid = auth.user?.id {
                WatchPartySwipeView(party: party, currentUserID: uid)
            }
        }
        .task {
            if auth.isPremium { await notifications.refresh() }
        }
        .task(id: trimmedQuery) {
            if auth.isPremium { await runSearch() }
        }
        #if os(iOS)
        .task { await push.refreshAuthorizationStatus() }
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var notificationPermissionBanner: some View {
        switch push.authorizationStatus {
        case .notDetermined:
            permissionBanner(
                title: "Get notified when friends share",
                subtitle: "Enable push notifications to see new shares right away.",
                actionLabel: "Enable",
                action: { Task { await push.requestPermission() } }
            )
        case .denied:
            permissionBanner(
                title: "Notifications are off",
                subtitle: "Turn on notifications in Settings to be alerted when a friend shares a movie.",
                actionLabel: "Open Settings",
                action: { push.openSystemSettings() }
            )
        default:
            EmptyView()
        }
    }

    private func permissionBanner(
        title: String,
        subtitle: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button(actionLabel, action: action)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accent, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }
    #endif

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find Friends")
                .font(.sectionTitle)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("", text: $searchQuery,
                          prompt: Text("Search by name or email").foregroundColor(.gray))
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                if isSearching {
                    ProgressView().tint(.white.opacity(0.6)).scaleEffect(0.7)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            if trimmedQuery.count == 1 {
                Text("Type at least 2 characters to search.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 4)
            } else if !trimmedQuery.isEmpty && searchResults.isEmpty && !isSearching {
                Text("No users found.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 4)
            }

            if !searchResults.isEmpty {
                VStack(spacing: 8) {
                    ForEach(searchResults) { user in
                        UserSearchRow(user: user) {
                            await addFriend(user)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("MovieBuffIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .opacity(0.85)
            Text("No friends yet")
                .font(.sectionTitle)
                .foregroundStyle(.white)
            Text("Send a request by email to get started.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(.white)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())
                Spacer()
            }
            content()
        }
    }

    private func banner(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func runSearch() async {
        let query = trimmedQuery
        errorMessage = nil
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await service.searchUsers(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addFriend(_ user: UserDTO) async {
        errorMessage = nil
        infoMessage = nil
        do {
            _ = try await service.sendRequest(email: user.email)
            infoMessage = "Request sent to \(user.displayName ?? user.email)."
            searchResults.removeAll { $0.id == user.id }
            await notifications.refreshFriends()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accept(_ friend: FriendDTO) async {
        errorMessage = nil
        do {
            _ = try await service.accept(friendshipID: friend.friendshipID)
            await notifications.refreshFriends()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeOrDecline(_ friend: FriendDTO) async {
        errorMessage = nil
        do {
            try await service.removeOrDecline(friendshipID: friend.friendshipID)
            await notifications.refreshFriends()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UserSearchRow: View {
    let user: UserDTO
    let onAdd: () async -> Void
    @State private var isAdding = false

    private var displayLabel: String {
        if let name = user.displayName, !name.isEmpty { return name }
        return user.email
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(label: displayLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if let name = user.displayName, !name.isEmpty, name != user.email {
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            Button {
                Task {
                    isAdding = true
                    await onAdd()
                    isAdding = false
                }
            } label: {
                if isAdding {
                    ProgressView().tint(.black)
                        .frame(width: 44, height: 20)
                } else {
                    Label("Add", systemImage: "person.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            .background(Theme.accent, in: Capsule())
            .buttonStyle(.plain)
            .disabled(isAdding)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct IncomingRequestRow: View {
    let friend: FriendDTO
    let onAccept: () async -> Void
    let onDecline: () async -> Void

    @State private var isBusy = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(label: friend.displayLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(friend.user.email).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if isBusy {
                ProgressView().tint(.white.opacity(0.6))
            } else {
                Button {
                    Task { isBusy = true; await onDecline(); isBusy = false }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(8)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    Task { isBusy = true; await onAccept(); isBusy = false }
                } label: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.black)
                        .padding(8)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FriendRow: View {
    let friend: FriendDTO

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(label: friend.displayLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(friend.user.email).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SentRequestRow: View {
    let friend: FriendDTO
    let onCancel: () async -> Void

    @State private var isBusy = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(label: friend.displayLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("Pending").font(.caption).foregroundStyle(.yellow.opacity(0.8))
            }
            Spacer()
            if isBusy {
                ProgressView().tint(.white.opacity(0.6))
            } else {
                Button {
                    Task { isBusy = true; await onCancel(); isBusy = false }
                } label: {
                    Text("Cancel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AvatarView: View {
    let label: String

    private var initials: String {
        let words = label.split(separator: " ")
        if let first = words.first, let firstChar = first.first {
            if words.count > 1, let secondChar = words[1].first {
                return String([firstChar, secondChar]).uppercased()
            }
            return String(firstChar).uppercased()
        }
        return "?"
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 40, height: 40)
            .overlay(
                Text(initials)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.black)
            )
    }
}

struct FriendMoviesView: View {
    let friend: FriendDTO

    @Environment(AuthStore.self) private var auth
    @State private var movies: [SavedMovie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSetup = false
    @State private var activeParty: WatchPartyDTO?

    private let service = FriendService()
    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                if isLoading && movies.isEmpty {
                    ProgressView().padding(.top, 100).tint(Theme.accent)
                } else if movies.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("\(friend.displayLabel) hasn't saved any movies yet.")
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
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
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding()
                }
            }
        }
        .navigationTitle("\(friend.displayLabel)'s List")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingSetup = true
                } label: {
                    Label("Watch Party", systemImage: "play.rectangle.on.rectangle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            WatchPartySetupView(friend: friend) { party in
                activeParty = party
            }
        }
        .navigationDestination(for: MovieSummary.self) { movie in
            MovieDetailView(imdbID: movie.imdbID)
        }
        .navigationDestination(item: $activeParty) { party in
            if let uid = auth.user?.id {
                WatchPartySwipeView(party: party, currentUserID: uid)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            movies = try await service.friendMovies(userID: friend.user.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SharesInboxView: View {
    @Environment(NotificationsStore.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @State private var navImdbID: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if notifications.shares.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("No shares yet")
                            .foregroundStyle(.white.opacity(0.6))
                        Text("When a friend shares a movie with you, it will show up here.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(notifications.shares) { share in
                                Button {
                                    Task {
                                        await notifications.markRead(share.id)
                                        navImdbID = share.imdbID
                                    }
                                } label: {
                                    ShareRow(share: share)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await notifications.refreshShares() }
                }
            }
            .navigationTitle("Shared with You")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .navigationDestination(item: $navImdbID) { imdbID in
                MovieDetailView(imdbID: imdbID)
            }
            .task { await notifications.refreshShares() }
        }
    }
}

private struct ShareRow: View {
    let share: SharedMovieDTO

    private var fromLabel: String {
        if let name = share.fromUser.displayName, !name.isEmpty { return name }
        return share.fromUser.email
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: share.posterURL.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                default:
                    ZStack {
                        Theme.surface
                        Image(systemName: "film").foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !share.isRead {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    }
                    Text("\(fromLabel) shared").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Text(share.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let message = share.message, !message.isEmpty {
                    Text("\u{201C}\(message)\u{201D}")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(10)
        .background(
            (share.isRead ? Theme.surface : Theme.surface.opacity(0.9)),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(share.isRead ? Color.clear : Theme.accent.opacity(0.5), lineWidth: 1)
        )
    }
}

struct ShareMovieSheet: View {
    let movieID: String
    let title: String
    let year: String?
    let posterURL: String?

    @Environment(\.dismiss) private var dismiss
    @State private var friends: [FriendDTO] = []
    @State private var selectedFriend: FriendDTO?
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let service = FriendService()

    private var acceptedFriends: [FriendDTO] {
        friends.filter { $0.status == .accepted }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Send \u{201C}\(title)\u{201D} to a friend:")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal)

                        if acceptedFriends.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "person.2.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.3))
                                Text("You don't have any friends yet.")
                                    .foregroundStyle(.white.opacity(0.6))
                                Text("Add a friend from the Friends tab to share movies.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.4))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(acceptedFriends) { friend in
                                    Button {
                                        selectedFriend = friend
                                    } label: {
                                        HStack {
                                            Text(friend.displayLabel)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if selectedFriend == friend {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Theme.accent)
                                            } else {
                                                Image(systemName: "circle")
                                                    .foregroundStyle(.white.opacity(0.3))
                                            }
                                        }
                                        .padding(12)
                                        .background(
                                            (selectedFriend == friend ? Theme.accent.opacity(0.15) : Theme.surface),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Message (optional)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                TextField("", text: $message,
                                          prompt: Text("You should watch this!").foregroundColor(.gray),
                                          axis: .vertical)
                                    .lineLimit(3, reservesSpace: true)
                                    .padding(12)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal)
                        }

                        if let successMessage {
                            Text(successMessage).foregroundStyle(.green).padding(.horizontal)
                        }
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red).padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Share")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView().tint(Theme.accent) }
                        else { Text("Send").foregroundStyle(Theme.accent) }
                    }
                    .disabled(selectedFriend == nil || isSending)
                }
            }
            .task { await loadFriends() }
        }
    }

    private func loadFriends() async {
        do {
            friends = try await service.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        guard let selectedFriend else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        successMessage = nil
        do {
            let request = ShareMovieRequest(
                imdbID: movieID,
                title: title,
                year: year,
                posterURL: posterURL,
                message: message.trimmingCharacters(in: .whitespaces).isEmpty ? nil : message
            )
            _ = try await service.shareMovie(userID: selectedFriend.user.id, request: request)
            successMessage = "Sent to \(selectedFriend.displayLabel)!"
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
