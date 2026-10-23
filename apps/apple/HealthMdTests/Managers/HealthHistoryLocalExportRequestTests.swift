import Foundation
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

@MainActor
final class HealthHistoryLocalExportRequestTests: XCTestCase {
    private func request(settings: ExportSettingsSnapshot? = nil,
                         scope: HealthHistoryScope? = nil,
                         dates: [Date]? = nil,
                         operationID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000183")!,
                         destination: String = String(repeating: "a", count: 64),
                         target: HealthHistoryLocalExportRequest.Target = .localFiles,
                         sourceIDs: [String] = ["apple_health"]) throws -> HealthHistoryLocalExportRequest {
        let fixture = try makeObservedContextTestFixture()
        return try .init(operationID: operationID,
            scope: scope ?? .init(metricIDs: ["steps"], startDate: fixture.date, endDate: fixture.date,
                timeZoneIdentifier: "UTC", allAvailable: false, profileID: nil, rangeSemantics: .ownerDates),
            settings: settings ?? fixture.manifest.settingsSnapshot,
            captureDates: dates ?? [fixture.date], sourceIDs: sourceIDs, target: target,
            destinationBindingSHA256: destination)
    }

    func testOnlySetValuedSettingsAreSortedAndOrderedPresentationRetainsMeaning() throws {
        var settings = try makeObservedContextTestFixture().manifest.settingsSnapshot
        settings.exportFormats = [.json, .csv, .markdown]
        settings.metricSelection.enabledCategoryIDs = ["activity", "heart"]
        settings.formatCustomization.frontmatterConfig.placeholderFields = ["reflection", "notes"]
        let first = try request(settings: settings)
        for _ in 0..<20 {
            settings.exportFormats = Set([ExportFormat.markdown, .csv, .json].shuffled())
            settings.metricSelection.enabledCategoryIDs = Set(["heart", "activity"].shuffled())
            XCTAssertEqual(try request(settings: settings).canonicalData, first.canonicalData)
        }
        settings.formatCustomization.frontmatterConfig.placeholderFields.reverse()
        XCTAssertNotEqual(try request(settings: settings).requestBindingSHA256, first.requestBindingSHA256,
                          "Ordered renderer settings must not collapse to one binding")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: first.canonicalData) as? [String: Any])
        let encodedSettings = try JSONSerialization.data(withJSONObject: XCTUnwrap(object["settings"]))
        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: encodedSettings)
        settings.formatCustomization.frontmatterConfig.placeholderFields.reverse()
        XCTAssertEqual(decoded, settings, "The binding retains the complete capture settings")
        XCTAssertEqual(object["schema"] as? String, "healthmd.local_export_history_request")
        XCTAssertEqual(object["schema_version"] as? Int, 1)
    }

    func testOperationDestinationTargetAndOriginalRangeAreBound() throws {
        let first = try request()
        XCTAssertNotEqual(try request(operationID: UUID()).requestBindingSHA256, first.requestBindingSHA256)
        XCTAssertNotEqual(try request(destination: String(repeating: "b", count: 64)).requestBindingSHA256, first.requestBindingSHA256)
        XCTAssertNotEqual(try request(target: .apiEndpoint).requestBindingSHA256, first.requestBindingSHA256)
        let allTime = HealthHistoryScope(metricIDs: first.scope.metricIDs, startDate: first.scope.startDate,
            endDate: first.scope.endDate, timeZoneIdentifier: "UTC", allAvailable: true,
            profileID: nil, rangeSemantics: .ownerDates)
        XCTAssertNotEqual(try request(scope: allTime).requestBindingSHA256, first.requestBindingSHA256)
        let noon = HealthHistoryScope(metricIDs: first.scope.metricIDs,
            startDate: first.scope.startDate.addingTimeInterval(3600),
            endDate: first.scope.endDate.addingTimeInterval(3600), timeZoneIdentifier: "UTC",
            allAvailable: false, profileID: nil, rangeSemantics: .ownerDates)
        XCTAssertNotEqual(try request(scope: noon).requestBindingSHA256, first.requestBindingSHA256,
                          "Original requested instants are preserved while capture uses owner dates")
    }

    func testRejectsUnfrozenOrMismatchedCaptureAuthorityBeforeObservation() throws {
        let first = try request()
        var settings = first.settings
        settings.calendarTimeZoneIdentifier = "America/Los_Angeles"
        XCTAssertThrowsError(try request(settings: settings))
        settings = first.settings
        settings.appleExportEngineAuthorityIsFrozen = false
        XCTAssertThrowsError(try request(settings: settings))
        settings = first.settings
        settings.metricSelection.enabledMetricIDs.insert("active_energy")
        XCTAssertThrowsError(try request(settings: settings))
        XCTAssertThrowsError(try request(dates: []))
        XCTAssertThrowsError(try request(dates: [first.captureDates[0], first.captureDates[0]]))
        XCTAssertThrowsError(try request(dates: [first.captureDates[0].addingTimeInterval(1)]))
        XCTAssertThrowsError(try request(dates: [first.captureDates[0].addingTimeInterval(86400)]))
        XCTAssertThrowsError(try request(destination: "not-a-digest"))
        XCTAssertThrowsError(try request(sourceIDs: ["apple_health", "bad/source"]))
        XCTAssertThrowsError(try request(sourceIDs: ["whoop"]))
        XCTAssertThrowsError(try request(sourceIDs: ["apple_health", "apple_health"]))
    }

    func testObservationIsBoundToExactLocalAdmissionAndCannotBorrowAnotherScope() throws {
        let request = try request()
        let assessment = HealthHistoryAssessment(id: UUID(), assessedAt: Date(), scope: request.scope,
            types: [.init(id: "HKQuantityTypeIdentifierStepCount", directMetricIDs: ["steps"],
                          dependencyMetricIDs: [], dependencyReasons: [], access: .unknown)])
        let observation = try request.observation(from: assessment)
        XCTAssertEqual(observation.operationID, request.operationID.uuidString.lowercased())
        XCTAssertEqual(observation.requestBindingSHA256, request.requestBindingSHA256)
        XCTAssertEqual(observation.types.first?.outcome, "unknown")
        XCTAssertNil(observation.sourceInstallationID)
        XCTAssertNil(observation.destinationInstallationID)
        let otherScope = HealthHistoryScope(metricIDs: ["steps"], startDate: request.scope.startDate,
            endDate: request.scope.endDate, timeZoneIdentifier: "UTC", allAvailable: true,
            profileID: nil, rangeSemantics: .ownerDates)
        let other = HealthHistoryAssessment(id: UUID(), assessedAt: Date(), scope: otherScope, types: [])
        XCTAssertThrowsError(try request.observation(from: other))
    }
}
