#if os(iOS)
import UIKit
import UserNotifications
import Observation

@Observable
@MainActor
final class PushCoordinator {
    static let shared = PushCoordinator()

    /// Latest APNs device token as hex, if iOS has issued one this session.
    var deviceToken: String?

    /// Set by notification-tap handling; observed by ContentView to present a deep-link sheet.
    var pendingImdbID: String?

    /// Current OS notification permission for our app.
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var isAuthenticated = false
    private let service = FriendService()

    private init() {}

    // MARK: - Lifecycle

    func handleLogin() async {
        isAuthenticated = true
        await requestAuthorizationIfNeeded()
        UIApplication.shared.registerForRemoteNotifications()
        if deviceToken != nil {
            await syncToBackend()
        }
    }

    func handleLogout() async {
        // Try to remove from backend BEFORE the caller clears the bearer token.
        await unregisterFromBackend()
        isAuthenticated = false
    }

    // MARK: - AppDelegate callbacks

    func setDeviceToken(_ token: String) {
        deviceToken = token
        if isAuthenticated {
            Task { await syncToBackend() }
        }
    }

    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        if let imdbID = userInfo["imdbID"] as? String, !imdbID.isEmpty {
            pendingImdbID = imdbID
        }
    }

    func clearPending() {
        pendingImdbID = nil
    }

    // MARK: - Internals

    private func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        let refreshed = await center.notificationSettings()
        authorizationStatus = refreshed.authorizationStatus
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func syncToBackend() async {
        guard let token = deviceToken else { return }
        try? await service.registerDeviceToken(token: token, platform: "ios")
    }

    private func unregisterFromBackend() async {
        guard let token = deviceToken else { return }
        try? await service.unregisterDeviceToken(token: token)
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            PushCoordinator.shared.setDeviceToken(hex)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed: \(error.localizedDescription)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            PushCoordinator.shared.handleNotificationTap(userInfo: userInfo)
        }
    }
}
#endif
