//! Bounded lossless artifact framing without retaining emitted content.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::{RenderError, WriteMode, artifact_plan};
use crate::semantic::SemanticProfile;

/// Maximum bytes accepted for one raw chunk, JSON item, or encoded CSV row.
pub const MAX_STREAM_ITEM_BYTES: usize = 1024 * 1024;
/// Maximum bytes emitted by one stream (2 GiB).
pub const MAX_STREAM_TOTAL_BYTES: u64 = 2 * 1024 * 1024 * 1024;

/// Closed lossless framing modes.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum StreamMode {
    /// Chunks are emitted unchanged.
    RawBytes,
    /// Valid JSON values are framed as one compact JSON array.
    JsonArray,
    /// Typed fields are RFC 4180 escaped and terminated with CRLF.
    Rfc4180Rows,
}

/// Destination-neutral identity for one streamed artifact.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StreamArtifactConfig {
    pub request_id: String,
    pub session_id: String,
    pub profile: SemanticProfile,
    pub relative_path: String,
    pub media_type: String,
    pub write_mode: WriteMode,
}

/// Completed artifact-plan item whose bytes were emitted incrementally.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct StreamArtifactPlanItem {
    pub artifact_id: String,
    pub relative_path: String,
    pub media_type: String,
    pub write_mode: WriteMode,
    pub byte_count: u64,
    pub sha256: String,
}

/// Final health-free descriptor for all bytes emitted by a stream.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct StreamDescriptor {
    /// Framing mode used by the stream.
    pub mode: StreamMode,
    /// Exact total emitted byte count, including framing.
    pub byte_count: u64,
    /// SHA-256 of emitted chunks concatenated in call order.
    pub sha256: String,
    /// Number of caller-provided items.
    pub item_count: u64,
    /// Destination-neutral plan identity when the stream was created as a planned artifact.
    pub artifact: Option<StreamArtifactPlanItem>,
}

/// Final framing bytes and their completed descriptor.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StreamFinish {
    /// Bytes that must be emitted immediately by the caller (`]` or `[]` for JSON arrays).
    pub chunk: Vec<u8>,
    /// Descriptor covering this final chunk and every previously returned chunk.
    pub descriptor: StreamDescriptor,
}

/// Stateful, bounded streaming encoder that retains only digest/count/framing state.
#[derive(Clone, Debug)]
pub struct LosslessArtifactStream {
    mode: StreamMode,
    digest: Sha256,
    byte_count: u64,
    item_count: u64,
    terminal: bool,
    artifact: Option<StreamArtifactConfig>,
}

impl LosslessArtifactStream {
    /// Create an empty stream in one explicit framing mode.
    #[must_use]
    pub fn new(mode: StreamMode) -> Self {
        Self {
            mode,
            digest: Sha256::new(),
            byte_count: 0,
            item_count: 0,
            terminal: false,
            artifact: None,
        }
    }

    /// Create a planned stream whose completed descriptor can be committed by a native writer.
    ///
    /// # Errors
    /// Returns a stable configuration/path error before any bytes are accepted.
    pub fn new_planned(
        mode: StreamMode,
        artifact: StreamArtifactConfig,
    ) -> Result<Self, RenderError> {
        if artifact.request_id.is_empty()
            || artifact.session_id.is_empty()
            || artifact.request_id.contains(['\0', '\n', '\r'])
            || artifact.session_id.contains(['\0', '\n', '\r'])
            || artifact.write_mode == WriteMode::ApiPost
        {
            return Err(RenderError::InvalidConfig);
        }
        artifact_plan::validate_relative_path(&artifact.relative_path)?;
        artifact_plan::validate_media_type(&artifact.media_type)?;
        Ok(Self {
            mode,
            digest: Sha256::new(),
            byte_count: 0,
            item_count: 0,
            terminal: false,
            artifact: Some(artifact),
        })
    }

    /// Emit an unchanged raw byte chunk.
    ///
    /// # Errors
    /// Returns a stable sequence, cancellation, item-size, or total-size error.
    pub fn push_raw(
        &mut self,
        bytes: &[u8],
        is_cancelled: impl Fn() -> bool,
    ) -> Result<Vec<u8>, RenderError> {
        self.check_ready(StreamMode::RawBytes, &is_cancelled)?;
        if bytes.len() > MAX_STREAM_ITEM_BYTES {
            return Err(RenderError::StreamItemTooLarge);
        }
        self.emit_item(bytes.to_vec())
    }

    /// Validate and frame one exact JSON value as an array item.
    ///
    /// The item bytes themselves are retained exactly; only `[`/`,` framing is added.
    ///
    /// # Errors
    /// Returns a stable sequence, cancellation, JSON, item-size, or total-size error.
    pub fn push_json_item(
        &mut self,
        item_bytes: &[u8],
        is_cancelled: impl Fn() -> bool,
    ) -> Result<Vec<u8>, RenderError> {
        self.check_ready(StreamMode::JsonArray, &is_cancelled)?;
        if item_bytes.len() > MAX_STREAM_ITEM_BYTES {
            return Err(RenderError::StreamItemTooLarge);
        }
        let _: serde_json::Value =
            serde_json::from_slice(item_bytes).map_err(|_| RenderError::InvalidStreamItem)?;
        let mut chunk = Vec::with_capacity(item_bytes.len().saturating_add(1));
        chunk.push(if self.item_count == 0 { b'[' } else { b',' });
        chunk.extend_from_slice(item_bytes);
        self.emit_item(chunk)
    }

    /// Encode and emit one RFC 4180 row using CRLF line termination.
    ///
    /// # Errors
    /// Returns a stable sequence, cancellation, field, item-size, or total-size error.
    pub fn push_rfc4180_row(
        &mut self,
        fields: &[String],
        is_cancelled: impl Fn() -> bool,
    ) -> Result<Vec<u8>, RenderError> {
        self.check_ready(StreamMode::Rfc4180Rows, &is_cancelled)?;
        if fields.is_empty() || fields.len() > 4_096 {
            return Err(RenderError::InvalidStreamItem);
        }
        let mut chunk = Vec::new();
        for (index, field) in fields.iter().enumerate() {
            if field.len() > MAX_STREAM_ITEM_BYTES || field.contains('\0') {
                return Err(RenderError::InvalidStreamItem);
            }
            if index != 0 {
                chunk.push(b',');
            }
            append_csv_field(&mut chunk, field);
            if chunk.len() > MAX_STREAM_ITEM_BYTES {
                return Err(RenderError::StreamItemTooLarge);
            }
        }
        chunk.extend_from_slice(b"\r\n");
        self.emit_item(chunk)
    }

    /// Terminate the stream and return final framing plus a digest descriptor.
    ///
    /// # Errors
    /// Returns a stable terminal, cancellation, or total-size error.
    pub fn finish(&mut self, is_cancelled: impl Fn() -> bool) -> Result<StreamFinish, RenderError> {
        if self.terminal {
            return Err(RenderError::StreamTerminal);
        }
        if is_cancelled() {
            self.terminal = true;
            return Err(RenderError::Cancelled);
        }
        let chunk = if self.mode == StreamMode::JsonArray {
            if self.item_count == 0 {
                b"[]".to_vec()
            } else {
                b"]".to_vec()
            }
        } else {
            Vec::new()
        };
        self.account(&chunk)?;
        self.terminal = true;
        let sha256 = format!("{:x}", self.digest.clone().finalize());
        let artifact = self
            .artifact
            .as_ref()
            .map(|artifact| StreamArtifactPlanItem {
                artifact_id: artifact_plan::artifact_id(
                    &artifact.request_id,
                    &artifact.session_id,
                    artifact.profile,
                    &artifact.relative_path,
                    &artifact.media_type,
                    artifact.write_mode,
                    &sha256,
                ),
                relative_path: artifact.relative_path.clone(),
                media_type: artifact.media_type.clone(),
                write_mode: artifact.write_mode,
                byte_count: self.byte_count,
                sha256: sha256.clone(),
            });
        Ok(StreamFinish {
            chunk,
            descriptor: StreamDescriptor {
                mode: self.mode,
                byte_count: self.byte_count,
                sha256,
                item_count: self.item_count,
                artifact,
            },
        })
    }

    fn check_ready(
        &mut self,
        expected: StreamMode,
        is_cancelled: &impl Fn() -> bool,
    ) -> Result<(), RenderError> {
        if self.terminal {
            return Err(RenderError::StreamTerminal);
        }
        if self.mode != expected {
            return Err(RenderError::StreamSequenceInvalid);
        }
        if is_cancelled() {
            self.terminal = true;
            return Err(RenderError::Cancelled);
        }
        Ok(())
    }

    fn emit_item(&mut self, chunk: Vec<u8>) -> Result<Vec<u8>, RenderError> {
        if chunk.len() > MAX_STREAM_ITEM_BYTES.saturating_add(1) {
            return Err(RenderError::StreamItemTooLarge);
        }
        self.account(&chunk)?;
        self.item_count = self
            .item_count
            .checked_add(1)
            .ok_or(RenderError::StreamTooLarge)?;
        Ok(chunk)
    }

    fn account(&mut self, chunk: &[u8]) -> Result<(), RenderError> {
        let length = u64::try_from(chunk.len()).map_err(|_| RenderError::StreamTooLarge)?;
        let next = self
            .byte_count
            .checked_add(length)
            .ok_or(RenderError::StreamTooLarge)?;
        if next > MAX_STREAM_TOTAL_BYTES {
            return Err(RenderError::StreamTooLarge);
        }
        self.digest.update(chunk);
        self.byte_count = next;
        Ok(())
    }
}

fn append_csv_field(output: &mut Vec<u8>, field: &str) {
    let quote = field
        .bytes()
        .any(|byte| matches!(byte, b',' | b'"' | b'\r' | b'\n'));
    if quote {
        output.push(b'"');
        for byte in field.bytes() {
            output.push(byte);
            if byte == b'"' {
                output.push(b'"');
            }
        }
        output.push(b'"');
    } else {
        output.extend_from_slice(field.as_bytes());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_stream_returns_chunks_and_retains_only_accounting() {
        let mut stream = LosslessArtifactStream::new(StreamMode::RawBytes);
        assert_eq!(stream.push_raw(b"abc", || false).unwrap(), b"abc");
        assert_eq!(stream.push_raw(b"def", || false).unwrap(), b"def");
        let finished = stream.finish(|| false).unwrap();
        assert!(finished.chunk.is_empty());
        assert_eq!(finished.descriptor.byte_count, 6);
        assert_eq!(finished.descriptor.item_count, 2);
        assert_eq!(
            finished.descriptor.sha256,
            "bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721"
        );
        assert_eq!(stream.finish(|| false), Err(RenderError::StreamTerminal));
    }

    #[test]
    fn planned_stream_finishes_as_destination_neutral_artifact_item() {
        let mut stream = LosslessArtifactStream::new_planned(
            StreamMode::RawBytes,
            StreamArtifactConfig {
                request_id: "stream-request".to_owned(),
                session_id: "stream-session".to_owned(),
                profile: SemanticProfile::AppleHealthDataV7,
                relative_path: "Health/Raw/archive.json".to_owned(),
                media_type: "application/json".to_owned(),
                write_mode: WriteMode::Overwrite,
            },
        )
        .unwrap();
        stream.push_raw(b"abc", || false).unwrap();
        let finish = stream.finish(|| false).unwrap();
        let artifact = finish.descriptor.artifact.unwrap();
        assert_eq!(artifact.relative_path, "Health/Raw/archive.json");
        assert_eq!(artifact.media_type, "application/json");
        assert_eq!(artifact.write_mode, WriteMode::Overwrite);
        assert_eq!(artifact.byte_count, 3);
        assert_eq!(artifact.sha256, finish.descriptor.sha256);
        assert_eq!(artifact.artifact_id.len(), 64);
        assert!(
            LosslessArtifactStream::new_planned(
                StreamMode::RawBytes,
                StreamArtifactConfig {
                    request_id: "request".to_owned(),
                    session_id: "session".to_owned(),
                    profile: SemanticProfile::AppleHealthDataV7,
                    relative_path: "../private".to_owned(),
                    media_type: "application/json".to_owned(),
                    write_mode: WriteMode::Overwrite,
                },
            )
            .is_err()
        );
    }

    #[test]
    fn json_and_csv_framing_are_exact() {
        let mut json = LosslessArtifactStream::new(StreamMode::JsonArray);
        let first = json.push_json_item(br#"{"a":1}"#, || false).unwrap();
        let second = json.push_json_item(b"2", || false).unwrap();
        let end = json.finish(|| false).unwrap();
        assert_eq!([first, second, end.chunk].concat(), br#"[{"a":1},2]"#);

        let mut csv = LosslessArtifactStream::new(StreamMode::Rfc4180Rows);
        assert_eq!(
            csv.push_rfc4180_row(
                &["a,b".to_owned(), "x\"y".to_owned(), "z\nq".to_owned()],
                || false,
            )
            .unwrap(),
            b"\"a,b\",\"x\"\"y\",\"z\nq\"\r\n"
        );
    }

    #[test]
    fn enforces_mode_size_cancellation_and_terminal_state() {
        let mut stream = LosslessArtifactStream::new(StreamMode::RawBytes);
        assert_eq!(
            stream.push_json_item(b"null", || false),
            Err(RenderError::StreamSequenceInvalid)
        );
        assert_eq!(
            stream.push_raw(&vec![0; MAX_STREAM_ITEM_BYTES + 1], || false),
            Err(RenderError::StreamItemTooLarge)
        );
        assert_eq!(stream.push_raw(b"x", || true), Err(RenderError::Cancelled));
        assert_eq!(
            stream.push_raw(b"x", || false),
            Err(RenderError::StreamTerminal)
        );
    }
}
