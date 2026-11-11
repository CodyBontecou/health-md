import XCTest
@testable import HealthMd

final class WHOOPExportResourceSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "WHOOPExportResourceSelectionTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToEveryResourceAndPersistsASubset() {
        XCTAssertEqual(WHOOPExportResourceSelection.stored(in: defaults), WHOOPExportResourceSelection.all)

        WHOOPExportResourceSelection.store([.sleep, .recovery], in: defaults)
        XCTAssertEqual(WHOOPExportResourceSelection.stored(in: defaults), [.sleep, .recovery])

        WHOOPExportResourceSelection.store(WHOOPExportResourceSelection.all, in: defaults)
        XCTAssertNil(defaults.object(forKey: WHOOPExportResourceSelection.defaultsKey))
    }

    func testTheLastSelectedResourceCannotBeTurnedOff() {
        let one: Set<WHOOPResourceName> = [.sleep]
        XCTAssertEqual(WHOOPExportResourceSelection.toggled(.sleep, in: one), one)
        XCTAssertEqual(WHOOPExportResourceSelection.toggled(.body, in: one), [.sleep, .body])
        XCTAssertEqual(WHOOPExportResourceSelection.toggled(.body, in: [.sleep, .body]), one)
    }

    func testDeselectedResourcesAreNotPlannedSoTheCaptureStaysComplete() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_773_556_800)
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-03-15",
            fetchedAt: fetchedAt,
            payloads: ["recovery", "sleep"].map {
                ExternalProviderPayload(
                    name: $0,
                    endpoint: "https://redacted.invalid/\($0)",
                    statusCode: 200,
                    fetchedAt: fetchedAt,
                    data: .object(["records": .array([])])
                )
            }
        )

        let whoop = try XCTUnwrap(HealthProviderSections.normalized(from: [record], whoopResources: [.recovery, .sleep])?.whoop)
        XCTAssertEqual(whoop.captureStatus, .complete)
        XCTAssertEqual(whoop.resources.map(\.resource), [.recovery, .sleep])
        XCTAssertTrue(whoop.recordCountsAreValid)

        let unfiltered = try XCTUnwrap(HealthProviderSections.normalized(from: [record], whoopResources: WHOOPExportResourceSelection.all)?.whoop)
        XCTAssertEqual(unfiltered.captureStatus, .partial, "Without a selection the missing collections are failures")
    }

    func testBodyOnlySelectionOnAPastDayIsNotRequested() throws {
        let record = ExternalDailyRecord(provider: .whoop, date: "2026-03-15", payloads: [])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        // Capture resolves today's-only body selection before normalization. An
        // explicitly planned but missing resource would correctly be partial.
        let resources = Set<WHOOPResourceName>([.body]).requested(for: day, calendar: calendar, now: now)
        XCTAssertTrue(resources.isEmpty)
        XCTAssertNil(HealthProviderSections.normalized(from: [record], whoopResources: resources)?.whoop,
                     "An unrequested historical singleton must not create a provider section")
    }
}
