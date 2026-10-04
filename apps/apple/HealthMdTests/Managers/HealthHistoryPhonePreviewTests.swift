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
        XCTAssertFalse(publications.isEmpty, "Busy requests should publish conservative evidence")
        XCTAssertTrue(publications.allSatisfy { $0.evidenceSource == "assessment_not_completed" })

        let beforeLateCompletion = publications
        provider.resumeAll()
        for task in tasks { await task.value }
        for _ in 0..<200 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(publications, beforeLateCompletion, "Late results cannot replace current evidence")

        provider.suspend = false
        let fresh = await coordinator.assessPreview(worker: worker,
            notCompleted: assessment(scope: current, completed: false), scope: current,
            isCurrent: { true }) { await provider.assess(scope: current) }
        XCTAssertEqual(provider.callCount, 2, "Only genuine provider completion frees admission")
        XCTAssertEqual(fresh?.evidenceSource, "synthetic_provider")
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

    private final class SuspendedHistoryProvider {
        private(set) var callCount = 0
        var suspend = true
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func assess(scope: HealthHistoryScope) async -> HealthHistoryAssessment {
            callCount += 1
            if suspend { await withCheckedContinuation { continuations.append($0) } }
            return HealthHistoryAssessment(id: UUID(), assessedAt: scope.startDate, scope: scope,
                types: [], evidenceSource: "synthetic_provider")
        }

        func resumeAll() {
            let owned = continuations
            continuations = []
            for continuation in owned { continuation.resume() }
        }
    }
}
