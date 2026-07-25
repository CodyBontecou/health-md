import CryptoKit
import Foundation

/// Versioned application-level transfer used for payloads that must remain far
/// below Multipeer and manual-IP frame limits. Only each chunk is represented as
/// `Data` in a SyncMessage; the complete payload is never base64-wrapped.
enum ConnectedTransferKind: String, Codable, Equatable {
    case macExportJobV1 = "mac_export_job_v1"
    case canonicalRawResultV1 = "canonical_raw_result_v1"
    case connectedCorpusPartitionV1 = "connected_corpus_partition_v1"
}

struct ConnectedTransferManifest: Codable, Equatable {
    let kind: ConnectedTransferKind
    let jobID: UUID
    let payloadSchemaVersion: Int
    let corpusPartition: ConnectedCorpusPartitionDescriptor?

    init(
        kind: ConnectedTransferKind,
        jobID: UUID,
        payloadSchemaVersion: Int,
        corpusPartition: ConnectedCorpusPartitionDescriptor? = nil
    ) {
        self.kind = kind
        self.jobID = jobID
        self.payloadSchemaVersion = payloadSchemaVersion
        self.corpusPartition = corpusPartition
    }
}

struct ConnectedTransferStart: Codable, Equatable {
    nonisolated static let currentProtocolVersion = 1
    nonisolated static let corpusPartitionProtocolVersion = 2

    let protocolVersion: Int
    let transferID: UUID
    let manifest: ConnectedTransferManifest
    let totalBytes: Int64
    let totalChunks: Int
    let chunkBytes: Int
    let sha256: String
}

struct ConnectedTransferChunk: Codable, Equatable {
    let transferID: UUID
    let sequence: Int
    let data: Data
    let sha256: String
}

struct ConnectedTransferTransportNegotiation: Equatable, Sendable {
    let binaryFrameVersion: Int
    let maximumInFlightChunks: Int
}

/// Binary framing negotiated independently from the durable corpus protocol.
/// It removes JSON/base64 expansion while retaining per-chunk hashes and the
/// receiver's post-persistence acknowledgement contract.
nonisolated enum ConnectedTransferBinaryFrame {
    static let currentVersion = 1
    private static let magic = Data([0x48, 0x4d, 0x44, 0x43, 0x54, 0x46, 0x52, 0x4d]) // HMDCTFRM
    private static let uuidStringBytes = 36
    private static let digestBytes = 32
    private static let fixedHeaderBytes = 8 + 2 + uuidStringBytes + 4 + 4 + digestBytes

    enum FrameError: Error, Equatable {
        case invalidMagic
        case unsupportedVersion
        case invalidIdentifier
        case invalidSequence
        case invalidLength
        case invalidDigest
    }

    static func isBinaryFrame(_ data: Data) -> Bool {
        data.count >= magic.count && data.prefix(magic.count) == magic
    }

    static func encode(
        _ chunk: ConnectedTransferChunk,
        version: Int = currentVersion
    ) throws -> Data {
        guard version == currentVersion else { throw FrameError.unsupportedVersion }
        guard chunk.sequence > 0, chunk.sequence <= Int(UInt32.max) else {
            throw FrameError.invalidSequence
        }
        guard chunk.data.count <= ConnectedTransferReceiver.maximumChunkBytes else {
            throw FrameError.invalidLength
        }
        let identifier = Data(chunk.transferID.uuidString.lowercased().utf8)
        guard identifier.count == uuidStringBytes else { throw FrameError.invalidIdentifier }
        guard let digest = Data(connectedTransferHex: chunk.sha256),
              digest.count == digestBytes else {
            throw FrameError.invalidDigest
        }

        var frame = Data()
        frame.reserveCapacity(fixedHeaderBytes + chunk.data.count)
        frame.append(magic)
        frame.appendBigEndian(UInt16(version))
        frame.append(identifier)
        frame.appendBigEndian(UInt32(chunk.sequence))
        frame.appendBigEndian(UInt32(chunk.data.count))
        frame.append(digest)
        frame.append(chunk.data)
        return frame
    }

    static func decode(_ frame: Data) throws -> (version: Int, chunk: ConnectedTransferChunk) {
        guard isBinaryFrame(frame) else { throw FrameError.invalidMagic }
        guard frame.count >= fixedHeaderBytes else { throw FrameError.invalidLength }
        var offset = magic.count
        let version = Int(try frame.readBigEndianUInt16(at: &offset))
        guard version == currentVersion else { throw FrameError.unsupportedVersion }

        let identifierData = frame.subdata(in: offset..<(offset + uuidStringBytes))
        offset += uuidStringBytes
        guard let identifier = String(data: identifierData, encoding: .utf8),
              let transferID = UUID(uuidString: identifier) else {
            throw FrameError.invalidIdentifier
        }
        let sequence = Int(try frame.readBigEndianUInt32(at: &offset))
        guard sequence > 0 else { throw FrameError.invalidSequence }
        let payloadLength = Int(try frame.readBigEndianUInt32(at: &offset))
        guard payloadLength <= ConnectedTransferReceiver.maximumChunkBytes else {
            throw FrameError.invalidLength
        }
        let digestEnd = offset + digestBytes
        guard digestEnd <= frame.count else { throw FrameError.invalidLength }
        let digest = frame.subdata(in: offset..<digestEnd).hexString
        offset = digestEnd
        guard payloadLength == frame.count - offset else { throw FrameError.invalidLength }
        let payload = frame.subdata(in: offset..<frame.count)
        return (
            version,
            ConnectedTransferChunk(
                transferID: transferID,
                sequence: sequence,
                data: payload,
                sha256: digest
            )
        )
    }
}

private extension Data {
    nonisolated init?(connectedTransferHex string: String) {
        guard string.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    nonisolated mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    nonisolated func readBigEndianUInt16(at offset: inout Int) throws -> UInt16 {
        guard offset + 2 <= count else { throw ConnectedTransferBinaryFrame.FrameError.invalidLength }
        let value = self[offset..<(offset + 2)].reduce(UInt16(0)) {
            ($0 << 8) | UInt16($1)
        }
        offset += 2
        return value
    }

    nonisolated func readBigEndianUInt32(at offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= count else { throw ConnectedTransferBinaryFrame.FrameError.invalidLength }
        let value = self[offset..<(offset + 4)].reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        offset += 4
        return value
    }
}

struct ConnectedTransferAck: Codable, Equatable {
    /// Sequence zero acknowledges `ConnectedTransferStart`; chunk sequences are 1-based.
    let transferID: UUID
    let sequence: Int
    let accepted: Bool
    let sha256: String
    let message: String?
}

struct ConnectedTransferComplete: Codable, Equatable {
    let transferID: UUID
    let totalBytes: Int64
    let totalChunks: Int
    let sha256: String
}

struct ConnectedTransferFinalAck: Codable, Equatable {
    let transferID: UUID
    let accepted: Bool
    let sha256: String
    let message: String?
}

enum ConnectedTransferAbortReason: String, Codable, Equatable {
    case unsupported
    case invalidManifest = "invalid_manifest"
    case sizeLimit = "size_limit"
    case sequenceMismatch = "sequence_mismatch"
    case chunkHashMismatch = "chunk_hash_mismatch"
    case finalHashMismatch = "final_hash_mismatch"
    case decodeFailure = "decode_failure"
    case applicationRejected = "application_rejected"
    case retriesExhausted = "retries_exhausted"
    case cancelled
    case disconnected
    case timedOut = "timed_out"
}

struct ConnectedTransferAbort: Codable, Equatable {
    let transferID: UUID
    let jobID: UUID?
    let reason: ConnectedTransferAbortReason
    let message: String
}

enum ConnectedTransferSendResult {
    case success(ConnectedTransferFinalAck)
    case failure(ConnectedTransferAbort)
}

struct ConnectedTransferPreparedFile {
    let url: URL
    let totalBytes: Int64
    let sha256: String

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

enum ConnectedTransferFile {
    static func encode<T: Encodable>(_ value: T) throws -> ConnectedTransferPreparedFile {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        let url = try makeRestrictedTemporaryFile(prefix: "healthmd-transfer-source")
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            return ConnectedTransferPreparedFile(
                url: url,
                totalBytes: Int64(data.count),
                sha256: sha256Hex(data)
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    static func inspect(_ url: URL) throws -> ConnectedTransferPreparedFile {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return ConnectedTransferPreparedFile(
            url: url,
            totalBytes: size,
            sha256: Data(hasher.finalize()).hexString
        )
    }

    static func makeRestrictedTemporaryFile(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-connected-transfer", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appendingPathComponent("\(prefix)-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).hexString
    }
}

@MainActor
final class ConnectedTransferReceiver {
    nonisolated static let maximumTotalBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    nonisolated static let maximumChunkBytes = 512 * 1_024
    nonisolated static let maximumChunkCount = 8_192
    nonisolated static let maximumCorpusPartitionBytes = ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
    nonisolated static let maximumConcurrentTransfers = 4
    nonisolated static let defaultInactivityTimeout: TimeInterval = 120

    struct ReadyTransfer {
        let start: ConnectedTransferStart
        let fileURL: URL
    }

    enum StartResult {
        case acknowledgement(ConnectedTransferAck)
        case abort(ConnectedTransferAbort)
    }

    enum ChunkResult {
        case acknowledgement(ConnectedTransferAck)
        case abort(ConnectedTransferAbort)
    }

    enum CompletionResult {
        case ready(ReadyTransfer)
        /// Digest validation completed and application persistence is still in
        /// progress. A duplicate completion must wait for the durable final ACK.
        case pending
        case replay(ConnectedTransferFinalAck)
        case abort(ConnectedTransferAbort)
    }

    // Session state is owned and accessed exclusively by the main-actor receiver,
    // but the object itself must not inherit global-actor-isolated destruction.
    // Nested actor-isolated teardown re-enters the Swift back-deployed deinit
    // executor while ConnectedTransferReceiver is being destroyed on iOS.
    fileprivate nonisolated final class Session {
        let start: ConnectedTransferStart
        let fileURL: URL
        let fileHandle: FileHandle
        var expectedSequence = 1
        var receivedBytes: Int64 = 0
        var hasher = SHA256()
        var acknowledgementsBySequence: [Int: (sha256: String, acknowledgement: ConnectedTransferAck)] = [:]
        var digestValidated = false
        var timeoutTask: Task<Void, Never>?

        init(start: ConnectedTransferStart, fileURL: URL, fileHandle: FileHandle) {
            self.start = start
            self.fileURL = fileURL
            self.fileHandle = fileHandle
        }
    }

    var onTimeout: ((ConnectedTransferAbort) -> Void)?
    private let inactivityTimeout: TimeInterval
    private var sessions: [UUID: Session] = [:]
    private var recentFinalAcknowledgements: [UUID: ConnectedTransferFinalAck] = [:]
    private var recentFinalOrder: [UUID] = []

    init(inactivityTimeout: TimeInterval = ConnectedTransferReceiver.defaultInactivityTimeout) {
        self.inactivityTimeout = inactivityTimeout
    }

    // Destruction does not require actor coordination: final ownership already
    // provides exclusive access, and each resource is safe to close from deinit.
    // Opting out also avoids the Swift back-deployment runtime's broken
    // main-actor deinit path on iOS while preserving main-actor access to the API.
    nonisolated deinit {
        for session in sessions.values {
            session.timeoutTask?.cancel()
            try? session.fileHandle.close()
            try? FileManager.default.removeItem(at: session.fileURL)
        }
    }

    var activeTransferIDs: Set<UUID> { Set(sessions.keys) }

    func spooledFileURL(for transferID: UUID) -> URL? {
        sessions[transferID]?.fileURL
    }

    func receive(_ start: ConnectedTransferStart) -> StartResult {
        if let existing = sessions[start.transferID] {
            guard existing.start == start else {
                return .abort(abort(for: start, reason: .invalidManifest, message: "Transfer start changed during retry."))
            }
            resetTimeout(for: existing)
            return .acknowledgement(startAcknowledgement(for: start))
        }

        guard sessions.count < Self.maximumConcurrentTransfers else {
            return .abort(abort(
                for: start,
                reason: .applicationRejected,
                message: "Too many connected transfers are already active."
            ))
        }
        if let message = validate(start) {
            return .abort(abort(for: start, reason: .sizeLimit, message: message))
        }

        var fileURL: URL?
        do {
            let createdURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "receive")
            fileURL = createdURL
            let handle = try FileHandle(forWritingTo: createdURL)
            let session = Session(start: start, fileURL: createdURL, fileHandle: handle)
            sessions[start.transferID] = session
            resetTimeout(for: session)
            return .acknowledgement(startAcknowledgement(for: start))
        } catch {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            return .abort(abort(
                for: start,
                reason: .applicationRejected,
                message: "Could not create a protected temporary transfer file."
            ))
        }
    }

    func receive(_ chunk: ConnectedTransferChunk) -> ChunkResult {
        guard let session = sessions[chunk.transferID] else {
            return .abort(ConnectedTransferAbort(
                transferID: chunk.transferID,
                jobID: nil,
                reason: .sequenceMismatch,
                message: "No active transfer exists for this chunk."
            ))
        }

        if chunk.sequence < session.expectedSequence {
            guard let prior = session.acknowledgementsBySequence[chunk.sequence],
                  prior.sha256 == chunk.sha256,
                  ConnectedTransferFile.sha256Hex(chunk.data) == chunk.sha256 else {
                let result = abort(for: session.start, reason: .chunkHashMismatch, message: "Duplicate chunk digest changed.")
                cleanup(session: session)
                return .abort(result)
            }
            resetTimeout(for: session)
            return .acknowledgement(prior.acknowledgement)
        }

        guard chunk.sequence == session.expectedSequence else {
            return .abortAndCleanup(
                receiver: self,
                session: session,
                reason: .sequenceMismatch,
                message: "Expected chunk \(session.expectedSequence), received \(chunk.sequence)."
            )
        }
        guard chunk.data.count <= session.start.chunkBytes,
              chunk.data.count <= Self.maximumChunkBytes else {
            return .abortAndCleanup(
                receiver: self,
                session: session,
                reason: .sizeLimit,
                message: "Chunk exceeds the declared byte limit."
            )
        }

        let expectedBytes = Int(min(
            Int64(session.start.chunkBytes),
            session.start.totalBytes - session.receivedBytes
        ))
        guard expectedBytes >= 0, chunk.data.count == expectedBytes else {
            return .abortAndCleanup(
                receiver: self,
                session: session,
                reason: .sizeLimit,
                message: "Chunk length does not match the declared transfer length."
            )
        }
        let actualHash = ConnectedTransferFile.sha256Hex(chunk.data)
        guard actualHash == chunk.sha256 else {
            return .abortAndCleanup(
                receiver: self,
                session: session,
                reason: .chunkHashMismatch,
                message: "Chunk SHA-256 validation failed."
            )
        }

        do {
            try session.fileHandle.write(contentsOf: chunk.data)
        } catch {
            return .abortAndCleanup(
                receiver: self,
                session: session,
                reason: .applicationRejected,
                message: "Could not spool transfer chunk to disk."
            )
        }
        session.hasher.update(data: chunk.data)
        session.receivedBytes += Int64(chunk.data.count)
        let acknowledgement = ConnectedTransferAck(
            transferID: chunk.transferID,
            sequence: chunk.sequence,
            accepted: true,
            sha256: chunk.sha256,
            message: nil
        )
        session.acknowledgementsBySequence[chunk.sequence] = (
            sha256: chunk.sha256,
            acknowledgement: acknowledgement
        )
        session.expectedSequence += 1
        resetTimeout(for: session)
        return .acknowledgement(acknowledgement)
    }

    func receive(_ complete: ConnectedTransferComplete) -> CompletionResult {
        if let replay = recentFinalAcknowledgements[complete.transferID] {
            return .replay(replay)
        }
        guard let session = sessions[complete.transferID] else {
            return .abort(ConnectedTransferAbort(
                transferID: complete.transferID,
                jobID: nil,
                reason: .sequenceMismatch,
                message: "No active transfer exists for completion."
            ))
        }
        guard !session.digestValidated else {
            return .pending
        }
        guard complete.totalBytes == session.start.totalBytes,
              complete.totalChunks == session.start.totalChunks,
              complete.sha256 == session.start.sha256,
              session.receivedBytes == session.start.totalBytes,
              session.expectedSequence - 1 == session.start.totalChunks else {
            let result = abort(for: session.start, reason: .sizeLimit, message: "Completion totals do not match the received transfer.")
            cleanup(session: session)
            return .abort(result)
        }

        let finalHash = Data(session.hasher.finalize()).hexString
        guard finalHash == session.start.sha256 else {
            let result = abort(for: session.start, reason: .finalHashMismatch, message: "Final SHA-256 validation failed.")
            cleanup(session: session)
            return .abort(result)
        }

        do {
            try session.fileHandle.synchronize()
            try session.fileHandle.close()
        } catch {
            let result = abort(for: session.start, reason: .applicationRejected, message: "Could not finalize the temporary transfer file.")
            cleanup(session: session)
            return .abort(result)
        }
        session.digestValidated = true
        session.timeoutTask?.cancel()
        return .ready(ReadyTransfer(start: session.start, fileURL: session.fileURL))
    }

    /// Called only after the verified file has decoded and the owning request/job
    /// accepted it. This is the final acceptance boundary used for quota accounting.
    func finish(
        transferID: UUID,
        accepted: Bool,
        reason: ConnectedTransferAbortReason = .applicationRejected,
        message: String? = nil
    ) -> ConnectedTransferFinalAck? {
        guard let session = sessions[transferID], session.digestValidated else { return nil }
        sessions.removeValue(forKey: transferID)
        session.timeoutTask?.cancel()
        try? FileManager.default.removeItem(at: session.fileURL)
        let acknowledgement = ConnectedTransferFinalAck(
            transferID: transferID,
            accepted: accepted,
            sha256: session.start.sha256,
            message: message ?? (accepted ? nil : reason.rawValue)
        )
        remember(acknowledgement)
        return acknowledgement
    }

    @discardableResult
    func cancel(
        transferID: UUID,
        reason: ConnectedTransferAbortReason,
        message: String
    ) -> ConnectedTransferAbort? {
        guard let session = sessions[transferID] else { return nil }
        let result = abort(for: session.start, reason: reason, message: message)
        cleanup(session: session)
        return result
    }

    @discardableResult
    func cancel(
        jobID: UUID,
        reason: ConnectedTransferAbortReason,
        message: String
    ) -> [ConnectedTransferAbort] {
        let matchingSessions = sessions.values.filter { $0.start.manifest.jobID == jobID }
        return matchingSessions.map { session in
            let result = abort(for: session.start, reason: reason, message: message)
            cleanup(session: session)
            return result
        }
    }

    func cancelAll(reason: ConnectedTransferAbortReason = .disconnected) {
        for session in Array(sessions.values) {
            cleanup(session: session)
        }
        sessions.removeAll()
    }

    private func validate(_ start: ConnectedTransferStart) -> String? {
        let isLegacy = start.protocolVersion == ConnectedTransferStart.currentProtocolVersion
        let isCorpusPartition = start.protocolVersion == ConnectedTransferStart.corpusPartitionProtocolVersion
            && start.manifest.kind == .connectedCorpusPartitionV1
            && start.manifest.corpusPartition != nil
        guard isLegacy || isCorpusPartition else {
            return "Unsupported connected-transfer protocol version."
        }
        if isLegacy {
            guard start.transferID == start.manifest.jobID,
                  start.manifest.kind != .connectedCorpusPartitionV1,
                  start.manifest.corpusPartition == nil else {
                return "Transfer and job identifiers must match."
            }
        } else {
            guard let descriptor = start.manifest.corpusPartition,
                  descriptor.jobID == start.manifest.jobID,
                  descriptor.byteCount == start.totalBytes,
                  descriptor.sha256 == start.sha256,
                  start.transferID != start.manifest.jobID else {
                return "Corpus partition manifest is inconsistent."
            }
        }
        let maximumBytes = isCorpusPartition ? Self.maximumCorpusPartitionBytes : Self.maximumTotalBytes
        guard start.totalBytes >= 0, start.totalBytes <= maximumBytes else {
            return "Declared transfer size exceeds the receiver limit."
        }
        guard start.chunkBytes > 0, start.chunkBytes <= Self.maximumChunkBytes else {
            return "Declared chunk size exceeds the receiver limit."
        }
        let calculatedChunks = start.totalBytes == 0
            ? 0
            : Int((start.totalBytes + Int64(start.chunkBytes) - 1) / Int64(start.chunkBytes))
        guard start.totalChunks == calculatedChunks,
              start.totalChunks >= 0,
              start.totalChunks <= Self.maximumChunkCount else {
            return "Declared chunk count is invalid or exceeds the receiver limit."
        }
        guard start.sha256.isSHA256Hex else {
            return "Declared transfer digest is invalid."
        }
        return nil
    }

    private func startAcknowledgement(for start: ConnectedTransferStart) -> ConnectedTransferAck {
        ConnectedTransferAck(
            transferID: start.transferID,
            sequence: 0,
            accepted: true,
            sha256: start.sha256,
            message: nil
        )
    }

    fileprivate func abort(
        for start: ConnectedTransferStart,
        reason: ConnectedTransferAbortReason,
        message: String
    ) -> ConnectedTransferAbort {
        ConnectedTransferAbort(
            transferID: start.transferID,
            jobID: start.manifest.jobID,
            reason: reason,
            message: message
        )
    }

    private func resetTimeout(for session: Session) {
        session.timeoutTask?.cancel()
        guard inactivityTimeout > 0 else { return }
        let transferID = session.start.transferID
        let nanoseconds = UInt64(max(inactivityTimeout, 0.001) * 1_000_000_000)
        session.timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  let current = self.sessions[transferID], current === session else { return }
            let result = self.abort(
                for: current.start,
                reason: .timedOut,
                message: "Connected transfer timed out waiting for validated progress."
            )
            self.cleanup(session: current)
            self.onTimeout?(result)
        }
    }

    fileprivate func cleanup(session: Session) {
        session.timeoutTask?.cancel()
        try? session.fileHandle.close()
        try? FileManager.default.removeItem(at: session.fileURL)
        sessions.removeValue(forKey: session.start.transferID)
    }

    private func remember(_ acknowledgement: ConnectedTransferFinalAck) {
        recentFinalAcknowledgements[acknowledgement.transferID] = acknowledgement
        recentFinalOrder.removeAll { $0 == acknowledgement.transferID }
        recentFinalOrder.append(acknowledgement.transferID)
        while recentFinalOrder.count > 32 {
            let removed = recentFinalOrder.removeFirst()
            recentFinalAcknowledgements.removeValue(forKey: removed)
        }
    }
}

private extension ConnectedTransferReceiver.ChunkResult {
    @MainActor
    static func abortAndCleanup(
        receiver: ConnectedTransferReceiver,
        session: ConnectedTransferReceiver.Session,
        reason: ConnectedTransferAbortReason,
        message: String
    ) -> Self {
        let result = receiver.abort(for: session.start, reason: reason, message: message)
        receiver.cleanup(session: session)
        return .abort(result)
    }
}

private extension Data {
    nonisolated var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

private extension String {
    var isSHA256Hex: Bool {
        count == 64 && unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }
}
