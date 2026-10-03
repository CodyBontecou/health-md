import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class HealthHistoryAssessmentWorkerTests: XCTestCase {
    private func scope() -> HealthHistoryScope {
        HealthHistoryScope(metricIDs: ["steps"], startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400), timeZoneIdentifier: "UTC",
            allAvailable: false, profileID: nil)
    }

    func testActualProviderSuccessAndDeadlineKeepOnePhysicalOwnerWithoutLateRelabeling() async {
        let store = FakeHealthStore()
        let sut = HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "HistoryWorkerTests")!)
        let successWorker = HealthHistoryAssessmentWorker()
        let request = scope()
        let fallback = sut.historyAssessmentNotCompleted(scope: request)
        let identifier = HKQuantityTypeIdentifier.stepCount.rawValue
        let boundary = request.startDate
        store.historyOutcome = .boundaries([identifier: boundary])
        let positive = await successWorker.assess(notCompleted: fallback) { await sut.assessHistoryAccess(scope: request) }
        XCTAssertEqual(positive.access(for: identifier), .limited(sampleEndBoundary: boundary))
        XCTAssertFalse(successWorker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(store.historyRequestedIdentifiers.count, 1)

        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 0.05)
        let entered = expectation(description: "uncooperative provider entered")
        let returned = expectation(description: "logical deadline returned")
        let gate = HistoryTestSuspension(entered: entered)
        store.historySuspension = { await gate.wait() }
        var observation: HealthHistoryAssessment?
        let task = Task { @MainActor in
            observation = await worker.assess(notCompleted: fallback) { await sut.assessHistoryAccess(scope: request) }
            returned.fulfill()
        }
        defer { gate.resume(); task.cancel() }
        await fulfillment(of: [entered, returned], timeout: 1)
        XCTAssertEqual(observation?.id, fallback.id)
        XCTAssertEqual(observation?.access(for: identifier), .unassessed(reason: "assessment_not_completed"))
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        let busy = await worker.assess(notCompleted: fallback) { XCTFail("No multiplied SDK orphan"); return positive }
        XCTAssertEqual(busy.id, fallback.id)
        XCTAssertEqual(store.historyRequestedIdentifiers.count, 2)
        gate.resume()
        for _ in 0..<100 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(observation?.id, fallback.id, "Late SDK completion must not replace returned evidence")
        store.historySuspension = nil
        let next = await worker.assess(notCompleted: fallback) { await sut.assessHistoryAccess(scope: request) }
        XCTAssertEqual(next.access(for: identifier), .limited(sampleEndBoundary: boundary))
        XCTAssertEqual(store.historyRequestedIdentifiers.count, 3)
    }

    func testCancellationReleasesLogicalCallerButDoesNotClaimSDKStopped() async {
        let store = FakeHealthStore()
        let sut = HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "HistoryWorkerCancelTests")!)
        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 5)
        let request = scope()
        let entered = expectation(description: "provider suspended")
        let returned = expectation(description: "cancelled logical caller released")
        let gate = HistoryTestSuspension(entered: entered)
        store.historySuspension = { await gate.wait() }
        let fallback = sut.historyAssessmentNotCompleted(scope: request)
        let task = Task { @MainActor in
            let result = await worker.assess(notCompleted: fallback) { await sut.assessHistoryAccess(scope: request) }
            XCTAssertEqual(result.id, fallback.id)
            returned.fulfill()
        }
        defer { gate.resume(); task.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        task.cancel()
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(store.historyRequestedIdentifiers.count, 1)
        worker.cancelLogicalWaiter()
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        gate.resume()
        for _ in 0..<100 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
    }
}

/// A real checked-continuation await that intentionally does not observe task
/// cancellation. Synthetic only; no claim the physical HealthKit SDK hangs.
@MainActor
final class HistoryTestSuspension {
    private let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    init(entered: XCTestExpectation) { self.entered = entered }
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func resume() {
        let owned = continuation
        continuation = nil
        owned?.resume()
    }
}
