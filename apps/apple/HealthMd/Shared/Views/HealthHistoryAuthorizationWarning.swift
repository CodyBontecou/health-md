import SwiftUI

struct HealthHistoryAuthorizationWarning: View {
    let assessment: HealthHistoryAuthorizationAssessment
    let onReviewPermissions: () -> Void

    var body: some View {
        if !assessment.supportsUnqualifiedFullHistoryClaim {
            let isLimited = assessment.state == .limitedHistory
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(isLimited ? "Apple Health history is limited" : "Full Apple Health history is unverified")
                        .font(.subheadline.weight(.semibold))
                    Text(isLimited
                         ? "Earlier data is unknown, not absent. All Time and all-available automation require full history access."
                         : "All Time and all-available automation require an OS 27+ assessment that covers every selected metric. Use an explicit date range until then.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    Button("Review Health permissions", action: onReviewPermissions)
                        .font(.footnote.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.s3)
            .accessibilityElement(children: .combine)
        }
    }
}
