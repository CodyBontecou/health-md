#if DEBUG
import Darwin
import Foundation
import os.log

/// Fixed physical-lab targets. Keeping this list closed prevents debug manifests or
/// telemetry labels from becoming an arbitrary command or data channel.
nonisolated enum ExportPerformanceLabTarget: String, CaseIterable, Codable, Sendable {
    case directRaw = "direct-raw"
    case directFiles = "direct-files"
    case localIPhone = "local-iphone"
    case apiEndpoint = "api-endpoint"
    case connectedMac = "connected-mac"
}

nonisolated struct ExportPerformanceRunContext: Equatable, Sendable {
    let runID: String
    let target: ExportPerformanceLabTarget
}

nonisolated enum ExportPerformanceSpanOutcome: String, Codable, Sendable {
    case success
    case cancelled
    case failure
}

nonisolated protocol ExportPerformanceCancellationClassifying: Error {}

nonisolated struct ExportPerformanceFootprint: Equatable, Codable, Sendable {
    let startBytes: UInt64
    let peakBytes: UInt64
    let endBytes: UInt64
}

nonisolated struct ExportPerformanceEnvironmentSnapshot: Equatable, Sendable {
    let thermalState: String
    let lowPowerModeEnabled: Bool
    let availableCapacityBytes: Int64?

    static func capture() -> Self {
        let thermalState: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "nominal"
        case .fair: thermalState = "fair"
        case .serious: thermalState = "serious"
        case .critical: thermalState = "critical"
        @unknown default: thermalState = "unknown"
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let capacity = try? root?.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
        return Self(
            thermalState: thermalState,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            availableCapacityBytes: capacity ?? nil
        )
    }
}

nonisolated struct ExportPerformanceSpanRecord: Equatable, Codable, Sendable {
    static let telemetryVersion = 1

    let telemetryVersion: Int
    let sequence: Int
    let runID: String
    let target: String
    let pipeline: String
    let phase: String
    let outcome: String
    let runElapsedMilliseconds: Int64
    let elapsedMilliseconds: Int64
    let itemCount: Int
    let byteCount: Int64
    let footprintStartBytes: UInt64?
    let footprintPeakBytes: UInt64?
    let footprintEndBytes: UInt64?
    let queryCount: Int?
    let queryElapsedMilliseconds: Int64?
    let queryMaximumConcurrency: Int?
    let queryActiveCount: Int?
    let thermalStateStart: String?
    let thermalStateEnd: String?
    let lowPowerModeStart: Bool?
    let lowPowerModeEnd: Bool?
    let availableCapacityStartBytes: Int64?
    let availableCapacityEndBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case telemetryVersion = "telemetry_version"
        case sequence
        case runID = "run_id"
        case target
        case pipeline
        case phase
        case outcome
        case runElapsedMilliseconds = "run_elapsed_milliseconds"
        case elapsedMilliseconds = "elapsed_milliseconds"
        case itemCount = "item_count"
        case byteCount = "byte_count"
        case footprintStartBytes = "footprint_start_bytes"
        case footprintPeakBytes = "footprint_peak_bytes"
        case footprintEndBytes = "footprint_end_bytes"
        case queryCount = "query_count"
        case queryElapsedMilliseconds = "query_elapsed_milliseconds"
        case queryMaximumConcurrency = "query_maximum_concurrency"
        case queryActiveCount = "query_active_count"
        case thermalStateStart = "thermal_state_start"
        case thermalStateEnd = "thermal_state_end"
        case lowPowerModeStart = "low_power_mode_start"
        case lowPowerModeEnd = "low_power_mode_end"
        case availableCapacityStartBytes = "available_capacity_start_bytes"
        case availableCapacityEndBytes = "available_capacity_end_bytes"
    }
}

nonisolated enum ExportPerformanceLabTelemetryError: Error, Equatable {
    case invalidRunID
    case runAlreadyActive
    case unsafeRoot
}

/// Process-wide run registration lets a host arm telemetry before the existing direct
/// protocol starts. No run identifier is added to a public export or wire contract.
nonisolated final class ExportPerformanceLabTelemetryStore: @unchecked Sendable {
    static let shared = ExportPerformanceLabTelemetryStore()

    private struct ActiveRun {
        let context: ExportPerformanceRunContext
        let startedAt: ContinuousClock.Instant
        let telemetryURL: URL
        var nextSequence: Int
    }

    private let lock = NSLock()
    private var activeRun: ActiveRun?
    private let encoder: JSONEncoder

    private init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    var activeContext: ExportPerformanceRunContext? {
        lock.lock()
        let context = activeRun?.context
        lock.unlock()
        return context
    }

    @discardableResult
    func beginRun(
        runID: String,
        target: ExportPerformanceLabTarget,
        rootDirectory: URL? = nil
    ) throws -> URL {
        guard Self.isSafeRunID(runID) else {
            throw ExportPerformanceLabTelemetryError.invalidRunID
        }

        let root = try rootDirectory ?? Self.defaultRootDirectory()
        guard root.isFileURL else { throw ExportPerformanceLabTelemetryError.unsafeRoot }
        let runsDirectory = root.appendingPathComponent("Runs", isDirectory: true)
        let runDirectory = runsDirectory.appendingPathComponent(runID, isDirectory: true)
        let telemetryURL = runDirectory.appendingPathComponent("telemetry.ndjson")
        guard !Self.isSymbolicLink(root),
              !Self.isSymbolicLink(runsDirectory),
              !Self.isSymbolicLink(runDirectory),
              !Self.isSymbolicLink(telemetryURL) else {
            throw ExportPerformanceLabTelemetryError.unsafeRoot
        }

        lock.lock()
        defer { lock.unlock() }
        guard activeRun == nil else {
            throw ExportPerformanceLabTelemetryError.runAlreadyActive
        }

        try FileManager.default.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        if !FileManager.default.fileExists(atPath: telemetryURL.path) {
            guard FileManager.default.createFile(
                atPath: telemetryURL.path,
                contents: nil,
                attributes: [
                    .posixPermissions: 0o600,
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        guard !Self.isSymbolicLink(runsDirectory),
              !Self.isSymbolicLink(runDirectory),
              !Self.isSymbolicLink(telemetryURL) else {
            throw ExportPerformanceLabTelemetryError.unsafeRoot
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: telemetryURL.path
        )
        let nextSequence = try Self.nextSequence(
            in: telemetryURL,
            runID: runID,
            target: target
        )
        activeRun = ActiveRun(
            context: ExportPerformanceRunContext(runID: runID, target: target),
            startedAt: .now,
            telemetryURL: telemetryURL,
            nextSequence: nextSequence
        )
        return telemetryURL
    }

    func endRun(runID: String) {
        lock.lock()
        if activeRun?.context.runID == runID {
            activeRun = nil
        }
        lock.unlock()
    }

    func append(
        context expectedContext: ExportPerformanceRunContext,
        pipeline: String,
        phase: String,
        outcome: ExportPerformanceSpanOutcome,
        elapsedMilliseconds: Int64,
        itemCount: Int,
        byteCount: Int64,
        footprint: ExportPerformanceFootprint?,
        querySnapshot: ExportPerformanceQuerySnapshot?,
        environmentStart: ExportPerformanceEnvironmentSnapshot?,
        environmentEnd: ExportPerformanceEnvironmentSnapshot?
    ) {
        guard Self.isSafeLabel(pipeline), Self.isSafeLabel(phase) else { return }

        lock.lock()
        defer { lock.unlock() }
        guard var run = activeRun, run.context == expectedContext else { return }
        let runElapsed = ExportPerformanceTimer.milliseconds(
            from: run.startedAt.duration(to: .now)
        )
        let record = ExportPerformanceSpanRecord(
            telemetryVersion: ExportPerformanceSpanRecord.telemetryVersion,
            sequence: run.nextSequence,
            runID: run.context.runID,
            target: run.context.target.rawValue,
            pipeline: pipeline,
            phase: phase,
            outcome: outcome.rawValue,
            runElapsedMilliseconds: runElapsed,
            elapsedMilliseconds: max(0, elapsedMilliseconds),
            itemCount: max(0, itemCount),
            byteCount: max(0, byteCount),
            footprintStartBytes: footprint?.startBytes,
            footprintPeakBytes: footprint?.peakBytes,
            footprintEndBytes: footprint?.endBytes,
            queryCount: querySnapshot?.totalQueries,
            queryElapsedMilliseconds: querySnapshot?.totalElapsedMilliseconds,
            queryMaximumConcurrency: querySnapshot?.maximumConcurrentQueries,
            queryActiveCount: querySnapshot?.activeQueries,
            thermalStateStart: environmentStart?.thermalState,
            thermalStateEnd: environmentEnd?.thermalState,
            lowPowerModeStart: environmentStart?.lowPowerModeEnabled,
            lowPowerModeEnd: environmentEnd?.lowPowerModeEnabled,
            availableCapacityStartBytes: environmentStart?.availableCapacityBytes,
            availableCapacityEndBytes: environmentEnd?.availableCapacityBytes
        )
        run.nextSequence += 1
        activeRun = run
        guard let encoded = try? encoder.encode(record),
              !Self.isSymbolicLink(run.telemetryURL) else { return }
        do {
            let handle = try FileHandle(forWritingTo: run.telemetryURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded)
            try handle.write(contentsOf: Data([0x0A]))
            try handle.synchronize()
        } catch {
            // Telemetry must never change an export outcome. The missing sequence is
            // detectable by the host and makes the performance run invalid.
        }
    }

    static func isSafeRunID(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count),
              let first = value.utf8.first,
              isASCIIAlphaNumeric(first) else { return false }
        return value.utf8.allSatisfy {
            isASCIIAlphaNumeric($0) || $0 == 0x2D || $0 == 0x5F || $0 == 0x2E
        }
    }

    static func isSafeLabel(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39)
                || $0 == 0x2D || $0 == 0x5F
        }
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
    }

    private static func isASCIIAlphaNumeric(_ value: UInt8) -> Bool {
        (value >= 0x41 && value <= 0x5A)
            || (value >= 0x61 && value <= 0x7A)
            || (value >= 0x30 && value <= 0x39)
    }

    private static func nextSequence(
        in telemetryURL: URL,
        runID: String,
        target: ExportPerformanceLabTarget
    ) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: telemetryURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard byteCount <= 16 * 1_024 * 1_024 else {
            throw CocoaError(.fileReadTooLarge)
        }
        guard byteCount > 0 else { return 0 }
        let data = try Data(contentsOf: telemetryURL, options: [.mappedIfSafe])
        let decoder = JSONDecoder()
        var expected = 0
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            let record = try decoder.decode(ExportPerformanceSpanRecord.self, from: Data(line))
            guard record.telemetryVersion == ExportPerformanceSpanRecord.telemetryVersion,
                  record.runID == runID,
                  record.target == target.rawValue,
                  record.sequence == expected else {
                throw CocoaError(.fileReadCorruptFile)
            }
            expected += 1
        }
        return expected
    }

    private static func defaultRootDirectory() throws -> URL {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return root.appendingPathComponent("HealthMdPerformanceLab", isDirectory: true)
    }
}

/// Samples this process only. It never reads payloads or other processes.
nonisolated final class ExportPerformanceFootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private let sample: @Sendable () -> UInt64?
    private let timerQueue = DispatchQueue(
        label: "com.healthexporter.export-performance-footprint-sampler",
        qos: .utility
    )
    private let timerQueueKey = DispatchSpecificKey<Void>()
    private var timer: DispatchSourceTimer?
    private var start: UInt64?
    private var peak: UInt64?

    init(sample: @escaping @Sendable () -> UInt64? = currentPhysicalFootprintBytes) {
        self.sample = sample
        timerQueue.setSpecific(key: timerQueueKey, value: ())
    }

    deinit {
        cancelTimer()
    }

    func startSampling() {
        let initial = sample()
        lock.lock()
        start = initial
        peak = initial
        guard initial != nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        self.timer = timer
        lock.unlock()

        timer.setEventHandler { [weak self] in
            self?.recordSample()
        }
        timer.schedule(
            deadline: .now() + .milliseconds(100),
            repeating: .milliseconds(100),
            leeway: .milliseconds(10)
        )
        timer.resume()
    }

    func stopSampling() -> ExportPerformanceFootprint? {
        cancelTimer()
        let ending = sample()
        lock.lock()
        defer { lock.unlock() }
        guard let start, let peak, let ending else { return nil }
        return ExportPerformanceFootprint(
            startBytes: start,
            peakBytes: max(peak, ending),
            endBytes: ending
        )
    }

    private func recordSample() {
        guard let current = sample() else { return }
        lock.lock()
        peak = max(peak ?? current, current)
        lock.unlock()
    }

    private func cancelTimer() {
        lock.lock()
        let timer = timer
        self.timer = nil
        lock.unlock()
        timer?.setEventHandler(handler: nil)
        timer?.cancel()
        if timer != nil, DispatchQueue.getSpecific(key: timerQueueKey) == nil {
            timerQueue.sync {}
        }
    }

    static func currentPhysicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}

nonisolated final class ExportPerformanceSpan: @unchecked Sendable {
    private let lock = NSLock()
    private let context: ExportPerformanceRunContext?
    private let pipeline: String
    private let phase: String
    private let timer = ExportPerformanceTimer()
    private let sampler = ExportPerformanceFootprintSampler()
    private let environmentStart = ExportPerformanceEnvironmentSnapshot.capture()
    private var finished = false

    init(context: ExportPerformanceRunContext?, pipeline: String, phase: String) {
        self.context = context
        self.pipeline = pipeline
        self.phase = phase
        sampler.startSampling()
    }

    func finish(
        outcome: ExportPerformanceSpanOutcome,
        itemCount: Int = 0,
        byteCount: Int64 = 0,
        querySnapshot: ExportPerformanceQuerySnapshot? = nil
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        let elapsed = timer.elapsedMilliseconds()
        let footprint = sampler.stopSampling()
        let environmentEnd = ExportPerformanceEnvironmentSnapshot.capture()
        ExportPerformanceInstrumentation.recordStructuredSpan(
            context: context,
            pipeline: pipeline,
            phase: phase,
            outcome: outcome,
            elapsedMilliseconds: elapsed,
            itemCount: itemCount,
            byteCount: byteCount,
            footprint: footprint,
            querySnapshot: querySnapshot,
            environmentStart: environmentStart,
            environmentEnd: environmentEnd
        )
    }
}

nonisolated extension ExportPerformanceInstrumentation {
    static func beginLabRun(
        runID: String,
        target: ExportPerformanceLabTarget,
        rootDirectory: URL? = nil
    ) throws -> URL {
        try ExportPerformanceLabTelemetryStore.shared.beginRun(
            runID: runID,
            target: target,
            rootDirectory: rootDirectory
        )
    }

    static func endLabRun(runID: String) {
        ExportPerformanceLabTelemetryStore.shared.endRun(runID: runID)
    }

    static func withRunContext<T>(
        _ context: ExportPerformanceRunContext,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $currentRunContext.withValue(context) {
            try await operation()
        }
    }

    static func beginSpan(pipeline: String, phase: String) -> ExportPerformanceSpan {
        ExportPerformanceSpan(
            context: resolvedRunContext(for: pipeline),
            pipeline: pipeline,
            phase: phase
        )
    }

    static func measureSpan<T>(
        pipeline: String,
        phase: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        let span = beginSpan(pipeline: pipeline, phase: phase)
        do {
            let value = try await operation()
            span.finish(outcome: .success)
            return value
        } catch {
            span.finish(outcome: spanOutcome(for: error))
            throw error
        }
    }

    static func measureSynchronousSpan<T>(
        pipeline: String,
        phase: String,
        operation: () throws -> T
    ) rethrows -> T {
        let span = beginSpan(pipeline: pipeline, phase: phase)
        do {
            let value = try operation()
            span.finish(outcome: .success)
            return value
        } catch {
            span.finish(outcome: spanOutcome(for: error))
            throw error
        }
    }

    static func recordLegacyCompletion(
        pipeline: String,
        phase: String,
        elapsedMilliseconds: Int64,
        itemCount: Int,
        byteCount: Int64,
        querySnapshot: ExportPerformanceQuerySnapshot?,
        outcome: ExportPerformanceSpanOutcome
    ) {
        recordStructuredSpan(
            context: resolvedRunContext(for: pipeline),
            pipeline: pipeline,
            phase: phase,
            outcome: outcome,
            elapsedMilliseconds: elapsedMilliseconds,
            itemCount: itemCount,
            byteCount: byteCount,
            footprint: nil,
            querySnapshot: querySnapshot,
            environmentStart: nil,
            environmentEnd: nil
        )
    }

    static func spanOutcome(for error: Error) -> ExportPerformanceSpanOutcome {
        if Task.isCancelled || error is CancellationError ||
            error is any ExportPerformanceCancellationClassifying {
            return .cancelled
        }
        return .failure
    }

    static func resolvedRunContext(
        for pipeline: String
    ) -> ExportPerformanceRunContext? {
        if let currentRunContext { return currentRunContext }
        guard let active = ExportPerformanceLabTelemetryStore.shared.activeContext else {
            return nil
        }
        let allowed: Set<String>
        switch active.target {
        case .directRaw:
            allowed = ["export-lab", "direct-raw", "healthkit"]
        case .directFiles:
            allowed = ["export-lab", "direct-file", "external-provider", "healthkit"]
        case .connectedMac:
            allowed = ["export-lab", "connected-mac", "local-files"]
        case .localIPhone, .apiEndpoint:
            allowed = ["export-lab"]
        }
        return allowed.contains(pipeline) ? active : nil
    }

    static func recordStructuredSpan(
        context: ExportPerformanceRunContext?,
        pipeline: String,
        phase: String,
        outcome: ExportPerformanceSpanOutcome,
        elapsedMilliseconds: Int64,
        itemCount: Int,
        byteCount: Int64,
        footprint: ExportPerformanceFootprint?,
        querySnapshot: ExportPerformanceQuerySnapshot?,
        environmentStart: ExportPerformanceEnvironmentSnapshot?,
        environmentEnd: ExportPerformanceEnvironmentSnapshot?
    ) {
        let logger = Logger(
            subsystem: "com.healthexporter",
            category: "ExportPerformanceLab"
        )
        if let context {
            logger.debug(
                "kind=span telemetry_version=1 run_id=\(context.runID, privacy: .public) target=\(context.target.rawValue, privacy: .public) pipeline=\(pipeline, privacy: .public) phase=\(phase, privacy: .public) outcome=\(outcome.rawValue, privacy: .public) elapsed_ms=\(elapsedMilliseconds) items=\(itemCount) bytes=\(byteCount) footprint_peak_bytes=\(footprint?.peakBytes ?? 0)"
            )
            ExportPerformanceLabTelemetryStore.shared.append(
                context: context,
                pipeline: pipeline,
                phase: phase,
                outcome: outcome,
                elapsedMilliseconds: elapsedMilliseconds,
                itemCount: itemCount,
                byteCount: byteCount,
                footprint: footprint,
                querySnapshot: querySnapshot,
                environmentStart: environmentStart,
                environmentEnd: environmentEnd
            )
        }
    }
}
#endif
