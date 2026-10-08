import SwiftUI

/// Routes incoming `moviebuff://` deep links (today, from the Share extension's
/// upsell buttons) to the right in-app destination. Held at `ContentView` scope
/// so a link that arrives while the app is backgrounded is handled on activation.
@Observable
@MainActor
final class DeepLinkRouter {
    /// A pending destination the UI should present. Cleared once handled.
    enum Route: Equatable {
        case premium
        case signIn
    }

    private(set) var pendingRoute: Route?

    /// Parses a `moviebuff://` URL and records where to send the user.
    /// Recognizes `moviebuff://premium` and `moviebuff://signin`.
    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "moviebuff" else { return }

        // The destination is carried in the host (moviebuff://premium) with the
        // first path component as a fallback (moviebuff:///premium).
        let target = (url.host ?? url.pathComponents.first { $0 != "/" } ?? "")
            .lowercased()

        switch target {
        case "premium":
            pendingRoute = .premium
        case "signin", "sign-in", "login":
            pendingRoute = .signIn
        default:
            break
        }
    }

    func clear() {
        pendingRoute = nil
    }
}
