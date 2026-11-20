#if os(iOS)
import XCTest
@testable import HealthMd

/// Make it daily's Restore Purchase for a returning user who reinstalled.
@MainActor
final class OnboardingRestoreOutcomeTests: XCTestCase {
    func testUnlockedAccessIsARestoreEvenWhenAnErrorLingers() {
        XCTAssertEqual(OnboardingRestoreOutcome.resolve(isUnlocked: true, error: nil), .restored)
        XCTAssertEqual(OnboardingRestoreOutcome.resolve(isUnlocked: true, error: "stale"), .restored)
    }

    func testNothingFoundShowsTheRestoreError() {
        let message = PurchaseManager.restoreNotFoundMessage
        XCTAssertEqual(OnboardingRestoreOutcome.resolve(isUnlocked: false, error: message), .failed(message))
    }

    func testCancelledSignInIsNotAFailure() {
        XCTAssertEqual(OnboardingRestoreOutcome.resolve(isUnlocked: false, error: nil), .cancelled)
        XCTAssertEqual(OnboardingRestoreOutcome.resolve(isUnlocked: false, error: ""), .cancelled)
    }

    func testRestoringBlocksTheTrialAndRestoreButtons() {
        XCTAssertTrue(OnboardingTrialState.restoring.isBusy)
        XCTAssertTrue(OnboardingTrialState.purchasing.isBusy)
        XCTAssertFalse(OnboardingTrialState.idle.isBusy)
        XCTAssertFalse(OnboardingTrialState.failed("x").isBusy)
    }
}
#endif
