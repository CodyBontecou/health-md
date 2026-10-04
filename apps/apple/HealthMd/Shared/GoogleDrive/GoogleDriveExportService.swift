import Foundation

/// Adapts every shipped Apple renderer and companion writer through an isolated app-container
/// folder. The folder is only a destination-neutral byte materializer: Drive receives the exact
/// resulting files, while append/update/Daily Note intent is retained for remote final-byte merge.
@MainActor
final class GoogleDriveArtifactBundleProducer {
    nonisolated deinit {}

    func produce(
        operationID: UUID,
        profileID: UUID?,
        dates: [Date],
        healthKitManager: HealthKitManager,
        settingsSnapshot: ExportSettingsSnapshot,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async throws -> (GoogleDriveGeneratedArtifactBundle, ExportOrchestrator.ExportResult) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-drive-materialize-\(operationID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try? (root as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)

        let vault = VaultManager()
        try vault.configureDirectTransportStagingRoot(
            root,
            healthSubfolder: settingsSnapshot.healthSubfolder ?? VaultManager.defaultHealthSubfolder
        )
        let settings = settingsSnapshot.makeAdvancedExportSettings()

        // Existing Daily Note behavior requires a file when createIfMissing is false. Empty
        // placeholders let the authoritative injector render its exact fragment without changing
        // remote missing-file semantics; unchanged placeholders are excluded below.
        var dailyNotePaths: [String: Bool] = [:]
        if settings.dailyNoteInjection.enabled {
            for date in dates {
                let path = ExportPathPlanner.dailyNoteRelativePath(
                    settings: settings.dailyNoteInjection,
                    date: date
                )
                dailyNotePaths[path] = settings.dailyNoteInjection.createIfMissing
                if !settings.dailyNoteInjection.createIfMissing {
                    let url = ExportPathPlanner.appendingRelativePath(path, to: root, isDirectory: false)
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                    FileManager.default.createFile(atPath: url.path, contents: Data())
                }
            }
        }

        let result = await ExportOrchestrator.exportDates(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vault,
            settings: settings,
            externalIntegrations: externalIntegrations,
            onProgress: onProgress
        )

        let aggregatePaths = Set(dates.flatMap { date in
            settings.exportFormats.map {
                ExportPathPlanner.aggregateRelativePath(
                    healthSubfolder: settingsSnapshot.healthSubfolder ?? VaultManager.defaultHealthSubfolder,
                    settings: settings,
                    date: date,
                    format: $0
                )
            }
        })
        let urls = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .map { (path: $0, url: root.appendingPathComponent($0)) }
            .filter { pair in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: pair.url.path, isDirectory: &isDirectory)
                    && !isDirectory.boolValue
            }
            .sorted { $0.path < $1.path }

        var artifacts: [GoogleDriveGeneratedArtifact] = []
        for pair in urls {
            let relativePath = pair.path.replacingOccurrences(of: "\\", with: "/")
            let data = try Data(contentsOf: pair.url, options: [.mappedIfSafe])
            if dailyNotePaths[relativePath] != nil && data.isEmpty { continue }
            let intent: GoogleDriveArtifactWriteIntent
            let createIfMissing: Bool
            if let dailyCreate = dailyNotePaths[relativePath] {
                intent = .dailyNoteMerge
                createIfMissing = dailyCreate
            } else if aggregatePaths.contains(relativePath) {
                createIfMissing = true
                switch settings.writeMode {
                case .overwrite: intent = .overwrite
                case .append: intent = .append
                case .update:
                    intent = pair.url.pathExtension.lowercased() == "md" ? .markdownUpdate : .overwrite
                }
            } else {
                intent = .overwrite
                createIfMissing = true
            }
            let digest = GoogleDriveDigest.sha256(data)
            artifacts.append(try GoogleDriveGeneratedArtifact(
                id: digest,
                relativePath: relativePath,
                mediaType: Self.mediaType(for: pair.url),
                writeIntent: intent,
                createIfMissing: createIfMissing,
                fragmentBytes: data
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let settingsData = try encoder.encode(settingsSnapshot)
        let settingsDigest = GoogleDriveDigest.sha256(settingsData)
        let rendererIdentity = settingsSnapshot.appleExportEnginePin.map {
            "\($0.profile)/artifact_plan_\($0.artifactPlanVersion)/\($0.coreSourceRevision)"
        } ?? "apple_health_data_v8/native"
        let bundle = try GoogleDriveGeneratedArtifactBundle(
            operationID: operationID,
            profileID: profileID,
            sourceDates: dates,
            settingsDigest: settingsDigest,
            rendererIdentity: rendererIdentity,
            artifacts: artifacts,
            captureEvidence: GoogleDriveCaptureEvidence.recording(dates: dates, result: result),
            settingsSnapshotData: settingsData
        )
        return (bundle, result)
    }

    private static func mediaType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": "text/markdown"
        case "json": "application/json"
        case "csv": "text/csv"
        case "zip": "application/zip"
        default: "application/octet-stream"
        }
    }
}

nonisolated struct GoogleDriveRecoveredOperation: Sendable {
    let operationID: UUID
    let profileID: UUID?
    let sourceDates: [Date]
    let destinationID: UUID
    let result: ExportOrchestrator.ExportResult
}

@MainActor
final class GoogleDriveExportService {
    nonisolated deinit {}
    static let shared: GoogleDriveExportService? = try? GoogleDriveExportService()

    private let destinationStore: GoogleDriveDestinationStore
    private let connectionManager: GoogleDriveConnectionManager
    private let runner: GoogleDriveDestinationRunner
    private let producer: GoogleDriveArtifactBundleProducer

    init(
        destinationStore: GoogleDriveDestinationStore? = nil,
        connectionManager: GoogleDriveConnectionManager? = nil,
        runner: GoogleDriveDestinationRunner? = nil,
        producer: GoogleDriveArtifactBundleProducer? = nil
    ) throws {
        let destinationStore = destinationStore ?? GoogleDriveDestinationStore()
        self.destinationStore = destinationStore
        self.connectionManager = connectionManager ?? GoogleDriveConnectionManager(destinationStore: destinationStore)
        self.runner = try runner ?? GoogleDriveDestinationRunner()
        self.producer = producer ?? GoogleDriveArtifactBundleProducer()
    }

    func readiness(destinationID: UUID?) -> GoogleDriveReadiness {
        destinationStore.reload()
        guard GoogleDriveConfiguration.from() != nil else { return .configurationMissing }
        guard let destination = destinationStore.destination(id: destinationID) else {
            return .destinationMissing
        }
        connectionManager.refreshReadiness(destinationID: destination.id)
        return connectionManager.readiness
    }

    /// Resumes exact protected bytes without recapturing HealthKit or rerendering. The caller owns
    /// durable history/quota recording and must acknowledge only after those side effects succeed.
    func resumeRecoverableOperation(_ operationID: UUID) async -> GoogleDriveRecoveredOperation? {
        do {
            let journal = try await runner.recoveryJournal(operationID: operationID)
            guard let evidence = journal.captureEvidence, evidence.isValid else {
                throw GoogleDriveError(.remoteConflict)
            }
            destinationStore.reload()
            guard let destination = destinationStore.destination(
                id: journal.destinationSnapshot.destinationID
            ), destination.fingerprint == journal.destinationSnapshot.fingerprint else {
                throw GoogleDriveError(.folderUnavailable)
            }
            let token = try await connectionManager.accessToken(destination: destination)
            let driveResult = await runner.resume(
                operationID: operationID,
                destination: destination,
                accessToken: token
            )
            return GoogleDriveRecoveredOperation(
                operationID: operationID,
                profileID: journal.profileID,
                sourceDates: journal.sourceDates,
                destinationID: destination.id,
                result: Self.resumedResult(driveResult, dates: journal.sourceDates, evidence: evidence)
            )
        } catch {
            return nil
        }
    }

    /// Called only after the owning manual/scheduled path durably records its terminal history.
    /// Until then the verified journal remains recoverable and cannot be retention-pruned.
    func acknowledgeCompletedOperation(_ operationID: UUID) async {
        var visited: Set<UUID> = []
        await acknowledge(operationID, visited: &visited)
    }

    private func acknowledge(_ operationID: UUID, visited: inout Set<UUID>) async {
        guard visited.insert(operationID).inserted,
              let journal = try? await runner.recoveryJournal(operationID: operationID),
              journal.captureEvidence?.isValid == true else { return }
        try? await runner.acknowledge(operationID: operationID)
        for residualID in journal.residualOperationIDs {
            await acknowledge(residualID, visited: &visited)
        }
    }

    func export(
        operationID: UUID = UUID(),
        profileID: UUID?,
        destinationSnapshot: GoogleDriveDestinationSnapshot,
        dates: [Date],
        healthKitManager: HealthKitManager,
        settingsSnapshot: ExportSettingsSnapshot,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportOrchestrator.ExportResult {
        // Profile/coordinator UI and this application service can own distinct store objects over
        // the same app-scoped persistence. Reload at the authority boundary before every run.
        destinationStore.reload()
        guard let destination = destinationStore.destination(id: destinationSnapshot.destinationID),
              destination.fingerprint == destinationSnapshot.fingerprint else {
            return Self.failure(dates: dates, error: GoogleDriveError(.folderUnavailable))
        }
        do {
            let token = try await connectionManager.accessToken(destination: destination)

            // A durable request keeps its operation ID across app launches. Resume its already
            // staged final bytes before asking HealthKit or the renderer for mutable source data.
            // A corrupt existing journal fails closed in `resume`; it is never overwritten by a
            // newly rendered bundle.
            if try await runner.hasRecoverableJournal(operationID: operationID) {
                let journal = try await runner.recoveryJournal(operationID: operationID)
                let normalized = Array(Set(dates)).sorted()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                guard let evidence = journal.captureEvidence, evidence.isValid,
                      journal.profileID == profileID,
                      journal.settingsDigest == GoogleDriveDigest.sha256(try encoder.encode(settingsSnapshot)),
                      Set(normalized).isSubset(of: Set(evidence.requestedDates)) else {
                    throw GoogleDriveError(.remoteConflict)
                }
                let resumed = await runner.resume(
                    operationID: operationID,
                    destination: destination,
                    accessToken: token
                )
                if resumed.isComplete, !normalized.isEmpty,
                   normalized.allSatisfy({ date in
                       !evidence.completedDates.contains(date) && evidence.failures.contains { $0.date == date }
                   }) {
                    // The stable scheduled request UUID is not an upload identity for failed
                    // capture. Journal the deterministic child handle before generating new bytes.
                    let residualID = Self.residualOperationID(parentID: operationID, dates: normalized)
                    try await runner.registerResidualOperation(parentID: operationID, residualID: residualID)
                    return await export(operationID: residualID, profileID: profileID,
                        destinationSnapshot: destinationSnapshot, dates: normalized,
                        healthKitManager: healthKitManager, settingsSnapshot: settingsSnapshot,
                        externalIntegrations: externalIntegrations, onProgress: onProgress)
                }
                return Self.resumedResult(resumed, dates: normalized, evidence: evidence)
            }

            let (bundle, generationResult) = try await producer.produce(
                operationID: operationID,
                profileID: profileID,
                dates: dates,
                healthKitManager: healthKitManager,
                settingsSnapshot: settingsSnapshot,
                externalIntegrations: externalIntegrations,
                onProgress: onProgress
            )
            guard generationResult.successCount > 0 || !bundle.artifacts.isEmpty else {
                return generationResult
            }
            let driveResult = await runner.run(
                bundle: bundle,
                destination: destination,
                accessToken: token
            )
            guard let evidence = bundle.captureEvidence, evidence.isValid else {
                return Self.failure(dates: dates, error: GoogleDriveError(.remoteConflict))
            }
            return Self.resumedResult(driveResult, dates: dates, evidence: evidence)
        } catch let error as GoogleDriveError {
            return Self.failure(dates: dates, error: error)
        } catch is CancellationError {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: [],
                wasCancelled: true,
                completedDates: []
            )
        } catch {
            return Self.failure(dates: dates, error: GoogleDriveError(.ambiguousCommit))
        }
    }

    private static func resumedResult(
        _ driveResult: GoogleDriveRunResult,
        dates: [Date],
        evidence: GoogleDriveCaptureEvidence
    ) -> ExportOrchestrator.ExportResult {
        let normalized = Array(Set(dates)).sorted()
        guard evidence.isValid, Set(normalized).isSubset(of: Set(evidence.requestedDates)) else {
            return failure(dates: normalized, error: GoogleDriveError(.remoteConflict))
        }
        let captureFailures = evidence.failures.filter { normalized.contains($0.date) }.map {
            FailedDateDetail(date: $0.date, reason: ExportFailureReason(rawValue: $0.reason) ?? .unknown)
        }
        let complete = driveResult.isComplete
        let uploadFailures = complete ? [] : normalized.filter { date in
            !captureFailures.contains { $0.date == date }
        }.map {
            FailedDateDetail(date: $0, reason: .fileWriteError,
                errorDetails: (driveResult.errorID ?? .ambiguousCommit).rawValue)
        }
        return ExportOrchestrator.ExportResult(
            // A verified artifact prefix is not proof that any entire owner date exported.
            successCount: complete ? evidence.exportedDates.filter { normalized.contains($0) }.count : 0,
            totalCount: normalized.count,
            failedDateDetails: captureFailures + uploadFailures,
            partialFailures: evidence.partialFailures.filter { normalized.contains($0.date) },
            looseAggregateFileCount: driveResult.verifiedArtifactCount,
            authoritativeFileCount: driveResult.verifiedArtifactCount,
            isFileCategoryBreakdownComplete: false,
            dailyNoteUpdateCount: complete ? evidence.dailyNoteUpdateCount : 0,
            dailyNoteSkipCount: evidence.dailyNoteSkipCount + driveResult.skippedArtifactCount,
            wasCancelled: evidence.wasCancelled,
            hadTerminalRangeFailure: evidence.hadTerminalRangeFailure,
            completedDates: complete ? evidence.completedDates.filter { normalized.contains($0) } : []
        )
    }

    private static func residualOperationID(parentID: UUID, dates: [Date]) -> UUID {
        let digest = GoogleDriveDigest.framedSHA256(
            ["healthmd.drive.capture-residual.v1", parentID.uuidString.lowercased()]
                + dates.map { String($0.timeIntervalSinceReferenceDate.bitPattern) }
        )
        let hex = String(digest.prefix(32))
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))")!
    }

    private static func failure(
        dates: [Date],
        error: GoogleDriveError
    ) -> ExportOrchestrator.ExportResult {
        ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: dates.count,
            failedDateDetails: dates.map {
                FailedDateDetail(
                    date: $0,
                    reason: .fileWriteError,
                    errorDetails: error.id.rawValue
                )
            },
            completedDates: []
        )
    }
}
