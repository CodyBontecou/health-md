import SwiftUI

/// Soft, non-blocking upgrade prompt surfaced after the 3rd and 7th free
/// exports ("value moments"). Unlike the hard quota block, dismissing is
/// free-form: the user keeps their remaining free exports either way.
///
/// The milestone is carried by `PurchaseManager.pendingUpgradePrompt` and the
/// analytics quota state (`freeExportsUsed`) on every value-moment event.
struct ExportUpgradePrompt: View {
    let milestone: Int
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @State private var didTrackShown = false

    private var remaining: Int {
        max(0, PurchaseManager.freeExportLimit - milestone)
    }

    var body: some View {
        VStack(spacing: Spacing.s6) {
            Image(systemName: "sparkles")
                .font(Typography.scaled(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.s2) {
                Text(title)
                    .font(Typography.heading20())
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(AccessibilityID.UpgradePrompt.title)

                Text(subtitle)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.s2) {
                Button {
                    onUpgrade()
                } label: {
                    Text("Unlock Unlimited Exports")
                        .font(Typography.headline())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.UpgradePrompt.upgrade)

                Button {
                    onDismiss()
                } label: {
                    Text(notNowTitle)
                        .font(Typography.body())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                .accessibilityIdentifier(AccessibilityID.UpgradePrompt.notNow)
            }
        }
        .padding(Spacing.s6)
        .frame(maxWidth: .infinity)
        .background(Color.bgPrimary)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !didTrackShown else { return }
            didTrackShown = true
            PricingAnalyticsClient.shared.trackUpgradePromptShown(
                quotaState: PurchaseManager.shared.analyticsQuotaState
            )
        }
    }

    private var title: String {
        milestone < PurchaseManager.freeExportLimit / 2
            ? "Your Health Archive Is Working"
            : "Keep the Streak Going"
    }

    private var subtitle: String {
        let limit = PurchaseManager.freeExportLimit
        if remaining > limit / 2 {
            return "You've saved \(milestone) of \(limit) free exports. Unlock once to keep your health journal going forever — including scheduled runs."
        }
        return "\(remaining) free export\(remaining == 1 ? "" : "s") left. Unlock unlimited private exports before your archive pauses."
    }

    private var notNowTitle: String {
        remaining > 0 ? "Not Now" : "Maybe Later"
    }
}
