import HealthMdCoreRust
import XCTest
@testable import HealthMd

final class HealthMdCoreRegistryAdapterTests: XCTestCase {
    func testRustRegistryMatchesGeneratedNativeCatalogAndOutputMappingExactly() throws {
        let snapshot = try HealthMdCoreRegistryAdapter.appleSnapshot()

        XCTAssertEqual(HealthMdCoreRegistryAdapter.shadowDifferences(snapshot: snapshot), [])
        XCTAssertEqual(snapshot.metrics.map(\.selectionId), HealthMetrics.all.map(\.id))
        XCTAssertEqual(snapshot.categories.map(\.categoryId), HealthMetricCategory.allCases.map(\.rawValue))
        XCTAssertEqual(snapshot.metrics.filter(\.archiveOnly).count, 58)
        XCTAssertEqual(snapshot.metrics.filter(\.defaultEnabled).count, 229)
        XCTAssertEqual(snapshot.outputs.count, 226)
    }

    func testPersistedSelectionUsesOnlyUnchangedNativeIds() throws {
        let state = MetricSelectionState()
        state.enabledMetrics = ["sleep_total", "active_energy", "scheduled_workout_plans"]
        state.enabledCategories = ["Sleep", "Activity", "Workouts"]

        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String]])

        XCTAssertEqual(Set(object["enabledMetrics"] ?? []), state.enabledMetrics)
        XCTAssertTrue((object["enabledMetrics"] ?? []).allSatisfy { !$0.hasPrefix("android.") })
        XCTAssertEqual(Set(object["enabledCategories"] ?? []), state.enabledCategories)
    }

    func testUnsupportedRegistryVersionFailsClosedWithStableError() {
        XCTAssertThrowsError(
            try HealthMdCoreService().metricRegistry(
                profile: .appleHealthDataV8,
                expectedRegistryVersion: 2
            )
        ) { error in
            XCTAssertEqual(error as? HealthMdCoreServiceError, .unsupportedRegistryVersion)
        }
    }
}
