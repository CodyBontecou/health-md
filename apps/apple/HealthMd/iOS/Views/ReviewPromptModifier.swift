#if os(iOS)
import StoreKit
import SwiftUI

/// Asks StoreKit for a rating at a calm foreground moment, with no custom pre-prompt.
///
/// `pending` is raised only by a visible full success: a manual export, or the user
/// dismissing a scheduled-export result. The request waits until `canPresent` (no
/// export, paywall, alert, partial notice or sheet, onboarding done) has held for a
/// short delay with the scene active, then asks only if `ReviewManager` says the
/// usage threshold and cooldown allow it. Anything that interrupts the delay
/// cancels it; leaving the foreground drops the pending moment.
private struct ReviewPromptModifier: ViewModifier {
    @Binding var pending: Bool
    let canPresent: Bool

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    static let settleDelay: Duration = .milliseconds(1200)

    private var isPresentationAllowed: Bool {
        #if DEBUG
        if MarketingCapture.isActive { return false }
        if TestMode.isUITesting { return TestMode.reviewPromptScenario == "eligible" }
        #else
        if TestMode.isUITesting { return false }
        #endif
        return true
    }

    private var isReady: Bool {
        pending && canPresent && scenePhase == .active && isPresentationAllowed
    }

    func body(content: Content) -> some View {
        content
            .task(id: isReady) {
                guard isReady else { return }
                do {
                    try await Task.sleep(for: Self.settleDelay)
                } catch {
                    return
                }
                pending = false
                guard ReviewManager.shared.isEligibleForReviewRequest else { return }
                ReviewManager.shared.didRequestReview()
                requestReview()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { pending = false }
            }
            #if DEBUG
            .onAppear {
                if TestMode.isUITesting, TestMode.reviewPromptScenario == "eligible" {
                    ReviewManager.shared.seedEligibleForTesting()
                }
            }
            #endif
    }
}

extension View {
    /// Requests an App Store rating after a visible full success when nothing else
    /// is on screen. See `ReviewPromptModifier`.
    func reviewPrompt(pending: Binding<Bool>, canPresent: Bool) -> some View {
        modifier(ReviewPromptModifier(pending: pending, canPresent: canPresent))
    }
}
#endif
