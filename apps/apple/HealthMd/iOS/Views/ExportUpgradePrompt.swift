import SwiftUI
import StoreKit

/// Guidance after the first completed free export, followed by a dismissible
/// lifetime offer after the third. Opening scheduling never enables a schedule.
struct ExportUpgradePrompt: View {
    let milestone: Int
    let onSchedule: () -> Void
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var didTrackShown = false

    private var isFirstExport: Bool { milestone == 1 }
    private var remaining: Int { purchaseManager.freeExportsRemaining }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.s6) {
                Image(systemName: isFirstExport ? "checkmark.circle" : "calendar.badge.clock")
                    .font(Typography.scaled(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: Spacing.s2) {
                    Text(isFirstExport ? "Your First Export Is Complete" : "Keep Your Health Notes Going")
                        .font(Typography.heading20())
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityIdentifier(AccessibilityID.UpgradePrompt.title)

                    Text(isFirstExport
                         ? "Make your next export easier. Choose a daily schedule to keep saving new health notes without repeating these steps."
                         : "You've completed three exports. Unlock once to keep exporting manually or on a schedule, without limits.")
                        .font(Typography.body())
                        .foregroundStyle(Color.textSecondary)

                    if isFirstExport {
                        Text("Scheduled runs use the same free allowance. You review the settings before turning them on.")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        if let price = purchaseManager.product?.displayPrice {
                            Text("Lifetime access: \(price)")
                                .font(Typography.headline())
                                .foregroundStyle(Color.textPrimary)
                        }
                        Text("One purchase. No subscription. Your exported files stay yours.")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)

                VStack(spacing: Spacing.s2) {
                    Button(action: isFirstExport ? onSchedule : onUpgrade) {
                        Text(isFirstExport ? "Set Up Daily Exports" : "See Lifetime Access")
                            .font(Typography.headline())
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(isFirstExport
                        ? AccessibilityID.UpgradePrompt.schedule
                        : AccessibilityID.UpgradePrompt.upgrade)

                    Button(action: onDismiss) {
                        Text(isFirstExport ? "Keep Exporting Manually" : "Continue Free")
                            .font(Typography.body())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier(AccessibilityID.UpgradePrompt.notNow)

                    Text("\(remaining) free exports remaining")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("upgradePrompt.remaining")
                }
            }
            .padding(Spacing.s6)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bgPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !didTrackShown else { return }
            didTrackShown = true
        }
        .task {
            if !isFirstExport { await purchaseManager.loadProductsIfNeeded() }
        }
    }
}
