import CryptoKit
import Darwin
import Foundation

public enum DirectTransferLimits {
    public static let chunkBytes = 512 * 1_024
    public static let minimumPartitionBytes: Int64 = 32 * 1_024 * 1_024
    public static let preferredPartitionBytes: Int64 = 48 * 1_024 * 1_024
    public static let maximumPartitionBytes: Int64 = 64 * 1_024 * 1_024
    public static let maximumInFlightChunks = 4
}

public struct DirectTransferCapabilities: Codable, Equatable, Sendable {
    public let protocolVersions: [Int]
    public let binaryFrameVersions: [Int]
    public let minimumPartitionBytes: Int64
    public let preferredPartitionBytes: Int64
    public let maximumPartitionBytes: Int64
    public let maximumInFlightChunks: Int

    public static let current = DirectTransferCapabilities(
        protocolVersions: [1],
        binaryFrameVersions: [DirectTransferBinaryFrame.currentVersion],
        minimumPartitionBytes: DirectTransferLimits.minimumPartitionBytes,
        preferredPartitionBytes: DirectTransferLimits.preferredPartitionBytes,
        maximumPartitionBytes: DirectTransferLimits.maximumPartitionBytes,
        maximumInFlightChunks: DirectTransferLimits.maximumInFlightChunks
    )

    public init(
        protocolVersions: [Int],
        binaryFrameVersions: [Int],
        minimumPartitionBytes: Int64,
        preferredPartitionBytes: Int64,
        maximumPartitionBytes: Int64,
        maximumInFlightChunks: Int
    ) {
        self.protocolVersions = Array(Set(protocolVersions)).sorted()
        self.binaryFrameVersions = Array(Set(binaryFrameVersions)).sorted()
        self.minimumPartitionBytes = minimumPartitionBytes
        self.preferredPartitionBytes = preferredPartitionBytes
        self.maximumPartitionBytes = maximumPartitionBytes
        self.maximumInFlightChunks = maximumInFlightChunks
    }

    public func negotiated(with peer: Self) -> DirectTransferNegotiation? {
        guard let protocolVersion = Set(protocolVersions).intersection(peer.protocolVersions).max(),
              let binaryFrameVersion = Set(binaryFrameVersions).intersection(peer.binaryFrameVersions).max() else {
            return nil
        }
        let minimum = max(minimumPartitionBytes, peer.minimumPartitionBytes)
        let maximum = min(maximumPartitionBytes, peer.maximumPartitionBytes)
        guard minimum <= maximum else { return nil }
        let preferred = min(max(preferredPartitionBytes, peer.preferredPartitionBytes), maximum)
        return DirectTransferNegotiation(
            protocolVersion: protocolVersion,
            binaryFrameVersion: binaryFrameVersion,
            partitionTargetBytes: max(minimum, preferred),
            maximumInFlightChunks: max(1, min(maximumInFlightChunks, peer.maximumInFlightChunks, 8))
        )
    }
}

public struct DirectTransferNegotiation: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let binaryFrameVersion: Int
    public let partitionTargetBytes: Int64
    public let maximumInFlightChunks: Int

    public init(
        protocolVersion: Int,
        binaryFrameVersion: Int,
        partitionTargetBytes: Int64,
        maximumInFlightChunks: Int
    ) {
        self.protocolVersion = protocolVersion
        self.binaryFrameVersion = binaryFrameVersion
        self.partitionTargetBytes = partitionTargetBytes
        self.maximumInFlightChunks = maximumInFlightChunks
    }
}

public struct DirectRequestFingerprint: Codable, Equatable, Hashable, Sendable {
    public let version: Int
    public let sha256: String

    public init(version: Int = 1, sha256: String) throws {
        guard version > 0, sha256.isHealthMdSHA256 else {
            throw DirectTransferError.invalidFingerprint
        }
        self.version = version
        self.sha256 = sha256
    }

    public static func make<T: Encodable>(for value: T) throws -> Self {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try Self(sha256: DirectTransferFile.sha256Hex(encoder.encode(value)))
    }
}

public struct DirectTransferSession: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let sessionID: UUID
    public let jobID: UUID
    public let requestFingerprint: DirectRequestFingerprint
    public let peerBinding: DirectPeerBinding
    public let partitionTargetBytes: Int64
    public let createdAt: Date

    public init(
        protocolVersion: Int = 1,
        sessionID: UUID,
        jobID: UUID,
        requestFingerprint: DirectRequestFingerprint,
        peerBinding: DirectPeerBinding,
        partitionTargetBytes: Int64,
        createdAt: Date
    ) throws {
        guard partitionTargetBytes >= DirectTransferLimits.minimumPartitionBytes,
              partitionTargetBytes <= DirectTransferLimits.maximumPartitionBytes else {
            throw DirectTransferError.invalidPartitionSize
        }
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.jobID = jobID
        self.requestFingerprint = requestFingerprint
        self.peerBinding = peerBinding
        self.partitionTargetBytes = partitionTargetBytes
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
    }
}

public struct DirectTransferItemSegment: Codable, Equatable, Hashable, Sendable {
    public let itemID: String
    public let offset: Int64
    public let itemByteCount: Int64
    public let isFinalSegment: Bool

    public init(
        itemID: String,
        offset: Int64,
        itemByteCount: Int64,
        isFinalSegment: Bool
    ) throws {
        guard !itemID.isEmpty,
              itemID.utf8.count <= 128,
              offset >= 0,
              itemByteCount >= 0,
              offset <= itemByteCount else {
            throw DirectTransferError.invalidItemSegment
        }
        self.itemID = itemID
        self.offset = offset
        self.itemByteCount = itemByteCount
        self.isFinalSegment = isFinalSegment
    }
}

public struct DirectTransferPartition: Codable, Equatable, Hashable, Sendable {
    public let index: Int
    public let transferID: UUID
    public let sourceDates: [String]
    public let byteCount: Int64
    public let chunkCount: Int
    public let sha256: String
    public let previousSHA256: String?
    /// A logical raw day can span any number of bounded physical partitions.
    public let itemSegment: DirectTransferItemSegment?

    public init(
        index: Int,
        transferID: UUID,
        sourceDates: [String],
        byteCount: Int64,
        chunkCount: Int,
        sha256: String,
        previousSHA256: String?,
        itemSegment: DirectTransferItemSegment? = nil
    ) throws {
        guard index >= 0 else { throw DirectTransferError.invalidPartitionIndex }
        guard byteCount >= 0, byteCount <= DirectTransferLimits.maximumPartitionBytes else {
            throw DirectTransferError.invalidPartitionSize
        }
        guard chunkCount >= 0,
              chunkCount <= Int((DirectTransferLimits.maximumPartitionBytes + Int64(DirectTransferLimits.chunkBytes) - 1) / Int64(DirectTransferLimits.chunkBytes)) else {
            throw DirectTransferError.invalidChunk
        }
        guard sha256.isHealthMdSHA256,
              previousSHA256.map(\.isHealthMdSHA256) ?? true else {
            throw DirectTransferError.invalidDigest
        }
        guard index != 0 || previousSHA256 == nil else {
            throw DirectTransferError.invalidDigestChain
        }
        if let itemSegment {
            guard sourceDates == [itemSegment.itemID],
                  itemSegment.offset + byteCount <= itemSegment.itemByteCount,
                  itemSegment.isFinalSegment == (itemSegment.offset + byteCount == itemSegment.itemByteCount) else {
                throw DirectTransferError.invalidItemSegment
            }
        }
        self.index = index
        self.transferID = transferID
        self.sourceDates = sourceDates
        self.byteCount = byteCount
        self.chunkCount = chunkCount
        self.sha256 = sha256
        self.previousSHA256 = previousSHA256
        self.itemSegment = itemSegment
    }
}

public struct DirectTransferOpen: Codable, Equatable, Sendable {
    public let session: DirectTransferSession
    public let partition: DirectTransferPartition

    public init(session: DirectTransferSession, partition: DirectTransferPartition) throws {
        guard session.sessionID != partition.transferID else {
            throw DirectTransferError.invalidIdentifier
        }
        self.session = session
        self.partition = partition
    }
}

public enum DirectTransferDispositionKind: String, Codable, Equatable, Sendable {
    case needed
    case alreadyCommitted = "already_committed"
    case rejected
}

public struct DirectTransferDisposition: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let jobID: UUID
    public let partitionIndex: Int
    public let partitionSHA256: String
    public let disposition: DirectTransferDispositionKind
    public let message: String?

    public init(
        sessionID: UUID,
        jobID: UUID,
        partitionIndex: Int,
        partitionSHA256: String,
        disposition: DirectTransferDispositionKind,
        message: String? = nil
    ) throws {
        guard partitionIndex >= 0, partitionSHA256.isHealthMdSHA256 else {
            throw DirectTransferError.invalidDigest
        }
        self.sessionID = sessionID
        self.jobID = jobID
        self.partitionIndex = partitionIndex
        self.partitionSHA256 = partitionSHA256
        self.disposition = disposition
        self.message = message
    }
}

public struct DirectTransferChunk: Codable, Equatable, Sendable {
    public let transferID: UUID
    public let sequence: Int
    public let data: Data
    public let sha256: String

    public init(transferID: UUID, sequence: Int, data: Data, sha256: String) throws {
        guard sequence > 0,
              data.count <= DirectTransferLimits.chunkBytes,
              sha256.isHealthMdSHA256 else {
            throw DirectTransferError.invalidChunk
        }
        self.transferID = transferID
        self.sequence = sequence
        self.data = data
        self.sha256 = sha256
    }
}

public struct DirectTransferChunkAcknowledgement: Codable, Equatable, Sendable {
    public let transferID: UUID
    public let sequence: Int
    public let accepted: Bool
    public let sha256: String
    public let message: String?

    public init(
        transferID: UUID,
        sequence: Int,
        accepted: Bool,
        sha256: String,
        message: String? = nil
    ) throws {
        guard sequence >= 0, sha256.isHealthMdSHA256 else {
            throw DirectTransferError.invalidChunk
        }
        self.transferID = transferID
        self.sequence = sequence
        self.accepted = accepted
        self.sha256 = sha256
        self.message = message
    }
}

public struct DirectTransferPartitionComplete: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let jobID: UUID
    public let partitionIndex: Int
    public let transferID: UUID
    public let partitionSHA256: String

    public init(
        sessionID: UUID,
        jobID: UUID,
        partitionIndex: Int,
        transferID: UUID,
        partitionSHA256: String
    ) throws {
        guard partitionIndex >= 0, partitionSHA256.isHealthMdSHA256 else {
            throw DirectTransferError.invalidDigest
        }
        self.sessionID = sessionID
        self.jobID = jobID
        self.partitionIndex = partitionIndex
        self.transferID = transferID
        self.partitionSHA256 = partitionSHA256
    }
}

public struct DirectTransferPartitionAcknowledgement: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let jobID: UUID
    public let partitionIndex: Int
    public let transferID: UUID
    public let partitionSHA256: String
    public let accepted: Bool
    public let message: String?

    public init(
        sessionID: UUID,
        jobID: UUID,
        partitionIndex: Int,
        transferID: UUID,
        partitionSHA256: String,
        accepted: Bool,
        message: String? = nil
    ) throws {
        guard partitionIndex >= 0, partitionSHA256.isHealthMdSHA256 else {
            throw DirectTransferError.invalidDigest
        }
        self.sessionID = sessionID
        self.jobID = jobID
        self.partitionIndex = partitionIndex
        self.transferID = transferID
        self.partitionSHA256 = partitionSHA256
        self.accepted = accepted
        self.message = message
    }
}

public struct DirectExportOutcome: Codable, Equatable, Sendable {
    public let status: String
    public let successCount: Int
    public let totalCount: Int
    public let failedDateIdentifiers: [String]

    public init(
        status: String,
        successCount: Int,
        totalCount: Int,
        failedDateIdentifiers: [String] = []
    ) throws {
        guard ["success", "partial_success"].contains(status),
              successCount >= 0,
              totalCount >= successCount else {
            throw DirectTransferError.invalidFinalization
        }
        self.status = status
        self.successCount = successCount
        self.totalCount = totalCount
        self.failedDateIdentifiers = failedDateIdentifiers
    }
}

public struct DirectTransferFinalize: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let jobID: UUID
    public let requestFingerprint: DirectRequestFingerprint
    public let totalPartitions: Int
    public let totalBytes: Int64
    public let finalPartitionSHA256: String?
    public let outcome: DirectExportOutcome?

    public init(
        sessionID: UUID,
        jobID: UUID,
        requestFingerprint: DirectRequestFingerprint,
        totalPartitions: Int,
        totalBytes: Int64,
        finalPartitionSHA256: String?,
        outcome: DirectExportOutcome? = nil
    ) throws {
        guard totalPartitions >= 0, totalBytes >= 0,
              finalPartitionSHA256.map(\.isHealthMdSHA256) ?? true else {
            throw DirectTransferError.invalidFinalization
        }
        self.sessionID = sessionID
        self.jobID = jobID
        self.requestFingerprint = requestFingerprint
        self.totalPartitions = totalPartitions
        self.totalBytes = totalBytes
        self.finalPartitionSHA256 = finalPartitionSHA256
        self.outcome = outcome
    }
}

public struct DirectTransferFinalAcknowledgement: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let jobID: UUID
    public let accepted: Bool
    public let totalPartitions: Int
    public let totalBytes: Int64
    public let finalPartitionSHA256: String?
    public let responseByteCount: Int64?
    public let responseSHA256: String?
    public let message: String?

    public init(
        sessionID: UUID,
        jobID: UUID,
        accepted: Bool,
        totalPartitions: Int,
        totalBytes: Int64,
        finalPartitionSHA256: String?,
        responseByteCount: Int64? = nil,
        responseSHA256: String? = nil,
        message: String? = nil
    ) throws {
        guard totalPartitions >= 0, totalBytes >= 0,
              finalPartitionSHA256.map(\.isHealthMdSHA256) ?? true,
              responseSHA256.map(\.isHealthMdSHA256) ?? true else {
            throw DirectTransferError.invalidFinalization
        }
        self.sessionID = sessionID
        self.jobID = jobID
        self.accepted = accepted
        self.totalPartitions = totalPartitions
        self.totalBytes = totalBytes
        self.finalPartitionSHA256 = finalPartitionSHA256
        self.responseByteCount = responseByteCount
        self.responseSHA256 = responseSHA256
        self.message = message
    }
}

public enum DirectTransferError: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidFingerprint
    case invalidPartitionIndex
    case invalidPartitionSize
    case invalidDigest
    case invalidDigestChain
    case invalidChunk
    case invalidFinalization
    case invalidItemSegment
    case invalidRawDayManifest
    case invalidFileManifest
    case invalidFrame
    case unsupportedFrameVersion
}

public enum DirectTransferBinaryFrame {
    public static let currentVersion = 1
    private static let magic = Data([0x48, 0x4d, 0x44, 0x44, 0x49, 0x52, 0x43, 0x54]) // HMDDIRCT
    private static let identifierBytes = 16
    private static let digestBytes = 32
    private static let headerBytes = 8 + 2 + identifierBytes + 4 + 4 + digestBytes

    public static func isBinaryFrame(_ data: Data) -> Bool {
        data.count >= magic.count && data.prefix(magic.count) == magic
    }

    public static func encode(_ chunk: DirectTransferChunk, version: Int = currentVersion) throws -> Data {
        guard version == currentVersion else { throw DirectTransferError.unsupportedFrameVersion }
        guard let digest = Data(healthMdHex: chunk.sha256), digest.count == digestBytes else {
            throw DirectTransferError.invalidDigest
        }
        var uuid = chunk.transferID.uuid
        let identifier = withUnsafeBytes(of: &uuid) { Data($0) }
        guard identifier.count == identifierBytes else { throw DirectTransferError.invalidIdentifier }
        var frame = Data()
        frame.reserveCapacity(headerBytes + chunk.data.count)
        frame.append(magic)
        frame.appendHealthMdBigEndian(UInt16(version))
        frame.append(identifier)
        frame.appendHealthMdBigEndian(UInt32(chunk.sequence))
        frame.appendHealthMdBigEndian(UInt32(chunk.data.count))
        frame.append(digest)
        frame.append(chunk.data)
        return frame
    }

    public static func decode(_ frame: Data) throws -> (version: Int, chunk: DirectTransferChunk) {
        guard isBinaryFrame(frame), frame.count >= headerBytes else {
            throw DirectTransferError.invalidFrame
        }
        var offset = magic.count
        let version = Int(try frame.readHealthMdUInt16(at: &offset))
        guard version == currentVersion else { throw DirectTransferError.unsupportedFrameVersion }
        let identifierEnd = offset + identifierBytes
        guard identifierEnd <= frame.count else { throw DirectTransferError.invalidFrame }
        let identifier = frame.subdata(in: offset..<identifierEnd)
        offset = identifierEnd
        let uuidBytes = [UInt8](identifier)
        guard uuidBytes.count == identifierBytes else { throw DirectTransferError.invalidIdentifier }
        let transferID = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        let sequence = Int(try frame.readHealthMdUInt32(at: &offset))
        let payloadLength = Int(try frame.readHealthMdUInt32(at: &offset))
        let digestEnd = offset + digestBytes
        guard sequence > 0,
              payloadLength <= DirectTransferLimits.chunkBytes,
              digestEnd <= frame.count,
              payloadLength == frame.count - digestEnd else {
            throw DirectTransferError.invalidFrame
        }
        let digest = frame.subdata(in: offset..<digestEnd).healthMdHexString
        let payload = frame.subdata(in: digestEnd..<frame.count)
        return (version, try DirectTransferChunk(
            transferID: transferID,
            sequence: sequence,
            data: payload,
            sha256: digest
        ))
    }
}

public struct DirectTransferPreparedFile: Sendable {
    public let url: URL
    public let totalBytes: Int64
    public let sha256: String

    public init(url: URL, totalBytes: Int64, sha256: String) {
        self.url = url
        self.totalBytes = totalBytes
        self.sha256 = sha256
    }
}

public enum DirectTransferFile {
    public static func inspect(_ url: URL) throws -> DirectTransferPreparedFile {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        _ = Darwin.fcntl(descriptor, F_NOCACHE, 1)

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0, status.st_size >= 0 else {
            throw posixError()
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            throw POSIXError(.EINVAL)
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 256 * 1_024)
        var remaining = Int64(status.st_size)
        while remaining > 0 {
            let requested = Int(min(Int64(buffer.count), remaining))
            let count: Int = buffer.withUnsafeMutableBytes { bytes in
                while true {
                    let result = Darwin.read(descriptor, bytes.baseAddress, requested)
                    if result < 0, errno == EINTR { continue }
                    return result
                }
            }
            guard count > 0 else {
                if count < 0 { throw posixError() }
                throw POSIXError(.EIO)
            }
            buffer.withUnsafeBytes { bytes in
                hasher.update(bufferPointer: UnsafeRawBufferPointer(
                    start: bytes.baseAddress,
                    count: count
                ))
            }
            remaining -= Int64(count)
        }
        let trailingCount: Int = buffer.withUnsafeMutableBytes { bytes in
            while true {
                let result = Darwin.read(descriptor, bytes.baseAddress, 1)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard trailingCount == 0 else {
            if trailingCount < 0 { throw posixError() }
            throw POSIXError(.EFBIG)
        }
        return DirectTransferPreparedFile(
            url: url,
            totalBytes: Int64(status.st_size),
            sha256: Data(hasher.finalize()).healthMdHexString
        )
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    public static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).healthMdHexString
    }
}

public extension String {
    var isHealthMdSHA256: Bool {
        count == 64 && unicodeScalars.allSatisfy {
            ("0"..."9").contains(Character($0)) || ("a"..."f").contains(Character($0))
        }
    }
}

private extension Data {
    init?(healthMdHex string: String) {
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

    var healthMdHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    mutating func appendHealthMdBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func readHealthMdUInt16(at offset: inout Int) throws -> UInt16 {
        guard offset + 2 <= count else { throw DirectTransferError.invalidFrame }
        let value = self[offset..<(offset + 2)].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        offset += 2
        return value
    }

    func readHealthMdUInt32(at offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= count else { throw DirectTransferError.invalidFrame }
        let value = self[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        offset += 4
        return value
    }
}
