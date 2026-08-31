import SwiftUI

struct ContentView: View {
    @State private var auth = AuthStore()
    @State private var subscriptions = SubscriptionStore()
    #if os(iOS)
    @Environment(PushCoordinator.self) private var push
    #endif

    var body: some View {
        Group {
            if auth.isAuthenticated {
                HomeView()
            } else {
                AuthView()
            }
        }
        .environment(auth)
        .environment(subscriptions)
        .preferredColorScheme(.dark)
        .task {
            await auth.restore()
            // Kick off StoreKit listeners. Any renewal/refund/family-sharing event
            // will POST the fresh transaction to our server and refresh the User.
            subscriptions.start {
                await auth.refreshUser()
            }
            // Sync existing entitlements on launch so a purchase made on another
            // device (or before signing in) is reflected in `isPremium`.
            await subscriptions.syncCurrentEntitlements()
            await auth.refreshUser()
        }
        #if os(iOS)
        .sheet(item: pendingSheetBinding) { item in
            NavigationStack {
                MovieDetailView(imdbID: item.value)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { push.clearPending() }
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .environment(auth)
        }
        #endif
    }

    #if os(iOS)
    private var pendingSheetBinding: Binding<PendingDeepLink?> {
        Binding(
            get: { push.pendingImdbID.map(PendingDeepLink.init) },
            set: { if $0 == nil { push.clearPending() } }
        )
    }
    #endif
}

#if os(iOS)
private struct PendingDeepLink: Identifiable {
    let value: String
    var id: String { value }
}
#endif

#Preview {
    ContentView()
}
