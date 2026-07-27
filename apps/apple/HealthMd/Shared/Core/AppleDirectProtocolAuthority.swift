import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust

enum AppleDirectProtocolEngineMode: String, Codable, CaseIterable, Sendable {
    case legacy
    case shadow
    case rust
}

enum AppleDirectProtocolStage: String, Codable, CaseIterable, Sendable {
    case compatibility
    case requestFingerprint
    case directMessage
    case transferFrame
    case transferNegotiation
}

struct AppleDirectProtocolComparisonSnapshot: Equatable, Sendable {
    let comparisons: [AppleDirectProtocolStage: Int]
    let mismatches: [AppleDirectProtocolStage: Int]
}

struct AppleDirectProtocolPin: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let engine: AppleDirectProtocolEngineMode
    let coreAPIVersion: UInt32
    let protocolAPIRevision: UInt32
    let appleApplicationProtocolVersion: UInt32
    let transferProtocolVersion: UInt32
    let coreCrateVersion: String
    /// Diagnostic provenance. Compatibility is pinned by versioned APIs, not an exact source hash.
    let coreSourceRevision: String

    init(
        version: Int = currentVersion,
        engine: AppleDirectProtocolEngineMode,
        coreAPIVersion: UInt32,
        protocolAPIRevision: UInt32,
        appleApplicationProtocolVersion: UInt32,
        transferProtocolVersion: UInt32,
        coreCrateVersion: String,
        coreSourceRevision: String
    ) throws {
        guard version == Self.currentVersion,
              engine != .legacy,
              coreAPIVersion > 0,
              protocolAPIRevision > 0,
              appleApplicationProtocolVersion > 0,
              transferProtocolVersion > 0,
              !coreCrateVersion.isEmpty,
              coreCrateVersion.utf8.count <= 64,
              !coreSourceRevision.isEmpty,
              coreSourceRevision.utf8.count <= 128 else {
            throw AppleDirectProtocolAuthorityError(stage: .compatibility)
        }
        self.version = version
        self.engine = engine
        self.coreAPIVersion = coreAPIVersion
        self.protocolAPIRevision = protocolAPIRevision
        self.appleApplicationProtocolVersion = appleApplicationProtocolVersion
        self.transferProtocolVersion = transferProtocolVersion
        self.coreCrateVersion = coreCrateVersion
        self.coreSourceRevision = coreSourceRevision
    }
}

struct AppleDirectProtocolBuildInfo: Equatable, Sendable {
    let coreAPIVersion: UInt32
    let crateVersion: String
    let coreSourceRevision: String
}

struct AppleDirectProtocolInfo: Equatable, Sendable {
    let protocolAPIRevision: UInt32
    let supportedPairingProtocolVersions: [UInt32]
    let appleApplicationProtocolVersion: UInt32
    let manualIPPort: UInt32
    let maximumControlJSONBytes: UInt64
    let transferProtocolVersion: UInt32
    let transferFrameHeaderBytes: UInt64
    let maximumChunkBytes: UInt64
    let minimumPartitionBytes: UInt64
    let preferredPartitionBytes: UInt64
    let maximumPartitionBytes: UInt64
    let maximumInFlightChunks: UInt32
    let durableJobLifetimeSeconds: UInt64
}

protocol AppleDirectProtocolRustCore: Sendable {
    func buildInfo() throws -> AppleDirectProtocolBuildInfo
    func protocolInfo() throws -> AppleDirectProtocolInfo
    func appleV1RequestFingerprint(_ bytes: Data) throws -> String
    func canonicalAppleV1Message(_ bytes: Data) throws -> Data
    func encodeTransferChunk(_ chunk: CoreDirectTransferChunk) throws -> Data
    func negotiateTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities
    ) throws -> CoreDirectTransferNegotiation
}

struct LiveAppleDirectProtocolRustCore: AppleDirectProtocolRustCore {
    private let service = HealthMdCoreService()

    func buildInfo() throws -> AppleDirectProtocolBuildInfo {
        let info = try service.buildInfo()
        return AppleDirectProtocolBuildInfo(
            coreAPIVersion: info.coreApiVersion,
            crateVersion: info.crateVersion,
            coreSourceRevision: info.coreSourceRevision
        )
    }

    func protocolInfo() throws -> AppleDirectProtocolInfo {
        let info = try service.directProtocolInfo()
        return AppleDirectProtocolInfo(
            protocolAPIRevision: info.protocolApiRevision,
            supportedPairingProtocolVersions: info.supportedPairingProtocolVersions,
            appleApplicationProtocolVersion: info.appleApplicationProtocolVersion,
            manualIPPort: info.manualIpPort,
            maximumControlJSONBytes: info.maximumControlJsonBytes,
            transferProtocolVersion: info.transferProtocolVersion,
            transferFrameHeaderBytes: info.transferFrameHeaderBytes,
            maximumChunkBytes: info.maximumChunkBytes,
            minimumPartitionBytes: info.minimumPartitionBytes,
            preferredPartitionBytes: info.preferredPartitionBytes,
            maximumPartitionBytes: info.maximumPartitionBytes,
            maximumInFlightChunks: info.maximumInFlightChunks,
            durableJobLifetimeSeconds: info.durableJobLifetimeSeconds
        )
    }

    func appleV1RequestFingerprint(_ bytes: Data) throws -> String {
        try service.appleV1RequestFingerprint(canonicalRequest: bytes)
    }

    func canonicalAppleV1Message(_ bytes: Data) throws -> Data {
        try service.canonicalAppleV1Message(bytes)
    }

    func encodeTransferChunk(_ chunk: CoreDirectTransferChunk) throws -> Data {
        try service.encodeTransferChunk(chunk)
    }

    func negotiateTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities
    ) throws -> CoreDirectTransferNegotiation {
        try service.negotiateTransfer(local: local, peer: peer)
    }
}

struct AppleDirectProtocolAuthorityError: LocalizedError, Equatable, Sendable {
    let stage: AppleDirectProtocolStage

    var errorDescription: String? {
        "The shared direct protocol core failed at \(stage.rawValue)."
    }
}

/// Operation-wide deterministic authority behind Apple-native direct transport and trust.
final class AppleDirectProtocolAuthority: DirectMessageCanonicalizing, @unchecked Sendable {
    static let shared = AppleDirectProtocolAuthority()
    static let expectedCoreAPIVersion: UInt32 = 4
    static let expectedProtocolAPIRevision: UInt32 = 1

    let defaultMode: AppleDirectProtocolEngineMode

    private let rustCore: any AppleDirectProtocolRustCore
    private let lock = NSLock()
    private var operationMode: AppleDirectProtocolEngineMode?
    private var comparisonCounts: [AppleDirectProtocolStage: Int] = [:]
    private var mismatchCounts: [AppleDirectProtocolStage: Int] = [:]

    init(
        defaultMode: AppleDirectProtocolEngineMode = AppleDirectProtocolAuthority.configuredMode(),
        rustCore: any AppleDirectProtocolRustCore = LiveAppleDirectProtocolRustCore()
    ) {
        self.defaultMode = defaultMode
        self.rustCore = rustCore
    }

    static func configuredMode(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppleDirectProtocolEngineMode {
        if let raw = environment["HEALTHMD_DIRECT_PROTOCOL_ENGINE"],
           let mode = AppleDirectProtocolEngineMode(rawValue: raw) {
            return mode
        }
#if HEALTHMD_APPLE_DIRECT_PROTOCOL_RUST && HEALTHMD_APPLE_DIRECT_PROTOCOL_SHADOW
#error("Select at most one Apple direct protocol authority")
#elseif HEALTHMD_APPLE_DIRECT_PROTOCOL_RUST
        return .rust
#elseif HEALTHMD_APPLE_DIRECT_PROTOCOL_SHADOW
        return .shadow
#else
        return .legacy
#endif
    }

    private var activeMode: AppleDirectProtocolEngineMode {
        lock.withLock { operationMode ?? defaultMode }
    }

    func assertCompatible() throws {
        let mode = activeMode
        guard mode != .legacy else { return }
        let compatible = isCompatible()
        if mode == .shadow {
            record(stage: .compatibility, mismatch: !compatible)
        } else if !compatible {
            throw AppleDirectProtocolAuthorityError(stage: .compatibility)
        }
    }

    func beginBootstrap() {
        lock.withLock { operationMode = .legacy }
    }

    func pinForNewOperation() throws -> AppleDirectProtocolPin? {
        guard defaultMode != .legacy else { return nil }
        guard isCompatible() else {
            throw AppleDirectProtocolAuthorityError(stage: .compatibility)
        }
        let build = try rustCore.buildInfo()
        let info = try rustCore.protocolInfo()
        return try AppleDirectProtocolPin(
            engine: defaultMode,
            coreAPIVersion: build.coreAPIVersion,
            protocolAPIRevision: info.protocolAPIRevision,
            appleApplicationProtocolVersion: info.appleApplicationProtocolVersion,
            transferProtocolVersion: info.transferProtocolVersion,
            coreCrateVersion: build.crateVersion,
            coreSourceRevision: build.coreSourceRevision
        )
    }

    func beginOperation(pin: AppleDirectProtocolPin?) throws {
        lock.withLock { operationMode = pin?.engine ?? .legacy }
        guard let pin else { return }
        do {
            let build = try rustCore.buildInfo()
            let info = try rustCore.protocolInfo()
            guard pin.version == AppleDirectProtocolPin.currentVersion,
                  pin.coreAPIVersion == build.coreAPIVersion,
                  pin.protocolAPIRevision == info.protocolAPIRevision,
                  pin.appleApplicationProtocolVersion == info.appleApplicationProtocolVersion,
                  pin.transferProtocolVersion == info.transferProtocolVersion else {
                throw AppleDirectProtocolAuthorityError(stage: .compatibility)
            }
        } catch {
            endOperation()
            throw AppleDirectProtocolAuthorityError(stage: .compatibility)
        }
    }

    func endOperation() {
        lock.withLock { operationMode = nil }
    }

    func canonicalizeDirectMessage(_ nativeBytes: Data) throws -> Data {
        try select(stage: .directMessage, native: nativeBytes) {
            try rustCore.canonicalAppleV1Message(nativeBytes)
        }
    }

    func requestFingerprint(_ request: DirectExportRequest) throws -> DirectRequestFingerprint {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(request)
        let native = try DirectRequestFingerprint.make(for: request)
        let digest: String = try select(stage: .requestFingerprint, native: native.sha256) {
            try rustCore.appleV1RequestFingerprint(bytes)
        }
        return try DirectRequestFingerprint(sha256: digest)
    }

    func encodeTransferChunk(_ chunk: DirectTransferChunk) throws -> Data {
        let native = try DirectTransferBinaryFrame.encode(chunk)
        return try select(stage: .transferFrame, native: native) {
            try rustCore.encodeTransferChunk(CoreDirectTransferChunk(
                transferId: chunk.transferID.uuidString.lowercased(),
                sequence: UInt64(chunk.sequence),
                sha256: chunk.sha256,
                chunkBytes: chunk.data
            ))
        }
    }

    func negotiateTransfer(
        local: DirectTransferCapabilities = .current,
        peer: DirectTransferCapabilities
    ) throws -> DirectTransferNegotiation? {
        let native = local.negotiated(with: peer)
        switch activeMode {
        case .legacy:
            return native
        case .shadow:
            do {
                let rust = try rustCore.negotiateTransfer(
                    local: try coreCapabilities(local),
                    peer: try coreCapabilities(peer)
                )
                let converted = try nativeNegotiation(rust)
                record(stage: .transferNegotiation, mismatch: converted != native)
            } catch {
                record(stage: .transferNegotiation, mismatch: true)
            }
            return native
        case .rust:
            do {
                return try nativeNegotiation(rustCore.negotiateTransfer(
                    local: try coreCapabilities(local),
                    peer: try coreCapabilities(peer)
                ))
            } catch {
                throw AppleDirectProtocolAuthorityError(stage: .transferNegotiation)
            }
        }
    }

    func comparisonSnapshot() -> AppleDirectProtocolComparisonSnapshot {
        lock.withLock {
            AppleDirectProtocolComparisonSnapshot(
                comparisons: comparisonCounts,
                mismatches: mismatchCounts
            )
        }
    }

    private func isCompatible() -> Bool {
        do {
            let build = try rustCore.buildInfo()
            let info = try rustCore.protocolInfo()
            return build.coreAPIVersion == Self.expectedCoreAPIVersion
                && info.protocolAPIRevision == Self.expectedProtocolAPIRevision
                && info.supportedPairingProtocolVersions.contains(1)
                && info.appleApplicationProtocolVersion == UInt32(HealthMdDirectProtocol.currentVersion)
                && info.manualIPPort == UInt32(HealthMdDirectProtocol.defaultManualIPPort)
                && info.maximumControlJSONBytes == UInt64(HealthMdDirectProtocol.maximumPacketBytes)
                && info.transferProtocolVersion == UInt32(DirectTransferBinaryFrame.currentVersion)
                && info.transferFrameHeaderBytes == 66
                && info.maximumChunkBytes == UInt64(DirectTransferLimits.chunkBytes)
                && info.minimumPartitionBytes == UInt64(DirectTransferLimits.minimumPartitionBytes)
                && info.preferredPartitionBytes == UInt64(DirectTransferLimits.preferredPartitionBytes)
                && info.maximumPartitionBytes == UInt64(DirectTransferLimits.maximumPartitionBytes)
                && info.maximumInFlightChunks == UInt32(DirectTransferLimits.maximumInFlightChunks)
                && info.durableJobLifetimeSeconds == UInt64(HealthMdDirectProtocol.jobLifetime)
        } catch {
            return false
        }
    }

    private func select<Value: Equatable>(
        stage: AppleDirectProtocolStage,
        native: Value,
        rust: () throws -> Value
    ) throws -> Value {
        switch activeMode {
        case .legacy:
            return native
        case .shadow:
            do {
                record(stage: stage, mismatch: try rust() != native)
            } catch {
                record(stage: stage, mismatch: true)
            }
            return native
        case .rust:
            do {
                return try rust()
            } catch {
                throw AppleDirectProtocolAuthorityError(stage: stage)
            }
        }
    }

    private func record(stage: AppleDirectProtocolStage, mismatch: Bool) {
        lock.withLock {
            comparisonCounts[stage, default: 0] += 1
            if mismatch { mismatchCounts[stage, default: 0] += 1 }
        }
    }

    private func coreCapabilities(
        _ value: DirectTransferCapabilities
    ) throws -> CoreDirectTransferCapabilities {
        guard value.protocolVersions.allSatisfy({ UInt32(exactly: $0) != nil }),
              value.binaryFrameVersions.allSatisfy({ UInt32(exactly: $0) != nil }),
              value.minimumPartitionBytes >= 0,
              value.preferredPartitionBytes >= 0,
              value.maximumPartitionBytes >= 0,
              value.maximumInFlightChunks >= 0,
              let maximumInFlightChunks = UInt32(exactly: value.maximumInFlightChunks) else {
            throw AppleDirectProtocolAuthorityError(stage: .transferNegotiation)
        }
        return CoreDirectTransferCapabilities(
            protocolVersions: value.protocolVersions.compactMap { UInt32(exactly: $0) },
            binaryFrameVersions: value.binaryFrameVersions.compactMap { UInt32(exactly: $0) },
            minimumPartitionBytes: UInt64(value.minimumPartitionBytes),
            preferredPartitionBytes: UInt64(value.preferredPartitionBytes),
            maximumPartitionBytes: UInt64(value.maximumPartitionBytes),
            maximumInFlightChunks: maximumInFlightChunks
        )
    }

    private func nativeNegotiation(
        _ value: CoreDirectTransferNegotiation
    ) throws -> DirectTransferNegotiation {
        guard let protocolVersion = Int(exactly: value.protocolVersion),
              let binaryFrameVersion = Int(exactly: value.binaryFrameVersion),
              let partitionTargetBytes = Int64(exactly: value.partitionTargetBytes),
              let maximumInFlightChunks = Int(exactly: value.maximumInFlightChunks) else {
            throw AppleDirectProtocolAuthorityError(stage: .transferNegotiation)
        }
        return DirectTransferNegotiation(
            protocolVersion: protocolVersion,
            binaryFrameVersion: binaryFrameVersion,
            partitionTargetBytes: partitionTargetBytes,
            maximumInFlightChunks: maximumInFlightChunks
        )
    }
}
