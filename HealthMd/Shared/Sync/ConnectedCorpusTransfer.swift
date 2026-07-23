import Foundation

/// Wire-only models for a resumable, partitioned connected export. Runtime
/// routing and persistence are intentionally owned by later integration work.
enum ConnectedCorpusTransferConstants {
    nonisolated static let mebibyte: Int64 = 1_024 * 1_024
    nonisolated static let minimumPartitionTargetBytes: Int64 = 32 * mebibyte
    nonisolated static let defaultPartitionTargetBytes: Int64 = 48 * mebibyte
    nonisolated static let maximumPartitionTargetBytes: Int64 = 64 * mebibyte
    /// Application items are disk-spooled and can span any number of bounded
    /// partitions. The signed 64-bit wire length is the format's only logical
    /// ceiling; it is not a user-facing health-data limit.
    nonisolated static let maximumItemBytes: Int64 = Int64.max
}

enum ConnectedMacExportDisconnectDisposition: Equatable, Sendable {
    case awaitReconnect
    case cancel
    case failBeforePayload
    case failAfterPayload
}

enum ConnectedMacExportLifecyclePolicy {
    /// A negotiated corpus producer owns retry and resume checkpoints across a
    /// transient peer disconnect. Legacy transfers cannot make that guarantee.
    nonisolated static func disconnectDisposition(
        payloadSent: Bool,
        usesResumableCorpus: Bool,
        userInitiated: Bool = false
    ) -> ConnectedMacExportDisconnectDisposition {
        if userInitiated { return .cancel }
        guard payloadSent else { return .failBeforePayload }
        return usesResumableCorpus ? .awaitReconnect : .failAfterPayload
    }
}

enum ConnectedCorpusTransferModelError: Error, Equatable, Sendable {
    case invalidProtocolVersions
    case invalidPartitionBounds
    case invalidPartitionTarget
    case invalidDigest
    case invalidFingerprintVersion
    case invalidPartitionIndex
    case invalidPartitionDates
    case invalidPartitionByteCount
    case invalidItemByteCount
    case invalidDigestChain
    case mismatchedSession
    case invalidPeerBinding
    case invalidFinalization
    case invalidJournal
}

/// The range and preference a peer supports for uncompressed partition targets.
/// Bounds outside 32...64 MiB, or bounds not ordered min <= preferred <= max,
/// are rejected while decoding instead of being silently clamped.
struct ConnectedCorpusPartitionTargetBounds: Codable, Equatable, Sendable {
    let minimumBytes: Int64
    let preferredBytes: Int64
    let maximumBytes: Int64

    static let `default` = ConnectedCorpusPartitionTargetBounds(
        minimumBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
        preferredBytes: ConnectedCorpusTransferConstants.defaultPartitionTargetBytes,
        maximumBytes: ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
    )

    init(minimumBytes: Int64, preferredBytes: Int64, maximumBytes: Int64) {
        self.minimumBytes = minimumBytes
        self.preferredBytes = preferredBytes
        self.maximumBytes = maximumBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            minimumBytes: try container.decode(Int64.self, forKey: .minimumBytes),
            preferredBytes: try container.decode(Int64.self, forKey: .preferredBytes),
            maximumBytes: try container.decode(Int64.self, forKey: .maximumBytes)
        )
        guard isValid else { throw ConnectedCorpusTransferModelError.invalidPartitionBounds }
    }

    var isValid: Bool {
        minimumBytes >= ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
            && minimumBytes <= preferredBytes
            && preferredBytes <= maximumBytes
            && maximumBytes <= ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
    }
}

struct ConnectedCorpusTransferCapabilities: Codable, Equatable, Sendable {
    static let currentProtocolVersion = 2

    let protocolVersions: [Int]
    let partitionTargetBounds: ConnectedCorpusPartitionTargetBounds

    static let current = ConnectedCorpusTransferCapabilities(
        protocolVersions: [1, currentProtocolVersion],
        partitionTargetBounds: .default
    )

    init(protocolVersions: [Int], partitionTargetBounds: ConnectedCorpusPartitionTargetBounds = .default) {
        self.protocolVersions = Array(Set(protocolVersions)).sorted()
        self.partitionTargetBounds = partitionTargetBounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            protocolVersions: try container.decode([Int].self, forKey: .protocolVersions),
            partitionTargetBounds: try container.decode(
                ConnectedCorpusPartitionTargetBounds.self,
                forKey: .partitionTargetBounds
            )
        )
        guard !protocolVersions.isEmpty, protocolVersions.allSatisfy({ $0 > 0 }) else {
            throw ConnectedCorpusTransferModelError.invalidProtocolVersions
        }
        guard partitionTargetBounds.isValid else {
            throw ConnectedCorpusTransferModelError.invalidPartitionBounds
        }
    }
}

struct ConnectedCorpusTransferNegotiation: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let partitionTargetBytes: Int64
}

/// Stable source/destination identities bound into durable protocol-v2 corpus
/// sessions so a reconnect cannot resume against a different installation.
struct ConnectedCorpusPeerBinding: Codable, Equatable, Hashable, Sendable {
    let sourceInstallationID: UUID
    let destinationInstallationID: UUID
}

/// A corpus negotiation plus the installation binding required for durable
/// recovery and status exchange.
struct ConnectedCorpusDurableNegotiation: Codable, Equatable, Sendable {
    let transfer: ConnectedCorpusTransferNegotiation
    let peerBinding: ConnectedCorpusPeerBinding

    var protocolVersion: Int { transfer.protocolVersion }
    var partitionTargetBytes: Int64 { transfer.partitionTargetBytes }
}

enum ConnectedCorpusTransferNegotiator {
    /// Selects the newest shared protocol and the smaller peer preference,
    /// clamped to the peers' intersecting supported range.
    static func negotiate(
        local: ConnectedCorpusTransferCapabilities,
        remote: ConnectedCorpusTransferCapabilities
    ) -> ConnectedCorpusTransferNegotiation? {
        guard local.partitionTargetBounds.isValid,
              remote.partitionTargetBounds.isValid,
              !local.protocolVersions.isEmpty,
              !remote.protocolVersions.isEmpty,
              local.protocolVersions.allSatisfy({ $0 > 0 }),
              remote.protocolVersions.allSatisfy({ $0 > 0 }) else {
            return nil
        }
        guard let protocolVersion = Set(local.protocolVersions)
            .intersection(remote.protocolVersions)
            .max() else {
            return nil
        }

        let lowerBound = max(
            local.partitionTargetBounds.minimumBytes,
            remote.partitionTargetBounds.minimumBytes
        )
        let upperBound = min(
            local.partitionTargetBounds.maximumBytes,
            remote.partitionTargetBounds.maximumBytes
        )
        guard lowerBound <= upperBound else { return nil }

        let sharedPreference = min(
            local.partitionTargetBounds.preferredBytes,
            remote.partitionTargetBounds.preferredBytes
        )
        return ConnectedCorpusTransferNegotiation(
            protocolVersion: protocolVersion,
            partitionTargetBytes: min(max(sharedPreference, lowerBound), upperBound)
        )
    }

    /// Establishes durable recovery only for corpus protocol v2+ peers that
    /// explicitly advertise recovery and stable installation identities.
    static func negotiateDurable(
        source: SyncPeerCapabilities,
        destination: SyncPeerCapabilities
    ) -> ConnectedCorpusDurableNegotiation? {
        guard source.supportsDurableConnectedExportRecovery,
              destination.supportsDurableConnectedExportRecovery,
              let sourceInstallationID = source.installationID,
              let destinationInstallationID = destination.installationID,
              let transfer = source.negotiateConnectedCorpusTransfer(with: destination),
              transfer.protocolVersion >= 2 else {
            return nil
        }

        return ConnectedCorpusDurableNegotiation(
            transfer: transfer,
            peerBinding: ConnectedCorpusPeerBinding(
                sourceInstallationID: sourceInstallationID,
                destinationInstallationID: destinationInstallationID
            )
        )
    }
}

/// Digest of the canonical, immutable request inputs. A reconnect may reuse a
/// session ID only when this fingerprint is unchanged.
struct ConnectedCorpusRequestFingerprint: Codable, Equatable, Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let sha256: String

    init(version: Int = currentVersion, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            sha256: try container.decode(String.self, forKey: .sha256)
        )
        guard version > 0 else { throw ConnectedCorpusTransferModelError.invalidFingerprintVersion }
        guard sha256.isConnectedCorpusSHA256 else {
            throw ConnectedCorpusTransferModelError.invalidDigest
        }
    }
}

/// Stable identity and immutable request metadata retained across reconnects.
struct ConnectedCorpusTransferSession: Codable, Equatable, Sendable {
    let sessionID: UUID
    let jobID: UUID
    let requestFingerprint: ConnectedCorpusRequestFingerprint
    let protocolVersion: Int
    let partitionTargetBytes: Int64
    let createdAt: Date
    /// Present only when durable protocol-v2 recovery was negotiated.
    let peerBinding: ConnectedCorpusPeerBinding?

    enum CodingKeys: String, CodingKey {
        case sessionID
        case jobID
        case requestFingerprint
        case protocolVersion
        case partitionTargetBytes
        case createdAt
        case peerBinding
    }

    init(
        sessionID: UUID,
        jobID: UUID,
        requestFingerprint: ConnectedCorpusRequestFingerprint,
        protocolVersion: Int = ConnectedCorpusTransferCapabilities.currentProtocolVersion,
        partitionTargetBytes: Int64 = ConnectedCorpusTransferConstants.defaultPartitionTargetBytes,
        createdAt: Date,
        peerBinding: ConnectedCorpusPeerBinding? = nil
    ) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.requestFingerprint = requestFingerprint
        self.protocolVersion = protocolVersion
        self.partitionTargetBytes = partitionTargetBytes
        self.createdAt = createdAt
        self.peerBinding = peerBinding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            jobID: try container.decode(UUID.self, forKey: .jobID),
            requestFingerprint: try container.decode(
                ConnectedCorpusRequestFingerprint.self,
                forKey: .requestFingerprint
            ),
            protocolVersion: try container.decode(Int.self, forKey: .protocolVersion),
            partitionTargetBytes: try container.decode(Int64.self, forKey: .partitionTargetBytes),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            peerBinding: try container.decodeIfPresent(ConnectedCorpusPeerBinding.self, forKey: .peerBinding)
        )
        guard protocolVersion > 0 else {
            throw ConnectedCorpusTransferModelError.invalidProtocolVersions
        }
        guard peerBinding == nil || protocolVersion >= 2 else {
            throw ConnectedCorpusTransferModelError.invalidPeerBinding
        }
        let validPartitionTargets = ClosedRange(
            uncheckedBounds: (
                lower: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
                upper: ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
            )
        )
        guard validPartitionTargets.contains(partitionTargetBytes) else {
            throw ConnectedCorpusTransferModelError.invalidPartitionTarget
        }
    }
}

/// Durable lifecycle state for a connected corpus export job.
enum ConnectedCorpusJobState: String, Codable, Equatable, Sendable {
    case preparing
    case transferring
    case paused
    case finalizing
    case completed
    case partialSuccess
    case failed
    case cancelled
    case expired
}

/// Wire/persistence snapshot for reconnect recovery. This model is additive;
/// no runtime path sends it until both peers complete durable negotiation.
struct ConnectedCorpusProgressSnapshot: Codable, Equatable, Sendable {
    let jobID: UUID
    let sessionID: UUID
    let requestFingerprint: ConnectedCorpusRequestFingerprint
    let state: ConnectedCorpusJobState
    let processedDays: Int
    let totalDays: Int
    let committedPartitionCount: Int
    let committedBytes: Int64
    let currentDate: Date?
    let message: String?
    let updatedAt: Date
    let expiresAt: Date

    var fingerprint: ConnectedCorpusRequestFingerprint { requestFingerprint }
    var committedByteCount: Int64 { committedBytes }

    init(
        jobID: UUID,
        sessionID: UUID,
        requestFingerprint: ConnectedCorpusRequestFingerprint,
        state: ConnectedCorpusJobState,
        processedDays: Int,
        totalDays: Int,
        committedPartitionCount: Int,
        committedBytes: Int64,
        currentDate: Date? = nil,
        message: String? = nil,
        updatedAt: Date,
        expiresAt: Date
    ) {
        self.jobID = jobID
        self.sessionID = sessionID
        self.requestFingerprint = requestFingerprint
        self.state = state
        self.processedDays = processedDays
        self.totalDays = totalDays
        self.committedPartitionCount = committedPartitionCount
        self.committedBytes = committedBytes
        self.currentDate = currentDate
        self.message = message
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }

    init(
        jobID: UUID,
        sessionID: UUID,
        fingerprint: ConnectedCorpusRequestFingerprint,
        state: ConnectedCorpusJobState,
        processedDays: Int,
        totalDays: Int,
        committedPartitionCount: Int,
        committedByteCount: Int64,
        currentDate: Date? = nil,
        message: String? = nil,
        updatedAt: Date,
        expiresAt: Date
    ) {
        self.init(
            jobID: jobID,
            sessionID: sessionID,
            requestFingerprint: fingerprint,
            state: state,
            processedDays: processedDays,
            totalDays: totalDays,
            committedPartitionCount: committedPartitionCount,
            committedBytes: committedByteCount,
            currentDate: currentDate,
            message: message,
            updatedAt: updatedAt,
            expiresAt: expiresAt
        )
    }
}

/// Exact source-day membership and digest-chain metadata for one partition.
struct ConnectedCorpusPartitionDescriptor: Codable, Equatable, Hashable, Sendable {
    let sessionID: UUID
    let jobID: UUID
    /// Zero-based partition index.
    let index: Int
    /// Exact source-device day instants; peers must not regenerate these in a local time zone.
    let sourceDates: [Date]
    let byteCount: Int64
    let sha256: String
    /// Nil for index zero; otherwise the SHA-256 of the preceding partition.
    let previousSHA256: String?

    var partitionIndex: Int { index }
    var exactSourceDates: [Date] { sourceDates }
    var previousDigest: String? { previousSHA256 }

    init(
        sessionID: UUID,
        jobID: UUID,
        index: Int,
        sourceDates: [Date],
        byteCount: Int64,
        sha256: String,
        previousSHA256: String?
    ) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.index = index
        self.sourceDates = sourceDates
        self.byteCount = byteCount
        self.sha256 = sha256
        self.previousSHA256 = previousSHA256
    }

    init(
        sessionID: UUID,
        jobID: UUID,
        partitionIndex: Int,
        exactSourceDates: [Date],
        byteCount: Int64,
        sha256: String,
        previousDigest: String?
    ) {
        self.init(
            sessionID: sessionID,
            jobID: jobID,
            index: partitionIndex,
            sourceDates: exactSourceDates,
            byteCount: byteCount,
            sha256: sha256,
            previousSHA256: previousDigest
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            jobID: try container.decode(UUID.self, forKey: .jobID),
            index: try container.decode(Int.self, forKey: .index),
            sourceDates: try container.decode([Date].self, forKey: .sourceDates),
            byteCount: try container.decode(Int64.self, forKey: .byteCount),
            sha256: try container.decode(String.self, forKey: .sha256),
            previousSHA256: try container.decodeIfPresent(String.self, forKey: .previousSHA256)
        )
        try validate()
    }

    func validate() throws {
        guard index >= 0 else { throw ConnectedCorpusTransferModelError.invalidPartitionIndex }
        guard !sourceDates.isEmpty,
              sourceDates == sourceDates.sorted(),
              Set(sourceDates).count == sourceDates.count else {
            throw ConnectedCorpusTransferModelError.invalidPartitionDates
        }
        guard byteCount > 0,
              byteCount <= ConnectedCorpusTransferConstants.maximumPartitionTargetBytes else {
            throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
        }
        guard sha256.isConnectedCorpusSHA256,
              previousSHA256.map(\.isConnectedCorpusSHA256) ?? true else {
            throw ConnectedCorpusTransferModelError.invalidDigest
        }
        guard (index == 0 && previousSHA256 == nil) || (index > 0 && previousSHA256 != nil) else {
            throw ConnectedCorpusTransferModelError.invalidDigestChain
        }
    }
}

enum ConnectedCorpusExportMode: String, Codable, Equatable, Sendable {
    case writeFiles = "write_files"
    case strictRaw = "strict_raw"
    case encryptedContext = "encrypted_context"
}

private extension ExportSettingsSnapshot {
    var hasSafeConnectedExportPaths: Bool {
        let candidates: [String?] = [
            healthSubfolder,
            filenameFormat,
            folderStructure,
            individualTracking.entriesFolder,
            individualTracking.filenameTemplate,
            dailyNoteInjection.folderPath,
            dailyNoteInjection.filenamePattern
        ] + individualTracking.metricConfigs.values.map(\.customFolder)
        return candidates.allSatisfy { candidate in
            guard let candidate else { return true }
            guard candidate.utf8.count <= 4_096,
                  !candidate.hasPrefix("/"),
                  !candidate.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }) else { return false }
            return candidate
                .split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { $0 != "." && $0 != ".." }
        }
    }
}

/// Immutable application metadata for the parent corpus export. The dates are
/// exact source-device instants; the receiver must not regenerate them in its
/// local time zone.
struct ConnectedCorpusExportManifest: Codable, Equatable, @unchecked Sendable {
    let mode: ConnectedCorpusExportMode
    let createdAt: Date
    let sourceDeviceName: String
    let sourceTimeZoneIdentifier: String?
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let requestedDates: [Date]
    /// Source-device owner-date strings paired one-to-one with requestedDates.
    let requestedDateIdentifiers: [String]?
    let transferDates: [Date]
    let settingsSnapshot: ExportSettingsSnapshot
    /// Strict-raw profile and selection are durable transfer protocol metadata.
    /// Canonical health values remain ordinary `healthmd.health_data` documents.
    let rawProfile: IPhoneExportRequest.RawProfile?
    let canonicalSelection: CanonicalHealthDataSelection?
    /// Logical source scope used for non-destructive encrypted-context merges.
    let selectedSourceIDs: [String]?
    let requestedTarget: ExportTargetSnapshot?

    init(
        mode: ConnectedCorpusExportMode,
        createdAt: Date,
        sourceDeviceName: String,
        sourceTimeZoneIdentifier: String? = nil,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        requestedDates: [Date],
        requestedDateIdentifiers: [String]? = nil,
        transferDates: [Date],
        settingsSnapshot: ExportSettingsSnapshot,
        rawProfile: IPhoneExportRequest.RawProfile? = nil,
        canonicalSelection: CanonicalHealthDataSelection? = nil,
        selectedSourceIDs: [String]? = nil,
        requestedTarget: ExportTargetSnapshot?
    ) {
        self.mode = mode
        self.createdAt = createdAt
        self.sourceDeviceName = sourceDeviceName
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.requestedDates = requestedDates
        self.requestedDateIdentifiers = requestedDateIdentifiers
        self.transferDates = transferDates
        self.settingsSnapshot = settingsSnapshot
        self.rawProfile = rawProfile
        self.canonicalSelection = canonicalSelection
        self.selectedSourceIDs = selectedSourceIDs.map { Array(Set($0)).sorted() }
        self.requestedTarget = requestedTarget
    }

    func validate() throws {
        guard sourceTimeZoneIdentifier.map({ TimeZone(identifier: $0) != nil }) ?? true,
              !requestedDates.isEmpty,
              requestedDates == requestedDates.sorted(),
              Set(requestedDates).count == requestedDates.count,
              !transferDates.isEmpty,
              transferDates == transferDates.sorted(),
              Set(transferDates).count == transferDates.count,
              Set(requestedDates).isSubset(of: Set(transferDates)),
              requestedDateIdentifiers.map({
                  $0.count == requestedDates.count
                      && Set($0).count == $0.count
                      && $0.allSatisfy { identifier in
                          identifier.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                      }
              }) ?? true,
              settingsSnapshot.hasSafeConnectedExportPaths,
              Calendar.current.isDate(requestedDates[0], inSameDayAs: dateRangeStart),
              Calendar.current.isDate(requestedDates[requestedDates.count - 1], inSameDayAs: dateRangeEnd) else {
            throw ConnectedCorpusTransferModelError.invalidPartitionDates
        }

        if mode == .encryptedContext {
            guard let canonicalSelection,
                  rawProfile == nil,
                  requestedTarget == nil,
                  !canonicalSelection.metricIDs.isEmpty,
                  !canonicalSelection.sourceIDs.isEmpty,
                  canonicalSelection.metricIDs == Array(Set(canonicalSelection.metricIDs)).sorted(),
                  canonicalSelection.sourceIDs == Array(Set(canonicalSelection.sourceIDs)).sorted(),
                  selectedSourceIDs == canonicalSelection.sourceIDs else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
    }
}

/// Sender opens (or reopens) one partition in a stable corpus session.
struct ConnectedCorpusTransferOpen: Codable, Equatable, Sendable {
    let session: ConnectedCorpusTransferSession
    let partition: ConnectedCorpusPartitionDescriptor
    let exportManifest: ConnectedCorpusExportManifest?

    init(
        session: ConnectedCorpusTransferSession,
        partition: ConnectedCorpusPartitionDescriptor,
        exportManifest: ConnectedCorpusExportManifest? = nil
    ) {
        self.session = session
        self.partition = partition
        self.exportManifest = exportManifest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            session: try container.decode(ConnectedCorpusTransferSession.self, forKey: .session),
            partition: try container.decode(ConnectedCorpusPartitionDescriptor.self, forKey: .partition),
            exportManifest: try container.decodeIfPresent(
                ConnectedCorpusExportManifest.self,
                forKey: .exportManifest
            )
        )
        guard session.sessionID == partition.sessionID, session.jobID == partition.jobID else {
            throw ConnectedCorpusTransferModelError.mismatchedSession
        }
        try exportManifest?.validate()
    }
}

enum ConnectedCorpusTransferDispositionKind: String, Codable, Equatable, Sendable {
    case accept
    case resume
    case alreadyCommitted = "already_committed"
    case reject
}

/// Receiver decision for an opened partition. `nextPartitionIndex` communicates
/// durable resume progress without changing the immutable request fingerprint.
struct ConnectedCorpusTransferDisposition: Codable, Equatable, Sendable {
    let sessionID: UUID
    let jobID: UUID
    let partitionIndex: Int
    let partitionSHA256: String
    let disposition: ConnectedCorpusTransferDispositionKind
    let nextPartitionIndex: Int
    let message: String?

    init(
        sessionID: UUID,
        jobID: UUID,
        partitionIndex: Int,
        partitionSHA256: String,
        disposition: ConnectedCorpusTransferDispositionKind,
        nextPartitionIndex: Int,
        message: String? = nil
    ) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.partitionIndex = partitionIndex
        self.partitionSHA256 = partitionSHA256
        self.disposition = disposition
        self.nextPartitionIndex = nextPartitionIndex
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            jobID: try container.decode(UUID.self, forKey: .jobID),
            partitionIndex: try container.decode(Int.self, forKey: .partitionIndex),
            partitionSHA256: try container.decode(String.self, forKey: .partitionSHA256),
            disposition: try container.decode(ConnectedCorpusTransferDispositionKind.self, forKey: .disposition),
            nextPartitionIndex: try container.decode(Int.self, forKey: .nextPartitionIndex),
            message: try container.decodeIfPresent(String.self, forKey: .message)
        )
        guard partitionIndex >= 0, nextPartitionIndex >= 0 else {
            throw ConnectedCorpusTransferModelError.invalidPartitionIndex
        }
        switch disposition {
        case .accept, .resume:
            guard nextPartitionIndex == partitionIndex else {
                throw ConnectedCorpusTransferModelError.invalidPartitionIndex
            }
        case .alreadyCommitted:
            guard nextPartitionIndex > partitionIndex else {
                throw ConnectedCorpusTransferModelError.invalidPartitionIndex
            }
        case .reject:
            break
        }
        guard partitionSHA256.isConnectedCorpusSHA256 else {
            throw ConnectedCorpusTransferModelError.invalidDigest
        }
    }
}

struct ConnectedCorpusTransferFinalize: Codable, Equatable, Sendable {
    let sessionID: UUID
    let jobID: UUID
    let requestFingerprint: ConnectedCorpusRequestFingerprint
    let partitionCount: Int
    let totalByteCount: Int64
    let finalPartitionSHA256: String?

    init(
        sessionID: UUID,
        jobID: UUID,
        requestFingerprint: ConnectedCorpusRequestFingerprint,
        partitionCount: Int,
        totalByteCount: Int64,
        finalPartitionSHA256: String?
    ) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.requestFingerprint = requestFingerprint
        self.partitionCount = partitionCount
        self.totalByteCount = totalByteCount
        self.finalPartitionSHA256 = finalPartitionSHA256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            jobID: try container.decode(UUID.self, forKey: .jobID),
            requestFingerprint: try container.decode(
                ConnectedCorpusRequestFingerprint.self,
                forKey: .requestFingerprint
            ),
            partitionCount: try container.decode(Int.self, forKey: .partitionCount),
            totalByteCount: try container.decode(Int64.self, forKey: .totalByteCount),
            finalPartitionSHA256: try container.decodeIfPresent(String.self, forKey: .finalPartitionSHA256)
        )
        guard partitionCount >= 0, totalByteCount >= 0,
              (partitionCount == 0) == (finalPartitionSHA256 == nil),
              finalPartitionSHA256.map(\.isConnectedCorpusSHA256) ?? true else {
            throw ConnectedCorpusTransferModelError.invalidFinalization
        }
    }
}

struct ConnectedCorpusTransferFinalAck: Codable, Equatable, Sendable {
    let sessionID: UUID
    let jobID: UUID
    let accepted: Bool
    let requestFingerprint: ConnectedCorpusRequestFingerprint
    let finalPartitionSHA256: String?
    let completedDates: [Date]?
    let successCount: Int?
    let totalCount: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case sessionID
        case jobID
        case accepted
        case requestFingerprint
        case finalPartitionSHA256
        case completedDates
        case successCount
        case totalCount
        case message
    }

    init(
        sessionID: UUID,
        jobID: UUID,
        accepted: Bool,
        requestFingerprint: ConnectedCorpusRequestFingerprint,
        finalPartitionSHA256: String?,
        completedDates: [Date]? = nil,
        successCount: Int? = nil,
        totalCount: Int? = nil,
        message: String? = nil
    ) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.accepted = accepted
        self.requestFingerprint = requestFingerprint
        self.finalPartitionSHA256 = finalPartitionSHA256
        self.completedDates = completedDates
        self.successCount = successCount
        self.totalCount = totalCount
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            jobID: try container.decode(UUID.self, forKey: .jobID),
            accepted: try container.decode(Bool.self, forKey: .accepted),
            requestFingerprint: try container.decode(
                ConnectedCorpusRequestFingerprint.self,
                forKey: .requestFingerprint
            ),
            finalPartitionSHA256: try container.decodeIfPresent(String.self, forKey: .finalPartitionSHA256),
            completedDates: try container.decodeIfPresent([Date].self, forKey: .completedDates),
            successCount: try container.decodeIfPresent(Int.self, forKey: .successCount),
            totalCount: try container.decodeIfPresent(Int.self, forKey: .totalCount),
            message: try container.decodeIfPresent(String.self, forKey: .message)
        )
        guard finalPartitionSHA256.map(\.isConnectedCorpusSHA256) ?? true,
              successCount.map({ $0 >= 0 }) ?? true,
              totalCount.map({ $0 >= 0 }) ?? true,
              successCount.map({ $0 <= (totalCount ?? $0) }) ?? true else {
            throw ConnectedCorpusTransferModelError.invalidFinalization
        }
        if let completedDates {
            guard completedDates == completedDates.sorted(),
                  Set(completedDates).count == completedDates.count,
                  completedDates.count <= (totalCount ?? completedDates.count) else {
                throw ConnectedCorpusTransferModelError.invalidFinalization
            }
        }
    }
}

enum ConnectedCorpusTransferCancelReason: String, Codable, Equatable, Sendable {
    case userRequested = "user_requested"
    case requestChanged = "request_changed"
    case protocolError = "protocol_error"
    case disconnected
    case timedOut = "timed_out"
}

struct ConnectedCorpusTransferCancel: Codable, Equatable, Sendable {
    let sessionID: UUID
    let jobID: UUID
    let reason: ConnectedCorpusTransferCancelReason
    let message: String?
    let requestedAt: Date
}

struct ConnectedCorpusTransferCancelAck: Codable, Equatable, Sendable {
    let sessionID: UUID
    let jobID: UUID
    let accepted: Bool
    let acknowledgedAt: Date
    let message: String?
}

enum ConnectedCorpusTransferJournalState: String, Codable, Equatable, Sendable {
    case open
    case finalizing
    case completed
    case cancelled
    case failed
}

enum ConnectedCorpusPartitionJournalState: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case transferred
    case committed
    case skipped
    case rejected
}

struct ConnectedCorpusPartitionJournal: Codable, Equatable, Sendable {
    let descriptor: ConnectedCorpusPartitionDescriptor
    let state: ConnectedCorpusPartitionJournalState
    let updatedAt: Date
}

/// Codable persistence shape only. The journal carries no file handles or
/// mutable request inputs and can be atomically replaced after durable progress.
struct ConnectedCorpusTransferJournal: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let session: ConnectedCorpusTransferSession
    let state: ConnectedCorpusTransferJournalState
    let partitions: [ConnectedCorpusPartitionJournal]
    let updatedAt: Date

    init(
        version: Int = currentVersion,
        session: ConnectedCorpusTransferSession,
        state: ConnectedCorpusTransferJournalState,
        partitions: [ConnectedCorpusPartitionJournal],
        updatedAt: Date
    ) {
        self.version = version
        self.session = session
        self.state = state
        self.partitions = partitions
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            session: try container.decode(ConnectedCorpusTransferSession.self, forKey: .session),
            state: try container.decode(ConnectedCorpusTransferJournalState.self, forKey: .state),
            partitions: try container.decode([ConnectedCorpusPartitionJournal].self, forKey: .partitions),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )

        let orderedIndexes = partitions.map(\.descriptor.index)
        guard version > 0,
              orderedIndexes == Array(0..<orderedIndexes.count),
              partitions.allSatisfy({
                  $0.descriptor.sessionID == session.sessionID
                      && $0.descriptor.jobID == session.jobID
              }) else {
            throw ConnectedCorpusTransferModelError.invalidJournal
        }
        for (offset, partition) in partitions.enumerated() where offset > 0 {
            guard partition.descriptor.previousSHA256 == partitions[offset - 1].descriptor.sha256 else {
                throw ConnectedCorpusTransferModelError.invalidJournal
            }
        }
    }
}

typealias ConnectedCorpusTransferJournalPartition = ConnectedCorpusPartitionJournal

extension String {
    var isConnectedCorpusSHA256: Bool {
        count == 64 && unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }
}
