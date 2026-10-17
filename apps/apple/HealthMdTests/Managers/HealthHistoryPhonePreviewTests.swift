import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class HealthHistoryPhonePreviewTests: XCTestCase {
    func testRepeatedScopeAndLifecycleInvalidationsRetainOnePhysicalProviderUntilReturn() async {
        let coordinator = HealthHistoryAssessmentCoordinator()
        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 60)
        let provider = SuspendedHistoryProvider()
        let original = scope(metrics: ["steps"])
        var current = original
        var publications: [HealthHistoryAssessment] = []
        var tasks: [Task<Void, Never>] = []

        func startPreview() {
            let request = current
            tasks.append(Task { @MainActor in
                let result = await coordinator.assessPreview(worker: worker,
                    notCompleted: assessment(scope: request, completed: false), scope: request,
                    isCurrent: { current == request }) {
                        await provider.assess(scope: request)
                    }
                if let result { publications.append(result) }
            })
        }
        startPreview()
        for _ in 0..<200 {
            if provider.callCount > 0 { break }
            await Task.yield()
        }
        XCTAssertEqual(provider.callCount, 1)

        // Scope edits, foreground refresh and A -> B -> A all invalidate the
        // logical owner. The synthetic provider deliberately ignores cancellation.
        for metrics: Set<String> in [["heart_rate_avg"], ["sleep_total"], ["steps"], ["steps"]] {
            coordinator.invalidate()
            worker.cancelLogicalWaiter()
            tasks.last?.cancel()
            current = scope(metrics: metrics)
            startPreview()
            for _ in 0..<20 { await Task.yield() }
        }
        XCTAssertEqual(provider.callCount, 1, "Invalidation must not multiply physical metadata calls")
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        XCTAssertTrue(publications.isEmpty, "The latest preview waits within its deadline for physical admission")

        provider.suspend = false
        provider.resumeAll()
        for task in tasks { await task.value }
        for _ in 0..<200 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(provider.callCount, 2, "Retirement admits one fresh assessment for the latest scope")
        XCTAssertEqual(publications.count, 1, "Obsolete and cancelled requests cannot publish")
        XCTAssertEqual(publications.first?.scope, current)
        XCTAssertEqual(publications.first?.evidenceSource, "synthetic_provider")
        XCTAssertEqual(publications.first?.hasIntersectingLimit, true)
        XCTAssertTrue(publications.first?.warningMessage.contains("Earlier data is unknown, not missing") == true)

        provider.suspend = false
        let fresh = await coordinator.assessPreview(worker: worker,
            notCompleted: assessment(scope: current, completed: false), scope: current,
            isCurrent: { true }) { await provider.assess(scope: current) }
        XCTAssertEqual(provider.callCount, 3, "Only genuine provider completion frees admission")
        XCTAssertEqual(fresh?.evidenceSource, "synthetic_provider")
    }

    func testWaitingPreviewDeadlineDoesNotMultiplyCallsOrPublishLateResults() async {
        let coordinator = HealthHistoryAssessmentCoordinator()
        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 0.05)
        let provider = SuspendedHistoryProvider()
        let request = scope(metrics: ["steps"])
        let first = Task { @MainActor in
            await worker.assess(notCompleted: assessment(scope: request, completed: false)) {
                await provider.assess(scope: request)
            }
        }
        for _ in 0..<200 {
            if provider.callCount > 0 { break }
            await Task.yield()
        }
        XCTAssertEqual(provider.callCount, 1)
        worker.cancelLogicalWaiter()
        first.cancel()

        let result = await coordinator.assessPreview(worker: worker,
            notCompleted: assessment(scope: request, completed: false), scope: request,
            isCurrent: { true }) { await provider.assess(scope: request) }
        XCTAssertEqual(result?.evidenceSource, "assessment_not_completed")
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        provider.resumeAll()
        _ = await first.value
        for _ in 0..<200 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(provider.callCount, 1, "Expired admission cannot start a late replacement")
        XCTAssertEqual(result?.evidenceSource, "assessment_not_completed")
    }

    func testNewestPreviewSupersedesLogicalWaiterBeforeTaskCancellationIsDelivered() async {
        let coordinator = HealthHistoryAssessmentCoordinator()
        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 5)
        let provider = SuspendedHistoryProvider()
        let request = scope(metrics: ["steps"])
        let first = Task { @MainActor in
            await coordinator.assessPreview(worker: worker,
                notCompleted: assessment(scope: request, completed: false), scope: request,
                isCurrent: { true }) { await provider.assess(scope: request) }
        }
        for _ in 0..<200 {
            if provider.callCount > 0 { break }
            await Task.yield()
        }
        XCTAssertEqual(provider.callCount, 1)
        // Deliberately omit explicit worker/task cancellation. Beginning the
        // replacement invalidates the old coordinator token first, just as a
        // new SwiftUI task may run before its predecessor's onCancel hop.
        let replacement = Task { @MainActor in
            await coordinator.assessPreview(worker: worker,
                notCompleted: assessment(scope: request, completed: false), scope: request,
                isCurrent: { true }) { await provider.assess(scope: request) }
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(provider.callCount, 1)
        provider.suspend = false
        provider.resumeAll()
        let oldResult = await first.value
        let result = await replacement.value
        XCTAssertNil(oldResult)
        XCTAssertEqual(result?.hasIntersectingLimit, true)
        XCTAssertEqual(provider.callCount, 2)
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
    }

    func testCancelledWaitingPreviewCannotStartAfterProviderRetires() async {
        let coordinator = HealthHistoryAssessmentCoordinator()
        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 5)
        let provider = SuspendedHistoryProvider()
        let request = scope(metrics: ["steps"])
        let first = Task { @MainActor in
            await worker.assess(notCompleted: assessment(scope: request, completed: false)) {
                await provider.assess(scope: request)
            }
        }
        for _ in 0..<200 {
            if provider.callCount > 0 { break }
            await Task.yield()
        }
        XCTAssertEqual(provider.callCount, 1)
        worker.cancelLogicalWaiter()
        first.cancel()
        let replacement = Task { @MainActor in
            await coordinator.assessPreview(worker: worker,
                notCompleted: assessment(scope: request, completed: false), scope: request,
                isCurrent: { true }) { await provider.assess(scope: request) }
        }
        for _ in 0..<20 { await Task.yield() }
        replacement.cancel()
        let result = await replacement.value
        XCTAssertNil(result)
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        provider.resumeAll()
        _ = await first.value
        for _ in 0..<200 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testExecutionAdmissionRemainsImmediateWhilePhysicalProviderIsUnresolved() async {
        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 5)
        let provider = SuspendedHistoryProvider()
        let request = scope(metrics: ["steps"])
        let first = Task { @MainActor in
            await worker.assess(notCompleted: assessment(scope: request, completed: false)) {
                await provider.assess(scope: request)
            }
        }
        for _ in 0..<200 {
            if provider.callCount > 0 { break }
            await Task.yield()
        }
        XCTAssertEqual(provider.callCount, 1)
        worker.cancelLogicalWaiter()
        let result = await worker.assess(notCompleted: assessment(scope: request, completed: false)) {
            XCTFail("Execution must not queue another provider call")
            return await provider.assess(scope: request)
        }
        XCTAssertEqual(result.evidenceSource, "assessment_not_completed")
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(provider.callCount, 1)
        provider.resumeAll()
        _ = await first.value
        for _ in 0..<200 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(provider.callCount, 1)
    }

    private func scope(metrics: Set<String>) -> HealthHistoryScope {
        HealthHistoryScope(metricIDs: metrics, startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400), timeZoneIdentifier: "UTC",
            allAvailable: false, profileID: nil, rangeSemantics: .ownerDates)
    }

    private func assessment(scope: HealthHistoryScope, completed: Bool) -> HealthHistoryAssessment {
        HealthHistoryAssessment(id: UUID(), assessedAt: scope.startDate, scope: scope,
            types: [HealthHistoryTypeAssessment(id: "synthetic_type", directMetricIDs: Array(scope.metricIDs),
                dependencyMetricIDs: [], dependencyReasons: [],
                access: completed ? .unknown : .unassessed(reason: "assessment_not_completed"))],
            evidenceSource: completed ? "synthetic_provider" : "assessment_not_completed")
    }

    @MainActor private final class SuspendedHistoryProvider {
        private(set) var callCount = 0
        var suspend = true
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func assess(scope: HealthHistoryScope) async -> HealthHistoryAssessment {
            callCount += 1
            if suspend { await withCheckedContinuation { continuations.append($0) } }
            let cancelled = Task.isCancelled
            return HealthHistoryAssessment(id: UUID(), assessedAt: scope.startDate, scope: scope,
                types: [HealthHistoryTypeAssessment(id: "synthetic_type",
                    directMetricIDs: Array(scope.metricIDs), dependencyMetricIDs: [], dependencyReasons: [],
                    access: cancelled ? .unassessed(reason: "assessment_not_completed")
                        : .limited(sampleEndBoundary: Date(timeIntervalSince1970: 1_893_456_000)))],
                evidenceSource: cancelled ? "assessment_not_completed" : "synthetic_provider")
        }

        func resumeAll() {
            let owned = continuations
            continuations = []
            for continuation in owned { continuation.resume() }
        }
    }
}
