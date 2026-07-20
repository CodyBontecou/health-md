#if os(macOS)
import Combine
import Foundation

/// Owns the durable Mac side of a connected-iPhone export. HTTP requests are
/// only transient waiters on these records: losing a waiter never cancels the
/// export or removes its journal.
@MainActor
final class MacIPhoneExportRequestCoordinator: ObservableObject {
    static let jobLifetime: TimeInterval = 7 * 24 * 60 * 60

    struct ExportRequest {
        let jobID: UUID?
        let startDate: Date
        let endDate: Date
        let requestedDateIdentifiers: [String]?
        let requestedBy: IPhoneExportRequest.RequestSource
        let settingsPolicy: IPhoneExportRequest.SettingsPolicy
        let responseMode: IPhoneExportRequest.ResponseMode
        let rawProfile: IPhoneExportRequest.RawProfile?
        let waitTimeoutSeconds: TimeInterval

        init(
            jobID: UUID? = nil,
            startDate: Date,
            endDate: Date,
            requestedDateIdentifiers: [String]? = nil,
            requestedBy: IPhoneExportRequest.RequestSource,
            settingsPolicy: IPhoneExportRequest.SettingsPolicy,
            responseMode: IPhoneExportRequest.ResponseMode,
            rawProfile: IPhoneExportRequest.RawProfile?,
            waitTimeoutSeconds: TimeInterval
        ) {
            self.jobID = jobID
            self.startDate = startDate
            self.endDate = endDate
            self.requestedDateIdentifiers = requestedDateIdentifiers
            self.requestedBy = requestedBy
            self.settingsPolicy = settingsPolicy
            self.responseMode = responseMode
            self.rawProfile = rawProfile
            self.waitTimeoutSeconds = waitTimeoutSeconds
        }
    }

    struct ExportResponse: Codable {
        enum Status: String, Codable {
            case accepted
            case preparing
            case success
            case partialSuccess = "partial_success"
            case failure
            case cancelled
            case unavailable
            case timedOut = "timed_out"
        }

        let status: Status
        let jobID: UUID?
        let message: String
        let successCount: Int?
        let totalCount: Int?
        let filesWritten: Int?
        let externalRecordCount: Int?
        let dailyNotesUpdated: Int?
        let dailyNotesSkipped: Int?
        let destinationDisplayName: String?
        let destinationPath: String?
        let failureReason: String?
        let rawData: IPhoneExportRawDataPayload?
        let rawResult: CanonicalRawResultEnvelope?
        let paused: Bool?
        let fractionComplete: Double?
        let processedDays: Int?
        let expiresAt: Date?
        var durable: Bool?
        var durableState: String?
        var sessionID: UUID?
        var committedPartitions: Int?
        var committedBytes: Int64?
        /// Transport-only durable artifact metadata; never encoded in JSON.
        var spooledControlResponse: ConnectedTransferPreparedFile? = nil
        var spooledRawDateRangeStart: String? = nil
        var spooledRawDateRangeEnd: String? = nil
        var spooledRawTotalDays: Int? = nil

        enum CodingKeys: String, CodingKey {
            case status
            case jobID = "job_id"
            case message
            case successCount = "success_count"
            case totalCount = "total_count"
            case filesWritten = "files_written"
            case externalRecordCount = "external_record_count"
            case dailyNotesUpdated = "daily_notes_updated"
            case dailyNotesSkipped = "daily_notes_skipped"
            case destinationDisplayName = "destination_display_name"
            case destinationPath = "destination_path"
            case failureReason = "failure_reason"
            case rawData = "raw_data"
            case rawResult = "raw_result"
            case paused
            case fractionComplete = "fraction_complete"
            case processedDays = "processed_days"
            case expiresAt = "expires_at"
            case durable
            case durableState = "state"
            case sessionID = "session_id"
            case committedPartitions = "committed_partitions"
            case committedBytes = "committed_bytes"
        }

        init(
            status: Status,
            jobID: UUID?,
            message: String,
            successCount: Int?,
            totalCount: Int?,
            filesWritten: Int?,
            externalRecordCount: Int?,
            dailyNotesUpdated: Int? = nil,
            dailyNotesSkipped: Int? = nil,
            destinationDisplayName: String?,
            destinationPath: String?,
            failureReason: String?,
            rawData: IPhoneExportRawDataPayload?,
            rawResult: CanonicalRawResultEnvelope?,
            paused: Bool? = nil,
            fractionComplete: Double? = nil,
            processedDays: Int? = nil,
            expiresAt: Date? = nil,
            durable: Bool? = nil,
            durableState: String? = nil,
            sessionID: UUID? = nil,
            committedPartitions: Int? = nil,
            committedBytes: Int64? = nil
        ) {
            self.status = status
            self.jobID = jobID
            self.message = message
            self.successCount = successCount
            self.totalCount = totalCount
            self.filesWritten = filesWritten
            self.externalRecordCount = externalRecordCount
            self.dailyNotesUpdated = dailyNotesUpdated
            self.dailyNotesSkipped = dailyNotesSkipped
            self.destinationDisplayName = destinationDisplayName
            self.destinationPath = destinationPath
            self.failureReason = failureReason
            self.rawData = rawData
            self.rawResult = rawResult
            self.paused = paused
            self.fractionComplete = fractionComplete
            self.processedDays = processedDays
            self.expiresAt = expiresAt
            self.durable = durable
            self.durableState = durableState
            self.sessionID = sessionID
            self.committedPartitions = committedPartitions
            self.committedBytes = committedBytes
        }

        static func unavailable(_ message: String, reason: String? = nil, jobID: UUID? = nil) -> Self {
            Self(
                status: .unavailable, jobID: jobID, message: message,
                successCount: nil, totalCount: nil, filesWritten: nil, externalRecordCount: nil,
                destinationDisplayName: nil, destinationPath: nil, failureReason: reason,
                rawData: nil, rawResult: nil
            )
        }

        func controlAPIData(using encoder: JSONEncoder) throws -> Data {
            precondition(spooledControlResponse == nil, "Spooled control responses must be streamed from disk.")
            let encoded = try encoder.encode(self)
            guard let rawResult else { return encoded }
            guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                return encoded
            }
            object["raw_result"] = try rawResult.controlAPIJSONObject()
            return try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        }
    }

    struct DurableProgress: Codable, Equatable {
        var processedDays: Int
        var totalDays: Int
        var currentDate: Date?
        var message: String
        var filesWritten: Int?
        var committedPartitions: Int? = nil
        var committedBytes: Int64? = nil

        var fractionComplete: Double {
            guard totalDays > 0 else { return 0 }
            return Double(processedDays) / Double(totalDays)
        }
    }

    struct JobRecord: Codable {
        enum State: String, Codable {
            case queued, sent, accepted, preparing, transferring, paused, completed, failed, cancelled

            var isTerminal: Bool {
                self == .completed || self == .failed || self == .cancelled
            }
        }

        struct SpoolArtifact: Codable {
            let relativePath: String
            let byteCount: Int64
            let sha256: String
            let dateRangeStart: String
            let dateRangeEnd: String
            let totalDays: Int
        }

        static let currentVersion = 2
        var version = currentVersion
        let request: IPhoneExportRequest
        let createdAt: Date
        /// Fixed at creation; progress and resume never extend retention.
        let expiresAt: Date
        var updatedAt: Date
        var state: State
        var paused: Bool
        var progress: DurableProgress?
        var terminalResponse: ExportResponse?
        var spoolArtifact: SpoolArtifact?
        var corpusSessionID: UUID?
        var corpusRequestFingerprint: ConnectedCorpusRequestFingerprint?
        var nextPartitionIndex: Int?
        /// Source-device ordering watermark for additive status snapshots.
        var lastCorpusStatusUpdatedAt: Date? = nil
        /// Stable installation binding for durable protocol-v2 recovery.
        var sourceInstallationID: UUID? = nil
        var destinationInstallationID: UUID? = nil
    }

    private struct PendingWaiter {
        let continuation: CheckedContinuation<ExportResponse, Never>
        let timeoutSeconds: TimeInterval
        var timeoutToken: UUID
        var timeoutTask: Task<Void, Never>
    }

    @Published private(set) var activeJobID: UUID?
    @Published private(set) var latestProgress: IPhoneExportPreparationProgress?
    /// Performs local receiver/session cleanup. `notifyPeer` is true only when
    /// the currently connected iPhone matches this durable job's binding.
    var onRequestTermination: ((_ jobID: UUID, _ notifyPeer: Bool) -> Void)?

    private let fileManager: FileManager
    private let rootURL: URL
    private let now: () -> Date
    private var records: [UUID: JobRecord] = [:]
    private var waiters: [UUID: PendingWaiter] = [:]

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.now = now
        if let rootURL {
            self.rootURL = rootURL
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // XCTest processes create many coordinators in one host; production
            // always uses the stable Application Support location below.
            self.rootURL = fileManager.temporaryDirectory
                .appendingPathComponent("HealthMdConnectedExportTests-\(UUID().uuidString)", isDirectory: true)
        } else {
            let support = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.rootURL = support
                .appendingPathComponent("Health.md", isDirectory: true)
                .appendingPathComponent("ConnectedExportJobs", isDirectory: true)
        }
        restoreJobs()
    }

    func requestExport(
        _ exportRequest: ExportRequest,
        syncService: SyncService,
        destinationStatus: MacDestinationStatus
    ) async -> ExportResponse {
        cleanupExpiredJobs()
        if let jobID = exportRequest.jobID, records[jobID] != nil {
            return await resumeExport(
                jobID: jobID,
                waitTimeoutSeconds: exportRequest.waitTimeoutSeconds,
                syncService: syncService,
                destinationStatus: destinationStatus
            )
        }
        if let rejection = preflight(
            responseMode: exportRequest.responseMode,
            rawProfile: exportRequest.rawProfile,
            syncService: syncService,
            destinationStatus: destinationStatus
        ) { return rejection }
        guard activeJobID == nil else {
            return .unavailable("Another iPhone export request is already active.", reason: "export_in_progress")
        }
        let dates = ExportOrchestrator.dateRange(from: exportRequest.startDate, to: exportRequest.endDate)
        guard !dates.isEmpty else {
            return .unavailable("Choose a valid date range.", reason: "invalid_date_range")
        }

        let createdAt = now()
        let request = IPhoneExportRequest(
            jobID: exportRequest.jobID ?? UUID(),
            createdAt: createdAt,
            dateRangeStart: exportRequest.startDate,
            dateRangeEnd: exportRequest.endDate,
            requestedDateIdentifiers: exportRequest.requestedDateIdentifiers,
            requestedBy: exportRequest.requestedBy,
            settingsPolicy: exportRequest.settingsPolicy,
            responseMode: exportRequest.responseMode,
            rawProfile: exportRequest.rawProfile
        )
        let peerBinding = syncService.remoteCapabilities.flatMap {
            ConnectedCorpusTransferNegotiator.negotiateDurable(
                source: $0,
                destination: syncService.localCapabilities
            )?.peerBinding
        }
        let record = JobRecord(
            request: request,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(Self.jobLifetime),
            updatedAt: createdAt,
            state: .sent,
            paused: false,
            progress: nil,
            terminalResponse: nil,
            spoolArtifact: nil,
            corpusSessionID: nil,
            corpusRequestFingerprint: nil,
            nextPartitionIndex: nil,
            sourceInstallationID: peerBinding?.sourceInstallationID,
            destinationInstallationID: peerBinding?.destinationInstallationID
        )
        do {
            try persist(record)
        } catch {
            return .unavailable("The Mac could not create the durable export job.", reason: "job_persistence_failed")
        }
        records[request.jobID] = record
        activeJobID = request.jobID
        latestProgress = nil
        syncService.send(.iphoneExportRequest(request))
        return await waitForJob(jobID: request.jobID, timeoutSeconds: exportRequest.waitTimeoutSeconds)
    }

    func jobResponse(jobID: UUID) -> ExportResponse {
        cleanupExpiredJobs()
        guard let record = records[jobID] else {
            return .unavailable("No durable export job exists for this identifier.", reason: "job_not_found", jobID: jobID)
        }
        return response(for: record)
    }

    func resumeExport(
        jobID: UUID,
        waitTimeoutSeconds: TimeInterval,
        syncService: SyncService,
        destinationStatus: MacDestinationStatus
    ) async -> ExportResponse {
        cleanupExpiredJobs()
        guard var record = records[jobID] else {
            return .unavailable("No durable export job exists for this identifier.", reason: "job_not_found", jobID: jobID)
        }
        if record.state.isTerminal { return response(for: record) }
        guard matchesBoundPeer(record, syncService: syncService) else {
            return .unavailable(
                "This durable export belongs to a different iPhone installation.",
                reason: "peer_changed",
                jobID: jobID
            )
        }
        if let rejection = preflight(
            responseMode: record.request.responseMode,
            rawProfile: record.request.rawProfile,
            syncService: syncService,
            destinationStatus: destinationStatus,
            jobID: jobID
        ) { return rejection }
        if let activeJobID, activeJobID != jobID {
            return .unavailable("Another iPhone export request is already active.", reason: "export_in_progress", jobID: jobID)
        }
        guard waiters[jobID] == nil else {
            return .unavailable("Another client is already waiting on this job.", reason: "job_waiter_exists", jobID: jobID)
        }
        record.state = .sent
        record.paused = false
        record.updatedAt = now()
        update(record)
        activeJobID = jobID
        // This is the exact Codable request created by the original POST,
        // including its original createdAt and immutable date identifiers.
        syncService.send(.iphoneExportRequest(record.request))
        return await waitForJob(jobID: jobID, timeoutSeconds: waitTimeoutSeconds)
    }

    func cancelExport(jobID: UUID, syncService: SyncService) -> ExportResponse {
        cleanupExpiredJobs()
        guard var record = records[jobID] else {
            return .unavailable("No durable export job exists for this identifier.", reason: "job_not_found", jobID: jobID)
        }
        if record.state.isTerminal { return response(for: record) }

        let notifyPeer = matchesBoundPeer(record, syncService: syncService)
        onRequestTermination?(jobID, notifyPeer)
        if notifyPeer {
            sendRemoteCancellation(jobID: jobID, syncService: syncService)
        }
        removeSpoolArtifact(record)
        let terminal = ExportResponse(
            status: .cancelled, jobID: jobID, message: "Export cancelled.",
            successCount: nil, totalCount: nil, filesWritten: nil, externalRecordCount: nil,
            destinationDisplayName: nil, destinationPath: nil,
            failureReason: IPhoneExportFailureReason.cancelled.rawValue,
            rawData: nil,
            rawResult: nil,
            paused: false,
            expiresAt: record.expiresAt,
            durable: true,
            durableState: JobRecord.State.cancelled.rawValue,
            sessionID: record.corpusSessionID,
            committedPartitions: record.progress?.committedPartitions
                ?? record.nextPartitionIndex,
            committedBytes: record.progress?.committedBytes
        )
        record.state = .cancelled
        record.paused = false
        record.terminalResponse = terminal
        record.spoolArtifact = nil
        record.updatedAt = now()
        update(record)
        finishWaiter(jobID: jobID, response: terminal)
        refreshActiveJobID()
        return terminal
    }

    /// Called after hello negotiation. Persisted paused jobs can be resent even
    /// when no HTTP waiter survived the disconnect or app relaunch.
    func resumePausedJobsAfterHello(
        syncService: SyncService,
        destinationStatus: MacDestinationStatus? = nil
    ) {
        cleanupExpiredJobs()
        guard syncService.connectionState == .connected,
              syncService.remoteCapabilities?.supportsIPhoneExportRequests == true else { return }
        // A cancelled job is also a bounded tombstone. If cancellation happened
        // while the bound iPhone was absent, deliver it on the next matching hello
        // so the iPhone can remove its retained outbound checkpoint.
        for (jobID, record) in records where record.state == .cancelled
            && record.sourceInstallationID != nil
            && matchesBoundPeer(record, syncService: syncService) {
            sendRemoteCancellation(jobID: jobID, syncService: syncService)
        }
        for (jobID, var record) in records where !record.state.isTerminal && record.paused {
            guard matchesBoundPeer(record, syncService: syncService) else { continue }
            if record.request.responseMode == .writeFiles {
                guard let destinationStatus,
                      destinationStatus.destinationFolderSelected,
                      destinationStatus.folderAccessHealthy else { continue }
            }
            record.paused = false
            record.state = .sent
            record.updatedAt = now()
            update(record)
            activeJobID = jobID
            syncService.send(.iphoneExportRequest(record.request))
            break // The control plane intentionally serializes connected exports.
        }
    }

    func handleAccepted(_ acknowledgement: IPhoneExportAcknowledgement) {
        cleanupExpiredJobs()
        guard var record = records[acknowledgement.jobID],
              !record.state.isTerminal,
              !record.paused else { return }
        record.state = record.corpusSessionID == nil ? .accepted : .transferring
        record.paused = false
        record.updatedAt = now()
        update(record)
        activeJobID = acknowledgement.jobID
        resetWaiterTimeout(for: acknowledgement.jobID)
    }

    func handlePreparationProgress(_ progress: IPhoneExportPreparationProgress) {
        cleanupExpiredJobs()
        guard var record = records[progress.jobID],
              !record.state.isTerminal,
              !record.paused else { return }
        let previousProgress = record.progress
        record.state = record.corpusSessionID == nil ? .preparing : .transferring
        record.paused = false
        record.progress = DurableProgress(
            processedDays: max(previousProgress?.processedDays ?? 0, progress.processedDays),
            totalDays: progress.totalDays,
            currentDate: progress.processedDays >= (previousProgress?.processedDays ?? 0)
                ? progress.currentDate : previousProgress?.currentDate,
            message: progress.message,
            filesWritten: previousProgress?.filesWritten,
            committedPartitions: previousProgress?.committedPartitions,
            committedBytes: previousProgress?.committedBytes
        )
        record.updatedAt = now()
        update(record)
        latestProgress = progress
        resetWaiterTimeout(for: progress.jobID)
    }

    func handleMacExportProgress(_ progress: MacExportProgress) {
        cleanupExpiredJobs()
        guard var record = records[progress.jobID],
              !record.state.isTerminal,
              !record.paused else { return }
        let previousProgress = record.progress
        record.state = .transferring
        record.paused = false
        record.progress = DurableProgress(
            processedDays: max(previousProgress?.processedDays ?? 0, progress.processedDays),
            totalDays: progress.totalDays,
            currentDate: progress.processedDays >= (previousProgress?.processedDays ?? 0)
                ? progress.currentDate : previousProgress?.currentDate,
            message: progress.message,
            filesWritten: progress.filesWritten,
            committedPartitions: previousProgress?.committedPartitions,
            committedBytes: previousProgress?.committedBytes
        )
        record.updatedAt = now()
        update(record)
        resetWaiterTimeout(for: progress.jobID)
    }

    func handleValidatedTransferProgress(jobID: UUID) {
        cleanupExpiredJobs()
        guard var record = records[jobID],
              !record.state.isTerminal,
              !record.paused else { return }
        record.state = .transferring
        record.paused = false
        record.updatedAt = now()
        update(record)
        resetWaiterTimeout(for: jobID)
    }

    func handleCorpusStatus(
        _ snapshot: ConnectedCorpusProgressSnapshot,
        syncService: SyncService
    ) {
        cleanupExpiredJobs()
        guard var record = records[snapshot.jobID],
              !record.state.isTerminal,
              matchesBoundPeer(record, syncService: syncService),
              record.corpusSessionID.map({ $0 == snapshot.sessionID }) ?? true,
              record.corpusRequestFingerprint.map({ $0 == snapshot.requestFingerprint }) ?? true else {
            return
        }
        let previousProgress = record.progress
        if let lastUpdatedAt = record.lastCorpusStatusUpdatedAt,
           snapshot.updatedAt < lastUpdatedAt {
            return
        }
        record.lastCorpusStatusUpdatedAt = max(
            record.lastCorpusStatusUpdatedAt ?? snapshot.updatedAt,
            snapshot.updatedAt
        )
        record.corpusSessionID = snapshot.sessionID
        record.corpusRequestFingerprint = snapshot.requestFingerprint
        let committedPartitions = max(
            previousProgress?.committedPartitions ?? record.nextPartitionIndex ?? 0,
            snapshot.committedPartitionCount
        )
        let committedBytes = max(previousProgress?.committedBytes ?? 0, snapshot.committedBytes)
        let processedDays = max(previousProgress?.processedDays ?? 0, snapshot.processedDays)
        record.nextPartitionIndex = committedPartitions
        record.progress = DurableProgress(
            processedDays: processedDays,
            totalDays: snapshot.totalDays,
            currentDate: snapshot.processedDays >= (previousProgress?.processedDays ?? 0)
                ? snapshot.currentDate : previousProgress?.currentDate,
            message: snapshot.message ?? "Durable export \(snapshot.state.rawValue).",
            filesWritten: previousProgress?.filesWritten,
            committedPartitions: committedPartitions,
            committedBytes: committedBytes
        )
        record.paused = snapshot.state == .paused
        switch snapshot.state {
        case .preparing: record.state = .preparing
        case .transferring: record.state = .transferring
        case .paused: record.state = .paused
        case .finalizing, .completed, .partialSuccess:
            // The application result remains authoritative; status keeps the
            // durable job visible while finalization/result delivery catches up.
            record.state = .transferring
        case .failed, .expired, .cancelled:
            // The peer's terminal snapshot is authoritative, but local receiver
            // state and spools still require cleanup if its explicit cancel or
            // rejection frame was lost.
            onRequestTermination?(snapshot.jobID, false)
            record.updatedAt = now()
            update(record)
            let status: ExportResponse.Status = snapshot.state == .cancelled ? .cancelled : .failure
            _ = finish(jobID: snapshot.jobID, response: ExportResponse(
                status: status,
                jobID: snapshot.jobID,
                message: snapshot.message ?? "Durable export \(snapshot.state.rawValue).",
                successCount: nil,
                totalCount: snapshot.totalDays,
                filesWritten: record.progress?.filesWritten,
                externalRecordCount: nil,
                destinationDisplayName: nil,
                destinationPath: nil,
                failureReason: snapshot.state.rawValue,
                rawData: nil,
                rawResult: nil,
                paused: false,
                fractionComplete: Double(processedDays) / Double(max(snapshot.totalDays, 1)),
                processedDays: processedDays,
                expiresAt: record.expiresAt,
                durable: true,
                durableState: snapshot.state.rawValue,
                sessionID: snapshot.sessionID,
                committedPartitions: committedPartitions,
                committedBytes: committedBytes
            ))
            return
        }
        record.updatedAt = now()
        update(record)
        resetWaiterTimeout(for: snapshot.jobID)
    }

    func handleCorpusSession(
        _ open: ConnectedCorpusTransferOpen,
        disposition: ConnectedCorpusTransferDisposition
    ) {
        cleanupExpiredJobs()
        guard disposition.disposition != .reject,
              var record = records[open.session.jobID], !record.state.isTerminal else { return }
        record.corpusSessionID = open.session.sessionID
        record.corpusRequestFingerprint = open.session.requestFingerprint
        record.nextPartitionIndex = max(
            record.nextPartitionIndex ?? 0,
            disposition.nextPartitionIndex
        )
        record.state = .transferring
        record.paused = false
        record.updatedAt = now()
        update(record)
    }

    func accepts(_ manifest: ConnectedTransferManifest) -> Bool {
        cleanupExpiredJobs()
        guard let record = records[manifest.jobID], !record.state.isTerminal else { return false }
        switch manifest.kind {
        case .canonicalRawResultV1:
            return record.request.responseMode == .rawJSON
                && record.request.rawProfile == .canonicalSourceRecordsV1
                && manifest.payloadSchemaVersion == CanonicalRawResultEnvelope.currentSchemaVersion
        case .macExportJobV1:
            return record.request.responseMode == .writeFiles && manifest.payloadSchemaVersion == 1
        case .connectedCorpusPartitionV1:
            return manifest.corpusPartition?.jobID == record.request.jobID
                && manifest.payloadSchemaVersion == ConnectedCorpusPartitionFileManifest.currentVersion
        }
    }

    func accepts(
        _ open: ConnectedCorpusTransferOpen,
        localInstallationID: UUID?,
        remoteInstallationID: UUID?
    ) -> Bool {
        cleanupExpiredJobs()
        guard var record = records[open.session.jobID], !record.state.isTerminal,
              open.partition.jobID == open.session.jobID,
              let manifest = open.exportManifest else { return false }
        let matches: Bool
        if let expected = record.request.requestedDateIdentifiers,
           let supplied = manifest.requestedDateIdentifiers {
            matches = expected == supplied
        } else {
            matches = Calendar.current.isDate(manifest.dateRangeStart, inSameDayAs: record.request.dateRangeStart)
                && Calendar.current.isDate(manifest.dateRangeEnd, inSameDayAs: record.request.dateRangeEnd)
        }
        guard matches else { return false }
        let modeMatches: Bool
        switch manifest.mode {
        case .writeFiles:
            modeMatches = record.request.responseMode == .writeFiles
        case .strictRaw:
            modeMatches = record.request.responseMode == .rawJSON
                && record.request.rawProfile == .canonicalSourceRecordsV1
        }
        guard modeMatches else { return false }

        switch (record.sourceInstallationID, record.destinationInstallationID) {
        case let (sourceInstallationID?, destinationInstallationID?):
            return sourceInstallationID == remoteInstallationID
                && destinationInstallationID == localInstallationID
                && open.session.peerBinding == ConnectedCorpusPeerBinding(
                    sourceInstallationID: sourceInstallationID,
                    destinationInstallationID: destinationInstallationID
                )
        case (nil, nil):
            guard let binding = open.session.peerBinding else {
                return true
            }
            // Version 1 predates persisted installation IDs. Adopt one binding
            // only when it exactly matches the authenticated live peers, then
            // persist the migration before admitting any partition bytes.
            guard record.version == 1,
                  open.session.protocolVersion >= 2,
                  let localInstallationID,
                  let remoteInstallationID,
                  binding.sourceInstallationID == remoteInstallationID,
                  binding.destinationInstallationID == localInstallationID else {
                return false
            }
            record.version = JobRecord.currentVersion
            record.sourceInstallationID = binding.sourceInstallationID
            record.destinationInstallationID = binding.destinationInstallationID
            do {
                try persist(record)
                records[record.request.jobID] = record
                return true
            } catch {
                return false
            }
        default:
            // A partially persisted binding is malformed and must never be
            // completed from untrusted transfer input.
            return false
        }
    }

    @discardableResult
    func complete(with payload: MacExportResultPayload) -> Bool {
        guard let record = records[payload.jobID], !record.state.isTerminal else { return false }
        let status: ExportResponse.Status
        switch payload.status {
        case .success: status = .success
        case .partialSuccess: status = .partialSuccess
        case .failure: status = .failure
        case .cancelled: status = .cancelled
        }
        return finish(jobID: payload.jobID, response: ExportResponse(
            status: status,
            jobID: payload.jobID,
            message: completionMessage(for: payload),
            successCount: payload.successCount,
            totalCount: payload.totalCount,
            filesWritten: payload.totalFilesWritten,
            externalRecordCount: payload.externalRecordFileCount,
            dailyNotesUpdated: payload.dailyNoteUpdateCount > 0 ? payload.dailyNoteUpdateCount : nil,
            dailyNotesSkipped: payload.dailyNoteSkipCount > 0 ? payload.dailyNoteSkipCount : nil,
            destinationDisplayName: payload.destinationDisplayName,
            destinationPath: payload.destinationPathForDisplay,
            failureReason: payload.failedDateDetails.first?.reason.rawValue,
            rawData: nil,
            rawResult: nil,
            paused: false,
            expiresAt: record.expiresAt
        ))
    }

    @discardableResult
    func complete(with strictResult: CanonicalRawResultEnvelope, jobID: UUID) -> Bool {
        guard let record = records[jobID], !record.state.isTerminal else { return false }
        let expectedDates = ExportOrchestrator.dateRange(
            from: record.request.dateRangeStart,
            to: record.request.dateRangeEnd
        )
        let formatter = Self.dateFormatter
        let expectedStrings = record.request.requestedDateIdentifiers ?? expectedDates.map(formatter.string(from:))
        let issues = record.request.rawProfile == .canonicalSourceRecordsV1
            ? strictResult.strictValidationIssues(expectedDates: expectedStrings)
            : ["raw_result_profile_mismatch"]
        guard issues.isEmpty else {
            _ = finish(jobID: jobID, response: ExportResponse(
                status: .failure, jobID: jobID,
                message: "The iPhone returned an invalid strict raw result.",
                successCount: 0, totalCount: expectedStrings.count, filesWritten: 0, externalRecordCount: 0,
                destinationDisplayName: nil, destinationPath: nil,
                failureReason: "raw_profile_response_mismatch", rawData: nil, rawResult: nil,
                paused: false, expiresAt: record.expiresAt
            ))
            return false
        }
        let incomplete = strictResult.hasPartialResult
            || strictResult.totalRequestedDays != expectedStrings.count
            || strictResult.days.count != expectedStrings.count
        let retained = strictResult.calculatedCaptureSummary.retainedDayCount
        return finish(jobID: jobID, response: ExportResponse(
            status: incomplete ? .partialSuccess : .success,
            jobID: jobID,
            message: incomplete
                ? "Fetched canonical raw data for \(retained)/\(expectedStrings.count) day(s) with incomplete capture."
                : "Fetched canonical raw data for all \(expectedStrings.count) requested day(s).",
            successCount: retained, totalCount: expectedStrings.count, filesWritten: 0, externalRecordCount: 0,
            destinationDisplayName: nil, destinationPath: nil,
            failureReason: incomplete ? "incomplete_raw_capture" : nil,
            rawData: nil, rawResult: strictResult, paused: false, expiresAt: record.expiresAt
        ))
    }

    @discardableResult
    func complete(with strictSpool: CanonicalRawResultSpool, jobID: UUID) async -> Bool {
        cleanupExpiredJobs()
        guard let record = records[jobID], !record.state.isTerminal else {
            strictSpool.remove()
            return false
        }
        let expectedCount = record.request.requestedDateIdentifiers?.count
            ?? ExportOrchestrator.dateRange(from: record.request.dateRangeStart, to: record.request.dateRangeEnd).count
        guard record.request.rawProfile == .canonicalSourceRecordsV1,
              strictSpool.totalRequestedDays == expectedCount else {
            strictSpool.remove()
            _ = finish(jobID: jobID, response: ExportResponse(
                status: .failure, jobID: jobID,
                message: "The iPhone returned an invalid partitioned strict raw result.",
                successCount: 0, totalCount: expectedCount, filesWritten: 0, externalRecordCount: 0,
                destinationDisplayName: nil, destinationPath: nil,
                failureReason: "raw_profile_response_mismatch", rawData: nil, rawResult: nil,
                paused: false, expiresAt: record.expiresAt
            ))
            return false
        }
        let incomplete = strictSpool.hasPartialResult
        var response = ExportResponse(
            status: incomplete ? .partialSuccess : .success,
            jobID: jobID,
            message: incomplete
                ? "Fetched canonical raw data for \(strictSpool.captureSummary.retainedDayCount)/\(expectedCount) day(s) with incomplete capture."
                : "Fetched canonical raw data for all \(expectedCount) requested day(s).",
            successCount: strictSpool.captureSummary.retainedDayCount,
            totalCount: expectedCount,
            filesWritten: 0,
            externalRecordCount: 0,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: incomplete ? "incomplete_raw_capture" : nil,
            rawData: nil,
            rawResult: nil,
            paused: false,
            expiresAt: record.expiresAt
        )
        do {
            let temporary = try await Self.composeControlResponse(response, rawResultFile: strictSpool.file.url) {
                self.cleanupExpiredJobs()
                guard self.records[jobID]?.state.isTerminal == false else { throw CancellationError() }
                self.resetWaiterTimeout(for: jobID)
            }
            strictSpool.remove()
            cleanupExpiredJobs()
            guard records[jobID]?.state.isTerminal == false else {
                temporary.remove()
                return false
            }
            let artifact = try installSpool(
                temporary,
                jobID: jobID,
                start: strictSpool.dateRangeStart,
                end: strictSpool.dateRangeEnd,
                totalDays: strictSpool.totalRequestedDays
            )
            guard var updated = records[jobID], !updated.state.isTerminal else { return false }
            updated.spoolArtifact = artifact
            updated.updatedAt = now()
            update(updated)
            response = responseWithSpool(response, artifact: artifact, jobID: jobID)
            return finish(jobID: jobID, response: response, preservingSpool: true)
        } catch {
            strictSpool.remove()
            return finish(jobID: jobID, response: ExportResponse(
                status: .failure, jobID: jobID,
                message: "The strict raw control response could not be prepared.",
                successCount: 0, totalCount: expectedCount, filesWritten: 0, externalRecordCount: 0,
                destinationDisplayName: nil, destinationPath: nil,
                failureReason: "raw_response_spool_failed", rawData: nil, rawResult: nil,
                paused: false, expiresAt: record.expiresAt
            ))
        }
    }

    @discardableResult
    func complete(with rawData: IPhoneExportRawDataPayload) -> Bool {
        guard let record = records[rawData.jobID], !record.state.isTerminal else { return false }
        if record.request.rawProfile == .canonicalSourceRecordsV1 {
            return finish(jobID: rawData.jobID, response: ExportResponse(
                status: .failure, jobID: rawData.jobID,
                message: "The iPhone attempted an unbounded strict raw response. Update Health.md on both devices.",
                successCount: 0, totalCount: rawData.totalDays, filesWritten: 0, externalRecordCount: 0,
                destinationDisplayName: nil, destinationPath: nil,
                failureReason: "strict_raw_stream_required", rawData: nil, rawResult: nil,
                paused: false, expiresAt: record.expiresAt
            ))
        }
        let successCount = rawData.records.count
        let externalCount = rawData.externalDailyRecords.filter(\.shouldExport).count
        return finish(jobID: rawData.jobID, response: ExportResponse(
            status: successCount > 0 ? .success : .failure,
            jobID: rawData.jobID,
            message: successCount > 0
                ? "Fetched raw health data for \(successCount)/\(rawData.totalDays) day(s)."
                : "No raw health data was found for the requested date range.",
            successCount: successCount, totalCount: rawData.totalDays, filesWritten: 0,
            externalRecordCount: externalCount,
            destinationDisplayName: nil, destinationPath: nil,
            failureReason: rawData.failedDateDetails.first?.reason.rawValue,
            rawData: rawData, rawResult: nil, paused: false, expiresAt: record.expiresAt
        ))
    }

    @discardableResult
    func complete(with failure: MacExportFailure) -> Bool {
        guard let jobID = failure.jobID, let record = records[jobID], !record.state.isTerminal else { return false }
        return finish(jobID: jobID, response: ExportResponse(
            status: failure.reason == .cancelled ? .cancelled : .failure,
            jobID: jobID, message: failure.message,
            successCount: 0, totalCount: nil, filesWritten: 0, externalRecordCount: nil,
            destinationDisplayName: nil, destinationPath: nil,
            failureReason: failure.reason.rawValue, rawData: nil, rawResult: nil,
            paused: false, expiresAt: record.expiresAt
        ))
    }

    @discardableResult
    func complete(with failure: IPhoneExportFailure) -> Bool {
        guard let jobID = failure.jobID, let record = records[jobID], !record.state.isTerminal else { return false }
        return finish(jobID: jobID, response: ExportResponse(
            status: .unavailable, jobID: jobID, message: failure.message,
            successCount: nil, totalCount: nil, filesWritten: nil, externalRecordCount: nil,
            destinationDisplayName: nil, destinationPath: nil,
            failureReason: failure.reason.rawValue, rawData: nil, rawResult: nil,
            paused: false, expiresAt: record.expiresAt
        ))
    }

    /// Backward-compatible entry point used by the HTTP connection monitor.
    /// Detaching a client is explicitly not cancellation.
    func cancelRequestForDisconnectedClient(jobID: UUID) {
        detachWaiter(jobID: jobID, timedOut: false)
    }

    func handlePeerDisconnectForResume() {
        cleanupExpiredJobs()
        for (jobID, var record) in records where !record.state.isTerminal {
            record.state = .paused
            record.paused = true
            record.progress = DurableProgress(
                processedDays: record.progress?.processedDays ?? 0,
                totalDays: max(record.progress?.totalDays ?? 1, 1),
                currentDate: record.progress?.currentDate,
                message: "Waiting for the iPhone to reconnect and resume…",
                filesWritten: record.progress?.filesWritten,
                committedPartitions: record.progress?.committedPartitions,
                committedBytes: record.progress?.committedBytes
            )
            record.updatedAt = now()
            update(record)
            if activeJobID == nil { activeJobID = jobID }
            detachWaiter(jobID: jobID, timedOut: false)
        }
        latestProgress = nil
    }

    /// Retained for source compatibility; a disconnect now pauses rather than
    /// cancelling durable work.
    func cancelActiveRequestForDisconnect() {
        handlePeerDisconnectForResume()
    }

    private func sendRemoteCancellation(jobID: UUID, syncService: SyncService) {
        syncService.send(.connectedTransferAbort(ConnectedTransferAbort(
            transferID: jobID,
            jobID: jobID,
            reason: .cancelled,
            message: "Mac explicitly cancelled the connected export transfer."
        )))
        syncService.send(.iphoneExportCancel(jobID: jobID))
    }

    private func matchesBoundPeer(_ record: JobRecord, syncService: SyncService) -> Bool {
        guard record.sourceInstallationID != nil || record.destinationInstallationID != nil else {
            return true
        }
        return record.sourceInstallationID == syncService.remoteCapabilities?.installationID
            && record.destinationInstallationID == syncService.installationID
    }

    private func preflight(
        responseMode: IPhoneExportRequest.ResponseMode,
        rawProfile: IPhoneExportRequest.RawProfile?,
        syncService: SyncService,
        destinationStatus: MacDestinationStatus,
        jobID: UUID? = nil
    ) -> ExportResponse? {
        guard syncService.connectionState == .connected else {
            return .unavailable("No iPhone is connected.", reason: "iphone_not_connected", jobID: jobID)
        }
        guard let capabilities = syncService.remoteCapabilities,
              capabilities.platform == .iOS,
              capabilities.supportsIPhoneExportRequests else {
            return .unavailable(
                "Connected iPhone does not support Mac-initiated exports. Update Health.md on iPhone.",
                reason: "unsupported_iphone", jobID: jobID
            )
        }
        if let rawProfile {
            guard responseMode == .rawJSON, capabilities.supports(rawProfile: rawProfile) else {
                return .unavailable(
                    "Connected iPhone cannot provide the requested strict raw profile. Update Health.md on iPhone.",
                    reason: "unsupported_raw_profile", jobID: jobID
                )
            }
        }
        let destinationReady = jobID == nil
            ? destinationStatus.canReceiveExports
            : destinationStatus.isConnected
                && destinationStatus.destinationFolderSelected
                && destinationStatus.folderAccessHealthy
        if responseMode == .writeFiles && !destinationReady {
            return .unavailable(
                destinationStatus.notReadyReason ?? "Mac destination is not ready.",
                reason: "mac_destination_unavailable", jobID: jobID
            )
        }
        return nil
    }

    private func waitForJob(jobID: UUID, timeoutSeconds: TimeInterval) async -> ExportResponse {
        guard waiters[jobID] == nil else {
            return .unavailable("Another client is already waiting on this job.", reason: "job_waiter_exists", jobID: jobID)
        }
        return await withCheckedContinuation { continuation in
            let token = UUID()
            waiters[jobID] = PendingWaiter(
                continuation: continuation,
                timeoutSeconds: timeoutSeconds,
                timeoutToken: token,
                timeoutTask: makeTimeoutTask(jobID: jobID, timeoutSeconds: timeoutSeconds, token: token)
            )
        }
    }

    private func makeTimeoutTask(jobID: UUID, timeoutSeconds: TimeInterval, token: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(timeoutSeconds, 0.001) * 1_000_000_000))
            } catch { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.waiters[jobID]?.timeoutToken == token else { return }
                self?.detachWaiter(jobID: jobID, timedOut: true)
            }
        }
    }

    private func resetWaiterTimeout(for jobID: UUID) {
        guard var waiter = waiters[jobID] else { return }
        waiter.timeoutTask.cancel()
        let token = UUID()
        waiter.timeoutToken = token
        waiter.timeoutTask = makeTimeoutTask(jobID: jobID, timeoutSeconds: waiter.timeoutSeconds, token: token)
        waiters[jobID] = waiter
    }

    private func detachWaiter(jobID: UUID, timedOut: Bool) {
        guard let waiter = waiters.removeValue(forKey: jobID) else { return }
        waiter.timeoutTask.cancel()
        let record = records[jobID]
        waiter.continuation.resume(returning: ExportResponse(
            status: timedOut ? .timedOut : .accepted,
            jobID: jobID,
            message: timedOut
                ? "Timed out waiting; the durable export job is still running."
                : "Client detached; the durable export job is still running.",
            successCount: nil,
            totalCount: record?.progress?.totalDays,
            filesWritten: record?.progress?.filesWritten,
            externalRecordCount: nil,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: timedOut ? IPhoneExportFailureReason.timedOut.rawValue : nil,
            rawData: nil,
            rawResult: nil,
            paused: record?.paused,
            fractionComplete: record?.progress?.fractionComplete,
            processedDays: record?.progress?.processedDays,
            expiresAt: record?.expiresAt,
            durable: true,
            durableState: record?.state.rawValue,
            sessionID: record?.corpusSessionID,
            committedPartitions: record?.progress?.committedPartitions
                ?? record?.nextPartitionIndex,
            committedBytes: record?.progress?.committedBytes
        ))
    }

    @discardableResult
    private func finish(jobID: UUID, response: ExportResponse, preservingSpool: Bool = false) -> Bool {
        cleanupExpiredJobs()
        guard var record = records[jobID], !record.state.isTerminal else { return false }
        record.state = response.status == .cancelled ? .cancelled
            : (response.status == .success || response.status == .partialSuccess ? .completed : .failed)
        record.paused = false
        if !preservingSpool {
            removeSpoolArtifact(record)
            record.spoolArtifact = nil
        }
        record.updatedAt = now()
        let durableResponse = responseWithDurableMetadata(response, record: record)
        record.terminalResponse = responseWithoutSpool(durableResponse)
        update(record)
        finishWaiter(jobID: jobID, response: durableResponse)
        if activeJobID == jobID { refreshActiveJobID() }
        latestProgress = nil
        return true
    }

    private func finishWaiter(jobID: UUID, response: ExportResponse) {
        guard let waiter = waiters.removeValue(forKey: jobID) else { return }
        waiter.timeoutTask.cancel()
        waiter.continuation.resume(returning: response)
    }

    private func response(for record: JobRecord) -> ExportResponse {
        if var terminal = record.terminalResponse {
            terminal = responseWithDurableMetadata(terminal, record: record)
            if let artifact = record.spoolArtifact {
                terminal = responseWithSpool(terminal, artifact: artifact, jobID: record.request.jobID)
            }
            return terminal
        }
        return ExportResponse(
            status: record.state == .queued || record.state == .sent || record.state == .accepted ? .accepted : .preparing,
            jobID: record.request.jobID,
            message: record.progress?.message ?? (record.paused ? "Export is paused." : "Export job is active."),
            successCount: nil,
            totalCount: record.progress?.totalDays,
            filesWritten: record.progress?.filesWritten,
            externalRecordCount: nil,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: nil,
            rawData: nil,
            rawResult: nil,
            paused: record.paused,
            fractionComplete: record.progress?.fractionComplete,
            processedDays: record.progress?.processedDays,
            expiresAt: record.expiresAt,
            durable: true,
            durableState: record.state.rawValue,
            sessionID: record.corpusSessionID,
            committedPartitions: record.progress?.committedPartitions
                ?? record.nextPartitionIndex,
            committedBytes: record.progress?.committedBytes
        )
    }

    private func responseWithDurableMetadata(
        _ response: ExportResponse,
        record: JobRecord
    ) -> ExportResponse {
        var response = response
        response.durable = true
        response.durableState = response.durableState ?? record.state.rawValue
        response.sessionID = record.corpusSessionID
        response.committedPartitions = record.progress?.committedPartitions
            ?? record.nextPartitionIndex
        response.committedBytes = record.progress?.committedBytes
        return response
    }

    private func responseWithoutSpool(_ response: ExportResponse) -> ExportResponse {
        var copy = response
        copy.spooledControlResponse = nil
        copy.spooledRawDateRangeStart = nil
        copy.spooledRawDateRangeEnd = nil
        copy.spooledRawTotalDays = nil
        return copy
    }

    private func responseWithSpool(_ response: ExportResponse, artifact: JobRecord.SpoolArtifact, jobID: UUID) -> ExportResponse {
        var response = response
        let url = jobDirectory(jobID: jobID).appendingPathComponent(artifact.relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return response }
        response.spooledControlResponse = ConnectedTransferPreparedFile(
            url: url, totalBytes: artifact.byteCount, sha256: artifact.sha256
        )
        response.spooledRawDateRangeStart = artifact.dateRangeStart
        response.spooledRawDateRangeEnd = artifact.dateRangeEnd
        response.spooledRawTotalDays = artifact.totalDays
        return response
    }

    private func installSpool(
        _ prepared: ConnectedTransferPreparedFile,
        jobID: UUID,
        start: String,
        end: String,
        totalDays: Int
    ) throws -> JobRecord.SpoolArtifact {
        let directory = jobDirectory(jobID: jobID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent("control-response.json")
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: prepared.url, to: destination)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return JobRecord.SpoolArtifact(
            relativePath: destination.lastPathComponent,
            byteCount: prepared.totalBytes,
            sha256: prepared.sha256,
            dateRangeStart: start,
            dateRangeEnd: end,
            totalDays: totalDays
        )
    }

    private func removeSpoolArtifact(_ record: JobRecord) {
        guard let artifact = record.spoolArtifact else { return }
        try? fileManager.removeItem(
            at: jobDirectory(jobID: record.request.jobID).appendingPathComponent(artifact.relativePath)
        )
    }

    private func update(_ record: JobRecord) {
        records[record.request.jobID] = record
        try? persist(record)
    }

    private func persist(_ record: JobRecord) throws {
        let directory = jobDirectory(jobID: record.request.jobID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        let destination = directory.appendingPathComponent("record.json")
        let temporary = directory.appendingPathComponent(".record-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    private func restoreJobs() {
        cleanupExpiredJobsFromDisk()
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for directory in directories {
            let recordURL = directory.appendingPathComponent("record.json")
            guard let data = try? Data(contentsOf: recordURL),
                  let record = try? JSONDecoder().decode(JobRecord.self, from: data),
                  (record.version == 1 || record.version == JobRecord.currentVersion),
                  record.request.jobID.uuidString.caseInsensitiveCompare(directory.lastPathComponent) == .orderedSame,
                  record.expiresAt == record.createdAt.addingTimeInterval(Self.jobLifetime),
                  record.expiresAt > now() else {
                try? fileManager.removeItem(at: directory)
                continue
            }
            records[record.request.jobID] = record
        }
        refreshActiveJobID()
    }

    private func cleanupExpiredJobs() {
        let expired = records.values.filter { $0.expiresAt <= now() }
        for record in expired {
            finishWaiter(jobID: record.request.jobID, response: .unavailable(
                "The durable export job expired.", reason: "job_expired", jobID: record.request.jobID
            ))
            records.removeValue(forKey: record.request.jobID)
            try? fileManager.removeItem(at: jobDirectory(jobID: record.request.jobID))
        }
        cleanupExpiredJobsFromDisk()
        refreshActiveJobID()
    }

    private func cleanupExpiredJobsFromDisk() {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for directory in directories {
            let recordURL = directory.appendingPathComponent("record.json")
            guard let data = try? Data(contentsOf: recordURL),
                  let record = try? JSONDecoder().decode(JobRecord.self, from: data),
                  record.expiresAt > now() else {
                try? fileManager.removeItem(at: directory)
                continue
            }
        }
    }

    private func refreshActiveJobID() {
        activeJobID = records.values
            .filter { !$0.state.isTerminal && $0.expiresAt > now() }
            .sorted { $0.createdAt < $1.createdAt }
            .first?.request.jobID
    }

    private func jobDirectory(jobID: UUID) -> URL {
        rootURL.appendingPathComponent(jobID.uuidString, isDirectory: true)
    }

    private static func composeControlResponse(
        _ response: ExportResponse,
        rawResultFile: URL,
        progress: () throws -> Void
    ) async throws -> ConnectedTransferPreparedFile {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let small = try encoder.encode(response)
        guard var object = try JSONSerialization.jsonObject(with: small) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        object.removeValue(forKey: "raw_result")
        let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "raw-control-response")
        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            try output.write(contentsOf: Data("{".utf8))
            for (index, key) in object.keys.sorted().enumerated() {
                if index > 0 { try output.write(contentsOf: Data(",".utf8)) }
                try output.write(contentsOf: JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed]))
                try output.write(contentsOf: Data(":".utf8))
                try output.write(contentsOf: JSONSerialization.data(
                    withJSONObject: object[key] as Any,
                    options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
                ))
            }
            if !object.isEmpty { try output.write(contentsOf: Data(",".utf8)) }
            try output.write(contentsOf: Data("\"raw_result\":".utf8))
            let input = try FileHandle(forReadingFrom: rawResultFile)
            defer { try? input.close() }
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                try progress()
                try Task.checkCancellation()
                try output.write(contentsOf: data)
                await Task.yield()
            }
            try output.write(contentsOf: Data("}".utf8))
            try output.synchronize()
            try output.close()
            return try ConnectedTransferFile.inspect(outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func completionMessage(for payload: MacExportResultPayload) -> String {
        let suffix = payload.externalRecordFileCount > 0
            ? " including \(payload.externalRecordFileCount) provider sidecar(s)" : ""
        switch payload.status {
        case .success:
            if payload.dailyNoteUpdateCount > 0 && payload.totalFilesWritten == 0 {
                return "Updated \(payload.dailyNoteUpdateCount) daily note(s); wrote no additional export files."
            }
            return "Exported \(payload.successCount) day(s), wrote \(payload.totalFilesWritten) file(s)\(suffix)."
        case .partialSuccess:
            if payload.dailyNoteSkipCount > 0 && payload.totalFilesWritten == 0 {
                return "Updated \(payload.dailyNoteUpdateCount) and skipped \(payload.dailyNoteSkipCount) daily note(s); wrote no additional export files."
            }
            if payload.dailyNoteUpdateCount > 0 && payload.totalFilesWritten == 0 {
                return "Updated \(payload.dailyNoteUpdateCount)/\(payload.totalCount) daily note(s); wrote no additional export files."
            }
            return "Exported \(payload.successCount)/\(payload.totalCount) day(s), wrote \(payload.totalFilesWritten) file(s)\(suffix)."
        case .failure:
            return payload.failedDateDetails.first?.detailedMessage ?? "Export failed."
        case .cancelled:
            return "Export cancelled."
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
#endif
