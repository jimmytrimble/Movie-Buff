import Foundation
import StoreKit
import SwiftUI

/// Product identifiers configured in App Store Connect. Add new products here
/// (e.g. a one-time lifetime unlock) without touching call sites.
enum PremiumProduct: String, CaseIterable {
    case monthly = "com.moviebuff.subscription.monthly"

    var displayName: String {
        switch self {
        case .monthly: return "Movie Buff Premium"
        }
    }
}

@Observable
@MainActor
final class SubscriptionStore {
    /// Products fetched from StoreKit, matched to `PremiumProduct` entries.
    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?

    private let service = SubscriptionService()
    private var updatesTask: Task<Void, Never>?

    /// Kick off StoreKit listeners. Call once at app launch.
    func start(onEntitlementChange: @escaping () async -> Void) {
        Task { await loadProducts() }
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            // StoreKit posts here for renewals, refunds, and any transaction
            // signed outside our purchase() flow (e.g. Family Sharing, restore).
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result {
                    await self?.sync(transaction: transaction)
                    await onEntitlementChange()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let ids = PremiumProduct.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
            self.products = fetched.sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Couldn't load subscription options: \(error.localizedDescription)"
        }
    }

    func product(for kind: PremiumProduct) -> Product? {
        products.first(where: { $0.id == kind.rawValue })
    }

    // MARK: - Purchase

    /// Runs the StoreKit purchase flow and, on success, forwards the signed
    /// transaction to our backend to flip the user's `isPremium` bit.
    /// Returns `true` if the user is now premium.
    @discardableResult
    func purchase(_ kind: PremiumProduct) async -> Bool {
        guard let product = product(for: kind) else {
            errorMessage = "That subscription isn't available right now."
            return false
        }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(.verified(let transaction)):
                await sync(transaction: transaction)
                await transaction.finish()
                return true
            case .success(.unverified(_, let error)):
                errorMessage = "Purchase couldn't be verified: \(error.localizedDescription)"
                return false
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Purchase is pending approval. You'll get access once it clears."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Replays existing purchases through the update stream. Users can trigger
    /// this from the paywall on a fresh install / device change.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Couldn't restore purchases: \(error.localizedDescription)"
        }
    }

    // MARK: - Sync to backend

    /// Forwards the signed JWS to our server so the User row picks up the new
    /// `subscriptionExpiresAt`. Failures are surfaced but don't crash the flow —
    /// on next launch we can retry with the current entitlement.
    private func sync(transaction: StoreKit.Transaction) async {
        let jws = transaction.jsonRepresentation  // Data
        guard let signed = String(data: jws, encoding: .utf8) else { return }
        do {
            _ = try await service.verifyApple(
                signedTransaction: signed,
                productID: transaction.productID
            )
        } catch {
            errorMessage = "Server couldn't verify subscription: \(error.localizedDescription)"
        }
    }

    /// Called at launch to bring the server in sync if a purchase happened while
    /// the app was offline (or on a different device).
    func syncCurrentEntitlements() async {
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                await sync(transaction: transaction)
            }
        }
    }
}
