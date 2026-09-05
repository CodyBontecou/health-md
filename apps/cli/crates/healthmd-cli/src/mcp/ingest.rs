//! Agent Data ingestion protocol v1 — the local Rust half.
//!
//! Implements the settled ingestion semantics of
//! `packages/contracts/agent-data/v1/contract.md` against the SQLite store:
//! strict upload-manifest validation mirroring `agent-data-ingest.schema.json`
//! (unknown-field rejection, bounds, formats), artifact-byte integrity
//! verification, health-free receipts exactly matching
//! `agent-ingest-response.schema.json`, and atomic, non-destructive promotion
//! into owner-date partitions.
//!
//! Rejection codes are the four stable v1 classes: `truncated`,
//! `checksum_invalid`, `manifest_incomplete`, and `transient`. The `transient`
//! mapping documented in `apps/cli/docs/agent-data.md` is local-file-only: it
//! is produced when the artifact file cannot be read as bytes at dispatch
//! time. The HTTPS transport mapping stays open for the gateway cycle; the
//! contract codes themselves are stable.

use std::path::{Path, PathBuf};

use chrono::{NaiveDate, Utc};
use rusqlite::{Connection, OptionalExtension as _, params};
use serde::Deserialize;
use serde_json::{Value, json};

use super::DataStoreOpenError;
use super::data_backend::{
    self, ArtifactEntry, ArtifactSchema, PhysicalFormat, RecordEntry, SourceFile, sha256_hex,
};
use super::data_sqlite;

/// Schema identity of the upload manifest contract.
pub(super) const INGEST_MANIFEST_SCHEMA: &str = "healthmd.agent_data_ingest";
/// Schema identity of the health-free receipt contract.
pub(super) const INGEST_RESPONSE_SCHEMA: &str = "healthmd.agent_ingest_response";
/// Concrete version of both ingestion contracts.
pub(super) const INGEST_SCHEMA_VERSION: u64 = 1;
/// Upload bound shared with the read model's JSON artifact bound (64 MiB).
const MAXIMUM_UPLOAD_BYTES: u64 = 67_108_864;
/// Bound for the `covered_owner_dates` list of a finalized partial upload.
const MAXIMUM_COVERED_OWNER_DATES: usize = 400;
/// Local bound for the manifest document itself; a valid manifest is tiny.
const MAXIMUM_MANIFEST_BYTES: u64 = 1_048_576;
/// Identifier length bound mirroring the manifest schema's `maxLength`.
const MAXIMUM_IDENTIFIER_CHARS: usize = 128;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ArtifactKind {
    HealthDataDaily,
    ExternalProviderDaily,
    RawSnapshot,
    RawChanges,
}

impl ArtifactKind {
    const fn requires_complete(self) -> bool {
        matches!(self, Self::RawSnapshot | Self::RawChanges)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Platform {
    Apple,
    Android,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Completeness {
    Complete,
    Partial { covered_owner_dates: Vec<String> },
}

impl Completeness {
    const fn type_text(&self) -> &'static str {
        match self {
            Self::Complete => "complete",
            Self::Partial { .. } => "partial",
        }
    }

    fn to_json(&self) -> Value {
        match self {
            Self::Complete => json!({"type": "complete"}),
            Self::Partial {
                covered_owner_dates,
            } => json!({
                "type": "partial",
                "finalized": true,
                "covered_owner_dates": covered_owner_dates
            }),
        }
    }
}

/// Strict wire form of `agent-data-ingest.schema.json` v1.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ManifestWire {
    schema: String,
    schema_version: u64,
    artifact_kind: ArtifactKindWire,
    platform: PlatformWire,
    artifact_schema: String,
    artifact_schema_version: u64,
    owner_date: String,
    physical_format: PhysicalFormatWire,
    media_type: String,
    byte_count: u64,
    sha256: String,
    completeness: CompletenessWire,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum ArtifactKindWire {
    HealthDataDaily,
    ExternalProviderDaily,
    RawSnapshot,
    RawChanges,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum PlatformWire {
    Apple,
    Android,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum PhysicalFormatWire {
    Json,
    Ndjson,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
enum CompletenessWire {
    Complete,
    Partial {
        finalized: bool,
        covered_owner_dates: Vec<String>,
    },
}

/// A validated upload manifest.
#[derive(Debug)]
pub(super) struct IngestManifest {
    artifact_kind: ArtifactKind,
    #[allow(dead_code)]
    platform: Platform,
    artifact_schema: String,
    artifact_schema_version: u64,
    owner_date: String,
    physical_format: PhysicalFormat,
    media_type: String,
    byte_count: u64,
    sha256: String,
    completeness: Completeness,
}

impl IngestManifest {
    /// Strictly decode and validate one manifest value.
    ///
    /// Mirrors the JSON schema the way the read model validates its contracts:
    /// unknown fields are rejected, every bound and format is enforced, and any
    /// failure leaves the manifest structurally incomplete or unidentifiable.
    fn from_value(value: Value) -> Result<Self, ()> {
        // serde's internally tagged enums cannot reject unknown variant fields,
        // so the completeness grammar is enforced on the raw object as well.
        enforce_completeness_grammar(value.get("completeness"))?;
        let wire: ManifestWire = serde_json::from_value(value).map_err(|_| ())?;
        if wire.schema != INGEST_MANIFEST_SCHEMA || wire.schema_version != INGEST_SCHEMA_VERSION {
            return Err(());
        }
        let completeness = match wire.completeness {
            CompletenessWire::Complete => Completeness::Complete,
            CompletenessWire::Partial {
                finalized: false,
                covered_owner_dates: _,
            } => return Err(()),
            CompletenessWire::Partial {
                finalized: true,
                covered_owner_dates,
            } => Completeness::Partial {
                covered_owner_dates,
            },
        };
        let manifest = Self {
            artifact_kind: match wire.artifact_kind {
                ArtifactKindWire::HealthDataDaily => ArtifactKind::HealthDataDaily,
                ArtifactKindWire::ExternalProviderDaily => ArtifactKind::ExternalProviderDaily,
                ArtifactKindWire::RawSnapshot => ArtifactKind::RawSnapshot,
                ArtifactKindWire::RawChanges => ArtifactKind::RawChanges,
            },
            platform: match wire.platform {
                PlatformWire::Apple => Platform::Apple,
                PlatformWire::Android => Platform::Android,
            },
            artifact_schema: wire.artifact_schema,
            artifact_schema_version: wire.artifact_schema_version,
            owner_date: wire.owner_date,
            physical_format: match wire.physical_format {
                PhysicalFormatWire::Json => PhysicalFormat::Json,
                PhysicalFormatWire::Ndjson => PhysicalFormat::Ndjson,
            },
            media_type: wire.media_type,
            byte_count: wire.byte_count,
            sha256: wire.sha256,
            completeness,
        };
        manifest.validate()?;
        Ok(manifest)
    }

    fn validate(&self) -> Result<(), ()> {
        if self.artifact_schema.is_empty()
            || self.artifact_schema.chars().count() > MAXIMUM_IDENTIFIER_CHARS
        {
            return Err(());
        }
        if self.artifact_schema_version == 0 {
            return Err(());
        }
        if !is_strict_date(&self.owner_date) {
            return Err(());
        }
        if self.media_type.is_empty() || self.media_type.chars().count() > MAXIMUM_IDENTIFIER_CHARS
        {
            return Err(());
        }
        if self.byte_count == 0 || self.byte_count > MAXIMUM_UPLOAD_BYTES {
            return Err(());
        }
        if !is_lowercase_sha256(&self.sha256) {
            return Err(());
        }
        if let Completeness::Partial {
            covered_owner_dates,
        } = &self.completeness
        {
            if covered_owner_dates.is_empty()
                || covered_owner_dates.len() > MAXIMUM_COVERED_OWNER_DATES
            {
                return Err(());
            }
            let mut seen = std::collections::BTreeSet::new();
            for date in covered_owner_dates {
                if !is_strict_date(date) || !seen.insert(date.clone()) {
                    return Err(());
                }
            }
        }
        if self.artifact_kind.requires_complete()
            && !matches!(self.completeness, Completeness::Complete)
        {
            return Err(());
        }
        Ok(())
    }
}

/// Reject any completeness object whose key set differs from the documented
/// grammar (`{"type"}` or `{"type", "finalized", "covered_owner_dates"}`).
fn enforce_completeness_grammar(completeness: Option<&Value>) -> Result<(), ()> {
    let Some(object) = completeness.and_then(Value::as_object) else {
        return Err(());
    };
    match object.get("type").and_then(Value::as_str) {
        Some("complete") => {
            if object.len() != 1 {
                return Err(());
            }
        }
        Some("partial") => {
            if object.len() != 3
                || !object.contains_key("finalized")
                || !object.contains_key("covered_owner_dates")
            {
                return Err(());
            }
        }
        _ => return Err(()),
    }
    Ok(())
}

fn is_lowercase_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
}

fn is_strict_date(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| matches!(index, 4 | 7) || byte.is_ascii_digit())
        && NaiveDate::parse_from_str(value, "%Y-%m-%d").is_ok()
}

/// The four stable v1 rejection classes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum Rejection {
    Truncated,
    Transient,
    ChecksumInvalid,
    ManifestIncomplete,
}

impl Rejection {
    const fn code(self) -> &'static str {
        match self {
            Self::Truncated => "truncated",
            Self::Transient => "transient",
            Self::ChecksumInvalid => "checksum_invalid",
            Self::ManifestIncomplete => "manifest_incomplete",
        }
    }
}

/// Ingest one manifest-described artifact upload into the SQLite store.
///
/// Rejected uploads are protocol outcomes and are returned as receipts; only
/// an unusable store or invalid argument paths surface as errors, because no
/// receipt could be produced for them.
///
/// # Errors
///
/// Returns a [`DataStoreOpenError`] with a health-free reason when the
/// argument paths or the database are unusable.
pub(super) fn ingest_upload(
    database: &Path,
    manifest_path: &Path,
    artifact_path: &Path,
) -> Result<Value, DataStoreOpenError> {
    let database = validated_ingest_database_path(database, manifest_path, artifact_path)?;
    if !manifest_path.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data manifest path must be absolute",
        ));
    }
    if !artifact_path.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data artifact path must be absolute",
        ));
    }
    let mut connection = data_sqlite::open_read_write(&database)?;
    data_sqlite::migrate(&mut connection)?;

    let Some(manifest) = read_manifest(manifest_path)? else {
        // An unreadable, oversized, or schema-invalid manifest is unidentifiable:
        // reject without a partition view, exactly like the contract fixture.
        return Ok(rejected_receipt(Rejection::ManifestIncomplete, None));
    };

    let bytes = match read_artifact_bytes(artifact_path, manifest.byte_count) {
        ArtifactRead::Bytes(bytes) => bytes,
        ArtifactRead::Transient => {
            // Local mapping decision: the artifact file could not be read as
            // bytes at dispatch time. See docs/agent-data.md; the HTTPS
            // transport mapping is deliberately left to the gateway cycle.
            return Ok(rejected_receipt(
                Rejection::Transient,
                partition_view(&connection, &manifest.owner_date)?,
            ));
        }
        ArtifactRead::Truncated => {
            return Ok(rejected_receipt(
                Rejection::Truncated,
                partition_view(&connection, &manifest.owner_date)?,
            ));
        }
    };
    if sha256_hex(&bytes) != manifest.sha256 {
        return Ok(rejected_receipt(
            Rejection::ChecksumInvalid,
            partition_view(&connection, &manifest.owner_date)?,
        ));
    }

    promote(&mut connection, &manifest, &bytes, artifact_path)?;
    let partition = partition_view_of_revision(&connection, &manifest)?
        .ok_or_else(|| DataStoreOpenError::new("the Agent Data ingest could not be completed"))?;
    Ok(json!({
        "schema": INGEST_RESPONSE_SCHEMA,
        "schema_version": INGEST_SCHEMA_VERSION,
        "outcome": "accepted",
        "stored": {
            "revision_id": manifest.sha256,
            "byte_count": manifest.byte_count,
            "completeness": manifest.completeness.to_json()
        },
        "partition": partition
    }))
}

enum ArtifactRead {
    Bytes(Vec<u8>),
    Truncated,
    Transient,
}

/// Read the manifest document, treating every unreadable or invalid form as an
/// unidentifiable (structurally incomplete) manifest.
fn read_manifest(path: &Path) -> Result<Option<IngestManifest>, DataStoreOpenError> {
    let Ok(metadata) = std::fs::metadata(path) else {
        return Ok(None);
    };
    if !metadata.is_file() || metadata.len() > MAXIMUM_MANIFEST_BYTES {
        return Ok(None);
    }
    match std::fs::read(path) {
        Ok(bytes) => match serde_json::from_slice::<Value>(&bytes) {
            Ok(value) => Ok(IngestManifest::from_value(value).ok()),
            Err(_) => Ok(None),
        },
        Err(_) => Ok(None),
    }
}

/// Read the exact artifact bytes, mapping genuine local I/O failures to
/// `transient` and any declared-length mismatch to `truncated`.
fn read_artifact_bytes(path: &Path, declared_byte_count: u64) -> ArtifactRead {
    let Ok(metadata) = std::fs::metadata(path) else {
        return ArtifactRead::Transient;
    };
    if !metadata.is_file() {
        // A directory or special file at dispatch time is not readable bytes.
        return ArtifactRead::Transient;
    }
    if metadata.len() != declared_byte_count {
        return ArtifactRead::Truncated;
    }
    match std::fs::read(path) {
        Ok(bytes) if bytes.len() as u64 == declared_byte_count => ArtifactRead::Bytes(bytes),
        Ok(_) => ArtifactRead::Truncated,
        Err(_) => ArtifactRead::Transient,
    }
}

/// Validate the database path first (mirroring `data import`), then the upload
/// paths: absolute, creatable parent, non-symlink file, and stored apart from
/// the upload files themselves.
fn validated_ingest_database_path(
    database: &Path,
    manifest: &Path,
    artifact: &Path,
) -> Result<PathBuf, DataStoreOpenError> {
    if !database.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data database path must be absolute",
        ));
    }
    let parent = database.parent().ok_or_else(|| {
        DataStoreOpenError::new("the Agent Data database path has no parent directory")
    })?;
    let parent = parent
        .canonicalize()
        .map_err(|_| DataStoreOpenError::new("the Agent Data database directory does not exist"))?;
    let file_name = database
        .file_name()
        .ok_or_else(|| DataStoreOpenError::new("the Agent Data database path has no file name"))?;
    let resolved = parent.join(file_name);
    if let Ok(metadata) = std::fs::symlink_metadata(&resolved) {
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(DataStoreOpenError::new(
                "the Agent Data database must be a non-symlink file",
            ));
        }
    }
    for upload in [manifest, artifact] {
        if let Ok(target) = upload.canonicalize() {
            if target == resolved {
                return Err(DataStoreOpenError::new(
                    "the Agent Data database must be stored outside the upload files",
                ));
            }
        }
    }
    Ok(resolved)
}

/// Promote one verified upload into the store inside a single transaction.
///
/// Idempotent by SHA-256 identity: identical bytes never duplicate rows and
/// never advance the store content revision. Partition bookkeeping records
/// every accepted revision; a re-statement of identical bytes may only upgrade
/// its recorded completeness from partial to complete (never the reverse), and
/// any change of a partition's authoritative revision is recorded as
/// supersession bookkeeping. Nothing is ever deleted.
fn promote(
    connection: &mut Connection,
    manifest: &IngestManifest,
    bytes: &[u8],
    artifact_path: &Path,
) -> Result<(), DataStoreOpenError> {
    let transaction = connection
        .transaction()
        .map_err(|_| DataStoreOpenError::new("the Agent Data ingest could not be completed"))?;
    let failure = || DataStoreOpenError::new("the Agent Data ingest could not be completed");
    let existed: i64 = transaction
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM artifacts WHERE artifact_id = ?1)",
            params![manifest.sha256],
            |row| row.get(0),
        )
        .map_err(|_| failure())?;
    if existed == 0 {
        let (entry, records) = indexed_entry(manifest, artifact_path);
        data_sqlite::insert_parsed_artifact(&transaction, bytes, &entry, &records)?;
    }
    let previous_authoritative = authoritative_revision(&transaction, &manifest.owner_date)?;
    let covered = match &manifest.completeness {
        Completeness::Complete => None,
        Completeness::Partial {
            covered_owner_dates,
        } => Some(serde_json::to_string(covered_owner_dates).map_err(|_| failure())?),
    };
    transaction
        .execute(
            "INSERT INTO ingested_partitions \
             (revision_id, owner_date, completeness, covered_owner_dates, byte_count, accepted_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(revision_id) DO UPDATE SET \
             completeness = CASE WHEN excluded.completeness = 'complete' \
                 THEN 'complete' ELSE ingested_partitions.completeness END, \
             covered_owner_dates = CASE WHEN excluded.completeness = 'partial' \
                 AND ingested_partitions.completeness = 'partial' \
                 THEN excluded.covered_owner_dates \
                 ELSE ingested_partitions.covered_owner_dates END",
            params![
                manifest.sha256,
                manifest.owner_date,
                manifest.completeness.type_text(),
                covered,
                i64::try_from(manifest.byte_count).unwrap_or(i64::MAX),
                Utc::now().to_rfc3339()
            ],
        )
        .map_err(|_| failure())?;
    if let (Some((previous_id, _)), Some((current_id, _))) = (
        previous_authoritative,
        authoritative_revision(&transaction, &manifest.owner_date)?,
    ) {
        if previous_id != current_id {
            transaction
                .execute(
                    "INSERT OR IGNORE INTO supersessions \
                     (relative_path, superseded_artifact_id, superseding_artifact_id, observed_at) \
                     VALUES (?1, ?2, ?3, ?4)",
                    params![
                        format!("ingest-partition:{}", manifest.owner_date),
                        previous_id,
                        current_id,
                        Utc::now().to_rfc3339()
                    ],
                )
                .map_err(|_| failure())?;
        }
    }
    transaction
        .commit()
        .map_err(|_| DataStoreOpenError::new("the Agent Data ingest could not be completed"))
}

/// Build the store entry for one upload.
///
/// When the read model recognizes the artifact bytes, the row is exactly what
/// directory import would store for the same bytes (guarded on the verified
/// SHA-256 identity), so promotion and import stay byte-identity compatible.
/// Otherwise the row carries the manifest-declared identity with zero record
/// rows — never a fabricated index.
fn indexed_entry(
    manifest: &IngestManifest,
    artifact_path: &Path,
) -> (ArtifactEntry, Vec<RecordEntry>) {
    let source = SourceFile {
        path: artifact_path.to_path_buf(),
        relative_path: format!("ingest/{}", manifest.sha256),
        byte_count: manifest.byte_count,
        modified_nanos: 0,
    };
    match data_backend::parse_artifact(&source) {
        Ok(Some((mut entry, records)))
            if entry.artifact_id == manifest.sha256
                && entry.byte_count == manifest.byte_count
                && entry.physical_format == manifest.physical_format =>
        {
            entry.relative_path = source.relative_path;
            (entry, records)
        }
        _ => {
            let entry = ArtifactEntry {
                artifact_id: manifest.sha256.clone(),
                relative_path: source.relative_path,
                byte_count: manifest.byte_count,
                media_type: manifest.media_type.clone(),
                physical_format: manifest.physical_format,
                schemas: vec![ArtifactSchema {
                    schema: manifest.artifact_schema.clone(),
                    schema_version: Some(manifest.artifact_schema_version),
                }],
                capture_status: manifest.completeness.type_text().to_owned(),
                detail_levels: Vec::new(),
                record_count: 0,
            };
            (entry, Vec::new())
        }
    }
}

/// The authoritative revision of one owner-date partition: the newest complete
/// accepted revision, or — while no complete revision exists — the newest
/// accepted partial. A partial never displaces a complete revision.
fn authoritative_revision(
    connection: &Connection,
    owner_date: &str,
) -> Result<Option<(String, Value)>, DataStoreOpenError> {
    let failure = || DataStoreOpenError::new("the Agent Data ingest could not be completed");
    let row = connection
        .query_row(
            "SELECT revision_id, completeness, covered_owner_dates FROM ingested_partitions \
             WHERE owner_date = ?1 \
             ORDER BY CASE completeness WHEN 'complete' THEN 0 ELSE 1 END, ingest_sequence DESC \
             LIMIT 1",
            params![owner_date],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|_| failure())?;
    let Some((revision_id, completeness_text, covered_text)) = row else {
        return Ok(None);
    };
    let completeness = if completeness_text == "complete" {
        json!({"type": "complete"})
    } else {
        let covered: Value = covered_text
            .as_deref()
            .and_then(|text| serde_json::from_str(text).ok())
            .unwrap_or_else(|| json!([]));
        json!({"type": "partial", "finalized": true, "covered_owner_dates": covered})
    };
    Ok(Some((revision_id, completeness)))
}

/// Build the partition view for a receipt, or `None` when the partition holds
/// no accepted revision yet (the response schema's `authoritative` member is
/// required whenever the view is present).
fn partition_view(
    connection: &Connection,
    owner_date: &str,
) -> Result<Option<Value>, DataStoreOpenError> {
    let failure = || DataStoreOpenError::new("the Agent Data ingest could not be completed");
    let (complete_present, partial_present): (i64, i64) = connection
        .query_row(
            "SELECT \
             EXISTS(SELECT 1 FROM ingested_partitions WHERE owner_date = ?1 \
                 AND completeness = 'complete'), \
             EXISTS(SELECT 1 FROM ingested_partitions WHERE owner_date = ?1 \
                 AND completeness = 'partial')",
            params![owner_date],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|_| failure())?;
    if complete_present == 0 && partial_present == 0 {
        return Ok(None);
    }
    let Some((revision_id, completeness)) = authoritative_revision(connection, owner_date)? else {
        return Ok(None);
    };
    Ok(Some(json!({
        "owner_date": owner_date,
        "authoritative": {
            "revision_id": revision_id,
            "completeness": completeness
        },
        "complete_revision_present": complete_present == 1,
        "partial_revision_present": partial_present == 1
    })))
}

/// Partition view for an accepted upload: normally the manifest's own
/// partition. Identical bytes already stored under a different manifest
/// owner-date fall back to that stored partition instead of failing the
/// receipt.
fn partition_view_of_revision(
    connection: &Connection,
    manifest: &IngestManifest,
) -> Result<Option<Value>, DataStoreOpenError> {
    if let Some(view) = partition_view(connection, &manifest.owner_date)? {
        return Ok(Some(view));
    }
    let stored: Option<String> = connection
        .query_row(
            "SELECT owner_date FROM ingested_partitions WHERE revision_id = ?1",
            params![manifest.sha256],
            |row| row.get(0),
        )
        .optional()
        .map_err(|_| DataStoreOpenError::new("the Agent Data ingest could not be completed"))?;
    match stored {
        Some(owner_date) => partition_view(connection, &owner_date),
        None => Ok(None),
    }
}

fn rejected_receipt(rejection: Rejection, partition: Option<Value>) -> Value {
    let mut receipt = json!({
        "schema": INGEST_RESPONSE_SCHEMA,
        "schema_version": INGEST_SCHEMA_VERSION,
        "outcome": "rejected",
        "rejection": {"code": rejection.code()}
    });
    if let (Some(object), Some(partition)) = (receipt.as_object_mut(), partition) {
        object.insert("partition".into(), partition);
    }
    receipt
}

#[cfg(test)]
mod tests {
    use std::fs;

    use serde_json::json;
    use tempfile::TempDir;

    use super::*;

    const DAY_BYTES: &str = "{\"schema\":\"healthmd.health_data\",\"schema_version\":8,\
\"date\":\"2026-03-15\",\"type\":\"health-data\",\"raw_capture_status\":\"complete\",\
\"unit_system\":\"metric\",\"units\":{},\"activity\":{\"steps\":12345}}";

    fn temporary() -> TempDir {
        tempfile::tempdir().expect("temporary root")
    }

    fn write_file(path: &Path, contents: &str) {
        std::fs::write(path, contents).expect("file write");
    }

    fn manifest_with_overrides(completeness: Value, overrides: &[(&str, Value)]) -> Value {
        let bytes = DAY_BYTES.as_bytes();
        let mut value = json!({
            "schema": "healthmd.agent_data_ingest",
            "schema_version": 1,
            "artifact_kind": "health_data_daily",
            "platform": "apple",
            "artifact_schema": "healthmd.health_data",
            "artifact_schema_version": 8,
            "owner_date": "2026-03-15",
            "physical_format": "json",
            "media_type": "application/json",
            "byte_count": bytes.len(),
            "sha256": sha256_hex(bytes),
            "completeness": completeness
        });
        for (key, replacement) in overrides {
            value
                .as_object_mut()
                .expect("manifest object")
                .insert((*key).to_owned(), replacement.clone());
        }
        value
    }

    fn manifest_for(contents: &str, completeness: Value) -> Value {
        let mut value = manifest_with_overrides(completeness, &[]);
        let object = value.as_object_mut().expect("manifest object");
        object.insert("sha256".into(), json!(sha256_hex(contents.as_bytes())));
        object.insert("byte_count".into(), json!(contents.len()));
        value
    }

    fn complete() -> Value {
        json!({"type": "complete"})
    }

    fn partial() -> Value {
        json!({"type": "partial", "finalized": true, "covered_owner_dates": ["2026-03-15"]})
    }

    fn ingest_into(
        temporary: &TempDir,
        manifest: Value,
        artifact_contents: &str,
    ) -> Result<Value, DataStoreOpenError> {
        let database = temporary.path().join("agent-data.sqlite");
        let manifest_path = temporary.path().join("manifest.json");
        let artifact_path = temporary.path().join("day.json");
        write_file(&manifest_path, &serde_json::to_string(&manifest).unwrap());
        write_file(&artifact_path, artifact_contents);
        ingest_upload(&database, &manifest_path, &artifact_path)
    }

    fn sorted_keys(value: &Value) -> Vec<String> {
        let mut keys: Vec<String> = value.as_object().expect("object").keys().cloned().collect();
        keys.sort();
        keys
    }

    #[test]
    fn manifest_validation_accepts_every_documented_shape() {
        assert!(IngestManifest::from_value(manifest_for(DAY_BYTES, complete())).is_ok());
        assert!(
            IngestManifest::from_value(manifest_for(
                DAY_BYTES,
                json!({
                    "type": "partial", "finalized": true,
                    "covered_owner_dates": ["2026-03-15", "2026-03-16"]
                })
            ))
            .is_ok()
        );
        let raw = manifest_with_overrides(complete(), &[("artifact_kind", json!("raw_snapshot"))]);
        assert!(IngestManifest::from_value(raw).is_ok());
        let android = manifest_with_overrides(
            partial(),
            &[
                ("platform", json!("android")),
                ("physical_format", json!("ndjson")),
                ("media_type", json!("application/x-ndjson")),
            ],
        );
        assert!(IngestManifest::from_value(android).is_ok());
    }

    #[test]
    fn manifest_validation_rejects_every_undocumented_shape() {
        let rejections = [
            manifest_with_overrides(complete(), &[("schema", json!("healthmd.other"))]),
            manifest_with_overrides(complete(), &[("schema_version", json!(2))]),
            manifest_with_overrides(complete(), &[("schema_version", json!("1"))]),
            manifest_with_overrides(complete(), &[("extra", json!(null))]),
            manifest_with_overrides(complete(), &[("artifact_kind", json!("embedded_records"))]),
            manifest_with_overrides(complete(), &[("platform", json!("watchos"))]),
            manifest_with_overrides(complete(), &[("physical_format", json!("xml"))]),
            manifest_with_overrides(complete(), &[("artifact_schema", json!(""))]),
            manifest_with_overrides(complete(), &[("artifact_schema", json!("x".repeat(129)))]),
            manifest_with_overrides(complete(), &[("artifact_schema_version", json!(0))]),
            manifest_with_overrides(complete(), &[("media_type", json!(""))]),
            manifest_with_overrides(complete(), &[("media_type", json!("x".repeat(129)))]),
            manifest_with_overrides(complete(), &[("owner_date", json!("2026-3-15"))]),
            manifest_with_overrides(complete(), &[("owner_date", json!("2026-02-30"))]),
            manifest_with_overrides(complete(), &[("owner_date", json!("not-a-date"))]),
            manifest_with_overrides(complete(), &[("byte_count", json!(0))]),
            manifest_with_overrides(complete(), &[("byte_count", json!(67_108_865))]),
            manifest_with_overrides(complete(), &[("sha256", json!("A".repeat(64)))]),
            manifest_with_overrides(complete(), &[("sha256", json!("abc"))]),
            manifest_with_overrides(complete(), &[("sha256", json!("z".repeat(64)))]),
            manifest_with_overrides(
                json!({"type": "partial", "finalized": false, "covered_owner_dates": ["2026-03-15"]}),
                &[],
            ),
            manifest_with_overrides(
                json!({"type": "partial", "finalized": true, "covered_owner_dates": []}),
                &[],
            ),
            manifest_with_overrides(
                json!({"type": "partial", "finalized": true,
                    "covered_owner_dates": ["2026-03-15", "2026-03-15"]}),
                &[],
            ),
            manifest_with_overrides(
                json!({"type": "partial", "finalized": true, "covered_owner_dates": ["bad-date"]}),
                &[],
            ),
            manifest_with_overrides(
                json!({"type": "partial", "finalized": true,
                    "covered_owner_dates": ["2026-03-15"], "extra": 1}),
                &[],
            ),
            manifest_with_overrides(json!({"type": "complete", "covered_owner_dates": []}), &[]),
            json!({"type": "complete"}),
            manifest_with_overrides(partial(), &[("artifact_kind", json!("raw_snapshot"))]),
            manifest_with_overrides(partial(), &[("artifact_kind", json!("raw_changes"))]),
        ];
        for (index, rejected) in rejections.iter().enumerate() {
            assert!(
                IngestManifest::from_value(rejected.clone()).is_err(),
                "manifest case {index} should be rejected: {rejected}"
            );
        }
        let too_many_dates = manifest_with_overrides(
            json!({
                "type": "partial",
                "finalized": true,
                "covered_owner_dates": (0..401)
                    .map(|day| format!("2025-{:02}-{:02}", (day / 28) % 12 + 1, day % 28 + 1))
                    .collect::<Vec<_>>()
            }),
            &[],
        );
        assert!(IngestManifest::from_value(too_many_dates).is_err());
    }

    #[test]
    fn accepted_receipt_matches_the_response_grammar_exactly() {
        let temporary = temporary();
        let receipt = ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES)
            .expect("ingest should accept");
        assert_eq!(receipt["outcome"], "accepted");
        assert_eq!(
            sorted_keys(&receipt),
            ["outcome", "partition", "schema", "schema_version", "stored"]
        );
        let stored = &receipt["stored"];
        assert_eq!(
            sorted_keys(stored),
            ["byte_count", "completeness", "revision_id"]
        );
        assert_eq!(stored["revision_id"], sha256_hex(DAY_BYTES.as_bytes()));
        assert_eq!(stored["byte_count"], DAY_BYTES.len() as u64);
        assert_eq!(stored["completeness"], json!({"type": "complete"}));
        let partition = &receipt["partition"];
        assert_eq!(
            sorted_keys(partition),
            [
                "authoritative",
                "complete_revision_present",
                "owner_date",
                "partial_revision_present"
            ]
        );
        assert_eq!(
            sorted_keys(&partition["authoritative"]),
            ["completeness", "revision_id"]
        );
        assert_eq!(partition["owner_date"], "2026-03-15");
        assert_eq!(partition["complete_revision_present"], true);
        assert_eq!(partition["partial_revision_present"], false);
        assert_eq!(
            partition["authoritative"]["revision_id"],
            sha256_hex(DAY_BYTES.as_bytes())
        );
    }

    #[test]
    fn rejected_receipts_carry_only_the_documented_grammar() {
        let temporary = temporary();
        ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES)
            .expect("first ingest accepts");
        let day_digest = sha256_hex(DAY_BYTES.as_bytes());

        // truncated: the declared byte count disagrees with the artifact file.
        let mut truncated = manifest_for(DAY_BYTES, complete());
        truncated
            .as_object_mut()
            .unwrap()
            .insert("byte_count".into(), json!(DAY_BYTES.len() + 1));
        let receipt = ingest_into(&temporary, truncated, DAY_BYTES).expect("receipt");
        assert_eq!(receipt["outcome"], "rejected");
        assert_eq!(receipt["rejection"], json!({"code": "truncated"}));
        assert_eq!(
            sorted_keys(&receipt),
            [
                "outcome",
                "partition",
                "rejection",
                "schema",
                "schema_version"
            ]
        );
        // The rejection carries the current partition view of the manifest's partition.
        assert_eq!(
            receipt["partition"]["authoritative"]["revision_id"],
            day_digest
        );

        // checksum_invalid: correct length, wrong digest.
        let wrong = format!(
            "{}{}",
            &day_digest[..63],
            if day_digest.ends_with('0') { '1' } else { '0' }
        );
        let mut checksum = manifest_for(DAY_BYTES, complete());
        checksum
            .as_object_mut()
            .unwrap()
            .insert("sha256".into(), json!(wrong));
        let receipt = ingest_into(&temporary, checksum, DAY_BYTES).expect("receipt");
        assert_eq!(receipt["outcome"], "rejected");
        assert_eq!(receipt["rejection"], json!({"code": "checksum_invalid"}));

        // manifest_incomplete: the manifest document is unidentifiable.
        let database = temporary.path().join("agent-data.sqlite");
        let manifest_path = temporary.path().join("missing.json");
        let artifact_path = temporary.path().join("day.json");
        write_file(&artifact_path, DAY_BYTES);
        let receipt = ingest_upload(&database, &manifest_path, &artifact_path).expect("receipt");
        assert_eq!(receipt["rejection"], json!({"code": "manifest_incomplete"}));
        assert_eq!(
            sorted_keys(&receipt),
            ["outcome", "rejection", "schema", "schema_version"]
        );

        // transient: the artifact path exists but is not readable bytes.
        let directory = temporary.path().join("artifact-directory");
        fs::create_dir(&directory).expect("directory");
        let manifest_path = temporary.path().join("manifest.json");
        write_file(
            &manifest_path,
            &serde_json::to_string(&manifest_for(DAY_BYTES, complete())).unwrap(),
        );
        let receipt = ingest_upload(&database, &manifest_path, &directory).expect("receipt");
        assert_eq!(receipt["rejection"], json!({"code": "transient"}));
    }

    #[test]
    fn rejection_of_an_unknown_partition_omits_the_partition_view() {
        let temporary = temporary();
        let mut other_partition = manifest_for(DAY_BYTES, complete());
        other_partition
            .as_object_mut()
            .unwrap()
            .insert("owner_date".into(), json!("2027-01-01"));
        // Keep the digest consistent so only the partition differs.
        let receipt = ingest_into(&temporary, other_partition, DAY_BYTES).expect("accepts");
        assert_eq!(receipt["partition"]["owner_date"], "2027-01-01");

        let mut rejected_manifest = manifest_for(DAY_BYTES, complete());
        rejected_manifest
            .as_object_mut()
            .unwrap()
            .insert("owner_date".into(), json!("2028-02-02"));
        rejected_manifest
            .as_object_mut()
            .unwrap()
            .insert("sha256".into(), json!(sha256_hex(b"mismatched")));
        let receipt = ingest_into(&temporary, rejected_manifest, DAY_BYTES).expect("receipt");
        assert_eq!(receipt["rejection"], json!({"code": "checksum_invalid"}));
        assert!(
            receipt.get("partition").is_none(),
            "a partition with no accepted revision must omit the view"
        );
    }

    #[test]
    fn idempotent_reingest_returns_a_stable_receipt_without_duplicate_rows() {
        let temporary = temporary();
        let first = ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES)
            .expect("first ingest accepts");
        let second = ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES)
            .expect("reingest accepts");
        assert_eq!(
            serde_json::to_string(&first).unwrap(),
            serde_json::to_string(&second).unwrap(),
            "identical bytes must produce a stable receipt"
        );
        let connection = Connection::open(temporary.path().join("agent-data.sqlite")).unwrap();
        let (artifacts, partitions): (i64, i64) = connection
            .query_row(
                "SELECT (SELECT COUNT(*) FROM artifacts), \
                 (SELECT COUNT(*) FROM ingested_partitions)",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!((artifacts, partitions), (1, 1));
        let revision = data_sqlite::read_content_revision(&connection).unwrap();
        drop(connection);
        ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES).unwrap();
        let connection = Connection::open(temporary.path().join("agent-data.sqlite")).unwrap();
        assert_eq!(
            data_sqlite::read_content_revision(&connection).unwrap(),
            revision,
            "identical bytes must not change the store revision"
        );
    }

    #[test]
    fn partial_is_authoritative_until_a_complete_revision_arrives() {
        let temporary = temporary();
        let receipt = ingest_into(&temporary, manifest_for(DAY_BYTES, partial()), DAY_BYTES)
            .expect("partial accepts");
        assert_eq!(receipt["outcome"], "accepted");
        assert_eq!(
            receipt["stored"]["completeness"],
            json!({"type": "partial", "finalized": true, "covered_owner_dates": ["2026-03-15"]})
        );
        assert_eq!(receipt["partition"]["complete_revision_present"], false);
        assert_eq!(receipt["partition"]["partial_revision_present"], true);
        assert_eq!(
            receipt["partition"]["authoritative"]["completeness"]["type"], "partial",
            "partial coverage is never concealed while it is authoritative"
        );

        // Identical bytes restated as complete upgrade the recorded revision.
        let complete_receipt =
            ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES)
                .expect("complete accepts");
        assert_eq!(
            complete_receipt["partition"]["complete_revision_present"],
            true
        );
        assert_eq!(
            complete_receipt["partition"]["partial_revision_present"],
            false
        );
        assert_eq!(
            complete_receipt["partition"]["authoritative"]["completeness"],
            json!({"type": "complete"}),
            "a complete restatement must displace the partial"
        );
        let connection = Connection::open(temporary.path().join("agent-data.sqlite")).unwrap();
        let (artifacts, partitions, supersessions): (i64, i64, i64) = connection
            .query_row(
                "SELECT (SELECT COUNT(*) FROM artifacts), \
                 (SELECT COUNT(*) FROM ingested_partitions), \
                 (SELECT COUNT(*) FROM supersessions)",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!((artifacts, partitions), (1, 1), "same bytes, one revision");
        assert_eq!(
            supersessions, 0,
            "a same-revision upgrade is not a supersession"
        );

        // A later partial for the same partition must not shadow a complete revision.
        let other_day = DAY_BYTES.replacen("12345", "54321", 1);
        let later = ingest_into(&temporary, manifest_for(&other_day, partial()), &other_day)
            .expect("later partial accepts");
        assert_eq!(
            later["partition"]["authoritative"]["completeness"],
            json!({"type": "complete"}),
            "a partial never displaces a complete revision"
        );
        assert_eq!(later["stored"]["completeness"]["type"], "partial");
        assert_eq!(later["partition"]["partial_revision_present"], true);
        let connection = Connection::open(temporary.path().join("agent-data.sqlite")).unwrap();
        let (artifacts, partitions): (i64, i64) = connection
            .query_row(
                "SELECT (SELECT COUNT(*) FROM artifacts), \
                 (SELECT COUNT(*) FROM ingested_partitions WHERE owner_date = '2026-03-15')",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(
            (artifacts, partitions),
            (2, 2),
            "nothing was deleted; both revisions stay stored"
        );
    }

    #[test]
    fn supersession_bookkeeping_records_authoritative_flips_without_deletion() {
        let temporary = temporary();
        ingest_into(&temporary, manifest_for(DAY_BYTES, partial()), DAY_BYTES)
            .expect("partial accepts");
        let complete_day = DAY_BYTES.replacen("12345", "54321", 1);
        let receipt = ingest_into(
            &temporary,
            manifest_for(&complete_day, complete()),
            &complete_day,
        )
        .expect("complete accepts");
        assert_eq!(receipt["outcome"], "accepted");
        assert_eq!(
            receipt["partition"]["authoritative"]["completeness"],
            json!({"type": "complete"})
        );
        let connection = Connection::open(temporary.path().join("agent-data.sqlite")).unwrap();
        let (supersessions, artifacts, partitions, payloads): (i64, i64, i64, i64) = connection
            .query_row(
                "SELECT (SELECT COUNT(*) FROM supersessions), \
                 (SELECT COUNT(*) FROM artifacts), \
                 (SELECT COUNT(*) FROM ingested_partitions), \
                 (SELECT COUNT(*) FROM artifacts WHERE payload IS NOT NULL)",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!(supersessions, 1, "the partial-to-complete flip is recorded");
        assert_eq!(
            (artifacts, partitions, payloads),
            (2, 2, 2),
            "non-destructive: both revisions and payloads stay stored"
        );
    }

    #[test]
    fn import_then_ingest_of_identical_bytes_adds_only_partition_bookkeeping() {
        let temporary = temporary();
        let exports = temporary.path().join("exports");
        fs::create_dir(&exports).expect("exports");
        write_file(&exports.join("day.json"), DAY_BYTES);
        let database = temporary.path().join("store.sqlite");
        data_sqlite::import_data(&database, &exports).expect("import");
        let revision_after_import =
            data_sqlite::read_content_revision(&Connection::open(&database).unwrap()).unwrap();

        let manifest_path = temporary.path().join("manifest.json");
        let artifact_path = temporary.path().join("upload.json");
        write_file(
            &manifest_path,
            &serde_json::to_string(&manifest_for(DAY_BYTES, complete())).unwrap(),
        );
        write_file(&artifact_path, DAY_BYTES);
        let receipt = ingest_upload(&database, &manifest_path, &artifact_path).expect("accepts");
        assert_eq!(receipt["outcome"], "accepted");
        assert_eq!(
            receipt["partition"]["authoritative"]["revision_id"],
            sha256_hex(DAY_BYTES.as_bytes())
        );
        let connection = Connection::open(&database).unwrap();
        let (artifacts, partitions): (i64, i64) = connection
            .query_row(
                "SELECT (SELECT COUNT(*) FROM artifacts), \
                 (SELECT COUNT(*) FROM ingested_partitions)",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!((artifacts, partitions), (1, 1));
        assert_eq!(
            data_sqlite::read_content_revision(&connection).unwrap(),
            revision_after_import,
            "partition-only bookkeeping must not invalidate cursors"
        );
    }

    #[test]
    fn unrecognized_content_is_stored_with_manifest_metadata_and_no_fabricated_records() {
        let temporary = temporary();
        let opaque = "not-a-recognized-healthmd-artifact-but-exact-bytes";
        let receipt = ingest_into(&temporary, manifest_for(opaque, complete()), opaque)
            .expect("integrity-verified upload accepts");
        assert_eq!(receipt["outcome"], "accepted");
        let connection = Connection::open(temporary.path().join("agent-data.sqlite")).unwrap();
        let (records, schemas, detail_levels): (i64, i64, i64) = connection
            .query_row(
                "SELECT (SELECT COUNT(*) FROM records), \
                 (SELECT COUNT(*) FROM artifact_schemas WHERE schema = 'healthmd.health_data'), \
                 (SELECT COUNT(*) FROM artifact_detail_levels)",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(records, 0, "no fabricated record index");
        assert_eq!(
            schemas, 1,
            "the manifest-declared schema identity is stored"
        );
        assert_eq!(detail_levels, 0, "no fabricated detail levels");
        let payload: String = connection
            .query_row(
                "SELECT CAST(payload AS TEXT) FROM artifacts WHERE artifact_id = ?1",
                params![sha256_hex(opaque.as_bytes())],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(payload, opaque, "the exact bytes are stored unchanged");
    }

    #[test]
    fn argument_paths_are_validated_with_health_free_errors() {
        let temporary = temporary();
        let relative = std::path::Path::new("manifest.json");
        let absolute = temporary.path().join("manifest.json");
        let database = temporary.path().join("agent-data.sqlite");
        let error = ingest_upload(&database, relative, &absolute).unwrap_err();
        assert_eq!(
            error.to_string(),
            "the Agent Data manifest path must be absolute"
        );
        let error = ingest_upload(&database, &absolute, relative).unwrap_err();
        assert_eq!(
            error.to_string(),
            "the Agent Data artifact path must be absolute"
        );
        let error =
            ingest_upload(std::path::Path::new("store.sqlite"), &absolute, &absolute).unwrap_err();
        assert_eq!(
            error.to_string(),
            "the Agent Data database path must be absolute"
        );

        // The database may not be one of the upload files.
        write_file(&absolute, "{}");
        write_file(&temporary.path().join("artifact.json"), DAY_BYTES);
        let artifact = temporary.path().join("artifact.json");
        let same = temporary.path().join("manifest.json");
        let error = ingest_upload(&same, &same, &artifact).unwrap_err();
        assert_eq!(
            error.to_string(),
            "the Agent Data database must be stored outside the upload files"
        );
    }

    #[test]
    fn a_version_one_database_is_upgraded_in_place_and_stays_readable() {
        let temporary = temporary();
        let database = temporary.path().join("agent-data.sqlite");
        ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES).expect("accepts");
        {
            let connection = Connection::open(&database).unwrap();
            connection.execute("PRAGMA user_version = 1", []).unwrap();
        }
        let receipt = ingest_into(&temporary, manifest_for(DAY_BYTES, complete()), DAY_BYTES)
            .expect("upgrade-and-reingest accepts");
        assert_eq!(receipt["outcome"], "accepted");
        let connection = Connection::open(&database).unwrap();
        let version: i64 = connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, i64::from(data_sqlite::DATABASE_SCHEMA_VERSION));
        let partitions: i64 = connection
            .query_row("SELECT COUNT(*) FROM ingested_partitions", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(partitions, 1, "rows survive the version round-trip");
    }

    #[test]
    fn digest_and_date_helpers_enforce_the_contract_formats() {
        assert!(is_lowercase_sha256(&"0".repeat(64)));
        assert!(!is_lowercase_sha256(&"0".repeat(63)));
        assert!(!is_lowercase_sha256(
            "0123456789abcdef0123456789ABCDEF0123456789abcdef0123456789abcdef"
        ));
        assert!(is_strict_date("2026-02-28"));
        assert!(!is_strict_date("2026-2-28"));
        assert!(!is_strict_date("2026-00-01"));
        assert!(!is_strict_date("2026-01-32"));
        assert!(!is_strict_date("20260101"));
    }
}
