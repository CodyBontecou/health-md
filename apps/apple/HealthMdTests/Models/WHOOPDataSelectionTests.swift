import Combine
import XCTest
@testable import HealthMd

@MainActor
final class WHOOPDataSelectionTests: XCTestCase {
    func testLegacyStateAndSnapshotDefaultToAllWHOOPResources() throws {
        let legacyState = Data(#"{"enabledMetrics":[],"enabledCategories":[]}"#.utf8)
        let state = try JSONDecoder().decode(MetricSelectionState.self, from: legacyState)
        XCTAssertEqual(state.enabledWHOOPResources, Set(WHOOPResourceName.allCases))

        let legacySnapshot = Data(#"{"enabledMetricIDs":[],"enabledCategoryIDs":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(MetricSelectionSnapshot.self, from: legacySnapshot)
        XCTAssertEqual(snapshot.enabledWHOOPResources, Set(WHOOPResourceName.allCases))
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["enabledWHOOPResources"], "Default snapshots retain the legacy encoding")
    }

    func testPartialAndAllOffSelectionsRoundTripWithoutReenablingDisabledResources() throws {
        let selections: [Set<WHOOPResourceName>] = [[.recovery, .sleep], []]
        for resources in selections {
            let state = MetricSelectionState()
            state.enabledWHOOPResources = resources
            let decodedState = try JSONDecoder().decode(
                MetricSelectionState.self, from: JSONEncoder().encode(state)
            )
            XCTAssertEqual(decodedState.enabledWHOOPResources, resources)
            let snapshot = MetricSelectionSnapshot.from(state)
            let decodedSnapshot = try JSONDecoder().decode(
                MetricSelectionSnapshot.self, from: JSONEncoder().encode(snapshot)
            )
            XCTAssertEqual(decodedSnapshot, snapshot)
            let restored = MetricSelectionState()
            decodedSnapshot.apply(to: restored)
            XCTAssertEqual(restored.enabledWHOOPResources, resources)
        }
    }

    func testAppleHealthBulkAndCategoryActionsRemainIndependent() {
        let state = MetricSelectionState()
        state.enabledWHOOPResources = [.recovery]
        state.deselectAll()
        XCTAssertEqual(state.enabledWHOOPResources, [.recovery])
        state.selectAll()
        state.toggleCategory(.sleep)
        state.removeMetricsUnavailableInCurrentBuild()
        XCTAssertEqual(state.enabledWHOOPResources, [.recovery])
    }

    func testWHOOPChangesAreObservableWithoutChangingAppleHealthMetrics() {
        let state = MetricSelectionState()
        let appleMetrics = state.enabledMetrics
        var events = 0
        let observation = state.objectWillChange.sink { events += 1 }
        state.enabledWHOOPResources.remove(.workouts)
        XCTAssertEqual(events, 1)
        XCTAssertEqual(state.enabledMetrics, appleMetrics)
        withExtendedLifetime(observation) {}
    }

    func testNativeSelectionRetainsSelectedPagesAndPaginationErrorsOnly() throws {
        let payloadNames = ["cycles", "sleep", "sleep_page_2", "sleep_pagination", "recovery", "body_measurements_snapshot", "unknown"]
        let record = ExternalDailyRecord(
            provider: .whoop, date: "2026-05-10",
            payloads: payloadNames.map {
                ExternalProviderPayload(
                    name: $0, endpoint: "https://redacted.invalid", statusCode: 200,
                    data: .object(["records": .array([.object(["synthetic": .bool(true)])])])
                )
            }
        )
        let selected = try XCTUnwrap(record.selectingWHOOPResources([.sleep]))
        XCTAssertEqual(selected.payloads.map(\.name), ["sleep", "sleep_page_2", "sleep_pagination"])
        XCTAssertEqual(selected.payloads[0].data, record.payloads[1].data)
        XCTAssertNil(record.selectingWHOOPResources([]))
        var otherProvider = record
        otherProvider.provider = .oura
        XCTAssertEqual(otherProvider.selectingWHOOPResources([]), otherProvider)
    }

    func testTypedSelectionDoesNotExportDisabledRecordsInAnyFormat() throws {
        let selection = MetricSelectionState()
        selection.enabledWHOOPResources = [.recovery]
        let day = ExportFixtures.whoopDay.filtered(by: selection)
        let whoop = try XCTUnwrap(day.providers?.whoop)
        XCTAssertEqual(whoop.resources.map(\.resource), [.recovery])
        XCTAssertEqual(whoop.captureStatus, .complete)
        XCTAssertTrue(whoop.recordCountsAreValid)
        XCTAssertTrue(whoop.cycles.isEmpty)
        XCTAssertTrue(whoop.sleep.isEmpty)
        XCTAssertTrue(whoop.workouts.isEmpty)
        XCTAssertNil(whoop.body)
        XCTAssertEqual(whoop.recoveries.count, 1)
        XCTAssertEqual(day.activity.steps, 1)

        let json = try day.toJSONThrowing()
        XCTAssertTrue(json.contains("hrv_rmssd_ms"))
        XCTAssertFalse(json.contains("sport_name"))
        let markdown = day.toMarkdown()
        XCTAssertTrue(markdown.contains("HRV (RMSSD)"))
        let bases = day.toObsidianBases()
        XCTAssertTrue(bases.contains("whoop_hrv_rmssd_ms:"))
        XCTAssertFalse(bases.contains("whoop_total_sleep_milliseconds:"))
        XCTAssertFalse(bases.contains("whoop_body_weight_kilograms:"))
        let csv = try day.toCSVThrowing()
        XCTAssertTrue(csv.contains("WHOOP Recovery"))
        XCTAssertFalse(csv.contains("WHOOP Sleep"))
        XCTAssertFalse(csv.contains("WHOOP Workout"))
        XCTAssertFalse(csv.contains("WHOOP Cycle"))
        XCTAssertFalse(csv.contains("WHOOP Body"))

        selection.enabledWHOOPResources = []
        let withoutWHOOP = ExportFixtures.whoopDay.filtered(by: selection)
        XCTAssertNil(withoutWHOOP.providers)
        XCTAssertFalse(try withoutWHOOP.toJSONThrowing().contains("\"providers\""))
        XCTAssertEqual(withoutWHOOP.activity.steps, 1)
    }

    func testBodyPlanningUsesOwnerCalendarAndSelectedBodyFailureIsNotComplete() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = Date(timeIntervalSince1970: 1_773_556_800)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let resources: Set<WHOOPResourceName> = [.body, .sleep]
        XCTAssertEqual(resources.requested(for: now, calendar: calendar, now: now), resources)
        XCTAssertEqual(resources.requested(for: yesterday, calendar: calendar, now: now), [.sleep])
        let failedBody = ExternalDailyRecord(
            provider: .whoop, date: "2026-03-15", fetchedAt: now,
            payloads: [], warnings: ["Synthetic credential failure"]
        )
        let section = try XCTUnwrap(HealthProviderSections.normalized(
            from: [failedBody], whoopResources: [.body]
        )?.whoop)
        XCTAssertEqual(section.captureStatus, .partial)
        XCTAssertEqual(section.resources.first?.resource, .body)
        XCTAssertEqual(section.resources.first?.status, .failure)
        XCTAssertTrue(section.recordCountsAreValid)
    }

    func testNormalizationPlansOnlyRequestedResourcesAndReportsSelectedFailures() throws {
        let record = ExternalDailyRecord(
            provider: .whoop, date: "2026-05-10",
            payloads: [ExternalProviderPayload(
                name: "recovery", endpoint: "https://redacted.invalid", statusCode: 200,
                data: .object(["records": .array([])])
            ), ExternalProviderPayload(
                name: "workouts", endpoint: "https://redacted.invalid", statusCode: 403,
                error: "Unselected permission error"
            )]
        )
        let section = try XCTUnwrap(HealthProviderSections.normalized(
            from: [record], whoopResources: [.recovery]
        )?.whoop)
        XCTAssertEqual(section.captureStatus, .complete)
        XCTAssertEqual(section.resources.map(\.resource), [.recovery])
        XCTAssertTrue(section.warnings.isEmpty)
        XCTAssertTrue(section.recordCountsAreValid)

        let partial = try XCTUnwrap(HealthProviderSections.normalized(
            from: [record], whoopResources: [.recovery, .sleep]
        )?.whoop)
        XCTAssertEqual(partial.captureStatus, .partial)
        XCTAssertEqual(partial.resources.last?.error?.code, "provider_capture_failed")
        XCTAssertTrue(partial.recordCountsAreValid)
        XCTAssertNil(HealthProviderSections.normalized(from: [record], whoopResources: []))
    }
}
