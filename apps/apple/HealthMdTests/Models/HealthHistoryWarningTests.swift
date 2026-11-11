import XCTest
@testable import HealthMd

final class HealthHistoryWarningTests: XCTestCase {
    private let boundary = Date(timeIntervalSince1970: 1_800_000_000)

    private func assessment(_ access: [HealthHistoryAccess], evidence: String = "HKHealthStore.earliestAuthorizedSampleDate(for:)") -> HealthHistoryAssessment {
        let scope = HealthHistoryScope(metricIDs: ["steps"], startDate: boundary.addingTimeInterval(-86400),
            endDate: boundary.addingTimeInterval(86400), timeZoneIdentifier: "UTC", allAvailable: true, profileID: nil)
        return HealthHistoryAssessment(id: UUID(), assessedAt: boundary, scope: scope,
            types: access.enumerated().map { index, value in
                HealthHistoryTypeAssessment(id: "type-\(index)", directMetricIDs: ["steps"],
                    dependencyMetricIDs: [], dependencyReasons: [], access: value)
            }, evidenceSource: evidence)
    }

    func testUnavailableFailureAndUnassessedDoNotClaimAnAPIReturnedNoBoundary() {
        for access: HealthHistoryAccess in [.apiUnavailable, .assessmentFailed, .unassessed(reason: "special_api_eligibility_unverified")] {
            let result = assessment([access])
            XCTAssertTrue(result.needsWarning)
            XCTAssertTrue(result.warningMessage.contains("could not check"))
            XCTAssertFalse(result.warningMessage.contains("no boundary is returned"))
            XCTAssertFalse(result.warningMessage.contains("OS 27"))
        }
    }

    func testSuccessfulOmissionStillExplainsAuthorizationAmbiguity() {
        XCTAssertTrue(assessment([.unknown]).warningMessage.contains("no boundary is returned"))
    }

    func testMixedUnknownAndUnavailableDoesNotImplyEveryTypeWasChecked() {
        XCTAssertTrue(assessment([.unknown, .apiUnavailable]).warningMessage.contains("could not check"))
    }

    func testKnownLimitationTakesPriorityOverUnavailableSibling() {
        let result = assessment([.apiUnavailable, .limited(sampleEndBoundary: boundary)])
        XCTAssertTrue(result.warningMessage.contains("limits the history"))
    }

    func testIncompleteAssessmentTakesPriorityOverGenericFallback() {
        let result = assessment([.apiUnavailable], evidence: "assessment_not_completed")
        XCTAssertTrue(result.warningMessage.contains("did not finish"))
    }
}
