import SwiftUI

struct CommentsView: View {
    let imdbID: String
    let movieTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [CommentDTO] = []
    @State private var filter: CommentFilter = .all
    @State private var draft: String = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var isPosting = false
    @State private var hasMore = true
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    // Reply state
    @State private var replyingTo: CommentDTO?
    // Expanded reply threads: parentID → replies
    @State private var expandedReplies: [UUID: [CommentDTO]] = [:]
    @State private var loadingReplies: Set<UUID> = []
    // Report sheet
    @State private var reportingComment: CommentDTO?
    // Spoiler state
    @State private var draftIsSpoiler: Bool = false
    @State private var revealedSpoilers: Set<UUID> = []

    private let service = CommentService()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterBar
                    content
                    if let replyingTo { replyContextBar(replyingTo) }
                    inputBar
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
                    VStack(spacing: 2) {
                        Text("Comments")
                            .font(.sectionTitle)
                            .foregroundStyle(.white)
                        Text(movieTitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .task { await reload() }
            .task(id: filter) { await reload() }
            .sheet(item: $reportingComment) { comment in
                ReportSheet(comment: comment) { reason in
                    Task { await report(comment, reason: reason) }
                }
                #if os(iOS)
                .presentationDetents([.medium])
                #endif
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterPill(label: "All", value: .all)
            filterPill(label: "Friends", value: .friends)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func filterPill(label: String, value: CommentFilter) -> some View {
        Button {
            if filter != value { filter = value }
        } label: {
            Text(label)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(filter == value ? Theme.accent : Color.white.opacity(0.08))
                )
                .foregroundStyle(filter == value ? .black : .white)
                .overlay(
                    Capsule().stroke(
                        filter == value ? Color.clear : Color.white.opacity(0.15),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if isLoading && comments.isEmpty {
            Spacer()
            ProgressView().tint(Theme.accent)
            Spacer()
        } else if comments.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(comments) { comment in
                        commentThread(for: comment)
                            .task {
                                if comment.id == comments.last?.id, hasMore, !isLoadingMore {
                                    await loadMore()
                                }
                            }
                    }
                    if isLoadingMore {
                        ProgressView().tint(Theme.accent).padding(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .refreshable { await reload() }
        }
    }

    private func commentThread(for comment: CommentDTO) -> some View {
        VStack(spacing: 8) {
            CommentRow(
                comment: comment,
                isReply: false,
                isRevealed: revealedSpoilers.contains(comment.id),
                onLike: { Task { await toggleLike(comment) } },
                onReply: { replyingTo = comment; isInputFocused = true },
                onDelete: { Task { await deleteComment(comment) } },
                onReport: { reportingComment = comment },
                onReveal: { revealedSpoilers.insert(comment.id) }
            )

            // Reply thread
            if comment.replyCount > 0 || expandedReplies[comment.id] != nil {
                repliesSection(for: comment)
            }
        }
    }

    @ViewBuilder
    private func repliesSection(for parent: CommentDTO) -> some View {
        let replies = expandedReplies[parent.id]

        if let replies {
            VStack(spacing: 8) {
                ForEach(replies) { reply in
                    CommentRow(
                        comment: reply,
                        isReply: true,
                        isRevealed: revealedSpoilers.contains(reply.id),
                        onLike: { Task { await toggleLike(reply) } },
                        onReply: { replyingTo = parent; isInputFocused = true },
                        onDelete: { Task { await deleteComment(reply) } },
                        onReport: { reportingComment = reply },
                        onReveal: { revealedSpoilers.insert(reply.id) }
                    )
                }
                Button {
                    expandedReplies[parent.id] = nil
                } label: {
                    Text("Hide replies")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 44)
            }
        } else {
            Button {
                Task { await loadReplies(for: parent) }
            } label: {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 24, height: 1)
                    if loadingReplies.contains(parent.id) {
                        ProgressView().tint(Theme.accent).scaleEffect(0.7)
                    } else {
                        Text("View \(parent.replyCount) \(parent.replyCount == 1 ? "reply" : "replies")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 44)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: filter == .friends ? "person.2.slash" : "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.35))
            Text(filter == .friends
                 ? "No friends have commented yet"
                 : "Be the first to comment")
                .foregroundStyle(.white.opacity(0.6))
                .font(.footnote)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Reply context + input

    private func replyContextBar(_ target: CommentDTO) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption).foregroundStyle(Theme.gold)
            Text("Replying to ")
                .font(.caption).foregroundStyle(.white.opacity(0.6)) +
            Text(target.author.displayName ?? target.author.email)
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
            Spacer()
            Button {
                replyingTo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.7))
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("", text: $draft,
                          prompt: Text(replyingTo == nil ? "Add a comment…" : "Add a reply…").foregroundColor(.gray),
                          axis: .vertical)
                    .lineLimit(1...4)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(.white)
                    .focused($isInputFocused)

                Button {
                    Task { await post() }
                } label: {
                    if isPosting {
                        ProgressView().tint(.black).frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(canPost ? .black : .white.opacity(0.4))
                            .frame(width: 36, height: 36)
                    }
                }
                .background(canPost ? Theme.accent : Color.white.opacity(0.08), in: Circle())
                .buttonStyle(.plain)
                .disabled(!canPost || isPosting)
            }

            HStack(spacing: 8) {
                Button {
                    draftIsSpoiler.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: draftIsSpoiler ? "eye.slash.fill" : "eye.slash")
                            .font(.caption)
                        Text("Mark as spoiler")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(draftIsSpoiler ? Theme.accent : Color.white.opacity(0.08))
                    )
                    .foregroundStyle(draftIsSpoiler ? .black : .white.opacity(0.75))
                    .overlay(
                        Capsule().stroke(draftIsSpoiler ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.background.opacity(0.95))
    }

    private var canPost: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        expandedReplies.removeAll()
        do {
            let page = try await service.page(imdbID: imdbID, filter: filter)
            comments = page.comments
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let last = comments.last, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.page(imdbID: imdbID, filter: filter, before: last.id)
            comments.append(contentsOf: page.comments)
            hasMore = page.hasMore
        } catch {
            hasMore = false
        }
    }

    private func loadReplies(for parent: CommentDTO) async {
        loadingReplies.insert(parent.id)
        defer { loadingReplies.remove(parent.id) }
        do {
            let replies = try await service.replies(imdbID: imdbID, commentID: parent.id)
            expandedReplies[parent.id] = replies
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func post() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        let parent = replyingTo
        let spoiler = draftIsSpoiler
        do {
            let posted = try await service.post(imdbID: imdbID, content: text, parentID: parent?.id, isSpoiler: spoiler)
            if let parent {
                // Append to expanded replies + bump reply count.
                expandedReplies[parent.id, default: []].append(posted)
                if let idx = comments.firstIndex(where: { $0.id == parent.id }) {
                    let old = comments[idx]
                    comments[idx] = CommentDTO(
                        id: old.id, author: old.author, content: old.content,
                        createdAt: old.createdAt, parentID: old.parentID,
                        replyCount: old.replyCount + 1,
                        likeCount: old.likeCount, isLiked: old.isLiked, isMine: old.isMine,
                        isSpoiler: old.isSpoiler
                    )
                }
            } else {
                comments.insert(posted, at: 0)
            }
            draft = ""
            replyingTo = nil
            draftIsSpoiler = false
            isInputFocused = false
            // Author sees their own spoilers unblurred.
            if spoiler { revealedSpoilers.insert(posted.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLike(_ comment: CommentDTO) async {
        do {
            let result = try await service.toggleLike(imdbID: imdbID, commentID: comment.id)
            updateComment(comment.id) { old in
                CommentDTO(
                    id: old.id, author: old.author, content: old.content,
                    createdAt: old.createdAt, parentID: old.parentID,
                    replyCount: old.replyCount,
                    likeCount: result.likeCount, isLiked: result.isLiked, isMine: old.isMine,
                    isSpoiler: old.isSpoiler
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteComment(_ comment: CommentDTO) async {
        do {
            try await service.delete(imdbID: imdbID, commentID: comment.id)
            comments.removeAll { $0.id == comment.id }
            // Also strip from any expanded reply thread.
            for parentID in expandedReplies.keys {
                expandedReplies[parentID]?.removeAll { $0.id == comment.id }
                if let parentIdx = comments.firstIndex(where: { $0.id == parentID }) {
                    let old = comments[parentIdx]
                    comments[parentIdx] = CommentDTO(
                        id: old.id, author: old.author, content: old.content,
                        createdAt: old.createdAt, parentID: old.parentID,
                        replyCount: max(0, old.replyCount - 1),
                        likeCount: old.likeCount, isLiked: old.isLiked, isMine: old.isMine,
                        isSpoiler: old.isSpoiler
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func report(_ comment: CommentDTO, reason: String) async {
        do {
            try await service.report(imdbID: imdbID, commentID: comment.id, reason: reason)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Update a comment in place regardless of whether it's a top-level or a reply.
    private func updateComment(_ id: UUID, transform: (CommentDTO) -> CommentDTO) {
        if let idx = comments.firstIndex(where: { $0.id == id }) {
            comments[idx] = transform(comments[idx])
            return
        }
        for parentID in expandedReplies.keys {
            if let idx = expandedReplies[parentID]?.firstIndex(where: { $0.id == id }) {
                expandedReplies[parentID]![idx] = transform(expandedReplies[parentID]![idx])
                return
            }
        }
    }
}

// MARK: - Row

private struct CommentRow: View {
    let comment: CommentDTO
    let isReply: Bool
    let isRevealed: Bool
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onReveal: () -> Void

    /// A user's own spoiler comments always show; others' need a tap to reveal.
    private var shouldObscure: Bool {
        comment.isSpoiler && !comment.isMine && !isRevealed
    }

    private var authorName: String {
        if comment.isMine { return "You" }
        if let name = comment.author.displayName, !name.isEmpty { return name }
        return comment.author.email
    }

    private var relativeTime: String {
        guard let date = comment.createdAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(authorName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(comment.isMine ? Theme.gold : .white)
                    if !relativeTime.isEmpty {
                        Text(relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if comment.isSpoiler {
                        Text("SPOILER")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                    Spacer()
                    Menu {
                        if comment.isMine {
                            Button("Delete", role: .destructive, action: onDelete)
                        } else {
                            Button("Report", role: .destructive, action: onReport)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                    }
                }
                ZStack {
                    Text(comment.content)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .blur(radius: shouldObscure ? 6 : 0)
                        .opacity(shouldObscure ? 0.35 : 1)
                    if shouldObscure {
                        Button(action: onReveal) {
                            HStack(spacing: 6) {
                                Image(systemName: "eye.slash.fill")
                                Text("Spoiler — tap to reveal")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Actions row
                HStack(spacing: 16) {
                    Button(action: onLike) {
                        HStack(spacing: 4) {
                            Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                                .foregroundStyle(comment.isLiked ? Color.red : .white.opacity(0.6))
                            if comment.likeCount > 0 {
                                Text("\(comment.likeCount)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if !isReply {
                        Button(action: onReply) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                Text("Reply")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.leading, isReply ? 32 : 0)
    }

    private var avatar: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: isReply ? 28 : 34, height: isReply ? 28 : 34)
            .overlay(
                Text(initials)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.black)
            )
    }

    private var initials: String {
        let source = comment.author.displayName?.isEmpty == false
            ? comment.author.displayName!
            : comment.author.email
        let parts = source.split(separator: " ")
        if let first = parts.first, let ch = first.first {
            if parts.count > 1, let second = parts[1].first {
                return String([ch, second]).uppercased()
            }
            return String(ch).uppercased()
        }
        return "?"
    }
}

// MARK: - Report sheet

private struct ReportSheet: View {
    let comment: CommentDTO
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let reasons: [String] = [
        "Spam",
        "Harassment or hate speech",
        "Off-topic",
        "Misinformation",
        "Sexual or explicit",
        "Other",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Why are you reporting this comment?")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal)

                    Text("\u{201C}\(comment.content)\u{201D}")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal)
                        .lineLimit(2)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(reasons, id: \.self) { reason in
                                Button {
                                    onSubmit(reason)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(reason)
                                            .foregroundStyle(.white)
                                            .font(.subheadline)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                    .padding(14)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Report")
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
        }
    }
}
