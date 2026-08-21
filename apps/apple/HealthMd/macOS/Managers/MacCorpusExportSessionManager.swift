#if os(macOS)
import CryptoKit
import Darwin
import Foundation
import HealthMdCoreRust

enum MacCorpusFinalizeOutcome {
    case files(result: MacExportResultPayload, acknowledgement: ConnectedCorpusTransferFinalAck)
    case strictRaw(spool: CanonicalRawResultSpool, acknowledgement: ConnectedCorpusTransferFinalAck)
    case failed(failure: MacExportFailure, acknowledgement: ConnectedCorpusTransferFinalAck)
    case replay(
        acknowledgement: ConnectedCorpusTransferFinalAck,
        fileResult: MacExportResultPayload?
    )
    case inProgress
}

/// Durable application-level receiver for corpus partitions. Transport ACKs are
/// issued only after this manager has applied complete items and atomically
/// replaced its journal.
@MainActor
final class MacCorpusExportSessionManager {
    private struct StoredItem: Codable, Equatable {
        let sourceDate: Date
        let relativePath: String
        /// Source-device owner date for strict raw items. Older file journals
        /// decode nil and continue using the exact source instant.
        let dateIdentifier: String?
        /// Exact protected spool identity. Nil decodes only for v2/v3 migration and is bound to
        /// the currently present regular file before the upgraded journal can be persisted.
        let byteCount: Int64?
        let sha256: String?
        /// V4 strict-raw items keep the canonical health document as an exact,
        /// separately checksummed disk source so finalization never recreates its String.
        let canonicalJSONRelativePath: String?
        let canonicalJSONByteCount: Int64?
        let canonicalJSONSHA256: String?

        init(
            sourceDate: Date,
            relativePath: String,
            dateIdentifier: String? = nil,
            byteCount: Int64? = nil,
            sha256: String? = nil,
            canonicalJSONRelativePath: String? = nil,
            canonicalJSONByteCount: Int64? = nil,
            canonicalJSONSHA256: String? = nil
        ) {
            self.sourceDate = sourceDate
            self.relativePath = relativePath
            self.dateIdentifier = dateIdentifier
            self.byteCount = byteCount
            self.sha256 = sha256
            self.canonicalJSONRelativePath = canonicalJSONRelativePath
            self.canonicalJSONByteCount = canonicalJSONByteCount
            self.canonicalJSONSHA256 = canonicalJSONSHA256
        }
    }

    private struct PartialItem: Codable, Equatable {
        let itemID: UUID
        let kind: ConnectedCorpusItemKind
        let sourceDate: Date
        let isRequestedDate: Bool
        let totalItemBytes: Int64
        let itemSHA256: String
        var nextOffset: Int64
        var prefixSHA256: String?
    }

    private struct StoredFinalizationFile: Codable, Equatable {
        let relativePath: String
        let spoolRelativePath: String
        let mediaType: String
        let byteCount: UInt64
        let sha256: String
    }

    private struct StoredFinalizationArtifact: Codable, Equatable {
        let artifactID: String
        let relativePath: String
        let spoolRelativePath: String
        let mediaType: String
        let writeMode: String
        let kind: AppleLooseDailyArtifactKind
        let format: ExportFormat
        let byteCount: UInt64
        let sha256: String
    }

    private struct StoredReceivedRangePlan: Codable, Equatable {
        static let schema = "healthmd.connected_received_range_plan"
        static let version = 1

        let schema: String
        let version: Int
        let destinationBinding: AppleVaultDestinationBinding
        let authority: ExportEngineMode
        let pin: AppleExportEnginePin
        let artifactPlanVersion: UInt32
        let requestID: String
        let sessionID: String
        let profile: String
        let totalByteCount: UInt64
        let immutablePlanSHA256: String
        let dataDictionary: StoredFinalizationFile?
        let artifacts: [StoredFinalizationArtifact]
        let dailyFileCount: Int
        let rollupFileCount: Int
        let requestedRecordDatesWithData: [Date]
        var dataDictionaryAcknowledged: Bool
        var nextArtifactIndex: Int
    }

    private struct StoredStrictRawTerminalSpool: Codable, Equatable {
        static let relativePath = "terminal/strict-raw-result.json"

        let relativePath: String
        let byteCount: Int64
        let sha256: String
        let profile: IPhoneExportRequest.RawProfile
        let canonicalSelection: CanonicalHealthDataSelection?
        let captureSummary: CanonicalRawCaptureSummary
        let missingDates: [String]
        let totalRequestedDays: Int
        let dateRangeStart: String
        let dateRangeEnd: String
    }

    private struct StoredReceivedRangePlanDigest: Codable {
        let schema: String
        let version: Int
        let destinationBinding: AppleVaultDestinationBinding
        let authority: ExportEngineMode
        let pin: AppleExportEnginePin
        let artifactPlanVersion: UInt32
        let requestID: String
        let sessionID: String
        let profile: String
        let totalByteCount: UInt64
        let dataDictionary: StoredFinalizationFile?
        let artifacts: [StoredFinalizationArtifact]
        let dailyFileCount: Int
        let rollupFileCount: Int
        let requestedRecordDatesWithData: [Date]
    }

    private enum ReceivedRangeCommitError: Error {
        case transient
        case invalid
    }

    private enum JournalPersistenceError: Error {
        case postPublication
    }

    private struct ProtectedSessionDirectoryBinding: Codable, Equatable {
        let deviceID: UInt64
        let inode: UInt64
    }

    private struct ExpiredCorruptSessionIdentity: Equatable {
        let binding: ProtectedSessionDirectoryBinding
        let birthSeconds: Int
        let birthNanoseconds: Int
    }

    private struct Journal: Codable {
        static let currentVersion = 5

        var version = currentVersion
        let session: ConnectedCorpusTransferSession
        let exportManifest: ConnectedCorpusExportManifest
        var state: ConnectedCorpusTransferJournalState
        var committedPartitions: [ConnectedCorpusPartitionDescriptor]
        var processedDates: [Date]
        var successfulRequestedDates: [Date]
        var completedDates: [Date]
        var failedDateDetails: [FailedDateDetail]
        var supportingDateFailures: [FailedDateDetail] = []
        var partialItems: [PartialItem]
        var completedItemIDs: [UUID]
        var recordItems: [StoredItem]
        var rawItems: [StoredItem]
        var totalPartitionBytes: Int64
        var totalFilesWritten: Int
        var externalRecordFileCount: Int
        var dailyNoteUpdateCount: Int?
        var dailyNoteSkipCount: Int?
        /// Write-side warnings (individual-entry coverage gaps under lossless
        /// records) collected across the session and replayed in the terminal
        /// result payload. Optional so earlier journals decode unchanged.
        var individualEntryCoverageGaps: [ExportPartialFailure]? = nil
        /// Derived-output warnings that are not tied to individual-entry extraction. Optional so
        /// earlier journals decode unchanged and terminal results can replay the exact warning.
        var derivedOutputPartialFailures: [ExportPartialFailure]? = nil
        /// Canonical strict-raw retained-day result survives payload spool cleanup and restart.
        var strictRawRetainedDayCount: Int? = nil
        /// Optional so journals created before one-time dictionary tracking decode unchanged.
        var dataDictionaryWritten: Bool? = nil
        /// A v4+ marker distinguishes a safe precommit `.finalizing` journal from an older journal
        /// that may already have performed destination writes without an exact persisted plan.
        var receivedRangePlanPersisted: Bool? = nil
        var receivedRangePlan: StoredReceivedRangePlan? = nil
        var terminalResult: MacExportResultPayload? = nil
        /// Optional v5 field. A terminal negative ACK is replayable only with this
        /// persisted application failure, so peers cannot strand exact failure details.
        var terminalFailure: MacExportFailure? = nil
        var terminalAcknowledgement: ConnectedCorpusTransferFinalAck? = nil
        /// A protected strict-raw terminal result bridges process death between journal
        /// completion and installation in the durable control-response store.
        var strictRawTerminalSpool: StoredStrictRawTerminalSpool? = nil
        /// App-private spool root identity. Optional only while v2/v3 journals are upgraded by
        /// securely opening their existing session directory; current journals require both.
        var protectedSessionDeviceID: UInt64? = nil
        var protectedSessionInode: UInt64? = nil
        /// Fixed recovery deadline. Optional only so existing v2 journals remain
        /// decodable and receive a conservative deadline from session creation.
        let expiresAt: Date?
        var updatedAt: Date
    }

    private final class Session {
        let directoryURL: URL
        var journal: Journal
        /// Resolved once from the durable manifest each time a session is opened/restored, never
        /// from the Mac's mutable current rollout default and never independently for each day.
        let dailyExportOperation: ConnectedMacDailyExportOperation?

        init(directoryURL: URL, journal: Journal) throws {
            self.directoryURL = directoryURL
            self.journal = journal
            if journal.exportManifest.mode == .writeFiles {
                dailyExportOperation = try ConnectedMacDailyExportOperation.resolve(
                    settingsSnapshot: journal.exportManifest.settingsSnapshot,
                    declaredPin: journal.exportManifest.effectiveAppleExportEnginePin,
                    supportsRangePlan: journal.session.protocolVersion
                        >= ConnectedCorpusTransferCapabilities.rangePlanProtocolVersion
                )
            } else {
                dailyExportOperation = nil
            }
        }

        var journalURL: URL { directoryURL.appendingPathComponent("journal.json") }
        var itemDirectoryURL: URL { directoryURL.appendingPathComponent("items", isDirectory: true) }
        var recordDirectoryURL: URL { directoryURL.appendingPathComponent("records", isDirectory: true) }
        var rawDirectoryURL: URL { directoryURL.appendingPathComponent("raw", isDirectory: true) }
        var finalizationDirectoryURL: URL {
            directoryURL.appendingPathComponent("finalization", isDirectory: true)
        }
        var finalizationArtifactDirectoryURL: URL {
            finalizationDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        }
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let diskSpaceCheck: ((URL, Int64) -> Bool)?
    private let queryContextStore: EncryptedHealthContextStore?
    private var activeSession: Session?
    /// Cancellation may interleave while an asynchronous native file transaction is queued.
    /// It is rejected until that one transaction reaches its artifact boundary, so an accepted
    /// cancellation can never be followed by a late destination mutation.
    private var destinationCommitInFlightSessionID: UUID?
    /// Distinguishes an actively executing async finalizer from a restored `.finalizing` journal
    /// that is merely attached through `open` and must be allowed to resume.
    private var finalizationExecutionSessionID: UUID?
    private var partitionExecutionSessionID: UUID?
    private var pendingDisconnectSessionIDs: Set<UUID> = []
    /// One successful `open` grants one exact transport-start admission. The
    /// admission is consumed before a receiver spool is created.
    private var admittedPartitions: Set<ConnectedCorpusPartitionDescriptor> = []
    private var suspendedExpiryTasks: [UUID: Task<Void, Never>] = [:]
    private var protectedSessionBindings: [String: ProtectedSessionDirectoryBinding] = [:]
    #if DEBUG
    var failNextTerminalPersistForTesting = false
    var failNextPartitionPersistForTesting = false
    var failNextPostRenameJournalSyncForTesting = false
    var failNextPostRenameRangePlanSyncForTesting = false
    var failNextPostRenameTerminalSyncForTesting = false
    var beforeProtectedCleanupForTesting: (() throws -> Void)?
    #endif

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        diskSpaceCheck: ((URL, Int64) -> Bool)? = nil,
        queryContextStore: EncryptedHealthContextStore? = nil
    ) {
        self.fileManager = fileManager
        self.diskSpaceCheck = diskSpaceCheck
        self.queryContextStore = queryContextStore
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.rootURL = support
                .appendingPathComponent("Health.md", isDirectory: true)
                .appendingPathComponent("ConnectedCorpusSessions", isDirectory: true)
        }
        cleanupExpiredSessions()
    }

    var activeJobID: UUID? { activeSession?.journal.session.jobID }
    var activeSessionID: UUID? { activeSession?.journal.session.sessionID }
    var activeExportMode: ConnectedCorpusExportMode? {
        activeSession?.journal.exportManifest.mode
    }
    var isBusy: Bool { activeSession != nil }

    #if DEBUG
    func cleanupExpiredSessionsForTesting(now: Date) {
        cleanupExpiredSessions(now: now)
    }
    #endif

    /// Releases the in-memory ownership after a peer disconnect while retaining
    /// the durable open journal. A reconnect with the same session/fingerprint
    /// restores it; unrelated sessions are no longer blocked indefinitely.
    func suspendForDisconnect() {
        guard let session = activeSession else { return }
        // Finalization no longer needs peer bytes. Let it finish and persist its
        // replayable terminal ACK; the iPhone will request that ACK after reconnecting.
        guard session.journal.state != .finalizing else { return }
        let sessionID = session.journal.session.sessionID
        if partitionExecutionSessionID == sessionID {
            pendingDisconnectSessionIDs.insert(sessionID)
            return
        }
        completeDisconnectSuspension(session)
    }

    private func completeDisconnectSuspension(_ session: Session) {
        let sessionID = session.journal.session.sessionID
        session.journal.updatedAt = Date()
        try? persist(session)
        if activeSession === session {
            activeSession = nil
        }
        admittedPartitions.removeAll()
        suspendedExpiryTasks[sessionID]?.cancel()
        let rawRemaining = (session.journal.expiresAt
            ?? session.journal.session.createdAt.addingTimeInterval(
                ConnectedCorpusOutboundStore.retentionInterval
            )).timeIntervalSinceNow
        let remaining = rawRemaining.isFinite
            ? min(max(rawRemaining, 0), ConnectedCorpusOutboundStore.retentionInterval)
            : 0
        suspendedExpiryTasks[sessionID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.activeSession?.journal.session.sessionID != sessionID else { return }
            self.cleanupExpiredSessions(now: Date())
            self.suspendedExpiryTasks.removeValue(forKey: sessionID)
        }
    }

    func open(
        _ open: ConnectedCorpusTransferOpen,
        vaultManager: VaultManager,
        localInstallationID: UUID? = nil,
        remoteInstallationID: UUID? = nil
    ) -> ConnectedCorpusTransferDisposition {
        cleanupExpiredSessions(vaultManager: vaultManager)
        let rejected: (String) -> ConnectedCorpusTransferDisposition = { message in
            ConnectedCorpusTransferDisposition(
                sessionID: open.session.sessionID,
                jobID: open.session.jobID,
                partitionIndex: open.partition.index,
                partitionSHA256: open.partition.sha256,
                disposition: .reject,
                nextPartitionIndex: self.activeSession?.journal.committedPartitions.count ?? 0,
                message: message
            )
        }

        guard let exportManifest = open.exportManifest else {
            return rejected("Corpus export manifest is missing.")
        }
        do {
            try open.partition.validate()
            try exportManifest.validate()
            guard try ConnectedCorpusRequestFingerprint.make(for: exportManifest)
                    == open.session.requestFingerprint else {
                return rejected("Corpus request fingerprint does not match its immutable manifest.")
            }
        } catch {
            return rejected("Corpus session metadata is malformed.")
        }
        guard ConnectedCorpusTransferCapabilities.current.protocolVersions.contains(
            open.session.protocolVersion
        ) else {
            return rejected("Corpus application-item protocol is unsupported.")
        }
        if let binding = open.session.peerBinding {
            guard open.session.protocolVersion >= 2,
                  binding.sourceInstallationID == remoteInstallationID,
                  binding.destinationInstallationID == localInstallationID else {
                return rejected("Durable corpus session belongs to a different app installation.")
            }
        }
        let admissionNow = Date()
        guard open.session.createdAt.timeIntervalSinceReferenceDate.isFinite,
              open.session.createdAt <= admissionNow.addingTimeInterval(5 * 60),
              admissionNow < open.session.createdAt.addingTimeInterval(
                  ConnectedCorpusOutboundStore.retentionInterval
              ) else {
            return rejected("Durable corpus session expired before it could resume.")
        }
        guard Set(open.partition.sourceDates).isSubset(of: Set(exportManifest.transferDates)) else {
            return rejected("Corpus partition contains dates outside the export request.")
        }
        if exportManifest.mode == .strictRaw,
           exportManifest.requestedDateIdentifiers?.count != exportManifest.requestedDates.count {
            return rejected("Strict raw corpus is missing source owner-date identifiers.")
        }
        if exportManifest.mode == .encryptedContext, queryContextStore == nil {
            return rejected("Encrypted context store is unavailable.")
        }
        if exportManifest.mode == .writeFiles {
            guard let vaultURL = vaultManager.vaultURL, vaultManager.canAccessSelectedVaultFolder() else {
                return rejected("Mac destination folder is unavailable.")
            }
            guard exportManifest.settingsSnapshot.hasFileDestinationOutput else {
                return rejected("Select an export format or enable Daily Notes Only.")
            }
            guard destinationPathsAreContained(
                manifest: exportManifest,
                vaultURL: vaultURL
            ) else {
                return rejected("Export paths must remain inside the selected Mac destination.")
            }
            let settings = exportManifest.settingsSnapshot.makeAdvancedExportSettings()
            settings.exportTimeZoneOverride = exportManifest.sourceTimeZoneIdentifier
                .flatMap(TimeZone.init(identifier:))
            do {
                try vaultManager.preflightExportDestinations(
                    settings: settings,
                    healthSubfolder: exportManifest.settingsSnapshot.healthSubfolder,
                    dates: exportManifest.requestedDates
                )
            } catch {
                return rejected(error.localizedDescription)
            }
        }

        do {
            if exportManifest.mode == .writeFiles {
                let operation = try ConnectedMacDailyExportOperation.resolve(
                    settingsSnapshot: exportManifest.settingsSnapshot,
                    declaredPin: exportManifest.effectiveAppleExportEnginePin,
                    supportsRangePlan: open.session.protocolVersion
                        >= ConnectedCorpusTransferCapabilities.rangePlanProtocolVersion
                )
                guard !operation.usesRangePlan
                        || exportManifest.transferDates.count <= HealthRollupRangeRequest.maximumDays else {
                    return rejected("Received-range authority exceeds the bounded semantic owner-date limit.")
                }
            }
            let session: Session
            if let activeSession {
                session = activeSession
                guard session.journal.session == open.session,
                      session.journal.exportManifest == exportManifest else {
                    return rejected("Another corpus session is active or this request changed.")
                }
            } else if let restored = try restoreSession(sessionID: open.session.sessionID) {
                session = restored
                guard session.journal.session == open.session,
                      session.journal.exportManifest == exportManifest else {
                    return rejected("Stored corpus session fingerprint does not match this request.")
                }
                activeSession = session
            } else {
                let directory = sessionDirectory(sessionID: open.session.sessionID)
                let protectedBinding = try prepareRootAndSessionDirectories(
                    sessionID: open.session.sessionID
                )
                var journal = Journal(
                    session: open.session,
                    exportManifest: exportManifest,
                    state: .open,
                    committedPartitions: [],
                    processedDates: [],
                    successfulRequestedDates: [],
                    completedDates: [],
                    failedDateDetails: [],
                    supportingDateFailures: [],
                    partialItems: [],
                    completedItemIDs: [],
                    recordItems: [],
                    rawItems: [],
                    totalPartitionBytes: 0,
                    totalFilesWritten: 0,
                    externalRecordFileCount: 0,
                    dailyNoteUpdateCount: 0,
                    dailyNoteSkipCount: 0,
                    receivedRangePlanPersisted: false,
                    expiresAt: open.session.createdAt.addingTimeInterval(
                        ConnectedCorpusOutboundStore.retentionInterval
                    ),
                    updatedAt: Date()
                )
                journal.protectedSessionDeviceID = protectedBinding.deviceID
                journal.protectedSessionInode = protectedBinding.inode
                protectedSessionBindings[directory.standardizedFileURL.path] = protectedBinding
                session = try Session(directoryURL: directory, journal: journal)
                try persist(session)
                activeSession = session
            }

            suspendedExpiryTasks.removeValue(forKey: open.session.sessionID)?.cancel()
            let isNewPartition = open.partition.index >= session.journal.committedPartitions.count
            let projectedBytesResult = session.journal.totalPartitionBytes.addingReportingOverflow(
                isNewPartition ? open.partition.byteCount : 0
            )
            guard !projectedBytesResult.overflow else {
                return rejected("Corpus byte counters overflowed.")
            }
            let projectedBytes = projectedBytesResult.partialValue
            let safetyBytes: Int64 = 128 * 1_024 * 1_024
            let rawFinalizationBytes = projectedBytes.multipliedReportingOverflow(by: 2)
            let appBaseBytes = exportManifest.mode == .strictRaw && !rawFinalizationBytes.overflow
                ? max(rawFinalizationBytes.partialValue, open.partition.byteCount * 2)
                : max(open.partition.byteCount * 2, safetyBytes)
            let appRequiredBytes = appBaseBytes.addingReportingOverflow(safetyBytes)
            guard !rawFinalizationBytes.overflow,
                  !appRequiredBytes.overflow,
                  hasAvailableDiskSpace(at: rootURL, requiredBytes: appRequiredBytes.partialValue) else {
                activeSession = nil
                admittedPartitions.removeAll()
                return rejected("Mac does not have enough available storage for corpus spooling and finalization.")
            }
            if exportManifest.mode == .writeFiles,
               let vaultURL = vaultManager.vaultURL {
                let formatMultiplier = Int64(max(
                    exportManifest.settingsSnapshot.exportFormats.count,
                    1
                ))
                let expandedOutputBytes = projectedBytes.multipliedReportingOverflow(
                    by: formatMultiplier
                )
                let destinationRequired = expandedOutputBytes.partialValue.addingReportingOverflow(
                    safetyBytes
                )
                guard !expandedOutputBytes.overflow,
                      !destinationRequired.overflow,
                      hasAvailableDiskSpace(
                        at: vaultURL,
                        requiredBytes: destinationRequired.partialValue
                      ) else {
                    activeSession = nil
                    admittedPartitions.removeAll()
                    return rejected("Mac destination does not have enough available storage for final output.")
                }
            }

            let committedCount = session.journal.committedPartitions.count
            if open.partition.index < committedCount {
                let prior = session.journal.committedPartitions[open.partition.index]
                guard prior.sha256 == open.partition.sha256 else {
                    if session.journal.state == .completed || session.journal.state == .cancelled
                        || session.journal.state == .failed {
                        activeSession = nil
                    }
                    return rejected("A committed partition index was replayed with different content.")
                }
                admittedPartitions.remove(open.partition)
                if session.journal.state == .completed || session.journal.state == .cancelled
                    || session.journal.state == .failed {
                    activeSession = nil
                }
                return ConnectedCorpusTransferDisposition(
                    sessionID: open.session.sessionID,
                    jobID: open.session.jobID,
                    partitionIndex: open.partition.index,
                    partitionSHA256: open.partition.sha256,
                    disposition: .alreadyCommitted,
                    nextPartitionIndex: committedCount,
                    message: "Partition was already durably committed."
                )
            }
            guard session.journal.state == .open || session.journal.state == .finalizing else {
                activeSession = nil
                admittedPartitions.removeAll()
                return rejected("Corpus session is already terminal.")
            }
            if session.journal.state == .finalizing,
               open.partition.index >= committedCount {
                return rejected("Corpus finalization has already started; no new partitions are accepted.")
            }
            guard open.partition.index == committedCount,
                  open.partition.previousSHA256 == session.journal.committedPartitions.last?.sha256 else {
                return rejected("Partition sequence or digest chain is inconsistent with the durable journal.")
            }
            admittedPartitions = [open.partition]
            return ConnectedCorpusTransferDisposition(
                sessionID: open.session.sessionID,
                jobID: open.session.jobID,
                partitionIndex: open.partition.index,
                partitionSHA256: open.partition.sha256,
                disposition: committedCount == 0 ? .accept : .resume,
                nextPartitionIndex: committedCount,
                message: "Partition may be transferred."
            )
        } catch {
            return rejected("Mac could not create or restore the protected corpus journal.")
        }
    }

    func consumeAdmission(for descriptor: ConnectedCorpusPartitionDescriptor) -> Bool {
        guard admittedPartitions.remove(descriptor) != nil,
              let session = activeSession,
              session.journal.session.sessionID == descriptor.sessionID,
              session.journal.session.jobID == descriptor.jobID,
              session.journal.state == .open else { return false }
        let committedCount = session.journal.committedPartitions.count
        return descriptor.index == committedCount
            && descriptor.previousSHA256 == session.journal.committedPartitions.last?.sha256
    }

    /// Applies one fully checksummed transport partition and persists its
    /// application commit before the caller emits ConnectedTransferFinalAck.
    func applyPartition(
        fileURL: URL,
        descriptor: ConnectedCorpusPartitionDescriptor,
        vaultManager: VaultManager
    ) async throws {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "connected-mac",
                phase: "apply-partition",
                timer: performanceTimer,
                byteCount: descriptor.byteCount
            )
        }
        #endif
        admittedPartitions.remove(descriptor)
        guard let session = activeSession,
              session.journal.session.sessionID == descriptor.sessionID,
              session.journal.session.jobID == descriptor.jobID else {
            throw ConnectedCorpusTransferModelError.mismatchedSession
        }
        guard partitionExecutionSessionID == nil else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let executionSessionID = descriptor.sessionID
        partitionExecutionSessionID = executionSessionID
        defer {
            if partitionExecutionSessionID == executionSessionID {
                partitionExecutionSessionID = nil
            }
            if pendingDisconnectSessionIDs.remove(executionSessionID) != nil {
                completeDisconnectSuspension(session)
            }
        }
        let committedCount = session.journal.committedPartitions.count
        if descriptor.index < committedCount {
            guard session.journal.committedPartitions[descriptor.index].sha256 == descriptor.sha256 else {
                throw ConnectedCorpusTransferModelError.invalidDigestChain
            }
            return
        }
        guard descriptor.index == committedCount,
              descriptor.previousSHA256 == session.journal.committedPartitions.last?.sha256 else {
            throw ConnectedCorpusTransferModelError.invalidDigestChain
        }

        let parsed = try ConnectedCorpusPartitionReader.parseManifest(
            at: fileURL,
            expected: descriptor
        )
        try validateItemContinuity(
            segments: parsed.manifest.segments,
            session: session
        )
        guard let protectedSessionDeviceID = session.journal.protectedSessionDeviceID,
              let protectedSessionInode = session.journal.protectedSessionInode else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var completedItems: [(ConnectedCorpusItemSegment, URL)] = []
        try ConnectedCorpusPartitionReader.applySegments(
            from: fileURL,
            parsed: parsed,
            protectedRootURL: session.directoryURL,
            protectedRootDeviceID: protectedSessionDeviceID,
            protectedRootInode: protectedSessionInode,
            destinationURL: { segment in
                session.itemDirectoryURL.appendingPathComponent("\(segment.itemID.uuidString).item")
            },
            completedItem: { segment, url in
                completedItems.append((segment, url))
            }
        )

        // Output writes use overwrite/atomic replacement semantics, but the
        // in-memory journal must also roll back if a later item in this same
        // partition fails. Otherwise replay would mistake the first item for a
        // durable duplicate even though the partition was never acknowledged.
        let journalBeforePartition = session.journal
        do {
            var projectedContextDays: [HealthMdCompactContextDay] = []
            for (segment, itemURL) in completedItems {
                switch segment.kind {
                case .macHealthDay:
                    if let contextDay = try await applyHealthDay(
                        itemURL: itemURL,
                        segment: segment,
                        session: session,
                        vaultManager: vaultManager
                    ) {
                        projectedContextDays.append(contextDay)
                    }
                case .strictRawDay:
                    try applyRawDay(itemURL: itemURL, segment: segment, session: session)
                }
                try ensurePartitionExecutionIsActive(session)
            }

            // Dedicated encrypted-context acquisitions commit their query
            // projection as part of application-level partition durability.
            // Ordinary file exports must remain independent of this disposable
            // local cache: a missing Keychain key or corrupt context index must
            // never reject otherwise valid export bytes.
            if session.journal.exportManifest.mode == .encryptedContext,
               !projectedContextDays.isEmpty,
               let queryContextStore {
                let selectedMetrics = Set(
                    session.journal.exportManifest.settingsSnapshot.metricSelection.enabledMetricIDs
                )
                var selectedSources = Set(
                    session.journal.exportManifest.selectedSourceIDs ?? ["apple_health"]
                )
                if session.journal.exportManifest.selectedSourceIDs == nil {
                    for day in projectedContextDays {
                        for evidence in day.evidence {
                            if let providerID = evidence.reference.providerID {
                                selectedSources.insert(providerID)
                            }
                        }
                    }
                }
                try await queryContextStore.mergeScoped(
                    projectedContextDays,
                    replacingMetricIDs: selectedMetrics,
                    sourceIDs: selectedSources
                )
                try ensurePartitionExecutionIsActive(session)
            }

            for segment in parsed.manifest.segments {
                if segment.isFinalSegment {
                    session.journal.partialItems.removeAll { $0.itemID == segment.itemID }
                    session.journal.completedItemIDs.append(segment.itemID)
                } else if let index = session.journal.partialItems.firstIndex(where: {
                    $0.itemID == segment.itemID
                }) {
                    session.journal.partialItems[index].nextOffset = segment.itemOffset + segment.segmentBytes
                } else {
                    session.journal.partialItems.append(PartialItem(
                        itemID: segment.itemID,
                        kind: segment.kind,
                        sourceDate: segment.sourceDate,
                        isRequestedDate: segment.isRequestedDate,
                        totalItemBytes: segment.totalItemBytes,
                        itemSHA256: segment.itemSHA256,
                        nextOffset: segment.itemOffset + segment.segmentBytes,
                        prefixSHA256: nil
                    ))
                }
            }
            for segment in parsed.manifest.segments where !segment.isFinalSegment {
                guard let index = session.journal.partialItems.firstIndex(where: {
                    $0.itemID == segment.itemID
                }) else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                let inspection = try inspectProtectedSessionFile(
                    relativePath: "items/\(segment.itemID.uuidString).item",
                    sessionDirectoryURL: session.directoryURL
                )
                guard inspection.byteCount == session.journal.partialItems[index].nextOffset else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                session.journal.partialItems[index].prefixSHA256 = inspection.sha256
            }
            session.journal.committedPartitions.append(descriptor)
            session.journal.totalPartitionBytes += descriptor.byteCount
            session.journal.updatedAt = Date()
            // File contents were synchronized by the partition reader/protected writer. Publish
            // every create/move/remove directory entry before the journal can acknowledge it.
            try syncDirectory(at: session.itemDirectoryURL)
            try syncDirectory(at: session.recordDirectoryURL)
            try syncDirectory(at: session.rawDirectoryURL)
            try syncDirectory(at: session.directoryURL)
            try persist(session)
        } catch {
            session.journal = journalBeforePartition
            throw error
        }
    }

    func finalize(
        _ finalize: ConnectedCorpusTransferFinalize,
        vaultManager: VaultManager,
        progress: ((_ processed: Int, _ total: Int, _ date: Date?) -> Void)? = nil
    ) async throws -> MacCorpusFinalizeOutcome {
        let session: Session
        if let activeSession {
            session = activeSession
        } else if let restored = try restoreSession(sessionID: finalize.sessionID) {
            session = restored
        } else {
            throw ConnectedCorpusTransferModelError.mismatchedSession
        }
        guard session.journal.session.sessionID == finalize.sessionID,
              session.journal.session.jobID == finalize.jobID,
              session.journal.session.requestFingerprint == finalize.requestFingerprint else {
            throw ConnectedCorpusTransferModelError.mismatchedSession
        }
        if (session.journal.state == .completed || session.journal.state == .failed),
           let acknowledgement = session.journal.terminalAcknowledgement,
           acknowledgement.finalPartitionSHA256 == finalize.finalPartitionSHA256,
           finalize.partitionCount == session.journal.committedPartitions.count,
           finalize.totalByteCount == session.journal.totalPartitionBytes {
            if session.journal.state == .failed,
               let failure = session.journal.terminalFailure {
                cleanupPayloadFiles(session)
                if activeSession === session { activeSession = nil }
                admittedPartitions.removeAll()
                return .failed(failure: failure, acknowledgement: acknowledgement)
            }
            if let storedSpool = session.journal.strictRawTerminalSpool {
                let spool = try restoreStrictRawTerminalSpool(storedSpool, session: session)
                cleanupPayloadFiles(session)
                if activeSession === session { activeSession = nil }
                admittedPartitions.removeAll()
                return .strictRaw(spool: spool, acknowledgement: acknowledgement)
            }
            cleanupPayloadFiles(session)
            if activeSession === session { activeSession = nil }
            admittedPartitions.removeAll()
            return .replay(
                acknowledgement: acknowledgement,
                fileResult: session.journal.terminalResult
            )
        }
        if finalizationExecutionSessionID == finalize.sessionID {
            return .inProgress
        }
        guard session.journal.state == .open || session.journal.state == .finalizing else {
            throw ConnectedCorpusTransferModelError.invalidFinalization
        }
        activeSession = session
        finalizationExecutionSessionID = finalize.sessionID
        defer {
            if finalizationExecutionSessionID == finalize.sessionID {
                finalizationExecutionSessionID = nil
            }
        }
        admittedPartitions.removeAll()
        let journal = session.journal
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "connected-mac",
                phase: "finalize-corpus",
                timer: performanceTimer,
                itemCount: journal.exportManifest.transferDates.count,
                byteCount: journal.totalPartitionBytes
            )
        }
        #endif
        guard finalize.partitionCount == journal.committedPartitions.count,
              finalize.totalByteCount == journal.totalPartitionBytes,
              finalize.finalPartitionSHA256 == journal.committedPartitions.last?.sha256,
              journal.partialItems.isEmpty,
              Set(journal.processedDates) == Set(journal.exportManifest.transferDates) else {
            throw ConnectedCorpusTransferModelError.invalidFinalization
        }
        let safetyBytes: Int64 = 128 * 1_024 * 1_024
        let writeFilesSettings: AdvancedExportSettings?
        if journal.exportManifest.mode == .writeFiles {
            writeFilesSettings = journal.exportManifest.settingsSnapshot.makeAdvancedExportSettings()
        } else {
            writeFilesSettings = nil
        }
        let requiresWriteFilesDerivedOutputs = writeFilesSettings.map {
            $0.archiveModeEnabled || HealthRollupExporter.isEnabled(settings: $0)
        } ?? false
        if journal.exportManifest.mode == .strictRaw {
            let required = journal.totalPartitionBytes.multipliedReportingOverflow(by: 2)
            let withSafety = required.partialValue.addingReportingOverflow(safetyBytes)
            guard !required.overflow, !withSafety.overflow,
                  hasAvailableDiskSpace(at: rootURL, requiredBytes: withSafety.partialValue) else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
        } else if requiresWriteFilesDerivedOutputs, let vaultURL = vaultManager.vaultURL {
            let formatMultiplier = Int64(max(
                journal.exportManifest.settingsSnapshot.exportFormats.count,
                1
            ))
            let expanded = journal.totalPartitionBytes.multipliedReportingOverflow(
                by: formatMultiplier
            )
            let required = expanded.partialValue.addingReportingOverflow(safetyBytes)
            guard !expanded.overflow, !required.overflow,
                  hasAvailableDiskSpace(at: vaultURL, requiredBytes: required.partialValue) else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        let journalBeforeFinalizing = session.journal
        session.journal.state = .finalizing
        session.journal.updatedAt = Date()
        do {
            try persist(session)
        } catch JournalPersistenceError.postPublication {
            activeSession = nil
            admittedPartitions.removeAll()
            return .inProgress
        } catch {
            session.journal = journalBeforeFinalizing
            throw error
        }

        switch journal.exportManifest.mode {
        case .encryptedContext:
            let journalBeforeTerminalCommit = session.journal
            session.journal.state = .completed
            session.journal.updatedAt = Date()
            let result = makeFileResult(session: session)
            let acknowledgement = ConnectedCorpusTransferFinalAck(
                sessionID: finalize.sessionID,
                jobID: finalize.jobID,
                accepted: true,
                requestFingerprint: finalize.requestFingerprint,
                finalPartitionSHA256: finalize.finalPartitionSHA256,
                completedDates: result.completedDates,
                successCount: result.successCount,
                totalCount: result.totalCount,
                message: "Encrypted query context finalized."
            )
            session.journal.terminalResult = result
            session.journal.terminalAcknowledgement = acknowledgement
            do {
                try persist(session)
            } catch JournalPersistenceError.postPublication {
                activeSession = nil
                admittedPartitions.removeAll()
                return .inProgress
            } catch {
                session.journal = journalBeforeTerminalCommit
                activeSession = nil
                admittedPartitions.removeAll()
                return .inProgress
            }
            cleanupPayloadFiles(session)
            activeSession = nil
            admittedPartitions.removeAll()
            return .files(result: result, acknowledgement: acknowledgement)

        case .writeFiles:
            guard let derivedSettings = writeFilesSettings else {
                throw ConnectedCorpusTransferModelError.invalidFinalization
            }
            derivedSettings.exportTimeZoneOverride = journal.exportManifest.sourceTimeZoneIdentifier
                .flatMap(TimeZone.init(identifier:))
            var sourceCalendar = Calendar.current
            sourceCalendar.timeZone = derivedSettings.exportTimeZoneOverride ?? .current
            let capturedRecordDates = Set(session.journal.recordItems.map(\.sourceDate))
            let unavailableRollupDates = Set(journal.exportManifest.transferDates).subtracting(
                capturedRecordDates
            )
            var rollupBlockedRequestedDates: Set<Date> = []
            if !unavailableRollupDates.isEmpty && derivedSettings.rollupSummariesEnabled {
                for requestedDate in journal.exportManifest.requestedDates {
                    let affectsRequestedDate = derivedSettings.enabledRollupPeriods.contains { period in
                        // Range v9 reports partial coverage from the immutable request. Missing
                        // source days must not suppress or fail the range artifact.
                        guard period != .range else { return false }
                        let window = HealthRollupPeriodWindow.window(
                            containing: requestedDate,
                            period: period,
                            calendar: sourceCalendar
                        )
                        return unavailableRollupDates.contains { $0 >= window.startDate && $0 <= window.endDate }
                    }
                    if affectsRequestedDate {
                        rollupBlockedRequestedDates.insert(requestedDate)
                        session.journal.completedDates.removeAll { $0 == requestedDate }
                        let sourceDays = unavailableRollupDates
                            .map { Self.sourceDateString($0, timeZone: sourceCalendar.timeZone) }
                            .sorted()
                            .joined(separator: ", ")
                        if !session.journal.failedDateDetails.contains(where: { $0.date == requestedDate }) {
                            session.journal.failedDateDetails.append(FailedDateDetail(
                                date: requestedDate,
                                reason: .healthKitError,
                                errorDetails: "Roll-up source capture failed for: \(sourceDays)."
                            ))
                        }
                    }
                }
            }
            let successfulRequestedDates = Set(session.journal.successfulRequestedDates)
            let requestedDates = Set(journal.exportManifest.requestedDates)
            let derivedRecordItems = journal.recordItems.filter {
                !requestedDates.contains($0.sourceDate)
                    || successfulRequestedDates.contains($0.sourceDate)
            }
            let usesRangePlan = session.dailyExportOperation?.usesRangePlan == true
            var effectiveRangeSettingsSnapshot = journal.exportManifest.settingsSnapshot
            if usesRangePlan {
                let rangeAvailability = ExportOrchestrator.settingsByDisablingUnavailableRangeSummary(
                    effectiveRangeSettingsSnapshot,
                    requestedDates: journal.exportManifest.effectiveOriginalRequestedDates,
                    calendarTimeZone: sourceCalendar.timeZone
                )
                effectiveRangeSettingsSnapshot = rangeAvailability.snapshot
                derivedSettings.generateRangeSummary = effectiveRangeSettingsSnapshot.generateRangeSummary
                if let warning = rangeAvailability.warning,
                   !(session.journal.derivedOutputPartialFailures ?? []).contains(warning) {
                    session.journal.derivedOutputPartialFailures =
                        (session.journal.derivedOutputPartialFailures ?? []) + [warning]
                }
            }
            let derived: MacCorpusDerivedOutputResult
            if usesRangePlan {
                    guard let calendarTimeZoneIdentifier = journal.exportManifest
                        .settingsSnapshot.calendarTimeZoneIdentifier else {
                        throw ConnectedMacDailyExportOperation.ResolutionError.unsupportedPinnedOperation
                    }
                    let rangeResult: AppleLooseDailyRangeWriteResult
                    let requestedRecordDatesWithData: Set<Date>
                    if let storedPlan = session.journal.receivedRangePlan {
                        requestedRecordDatesWithData = Set(storedPlan.requestedRecordDatesWithData)
                        do {
                            rangeResult = try await commitStoredReceivedRangePlan(
                                session: session,
                                vaultManager: vaultManager
                            )
                        } catch ReceivedRangeCommitError.transient {
                            activeSession = nil
                            admittedPartitions.removeAll()
                            return .inProgress
                        } catch ReceivedRangeCommitError.invalid {
                            throw ConnectedCorpusTransferModelError.invalidJournal
                        }
                    } else {
                        guard session.journal.receivedRangePlanPersisted == false else {
                            throw ConnectedCorpusTransferModelError.invalidJournal
                        }
                        let effectiveRecordItems = effectiveRangeSettingsSnapshot.generateRangeSummary
                            ? derivedRecordItems
                            : derivedRecordItems.filter { requestedDates.contains($0.sourceDate) }
                        let rangeInput = try receivedRangeInput(
                            session: session,
                            items: effectiveRecordItems,
                            settings: derivedSettings,
                            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
                        )
                        requestedRecordDatesWithData = rangeInput.requestedRecordDatesWithData
                        if !derivedSettings.summaryOnlyModeEnabled {
                            let emptyRequestedDates = Set(session.journal.successfulRequestedDates)
                                .subtracting(rangeInput.requestedRecordDatesWithData)
                            for date in emptyRequestedDates {
                                if !session.journal.failedDateDetails.contains(where: { $0.date == date }) {
                                    session.journal.failedDateDetails.append(FailedDateDetail(
                                        date: date,
                                        reason: .noHealthData
                                    ))
                                }
                                if !session.journal.completedDates.contains(date) {
                                    session.journal.completedDates.append(date)
                                }
                            }
                            session.journal.successfulRequestedDates.removeAll {
                                emptyRequestedDates.contains($0)
                            }
                        }
                        if rangeInput.records.isEmpty || !rangeInput.hasAnyData {
                            rangeResult = AppleLooseDailyRangeWriteResult(
                                dailyFileCount: 0,
                                rollupFileCount: 0
                            )
                        } else {
                            let requestedRange = try effectiveRangeSettingsSnapshot.generateRangeSummary
                                ? HealthRollupRangeRequest(
                                    ownerDateIdentifiers: Set(journal.exportManifest.effectiveOriginalRequestedDates.map {
                                        HealthKitDailyOwnershipMetadata.ownerDate(
                                            for: $0,
                                            calendarTimeZoneIdentifier: journal.exportManifest
                                                .effectiveOriginalCalendarTimeZoneIdentifier
                                                ?? calendarTimeZoneIdentifier
                                        )
                                    }),
                                    calendarTimeZoneIdentifier: journal.exportManifest
                                        .effectiveOriginalCalendarTimeZoneIdentifier
                                        ?? calendarTimeZoneIdentifier
                                )
                                : nil
                            guard let materialized = try await vaultManager.materializeHealthDataRange(
                                rangeInput.records,
                                settingsSnapshot: effectiveRangeSettingsSnapshot,
                                operationSurface: .connectedReceivedRangeWithoutSideEffects,
                                dailyOutputOwnerDates: rangeInput.dailyOutputOwnerDates,
                                requestedRange: requestedRange,
                                operationIdentity: AppleExportOperationIdentity(
                                    requestID: journal.session.jobID.uuidString.lowercased(),
                                    sessionID: journal.session.sessionID.uuidString.lowercased(),
                                    capturedAt: journal.exportManifest.createdAt,
                                    calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
                                ),
                                includeDataDictionary: session.journal.dataDictionaryWritten != true
                            ) else {
                                throw ConnectedMacDailyExportOperation.ResolutionError.unsupportedPinnedOperation
                            }
                            do {
                                try persistReceivedRangePlan(
                                    materialized,
                                    requestedRecordDatesWithData: rangeInput.requestedRecordDatesWithData,
                                    session: session,
                                    vaultManager: vaultManager
                                )
                            } catch ReceivedRangeCommitError.transient {
                                activeSession = nil
                                admittedPartitions.removeAll()
                                return .inProgress
                            }
                            do {
                                rangeResult = try await commitStoredReceivedRangePlan(
                                    session: session,
                                    vaultManager: vaultManager
                                )
                            } catch ReceivedRangeCommitError.transient {
                                activeSession = nil
                                admittedPartitions.removeAll()
                                return .inProgress
                            } catch ReceivedRangeCommitError.invalid {
                                throw ConnectedCorpusTransferModelError.invalidJournal
                            }
                        }
                    }
                    try ensureFinalizationIsActive(session)
                    session.journal.totalFilesWritten += rangeResult.totalFileCount
                    if rangeResult.totalFileCount > 0 {
                        session.journal.dataDictionaryWritten = true
                    }
                    if !derivedSettings.summaryOnlyModeEnabled,
                       rangeResult.dailyFileCount > 0 {
                        session.journal.completedDates = Array(Set(
                            session.journal.completedDates
                                + requestedRecordDatesWithData
                        )).sorted()
                    }
                    derived = MacCorpusDerivedOutputResult(
                        rollupFileCount: rangeResult.rollupFileCount,
                        archiveFileCount: 0
                    )
            } else {
                if derivedSettings.generateRangeSummary,
                   let originalTimeZoneIdentifier = journal.exportManifest
                    .effectiveOriginalCalendarTimeZoneIdentifier,
                   let originalTimeZone = TimeZone(identifier: originalTimeZoneIdentifier) {
                    do {
                        _ = try HealthRollupRangeRequest(
                            ownerDateIdentifiers: Set(
                                journal.exportManifest.effectiveOriginalRequestedDates.map {
                                    HealthKitDailyOwnershipMetadata.ownerDate(
                                        for: $0,
                                        calendarTimeZoneIdentifier: originalTimeZoneIdentifier
                                    )
                                }
                            ),
                            calendarTimeZoneIdentifier: originalTimeZoneIdentifier
                        )
                    } catch HealthRollupRangeRequest.ValidationError.exceedsDayLimit {
                        let originalDates = journal.exportManifest.effectiveOriginalRequestedDates
                        let firstDate = originalDates.first
                            ?? journal.exportManifest.dateRangeStart
                        let lastDate = originalDates.last ?? firstDate
                        let formatter = DateFormatter()
                        formatter.calendar = Calendar(identifier: .gregorian)
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        formatter.timeZone = originalTimeZone
                        formatter.dateFormat = "yyyy-MM-dd"
                        let first = formatter.string(from: firstDate)
                        let last = formatter.string(from: lastDate)
                        let warning = ExportPartialFailure(
                            date: firstDate,
                            dataType: "Range Summary",
                            dateRangeDescription: first == last ? first : "\(first) – \(last)",
                            errorDescription: HealthRollupRangeRequest.dayLimitUnavailableMessage
                        )
                        if !(session.journal.derivedOutputPartialFailures ?? []).contains(warning) {
                            session.journal.derivedOutputPartialFailures =
                                (session.journal.derivedOutputPartialFailures ?? []) + [warning]
                        }
                    } catch {
                        // Other invalid authority remains a finalization failure below.
                    }
                }
                let archiveWorkDirectoryURL = vaultManager.vaultURL.map {
                    Self.archiveWorkDirectoryURL(vaultURL: $0, sessionID: journal.session.sessionID)
                }
                derived = try await vaultManager.finalizeCorpusDerivedOutputs(
                    recordPayloadFiles: derivedRecordItems.map {
                        session.directoryURL.appendingPathComponent($0.relativePath)
                    },
                    recordSourceDates: derivedRecordItems.map(\.sourceDate),
                    settings: derivedSettings,
                    requestedDates: journal.exportManifest.requestedDates,
                    rollupRequestedDates: journal.exportManifest.effectiveOriginalRequestedDates,
                    rollupCalendarTimeZoneIdentifier: journal.exportManifest
                        .effectiveOriginalCalendarTimeZoneIdentifier,
                    startDate: journal.exportManifest.dateRangeStart,
                    endDate: journal.exportManifest.dateRangeEnd,
                    healthSubfolder: journal.exportManifest.settingsSnapshot.healthSubfolder,
                    archiveWorkDirectoryURL: archiveWorkDirectoryURL,
                    unavailableRollupDates: unavailableRollupDates,
                    writeDataDictionary: session.journal.dataDictionaryWritten != true,
                    corpusProtocolVersion: journal.session.protocolVersion,
                    progress: progress,
                    cancellationCheck: {
                        self.activeSession !== session || session.journal.state == .cancelled
                    }
                )
                try ensureFinalizationIsActive(session)
                session.journal.totalFilesWritten += derived.rollupFileCount + derived.archiveFileCount
                if derived.rollupFileCount > 0 { session.journal.dataDictionaryWritten = true }
                if let archiveWorkDirectoryURL {
                    try? fileManager.removeItem(at: archiveWorkDirectoryURL)
                    let parent = archiveWorkDirectoryURL.deletingLastPathComponent()
                    if (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
                        try? fileManager.removeItem(at: parent)
                    }
                }
            }

            let settings = usesRangePlan
                ? derivedSettings
                : journal.exportManifest.settingsSnapshot.makeAdvancedExportSettings()
            if settings.summaryOnlyModeEnabled && derived.rollupFileCount == 0
                && (!usesRangePlan || session.journal.failedDateDetails.isEmpty) {
                let terminalFailures = ExportOrchestrator.terminalNoDataFailures(
                    for: journal.exportManifest.requestedDates,
                    calendar: sourceCalendar
                )
                session.journal.failedDateDetails.append(contentsOf: terminalFailures.filter { failure in
                    !session.journal.failedDateDetails.contains(where: { existing in
                        sourceCalendar.isDate(existing.date, inSameDayAs: failure.date)
                    })
                })
                session.journal.completedDates = Array(Set(
                    session.journal.completedDates + journal.exportManifest.requestedDates
                )).sorted()
            }
            let failedRequestedDates = Set(session.journal.failedDateDetails.map(\.date))
            if settings.archiveModeEnabled && derived.archiveFileCount > 0 {
                session.journal.completedDates = Array(Set(
                    session.journal.completedDates + session.journal.successfulRequestedDates.filter {
                        !rollupBlockedRequestedDates.contains($0)
                            && !failedRequestedDates.contains($0)
                    }
                )).sorted()
            } else if settings.summaryOnlyModeEnabled && derived.rollupFileCount > 0 {
                session.journal.completedDates = Array(Set(
                    session.journal.completedDates + session.journal.successfulRequestedDates.filter {
                        !rollupBlockedRequestedDates.contains($0)
                            && !failedRequestedDates.contains($0)
                    }
                )).sorted()
            }
            let journalBeforeTerminalCommit = session.journal
            session.journal.state = .completed
            session.journal.updatedAt = Date()
            let result = makeFileResult(session: session)
            let acknowledgement = ConnectedCorpusTransferFinalAck(
                sessionID: finalize.sessionID,
                jobID: finalize.jobID,
                accepted: true,
                requestFingerprint: finalize.requestFingerprint,
                finalPartitionSHA256: finalize.finalPartitionSHA256,
                completedDates: result.completedDates,
                successCount: result.successCount,
                totalCount: result.totalCount,
                message: "Corpus export finalized."
            )
            session.journal.terminalResult = result
            session.journal.terminalAcknowledgement = acknowledgement
            if usesRangePlan, session.journal.receivedRangePlanPersisted == true {
                session.journal.receivedRangePlan = nil
            }
            do {
                try persist(session)
            } catch JournalPersistenceError.postPublication {
                activeSession = nil
                admittedPartitions.removeAll()
                return .inProgress
            } catch {
                session.journal = journalBeforeTerminalCommit
                if usesRangePlan, journalBeforeTerminalCommit.receivedRangePlan != nil {
                    activeSession = nil
                    admittedPartitions.removeAll()
                    return .inProgress
                }
                throw error
            }
            cleanupPayloadFiles(session)
            activeSession = nil
            admittedPartitions.removeAll()
            return .files(result: result, acknowledgement: acknowledgement)

        case .strictRaw:
            let dateFormatter = Self.sourceDateFormatter
            let identifiersBySourceDate = Dictionary(uniqueKeysWithValues: session.journal.rawItems.map {
                ($0.sourceDate, $0.dateIdentifier ?? dateFormatter.string(from: $0.sourceDate))
            })
            guard let expectedDates = journal.exportManifest.requestedDateIdentifiers else {
                throw ConnectedCorpusTransferModelError.invalidFinalization
            }
            for (sourceDate, expectedIdentifier) in zip(
                journal.exportManifest.requestedDates,
                expectedDates
            ) {
                guard identifiersBySourceDate[sourceDate] == expectedIdentifier else {
                    throw ConnectedCorpusTransferModelError.invalidFinalization
                }
            }
            let reportProgress: (Int, Int) -> Void = { processed, total in
                let date = processed > 0 && processed <= journal.exportManifest.requestedDates.count
                    ? journal.exportManifest.requestedDates[processed - 1]
                    : nil
                progress?(processed, total, date)
            }
            let isCancelled = {
                self.activeSession !== session || session.journal.state == .cancelled
            }
            let spool: CanonicalRawResultSpool
            if ConnectedCorpusApplicationItemCodec.usesStreamableItems(
                protocolVersion: journal.session.protocolVersion
            ) {
                var temporaryCanonicalFiles: [ConnectedTransferPreparedFile] = []
                defer { temporaryCanonicalFiles.forEach { $0.remove() } }
                var sourcesByDate: [String: CanonicalRawStoredDaySource] = [:]
                for item in session.journal.rawItems {
                    guard let itemByteCount = item.byteCount,
                          let itemSHA256 = item.sha256 else {
                        throw ConnectedCorpusTransferModelError.invalidJournal
                    }
                    let descriptor = try openVerifiedProtectedSessionFile(
                        relativePath: item.relativePath,
                        expectedByteCount: itemByteCount,
                        expectedSHA256: itemSHA256,
                        sessionDirectoryURL: session.directoryURL
                    )
                    let decoded: ConnectedCorpusApplicationItemCodec.DecodedRawDay
                    do {
                        decoded = try ConnectedCorpusApplicationItemCodec.decodeRawDay(
                            fromFileDescriptor: descriptor,
                            extractCanonicalJSON: false
                        )
                    } catch {
                        Darwin.close(descriptor)
                        throw error
                    }
                    Darwin.close(descriptor)
                    let identifier = item.dateIdentifier ?? dateFormatter.string(from: item.sourceDate)
                    guard decoded.sourceDate == item.sourceDate,
                          decoded.day.date == identifier else {
                        throw ConnectedCorpusTransferModelError.invalidJournal
                    }
                    let canonicalFile: ConnectedTransferPreparedFile?
                    if decoded.hasCanonicalJSON {
                        guard let relativePath = item.canonicalJSONRelativePath,
                              let byteCount = item.canonicalJSONByteCount,
                              let sha256 = item.canonicalJSONSHA256 else {
                            throw ConnectedCorpusTransferModelError.invalidJournal
                        }
                        let temporaryURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
                            prefix: "validated-corpus-canonical-day"
                        )
                        do {
                            try copyProtectedSessionFileToURL(
                                relativePath: relativePath,
                                session: session,
                                destinationURL: temporaryURL,
                                expectedByteCount: byteCount,
                                expectedSHA256: sha256
                            )
                            let prepared = try ConnectedTransferFile.inspect(temporaryURL)
                            guard prepared.totalBytes == byteCount,
                                  prepared.sha256 == sha256 else {
                                throw ConnectedCorpusTransferModelError.invalidJournal
                            }
                            temporaryCanonicalFiles.append(prepared)
                            canonicalFile = prepared
                        } catch {
                            try? fileManager.removeItem(at: temporaryURL)
                            throw error
                        }
                    } else {
                        guard item.canonicalJSONRelativePath == nil,
                              item.canonicalJSONByteCount == nil,
                              item.canonicalJSONSHA256 == nil else {
                            throw ConnectedCorpusTransferModelError.invalidJournal
                        }
                        canonicalFile = nil
                    }
                    guard sourcesByDate.updateValue(
                        CanonicalRawStoredDaySource(
                            day: decoded.day,
                            canonicalJSONFile: canonicalFile
                        ),
                        forKey: identifier
                    ) == nil else {
                        throw ConnectedCorpusTransferModelError.invalidJournal
                    }
                }
                let orderedSources = try expectedDates.map { date -> CanonicalRawStoredDaySource in
                    guard let source = sourcesByDate[date] else {
                        throw ConnectedCorpusTransferModelError.invalidFinalization
                    }
                    return source
                }
                spool = try await CanonicalRawResultSpoolWriter.writeStreamed(
                    profile: journal.exportManifest.rawProfile ?? .canonicalSourceRecordsV1,
                    canonicalSelection: journal.exportManifest.canonicalSelection,
                    createdAt: journal.exportManifest.createdAt,
                    sourceDeviceName: journal.exportManifest.sourceDeviceName,
                    expectedDates: expectedDates,
                    daySources: orderedSources,
                    progress: reportProgress,
                    cancellationCheck: isCancelled
                )
            } else {
                var validatedRawURLs: [URL] = []
                defer { validatedRawURLs.forEach { try? fileManager.removeItem(at: $0) } }
                var rawFilesByDate: [String: URL] = [:]
                for item in session.journal.rawItems {
                    let data = try protectedStoredItemData(
                        item,
                        sessionDirectoryURL: session.directoryURL
                    )
                    let validatedURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
                        prefix: "validated-corpus-raw-day"
                    )
                    do {
                        let handle = try FileHandle(forWritingTo: validatedURL)
                        try handle.write(contentsOf: data)
                        try handle.synchronize()
                        try handle.close()
                    } catch {
                        try? fileManager.removeItem(at: validatedURL)
                        throw error
                    }
                    validatedRawURLs.append(validatedURL)
                    let identifier = item.dateIdentifier ?? dateFormatter.string(from: item.sourceDate)
                    guard rawFilesByDate.updateValue(validatedURL, forKey: identifier) == nil else {
                        throw ConnectedCorpusTransferModelError.invalidJournal
                    }
                }
                let orderedFiles = try expectedDates.map { date -> URL in
                    guard let url = rawFilesByDate[date] else {
                        throw ConnectedCorpusTransferModelError.invalidFinalization
                    }
                    return url
                }
                spool = try await CanonicalRawResultSpoolWriter.write(
                    profile: journal.exportManifest.rawProfile ?? .canonicalSourceRecordsV1,
                    canonicalSelection: journal.exportManifest.canonicalSelection,
                    createdAt: journal.exportManifest.createdAt,
                    sourceDeviceName: journal.exportManifest.sourceDeviceName,
                    expectedDates: expectedDates,
                    dayFiles: orderedFiles,
                    progress: reportProgress,
                    cancellationCheck: isCancelled
                )
            }
            try ensureFinalizationIsActive(session)
            let journalBeforeTerminalCommit = session.journal
            let storedTerminalSpool: StoredStrictRawTerminalSpool
            do {
                storedTerminalSpool = try persistStrictRawTerminalSpool(spool, session: session)
            } catch {
                spool.remove()
                throw error
            }
            session.journal.state = .completed
            session.journal.strictRawRetainedDayCount = spool.captureSummary.retainedDayCount
            session.journal.strictRawTerminalSpool = storedTerminalSpool
            session.journal.updatedAt = Date()
            let acknowledgement = ConnectedCorpusTransferFinalAck(
                sessionID: finalize.sessionID,
                jobID: finalize.jobID,
                accepted: true,
                requestFingerprint: finalize.requestFingerprint,
                finalPartitionSHA256: finalize.finalPartitionSHA256,
                completedDates: journal.exportManifest.requestedDates,
                successCount: spool.captureSummary.retainedDayCount,
                totalCount: spool.totalRequestedDays,
                message: "Strict raw corpus finalized."
            )
            session.journal.terminalAcknowledgement = acknowledgement
            do {
                try persist(session)
            } catch JournalPersistenceError.postPublication {
                spool.remove()
                activeSession = nil
                admittedPartitions.removeAll()
                return .inProgress
            } catch {
                session.journal = journalBeforeTerminalCommit
                spool.remove()
                try? removeProtectedStrictRawTerminalSpool(session)
                activeSession = nil
                admittedPartitions.removeAll()
                return .inProgress
            }
            cleanupPayloadFiles(session)
            activeSession = nil
            admittedPartitions.removeAll()
            return .strictRaw(spool: spool, acknowledgement: acknowledgement)
        }
    }

    /// Durably binds an application failure to its rejected final acknowledgement.
    /// Returning nil means neither message is safe to publish; the sender must pause
    /// and retry finalization instead of becoming terminal without failure details.
    func recordFinalizationFailure(
        _ finalize: ConnectedCorpusTransferFinalize,
        failure: MacExportFailure,
        vaultManager: VaultManager
    ) -> ConnectedCorpusTransferFinalAck? {
        let session: Session
        if let activeSession {
            session = activeSession
        } else if let restored = try? restoreSession(sessionID: finalize.sessionID) {
            session = restored
        } else {
            return nil
        }
        guard session.journal.session.sessionID == finalize.sessionID,
              session.journal.session.jobID == finalize.jobID,
              session.journal.session.requestFingerprint == finalize.requestFingerprint,
              finalize.partitionCount == session.journal.committedPartitions.count,
              finalize.totalByteCount == session.journal.totalPartitionBytes,
              finalize.finalPartitionSHA256 == session.journal.committedPartitions.last?.sha256 else {
            return nil
        }
        if session.journal.state == .failed,
           session.journal.terminalFailure == failure,
           let acknowledgement = session.journal.terminalAcknowledgement {
            return acknowledgement
        }
        guard session.journal.state == .open || session.journal.state == .finalizing,
              destinationCommitInFlightSessionID != finalize.sessionID,
              partitionExecutionSessionID != finalize.sessionID else {
            return nil
        }

        let acknowledgement = ConnectedCorpusTransferFinalAck(
            sessionID: finalize.sessionID,
            jobID: finalize.jobID,
            accepted: false,
            requestFingerprint: finalize.requestFingerprint,
            finalPartitionSHA256: finalize.finalPartitionSHA256,
            message: failure.message
        )
        let journalBeforeFailure = session.journal
        session.journal.state = .failed
        session.journal.terminalResult = nil
        session.journal.terminalFailure = failure
        session.journal.terminalAcknowledgement = acknowledgement
        session.journal.receivedRangePlan = nil
        session.journal.updatedAt = Date()
        do {
            try persist(session)
        } catch {
            session.journal = journalBeforeFailure
            activeSession = nil
            admittedPartitions.removeAll()
            return nil
        }
        cleanupPayloadFiles(session)
        cleanupArchiveWork(session: session, vaultManager: vaultManager)
        activeSession = nil
        admittedPartitions.removeAll()
        return acknowledgement
    }

    func cancel(
        jobID: UUID,
        vaultManager: VaultManager
    ) -> (ConnectedCorpusTransferCancelAck, MacExportResultPayload?)? {
        if let activeSession, activeSession.journal.session.jobID == jobID {
            return cancel(
                sessionID: activeSession.journal.session.sessionID,
                jobID: jobID,
                vaultManager: vaultManager
            )
        }
        guard activeSession == nil,
              let directories = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return nil }
        let candidates = directories.compactMap { directory -> Session? in
            guard let sessionID = UUID(uuidString: directory.lastPathComponent),
                  let session = try? restoreSession(sessionID: sessionID),
                  session.journal.session.jobID == jobID,
                  session.journal.state == .open || session.journal.state == .finalizing else {
                return nil
            }
            return session
        }
        guard let session = candidates.max(by: { $0.journal.updatedAt < $1.journal.updatedAt }) else {
            return nil
        }
        activeSession = session
        return cancel(
            sessionID: session.journal.session.sessionID,
            jobID: jobID,
            vaultManager: vaultManager
        )
    }

    func cancel(
        sessionID: UUID,
        jobID: UUID,
        vaultManager: VaultManager
    ) -> (ConnectedCorpusTransferCancelAck, MacExportResultPayload?) {
        if destinationCommitInFlightSessionID == sessionID
            || partitionExecutionSessionID == sessionID {
            return (
                ConnectedCorpusTransferCancelAck(
                    sessionID: sessionID,
                    jobID: jobID,
                    accepted: false,
                    acknowledgedAt: Date(),
                    message: "Corpus cancellation will retry after the current atomic file transaction."
                ),
                nil
            )
        }
        let session: Session?
        if let activeSession {
            session = activeSession.journal.session.sessionID == sessionID
                && activeSession.journal.session.jobID == jobID
                ? activeSession
                : nil
        } else if let restored = try? restoreSession(sessionID: sessionID),
                  restored.journal.session.jobID == jobID {
            session = restored
        } else {
            session = nil
        }
        guard let session else {
            return (
                ConnectedCorpusTransferCancelAck(
                    sessionID: sessionID,
                    jobID: jobID,
                    accepted: false,
                    acknowledgedAt: Date(),
                    message: "No matching corpus session is active or resumable."
                ),
                nil
            )
        }
        suspendedExpiryTasks.removeValue(forKey: sessionID)?.cancel()
        let journalBeforeCancellation = session.journal
        do {
            try recordDurableRangePlanProgressForCancellation(session: session)
            session.journal.state = .cancelled
            session.journal.receivedRangePlan = nil
            session.journal.updatedAt = Date()
            try persist(session)
        } catch {
            session.journal = journalBeforeCancellation
            activeSession = nil
            admittedPartitions.removeAll()
            return (
                ConnectedCorpusTransferCancelAck(
                    sessionID: sessionID,
                    jobID: jobID,
                    accepted: false,
                    acknowledgedAt: Date(),
                    message: "Corpus cancellation could not be durably recorded."
                ),
                nil
            )
        }
        let result = makeFileResult(session: session, forcedStatus: .cancelled)
        cleanupPayloadFiles(session)
        cleanupArchiveWork(session: session, vaultManager: vaultManager)
        activeSession = nil
        admittedPartitions.removeAll()
        return (
            ConnectedCorpusTransferCancelAck(
                sessionID: sessionID,
                jobID: jobID,
                accepted: true,
                acknowledgedAt: Date(),
                message: "Corpus session cancelled after durable committed dates were recorded."
            ),
            session.journal.exportManifest.mode == .strictRaw ? nil : result
        )
    }

    private func recordDurableRangePlanProgressForCancellation(session: Session) throws {
        guard session.dailyExportOperation?.usesRangePlan == true,
              let plan = session.journal.receivedRangePlan else { return }
        let committedArtifacts = plan.artifacts.prefix(plan.nextArtifactIndex)
        let fileCount = session.journal.totalFilesWritten.addingReportingOverflow(
            committedArtifacts.count
        )
        guard !fileCount.overflow else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        let settings = session.journal.exportManifest.settingsSnapshot.makeAdvancedExportSettings()
        var completedDates = Set(session.journal.completedDates)
        if settings.summaryOnlyModeEnabled {
            // A summary date represents the complete immutable range, not one
            // format within it. Only the fully committed plan completes those dates.
            if plan.nextArtifactIndex == plan.artifacts.count, plan.rollupFileCount > 0 {
                completedDates.formUnion(plan.requestedRecordDatesWithData)
            }
        } else {
            let formatsPerDate = settings.looseFormatsPerDate
            guard formatsPerDate > 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            // Daily artifacts are materialized date-major and precede roll-ups.
            // A date becomes durable only after every configured format crossed
            // the persisted artifact frontier.
            let committedDailyFileCount = committedArtifacts.count(where: { $0.kind == .daily })
            let completedDailyDateCount = min(
                committedDailyFileCount / formatsPerDate,
                plan.requestedRecordDatesWithData.count
            )
            completedDates.formUnion(
                plan.requestedRecordDatesWithData.prefix(completedDailyDateCount)
            )
        }
        session.journal.totalFilesWritten = fileCount.partialValue
        session.journal.completedDates = Array(completedDates).sorted()
    }

    private func validateItemContinuity(
        segments: [ConnectedCorpusItemSegment],
        session: Session
    ) throws {
        let journal = session.journal
        let completed = Set(journal.completedItemIDs)
        for segment in segments {
            if let partial = journal.partialItems.first(where: { $0.itemID == segment.itemID }) {
                let inspection = try inspectProtectedSessionFile(
                    relativePath: "items/\(segment.itemID.uuidString).item",
                    sessionDirectoryURL: session.directoryURL
                )
                guard inspection.byteCount == partial.nextOffset,
                      inspection.sha256 == partial.prefixSHA256,
                      partial.kind == segment.kind,
                      partial.sourceDate == segment.sourceDate,
                      partial.isRequestedDate == segment.isRequestedDate,
                      partial.totalItemBytes == segment.totalItemBytes,
                      partial.itemSHA256 == segment.itemSHA256,
                      partial.nextOffset == segment.itemOffset else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
            } else {
                guard segment.itemOffset == 0,
                      !completed.contains(segment.itemID) else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
            }
        }
    }

    private func applyHealthDay(
        itemURL: URL,
        segment: ConnectedCorpusItemSegment,
        session: Session,
        vaultManager: VaultManager
    ) async throws -> HealthMdCompactContextDay? {
        let itemRelativePath = "items/\(segment.itemID.uuidString).item"
        let payload = try decodeHealthDayPayload(
            relativePath: itemRelativePath,
            expectedByteCount: segment.totalItemBytes,
            expectedSHA256: segment.itemSHA256,
            session: session
        )
        let expectedRequested = session.journal.exportManifest.requestedDates.contains(payload.sourceDate)
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = session.journal.exportManifest.sourceTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:)) ?? .current
        guard payload.sourceDate == segment.sourceDate,
              payload.isRequestedDate == segment.isRequestedDate,
              payload.isRequestedDate == expectedRequested,
              payload.failure.map({ $0.date == payload.sourceDate }) ?? true,
              payload.record.map({ sourceCalendar.isDate($0.date, inSameDayAs: payload.sourceDate) }) ?? true,
              !session.journal.processedDates.contains(payload.sourceDate) else {
            throw ConnectedCorpusTransferModelError.invalidPartitionDates
        }

        let contextDay: HealthMdCompactContextDay?
        let capturesEncryptedContext = session.journal.exportManifest.mode == .encryptedContext
        if queryContextStore == nil || !capturesEncryptedContext {
            contextDay = nil
        } else if let record = payload.record {
            contextDay = try HealthMdQueryContextProjector.project(
                record,
                externalProviderRecords: payload.externalDailyRecords,
                options: HealthMdContextProjectionOptions(
                    enabledMetricIDs: session.journal.exportManifest.settingsSnapshot.metricSelection.enabledMetricIDs,
                    includesAppleHealth: session.journal.exportManifest.selectedSourceIDs?
                        .contains("apple_health") ?? true
                )
            )
        } else {
            contextDay = try unavailableContextDay(
                payload: payload,
                segment: segment,
                calendar: sourceCalendar,
                enabledMetricIDs: session.journal.exportManifest.settingsSnapshot.metricSelection.enabledMetricIDs,
                includesAppleHealth: session.journal.exportManifest.selectedSourceIDs?
                    .contains("apple_health") ?? true
            )
        }

        if let failure = payload.failure {
            if payload.isRequestedDate {
                session.journal.failedDateDetails.append(failure)
                if failure.reason == .noHealthData {
                    session.journal.completedDates.append(payload.sourceDate)
                }
            } else {
                session.journal.supportingDateFailures.append(failure)
            }
        }

        if let record = payload.record {
            let relativePath = "records/\(segment.itemID.uuidString).json"
            try moveOrReconcileProtectedSessionFile(
                from: itemRelativePath,
                to: relativePath,
                expectedByteCount: segment.totalItemBytes,
                expectedSHA256: segment.itemSHA256,
                sessionDirectoryURL: session.directoryURL
            )
            session.journal.recordItems.append(StoredItem(
                sourceDate: payload.sourceDate,
                relativePath: relativePath,
                byteCount: segment.totalItemBytes,
                sha256: segment.itemSHA256
            ))

            if payload.isRequestedDate,
               session.journal.exportManifest.mode == .encryptedContext {
                session.journal.successfulRequestedDates.append(payload.sourceDate)
                session.journal.completedDates.append(payload.sourceDate)
            } else if session.journal.exportManifest.mode == .writeFiles {
                guard let baseDailyExportOperation = session.dailyExportOperation else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                // The complete immutable payload is decoded and its native-companion gate is
                // validated before VaultManager can plan or open the destination for this day.
                let dailyExportOperation = try baseDailyExportOperation.validating(
                    records: [record],
                    hasNativeOnlyCompanionAction: payload.externalDailyRecords.contains(
                        where: \.shouldExport
                    )
                )
                let settings = dailyExportOperation.settingsSnapshot.makeAdvancedExportSettings()
                settings.exportTimeZoneOverride = session.journal.exportManifest.sourceTimeZoneIdentifier
                    .flatMap(TimeZone.init(identifier:))
                if dailyExportOperation.usesRangePlan {
                    // Durable corpus partitions own only captured records. The complete requested
                    // daily plus roll-up destination plan is materialized once during finalization.
                    if payload.isRequestedDate {
                        session.journal.successfulRequestedDates.append(payload.sourceDate)
                    }
                } else if !payload.isRequestedDate {
                    // Legacy/non-range support records are retained only for native roll-up/archive
                    // finalization and never produce a daily destination write.
                } else if settings.summaryOnlyModeEnabled {
                    session.journal.successfulRequestedDates.append(payload.sourceDate)
                } else {
                    do {
                        // Archive mode intentionally writes no loose daily aggregate, but this
                        // call still performs configured standard-mode side effects.
                        let writeResult = try await vaultManager.exportHealthData(
                            record,
                            settings: settings,
                            healthSubfolder: dailyExportOperation.settingsSnapshot.healthSubfolder,
                            writeDataDictionary: session.journal.dataDictionaryWritten != true,
                            operationSurface: dailyExportOperation.surface,
                            frozenSettingsSnapshot: dailyExportOperation.settingsSnapshot
                        )
                        if !settings.archiveModeEnabled && !settings.dailyNotesOnlyModeEnabled {
                            session.journal.dataDictionaryWritten = true
                        }
                        session.journal.dailyNoteUpdateCount =
                            (session.journal.dailyNoteUpdateCount ?? 0) + writeResult.dailyNoteUpdatedCount
                        session.journal.dailyNoteSkipCount =
                            (session.journal.dailyNoteSkipCount ?? 0) + writeResult.dailyNoteSkippedCount
                        session.journal.individualEntryCoverageGaps =
                            (session.journal.individualEntryCoverageGaps ?? [])
                            + writeResult.individualEntryCoverageGaps

                        if settings.dailyNotesOnlyModeEnabled {
                            switch writeResult.dailyNoteResult {
                            case .updated:
                                break
                            case .skipped(let reason):
                                session.journal.failedDateDetails.append(FailedDateDetail(
                                    date: payload.sourceDate,
                                    reason: .noHealthData,
                                    errorDetails: reason
                                ))
                                session.journal.completedDates.append(payload.sourceDate)
                                session.journal.processedDates.append(payload.sourceDate)
                                return contextDay
                            case .failed(let error):
                                session.journal.failedDateDetails.append(FailedDateDetail(
                                    date: payload.sourceDate,
                                    reason: .fileWriteError,
                                    errorDetails: error.localizedDescription
                                ))
                                session.journal.processedDates.append(payload.sourceDate)
                                return contextDay
                            case .none:
                                session.journal.failedDateDetails.append(FailedDateDetail(
                                    date: payload.sourceDate,
                                    reason: .fileWriteError,
                                    errorDetails: "Daily note update was not performed."
                                ))
                                session.journal.processedDates.append(payload.sourceDate)
                                return contextDay
                            }
                        }

                        if !settings.archiveModeEnabled {
                            session.journal.totalFilesWritten += settings.looseFormatsPerDate
                            session.journal.completedDates.append(payload.sourceDate)
                        }
                        session.journal.successfulRequestedDates.append(payload.sourceDate)
                        if settings.writesExternalProviderSidecars && !payload.externalDailyRecords.isEmpty {
                            do {
                                let count = try await vaultManager.exportExternalDailyRecords(
                                    payload.externalDailyRecords,
                                    healthSubfolder: session.journal.exportManifest.settingsSnapshot.healthSubfolder
                                )
                                session.journal.externalRecordFileCount += count
                                session.journal.totalFilesWritten += count
                            } catch {
                                session.journal.completedDates.removeAll { $0 == payload.sourceDate }
                                session.journal.failedDateDetails.append(FailedDateDetail(
                                    date: payload.sourceDate,
                                    reason: .fileWriteError,
                                    errorDetails: "External provider sidecar export failed: \(error.localizedDescription)"
                                ))
                            }
                        }
                    } catch {
                        session.journal.failedDateDetails.append(FailedDateDetail(
                            date: payload.sourceDate,
                            reason: .fileWriteError,
                            errorDetails: error.localizedDescription
                        ))
                    }
                }
            }
        } else {
            try removeProtectedSessionFile(
                relativePath: itemRelativePath,
                sessionDirectoryURL: session.directoryURL
            )
            if payload.failure == nil, payload.isRequestedDate {
                session.journal.failedDateDetails.append(FailedDateDetail(
                    date: payload.sourceDate,
                    reason: .noHealthData
                ))
                session.journal.completedDates.append(payload.sourceDate)
            }
        }
        session.journal.processedDates.append(payload.sourceDate)
        return contextDay
    }

    private struct ReceivedRangeInput {
        let records: [HealthData]
        let dailyOutputOwnerDates: Set<String>
        let requestedRecordDatesWithData: Set<Date>
        let hasAnyData: Bool
    }

    private func receivedRangeInput(
        session: Session,
        items: [StoredItem],
        settings: AdvancedExportSettings,
        calendarTimeZoneIdentifier: String
    ) throws -> ReceivedRangeInput {
        let requestedDates = Set(session.journal.exportManifest.requestedDates)
        let successfulRequestedDates = Set(session.journal.successfulRequestedDates)
        var records: [HealthData] = []
        var dailyOutputOwnerDates: Set<String> = []
        var requestedRecordDatesWithData: Set<Date> = []
        var hasAnyData = false

        for item in items.sorted(by: { $0.sourceDate < $1.sourceDate }) {
            let payload = try decodeHealthDayPayload(
                storedItem: item,
                session: session
            )
            guard payload.sourceDate == item.sourceDate,
                  let record = payload.record,
                  payload.externalDailyRecords.allSatisfy({ !$0.shouldExport }) else {
                throw ConnectedMacDailyExportOperation.ResolutionError.unsupportedPinnedOperation
            }
            let prepared = record.preparedExport(settings: settings)
            records.append(record)
            hasAnyData = hasAnyData || prepared.hasAnyData
            guard prepared.hasAnyData else { continue }
            if requestedDates.contains(payload.sourceDate),
               successfulRequestedDates.contains(payload.sourceDate) {
                requestedRecordDatesWithData.insert(payload.sourceDate)
                if !settings.summaryOnlyModeEnabled {
                    dailyOutputOwnerDates.insert(
                        HealthKitDailyOwnershipMetadata.ownerDate(
                            for: record.date,
                            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
                        )
                    )
                }
            }
        }
        return ReceivedRangeInput(
            records: records,
            dailyOutputOwnerDates: dailyOutputOwnerDates,
            requestedRecordDatesWithData: requestedRecordDatesWithData,
            hasAnyData: hasAnyData
        )
    }

    private func persistReceivedRangePlan(
        _ materialized: AppleLooseDailyRangeMaterialization,
        requestedRecordDatesWithData: Set<Date>,
        session: Session,
        vaultManager: VaultManager
    ) throws {
        guard session.journal.state == .finalizing,
              session.journal.receivedRangePlanPersisted == false,
              session.journal.receivedRangePlan == nil,
              let expectedPin = session.journal.exportManifest.effectiveAppleExportEnginePin,
              materialized.operation.pin == expectedPin,
              materialized.operation.authority == expectedPin.engine,
              materialized.operation.selectedPlan.requestID
                == session.journal.session.jobID.uuidString.lowercased(),
              materialized.operation.selectedPlan.sessionID
                == session.journal.session.sessionID.uuidString.lowercased(),
              materialized.operation.identity.requestID
                == session.journal.session.jobID.uuidString.lowercased(),
              materialized.operation.identity.sessionID
                == session.journal.session.sessionID.uuidString.lowercased(),
              materialized.operation.identity.calendarTimeZoneIdentifier
                == expectedPin.calendarTimeZoneIdentifier,
              materialized.operation.artifacts.map(\.artifact)
                == materialized.operation.selectedPlan.artifacts,
              materialized.operation.artifacts.allSatisfy({
                  $0.artifact.role == .file && $0.artifact.writeMode == .overwrite
              }) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        let dictionaryByteCount = UInt64(materialized.dataDictionary?.data.count ?? 0)
        let (spoolByteCount, spoolOverflow) = materialized.operation.selectedPlan.totalByteCount
            .addingReportingOverflow(dictionaryByteCount)
        let maximumSpoolBytes: UInt64 = 33 * 1_024 * 1_024
        guard !spoolOverflow,
              spoolByteCount <= maximumSpoolBytes,
              let requiredBytes = Int64(exactly: spoolByteCount),
              hasAvailableDiskSpace(
                  at: rootURL,
                  requiredBytes: requiredBytes + 128 * 1_024 * 1_024
              ) else {
            throw CocoaError(.fileWriteOutOfSpace)
        }

        let destinationBinding = try vaultManager.exactDestinationBinding()
        try? removeProtectedSessionTree(
            relativePath: "finalization",
            sessionDirectoryURL: session.directoryURL
        )
        do {
            let artifactDirectoryDescriptor = try openProtectedSessionDirectory(
                relativePath: "finalization/artifacts",
                sessionDirectoryURL: session.directoryURL,
                createDirectories: true
            )
            guard Darwin.fsync(artifactDirectoryDescriptor) == 0 else {
                Darwin.close(artifactDirectoryDescriptor)
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            Darwin.close(artifactDirectoryDescriptor)

            let storedDictionary: StoredFinalizationFile?
            if let dictionary = materialized.dataDictionary {
                let spoolRelativePath = "finalization/data-dictionary.artifact"
                try writeProtectedFinalizationData(
                    dictionary.data,
                    relativePath: spoolRelativePath,
                    sessionDirectoryURL: session.directoryURL
                )
                storedDictionary = StoredFinalizationFile(
                    relativePath: dictionary.relativePath,
                    spoolRelativePath: spoolRelativePath,
                    mediaType: dictionary.mediaType,
                    byteCount: UInt64(dictionary.data.count),
                    sha256: NativeExportArtifact.sha256(of: dictionary.data)
                )
            } else {
                storedDictionary = nil
            }

            var storedArtifacts: [StoredFinalizationArtifact] = []
            storedArtifacts.reserveCapacity(materialized.operation.artifacts.count)
            for (index, planned) in materialized.operation.artifacts.enumerated() {
                let spoolRelativePath = String(
                    format: "finalization/artifacts/%04d.artifact",
                    index
                )
                try writeProtectedFinalizationData(
                    planned.artifact.inlineData,
                    relativePath: spoolRelativePath,
                    sessionDirectoryURL: session.directoryURL
                )
                storedArtifacts.append(StoredFinalizationArtifact(
                    artifactID: planned.artifact.id,
                    relativePath: planned.artifact.relativePath,
                    spoolRelativePath: spoolRelativePath,
                    mediaType: planned.artifact.mediaType,
                    writeMode: "overwrite",
                    kind: planned.kind,
                    format: planned.format,
                    byteCount: planned.artifact.byteCount,
                    sha256: planned.artifact.sha256
                ))
            }
            try syncProtectedSessionDirectory(
                relativePath: "finalization/artifacts",
                sessionDirectoryURL: session.directoryURL
            )
            try syncProtectedSessionDirectory(
                relativePath: "finalization",
                sessionDirectoryURL: session.directoryURL
            )

            let orderedRequestedDates = requestedRecordDatesWithData.sorted()
            var plan = StoredReceivedRangePlan(
                schema: StoredReceivedRangePlan.schema,
                version: StoredReceivedRangePlan.version,
                destinationBinding: destinationBinding,
                authority: materialized.operation.authority,
                pin: materialized.operation.pin,
                artifactPlanVersion: materialized.operation.selectedPlan.artifactPlanVersion,
                requestID: materialized.operation.selectedPlan.requestID,
                sessionID: materialized.operation.selectedPlan.sessionID,
                profile: "apple_health_data_v8",
                totalByteCount: materialized.operation.selectedPlan.totalByteCount,
                immutablePlanSHA256: "",
                dataDictionary: storedDictionary,
                artifacts: storedArtifacts,
                dailyFileCount: materialized.result.dailyFileCount,
                rollupFileCount: materialized.result.rollupFileCount,
                requestedRecordDatesWithData: orderedRequestedDates,
                dataDictionaryAcknowledged: false,
                nextArtifactIndex: 0
            )
            plan = StoredReceivedRangePlan(
                schema: plan.schema,
                version: plan.version,
                destinationBinding: plan.destinationBinding,
                authority: plan.authority,
                pin: plan.pin,
                artifactPlanVersion: plan.artifactPlanVersion,
                requestID: plan.requestID,
                sessionID: plan.sessionID,
                profile: plan.profile,
                totalByteCount: plan.totalByteCount,
                immutablePlanSHA256: try immutableDigest(for: plan),
                dataDictionary: plan.dataDictionary,
                artifacts: plan.artifacts,
                dailyFileCount: plan.dailyFileCount,
                rollupFileCount: plan.rollupFileCount,
                requestedRecordDatesWithData: plan.requestedRecordDatesWithData,
                dataDictionaryAcknowledged: false,
                nextArtifactIndex: 0
            )
            try validateStoredReceivedRangePlan(
                plan,
                journal: session.journal,
                sessionDirectoryURL: session.directoryURL
            )

            let journalBeforePlan = session.journal
            session.journal.receivedRangePlan = plan
            session.journal.receivedRangePlanPersisted = true
            do {
                try persist(session)
            } catch JournalPersistenceError.postPublication {
                throw ReceivedRangeCommitError.transient
            } catch {
                session.journal = journalBeforePlan
                throw error
            }
        } catch {
            if session.journal.receivedRangePlanPersisted != true {
                try? removeProtectedSessionTree(
                    relativePath: "finalization",
                    sessionDirectoryURL: session.directoryURL
                )
            }
            throw error
        }
    }

    private func commitStoredReceivedRangePlan(
        session: Session,
        vaultManager: VaultManager
    ) async throws -> AppleLooseDailyRangeWriteResult {
        guard let initialPlan = session.journal.receivedRangePlan,
              session.journal.receivedRangePlanPersisted == true else {
            throw ReceivedRangeCommitError.invalid
        }
        try ensureFinalizationIsActive(session)
        do {
            try validateStoredReceivedRangePlan(
                initialPlan,
                journal: session.journal,
                sessionDirectoryURL: session.directoryURL
            )
            try vaultManager.preflightExportArtifactPaths(
                initialPlan.artifacts.map(\.relativePath)
                    + (initialPlan.dataDictionary.map { [$0.relativePath] } ?? [])
            )
        } catch {
            throw ReceivedRangeCommitError.invalid
        }

        if let dictionary = initialPlan.dataDictionary {
            let data: Data
            do {
                data = try protectedFinalizationData(
                    dictionary,
                    sessionDirectoryURL: session.directoryURL
                )
            } catch {
                throw ReceivedRangeCommitError.invalid
            }
            let state = try await exactDestinationState(
                relativePath: dictionary.relativePath,
                data: data,
                binding: initialPlan.destinationBinding,
                vaultManager: vaultManager
            )
            try ensureFinalizationIsActive(session)
            guard let current = session.journal.receivedRangePlan else {
                throw ReceivedRangeCommitError.invalid
            }
            if current.dataDictionaryAcknowledged {
                guard state == .exact else { throw ReceivedRangeCommitError.invalid }
            } else {
                try await withDestinationCommitTransaction(session: session) {
                    let transactionalState = try await exactDestinationState(
                        relativePath: dictionary.relativePath,
                        data: data,
                        binding: initialPlan.destinationBinding,
                        vaultManager: vaultManager
                    )
                    try ensureFinalizationIsActive(session)
                    if transactionalState != .exact {
                        try await overwriteExactDestination(
                            relativePath: dictionary.relativePath,
                            data: data,
                            binding: initialPlan.destinationBinding,
                            session: session,
                            vaultManager: vaultManager
                        )
                        try ensureFinalizationIsActive(session)
                    }
                    let readback = try await exactDestinationState(
                        relativePath: dictionary.relativePath,
                        data: data,
                        binding: initialPlan.destinationBinding,
                        vaultManager: vaultManager
                    )
                    try ensureFinalizationIsActive(session)
                    guard readback == .exact else { throw ReceivedRangeCommitError.invalid }
                    try advanceReceivedRangePlan(session: session) { plan in
                        plan.dataDictionaryAcknowledged = true
                    }
                }
            }
        } else if initialPlan.dataDictionaryAcknowledged {
            throw ReceivedRangeCommitError.invalid
        }

        for index in initialPlan.artifacts.indices {
            try ensureFinalizationIsActive(session)
            let artifact = initialPlan.artifacts[index]
            let data: Data
            do {
                data = try protectedFinalizationData(
                    artifact,
                    sessionDirectoryURL: session.directoryURL
                )
            } catch {
                throw ReceivedRangeCommitError.invalid
            }
            let state = try await exactDestinationState(
                relativePath: artifact.relativePath,
                data: data,
                binding: initialPlan.destinationBinding,
                vaultManager: vaultManager
            )
            try ensureFinalizationIsActive(session)
            guard let current = session.journal.receivedRangePlan else {
                throw ReceivedRangeCommitError.invalid
            }
            if index < current.nextArtifactIndex {
                guard state == .exact else { throw ReceivedRangeCommitError.invalid }
                continue
            }
            guard index == current.nextArtifactIndex else {
                throw ReceivedRangeCommitError.invalid
            }
            try await withDestinationCommitTransaction(session: session) {
                let transactionalState = try await exactDestinationState(
                    relativePath: artifact.relativePath,
                    data: data,
                    binding: initialPlan.destinationBinding,
                    vaultManager: vaultManager
                )
                try ensureFinalizationIsActive(session)
                if transactionalState != .exact {
                    try await overwriteExactDestination(
                        relativePath: artifact.relativePath,
                        data: data,
                        binding: initialPlan.destinationBinding,
                        session: session,
                        vaultManager: vaultManager
                    )
                    try ensureFinalizationIsActive(session)
                }
                let readback = try await exactDestinationState(
                    relativePath: artifact.relativePath,
                    data: data,
                    binding: initialPlan.destinationBinding,
                    vaultManager: vaultManager
                )
                try ensureFinalizationIsActive(session)
                guard readback == .exact else { throw ReceivedRangeCommitError.invalid }
                try advanceReceivedRangePlan(session: session) { plan in
                    plan.nextArtifactIndex = index + 1
                }
            }
        }
        guard let completedPlan = session.journal.receivedRangePlan,
              completedPlan.dataDictionary == nil || completedPlan.dataDictionaryAcknowledged,
              completedPlan.nextArtifactIndex == completedPlan.artifacts.count else {
            throw ReceivedRangeCommitError.invalid
        }
        return AppleLooseDailyRangeWriteResult(
            dailyFileCount: completedPlan.dailyFileCount,
            rollupFileCount: completedPlan.rollupFileCount
        )
    }

    private func advanceReceivedRangePlan(
        session: Session,
        mutation: (inout StoredReceivedRangePlan) -> Void
    ) throws {
        guard var plan = session.journal.receivedRangePlan else {
            throw ReceivedRangeCommitError.invalid
        }
        let priorPlan = plan
        mutation(&plan)
        session.journal.receivedRangePlan = plan
        do {
            try persist(session)
        } catch JournalPersistenceError.postPublication {
            throw ReceivedRangeCommitError.transient
        } catch {
            session.journal.receivedRangePlan = priorPlan
            throw ReceivedRangeCommitError.transient
        }
    }

    private func exactDestinationState(
        relativePath: String,
        data: Data,
        binding: AppleVaultDestinationBinding,
        vaultManager: VaultManager
    ) async throws -> AppleExactDestinationState {
        do {
            return try await vaultManager.inspectExactUTF8Artifact(
                relativePath: relativePath,
                expectedData: data,
                binding: binding
            )
        } catch let error as AppleExactDestinationError {
            switch error {
            case .destinationUnavailable:
                throw ReceivedRangeCommitError.transient
            case .destinationRebound, .unsafeRelativePath, .invalidUTF8:
                throw ReceivedRangeCommitError.invalid
            }
        } catch {
            throw ReceivedRangeCommitError.transient
        }
    }

    private func withDestinationCommitTransaction<T>(
        session: Session,
        operation: () async throws -> T
    ) async throws -> T {
        try ensureFinalizationIsActive(session)
        guard destinationCommitInFlightSessionID == nil else {
            throw ReceivedRangeCommitError.invalid
        }
        let sessionID = session.journal.session.sessionID
        destinationCommitInFlightSessionID = sessionID
        defer {
            if destinationCommitInFlightSessionID == sessionID {
                destinationCommitInFlightSessionID = nil
            }
        }
        return try await operation()
    }

    private func overwriteExactDestination(
        relativePath: String,
        data: Data,
        binding: AppleVaultDestinationBinding,
        session: Session,
        vaultManager: VaultManager
    ) async throws {
        try ensureFinalizationIsActive(session)
        guard destinationCommitInFlightSessionID == session.journal.session.sessionID else {
            throw ReceivedRangeCommitError.invalid
        }
        do {
            try await vaultManager.overwriteExactUTF8Artifact(
                relativePath: relativePath,
                data: data,
                binding: binding
            )
        } catch let error as AppleExactDestinationError {
            switch error {
            case .destinationUnavailable:
                throw ReceivedRangeCommitError.transient
            case .destinationRebound, .unsafeRelativePath, .invalidUTF8:
                throw ReceivedRangeCommitError.invalid
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ReceivedRangeCommitError.transient
        }
    }

    private func validateStoredReceivedRangePlan(
        _ plan: StoredReceivedRangePlan,
        journal: Journal,
        sessionDirectoryURL: URL
    ) throws {
        guard plan.artifacts.count <= 4_096,
              plan.requestedRecordDatesWithData.count
                <= journal.exportManifest.requestedDates.count else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var calculatedArtifactBytes: UInt64 = 0
        for artifact in plan.artifacts {
            let sum = calculatedArtifactBytes.addingReportingOverflow(artifact.byteCount)
            guard !sum.overflow,
                  artifact.byteCount <= 8 * 1_024 * 1_024,
                  artifact.relativePath.utf8.count <= 4_096,
                  artifact.mediaType.utf8.count <= 128 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            calculatedArtifactBytes = sum.partialValue
        }
        let dictionaryBytes = plan.dataDictionary?.byteCount ?? 0
        let combinedBytes = calculatedArtifactBytes.addingReportingOverflow(dictionaryBytes)
        let fileCount = plan.dailyFileCount.addingReportingOverflow(plan.rollupFileCount)
        guard !combinedBytes.overflow,
              !fileCount.overflow,
              calculatedArtifactBytes == plan.totalByteCount,
              calculatedArtifactBytes <= 32 * 1_024 * 1_024,
              dictionaryBytes <= 1 * 1_024 * 1_024,
              combinedBytes.partialValue <= 33 * 1_024 * 1_024 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        guard plan.schema == StoredReceivedRangePlan.schema,
              plan.version == StoredReceivedRangePlan.version,
              plan.authority == plan.pin.engine,
              plan.authority == .shadow || plan.authority == .rust,
              plan.pin == journal.exportManifest.effectiveAppleExportEnginePin,
              plan.artifactPlanVersion == plan.pin.artifactPlanVersion,
              plan.requestID == journal.session.jobID.uuidString.lowercased(),
              plan.sessionID == journal.session.sessionID.uuidString.lowercased(),
              plan.profile == "apple_health_data_v8",
              plan.dailyFileCount >= 0,
              plan.rollupFileCount >= 0,
              fileCount.partialValue == plan.artifacts.count,
              plan.dailyFileCount == plan.artifacts.count(where: { $0.kind == .daily }),
              plan.rollupFileCount == plan.artifacts.count(where: { $0.kind == .rollup }),
              plan.nextArtifactIndex >= 0,
              plan.nextArtifactIndex <= plan.artifacts.count,
              plan.dataDictionary != nil || !plan.dataDictionaryAcknowledged,
              Set(plan.requestedRecordDatesWithData).count
                == plan.requestedRecordDatesWithData.count,
              plan.requestedRecordDatesWithData == plan.requestedRecordDatesWithData.sorted(),
              Set(plan.requestedRecordDatesWithData).isSubset(
                  of: Set(journal.exportManifest.requestedDates)
              ),
              AppleExportEnginePin.isLowercaseSHA256(plan.immutablePlanSHA256),
              plan.immutablePlanSHA256 == (try immutableDigest(for: plan)),
              Self.isValidStoredDestinationBinding(plan.destinationBinding) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        if let dictionary = plan.dataDictionary {
            let artifactPaths = Set(plan.artifacts.map {
                Self.portableDestinationPathKey($0.relativePath)
            })
            guard !artifactPaths.contains(
                Self.portableDestinationPathKey(dictionary.relativePath)
            ) else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }

        let finalizationDirectoryURL = sessionDirectoryURL.appendingPathComponent(
            "finalization",
            isDirectory: true
        )
        let artifactDirectoryURL = finalizationDirectoryURL.appendingPathComponent(
            "artifacts",
            isDirectory: true
        )
        let expectedRootEntries = Set(
            ["artifacts"] + (plan.dataDictionary == nil ? [] : ["data-dictionary.artifact"])
        )
        let actualRootEntries = try Set(
            fileManager.contentsOfDirectory(
                at: finalizationDirectoryURL,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent)
        )
        let expectedArtifactEntries = Set(plan.artifacts.indices.map {
            String(format: "%04d.artifact", $0)
        })
        let actualArtifactEntries = try Set(
            fileManager.contentsOfDirectory(
                at: artifactDirectoryURL,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent)
        )
        guard actualRootEntries == expectedRootEntries,
              actualArtifactEntries == expectedArtifactEntries,
              hasRestrictedPermissions(at: finalizationDirectoryURL, maximum: 0o700),
              hasRestrictedPermissions(at: artifactDirectoryURL, maximum: 0o700) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        var nativeArtifacts: [NativeExportArtifact] = []
        nativeArtifacts.reserveCapacity(plan.artifacts.count)
        for (index, artifact) in plan.artifacts.enumerated() {
            guard artifact.spoolRelativePath == String(
                format: "finalization/artifacts/%04d.artifact",
                index
            ),
            artifact.writeMode == "overwrite",
            artifact.relativePath.lowercased().hasSuffix(
                "." + artifact.format.fileExtension.lowercased()
            ),
            Self.expectedMediaType(for: artifact.format) == artifact.mediaType else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let artifactURL = sessionDirectoryURL.appendingPathComponent(
                artifact.spoolRelativePath
            )
            guard hasRestrictedPermissions(at: artifactURL, maximum: 0o600) else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let data = try protectedFinalizationData(
                artifact,
                sessionDirectoryURL: sessionDirectoryURL
            )
            nativeArtifacts.append(try NativeExportArtifact(
                role: .file,
                id: artifact.artifactID,
                relativePath: artifact.relativePath,
                mediaType: artifact.mediaType,
                writeMode: .overwrite,
                inlineData: data,
                byteCount: artifact.byteCount,
                sha256: artifact.sha256
            ))
        }
        if let dictionary = plan.dataDictionary {
            guard dictionary.spoolRelativePath == "finalization/data-dictionary.artifact",
                  dictionary.relativePath.hasSuffix(
                      "/" + HealthMdExportSchema.dataDictionaryFilename
                  ) || dictionary.relativePath == HealthMdExportSchema.dataDictionaryFilename,
                  dictionary.mediaType == "application/json" else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let dictionaryURL = sessionDirectoryURL.appendingPathComponent(
                dictionary.spoolRelativePath
            )
            guard hasRestrictedPermissions(at: dictionaryURL, maximum: 0o600) else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            _ = try protectedFinalizationData(
                dictionary,
                sessionDirectoryURL: sessionDirectoryURL
            )
        }
        _ = try NativeExportArtifactPlan(
            artifactPlanVersion: plan.artifactPlanVersion,
            requestID: plan.requestID,
            sessionID: plan.sessionID,
            profile: .appleHealthDataV8,
            artifacts: nativeArtifacts,
            totalByteCount: plan.totalByteCount,
            pin: plan.pin
        )
    }

    private func decodeHealthDayPayload(
        storedItem item: StoredItem,
        session: Session
    ) throws -> ConnectedCorpusHealthDayPayload {
        guard let byteCount = item.byteCount,
              let sha256 = item.sha256,
              byteCount > 0,
              sha256.isConnectedCorpusSHA256,
              Self.isSafeStoredPath(item.relativePath, prefix: "records/") else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return try decodeHealthDayPayload(
            relativePath: item.relativePath,
            expectedByteCount: byteCount,
            expectedSHA256: sha256,
            session: session
        )
    }

    private func decodeHealthDayPayload(
        relativePath: String,
        expectedByteCount: Int64,
        expectedSHA256: String,
        session: Session
    ) throws -> ConnectedCorpusHealthDayPayload {
        if ConnectedCorpusApplicationItemCodec.usesStreamableItems(
            protocolVersion: session.journal.session.protocolVersion
        ) {
            let descriptor = try openVerifiedProtectedSessionFile(
                relativePath: relativePath,
                expectedByteCount: expectedByteCount,
                expectedSHA256: expectedSHA256,
                sessionDirectoryURL: session.directoryURL
            )
            defer { Darwin.close(descriptor) }
            return try ConnectedCorpusApplicationItemCodec.decode(
                ConnectedCorpusHealthDayPayload.self,
                fromFileDescriptor: descriptor,
                expectedKind: .macHealthDay
            )
        }
        guard let unsignedByteCount = UInt64(exactly: expectedByteCount) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let data = try readProtectedFinalizationData(
            relativePath: relativePath,
            expectedByteCount: unsignedByteCount,
            sessionDirectoryURL: session.directoryURL
        )
        guard NativeExportArtifact.sha256(of: data) == expectedSHA256 else {
            throw ConnectedCorpusTransferModelError.invalidDigest
        }
        return try JSONDecoder().decode(ConnectedCorpusHealthDayPayload.self, from: data)
    }

    private func protectedStoredItemData(
        _ item: StoredItem,
        sessionDirectoryURL: URL
    ) throws -> Data {
        guard let byteCount = item.byteCount,
              let expectedSHA256 = item.sha256,
              byteCount > 0,
              let unsignedByteCount = UInt64(exactly: byteCount),
              expectedSHA256.isConnectedCorpusSHA256 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let data = try readProtectedFinalizationData(
            relativePath: item.relativePath,
            expectedByteCount: unsignedByteCount,
            sessionDirectoryURL: sessionDirectoryURL
        )
        guard NativeExportArtifact.sha256(of: data) == expectedSHA256 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return data
    }

    private func protectedFinalizationData(
        _ file: StoredFinalizationFile,
        sessionDirectoryURL: URL
    ) throws -> Data {
        try protectedFinalizationData(
            relativePath: file.spoolRelativePath,
            expectedByteCount: file.byteCount,
            expectedSHA256: file.sha256,
            sessionDirectoryURL: sessionDirectoryURL
        )
    }

    private func protectedFinalizationData(
        _ artifact: StoredFinalizationArtifact,
        sessionDirectoryURL: URL
    ) throws -> Data {
        try protectedFinalizationData(
            relativePath: artifact.spoolRelativePath,
            expectedByteCount: artifact.byteCount,
            expectedSHA256: artifact.sha256,
            sessionDirectoryURL: sessionDirectoryURL
        )
    }

    private func protectedFinalizationData(
        relativePath: String,
        expectedByteCount: UInt64,
        expectedSHA256: String,
        sessionDirectoryURL: URL
    ) throws -> Data {
        guard Self.isSafeStoredPath(relativePath, prefix: "finalization/") else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let data = try readProtectedFinalizationData(
            relativePath: relativePath,
            expectedByteCount: expectedByteCount,
            sessionDirectoryURL: sessionDirectoryURL
        )
        guard UInt64(data.count) == expectedByteCount,
              AppleExportEnginePin.isLowercaseSHA256(expectedSHA256),
              NativeExportArtifact.sha256(of: data) == expectedSHA256,
              String(data: data, encoding: .utf8) != nil else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return data
    }

    private func bindLegacyStoredItems(
        _ items: [StoredItem],
        prefix: String,
        sessionDirectoryURL: URL
    ) throws -> [StoredItem] {
        try items.map { item in
            guard Self.isSafeStoredPath(item.relativePath, prefix: prefix) else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            if let byteCount = item.byteCount, let sha256 = item.sha256 {
                guard byteCount > 0, sha256.isConnectedCorpusSHA256 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                return item
            }
            guard item.byteCount == nil, item.sha256 == nil else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let inspection = try inspectProtectedSessionFile(
                relativePath: item.relativePath,
                sessionDirectoryURL: sessionDirectoryURL
            )
            return StoredItem(
                sourceDate: item.sourceDate,
                relativePath: item.relativePath,
                dateIdentifier: item.dateIdentifier,
                byteCount: inspection.byteCount,
                sha256: inspection.sha256
            )
        }
    }

    private func persistStrictRawTerminalSpool(
        _ spool: CanonicalRawResultSpool,
        session: Session
    ) throws -> StoredStrictRawTerminalSpool {
        try copyFileIntoProtectedSession(
            source: spool.file,
            relativePath: StoredStrictRawTerminalSpool.relativePath,
            session: session
        )
        return StoredStrictRawTerminalSpool(
            relativePath: StoredStrictRawTerminalSpool.relativePath,
            byteCount: spool.file.totalBytes,
            sha256: spool.file.sha256,
            profile: spool.profile,
            canonicalSelection: spool.canonicalSelection,
            captureSummary: spool.captureSummary,
            missingDates: spool.missingDates,
            totalRequestedDays: spool.totalRequestedDays,
            dateRangeStart: spool.dateRangeStart,
            dateRangeEnd: spool.dateRangeEnd
        )
    }

    private func restoreStrictRawTerminalSpool(
        _ stored: StoredStrictRawTerminalSpool,
        session: Session
    ) throws -> CanonicalRawResultSpool {
        guard stored.relativePath == StoredStrictRawTerminalSpool.relativePath,
              stored.byteCount > 0,
              stored.sha256.count == 64,
              stored.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              stored.totalRequestedDays > 0,
              !stored.dateRangeStart.isEmpty,
              !stored.dateRangeEnd.isEmpty else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let inspection = try inspectProtectedSessionFile(
            relativePath: stored.relativePath,
            sessionDirectoryURL: session.directoryURL
        )
        guard inspection.byteCount == stored.byteCount,
              inspection.sha256 == stored.sha256 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let temporaryURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "connected-strict-raw-replay"
        )
        var shouldRemove = true
        defer {
            if shouldRemove { try? fileManager.removeItem(at: temporaryURL) }
        }
        try copyProtectedSessionFileToURL(
            relativePath: stored.relativePath,
            session: session,
            destinationURL: temporaryURL,
            expectedByteCount: stored.byteCount,
            expectedSHA256: stored.sha256
        )
        let prepared = try ConnectedTransferFile.inspect(temporaryURL)
        guard prepared.totalBytes == stored.byteCount,
              prepared.sha256 == stored.sha256 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        shouldRemove = false
        return CanonicalRawResultSpool(
            file: prepared,
            profile: stored.profile,
            canonicalSelection: stored.canonicalSelection,
            captureSummary: stored.captureSummary,
            missingDates: stored.missingDates,
            totalRequestedDays: stored.totalRequestedDays,
            dateRangeStart: stored.dateRangeStart,
            dateRangeEnd: stored.dateRangeEnd
        )
    }

    private func copyFileIntoProtectedSession(
        source: ConnectedTransferPreparedFile,
        relativePath: String,
        session: Session
    ) throws {
        let (parentPath, filename) = try protectedParentAndFilename(relativePath)
        let ensuredParentDescriptor = try openProtectedSessionDirectory(
            relativePath: parentPath,
            sessionDirectoryURL: session.directoryURL,
            createDirectories: true
        )
        Darwin.close(ensuredParentDescriptor)
        if let inspection = try? inspectProtectedSessionFile(
            relativePath: relativePath,
            sessionDirectoryURL: session.directoryURL
        ) {
            guard inspection.byteCount == source.totalBytes,
                  inspection.sha256 == source.sha256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            return
        }
        let sourceDescriptor = Darwin.open(
            source.url.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard sourceDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(sourceDescriptor) }
        var sourceMetadata = stat()
        guard Darwin.fstat(sourceDescriptor, &sourceMetadata) == 0,
              sourceMetadata.st_mode & S_IFMT == S_IFREG,
              sourceMetadata.st_nlink == 1,
              sourceMetadata.st_size == source.totalBytes else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let parentDescriptor = try openProtectedSessionDirectory(
            relativePath: parentPath,
            sessionDirectoryURL: session.directoryURL,
            createDirectories: false
        )
        defer { Darwin.close(parentDescriptor) }
        let temporaryName = ".strict-raw-\(UUID().uuidString).tmp"
        let temporaryDescriptor = temporaryName.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard temporaryDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var temporaryIsPresent = true
        defer {
            Darwin.close(temporaryDescriptor)
            if temporaryIsPresent {
                _ = temporaryName.withCString { Darwin.unlinkat(parentDescriptor, $0, 0) }
            }
        }
        let copied = try copyAndHash(
            sourceDescriptor: sourceDescriptor,
            destinationDescriptor: temporaryDescriptor
        )
        guard copied.byteCount == source.totalBytes,
              copied.sha256 == source.sha256,
              Darwin.fchmod(temporaryDescriptor, mode_t(0o600)) == 0,
              Darwin.fsync(temporaryDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let renameResult = temporaryName.withCString { temporaryPointer in
            filename.withCString { filenamePointer in
                Darwin.renameatx_np(
                    parentDescriptor,
                    temporaryPointer,
                    parentDescriptor,
                    filenamePointer,
                    UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)
                )
            }
        }
        if renameResult != 0 {
            guard errno == EEXIST,
                  let inspection = try? inspectProtectedSessionFile(
                    relativePath: relativePath,
                    sessionDirectoryURL: session.directoryURL
                  ),
                  inspection.byteCount == source.totalBytes,
                  inspection.sha256 == source.sha256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        } else {
            temporaryIsPresent = false
        }
        guard Darwin.fsync(parentDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func copyProtectedSessionFileToURL(
        relativePath: String,
        session: Session,
        destinationURL: URL,
        expectedByteCount: Int64,
        expectedSHA256: String
    ) throws {
        let sourceDescriptor = try openProtectedSessionFile(
            relativePath: relativePath,
            sessionDirectoryURL: session.directoryURL
        )
        defer { Darwin.close(sourceDescriptor) }
        let destinationDescriptor = Darwin.open(
            destinationURL.path,
            O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC
        )
        guard destinationDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(destinationDescriptor) }
        let copied = try copyAndHash(
            sourceDescriptor: sourceDescriptor,
            destinationDescriptor: destinationDescriptor
        )
        guard copied.byteCount == expectedByteCount,
              copied.sha256 == expectedSHA256,
              Darwin.fchmod(destinationDescriptor, mode_t(0o600)) == 0,
              Darwin.fsync(destinationDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func copyAndHash(
        sourceDescriptor: Int32,
        destinationDescriptor: Int32
    ) throws -> (byteCount: Int64, sha256: String) {
        var hasher = SHA256()
        var totalBytes: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let readCount = buffer.withUnsafeMutableBytes {
                Darwin.read(sourceDescriptor, $0.baseAddress, $0.count)
            }
            if readCount < 0, errno == EINTR { continue }
            guard readCount >= 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            if readCount == 0 { break }
            let addition = totalBytes.addingReportingOverflow(Int64(readCount))
            guard !addition.overflow else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            totalBytes = addition.partialValue
            var written = 0
            while written < readCount {
                let writeCount = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        destinationDescriptor,
                        bytes.baseAddress?.advanced(by: written),
                        readCount - written
                    )
                }
                if writeCount < 0, errno == EINTR { continue }
                guard writeCount > 0 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                written += writeCount
            }
            hasher.update(data: Data(buffer[0..<readCount]))
        }
        return (
            totalBytes,
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    private func removeProtectedStrictRawTerminalSpool(_ session: Session) throws {
        try removeProtectedSessionTree(
            relativePath: "terminal",
            sessionDirectoryURL: session.directoryURL
        )
    }

    private func validateProtectedSourceSpools(
        _ journal: Journal,
        sessionDirectoryURL: URL
    ) throws {
        for item in journal.recordItems + journal.rawItems {
            guard let expectedByteCount = item.byteCount,
                  let expectedSHA256 = item.sha256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let inspection = try inspectProtectedSessionFile(
                relativePath: item.relativePath,
                sessionDirectoryURL: sessionDirectoryURL
            )
            guard inspection.byteCount == expectedByteCount,
                  inspection.sha256 == expectedSHA256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            if let canonicalPath = item.canonicalJSONRelativePath,
               let canonicalByteCount = item.canonicalJSONByteCount,
               let canonicalSHA256 = item.canonicalJSONSHA256 {
                let canonicalInspection = try inspectProtectedSessionFile(
                    relativePath: canonicalPath,
                    sessionDirectoryURL: sessionDirectoryURL
                )
                guard canonicalInspection.byteCount == canonicalByteCount,
                      canonicalInspection.sha256 == canonicalSHA256 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
            }
        }
        for partial in journal.partialItems {
            guard let expectedSHA256 = partial.prefixSHA256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let inspection = try inspectProtectedSessionFile(
                relativePath: "items/\(partial.itemID.uuidString).item",
                sessionDirectoryURL: sessionDirectoryURL
            )
            guard inspection.byteCount == partial.nextOffset,
                  inspection.sha256 == expectedSHA256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
    }

    private func inspectProtectedSessionFile(
        relativePath: String,
        sessionDirectoryURL: URL
    ) throws -> (byteCount: Int64, sha256: String) {
        let descriptor = try openProtectedSessionFile(
            relativePath: relativePath,
            sessionDirectoryURL: sessionDirectoryURL
        )
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0,
              metadata.st_size > 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        var totalBytes: Int64 = 0
        while true {
            let readCount = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if readCount < 0, errno == EINTR { continue }
            guard readCount >= 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            if readCount == 0 { break }
            let total = totalBytes.addingReportingOverflow(Int64(readCount))
            guard !total.overflow, total.partialValue <= metadata.st_size else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            totalBytes = total.partialValue
            hasher.update(data: Data(buffer[0..<readCount]))
        }
        var finalMetadata = stat()
        guard totalBytes == metadata.st_size,
              Darwin.fstat(descriptor, &finalMetadata) == 0,
              finalMetadata.st_dev == metadata.st_dev,
              finalMetadata.st_ino == metadata.st_ino,
              finalMetadata.st_nlink == 1,
              finalMetadata.st_mode & S_IFMT == S_IFREG,
              finalMetadata.st_size == metadata.st_size else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return (
            totalBytes,
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    private func openProtectedSessionFile(
        relativePath: String,
        sessionDirectoryURL: URL
    ) throws -> Int32 {
        let (parentPath, filename) = try protectedParentAndFilename(relativePath)
        let parentDescriptor = try openProtectedSessionDirectory(
            relativePath: parentPath,
            sessionDirectoryURL: sessionDirectoryURL,
            createDirectories: false
        )
        defer { Darwin.close(parentDescriptor) }
        let fileDescriptor = filename.withCString {
            Darwin.openat(parentDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fileDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return fileDescriptor
    }

    private func openVerifiedProtectedSessionFile(
        relativePath: String,
        expectedByteCount: Int64,
        expectedSHA256: String,
        sessionDirectoryURL: URL
    ) throws -> Int32 {
        guard expectedByteCount > 0, expectedSHA256.isConnectedCorpusSHA256 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let descriptor = try openProtectedSessionFile(
            relativePath: relativePath,
            sessionDirectoryURL: sessionDirectoryURL
        )
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0,
              metadata.st_size == expectedByteCount else {
            Darwin.close(descriptor)
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var hasher = SHA256()
        var offset: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        do {
            while offset < expectedByteCount {
                let requested = Int(min(Int64(buffer.count), expectedByteCount - offset))
                let count = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.pread(descriptor, bytes.baseAddress, requested, off_t(offset))
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                hasher.update(data: Data(buffer[0..<count]))
                offset += Int64(count)
            }
            var finalMetadata = stat()
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == expectedSHA256,
                  Darwin.fstat(descriptor, &finalMetadata) == 0,
                  finalMetadata.st_dev == metadata.st_dev,
                  finalMetadata.st_ino == metadata.st_ino,
                  finalMetadata.st_mode == metadata.st_mode,
                  finalMetadata.st_nlink == 1,
                  finalMetadata.st_size == metadata.st_size else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func readProtectedFinalizationData(
        relativePath: String,
        expectedByteCount: UInt64,
        sessionDirectoryURL: URL
    ) throws -> Data {
        guard let expectedCount = Int(exactly: expectedByteCount) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let fileDescriptor = try openProtectedSessionFile(
            relativePath: relativePath,
            sessionDirectoryURL: sessionDirectoryURL
        )
        defer { Darwin.close(fileDescriptor) }
        var metadata = stat()
        guard Darwin.fstat(fileDescriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0,
              metadata.st_size >= 0,
              UInt64(metadata.st_size) == expectedByteCount else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var data = Data(count: expectedCount)
        var offset = 0
        while offset < expectedCount {
            let readCount = data.withUnsafeMutableBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return Darwin.read(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    expectedCount - offset
                )
            }
            if readCount < 0, errno == EINTR { continue }
            guard readCount > 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            offset += readCount
        }
        var finalMetadata = stat()
        guard Darwin.fstat(fileDescriptor, &finalMetadata) == 0,
              finalMetadata.st_dev == metadata.st_dev,
              finalMetadata.st_ino == metadata.st_ino,
              finalMetadata.st_nlink == 1,
              finalMetadata.st_mode & S_IFMT == S_IFREG,
              finalMetadata.st_size == metadata.st_size else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return data
    }

    private func immutableDigest(for plan: StoredReceivedRangePlan) throws -> String {
        let digestInput = StoredReceivedRangePlanDigest(
            schema: plan.schema,
            version: plan.version,
            destinationBinding: plan.destinationBinding,
            authority: plan.authority,
            pin: plan.pin,
            artifactPlanVersion: plan.artifactPlanVersion,
            requestID: plan.requestID,
            sessionID: plan.sessionID,
            profile: plan.profile,
            totalByteCount: plan.totalByteCount,
            dataDictionary: plan.dataDictionary,
            artifacts: plan.artifacts,
            dailyFileCount: plan.dailyFileCount,
            rollupFileCount: plan.rollupFileCount,
            requestedRecordDatesWithData: plan.requestedRecordDatesWithData
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return NativeExportArtifact.sha256(of: try encoder.encode(digestInput))
    }

    private func writeProtectedFinalizationData(
        _ data: Data,
        relativePath: String,
        sessionDirectoryURL: URL
    ) throws {
        let (parentPath, filename) = try protectedParentAndFilename(relativePath)
        let parentDescriptor = try openProtectedSessionDirectory(
            relativePath: parentPath,
            sessionDirectoryURL: sessionDirectoryURL,
            createDirectories: true
        )
        defer { Darwin.close(parentDescriptor) }

        var existing = stat()
        let existingResult = filename.withCString {
            Darwin.fstatat(parentDescriptor, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if existingResult == 0 {
            guard existing.st_mode & S_IFMT == S_IFREG,
                  existing.st_nlink == 1,
                  existing.st_mode & 0o077 == 0,
                  existing.st_size == Int64(data.count) else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let existingDescriptor = filename.withCString {
                Darwin.openat(parentDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard existingDescriptor >= 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            defer { Darwin.close(existingDescriptor) }
            let existingData = try readExactProtectedBytes(
                descriptor: existingDescriptor,
                count: data.count
            )
            var finalMetadata = stat()
            guard existingData == data,
                  Darwin.fstat(existingDescriptor, &finalMetadata) == 0,
                  finalMetadata.st_dev == existing.st_dev,
                  finalMetadata.st_ino == existing.st_ino,
                  finalMetadata.st_nlink == 1,
                  finalMetadata.st_size == existing.st_size,
                  Darwin.fsync(existingDescriptor) == 0,
                  Darwin.fsync(parentDescriptor) == 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            return
        }
        guard errno == ENOENT else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        let temporaryName = ".artifact-\(UUID().uuidString).tmp"
        let descriptor = temporaryName.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var temporaryIsPresent = true
        defer {
            Darwin.close(descriptor)
            if temporaryIsPresent {
                _ = temporaryName.withCString { Darwin.unlinkat(parentDescriptor, $0, 0) }
            }
        }
        try writeAllProtectedBytes(data, descriptor: descriptor)
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0,
              Darwin.fsync(descriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let renameResult = temporaryName.withCString { temporaryPointer in
            filename.withCString { filenamePointer in
                Darwin.renameatx_np(
                    parentDescriptor,
                    temporaryPointer,
                    parentDescriptor,
                    filenamePointer,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        temporaryIsPresent = false
        guard Darwin.fsync(parentDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func moveOrReconcileProtectedSessionFile(
        from sourceRelativePath: String,
        to destinationRelativePath: String,
        expectedByteCount: Int64,
        expectedSHA256: String,
        sessionDirectoryURL: URL
    ) throws {
        let (sourceParentPath, sourceFilename) = try protectedParentAndFilename(sourceRelativePath)
        let (destinationParentPath, destinationFilename) = try protectedParentAndFilename(
            destinationRelativePath
        )
        let sourceParent = try openProtectedSessionDirectory(
            relativePath: sourceParentPath,
            sessionDirectoryURL: sessionDirectoryURL,
            createDirectories: false
        )
        defer { Darwin.close(sourceParent) }
        let destinationParent = try openProtectedSessionDirectory(
            relativePath: destinationParentPath,
            sessionDirectoryURL: sessionDirectoryURL,
            createDirectories: false
        )
        defer { Darwin.close(destinationParent) }

        var sourceMetadata = stat()
        guard sourceFilename.withCString({
            Darwin.fstatat(sourceParent, $0, &sourceMetadata, AT_SYMLINK_NOFOLLOW)
        }) == 0,
        sourceMetadata.st_mode & S_IFMT == S_IFREG,
        sourceMetadata.st_nlink == 1,
        sourceMetadata.st_size == expectedByteCount else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        var destinationMetadata = stat()
        let destinationResult = destinationFilename.withCString {
            Darwin.fstatat(destinationParent, $0, &destinationMetadata, AT_SYMLINK_NOFOLLOW)
        }
        if destinationResult == 0 {
            let inspection = try inspectProtectedSessionFile(
                relativePath: destinationRelativePath,
                sessionDirectoryURL: sessionDirectoryURL
            )
            guard inspection.byteCount == expectedByteCount,
                  inspection.sha256 == expectedSHA256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            try removeProtectedSessionFile(
                relativePath: sourceRelativePath,
                sessionDirectoryURL: sessionDirectoryURL
            )
            return
        }
        guard errno == ENOENT else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let renameResult = sourceFilename.withCString { sourcePointer in
            destinationFilename.withCString { destinationPointer in
                Darwin.renameatx_np(
                    sourceParent,
                    sourcePointer,
                    destinationParent,
                    destinationPointer,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0,
              Darwin.fsync(sourceParent) == 0,
              Darwin.fsync(destinationParent) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func removeProtectedSessionFile(
        relativePath: String,
        sessionDirectoryURL: URL
    ) throws {
        let (parentPath, filename) = try protectedParentAndFilename(relativePath)
        let parentDescriptor = try openProtectedSessionDirectory(
            relativePath: parentPath,
            sessionDirectoryURL: sessionDirectoryURL,
            createDirectories: false
        )
        defer { Darwin.close(parentDescriptor) }
        var metadata = stat()
        guard filename.withCString({
            Darwin.fstatat(parentDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }) == 0,
        metadata.st_mode & S_IFMT == S_IFREG,
        metadata.st_nlink == 1,
        filename.withCString({ Darwin.unlinkat(parentDescriptor, $0, 0) }) == 0,
        Darwin.fsync(parentDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func protectedParentAndFilename(_ relativePath: String) throws -> (String, String) {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard let filename = components.last,
              !filename.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return (components.dropLast().joined(separator: "/"), filename)
    }

    private func openProtectedSessionDirectory(
        relativePath: String,
        sessionDirectoryURL: URL,
        createDirectories: Bool
    ) throws -> Int32 {
        var currentDescriptor = Darwin.open(
            sessionDirectoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard currentDescriptor >= 0,
              let expectedBinding = protectedSessionBindings[
                  sessionDirectoryURL.standardizedFileURL.path
              ] else {
            if currentDescriptor >= 0 { Darwin.close(currentDescriptor) }
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var rootMetadata = stat()
        guard Darwin.fstat(currentDescriptor, &rootMetadata) == 0,
              rootMetadata.st_mode & S_IFMT == S_IFDIR,
              rootMetadata.st_mode & 0o077 == 0,
              UInt64(rootMetadata.st_dev) == expectedBinding.deviceID,
              UInt64(rootMetadata.st_ino) == expectedBinding.inode else {
            Darwin.close(currentDescriptor)
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let components = relativePath.isEmpty
            ? []
            : relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            Darwin.close(currentDescriptor)
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        for component in components {
            var nextDescriptor = component.withCString {
                Darwin.openat(
                    currentDescriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            if nextDescriptor < 0, errno == ENOENT, createDirectories {
                let creationResult = component.withCString {
                    Darwin.mkdirat(currentDescriptor, $0, mode_t(0o700))
                }
                if creationResult != 0 && errno != EEXIST {
                    Darwin.close(currentDescriptor)
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                nextDescriptor = component.withCString {
                    Darwin.openat(
                        currentDescriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
            }
            guard nextDescriptor >= 0 else {
                Darwin.close(currentDescriptor)
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            var metadata = stat()
            guard Darwin.fstat(nextDescriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFDIR,
                  metadata.st_mode & 0o077 == 0 else {
                Darwin.close(nextDescriptor)
                Darwin.close(currentDescriptor)
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            Darwin.close(currentDescriptor)
            currentDescriptor = nextDescriptor
        }
        return currentDescriptor
    }

    private func writeAllProtectedBytes(_ data: Data, descriptor: Int32) throws {
        var offset = 0
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            while offset < data.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                offset += count
            }
        }
    }

    private func hasRestrictedPermissions(at url: URL, maximum: Int) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return permissions.intValue & ~maximum == 0
    }

    private func syncDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func portableDestinationPathKey(_ path: String) -> String {
        path.precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCompatibilityMapping
    }

    private static func expectedMediaType(for format: ExportFormat) -> String {
        switch format {
        case .markdown, .obsidianBases: "text/markdown; charset=utf-8"
        case .json: "application/json"
        case .csv: "text/csv; charset=utf-8"
        }
    }

    private static func isValidStoredDestinationBinding(
        _ binding: AppleVaultDestinationBinding
    ) -> Bool {
        guard binding.standardizedPath.hasPrefix("/"),
              binding.resolvedPath.hasPrefix("/"),
              binding.deviceID > 0,
              binding.inode > 0,
              URL(fileURLWithPath: binding.standardizedPath).standardizedFileURL.path
                == binding.standardizedPath,
              let resolvedPointer = Darwin.realpath(binding.standardizedPath, nil) else {
            return false
        }
        defer { Darwin.free(resolvedPointer) }
        return String(cString: resolvedPointer) == binding.resolvedPath
    }

    private func unavailableContextDay(
        payload: ConnectedCorpusHealthDayPayload,
        segment: ConnectedCorpusItemSegment,
        calendar: Calendar,
        enabledMetricIDs: Set<String>,
        includesAppleHealth: Bool
    ) throws -> HealthMdCompactContextDay {
        let intervalStart = calendar.startOfDay(for: payload.sourceDate)
        guard let intervalEnd = calendar.date(byAdding: .day, value: 1, to: intervalStart) else {
            throw ConnectedCorpusTransferModelError.invalidPartitionDates
        }
        let ownerDate = MacCorpusExportSessionManager.sourceDateString(
            payload.sourceDate,
            timeZone: calendar.timeZone
        )
        let reason = payload.failure?.reason.rawValue ?? "missing_record"
        let limitation = HealthMdLimitation(
            code: "capture_\(reason)",
            message: payload.failure?.errorDetails
                ?? "The iPhone did not provide a complete captured record for this owner day."
        )
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })
        let metrics = includesAppleHealth ? enabledMetricIDs.sorted().map { metricID in
            HealthMdContextMetric(
                observationID: "\(ownerDate):\(metricID)",
                metricID: metricID,
                displayName: definitions[metricID]?.name ?? metricID,
                value: nil,
                status: .failed,
                limitations: [limitation]
            )
        } : []
        return HealthMdCompactContextDay(
            ownerDate: ownerDate,
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            calendarTimeZone: calendar.timeZone.identifier,
            source: HealthMdSourceDescriptor(
                schema: "healthmd.connected_corpus_health_day",
                schemaVersion: 1,
                digest: segment.itemSHA256
            ),
            status: .failed,
            metrics: metrics,
            limitations: [limitation]
        )
    }

    private func applyRawDay(
        itemURL: URL,
        segment: ConnectedCorpusItemSegment,
        session: Session
    ) throws {
        let itemRelativePath = "items/\(segment.itemID.uuidString).item"
        if ConnectedCorpusApplicationItemCodec.usesStreamableItems(
            protocolVersion: session.journal.session.protocolVersion
        ) {
            let descriptor = try openVerifiedProtectedSessionFile(
                relativePath: itemRelativePath,
                expectedByteCount: segment.totalItemBytes,
                expectedSHA256: segment.itemSHA256,
                sessionDirectoryURL: session.directoryURL
            )
            defer { Darwin.close(descriptor) }
            let decoded = try ConnectedCorpusApplicationItemCodec.decodeRawDay(
                fromFileDescriptor: descriptor
            )
            defer { decoded.canonicalJSONFile?.remove() }
            let expectedIdentifier = zip(
                session.journal.exportManifest.requestedDates,
                session.journal.exportManifest.requestedDateIdentifiers ?? []
            ).first(where: { $0.0 == decoded.sourceDate })?.1
            guard decoded.sourceDate == segment.sourceDate,
                  segment.isRequestedDate,
                  expectedIdentifier == decoded.day.date,
                  !session.journal.processedDates.contains(decoded.sourceDate) else {
                throw ConnectedCorpusTransferModelError.invalidPartitionDates
            }
            let relativePath = "raw/\(segment.itemID.uuidString).item"
            let canonicalRelativePath = decoded.canonicalJSONFile.map { _ in
                "raw/\(segment.itemID.uuidString).health-data.json"
            }
            if let canonicalFile = decoded.canonicalJSONFile,
               let canonicalRelativePath {
                try copyFileIntoProtectedSession(
                    source: canonicalFile,
                    relativePath: canonicalRelativePath,
                    session: session
                )
            }
            try moveOrReconcileProtectedSessionFile(
                from: itemRelativePath,
                to: relativePath,
                expectedByteCount: segment.totalItemBytes,
                expectedSHA256: segment.itemSHA256,
                sessionDirectoryURL: session.directoryURL
            )
            session.journal.rawItems.append(StoredItem(
                sourceDate: decoded.sourceDate,
                relativePath: relativePath,
                dateIdentifier: decoded.day.date,
                byteCount: segment.totalItemBytes,
                sha256: segment.itemSHA256,
                canonicalJSONRelativePath: canonicalRelativePath,
                canonicalJSONByteCount: decoded.canonicalJSONFile?.totalBytes,
                canonicalJSONSHA256: decoded.canonicalJSONFile?.sha256
            ))
            session.journal.processedDates.append(decoded.sourceDate)
            return
        }

        let itemData = try readProtectedFinalizationData(
            relativePath: itemRelativePath,
            expectedByteCount: UInt64(segment.totalItemBytes),
            sessionDirectoryURL: session.directoryURL
        )
        guard NativeExportArtifact.sha256(of: itemData) == segment.itemSHA256 else {
            throw ConnectedCorpusTransferModelError.invalidDigest
        }
        let payload = try JSONDecoder().decode(ConnectedCorpusRawDayPayload.self, from: itemData)
        let expectedIdentifier = zip(
            session.journal.exportManifest.requestedDates,
            session.journal.exportManifest.requestedDateIdentifiers ?? []
        ).first(where: { $0.0 == payload.sourceDate })?.1
        guard payload.sourceDate == segment.sourceDate,
              segment.isRequestedDate,
              expectedIdentifier == payload.day.date,
              !session.journal.processedDates.contains(payload.sourceDate) else {
            throw ConnectedCorpusTransferModelError.invalidPartitionDates
        }
        let relativePath = "raw/\(segment.itemID.uuidString).json"
        let storedData = try JSONEncoder().encode(payload.day)
        try writeProtectedFinalizationData(
            storedData,
            relativePath: relativePath,
            sessionDirectoryURL: session.directoryURL
        )
        try removeProtectedSessionFile(
            relativePath: itemRelativePath,
            sessionDirectoryURL: session.directoryURL
        )
        session.journal.rawItems.append(StoredItem(
            sourceDate: payload.sourceDate,
            relativePath: relativePath,
            dateIdentifier: payload.day.date,
            byteCount: Int64(storedData.count),
            sha256: NativeExportArtifact.sha256(of: storedData)
        ))
        session.journal.processedDates.append(payload.sourceDate)
    }

    private func makeFileResult(
        session: Session,
        forcedStatus: MacExportResultStatus? = nil
    ) -> MacExportResultPayload {
        let requestedDates = session.journal.exportManifest.requestedDates
        var effectiveSnapshot = session.journal.exportManifest.settingsSnapshot
        if let timeZoneIdentifier = session.journal.exportManifest.effectiveOriginalCalendarTimeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            effectiveSnapshot = ExportOrchestrator.settingsByDisablingUnavailableRangeSummary(
                effectiveSnapshot,
                requestedDates: session.journal.exportManifest.effectiveOriginalRequestedDates,
                calendarTimeZone: timeZone
            ).snapshot
        }
        let settings = effectiveSnapshot.makeAdvancedExportSettings()
        let successfulDates = Set(session.journal.successfulRequestedDates)
        let durableDates = Set(session.journal.completedDates)
        let terminalNoDataDates = Set(session.journal.failedDateDetails.compactMap { detail in
            detail.reason == .noHealthData
                && detail.errorDetails == "No roll-up summary data was available for the selected period."
                ? detail.date
                : nil
        })
        let requiresDurableDate = settings.archiveModeEnabled
            || settings.summaryOnlyModeEnabled
            || session.dailyExportOperation?.usesRangePlan == true
        let successCount = requestedDates.filter {
            successfulDates.contains($0)
                && !terminalNoDataDates.contains($0)
                && (!requiresDurableDate || durableDates.contains($0))
        }.count
        let status: MacExportResultStatus = forcedStatus ?? {
            if successCount == requestedDates.count && session.journal.failedDateDetails.isEmpty { return .success }
            if successCount > 0 || (session.journal.dailyNoteSkipCount ?? 0) > 0 { return .partialSuccess }
            return .failure
        }()
        let formatsPerDate = settings.looseFormatsPerDate
        return MacExportResultPayload(
            jobID: session.journal.session.jobID,
            status: status,
            successCount: successCount,
            totalCount: requestedDates.count,
            formatsPerDate: formatsPerDate,
            totalFilesWritten: session.journal.totalFilesWritten,
            externalRecordFileCount: session.journal.externalRecordFileCount,
            dailyNoteUpdateCount: session.journal.dailyNoteUpdateCount ?? 0,
            dailyNoteSkipCount: session.journal.dailyNoteSkipCount ?? 0,
            failedDateDetails: session.journal.failedDateDetails,
            partialFailures: (session.journal.individualEntryCoverageGaps ?? [])
                + (session.journal.derivedOutputPartialFailures ?? []),
            completedDates: Array(Set(session.journal.completedDates)).sorted(),
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
    }

    private func prepareRootAndSessionDirectories(
        sessionID: UUID
    ) throws -> ProtectedSessionDirectoryBinding {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let rootDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(rootDescriptor) }
        guard Darwin.fchmod(rootDescriptor, mode_t(0o700)) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        let sessionName = sessionID.uuidString
        let creationResult = sessionName.withCString {
            Darwin.mkdirat(rootDescriptor, $0, mode_t(0o700))
        }
        guard creationResult == 0 else {
            // A directory without a securely restored journal is ambiguous and retained rather
            // than adopted as a new operation.
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let sessionDescriptor = sessionName.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard sessionDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(sessionDescriptor) }
        var sessionMetadata = stat()
        guard Darwin.fstat(sessionDescriptor, &sessionMetadata) == 0,
              sessionMetadata.st_mode & S_IFMT == S_IFDIR,
              Darwin.fchmod(sessionDescriptor, mode_t(0o700)) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        for component in ["items", "records", "raw"] {
            let childCreation = component.withCString {
                Darwin.mkdirat(sessionDescriptor, $0, mode_t(0o700))
            }
            guard childCreation == 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let childDescriptor = component.withCString {
                Darwin.openat(
                    sessionDescriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard childDescriptor >= 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let childSync = Darwin.fchmod(childDescriptor, mode_t(0o700)) == 0
                && Darwin.fsync(childDescriptor) == 0
            Darwin.close(childDescriptor)
            guard childSync else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
        guard Darwin.fsync(sessionDescriptor) == 0,
              Darwin.fsync(rootDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        try syncDirectory(at: rootURL.deletingLastPathComponent())

        let directory = sessionDirectory(sessionID: sessionID)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        return ProtectedSessionDirectoryBinding(
            deviceID: UInt64(sessionMetadata.st_dev),
            inode: UInt64(sessionMetadata.st_ino)
        )
    }

    private func persist(_ session: Session) throws {
        #if DEBUG
        if (session.journal.state == .completed || session.journal.state == .failed),
           failNextTerminalPersistForTesting {
            failNextTerminalPersistForTesting = false
            throw CocoaError(.fileWriteUnknown)
        }
        if session.journal.state == .open,
           !session.journal.committedPartitions.isEmpty,
           failNextPartitionPersistForTesting {
            failNextPartitionPersistForTesting = false
            throw CocoaError(.fileWriteUnknown)
        }
        #endif
        guard let protectedBinding = protectedSessionBindings[
            session.directoryURL.standardizedFileURL.path
        ],
        session.journal.protectedSessionDeviceID == protectedBinding.deviceID,
        session.journal.protectedSessionInode == protectedBinding.inode else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        session.journal.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(session.journal)
        guard !data.isEmpty, data.count <= 32 * 1_024 * 1_024 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let directoryDescriptor = try openProtectedSessionDirectory(
            relativePath: "",
            sessionDirectoryURL: session.directoryURL,
            createDirectories: false
        )
        defer { Darwin.close(directoryDescriptor) }
        guard let resolvedDirectoryPointer = Darwin.realpath(session.directoryURL.path, nil) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.free(resolvedDirectoryPointer) }
        let expectedDirectoryPath = String(cString: resolvedDirectoryPointer)
        guard try protectedDescriptorPath(directoryDescriptor) == expectedDirectoryPath else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        let temporaryName = ".journal-\(UUID().uuidString).tmp"
        let temporaryDescriptor = temporaryName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard temporaryDescriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var temporaryIsPresent = true
        defer {
            Darwin.close(temporaryDescriptor)
            if temporaryIsPresent {
                _ = temporaryName.withCString {
                    Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }
        try writeAllProtectedBytes(data, descriptor: temporaryDescriptor)
        guard Darwin.fchmod(temporaryDescriptor, mode_t(0o600)) == 0,
              Darwin.fsync(temporaryDescriptor) == 0,
              try protectedDescriptorPath(directoryDescriptor) == expectedDirectoryPath else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let temporaryPath = URL(
            fileURLWithPath: expectedDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(temporaryName).path
        let journalPath = URL(
            fileURLWithPath: expectedDirectoryPath,
            isDirectory: true
        ).appendingPathComponent("journal.json").path
        let renameResult = temporaryPath.withCString { source in
            journalPath.withCString { destination in
                Darwin.renamex_np(
                    source,
                    destination,
                    UInt32(RENAME_NOFOLLOW_ANY)
                )
            }
        }
        guard renameResult == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        temporaryIsPresent = false
        do {
            #if DEBUG
            let failRangePlan = session.journal.state == .finalizing
                && session.journal.receivedRangePlanPersisted == true
                && failNextPostRenameRangePlanSyncForTesting
            let failTerminal = (session.journal.state == .completed || session.journal.state == .failed)
                && failNextPostRenameTerminalSyncForTesting
            if failNextPostRenameJournalSyncForTesting || failRangePlan || failTerminal {
                failNextPostRenameJournalSyncForTesting = false
                if failRangePlan { failNextPostRenameRangePlanSyncForTesting = false }
                if failTerminal { failNextPostRenameTerminalSyncForTesting = false }
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            guard Darwin.fsync(directoryDescriptor) == 0,
                  try protectedDescriptorPath(directoryDescriptor) == expectedDirectoryPath else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        } catch {
            throw JournalPersistenceError.postPublication
        }
    }

    private func protectedDescriptorPath(_ descriptor: Int32) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard Darwin.fcntl(descriptor, F_GETPATH, &buffer) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return String(cString: buffer)
    }

    private func readProtectedJournal(
        sessionID: UUID
    ) throws -> (data: Data, binding: ProtectedSessionDirectoryBinding)? {
        let rootDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        if rootDescriptor < 0, errno == ENOENT { return nil }
        guard rootDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(rootDescriptor) }

        let sessionDescriptor = sessionID.uuidString.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        if sessionDescriptor < 0, errno == ENOENT { return nil }
        guard sessionDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(sessionDescriptor) }
        var sessionMetadata = stat()
        guard Darwin.fstat(sessionDescriptor, &sessionMetadata) == 0,
              sessionMetadata.st_mode & S_IFMT == S_IFDIR,
              sessionMetadata.st_mode & 0o077 == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        let journalDescriptor = "journal.json".withCString {
            Darwin.openat(sessionDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        if journalDescriptor < 0, errno == ENOENT { return nil }
        guard journalDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(journalDescriptor) }
        var journalMetadata = stat()
        guard Darwin.fstat(journalDescriptor, &journalMetadata) == 0,
              journalMetadata.st_mode & S_IFMT == S_IFREG,
              journalMetadata.st_nlink == 1,
              journalMetadata.st_mode & 0o077 == 0,
              journalMetadata.st_size > 0,
              journalMetadata.st_size <= 32 * 1_024 * 1_024,
              let count = Int(exactly: journalMetadata.st_size) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let data = try readExactProtectedBytes(descriptor: journalDescriptor, count: count)
        var finalMetadata = stat()
        guard Darwin.fstat(journalDescriptor, &finalMetadata) == 0,
              finalMetadata.st_dev == journalMetadata.st_dev,
              finalMetadata.st_ino == journalMetadata.st_ino,
              finalMetadata.st_nlink == 1,
              finalMetadata.st_size == journalMetadata.st_size else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        return (
            data,
            ProtectedSessionDirectoryBinding(
                deviceID: UInt64(sessionMetadata.st_dev),
                inode: UInt64(sessionMetadata.st_ino)
            )
        )
    }

    private func readExactProtectedBytes(descriptor: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let readCount = data.withUnsafeMutableBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return Darwin.read(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    count - offset
                )
            }
            if readCount < 0, errno == EINTR { continue }
            guard readCount > 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            offset += readCount
        }
        return data
    }

    private func restoreSession(sessionID: UUID) throws -> Session? {
        let directory = sessionDirectory(sessionID: sessionID)
        guard let protectedJournal = try readProtectedJournal(sessionID: sessionID) else {
            return nil
        }
        let actualBinding = protectedJournal.binding
        protectedSessionBindings[directory.standardizedFileURL.path] = actualBinding
        var journal = try JSONDecoder().decode(Journal.self, from: protectedJournal.data)
        let storedVersion = journal.version
        guard (2...Journal.currentVersion).contains(storedVersion) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let usesRangePlan = try journalUsesReceivedRangePlan(journal)
        if storedVersion < 4 {
            journal.protectedSessionDeviceID = actualBinding.deviceID
            journal.protectedSessionInode = actualBinding.inode
            // Old `.finalizing` range journals may already have changed destination files without
            // persisting the selected bytes. Re-rendering or restarting at artifact zero is unsafe.
            guard !(journal.state == .finalizing && usesRangePlan) else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            journal.receivedRangePlanPersisted = false
            journal.receivedRangePlan = nil
            if journal.state == .open || journal.state == .finalizing {
                journal.recordItems = try bindLegacyStoredItems(
                    journal.recordItems,
                    prefix: "records/",
                    sessionDirectoryURL: directory
                )
                journal.rawItems = try bindLegacyStoredItems(
                    journal.rawItems,
                    prefix: "raw/",
                    sessionDirectoryURL: directory
                )
                for index in journal.partialItems.indices {
                    let relativePath = "items/\(journal.partialItems[index].itemID.uuidString).item"
                    let inspection = try inspectProtectedSessionFile(
                        relativePath: relativePath,
                        sessionDirectoryURL: directory
                    )
                    guard inspection.byteCount == journal.partialItems[index].nextOffset else {
                        throw ConnectedCorpusTransferModelError.invalidJournal
                    }
                    journal.partialItems[index].prefixSHA256 = inspection.sha256
                }
            }
            if journal.state == .completed,
               journal.exportManifest.mode == .strictRaw,
               let retainedCount = journal.terminalAcknowledgement?.successCount,
               retainedCount >= 0,
               retainedCount <= journal.rawItems.count {
                journal.strictRawRetainedDayCount = retainedCount
            }
        } else {
            guard journal.receivedRangePlanPersisted != nil,
                  journal.protectedSessionDeviceID == actualBinding.deviceID,
                  journal.protectedSessionInode == actualBinding.inode else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
        journal.version = Journal.currentVersion
        try validateRestoredJournal(journal, sessionID: sessionID)
        if journal.state == .open
            || (journal.state == .finalizing && journal.receivedRangePlan == nil) {
            try validateProtectedSourceSpools(journal, sessionDirectoryURL: directory)
        }
        if let plan = journal.receivedRangePlan {
            try validateStoredReceivedRangePlan(
                plan,
                journal: journal,
                sessionDirectoryURL: directory
            )
        }
        if let strictSpool = journal.strictRawTerminalSpool {
            guard journal.state == .completed,
                  journal.exportManifest.mode == .strictRaw,
                  strictSpool.relativePath == StoredStrictRawTerminalSpool.relativePath,
                  strictSpool.byteCount > 0,
                  strictSpool.sha256.isConnectedCorpusSHA256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let inspection = try inspectProtectedSessionFile(
                relativePath: strictSpool.relativePath,
                sessionDirectoryURL: directory
            )
            guard inspection.byteCount == strictSpool.byteCount,
                  inspection.sha256 == strictSpool.sha256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
        let session = try Session(directoryURL: directory, journal: journal)
        if storedVersion < Journal.currentVersion {
            try persist(session)
        }
        return session
    }

    private func validateRestoredJournal(_ journal: Journal, sessionID: UUID) throws {
        try journal.exportManifest.validate()
        let canonicalExpiry = journal.session.createdAt.addingTimeInterval(
            ConnectedCorpusOutboundStore.retentionInterval
        )
        guard journal.session.createdAt.timeIntervalSinceReferenceDate.isFinite,
              journal.session.createdAt <= Date().addingTimeInterval(5 * 60),
              journal.version == Journal.currentVersion,
              journal.session.sessionID == sessionID,
              ConnectedCorpusTransferCapabilities.current.protocolVersions.contains(
                  journal.session.protocolVersion
              ),
              journal.session.requestFingerprint == (try ConnectedCorpusRequestFingerprint.make(
                for: journal.exportManifest
              )),
              (journal.expiresAt ?? canonicalExpiry) == canonicalExpiry,
              journal.totalPartitionBytes >= 0,
              journal.totalFilesWritten >= 0,
              journal.externalRecordFileCount >= 0,
              journal.strictRawRetainedDayCount.map({ $0 >= 0 }) ?? true,
              journal.protectedSessionDeviceID.map({ $0 > 0 }) ?? false,
              journal.protectedSessionInode.map({ $0 > 0 }) ?? false else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var totalBytes: Int64 = 0
        var previousDigest: String?
        for (index, descriptor) in journal.committedPartitions.enumerated() {
            try descriptor.validate()
            let sum = totalBytes.addingReportingOverflow(descriptor.byteCount)
            guard !sum.overflow,
                  descriptor.sessionID == sessionID,
                  descriptor.jobID == journal.session.jobID,
                  descriptor.index == index,
                  descriptor.previousSHA256 == previousDigest,
                  Set(descriptor.sourceDates).isSubset(of: Set(journal.exportManifest.transferDates)) else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            totalBytes = sum.partialValue
            previousDigest = descriptor.sha256
        }
        let processed = Set(journal.processedDates)
        let requested = Set(journal.exportManifest.requestedDates)
        let transfer = Set(journal.exportManifest.transferDates)
        let partialIDs = journal.partialItems.map(\.itemID)
        let completedItemIDs = Set(journal.completedItemIDs)
        let requiresSourceSpoolBindings = journal.state == .open || journal.state == .finalizing
        guard totalBytes == journal.totalPartitionBytes,
              Set(partialIDs).count == partialIDs.count,
              completedItemIDs.count == journal.completedItemIDs.count,
              completedItemIDs.isDisjoint(with: Set(partialIDs)),
              journal.partialItems.allSatisfy({
                  transfer.contains($0.sourceDate)
                      && !processed.contains($0.sourceDate)
                      && $0.totalItemBytes > 0
                      && $0.nextOffset > 0
                      && $0.nextOffset < $0.totalItemBytes
                      && $0.itemSHA256.isConnectedCorpusSHA256
                      && (!requiresSourceSpoolBindings
                          || $0.prefixSHA256?.isConnectedCorpusSHA256 == true)
              }),
              processed.count == journal.processedDates.count,
              processed.isSubset(of: transfer),
              Set(journal.successfulRequestedDates).isSubset(of: requested),
              Set(journal.completedDates).isSubset(of: requested),
              journal.failedDateDetails.allSatisfy({ requested.contains($0.date) }),
              journal.supportingDateFailures.allSatisfy({
                  transfer.contains($0.date) && !requested.contains($0.date)
              }),
              journal.recordItems.allSatisfy({
                  processed.contains($0.sourceDate)
                      && Self.isSafeStoredPath($0.relativePath, prefix: "records/")
                      && $0.canonicalJSONRelativePath == nil
                      && $0.canonicalJSONByteCount == nil
                      && $0.canonicalJSONSHA256 == nil
                      && (!requiresSourceSpoolBindings
                          || (($0.byteCount.map { $0 > 0 } ?? false)
                              && $0.sha256?.isConnectedCorpusSHA256 == true))
              }),
              journal.rawItems.allSatisfy({ item in
                  let canonicalFields = [
                      item.canonicalJSONRelativePath != nil,
                      item.canonicalJSONByteCount != nil,
                      item.canonicalJSONSHA256 != nil
                  ]
                  let canonicalBindingIsValid = canonicalFields.allSatisfy { !$0 }
                      || (canonicalFields.allSatisfy { $0 }
                          && Self.isSafeStoredPath(
                              item.canonicalJSONRelativePath ?? "",
                              prefix: "raw/"
                          )
                          && (item.canonicalJSONByteCount.map { $0 > 0 } ?? false)
                          && item.canonicalJSONSHA256?.isConnectedCorpusSHA256 == true)
                  return processed.contains(item.sourceDate)
                      && Self.isSafeStoredPath(item.relativePath, prefix: "raw/")
                      && canonicalBindingIsValid
                      && (ConnectedCorpusApplicationItemCodec.usesStreamableItems(
                          protocolVersion: journal.session.protocolVersion
                      ) || canonicalFields.allSatisfy { !$0 })
                      && (!requiresSourceSpoolBindings
                          || ((item.byteCount.map { $0 > 0 } ?? false)
                              && item.sha256?.isConnectedCorpusSHA256 == true))
              }) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        if let acknowledgement = journal.terminalAcknowledgement {
            guard acknowledgement.sessionID == sessionID,
                  acknowledgement.jobID == journal.session.jobID,
                  acknowledgement.requestFingerprint == journal.session.requestFingerprint,
                  acknowledgement.finalPartitionSHA256 == journal.committedPartitions.last?.sha256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
        if (journal.state == .completed || journal.state == .failed),
           journal.terminalAcknowledgement == nil {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        guard let planPersisted = journal.receivedRangePlanPersisted else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let usesRangePlan = try journalUsesReceivedRangePlan(journal)
        if journal.receivedRangePlan != nil {
            guard planPersisted,
                  usesRangePlan,
                  journal.state == .finalizing else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        } else if planPersisted,
                  journal.state != .completed,
                  journal.state != .cancelled,
                  journal.state != .failed {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        if !usesRangePlan,
           planPersisted || journal.receivedRangePlan != nil {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        if usesRangePlan,
           journal.exportManifest.transferDates.count > HealthRollupRangeRequest.maximumDays {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        if journal.state == .open,
           planPersisted || journal.receivedRangePlan != nil {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        if journal.exportManifest.mode != .strictRaw
            || journal.state != .completed {
            guard journal.strictRawRetainedDayCount == nil,
                  journal.strictRawTerminalSpool == nil else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
        try validateTerminalEnvelope(journal)
    }

    private func validateTerminalEnvelope(_ journal: Journal) throws {
        if journal.state == .failed {
            guard journal.partialItems.isEmpty,
                  journal.terminalResult == nil,
                  let failure = journal.terminalFailure,
                  failure.jobID == journal.session.jobID,
                  let acknowledgement = journal.terminalAcknowledgement,
                  !acknowledgement.accepted,
                  acknowledgement.sessionID == journal.session.sessionID,
                  acknowledgement.jobID == journal.session.jobID,
                  acknowledgement.requestFingerprint == journal.session.requestFingerprint,
                  acknowledgement.finalPartitionSHA256 == journal.committedPartitions.last?.sha256,
                  acknowledgement.message == failure.message else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            return
        }
        guard journal.state == .completed else {
            guard journal.terminalAcknowledgement == nil,
                  journal.terminalResult == nil,
                  journal.terminalFailure == nil else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            return
        }
        guard journal.partialItems.isEmpty,
              journal.terminalFailure == nil,
              let acknowledgement = journal.terminalAcknowledgement,
              acknowledgement.accepted,
              acknowledgement.sessionID == journal.session.sessionID,
              acknowledgement.jobID == journal.session.jobID,
              acknowledgement.requestFingerprint == journal.session.requestFingerprint,
              acknowledgement.finalPartitionSHA256 == journal.committedPartitions.last?.sha256 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }

        switch journal.exportManifest.mode {
        case .strictRaw:
            guard let retainedDayCount = journal.strictRawRetainedDayCount,
                  retainedDayCount <= journal.rawItems.count,
                  journal.terminalResult == nil,
                  acknowledgement.completedDates == journal.exportManifest.requestedDates,
                  acknowledgement.successCount == retainedDayCount,
                  acknowledgement.totalCount == journal.exportManifest.requestedDates.count,
                  acknowledgement.message == "Strict raw corpus finalized." else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            if let strictSpool = journal.strictRawTerminalSpool {
                guard strictSpool.relativePath == StoredStrictRawTerminalSpool.relativePath,
                      strictSpool.byteCount > 0,
                      strictSpool.sha256.isConnectedCorpusSHA256,
                      strictSpool.profile == (journal.exportManifest.rawProfile
                        ?? .canonicalSourceRecordsV1),
                      strictSpool.canonicalSelection == journal.exportManifest.canonicalSelection,
                      strictSpool.captureSummary.retainedDayCount == retainedDayCount,
                      strictSpool.totalRequestedDays
                        == journal.exportManifest.requestedDates.count,
                      strictSpool.missingDates.count
                        == strictSpool.captureSummary.missingDayCount else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
            }
        case .writeFiles, .encryptedContext:
            guard let result = journal.terminalResult else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            let requestedDates = journal.exportManifest.requestedDates
            var effectiveSnapshot = journal.exportManifest.settingsSnapshot
            if let timeZoneIdentifier = journal.exportManifest.effectiveOriginalCalendarTimeZoneIdentifier,
               let timeZone = TimeZone(identifier: timeZoneIdentifier) {
                effectiveSnapshot = ExportOrchestrator.settingsByDisablingUnavailableRangeSummary(
                    effectiveSnapshot,
                    requestedDates: journal.exportManifest.effectiveOriginalRequestedDates,
                    calendarTimeZone: timeZone
                ).snapshot
            }
            let settings = effectiveSnapshot.makeAdvancedExportSettings()
            let successfulDates = Set(journal.successfulRequestedDates)
            let durableDates = Set(journal.completedDates)
            let terminalNoDataDates = Set(journal.failedDateDetails.compactMap { detail in
                detail.reason == .noHealthData
                    && detail.errorDetails == "No roll-up summary data was available for the selected period."
                    ? detail.date
                    : nil
            })
            let successCount = requestedDates.count {
                successfulDates.contains($0)
                    && !terminalNoDataDates.contains($0)
                    && (!settings.archiveModeEnabled && !settings.summaryOnlyModeEnabled
                        || durableDates.contains($0))
            }
            let expectedStatus: MacExportResultStatus
            if successCount == requestedDates.count && journal.failedDateDetails.isEmpty {
                expectedStatus = .success
            } else if successCount > 0 || (journal.dailyNoteSkipCount ?? 0) > 0 {
                expectedStatus = .partialSuccess
            } else {
                expectedStatus = .failure
            }
            let completedDates = Array(Set(journal.completedDates)).sorted()
            let expectedMessage = journal.exportManifest.mode == .encryptedContext
                ? "Encrypted query context finalized."
                : "Corpus export finalized."
            guard result.jobID == journal.session.jobID,
                  result.status == expectedStatus,
                  result.successCount == successCount,
                  result.totalCount == requestedDates.count,
                  result.formatsPerDate == settings.looseFormatsPerDate,
                  result.totalFilesWritten == journal.totalFilesWritten,
                  result.externalRecordFileCount == journal.externalRecordFileCount,
                  result.dailyNoteUpdateCount == (journal.dailyNoteUpdateCount ?? 0),
                  result.dailyNoteSkipCount == (journal.dailyNoteSkipCount ?? 0),
                  failedDateDetailsMatch(result.failedDateDetails, journal.failedDateDetails),
                  result.completedDates == completedDates,
                  result.destinationDisplayName == nil,
                  result.destinationPathForDisplay == nil,
                  result.completedAt >= journal.session.createdAt,
                  result.completedAt <= journal.updatedAt.addingTimeInterval(1),
                  acknowledgement.completedDates == completedDates,
                  acknowledgement.successCount == successCount,
                  acknowledgement.totalCount == requestedDates.count,
                  acknowledgement.message == expectedMessage else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
    }

    private func failedDateDetailsMatch(
        _ lhs: [FailedDateDetail],
        _ rhs: [FailedDateDetail]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
            left.date == right.date
                && left.reason.rawValue == right.reason.rawValue
                && left.errorDetails == right.errorDetails
        }
    }

    private func journalUsesReceivedRangePlan(_ journal: Journal) throws -> Bool {
        guard journal.exportManifest.mode == .writeFiles else { return false }
        return try ConnectedMacDailyExportOperation.resolve(
            settingsSnapshot: journal.exportManifest.settingsSnapshot,
            declaredPin: journal.exportManifest.effectiveAppleExportEnginePin,
            supportsRangePlan: journal.session.protocolVersion
                >= ConnectedCorpusTransferCapabilities.rangePlanProtocolVersion
        ).usesRangePlan
    }

    private static func isSafeStoredPath(_ path: String, prefix: String) -> Bool {
        path.hasPrefix(prefix)
            && !path.hasPrefix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private func sessionDirectory(sessionID: UUID) -> URL {
        rootURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    private func cleanupPayloadFiles(_ session: Session) {
        #if DEBUG
        let cleanupHook = beforeProtectedCleanupForTesting
        beforeProtectedCleanupForTesting = nil
        try? cleanupHook?()
        #endif
        for relativePath in ["items", "records", "raw", "finalization"] {
            try? removeProtectedSessionTree(
                relativePath: relativePath,
                sessionDirectoryURL: session.directoryURL
            )
        }
    }

    private func syncProtectedSessionDirectory(
        relativePath: String,
        sessionDirectoryURL: URL
    ) throws {
        let descriptor = try openProtectedSessionDirectory(
            relativePath: relativePath,
            sessionDirectoryURL: sessionDirectoryURL,
            createDirectories: false
        )
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func removeProtectedSessionTree(
        relativePath: String,
        sessionDirectoryURL: URL
    ) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.count == 1,
              let name = components.first,
              !name.isEmpty,
              name != ".",
              name != ".." else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let rootDescriptor = try openProtectedSessionDirectory(
            relativePath: "",
            sessionDirectoryURL: sessionDirectoryURL,
            createDirectories: false
        )
        defer { Darwin.close(rootDescriptor) }
        var metadata = stat()
        let status = name.withCString {
            Darwin.fstatat(rootDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if status != 0, errno == ENOENT { return }
        guard status == 0, metadata.st_mode & S_IFMT == S_IFDIR else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        let directoryDescriptor = name.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard directoryDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var directoryIsOpen = true
        defer {
            if directoryIsOpen { Darwin.close(directoryDescriptor) }
        }
        try removeProtectedDirectoryContents(directoryDescriptor)
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        Darwin.close(directoryDescriptor)
        directoryIsOpen = false
        guard name.withCString({
            Darwin.unlinkat(rootDescriptor, $0, AT_REMOVEDIR)
        }) == 0,
        Darwin.fsync(rootDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func removeProtectedDirectoryContents(_ descriptor: Int32) throws {
        let scanDescriptor = Darwin.fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        guard scanDescriptor >= 0, let directory = Darwin.fdopendir(scanDescriptor) else {
            if scanDescriptor >= 0 { Darwin.close(scanDescriptor) }
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.closedir(directory) }
        while let entry = Darwin.readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { rawBuffer -> String in
                let characters = rawBuffer.bindMemory(to: CChar.self)
                guard let baseAddress = characters.baseAddress else { return "" }
                return String(cString: baseAddress)
            }
            if name == "." || name == ".." { continue }
            guard !name.isEmpty else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            var metadata = stat()
            guard name.withCString({
                Darwin.fstatat(descriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
            }) == 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            if metadata.st_mode & S_IFMT == S_IFDIR {
                let childDescriptor = name.withCString {
                    Darwin.openat(
                        descriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                guard childDescriptor >= 0 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
                do {
                    try removeProtectedDirectoryContents(childDescriptor)
                    guard Darwin.fsync(childDescriptor) == 0 else {
                        throw ConnectedCorpusTransferModelError.invalidJournal
                    }
                    Darwin.close(childDescriptor)
                } catch {
                    Darwin.close(childDescriptor)
                    throw error
                }
                guard name.withCString({
                    Darwin.unlinkat(descriptor, $0, AT_REMOVEDIR)
                }) == 0 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
            } else {
                guard name.withCString({ Darwin.unlinkat(descriptor, $0, 0) }) == 0 else {
                    throw ConnectedCorpusTransferModelError.invalidJournal
                }
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
    }

    private func cleanupExpiredSessions(
        now: Date = Date(),
        vaultManager: VaultManager? = nil
    ) {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for directory in directories where directory != activeSession?.directoryURL {
            guard let sessionID = UUID(uuidString: directory.lastPathComponent) else { continue }
            guard let restored = try? restoreSession(sessionID: sessionID) else {
                // Before the fixed retention deadline, corrupt state remains quarantined so the
                // same durable session cannot look missing and restart external writes. After the
                // app-private directory itself has aged past retention, remove it through bound,
                // no-follow descriptors so corrupt health payloads cannot persist indefinitely.
                guard let expiredIdentity = corruptSessionDirectoryIdentityIfExpired(
                    sessionID: sessionID,
                    now: now
                ) else {
                    continue
                }
                if let vaultURL = vaultManager?.vaultURL {
                    try? fileManager.removeItem(at: Self.archiveWorkDirectoryURL(
                        vaultURL: vaultURL,
                        sessionID: sessionID
                    ))
                }
                try? removeExpiredProtectedSessionDirectory(
                    sessionID: sessionID,
                    expectedIdentity: expiredIdentity
                )
                continue
            }
            let journal = restored.journal
            let expiresAt = journal.session.createdAt.addingTimeInterval(
                ConnectedCorpusOutboundStore.retentionInterval
            )
            if now >= expiresAt {
                if let vaultURL = vaultManager?.vaultURL {
                    let archiveWork = Self.archiveWorkDirectoryURL(
                        vaultURL: vaultURL,
                        sessionID: journal.session.sessionID
                    )
                    try? fileManager.removeItem(at: archiveWork)
                }
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private func corruptSessionDirectoryIdentityIfExpired(
        sessionID: UUID,
        now: Date
    ) -> ExpiredCorruptSessionIdentity? {
        let rootDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else { return nil }
        defer { Darwin.close(rootDescriptor) }
        let name = sessionID.uuidString
        let descriptor = name.withCString {
            Darwin.openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_birthtimespec.tv_sec > 0 else {
            return nil
        }
        let createdAt = Date(
            timeIntervalSince1970: TimeInterval(metadata.st_birthtimespec.tv_sec)
                + TimeInterval(metadata.st_birthtimespec.tv_nsec) / 1_000_000_000
        )
        guard createdAt <= now.addingTimeInterval(
            -ConnectedCorpusOutboundStore.retentionInterval
        ) else {
            return nil
        }
        return ExpiredCorruptSessionIdentity(
            binding: ProtectedSessionDirectoryBinding(
                deviceID: UInt64(metadata.st_dev),
                inode: UInt64(metadata.st_ino)
            ),
            birthSeconds: metadata.st_birthtimespec.tv_sec,
            birthNanoseconds: metadata.st_birthtimespec.tv_nsec
        )
    }

    private func removeExpiredProtectedSessionDirectory(
        sessionID: UUID,
        expectedIdentity: ExpiredCorruptSessionIdentity
    ) throws {
        let rootDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        defer { Darwin.close(rootDescriptor) }
        let name = sessionID.uuidString
        let descriptor = name.withCString {
            Darwin.openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        var descriptorMetadata = stat()
        guard Darwin.fstat(descriptor, &descriptorMetadata) == 0,
              UInt64(descriptorMetadata.st_dev) == expectedIdentity.binding.deviceID,
              UInt64(descriptorMetadata.st_ino) == expectedIdentity.binding.inode,
              descriptorMetadata.st_birthtimespec.tv_sec == expectedIdentity.birthSeconds,
              descriptorMetadata.st_birthtimespec.tv_nsec == expectedIdentity.birthNanoseconds else {
            Darwin.close(descriptor)
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        do {
            try removeProtectedDirectoryContents(descriptor)
            guard Darwin.fsync(descriptor) == 0 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
            Darwin.close(descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        var liveMetadata = stat()
        guard name.withCString({
            Darwin.fstatat(rootDescriptor, $0, &liveMetadata, AT_SYMLINK_NOFOLLOW)
        }) == 0,
              UInt64(liveMetadata.st_dev) == expectedIdentity.binding.deviceID,
              UInt64(liveMetadata.st_ino) == expectedIdentity.binding.inode,
              liveMetadata.st_birthtimespec.tv_sec == expectedIdentity.birthSeconds,
              liveMetadata.st_birthtimespec.tv_nsec == expectedIdentity.birthNanoseconds,
              name.withCString({ Darwin.unlinkat(rootDescriptor, $0, AT_REMOVEDIR) }) == 0,
              Darwin.fsync(rootDescriptor) == 0 else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        protectedSessionBindings.removeValue(
            forKey: sessionDirectory(sessionID: sessionID).standardizedFileURL.path
        )
    }

    private func destinationPathsAreContained(
        manifest: ConnectedCorpusExportManifest,
        vaultURL: URL
    ) -> Bool {
        let settings = manifest.settingsSnapshot.makeAdvancedExportSettings()
        settings.exportTimeZoneOverride = manifest.sourceTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        let healthSubfolder = manifest.settingsSnapshot.healthSubfolder ?? ""
        var candidates: [URL] = []
        if settings.writesDailyAggregateFiles {
            candidates.append(contentsOf: manifest.requestedDates.flatMap { date in
                ExportPathPlanner.aggregateOutputTargets(
                    vaultURL: vaultURL,
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date
                ).map(\.url)
            })
            candidates.append(ExportPathPlanner.healthSubfolderURL(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder
            ))
        }
        if settings.dailyNoteInjection.enabled {
            candidates.append(contentsOf: manifest.requestedDates.map {
                ExportPathPlanner.dailyNoteURL(
                    vaultURL: vaultURL,
                    settings: settings.dailyNoteInjection,
                    date: $0,
                    timeZone: settings.exportTimeZoneOverride ?? .current
                )
            })
        }
        if settings.writesIndividualEntryFiles {
            let entriesRoot = ExportPathPlanner.appendingRelativePath(
                settings.individualTracking.entriesFolder,
                to: vaultURL,
                isDirectory: true
            )
            candidates.append(entriesRoot)
            candidates.append(contentsOf: settings.individualTracking.metricConfigs.values.compactMap {
                $0.customFolder.map {
                    ExportPathPlanner.appendingRelativePath($0, to: entriesRoot, isDirectory: true)
                }
            })
        }
        if settings.hasFileDestinationOutput {
            for period in settings.enabledRollupPeriods {
                for format in settings.exportFormats {
                    candidates.append(HealthRollupExporter.folderURL(
                        vaultURL: vaultURL,
                        healthSubfolder: healthSubfolder,
                        period: period,
                        format: format,
                        settings: settings
                    ))
                }
            }
        }
        let canonicalRoot = vaultURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        return candidates.allSatisfy { candidate in
            let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
            return path == canonicalRoot || path.hasPrefix(rootPrefix)
        }
    }

    private func cleanupArchiveWork(session: Session, vaultManager: VaultManager) {
        guard let vaultURL = vaultManager.vaultURL else { return }
        let work = Self.archiveWorkDirectoryURL(
            vaultURL: vaultURL,
            sessionID: session.journal.session.sessionID
        )
        try? fileManager.removeItem(at: work)
        let parent = work.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? fileManager.removeItem(at: parent)
        }
    }

    private static func archiveWorkDirectoryURL(vaultURL: URL, sessionID: UUID) -> URL {
        vaultURL
            .appendingPathComponent(".healthmd-archive-work", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    private func ensurePartitionExecutionIsActive(_ session: Session) throws {
        guard !Task.isCancelled,
              activeSession === session,
              partitionExecutionSessionID == session.journal.session.sessionID,
              session.journal.state == .open else {
            throw CancellationError()
        }
    }

    private func ensureFinalizationIsActive(_ session: Session) throws {
        guard !Task.isCancelled,
              activeSession === session,
              session.journal.state == .finalizing else {
            throw CancellationError()
        }
    }

    private func hasAvailableDiskSpace(at url: URL, requiredBytes: Int64) -> Bool {
        if let diskSpaceCheck {
            return diskSpaceCheck(url, requiredBytes)
        }
        let probe = fileManager.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        if let values = try? probe.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) {
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return available >= requiredBytes
            }
            if let available = values.volumeAvailableCapacity {
                return Int64(available) >= requiredBytes
            }
        }
        return false
    }

    private static func sourceDateString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static let sourceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
#endif
