import Foundation
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

@MainActor
final class HealthHistoryExportAdmissionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func request() -> DirectExportRequest {
        DirectExportRequest(jobID: UUID(), createdAt: date,
            dateSelection: .exact(start: "2023-11-14", end: "2023-11-15"),
            responseMode: .rawJSON, rawProfile: .healthDataProjection,
            canonicalSelection: .init(metricIDs: ["steps"], detailLevel: .summary))
    }

    private func scope(_ request: DirectExportRequest) throws -> HealthHistoryScope {
        try HealthHistoryExportAdmission.scope(for: request,
            resolvedDates: [date, date.addingTimeInterval(86400)], metricIDs: ["steps"], timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private func assessment(_ scope: HealthHistoryScope, pending: Bool) -> HealthHistoryAssessment {
        HealthHistoryAssessment(id: UUID(), assessedAt: date, scope: scope,
            types: [.init(id: "steps_type", directMetricIDs: ["steps"], dependencyMetricIDs: [], dependencyReasons: [],
                access: pending ? .unassessed(reason: "assessment_not_completed") : .limited(sampleEndBoundary: date))],
            evidenceSource: pending ? "assessment_not_completed" : "synthetic_ui_fixture")
    }

    func testExplicitOriginalBoundsAreNotClampedToResolvedReadableDays() throws {
        let original = request()
        let limited = try HealthHistoryExportAdmission.scope(for: original,
            resolvedDates: [date.addingTimeInterval(86400)], metricIDs: ["steps"], timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(CanonicalRFC3339UTC.string(from: limited.startDate), "2023-11-14T00:00:00.000000000Z")
        XCTAssertEqual(CanonicalRFC3339UTC.string(from: limited.endDate), "2023-11-15T00:00:00.000000000Z")
        XCTAssertFalse(limited.allAvailable)
        let all = DirectExportRequest(jobID: UUID(), createdAt: date, dateSelection: .allAvailable,
            responseMode: .rawJSON, rawProfile: .canonicalSourceRecordsV1)
        let allScope = try scope(all)
        XCTAssertTrue(allScope.allAvailable)
        XCTAssertEqual(allScope.startDate, date)
        XCTAssertEqual(allScope.endDate, date.addingTimeInterval(86400))
    }

    func testDeadlineAndRetryRetainOnePhysicalOwnerAndFrozenEvidence() async throws {
        let request = request(), binding = DirectPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID())
        let scope = try scope(request)
        let worker = HealthHistoryAssessmentWorker(logicalDeadline: 0.03)
        let admission = HealthHistoryExportAdmission(worker: worker)
        var calls = 0
        var continuation: CheckedContinuation<HealthHistoryAssessment, Never>?
        let pending = assessment(scope, pending: true), completed = assessment(scope, pending: false)
        let first = Task { @MainActor in
            try await admission.observe(scope: scope, operationID: request.jobID, requestBindingSHA256: String(repeating: "a", count: 64),
                peerBinding: binding, notCompleted: pending, operation: {
                    calls += 1
                    return await withCheckedContinuation { continuation = $0 }
                })
        }
        defer { continuation?.resume(returning: completed) }
        let frozen = try await first.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(frozen.evidenceMethod, "assessment_not_completed")
        XCTAssertTrue(worker.hasUnresolvedPhysicalOperation)
        let retry = try await admission.observe(scope: scope, operationID: UUID(), requestBindingSHA256: String(repeating: "b", count: 64),
            peerBinding: binding, notCompleted: pending, operation: { calls += 1; return completed })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(retry.evidenceMethod, "assessment_not_completed")
        continuation?.resume(returning: completed)
        continuation = nil
        for _ in 0..<200 {
            if !worker.hasUnresolvedPhysicalOperation { break }
            await Task.yield()
        }
        XCTAssertFalse(worker.hasUnresolvedPhysicalOperation)
        XCTAssertEqual(frozen.types.first?.outcome, "unassessed")
        XCTAssertEqual(retry.types.first?.outcome, "unassessed")
    }

    func testCancelledAdmissionDoesNotStartProviderOrProduceObservation() async throws {
        let request = request(), scope = try scope(request)
        let admission = HealthHistoryExportAdmission()
        var calls = 0
        let task = Task { @MainActor in
            try await admission.observe(scope: scope, operationID: request.jobID, requestBindingSHA256: String(repeating: "a", count: 64),
                peerBinding: .init(sourceInstallationID: UUID(), destinationInstallationID: UUID()),
                notCompleted: assessment(scope, pending: true), operation: { calls += 1; return self.assessment(scope, pending: false) })
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled admission returned evidence") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 0)
    }

    func testObservedResumeRequiresNegotiationAndLegacyJobIsNotBackfilled() async throws {
        let request = request(), scope = try scope(request)
        let binding = DirectPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID())
        let fingerprint = try DirectRequestFingerprint.make(for: request)
        let observation = try await HealthHistoryExportAdmission().observe(scope: scope, operationID: request.jobID,
            requestBindingSHA256: fingerprint.sha256, peerBinding: binding, notCompleted: assessment(scope, pending: true),
            operation: { self.assessment(scope, pending: false) })
        func accepted(_ observation: ExportHistoryObservation?) -> DirectExportAccepted {
            .init(jobID: request.jobID, acceptedAt: date, peerBinding: binding,
                resolvedDateIdentifiers: ["2023-11-14", "2023-11-15"], sourceTimeZoneIdentifier: scope.timeZoneIdentifier,
                resolvedCanonicalSelection: request.canonicalSelection, historyObservation: observation)
        }
        let session = try DirectTransferSession(sessionID: UUID(), jobID: request.jobID, requestFingerprint: fingerprint,
            peerBinding: binding, partitionTargetBytes: DirectTransferLimits.minimumPartitionBytes, createdAt: date)
        XCTAssertNoThrow(try HealthHistoryExportAdmission.validateResume(request: request, accepted: accepted(observation),
            session: session, historyRequired: true, negotiatedVersion: 1))
        XCTAssertThrowsError(try HealthHistoryExportAdmission.validateResume(request: request, accepted: accepted(observation),
            session: session, historyRequired: true, negotiatedVersion: nil))
        XCTAssertThrowsError(try HealthHistoryExportAdmission.validateResume(request: request, accepted: accepted(nil),
            session: session, historyRequired: true, negotiatedVersion: 1))
        XCTAssertThrowsError(try HealthHistoryExportAdmission.validateResume(request: request, accepted: accepted(observation),
            session: session, historyRequired: false, negotiatedVersion: 1))
        XCTAssertNoThrow(try HealthHistoryExportAdmission.validateResume(request: request, accepted: accepted(nil),
            session: session, historyRequired: false, negotiatedVersion: 1))
    }
    func testObservedCaptureRejectsChangedMetricsDatesAndTimeZone() async throws {
        let request = request(), scope = try scope(request)
        let binding = DirectPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID())
        let observation = try await HealthHistoryExportAdmission().observe(scope: scope, operationID: request.jobID,
            requestBindingSHA256: String(repeating: "a", count: 64), peerBinding: binding,
            notCompleted: assessment(scope, pending: true), operation: { self.assessment(scope, pending: false) })
        let accepted = DirectExportAccepted(jobID: request.jobID, acceptedAt: date, peerBinding: binding,
            resolvedDateIdentifiers: ["2023-11-14", "2023-11-15"], sourceTimeZoneIdentifier: scope.timeZoneIdentifier,
            resolvedCanonicalSelection: request.canonicalSelection, historyObservation: observation)
        let dates = [scope.startDate, scope.endDate]
        func validate(metrics: Set<String> = ["steps"], capture: [Date]? = nil,
                      original: [Date]? = nil, zone: String? = "GMT") throws {
            try HealthHistoryExportAdmission.validateCaptureScope(request: request, accepted: accepted,
                metricIDs: metrics, requestedDates: capture ?? dates, originalDates: original ?? dates,
                timeZoneIdentifier: zone)
        }
        XCTAssertNoThrow(try validate())
        XCTAssertThrowsError(try validate(metrics: ["active_energy"]))
        XCTAssertThrowsError(try validate(capture: [scope.startDate]))
        XCTAssertThrowsError(try validate(original: [scope.endDate]))
        XCTAssertThrowsError(try validate(original: dates + [scope.endDate.addingTimeInterval(86400)]))
        XCTAssertThrowsError(try validate(zone: "America/New_York"))
        XCTAssertThrowsError(try validate(zone: nil))
        let legacy = DirectExportAccepted(jobID: request.jobID, acceptedAt: date, peerBinding: binding,
            resolvedDateIdentifiers: accepted.resolvedDateIdentifiers, sourceTimeZoneIdentifier: scope.timeZoneIdentifier)
        XCTAssertNoThrow(try HealthHistoryExportAdmission.validateCaptureScope(request: request, accepted: legacy,
            metricIDs: [], requestedDates: [], originalDates: [], timeZoneIdentifier: nil))
    }

}
