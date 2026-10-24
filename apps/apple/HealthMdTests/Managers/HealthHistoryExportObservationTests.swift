import Foundation
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

final class HealthHistoryExportObservationTests: XCTestCase {
    func testAdmissionEvidencePreservesScopeAndAmbiguousOutcomes() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let boundary = start.addingTimeInterval(100.125)
        let scope = HealthHistoryScope(metricIDs: ["steps", "heart_rate_avg"], startDate: start,
            endDate: start.addingTimeInterval(86400), timeZoneIdentifier: "America/Puerto_Rico",
            allAvailable: true, profileID: nil, rangeSemantics: .ownerDates)
        let assessment = HealthHistoryAssessment(id: UUID(), assessedAt: start, scope: scope,
            types: [
                .init(id: "steps_type", directMetricIDs: ["steps"], dependencyMetricIDs: [],
                      dependencyReasons: [], access: .limited(sampleEndBoundary: boundary)),
                .init(id: "heart_type", directMetricIDs: ["heart_rate_avg"], dependencyMetricIDs: [],
                      dependencyReasons: [], access: .unknown)
            ])
        let operation = UUID(), source = UUID(), destination = UUID()
        let observation = try assessment.exportObservation(operationID: operation,
            requestBindingSHA256: String(repeating: "a", count: 64),
            sourceInstallationID: source, destinationInstallationID: destination)
        XCTAssertEqual(observation.operationID, operation.uuidString.lowercased())
        XCTAssertEqual(observation.sourceInstallationID, source.uuidString.lowercased())
        XCTAssertEqual(observation.destinationInstallationID, destination.uuidString.lowercased())
        XCTAssertEqual(observation.requestedStart, CanonicalRFC3339UTC.string(from: start))
        XCTAssertEqual(observation.types.map(\.outcome), ["unknown", "limited"])
        XCTAssertEqual(observation.types.last?.sampleEndBoundary, CanonicalRFC3339UTC.string(from: boundary))
        XCTAssertTrue(observation.allAvailable)
        XCTAssertEqual(observation.rangeSemantics, "owner_dates")
        XCTAssertEqual(try JSONDecoder().decode(ExportHistoryObservation.self,
            from: JSONEncoder().encode(observation)), observation)
    }

    func testNotCompletedRemainsUnassessedAndInvalidDatesFailWithoutTrapping() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let scope = HealthHistoryScope(metricIDs: ["steps"], startDate: date, endDate: date,
            timeZoneIdentifier: "UTC", allAvailable: false, profileID: nil)
        func assessment(at observedAt: Date) -> HealthHistoryAssessment {
            HealthHistoryAssessment(id: UUID(), assessedAt: observedAt, scope: scope,
                types: [.init(id: "steps_type", directMetricIDs: ["steps"], dependencyMetricIDs: [],
                    dependencyReasons: [], access: .unassessed(reason: "assessment_not_completed"))],
                evidenceSource: "assessment_not_completed")
        }
        let observation = try assessment(at: date).exportObservation(operationID: UUID(),
            requestBindingSHA256: String(repeating: "a", count: 64))
        XCTAssertEqual(observation.evidenceMethod, "assessment_not_completed")
        XCTAssertEqual(observation.types.first?.outcome, "unassessed")
        XCTAssertNil(observation.sourceInstallationID)
        XCTAssertThrowsError(try assessment(at: Date(timeIntervalSince1970: 1e300))
            .exportObservation(operationID: UUID(), requestBindingSHA256: String(repeating: "a", count: 64)))
        XCTAssertThrowsError(try assessment(at: Date(timeIntervalSince1970: .nan))
            .exportObservation(operationID: UUID(), requestBindingSHA256: String(repeating: "a", count: 64)))
    }
}
