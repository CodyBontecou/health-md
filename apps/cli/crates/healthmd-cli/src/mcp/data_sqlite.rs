//! Health.md-owned `SQLite` Agent Data store.
//!
//! The second local [`ArtifactStore`] backing class: a single `SQLite` database that
//! stores the EXACT artifact bytes plus indexing metadata and exposes the identical
//! Agent Data grant, query, response, and MCP operation contracts as the directory
//! store. The database is append-safe and non-destructive: imports insert rows and
//! supersession bookkeeping only, and no stored payload is ever deleted or rewritten.
//! Retention and cleanup stay deferred to the user by design.
//!
//! Recognition and parsing of export artifacts are shared with the directory store
//! through `data_backend::parse_artifact`; grant evaluation, cursor mechanics,
//! pagination, and chunking are shared through `data_backend::execute_query`.

use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
    path::{Path, PathBuf},
    sync::Arc,
};

use async_trait::async_trait;
use chrono::{DateTime, NaiveDate, Utc};
use healthmd_operations::{
    AgentDataDetailLevel, AgentDataGrant, AgentDataQueryRequest, ArtifactStore,
    BackendCapabilities, BackendError, CallContext,
};
use rusqlite::{Connection, OpenFlags, params};
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use uuid::Uuid;

use super::data_backend::{
    self, ArtifactByteSource, ArtifactEntry, ArtifactIndex, ArtifactSchema, DataServeOptions,
    DataStoreOpenError, INDEX_SCHEMA, INDEX_SCHEMA_VERSION, MAXIMUM_GRANT_BYTES,
    MAXIMUM_NDJSON_LINE_BYTES, PhysicalFormat, RecordEntry, RecordLocator, backend_failure,
    execute_query, record_order, scan_source_files, sha256_hex,
};

/// `PRAGMA user_version` of the current Agent Data `SQLite` schema.
///
/// Version 2 added the additive `ingested_partitions` table (ingestion protocol v1
/// owner-date partition bookkeeping). Databases at version 1 stay readable and are
/// upgraded in place by the next read-write open.
pub(super) const DATABASE_SCHEMA_VERSION: u32 = 2;
/// File-type identity so an unrelated `SQLite` database is never mistaken for a store.
const DATABASE_APPLICATION_ID: i32 = 0x484D_4441; // "HMDA"
const DATABASE_BUSY_TIMEOUT_MS: u64 = 5_000;

struct SqliteShared {
    connection: std::sync::Mutex<Connection>,
    index: std::sync::RwLock<Arc<ArtifactIndex>>,
}

/// Serves the Agent Data contract from a Health.md-owned `SQLite` database.
///
/// The connection is opened read-only, so serving can never mutate stored data.
pub struct SqliteArtifactStore {
    grant: Arc<AgentDataGrant>,
    cursor_key: [u8; 32],
    shared: Arc<SqliteShared>,
}

/// Reads verified artifact bytes from the `SQLite` payload table.
pub(super) struct SqliteByteSource {
    shared: Arc<SqliteShared>,
}

impl ArtifactByteSource for SqliteByteSource {
    fn full_bytes(&self, artifact: &ArtifactEntry) -> Result<Arc<Vec<u8>>, BackendError> {
        let connection = lock_connection(&self.shared)?;
        read_verified_payload(&connection, artifact).map(Arc::new)
    }

    fn verified_chunk(
        &self,
        artifact: &ArtifactEntry,
        offset: usize,
        maximum_bytes: usize,
    ) -> Result<(Vec<u8>, usize), BackendError> {
        let connection = lock_connection(&self.shared)?;
        let bytes = read_verified_payload(&connection, artifact)?;
        let total_byte_count = bytes.len();
        if offset > total_byte_count {
            return Err(data_backend::invalid_cursor());
        }
        let end = offset.saturating_add(maximum_bytes).min(total_byte_count);
        Ok((bytes[offset..end].to_vec(), total_byte_count))
    }

    fn verified_ndjson_line(
        &self,
        artifact: &ArtifactEntry,
        target_line: usize,
    ) -> Result<Vec<u8>, BackendError> {
        let connection = lock_connection(&self.shared)?;
        let bytes = read_verified_payload(&connection, artifact)?;
        let mut selected = None;
        let mut line_number = 0_usize;
        for line in bytes.split_inclusive(|byte| *byte == b'\n') {
            line_number += 1;
            if line.len() > MAXIMUM_NDJSON_LINE_BYTES {
                return Err(store_corrupt());
            }
            if line_number == target_line {
                let mut value = line.to_vec();
                if value.last() == Some(&b'\n') {
                    value.pop();
                    if value.last() == Some(&b'\r') {
                        value.pop();
                    }
                }
                selected = Some(value);
            }
        }
        selected.ok_or_else(|| backend_failure("healthmd_agent_source_changed"))
    }
}

/// Convert a bounded in-memory count into the database integer type without wrapping.
fn sqlite_count(value: usize) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

fn lock_connection(
    shared: &SqliteShared,
) -> Result<std::sync::MutexGuard<'_, Connection>, BackendError> {
    shared
        .connection
        .lock()
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))
}

fn store_corrupt() -> BackendError {
    BackendError::new(
        "healthmd_agent_store_corrupt",
        "The Agent Data store failed its stored-byte integrity verification.",
    )
}

impl SqliteArtifactStore {
    /// Open an imported Agent Data `SQLite` database for read-only serving.
    ///
    /// # Errors
    ///
    /// Returns a path-free error when the database, grant, or stored index is invalid.
    #[allow(clippy::needless_pass_by_value)]
    pub fn open(options: DataServeOptions) -> Result<Self, DataStoreOpenError> {
        let DataServeOptions::Database { database, grant } = &options else {
            return Err(DataStoreOpenError::new(
                "the database store requires --database backing options",
            ));
        };
        let database = validated_database_path(database)?;
        let grant_path = validated_grant_path(grant, &database)?;
        let grant_bytes = std::fs::read(&grant_path)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant could not be read"))?;
        let grant_value = serde_json::from_slice(&grant_bytes)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant is not valid JSON"))?;
        let grant = AgentDataGrant::from_value(grant_value)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant is invalid"))?;

        let connection = open_read_only(&database)?;
        verify_schema(&connection)?;
        let index = load_index(&connection)?;

        let mut cursor_key = [0_u8; 32];
        getrandom::fill(&mut cursor_key)
            .map_err(|_| DataStoreOpenError::new("secure cursor state could not be initialized"))?;

        Ok(Self {
            grant: Arc::new(grant),
            cursor_key,
            shared: Arc::new(SqliteShared {
                connection: std::sync::Mutex::new(connection),
                index: std::sync::RwLock::new(Arc::new(index)),
            }),
        })
    }
}

/// Reload the in-memory index when the database content revision changed.
fn refresh_index(shared: &Arc<SqliteShared>) -> Result<Arc<ArtifactIndex>, BackendError> {
    let connection = lock_connection(shared)?;
    let revision = read_content_revision(&connection)
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))?;
    if let Ok(cached) = shared.index.read() {
        if cached.index_revision == revision {
            return Ok(Arc::clone(&cached));
        }
    }
    let rebuilt =
        load_index(&connection).map_err(|_| backend_failure("healthmd_agent_index_failed"))?;
    let rebuilt = Arc::new(rebuilt);
    if let Ok(mut index) = shared.index.write() {
        *index = Arc::clone(&rebuilt);
    }
    Ok(rebuilt)
}

#[async_trait]
impl ArtifactStore for SqliteArtifactStore {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            source_kind: "artifact_store".to_owned(),
            transport: "local_database".to_owned(),
            supports_queries: true,
            supports_local_file_exports: false,
            requires_foreground_source: false,
            instructions: "Use the fixed Agent Data tools to read only records permitted by the configured grant. The Health.md-owned database is served read-only; no stored payload is ever deleted or rewritten.".to_owned(),
        }
    }

    async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let shared = Arc::clone(&self.shared);
        let index = tokio::task::spawn_blocking(move || refresh_index(&shared))
            .await
            .map_err(|_| backend_failure("healthmd_agent_index_failed"))??;
        Ok(json!({
            "schema": "healthmd.agent_data_readiness",
            "schema_version": 1,
            "ready": true,
            "source_kind": "database",
            "artifact_count": index.artifacts.len(),
            "record_count": index.records.len(),
            "index_revision": index.index_revision,
            "requires_foreground_source": false
        }))
    }

    async fn doctor(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let shared = Arc::clone(&self.shared);
        let result = tokio::task::spawn_blocking(move || {
            let index = refresh_index(&shared)?;
            doctor_with(&shared, &index)
        })
        .await
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))??;
        Ok(result)
    }

    async fn query_page(
        &self,
        context: &CallContext,
        request: AgentDataQueryRequest,
    ) -> Result<Value, BackendError> {
        if context.cancellation.is_cancelled() {
            return Err(BackendError::new(
                "healthmd_request_cancelled",
                "The Agent Data request was cancelled.",
            ));
        }
        let grant = Arc::clone(&self.grant);
        let cursor_key = self.cursor_key;
        let shared = Arc::clone(&self.shared);
        let result = tokio::task::spawn_blocking(move || {
            let index = refresh_index(&shared)?;
            let source = SqliteByteSource {
                shared: shared.clone(),
            };
            execute_query(&source, "database", &index, &grant, &cursor_key, &request)
        })
        .await
        .map_err(|_| backend_failure("healthmd_agent_query_failed"))??;
        if context.cancellation.is_cancelled() {
            return Err(BackendError::new(
                "healthmd_request_cancelled",
                "The Agent Data request was cancelled.",
            ));
        }
        Ok(result)
    }
}

/// Build the health-free database diagnostics report from the current store state.
fn doctor_with(shared: &Arc<SqliteShared>, index: &ArtifactIndex) -> Result<Value, BackendError> {
    let connection = lock_connection(shared)?;
    let failure = || backend_failure("healthmd_agent_index_failed");
    let (ignored, invalid): (u64, u64) = connection
        .query_row(
            "SELECT COALESCE(SUM(ignored_count), 0), COALESCE(SUM(invalid_count), 0) FROM imports",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|_| failure())?;
    let schema_version = connection
        .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
        .map_err(|_| failure())?;
    let quick_check = connection
        .query_row("PRAGMA quick_check", [], |row| row.get::<_, String>(0))
        .unwrap_or_else(|_| "failed".to_owned());
    let mut checked = 0_usize;
    let mut sha_mismatches = 0_usize;
    for artifact in &index.artifacts {
        checked += 1;
        if read_verified_payload(&connection, artifact).is_err() {
            sha_mismatches += 1;
        }
    }
    let superseded: u64 = connection
        .query_row("SELECT COUNT(*) FROM supersessions", [], |row| row.get(0))
        .map_err(|_| failure())?;
    Ok(json!({
        "schema": "healthmd.agent_data_diagnostics",
        "schema_version": 1,
        "ready": true,
        "source_kind": "database",
        "artifact_count": index.artifacts.len(),
        "record_count": index.records.len(),
        "ignored_file_count": ignored,
        "invalid_artifact_count": invalid,
        "index_revision": index.index_revision,
        "source_modified": false,
        "database": {
            "schema_version": schema_version,
            "integrity_check": quick_check,
            "checked_artifact_count": checked,
            "sha_mismatch_count": sha_mismatches,
            "superseded_artifact_observation_count": superseded,
            "non_destructive": true
        }
    }))
}

#[allow(clippy::missing_panics_doc, clippy::too_many_lines)]
pub(super) fn import_data(database: &Path, directory: &Path) -> Result<Value, DataStoreOpenError> {
    let database = validated_import_database_path(database, directory)?;
    let root = data_backend::validated_directory(directory)?;
    let mut connection = open_read_write(&database)?;
    migrate(&mut connection)?;

    let files = scan_source_files(&root)?;
    let started_at = Utc::now();
    let import_id = {
        let inserted = connection
            .execute(
                "INSERT INTO imports (started_at, finished_at, source_directory, scanned_file_count) \
                 VALUES (?1, NULL, ?2, ?3)",
                params![
                    started_at.to_rfc3339(),
                    root.to_string_lossy(),
                    sqlite_count(files.len())
                ],
            )
            .map_err(|_| {
                DataStoreOpenError::new("the Agent Data import could not be started")
            })?;
        if inserted != 1 {
            return Err(DataStoreOpenError::new(
                "the Agent Data import could not be started",
            ));
        }
        connection.last_insert_rowid()
    };

    let mut imported = 0_usize;
    let mut duplicates = 0_usize;
    let mut ignored = 0_usize;
    let mut invalid = 0_usize;
    let mut supersessions = 0_usize;
    for file in &files {
        match data_backend::parse_artifact(file) {
            Ok(Some((artifact, records))) => {
                let existed = connection
                    .query_row(
                        "SELECT EXISTS(SELECT 1 FROM artifacts WHERE artifact_id = ?1)",
                        params![artifact.artifact_id],
                        |row| row.get::<_, i64>(0),
                    )
                    .map_err(|_| {
                        DataStoreOpenError::new("the Agent Data import could not be completed")
                    })?;
                if existed == 1 {
                    duplicates += 1;
                } else {
                    insert_artifact(&mut connection, &file.path, &artifact, &records)?;
                    imported += 1;
                }
                supersessions += record_source_observation(
                    &mut connection,
                    &artifact.artifact_id,
                    &file.relative_path,
                )?;
            }
            Ok(None) => ignored += 1,
            Err(()) => invalid += 1,
        }
    }
    let finished_at = Utc::now().to_rfc3339();
    connection
        .execute(
            "UPDATE imports SET finished_at = ?1, imported_count = ?2, duplicate_count = ?3, \
             ignored_count = ?4, invalid_count = ?5 WHERE import_id = ?6",
            params![
                finished_at,
                sqlite_count(imported),
                sqlite_count(duplicates),
                sqlite_count(ignored),
                sqlite_count(invalid),
                import_id
            ],
        )
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))?;
    let (artifact_count, record_count): (i64, i64) = connection
        .query_row(
            "SELECT (SELECT COUNT(*) FROM artifacts), (SELECT COUNT(*) FROM records)",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))?;
    let revision = read_content_revision(&connection)
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))?;
    Ok(json!({
        "schema": "healthmd.agent_data_import",
        "schema_version": 1,
        "status": "success",
        "database_schema_version": DATABASE_SCHEMA_VERSION,
        "scanned_file_count": files.len(),
        "imported_artifact_count": imported,
        "duplicate_artifact_count": duplicates,
        "ignored_file_count": ignored,
        "invalid_file_count": invalid,
        "supersession_observation_count": supersessions,
        "artifact_count": artifact_count,
        "record_count": record_count,
        "index_revision": revision,
        "non_destructive": true
    }))
}

#[allow(clippy::needless_pass_by_ref_mut)]
fn insert_artifact(
    connection: &mut Connection,
    source_path: &Path,
    artifact: &ArtifactEntry,
    records: &[RecordEntry],
) -> Result<(), DataStoreOpenError> {
    let bytes = std::fs::read(source_path).map_err(|_| {
        DataStoreOpenError::new("the export artifact changed during the Agent Data import")
    })?;
    if bytes.len() as u64 != artifact.byte_count || sha256_hex(&bytes) != artifact.artifact_id {
        return Err(DataStoreOpenError::new(
            "the export artifact changed during the Agent Data import",
        ));
    }
    let transaction = connection
        .transaction()
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))?;
    insert_parsed_artifact(&transaction, &bytes, artifact, records)?;
    transaction
        .commit()
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))
}

/// Insert verified artifact bytes and their indexing metadata inside an open transaction.
///
/// Shared by directory import and single-upload ingestion so both promotion paths write
/// byte-identical rows. Never deletes or rewrites stored payloads; advances the store
/// content revision exactly once per new artifact.
pub(super) fn insert_parsed_artifact(
    transaction: &rusqlite::Transaction<'_>,
    bytes: &[u8],
    artifact: &ArtifactEntry,
    records: &[RecordEntry],
) -> Result<(), DataStoreOpenError> {
    let imported_at = Utc::now().to_rfc3339();
    let failure = || DataStoreOpenError::new("the Agent Data import could not be completed");
    transaction
        .execute(
            "INSERT INTO artifacts \
             (artifact_id, byte_count, media_type, physical_format, capture_status, \
              record_count, payload, first_imported_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                artifact.artifact_id,
                i64::try_from(artifact.byte_count).unwrap_or(i64::MAX),
                artifact.media_type,
                physical_format_text(artifact.physical_format),
                artifact.capture_status,
                sqlite_count(records.len()),
                bytes,
                imported_at
            ],
        )
        .map_err(|_| failure())?;
    for (position, schema) in artifact.schemas.iter().enumerate() {
        transaction
            .execute(
                "INSERT INTO artifact_schemas (artifact_id, position, schema, schema_version) \
                 VALUES (?1, ?2, ?3, ?4)",
                params![
                    artifact.artifact_id,
                    sqlite_count(position),
                    schema.schema,
                    schema
                        .schema_version
                        .map(|version| i64::try_from(version).unwrap_or(i64::MAX))
                ],
            )
            .map_err(|_| failure())?;
    }
    for detail_level in &artifact.detail_levels {
        transaction
            .execute(
                "INSERT INTO artifact_detail_levels (artifact_id, detail_level) VALUES (?1, ?2)",
                params![artifact.artifact_id, detail_level_text(*detail_level)],
            )
            .map_err(|_| failure())?;
    }
    for record in records {
        let (locator_type, locator_value) = locator_columns(&record.locator);
        transaction
            .execute(
                "INSERT INTO records (record_id, artifact_id, locator_type, locator_value, \
                 metric_ids, source_id, source_schema, source_schema_version, detail_level, \
                 owner_date, start_time, end_time, capture_status) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
                params![
                    record.record_id,
                    record.artifact_id,
                    locator_type,
                    locator_value,
                    serde_json::to_string(&record.metric_ids).map_err(|_| failure())?,
                    record.source_id,
                    record.source_schema,
                    record
                        .source_schema_version
                        .map(|version| i64::try_from(version).unwrap_or(i64::MAX)),
                    detail_level_text(record.detail_level),
                    record
                        .owner_date
                        .map(|date| date.format("%Y-%m-%d").to_string()),
                    record.start_time.map(|time| time.to_rfc3339()),
                    record.end_time.map(|time| time.to_rfc3339()),
                    record.capture_status
                ],
            )
            .map_err(|_| failure())?;
    }
    advance_content_revision(transaction, &artifact.artifact_id)?;
    Ok(())
}

/// Record that `relative_path` now resolves to `artifact_id`, appending supersession
/// bookkeeping when a different artifact previously occupied that path. Never deletes.
#[allow(clippy::needless_pass_by_ref_mut)]
fn record_source_observation(
    connection: &mut Connection,
    artifact_id: &str,
    relative_path: &str,
) -> Result<usize, DataStoreOpenError> {
    let transaction = connection
        .transaction()
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))?;
    let failure = || DataStoreOpenError::new("the Agent Data import could not be completed");
    let previous: Vec<String> = {
        let mut statement = transaction
            .prepare("SELECT DISTINCT artifact_id FROM artifact_sources WHERE relative_path = ?1")
            .map_err(|_| failure())?;

        statement
            .query_map(params![relative_path], |row| row.get::<_, String>(0))
            .map_err(|_| failure())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| failure())?
    };
    let observed_at = Utc::now().to_rfc3339();
    for previous_artifact in previous.iter().filter(|value| *value != artifact_id) {
        transaction
            .execute(
                "INSERT OR IGNORE INTO supersessions \
                 (relative_path, superseded_artifact_id, superseding_artifact_id, observed_at) \
                 VALUES (?1, ?2, ?3, ?4)",
                params![relative_path, previous_artifact, artifact_id, observed_at],
            )
            .map_err(|_| failure())?;
    }
    transaction
        .execute(
            "INSERT INTO artifact_sources (artifact_id, relative_path, first_seen_at, last_seen_at) \
             VALUES (?1, ?2, ?3, ?3) \
             ON CONFLICT(artifact_id, relative_path) DO UPDATE SET last_seen_at = excluded.last_seen_at",
            params![artifact_id, relative_path, observed_at],
        )
        .map_err(|_| failure())?;
    let supersessions = previous
        .iter()
        .filter(|value| *value != artifact_id)
        .count();
    transaction
        .commit()
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))?;
    Ok(supersessions)
}

fn advance_content_revision(
    connection: &Connection,
    artifact_id: &str,
) -> Result<(), DataStoreOpenError> {
    let previous = read_content_revision(connection)?;
    let mut hasher = Sha256::new();
    hasher.update(b"healthmd.agent-data.sqlite.revision.v1\n");
    hasher.update(previous.as_bytes());
    hasher.update(b"\n");
    hasher.update(artifact_id.as_bytes());
    let revision = hex(hasher.finalize());
    connection
        .execute(
            "UPDATE store_meta SET value = ?1 WHERE key = 'content_revision'",
            params![revision],
        )
        .map_err(|_| DataStoreOpenError::new("the Agent Data import could not be completed"))?;
    Ok(())
}

fn read_content_revision(connection: &Connection) -> Result<String, DataStoreOpenError> {
    connection
        .query_row(
            "SELECT value FROM store_meta WHERE key = 'content_revision'",
            [],
            |row| row.get::<_, String>(0),
        )
        .map_err(|_| DataStoreOpenError::new("the Agent Data store metadata is invalid"))
}

fn hex(bytes: impl AsRef<[u8]>) -> String {
    let bytes = bytes.as_ref();
    let mut value = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        let _ = write!(value, "{byte:02x}");
    }
    value
}

pub(super) fn migrate(connection: &mut Connection) -> Result<(), DataStoreOpenError> {
    let application_id = connection
        .query_row("PRAGMA application_id", [], |row| row.get::<_, i64>(0))
        .map_err(|_| DataStoreOpenError::new("the file is not a usable SQLite database"))?;
    let user_version = connection
        .query_row("PRAGMA user_version", [], |row| row.get::<_, i64>(0))
        .map_err(|_| DataStoreOpenError::new("the file is not a usable SQLite database"))?;
    if application_id != 0 && application_id != i64::from(DATABASE_APPLICATION_ID) {
        return Err(DataStoreOpenError::new(
            "the file is not a Health.md Agent Data database",
        ));
    }
    if user_version > i64::from(DATABASE_SCHEMA_VERSION) {
        return Err(DataStoreOpenError::new(
            "the Agent Data database was created by a newer Health.md version",
        ));
    }
    if application_id == i64::from(DATABASE_APPLICATION_ID)
        && user_version == i64::from(DATABASE_SCHEMA_VERSION)
    {
        return Ok(());
    }
    let transaction = connection
        .transaction()
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be initialized"))?;
    transaction
        .execute_batch(SCHEMA_V1)
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be initialized"))?;
    transaction
        .execute_batch(SCHEMA_V2)
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be initialized"))?;
    if store_meta(&transaction, "store_id").is_err() {
        transaction
            .execute(
                "INSERT INTO store_meta (key, value) VALUES ('store_id', ?1)",
                params![Uuid::new_v4().simple().to_string()],
            )
            .map_err(|_| {
                DataStoreOpenError::new("the Agent Data database could not be initialized")
            })?;
    }
    if read_content_revision(&transaction).is_err() {
        let store_id = store_meta(&transaction, "store_id").map_err(|_| {
            DataStoreOpenError::new("the Agent Data database could not be initialized")
        })?;
        let mut hasher = Sha256::new();
        hasher.update(b"healthmd.agent-data.sqlite.revision.v1\n");
        hasher.update(store_id.as_bytes());
        transaction
            .execute(
                "INSERT INTO store_meta (key, value) VALUES ('content_revision', ?1)",
                params![hex(hasher.finalize())],
            )
            .map_err(|_| {
                DataStoreOpenError::new("the Agent Data database could not be initialized")
            })?;
    }
    transaction
        .execute_batch(
            "PRAGMA application_id = 0x484D4441; \
             PRAGMA user_version = 2;",
        )
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be initialized"))?;
    transaction
        .commit()
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be initialized"))
}

fn store_meta(connection: &Connection, key: &str) -> Result<String, rusqlite::Error> {
    connection.query_row(
        "SELECT value FROM store_meta WHERE key = ?1",
        params![key],
        |row| row.get::<_, String>(0),
    )
}

const SCHEMA_V1: &str = "CREATE TABLE IF NOT EXISTS store_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS artifacts (
    artifact_id TEXT PRIMARY KEY,
    byte_count INTEGER NOT NULL,
    media_type TEXT NOT NULL,
    physical_format TEXT NOT NULL CHECK (physical_format IN ('json', 'ndjson')),
    capture_status TEXT NOT NULL,
    record_count INTEGER NOT NULL,
    payload BLOB NOT NULL,
    first_imported_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS artifact_schemas (
    artifact_id TEXT NOT NULL REFERENCES artifacts(artifact_id),
    position INTEGER NOT NULL,
    schema TEXT NOT NULL,
    schema_version INTEGER,
    PRIMARY KEY (artifact_id, position)
);
CREATE TABLE IF NOT EXISTS artifact_detail_levels (
    artifact_id TEXT NOT NULL REFERENCES artifacts(artifact_id),
    detail_level TEXT NOT NULL CHECK (detail_level IN ('common', 'lossless')),
    PRIMARY KEY (artifact_id, detail_level)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS records (
    record_id TEXT PRIMARY KEY,
    artifact_id TEXT NOT NULL REFERENCES artifacts(artifact_id),
    locator_type TEXT NOT NULL CHECK (locator_type IN ('json_pointer', 'ndjson_line')),
    locator_value TEXT NOT NULL,
    metric_ids TEXT NOT NULL,
    source_id TEXT NOT NULL,
    source_schema TEXT NOT NULL,
    source_schema_version INTEGER,
    detail_level TEXT NOT NULL CHECK (detail_level IN ('common', 'lossless')),
    owner_date TEXT,
    start_time TEXT,
    end_time TEXT,
    capture_status TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS records_artifact ON records(artifact_id);
CREATE INDEX IF NOT EXISTS records_detail ON records(detail_level);
CREATE TABLE IF NOT EXISTS artifact_sources (
    artifact_id TEXT NOT NULL REFERENCES artifacts(artifact_id),
    relative_path TEXT NOT NULL,
    first_seen_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    PRIMARY KEY (artifact_id, relative_path)
);
CREATE TABLE IF NOT EXISTS supersessions (
    relative_path TEXT NOT NULL,
    superseded_artifact_id TEXT NOT NULL,
    superseding_artifact_id TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    PRIMARY KEY (relative_path, superseded_artifact_id, superseding_artifact_id)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS imports (
    import_id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    source_directory TEXT NOT NULL,
    scanned_file_count INTEGER NOT NULL,
    imported_count INTEGER NOT NULL DEFAULT 0,
    duplicate_count INTEGER NOT NULL DEFAULT 0,
    ignored_count INTEGER NOT NULL DEFAULT 0,
    invalid_count INTEGER NOT NULL DEFAULT 0
);";

/// Additive schema version 2: owner-date partition bookkeeping for ingestion protocol v1.
/// Applied on top of [`SCHEMA_V1`] without touching any version-1 table or row.
const SCHEMA_V2: &str = "CREATE TABLE IF NOT EXISTS ingested_partitions (
    ingest_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    revision_id TEXT NOT NULL UNIQUE REFERENCES artifacts(artifact_id),
    owner_date TEXT NOT NULL,
    completeness TEXT NOT NULL CHECK (completeness IN ('complete', 'partial')),
    covered_owner_dates TEXT,
    byte_count INTEGER NOT NULL,
    accepted_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ingested_partitions_partition ON ingested_partitions(owner_date);";

fn open_read_only(path: &Path) -> Result<Connection, DataStoreOpenError> {
    let connection = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be opened"))?;
    connection
        .busy_timeout(std::time::Duration::from_millis(DATABASE_BUSY_TIMEOUT_MS))
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be opened"))?;
    Ok(connection)
}

pub(super) fn open_read_write(path: &Path) -> Result<Connection, DataStoreOpenError> {
    let connection = Connection::open(path)
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be created"))?;
    connection
        .busy_timeout(std::time::Duration::from_millis(DATABASE_BUSY_TIMEOUT_MS))
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be created"))?;
    Ok(connection)
}

fn verify_schema(connection: &Connection) -> Result<(), DataStoreOpenError> {
    let application_id = connection
        .query_row("PRAGMA application_id", [], |row| row.get::<_, i64>(0))
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be read"))?;
    let user_version = connection
        .query_row("PRAGMA user_version", [], |row| row.get::<_, i64>(0))
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be read"))?;
    if application_id != i64::from(DATABASE_APPLICATION_ID) || user_version == 0 {
        return Err(DataStoreOpenError::new(
            "the file is not an imported Health.md Agent Data database",
        ));
    }
    if user_version > i64::from(DATABASE_SCHEMA_VERSION) {
        return Err(DataStoreOpenError::new(
            "the Agent Data database was created by a newer Health.md version",
        ));
    }
    Ok(())
}

fn validated_database_path(path: &Path) -> Result<PathBuf, DataStoreOpenError> {
    if !path.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data database path must be absolute",
        ));
    }
    let metadata = std::fs::symlink_metadata(path).map_err(|_| {
        DataStoreOpenError::new(
            "the Agent Data database does not exist; run `healthmd data import`",
        )
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(DataStoreOpenError::new(
            "the Agent Data database must be an existing non-symlink file",
        ));
    }
    path.canonicalize()
        .map_err(|_| DataStoreOpenError::new("the Agent Data database could not be resolved"))
}

fn validated_import_database_path(
    database: &Path,
    directory: &Path,
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
    if let Ok(root) = directory.canonicalize() {
        if resolved.starts_with(root) {
            return Err(DataStoreOpenError::new(
                "the Agent Data database must be stored outside the import directory",
            ));
        }
    }
    Ok(resolved)
}

fn validated_grant_path(grant: &Path, database: &Path) -> Result<PathBuf, DataStoreOpenError> {
    let grant_path = data_backend::validated_regular_file(grant, MAXIMUM_GRANT_BYTES)?;
    if grant_path == database {
        return Err(DataStoreOpenError::new(
            "the Agent Data grant must be stored outside the Agent Data database",
        ));
    }
    Ok(grant_path)
}

fn physical_format_text(format: PhysicalFormat) -> &'static str {
    match format {
        PhysicalFormat::Json => "json",
        PhysicalFormat::Ndjson => "ndjson",
    }
}

fn physical_format_from_text(text: &str) -> Option<PhysicalFormat> {
    match text {
        "json" => Some(PhysicalFormat::Json),
        "ndjson" => Some(PhysicalFormat::Ndjson),
        _ => None,
    }
}

fn detail_level_text(level: AgentDataDetailLevel) -> &'static str {
    match level {
        AgentDataDetailLevel::Common => "common",
        AgentDataDetailLevel::Lossless => "lossless",
    }
}

fn detail_level_from_text(text: &str) -> Option<AgentDataDetailLevel> {
    match text {
        "common" => Some(AgentDataDetailLevel::Common),
        "lossless" => Some(AgentDataDetailLevel::Lossless),
        _ => None,
    }
}

fn locator_columns(locator: &RecordLocator) -> (&'static str, String) {
    match locator {
        RecordLocator::JsonPointer { pointer } => ("json_pointer", pointer.clone()),
        RecordLocator::NdjsonLine { line } => ("ndjson_line", line.to_string()),
    }
}

#[allow(clippy::too_many_lines)]
fn load_index(connection: &Connection) -> Result<ArtifactIndex, DataStoreOpenError> {
    let failure = || DataStoreOpenError::new("the Agent Data index could not be loaded");
    let content_revision = read_content_revision(connection)?;
    let mut artifacts = {
        let mut statement = connection
            .prepare(
                "SELECT artifact_id, byte_count, media_type, physical_format, capture_status, \
                 record_count FROM artifacts ORDER BY artifact_id",
            )
            .map_err(|_| failure())?;

        statement
            .query_map([], |row| {
                Ok(ArtifactEntry {
                    artifact_id: row.get(0)?,
                    relative_path: String::new(),
                    byte_count: u64::try_from(row.get::<_, i64>(1)?).unwrap_or(0),
                    media_type: row.get(2)?,
                    physical_format: physical_format_from_text(&row.get::<_, String>(3)?)
                        .unwrap_or(PhysicalFormat::Json),
                    schemas: Vec::new(),
                    capture_status: row.get(4)?,
                    detail_levels: Vec::new(),
                    record_count: usize::try_from(row.get::<_, i64>(5)?).unwrap_or(0),
                })
            })
            .map_err(|_| failure())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| failure())?
    };
    let mut schemas: BTreeMap<String, Vec<ArtifactSchema>> = BTreeMap::new();
    {
        let mut statement = connection
            .prepare(
                "SELECT artifact_id, schema, schema_version FROM artifact_schemas \
                 ORDER BY artifact_id, position",
            )
            .map_err(|_| failure())?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    ArtifactSchema {
                        schema: row.get(1)?,
                        schema_version: row
                            .get::<_, Option<i64>>(2)?
                            .and_then(|value| u64::try_from(value).ok()),
                    },
                ))
            })
            .map_err(|_| failure())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| failure())?;
        for (artifact_id, schema) in rows {
            schemas.entry(artifact_id).or_default().push(schema);
        }
    }
    let mut detail_levels: BTreeMap<String, BTreeSet<AgentDataDetailLevel>> = BTreeMap::new();
    {
        let mut statement = connection
            .prepare("SELECT artifact_id, detail_level FROM artifact_detail_levels")
            .map_err(|_| failure())?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    detail_level_from_text(&row.get::<_, String>(1)?),
                ))
            })
            .map_err(|_| failure())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| failure())?;
        for (artifact_id, detail_level) in rows {
            if let Some(detail_level) = detail_level {
                detail_levels
                    .entry(artifact_id)
                    .or_default()
                    .insert(detail_level);
            }
        }
    }
    for artifact in &mut artifacts {
        if let Some(values) = schemas.remove(&artifact.artifact_id) {
            artifact.schemas = values;
        }
        if let Some(values) = detail_levels.remove(&artifact.artifact_id) {
            artifact.detail_levels = values.into_iter().collect();
        }
    }
    let mut records = {
        let mut statement = connection
            .prepare(
                "SELECT record_id, artifact_id, locator_type, locator_value, metric_ids, \
                 source_id, source_schema, source_schema_version, detail_level, owner_date, \
                 start_time, end_time, capture_status FROM records",
            )
            .map_err(|_| failure())?;

        statement
            .query_map([], |row| {
                Ok::<RecordEntry, rusqlite::Error>(RecordEntry {
                    record_id: row.get(0)?,
                    artifact_id: row.get(1)?,
                    locator: match row.get::<_, String>(2)?.as_str() {
                        "json_pointer" => RecordLocator::JsonPointer {
                            pointer: row.get(3)?,
                        },
                        _ => RecordLocator::NdjsonLine {
                            line: row.get::<_, String>(3)?.parse().unwrap_or(0),
                        },
                    },
                    metric_ids: serde_json::from_str(&row.get::<_, String>(4)?).unwrap_or_default(),
                    source_id: row.get(5)?,
                    source_schema: row.get(6)?,
                    source_schema_version: row
                        .get::<_, Option<i64>>(7)?
                        .and_then(|value| u64::try_from(value).ok()),
                    detail_level: detail_level_from_text(&row.get::<_, String>(8)?)
                        .unwrap_or(AgentDataDetailLevel::Common),
                    owner_date: row
                        .get::<_, Option<String>>(9)?
                        .and_then(|value| NaiveDate::parse_from_str(&value, "%Y-%m-%d").ok()),
                    start_time: row
                        .get::<_, Option<String>>(10)?
                        .and_then(|value| DateTime::parse_from_rfc3339(&value).ok())
                        .map(|value| value.with_timezone(&Utc)),
                    end_time: row
                        .get::<_, Option<String>>(11)?
                        .and_then(|value| DateTime::parse_from_rfc3339(&value).ok())
                        .map(|value| value.with_timezone(&Utc)),
                    capture_status: row.get(12)?,
                })
            })
            .map_err(|_| failure())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| failure())?
    };
    records.sort_by(record_order);
    let (ignored, invalid): (u64, u64) = connection
        .query_row(
            "SELECT COALESCE(SUM(ignored_count), 0), COALESCE(SUM(invalid_count), 0) FROM imports",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|_| failure())?;
    Ok(ArtifactIndex {
        schema: INDEX_SCHEMA.to_owned(),
        schema_version: INDEX_SCHEMA_VERSION,
        source_fingerprint: content_revision.clone(),
        index_revision: content_revision,
        artifacts,
        records,
        ignored_file_count: usize::try_from(ignored).unwrap_or(usize::MAX),
        invalid_artifact_count: usize::try_from(invalid).unwrap_or(usize::MAX),
    })
}

fn read_verified_payload(
    connection: &Connection,
    artifact: &ArtifactEntry,
) -> Result<Vec<u8>, BackendError> {
    let row = connection
        .query_row(
            "SELECT payload, byte_count FROM artifacts WHERE artifact_id = ?1",
            params![artifact.artifact_id],
            |row| {
                Ok((
                    row.get::<_, Vec<u8>>(0)?,
                    u64::try_from(row.get::<_, i64>(1)?).unwrap_or(0),
                ))
            },
        )
        .map_err(|_| backend_failure("healthmd_agent_index_invalid"))?;
    let (bytes, byte_count) = row;
    if byte_count != artifact.byte_count || bytes.len() as u64 != artifact.byte_count {
        return Err(store_corrupt());
    }
    if sha256_hex(&bytes) != artifact.artifact_id {
        return Err(store_corrupt());
    }
    Ok(bytes)
}

impl fmt::Debug for SqliteArtifactStore {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SqliteArtifactStore")
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use std::{fs, io::Write as _, sync::Arc};

    use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
    use healthmd_operations::{
        AGENT_DATA_GRANT_SCHEMA, AGENT_DATA_QUERY_SCHEMA, AGENT_DATA_SCHEMA_VERSION, ArtifactStore,
        CallerIdentity,
    };
    use serde_json::{Value, json};
    use tempfile::TempDir;
    use tokio_util::sync::CancellationToken;

    use super::*;

    const DAY_ONE: &str = r#"{
      "schema":"healthmd.health_data","schema_version":8,"date":"2026-03-15",
      "type":"health-data","raw_capture_status":"complete","unit_system":"metric","units":{},
      "activity":{"steps":12345},"heart":{"restingHeartRate":58},
      "healthkit_record_archive":{"schema":"healthmd.healthkit_records","schema_version":1,
        "capture_status":"complete","records":[{"record_kind":"quantity","start_date":"2026-03-15T12:00:00Z",
        "end_date":"2026-03-15T12:00:01Z","selected_metric_ids":["heart_rate_avg"],"payload":{"value":72}}],
        "external_records":[],"medication_inventory":[]}
    }"#;
    const DAY_TWO: &str = r#"{
      "schema":"healthmd.health_data","schema_version":8,"date":"2026-03-16",
      "type":"health-data","raw_capture_status":"complete","unit_system":"metric","units":{},
      "activity":{"steps":999}
    }"#;
    const BIG_NOTES: &str = "synthetic-notes-";

    fn write_file(path: &Path, contents: &str) {
        let mut file = fs::File::create(path).unwrap();
        file.write_all(contents.as_bytes()).unwrap();
        file.sync_all().unwrap();
    }

    fn exports_with_files(temporary: &TempDir, files: &[(&str, &str)]) -> PathBuf {
        let exports = temporary.path().join("exports");
        fs::create_dir(&exports).unwrap();
        for (name, contents) in files {
            write_file(&exports.join(name), contents);
        }
        exports
    }

    #[allow(clippy::needless_pass_by_value)]
    fn grant_file(temporary: &TempDir, value: Value) -> PathBuf {
        let path = temporary.path().join("grant.json");
        write_file(&path, &serde_json::to_string(&value).unwrap());
        path
    }

    #[allow(clippy::needless_pass_by_value)]
    fn grant(
        metrics: Value,
        sources: Value,
        dates: Value,
        times: Value,
        details: Value,
        bulk: bool,
    ) -> Value {
        json!({
            "schema": AGENT_DATA_GRANT_SCHEMA,
            "schema_version": AGENT_DATA_SCHEMA_VERSION,
            "metrics": metrics,
            "sources": sources,
            "dates": dates,
            "times": times,
            "detail_levels": details,
            "bulk_download": bulk
        })
    }

    fn all_available() -> Value {
        json!({"type": "all_available"})
    }

    #[allow(clippy::needless_pass_by_value)]
    fn query(operation: Value) -> AgentDataQueryRequest {
        query_paged(operation, 250, 262_144, None)
    }

    #[allow(clippy::needless_pass_by_value)]
    fn query_paged(
        operation: Value,
        max_items: usize,
        max_bytes: usize,
        cursor: Option<&str>,
    ) -> AgentDataQueryRequest {
        AgentDataQueryRequest::from_value(json!({
            "schema": AGENT_DATA_QUERY_SCHEMA,
            "schema_version": AGENT_DATA_SCHEMA_VERSION,
            "operation": operation,
            "page": {"max_items": max_items, "max_bytes": max_bytes, "cursor": cursor}
        }))
        .unwrap()
    }

    #[allow(clippy::needless_pass_by_value)]
    fn records_operation(
        metrics: Value,
        sources: Value,
        dates: Value,
        times: Value,
        detail: &str,
    ) -> Value {
        json!({
            "type": "records",
            "metrics": metrics,
            "sources": sources,
            "dates": dates,
            "times": times,
            "detail_level": detail
        })
    }

    fn import(temporary: &TempDir, exports: &Path) -> PathBuf {
        let database = temporary.path().join("agent-data.sqlite");
        import_data(&database, exports).unwrap();
        database
    }

    fn open_store(temporary: &TempDir, database: &Path, grant_value: Value) -> SqliteArtifactStore {
        let grant_path = grant_file(temporary, grant_value);
        SqliteArtifactStore::open(DataServeOptions::Database {
            database: database.to_path_buf(),
            grant: grant_path,
        })
        .unwrap()
    }

    fn context() -> CallContext {
        CallContext {
            caller: CallerIdentity::local_read_only(),
            cancellation: CancellationToken::new(),
            session_id: None,
            progress: None,
        }
    }

    fn two_day_store(grant_value: Value) -> (TempDir, PathBuf, SqliteArtifactStore) {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(
            &temporary,
            &[("day1.json", DAY_ONE), ("day2.json", DAY_TWO)],
        );
        let database = import(&temporary, &exports);
        let store = open_store(&temporary, &database, grant_value);
        (temporary, database, store)
    }

    #[tokio::test]
    #[allow(clippy::too_many_lines)]
    async fn catalog_and_records_enforce_every_grant_gate() {
        let (_temporary, _database, store) = two_day_store(grant(
            json!({"type": "explicit", "metric_ids": [
                "healthmd.health_data#/activity/steps",
                "healthmd.healthkit_records#metric:heart_rate_avg"
            ]}),
            all_available(),
            all_available(),
            all_available(),
            json!(["common", "lossless"]),
            false,
        ));
        let catalog = store
            .query_page(&context(), query(json!({"type": "catalog"})))
            .await
            .unwrap();
        assert_eq!(catalog["receipt"]["source_kind"], "database");
        assert_eq!(catalog["items"].as_array().unwrap().len(), 2);
        assert!(catalog["items"].as_array().unwrap().iter().all(|item| {
            item["metric_id"].as_str().is_some_and(|metric| {
                metric == "healthmd.health_data#/activity/steps"
                    || metric == "healthmd.healthkit_records#metric:heart_rate_avg"
            })
        }));

        let records = store
            .query_page(
                &context(),
                query(records_operation(
                    json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
                    all_available(),
                    all_available(),
                    all_available(),
                    "common",
                )),
            )
            .await
            .unwrap();
        assert_eq!(records["items"].as_array().unwrap().len(), 2);
        assert_eq!(records["items"][0]["value"], 12345);
        assert!(
            !serde_json::to_string(&records)
                .unwrap()
                .contains("restingHeartRate"),
            "an ungranted sibling metric must never leak"
        );

        let source_gated = store
            .query_page(
                &context(),
                query(records_operation(
                    json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
                    json!({"type": "explicit", "source_ids": ["nonexistent_source"]}),
                    all_available(),
                    all_available(),
                    "common",
                )),
            )
            .await
            .unwrap();
        assert!(source_gated["items"].as_array().unwrap().is_empty());

        let date_gated = store
            .query_page(
                &context(),
                query(records_operation(
                    json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
                    all_available(),
                    json!({"type": "exact", "start_date": "2026-03-15", "end_date": "2026-03-15"}),
                    all_available(),
                    "common",
                )),
            )
            .await
            .unwrap();
        assert_eq!(date_gated["items"].as_array().unwrap().len(), 1);
        assert_eq!(date_gated["items"][0]["owner_date"], "2026-03-15");

        let time_gated = store
            .query_page(
                &context(),
                query(records_operation(
                    json!({"type": "explicit", "metric_ids": ["healthmd.healthkit_records#metric:heart_rate_avg"]}),
                    all_available(),
                    all_available(),
                    json!({"type": "exact", "start_inclusive": "2026-03-15T11:00:00Z", "end_exclusive": "2026-03-15T13:00:00Z"}),
                    "lossless",
                )),
            )
            .await
            .unwrap();
        assert_eq!(time_gated["items"].as_array().unwrap().len(), 1);
        assert_eq!(time_gated["items"][0]["detail_level"], "lossless");

        let instants_exclude_untimed_common_records = store
            .query_page(
                &context(),
                query(records_operation(
                    json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
                    all_available(),
                    all_available(),
                    json!({"type": "exact", "start_inclusive": "2026-03-15T11:00:00Z", "end_exclusive": "2026-03-15T13:00:00Z"}),
                    "common",
                )),
            )
            .await
            .unwrap();
        assert!(
            instants_exclude_untimed_common_records["items"]
                .as_array()
                .unwrap()
                .is_empty(),
            "a scoped instant grant excludes records without a parseable instant"
        );
    }

    #[tokio::test]
    async fn detail_level_gate_is_independent() {
        let (_temporary, _database, store) = two_day_store(grant(
            json!({"type": "all_available"}),
            all_available(),
            all_available(),
            all_available(),
            json!(["common"]),
            false,
        ));
        let lossless = store
            .query_page(
                &context(),
                query(records_operation(
                    all_available(),
                    all_available(),
                    all_available(),
                    all_available(),
                    "lossless",
                )),
            )
            .await
            .unwrap();
        assert!(lossless["items"].as_array().unwrap().is_empty());
    }

    #[tokio::test]
    async fn bulk_download_gate_guards_whole_artifacts() {
        let (temporary, database, restricted) = two_day_store(grant(
            json!({"type": "all_available"}),
            all_available(),
            all_available(),
            all_available(),
            json!(["common", "lossless"]),
            false,
        ));
        let artifacts = restricted
            .query_page(&context(), query(json!({"type": "artifacts"})))
            .await
            .unwrap();
        assert!(artifacts["items"].as_array().unwrap().is_empty());
        let denied = restricted
            .query_page(
                &context(),
                query(json!({"type": "artifact_read", "artifact_id": "0".repeat(64)})),
            )
            .await
            .unwrap_err();
        assert_eq!(denied.code, "healthmd_agent_bulk_download_denied");
        drop(restricted);

        let broad = open_store(
            &temporary,
            &database,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common", "lossless"]),
                true,
            ),
        );
        let artifacts = broad
            .query_page(&context(), query(json!({"type": "artifacts"})))
            .await
            .unwrap();
        assert_eq!(artifacts["items"].as_array().unwrap().len(), 2);
        let artifact_id = artifacts["items"][0]["artifact_id"]
            .as_str()
            .unwrap()
            .to_owned();
        let response = broad
            .query_page(
                &context(),
                query(json!({"type": "artifact_read", "artifact_id": artifact_id})),
            )
            .await
            .unwrap();
        assert_eq!(response["receipt"]["source_kind"], "database");
        let decoded = URL_SAFE_NO_PAD
            .decode(response["items"][0]["data"].as_str().unwrap())
            .unwrap();
        let expected =
            if response["items"][0]["byte_count"].as_u64().unwrap() == DAY_ONE.len() as u64 {
                DAY_ONE
            } else {
                DAY_TWO
            };
        assert_eq!(decoded, expected.as_bytes());
    }

    #[tokio::test]
    #[allow(clippy::too_many_lines)]
    async fn record_read_and_artifact_read_are_chunked_and_exact() {
        let temporary = TempDir::new().unwrap();
        let big = format!(
            "{}{}",
            BIG_NOTES.repeat(384),
            "-tail-marker-for-chunking-verification"
        );
        let day = DAY_ONE.replacen(
            "\"heart\":{\"restingHeartRate\":58}",
            &format!("\"heart\":{{\"note\":\"{big}\"}}"),
            1,
        );
        let exports = exports_with_files(&temporary, &[("day.json", &day)]);
        let database = import(&temporary, &exports);
        let store = open_store(
            &temporary,
            &database,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common", "lossless"]),
                true,
            ),
        );

        let records = store
            .query_page(
                &context(),
                query(records_operation(
                    json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/heart/note"]}),
                    all_available(),
                    all_available(),
                    all_available(),
                    "common",
                )),
            )
            .await
            .unwrap();
        let record_id = records["items"][0]["record_id"]
            .as_str()
            .unwrap()
            .to_owned();
        let mut cursor = None;
        let mut assembled = Vec::new();
        let mut chunks = 0;
        loop {
            let response = store
                .query_page(
                    &context(),
                    query_paged(
                        json!({"type": "record_read", "record_id": record_id}),
                        250,
                        4_096,
                        cursor.as_deref(),
                    ),
                )
                .await
                .unwrap();
            let item = &response["items"][0];
            assembled.extend_from_slice(
                &URL_SAFE_NO_PAD
                    .decode(item["data"].as_str().unwrap())
                    .unwrap(),
            );
            chunks += 1;
            if item["complete"].as_bool().unwrap() {
                break;
            }
            cursor = response["next_cursor"].as_str().map(str::to_owned);
        }
        assert!(chunks >= 2, "an oversized record must need multiple chunks");
        let value: Value = serde_json::from_slice(&assembled).unwrap();
        assert!(
            value
                .as_str()
                .unwrap()
                .ends_with("-tail-marker-for-chunking-verification")
        );

        let artifacts = store
            .query_page(&context(), query(json!({"type": "artifacts"})))
            .await
            .unwrap();
        let artifact_id = artifacts["items"][0]["artifact_id"]
            .as_str()
            .unwrap()
            .to_owned();
        let mut cursor = None;
        let mut assembled = Vec::new();
        let mut chunks = 0;
        loop {
            let response = store
                .query_page(
                    &context(),
                    query_paged(
                        json!({"type": "artifact_read", "artifact_id": artifact_id}),
                        250,
                        4_096,
                        cursor.as_deref(),
                    ),
                )
                .await
                .unwrap();
            let item = &response["items"][0];
            assembled.extend_from_slice(
                &URL_SAFE_NO_PAD
                    .decode(item["data"].as_str().unwrap())
                    .unwrap(),
            );
            chunks += 1;
            if item["complete"].as_bool().unwrap() {
                break;
            }
            cursor = response["next_cursor"].as_str().map(str::to_owned);
        }
        assert!(chunks >= 2, "the whole artifact must need multiple chunks");
        assert_eq!(assembled, day.as_bytes());
    }

    #[tokio::test]
    async fn cursors_are_query_and_revision_bound() {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(
            &temporary,
            &[("day1.json", DAY_ONE), ("day2.json", DAY_TWO)],
        );
        let database = import(&temporary, &exports);
        let store = open_store(
            &temporary,
            &database,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common"]),
                false,
            ),
        );
        let operation = records_operation(
            json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
            all_available(),
            all_available(),
            all_available(),
            "common",
        );
        let first = store
            .query_page(&context(), query_paged(operation.clone(), 1, 262_144, None))
            .await
            .unwrap();
        let cursor = first["next_cursor"].as_str().unwrap().to_owned();

        let second = store
            .query_page(
                &context(),
                query_paged(operation.clone(), 1, 262_144, Some(&cursor)),
            )
            .await
            .unwrap();
        assert_eq!(second["items"].as_array().unwrap().len(), 1);

        let different_query = records_operation(
            json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
            all_available(),
            json!({"type": "exact", "start_date": "2026-03-16", "end_date": "2026-03-16"}),
            all_available(),
            "common",
        );
        let stale = store
            .query_page(
                &context(),
                query_paged(different_query, 1, 262_144, Some(&cursor)),
            )
            .await
            .unwrap_err();
        assert_eq!(stale.code, "healthmd_agent_cursor_stale");

        let tampered = format!("{}.{}", &cursor[..cursor.len() - 2], "aa");
        let invalid = store
            .query_page(
                &context(),
                query_paged(operation.clone(), 1, 262_144, Some(&tampered)),
            )
            .await
            .unwrap_err();
        assert_eq!(invalid.code, "healthmd_agent_cursor_invalid");

        write_file(
            &exports.join("day1.json"),
            &DAY_ONE.replacen("12345", "54321", 1),
        );
        import_data(&database, &exports).unwrap();
        let after_reimport = store
            .query_page(
                &context(),
                query_paged(operation, 1, 262_144, Some(&cursor)),
            )
            .await
            .unwrap_err();
        assert_eq!(
            after_reimport.code, "healthmd_agent_cursor_stale",
            "a cursor from an older store revision must be rejected after re-import"
        );
    }

    #[tokio::test]
    async fn corrupted_payload_rows_never_return_and_doctor_reports_them() {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(&temporary, &[("day.json", DAY_ONE)]);
        let database = import(&temporary, &exports);
        let store = open_store(
            &temporary,
            &database,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common"]),
                false,
            ),
        );
        {
            let connection = Connection::open(&database).unwrap();
            connection
                .execute("UPDATE artifacts SET payload = X'DEADBEEF'", [])
                .unwrap();
        }
        let context = context();
        let failed = store
            .query_page(
                &context,
                query(records_operation(
                    json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
                    all_available(),
                    all_available(),
                    all_available(),
                    "common",
                )),
            )
            .await
            .unwrap_err();
        assert_eq!(failed.code, "healthmd_agent_store_corrupt");
        assert!(!failed.retryable);

        let doctor = store.doctor(&context).await.unwrap();
        assert_eq!(doctor["source_kind"], "database");
        assert_eq!(doctor["database"]["sha_mismatch_count"], 1);
        assert_eq!(doctor["database"]["checked_artifact_count"], 1);
        assert_eq!(
            doctor["database"]["schema_version"],
            i64::from(DATABASE_SCHEMA_VERSION)
        );
        assert_eq!(doctor["database"]["non_destructive"], true);
    }

    #[tokio::test]
    async fn reimport_is_idempotent_and_supersession_is_recorded_without_deletion() {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(&temporary, &[("day.json", DAY_ONE)]);
        let database = temporary.path().join("agent-data.sqlite");

        let first = import_data(&database, &exports).unwrap();
        assert_eq!(first["imported_artifact_count"], 1);
        assert_eq!(first["artifact_count"], 1);
        let revision_one = first["index_revision"].as_str().unwrap().to_owned();

        let second = import_data(&database, &exports).unwrap();
        assert_eq!(second["imported_artifact_count"], 0);
        assert_eq!(second["duplicate_artifact_count"], 1);
        assert_eq!(second["artifact_count"], 1);
        assert_eq!(
            second["index_revision"].as_str().unwrap(),
            revision_one.as_str(),
            "identical bytes must not change the store revision"
        );

        write_file(
            &exports.join("day.json"),
            &DAY_ONE.replacen("12345", "54321", 1),
        );
        let third = import_data(&database, &exports).unwrap();
        assert_eq!(third["imported_artifact_count"], 1);
        assert_eq!(third["supersession_observation_count"], 1);
        assert_eq!(third["artifact_count"], 2);
        assert_ne!(third["index_revision"].as_str().unwrap(), revision_one);

        let store = open_store(
            &temporary,
            &database,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common"]),
                false,
            ),
        );
        let context = context();
        let doctor = store.doctor(&context).await.unwrap();
        assert_eq!(
            doctor["database"]["superseded_artifact_observation_count"],
            1
        );
        assert_eq!(doctor["artifact_count"], 2);
        let catalog = store
            .query_page(&context, query(json!({"type": "catalog"})))
            .await
            .unwrap();
        let steps = catalog["items"]
            .as_array()
            .unwrap()
            .iter()
            .find(|item| item["metric_id"] == "healthmd.health_data#/activity/steps")
            .expect("the steps metric stays discoverable");
        assert_eq!(
            steps["record_count"], 2,
            "both the superseded and superseding artifact stay queryable; nothing was deleted"
        );
    }

    #[tokio::test]
    async fn ignored_and_invalid_imports_are_counted_without_failing() {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(
            &temporary,
            &[
                ("day.json", DAY_ONE),
                ("unrelated.json", "{\"hello\": \"world\"}"),
                (
                    "broken.json",
                    "{\"schema\":\"healthmd.api_export\",\"records\":[{}]}",
                ),
            ],
        );
        let database = temporary.path().join("agent-data.sqlite");
        let first = import_data(&database, &exports).unwrap();
        assert_eq!(first["ignored_file_count"], 1);
        assert_eq!(first["invalid_file_count"], 1);
        let second = import_data(&database, &exports).unwrap();
        assert_eq!(second["ignored_file_count"], 1);
        assert_eq!(second["invalid_file_count"], 1);

        let store = open_store(
            &temporary,
            &database,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common"]),
                false,
            ),
        );
        let doctor = store.doctor(&context()).await.unwrap();
        assert_eq!(doctor["ignored_file_count"], 2);
        assert_eq!(doctor["invalid_artifact_count"], 2);
    }

    #[tokio::test]
    async fn readiness_and_capabilities_are_honest_for_the_database_class() {
        let (_temporary, _database, store) = two_day_store(grant(
            json!({"type": "all_available"}),
            all_available(),
            all_available(),
            all_available(),
            json!(["common"]),
            false,
        ));
        let context = context();
        let readiness = store.readiness(&context).await.unwrap();
        assert_eq!(readiness["source_kind"], "database");
        assert_eq!(readiness["ready"], true);
        assert_eq!(readiness["artifact_count"], 2);
        assert!(
            readiness["index_revision"]
                .as_str()
                .is_some_and(|value| !value.is_empty())
        );
        let capabilities = store.capabilities();
        assert_eq!(capabilities.transport, "local_database");
        assert!(!capabilities.requires_foreground_source);
    }

    #[tokio::test]
    async fn unsupported_database_files_are_rejected_with_clear_errors() {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(&temporary, &[("day.json", DAY_ONE)]);

        let not_sqlite = temporary.path().join("not-a-database.sqlite");
        write_file(&not_sqlite, "this is not a database");
        let error = import_data(&not_sqlite, &exports).unwrap_err();
        assert_eq!(
            error.to_string(),
            "the file is not a usable SQLite database"
        );

        let grant_path = grant_file(
            &temporary,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common"]),
                false,
            ),
        );
        let serve_error = SqliteArtifactStore::open(DataServeOptions::Database {
            database: not_sqlite,
            grant: grant_path,
        })
        .unwrap_err();
        assert_eq!(
            serve_error.to_string(),
            "the Agent Data database could not be read"
        );

        let database = import(&temporary, &exports);
        {
            let connection = Connection::open(&database).unwrap();
            connection.execute("PRAGMA user_version = 99", []).unwrap();
        }
        let future = SqliteArtifactStore::open(DataServeOptions::Database {
            database,
            grant: grant_file(
                &temporary,
                grant(
                    json!({"type": "all_available"}),
                    all_available(),
                    all_available(),
                    all_available(),
                    json!(["common"]),
                    false,
                ),
            ),
        })
        .unwrap_err();
        assert_eq!(
            future.to_string(),
            "the Agent Data database was created by a newer Health.md version"
        );
    }

    #[tokio::test]
    async fn grant_must_live_outside_the_database_and_import_directory() {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(&temporary, &[("day.json", DAY_ONE)]);
        let database = import(&temporary, &exports);
        let store = SqliteArtifactStore::open(DataServeOptions::Database {
            database: database.clone(),
            grant: database.clone(),
        });
        assert!(store.is_err());

        let inside = exports.join("inside.sqlite");
        let error = import_data(&inside, &exports).unwrap_err();
        assert_eq!(
            error.to_string(),
            "the Agent Data database must be stored outside the import directory"
        );
    }

    #[test]
    fn schema_is_versioned_with_user_version_and_application_id() {
        let temporary = TempDir::new().unwrap();
        let exports = exports_with_files(&temporary, &[("day.json", DAY_ONE)]);
        let database = import(&temporary, &exports);
        let connection = Connection::open(&database).unwrap();
        let user_version: i64 = connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        let application_id: i64 = connection
            .query_row("PRAGMA application_id", [], |row| row.get(0))
            .unwrap();
        assert_eq!(user_version, i64::from(DATABASE_SCHEMA_VERSION));
        assert_eq!(application_id, i64::from(DATABASE_APPLICATION_ID));
        let tables: usize = connection
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .map(|value| usize::try_from(value).unwrap_or(0))
            .unwrap();
        assert_eq!(tables, 9);
        let partitions: i64 = connection
            .query_row("SELECT COUNT(*) FROM ingested_partitions", [], |row| row.get(0))
            .unwrap();
        assert_eq!(partitions, 0, "directory import must not create partition rows");
    }

    #[tokio::test]
    async fn shared_backend_adapter_accepts_the_database_contract() {
        use healthmd_operations::{ArtifactStoreBackend, HealthDataBackend, QueryDetailLevel};

        let (temporary, database, store) = two_day_store(grant(
            json!({"type": "all_available"}),
            all_available(),
            all_available(),
            all_available(),
            json!(["common"]),
            false,
        ));
        drop(store);
        let reopened = open_store(
            &temporary,
            &database,
            grant(
                json!({"type": "all_available"}),
                all_available(),
                all_available(),
                all_available(),
                json!(["common"]),
                false,
            ),
        );
        let backend = ArtifactStoreBackend::new(Arc::new(reopened));
        let context = CallContext {
            caller: CallerIdentity::local_read_only(),
            cancellation: CancellationToken::new(),
            session_id: None,
            progress: None,
        };
        let result = backend
            .query_page(
                &context,
                healthmd_operations::QueryPageRequest {
                    query: serde_json::to_value(query(json!({"type": "catalog"}))).unwrap(),
                    detail_level: QueryDetailLevel::Summary,
                },
            )
            .await
            .unwrap();
        assert_eq!(result["schema"], "healthmd.agent_query_response");
        assert_eq!(result["receipt"]["source_kind"], "database");
    }
}
