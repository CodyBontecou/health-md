import Foundation
import os

// MARK: - Agent Data gateway export runner
//
// Mirrors the structure and discipline of `APIEndpointExportRunner` /
// `APIExportClient`, but uploads the export engine's existing artifact files
// instead of re-capturing HealthKit into a request envelope.
//
// The profile's export is materialized EXACTLY as a folder destination would:
// the standard `ExportOrchestrator.exportDates` engine runs unchanged over an
// ephemeral app-container staging root (the same
// `configureDirectTransportStagingRoot` staging pattern the direct CLI
// transfer uses), so the staged files are byte-identical with what a folder
// destination would write. Each ingest-eligible artifact file is then
// uploaded individually per Agent Data ingestion protocol v1 — the exact
// staged bytes, never re-encoded, re-rendered, or wrapped in an envelope.
//
// Eligible artifact families on Apple (the contract's four standalone kinds,
// of which Apple's folder engine produces two):
// - `health_data_daily`: the per-day `healthmd.health_data` JSON document.
// - `external_provider_daily`: the `healthmd.external_provider_daily` sidecar.
// `raw_snapshot`/`raw_changes` are Android raw families Apple never emits.
// Other generated outputs (markdown, CSV, rollups, archives, the data
// dictionary) have no Agent Data v1 upload kind; they are staged by the
// engine but never uploaded and never fabricated under a wrong kind — they
// are reported as ineligible in the run summary.
//
// A failed upload never loses the staged artifact (staging lives until the
// run completes) and never blocks the remaining artifacts: the run always
// finishes with a per-artifact outcome for every eligible file.

/// Health-free per-artifact outcome surfaced in export results and history.
struct AgentDataGatewayUploadSummary: Equatable {
    struct ArtifactOutcome: Equatable {
        /// Owner date of the artifact's partition (the exported day for daily
        /// kinds). Not health data.
        let ownerDate: String
        /// Health-free family label of the artifact.
        let kindLabel: String
        let result: AgentDataIngestUploadOutcome.Result

        static func healthDataDaily(ownerDate: String, result: AgentDataIngestUploadOutcome.Result) -> Self {
            Self(ownerDate: ownerDate, kindLabel: "Daily export", result: result)
        }

        static func providerSidecar(ownerDate: String, result: AgentDataIngestUploadOutcome.Result) -> Self {
            Self(ownerDate: ownerDate, kindLabel: "Provider sidecar", result: result)
        }

        var isAccepted: Bool {
            result == .accepted
        }

        /// Health-free failure description for failed-date surfaces.
        var failureDescription: String {
            switch result {
            case .accepted:
                return ""
            case .rejected(let code):
                switch code {
                case .truncated:
                    return "The Agent Data gateway reported a truncated upload for \(ownerDate)."
                case .checksumInvalid:
                    return "The Agent Data gateway reported a checksum mismatch for \(ownerDate)."
                case .manifestIncomplete:
                    return "The Agent Data gateway reported an incomplete upload manifest for \(ownerDate)."
                case .transient:
                    return "The Agent Data gateway asked Health.md to retry \(ownerDate) later."
                }
            case .uploadFailed(let description):
                return description
            }
        }
    }

    /// One outcome per eligible artifact, in upload order.
    let outcomes: [ArtifactOutcome]
    /// Engine outputs staged but not eligible for Agent Data upload
    /// (markdown, CSV, rollups, archives, data dictionary).
    let ineligibleStagedFileCount: Int

    init(outcomes: [ArtifactOutcome], ineligibleStagedFileCount: Int) {
        self.outcomes = outcomes
        self.ineligibleStagedFileCount = max(0, ineligibleStagedFileCount)
    }

    init() {
        self.init(outcomes: [], ineligibleStagedFileCount: 0)
    }

    var acceptedCount: Int {
        outcomes.filter(\.isAccepted).count
    }

    var rejectedCount: Int {
        outcomes.filter {
            if case .rejected = $0.result { return true }
            return false
        }.count
    }

    var uploadFailedCount: Int {
        outcomes.filter {
            if case .uploadFailed = $0.result { return true }
            return false
        }.count
    }

    var eligibleCount: Int { outcomes.count }

    /// True when every eligible artifact was accepted.
    var didUploadAllEligibleArtifacts: Bool {
        !outcomes.isEmpty && acceptedCount == outcomes.count
    }

    /// Health-free, single-line run summary for status surfaces and history.
    var localizedDescription: String {
        if outcomes.isEmpty {
            return "No Agent Data artifacts were eligible for upload"
        }
        var line = "Uploaded \(acceptedCount) of \(outcomes.count) artifact\(outcomes.count == 1 ? "" : "s") to the Agent Data gateway"
        if rejectedCount > 0 { line += "; \(rejectedCount) rejected" }
        if uploadFailedCount > 0 { line += "; \(uploadFailedCount) failed" }
        return line
    }
}

/// Combined destination outcome: the standard export result (day accounting
/// for history, quota, and retries) plus the per-artifact upload summary.
struct AgentDataGatewayExportResult {
    let export: ExportOrchestrator.ExportResult
    let uploads: AgentDataGatewayUploadSummary
}

@MainActor
struct AgentDataGatewayExportRunner {
    /// Materialization seam: runs the folder-destination export engine over
    /// the staging vault. Production uses `ExportOrchestrator.exportDates`
    /// unchanged; tests may substitute their own engine double.
    typealias Materializer = (
        _ dates: [Date],
        _ stagingVault: VaultManager,
        _ settings: AdvancedExportSettings,
        _ onProgress: ((Int, Int, String) -> Void)?
    ) async throws -> ExportOrchestrator.ExportResult

    /// Upload seam over the real ingest client so tests can drive outcome
    /// matrices without a network, while wire-truth tests exercise the real
    /// client against a loopback gateway.
    typealias Uploader = (
        _ manifest: AgentDataIngestManifest,
        _ artifactFileURL: URL,
        _ stagingDirectory: URL
    ) async -> AgentDataIngestUploadOutcome

    /// Health-free progress phases for status surfaces.
    enum ExportProgress: Equatable {
        case materializing(dateString: String, processed: Int, total: Int)
        case uploading(processed: Int, total: Int)
    }

    typealias ProgressHandler = (ExportProgress) -> Void

    /// One staged artifact matched to its ingest manifest inputs.
    private struct EligibleArtifact {
        enum Family {
            case healthDataDaily
            case providerSidecar
        }

        let url: URL
        let ownerDate: String
        let family: Family
    }

    static func export(
        dates: [Date],
        healthKitManager: HealthKitManager,
        settings: AdvancedExportSettings,
        destination: AgentDataGatewayDestinationSnapshot,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil,
        client: AgentDataIngestClient = AgentDataIngestClient(),
        materialize customMaterializer: Materializer? = nil,
        uploader customUploader: Uploader? = nil,
        onProgress: ProgressHandler? = nil
    ) async -> AgentDataGatewayExportResult {
        // Freeze the calendar before any capture or path planning, matching
        // the folder destination's foreground freeze.
        let calendarTimeZone = settings.exportTimeZoneOverride ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = calendarTimeZone
        let normalizedDates = HealthKitDailyCapture.normalizedDates(dates, calendar: calendar)

        guard !normalizedDates.isEmpty else {
            return AgentDataGatewayExportResult(
                export: ExportOrchestrator.ExportResult(
                    successCount: 0,
                    totalCount: 0,
                    failedDateDetails: [],
                    formatsPerDate: 0,
                    looseAggregateFileCount: 0,
                    isFileCategoryBreakdownComplete: true,
                    completedDates: []
                ),
                uploads: AgentDataGatewayUploadSummary()
            )
        }

        guard !settings.dailyNotesOnlyModeEnabled else {
            return failureResult(
                dates: normalizedDates,
                message: "Daily Notes Only requires a filesystem destination and cannot export to an Agent Data gateway."
            )
        }
        // The gateway ingests the export engine's JSON daily documents; the
        // JSON format must be part of the profile's output.
        guard settings.exportFormats.contains(.json) else {
            return failureResult(
                dates: normalizedDates,
                message: "Select the JSON format before exporting to an Agent Data gateway."
            )
        }

        let awakeActivityID = UUID()
        IdleTimerCoordinator.shared.beginActivity(awakeActivityID)
        defer { IdleTimerCoordinator.shared.endActivity(awakeActivityID) }

        externalIntegrations?.beginExportAction()
        var didEndExportAction = false
        func finishExportAction(succeeded: Bool) {
            guard !didEndExportAction else { return }
            didEndExportAction = true
            externalIntegrations?.endExportAction(succeeded: succeeded)
        }
        defer { finishExportAction(succeeded: false) }

        let runID = UUID().uuidString
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-agent-data-gateway-\(runID)", isDirectory: true)
        let generatedRoot = stagingRoot.appendingPathComponent("generated", isDirectory: true)
        let bodySpool = stagingRoot.appendingPathComponent("bodies", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return failureResult(
                dates: normalizedDates,
                message: "Health.md could not prepare the Agent Data gateway staging area."
            )
        }
        defer {
            // Staging is ephemeral producer storage; it outlives every upload
            // attempt and is removed only once the run completes.
            try? FileManager.default.removeItem(at: stagingRoot)
        }

        // Isolated staging vault over the same engine machinery a folder
        // destination uses (the direct CLI transfer's staging pattern).
        let suiteName = "HealthMd.AgentDataGateway.\(runID)"
        guard let stagingDefaults = UserDefaults(suiteName: suiteName) else {
            return failureResult(
                dates: normalizedDates,
                message: "Health.md could not prepare the Agent Data gateway staging area."
            )
        }
        stagingDefaults.removePersistentDomain(forName: suiteName)
        let stagingVault = makeStagingVaultManager(defaults: stagingDefaults)
        do {
            try stagingVault.configureDirectTransportStagingRoot(
                generatedRoot,
                healthSubfolder: "Health"
            )
        } catch {
            return failureResult(
                dates: normalizedDates,
                message: "Health.md could not prepare the Agent Data gateway staging area."
            )
        }

        let materializer: Materializer
        if let customMaterializer {
            materializer = customMaterializer
        } else {
            // The production materializer reuses the folder-destination
            // engine unchanged, including provider sidecar staging.
            let frozenExternalIntegrations = externalIntegrations
            materializer = { materializationDates, vault, materializationSettings, progress in
                await ExportOrchestrator.exportDates(
                    materializationDates,
                    healthKitManager: healthKitManager,
                    vaultManager: vault,
                    settings: materializationSettings,
                    externalIntegrations: frozenExternalIntegrations,
                    onProgress: progress
                )
            }
        }

        let uploader: Uploader
        if let customUploader {
            uploader = customUploader
        } else {
            uploader = { manifest, artifactURL, stagingDirectory in
                await client.upload(
                    manifest: manifest,
                    artifactFileURL: artifactURL,
                    destination: destination,
                    stagingDirectory: stagingDirectory
                )
            }
        }

        let materialization: ExportOrchestrator.ExportResult
        do {
            materialization = try await materializer(
                normalizedDates,
                stagingVault,
                settings,
                { processed, total, dateString in
                    onProgress?(.materializing(
                        dateString: dateString,
                        processed: processed,
                        total: total
                    ))
                }
            )
        } catch is CancellationError {
            return failureResult(
                dates: normalizedDates,
                message: "Agent Data gateway export cancelled."
            )
        } catch {
            return failureResult(
                dates: normalizedDates,
                message: "Health.md could not prepare the Agent Data gateway export."
            )
        }

        // Classify the staged tree: eligible ingest artifacts plus an honest
        // count of everything else the engine wrote.
        let eligibleArtifacts: [EligibleArtifact]
        let ineligibleCount: Int
        do {
            (eligibleArtifacts, ineligibleCount) = try classifyStagedArtifacts(
                root: generatedRoot,
                healthSubfolder: stagingVault.healthSubfolder,
                settings: settings,
                dates: normalizedDates,
                calendarTimeZone: calendarTimeZone
            )
        } catch {
            return AgentDataGatewayExportResult(
                export: ExportOrchestrator.ExportResult(
                    successCount: materialization.successCount,
                    totalCount: materialization.totalCount,
                    failedDateDetails: materialization.failedDateDetails,
                    partialFailures: materialization.partialFailures,
                    formatsPerDate: 1,
                    looseAggregateFileCount: 0,
                    isFileCategoryBreakdownComplete: true,
                    wasCancelled: materialization.wasCancelled,
                    completedDates: materialization.completedDates
                ),
                uploads: AgentDataGatewayUploadSummary()
            )
        }

        // Upload every eligible artifact individually. A failed upload is
        // recorded and never blocks the remaining artifacts.
        var outcomes: [AgentDataGatewayUploadSummary.ArtifactOutcome] = []
        outcomes.reserveCapacity(eligibleArtifacts.count)
        var wasCancelled = materialization.wasCancelled
        for (index, artifact) in eligibleArtifacts.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            onProgress?(.uploading(processed: index, total: eligibleArtifacts.count))
            let manifest: AgentDataIngestManifest
            do {
                manifest = try ingestManifest(for: artifact)
            } catch {
                outcomes.append(outcome(
                    for: artifact,
                    result: .uploadFailed(
                        description: "Health.md could not describe the staged artifact for upload."
                    )
                ))
                continue
            }
            let uploadOutcome = await uploader(manifest, artifact.url, bodySpool)
            outcomes.append(outcome(for: artifact, result: uploadOutcome.result))
        }
        if !eligibleArtifacts.isEmpty {
            onProgress?(.uploading(
                processed: eligibleArtifacts.count,
                total: eligibleArtifacts.count
            ))
        }

        finishExportAction(succeeded: !wasCancelled && outcomes.allSatisfy(\.isAccepted))

        let summary = AgentDataGatewayUploadSummary(
            outcomes: outcomes,
            ineligibleStagedFileCount: ineligibleCount
        )
        return AgentDataGatewayExportResult(
            export: combinedResult(
                materialization: materialization,
                outcomes: outcomes,
                normalizedDates: normalizedDates,
                calendarTimeZone: calendarTimeZone
            ),
            uploads: summary
        )
    }

    // MARK: - Classification

    /// Deterministically maps staged files to ingest artifact families using
    /// the engine's own path truth:
    /// - the expected per-day JSON path (computed exactly as the writer
    ///   computes it via `ExportPathPlanner`) → `health_data_daily`;
    /// - `<ownerDate>.json` inside the `integrations` sidecar subtree →
    ///   `external_provider_daily`;
    /// - everything else → ineligible (counted, never uploaded).
    private static func classifyStagedArtifacts(
        root: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        dates: [Date],
        calendarTimeZone: TimeZone
    ) throws -> (eligible: [EligibleArtifact], ineligible: Int) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], 0)
        }

        // The writer's exact per-day JSON destination, keyed by path.
        var expectedDailyPathsByOwnerDate: [String: String] = [:]
        for date in dates {
            let url = ExportPathPlanner.aggregateFileURL(
                vaultURL: root,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: date,
                format: .json
            )
            expectedDailyPathsByOwnerDate[url.standardizedFileURL.path] =
                APIExportClient.dayString(from: date, timeZone: calendarTimeZone)
        }

        let requestedOwnerDates = Set(expectedDailyPathsByOwnerDate.values)
        let integrationsPrefix = ExportPathPlanner.healthSubfolderURL(
            vaultURL: root,
            healthSubfolder: healthSubfolder
        )
        .appendingPathComponent("integrations", isDirectory: true)
        .standardizedFileURL
        .path + "/"

        var eligible: [EligibleArtifact] = []
        var ineligible = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let path = url.standardizedFileURL.path
            if let ownerDate = expectedDailyPathsByOwnerDate[path] {
                eligible.append(EligibleArtifact(
                    url: url,
                    ownerDate: ownerDate,
                    family: .healthDataDaily
                ))
                continue
            }
            if path.hasPrefix(integrationsPrefix),
               let ownerDate = ownerDateFromSidecarFilename(url.lastPathComponent),
               requestedOwnerDates.contains(ownerDate) {
                eligible.append(EligibleArtifact(
                    url: url,
                    ownerDate: ownerDate,
                    family: .providerSidecar
                ))
                continue
            }
            ineligible += 1
        }
        eligible.sort { $0.url.path < $1.url.path }
        return (eligible, ineligible)
    }

    /// Sidecar files are written by the engine as `<ownerDate>.json`.
    private static func ownerDateFromSidecarFilename(_ filename: String) -> String? {
        guard filename.hasSuffix(".json") else { return nil }
        let stem = String(filename.dropLast(".json".count))
        return AgentDataIngestManifest.isISODate(stem) ? stem : nil
    }

    // MARK: - Manifest

    /// Builds the v1 manifest over the EXACT staged bytes. `byte_count` and
    /// `sha256` are streamed from the file, so the manifest always describes
    /// the bytes that will be sent. Apple daily artifacts are complete,
    /// finalized snapshots of their exported day; the phone never emits an
    /// unfinalized partial on this surface.
    private static func ingestManifest(for artifact: EligibleArtifact) throws -> AgentDataIngestManifest {
        switch artifact.family {
        case .healthDataDaily:
            return try AgentDataIngestManifestBuilder.manifest(
                kind: .healthDataDaily,
                platform: "apple",
                artifactSchema: HealthMdExportSchema.identifier,
                artifactSchemaVersion: HealthMdExportSchema.version,
                ownerDate: artifact.ownerDate,
                physicalFormat: .json,
                mediaType: "application/json",
                artifactFileURL: artifact.url,
                completeness: .complete
            )
        case .providerSidecar:
            return try AgentDataIngestManifestBuilder.manifest(
                kind: .externalProviderDaily,
                platform: "apple",
                artifactSchema: ExternalDailyRecord.schema,
                artifactSchemaVersion: ExternalDailyRecord.schemaVersion,
                ownerDate: artifact.ownerDate,
                physicalFormat: .json,
                mediaType: "application/json",
                artifactFileURL: artifact.url,
                completeness: .complete
            )
        }
    }

    // MARK: - Result composition

    /// Day accounting for the gateway destination: a materialized day counts
    /// as exported only when every eligible artifact for that day was
    /// accepted (a day with no eligible artifact, e.g. a no-data day,
    /// completes exactly like a folder destination's no-data day). Upload
    /// failures surface as health-free failed-date details so residual
    /// scheduled retries keep the day retryable.
    private static func combinedResult(
        materialization: ExportOrchestrator.ExportResult,
        outcomes: [AgentDataGatewayUploadSummary.ArtifactOutcome],
        normalizedDates: [Date],
        calendarTimeZone: TimeZone
    ) -> ExportOrchestrator.ExportResult {
        var failureDescriptionByOwnerDate: [String: String] = [:]
        for outcome in outcomes where !outcome.isAccepted {
            // First failure per day wins; the full per-artifact detail stays
            // in the upload summary.
            if failureDescriptionByOwnerDate[outcome.ownerDate] == nil {
                failureDescriptionByOwnerDate[outcome.ownerDate] = outcome.failureDescription
            }
        }

        let completedDates = (materialization.completedDates ?? []).filter { date in
            let ownerDate = APIExportClient.dayString(from: date, timeZone: calendarTimeZone)
            return failureDescriptionByOwnerDate[ownerDate] == nil
        }
        let materializedOwnerDates = Set((materialization.completedDates ?? []).map {
            APIExportClient.dayString(from: $0, timeZone: calendarTimeZone)
        })
        var failedDateDetails = materialization.failedDateDetails
        for (ownerDate, description) in failureDescriptionByOwnerDate.sorted(by: { $0.key < $1.key }) {
            guard materializedOwnerDates.contains(ownerDate),
                  let date = normalizedDates.first(where: {
                      APIExportClient.dayString(from: $0, timeZone: calendarTimeZone) == ownerDate
                  }) else { continue }
            failedDateDetails.append(FailedDateDetail(
                date: date,
                reason: .unknown,
                errorDetails: description
            ))
        }

        let acceptedCount = outcomes.filter(\.isAccepted).count
        return ExportOrchestrator.ExportResult(
            successCount: completedDates.count,
            totalCount: materialization.totalCount,
            failedDateDetails: failedDateDetails,
            partialFailures: materialization.partialFailures,
            formatsPerDate: 1,
            looseAggregateFileCount: acceptedCount,
            isFileCategoryBreakdownComplete: true,
            completedDates: completedDates
        )
    }

    private static func outcome(
        for artifact: EligibleArtifact,
        result: AgentDataIngestUploadOutcome.Result
    ) -> AgentDataGatewayUploadSummary.ArtifactOutcome {
        switch artifact.family {
        case .healthDataDaily:
            return .healthDataDaily(ownerDate: artifact.ownerDate, result: result)
        case .providerSidecar:
            return .providerSidecar(ownerDate: artifact.ownerDate, result: result)
        }
    }

    private static func failureResult(
        dates: [Date],
        message: String
    ) -> AgentDataGatewayExportResult {
        AgentDataGatewayExportResult(
            export: ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map {
                    FailedDateDetail(date: $0, reason: .unknown, errorDetails: message)
                },
                formatsPerDate: 0,
                looseAggregateFileCount: 0,
                isFileCategoryBreakdownComplete: true,
                completedDates: []
            ),
            uploads: AgentDataGatewayUploadSummary()
        )
    }

    /// Isolated staging `VaultManager` over a per-run UserDefaults suite with
    /// passthrough coordination, mirroring the direct CLI transfer's staging
    /// construction.
    private static func makeStagingVaultManager(defaults: UserDefaults) -> VaultManager {
        VaultManager(
            defaults: SystemUserDefaults(defaults: defaults),
            fileCoordinator: PassthroughFileCoordinator(),
            bookmarkResolver: AgentDataGatewayStagingBookmarkResolver()
        )
    }
}

/// Passthrough resolver for the ephemeral staging root; mirrors the direct
/// CLI transfer's `DirectStagingBookmarkResolver`.
private final class AgentDataGatewayStagingBookmarkResolver: BookmarkResolving {
    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (URL(fileURLWithPath: path), false)
    }

    func createBookmarkData(for url: URL) throws -> Data { Data(url.path.utf8) }
    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}
