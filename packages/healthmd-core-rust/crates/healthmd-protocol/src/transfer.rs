//! Request fingerprints, transfer negotiation, and binary chunk frames.

use sha2::{Digest as _, Sha256};
use thiserror::Error;

use crate::{
    TRANSFER_FRAME_BYTES,
    encoding::canonical_json,
    models::{ExportRequest, RequestFingerprint, TransferChunk},
    wire::TransferCapabilities,
};

const BINARY_MAGIC: &[u8; 8] = b"HMDDIRCT";
const BINARY_VERSION: u16 = 1;
const BINARY_HEADER_BYTES: usize = 8 + 2 + 16 + 4 + 4 + 32;

#[derive(Clone, Copy, Debug, Eq, Error, PartialEq)]
pub enum TransferError {
    #[error("the transfer frame is malformed")]
    InvalidFrame,
    #[error("the transfer frame version is unsupported")]
    UnsupportedFrameVersion,
    #[error("the transfer chunk is invalid")]
    InvalidChunk,
    #[error("the request fingerprint could not be encoded")]
    FingerprintEncoding,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TransferNegotiation {
    pub protocol_version: i32,
    pub binary_frame_version: i32,
    pub partition_target_bytes: i64,
    pub maximum_in_flight_chunks: i32,
}

/// Compute the deployed Foundation-compatible request fingerprint.
///
/// # Errors
///
/// Returns an error if the request cannot be represented as canonical JSON.
pub fn request_fingerprint(request: &ExportRequest) -> Result<RequestFingerprint, TransferError> {
    let encoded = canonical_json(request).map_err(|_| TransferError::FingerprintEncoding)?;
    Ok(RequestFingerprint {
        version: 1,
        sha256: sha256_hex(&encoded),
    })
}

#[must_use]
pub fn negotiate_transfer(
    local: &TransferCapabilities,
    peer: &TransferCapabilities,
) -> Option<TransferNegotiation> {
    let protocol_version = local
        .protocol_versions
        .iter()
        .filter(|version| peer.protocol_versions.contains(version))
        .max()
        .copied()?;
    let binary_frame_version = local
        .binary_frame_versions
        .iter()
        .filter(|version| peer.binary_frame_versions.contains(version))
        .max()
        .copied()?;
    let minimum = local
        .minimum_partition_bytes
        .max(peer.minimum_partition_bytes);
    let maximum = local
        .maximum_partition_bytes
        .min(peer.maximum_partition_bytes);
    if minimum > maximum {
        return None;
    }
    let preferred = local
        .preferred_partition_bytes
        .max(peer.preferred_partition_bytes)
        .clamp(minimum, maximum);
    Some(TransferNegotiation {
        protocol_version,
        binary_frame_version,
        partition_target_bytes: preferred,
        maximum_in_flight_chunks: local
            .maximum_in_flight_chunks
            .min(peer.maximum_in_flight_chunks)
            .clamp(1, 8),
    })
}

/// Encode a binary chunk exactly as Swift `DirectTransferBinaryFrame` v1.
///
/// # Errors
///
/// Returns an error for invalid sequence, size, digest, or identifier fields.
pub fn encode_binary_chunk(chunk: &TransferChunk) -> Result<Vec<u8>, TransferError> {
    let sequence = u32::try_from(chunk.sequence)
        .ok()
        .filter(|sequence| *sequence > 0)
        .ok_or(TransferError::InvalidChunk)?;
    if chunk.data.len() > TRANSFER_FRAME_BYTES || sha256_hex(&chunk.data) != chunk.sha256 {
        return Err(TransferError::InvalidChunk);
    }
    let digest = decode_sha256(&chunk.sha256).ok_or(TransferError::InvalidChunk)?;
    let payload_length =
        u32::try_from(chunk.data.len()).map_err(|_| TransferError::InvalidChunk)?;
    let mut frame = Vec::with_capacity(BINARY_HEADER_BYTES + chunk.data.len());
    frame.extend_from_slice(BINARY_MAGIC);
    frame.extend_from_slice(&BINARY_VERSION.to_be_bytes());
    frame.extend_from_slice(chunk.transfer_id.0.as_bytes());
    frame.extend_from_slice(&sequence.to_be_bytes());
    frame.extend_from_slice(&payload_length.to_be_bytes());
    frame.extend_from_slice(&digest);
    frame.extend_from_slice(&chunk.data);
    Ok(frame)
}

/// Decode and structurally validate a Swift binary chunk frame.
///
/// # Errors
///
/// Returns an error for bad magic/version/length/sequence/digest.
pub fn decode_binary_chunk(frame: &[u8]) -> Result<TransferChunk, TransferError> {
    if frame.len() < BINARY_HEADER_BYTES || !frame.starts_with(BINARY_MAGIC) {
        return Err(TransferError::InvalidFrame);
    }
    let version = u16::from_be_bytes([frame[8], frame[9]]);
    if version != BINARY_VERSION {
        return Err(TransferError::UnsupportedFrameVersion);
    }
    let transfer_id =
        uuid::Uuid::from_slice(&frame[10..26]).map_err(|_| TransferError::InvalidFrame)?;
    let sequence = u32::from_be_bytes(
        frame[26..30]
            .try_into()
            .map_err(|_| TransferError::InvalidFrame)?,
    );
    let payload_length = usize::try_from(u32::from_be_bytes(
        frame[30..34]
            .try_into()
            .map_err(|_| TransferError::InvalidFrame)?,
    ))
    .map_err(|_| TransferError::InvalidFrame)?;
    let digest: [u8; 32] = frame[34..66]
        .try_into()
        .map_err(|_| TransferError::InvalidFrame)?;
    let payload = &frame[BINARY_HEADER_BYTES..];
    if sequence == 0 || payload_length > TRANSFER_FRAME_BYTES || payload_length != payload.len() {
        return Err(TransferError::InvalidFrame);
    }
    let digest_hex = hex(&digest);
    if sha256_hex(payload) != digest_hex {
        return Err(TransferError::InvalidChunk);
    }
    Ok(TransferChunk {
        transfer_id: transfer_id.into(),
        sequence: i64::from(sequence),
        data: payload.to_vec(),
        sha256: digest_hex,
    })
}

#[must_use]
pub fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

#[must_use]
pub fn is_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn decode_sha256(value: &str) -> Option<[u8; 32]> {
    if !is_sha256(value) {
        return None;
    }
    let mut bytes = [0_u8; 32];
    for (index, output) in bytes.iter_mut().enumerate() {
        *output = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16).ok()?;
    }
    Some(bytes)
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    bytes.iter().fold(String::new(), |mut output, byte| {
        write!(output, "{byte:02x}").expect("writing to a string succeeds");
        output
    })
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use super::*;
    use crate::encoding::SwiftUuid;

    #[test]
    fn binary_frame_round_trips() {
        let payload = vec![0xab; 4096];
        let chunk = TransferChunk {
            transfer_id: SwiftUuid(
                Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap(),
            ),
            sequence: 1,
            sha256: sha256_hex(&payload),
            data: payload,
        };
        let frame = encode_binary_chunk(&chunk).unwrap();
        assert_eq!(decode_binary_chunk(&frame).unwrap(), chunk);
    }

    #[test]
    fn current_capabilities_negotiate_48_mib_and_four_chunks() {
        let current = TransferCapabilities::default();
        assert_eq!(
            negotiate_transfer(&current, &current),
            Some(TransferNegotiation {
                protocol_version: 1,
                binary_frame_version: 1,
                partition_target_bytes: 48 * 1024 * 1024,
                maximum_in_flight_chunks: 4,
            })
        );
    }
}
