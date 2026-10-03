import Foundation
import XCTest
@testable import HealthMdWatchExport

@MainActor
private final class MemoryStore: WatchExportStateStore {
    var state = WatchExportState()
    var failRead = false
    var failWrite = false
    var writes = 0
    func load() throws -> WatchExportState {
        if failRead { throw WatchExportError.storage }
        return state
    }
    func save(_ state: WatchExportState) throws {
        if failWrite { throw WatchExportError.storage }
        writes += 1
        self.state = state
    }
}

private final class RecordingTransport: WatchExportTransport {
    var uploads: [(WatchPendingUpload, WatchExportDestination)] = []
    var error: Error?
    var duringUpload: (() async throws -> Void)?
    func upload(_ pending: WatchPendingUpload, to destination: WatchExportDestination) async throws {
        uploads.append((pending, destination))
        try await duringUpload?()
        if let error { throw error }
    }
}

@MainActor
final class WatchExportServiceTests: XCTestCase {
    private func payload() throws -> WatchExportPayload {
        let now = Date()
        return try WatchExportPayload(capturedAt: now, intervalStart: now, intervalEnd: now,
                                      calendarTimezone: "UTC", earliestPermittedSampleDate: now,
                                      observations: WatchExportMetric.allCases.map { try WatchExportObservation(metric: $0, value: nil) })
    }

    func testOfflineFailurePersistsExactBytesAndRetryAfterRelaunchDoesNotRecapture() async throws {
        let store = MemoryStore()
        let transport = RecordingTransport()
        transport.error = WatchExportError.transport
        let service = WatchExportService(store: store, transport: transport)
        try service.configure(endpoint: "https://example.com/watch", token: "synthetic-test-token")
        var captures = 0
        do {
            try await service.sync(capture: { captures += 1; return try self.payload() }, progress: { _ in })
            XCTFail("Expected uncertain delivery")
        } catch {}
        let queued = try XCTUnwrap(store.state.pending)
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(transport.uploads[0].0, queued)
        XCTAssertThrowsError(try service.configure(endpoint: "https://other.example/watch", token: "other-token"))
        XCTAssertThrowsError(try service.forgetDestination())
        transport.error = nil
        let relaunched = WatchExportService(store: store, transport: transport)
        var messages: [String] = []
        try await relaunched.sync(capture: { XCTFail("Retry must not recapture"); return try self.payload() }, progress: { messages.append($0) })
        XCTAssertEqual(transport.uploads.count, 2)
        XCTAssertEqual(transport.uploads[1].0, queued)
        XCTAssertEqual(transport.uploads[0].1, transport.uploads[1].1)
        XCTAssertNil(store.state.pending)
        XCTAssertTrue(messages.last?.hasPrefix("Backend acknowledged") == true)
    }

    func testCaptureAndSecureWriteFailuresDoNotStartNetworking() async throws {
        let store = MemoryStore()
        let transport = RecordingTransport()
        let service = WatchExportService(store: store, transport: transport)
        try service.configure(endpoint: "https://example.com/watch", token: "synthetic")
        do {
            try await service.sync(capture: { throw WatchExportError.unavailable }, progress: { _ in })
            XCTFail("Expected unavailable capture")
        } catch {}
        XCTAssertNil(store.state.pending)
        store.failWrite = true
        do {
            try await service.sync(capture: { try self.payload() }, progress: { _ in })
            XCTFail("Expected storage failure")
        } catch {}
        XCTAssertTrue(transport.uploads.isEmpty)
        XCTAssertFalse(service.isRunning)
    }

    func testReadFailureCannotResetExistingPendingDataOrReroute() async throws {
        let store = MemoryStore()
        let transport = RecordingTransport()
        let service = WatchExportService(store: store, transport: transport)
        try service.configure(endpoint: "https://example.com/watch", token: "synthetic")
        store.failRead = true
        XCTAssertThrowsError(try service.configure(endpoint: "https://other.example/watch", token: "synthetic"))
        do {
            try await service.sync(capture: { XCTFail("Read failure must not capture"); return try self.payload() }, progress: { _ in })
            XCTFail("Expected storage failure")
        } catch {}
        XCTAssertEqual(store.state.destination?.endpoint.absoluteString, "https://example.com/watch")
        XCTAssertTrue(transport.uploads.isEmpty)
    }

    func testInterruptionAndFailureToCommitAcknowledgementKeepPendingAndNeverReportSuccess() async throws {
        for failure in [CancellationError() as Error, WatchExportError.rejected] {
            let store = MemoryStore()
            let transport = RecordingTransport()
            let service = WatchExportService(store: store, transport: transport)
            try service.configure(endpoint: "https://example.com/watch", token: "synthetic")
            transport.error = failure
            var messages: [String] = []
            do {
                try await service.sync(capture: { try self.payload() }, progress: { messages.append($0) })
                XCTFail("Expected failure")
            } catch {}
            XCTAssertNotNil(store.state.pending)
            XCTAssertFalse(messages.contains { $0.hasPrefix("Backend acknowledged") })
        }
        let store = MemoryStore()
        let transport = RecordingTransport()
        let service = WatchExportService(store: store, transport: transport)
        try service.configure(endpoint: "https://example.com/watch", token: "synthetic")
        transport.duringUpload = { store.failWrite = true }
        var messages: [String] = []
        do {
            try await service.sync(capture: { try self.payload() }, progress: { messages.append($0) })
            XCTFail("Expected local commit failure")
        } catch {}
        XCTAssertNotNil(store.state.pending)
        XCTAssertFalse(messages.contains { $0.hasPrefix("Backend acknowledged") })
    }

    func testTaskCancellationAfterBackendResponseDoesNotCommitSuccess() async throws {
        let store = MemoryStore()
        let transport = RecordingTransport()
        let service = WatchExportService(store: store, transport: transport)
        try service.configure(endpoint: "https://example.com/watch", token: "synthetic")
        transport.duringUpload = { withUnsafeCurrentTask { $0?.cancel() } }
        var messages: [String] = []
        let task = Task {
            try await service.sync(capture: { try self.payload() }, progress: { messages.append($0) })
        }
        do { try await task.value; XCTFail("Expected task cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNotNil(store.state.pending)
        XCTAssertFalse(messages.contains { $0.hasPrefix("Backend acknowledged") })
    }

    func testConcurrentSyncAndDestinationChangesAreBlockedDuringUpload() async throws {
        let store = MemoryStore()
        let transport = RecordingTransport()
        let service = WatchExportService(store: store, transport: transport)
        try service.configure(endpoint: "https://example.com/watch", token: "synthetic")
        transport.duringUpload = {
            XCTAssertTrue(service.isRunning)
            XCTAssertThrowsError(try service.discardPending())
            XCTAssertThrowsError(try service.configure(endpoint: "https://other.example/watch", token: "synthetic"))
            do {
                try await service.sync(capture: { XCTFail("Concurrent capture"); return try self.payload() }, progress: { _ in })
                XCTFail("Expected concurrent sync rejection")
            } catch {}
        }
        try await service.sync(capture: { try self.payload() }, progress: { _ in })
        XCTAssertEqual(transport.uploads.count, 1)
    }

    func testDiscardIsExplicitAndAllowsNewDestinationWithoutTouchingHealthStore() async throws {
        let store = MemoryStore()
        let transport = RecordingTransport()
        let service = WatchExportService(store: store, transport: transport)
        try service.configure(endpoint: "https://example.com/watch", token: "synthetic")
        transport.error = WatchExportError.transport
        do { try await service.sync(capture: { try self.payload() }, progress: { _ in }) } catch {}
        let writes = store.writes
        try service.discardPending()
        XCTAssertNil(store.state.pending)
        XCTAssertNotNil(store.state.destination)
        XCTAssertEqual(store.writes, writes + 1)
        try service.configure(endpoint: "https://other.example/watch", token: "new-synthetic")
        try service.forgetDestination()
        XCTAssertNil(store.state.destination)
        XCTAssertEqual(transport.uploads.count, 1)
    }
}
