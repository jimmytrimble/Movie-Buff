import SwiftUI

/// Another user's profile. Profiles themselves are a general feature; the
/// **Message** action is premium and only offered to accepted friends.
struct PublicProfileView: View {
    let userID: UUID
    var preloadedName: String?

    @Environment(AuthStore.self) private var auth
    @Environment(SubscriptionStore.self) private var subscriptions

    @State private var profile: ProfileDTO?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTab: ProfileTab = .saved

    @State private var chatTarget: UserDTO?
    @State private var showPaywall = false
    @State private var requestSent = false

    private let profileService = ProfileService()
    private let friendService = FriendService()

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                if let profile {
                    VStack(alignment: .leading, spacing: 20) {
                        header(profile)
                        actionRow(profile)
                        statsBar(profile)
                        ProfileContentTabs(profile: profile, selectedTab: $selectedTab)
                    }
                    .padding()
                } else if isLoading {
                    ProgressView().tint(Theme.accent).padding(.top, 120)
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.4))
                        Text(errorMessage)
                            .font(.footnote).foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 120)
                }
            }
        }
        .navigationTitle(profile?.user.displayLabel ?? preloadedName ?? "Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: MovieSummary.self) { movie in
            MovieDetailView(imdbID: movie.imdbID)
        }
        .navigationDestination(item: $chatTarget) { user in
            ChatView(otherUser: user)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Messaging friends is a Premium feature.")
                .environment(auth)
                .environment(subscriptions)
        }
        .task { await load() }
    }

    private func header(_ profile: ProfileDTO) -> some View {
        VStack(spacing: 12) {
            ProfileAvatar(imageData: profile.user.avatarImageData,
                          label: profile.user.displayLabel, size: 96)
                .shadow(color: Theme.gold.opacity(0.35), radius: 12, y: 4)
            Text(profile.user.displayLabel)
                .font(.sectionTitle).foregroundStyle(.white)
            if let bio = profile.user.bio, !bio.isEmpty {
                Text(bio)
                    .font(.footnote).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func actionRow(_ profile: ProfileDTO) -> some View {
        if !profile.isSelf {
            if profile.isFriend {
                Button {
                    if auth.isPremium { chatTarget = profile.user }
                    else { showPaywall = true }
                } label: {
                    Label("Message", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            } else if requestSent {
                Text("Friend request sent")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    Task { await sendRequest(profile.user) }
                } label: {
                    Label("Add Friend", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statsBar(_ profile: ProfileDTO) -> some View {
        HStack(spacing: 0) {
            stat(profile.savedCount, "Saved")
            divider
            stat(profile.commentCount, "Comments")
            divider
            stat(profile.ratings.count, "Ratings")
        }
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stat(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.weight(.black)).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 28)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await profileService.profile(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendRequest(_ user: UserDTO) async {
        do {
            _ = try await friendService.sendRequest(email: user.email)
            requestSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
