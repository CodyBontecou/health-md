//
//  HealthDataStoreTests.swift
//  HealthMdTests
//
//  Tests for HealthDataStore persistence using isolated temp directories.
//  macOS-only — mirrors the #if os(macOS) guard on the production type.
//

#if os(macOS)
import XCTest
@testable import HealthMd

@MainActor
final class HealthDataStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: HealthDataStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthDataStoreTests-\(UUID().uuidString)")
        store = HealthDataStore(storeDirectory: tempDir)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Initialization

    func testInit_createsStoreDirectory() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: tempDir.path),
            "Init should create the store directory"
        )
    }

    // MARK: - Store & Fetch

    func testStore_writesDateFile() {
        let record = ExportFixtures.fullDay
        store.store([record])

        let dateString = dateString(for: record.date)
        let fileURL = tempDir.appendingPathComponent("\(dateString).json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Storing a record should create a date-named JSON file"
        )
    }

    func testFetch_returnsStoredData() {
        let record = ExportFixtures.partialDay
        store.store([record])

        let fetched = store.fetchHealthData(for: record.date)
        XCTAssertNotNil(fetched, "Should return stored data")
        XCTAssertEqual(fetched?.activity.steps, record.activity.steps)
    }

    func testFetch_missingDate_returnsNil() {
        let missingDate = Date(timeIntervalSince1970: 0)
        XCTAssertNil(store.fetchHealthData(for: missingDate))
    }

    func testHasData_trueAfterStore() {
        let record = ExportFixtures.emptyDay
        store.store([record])
        XCTAssertTrue(store.hasData(for: record.date))
    }

    func testHasData_falseBeforeStore() {
        let missingDate = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(store.hasData(for: missingDate))
    }

    // MARK: - Metadata

    func testStore_updatesMetadata() {
        store.store([ExportFixtures.fullDay], fromDevice: "iPhone 15 Pro")

        XCTAssertNotNil(store.lastSyncDate, "lastSyncDate should be set after store")
        XCTAssertEqual(store.lastSyncDevice, "iPhone 15 Pro")
        XCTAssertEqual(store.recordCount, 1)
    }

    func testStore_multipleRecords_updatesRecordCount() {
        let day1 = ExportFixtures.fullDay
        var day2 = ExportFixtures.partialDay
        // Give day2 a different date so it produces a separate file
        let cal = Calendar(identifier: .gregorian)
        day2 = HealthData(date: cal.date(byAdding: .day, value: 1, to: day1.date)!)
        store.store([day1, day2])

        XCTAssertEqual(store.recordCount, 2)
    }

    // MARK: - Available Dates & Date Range

    func testAvailableDates_matchesStoredRecords() {
        store.store([ExportFixtures.fullDay])
        XCTAssertEqual(store.availableDates.count, 1)
    }

    func testDateRange_singleRecord() {
        store.store([ExportFixtures.fullDay])

        let range = store.dateRange()
        XCTAssertNotNil(range)
        XCTAssertEqual(range?.earliest, range?.latest, "Single record: earliest == latest")
    }

    func testDateRange_multipleRecords() {
        let cal = Calendar(identifier: .gregorian)
        let day1 = ExportFixtures.fullDay
        let day2Date = cal.date(byAdding: .day, value: 3, to: day1.date)!
        let day2 = HealthData(date: day2Date)
        store.store([day1, day2])

        let range = store.dateRange()
        XCTAssertNotNil(range)
        XCTAssertTrue(range!.earliest < range!.latest)
    }

    func testDateRange_empty_returnsNil() {
        XCTAssertNil(store.dateRange())
    }

    // MARK: - Delete All

    func testDeleteAll_clearsFilesAndState() {
        store.store([ExportFixtures.fullDay], fromDevice: "Test")

        store.deleteAll()

        XCTAssertNil(store.lastSyncDate)
        XCTAssertNil(store.lastSyncDevice)
        XCTAssertEqual(store.recordCount, 0)
        XCTAssertTrue(store.availableDates.isEmpty)
        XCTAssertNil(store.fetchHealthData(for: ExportFixtures.fullDay.date))
    }

    // MARK: - Sync Progress

    func testUpdateSyncProgress_setsProgress() {
        let progress = SyncProgressInfo(
            totalDays: 10,
            processedDays: 5,
            recordsInBatch: 3,
            isComplete: false,
            message: "Syncing..."
        )
        store.updateSyncProgress(progress)

        XCTAssertNotNil(store.syncProgress)
        XCTAssertTrue(store.isSyncingAllData)
        XCTAssertEqual(store.syncProgress?.processedDays, 5)
    }

    func testUpdateSyncProgress_complete_clearsIsSyncing() {
        let progress = SyncProgressInfo(
            totalDays: 10,
            processedDays: 10,
            recordsInBatch: 10,
            isComplete: true,
            message: "Done"
        )
        store.updateSyncProgress(progress)

        XCTAssertFalse(store.isSyncingAllData, "Completed sync should set isSyncingAllData to false")
    }

    // MARK: - Round-trip with Fixtures

    func testRoundTrip_fullDay() {
        let original = ExportFixtures.fullDay
        store.store([original])

        let fetched = store.fetchHealthData(for: original.date)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.sleep.totalDuration, original.sleep.totalDuration)
        XCTAssertEqual(fetched?.activity.steps, original.activity.steps)
        XCTAssertEqual(fetched?.heart.restingHeartRate, original.heart.restingHeartRate)
        XCTAssertEqual(fetched?.body.weight, original.body.weight)
        XCTAssertEqual(fetched?.nutrition.protein, original.nutrition.protein)
    }

    func testRoundTrip_edgeCaseDay() {
        let original = ExportFixtures.edgeCaseDay
        store.store([original])

        let fetched = store.fetchHealthData(for: original.date)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.sleep.totalDuration, 0)
        XCTAssertEqual(fetched?.activity.steps, 0)
    }

    // MARK: - Helpers

    private func dateString(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        return df.string(from: date)
    }
}
#endif
