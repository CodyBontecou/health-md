import CryptoKit
import Foundation
import HealthMdConnectionCore

public enum DirectRawReceiverError: LocalizedError, Equatable {
    case requestChanged
    case sessionChanged
    case unexpectedDate(String)
    case manifestChanged(String)
    case partitionOutOfOrder
    case partitionChanged
    case invalidChunk
    case invalidPartition
    case incompleteTransfer
    case invalidFinalization
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .requestChanged: return "The durable direct export request changed."
        case .sessionChanged: return "The durable direct export session or peer binding changed."
        case .unexpectedDate(let date): return "The direct export contained an unexpected date: \(date)."
        case .manifestChanged(let date): return "The direct raw-day manifest changed for \(date)."
        case .partitionOutOfOrder: return "The direct export partition arrived out of order."
        case .partitionChanged: return "A previously committed direct export partition changed."
        case .invalidChunk: return "A direct export chunk failed validation."
        case .invalidPartition: return "A direct export partition failed validation."
        case .incompleteTransfer: return "The direct export is incomplete."
        case .invalidFinalization: return "The direct export finalization did not match the durable corpus."
        case .cancelled: return "The direct export was cancelled."
        }
    }
}

public struct DirectRawReceiveArtifact: Equatable, Sendable {
    public let fileURL: URL
    public let status: String
    public let sha256: String
    public let byteCount: Int64
    public let dateRangeStart: String
    public let dateRangeEnd: String
    public let totalDays: Int
    public let profile: DirectRawProfile

    public init(
        fileURL: URL,
        status: String,
        sha256: String,
        byteCount: Int64,
        dateRangeStart: String,
        dateRangeEnd: String,
        totalDays: Int,
        profile: DirectRawProfile
    ) {
        self.fileURL = fileURL
        self.status = status
        self.sha256 = sha256
        self.byteCount = byteCount
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.totalDays = totalDays
        self.profile = profile
    }
}

private struct DirectRawReceiveJournal: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let request: DirectExportRequest
    let accepted: DirectExportAccepted
    let session: DirectTransferSession
    var manifests: [String: DirectRawDayManifest]
    var committedPartitions: [DirectTransferPartition]
    var updatedAt: Date
}

/// Durable, partition-checkpointed raw receiver. Corpus bytes remain in bounded
/// partition files until final response assembly, avoiding corpus-sized memory.
public actor DirectRawReceiver {
    private struct PendingPartition {
        let descriptor: DirectTransferPartition
        let temporaryURL: URL
        var nextSequence: Int
        var receivedBytes: Int64
    }

    private let layout: DirectClientStorageLayout
    private let jobStore: DirectJobStore
    private let fileManager: FileManager
    private var journal: DirectRawReceiveJournal?
    private var pending: PendingPartition?

    public init(
        layout: DirectClientStorageLayout,
        jobStore: DirectJobStore,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.jobStore = jobStore
        self.fileManager = fileManager
    }

    public func prepare(
        request: DirectExportRequest,
        accepted: DirectExportAccepted,
        session: DirectTransferSession
    ) async throws {
        guard request.jobID == accepted.jobID,
              request.jobID == session.jobID,
              session.peerBinding == accepted.peerBinding,
              accepted.resolvedDateIdentifiers.count <= 100_000,
              accepted.resolvedDateIdentifiers == accepted.resolvedDateIdentifiers.sorted(),
              Set(accepted.resolvedDateIdentifiers).count == accepted.resolvedDateIdentifiers.count,
              accepted.resolvedDateIdentifiers.allSatisfy(Self.isSourceDate),
              try DirectRequestFingerprint.make(for: request) == session.requestFingerprint else {
            throw DirectRawReceiverError.sessionChanged
        }
        let directory = try sessionDirectory(jobID: request.jobID)
        let journalURL = directory.appendingPathComponent("journal.json")
        if fileManager.fileExists(atPath: journalURL.path) {
            let persisted = try JSONDecoder.healthMdDirect.decode(
                DirectRawReceiveJournal.self,
                from: Data(contentsOf: journalURL)
            )
            guard persisted.request == request else { throw DirectRawReceiverError.requestChanged }
            guard persisted.session == session,
                  persisted.accepted.peerBinding == accepted.peerBinding,
                  persisted.accepted.resolvedDateIdentifiers == accepted.resolvedDateIdentifiers,
                  persisted.accepted.sourceDeviceName == accepted.sourceDeviceName,
                  persisted.accepted.resolvedCanonicalSelection == accepted.resolvedCanonicalSelection else {
                throw DirectRawReceiverError.sessionChanged
            }
            journal = persisted
        } else {
            let created = DirectRawReceiveJournal(
                version: DirectRawReceiveJournal.currentVersion,
                request: request,
                accepted: accepted,
                session: session,
                manifests: [:],
                committedPartitions: [],
                updatedAt: Date()
            )
            journal = created
            try saveJournal(created)
        }
        try? fileManager.removeItem(at: directory.appendingPathComponent("pending.partition"))
        pending = nil

        var record = try await jobStore.load(jobID: request.jobID)
        record.state = .preparing
        record.updatedAt = Date()
        record.peerBinding = session.peerBinding
        record.sessionID = session.sessionID
        record.requestFingerprint = session.requestFingerprint
        record.totalDays = accepted.resolvedDateIdentifiers.count
        record.message = "iPhone accepted the direct raw export."
        try await jobStore.save(record)
    }

    public func store(manifest: DirectRawDayManifest) async throws {
        guard var journal else { throw DirectRawReceiverError.incompleteTransfer }
        _ = try DirectRawDayManifest(
            jobID: manifest.jobID,
            date: manifest.date,
            status: manifest.status,
            captureStatus: manifest.captureStatus,
            sampleCount: manifest.sampleCount,
            recordCount: manifest.recordCount,
            queryStatusCounts: manifest.queryStatusCounts,
            integrityWarningCount: manifest.integrityWarningCount,
            integrityWarningCodes: manifest.integrityWarningCodes,
            partialFailureCount: manifest.partialFailureCount,
            partialFailureTypes: manifest.partialFailureTypes,
            failureCode: manifest.failureCode,
            healthDataByteCount: manifest.healthDataByteCount,
            healthDataSHA256: manifest.healthDataSHA256
        )
        guard manifest.integrityWarningCodes.count <= 10_000,
              manifest.partialFailureTypes.count <= 10_000,
              manifest.jobID == journal.request.jobID,
              journal.accepted.resolvedDateIdentifiers.contains(manifest.date) else {
            throw DirectRawReceiverError.unexpectedDate(manifest.date)
        }
        if let existing = journal.manifests[manifest.date], existing != manifest {
            throw DirectRawReceiverError.manifestChanged(manifest.date)
        }
        journal.manifests[manifest.date] = manifest
        journal.updatedAt = Date()
        self.journal = journal
        try saveJournal(journal)
    }

    public func disposition(for open: DirectTransferOpen) async throws -> DirectTransferDisposition {
        guard let journal else { throw DirectRawReceiverError.incompleteTransfer }
        try validate(open: open, against: journal)
        let descriptor = open.partition
        if descriptor.index < journal.committedPartitions.count {
            let committed = journal.committedPartitions[descriptor.index]
            guard committed == descriptor else { throw DirectRawReceiverError.partitionChanged }
            return try DirectTransferDisposition(
                sessionID: open.session.sessionID,
                jobID: open.session.jobID,
                partitionIndex: descriptor.index,
                partitionSHA256: descriptor.sha256,
                disposition: .alreadyCommitted,
                message: "Partition already committed by the durable CLI receiver."
            )
        }
        guard descriptor.index == journal.committedPartitions.count else {
            throw DirectRawReceiverError.partitionOutOfOrder
        }
        let temporaryURL = try sessionDirectory(jobID: open.session.jobID)
            .appendingPathComponent("pending.partition")
        fileManager.createFile(atPath: temporaryURL.path, contents: nil)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
        pending = PendingPartition(
            descriptor: descriptor,
            temporaryURL: temporaryURL,
            nextSequence: 1,
            receivedBytes: 0
        )
        return try DirectTransferDisposition(
            sessionID: open.session.sessionID,
            jobID: open.session.jobID,
            partitionIndex: descriptor.index,
            partitionSHA256: descriptor.sha256,
            disposition: .needed
        )
    }

    public func receive(_ chunk: DirectTransferChunk) throws -> DirectTransferChunkAcknowledgement {
        guard var pending,
              chunk.transferID == pending.descriptor.transferID,
              chunk.sequence == pending.nextSequence,
              DirectTransferFile.sha256Hex(chunk.data) == chunk.sha256,
              pending.receivedBytes + Int64(chunk.data.count) <= pending.descriptor.byteCount else {
            throw DirectRawReceiverError.invalidChunk
        }
        let handle = try FileHandle(forWritingTo: pending.temporaryURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: chunk.data)
        try handle.synchronize()
        pending.nextSequence += 1
        pending.receivedBytes += Int64(chunk.data.count)
        self.pending = pending
        return try DirectTransferChunkAcknowledgement(
            transferID: chunk.transferID,
            sequence: chunk.sequence,
            accepted: true,
            sha256: chunk.sha256
        )
    }

    public func commit(
        _ complete: DirectTransferPartitionComplete
    ) async throws -> DirectTransferPartitionAcknowledgement {
        guard var journal,
              let pending,
              complete.sessionID == journal.session.sessionID,
              complete.jobID == journal.request.jobID,
              complete.partitionIndex == pending.descriptor.index,
              complete.transferID == pending.descriptor.transferID,
              complete.partitionSHA256 == pending.descriptor.sha256,
              pending.nextSequence - 1 == pending.descriptor.chunkCount,
              pending.receivedBytes == pending.descriptor.byteCount else {
            throw DirectRawReceiverError.invalidPartition
        }
        let inspected = try DirectTransferFile.inspect(pending.temporaryURL)
        guard inspected.totalBytes == pending.descriptor.byteCount,
              inspected.sha256 == pending.descriptor.sha256 else {
            throw DirectRawReceiverError.invalidPartition
        }
        let destination = try partitionURL(
            jobID: journal.request.jobID,
            index: pending.descriptor.index
        )
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: pending.temporaryURL, to: destination)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        journal.committedPartitions.append(pending.descriptor)
        journal.updatedAt = Date()
        self.journal = journal
        self.pending = nil
        try saveJournal(journal)

        var record = try await jobStore.load(jobID: journal.request.jobID)
        record.state = .transferring
        record.updatedAt = Date()
        record.committedPartitions = journal.committedPartitions.count
        record.committedBytes = journal.committedPartitions.reduce(0) { $0 + $1.byteCount }
        record.processedDays = completedDayCount(journal)
        record.message = "Committed direct corpus partition \(pending.descriptor.index + 1)."
        try await jobStore.save(record)

        return try DirectTransferPartitionAcknowledgement(
            sessionID: complete.sessionID,
            jobID: complete.jobID,
            partitionIndex: complete.partitionIndex,
            transferID: complete.transferID,
            partitionSHA256: complete.partitionSHA256,
            accepted: true
        )
    }

    public func finalize(_ finalize: DirectTransferFinalize) async throws -> DirectRawReceiveArtifact {
        guard let journal,
              finalize.sessionID == journal.session.sessionID,
              finalize.jobID == journal.request.jobID,
              finalize.requestFingerprint == journal.session.requestFingerprint,
              finalize.totalPartitions == journal.committedPartitions.count,
              finalize.totalBytes == journal.committedPartitions.reduce(0, { $0 + $1.byteCount }),
              finalize.finalPartitionSHA256 == journal.committedPartitions.last?.sha256 else {
            throw DirectRawReceiverError.invalidFinalization
        }
        try validateCompleteCorpus(journal)
        let artifact = try assembleResponse(journal)

        var record = try await jobStore.load(jobID: journal.request.jobID)
        record.state = .awaitingPeerAcknowledgement
        record.updatedAt = Date()
        record.committedPartitions = journal.committedPartitions.count
        record.committedBytes = finalize.totalBytes
        record.processedDays = journal.accepted.resolvedDateIdentifiers.count
        record.totalDays = journal.accepted.resolvedDateIdentifiers.count
        record.message = "Direct raw response committed; awaiting iPhone acknowledgement."
        record.responseArtifact = try DirectResponseArtifact(
            relativePath: artifact.fileURL.lastPathComponent,
            byteCount: artifact.byteCount,
            sha256: artifact.sha256,
            dateRangeStart: artifact.dateRangeStart,
            dateRangeEnd: artifact.dateRangeEnd,
            totalDays: artifact.totalDays
        )
        try await jobStore.save(record)
        return artifact
    }

    public func acknowledgePeerCompletion(jobID: UUID) async throws {
        var record = try await jobStore.load(jobID: jobID)
        guard record.state == .awaitingPeerAcknowledgement,
              record.responseArtifact != nil else {
            throw DirectRawReceiverError.invalidFinalization
        }
        record.state = .completed
        record.updatedAt = Date()
        record.message = "Direct raw export completed and acknowledged by iPhone."
        try await jobStore.save(record)
    }

    public func artifact(jobID: UUID) async throws -> DirectRawReceiveArtifact {
        let record = try await jobStore.load(jobID: jobID)
        guard let artifact = record.responseArtifact,
              let profile = record.request.rawProfile else {
            throw DirectRawReceiverError.incompleteTransfer
        }
        let fileURL = layout.responseSpoolsURL
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(artifact.relativePath)
        let inspected = try DirectTransferFile.inspect(fileURL)
        guard inspected.totalBytes == artifact.byteCount,
              inspected.sha256 == artifact.sha256 else {
            throw DirectRawReceiverError.invalidFinalization
        }
        return DirectRawReceiveArtifact(
            fileURL: fileURL,
            status: record.state == .completed ? responseStatus(for: try loadJournal(jobID: jobID)) : record.state.rawValue,
            sha256: artifact.sha256,
            byteCount: artifact.byteCount,
            dateRangeStart: artifact.dateRangeStart,
            dateRangeEnd: artifact.dateRangeEnd,
            totalDays: artifact.totalDays,
            profile: profile
        )
    }

    public func cancel(jobID: UUID, message: String = "Direct export cancelled by the CLI.") async throws {
        var record = try await jobStore.load(jobID: jobID)
        record.state = .cancelled
        record.updatedAt = Date()
        record.message = message
        try await jobStore.save(record)
        pending = nil
    }

    private func validate(
        open: DirectTransferOpen,
        against journal: DirectRawReceiveJournal
    ) throws {
        _ = try DirectTransferSession(
            protocolVersion: open.session.protocolVersion,
            sessionID: open.session.sessionID,
            jobID: open.session.jobID,
            requestFingerprint: open.session.requestFingerprint,
            peerBinding: open.session.peerBinding,
            partitionTargetBytes: open.session.partitionTargetBytes,
            createdAt: open.session.createdAt
        )
        _ = try DirectTransferPartition(
            index: open.partition.index,
            transferID: open.partition.transferID,
            sourceDates: open.partition.sourceDates,
            byteCount: open.partition.byteCount,
            chunkCount: open.partition.chunkCount,
            sha256: open.partition.sha256,
            previousSHA256: open.partition.previousSHA256,
            itemSegment: open.partition.itemSegment
        )
        guard open.session == journal.session,
              let segment = open.partition.itemSegment,
              journal.accepted.resolvedDateIdentifiers.contains(segment.itemID),
              let manifest = journal.manifests[segment.itemID],
              manifest.healthDataByteCount == segment.itemByteCount,
              manifest.healthDataSHA256 != nil else {
            throw DirectRawReceiverError.invalidPartition
        }
        let expectedPrevious = journal.committedPartitions.last?.sha256
        if open.partition.index == journal.committedPartitions.count,
           open.partition.previousSHA256 != expectedPrevious {
            throw DirectRawReceiverError.invalidPartition
        }
    }

    private func validateCompleteCorpus(_ journal: DirectRawReceiveJournal) throws {
        let expectedDates = journal.accepted.resolvedDateIdentifiers
        guard !expectedDates.isEmpty,
              Set(expectedDates).count == expectedDates.count,
              Set(journal.manifests.keys) == Set(expectedDates) else {
            throw DirectRawReceiverError.incompleteTransfer
        }
        var descriptorsByDate: [String: [DirectTransferPartition]] = [:]
        for descriptor in journal.committedPartitions {
            guard let segment = descriptor.itemSegment else {
                throw DirectRawReceiverError.invalidPartition
            }
            descriptorsByDate[segment.itemID, default: []].append(descriptor)
        }
        for date in expectedDates {
            guard let manifest = journal.manifests[date] else {
                throw DirectRawReceiverError.incompleteTransfer
            }
            let descriptors = descriptorsByDate[date, default: []].sorted { $0.index < $1.index }
            if manifest.healthDataByteCount == 0 {
                guard descriptors.isEmpty, manifest.healthDataSHA256 == nil else {
                    throw DirectRawReceiverError.invalidPartition
                }
                continue
            }
            var offset: Int64 = 0
            var hasher = SHA256()
            for descriptor in descriptors {
                guard let segment = descriptor.itemSegment,
                      segment.offset == offset,
                      segment.itemByteCount == manifest.healthDataByteCount else {
                    throw DirectRawReceiverError.invalidPartition
                }
                let file = try partitionURL(jobID: journal.request.jobID, index: descriptor.index)
                let handle = try FileHandle(forReadingFrom: file)
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                    hasher.update(data: data)
                }
                try handle.close()
                offset += descriptor.byteCount
            }
            guard offset == manifest.healthDataByteCount,
                  descriptors.last?.itemSegment?.isFinalSegment == true,
                  Data(hasher.finalize()).map({ String(format: "%02x", $0) }).joined() == manifest.healthDataSHA256 else {
                throw DirectRawReceiverError.invalidPartition
            }
        }
    }

    private func assembleResponse(_ journal: DirectRawReceiveJournal) throws -> DirectRawReceiveArtifact {
        guard let profile = journal.request.rawProfile else {
            throw DirectRawReceiverError.invalidFinalization
        }
        let directory = layout.responseSpoolsURL
            .appendingPathComponent(journal.request.jobID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = directory.appendingPathComponent("response.tmp")
        let destination = directory.appendingPathComponent("response.json")
        fileManager.createFile(atPath: temporary.path, contents: nil)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }

        let status = responseStatus(for: journal)
        let dates = journal.accepted.resolvedDateIdentifiers
        let manifests = dates.compactMap { journal.manifests[$0] }
        let summary = captureSummary(manifests)
        let missingDates = manifests.filter { $0.status == "missing" }.map(\.date)

        try output.write(contentsOf: Data("{".utf8))
        try writeMember("job_id", value: journal.request.jobID.uuidString.lowercased(), first: true, to: output)
        try writeMember("message", value: "iPhone direct raw export completed.", first: false, to: output)
        try writeMember("status", value: status, first: false, to: output)
        try output.write(contentsOf: Data(",\"raw_result\":{".utf8))
        try writeMember("schema", value: "healthmd.raw_result", first: true, to: output)
        try writeMember("schema_version", value: 1, first: false, to: output)
        try writeMember("profile", value: profile.rawValue, first: false, to: output)
        if let selection = journal.accepted.resolvedCanonicalSelection {
            try writeMember("canonical_selection", value: canonicalSelectionObject(selection), first: false, to: output)
        }
        try writeMember("created_at", value: Self.rfc3339(journal.request.createdAt), first: false, to: output)
        try writeMember("source_device_name", value: journal.accepted.sourceDeviceName, first: false, to: output)
        try writeMember("date_range", value: ["start": dates.first ?? "", "end": dates.last ?? ""], first: false, to: output)
        try writeMember("total_requested_days", value: dates.count, first: false, to: output)
        try output.write(contentsOf: Data(",\"days\":[".utf8))
        for (dayIndex, manifest) in manifests.enumerated() {
            if dayIndex > 0 { try output.write(contentsOf: Data(",".utf8)) }
            var day = dayObject(manifest)
            let healthDataBytes = day.removeValue(forKey: "health_data")
            var encoded = try jsonData(day)
            guard encoded.last == UInt8(ascii: "}") else { throw DirectRawReceiverError.invalidFinalization }
            encoded.removeLast()
            try output.write(contentsOf: encoded)
            if healthDataBytes != nil || manifest.healthDataByteCount > 0 {
                try output.write(contentsOf: Data(",\"health_data\":".utf8))
                for descriptor in journal.committedPartitions where descriptor.itemSegment?.itemID == manifest.date {
                    let input = try FileHandle(forReadingFrom: partitionURL(
                        jobID: journal.request.jobID,
                        index: descriptor.index
                    ))
                    while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                        try output.write(contentsOf: data)
                    }
                    try input.close()
                }
            }
            try output.write(contentsOf: Data("}".utf8))
        }
        try output.write(contentsOf: Data("]".utf8))
        try writeMember("capture_summary", value: summary, first: false, to: output)
        try writeMember("missing_dates", value: missingDates, first: false, to: output)
        try output.write(contentsOf: Data("}}".utf8))
        try output.synchronize()
        try output.close()
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let inspected = try DirectTransferFile.inspect(destination)
        return DirectRawReceiveArtifact(
            fileURL: destination,
            status: status,
            sha256: inspected.sha256,
            byteCount: inspected.totalBytes,
            dateRangeStart: dates.first ?? "",
            dateRangeEnd: dates.last ?? "",
            totalDays: dates.count,
            profile: profile
        )
    }

    private func responseStatus(for journal: DirectRawReceiveJournal) -> String {
        let partialStatuses = Set(["partial", "failed", "cancelled", "missing"])
        return journal.manifests.values.contains(where: { partialStatuses.contains($0.status) })
            ? "partial_success" : "success"
    }

    private func completedDayCount(_ journal: DirectRawReceiveJournal) -> Int {
        let completed = Set(journal.committedPartitions.compactMap { descriptor -> String? in
            guard let segment = descriptor.itemSegment, segment.isFinalSegment else { return nil }
            return segment.itemID
        })
        let empty = Set(journal.manifests.values.filter { $0.healthDataByteCount == 0 }.map(\.date))
        return completed.union(empty).count
    }

    private func captureSummary(_ manifests: [DirectRawDayManifest]) -> [String: Any] {
        var statusCounts: [String: Int] = [:]
        var queryCounts = ["success": 0, "failure": 0, "unsupported": 0, "skipped": 0, "cancelled": 0]
        var sampleCount = 0
        var recordCount = 0
        var warningCount = 0
        var partialFailureCount = 0
        for manifest in manifests {
            statusCounts[manifest.status, default: 0] += 1
            sampleCount += manifest.sampleCount
            recordCount += manifest.recordCount
            warningCount += manifest.integrityWarningCount
            partialFailureCount += manifest.partialFailureCount
            for (key, value) in manifest.queryStatusCounts { queryCounts[key, default: 0] += value }
        }
        return [
            "retained_day_count": manifests.filter { $0.healthDataByteCount > 0 }.count,
            "complete_day_count": statusCounts["complete", default: 0],
            "complete_empty_day_count": statusCounts["complete_empty", default: 0],
            "warning_day_count": statusCounts["complete_with_warnings", default: 0],
            "partial_day_count": statusCounts["partial", default: 0],
            "failed_day_count": statusCounts["failed", default: 0],
            "cancelled_day_count": statusCounts["cancelled", default: 0],
            "missing_day_count": statusCounts["missing", default: 0],
            "sample_count": sampleCount,
            "record_count": recordCount,
            "query_status_counts": queryCounts,
            "integrity_warning_count": warningCount,
            "partial_failure_count": partialFailureCount,
            "day_status_counts": statusCounts
        ]
    }

    private func dayObject(_ manifest: DirectRawDayManifest) -> [String: Any] {
        var object: [String: Any] = [
            "date": manifest.date,
            "status": manifest.status,
            "sample_count": manifest.sampleCount,
            "record_count": manifest.recordCount,
            "query_status_counts": manifest.queryStatusCounts,
            "integrity_warning_count": manifest.integrityWarningCount,
            "integrity_warning_codes": manifest.integrityWarningCodes,
            "partial_failure_count": manifest.partialFailureCount,
            "partial_failure_types": manifest.partialFailureTypes
        ]
        if let captureStatus = manifest.captureStatus { object["capture_status"] = captureStatus }
        if let failureCode = manifest.failureCode { object["failure_code"] = failureCode }
        return object
    }

    private func canonicalSelectionObject(_ selection: DirectCanonicalSelection) -> [String: Any] {
        [
            "metric_ids": selection.metricIDs,
            "source_ids": selection.sourceIDs,
            "detail_level": selection.detailLevel.rawValue,
            "object_paths": selection.objectPaths,
            "field_pointers": selection.fieldPointers
        ]
    }

    private func writeMember(
        _ key: String,
        value: Any,
        first: Bool,
        to handle: FileHandle
    ) throws {
        if !first { try handle.write(contentsOf: Data(",".utf8)) }
        try handle.write(contentsOf: try jsonData(key))
        try handle.write(contentsOf: Data(":".utf8))
        try handle.write(contentsOf: try jsonData(value))
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    private func sessionDirectory(jobID: UUID) throws -> URL {
        try layout.prepare(fileManager: fileManager)
        let directory = layout.corpusSessionsURL
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func partitionURL(jobID: UUID, index: Int) throws -> URL {
        try sessionDirectory(jobID: jobID)
            .appendingPathComponent(String(format: "partition-%08d.bin", index))
    }

    private func saveJournal(_ journal: DirectRawReceiveJournal) throws {
        let url = try sessionDirectory(jobID: journal.request.jobID)
            .appendingPathComponent("journal.json")
        try restrictedAtomicWrite(JSONEncoder.healthMdDirect.encode(journal), to: url)
    }

    private func loadJournal(jobID: UUID) throws -> DirectRawReceiveJournal {
        let url = try sessionDirectory(jobID: jobID).appendingPathComponent("journal.json")
        return try JSONDecoder.healthMdDirect.decode(
            DirectRawReceiveJournal.self,
            from: Data(contentsOf: url)
        )
    }

    private func restrictedAtomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private static func isSourceDate(_ value: String) -> Bool {
        guard value.utf8.count == 10 else { return false }
        let bytes = Array(value.utf8)
        guard bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                index == 4 || index == 7 || (48...57).contains(byte)
              }) else { return false }
        guard let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)),
              (1900...9999).contains(year),
              (1...12).contains(month) else { return false }
        let leap = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...monthDays[month - 1]).contains(day)
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
