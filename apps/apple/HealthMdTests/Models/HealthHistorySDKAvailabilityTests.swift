import HealthKit
import XCTest
@testable import HealthMd

@MainActor
final class HealthHistorySDKAvailabilityTests: XCTestCase {
    func testAdapterRejectsBoundaryReadsWithoutSDKSupport() async throws {
        let adapter = SystemHealthStoreAdapter()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))

        XCTAssertFalse(adapter.supportsHistoryAuthorizationBoundaries)
        do {
            _ = try await adapter.earliestAuthorizedSampleDates(for: [type])
            XCTFail("Expected unsupported history-boundary assessment")
        } catch {
            let failure = error as NSError
            XCTAssertEqual(failure.domain, "HealthMd.HealthKitCapability")
            XCTAssertEqual(failure.code, 27)
            XCTAssertEqual(
                failure.localizedDescription,
                "Health history authorization boundaries are unavailable in this build."
            )
        }
    }

    func testUnavailableAssessmentPublishesHealthFreeReceiptWithoutReads() async throws {
        let store = FakeHealthStore()
        store.historyAuthorizationBoundariesSupported = false
        let suite = "HealthHistorySDKAvailabilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("synthetic-sentinel", forKey: "unrelated-export-preference")
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let preferencesBeforeAssessment = defaults.persistentDomain(forName: suite) as NSDictionary?

        let assessment = await manager.assessHistoryAuthorization(
            forMetricIDs: ["steps"], publish: true
        )

        XCTAssertEqual(assessment.state, .apiUnavailable)
        XCTAssertEqual(assessment.assessedTypeIdentifiers, [HKQuantityTypeIdentifier.stepCount.rawValue])
        XCTAssertTrue(assessment.boundaries.isEmpty)
        XCTAssertNil(assessment.earliestAuthorizedSampleDate)
        XCTAssertNil(assessment.checkedAt)
        XCTAssertFalse(assessment.supportsUnqualifiedFullHistoryClaim)
        XCTAssertEqual(manager.historyAuthorizationAssessment, assessment)
        XCTAssertEqual(
            assessment.message,
            "This build cannot report limited HealthKit history boundaries. Full-history completeness is unverified."
        )
        XCTAssertTrue(store.historyAuthorizationReadTypes.isEmpty)
        XCTAssertTrue(store.queriedSumIdentifiers.isEmpty)
        XCTAssertTrue(store.quantitySampleQueries.isEmpty)
        XCTAssertTrue(store.queriedQuantityRecordIdentifiers.isEmpty)
        XCTAssertFalse(store.authRequested)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, preferencesBeforeAssessment)

        let receipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(assessment)) as? [String: Any]
        )
        XCTAssertEqual(receipt["schema"] as? String, "healthmd.history_authorization")
        XCTAssertEqual(receipt["schema_version"] as? Int, 1)
        XCTAssertEqual(receipt["state"] as? String, "api_unavailable")
        XCTAssertNil(receipt["checked_at"])
        XCTAssertEqual((receipt["boundaries"] as? [Any])?.count, 0)
    }

    func testEmptyBoundaryRequestAlsoFailsClosed() async {
        do {
            _ = try await SystemHealthStoreAdapter().earliestAuthorizedSampleDates(for: [])
            XCTFail("An empty request must not fabricate an unrestricted boundary result")
        } catch {
            XCTAssertEqual((error as NSError).domain, "HealthMd.HealthKitCapability")
            XCTAssertEqual((error as NSError).code, 27)
        }
    }

    func testReadableEarliestDateDoesNotQualifyAllAvailableWithoutBoundaryProof() {
        for state in [HealthHistoryAuthorizationState.apiUnavailable, .unknown, .limitedHistory] {
            let assessment = HealthHistoryAuthorizationAssessment(
                state: state, message: "Synthetic incomplete history assessment."
            )
            let discovery = makeDiscovery(assessment: assessment)

            XCTAssertTrue(discovery.isComplete)
            XCTAssertNotNil(discovery.earliestDate)
            XCTAssertFalse(discovery.supportsUnqualifiedFullHistoryClaim)
        }
    }

    func testAllAvailableRequiresBothCompleteDiscoveryAndCompleteAssessment() {
        let unrestricted = HealthHistoryAuthorizationAssessment(
            state: .fullHistory, message: "Synthetic supported unrestricted assessment."
        )
        XCTAssertTrue(makeDiscovery(assessment: unrestricted).supportsUnqualifiedFullHistoryClaim)
        XCTAssertFalse(makeDiscovery(
            assessment: unrestricted, failedTypeIdentifiers: ["synthetic-failed-type"]
        ).supportsUnqualifiedFullHistoryClaim)
        XCTAssertFalse(makeDiscovery(
            assessment: unrestricted, unresolvedMetricIDs: ["synthetic-unresolved-metric"]
        ).supportsUnqualifiedFullHistoryClaim)
        let unassessed = HealthHistoryAuthorizationAssessment(
            state: .fullHistory,
            unassessedMetricIDs: ["synthetic-unassessed-metric"],
            message: "Synthetic unassessed history scope."
        )
        XCTAssertFalse(makeDiscovery(assessment: unassessed).supportsUnqualifiedFullHistoryClaim)
    }

    func testSupportedFakeKeepsFullLimitedAndFailedAssessmentsDistinct() async throws {
        let store = FakeHealthStore()
        let suite = "HealthHistorySDKAvailabilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))

        let unrestricted = await manager.assessHistoryAuthorization(forMetricIDs: ["steps"])
        XCTAssertEqual(unrestricted.state, .fullHistory)
        XCTAssertTrue(unrestricted.supportsUnqualifiedFullHistoryClaim)
        XCTAssertTrue(unrestricted.message.contains("denied read"))

        store.authorizedHistoryBoundaries[type.identifier] = Date(timeIntervalSince1970: 0)
        let limited = await manager.assessHistoryAuthorization(forMetricIDs: ["steps"])
        XCTAssertEqual(limited.state, .limitedHistory)
        XCTAssertFalse(limited.supportsUnqualifiedFullHistoryClaim)

        store.errorForAuthorizedHistoryBoundaries = NSError(
            domain: "SyntheticBoundaryFailure", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synthetic-private-provider-error"]
        )
        let failed = await manager.assessHistoryAuthorization(forMetricIDs: ["steps"])
        XCTAssertEqual(failed.state, .unknown)
        XCTAssertFalse(failed.supportsUnqualifiedFullHistoryClaim)
        XCTAssertEqual(failed.message, "HealthKit could not report the selected history authorization boundary.")
    }

    private func makeDiscovery(
        assessment: HealthHistoryAuthorizationAssessment,
        failedTypeIdentifiers: [String] = [],
        unresolvedMetricIDs: [String] = []
    ) -> HealthKitEarliestDataDiscovery {
        HealthKitEarliestDataDiscovery(
            earliestDate: Date(timeIntervalSince1970: 0),
            queriedTypeIdentifiers: ["synthetic-readable-type"],
            snapshotOnlyTypeIdentifiers: [],
            failedTypeIdentifiers: failedTypeIdentifiers,
            unresolvedMetricIDs: unresolvedMetricIDs,
            historyAuthorization: assessment
        )
    }
}
