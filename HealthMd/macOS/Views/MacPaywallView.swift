#if os(macOS)
import SwiftUI

/// macOS is a free companion app. Export access is controlled by the iPhone/iPad app,
/// where Apple Health exports originate.
struct MacPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)

            Text("Health.md for Mac is free")
                .font(BrandTypography.heading())
                .foregroundStyle(Color.textPrimary)

            Text("Use this Mac app as a local destination for exports started from Health.md on iPhone. The Mac app does not sell or gate access.")
                .font(BrandTypography.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .controlSize(.large)
        }
        .padding(32)
        .frame(width: 420)
        .background(Color.bgSecondary)
    }
}

#endif
