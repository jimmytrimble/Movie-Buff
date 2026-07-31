import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.moviebuff.auth"

    static func save(_ value: String, for key: String) {
        delete(key: key)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@Observable
@MainActor
final class AuthStore {
    private(set) var user: User?
    private(set) var token: String?
    var isLoading = false
    var errorMessage: String?

    private let authService: AuthService
    private let tokenKey = "auth_token"

    var isAuthenticated: Bool { token != nil }

    init(authService: AuthService = AuthService()) {
        self.authService = authService
    }

    func restore() async {
        guard let saved = KeychainHelper.read(key: tokenKey) else { return }
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
        KeychainHelper.delete(key: tokenKey)
        await APIClient.shared.setAuthToken(nil)
    }
}
