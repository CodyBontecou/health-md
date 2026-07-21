#if os(macOS)
import Foundation

enum MacCorpusFinalizeOutcome {
    case files(result: MacExportResultPayload, acknowledgement: ConnectedCorpusTransferFinalAck)
    case strictRaw(spool: CanonicalRawResultSpool, acknowledgement: ConnectedCorpusTransferFinalAck)
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

        init(sourceDate: Date, relativePath: String, dateIdentifier: String? = nil) {
            self.sourceDate = sourceDate
            self.relativePath = relativePath
            self.dateIdentifier = dateIdentifier
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
    }

    private struct Journal: Codable {
        static let currentVersion = 3

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
        /// Optional so journals created before one-time dictionary tracking decode unchanged.
        var dataDictionaryWritten: Bool? = nil
        var terminalResult: MacExportResultPayload? = nil
        var terminalAcknowledgement: ConnectedCorpusTransferFinalAck? = nil
        /// Fixed recovery deadline. Optional only so existing v2 journals remain
        /// decodable and receive a conservative deadline from session creation.
        let expiresAt: Date?
        var updatedAt: Date
    }

    private final class Session {
        let directoryURL: URL
        var journal: Journal

        init(directoryURL: URL, journal: Journal) {
            self.directoryURL = directoryURL
            self.journal = journal
        }

        var journalURL: URL { directoryURL.appendingPathComponent("journal.json") }
        var itemDirectoryURL: URL { directoryURL.appendingPathComponent("items", isDirectory: true) }
        var recordDirectoryURL: URL { directoryURL.appendingPathComponent("records", isDirectory: true) }
        var rawDirectoryURL: URL { directoryURL.appendingPathComponent("raw", isDirectory: true) }
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let diskSpaceCheck: ((URL, Int64) -> Bool)?
    private let queryContextStore: EncryptedHealthContextStore?
    private var activeSession: Session?
    /// One successful `open` grants one exact transport-start admission. The
    /// admission is consumed before a receiver spool is created.
    private var admittedPartitions: Set<ConnectedCorpusPartitionDescriptor> = []
    private var suspendedExpiryTasks: [UUID: Task<Void, Never>] = [:]

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
    var isBusy: Bool { activeSession != nil }

    /// Releases the in-memory ownership after a peer disconnect while retaining
    /// the durable open journal. A reconnect with the same session/fingerprint
    /// restores it; unrelated sessions are no longer blocked indefinitely.
    func suspendForDisconnect() {
        guard let session = activeSession else { return }
        // Finalization no longer needs peer bytes. Let it finish and persist its
        // replayable terminal ACK; the iPhone will request that ACK after reconnecting.
        guard session.journal.state != .finalizing else { return }
        session.journal.updatedAt = Date()
        try? persist(session)
        activeSession = nil
        admittedPartitions.removeAll()
        let sessionID = session.journal.session.sessionID
        suspendedExpiryTasks[sessionID]?.cancel()
        let remaining = max(
            (session.journal.expiresAt
                ?? session.journal.session.createdAt.addingTimeInterval(
                    ConnectedCorpusOutboundStore.retentionInterval
                )).timeIntervalSinceNow,
            0
        )
        suspendedExpiryTasks[sessionID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.activeSession?.journal.session.sessionID != sessionID else { return }
            try? self.fileManager.removeItem(at: self.sessionDirectory(sessionID: sessionID))
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
            guard try ConnectedCorpusRequestFingerprint.make(for: exportManifest) == open.session.requestFingerprint else {
                return rejected("Corpus request fingerprint does not match its immutable manifest.")
            }
        } catch {
            return rejected("Corpus session metadata is malformed.")
        }
        if let binding = open.session.peerBinding {
            guard open.session.protocolVersion >= 2,
                  binding.sourceInstallationID == remoteInstallationID,
                  binding.destinationInstallationID == localInstallationID else {
                return rejected("Durable corpus session belongs to a different app installation.")
            }
        }
        guard Date() < open.session.createdAt.addingTimeInterval(
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
        }

        do {
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
                try prepareRootAndSessionDirectories(sessionID: open.session.sessionID)
                let directory = sessionDirectory(sessionID: open.session.sessionID)
                session = Session(
                    directoryURL: directory,
                    journal: Journal(
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
                        expiresAt: open.session.createdAt.addingTimeInterval(
                            ConnectedCorpusOutboundStore.retentionInterval
                        ),
                        updatedAt: Date()
                    )
                )
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

            guard session.journal.state == .open || session.journal.state == .finalizing else {
                return rejected("Corpus session is already terminal.")
            }
            let committedCount = session.journal.committedPartitions.count
            if session.journal.state == .finalizing,
               open.partition.index >= committedCount {
                return rejected("Corpus finalization has already started; no new partitions are accepted.")
            }
            if open.partition.index < committedCount {
                let prior = session.journal.committedPartitions[open.partition.index]
                guard prior.sha256 == open.partition.sha256 else {
                    return rejected("A committed partition index was replayed with different content.")
                }
                admittedPartitions.remove(open.partition)
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
            journal: session.journal
        )
        var completedItems: [(ConnectedCorpusItemSegment, URL)] = []
        try ConnectedCorpusPartitionReader.applySegments(
            from: fileURL,
            parsed: parsed,
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
            }

            // The encrypted context commit is part of application-level
            // partition durability. The transport ACK is not emitted until both
            // context and the resumable corpus journal are durable.
            if !projectedContextDays.isEmpty, let queryContextStore {
                try await queryContextStore.upsert(projectedContextDays)
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
                        nextOffset: segment.itemOffset + segment.segmentBytes
                    ))
                }
            }
            session.journal.committedPartitions.append(descriptor)
            session.journal.totalPartitionBytes += descriptor.byteCount
            session.journal.updatedAt = Date()
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
        let wasAlreadyActive: Bool
        if let activeSession {
            session = activeSession
            wasAlreadyActive = true
        } else if let restored = try restoreSession(sessionID: finalize.sessionID) {
            session = restored
            wasAlreadyActive = false
        } else {
            throw ConnectedCorpusTransferModelError.mismatchedSession
        }
        guard session.journal.session.sessionID == finalize.sessionID,
              session.journal.session.jobID == finalize.jobID,
              session.journal.session.requestFingerprint == finalize.requestFingerprint else {
            throw ConnectedCorpusTransferModelError.mismatchedSession
        }
        if session.journal.state == .completed,
           let acknowledgement = session.journal.terminalAcknowledgement,
           acknowledgement.finalPartitionSHA256 == finalize.finalPartitionSHA256 {
            return .replay(
                acknowledgement: acknowledgement,
                fileResult: session.journal.terminalResult
            )
        }
        if session.journal.state == .finalizing && wasAlreadyActive {
            return .inProgress
        }
        guard session.journal.state == .open || session.journal.state == .finalizing else {
            throw ConnectedCorpusTransferModelError.invalidFinalization
        }
        activeSession = session
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
        session.journal.state = .finalizing
        session.journal.updatedAt = Date()
        try persist(session)

        switch journal.exportManifest.mode {
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
            let archiveWorkDirectoryURL = vaultManager.vaultURL.map {
                Self.archiveWorkDirectoryURL(vaultURL: $0, sessionID: journal.session.sessionID)
            }
            let successfulRequestedDates = Set(session.journal.successfulRequestedDates)
            let requestedDates = Set(journal.exportManifest.requestedDates)
            let derivedRecordItems = journal.recordItems.filter {
                !requestedDates.contains($0.sourceDate)
                    || successfulRequestedDates.contains($0.sourceDate)
            }
            let derived = try await vaultManager.finalizeCorpusDerivedOutputs(
                recordPayloadFiles: derivedRecordItems.map {
                    session.directoryURL.appendingPathComponent($0.relativePath)
                },
                recordSourceDates: derivedRecordItems.map(\.sourceDate),
                settings: derivedSettings,
                requestedDates: journal.exportManifest.requestedDates,
                startDate: journal.exportManifest.dateRangeStart,
                endDate: journal.exportManifest.dateRangeEnd,
                healthSubfolder: journal.exportManifest.settingsSnapshot.healthSubfolder,
                archiveWorkDirectoryURL: archiveWorkDirectoryURL,
                unavailableRollupDates: unavailableRollupDates,
                writeDataDictionary: session.journal.dataDictionaryWritten != true,
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

            let settings = journal.exportManifest.settingsSnapshot.makeAdvancedExportSettings()
            if settings.summaryOnlyModeEnabled && derived.rollupFileCount == 0 {
                session.journal.failedDateDetails.append(FailedDateDetail(
                    date: journal.exportManifest.requestedDates.first ?? journal.exportManifest.dateRangeStart,
                    reason: .noHealthData,
                    errorDetails: "No roll-up summary data was available for the selected period."
                ))
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
            try persist(session)
            cleanupPayloadFiles(session)
            activeSession = nil
            admittedPartitions.removeAll()
            return .files(result: result, acknowledgement: acknowledgement)

        case .strictRaw:
            let dateFormatter = Self.sourceDateFormatter
            let identifiersBySourceDate = Dictionary(uniqueKeysWithValues: session.journal.rawItems.map {
                ($0.sourceDate, $0.dateIdentifier ?? dateFormatter.string(from: $0.sourceDate))
            })
            let rawFilesByDate = Dictionary(uniqueKeysWithValues: session.journal.rawItems.map {
                ($0.dateIdentifier ?? dateFormatter.string(from: $0.sourceDate), session.directoryURL.appendingPathComponent($0.relativePath))
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
            let orderedFiles = try expectedDates.map { date -> URL in
                guard let url = rawFilesByDate[date] else {
                    throw ConnectedCorpusTransferModelError.invalidFinalization
                }
                return url
            }
            let spool = try await CanonicalRawResultSpoolWriter.write(
                createdAt: journal.exportManifest.createdAt,
                sourceDeviceName: journal.exportManifest.sourceDeviceName,
                expectedDates: expectedDates,
                dayFiles: orderedFiles,
                progress: { processed, total in
                    let date = processed > 0 && processed <= journal.exportManifest.requestedDates.count
                        ? journal.exportManifest.requestedDates[processed - 1]
                        : nil
                    progress?(processed, total, date)
                },
                cancellationCheck: {
                    self.activeSession !== session || session.journal.state == .cancelled
                }
            )
            try ensureFinalizationIsActive(session)
            session.journal.state = .completed
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
            try persist(session)
            cleanupPayloadFiles(session)
            activeSession = nil
            admittedPartitions.removeAll()
            return .strictRaw(spool: spool, acknowledgement: acknowledgement)
        }
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
        session.journal.state = .cancelled
        session.journal.updatedAt = Date()
        try? persist(session)
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
            session.journal.exportManifest.mode == .writeFiles ? result : nil
        )
    }

    private func validateItemContinuity(
        segments: [ConnectedCorpusItemSegment],
        journal: Journal
    ) throws {
        let completed = Set(journal.completedItemIDs)
        for segment in segments {
            if let partial = journal.partialItems.first(where: { $0.itemID == segment.itemID }) {
                guard partial.kind == segment.kind,
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
        let payload = try JSONDecoder().decode(
            ConnectedCorpusHealthDayPayload.self,
            from: Data(contentsOf: itemURL, options: [.mappedIfSafe])
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
        if queryContextStore == nil {
            contextDay = nil
        } else if let record = payload.record {
            contextDay = try HealthMdQueryContextProjector.project(
                record,
                externalProviderRecords: payload.externalDailyRecords,
                options: HealthMdContextProjectionOptions(
                    enabledMetricIDs: session.journal.exportManifest.settingsSnapshot.metricSelection.enabledMetricIDs
                )
            )
        } else {
            contextDay = try unavailableContextDay(
                payload: payload,
                segment: segment,
                calendar: sourceCalendar,
                enabledMetricIDs: session.journal.exportManifest.settingsSnapshot.metricSelection.enabledMetricIDs
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
            let storedURL = session.directoryURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: storedURL.path) { try fileManager.removeItem(at: storedURL) }
            try fileManager.moveItem(at: itemURL, to: storedURL)
            session.journal.recordItems.append(StoredItem(sourceDate: payload.sourceDate, relativePath: relativePath))

            if payload.isRequestedDate {
                let settings = session.journal.exportManifest.settingsSnapshot.makeAdvancedExportSettings()
                settings.exportTimeZoneOverride = session.journal.exportManifest.sourceTimeZoneIdentifier
                    .flatMap(TimeZone.init(identifier:))
                if settings.summaryOnlyModeEnabled {
                    session.journal.successfulRequestedDates.append(payload.sourceDate)
                } else {
                    do {
                        // Archive mode intentionally writes no loose daily aggregate, but this
                        // call still performs configured standard-mode side effects.
                        let writeResult = try await vaultManager.exportHealthData(
                            record,
                            settings: settings,
                            healthSubfolder: session.journal.exportManifest.settingsSnapshot.healthSubfolder,
                            writeDataDictionary: session.journal.dataDictionaryWritten != true
                        )
                        if !settings.archiveModeEnabled && !settings.dailyNotesOnlyModeEnabled {
                            session.journal.dataDictionaryWritten = true
                        }
                        session.journal.dailyNoteUpdateCount =
                            (session.journal.dailyNoteUpdateCount ?? 0) + writeResult.dailyNoteUpdatedCount
                        session.journal.dailyNoteSkipCount =
                            (session.journal.dailyNoteSkipCount ?? 0) + writeResult.dailyNoteSkippedCount

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
            try? fileManager.removeItem(at: itemURL)
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

    private func unavailableContextDay(
        payload: ConnectedCorpusHealthDayPayload,
        segment: ConnectedCorpusItemSegment,
        calendar: Calendar,
        enabledMetricIDs: Set<String>
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
        let metrics = enabledMetricIDs.sorted().map { metricID in
            HealthMdContextMetric(
                observationID: "\(ownerDate):\(metricID)",
                metricID: metricID,
                displayName: definitions[metricID]?.name ?? metricID,
                value: nil,
                status: .failed,
                limitations: [limitation]
            )
        }
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
        let payload = try JSONDecoder().decode(
            ConnectedCorpusRawDayPayload.self,
            from: Data(contentsOf: itemURL, options: [.mappedIfSafe])
        )
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
        let storedURL = session.directoryURL.appendingPathComponent(relativePath)
        try JSONEncoder().encode(payload.day).write(to: storedURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storedURL.path)
        try? fileManager.removeItem(at: itemURL)
        session.journal.rawItems.append(StoredItem(
            sourceDate: payload.sourceDate,
            relativePath: relativePath,
            dateIdentifier: payload.day.date
        ))
        session.journal.processedDates.append(payload.sourceDate)
    }

    private func makeFileResult(
        session: Session,
        forcedStatus: MacExportResultStatus? = nil
    ) -> MacExportResultPayload {
        let requestedDates = session.journal.exportManifest.requestedDates
        let settings = session.journal.exportManifest.settingsSnapshot.makeAdvancedExportSettings()
        let successfulDates = Set(session.journal.successfulRequestedDates)
        let durableDates = Set(session.journal.completedDates)
        let successCount = requestedDates.filter {
            successfulDates.contains($0)
                && (!settings.archiveModeEnabled && !settings.summaryOnlyModeEnabled || durableDates.contains($0))
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
            completedDates: Array(Set(session.journal.completedDates)).sorted(),
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
    }

    private func prepareRootAndSessionDirectories(sessionID: UUID) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let directory = sessionDirectory(sessionID: sessionID)
        for url in [
            directory,
            directory.appendingPathComponent("items", isDirectory: true),
            directory.appendingPathComponent("records", isDirectory: true),
            directory.appendingPathComponent("raw", isDirectory: true)
        ] {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private func persist(_ session: Session) throws {
        session.journal.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(session.journal)
        let temporaryURL = session.directoryURL.appendingPathComponent(".journal-\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else { throw CocoaError(.fileWriteUnknown) }
        do {
            let handle = try FileHandle(forWritingTo: temporaryURL)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if fileManager.fileExists(atPath: session.journalURL.path) {
                _ = try fileManager.replaceItemAt(session.journalURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: session.journalURL)
            }
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: session.journalURL.path)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func restoreSession(sessionID: UUID) throws -> Session? {
        let directory = sessionDirectory(sessionID: sessionID)
        let journalURL = directory.appendingPathComponent("journal.json")
        guard fileManager.fileExists(atPath: journalURL.path) else { return nil }
        var journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard journal.version == 2 || journal.version == Journal.currentVersion else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        journal.version = Journal.currentVersion
        try validateRestoredJournal(journal, sessionID: sessionID)
        return Session(directoryURL: directory, journal: journal)
    }

    private func validateRestoredJournal(_ journal: Journal, sessionID: UUID) throws {
        try journal.exportManifest.validate()
        guard journal.version == Journal.currentVersion,
              journal.session.sessionID == sessionID,
              journal.session.requestFingerprint == (try ConnectedCorpusRequestFingerprint.make(
                for: journal.exportManifest
              )),
              (journal.expiresAt
                  ?? journal.session.createdAt.addingTimeInterval(
                      ConnectedCorpusOutboundStore.retentionInterval
                  )) > journal.session.createdAt,
              journal.totalPartitionBytes >= 0,
              journal.totalFilesWritten >= 0,
              journal.externalRecordFileCount >= 0 else {
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
                  processed.contains($0.sourceDate) && Self.isSafeStoredPath($0.relativePath, prefix: "records/")
              }),
              journal.rawItems.allSatisfy({
                  processed.contains($0.sourceDate) && Self.isSafeStoredPath($0.relativePath, prefix: "raw/")
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
        if journal.state == .completed, journal.terminalAcknowledgement == nil {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
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
        for url in [session.itemDirectoryURL, session.recordDirectoryURL, session.rawDirectoryURL] {
            try? fileManager.removeItem(at: url)
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
            let journalURL = directory.appendingPathComponent("journal.json")
            guard let data = try? Data(contentsOf: journalURL),
                  let journal = try? JSONDecoder().decode(Journal.self, from: data) else {
                try? fileManager.removeItem(at: directory)
                continue
            }
            let expiresAt = journal.expiresAt
                ?? journal.session.createdAt.addingTimeInterval(
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
                    date: $0
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
