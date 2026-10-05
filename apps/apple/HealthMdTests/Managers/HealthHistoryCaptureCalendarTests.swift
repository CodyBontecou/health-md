import Foundation
import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class HealthHistoryCaptureCalendarTests: XCTestCase {
    func testActualFetchPinsGregorianAcrossNonGregorianProviderChangeDuringAwait() async throws {
        try await checkFetch(pinned: true)
    }

    func testOtherCallersRetainDynamicNonGregorianCalendarDuringAwait() async throws {
        try await checkFetch(pinned: false)
    }

    private func checkFetch(pinned: Bool) async throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        let probe = HistoryCalendarProbe(calendar: Calendar(identifier: .islamicUmmAlQura))
        let store = FakeHealthStore()
        let sut = HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "HistoryCalendarTests")!,
                                   calendarProvider: { probe.read() })
        let entered = expectation(description: "actual sum provider suspended")
        let finished = expectation(description: "actual fetch returned")
        let gate = HistoryTestSuspension(entered: entered)
        store.querySumSuspension = {
            probe.record(HealthKitManager.effectiveFetchCalendar.identifier)
            await gate.wait()
            probe.record(HealthKitManager.effectiveFetchCalendar.identifier)
        }
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1234
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("steps")
        let calendar = pinned ? gregorian : nil
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            do {
                let data = try await sut.fetchHealthData(for: Date(timeIntervalSince1970: 1_800_000_000),
                    detailPolicy: .summary, metricSelection: selection,
                    timeZone: TimeZone(secondsFromGMT: 0), captureCalendar: calendar)
                XCTAssertEqual(data.activity.steps, 1234)
            } catch { XCTFail("Synthetic actual-fetch control failed: \(error)") }
        }
        defer { gate.resume(); task.cancel() }
        await fulfillment(of: [entered], timeout: 2)
        probe.replace(Calendar(identifier: .coptic))
        gate.resume()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(probe.observations, pinned ? [.gregorian, .gregorian] : [.islamicUmmAlQura, .coptic])
    }
}

/// Test-only lock-protected value supplier; no Apple SDK object conformance or
/// runtime permission claim. All mutable fields are accessed under this lock.
nonisolated private final class HistoryCalendarProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calendar: Calendar
    private var recorded: [Calendar.Identifier] = []
    init(calendar: Calendar) { self.calendar = calendar }
    func read() -> Calendar { lock.lock(); defer { lock.unlock() }; return calendar }
    func replace(_ value: Calendar) { lock.lock(); defer { lock.unlock() }; calendar = value }
    func record(_ value: Calendar.Identifier) { lock.lock(); defer { lock.unlock() }; recorded.append(value) }
    var observations: [Calendar.Identifier] { lock.lock(); defer { lock.unlock() }; return recorded }
}
