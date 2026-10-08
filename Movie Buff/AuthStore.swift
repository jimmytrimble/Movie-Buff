import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.moviebuff.auth"
    /// App Group keychain shared with the Share Extension so it can authenticate
    /// API calls without the user leaving the host app. iOS-only: macOS app-group
    /// keychain access requires a team-prefixed group instead.
    private static let sharedAccessGroup = "group.JJ.Movie-Buff"

    private static func baseQuery(for key: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        #if os(iOS)
        if shared {
            query[kSecAttrAccessGroup as String] = sharedAccessGroup
        }
        #endif
        return query
    }

    static func save(_ value: String, for key: String) {
        delete(key: key)
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(for: key, shared: true)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        if let value = read(key: key, shared: true) {
            return value
        }
        // Migrate items saved before keychain sharing: re-save into the shared
        // group so the Share Extension can see them from now on.
        if let legacy = read(key: key, shared: false) {
            save(legacy, for: key)
            return legacy
        }
        return nil
    }

    private static func read(key: String, shared: Bool) -> String? {
        var query = baseQuery(for: key, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        SecItemDelete(baseQuery(for: key, shared: true) as CFDictionary)
        SecItemDelete(baseQuery(for: key, shared: false) as CFDictionary)
    }
}

@Observable
@MainActor
final class AuthStore {
    private(set) var user: User?
    private(set) var token: String?
    private(set) var isGuest = false
    var isLoading = false
    var errorMessage: String?

    private let authService: AuthService
    private let tokenKey = "auth_token"
    private let guestKey = "auth_guest_mode"

    var isAuthenticated: Bool { token != nil || isGuest }
    var isSignedIn: Bool { token != nil }
    /// Signed-in AND actively subscribed. Free users and guests both return false.
    var isPremium: Bool { user?.isPremium == true }

    init(authService: AuthService? = nil) {
        self.authService = authService ?? AuthService()
    }

    func restore() async {
        if let saved = KeychainHelper.read(key: tokenKey) {
            self.token = saved
            await APIClient.shared.setAuthToken(saved)
            do {
                self.user = try await authService.me()
                #if os(iOS)
                await PushCoordinator.shared.handleLogin()
                #endif
            } catch {
                await signOutLocal()
            }
            return
        }
        if KeychainHelper.read(key: guestKey) != nil {
            self.isGuest = true
        }
    }

    func continueAsGuest() {
        isGuest = true
        errorMessage = nil
        KeychainHelper.save("1", for: guestKey)
    }

    func exitGuestMode() {
        isGuest = false
        KeychainHelper.delete(key: guestKey)
    }

    func login(identifier: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await authService.login(identifier: identifier, password: password)
            await apply(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await authService.register(email: email, password: password, displayName: displayName)
            await apply(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        do { try await authService.logout() } catch {}
        await signOutLocal()
    }

    /// Re-fetches the current user from the server. Used after a subscription
    /// purchase to pick up the new `isPremium` state.
    func refreshUser() async {
        guard token != nil else { return }
        do {
            self.user = try await authService.me()
        } catch {
            // Silent — we'll just keep the last known state.
        }
    }

    func updateProfile(
        email: String?,
        displayName: String?,
        currentPassword: String?,
        newPassword: String?
    ) async throws {
        let request = UpdateProfileRequest(
            email: email,
            displayName: displayName,
            currentPassword: currentPassword,
            newPassword: newPassword
        )
        let updated = try await authService.updateProfile(request)
        self.user = updated
    }

    func forgotPassword(email: String) async throws {
        try await authService.forgotPassword(email: email)
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        try await authService.resetPassword(email: email, code: code, newPassword: newPassword)
    }

    private func apply(_ response: AuthResponse) async {
        self.token = response.token
        self.user = response.user
        self.isGuest = false
        KeychainHelper.delete(key: guestKey)
        KeychainHelper.save(response.token, for: tokenKey)
        await APIClient.shared.setAuthToken(response.token)
        #if os(iOS)
        await PushCoordinator.shared.handleLogin()
        #endif
    }

    private func signOutLocal() async {
        #if os(iOS)
        // Deregister BEFORE clearing the bearer token so the DELETE succeeds.
        await PushCoordinator.shared.handleLogout()
        #endif
        self.token = nil
        self.user = nil
        self.isGuest = false
        KeychainHelper.delete(key: tokenKey)
        KeychainHelper.delete(key: guestKey)
        await APIClient.shared.setAuthToken(nil)
    }
}
