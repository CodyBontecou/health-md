//! Bounded, transport-independent protocol foundation for native callers.
//!
//! All operations are synchronous and side-effect free. JSON APIs parse only direct-protocol
//! metadata models; transfer payload bytes remain opaque. Stateful trust, secure-channel
//! sequencing, sealing, and opening deliberately remain outside this API.

use serde::de::DeserializeOwned;
use thiserror::Error;
use uuid::Uuid;

use crate::{
    ANDROID_APPLICATION_PROTOCOL_VERSION, ANDROID_PAIRING_PROTOCOL_VERSION,
    CURRENT_PROTOCOL_VERSION, DEFAULT_MANUAL_IP_PORT, IOS_APPLICATION_PROTOCOL_VERSION,
    JOB_LIFETIME_SECONDS, MAXIMUM_PACKET_BYTES, TRANSFER_FRAME_BYTES, crypto,
    encoding::{SwiftUuid, canonical_json},
    models::{ExportRequest as AppleExportRequest, TransferChunk},
    transfer::{
        TransferError, decode_binary_chunk, encode_binary_chunk, negotiate_transfer,
        request_fingerprint as apple_request_fingerprint,
    },
    v2::{
        Envelope as AndroidEnvelope, ExportRequest as AndroidExportRequest,
        Message as AndroidMessage, request_fingerprint as android_request_fingerprint,
    },
    wire::{DirectMessage, TransferCapabilities},
};

/// Revision of this internal, transport-independent native API.
pub const PROTOCOL_API_REVISION: u32 = 1;
/// Deployed binary transfer-frame version.
pub const TRANSFER_PROTOCOL_VERSION: u32 = 1;
/// Deployed binary transfer-frame header byte count.
pub const TRANSFER_FRAME_HEADER_BYTES: u64 = 66;
/// Maximum complete binary transfer-frame byte count.
pub const MAXIMUM_TRANSFER_FRAME_BYTES: u64 =
    TRANSFER_FRAME_HEADER_BYTES + TRANSFER_FRAME_BYTES as u64;
/// Minimum negotiated partition size.
pub const MINIMUM_PARTITION_BYTES: u64 = 32 * 1_024 * 1_024;
/// Preferred negotiated partition size.
pub const PREFERRED_PARTITION_BYTES: u64 = 48 * 1_024 * 1_024;
/// Maximum negotiated partition size.
pub const MAXIMUM_PARTITION_BYTES: u64 = 64 * 1_024 * 1_024;
/// Preferred bounded in-flight chunk window.
pub const PREFERRED_IN_FLIGHT_CHUNKS: u32 = 4;
/// Maximum negotiated in-flight chunk window.
pub const MAXIMUM_IN_FLIGHT_CHUNKS: u32 = 8;
/// Pairing-code lifetime in seconds.
pub const PAIRING_CODE_LIFETIME_SECONDS: u64 = 10 * 60;

/// Stable, health-free protocol foundation failures.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq)]
pub enum ProtocolFoundationError {
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
}

/// Independently versioned direct-protocol constants for native compatibility checks.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DirectProtocolInfo {
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

/// Return constants without consulting process, network, or persistent state.
#[must_use]
pub fn direct_protocol_info() -> DirectProtocolInfo {
    DirectProtocolInfo {
        protocol_api_revision: PROTOCOL_API_REVISION,
        direct_pairing_protocol_version: u32::from(CURRENT_PROTOCOL_VERSION),
        supported_pairing_protocol_versions: vec![
            u32::from(CURRENT_PROTOCOL_VERSION),
            u32::from(ANDROID_PAIRING_PROTOCOL_VERSION),
        ],
        apple_application_protocol_version: IOS_APPLICATION_PROTOCOL_VERSION as u32,
        android_application_protocol_version: ANDROID_APPLICATION_PROTOCOL_VERSION as u32,
        manual_ip_port: u32::from(DEFAULT_MANUAL_IP_PORT),
        maximum_control_json_bytes: MAXIMUM_PACKET_BYTES as u64,
        transfer_protocol_version: TRANSFER_PROTOCOL_VERSION,
        transfer_frame_header_bytes: TRANSFER_FRAME_HEADER_BYTES,
        maximum_chunk_bytes: TRANSFER_FRAME_BYTES as u64,
        maximum_transfer_frame_bytes: MAXIMUM_TRANSFER_FRAME_BYTES,
        minimum_partition_bytes: MINIMUM_PARTITION_BYTES,
        preferred_partition_bytes: PREFERRED_PARTITION_BYTES,
        maximum_partition_bytes: MAXIMUM_PARTITION_BYTES,
        preferred_in_flight_chunks: PREFERRED_IN_FLIGHT_CHUNKS,
        maximum_in_flight_chunks: MAXIMUM_IN_FLIGHT_CHUNKS,
        pairing_code_lifetime_seconds: PAIRING_CODE_LIFETIME_SECONDS,
        durable_job_lifetime_seconds: JOB_LIFETIME_SECONDS as u64,
    }
}

/// Validate and fingerprint exact canonical Apple-v1 `DirectExportRequest` bytes.
///
/// The input must already use Foundation-compatible key ordering, UUID casing, whole-second UTC
/// dates, base64, optional omission, and compact JSON. The returned digest is lowercase SHA-256.
///
/// # Errors
/// Returns stable size/profile/version/strict-JSON/canonicalization failures.
pub fn apple_v1_request_fingerprint(
    request_bytes: &[u8],
) -> Result<String, ProtocolFoundationError> {
    bounded_json(request_bytes)?;
    reject_android_request_shape(request_bytes)?;
    let request: AppleExportRequest =
        strict_decode(request_bytes, ProtocolFoundationError::InvalidRequest)?;
    validate_apple_request(&request)?;
    require_canonical(request_bytes, &request)?;
    apple_request_fingerprint(&request)
        .map(|fingerprint| fingerprint.sha256)
        .map_err(|_| ProtocolFoundationError::SerializationFailed)
}

/// Validate and fingerprint exact canonical Android-v2 `ExportRequest` bytes.
///
/// # Errors
/// Returns stable size/profile/strict-JSON/canonicalization failures.
pub fn android_v2_request_fingerprint(
    request_bytes: &[u8],
) -> Result<String, ProtocolFoundationError> {
    bounded_json(request_bytes)?;
    reject_apple_request_shape(request_bytes)?;
    let request: AndroidExportRequest =
        strict_decode(request_bytes, ProtocolFoundationError::InvalidRequest)?;
    require_canonical(request_bytes, &request)?;
    android_request_fingerprint(&request).map_err(|_| ProtocolFoundationError::SerializationFailed)
}

/// Strictly decode one complete Apple-v1 `DirectMessage` and return owned canonical bytes.
///
/// Opaque chunk bytes are decoded only as the protocol envelope's `Data` member and are never
/// interpreted as health JSON.
///
/// # Errors
/// Returns stable size, unknown-field, model, version, or serialization failures.
pub fn canonicalize_apple_v1_message(
    message_bytes: &[u8],
) -> Result<Vec<u8>, ProtocolFoundationError> {
    bounded_json(message_bytes)?;
    let message: DirectMessage =
        strict_decode(message_bytes, ProtocolFoundationError::InvalidAppleMessage)?;
    validate_apple_message(&message)?;
    let canonical = encode_bounded(&message)?;
    require_no_unknown_fields(message_bytes, &canonical)?;
    Ok(canonical)
}

/// Strictly decode one complete Android-v2 `Envelope` and return owned canonical bytes.
///
/// # Errors
/// Returns stable size, unknown-field, model, version, or serialization failures.
pub fn canonicalize_android_v2_envelope(
    envelope_bytes: &[u8],
) -> Result<Vec<u8>, ProtocolFoundationError> {
    bounded_json(envelope_bytes)?;
    let envelope: AndroidEnvelope = strict_decode(
        envelope_bytes,
        ProtocolFoundationError::InvalidAndroidEnvelope,
    )?;
    envelope
        .validate_version()
        .map_err(|_| ProtocolFoundationError::UnsupportedProtocolVersion)?;
    validate_android_kotlin_ranges(&envelope.message)?;
    let canonical = encode_bounded(&envelope)?;
    require_no_unknown_fields(envelope_bytes, &canonical)?;
    Ok(canonical)
}

/// One owned, language-neutral transfer chunk. Payload bytes remain opaque.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OwnedTransferChunk {
    pub transfer_id: String,
    pub sequence: u64,
    pub sha256: String,
    pub chunk_bytes: Vec<u8>,
}

/// Encode an owned chunk with the deployed `HMDDIRCT` frame layout.
///
/// # Errors
/// Returns stable metadata, chunk-limit, digest, and framing failures.
pub fn encode_owned_transfer_chunk(
    chunk: &OwnedTransferChunk,
) -> Result<Vec<u8>, ProtocolFoundationError> {
    if chunk.chunk_bytes.len() > TRANSFER_FRAME_BYTES {
        return Err(ProtocolFoundationError::TransferFrameTooLarge);
    }
    let transfer_id = Uuid::parse_str(&chunk.transfer_id)
        .map_err(|_| ProtocolFoundationError::InvalidTransferMetadata)?;
    let sequence = i64::try_from(chunk.sequence)
        .ok()
        .filter(|value| *value > 0 && *value <= i64::from(u32::MAX))
        .ok_or(ProtocolFoundationError::InvalidTransferMetadata)?;
    let model = TransferChunk {
        transfer_id: SwiftUuid(transfer_id),
        sequence,
        data: chunk.chunk_bytes.clone(),
        sha256: chunk.sha256.clone(),
    };
    encode_binary_chunk(&model).map_err(map_transfer_error)
}

/// Decode and fully validate one deployed `HMDDIRCT` frame.
///
/// # Errors
/// Returns stable frame-limit, version, length, sequence, or digest failures.
pub fn decode_owned_transfer_chunk(
    frame_bytes: &[u8],
) -> Result<OwnedTransferChunk, ProtocolFoundationError> {
    if frame_bytes.len() as u64 > MAXIMUM_TRANSFER_FRAME_BYTES {
        return Err(ProtocolFoundationError::TransferFrameTooLarge);
    }
    let chunk = decode_binary_chunk(frame_bytes).map_err(map_transfer_error)?;
    Ok(OwnedTransferChunk {
        transfer_id: chunk.transfer_id.0.hyphenated().to_string().to_lowercase(),
        sequence: u64::try_from(chunk.sequence)
            .map_err(|_| ProtocolFoundationError::InvalidTransferFrame)?,
        sha256: chunk.sha256,
        chunk_bytes: chunk.data,
    })
}

/// Owned unsigned transfer capabilities suitable for native records.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OwnedTransferCapabilities {
    pub protocol_versions: Vec<u32>,
    pub binary_frame_versions: Vec<u32>,
    pub minimum_partition_bytes: u64,
    pub preferred_partition_bytes: u64,
    pub maximum_partition_bytes: u64,
    pub maximum_in_flight_chunks: u32,
}

impl Default for OwnedTransferCapabilities {
    fn default() -> Self {
        Self {
            protocol_versions: vec![TRANSFER_PROTOCOL_VERSION],
            binary_frame_versions: vec![TRANSFER_PROTOCOL_VERSION],
            minimum_partition_bytes: MINIMUM_PARTITION_BYTES,
            preferred_partition_bytes: PREFERRED_PARTITION_BYTES,
            maximum_partition_bytes: MAXIMUM_PARTITION_BYTES,
            maximum_in_flight_chunks: PREFERRED_IN_FLIGHT_CHUNKS,
        }
    }
}

/// Negotiated transfer values. No wire behavior is added by this representation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OwnedTransferNegotiation {
    pub protocol_version: u32,
    pub binary_frame_version: u32,
    pub partition_target_bytes: u64,
    pub maximum_in_flight_chunks: u32,
}

/// Reuse the deployed pure transfer-capability negotiation.
///
/// # Errors
/// Returns stable invalid-capability or no-common-capability failures.
pub fn negotiate_owned_transfer(
    local: &OwnedTransferCapabilities,
    peer: &OwnedTransferCapabilities,
) -> Result<OwnedTransferNegotiation, ProtocolFoundationError> {
    let local = transfer_capabilities_model(local)?;
    let peer = transfer_capabilities_model(peer)?;
    let negotiated = negotiate_transfer(&local, &peer)
        .ok_or(ProtocolFoundationError::TransferNegotiationFailed)?;
    Ok(OwnedTransferNegotiation {
        protocol_version: u32::try_from(negotiated.protocol_version)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        binary_frame_version: u32::try_from(negotiated.binary_frame_version)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        partition_target_bytes: u64::try_from(negotiated.partition_target_bytes)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        maximum_in_flight_chunks: u32::try_from(negotiated.maximum_in_flight_chunks)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
    })
}

/// Closed pairing transcript profile backed by reviewed v1/v2 Rust crypto.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PairingProfile {
    AppleV1,
    AndroidV2,
}

/// Constant-time verification of a new-pairing client transcript.
///
/// Every key, nonce, and verifier input must be exactly 32 bytes. The pairing code must be six
/// ASCII digits for Apple v1 or twenty ASCII digits for Android v2. This operation does not read or
/// persist trust and returns no secret-bearing error.
///
/// # Errors
/// Returns only stable profile/code/transcript-shape failures.
pub fn verify_pairing_client_transcript(
    profile: PairingProfile,
    pairing_code: &str,
    client_installation_id: &str,
    client_public_key: &[u8],
    client_nonce: &[u8],
    expected_verifier: &[u8],
) -> Result<bool, ProtocolFoundationError> {
    validate_pairing_code(profile, pairing_code)?;
    if client_public_key.len() != 32 || client_nonce.len() != 32 || expected_verifier.len() != 32 {
        return Err(ProtocolFoundationError::InvalidPairingTranscript);
    }
    let installation_id = Uuid::parse_str(client_installation_id)
        .map_err(|_| ProtocolFoundationError::InvalidPairingTranscript)?;
    let actual = match profile {
        PairingProfile::AppleV1 => crypto::pairing_verifier(
            pairing_code,
            installation_id,
            client_public_key,
            client_nonce,
        ),
        PairingProfile::AndroidV2 => crypto::android_pairing_verifier(
            pairing_code,
            installation_id,
            client_public_key,
            client_nonce,
        ),
    };
    Ok(crypto::constant_time_equal(&actual, expected_verifier))
}

/// Derive the deployed v1 session key from three fixed 32-byte inputs.
///
/// The caller owns the returned secret and is responsible for promptly zeroizing its native copy.
/// Rust zeroizes its secret-bearing transcript buffer before returning.
///
/// # Errors
/// Returns a stable shape error unless all inputs are exactly 32 bytes.
pub fn derive_session_key(
    shared_secret: &[u8],
    client_nonce: &[u8],
    server_nonce: &[u8],
) -> Result<[u8; 32], ProtocolFoundationError> {
    let shared_secret: &[u8; 32] = shared_secret
        .try_into()
        .map_err(|_| ProtocolFoundationError::InvalidSessionKeyInput)?;
    if shared_secret == &[0; 32] || client_nonce.len() != 32 || server_nonce.len() != 32 {
        return Err(ProtocolFoundationError::InvalidSessionKeyInput);
    }
    Ok(crypto::session_key(
        shared_secret,
        client_nonce,
        server_nonce,
    ))
}

fn validate_apple_request(request: &AppleExportRequest) -> Result<(), ProtocolFoundationError> {
    if request.protocol_version != IOS_APPLICATION_PROTOCOL_VERSION {
        return Err(ProtocolFoundationError::UnsupportedProtocolVersion);
    }
    Ok(())
}

fn validate_apple_message(message: &DirectMessage) -> Result<(), ProtocolFoundationError> {
    match message {
        DirectMessage::ExportRequest(request) => validate_apple_request(&request.value),
        DirectMessage::TransferSession(session)
            if session.value.protocol_version != i32::from(CURRENT_PROTOCOL_VERSION) =>
        {
            Err(ProtocolFoundationError::UnsupportedProtocolVersion)
        }
        DirectMessage::TransferChunk(chunk) => encode_binary_chunk(&chunk.value)
            .map(|_| ())
            .map_err(map_transfer_error),
        _ => Ok(()),
    }
}

fn validate_android_kotlin_ranges(message: &AndroidMessage) -> Result<(), ProtocolFoundationError> {
    let long = |value: u64| {
        if i64::try_from(value).is_ok() {
            Ok(())
        } else {
            Err(ProtocolFoundationError::InvalidAndroidEnvelope)
        }
    };
    let int = |value: u32| {
        if i32::try_from(value).is_ok() {
            Ok(())
        } else {
            Err(ProtocolFoundationError::InvalidAndroidEnvelope)
        }
    };
    let session = |value: &crate::v2::TransferSession| long(value.partition_target_bytes);
    let partition = |value: &crate::v2::TransferPartition| {
        long(value.index)?;
        long(value.artifact_offset)?;
        long(value.byte_count)?;
        long(value.chunk_count)
    };

    match message {
        AndroidMessage::SourceHello(value) => {
            int(value.limits.maximum_control_bytes)?;
            int(value.limits.maximum_chunk_bytes)?;
            long(value.limits.preferred_partition_bytes)
        }
        AndroidMessage::ExportProgress(value) => {
            long(value.completed_units)?;
            long(value.total_units)?;
            long(value.committed_bytes)
        }
        AndroidMessage::ArtifactManifest(value) => long(value.byte_count),
        AndroidMessage::TransferSession(value) => session(value),
        AndroidMessage::TransferOpen(value) => {
            session(&value.session)?;
            partition(&value.partition)
        }
        AndroidMessage::TransferDisposition(value) => long(value.partition_index),
        AndroidMessage::TransferChunkAcknowledgement(value) => int(value.sequence),
        AndroidMessage::TransferPartitionComplete(value) => long(value.partition_index),
        AndroidMessage::TransferPartitionAcknowledgement(value) => long(value.partition_index),
        AndroidMessage::TransferFinalize(value) => {
            long(value.total_partitions)?;
            long(value.total_bytes)
        }
        AndroidMessage::TransferFinalAcknowledgement(value) => {
            long(value.total_partitions)?;
            long(value.total_bytes)?;
            value.response_byte_count.map_or(Ok(()), long)
        }
        AndroidMessage::StatusRequest(_)
        | AndroidMessage::StatusResponse(_)
        | AndroidMessage::ExportRequest(_)
        | AndroidMessage::ExportAccepted(_)
        | AndroidMessage::ExportRejected(_)
        | AndroidMessage::CompletionConfirmed(_)
        | AndroidMessage::Cancel(_)
        | AndroidMessage::CancelAcknowledged(_)
        | AndroidMessage::Ping(_)
        | AndroidMessage::Pong(_) => Ok(()),
    }
}

fn bounded_json(bytes: &[u8]) -> Result<(), ProtocolFoundationError> {
    if bytes.is_empty() {
        Err(ProtocolFoundationError::InvalidJson)
    } else if bytes.len() > MAXIMUM_PACKET_BYTES {
        Err(ProtocolFoundationError::InputTooLarge)
    } else {
        Ok(())
    }
}

fn strict_decode<T: DeserializeOwned>(
    bytes: &[u8],
    invalid: ProtocolFoundationError,
) -> Result<T, ProtocolFoundationError> {
    let mut ignored = false;
    let mut deserializer = serde_json::Deserializer::from_slice(bytes);
    let decoded = serde_ignored::deserialize(&mut deserializer, |_| ignored = true)
        .map_err(|error| classify_json_error(&error, invalid))?;
    deserializer
        .end()
        .map_err(|error| classify_json_error(&error, invalid))?;
    if ignored {
        return Err(ProtocolFoundationError::UnknownField);
    }
    Ok(decoded)
}

fn classify_json_error(
    error: &serde_json::Error,
    invalid: ProtocolFoundationError,
) -> ProtocolFoundationError {
    let message = error.to_string();
    if message.starts_with("unknown field") {
        ProtocolFoundationError::UnknownField
    } else if error.is_syntax() || error.is_eof() {
        ProtocolFoundationError::InvalidJson
    } else {
        invalid
    }
}

fn require_canonical<T: serde::Serialize>(
    input: &[u8],
    value: &T,
) -> Result<(), ProtocolFoundationError> {
    let encoded =
        canonical_json(value).map_err(|_| ProtocolFoundationError::SerializationFailed)?;
    require_no_unknown_fields(input, &encoded)?;
    if encoded == input {
        Ok(())
    } else {
        Err(ProtocolFoundationError::NonCanonicalJson)
    }
}

fn require_no_unknown_fields(
    input: &[u8],
    canonical: &[u8],
) -> Result<(), ProtocolFoundationError> {
    let input: serde_json::Value =
        serde_json::from_slice(input).map_err(|_| ProtocolFoundationError::InvalidJson)?;
    let canonical: serde_json::Value = serde_json::from_slice(canonical)
        .map_err(|_| ProtocolFoundationError::SerializationFailed)?;
    if input_shape_is_subset(&input, &canonical) {
        Ok(())
    } else if input_shape_is_subset_allowing_absent_null(&input, &canonical) {
        // Optional nulls are known fields but violate the deployed omit-null canonical form.
        Err(ProtocolFoundationError::NonCanonicalJson)
    } else {
        Err(ProtocolFoundationError::UnknownField)
    }
}

fn input_shape_is_subset(input: &serde_json::Value, canonical: &serde_json::Value) -> bool {
    match (input, canonical) {
        (serde_json::Value::Object(input), serde_json::Value::Object(canonical)) => {
            input.iter().all(|(key, input_value)| {
                canonical.get(key).is_some_and(|canonical_value| {
                    input_shape_is_subset(input_value, canonical_value)
                })
            })
        }
        (serde_json::Value::Array(input), serde_json::Value::Array(canonical)) => {
            input.len() == canonical.len()
                && input
                    .iter()
                    .zip(canonical)
                    .all(|(input, canonical)| input_shape_is_subset(input, canonical))
        }
        _ => true,
    }
}

fn input_shape_is_subset_allowing_absent_null(
    input: &serde_json::Value,
    canonical: &serde_json::Value,
) -> bool {
    match (input, canonical) {
        (serde_json::Value::Object(input), serde_json::Value::Object(canonical)) => {
            input.iter().all(|(key, input_value)| {
                canonical.get(key).map_or_else(
                    || input_value.is_null(),
                    |canonical_value| {
                        input_shape_is_subset_allowing_absent_null(input_value, canonical_value)
                    },
                )
            })
        }
        (serde_json::Value::Array(input), serde_json::Value::Array(canonical)) => {
            input.len() == canonical.len()
                && input.iter().zip(canonical).all(|(input, canonical)| {
                    input_shape_is_subset_allowing_absent_null(input, canonical)
                })
        }
        _ => true,
    }
}

fn encode_bounded<T: serde::Serialize>(value: &T) -> Result<Vec<u8>, ProtocolFoundationError> {
    let encoded =
        canonical_json(value).map_err(|_| ProtocolFoundationError::SerializationFailed)?;
    if encoded.len() > MAXIMUM_PACKET_BYTES {
        Err(ProtocolFoundationError::InputTooLarge)
    } else {
        Ok(encoded)
    }
}

fn reject_android_request_shape(bytes: &[u8]) -> Result<(), ProtocolFoundationError> {
    let value: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| ProtocolFoundationError::InvalidJson)?;
    if value
        .as_object()
        .is_some_and(|object| object.contains_key("source_installation_id"))
    {
        Err(ProtocolFoundationError::WrongProtocolProfile)
    } else {
        Ok(())
    }
}

fn reject_apple_request_shape(bytes: &[u8]) -> Result<(), ProtocolFoundationError> {
    let value: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| ProtocolFoundationError::InvalidJson)?;
    if value
        .as_object()
        .is_some_and(|object| object.contains_key("protocolVersion"))
    {
        Err(ProtocolFoundationError::WrongProtocolProfile)
    } else {
        Ok(())
    }
}

fn map_transfer_error(error: TransferError) -> ProtocolFoundationError {
    match error {
        TransferError::InvalidFrame => ProtocolFoundationError::InvalidTransferFrame,
        TransferError::UnsupportedFrameVersion => {
            ProtocolFoundationError::UnsupportedTransferFrameVersion
        }
        TransferError::InvalidChunk => ProtocolFoundationError::InvalidTransferChunk,
        TransferError::FingerprintEncoding => ProtocolFoundationError::SerializationFailed,
    }
}

fn transfer_capabilities_model(
    value: &OwnedTransferCapabilities,
) -> Result<TransferCapabilities, ProtocolFoundationError> {
    if value.protocol_versions.is_empty()
        || value.binary_frame_versions.is_empty()
        || value.minimum_partition_bytes == 0
        || value.minimum_partition_bytes > value.maximum_partition_bytes
    {
        return Err(ProtocolFoundationError::InvalidTransferCapabilities);
    }
    Ok(TransferCapabilities {
        protocol_versions: value
            .protocol_versions
            .iter()
            .copied()
            .map(i32::try_from)
            .collect::<Result<_, _>>()
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        binary_frame_versions: value
            .binary_frame_versions
            .iter()
            .copied()
            .map(i32::try_from)
            .collect::<Result<_, _>>()
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        minimum_partition_bytes: i64::try_from(value.minimum_partition_bytes)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        preferred_partition_bytes: i64::try_from(value.preferred_partition_bytes)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        maximum_partition_bytes: i64::try_from(value.maximum_partition_bytes)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
        maximum_in_flight_chunks: i32::try_from(value.maximum_in_flight_chunks)
            .map_err(|_| ProtocolFoundationError::InvalidTransferCapabilities)?,
    })
}

fn validate_pairing_code(
    profile: PairingProfile,
    pairing_code: &str,
) -> Result<(), ProtocolFoundationError> {
    let expected_length = match profile {
        PairingProfile::AppleV1 => 6,
        PairingProfile::AndroidV2 => 20,
    };
    if pairing_code.len() == expected_length
        && pairing_code.bytes().all(|byte| byte.is_ascii_digit())
    {
        Ok(())
    } else {
        Err(ProtocolFoundationError::InvalidPairingCode)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transfer::sha256_hex;

    #[test]
    fn info_pins_deployed_versions_and_limits_without_bumping_wire_versions() {
        let info = direct_protocol_info();
        assert_eq!(info.protocol_api_revision, 1);
        assert_eq!(info.direct_pairing_protocol_version, 1);
        assert_eq!(info.supported_pairing_protocol_versions, [1, 2]);
        assert_eq!(info.apple_application_protocol_version, 1);
        assert_eq!(info.android_application_protocol_version, 2);
        assert_eq!(info.maximum_control_json_bytes, 2 * 1_024 * 1_024);
        assert_eq!(info.maximum_chunk_bytes, 512 * 1_024);
        assert_eq!(info.maximum_transfer_frame_bytes, 512 * 1_024 + 66);
        assert_eq!(info.durable_job_lifetime_seconds, 7 * 24 * 60 * 60);
    }

    #[test]
    fn frame_sequence_boundaries_and_payload_limit_are_strict() {
        let payload = vec![0xa5; TRANSFER_FRAME_BYTES];
        let mut chunk = OwnedTransferChunk {
            transfer_id: "11111111-2222-4333-8444-555555555555".to_owned(),
            sequence: u64::from(u32::MAX),
            sha256: sha256_hex(&payload),
            chunk_bytes: payload,
        };
        let frame = encode_owned_transfer_chunk(&chunk).unwrap();
        assert_eq!(decode_owned_transfer_chunk(&frame).unwrap(), chunk);

        chunk.sequence = 0;
        assert_eq!(
            encode_owned_transfer_chunk(&chunk),
            Err(ProtocolFoundationError::InvalidTransferMetadata)
        );
        chunk.sequence = u64::from(u32::MAX) + 1;
        assert_eq!(
            encode_owned_transfer_chunk(&chunk),
            Err(ProtocolFoundationError::InvalidTransferMetadata)
        );
        chunk.sequence = 1;
        chunk.chunk_bytes.push(0);
        assert_eq!(
            encode_owned_transfer_chunk(&chunk),
            Err(ProtocolFoundationError::TransferFrameTooLarge)
        );
    }

    #[test]
    fn every_truncated_header_and_payload_is_rejected() {
        let payload = b"opaque fixture bytes".to_vec();
        let chunk = OwnedTransferChunk {
            transfer_id: "11111111-2222-4333-8444-555555555555".to_owned(),
            sequence: 1,
            sha256: sha256_hex(&payload),
            chunk_bytes: payload,
        };
        let frame = encode_owned_transfer_chunk(&chunk).unwrap();
        for length in 0..frame.len() {
            assert!(decode_owned_transfer_chunk(&frame[..length]).is_err());
        }

        let mut unsupported_version = frame.clone();
        unsupported_version[9] = 2;
        assert_eq!(
            decode_owned_transfer_chunk(&unsupported_version),
            Err(ProtocolFoundationError::UnsupportedTransferFrameVersion)
        );
        let mut corrupted_payload = frame;
        *corrupted_payload.last_mut().unwrap() ^= 1;
        assert_eq!(
            decode_owned_transfer_chunk(&corrupted_payload),
            Err(ProtocolFoundationError::InvalidTransferChunk)
        );
    }

    #[test]
    fn json_and_crypto_inputs_are_bounded_before_parsing_or_derivation() {
        let oversized = vec![b' '; MAXIMUM_PACKET_BYTES + 1];
        assert_eq!(
            apple_v1_request_fingerprint(&oversized),
            Err(ProtocolFoundationError::InputTooLarge)
        );
        assert_eq!(
            android_v2_request_fingerprint(&oversized),
            Err(ProtocolFoundationError::InputTooLarge)
        );
        assert_eq!(
            apple_v1_request_fingerprint(br#"{"source_installation_id":"synthetic"}"#),
            Err(ProtocolFoundationError::WrongProtocolProfile)
        );
        assert_eq!(
            android_v2_request_fingerprint(br#"{"protocolVersion":1}"#),
            Err(ProtocolFoundationError::WrongProtocolProfile)
        );
        assert_eq!(
            verify_pairing_client_transcript(
                PairingProfile::AndroidV2,
                "123456",
                "abcdefab-cdef-4abc-8def-abcdefabcdef",
                &[0; 32],
                &[0; 32],
                &[0; 32],
            ),
            Err(ProtocolFoundationError::InvalidPairingCode)
        );
    }

    #[test]
    fn pairing_replay_with_a_different_nonce_fails_constant_time_comparison() {
        let expected = crypto::pairing_verifier(
            "123456",
            Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap(),
            &[7; 32],
            &[9; 32],
        );
        assert!(
            verify_pairing_client_transcript(
                PairingProfile::AppleV1,
                "123456",
                "abcdefab-cdef-4abc-8def-abcdefabcdef",
                &[7; 32],
                &[9; 32],
                &expected,
            )
            .unwrap()
        );
        assert!(
            !verify_pairing_client_transcript(
                PairingProfile::AppleV1,
                "123456",
                "abcdefab-cdef-4abc-8def-abcdefabcdef",
                &[7; 32],
                &[10; 32],
                &expected,
            )
            .unwrap()
        );
    }

    #[test]
    fn malformed_secret_inputs_return_only_fixed_errors() {
        let error = derive_session_key(b"secret value", &[2; 32], &[3; 32]).unwrap_err();
        assert_eq!(error, ProtocolFoundationError::InvalidSessionKeyInput);
        assert_eq!(error.to_string(), "session-key input is invalid");
        assert!(!error.to_string().contains("secret value"));
        assert_eq!(
            derive_session_key(&[0; 32], &[2; 32], &[3; 32]),
            Err(ProtocolFoundationError::InvalidSessionKeyInput)
        );
    }
}
