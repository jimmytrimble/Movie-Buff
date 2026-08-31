import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @Environment(SubscriptionStore.self) private var subscriptions

    /// Reason line shown at the top — lets callers customize (e.g. "Sign in to save movies").
    var reason: String = "Unlock the full Movie Buff experience."

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        heroBadge
                        Text(reason)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        features

                        priceSection

                        if let error = subscriptions.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        VStack(spacing: 10) {
                            purchaseButton
                            restoreButton
                        }
                        .padding(.horizontal, 24)

                        legalFooter
                    }
                    .padding(.vertical, 32)
                }
            }
            .navigationTitle("Premium")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .task { await subscriptions.loadProducts() }
        }
        .preferredColorScheme(.dark)
    }

    private var heroBadge: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Theme.gold, Theme.goldSoft],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 96, height: 96)
                .shadow(color: Theme.gold.opacity(0.5), radius: 20, y: 6)
            Image(systemName: "star.fill")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(.black)
        }
        .padding(.top, 8)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "play.house.fill", title: "Reels", subtitle: "Discover new trailers, one swipe at a time.")
            featureRow(icon: "bookmark.fill", title: "Saved list", subtitle: "Keep every movie you want to watch in sync.")
            featureRow(icon: "person.2.fill", title: "Friends & sharing", subtitle: "Trade recs and run watch parties.")
            featureRow(icon: "bubble.left.and.bubble.right.fill", title: "Comments", subtitle: "Join the conversation on every movie.")
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    @ViewBuilder
    private var priceSection: some View {
        if let product = subscriptions.product(for: .monthly) {
            VStack(spacing: 4) {
                Text(product.displayPrice + " / month")
                    .font(.title.weight(.black))
                    .foregroundStyle(.white)
                Text("Auto-renews monthly. Cancel anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else {
            ProgressView().tint(.white.opacity(0.6))
        }
    }

    private var purchaseButton: some View {
        Button {
            Task {
                let ok = await subscriptions.purchase(.monthly)
                if ok {
                    await auth.refreshUser()
                    dismiss()
                }
            }
        } label: {
            HStack {
                if subscriptions.isPurchasing { ProgressView().tint(.black) }
                Text("Start Premium")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(.black)
        }
        .disabled(subscriptions.isPurchasing || subscriptions.product(for: .monthly) == nil)
    }

    private var restoreButton: some View {
        Button {
            Task {
                await subscriptions.restore()
                await auth.refreshUser()
            }
        } label: {
            Text("Restore Purchase")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.gold)
                .padding(.vertical, 6)
        }
    }

    private var legalFooter: some View {
        Text("Payment is charged to your Apple ID at confirmation of purchase. Subscriptions auto-renew unless auto-renew is turned off at least 24 hours before the end of the current period. Manage or cancel in Settings ▸ Apple ID ▸ Subscriptions.")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }
}
