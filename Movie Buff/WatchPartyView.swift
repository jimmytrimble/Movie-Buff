import SwiftUI

// MARK: - Setup

struct WatchPartySetupView: View {
    let friend: FriendDTO
    let onStarted: (WatchPartyDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: WatchPartySource = .shuffle
    @State private var selectedGenre: String?
    @State private var categories: [String] = []
    @State private var isStarting = false
    @State private var errorMessage: String?

    private let service = WatchPartyService()
    private let movies = MovieService()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        sourcePicker
                        if source == .genre {
                            genrePicker
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Button {
                            Task { await start() }
                        } label: {
                            HStack {
                                if isStarting { ProgressView().tint(.black) }
                                Text("Start Watch Party").font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                            .opacity(canStart ? 1 : 0.5)
                        }
                        .disabled(!canStart || isStarting)
                    }
                    .padding()
                }
            }
            .navigationTitle("Watch Party")
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
            }
            .task { await loadCategories() }
        }
    }

    private var canStart: Bool {
        source != .genre || (selectedGenre?.isEmpty == false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Watching with").font(.caption).foregroundStyle(.white.opacity(0.6)).tracking(1)
            Text(friend.displayLabel)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Swipe right on movies you'd watch. The first one you both swipe right on wins.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick from")
                .font(.headline).foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 8) {
                sourceChip("Shuffle Our Lists", value: .shuffle, icon: "shuffle")
                sourceChip("A Genre", value: .genre, icon: "theatermasks")
                sourceChip("All Movies", value: .all, icon: "sparkles")
            }
        }
    }

    private func sourceChip(_ label: String, value: WatchPartySource, icon: String) -> some View {
        Button {
            source = value
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(8)
            .background(source == value ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(source == value ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }

    private var genrePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Genre").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            if categories.isEmpty {
                ProgressView().tint(.white.opacity(0.6))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(categories, id: \.self) { g in
                        Button { selectedGenre = g } label: {
                            Text(g)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(selectedGenre == g ? Theme.accent : Color.white.opacity(0.08),
                                            in: Capsule())
                                .foregroundStyle(selectedGenre == g ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadCategories() async {
        if categories.isEmpty {
            categories = (try? await movies.categories()) ?? []
        }
    }

    private func start() async {
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            let party = try await service.start(
                recipientID: friend.user.id,
                source: source,
                genre: source == .genre ? selectedGenre : nil
            )
            onStarted(party)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Swipe

struct WatchPartySwipeView: View {
    @State private var party: WatchPartyDTO
    let currentUserID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isFlipped: Bool = false
    @State private var isVoting: Bool = false
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?

    private let service = WatchPartyService()

    init(party: WatchPartyDTO, currentUserID: UUID) {
        _party = State(initialValue: party)
        self.currentUserID = currentUserID
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                header
                if party.statusEnum == .matched, let matchedID = party.matchedImdbID,
                   let matchedMovie = party.deck.first(where: { $0.imdbID == matchedID }) {
                    matchedView(matchedMovie)
                } else if currentIndex < party.deck.count {
                    cardStack
                    controls
                } else {
                    exhaustedView
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red).padding()
                }
            }
            .padding()
        }
        .navigationTitle("Watch Party")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        try? await service.end(party.id)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: Header

    private var opponent: UserDTO { party.other(than: currentUserID) }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Watching with \(opponent.displayName ?? opponent.email)")
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
            Text("\(currentIndex + 1) / \(party.deck.count)")
                .font(.caption).foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: Card stack

    private var cardStack: some View {
        ZStack {
            // Peek at next card behind
            if currentIndex + 1 < party.deck.count {
                cardView(party.deck[currentIndex + 1], showBack: false)
                    .scaleEffect(0.94)
                    .opacity(0.6)
                    .offset(y: 12)
            }
            cardView(party.deck[currentIndex], showBack: isFlipped)
                .offset(x: dragOffset.width, y: dragOffset.height)
                .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                .overlay(alignment: .topLeading) { likeStamp }
                .overlay(alignment: .topTrailing) { nopeStamp }
                .gesture(dragGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.spring) { isFlipped.toggle() }
                }
        }
        .frame(maxHeight: .infinity)
    }

    private func cardView(_ movie: WatchPartyDeckEntry, showBack: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 8)

            if showBack {
                cardBack(movie)
            } else {
                cardFront(movie)
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func cardFront(_ movie: WatchPartyDeckEntry) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                default: Theme.surface
                }
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.title3.bold()).foregroundStyle(.white).lineLimit(2)
                if let year = movie.year, !year.isEmpty {
                    Text(year).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Text("Double-tap for details")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            .padding()
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @State private var backDetail: MovieDetail?

    private func cardBack(_ movie: WatchPartyDeckEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(movie.title).font(.title3.bold()).foregroundStyle(.white)
                if let detail = backDetail, detail.imdbID == movie.imdbID {
                    if let rating = detail.imdbRating, rating != "N/A" {
                        Label(rating, systemImage: "star.fill").foregroundStyle(.yellow).font(.caption)
                    }
                    if let genre = detail.genre { Text(genre).font(.footnote).foregroundStyle(.white.opacity(0.7)) }
                    if let plot = detail.plot { Text(plot).font(.footnote).foregroundStyle(.white.opacity(0.85)) }
                    if let actors = detail.actors, actors != "N/A" {
                        Text("Cast: \(actors)").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    HStack { ProgressView().tint(.white.opacity(0.6)); Text("Loading…").foregroundStyle(.white.opacity(0.5)) }
                        .task { backDetail = try? await MovieService().detail(imdbID: movie.imdbID) }
                }
                Text("Double-tap to flip back").font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
            .padding()
        }
    }

    private var likeStamp: some View {
        Text("YES")
            .font(.system(size: 44, weight: .heavy))
            .foregroundStyle(.green)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.green, lineWidth: 3))
            .rotationEffect(.degrees(-14))
            .opacity(Double(max(0, min(1, dragOffset.width / 120))))
            .padding()
    }

    private var nopeStamp: some View {
        Text("NOPE")
            .font(.system(size: 44, weight: .heavy))
            .foregroundStyle(.red)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.red, lineWidth: 3))
            .rotationEffect(.degrees(14))
            .opacity(Double(max(0, min(1, -dragOffset.width / 120))))
            .padding()
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isVoting { dragOffset = value.translation }
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    swipeAway(right: true)
                } else if value.translation.width < -threshold {
                    swipeAway(right: false)
                } else {
                    withAnimation(.spring) { dragOffset = .zero }
                }
            }
    }

    private var controls: some View {
        HStack(spacing: 40) {
            circleButton(icon: "xmark", color: .red) { swipeAway(right: false) }
            circleButton(icon: "heart.fill", color: .green) { swipeAway(right: true) }
        }
        .disabled(isVoting)
        .padding(.bottom, 12)
    }

    private func circleButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(color)
                .frame(width: 56, height: 56)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Match / exhausted

    private func matchedView(_ movie: WatchPartyDeckEntry) -> some View {
        VStack(spacing: 16) {
            Text("It's a match! 🍿").font(.title.bold()).foregroundStyle(Theme.accent)
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2/3, contentMode: .fit)
                default:
                    Theme.surface.aspectRatio(2/3, contentMode: .fit)
                }
            }
            .frame(maxWidth: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 12)

            Text(movie.title).font(.title3.bold()).foregroundStyle(.white).multilineTextAlignment(.center)

            NavigationLink {
                MovieDetailView(imdbID: movie.imdbID)
            } label: {
                Text("Watch This")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }

            Button {
                Task { await continueSwiping() }
            } label: {
                Text(continueButtonLabel)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal)
    }

    private var continueButtonLabel: String {
        let mine = party.isInitiator(currentUserID) ? party.initiatorWantsContinue : party.recipientWantsContinue
        let theirs = party.isInitiator(currentUserID) ? party.recipientWantsContinue : party.initiatorWantsContinue
        if mine, !theirs { return "Waiting on \(opponent.displayName ?? "friend")…" }
        return "Continue Shuffling"
    }

    private var exhaustedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack").font(.system(size: 60)).foregroundStyle(.white.opacity(0.4))
            Text("You've seen every movie in the deck.")
                .foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            Button("End Party") {
                Task { try? await service.end(party.id); dismiss() }
            }
            .foregroundStyle(Theme.accent)
        }
        .padding()
    }

    // MARK: Actions

    private func swipeAway(right: Bool) {
        guard currentIndex < party.deck.count else { return }
        isVoting = true
        let movie = party.deck[currentIndex]
        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset.width = right ? 800 : -800
        }
        Task {
            defer { isVoting = false }
            do {
                let result = try await service.vote(party.id, imdbID: movie.imdbID, vote: right)
                party = result.party
            } catch {
                errorMessage = error.localizedDescription
            }
            currentIndex += 1
            isFlipped = false
            backDetail = nil
            dragOffset = .zero
        }
    }

    private func continueSwiping() async {
        do {
            party = try await service.continueSwiping(party.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                if let refreshed = try? await service.get(party.id) {
                    await MainActor.run { self.party = refreshed }
                }
            }
        }
    }
}

// MARK: - Pending invitations list (used inside FriendsView)

struct WatchPartyInviteRow: View {
    let party: WatchPartyDTO
    let currentUserID: UUID
    let onOpen: (WatchPartyDTO) -> Void

    @State private var isBusy = false

    private let service = WatchPartyService()

    private var isIncoming: Bool { party.isRecipient(currentUserID) }
    private var otherLabel: String {
        let u = party.other(than: currentUserID)
        return u.displayName ?? u.email
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack.fill")
                .foregroundStyle(Theme.accent)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(otherLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            if isBusy {
                ProgressView().tint(.white.opacity(0.6))
            } else if party.statusEnum == .pending && isIncoming {
                Button("Decline") {
                    Task { isBusy = true; try? await service.decline(party.id); isBusy = false }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                Button("Accept") {
                    Task {
                        isBusy = true
                        if let p = try? await service.accept(party.id) { onOpen(p) }
                        isBusy = false
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.accent, in: Capsule())
                .buttonStyle(.plain)
            } else {
                Button("Open") { onOpen(party) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var subtitle: String {
        switch party.statusEnum {
        case .pending:  return isIncoming ? "Wants to Watch Party" : "Invite sent"
        case .active:   return "Swiping…"
        case .matched:  return "Match found!"
        case .ended:    return "Ended"
        }
    }
}
