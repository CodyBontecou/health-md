import CoreFoundation
import CryptoKit
import Darwin
import Foundation
@testable import HealthMd

#if os(macOS)
/// Generates deterministic, synthetic documentation for app-owned automation contracts.
/// Every contract model is encoded with its production Codable or public serialization path.
@MainActor
enum GeneratedAutomationReferenceDocumentation {
    static let relativeGeneratedDirectory = "docs/reference/generated/automation"
    static let updateOutputDirectoryName = "healthmd-generated-automation-reference-docs-current"

    static let requiredArtifactNames: Set<String> = [
        "api-export-v1.json",
        "api-export-v2-provider-sidecar.json",
        "agent-query-request.json",
        "agent-query-response.json",
        "agent-evidence-response.json",
        "control-status.json",
        "control-write-files-request.json",
        "control-strict-raw-request.json",
        "raw-result-complete.json",
        "raw-result-partial.json",
        "peer-capabilities.json",
        "iphone-export-request-write-files.json",
        "iphone-export-request-strict-raw.json",
        "iphone-export-progress.json",
        "transfer-offer.json",
        "transfer-chunk.json",
        "transfer-acknowledgement.json",
        "transfer-complete.json",
        "transfer-rejection.json",
        "mac-export-job.json",
        "mac-export-result-success.json",
        "mac-export-result-partial.json",
        "message-fields.md",
        "manifest.json"
    ]

    static let documentedControlResponseStatuses: Set<String> = [
        "success", "partial_success", "failure", "cancelled", "unavailable", "timed_out"
    ]

    private static let dayStart = Date(timeIntervalSince1970: 1_773_532_800)
    private static let dayEnd = Date(timeIntervalSince1970: 1_773_619_200)
    private static let createdAt = Date(timeIntervalSince1970: 1_773_578_096)
    private static let jobID = UUID(uuidString: "A1700000-0000-4000-8000-000000000001")!
    private static let secondJobID = UUID(uuidString: "A1700000-0000-4000-8000-000000000002")!
    private static let installationID = UUID(uuidString: "A1700000-0000-4000-8000-000000000003")!
    private static let transferBytes = Data("Health.md connected transfer documentation fixture.".utf8)

    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation
    // state that is unsafe to tear down during some macOS XCTest process exits.
    private static let retainedSettings: AdvancedExportSettings = {
        let suiteName = "GeneratedAutomationReferenceDocumentation"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json]
        settings.includeGranularData = true
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.summaryOnlyExport = false
        settings.formatCustomization.unitPreference = .metric
        return settings
    }()

    static func files() throws -> [String: Data] {
        let previousTimeZone = NSTimeZone.default
        let previousTZEnvironment = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", "UTC", 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        defer {
            NSTimeZone.default = previousTimeZone
            if let previousTZEnvironment {
                setenv("TZ", previousTZEnvironment, 1)
            } else {
                unsetenv("TZ")
            }
            tzset()
            NSTimeZone.resetSystemTimeZone()
        }

        let completeRecord = completeHealthData()
        let partialRecord = partialHealthData()
        let sidecar = providerSidecar()
        let snapshot = settingsSnapshot()
        let completeRawResult = try CanonicalRawResultEnvelope(
            createdAt: createdAt,
            sourceDeviceName: "Synthetic iPhone",
            requestedDates: ["2026-03-15"],
            days: [CanonicalRawDayResult.captured(
                completeRecord,
                customization: retainedSettings.formatCustomization
            )]
        )
        let partialRawResult = try CanonicalRawResultEnvelope(
            createdAt: createdAt,
            sourceDeviceName: "Synthetic iPhone",
            requestedDates: ["2026-03-15", "2026-03-16"],
            days: [CanonicalRawDayResult.captured(
                partialRecord,
                customization: retainedSettings.formatCustomization
            )]
        )

        let writeFilesRequest = IPhoneExportRequest(
            jobID: jobID,
            createdAt: createdAt,
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly,
            responseMode: .writeFiles,
            rawProfile: nil
        )
        let strictRawRequest = IPhoneExportRequest(
            jobID: jobID,
            createdAt: createdAt,
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly,
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        let progress = IPhoneExportPreparationProgress(
            jobID: jobID,
            processedDays: 1,
            totalDays: 2,
            currentDate: dayStart,
            message: "Prepared 1 of 2 requested days."
        )
        let transfer = transferFixtures()
        let macJob = MacExportJob(
            jobID: jobID,
            createdAt: createdAt,
            sourceDeviceName: "Synthetic iPhone",
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            requestedDates: [dayStart, dayEnd],
            records: [completeRecord, partialRecord],
            externalDailyRecords: [sidecar],
            settingsSnapshot: snapshot,
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "Synthetic Export Destination"
            )
        )
        let macSuccess = MacExportResultPayload(
            jobID: jobID,
            status: .success,
            successCount: 2,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 3,
            externalRecordFileCount: 1,
            failedDateDetails: [],
            completedDates: [dayStart, dayEnd],
            destinationDisplayName: "Synthetic Export Destination",
            destinationPathForDisplay: "/Synthetic/HealthExports",
            completedAt: createdAt
        )
        let macPartial = MacExportResultPayload(
            jobID: jobID,
            status: .partialSuccess,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 2,
            externalRecordFileCount: 1,
            failedDateDetails: [failedDateDetail],
            completedDates: [dayStart, dayEnd],
            destinationDisplayName: "Synthetic Export Destination",
            destinationPathForDisplay: "/Synthetic/HealthExports",
            completedAt: createdAt
        )
        let agentRange = HealthMdDateRange(
            startDate: "2026-03-15",
            endDate: "2026-03-16"
        )
        let agentQuery = HealthMdQueryRequest(
            metrics: .explicit(["steps"]),
            sources: .allAvailable,
            dates: .exact(agentRange),
            operation: .metricSeries,
            page: .init(maxItems: 250, maxBytes: 262_144)
        )
        let agentSource = HealthMdSourceDescriptor(
            schema: "healthmd.health_data",
            schemaVersion: 7,
            digest: String(repeating: "a", count: 64)
        )
        let agentEvidence = HealthMdEvidenceReference(
            evidenceID: "evidence-steps-2026-03-15",
            locator: .canonicalUUID(
                ownerDate: "2026-03-15",
                uuid: "A1700000-0000-4000-8000-000000000010"
            ),
            source: agentSource,
            sourceID: HealthMdEvidenceSourceIDs.appleHealth
        )
        let agentCoverage = HealthMdCoverage(
            requestedRange: agentRange,
            availableRange: agentRange,
            status: .available,
            daysConsidered: 2,
            daysWithValues: 1,
            missing: [.init(
                range: .init(startDate: "2026-03-16", endDate: "2026-03-16"),
                status: .completeEmpty,
                reason: "No matching observation was stored for this day."
            )]
        )
        let agentPoint = HealthMdMetricPoint(
            metricID: "steps",
            displayName: "Steps",
            ownerDate: "2026-03-15",
            value: .count(12_345),
            status: .available,
            evidence: [agentEvidence],
            limitations: []
        )
        let agentQueryResponse = HealthMdQueryResponse(
            items: [.metric(agentPoint)],
            packet: nil,
            coverage: agentCoverage,
            sources: [agentSource],
            evidence: [agentEvidence],
            nextCursor: "synthetic-opaque-authenticated-cursor",
            limitations: []
        )
        let agentPacket = try HealthMdQueryCanonicalSerializer.makePacket(
            kind: .doctorVisit,
            range: agentRange,
            facts: [.init(
                factID: "steps-2026-03-15",
                label: "Steps",
                ownerDate: "2026-03-15",
                value: .count(12_345),
                evidence: [agentEvidence]
            )],
            coverage: agentCoverage,
            sources: [agentSource],
            limitations: [.init(
                code: "factual_observations_only",
                message: "This packet reports stored observations only and does not diagnose conditions or recommend treatment."
            )],
            metadata: .init(generatedAt: createdAt)
        )
        let agentEvidenceResponse = HealthMdQueryResponse(
            items: [],
            packet: agentPacket,
            coverage: agentCoverage,
            sources: [agentSource],
            evidence: [agentEvidence],
            nextCursor: nil,
            limitations: agentPacket.limitations
        )

        var generated: [String: Data] = [:]
        generated["api-export-v1.json"] = try canonicalJSON(APIExportClient.makePayload(
            records: [completeRecord],
            failedDateDetails: [failedDateDetail],
            settings: retainedSettings,
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            exportedAt: createdAt,
            connectedAppsEnabled: false
        ))
        generated["api-export-v2-provider-sidecar.json"] = try canonicalJSON(APIExportClient.makePayload(
            records: [completeRecord],
            failedDateDetails: [failedDateDetail],
            externalRecords: [sidecar],
            settings: retainedSettings,
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            exportedAt: createdAt,
            connectedAppsEnabled: true
        ))
        generated["agent-query-request.json"] = try HealthMdQueryCanonicalSerializer.data(for: agentQuery)
        generated["agent-query-response.json"] = try HealthMdQueryCanonicalSerializer.data(for: agentQueryResponse)
        generated["agent-evidence-response.json"] = try HealthMdQueryCanonicalSerializer.data(for: agentEvidenceResponse)
        generated["control-status.json"] = try encodeControl(statusResponse())

        // HealthMdControlServer.ExportRequestBody is private by design. These bodies
        // follow the same JSONSerialization construction used by control-server tests.
        generated["control-write-files-request.json"] = try jsonData([
            "source": "connected_iphone",
            "date_range": ["start": "2026-03-15", "end": "2026-03-16"],
            "settings_policy": "requested_dates_only",
            "response_mode": "write_files",
            "wait_timeout_seconds": 120
        ])
        generated["control-strict-raw-request.json"] = try jsonData([
            "source": "connected_iphone",
            "date_range": ["start": "2026-03-15", "end": "2026-03-16"],
            "settings_policy": "requested_dates_only",
            "response_mode": "raw_json",
            "raw_profile": "canonical_source_records_v1",
            "wait_timeout_seconds": 120
        ])
        generated.merge(try controlResponseFiles()) { _, replacement in replacement }

        generated["raw-result-complete.json"] = try jsonData(completeRawResult.controlAPIJSONObject())
        generated["raw-result-partial.json"] = try jsonData(partialRawResult.controlAPIJSONObject())
        generated["peer-capabilities.json"] = try encodeConnected(peerCapabilities)
        generated["iphone-export-request-write-files.json"] = try encodeConnected(writeFilesRequest)
        generated["iphone-export-request-strict-raw.json"] = try encodeConnected(strictRawRequest)
        generated["iphone-export-progress.json"] = try encodeConnected(progress)
        generated["transfer-offer.json"] = try encodeConnected(transfer.start)
        generated["transfer-chunk.json"] = try encodeConnected(transfer.chunk)
        generated["transfer-acknowledgement.json"] = try encodeConnected(transfer.acknowledgement)
        generated["transfer-complete.json"] = try encodeConnected(transfer.complete)
        generated["transfer-rejection.json"] = try encodeConnected(transfer.rejection)
        generated["mac-export-job.json"] = try encodeConnected(macJob)
        generated["mac-export-result-success.json"] = try encodeConnected(macSuccess)
        generated["mac-export-result-partial.json"] = try encodeConnected(macPartial)

        let messages = syncMessages(
            completeRecord: completeRecord,
            sidecar: sidecar,
            snapshot: snapshot,
            completeRawResult: completeRawResult,
            strictRawRequest: strictRawRequest,
            progress: progress,
            transfer: transfer,
            macJob: macJob,
            macPartial: macPartial
        )
        generated["message-fields.md"] = text(try messageFieldInventory(
            generatedJSON: generated,
            messages: messages
        ))

        let ellipsisArtifacts = generated.compactMap { name, data -> String? in
            let value = String(decoding: data, as: UTF8.self)
            return value.contains("...") || value.contains("…") ? name : nil
        }
        guard ellipsisArtifacts.isEmpty else {
            throw GenerationError.ellipsisFound(ellipsisArtifacts.sorted())
        }
        guard requiredArtifactNames.subtracting(Set(generated.keys).union(["manifest.json"])).isEmpty else {
            throw GenerationError.requiredArtifactsMissing(
                requiredArtifactNames.subtracting(Set(generated.keys).union(["manifest.json"])).sorted()
            )
        }

        generated["manifest.json"] = try manifest(files: generated, syncMessageCount: messages.count)
        return generated
    }

    static func write(to directory: URL) throws {
        let normalizedPath = directory.standardizedFileURL.path
        guard !normalizedPath.contains("HealthMdTests/Fixtures/Export"),
              !normalizedPath.contains("export_schema_signature") else {
            throw GenerationError.refusedSchemaFixturePath(normalizedPath)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in try files() {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }

    static var committedDirectory: URL {
        repositoryRoot.appendingPathComponent(relativeGeneratedDirectory, isDirectory: true)
    }

    static var updateMarker: URL {
        repositoryRoot.appendingPathComponent(
            "HealthMdTests/.update-generated-automation-reference-docs",
            isDirectory: false
        )
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Documentation
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // repository root
    }

    static func productionSyncMessageCaseNames() throws -> Set<String> {
        let sourceURL = repositoryRoot.appendingPathComponent("HealthMd/Shared/Sync/SyncPayload.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        guard let declaration = source.range(of: "enum SyncMessage: Codable {") else {
            throw GenerationError.syncMessageDeclarationMissing
        }
        let suffix = source[declaration.upperBound...]
        guard let end = suffix.range(of: "\n}\n\nextension SyncMessage") else {
            throw GenerationError.syncMessageDeclarationMissing
        }
        return Set(suffix[..<end.lowerBound].split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { return nil }
            let declaration = trimmed.dropFirst("case ".count)
            return String(declaration.prefix { $0 != "(" && !$0.isWhitespace })
        })
    }

    static func documentedSyncMessageCaseNames() throws -> Set<String> {
        let completeRaw = try CanonicalRawResultEnvelope(
            createdAt: createdAt,
            sourceDeviceName: "Synthetic iPhone",
            requestedDates: ["2026-03-15"],
            days: [CanonicalRawDayResult.captured(
                completeHealthData(),
                customization: retainedSettings.formatCustomization
            )]
        )
        let strictRequest = IPhoneExportRequest(
            jobID: jobID,
            createdAt: createdAt,
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly,
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        let progress = IPhoneExportPreparationProgress(
            jobID: jobID,
            processedDays: 1,
            totalDays: 2,
            currentDate: dayStart,
            message: "Prepared 1 of 2 requested days."
        )
        let sidecar = providerSidecar()
        let snapshot = settingsSnapshot()
        let macJob = MacExportJob(
            jobID: jobID,
            createdAt: createdAt,
            sourceDeviceName: "Synthetic iPhone",
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            requestedDates: [dayStart, dayEnd],
            records: [completeHealthData()],
            externalDailyRecords: [sidecar],
            settingsSnapshot: snapshot,
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "Synthetic Export Destination"
            )
        )
        let macPartial = MacExportResultPayload(
            jobID: jobID,
            status: .partialSuccess,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 2,
            externalRecordFileCount: 1,
            failedDateDetails: [failedDateDetail],
            completedDates: [dayStart, dayEnd],
            destinationDisplayName: "Synthetic Export Destination",
            destinationPathForDisplay: "/Synthetic/HealthExports",
            completedAt: createdAt
        )
        return Set(syncMessages(
            completeRecord: completeHealthData(),
            sidecar: sidecar,
            snapshot: snapshot,
            completeRawResult: completeRaw,
            strictRawRequest: strictRequest,
            progress: progress,
            transfer: transferFixtures(),
            macJob: macJob,
            macPartial: macPartial
        ).map(\.name))
    }

    private static var failedDateDetail: FailedDateDetail {
        FailedDateDetail(
            date: dayEnd,
            reason: .noHealthData,
            errorDetails: "Synthetic fixture: no source records were returned."
        )
    }

    private static var peerCapabilities: SyncPeerCapabilities {
        SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "9.9.9-documentation",
            buildNumber: "9999",
            platform: .iOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsRollupSummaries: true,
            supportsSummaryOnlyExports: true,
            supportsIPhoneExportRequests: true,
            supportsAllAvailableHistoryExportRequests: true,
            supportsProfileScopedIPhoneExportRequests: true,
            supportsChunkedMacExportJobs: true,
            supportsSizeBoundedConnectedTransfers: true,
            supportsStrictRawStreaming: true,
            supportsPerDateExportCompletion: true,
            supportsManualIPSync: true,
            manualIPSyncRequiresPairing: true,
            supportsDailyNoteOnlyExports: true,
            supportsPartitionedConnectedExports: true,
            connectedCorpusTransferCapabilities: .current,
            canonicalArchiveSchemaVersions: [HealthKitRecordArchive.currentRecordSchemaVersion],
            canonicalRawResultSchemaVersions: [CanonicalRawResultEnvelope.currentSchemaVersion],
            installationID: installationID,
            supportsDurableConnectedExportRecovery: true
        )
    }

    private static func statusResponse() -> HealthMdControlServer.StatusResponse {
        HealthMdControlServer.StatusResponse(
            macApp: "running",
            iphone: .init(
                connected: true,
                name: "Synthetic iPhone",
                canTriggerExports: true,
                canTriggerRawExports: true
            ),
            destination: .init(
                selected: true,
                writable: true,
                path: "/Synthetic/HealthExports",
                displayName: "Synthetic Export Destination"
            ),
            activeExport: .init(
                jobID: secondJobID,
                message: "Transferring synthetic durable export.",
                fractionComplete: 0.5,
                durable: true,
                paused: false,
                processedDays: 1,
                totalDays: 2,
                expiresAt: createdAt.addingTimeInterval(ConnectedCorpusOutboundStore.retentionInterval),
                state: ConnectedCorpusJobState.transferring.rawValue,
                sessionID: secondJobID,
                committedPartitions: 1,
                committedBytes: Int64(48 * 1_024 * 1_024)
            )
        )
    }

    private static func controlResponseFiles() throws -> [String: Data] {
        let success = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .success,
            jobID: jobID,
            message: "Exported 2 days and wrote 3 files including 1 provider sidecar.",
            successCount: 2,
            totalCount: 2,
            filesWritten: 3,
            externalRecordCount: 1,
            destinationDisplayName: "Synthetic Export Destination",
            destinationPath: "/Synthetic/HealthExports",
            failureReason: nil,
            rawData: nil,
            rawResult: nil,
            paused: false,
            fractionComplete: 1,
            processedDays: 2,
            expiresAt: createdAt.addingTimeInterval(ConnectedCorpusOutboundStore.retentionInterval),
            durable: true,
            durableState: ConnectedCorpusJobState.completed.rawValue,
            sessionID: secondJobID,
            committedPartitions: 2,
            committedBytes: Int64(96 * 1_024 * 1_024)
        )
        let partial = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .partialSuccess,
            jobID: jobID,
            message: "Exported 1 of 2 days and wrote 2 files including 1 provider sidecar.",
            successCount: 1,
            totalCount: 2,
            filesWritten: 2,
            externalRecordCount: 1,
            destinationDisplayName: "Synthetic Export Destination",
            destinationPath: "/Synthetic/HealthExports",
            failureReason: ExportFailureReason.noHealthData.rawValue,
            rawData: nil,
            rawResult: nil
        )
        let failure = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .failure,
            jobID: jobID,
            message: "The synthetic export could not be written.",
            successCount: 0,
            totalCount: 2,
            filesWritten: 0,
            externalRecordCount: 0,
            destinationDisplayName: "Synthetic Export Destination",
            destinationPath: "/Synthetic/HealthExports",
            failureReason: MacExportFailureReason.exportWriteFailure.rawValue,
            rawData: nil,
            rawResult: nil
        )
        let cancelled = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .cancelled,
            jobID: jobID,
            message: "Export cancelled.",
            successCount: 1,
            totalCount: 2,
            filesWritten: 1,
            externalRecordCount: 0,
            destinationDisplayName: "Synthetic Export Destination",
            destinationPath: "/Synthetic/HealthExports",
            failureReason: MacExportFailureReason.cancelled.rawValue,
            rawData: nil,
            rawResult: nil
        )
        let unavailable = MacIPhoneExportRequestCoordinator.ExportResponse.unavailable(
            "No synthetic iPhone is connected.",
            reason: "iphone_not_connected"
        )
        let timedOut = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .timedOut,
            jobID: jobID,
            message: "Timed out waiting for iPhone export result.",
            successCount: nil,
            totalCount: nil,
            filesWritten: nil,
            externalRecordCount: nil,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: IPhoneExportFailureReason.timedOut.rawValue,
            rawData: nil,
            rawResult: nil
        )

        return [
            "control-export-response-success.json": try encodeControlResponse(success),
            "control-export-response-partial-success.json": try encodeControlResponse(partial),
            "control-export-response-failure.json": try encodeControlResponse(failure),
            "control-export-response-cancelled.json": try encodeControlResponse(cancelled),
            "control-export-response-unavailable.json": try encodeControlResponse(unavailable),
            "control-export-response-timed-out.json": try encodeControlResponse(timedOut)
        ]
    }

    private static func completeHealthData() -> HealthData {
        HealthData(
            date: dayStart,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: HealthKitRecordArchive(
                captureStatus: .complete,
                dailyOwnership: ownership(for: "2026-03-15", start: dayStart),
                queryManifest: HealthKitQueryManifest(results: [HealthKitQueryResult(
                    identifier: "HKQuantityTypeIdentifierStepCount",
                    objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
                    operation: "sampleQuery",
                    metricIDs: ["steps"],
                    interval: HealthKitQueryInterval(startDate: dayStart, endDate: dayEnd),
                    status: .success,
                    recordCount: 0,
                    statusDescription: "Synthetic complete-empty query."
                )])
            ),
            healthKitRecordCaptureStatus: .complete
        )
    }

    private static func partialHealthData() -> HealthData {
        HealthData(
            date: dayStart,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            partialFailures: [ExportPartialFailure(
                date: dayStart,
                dataType: "workouts",
                dateRangeDescription: "2026-03-15",
                errorDescription: "Synthetic fixture query was unavailable."
            )],
            healthKitRecordArchive: HealthKitRecordArchive(
                captureStatus: .partial,
                dailyOwnership: ownership(for: "2026-03-15", start: dayStart),
                queryManifest: HealthKitQueryManifest(results: [
                    HealthKitQueryResult(
                        identifier: "HKQuantityTypeIdentifierStepCount",
                        objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
                        operation: "sampleQuery",
                        metricIDs: ["steps"],
                        interval: HealthKitQueryInterval(startDate: dayStart, endDate: dayEnd),
                        status: .success,
                        recordCount: 0,
                        statusDescription: "Synthetic query completed."
                    ),
                    HealthKitQueryResult(
                        identifier: "HKWorkoutType",
                        objectTypeIdentifier: "HKWorkoutType",
                        operation: "sampleQuery",
                        metricIDs: ["workouts"],
                        interval: HealthKitQueryInterval(startDate: dayStart, endDate: dayEnd),
                        status: .unsupported,
                        recordCount: 0,
                        error: HealthKitQueryError(
                            domain: "HealthMdDocumentationFixture",
                            code: 1001,
                            description: "Synthetic fixture type is unavailable.",
                            isRecoverable: false
                        ),
                        statusDescription: "Synthetic unsupported query."
                    )
                ]),
                integrityWarnings: [HealthKitRecordIntegrityWarning(
                    code: "synthetic_relationship_missing",
                    message: "Synthetic related fixture record was unavailable.",
                    metricIDs: ["workouts"]
                )]
            ),
            healthKitRecordCaptureStatus: .partial
        )
    }

    private static func ownership(for date: String, start: Date) -> HealthKitDailyOwnershipMetadata {
        HealthKitDailyOwnershipMetadata(
            ownerDate: date,
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZoneIdentifier: "UTC"
        )
    }

    private static func providerSidecar() -> ExternalDailyRecord {
        ExternalDailyRecord(
            provider: .whoop,
            date: "2026-03-15",
            fetchedAt: createdAt,
            payloads: [ExternalProviderPayload(
                name: "cycles",
                endpoint: "https://api.example.invalid/documentation/cycles",
                statusCode: 200,
                fetchedAt: createdAt,
                data: .object([
                    "fixture_id": .string("documentation-cycle-001"),
                    "score": .number(73.5),
                    "synthetic": .bool(true)
                ])
            )],
            warnings: ["Synthetic provider response for documentation only."]
        )
    }

    private static func settingsSnapshot() -> ExportSettingsSnapshot {
        var snapshot = ExportSettingsSnapshot.from(
            retainedSettings,
            healthSubfolder: "Health.md/Synthetic Exports"
        )
        snapshot.exportFormats = [.json]
        snapshot.includeMetadata = true
        snapshot.groupByCategory = true
        snapshot.filenameFormat = "yyyy-MM-dd"
        snapshot.folderStructure = "daily"
        snapshot.organizeFormatsIntoFolders = true
        snapshot.archiveExportFiles = false
        snapshot.summaryOnlyExport = false
        snapshot.writeMode = .overwrite
        snapshot.includeGranularData = true
        snapshot.generateWeeklyRollups = false
        snapshot.generateMonthlyRollups = false
        snapshot.generateYearlyRollups = false
        snapshot.metricSelection = MetricSelectionSnapshot(
            enabledMetricIDs: ["steps"],
            enabledCategoryIDs: ["activity"]
        )
        return snapshot
    }

    private struct TransferFixtures {
        let start: ConnectedTransferStart
        let chunk: ConnectedTransferChunk
        let acknowledgement: ConnectedTransferAck
        let complete: ConnectedTransferComplete
        let finalAcknowledgement: ConnectedTransferFinalAck
        let rejection: ConnectedTransferAbort
    }

    private static func transferFixtures() -> TransferFixtures {
        let digest = ConnectedTransferFile.sha256Hex(transferBytes)
        let manifest = ConnectedTransferManifest(
            kind: .canonicalRawResultV1,
            jobID: jobID,
            payloadSchemaVersion: CanonicalRawResultEnvelope.currentSchemaVersion
        )
        return TransferFixtures(
            start: ConnectedTransferStart(
                protocolVersion: ConnectedTransferStart.currentProtocolVersion,
                transferID: jobID,
                manifest: manifest,
                totalBytes: Int64(transferBytes.count),
                totalChunks: 1,
                chunkBytes: ConnectedTransferReceiver.maximumChunkBytes,
                sha256: digest
            ),
            chunk: ConnectedTransferChunk(
                transferID: jobID,
                sequence: 1,
                data: transferBytes,
                sha256: digest
            ),
            acknowledgement: ConnectedTransferAck(
                transferID: jobID,
                sequence: 1,
                accepted: true,
                sha256: digest,
                message: "Chunk accepted."
            ),
            complete: ConnectedTransferComplete(
                transferID: jobID,
                totalBytes: Int64(transferBytes.count),
                totalChunks: 1,
                sha256: digest
            ),
            finalAcknowledgement: ConnectedTransferFinalAck(
                transferID: jobID,
                accepted: true,
                sha256: digest,
                message: "Transfer decoded and accepted."
            ),
            rejection: ConnectedTransferAbort(
                transferID: jobID,
                jobID: jobID,
                reason: .invalidManifest,
                message: "Synthetic fixture manifest was rejected."
            )
        )
    }

    private struct NamedSyncMessage {
        let name: String
        let value: SyncMessage
    }

    private static func syncMessages(
        completeRecord: HealthData,
        sidecar: ExternalDailyRecord,
        snapshot: ExportSettingsSnapshot,
        completeRawResult: CanonicalRawResultEnvelope,
        strictRawRequest: IPhoneExportRequest,
        progress: IPhoneExportPreparationProgress,
        transfer: TransferFixtures,
        macJob: MacExportJob,
        macPartial: MacExportResultPayload
    ) -> [NamedSyncMessage] {
        let destinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: false,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Synthetic Export Destination",
            destinationPathForDisplay: "/Synthetic/HealthExports",
            lastError: "Synthetic export is already active.",
            activeJobID: secondJobID,
            capabilities: peerCapabilities
        )
        let streamStart = MacExportStreamStart(
            jobID: jobID,
            createdAt: createdAt,
            sourceDeviceName: "Synthetic iPhone",
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            requestedDates: [dayStart, dayEnd],
            totalRequestedDays: 2,
            totalTransferDays: 2,
            settingsSnapshot: snapshot,
            requestedTarget: macJob.requestedTarget,
            chunkStrategyVersion: 1
        )
        let streamChunk = MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: [completeRecord],
            externalDailyRecords: [sidecar],
            processedTransferDays: 1,
            totalTransferDays: 2
        )
        let rawPayload = IPhoneExportRawDataPayload(
            jobID: jobID,
            createdAt: createdAt,
            sourceDeviceName: "Synthetic iPhone",
            dateRangeStart: dayStart,
            dateRangeEnd: dayEnd,
            totalDays: 2,
            records: [completeRecord],
            externalDailyRecords: [sidecar],
            failedDateDetails: [failedDateDetail],
            settingsSnapshot: snapshot,
            strictResult: nil
        )
        let corpusFingerprint = ConnectedCorpusRequestFingerprint(sha256: transfer.start.sha256)
        let corpusSession = ConnectedCorpusTransferSession(
            sessionID: secondJobID,
            jobID: jobID,
            requestFingerprint: corpusFingerprint,
            createdAt: createdAt
        )
        let corpusPartition = ConnectedCorpusPartitionDescriptor(
            sessionID: secondJobID,
            jobID: jobID,
            index: 0,
            sourceDates: [dayStart, dayEnd],
            byteCount: transfer.start.totalBytes,
            sha256: transfer.start.sha256,
            previousSHA256: nil
        )

        let values: [SyncMessage] = [
            .requestData(dates: [dayStart, dayEnd]),
            .requestAllData,
            .healthData(SyncPayload(
                deviceName: "Synthetic iPhone",
                syncTimestamp: createdAt,
                healthRecords: [completeRecord]
            )),
            .syncProgress(SyncProgressInfo(
                totalDays: 2,
                processedDays: 1,
                recordsInBatch: 1,
                isComplete: false,
                message: "Processed 1 of 2 synthetic days."
            )),
            .hello(peerCapabilities),
            .macStatus(destinationStatus),
            .macExportRequest(macJob),
            .macExportStreamStart(streamStart),
            .macExportStreamChunk(streamChunk),
            .macExportStreamChunkAck(MacExportStreamChunkAck(
                jobID: jobID,
                sequence: 1,
                accepted: true,
                message: "Synthetic stream chunk accepted.",
                processedDays: 1,
                filesWritten: 1
            )),
            .macExportStreamComplete(MacExportStreamComplete(
                jobID: jobID,
                totalChunks: 2,
                iphoneFailedDateDetails: [failedDateDetail]
            )),
            .macExportStreamAbort(MacExportStreamAbort(
                jobID: jobID,
                reason: .payloadDecodeFailure,
                message: "Synthetic stream payload could not be decoded."
            )),
            .macExportAccepted(MacExportAcknowledgement(
                jobID: jobID,
                acceptedAt: createdAt,
                message: "Synthetic export accepted."
            )),
            .macExportProgress(MacExportProgress(
                jobID: jobID,
                phase: .writing,
                processedDays: 1,
                totalDays: 2,
                currentDate: dayStart,
                filesWritten: 1,
                message: "Writing synthetic export files."
            )),
            .macExportResult(macPartial),
            .macExportCancel(jobID: jobID),
            .macExportFailed(MacExportFailure(
                jobID: jobID,
                reason: .exportWriteFailure,
                message: "Synthetic export write failed.",
                underlyingError: "Synthetic fixture filesystem rejection.",
                occurredAt: createdAt
            )),
            .iphoneExportRequest(strictRawRequest),
            .iphoneExportAccepted(IPhoneExportAcknowledgement(
                jobID: jobID,
                acceptedAt: createdAt,
                message: "Synthetic iPhone request accepted."
            )),
            .iphoneExportPreparationProgress(progress),
            .iphoneExportRawData(rawPayload),
            .connectedTransferStart(transfer.start),
            .connectedTransferChunk(transfer.chunk),
            .connectedTransferAck(transfer.acknowledgement),
            .connectedTransferComplete(transfer.complete),
            .connectedTransferFinalAck(transfer.finalAcknowledgement),
            .connectedTransferAbort(transfer.rejection),
            .connectedCorpusTransferOpen(ConnectedCorpusTransferOpen(
                session: corpusSession,
                partition: corpusPartition
            )),
            .connectedCorpusTransferDisposition(ConnectedCorpusTransferDisposition(
                sessionID: secondJobID,
                jobID: jobID,
                partitionIndex: 0,
                partitionSHA256: transfer.start.sha256,
                disposition: .accept,
                nextPartitionIndex: 0,
                message: "Synthetic corpus partition accepted."
            )),
            .connectedCorpusStatus(ConnectedCorpusProgressSnapshot(
                jobID: jobID,
                sessionID: secondJobID,
                requestFingerprint: corpusFingerprint,
                state: .transferring,
                processedDays: 1,
                totalDays: 2,
                committedPartitionCount: 0,
                committedBytes: 0,
                currentDate: dayStart,
                message: "Transferring synthetic durable corpus.",
                updatedAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(ConnectedCorpusOutboundStore.retentionInterval)
            )),
            .connectedCorpusTransferFinalize(ConnectedCorpusTransferFinalize(
                sessionID: secondJobID,
                jobID: jobID,
                requestFingerprint: corpusFingerprint,
                partitionCount: 1,
                totalByteCount: transfer.start.totalBytes,
                finalPartitionSHA256: transfer.start.sha256
            )),
            .connectedCorpusTransferFinalAck(ConnectedCorpusTransferFinalAck(
                sessionID: secondJobID,
                jobID: jobID,
                accepted: true,
                requestFingerprint: corpusFingerprint,
                finalPartitionSHA256: transfer.start.sha256,
                message: "Synthetic corpus session accepted."
            )),
            .connectedCorpusTransferCancel(ConnectedCorpusTransferCancel(
                sessionID: secondJobID,
                jobID: jobID,
                reason: .userRequested,
                message: "Synthetic corpus session cancelled.",
                requestedAt: createdAt
            )),
            .connectedCorpusTransferCancelAck(ConnectedCorpusTransferCancelAck(
                sessionID: secondJobID,
                jobID: jobID,
                accepted: true,
                acknowledgedAt: createdAt,
                message: "Synthetic corpus cancellation acknowledged."
            )),
            .iphoneExportCancel(jobID: jobID),
            .iphoneExportRejected(IPhoneExportFailure(
                jobID: jobID,
                reason: .healthKitNotAuthorized,
                message: "Synthetic HealthKit authorization is unavailable.",
                underlyingError: "Synthetic fixture authorization denial.",
                occurredAt: createdAt
            )),
            .ping,
            .pong
        ]
        return values.map { NamedSyncMessage(name: $0.operationalName, value: $0) }
            .sorted { $0.name < $1.name }
    }

    private static func messageFieldInventory(
        generatedJSON: [String: Data],
        messages: [NamedSyncMessage]
    ) throws -> String {
        var lines = [
            "# Generated automation message and field inventory",
            "",
            "This inventory is generated from production API/control serialization and every current `SyncMessage` Codable case. Paths ending in `[]` describe array elements.",
            "",
            "- Generated JSON artifacts inventoried: \(generatedJSON.keys.filter { $0.hasSuffix(".json") }.count)",
            "- Sync messages inventoried: \(messages.count)",
            "",
            "## SyncMessage wire inventory"
        ]

        for message in messages {
            let data = try encodeWire(message.value)
            _ = try JSONDecoder().decode(SyncMessage.self, from: data)
            let object = try JSONSerialization.jsonObject(with: data)
            lines.append(contentsOf: fieldTable(title: "`\(message.name)`", object: object))
        }

        lines.append(contentsOf: ["", "## Generated JSON artifact inventory"])
        for name in generatedJSON.keys.filter({ $0.hasSuffix(".json") }).sorted() {
            let object = try JSONSerialization.jsonObject(with: generatedJSON[name]!)
            lines.append(contentsOf: fieldTable(title: "`\(name)`", object: object))
        }
        return lines.joined(separator: "\n")
    }

    private static func fieldTable(title: String, object: Any) -> [String] {
        var observations: [String: Set<String>] = [:]
        collectTypes(object, path: "$", observations: &observations)
        var lines = [
            "",
            "### \(title)",
            "",
            "| JSON path | Observed type or types |",
            "|---|---|"
        ]
        for path in observations.keys.sorted() {
            let types = observations[path, default: []].sorted().joined(separator: ", ")
            lines.append("| `\(markdownCell(path))` | \(markdownCell(types)) |")
        }
        return lines
    }

    private static func collectTypes(
        _ value: Any,
        path: String,
        observations: inout [String: Set<String>]
    ) {
        observations[path, default: []].insert(jsonType(of: value))
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                collectTypes(dictionary[key]!, path: "\(path).\(key)", observations: &observations)
            }
        } else if let array = value as? [Any] {
            for element in array {
                collectTypes(element, path: "\(path)[]", observations: &observations)
            }
        }
    }

    private static func jsonType(of value: Any) -> String {
        if value is NSNull { return "null" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return "boolean" }
            return number.doubleValue.rounded() == number.doubleValue ? "integer" : "number"
        }
        if value is String { return "string" }
        if value is [Any] { return "array" }
        if value is [String: Any] { return "object" }
        return "unknown"
    }

    private static func markdownCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func encodeConnected<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return textData(try encoder.encode(value))
    }

    private static func encodeWire(_ value: SyncMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func encodeControl<T: Encodable>(_ value: T) throws -> Data {
        let encoder = controlEncoder()
        return textData(try encoder.encode(value))
    }

    private static func encodeControlResponse(
        _ response: MacIPhoneExportRequestCoordinator.ExportResponse
    ) throws -> Data {
        textData(try response.controlAPIData(using: controlEncoder()))
    }

    private static func controlEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func canonicalJSON(_ data: Data) throws -> Data {
        try jsonData(JSONSerialization.jsonObject(with: data))
    }

    private static func jsonData(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw GenerationError.invalidJSONObject
        }
        return textData(try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ))
    }

    private static func text(_ value: String) -> Data {
        Data((value.hasSuffix("\n") ? value : value + "\n").utf8)
    }

    private static func textData(_ value: Data) -> Data {
        var data = value
        if data.last != 0x0a { data.append(0x0a) }
        return data
    }

    private struct ManifestArtifact: Codable {
        let bytes: Int
        let path: String
        let sha256: String
    }

    private struct Manifest: Codable {
        let artifactCount: Int
        let hashedArtifactCount: Int
        let artifacts: [ManifestArtifact]
        let contracts: [String]
        let controlResponseStatuses: [String]
        let generatedGroup: String
        let generator: String
        let syntheticDataOnly: Bool
        let syncMessageCount: Int

        enum CodingKeys: String, CodingKey {
            case artifactCount = "artifact_count"
            case hashedArtifactCount = "hashed_artifact_count"
            case artifacts
            case contracts
            case controlResponseStatuses = "control_response_statuses"
            case generatedGroup = "generated_group"
            case generator
            case syntheticDataOnly = "synthetic_data_only"
            case syncMessageCount = "sync_message_count"
        }
    }

    private static func manifest(files: [String: Data], syncMessageCount: Int) throws -> Data {
        let artifacts = files.keys.sorted().map { name in
            let data = files[name] ?? Data()
            return ManifestArtifact(bytes: data.count, path: name, sha256: sha256(data))
        }
        let manifest = Manifest(
            artifactCount: files.count + 1,
            hashedArtifactCount: files.count,
            artifacts: artifacts,
            contracts: [
                "healthmd.api_export/v1",
                "healthmd.api_export/v2",
                "healthmd.raw_result/v1",
                "localhost-control/v1",
                "sync-protocol/v2",
                "connected-transfer/v1"
            ],
            controlResponseStatuses: documentedControlResponseStatuses.sorted(),
            generatedGroup: "automation",
            generator: "HealthMdTests/Documentation/GeneratedAutomationReferenceDocumentation.swift",
            syntheticDataOnly: true,
            syncMessageCount: syncMessageCount
        )
        return try encodeConnected(manifest)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    enum GenerationError: Error {
        case ellipsisFound([String])
        case invalidJSONObject
        case refusedSchemaFixturePath(String)
        case requiredArtifactsMissing([String])
        case syncMessageDeclarationMissing
    }
}
#endif
