import Foundation

/// Health-free Swift entry point for the coarse shared-core UniFFI API.
public struct HealthMdCoreService: Sendable {
    public init() {}

    public func buildInfo() throws -> CoreBuildInfo {
        try translateError {
            try getBuildInfo()
        }
    }

    public func selfTest() throws -> CoreSelfTestReport {
        try translateError {
            try runSelfTest()
        }
    }

    public func metricRegistry(
        profile: CoreMetricRegistryProfile,
        expectedRegistryVersion: UInt32 = 1
    ) throws -> CoreMetricRegistrySnapshot {
        try translateError {
            try getMetricRegistry(
                profile: profile,
                expectedRegistryVersion: expectedRegistryVersion
            )
        }
    }

    public func semanticSession(configuration: Data) throws -> HealthMdCoreSemanticSession {
        try translateError {
            try HealthMdCoreSemanticSession(
                generated: createSemanticSession(configBytes: configuration)
            )
        }
    }

    public func renderSession(
        configuration: Data,
        semanticResult: Data
    ) throws -> HealthMdCoreRenderSession {
        try translateRenderError {
            HealthMdCoreRenderSession(
                generated: try createRenderSession(
                    configBytes: configuration,
                    semanticResultBytes: semanticResult
                )
            )
        }
    }

    public func losslessArtifactStream(mode: CoreStreamMode) -> HealthMdCoreLosslessArtifactStream {
        HealthMdCoreLosslessArtifactStream(generated: createLosslessArtifactStream(mode: mode))
    }

    public func plannedLosslessArtifactStream(
        mode: CoreStreamMode,
        artifact: CoreStreamArtifactConfig
    ) throws -> HealthMdCoreLosslessArtifactStream {
        try translateRenderError {
            HealthMdCoreLosslessArtifactStream(
                generated: try createPlannedLosslessArtifactStream(mode: mode, artifact: artifact)
            )
        }
    }

    public func mergeMarkdown(
        profile: CoreMetricRegistryProfile,
        existing: String,
        generated: String,
        preservePreamble: Bool = false
    ) throws -> String {
        try translateRenderError {
            try mergeProfileRenderedMarkdown(
                profile: profile,
                existing: existing,
                generated: generated,
                preservePreamble: preservePreamble
            )
        }
    }

    public func mergeMarkdown(existing: String, generated: String) throws -> String {
        try translateRenderError {
            try mergeRenderedMarkdown(existing: existing, generated: generated)
        }
    }

    public func directProtocolInfo() throws -> CoreDirectProtocolInfo {
        try translateProtocolError { try getDirectProtocolInfo() }
    }

    public func appleV1RequestFingerprint(canonicalRequest: Data) throws -> String {
        try translateProtocolError {
            try fingerprintAppleV1DirectRequest(requestBytes: canonicalRequest)
        }
    }

    public func androidV2RequestFingerprint(canonicalRequest: Data) throws -> String {
        try translateProtocolError {
            try fingerprintAndroidV2DirectRequest(requestBytes: canonicalRequest)
        }
    }

    public func canonicalAppleV1Message(_ message: Data) throws -> Data {
        try translateProtocolError {
            try canonicalizeAppleV1DirectMessage(messageBytes: message)
        }
    }

    public func canonicalAndroidV2Envelope(_ envelope: Data) throws -> Data {
        try translateProtocolError {
            try canonicalizeAndroidV2DirectEnvelope(envelopeBytes: envelope)
        }
    }

    public func encodeTransferChunk(_ chunk: CoreDirectTransferChunk) throws -> Data {
        try translateProtocolError { try encodeDirectTransferChunk(chunk: chunk) }
    }

    public func decodeTransferChunk(_ frame: Data) throws -> CoreDirectTransferChunk {
        try translateProtocolError { try decodeDirectTransferChunk(frameBytes: frame) }
    }

    public func defaultTransferCapabilities() throws -> CoreDirectTransferCapabilities {
        try translateProtocolError { try getDefaultDirectTransferCapabilities() }
    }

    public func negotiateTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities
    ) throws -> CoreDirectTransferNegotiation {
        try translateProtocolError {
            try negotiateDirectTransfer(local: local, peer: peer)
        }
    }

    public func verifyPairingClientTranscript(
        _ request: CoreDirectPairingVerifierRequest
    ) throws -> Bool {
        try translateProtocolError {
            try verifyDirectPairingClientTranscript(request: request)
        }
    }

    /// The caller owns the returned key bytes and should overwrite them promptly after use.
    public func deriveSessionKey(_ request: CoreDirectSessionKeyRequest) throws -> Data {
        try translateProtocolError { try deriveDirectSessionKey(request: request) }
    }

    public func validateFixture(
        _ fixture: Data,
        expectedSHA256: String
    ) throws -> FixtureValidation {
        try translateError {
            try HealthMdCoreRust.validateFixture(
                fixtureBytes: fixture,
                expectedSha256: expectedSHA256
            )
        }
    }

    fileprivate func translateProtocolError<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        do {
            return try operation()
        } catch let error as HealthmdProtocolError {
            throw HealthMdProtocolServiceError(error)
        } catch {
            throw HealthMdProtocolServiceError.internalFailure
        }
    }

    fileprivate func translateRenderError<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch let error as HealthmdRenderError {
            throw HealthMdRenderServiceError(error)
        } catch {
            throw HealthMdRenderServiceError.internalFailure
        }
    }

    fileprivate func translateError<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch let error as HealthmdCoreError {
            throw HealthMdCoreServiceError(error)
        } catch {
            // Never expose binding, parser, path, or payload details to native callers.
            throw HealthMdCoreServiceError.internalFailure
        }
    }
}

/// Handwritten cancellation-safe owner for one coarse Rust semantic session.
public final class HealthMdCoreSemanticSession: @unchecked Sendable {
    private let generated: CoreSemanticSession
    private let service = HealthMdCoreService()

    fileprivate init(generated: CoreSemanticSession) {
        self.generated = generated
    }

    public func process(batch: Data) throws -> Data {
        try service.translateError {
            try generated.processBatch(batchBytes: batch)
        }
    }

    public func cancel() {
        generated.cancel()
    }
}

/// Handwritten owner for one bounded Rust render session.
public final class HealthMdCoreRenderSession: @unchecked Sendable {
    private let generated: CoreRenderSession
    private let service = HealthMdCoreService()

    fileprivate init(generated: CoreRenderSession) {
        self.generated = generated
    }

    public func process(batch: Data) throws -> CoreRenderBatchReceipt {
        try service.translateRenderError {
            try generated.processBatch(batchBytes: batch)
        }
    }

    public func finish() throws -> CoreArtifactPlan {
        try service.translateRenderError {
            try generated.finish()
        }
    }

    public func cancel() { generated.cancel() }
}

/// Handwritten owner for one bounded lossless artifact stream.
public final class HealthMdCoreLosslessArtifactStream: @unchecked Sendable {
    private let generated: CoreLosslessArtifactStream
    private let service = HealthMdCoreService()

    fileprivate init(generated: CoreLosslessArtifactStream) {
        self.generated = generated
    }

    public func push(raw bytes: Data) throws -> Data {
        try service.translateRenderError { try generated.pushRaw(bytes: bytes) }
    }

    public func push(jsonItem bytes: Data) throws -> Data {
        try service.translateRenderError { try generated.pushJsonItem(bytes: bytes) }
    }

    public func push(csvFields fields: [String]) throws -> Data {
        try service.translateRenderError { try generated.pushRfc4180Row(fields: fields) }
    }

    public func finish() throws -> CoreStreamFinish {
        try service.translateRenderError { try generated.finish() }
    }

    public func cancel() { generated.cancel() }
}

/// Stable health-free protocol failures exposed by the handwritten wrapper.
public enum HealthMdProtocolServiceError: Error, Equatable, Sendable {
    case inputTooLarge, invalidJSON, unknownField, nonCanonicalJSON, wrongProfile
    case unsupportedProtocolVersion, invalidRequest, invalidAppleMessage, invalidAndroidEnvelope
    case invalidTransferCapabilities, transferNegotiationFailed, invalidTransferMetadata
    case transferFrameTooLarge, invalidTransferFrame, unsupportedTransferFrameVersion
    case invalidTransferChunk, invalidPairingProfile, invalidPairingCode, invalidPairingTranscript
    case invalidSessionKeyInput, serializationFailed, internalFailure

    public var code: String {
        switch self {
        case .inputTooLarge: "protocol_input_too_large"
        case .invalidJSON: "invalid_protocol_json"
        case .unknownField: "protocol_unknown_field"
        case .nonCanonicalJSON: "non_canonical_protocol_json"
        case .wrongProfile: "wrong_protocol_profile"
        case .unsupportedProtocolVersion: "unsupported_direct_protocol_version"
        case .invalidRequest: "invalid_direct_export_request"
        case .invalidAppleMessage: "invalid_apple_direct_message"
        case .invalidAndroidEnvelope: "invalid_android_direct_envelope"
        case .invalidTransferCapabilities: "invalid_transfer_capabilities"
        case .transferNegotiationFailed: "transfer_negotiation_failed"
        case .invalidTransferMetadata: "invalid_transfer_metadata"
        case .transferFrameTooLarge: "transfer_frame_too_large"
        case .invalidTransferFrame: "invalid_transfer_frame"
        case .unsupportedTransferFrameVersion: "unsupported_transfer_frame_version"
        case .invalidTransferChunk: "invalid_transfer_chunk"
        case .invalidPairingProfile: "invalid_pairing_profile"
        case .invalidPairingCode: "invalid_pairing_code"
        case .invalidPairingTranscript: "invalid_pairing_transcript"
        case .invalidSessionKeyInput: "invalid_session_key_input"
        case .serializationFailed: "protocol_serialization_failed"
        case .internalFailure: "internal_protocol_failure"
        }
    }

    public var message: String {
        switch self {
        case .inputTooLarge: "protocol input exceeds the size limit"
        case .invalidJSON: "protocol JSON is invalid"
        case .unknownField: "protocol JSON contains an unknown field"
        case .nonCanonicalJSON: "protocol JSON is not canonical"
        case .wrongProfile: "protocol profile does not match the operation"
        case .unsupportedProtocolVersion: "direct protocol version is unsupported"
        case .invalidRequest: "direct export request is invalid"
        case .invalidAppleMessage: "Apple direct message is invalid"
        case .invalidAndroidEnvelope: "Android direct envelope is invalid"
        case .invalidTransferCapabilities: "transfer capabilities are invalid"
        case .transferNegotiationFailed: "transfer capabilities are incompatible"
        case .invalidTransferMetadata: "transfer chunk metadata is invalid"
        case .transferFrameTooLarge: "transfer frame exceeds the size limit"
        case .invalidTransferFrame: "transfer frame is invalid"
        case .unsupportedTransferFrameVersion: "transfer frame version is unsupported"
        case .invalidTransferChunk: "transfer chunk is invalid"
        case .invalidPairingProfile: "pairing profile is invalid"
        case .invalidPairingCode: "pairing code is invalid"
        case .invalidPairingTranscript: "pairing transcript input is invalid"
        case .invalidSessionKeyInput: "session-key input is invalid"
        case .serializationFailed: "protocol serialization failed"
        case .internalFailure: "shared protocol core failed internally"
        }
    }

    fileprivate init(_ error: HealthmdProtocolError) {
        switch error {
        case .InputTooLarge: self = .inputTooLarge
        case .InvalidJson: self = .invalidJSON
        case .UnknownField: self = .unknownField
        case .NonCanonicalJson: self = .nonCanonicalJSON
        case .WrongProtocolProfile: self = .wrongProfile
        case .UnsupportedProtocolVersion: self = .unsupportedProtocolVersion
        case .InvalidRequest: self = .invalidRequest
        case .InvalidAppleMessage: self = .invalidAppleMessage
        case .InvalidAndroidEnvelope: self = .invalidAndroidEnvelope
        case .InvalidTransferCapabilities: self = .invalidTransferCapabilities
        case .TransferNegotiationFailed: self = .transferNegotiationFailed
        case .InvalidTransferMetadata: self = .invalidTransferMetadata
        case .TransferFrameTooLarge: self = .transferFrameTooLarge
        case .InvalidTransferFrame: self = .invalidTransferFrame
        case .UnsupportedTransferFrameVersion: self = .unsupportedTransferFrameVersion
        case .InvalidTransferChunk: self = .invalidTransferChunk
        case .InvalidPairingProfile: self = .invalidPairingProfile
        case .InvalidPairingCode: self = .invalidPairingCode
        case .InvalidPairingTranscript: self = .invalidPairingTranscript
        case .InvalidSessionKeyInput: self = .invalidSessionKeyInput
        case .SerializationFailed: self = .serializationFailed
        case .InternalPanic: self = .internalFailure
        }
    }
}

extension HealthMdProtocolServiceError: LocalizedError {
    public var errorDescription: String? { message }
}

/// Stable health-free renderer failures exposed by the handwritten wrapper.
public enum HealthMdRenderServiceError: Error, Equatable, Sendable {
    case configTooLarge, invalidConfig, semanticResultTooLarge, invalidSemanticResult
    case unsupportedRenderInputVersion, unsupportedArtifactPlanVersion, unsupportedProfileRevision
    case batchTooLarge, invalidBatch, sequenceInvalid, limitExceeded, presentationMismatch
    case extensionNotRetained, extensionSelectionInvalid, unsupportedOperation
    case invalidPath, pathCollision, invalidArtifact, artifactTooLarge, artifactLimitExceeded
    case inlineOutputTooLarge, sessionTerminal, cancelled, invalidStreamItem, streamItemTooLarge
    case streamTooLarge, streamSequenceInvalid, streamTerminal, serializationFailed, internalFailure

    public var code: String {
        switch self {
        case .configTooLarge: "render_config_too_large"
        case .invalidConfig: "invalid_render_config"
        case .semanticResultTooLarge: "semantic_result_too_large"
        case .invalidSemanticResult: "invalid_semantic_result"
        case .unsupportedRenderInputVersion: "unsupported_render_input_version"
        case .unsupportedArtifactPlanVersion: "unsupported_artifact_plan_version"
        case .unsupportedProfileRevision: "unsupported_render_profile_revision"
        case .batchTooLarge: "render_batch_too_large"
        case .invalidBatch: "invalid_render_batch"
        case .sequenceInvalid: "render_sequence_invalid"
        case .limitExceeded: "render_limit_exceeded"
        case .presentationMismatch: "render_presentation_mismatch"
        case .extensionNotRetained: "render_extension_not_retained"
        case .extensionSelectionInvalid: "render_extension_selection_invalid"
        case .unsupportedOperation: "unsupported_render_operation"
        case .invalidPath: "invalid_artifact_path"
        case .pathCollision: "artifact_path_collision"
        case .invalidArtifact: "invalid_artifact"
        case .artifactTooLarge: "artifact_too_large"
        case .artifactLimitExceeded: "artifact_limit_exceeded"
        case .inlineOutputTooLarge: "inline_output_too_large"
        case .sessionTerminal: "render_session_terminal"
        case .cancelled: "render_cancelled"
        case .invalidStreamItem: "invalid_stream_item"
        case .streamItemTooLarge: "stream_item_too_large"
        case .streamTooLarge: "stream_too_large"
        case .streamSequenceInvalid: "stream_sequence_invalid"
        case .streamTerminal: "stream_terminal"
        case .serializationFailed: "render_serialization_failed"
        case .internalFailure: "internal_failure"
        }
    }

    fileprivate init(_ error: HealthmdRenderError) {
        switch error {
        case .ConfigTooLarge: self = .configTooLarge
        case .InvalidConfig: self = .invalidConfig
        case .SemanticResultTooLarge: self = .semanticResultTooLarge
        case .InvalidSemanticResult: self = .invalidSemanticResult
        case .UnsupportedRenderInputVersion: self = .unsupportedRenderInputVersion
        case .UnsupportedArtifactPlanVersion: self = .unsupportedArtifactPlanVersion
        case .UnsupportedProfileRevision: self = .unsupportedProfileRevision
        case .BatchTooLarge: self = .batchTooLarge
        case .InvalidBatch: self = .invalidBatch
        case .SequenceInvalid: self = .sequenceInvalid
        case .LimitExceeded: self = .limitExceeded
        case .PresentationMismatch: self = .presentationMismatch
        case .ExtensionNotRetained: self = .extensionNotRetained
        case .ExtensionSelectionInvalid: self = .extensionSelectionInvalid
        case .UnsupportedOperation: self = .unsupportedOperation
        case .InvalidPath: self = .invalidPath
        case .PathCollision: self = .pathCollision
        case .InvalidArtifact: self = .invalidArtifact
        case .ArtifactTooLarge: self = .artifactTooLarge
        case .ArtifactLimitExceeded: self = .artifactLimitExceeded
        case .InlineOutputTooLarge: self = .inlineOutputTooLarge
        case .SessionTerminal: self = .sessionTerminal
        case .Cancelled: self = .cancelled
        case .InvalidStreamItem: self = .invalidStreamItem
        case .StreamItemTooLarge: self = .streamItemTooLarge
        case .StreamTooLarge: self = .streamTooLarge
        case .StreamSequenceInvalid: self = .streamSequenceInvalid
        case .StreamTerminal: self = .streamTerminal
        case .SerializationFailed: self = .serializationFailed
        case .InternalPanic: self = .internalFailure
        }
    }
}

extension HealthMdRenderServiceError: LocalizedError {
    public var errorDescription: String? { code }
}

/// Stable, health-free failures exposed by the handwritten Apple wrapper.
public enum HealthMdCoreServiceError: Error, Equatable, Sendable {
    case invalidFixtureDigest
    case fixtureTooLarge
    case fixtureDigestMismatch
    case invalidFixture
    case nonCanonicalFixture
    case unsupportedFixtureFormatVersion
    case unsupportedSemanticInputVersion
    case unsupportedRegistryVersion
    case unsupportedPersistedStateVersion
    case invalidRegistry
    case unsupportedRegistryProfile
    case semanticConfigTooLarge
    case invalidSemanticConfig
    case semanticBatchTooLarge
    case invalidSemanticBatch
    case semanticLimitExceeded
    case semanticSequenceInvalid
    case semanticSessionTerminal
    case unsupportedSemanticOperation
    case internalFailure

    public var code: String {
        switch self {
        case .invalidFixtureDigest: "invalid_fixture_digest"
        case .fixtureTooLarge: "fixture_too_large"
        case .fixtureDigestMismatch: "fixture_digest_mismatch"
        case .invalidFixture: "invalid_fixture"
        case .nonCanonicalFixture: "non_canonical_fixture"
        case .unsupportedFixtureFormatVersion: "unsupported_fixture_format_version"
        case .unsupportedSemanticInputVersion: "unsupported_semantic_input_version"
        case .unsupportedRegistryVersion: "unsupported_registry_version"
        case .unsupportedPersistedStateVersion: "unsupported_persisted_state_version"
        case .invalidRegistry: "invalid_registry"
        case .unsupportedRegistryProfile: "unsupported_registry_profile"
        case .semanticConfigTooLarge: "semantic_config_too_large"
        case .invalidSemanticConfig: "invalid_semantic_config"
        case .semanticBatchTooLarge: "semantic_batch_too_large"
        case .invalidSemanticBatch: "invalid_semantic_batch"
        case .semanticLimitExceeded: "semantic_limit_exceeded"
        case .semanticSequenceInvalid: "semantic_sequence_invalid"
        case .semanticSessionTerminal: "semantic_session_terminal"
        case .unsupportedSemanticOperation: "unsupported_semantic_operation"
        case .internalFailure: "internal_failure"
        }
    }

    public var message: String {
        switch self {
        case .invalidFixtureDigest: "fixture digest must be lowercase SHA-256"
        case .fixtureTooLarge: "fixture exceeds the size limit"
        case .fixtureDigestMismatch: "fixture digest does not match"
        case .invalidFixture: "fixture envelope is invalid"
        case .nonCanonicalFixture: "fixture bytes are not canonical"
        case .unsupportedFixtureFormatVersion: "fixture format version is unsupported"
        case .unsupportedSemanticInputVersion: "semantic input version is unsupported"
        case .unsupportedRegistryVersion: "registry version is unsupported"
        case .unsupportedPersistedStateVersion: "persisted-state version is unsupported"
        case .invalidRegistry: "metric registry is invalid"
        case .unsupportedRegistryProfile: "metric registry profile is unsupported"
        case .semanticConfigTooLarge: "semantic configuration exceeds the size limit"
        case .invalidSemanticConfig: "semantic configuration is invalid"
        case .semanticBatchTooLarge: "semantic batch exceeds the size limit"
        case .invalidSemanticBatch: "semantic batch is invalid"
        case .semanticLimitExceeded: "semantic session exceeds a limit"
        case .semanticSequenceInvalid: "semantic input sequence is invalid"
        case .semanticSessionTerminal: "semantic session is terminal"
        case .unsupportedSemanticOperation: "semantic operation is unsupported for the profile"
        case .internalFailure: "shared core failed internally"
        }
    }

    fileprivate init(_ error: HealthmdCoreError) {
        switch error {
        case .InvalidFixtureDigest: self = .invalidFixtureDigest
        case .FixtureTooLarge: self = .fixtureTooLarge
        case .FixtureDigestMismatch: self = .fixtureDigestMismatch
        case .InvalidFixture: self = .invalidFixture
        case .NonCanonicalFixture: self = .nonCanonicalFixture
        case .UnsupportedFixtureFormatVersion: self = .unsupportedFixtureFormatVersion
        case .UnsupportedSemanticInputVersion: self = .unsupportedSemanticInputVersion
        case .UnsupportedRegistryVersion: self = .unsupportedRegistryVersion
        case .UnsupportedPersistedStateVersion: self = .unsupportedPersistedStateVersion
        case .InvalidRegistry: self = .invalidRegistry
        case .UnsupportedRegistryProfile: self = .unsupportedRegistryProfile
        case .SemanticConfigTooLarge: self = .semanticConfigTooLarge
        case .InvalidSemanticConfig: self = .invalidSemanticConfig
        case .SemanticBatchTooLarge: self = .semanticBatchTooLarge
        case .InvalidSemanticBatch: self = .invalidSemanticBatch
        case .SemanticLimitExceeded: self = .semanticLimitExceeded
        case .SemanticSequenceInvalid: self = .semanticSequenceInvalid
        case .SemanticSessionTerminal: self = .semanticSessionTerminal
        case .UnsupportedSemanticOperation: self = .unsupportedSemanticOperation
        case .InternalPanic: self = .internalFailure
        }
    }
}

extension HealthMdCoreServiceError: LocalizedError {
    public var errorDescription: String? { message }
}
