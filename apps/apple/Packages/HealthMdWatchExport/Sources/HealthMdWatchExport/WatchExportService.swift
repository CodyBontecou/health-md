import Foundation

// Read/write failures never become an empty state, which would lose a pending delivery.
@MainActor
protocol WatchExportStateStore {
    func load() throws -> WatchExportState
    func save(_ state: WatchExportState) throws
}

protocol WatchExportTransport {
    func upload(_ pending: WatchPendingUpload, to destination: WatchExportDestination) async throws
}

enum WatchExportCapture {
    static func capture(at now: Date, calendar: Calendar, earliestPermittedSampleDate: Date,
                        query: (WatchExportMetric, Date, Date) async throws -> Double?) async throws -> WatchExportPayload {
        let start = calendar.startOfDay(for: now)
        var observations: [WatchExportObservation] = []
        for metric in WatchExportMetric.allCases {
            try Task.checkCancellation()
            do {
                let value = try await query(metric, start, now)
                try Task.checkCancellation()
                observations.append(try WatchExportObservation(metric: metric, value: value))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                observations.append(try WatchExportObservation(metric: metric, value: nil, status: .failed))
            }
        }
        return try WatchExportPayload(capturedAt: now, intervalStart: start, intervalEnd: now,
                                      calendarTimezone: calendar.timeZone.identifier,
                                      earliestPermittedSampleDate: earliestPermittedSampleDate,
                                      observations: observations)
    }
}

@MainActor
final class WatchExportService {
    private let store: any WatchExportStateStore
    private let transport: any WatchExportTransport
    private(set) var isRunning = false

    init(store: any WatchExportStateStore, transport: any WatchExportTransport) {
        self.store = store
        self.transport = transport
    }

    func state() throws -> WatchExportState {
        let state = try store.load()
        if let destination = state.destination { _ = try destination.validated() }
        if let pending = state.pending {
            guard state.destination != nil, !pending.body.isEmpty, pending.body.count <= 64 * 1024 else {
                throw WatchExportError.storage
            }
        }
        return state
    }

    func configure(endpoint: String, token: String) throws {
        guard !isRunning else { throw WatchExportError.pendingUpload }
        var state = try self.state()
        guard state.pending == nil else { throw WatchExportError.pendingUpload }
        state.destination = try WatchExportDestination(endpoint: endpoint, bearerToken: token)
        try store.save(state)
    }

    func discardPending() throws {
        guard !isRunning else { throw WatchExportError.pendingUpload }
        var state = try self.state()
        state.pending = nil
        try store.save(state)
    }

    func forgetDestination() throws {
        guard !isRunning else { throw WatchExportError.pendingUpload }
        let state = try self.state()
        guard state.pending == nil else { throw WatchExportError.pendingUpload }
        try store.save(WatchExportState())
    }

    // Retry never calls capture. Destination and exact bytes are committed together
    // before networking; cancellation/process death leaves them eligible for retry.
    func sync(capture: () async throws -> WatchExportPayload,
              progress: (String) -> Void) async throws {
        guard !isRunning else { throw WatchExportError.pendingUpload }
        isRunning = true
        defer { isRunning = false }
        var state = try self.state()
        guard let destination = state.destination else { throw WatchExportError.noDestination }
        if state.pending == nil {
            progress("Reading local Health data…")
            let payload = try await capture()
            try Task.checkCancellation()
            let body = try payload.encoded()
            guard body.count <= 64 * 1024 else { throw WatchExportError.invalidCapture }
            state.pending = WatchPendingUpload(id: payload.uploadID, body: body)
            try store.save(state)
        }
        guard let pending = state.pending else { throw WatchExportError.storage }
        try Task.checkCancellation()
        progress("Uploading pending snapshot… Keep Health.md open.")
        try await transport.upload(pending, to: destination)
        try Task.checkCancellation()
        state.pending = nil
        // If this fails, don't report success. A matching backend ACK may have been
        // received; idempotency makes retry safe when local commit is interrupted.
        try store.save(state)
        progress("Backend acknowledged snapshot. Missing values remain unknown; not a full health history.")
    }
}
