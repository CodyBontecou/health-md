//! Thin proc-macro `UniFFI` boundary for `healthmd-core`.

use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

use thiserror::Error;
use zeroize::Zeroizing;

uniffi::setup_scaffolding!();

/// Independently versioned build information for native compatibility checks.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreBuildInfo {
    /// Rust package version; independent from public export schemas.
    pub crate_version: String,
    /// Git/source revision used by reproducible native packaging.
    pub core_source_revision: String,
    /// Exact SHA-256 of the embedded metric/profile registry.
    pub registry_sha256: String,
    /// Coarse core API contract version.
    pub core_api_version: u32,
    /// Semantic native-to-core input contract version.
    pub semantic_input_version: u32,
    /// Internal normalized canonical result model version.
    pub canonical_model_version: u32,
    /// Registry contract version.
    pub registry_version: u32,
    /// Render native-to-core input contract version.
    pub render_input_version: u32,
    /// Destination-neutral artifact-plan contract version.
    pub artifact_plan_version: u32,
    /// Profile renderer implementation revision.
    pub render_profile_revision: u32,
    /// Persisted-state contract version.
    pub persisted_state_version: u32,
}

/// Independently versioned, transport-independent direct-protocol constants.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreDirectProtocolInfo {
    pub protocol_api_revision: u32,
    pub direct_pairing_protocol_version: u32,
    pub supported_pairing_protocol_versions: Vec<u32>,
    pub apple_application_protocol_version: u32,
    pub android_application_protocol_version: u32,
    pub manual_ip_port: u32,
    pub maximum_control_json_bytes: u64,
    pub transfer_protocol_version: u32,
    pub transfer_frame_header_bytes: u64,
    pub maximum_chunk_bytes: u64,
    pub maximum_transfer_frame_bytes: u64,
    pub minimum_partition_bytes: u64,
    pub preferred_partition_bytes: u64,
    pub maximum_partition_bytes: u64,
    pub preferred_in_flight_chunks: u32,
    pub maximum_in_flight_chunks: u32,
    pub pairing_code_lifetime_seconds: u64,
    pub durable_job_lifetime_seconds: u64,
}

/// One owned transfer frame request/result. `chunk_bytes` remain opaque.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreDirectTransferChunk {
    pub transfer_id: String,
    pub sequence: u64,
    pub sha256: String,
    pub chunk_bytes: Vec<u8>,
}

/// Existing deployed transfer-capability fields in a native-owned record.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreDirectTransferCapabilities {
    pub protocol_versions: Vec<u32>,
    pub binary_frame_versions: Vec<u32>,
    pub minimum_partition_bytes: u64,
    pub preferred_partition_bytes: u64,
    pub maximum_partition_bytes: u64,
    pub maximum_in_flight_chunks: u32,
}

/// Pure result of the existing transfer-capability negotiation.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreDirectTransferNegotiation {
    pub protocol_version: u32,
    pub binary_frame_version: u32,
    pub partition_target_bytes: u64,
    pub maximum_in_flight_chunks: u32,
}

/// Reviewed new-pairing transcript profiles.
#[derive(Clone, Copy, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CoreDirectPairingProfile {
    AppleV1,
    AndroidV2,
}

/// Owned, JSON-free input for stateless new-pairing client-proof verification.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreDirectPairingVerifierRequest {
    pub profile: CoreDirectPairingProfile,
    pub pairing_code_bytes: Vec<u8>,
    pub client_installation_id: String,
    pub client_public_key: Vec<u8>,
    pub client_nonce: Vec<u8>,
    pub expected_verifier: Vec<u8>,
}

/// Owned, JSON-free fixed-width input for deployed session-key derivation.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreDirectSessionKeyRequest {
    pub shared_secret: Vec<u8>,
    pub client_nonce: Vec<u8>,
    pub server_nonce: Vec<u8>,
}

/// Health-free evidence that a deterministic fixture passed validation.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct FixtureValidation {
    /// Validated fixture-envelope version.
    pub fixture_format_version: u32,
    /// Validated byte count.
    pub byte_count: u64,
    /// SHA-256 of the exact validated bytes.
    pub sha256: String,
}

/// Health-free result of the embedded shared-core self-test.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreSelfTestReport {
    /// True only after every embedded check completed.
    pub passed: bool,
    /// Version information exercised by the self-test.
    pub build_info: CoreBuildInfo,
    /// Exact embedded fixture validation evidence.
    pub fixture: FixtureValidation,
}

/// Closed shipped registry profiles.
#[derive(Clone, Copy, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CoreMetricRegistryProfile {
    /// Apple `healthmd.health_data` v7.
    AppleHealthDataV7,
    /// Android frozen v4.
    AndroidFrozenV4,
    /// Android analytical v5.
    AndroidAnalyticalV5,
}

/// One ordered native category.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreRegistryCategory {
    pub category_id: String,
    pub label_key: String,
    pub ordinal: u32,
}

/// One ordered selectable native metric.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreRegistryMetric {
    pub semantic_id: String,
    pub selection_id: String,
    pub label_key: String,
    pub reference_name: String,
    pub category_id: String,
    pub unit: String,
    pub kind: String,
    pub source_aggregation: String,
    pub default_enabled: bool,
    pub archive_only: bool,
    pub availability_key: String,
    pub authorization_key: String,
    pub capability_id: String,
    pub source_selector: String,
    pub related_semantic_ids: Vec<String>,
    pub ordinal: u32,
}

/// One unavailable or stale native selection identity.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreRegistryUnavailableMetric {
    pub selection_id: String,
    pub category_id: String,
    pub label_key: String,
    pub reason_key: String,
}

/// One metadata-only public output projection.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreRegistryOutput {
    pub selection_ids: Vec<String>,
    pub surface: String,
    pub key: String,
    pub unit: String,
    pub daily_aggregation: String,
    pub rollup: String,
    pub alias_kind: String,
    pub platform_native: bool,
    pub condition: String,
    pub enabled_by_default: bool,
    pub ordinal: u32,
}

/// Immutable coarse profile snapshot cached by native adapters.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreMetricRegistrySnapshot {
    pub registry_version: u32,
    pub registry_sha256: String,
    pub profile_id: String,
    pub public_profile_id: String,
    pub public_schema: String,
    pub public_schema_version: u32,
    pub profile_revision: u32,
    pub categories: Vec<CoreRegistryCategory>,
    pub metrics: Vec<CoreRegistryMetric>,
    pub unavailable_metrics: Vec<CoreRegistryUnavailableMetric>,
    pub outputs: Vec<CoreRegistryOutput>,
}

/// Stable native-facing failures. Variants and messages contain no health or fixture values.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq, uniffi::Error)]
pub enum HealthmdCoreError {
    /// The expected digest was malformed.
    #[error("fixture digest must be lowercase SHA-256")]
    InvalidFixtureDigest,
    /// The fixture exceeded the public boundary limit.
    #[error("fixture exceeds the size limit")]
    FixtureTooLarge,
    /// The exact bytes did not match the expected digest.
    #[error("fixture digest does not match")]
    FixtureDigestMismatch,
    /// The fixture envelope was invalid.
    #[error("fixture envelope is invalid")]
    InvalidFixture,
    /// The JSON bytes were not canonical.
    #[error("fixture bytes are not canonical")]
    NonCanonicalFixture,
    /// The fixture envelope version was unsupported.
    #[error("fixture format version is unsupported")]
    UnsupportedFixtureFormatVersion,
    /// The semantic input version was unsupported.
    #[error("semantic input version is unsupported")]
    UnsupportedSemanticInputVersion,
    /// The registry version was unsupported.
    #[error("registry version is unsupported")]
    UnsupportedRegistryVersion,
    /// The persisted-state version was unsupported.
    #[error("persisted-state version is unsupported")]
    UnsupportedPersistedStateVersion,
    /// The embedded registry failed deterministic validation.
    #[error("metric registry is invalid")]
    InvalidRegistry,
    /// The requested registry profile was unsupported.
    #[error("metric registry profile is unsupported")]
    UnsupportedRegistryProfile,
    /// Semantic configuration exceeded its bounded input limit.
    #[error("semantic configuration exceeds the size limit")]
    SemanticConfigTooLarge,
    /// Semantic configuration was invalid.
    #[error("semantic configuration is invalid")]
    InvalidSemanticConfig,
    /// One semantic batch exceeded its bounded input limit.
    #[error("semantic batch exceeds the size limit")]
    SemanticBatchTooLarge,
    /// One semantic batch was invalid.
    #[error("semantic batch is invalid")]
    InvalidSemanticBatch,
    /// A bounded semantic session limit was exceeded.
    #[error("semantic session exceeds a limit")]
    SemanticLimitExceeded,
    /// Semantic batch or record ordering was invalid.
    #[error("semantic input sequence is invalid")]
    SemanticSequenceInvalid,
    /// The semantic session had already completed or observed cancellation.
    #[error("semantic session is terminal")]
    SemanticSessionTerminal,
    /// The explicit profile does not support the requested semantic operation.
    #[error("semantic operation is unsupported for the profile")]
    UnsupportedSemanticOperation,
    /// A Rust panic was contained at the native boundary.
    #[error("shared core failed internally")]
    InternalPanic,
}

/// Closed, stable, health-free direct-protocol failures.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq, uniffi::Error)]
pub enum HealthmdProtocolError {
    #[error("protocol input exceeds the size limit")]
    InputTooLarge,
    #[error("protocol JSON is invalid")]
    InvalidJson,
    #[error("protocol JSON contains an unknown field")]
    UnknownField,
    #[error("protocol JSON is not canonical")]
    NonCanonicalJson,
    #[error("protocol profile does not match the operation")]
    WrongProtocolProfile,
    #[error("direct protocol version is unsupported")]
    UnsupportedProtocolVersion,
    #[error("direct export request is invalid")]
    InvalidRequest,
    #[error("Apple direct message is invalid")]
    InvalidAppleMessage,
    #[error("Android direct envelope is invalid")]
    InvalidAndroidEnvelope,
    #[error("transfer capabilities are invalid")]
    InvalidTransferCapabilities,
    #[error("transfer capabilities are incompatible")]
    TransferNegotiationFailed,
    #[error("transfer chunk metadata is invalid")]
    InvalidTransferMetadata,
    #[error("transfer frame exceeds the size limit")]
    TransferFrameTooLarge,
    #[error("transfer frame is invalid")]
    InvalidTransferFrame,
    #[error("transfer frame version is unsupported")]
    UnsupportedTransferFrameVersion,
    #[error("transfer chunk is invalid")]
    InvalidTransferChunk,
    #[error("pairing profile is invalid")]
    InvalidPairingProfile,
    #[error("pairing code is invalid")]
    InvalidPairingCode,
    #[error("pairing transcript input is invalid")]
    InvalidPairingTranscript,
    #[error("session-key input is invalid")]
    InvalidSessionKeyInput,
    #[error("protocol serialization failed")]
    SerializationFailed,
    #[error("shared protocol core failed internally")]
    InternalPanic,
}

impl HealthmdProtocolError {
    pub const fn code(self) -> &'static str {
        match self {
            Self::InputTooLarge => "protocol_input_too_large",
            Self::InvalidJson => "invalid_protocol_json",
            Self::UnknownField => "protocol_unknown_field",
            Self::NonCanonicalJson => "non_canonical_protocol_json",
            Self::WrongProtocolProfile => "wrong_protocol_profile",
            Self::UnsupportedProtocolVersion => "unsupported_direct_protocol_version",
            Self::InvalidRequest => "invalid_direct_export_request",
            Self::InvalidAppleMessage => "invalid_apple_direct_message",
            Self::InvalidAndroidEnvelope => "invalid_android_direct_envelope",
            Self::InvalidTransferCapabilities => "invalid_transfer_capabilities",
            Self::TransferNegotiationFailed => "transfer_negotiation_failed",
            Self::InvalidTransferMetadata => "invalid_transfer_metadata",
            Self::TransferFrameTooLarge => "transfer_frame_too_large",
            Self::InvalidTransferFrame => "invalid_transfer_frame",
            Self::UnsupportedTransferFrameVersion => "unsupported_transfer_frame_version",
            Self::InvalidTransferChunk => "invalid_transfer_chunk",
            Self::InvalidPairingProfile => "invalid_pairing_profile",
            Self::InvalidPairingCode => "invalid_pairing_code",
            Self::InvalidPairingTranscript => "invalid_pairing_transcript",
            Self::InvalidSessionKeyInput => "invalid_session_key_input",
            Self::SerializationFailed => "protocol_serialization_failed",
            Self::InternalPanic => "internal_protocol_failure",
        }
    }
}

impl From<healthmd_protocol::foundation::ProtocolFoundationError> for HealthmdProtocolError {
    fn from(value: healthmd_protocol::foundation::ProtocolFoundationError) -> Self {
        use healthmd_protocol::foundation::ProtocolFoundationError as Source;
        match value {
            Source::InputTooLarge => Self::InputTooLarge,
            Source::InvalidJson => Self::InvalidJson,
            Source::UnknownField => Self::UnknownField,
            Source::NonCanonicalJson => Self::NonCanonicalJson,
            Source::WrongProtocolProfile => Self::WrongProtocolProfile,
            Source::UnsupportedProtocolVersion => Self::UnsupportedProtocolVersion,
            Source::InvalidRequest => Self::InvalidRequest,
            Source::InvalidAppleMessage => Self::InvalidAppleMessage,
            Source::InvalidAndroidEnvelope => Self::InvalidAndroidEnvelope,
            Source::InvalidTransferCapabilities => Self::InvalidTransferCapabilities,
            Source::TransferNegotiationFailed => Self::TransferNegotiationFailed,
            Source::InvalidTransferMetadata => Self::InvalidTransferMetadata,
            Source::TransferFrameTooLarge => Self::TransferFrameTooLarge,
            Source::InvalidTransferFrame => Self::InvalidTransferFrame,
            Source::UnsupportedTransferFrameVersion => Self::UnsupportedTransferFrameVersion,
            Source::InvalidTransferChunk => Self::InvalidTransferChunk,
            Source::InvalidPairingProfile => Self::InvalidPairingProfile,
            Source::InvalidPairingCode => Self::InvalidPairingCode,
            Source::InvalidPairingTranscript => Self::InvalidPairingTranscript,
            Source::InvalidSessionKeyInput => Self::InvalidSessionKeyInput,
            Source::SerializationFailed => Self::SerializationFailed,
        }
    }
}

/// Stable native-facing render failures. No variant contains health data or destination paths.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq, uniffi::Error)]
pub enum HealthmdRenderError {
    #[error("render configuration exceeds the size limit")]
    ConfigTooLarge,
    #[error("render configuration is invalid")]
    InvalidConfig,
    #[error("completed semantic result exceeds the size limit")]
    SemanticResultTooLarge,
    #[error("completed semantic result is invalid")]
    InvalidSemanticResult,
    #[error("render input version is unsupported")]
    UnsupportedRenderInputVersion,
    #[error("artifact plan version is unsupported")]
    UnsupportedArtifactPlanVersion,
    #[error("render profile revision is unsupported")]
    UnsupportedProfileRevision,
    #[error("render batch exceeds the size limit")]
    BatchTooLarge,
    #[error("render batch is invalid")]
    InvalidBatch,
    #[error("render input sequence is invalid")]
    SequenceInvalid,
    #[error("render input exceeds a limit")]
    LimitExceeded,
    #[error("render presentation does not match semantic output")]
    PresentationMismatch,
    #[error("render extension payload is not retained")]
    ExtensionNotRetained,
    #[error("render extension selection is invalid")]
    ExtensionSelectionInvalid,
    #[error("render operation is unsupported for the profile")]
    UnsupportedOperation,
    #[error("artifact path is invalid")]
    InvalidPath,
    #[error("artifact paths collide")]
    PathCollision,
    #[error("artifact is invalid")]
    InvalidArtifact,
    #[error("artifact exceeds the inline size limit")]
    ArtifactTooLarge,
    #[error("artifact count exceeds the limit")]
    ArtifactLimitExceeded,
    #[error("inline output exceeds the size limit")]
    InlineOutputTooLarge,
    #[error("render session is terminal")]
    SessionTerminal,
    #[error("render operation was cancelled")]
    Cancelled,
    #[error("stream item is invalid")]
    InvalidStreamItem,
    #[error("stream item exceeds the size limit")]
    StreamItemTooLarge,
    #[error("stream exceeds the size limit")]
    StreamTooLarge,
    #[error("stream sequence is invalid")]
    StreamSequenceInvalid,
    #[error("stream is terminal")]
    StreamTerminal,
    #[error("render serialization failed")]
    SerializationFailed,
    #[error("shared core failed internally")]
    InternalPanic,
}

impl From<healthmd_core::render::RenderError> for HealthmdRenderError {
    fn from(value: healthmd_core::render::RenderError) -> Self {
        use healthmd_core::render::RenderError as Source;
        match value {
            Source::ConfigTooLarge => Self::ConfigTooLarge,
            Source::InvalidConfig => Self::InvalidConfig,
            Source::SemanticResultTooLarge => Self::SemanticResultTooLarge,
            Source::InvalidSemanticResult => Self::InvalidSemanticResult,
            Source::UnsupportedRenderInputVersion => Self::UnsupportedRenderInputVersion,
            Source::UnsupportedArtifactPlanVersion => Self::UnsupportedArtifactPlanVersion,
            Source::UnsupportedProfileRevision => Self::UnsupportedProfileRevision,
            Source::BatchTooLarge => Self::BatchTooLarge,
            Source::InvalidBatch => Self::InvalidBatch,
            Source::SequenceInvalid => Self::SequenceInvalid,
            Source::LimitExceeded => Self::LimitExceeded,
            Source::PresentationMismatch => Self::PresentationMismatch,
            Source::ExtensionNotRetained => Self::ExtensionNotRetained,
            Source::ExtensionSelectionInvalid => Self::ExtensionSelectionInvalid,
            Source::UnsupportedOperation => Self::UnsupportedOperation,
            Source::InvalidPath => Self::InvalidPath,
            Source::PathCollision => Self::PathCollision,
            Source::InvalidArtifact => Self::InvalidArtifact,
            Source::ArtifactTooLarge => Self::ArtifactTooLarge,
            Source::ArtifactLimitExceeded => Self::ArtifactLimitExceeded,
            Source::InlineOutputTooLarge => Self::InlineOutputTooLarge,
            Source::SessionTerminal => Self::SessionTerminal,
            Source::Cancelled => Self::Cancelled,
            Source::InvalidStreamItem => Self::InvalidStreamItem,
            Source::StreamItemTooLarge => Self::StreamItemTooLarge,
            Source::StreamTooLarge => Self::StreamTooLarge,
            Source::StreamSequenceInvalid => Self::StreamSequenceInvalid,
            Source::StreamTerminal => Self::StreamTerminal,
            Source::SerializationFailed => Self::SerializationFailed,
        }
    }
}

/// Exact write operation for one planned artifact.
#[derive(Clone, Copy, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CoreArtifactWriteMode {
    Overwrite,
    Append,
    MarkdownMerge,
    ApiPost,
}

/// One destination-neutral inline artifact.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreArtifactPlanItem {
    pub artifact_id: String,
    pub relative_path: String,
    pub media_type: String,
    pub write_mode: CoreArtifactWriteMode,
    pub content: Vec<u8>,
    pub byte_count: u64,
    pub sha256: String,
}

/// Completed artifact plan returned in deterministic order.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreArtifactPlan {
    pub schema: String,
    pub artifact_plan_version: u32,
    pub request_id: String,
    pub session_id: String,
    pub profile: CoreMetricRegistryProfile,
    pub items: Vec<CoreArtifactPlanItem>,
    pub total_byte_count: u64,
}

/// Health-free receipt for one accepted render batch.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreRenderBatchReceipt {
    pub next_batch_index: u32,
    pub days_accepted: u32,
    pub facts_accepted: u32,
    pub final_batch: bool,
}

/// Closed lossless stream framing modes.
#[derive(Clone, Copy, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CoreStreamMode {
    RawBytes,
    JsonArray,
    Rfc4180Rows,
}

/// Destination-neutral configuration for a streamed artifact.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreStreamArtifactConfig {
    pub request_id: String,
    pub session_id: String,
    pub profile: CoreMetricRegistryProfile,
    pub relative_path: String,
    pub media_type: String,
    pub write_mode: CoreArtifactWriteMode,
}

/// Completed streamed artifact plan item. Content was emitted incrementally.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreStreamArtifactPlanItem {
    pub artifact_id: String,
    pub relative_path: String,
    pub media_type: String,
    pub write_mode: CoreArtifactWriteMode,
    pub byte_count: u64,
    pub sha256: String,
}

/// Final health-free stream evidence.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreStreamDescriptor {
    pub mode: CoreStreamMode,
    pub byte_count: u64,
    pub sha256: String,
    pub item_count: u64,
    pub artifact: Option<CoreStreamArtifactPlanItem>,
}

/// Final framing chunk and completed stream descriptor.
#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CoreStreamFinish {
    pub chunk: Vec<u8>,
    pub descriptor: CoreStreamDescriptor,
}

impl From<healthmd_core::BuildInfo> for CoreBuildInfo {
    fn from(value: healthmd_core::BuildInfo) -> Self {
        Self {
            crate_version: value.crate_version,
            core_source_revision: value.core_source_revision,
            registry_sha256: value.registry_sha256,
            core_api_version: value.core_api_version,
            semantic_input_version: value.semantic_input_version,
            canonical_model_version: value.canonical_model_version,
            registry_version: value.registry_version,
            render_input_version: value.render_input_version,
            artifact_plan_version: value.artifact_plan_version,
            render_profile_revision: value.render_profile_revision,
            persisted_state_version: value.persisted_state_version,
        }
    }
}

impl From<healthmd_protocol::foundation::DirectProtocolInfo> for CoreDirectProtocolInfo {
    fn from(value: healthmd_protocol::foundation::DirectProtocolInfo) -> Self {
        Self {
            protocol_api_revision: value.protocol_api_revision,
            direct_pairing_protocol_version: value.direct_pairing_protocol_version,
            supported_pairing_protocol_versions: value.supported_pairing_protocol_versions,
            apple_application_protocol_version: value.apple_application_protocol_version,
            android_application_protocol_version: value.android_application_protocol_version,
            manual_ip_port: value.manual_ip_port,
            maximum_control_json_bytes: value.maximum_control_json_bytes,
            transfer_protocol_version: value.transfer_protocol_version,
            transfer_frame_header_bytes: value.transfer_frame_header_bytes,
            maximum_chunk_bytes: value.maximum_chunk_bytes,
            maximum_transfer_frame_bytes: value.maximum_transfer_frame_bytes,
            minimum_partition_bytes: value.minimum_partition_bytes,
            preferred_partition_bytes: value.preferred_partition_bytes,
            maximum_partition_bytes: value.maximum_partition_bytes,
            preferred_in_flight_chunks: value.preferred_in_flight_chunks,
            maximum_in_flight_chunks: value.maximum_in_flight_chunks,
            pairing_code_lifetime_seconds: value.pairing_code_lifetime_seconds,
            durable_job_lifetime_seconds: value.durable_job_lifetime_seconds,
        }
    }
}

impl From<CoreDirectTransferChunk> for healthmd_protocol::foundation::OwnedTransferChunk {
    fn from(value: CoreDirectTransferChunk) -> Self {
        Self {
            transfer_id: value.transfer_id,
            sequence: value.sequence,
            sha256: value.sha256,
            chunk_bytes: value.chunk_bytes,
        }
    }
}

impl From<healthmd_protocol::foundation::OwnedTransferChunk> for CoreDirectTransferChunk {
    fn from(value: healthmd_protocol::foundation::OwnedTransferChunk) -> Self {
        Self {
            transfer_id: value.transfer_id,
            sequence: value.sequence,
            sha256: value.sha256,
            chunk_bytes: value.chunk_bytes,
        }
    }
}

impl From<CoreDirectTransferCapabilities>
    for healthmd_protocol::foundation::OwnedTransferCapabilities
{
    fn from(value: CoreDirectTransferCapabilities) -> Self {
        Self {
            protocol_versions: value.protocol_versions,
            binary_frame_versions: value.binary_frame_versions,
            minimum_partition_bytes: value.minimum_partition_bytes,
            preferred_partition_bytes: value.preferred_partition_bytes,
            maximum_partition_bytes: value.maximum_partition_bytes,
            maximum_in_flight_chunks: value.maximum_in_flight_chunks,
        }
    }
}

impl From<healthmd_protocol::foundation::OwnedTransferCapabilities>
    for CoreDirectTransferCapabilities
{
    fn from(value: healthmd_protocol::foundation::OwnedTransferCapabilities) -> Self {
        Self {
            protocol_versions: value.protocol_versions,
            binary_frame_versions: value.binary_frame_versions,
            minimum_partition_bytes: value.minimum_partition_bytes,
            preferred_partition_bytes: value.preferred_partition_bytes,
            maximum_partition_bytes: value.maximum_partition_bytes,
            maximum_in_flight_chunks: value.maximum_in_flight_chunks,
        }
    }
}

impl From<healthmd_protocol::foundation::OwnedTransferNegotiation>
    for CoreDirectTransferNegotiation
{
    fn from(value: healthmd_protocol::foundation::OwnedTransferNegotiation) -> Self {
        Self {
            protocol_version: value.protocol_version,
            binary_frame_version: value.binary_frame_version,
            partition_target_bytes: value.partition_target_bytes,
            maximum_in_flight_chunks: value.maximum_in_flight_chunks,
        }
    }
}

impl From<CoreDirectPairingProfile> for healthmd_protocol::foundation::PairingProfile {
    fn from(value: CoreDirectPairingProfile) -> Self {
        match value {
            CoreDirectPairingProfile::AppleV1 => Self::AppleV1,
            CoreDirectPairingProfile::AndroidV2 => Self::AndroidV2,
        }
    }
}

impl From<healthmd_core::FixtureValidation> for FixtureValidation {
    fn from(value: healthmd_core::FixtureValidation) -> Self {
        Self {
            fixture_format_version: value.fixture_format_version,
            byte_count: value.byte_count,
            sha256: value.sha256,
        }
    }
}

impl From<healthmd_core::SelfTestReport> for CoreSelfTestReport {
    fn from(value: healthmd_core::SelfTestReport) -> Self {
        Self {
            passed: value.passed,
            build_info: value.build_info.into(),
            fixture: value.fixture.into(),
        }
    }
}

impl From<healthmd_core::CoreError> for HealthmdCoreError {
    fn from(value: healthmd_core::CoreError) -> Self {
        match value {
            healthmd_core::CoreError::InvalidFixtureDigest => Self::InvalidFixtureDigest,
            healthmd_core::CoreError::FixtureTooLarge => Self::FixtureTooLarge,
            healthmd_core::CoreError::FixtureDigestMismatch => Self::FixtureDigestMismatch,
            healthmd_core::CoreError::InvalidFixture => Self::InvalidFixture,
            healthmd_core::CoreError::NonCanonicalFixture => Self::NonCanonicalFixture,
            healthmd_core::CoreError::UnsupportedFixtureFormatVersion => {
                Self::UnsupportedFixtureFormatVersion
            }
            healthmd_core::CoreError::UnsupportedSemanticInputVersion => {
                Self::UnsupportedSemanticInputVersion
            }
            healthmd_core::CoreError::UnsupportedRegistryVersion => {
                Self::UnsupportedRegistryVersion
            }
            healthmd_core::CoreError::UnsupportedPersistedStateVersion => {
                Self::UnsupportedPersistedStateVersion
            }
            healthmd_core::CoreError::InvalidRegistry => Self::InvalidRegistry,
            healthmd_core::CoreError::UnsupportedRegistryProfile => {
                Self::UnsupportedRegistryProfile
            }
            healthmd_core::CoreError::SemanticConfigTooLarge => Self::SemanticConfigTooLarge,
            healthmd_core::CoreError::InvalidSemanticConfig => Self::InvalidSemanticConfig,
            healthmd_core::CoreError::SemanticBatchTooLarge => Self::SemanticBatchTooLarge,
            healthmd_core::CoreError::InvalidSemanticBatch => Self::InvalidSemanticBatch,
            healthmd_core::CoreError::SemanticLimitExceeded => Self::SemanticLimitExceeded,
            healthmd_core::CoreError::SemanticSequenceInvalid => Self::SemanticSequenceInvalid,
            healthmd_core::CoreError::SemanticSessionTerminal => Self::SemanticSessionTerminal,
            healthmd_core::CoreError::UnsupportedSemanticOperation => {
                Self::UnsupportedSemanticOperation
            }
        }
    }
}

/// Coarse, bounded, ephemeral semantic processing session.
#[derive(uniffi::Object)]
pub struct CoreSemanticSession {
    inner: Mutex<healthmd_core::semantic::SemanticSession>,
    cancelled: AtomicBool,
}

#[uniffi::export]
impl CoreSemanticSession {
    /// Process one bounded batch and return canonical semantic-result JSON bytes.
    ///
    /// # Errors
    /// Returns stable semantic contract/session errors or a contained internal panic.
    pub fn process_batch(&self, batch_bytes: &[u8]) -> Result<Vec<u8>, HealthmdCoreError> {
        panic_guard(|| {
            let mut session = self
                .inner
                .lock()
                .map_err(|_| HealthmdCoreError::InternalPanic)?;
            session
                .process_batch(batch_bytes, || self.cancelled.load(Ordering::Acquire))
                .map_err(HealthmdCoreError::from)
        })
    }

    /// Request idempotent cancellation. Processing observes this between bounded record groups.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }
}

/// Coarse, bounded, ephemeral render session.
#[derive(uniffi::Object)]
pub struct CoreRenderSession {
    inner: Mutex<healthmd_core::render::RenderSession>,
    cancelled: AtomicBool,
}

#[uniffi::export]
impl CoreRenderSession {
    /// Process one bounded presentation batch transactionally.
    ///
    /// # Errors
    /// Returns stable render validation/session errors or a contained panic.
    pub fn process_batch(
        &self,
        batch_bytes: &[u8],
    ) -> Result<CoreRenderBatchReceipt, HealthmdRenderError> {
        render_panic_guard(|| {
            let mut session = self
                .inner
                .lock()
                .map_err(|_| HealthmdRenderError::InternalPanic)?;
            session
                .process_batch(batch_bytes, || self.cancelled.load(Ordering::Acquire))
                .map(|receipt| CoreRenderBatchReceipt {
                    next_batch_index: receipt.next_batch_index,
                    days_accepted: receipt.days_accepted,
                    facts_accepted: receipt.facts_accepted,
                    final_batch: receipt.final_batch,
                })
                .map_err(HealthmdRenderError::from)
        })
    }

    /// Finalize all exact artifact bytes and descriptors.
    ///
    /// # Errors
    /// Returns stable render/path/output errors or a contained panic.
    pub fn finish(&self) -> Result<CoreArtifactPlan, HealthmdRenderError> {
        render_panic_guard(|| {
            let mut session = self
                .inner
                .lock()
                .map_err(|_| HealthmdRenderError::InternalPanic)?;
            session
                .finish(|| self.cancelled.load(Ordering::Acquire))
                .map(CoreArtifactPlan::from)
                .map_err(HealthmdRenderError::from)
        })
    }

    /// Request idempotent lock-independent cancellation.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }
}

/// Bounded lossless stream that never retains already-returned output chunks.
#[derive(uniffi::Object)]
pub struct CoreLosslessArtifactStream {
    inner: Mutex<healthmd_core::render::LosslessArtifactStream>,
    cancelled: AtomicBool,
}

#[uniffi::export]
impl CoreLosslessArtifactStream {
    /// Emit one bounded raw chunk.
    ///
    /// # Errors
    /// Returns stable stream sequence, bound, cancellation, or contained-panic errors.
    pub fn push_raw(&self, bytes: &[u8]) -> Result<Vec<u8>, HealthmdRenderError> {
        render_panic_guard(|| {
            self.inner
                .lock()
                .map_err(|_| HealthmdRenderError::InternalPanic)?
                .push_raw(bytes, || self.cancelled.load(Ordering::Acquire))
                .map_err(HealthmdRenderError::from)
        })
    }

    /// Emit one bounded JSON-array item.
    ///
    /// # Errors
    /// Returns stable stream validation, bound, cancellation, or contained-panic errors.
    pub fn push_json_item(&self, bytes: &[u8]) -> Result<Vec<u8>, HealthmdRenderError> {
        render_panic_guard(|| {
            self.inner
                .lock()
                .map_err(|_| HealthmdRenderError::InternalPanic)?
                .push_json_item(bytes, || self.cancelled.load(Ordering::Acquire))
                .map_err(HealthmdRenderError::from)
        })
    }

    /// Emit one bounded RFC 4180 row.
    ///
    /// # Errors
    /// Returns stable stream validation, bound, cancellation, or contained-panic errors.
    pub fn push_rfc4180_row(&self, fields: &[String]) -> Result<Vec<u8>, HealthmdRenderError> {
        render_panic_guard(|| {
            self.inner
                .lock()
                .map_err(|_| HealthmdRenderError::InternalPanic)?
                .push_rfc4180_row(fields, || self.cancelled.load(Ordering::Acquire))
                .map_err(HealthmdRenderError::from)
        })
    }

    /// Finalize framing and checksum evidence.
    ///
    /// # Errors
    /// Returns stable terminal, cancellation, bound, or contained-panic errors.
    pub fn finish(&self) -> Result<CoreStreamFinish, HealthmdRenderError> {
        render_panic_guard(|| {
            self.inner
                .lock()
                .map_err(|_| HealthmdRenderError::InternalPanic)?
                .finish(|| self.cancelled.load(Ordering::Acquire))
                .map(CoreStreamFinish::from)
                .map_err(HealthmdRenderError::from)
        })
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }
}

impl From<healthmd_core::render::ArtifactPlan> for CoreArtifactPlan {
    fn from(value: healthmd_core::render::ArtifactPlan) -> Self {
        Self {
            schema: value.schema,
            artifact_plan_version: value.artifact_plan_version,
            request_id: value.request_id,
            session_id: value.session_id,
            profile: core_profile(value.profile),
            items: value
                .items
                .into_iter()
                .map(CoreArtifactPlanItem::from)
                .collect(),
            total_byte_count: value.total_byte_count,
        }
    }
}

impl From<healthmd_core::render::ArtifactPlanItem> for CoreArtifactPlanItem {
    fn from(value: healthmd_core::render::ArtifactPlanItem) -> Self {
        Self {
            artifact_id: value.artifact_id,
            relative_path: value.relative_path,
            media_type: value.media_type,
            write_mode: core_write_mode(value.write_mode),
            content: value.content,
            byte_count: value.byte_count,
            sha256: value.sha256,
        }
    }
}

impl From<healthmd_core::render::StreamFinish> for CoreStreamFinish {
    fn from(value: healthmd_core::render::StreamFinish) -> Self {
        Self {
            chunk: value.chunk,
            descriptor: CoreStreamDescriptor::from(value.descriptor),
        }
    }
}

impl From<healthmd_core::render::StreamDescriptor> for CoreStreamDescriptor {
    fn from(value: healthmd_core::render::StreamDescriptor) -> Self {
        Self {
            mode: match value.mode {
                healthmd_core::render::StreamMode::RawBytes => CoreStreamMode::RawBytes,
                healthmd_core::render::StreamMode::JsonArray => CoreStreamMode::JsonArray,
                healthmd_core::render::StreamMode::Rfc4180Rows => CoreStreamMode::Rfc4180Rows,
            },
            byte_count: value.byte_count,
            sha256: value.sha256,
            item_count: value.item_count,
            artifact: value.artifact.map(CoreStreamArtifactPlanItem::from),
        }
    }
}

impl From<healthmd_core::render::StreamArtifactPlanItem> for CoreStreamArtifactPlanItem {
    fn from(value: healthmd_core::render::StreamArtifactPlanItem) -> Self {
        Self {
            artifact_id: value.artifact_id,
            relative_path: value.relative_path,
            media_type: value.media_type,
            write_mode: core_write_mode(value.write_mode),
            byte_count: value.byte_count,
            sha256: value.sha256,
        }
    }
}

const fn core_write_mode(mode: healthmd_core::render::WriteMode) -> CoreArtifactWriteMode {
    match mode {
        healthmd_core::render::WriteMode::Overwrite => CoreArtifactWriteMode::Overwrite,
        healthmd_core::render::WriteMode::Append => CoreArtifactWriteMode::Append,
        healthmd_core::render::WriteMode::MarkdownMerge => CoreArtifactWriteMode::MarkdownMerge,
        healthmd_core::render::WriteMode::ApiPost => CoreArtifactWriteMode::ApiPost,
    }
}

const fn render_write_mode(mode: CoreArtifactWriteMode) -> healthmd_core::render::WriteMode {
    match mode {
        CoreArtifactWriteMode::Overwrite => healthmd_core::render::WriteMode::Overwrite,
        CoreArtifactWriteMode::Append => healthmd_core::render::WriteMode::Append,
        CoreArtifactWriteMode::MarkdownMerge => healthmd_core::render::WriteMode::MarkdownMerge,
        CoreArtifactWriteMode::ApiPost => healthmd_core::render::WriteMode::ApiPost,
    }
}

const fn semantic_profile(
    profile: CoreMetricRegistryProfile,
) -> healthmd_core::semantic::SemanticProfile {
    match profile {
        CoreMetricRegistryProfile::AppleHealthDataV7 => {
            healthmd_core::semantic::SemanticProfile::AppleHealthDataV7
        }
        CoreMetricRegistryProfile::AndroidFrozenV4 => {
            healthmd_core::semantic::SemanticProfile::AndroidFrozenV4
        }
        CoreMetricRegistryProfile::AndroidAnalyticalV5 => {
            healthmd_core::semantic::SemanticProfile::AndroidAnalyticalV5
        }
    }
}

const fn core_profile(
    profile: healthmd_core::semantic::SemanticProfile,
) -> CoreMetricRegistryProfile {
    match profile {
        healthmd_core::semantic::SemanticProfile::AppleHealthDataV7 => {
            CoreMetricRegistryProfile::AppleHealthDataV7
        }
        healthmd_core::semantic::SemanticProfile::AndroidFrozenV4 => {
            CoreMetricRegistryProfile::AndroidFrozenV4
        }
        healthmd_core::semantic::SemanticProfile::AndroidAnalyticalV5 => {
            CoreMetricRegistryProfile::AndroidAnalyticalV5
        }
    }
}

impl From<CoreMetricRegistryProfile> for healthmd_core::registry::MetricRegistryProfile {
    fn from(value: CoreMetricRegistryProfile) -> Self {
        match value {
            CoreMetricRegistryProfile::AppleHealthDataV7 => Self::AppleHealthDataV7,
            CoreMetricRegistryProfile::AndroidFrozenV4 => Self::AndroidFrozenV4,
            CoreMetricRegistryProfile::AndroidAnalyticalV5 => Self::AndroidAnalyticalV5,
        }
    }
}

impl From<healthmd_core::registry::MetricRegistrySnapshot> for CoreMetricRegistrySnapshot {
    fn from(value: healthmd_core::registry::MetricRegistrySnapshot) -> Self {
        Self {
            registry_version: value.registry_version,
            registry_sha256: value.registry_sha256,
            profile_id: value.profile_id,
            public_profile_id: value.public_profile_id,
            public_schema: value.public_schema,
            public_schema_version: value.public_schema_version,
            profile_revision: value.profile_revision,
            categories: value
                .categories
                .into_iter()
                .map(|category| CoreRegistryCategory {
                    category_id: category.category_id,
                    label_key: category.label_key,
                    ordinal: category.ordinal,
                })
                .collect(),
            metrics: value
                .metrics
                .into_iter()
                .map(|metric| CoreRegistryMetric {
                    semantic_id: metric.semantic_id,
                    selection_id: metric.selection_id,
                    label_key: metric.label_key,
                    reference_name: metric.reference_name,
                    category_id: metric.category_id,
                    unit: metric.unit,
                    kind: metric.kind,
                    source_aggregation: metric.source_aggregation,
                    default_enabled: metric.default_enabled,
                    archive_only: metric.archive_only,
                    availability_key: metric.availability_key,
                    authorization_key: metric.authorization_key,
                    capability_id: metric.capability_id,
                    source_selector: metric.source_selector,
                    related_semantic_ids: metric.related_semantic_ids,
                    ordinal: metric.ordinal,
                })
                .collect(),
            unavailable_metrics: value
                .unavailable_metrics
                .into_iter()
                .map(|metric| CoreRegistryUnavailableMetric {
                    selection_id: metric.selection_id,
                    category_id: metric.category_id,
                    label_key: metric.label_key,
                    reason_key: metric.reason_key,
                })
                .collect(),
            outputs: value
                .outputs
                .into_iter()
                .map(|output| CoreRegistryOutput {
                    selection_ids: output.selection_ids,
                    surface: output.surface,
                    key: output.key,
                    unit: output.unit,
                    daily_aggregation: output.daily_aggregation,
                    rollup: output.rollup,
                    alias_kind: output.alias_kind,
                    platform_native: output.platform_native,
                    condition: output.condition,
                    enabled_by_default: output.enabled_by_default,
                    ordinal: output.ordinal,
                })
                .collect(),
        }
    }
}

/// Return independently versioned direct-protocol API information and deployed constants.
///
/// # Errors
/// Returns a contained internal panic without exposing native state.
#[uniffi::export]
pub fn get_direct_protocol_info() -> Result<CoreDirectProtocolInfo, HealthmdProtocolError> {
    protocol_panic_guard(|| Ok(healthmd_protocol::foundation::direct_protocol_info().into()))
}

/// Validate and fingerprint exact canonical Foundation-compatible Apple-v1 request bytes.
///
/// # Errors
/// Returns stable bounded/profile/version/canonical JSON errors or a contained panic.
#[uniffi::export]
pub fn fingerprint_apple_v1_direct_request(
    request_bytes: &[u8],
) -> Result<String, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        healthmd_protocol::foundation::apple_v1_request_fingerprint(request_bytes)
            .map_err(HealthmdProtocolError::from)
    })
}

/// Validate and fingerprint exact canonical Android-v2 request bytes.
///
/// # Errors
/// Returns stable bounded/profile/canonical JSON errors or a contained panic.
#[uniffi::export]
pub fn fingerprint_android_v2_direct_request(
    request_bytes: &[u8],
) -> Result<String, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        healthmd_protocol::foundation::android_v2_request_fingerprint(request_bytes)
            .map_err(HealthmdProtocolError::from)
    })
}

/// Strictly validate a complete Apple-v1 `DirectMessage` and return canonical owned bytes.
///
/// # Errors
/// Returns stable bounded/model/version errors or a contained panic.
#[uniffi::export]
pub fn canonicalize_apple_v1_direct_message(
    message_bytes: &[u8],
) -> Result<Vec<u8>, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        healthmd_protocol::foundation::canonicalize_apple_v1_message(message_bytes)
            .map_err(HealthmdProtocolError::from)
    })
}

/// Strictly validate a complete Android-v2 `Envelope` and return canonical owned bytes.
///
/// # Errors
/// Returns stable bounded/model/version errors or a contained panic.
#[uniffi::export]
pub fn canonicalize_android_v2_direct_envelope(
    envelope_bytes: &[u8],
) -> Result<Vec<u8>, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        healthmd_protocol::foundation::canonicalize_android_v2_envelope(envelope_bytes)
            .map_err(HealthmdProtocolError::from)
    })
}

/// Encode one opaque chunk with the deployed `HMDDIRCT` frame layout.
///
/// # Errors
/// Returns stable metadata/size/digest errors or a contained panic.
#[uniffi::export]
pub fn encode_direct_transfer_chunk(
    chunk: CoreDirectTransferChunk,
) -> Result<Vec<u8>, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        healthmd_protocol::foundation::encode_owned_transfer_chunk(&chunk.into())
            .map_err(HealthmdProtocolError::from)
    })
}

/// Decode and validate one deployed `HMDDIRCT` frame without interpreting its opaque chunk bytes.
///
/// # Errors
/// Returns stable frame/size/version/digest errors or a contained panic.
#[uniffi::export]
pub fn decode_direct_transfer_chunk(
    frame_bytes: &[u8],
) -> Result<CoreDirectTransferChunk, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        healthmd_protocol::foundation::decode_owned_transfer_chunk(frame_bytes)
            .map(CoreDirectTransferChunk::from)
            .map_err(HealthmdProtocolError::from)
    })
}

/// Return the deployed transfer capabilities used by the existing pure negotiation.
///
/// # Errors
/// Returns a contained internal panic.
#[uniffi::export]
pub fn get_default_direct_transfer_capabilities()
-> Result<CoreDirectTransferCapabilities, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        Ok(healthmd_protocol::foundation::OwnedTransferCapabilities::default().into())
    })
}

/// Negotiate two owned capability records with the existing pure Rust algorithm.
///
/// # Errors
/// Returns stable invalid/incompatible capability errors or a contained panic.
#[uniffi::export]
pub fn negotiate_direct_transfer(
    local: CoreDirectTransferCapabilities,
    peer: CoreDirectTransferCapabilities,
) -> Result<CoreDirectTransferNegotiation, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        healthmd_protocol::foundation::negotiate_owned_transfer(&local.into(), &peer.into())
            .map(CoreDirectTransferNegotiation::from)
            .map_err(HealthmdProtocolError::from)
    })
}

/// Verify one reviewed new-pairing client transcript in constant time.
///
/// Selected Rust-owned vectors are zeroized on return. Generated language/FFI transport buffers are
/// outside that guarantee, so this remains a conformance surface rather than production key custody.
/// No trust state is read or written.
///
/// # Errors
/// Returns only stable profile/code/fixed-width errors or a contained panic.
#[uniffi::export]
pub fn verify_direct_pairing_client_transcript(
    request: CoreDirectPairingVerifierRequest,
) -> Result<bool, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        let CoreDirectPairingVerifierRequest {
            profile,
            pairing_code_bytes,
            client_installation_id,
            client_public_key,
            client_nonce,
            expected_verifier,
        } = request;
        let pairing_code_bytes = Zeroizing::new(pairing_code_bytes);
        let client_public_key = Zeroizing::new(client_public_key);
        let client_nonce = Zeroizing::new(client_nonce);
        let expected_verifier = Zeroizing::new(expected_verifier);
        let pairing_code = std::str::from_utf8(&pairing_code_bytes)
            .map_err(|_| HealthmdProtocolError::InvalidPairingCode)?;
        healthmd_protocol::foundation::verify_pairing_client_transcript(
            profile.into(),
            pairing_code,
            &client_installation_id,
            &client_public_key,
            &client_nonce,
            &expected_verifier,
        )
        .map_err(HealthmdProtocolError::from)
    })
}

/// Derive the reviewed deployed session key from three fixed 32-byte inputs.
///
/// Selected Rust-owned input/result vectors are zeroized. Generated language/FFI transport buffers
/// are outside that guarantee; the caller owns and must promptly overwrite the returned native byte
/// array. This API performs no sequence, seal, open, or persistence work and is not production key
/// custody until a dedicated secret-FFI review is complete.
///
/// # Errors
/// Returns a stable fixed-width error or a contained panic.
#[uniffi::export]
pub fn derive_direct_session_key(
    request: CoreDirectSessionKeyRequest,
) -> Result<Vec<u8>, HealthmdProtocolError> {
    protocol_panic_guard(|| {
        let shared_secret = Zeroizing::new(request.shared_secret);
        let client_nonce = Zeroizing::new(request.client_nonce);
        let server_nonce = Zeroizing::new(request.server_nonce);
        let key = Zeroizing::new(
            healthmd_protocol::foundation::derive_session_key(
                &shared_secret,
                &client_nonce,
                &server_nonce,
            )
            .map_err(HealthmdProtocolError::from)?,
        );
        Ok(key.to_vec())
    })
}

/// Create one bounded semantic session from strict versioned JSON configuration.
///
/// # Errors
/// Returns a stable configuration/profile error or a contained internal panic.
#[uniffi::export]
pub fn create_semantic_session(
    config_bytes: &[u8],
) -> Result<Arc<CoreSemanticSession>, HealthmdCoreError> {
    panic_guard(|| {
        let session = healthmd_core::semantic::SemanticSession::from_json(config_bytes)
            .map_err(HealthmdCoreError::from)?;
        Ok(Arc::new(CoreSemanticSession {
            inner: Mutex::new(session),
            cancelled: AtomicBool::new(false),
        }))
    })
}

/// Create one bounded renderer from strict configuration and completed semantic-result bytes.
///
/// # Errors
/// Returns stable configuration/profile/result errors or a contained panic.
#[uniffi::export]
pub fn create_render_session(
    config_bytes: &[u8],
    semantic_result_bytes: &[u8],
) -> Result<Arc<CoreRenderSession>, HealthmdRenderError> {
    render_panic_guard(|| {
        let session =
            healthmd_core::render::RenderSession::from_json(config_bytes, semantic_result_bytes)
                .map_err(HealthmdRenderError::from)?;
        Ok(Arc::new(CoreRenderSession {
            inner: Mutex::new(session),
            cancelled: AtomicBool::new(false),
        }))
    })
}

/// Create a bounded lossless encoder in one explicit framing mode.
#[uniffi::export]
pub fn create_lossless_artifact_stream(mode: CoreStreamMode) -> Arc<CoreLosslessArtifactStream> {
    let mode = match mode {
        CoreStreamMode::RawBytes => healthmd_core::render::StreamMode::RawBytes,
        CoreStreamMode::JsonArray => healthmd_core::render::StreamMode::JsonArray,
        CoreStreamMode::Rfc4180Rows => healthmd_core::render::StreamMode::Rfc4180Rows,
    };
    Arc::new(CoreLosslessArtifactStream {
        inner: Mutex::new(healthmd_core::render::LosslessArtifactStream::new(mode)),
        cancelled: AtomicBool::new(false),
    })
}

/// Create a bounded stream with a destination-neutral artifact-plan identity.
///
/// # Errors
/// Returns stable configuration/path errors before any bytes are accepted.
#[uniffi::export]
pub fn create_planned_lossless_artifact_stream(
    mode: CoreStreamMode,
    artifact: CoreStreamArtifactConfig,
) -> Result<Arc<CoreLosslessArtifactStream>, HealthmdRenderError> {
    render_panic_guard(|| {
        let mode = match mode {
            CoreStreamMode::RawBytes => healthmd_core::render::StreamMode::RawBytes,
            CoreStreamMode::JsonArray => healthmd_core::render::StreamMode::JsonArray,
            CoreStreamMode::Rfc4180Rows => healthmd_core::render::StreamMode::Rfc4180Rows,
        };
        let stream = healthmd_core::render::LosslessArtifactStream::new_planned(
            mode,
            healthmd_core::render::StreamArtifactConfig {
                request_id: artifact.request_id,
                session_id: artifact.session_id,
                profile: semantic_profile(artifact.profile),
                relative_path: artifact.relative_path,
                media_type: artifact.media_type,
                write_mode: render_write_mode(artifact.write_mode),
            },
        )
        .map_err(HealthmdRenderError::from)?;
        Ok(Arc::new(CoreLosslessArtifactStream {
            inner: Mutex::new(stream),
            cancelled: AtomicBool::new(false),
        }))
    })
}

/// Pure profile-exact managed-Markdown merge. Destination reads and writes remain native.
///
/// # Errors
/// Returns stable size/validation errors or a contained panic.
#[uniffi::export]
pub fn merge_profile_rendered_markdown(
    profile: CoreMetricRegistryProfile,
    existing: &str,
    generated: &str,
    preserve_preamble: bool,
) -> Result<String, HealthmdRenderError> {
    render_panic_guard(|| {
        healthmd_core::render::merge_profile_markdown(
            semantic_profile(profile),
            existing,
            generated,
            preserve_preamble,
        )
        .map_err(HealthmdRenderError::from)
    })
}

/// Backward-compatible Apple-style managed-Markdown merge.
///
/// # Errors
/// Returns stable size/validation errors or a contained panic.
#[uniffi::export]
pub fn merge_rendered_markdown(
    existing: &str,
    generated: &str,
) -> Result<String, HealthmdRenderError> {
    render_panic_guard(|| {
        healthmd_core::render::merge_markdown(existing, generated)
            .map_err(HealthmdRenderError::from)
    })
}

/// Return independently versioned build information.
///
/// # Errors
///
/// Returns [`HealthmdCoreError::InternalPanic`] if the guarded Rust operation panics.
#[uniffi::export]
pub fn get_build_info() -> Result<CoreBuildInfo, HealthmdCoreError> {
    panic_guard(|| Ok(healthmd_core::build_info().into()))
}

/// Run the deterministic embedded self-test.
///
/// # Errors
///
/// Returns a stable fixture error if the embedded fixture is inconsistent, or
/// [`HealthmdCoreError::InternalPanic`] if the guarded Rust operation panics.
#[uniffi::export]
pub fn run_self_test() -> Result<CoreSelfTestReport, HealthmdCoreError> {
    panic_guard(|| {
        healthmd_core::self_test()
            .map(CoreSelfTestReport::from)
            .map_err(HealthmdCoreError::from)
    })
}

/// Return one complete immutable registry profile for native caching.
///
/// # Errors
///
/// Returns a stable registry/version error or [`HealthmdCoreError::InternalPanic`].
#[uniffi::export]
pub fn get_metric_registry(
    profile: CoreMetricRegistryProfile,
    expected_registry_version: u32,
) -> Result<CoreMetricRegistrySnapshot, HealthmdCoreError> {
    panic_guard(|| {
        healthmd_core::registry::metric_registry_snapshot(profile.into(), expected_registry_version)
            .map(CoreMetricRegistrySnapshot::from)
            .map_err(HealthmdCoreError::from)
    })
}

/// Validate exact bounded fixture bytes without returning fixture content.
///
/// # Errors
///
/// Returns a stable fixture error for invalid input or an unsupported version, or
/// [`HealthmdCoreError::InternalPanic`] if the guarded Rust operation panics.
#[uniffi::export]
pub fn validate_fixture(
    fixture_bytes: &[u8],
    expected_sha256: &str,
) -> Result<FixtureValidation, HealthmdCoreError> {
    panic_guard(|| {
        healthmd_core::validate_fixture(fixture_bytes, expected_sha256)
            .map(FixtureValidation::from)
            .map_err(HealthmdCoreError::from)
    })
}

fn panic_guard<T>(
    operation: impl FnOnce() -> Result<T, HealthmdCoreError>,
) -> Result<T, HealthmdCoreError> {
    catch_unwind(AssertUnwindSafe(operation)).unwrap_or(Err(HealthmdCoreError::InternalPanic))
}

fn render_panic_guard<T>(
    operation: impl FnOnce() -> Result<T, HealthmdRenderError>,
) -> Result<T, HealthmdRenderError> {
    catch_unwind(AssertUnwindSafe(operation)).unwrap_or(Err(HealthmdRenderError::InternalPanic))
}

fn protocol_panic_guard<T>(
    operation: impl FnOnce() -> Result<T, HealthmdProtocolError>,
) -> Result<T, HealthmdProtocolError> {
    catch_unwind(AssertUnwindSafe(operation)).unwrap_or(Err(HealthmdProtocolError::InternalPanic))
}

#[cfg(test)]
mod tests {
    use base64::{Engine as _, engine::general_purpose::STANDARD};

    use super::*;

    const FIXTURE: &[u8] = include_bytes!("../../healthmd-core/fixtures/m1-self-test.json");
    const FIXTURE_SHA256: &str = "afb53fde32e77e4b8272f021c262a42b7f943f8604ca7fde4c6dbf7ed977a799";

    #[test]
    fn ffi_api_maps_coarse_core_results() {
        let info = get_build_info().expect("build info should succeed");
        let self_test = run_self_test().expect("self-test should succeed");
        let fixture = validate_fixture(FIXTURE, FIXTURE_SHA256).expect("fixture should validate");

        assert!(!info.core_source_revision.is_empty());
        assert_eq!(info.registry_sha256, healthmd_core::REGISTRY_SHA256);
        assert_eq!(info.core_api_version, 4);
        assert_eq!(info.semantic_input_version, 1);
        assert_eq!(info.canonical_model_version, 1);
        assert_eq!(info.registry_version, 1);
        assert_eq!(info.render_input_version, 1);
        assert_eq!(info.artifact_plan_version, 1);
        assert_eq!(info.render_profile_revision, 1);
        assert_eq!(info.persisted_state_version, 1);
        assert!(self_test.passed);
        assert_eq!(self_test.build_info, info);
        assert_eq!(self_test.fixture, fixture);

        let apple = get_metric_registry(CoreMetricRegistryProfile::AppleHealthDataV7, 1)
            .expect("Apple registry should project");
        let frozen = get_metric_registry(CoreMetricRegistryProfile::AndroidFrozenV4, 1)
            .expect("Android registry should project");
        assert_eq!((apple.metrics.len(), apple.outputs.len()), (230, 226));
        assert_eq!(
            (frozen.metrics.len(), frozen.unavailable_metrics.len()),
            (106, 102)
        );
        assert_eq!(apple.registry_sha256, info.registry_sha256);
    }

    #[test]
    fn coarse_semantic_session_processes_and_cancels() {
        let config = format!(
            concat!(
                "{{\"schema\":\"healthmd.semantic_session_config\",",
                "\"semantic_input_version\":1,\"canonical_model_version\":1,",
                "\"registry_version\":1,\"registry_sha256\":\"{}\",\"profile_revision\":1,",
                "\"session_id\":\"ffi-test\",\"profile\":\"apple_health_data_v7\",",
                "\"calendar_time_zone\":\"UTC\",",
                "\"selected_selection_ids\":[\"steps\"],\"disabled_output_keys\":[],",
                "\"retain_platform_extensions\":false,\"rollup_periods\":[]}}"
            ),
            healthmd_core::REGISTRY_SHA256
        );
        let session = create_semantic_session(config.as_bytes()).expect("session");
        session.cancel();
        let result = session
            .process_batch(b"private bytes never parsed after cancellation")
            .expect("cancel result");
        let result: serde_json::Value = serde_json::from_slice(&result).expect("result JSON");
        assert_eq!(result["state"], "cancelled");
        assert_eq!(
            session.process_batch(b"{}"),
            Err(HealthmdCoreError::SemanticSessionTerminal)
        );
    }

    #[test]
    fn render_stream_and_merge_cross_the_coarse_boundary() {
        let stream = create_lossless_artifact_stream(CoreStreamMode::JsonArray);
        let first = stream.push_json_item(br#"{"a":1}"#).expect("item");
        let second = stream.push_json_item(b"2").expect("item");
        let finish = stream.finish().expect("finish");
        assert_eq!([first, second, finish.chunk].concat(), br#"[{"a":1},2]"#);
        assert_eq!(finish.descriptor.mode, CoreStreamMode::JsonArray);
        assert_eq!(finish.descriptor.item_count, 2);
        assert!(finish.descriptor.artifact.is_none());
        assert_eq!(stream.finish(), Err(HealthmdRenderError::StreamTerminal));

        let planned = create_planned_lossless_artifact_stream(
            CoreStreamMode::RawBytes,
            CoreStreamArtifactConfig {
                request_id: "ffi-stream".to_owned(),
                session_id: "ffi-session".to_owned(),
                profile: CoreMetricRegistryProfile::AppleHealthDataV7,
                relative_path: "Health/Raw/archive.json".to_owned(),
                media_type: "application/json".to_owned(),
                write_mode: CoreArtifactWriteMode::Overwrite,
            },
        )
        .expect("planned stream");
        assert_eq!(planned.push_raw(b"abc").unwrap(), b"abc");
        let artifact = planned.finish().unwrap().descriptor.artifact.unwrap();
        assert_eq!(artifact.relative_path, "Health/Raw/archive.json");
        assert_eq!(artifact.byte_count, 3);
        assert_eq!(artifact.artifact_id.len(), 64);

        let merged = merge_rendered_markdown(
            "---\ndate: old\nuser: keep\n---\n## Sleep\nold\n",
            "---\ndate: new\n---\n## Sleep\nnew\n",
        )
        .expect("merge");
        assert!(merged.contains("user: keep"));
        assert!(merged.contains("## Sleep\nnew"));
        assert!(!merged.contains("## Sleep\nold"));
    }

    #[test]
    fn ffi_errors_remain_stable_and_health_free() {
        let private_value = b"private-health-value";
        let error = validate_fixture(private_value, &"0".repeat(64))
            .expect_err("digest mismatch should fail");

        assert_eq!(error, HealthmdCoreError::FixtureDigestMismatch);
        assert_eq!(error.to_string(), "fixture digest does not match");
        assert!(!error.to_string().contains("private-health-value"));
    }

    #[test]
    fn protocol_foundation_crosses_the_ffi_boundary_with_exact_fixture_bytes() {
        let info = get_direct_protocol_info().expect("protocol info");
        assert_eq!(info.protocol_api_revision, 1);
        assert_eq!(info.direct_pairing_protocol_version, 1);
        assert_eq!(info.supported_pairing_protocol_versions, [1, 2]);
        assert_eq!(info.apple_application_protocol_version, 1);
        assert_eq!(info.android_application_protocol_version, 2);
        assert_eq!(info.maximum_chunk_bytes, 512 * 1_024);

        let fixture: serde_json::Value = serde_json::from_str(include_str!(
            "../../healthmd-protocol/tests/fixtures/swift-direct-v1.json"
        ))
        .unwrap();
        let request = STANDARD
            .decode(fixture["request_json_base64"].as_str().unwrap())
            .unwrap();
        assert_eq!(
            fingerprint_apple_v1_direct_request(&request).unwrap(),
            fixture["request_fingerprint"].as_str().unwrap()
        );
        let message = STANDARD
            .decode(fixture["request_message_json_base64"].as_str().unwrap())
            .unwrap();
        assert_eq!(
            canonicalize_apple_v1_direct_message(&message).unwrap(),
            message
        );

        let android_fixture: serde_json::Value = serde_json::from_str(include_str!(
            "../../healthmd-protocol/tests/fixtures/kotlin-direct-v2.json"
        ))
        .unwrap();
        let android_request = STANDARD
            .decode(android_fixture["request_json_base64"].as_str().unwrap())
            .unwrap();
        assert_eq!(
            fingerprint_android_v2_direct_request(&android_request).unwrap(),
            android_fixture["request_fingerprint"].as_str().unwrap()
        );
        let envelope = STANDARD
            .decode(
                android_fixture["status_request_envelope_json_base64"]
                    .as_str()
                    .unwrap(),
            )
            .unwrap();
        assert_eq!(
            canonicalize_android_v2_direct_envelope(&envelope).unwrap(),
            envelope
        );
    }

    #[test]
    fn transfer_negotiation_and_frame_round_trip_use_owned_records() {
        let capabilities = get_default_direct_transfer_capabilities().unwrap();
        assert_eq!(
            negotiate_direct_transfer(capabilities.clone(), capabilities).unwrap(),
            CoreDirectTransferNegotiation {
                protocol_version: 1,
                binary_frame_version: 1,
                partition_target_bytes: 48 * 1_024 * 1_024,
                maximum_in_flight_chunks: 4,
            }
        );

        let payload = b"opaque protocol fixture".to_vec();
        let chunk = CoreDirectTransferChunk {
            transfer_id: "11111111-2222-4333-8444-555555555555".to_owned(),
            sequence: 1,
            sha256: healthmd_protocol::transfer::sha256_hex(&payload),
            chunk_bytes: payload,
        };
        let frame = encode_direct_transfer_chunk(chunk.clone()).unwrap();
        assert_eq!(decode_direct_transfer_chunk(&frame).unwrap(), chunk);
        for length in 0..frame.len() {
            assert!(decode_direct_transfer_chunk(&frame[..length]).is_err());
        }
    }

    #[test]
    fn reviewed_pairing_and_session_vectors_cross_json_free_boundary() {
        let pairing_verifier =
            decode_hex("9dadfaf54d6729b004aa0a6344f7df42b4de0093cbf5cca6fe62376acbad00df");
        assert!(
            verify_direct_pairing_client_transcript(CoreDirectPairingVerifierRequest {
                profile: CoreDirectPairingProfile::AppleV1,
                pairing_code_bytes: b"123456".to_vec(),
                client_installation_id: "abcdefab-cdef-4abc-8def-abcdefabcdef".to_owned(),
                client_public_key: decode_hex(
                    "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f",
                ),
                client_nonce: (0x40_u8..=0x5f).collect(),
                expected_verifier: pairing_verifier,
            })
            .unwrap()
        );

        let key = derive_direct_session_key(CoreDirectSessionKeyRequest {
            shared_secret: decode_hex(
                "9663aa1da97e848a914a436d04163dfbb89178f107f1b5b77ed3854203382854",
            ),
            client_nonce: (0x40_u8..=0x5f).collect(),
            server_nonce: (0x60_u8..=0x7f).collect(),
        })
        .unwrap();
        assert_eq!(
            key,
            decode_hex("47cea6b163b799c16e44a750893eab311521060a7266a59ec054d53f71b698e9")
        );
    }

    #[test]
    fn protocol_errors_have_fixed_codes_messages_and_contained_panics() {
        let private_value = b"private-health-value";
        let error = fingerprint_apple_v1_direct_request(private_value).unwrap_err();
        assert_eq!(error, HealthmdProtocolError::InvalidJson);
        assert_eq!(error.code(), "invalid_protocol_json");
        assert_eq!(error.to_string(), "protocol JSON is invalid");
        assert!(!error.to_string().contains("private-health-value"));

        let panic = protocol_panic_guard(|| -> Result<(), HealthmdProtocolError> {
            panic!("synthetic secret that must not escape")
        });
        assert_eq!(panic, Err(HealthmdProtocolError::InternalPanic));
        assert_eq!(
            panic.unwrap_err().to_string(),
            "shared protocol core failed internally"
        );
    }

    #[test]
    fn panic_guard_contains_panics_without_exposing_payloads() {
        let result = panic_guard(|| -> Result<(), HealthmdCoreError> {
            panic!("synthetic private value that must not escape")
        });

        assert_eq!(result, Err(HealthmdCoreError::InternalPanic));
        assert_eq!(
            result.expect_err("panic should be contained").to_string(),
            "shared core failed internally"
        );
    }

    fn decode_hex(value: &str) -> Vec<u8> {
        value
            .as_bytes()
            .chunks_exact(2)
            .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
            .collect()
    }
}
