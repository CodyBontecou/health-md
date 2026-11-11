import Foundation
import Testing
@testable import HealthMd

@MainActor
struct ReviewIntroductionPolicyTests {
    private let defaults = FakeUserDefaults()
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func manager(after days: Double = 0) -> ReviewManager {
        let date = start.addingTimeInterval(days * 86_400)
        return ReviewManager(defaults: defaults, now: { date })
    }

    private func establishUsage(_ manager: ReviewManager) {
        for _ in 0..<3 { _ = manager.recordSuccessfulExport() }
    }

    @Test func firstRunCannotClaimAnIntroduction() {
        #expect(!manager().claimIntroduction(forRelease: "3.5.0"))
    }

    @Test func dismissalStillReservesCooldownAcrossRelaunch() {
        let first = manager()
        establishUsage(first)
        #expect(first.claimIntroduction())
        #expect(!manager().claimIntroduction())
        #expect(!manager(after: 119).claimIntroduction(forRelease: "3.5.0"))
        #expect(manager(after: 120).claimIntroduction(forRelease: "3.5.0"))
    }

    @Test func nativeRequestAttemptExtendsCooldownWithoutAssumingSubmission() {
        let first = manager()
        establishUsage(first)
        #expect(first.claimIntroduction())
        manager(after: 1).didRequestReview()
        #expect(!manager(after: 120).claimIntroduction())
        #expect(manager(after: 121).claimIntroduction())
    }

    @Test func releaseFamilyIsNotRepeatedEvenAfterCooldown() {
        let first = manager()
        establishUsage(first)
        #expect(first.claimIntroduction(forRelease: "3.5.0"))
        #expect(!manager(after: 121).claimIntroduction(forRelease: "3.5.9"))
        #expect(manager(after: 121).claimIntroduction(forRelease: "3.6.0"))
    }

    @Test func blockedReleaseDoesNotConsumeTheNextRelease() {
        let first = manager()
        establishUsage(first)
        #expect(first.claimIntroduction(forRelease: "3.5.0"))
        #expect(!manager(after: 10).claimIntroduction(forRelease: "3.6.0"))
        #expect(manager(after: 120).claimIntroduction(forRelease: "3.6.0"))
    }

    @Test func clockRollbackDoesNotBypassCooldown() {
        let first = manager()
        establishUsage(first)
        #expect(first.claimIntroduction())
        #expect(!manager(after: -1).claimIntroduction())
    }

    @Test(arguments: ["", "3", "3..0", "3.a.0", "-3.5.0", "3.5.0.1"])
    func invalidReleaseCannotClaim(_ version: String) {
        let first = manager()
        establishUsage(first)
        #expect(!first.claimIntroduction(forRelease: version))
        #expect(first.claimIntroduction(forRelease: "3.5.0"))
    }

    @Test func releaseNotesSkipPatchesAndAllowMinorAndMajorUpdates() {
        #expect(!ReviewManager.shouldPresentReleaseNotes(current: "3.4.4", lastSeen: "3.4.3"))
        #expect(!ReviewManager.shouldPresentReleaseNotes(current: "3.4.4", lastSeen: "3.4.4"))
        #expect(ReviewManager.shouldPresentReleaseNotes(current: "3.5.0", lastSeen: "3.4.4"))
        #expect(ReviewManager.shouldPresentReleaseNotes(current: "4.0.0", lastSeen: "3.5.0"))
        #expect(ReviewManager.shouldPresentReleaseNotes(current: "3.5.0", lastSeen: nil))
    }
}
