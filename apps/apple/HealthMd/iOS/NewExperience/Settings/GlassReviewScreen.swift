#if os(iOS)
import StoreKit
import SwiftUI

/// ReviewG, opened by the user from App & support. App Store guideline 5.6.1 reserves
/// automatic prompts for the system API, so this never appears on its own and the
/// app's existing `requestReview()` timing is unchanged. "Quick rating" asks the same
/// system API only when tapped; the system decides whether to show its prompt.
struct GlassReviewScreen: View {
    let onSendFeedback: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    private let writeReviewURL = URL(string: "https://apps.apple.com/app/id6757763969?action=write-review")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                        VStack(spacing: 10) {
                            Image("HealthCrystalHeart")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .accessibilityHidden(true)
                            Text("Help us grow")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(palette.text)
                            Text("A review helps more people own their health data.")
                                .glassFont(.body)
                                .foregroundStyle(palette.sec)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                        reviewsPanel
                    }
                    .padding(.horizontal, GlassMetrics.screenMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 8) {
                    Link(destination: writeReviewURL) {
                        Text("Write a review")
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    Button {
                        requestReview()
                    } label: {
                        Text("Quick rating")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Capsule().fill(palette.surface2))
                            .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("glass.review.quickRating")
                    Button(String(localized: "Send feedback instead"), action: onSendFeedback)
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .glassSurface(cornerRadius: 0)
            }
            .background(palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("glass.review")
    }

    /// One real five-star App Store review, from the selection the website publishes
    /// (apps/website/index.html, #reviews). The quote stays in its original English.
    /// The storefront is not known here, so none is named.
    private var reviewsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Five-star App Store reviews")
                .glassFont(.caption)
                .foregroundStyle(palette.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "“\(Self.review.quote)”")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "— \(Self.review.author)")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 4)
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private struct Review { let quote: String; let author: String }

    private static let review = Review(
        quote: "Works great, I needed a solution to export my health file to markdown locally. This allows me to have that.",
        author: "Manjil"
    )
}
#endif
