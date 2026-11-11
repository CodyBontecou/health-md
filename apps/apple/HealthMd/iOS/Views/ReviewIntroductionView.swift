#if os(iOS)
import SwiftUI
import StoreKit

/// An optional introduction. StoreKit owns all rating entry and may show no UI.
struct ReviewIntroductionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var feedbackReporter = FeedbackReporter()
    @State private var showMailCompose = false
    @State private var requestAttempted = false
    @State private var showStoreFailure = false
    @State private var reviews = AppStoreReview.verifiedExcerpts

    private let storeURL = URL(string: "https://apps.apple.com/app/id6757763969?action=write-review")!

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Spacing.s6) {
                    Spacer(minLength: Spacing.s10)
                    ratingCrest
                        .accessibilityHidden(true)
                    VStack(spacing: Spacing.s3) {
                        Text("Help us grow")
                            .font(Typography.heading24())
                            .accessibilityAddTraits(.isHeader)
                        Text("Leave a review to help more people make their health data their own.")
                            .font(Typography.body())
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    Text("Built with the Health.md community")
                        .font(Typography.label())
                        .multilineTextAlignment(.center)
                    reviewCards(availableWidth: min(geometry.size.width, 460))
                    Spacer(minLength: Spacing.s10)
                }
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s8)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(0, geometry.size.height))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background { UpdateMomentBackground() }
        .foregroundStyle(.white)
        .task {
            do {
                let fetched = try await AppStoreReviewsClient().fetch()
                try Task.checkCancellation()
                reviews = fetched
            } catch {
                // The verified, bundled excerpts remain available offline. A
                // cancelled fetch must not update a dismissed introduction.
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(Typography.headline())
                .frame(minWidth: 44, minHeight: 44)
                .background(.white.opacity(0.1), in: Circle())
                .padding(Spacing.s4)
                .accessibilityIdentifier("reviewIntroduction.close")
        }
        .sheet(isPresented: $showMailCompose, onDismiss: feedbackReporter.mailSheetDismissed) {
            MailComposeView(onCompletion: feedbackReporter.completeMail)
        }
        .feedbackFailureSheet($feedbackReporter.failure)
        .alert("App Store Could Not Be Opened", isPresented: $showStoreFailure) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again later. You can close this screen and keep using Health.md.")
        }
    }

    private var ratingCrest: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 60))
            HStack(spacing: Spacing.s1) {
                ForEach(0..<5) { _ in
                    Image(systemName: "star.fill")
                        .font(.title3)
                }
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 60))
        }
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func reviewCards(availableWidth: CGFloat) -> some View {
        let highlights = reviews.filter { $0.rating == 5 }
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text("Five-star App Store reviews · US")
                    .font(Typography.label())
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, Spacing.s6)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: Spacing.s4) {
                        ForEach(highlights) { review in
                            reviewCard(review)
                        }
                    }
                    .padding(.horizontal, Spacing.s6)
                } else {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: Spacing.s4) {
                            ForEach(highlights) { review in
                                reviewCard(review)
                                    .frame(width: max(220, min(availableWidth - 80, 340)))
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, Spacing.s6, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, -Spacing.s6)
            .accessibilityIdentifier("reviewIntroduction.reviews")
        }
    }

    private func reviewCard(_ review: AppStoreReview) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s1) {
                ForEach(0..<5) { index in
                    Image(systemName: index < review.rating ? "star.fill" : "star")
                        .foregroundStyle(Color.warning)
                }
            }
            .font(Typography.label())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(review.rating) out of 5 stars"))
            Text(verbatim: review.title)
                .font(Typography.headline())
            Text(verbatim: "“\(review.body)”")
                .font(Typography.body())
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: review.author)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Spacer(minLength: Spacing.s2)
                Link("App Store", destination: review.sourceURL)
                    .accessibilityLabel(Text("Read full reviews on the App Store"))
                    .frame(minHeight: 44)
            }
            .font(Typography.label())
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(Spacing.s6)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: Spacing.s6))
        .overlay {
            RoundedRectangle(cornerRadius: Spacing.s6)
                .strokeBorder(.white.opacity(0.12))
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.s2) {
            Button("Send feedback") {
                if FeedbackHelper.canSendMail {
                    showMailCompose = true
                } else {
                    feedbackReporter.open(.email)
                }
            }
            .font(Typography.label())
            .frame(minHeight: 44)
            .accessibilityIdentifier("reviewIntroduction.feedback")

            Button(action: continueToReview) {
                Group {
                    if requestAttempted {
                        Text("Write a review")
                    } else {
                        Text("Continue")
                    }
                }
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.white, in: Capsule())
            }
            .accessibilityHint(requestAttempted
                ? Text("Opens the App Store review page")
                : Text("Requests Apple’s optional rating dialog"))
            .accessibilityIdentifier("reviewIntroduction.continue")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.s6)
        .padding(.bottom, Spacing.s4)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
    }

    private func continueToReview() {
        guard scenePhase == .active else { return }
        if requestAttempted {
            openURL(storeURL) { accepted in
                if !accepted { showStoreFailure = true }
            }
        } else {
            requestAttempted = true
            ReviewManager.shared.didRequestReview()
            requestReview()
        }
    }
}
#endif
