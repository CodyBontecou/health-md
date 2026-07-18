#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacIPhoneExportRequestCoordinator: ObservableObject {
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
        let destinationDisplayName: String?
        let destinationPath: String?
        let failureReason: String?
        /// Legacy raw response retained for requests that do not select a strict profile.
        let rawData: IPhoneExportRawDataPayload?
        /// Strict versioned raw-result response. The control server injects each
        /// canonical daily JSON document as an object rather than internal Codable.
        let rawResult: CanonicalRawResultEnvelope?
        /// Corpus-scale strict raw responses are already validated and composed
        /// as public control JSON on disk. This transport-only property is not
        /// part of the API payload.
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
            case destinationDisplayName = "destination_display_name"
            case destinationPath = "destination_path"
            case failureReason = "failure_reason"
            case rawData = "raw_data"
            case rawResult = "raw_result"
        }

        static func unavailable(_ message: String, reason: String? = nil) -> Self {
            Self(
                status: .unavailable,
                jobID: nil,
                message: message,
                successCount: nil,
                totalCount: nil,
                filesWritten: nil,
                externalRecordCount: nil,
                destinationDisplayName: nil,
                destinationPath: nil,
                failureReason: reason,
                rawData: nil,
                rawResult: nil
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

    private struct PendingRequest {
        let request: IPhoneExportRequest
        let continuation: CheckedContinuation<ExportResponse, Never>
        let inactivityTimeoutSeconds: TimeInterval
        let sendCancellation: () -> Void
        var timeoutToken: UUID
        var timeoutTask: Task<Void, Never>
    }

    @Published private(set) var activeJobID: UUID?
    @Published private(set) var latestProgress: IPhoneExportPreparationProgress?
    var onRequestCancellation: ((UUID) -> Void)?
    private var pendingRequests: [UUID: PendingRequest] = [:]

    func requestExport(
        _ exportRequest: ExportRequest,
        syncService: SyncService,
        destinationStatus: MacDestinationStatus
    ) async -> ExportResponse {
        guard syncService.connectionState == .connected else {
            return .unavailable("No iPhone is connected.", reason: "iphone_not_connected")
        }
        guard let capabilities = syncService.remoteCapabilities,
              capabilities.platform == .iOS,
              capabilities.supportsIPhoneExportRequests else {
            return .unavailable("Connected iPhone does not support Mac-initiated exports. Update Health.md on iPhone.", reason: "unsupported_iphone")
        }
        if let rawProfile = exportRequest.rawProfile {
            guard exportRequest.responseMode == .rawJSON,
                  capabilities.supports(rawProfile: rawProfile) else {
                return .unavailable(
                    "Connected iPhone cannot provide the requested strict raw profile. Update Health.md on iPhone.",
                    reason: "unsupported_raw_profile"
                )
            }
        }
        if exportRequest.responseMode == .writeFiles {
            guard destinationStatus.canReceiveExports else {
                return .unavailable(destinationStatus.notReadyReason ?? "Mac destination is not ready.", reason: "mac_destination_unavailable")
            }
        }
        guard activeJobID == nil else {
            return .unavailable("Another iPhone export request is already active.", reason: "export_in_progress")
        }

        let dates = ExportOrchestrator.dateRange(from: exportRequest.startDate, to: exportRequest.endDate)
        guard !dates.isEmpty else {
            return .unavailable("Choose a valid date range.", reason: "invalid_date_range")
        }

        let request = IPhoneExportRequest(
            jobID: exportRequest.jobID ?? UUID(),
            createdAt: Date(),
            dateRangeStart: exportRequest.startDate,
            dateRangeEnd: exportRequest.endDate,
            requestedDateIdentifiers: exportRequest.requestedDateIdentifiers,
            requestedBy: exportRequest.requestedBy,
            settingsPolicy: exportRequest.settingsPolicy,
            responseMode: exportRequest.responseMode,
            rawProfile: exportRequest.rawProfile
        )

        activeJobID = request.jobID
        latestProgress = nil

        return await withCheckedContinuation { continuation in
            let timeoutToken = UUID()
            let cancellationCleanup = onRequestCancellation
            pendingRequests[request.jobID] = PendingRequest(
                request: request,
                continuation: continuation,
                inactivityTimeoutSeconds: exportRequest.waitTimeoutSeconds,
                sendCancellation: { [weak syncService] in
                    cancellationCleanup?(request.jobID)
                    syncService?.send(.connectedTransferAbort(ConnectedTransferAbort(
                        transferID: request.jobID,
                        jobID: request.jobID,
                        reason: .cancelled,
                        message: "Mac cancelled the connected export transfer."
                    )))
                    syncService?.send(.iphoneExportCancel(jobID: request.jobID))
                },
                timeoutToken: timeoutToken,
                timeoutTask: makeTimeoutTask(
                    jobID: request.jobID,
                    timeoutSeconds: exportRequest.waitTimeoutSeconds,
                    timeoutToken: timeoutToken
                )
            )
            syncService.send(.iphoneExportRequest(request))
        }
    }

    func handleAccepted(_ acknowledgement: IPhoneExportAcknowledgement) {
        guard pendingRequests[acknowledgement.jobID] != nil else { return }
        activeJobID = acknowledgement.jobID
        resetInactivityTimeout(for: acknowledgement.jobID)
    }

    func handlePreparationProgress(_ progress: IPhoneExportPreparationProgress) {
        guard pendingRequests[progress.jobID] != nil else { return }
        latestProgress = progress
        resetInactivityTimeout(for: progress.jobID)
    }

    func handleMacExportProgress(_ progress: MacExportProgress) {
        guard pendingRequests[progress.jobID] != nil else { return }
        resetInactivityTimeout(for: progress.jobID)
    }

    /// Only receiver-validated transfer progress extends a control request's
    /// inactivity deadline. Merely receiving malformed or out-of-order bytes does not.
    func handleValidatedTransferProgress(jobID: UUID) {
        guard pendingRequests[jobID] != nil else { return }
        resetInactivityTimeout(for: jobID)
    }

    func accepts(_ manifest: ConnectedTransferManifest) -> Bool {
        guard let pending = pendingRequests[manifest.jobID] else { return false }
        switch manifest.kind {
        case .canonicalRawResultV1:
            return pending.request.responseMode == .rawJSON
                && pending.request.rawProfile == .canonicalSourceRecordsV1
                && manifest.payloadSchemaVersion == CanonicalRawResultEnvelope.currentSchemaVersion
        case .macExportJobV1:
            return pending.request.responseMode == .writeFiles && manifest.payloadSchemaVersion == 1
        case .connectedCorpusPartitionV1:
            return manifest.corpusPartition?.jobID == pending.request.jobID
                && manifest.payloadSchemaVersion == ConnectedCorpusPartitionFileManifest.currentVersion
        }
    }

    func accepts(_ open: ConnectedCorpusTransferOpen) -> Bool {
        guard let pending = pendingRequests[open.session.jobID],
              open.partition.jobID == open.session.jobID,
              let manifest = open.exportManifest else {
            return false
        }
        let dateRangeMatches: Bool
        if let expected = pending.request.requestedDateIdentifiers,
           let supplied = manifest.requestedDateIdentifiers {
            dateRangeMatches = expected == supplied
        } else {
            dateRangeMatches = Calendar.current.isDate(
                manifest.dateRangeStart,
                inSameDayAs: pending.request.dateRangeStart
            ) && Calendar.current.isDate(
                manifest.dateRangeEnd,
                inSameDayAs: pending.request.dateRangeEnd
            )
        }
        guard dateRangeMatches else { return false }
        switch manifest.mode {
        case .writeFiles:
            return pending.request.responseMode == .writeFiles
        case .strictRaw:
            return pending.request.responseMode == .rawJSON
                && pending.request.rawProfile == .canonicalSourceRecordsV1
        }
    }

    @discardableResult
    func complete(with payload: MacExportResultPayload) -> Bool {
        guard let pending = pendingRequests.removeValue(forKey: payload.jobID) else { return false }
        pending.timeoutTask.cancel()
        activeJobID = nil
        latestProgress = nil

        let status: ExportResponse.Status
        switch payload.status {
        case .success: status = .success
        case .partialSuccess: status = .partialSuccess
        case .failure: status = .failure
        case .cancelled: status = .cancelled
        }

        pending.continuation.resume(returning: ExportResponse(
            status: status,
            jobID: payload.jobID,
            message: completionMessage(for: payload),
            successCount: payload.successCount,
            totalCount: payload.totalCount,
            filesWritten: payload.totalFilesWritten,
            externalRecordCount: payload.externalRecordFileCount,
            destinationDisplayName: payload.destinationDisplayName,
            destinationPath: payload.destinationPathForDisplay,
            failureReason: payload.failedDateDetails.first?.reason.rawValue,
            rawData: nil,
            rawResult: nil
        ))
        return true
    }

    /// Completes the strict raw control request only after the spool file's
    /// declared length and SHA-256 have been validated and this envelope decoded.
    @discardableResult
    func complete(with strictResult: CanonicalRawResultEnvelope, jobID: UUID) -> Bool {
        guard let pending = pendingRequests.removeValue(forKey: jobID) else { return false }
        pending.timeoutTask.cancel()
        activeJobID = nil
        latestProgress = nil

        let expectedDates = ExportOrchestrator.dateRange(
            from: pending.request.dateRangeStart,
            to: pending.request.dateRangeEnd
        )
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let expectedDateStrings = expectedDates.map { dateFormatter.string(from: $0) }
        let validationIssues = pending.request.rawProfile == .canonicalSourceRecordsV1
            ? strictResult.strictValidationIssues(expectedDates: expectedDateStrings)
            : ["raw_result_profile_mismatch"]
        guard validationIssues.isEmpty else {
            pending.continuation.resume(returning: ExportResponse(
                status: .failure,
                jobID: jobID,
                message: "The iPhone returned an invalid strict raw result.",
                successCount: 0,
                totalCount: expectedDates.count,
                filesWritten: 0,
                externalRecordCount: 0,
                destinationDisplayName: nil,
                destinationPath: nil,
                failureReason: "raw_profile_response_mismatch",
                rawData: nil,
                rawResult: nil
            ))
            return false
        }
        let expectedDayCount = expectedDates.count
        let isIncomplete = strictResult.hasPartialResult
            || strictResult.totalRequestedDays != expectedDayCount
            || strictResult.days.count != expectedDayCount
        let status: ExportResponse.Status = isIncomplete ? .partialSuccess : .success
        let retainedCount = strictResult.calculatedCaptureSummary.retainedDayCount
        pending.continuation.resume(returning: ExportResponse(
            status: status,
            jobID: jobID,
            message: isIncomplete
                ? "Fetched canonical raw data for \(retainedCount)/\(expectedDayCount) day(s) with incomplete capture."
                : "Fetched canonical raw data for all \(expectedDayCount) requested day(s).",
            successCount: retainedCount,
            totalCount: expectedDayCount,
            filesWritten: 0,
            externalRecordCount: 0,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: isIncomplete ? "incomplete_raw_capture" : nil,
            rawData: nil,
            rawResult: strictResult
        ))
        return true
    }

    /// Completes a corpus strict-raw request with an already validated,
    /// disk-backed `healthmd.raw_result` object and composes the outer response
    /// without loading the raw corpus into memory.
    @discardableResult
    func complete(with strictSpool: CanonicalRawResultSpool, jobID: UUID) async -> Bool {
        guard let pending = pendingRequests[jobID] else { return false }
        let expectedDayCount = pending.request.requestedDateIdentifiers?.count
            ?? ExportOrchestrator.dateRange(
                from: pending.request.dateRangeStart,
                to: pending.request.dateRangeEnd
            ).count
        guard pending.request.rawProfile == .canonicalSourceRecordsV1,
              strictSpool.totalRequestedDays == expectedDayCount else {
            guard let removed = pendingRequests.removeValue(forKey: jobID) else { return false }
            removed.timeoutTask.cancel()
            activeJobID = nil
            latestProgress = nil
            removed.continuation.resume(returning: ExportResponse(
                status: .failure,
                jobID: jobID,
                message: "The iPhone returned an invalid partitioned strict raw result.",
                successCount: 0,
                totalCount: expectedDayCount,
                filesWritten: 0,
                externalRecordCount: 0,
                destinationDisplayName: nil,
                destinationPath: nil,
                failureReason: "raw_profile_response_mismatch",
                rawData: nil,
                rawResult: nil
            ))
            return false
        }

        let isIncomplete = strictSpool.hasPartialResult
        var response = ExportResponse(
            status: isIncomplete ? .partialSuccess : .success,
            jobID: jobID,
            message: isIncomplete
                ? "Fetched canonical raw data for \(strictSpool.captureSummary.retainedDayCount)/\(expectedDayCount) day(s) with incomplete capture."
                : "Fetched canonical raw data for all \(expectedDayCount) requested day(s).",
            successCount: strictSpool.captureSummary.retainedDayCount,
            totalCount: expectedDayCount,
            filesWritten: 0,
            externalRecordCount: 0,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: isIncomplete ? "incomplete_raw_capture" : nil,
            rawData: nil,
            rawResult: nil
        )
        do {
            response.spooledControlResponse = try await Self.composeControlResponse(
                response,
                rawResultFile: strictSpool.file.url,
                progress: {
                    guard self.pendingRequests[jobID] != nil else { throw CancellationError() }
                    self.resetInactivityTimeout(for: jobID)
                }
            )
            guard let removed = pendingRequests.removeValue(forKey: jobID) else {
                response.spooledControlResponse?.remove()
                strictSpool.remove()
                return false
            }
            response.spooledRawDateRangeStart = strictSpool.dateRangeStart
            response.spooledRawDateRangeEnd = strictSpool.dateRangeEnd
            response.spooledRawTotalDays = strictSpool.totalRequestedDays
            strictSpool.remove()
            removed.timeoutTask.cancel()
            activeJobID = nil
            latestProgress = nil
            removed.continuation.resume(returning: response)
            return true
        } catch {
            strictSpool.remove()
            guard let removed = pendingRequests.removeValue(forKey: jobID) else { return false }
            removed.timeoutTask.cancel()
            activeJobID = nil
            latestProgress = nil
            removed.continuation.resume(returning: ExportResponse(
                status: .failure,
                jobID: jobID,
                message: "The strict raw control response could not be prepared.",
                successCount: 0,
                totalCount: expectedDayCount,
                filesWritten: 0,
                externalRecordCount: 0,
                destinationDisplayName: nil,
                destinationPath: nil,
                failureReason: "raw_response_spool_failed",
                rawData: nil,
                rawResult: nil
            ))
            return false
        }
    }

    @discardableResult
    func complete(with rawData: IPhoneExportRawDataPayload) -> Bool {
        guard let pending = pendingRequests.removeValue(forKey: rawData.jobID) else { return false }
        pending.timeoutTask.cancel()
        activeJobID = nil
        latestProgress = nil

        if pending.request.rawProfile == .canonicalSourceRecordsV1 {
            // Strict raw is a mandatory negotiated stream. Never silently accept
            // the legacy whole-payload message, even if it happens to contain a
            // strict envelope.
            pending.continuation.resume(returning: ExportResponse(
                status: .failure,
                jobID: rawData.jobID,
                message: "The iPhone attempted an unbounded strict raw response. Update Health.md on both devices.",
                successCount: 0,
                totalCount: rawData.totalDays,
                filesWritten: 0,
                externalRecordCount: 0,
                destinationDisplayName: nil,
                destinationPath: nil,
                failureReason: "strict_raw_stream_required",
                rawData: nil,
                rawResult: nil
            ))
            return true
        }

        // Requests from older control clients keep the previous payload and no-data semantics.
        let successCount = rawData.records.count
        let externalRecordCount = rawData.externalDailyRecords.filter(\.shouldExport).count
        pending.continuation.resume(returning: ExportResponse(
            status: successCount > 0 ? .success : .failure,
            jobID: rawData.jobID,
            message: successCount > 0
                ? "Fetched raw health data for \(successCount)/\(rawData.totalDays) day(s)."
                : "No raw health data was found for the requested date range.",
            successCount: successCount,
            totalCount: rawData.totalDays,
            filesWritten: 0,
            externalRecordCount: externalRecordCount,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: rawData.failedDateDetails.first?.reason.rawValue,
            rawData: rawData,
            rawResult: nil
        ))
        return true
    }

    @discardableResult
    func complete(with failure: MacExportFailure) -> Bool {
        guard let jobID = failure.jobID,
              let pending = pendingRequests.removeValue(forKey: jobID) else { return false }
        pending.timeoutTask.cancel()
        activeJobID = nil
        latestProgress = nil
        pending.continuation.resume(returning: ExportResponse(
            status: failure.reason == .cancelled ? .cancelled : .failure,
            jobID: jobID,
            message: failure.message,
            successCount: 0,
            totalCount: nil,
            filesWritten: 0,
            externalRecordCount: nil,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: failure.reason.rawValue,
            rawData: nil,
            rawResult: nil
        ))
        return true
    }

    @discardableResult
    func complete(with failure: IPhoneExportFailure) -> Bool {
        guard let jobID = failure.jobID,
              let pending = pendingRequests.removeValue(forKey: jobID) else { return false }
        pending.timeoutTask.cancel()
        activeJobID = nil
        latestProgress = nil
        pending.continuation.resume(returning: ExportResponse(
            status: .unavailable,
            jobID: jobID,
            message: failure.message,
            successCount: nil,
            totalCount: nil,
            filesWritten: nil,
            externalRecordCount: nil,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: failure.reason.rawValue,
            rawData: nil,
            rawResult: nil
        ))
        return true
    }

    /// Cancels work when the loopback CLI closes its HTTP connection before a
    /// response is available (for example Ctrl-C or a broken output pipeline).
    func cancelRequestForDisconnectedClient(jobID: UUID) {
        guard let pending = pendingRequests.removeValue(forKey: jobID) else { return }
        pending.timeoutTask.cancel()
        pending.sendCancellation()
        if activeJobID == jobID { activeJobID = nil }
        latestProgress = nil
        pending.continuation.resume(returning: ExportResponse(
            status: .cancelled,
            jobID: jobID,
            message: "CLI disconnected; the connected export was cancelled at a partition checkpoint.",
            successCount: nil,
            totalCount: nil,
            filesWritten: nil,
            externalRecordCount: nil,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: IPhoneExportFailureReason.cancelled.rawValue,
            rawData: nil,
            rawResult: nil
        ))
    }

    /// Keeps the loopback request and its inactivity deadline alive while the
    /// iPhone reconnects. The durable corpus journal is detached separately and
    /// restored only when the same session fingerprint opens again.
    func handlePeerDisconnectForResume() {
        guard let jobID = activeJobID,
              pendingRequests[jobID] != nil else { return }
        latestProgress = IPhoneExportPreparationProgress(
            jobID: jobID,
            processedDays: latestProgress?.processedDays ?? 0,
            totalDays: max(latestProgress?.totalDays ?? 1, 1),
            currentDate: latestProgress?.currentDate,
            message: "Waiting for the iPhone to reconnect and resume…"
        )
    }

    /// Completes a pending control request after a peer disconnect. Cancellation
    /// still flows through `iphoneExportCancel`; a closed transport makes the send
    /// a harmless no-op, and late results no longer have a continuation to resume.
    func cancelActiveRequestForDisconnect() {
        guard let jobID = activeJobID,
              let pending = pendingRequests.removeValue(forKey: jobID) else { return }
        pending.timeoutTask.cancel()
        pending.sendCancellation()
        activeJobID = nil
        latestProgress = nil
        pending.continuation.resume(returning: ExportResponse(
            status: .unavailable,
            jobID: jobID,
            message: "The iPhone disconnected before the export completed.",
            successCount: nil,
            totalCount: nil,
            filesWritten: nil,
            externalRecordCount: nil,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: "iphone_disconnected",
            rawData: nil,
            rawResult: nil
        ))
    }

    private func makeTimeoutTask(jobID: UUID, timeoutSeconds: TimeInterval, timeoutToken: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            let nanoseconds = UInt64(max(timeoutSeconds, 0.001) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completeTimedOut(jobID: jobID, timeoutToken: timeoutToken)
            }
        }
    }

    private func resetInactivityTimeout(for jobID: UUID) {
        guard var pending = pendingRequests[jobID] else { return }
        pending.timeoutTask.cancel()
        let timeoutToken = UUID()
        pending.timeoutToken = timeoutToken
        pending.timeoutTask = makeTimeoutTask(
            jobID: jobID,
            timeoutSeconds: pending.inactivityTimeoutSeconds,
            timeoutToken: timeoutToken
        )
        pendingRequests[jobID] = pending
    }

    private func completeTimedOut(jobID: UUID, timeoutToken: UUID) {
        guard let current = pendingRequests[jobID], current.timeoutToken == timeoutToken else { return }
        guard let pending = pendingRequests.removeValue(forKey: jobID) else { return }
        pending.timeoutTask.cancel()
        pending.sendCancellation()
        activeJobID = nil
        latestProgress = nil
        pending.continuation.resume(returning: ExportResponse(
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
        ))
    }

    private static func composeControlResponse(
        _ response: ExportResponse,
        rawResultFile: URL,
        progress: () throws -> Void
    ) async throws -> ConnectedTransferPreparedFile {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let smallResponseData = try encoder.encode(response)
        guard var object = try JSONSerialization.jsonObject(with: smallResponseData) as? [String: Any] else {
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
                let keyData = try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed])
                let valueData = try JSONSerialization.data(
                    withJSONObject: object[key] as Any,
                    options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
                )
                try output.write(contentsOf: keyData)
                try output.write(contentsOf: Data(":".utf8))
                try output.write(contentsOf: valueData)
            }
            if !object.isEmpty { try output.write(contentsOf: Data(",".utf8)) }
            try output.write(contentsOf: Data("\"raw_result\":".utf8))

            let rawInput = try FileHandle(forReadingFrom: rawResultFile)
            defer { try? rawInput.close() }
            while let data = try rawInput.read(upToCount: 1_048_576), !data.isEmpty {
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
        let providerSuffix = payload.externalRecordFileCount > 0
            ? " including \(payload.externalRecordFileCount) provider sidecar(s)"
            : ""
        switch payload.status {
        case .success:
            return "Exported \(payload.successCount) day(s), wrote \(payload.totalFilesWritten) file(s)\(providerSuffix)."
        case .partialSuccess:
            return "Exported \(payload.successCount)/\(payload.totalCount) day(s), wrote \(payload.totalFilesWritten) file(s)\(providerSuffix)."
        case .failure:
            return payload.failedDateDetails.first?.detailedMessage ?? "Export failed."
        case .cancelled:
            return "Export cancelled."
        }
    }
}
#endif
