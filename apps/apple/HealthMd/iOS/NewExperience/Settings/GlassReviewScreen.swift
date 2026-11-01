#if os(iOS)
import SwiftUI

/// ReviewG, opened by the user from App & support. App Store guideline 5.6.1 reserves
/// automatic prompts for the system API, so this never appears on its own and the
/// app's existing `requestReview()` timing is unchanged. Sample review text is omitted.
struct GlassReviewScreen: View {
    let onSendFeedback: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let writeReviewURL = URL(string: "https://apps.apple.com/app/id6757763969?action=write-review")!

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                Text("Help us grow").glassFont(.largeTitle).foregroundStyle(palette.text)
                Text("A review helps more people own their health data.")
                    .glassFont(.body)
                    .foregroundStyle(palette.sec)
                Spacer()
                Link(destination: writeReviewURL) {
                    Text("Write a review")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                Button(String(localized: "Send feedback instead"), action: onSendFeedback)
                    .buttonStyle(.plain)
                    .glassFont(.caption)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
            }
            .padding(GlassMetrics.screenMargin)
            .background(palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("glass.review")
    }
}
#endif
