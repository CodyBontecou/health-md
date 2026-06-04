import XCTest
@testable import HealthMd

final class PendingExportRequestTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        suiteName = "PendingExportRequestTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStoreReloadsRequestWithMultipleDates() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            dates: [
                date(year: 2026, month: 5, day: 12, hour: 9),
                date(year: 2026, month: 5, day: 13, hour: 18)
            ],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 14, hour: 10)
        )

        try store.upsert(request)

        let reloadedStore = PendingExportStore(userDefaults: defaults)
        XCTAssertEqual(try reloadedStore.loadAll(), [request])
    }

    func testRequestNormalizesDatesToStartOfDayAndSortedOrder() {
        let late = date(year: 2026, month: 5, day: 14, hour: 23, minute: 45)
        let early = date(year: 2026, month: 5, day: 13, hour: 6, minute: 15)

        let request = PendingExportRequest(
            dates: [late, early, late],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )

        XCTAssertEqual(request.dates, [
            calendar.startOfDay(for: early),
            calendar.startOfDay(for: late)
        ])
    }

    func testDecodingPreservesPersistedDatesWithoutRenormalizing() throws {
        let persistedDate = date(year: 2026, month: 5, day: 14, hour: 16, minute: 45)
        let payload = RawPendingExportRequestPayload(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            dates: [persistedDate],
            source: .scheduled,
            reason: nil,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 7),
            notificationMetadata: ["notification": "pending"]
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PendingExportRequest.self, from: data)

        XCTAssertEqual(decoded.dates, [persistedDate])
        XCTAssertEqual(decoded.notificationMetadata, ["notification": "pending"])
    }

    func testRequestCarriesGenericReasonAndMetadataForRetryDiagnostics() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            reason: .destinationAccessDenied,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 9),
            metadata: ["trigger": "silent-push"]
        )

        try store.upsert(request)

        let reloaded = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(reloaded.reason, .destinationAccessDenied)
        XCTAssertEqual(reloaded.metadata, ["trigger": "silent-push"])
        XCTAssertEqual(reloaded.notificationMetadata, ["trigger": "silent-push"])
    }

    func testReplacingSameScheduledOccurrenceDoesNotDuplicatePendingWork() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let fireDate = date(year: 2026, month: 5, day: 15, hour: 8)

        let first = PendingExportRequest(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )
        let replacement = PendingExportRequest(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            dates: [date(year: 2026, month: 5, day: 13, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8, minute: 1)
        )

        try store.upsert(first)
        try store.upsert(replacement)

        XCTAssertEqual(try store.loadAll(), [replacement])
    }

    func testReplacingSameShortcutDatesDoesNotDuplicatePendingWork() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let shortcutDates = [
            date(year: 2026, month: 5, day: 13, hour: 7),
            date(year: 2026, month: 5, day: 14, hour: 7)
        ]

        let first = PendingExportRequest(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            dates: shortcutDates,
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )
        let replacement = PendingExportRequest(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            dates: shortcutDates.reversed(),
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8, minute: 1)
        )

        try store.upsert(first)
        try store.upsert(replacement)

        XCTAssertEqual(try store.loadAll(), [replacement])
    }

    func testRemovingOneRequestPreservesOtherRequests() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let scheduled = PendingExportRequest(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )
        let shortcut = PendingExportRequest(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            dates: [date(year: 2026, month: 5, day: 13, hour: 7)],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 9)
        )

        try store.upsert(scheduled)
        try store.upsert(shortcut)
        try store.remove(id: scheduled.id)

        XCTAssertEqual(try store.loadAll(), [shortcut])
    }

    func testClearCompletedRequestsRemovesOnlyCompletedIDs() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let completed = PendingExportRequest(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            dates: [date(year: 2026, month: 5, day: 12, hour: 7)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 13, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 13, hour: 8)
        )
        let pending = PendingExportRequest(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )

        try store.upsert(completed)
        try store.upsert(pending)
        try store.clearCompletedRequests(ids: [completed.id])

        XCTAssertEqual(try store.loadAll(), [pending])
    }

    func testCorruptPersistedDataFailsSafelyWithoutCrashing() throws {
        defaults.set(Data("not-json".utf8), forKey: PendingExportStore.storageKey)

        let store = PendingExportStore(userDefaults: defaults)

        XCTAssertEqual(try store.loadAll(), [])
    }

    func testNotificationIdentifierIsDeterministicForRequest() {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 9)
        )

        XCTAssertEqual(
            store.notificationIdentifier(for: request),
            "healthmd.pending-export.66666666-6666-6666-6666-666666666666"
        )
    }

    private struct RawPendingExportRequestPayload: Encodable {
        let id: UUID
        let dates: [Date]
        let source: PendingExportSource
        let reason: PendingExportReason?
        let scheduledFireDate: Date?
        let createdAt: Date
        let notificationMetadata: [String: String]
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
