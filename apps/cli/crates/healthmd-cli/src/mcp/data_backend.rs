use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    fmt, fs,
    io::{BufRead as _, BufReader, Read as _, Write as _},
    path::{Path, PathBuf},
    sync::Arc,
    time::UNIX_EPOCH,
};

use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{DateTime, NaiveDate, Utc};
use directories::BaseDirs;
use healthmd_operations::{
    AGENT_QUERY_RESPONSE_SCHEMA, AgentDataDetailLevel, AgentDataGrant, AgentDataOperation,
    AgentDataQueryRequest, AgentDataRecordScope, ArtifactStore, BackendCapabilities, BackendError,
    CallContext,
};
use hmac::{Hmac, Mac as _};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use tempfile::NamedTempFile;
use tokio::sync::{Mutex, RwLock};

const INDEX_SCHEMA: &str = "healthmd.agent_data_index";
const INDEX_SCHEMA_VERSION: u16 = 1;
const MAXIMUM_GRANT_BYTES: u64 = 1_048_576;
const MAXIMUM_JSON_ARTIFACT_BYTES: u64 = 64 * 1_048_576;
const MAXIMUM_NDJSON_LINE_BYTES: usize = 2 * 1_048_576;
const MAXIMUM_SOURCE_FILES: usize = 10_000;
const MAXIMUM_DIRECTORY_DEPTH: usize = 32;
const CURSOR_VERSION: u16 = 1;
const CURSOR_RESPONSE_OVERHEAD_BYTES: usize = 2_048;
const DAILY_RESERVED_FIELDS: &[&str] = &[
    "schema",
    "schema_version",
    "date",
    "type",
    "units",
    "unit_system",
    "raw_capture_status",
    "time_context",
    "metadata",
    "schemaProfile",
    "schemaVersion",
    "healthkit_record_archive",
];

type HmacSha256 = Hmac<Sha256>;

#[derive(Clone, Debug)]
pub struct DataServeOptions {
    pub directory: PathBuf,
    pub grant: PathBuf,
    pub index: Option<PathBuf>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DataStoreOpenError {
    message: &'static str,
}

impl DataStoreOpenError {
    const fn new(message: &'static str) -> Self {
        Self { message }
    }
}

impl fmt::Display for DataStoreOpenError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message)
    }
}

impl std::error::Error for DataStoreOpenError {}

pub struct DirectoryArtifactStore {
    root: PathBuf,
    index_path: PathBuf,
    grant: Arc<AgentDataGrant>,
    cursor_key: [u8; 32],
    index: RwLock<Arc<DirectoryIndex>>,
    refresh: Mutex<()>,
}

impl DirectoryArtifactStore {
    /// Open an explicitly configured, read-only export directory and build its external index.
    ///
    /// # Errors
    ///
    /// Returns a path-free error when directory, grant, index, or artifact validation fails.
    pub fn open(options: DataServeOptions) -> Result<Self, DataStoreOpenError> {
        let root = validated_directory(&options.directory)?;
        let grant_path = validated_regular_file(&options.grant, MAXIMUM_GRANT_BYTES)?;
        if grant_path.starts_with(&root) {
            return Err(DataStoreOpenError::new(
                "the Agent Data grant must be stored outside the export directory",
            ));
        }
        let grant_bytes = fs::read(&grant_path)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant could not be read"))?;
        let grant_value = serde_json::from_slice(&grant_bytes)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant is not valid JSON"))?;
        let grant = AgentDataGrant::from_value(grant_value)
            .map_err(|_| DataStoreOpenError::new("the Agent Data grant is invalid"))?;

        let root_binding = sha256_hex(root.to_string_lossy().as_bytes());
        let index_path = match options.index {
            Some(path) => validated_index_path(&root, &path)?,
            None => default_index_path(&root_binding)?,
        };
        let source_files = scan_source_files(&root)?;
        let index = build_stable_index(&root, &source_files)?;
        persist_index(&index_path, &index)?;

        let mut cursor_key = [0_u8; 32];
        getrandom::fill(&mut cursor_key)
            .map_err(|_| DataStoreOpenError::new("secure cursor state could not be initialized"))?;

        Ok(Self {
            root,
            index_path,
            grant: Arc::new(grant),
            cursor_key,
            index: RwLock::new(Arc::new(index)),
            refresh: Mutex::new(()),
        })
    }

    async fn current_index(&self) -> Result<Arc<DirectoryIndex>, BackendError> {
        self.refresh_if_needed().await?;
        let index = self.index.read().await;
        Ok(Arc::clone(&index))
    }

    async fn refresh_if_needed(&self) -> Result<(), BackendError> {
        let root = self.root.clone();
        let files = tokio::task::spawn_blocking(move || scan_source_files(&root))
            .await
            .map_err(|_| backend_failure("healthmd_agent_index_failed"))?
            .map_err(open_to_backend)?;
        let fingerprint = source_fingerprint(&files);
        if self.index.read().await.source_fingerprint == fingerprint {
            return Ok(());
        }

        let _refresh_guard = self.refresh.lock().await;
        if self.index.read().await.source_fingerprint == fingerprint {
            return Ok(());
        }
        let root = self.root.clone();
        let index_path = self.index_path.clone();
        let rebuilt = tokio::task::spawn_blocking(move || {
            let index = build_stable_index(&root, &files)?;
            persist_index(&index_path, &index)?;
            Ok::<_, DataStoreOpenError>(index)
        })
        .await
        .map_err(|_| backend_failure("healthmd_agent_index_failed"))?
        .map_err(open_to_backend)?;
        *self.index.write().await = Arc::new(rebuilt);
        Ok(())
    }
}

#[async_trait]
impl ArtifactStore for DirectoryArtifactStore {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            source_kind: "artifact_store".to_owned(),
            transport: "local_directory".to_owned(),
            supports_queries: true,
            supports_local_file_exports: false,
            requires_foreground_source: false,
            instructions: "Use the fixed Agent Data tools to read only records permitted by the configured grant. The source directory is never modified.".to_owned(),
        }
    }

    async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let index = self.current_index().await?;
        Ok(json!({
            "schema": "healthmd.agent_data_readiness",
            "schema_version": 1,
            "ready": true,
            "source_kind": "directory",
            "artifact_count": index.artifacts.len(),
            "record_count": index.records.len(),
            "index_revision": index.index_revision,
            "requires_foreground_source": false
        }))
    }

    async fn doctor(&self, _context: &CallContext) -> Result<Value, BackendError> {
        let index = self.current_index().await?;
        Ok(json!({
            "schema": "healthmd.agent_data_diagnostics",
            "schema_version": 1,
            "ready": true,
            "source_kind": "directory",
            "artifact_count": index.artifacts.len(),
            "record_count": index.records.len(),
            "ignored_file_count": index.ignored_file_count,
            "invalid_artifact_count": index.invalid_artifact_count,
            "index_revision": index.index_revision,
            "source_modified": false
        }))
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
        let index = self.current_index().await?;
        let root = self.root.clone();
        let grant = Arc::clone(&self.grant);
        let cursor_key = self.cursor_key;
        let result = tokio::task::spawn_blocking(move || {
            execute_query(&root, &index, &grant, &cursor_key, &request)
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

#[derive(Clone, Debug)]
struct SourceFile {
    path: PathBuf,
    relative_path: String,
    byte_count: u64,
    modified_nanos: u128,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct DirectoryIndex {
    schema: String,
    schema_version: u16,
    source_fingerprint: String,
    index_revision: String,
    artifacts: Vec<ArtifactEntry>,
    records: Vec<RecordEntry>,
    ignored_file_count: usize,
    invalid_artifact_count: usize,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ArtifactEntry {
    artifact_id: String,
    relative_path: String,
    byte_count: u64,
    media_type: String,
    physical_format: PhysicalFormat,
    schemas: Vec<ArtifactSchema>,
    capture_status: String,
    detail_levels: Vec<AgentDataDetailLevel>,
    record_count: usize,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum PhysicalFormat {
    Json,
    Ndjson,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct ArtifactSchema {
    schema: String,
    schema_version: Option<u64>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct RecordEntry {
    record_id: String,
    artifact_id: String,
    locator: RecordLocator,
    metric_ids: Vec<String>,
    source_id: String,
    source_schema: String,
    source_schema_version: Option<u64>,
    detail_level: AgentDataDetailLevel,
    owner_date: Option<NaiveDate>,
    start_time: Option<DateTime<Utc>>,
    end_time: Option<DateTime<Utc>>,
    capture_status: String,
}

impl RecordEntry {
    fn scope(&self) -> AgentDataRecordScope<'_> {
        AgentDataRecordScope {
            metric_ids: &self.metric_ids,
            source_id: &self.source_id,
            detail_level: self.detail_level,
            owner_date: self.owner_date,
            start_time: self.start_time,
            end_time: self.end_time,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
enum RecordLocator {
    JsonPointer { pointer: String },
    NdjsonLine { line: usize },
}

#[derive(Default)]
struct ParsedArtifact {
    schemas: Vec<ArtifactSchema>,
    capture_status: String,
    detail_levels: BTreeSet<AgentDataDetailLevel>,
    records: Vec<RecordEntry>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct CursorPayload {
    version: u16,
    index_revision: String,
    query_fingerprint: String,
    offset: usize,
}

fn validated_directory(path: &Path) -> Result<PathBuf, DataStoreOpenError> {
    if !path.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data directory must be an absolute path",
        ));
    }
    let metadata = fs::symlink_metadata(path).map_err(|_| {
        DataStoreOpenError::new("the Agent Data directory does not exist or is inaccessible")
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(DataStoreOpenError::new(
            "the Agent Data directory must be an existing non-symlink directory",
        ));
    }
    path.canonicalize()
        .map_err(|_| DataStoreOpenError::new("the Agent Data directory could not be resolved"))
}

fn validated_regular_file(path: &Path, maximum_bytes: u64) -> Result<PathBuf, DataStoreOpenError> {
    if !path.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data grant must be an absolute path",
        ));
    }
    let metadata = fs::symlink_metadata(path)
        .map_err(|_| DataStoreOpenError::new("the Agent Data grant does not exist"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() || metadata.len() > maximum_bytes {
        return Err(DataStoreOpenError::new(
            "the Agent Data grant must be a bounded non-symlink file",
        ));
    }
    path.canonicalize()
        .map_err(|_| DataStoreOpenError::new("the Agent Data grant could not be resolved"))
}

fn validated_index_path(root: &Path, path: &Path) -> Result<PathBuf, DataStoreOpenError> {
    if !path.is_absolute() {
        return Err(DataStoreOpenError::new(
            "the Agent Data index path must be absolute",
        ));
    }
    if fs::symlink_metadata(path)
        .is_ok_and(|metadata| metadata.file_type().is_symlink() || !metadata.is_file())
    {
        return Err(DataStoreOpenError::new(
            "the Agent Data index path must not be a symlink",
        ));
    }
    let parent = path.parent().ok_or_else(|| {
        DataStoreOpenError::new("the Agent Data index path has no parent directory")
    })?;
    prepare_private_directory(parent)?;
    let parent = parent
        .canonicalize()
        .map_err(|_| DataStoreOpenError::new("the Agent Data index directory is inaccessible"))?;
    let resolved = parent
        .join(path.file_name().ok_or_else(|| {
            DataStoreOpenError::new("the Agent Data index path has no file name")
        })?);
    if resolved.starts_with(root) {
        return Err(DataStoreOpenError::new(
            "the Agent Data index must be stored outside the export directory",
        ));
    }
    Ok(resolved)
}

fn default_index_path(root_binding: &str) -> Result<PathBuf, DataStoreOpenError> {
    let base = BaseDirs::new()
        .ok_or_else(|| DataStoreOpenError::new("no private data directory is available"))?;
    let directory = base
        .data_local_dir()
        .join("Health.md")
        .join("CLI")
        .join("AgentData")
        .join("v1")
        .join("indexes");
    prepare_private_directory(&directory)?;
    Ok(directory.join(format!("{root_binding}.json")))
}

fn prepare_private_directory(path: &Path) -> Result<(), DataStoreOpenError> {
    fs::create_dir_all(path).map_err(|_| {
        DataStoreOpenError::new("the private Agent Data directory could not be created")
    })?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(|_| {
            DataStoreOpenError::new("the private Agent Data directory could not be restricted")
        })?;
    }
    Ok(())
}

fn scan_source_files(root: &Path) -> Result<Vec<SourceFile>, DataStoreOpenError> {
    let mut pending = vec![(root.to_path_buf(), 0_usize)];
    let mut files = Vec::new();
    while let Some((directory, depth)) = pending.pop() {
        if depth > MAXIMUM_DIRECTORY_DEPTH {
            return Err(DataStoreOpenError::new(
                "the Agent Data directory exceeds the supported nesting depth",
            ));
        }
        let entries = fs::read_dir(&directory).map_err(|_| {
            DataStoreOpenError::new("the Agent Data directory could not be scanned")
        })?;
        for entry in entries {
            let entry = entry.map_err(|_| {
                DataStoreOpenError::new("the Agent Data directory could not be scanned")
            })?;
            let path = entry.path();
            let metadata = fs::symlink_metadata(&path).map_err(|_| {
                DataStoreOpenError::new("the Agent Data directory changed during indexing")
            })?;
            if metadata.file_type().is_symlink() {
                continue;
            }
            if metadata.is_dir() {
                pending.push((path, depth + 1));
                continue;
            }
            if !metadata.is_file() || !supported_extension(&path) {
                continue;
            }
            if files.len() >= MAXIMUM_SOURCE_FILES {
                return Err(DataStoreOpenError::new(
                    "the Agent Data directory contains too many candidate files",
                ));
            }
            let relative = path.strip_prefix(root).map_err(|_| {
                DataStoreOpenError::new("the Agent Data directory changed during indexing")
            })?;
            let relative_path = relative
                .components()
                .map(|component| component.as_os_str().to_string_lossy())
                .collect::<Vec<_>>()
                .join("/");
            if relative_path.len() > 4_096 {
                return Err(DataStoreOpenError::new(
                    "an Agent Data artifact path exceeds the supported bound",
                ));
            }
            let modified_nanos = metadata
                .modified()
                .ok()
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map_or(0, |value| value.as_nanos());
            files.push(SourceFile {
                path,
                relative_path,
                byte_count: metadata.len(),
                modified_nanos,
            });
        }
    }
    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(files)
}

fn supported_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| {
            matches!(
                value.to_ascii_lowercase().as_str(),
                "json" | "jsonl" | "ndjson"
            )
        })
}

fn source_fingerprint(files: &[SourceFile]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"healthmd.agent-data.directory-fingerprint.v1\n");
    for file in files {
        hasher.update(file.relative_path.len().to_be_bytes());
        hasher.update(file.relative_path.as_bytes());
        hasher.update(file.byte_count.to_be_bytes());
        hasher.update(file.modified_nanos.to_be_bytes());
    }
    hex_digest(hasher.finalize())
}

fn build_stable_index(
    root: &Path,
    files: &[SourceFile],
) -> Result<DirectoryIndex, DataStoreOpenError> {
    let expected_fingerprint = source_fingerprint(files);
    let mut artifacts = Vec::new();
    let mut records = Vec::new();
    let mut seen_artifacts = BTreeSet::new();
    let mut ignored_file_count = 0_usize;
    let mut invalid_artifact_count = 0_usize;

    for file in files {
        match parse_artifact(file) {
            Ok(Some((mut artifact, mut artifact_records))) => {
                if !seen_artifacts.insert(artifact.artifact_id.clone()) {
                    ignored_file_count += 1;
                    continue;
                }
                artifact.record_count = artifact_records.len();
                artifacts.push(artifact);
                records.append(&mut artifact_records);
            }
            Ok(None) => ignored_file_count += 1,
            Err(()) => invalid_artifact_count += 1,
        }
    }
    artifacts.sort_by(|left, right| left.artifact_id.cmp(&right.artifact_id));
    records.sort_by(record_order);

    let current_files = scan_source_files(root)?;
    if source_fingerprint(&current_files) != expected_fingerprint {
        return Err(DataStoreOpenError::new(
            "the Agent Data directory changed during indexing",
        ));
    }
    let revision_value = serde_json::to_vec(&(
        &expected_fingerprint,
        &artifacts,
        &records,
        ignored_file_count,
        invalid_artifact_count,
    ))
    .map_err(|_| DataStoreOpenError::new("the Agent Data index could not be encoded"))?;
    Ok(DirectoryIndex {
        schema: INDEX_SCHEMA.to_owned(),
        schema_version: INDEX_SCHEMA_VERSION,
        source_fingerprint: expected_fingerprint,
        index_revision: sha256_hex(&revision_value),
        artifacts,
        records,
        ignored_file_count,
        invalid_artifact_count,
    })
}

fn parse_artifact(file: &SourceFile) -> Result<Option<(ArtifactEntry, Vec<RecordEntry>)>, ()> {
    let physical_format = match file
        .path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("json") => PhysicalFormat::Json,
        Some("jsonl" | "ndjson") => PhysicalFormat::Ndjson,
        _ => return Ok(None),
    };
    let artifact_id = hash_file(&file.path).map_err(|_| ())?;
    let parsed = match physical_format {
        PhysicalFormat::Json => {
            if file.byte_count > MAXIMUM_JSON_ARTIFACT_BYTES {
                return Err(());
            }
            let bytes = fs::read(&file.path).map_err(|_| ())?;
            let value: Value = serde_json::from_slice(&bytes).map_err(|_| ())?;
            parse_json_artifact(&value, &artifact_id)?
        }
        PhysicalFormat::Ndjson => parse_ndjson_artifact(&file.path, &artifact_id)?,
    };
    let Some(mut parsed) = parsed else {
        return Ok(None);
    };
    for record in &mut parsed.records {
        record.metric_ids.sort();
        record.metric_ids.dedup();
        let locator = serde_json::to_vec(&record.locator).map_err(|_| ())?;
        let mut identity = Sha256::new();
        identity.update(b"healthmd.agent-data.record.v1\n");
        identity.update(artifact_id.as_bytes());
        identity.update(&locator);
        identity.update(serde_json::to_vec(&record.metric_ids).map_err(|_| ())?);
        record.record_id = hex_digest(identity.finalize());
    }
    let detail_levels = parsed.detail_levels.into_iter().collect();
    let media_type = match physical_format {
        PhysicalFormat::Json => "application/json",
        PhysicalFormat::Ndjson => "application/x-ndjson",
    };
    Ok(Some((
        ArtifactEntry {
            artifact_id,
            relative_path: file.relative_path.clone(),
            byte_count: file.byte_count,
            media_type: media_type.to_owned(),
            physical_format,
            schemas: parsed.schemas,
            capture_status: parsed.capture_status,
            detail_levels,
            record_count: 0,
        },
        parsed.records,
    )))
}

fn parse_json_artifact(value: &Value, artifact_id: &str) -> Result<Option<ParsedArtifact>, ()> {
    if value.get("schema").and_then(Value::as_str) == Some("healthmd.api_export") {
        return parse_api_export(value, artifact_id).map(Some);
    }
    if is_daily_record(value) {
        let mut parsed = ParsedArtifact::default();
        index_daily_record(value, "", artifact_id, &mut parsed)?;
        return Ok(Some(parsed));
    }
    if value.pointer("/header/schema").and_then(Value::as_str) == Some("healthmd.raw-snapshot") {
        return parse_raw_snapshot(value, artifact_id).map(Some);
    }
    if value.pointer("/header/schema").and_then(Value::as_str) == Some("healthmd.raw-changes") {
        return parse_raw_changes(value, artifact_id).map(Some);
    }
    match value.as_array() {
        Some(values) if values.iter().all(is_daily_record) => {
            let mut parsed = ParsedArtifact::default();
            for (index, daily) in values.iter().enumerate() {
                index_daily_record(daily, &format!("/{index}"), artifact_id, &mut parsed)?;
            }
            return Ok(Some(parsed));
        }
        _ => {}
    }
    Ok(None)
}

fn parse_api_export(value: &Value, artifact_id: &str) -> Result<ParsedArtifact, ()> {
    let mut parsed = ParsedArtifact {
        schemas: vec![schema_reference(value, "healthmd.api_export")],
        capture_status: if value
            .get("failed_date_details")
            .and_then(Value::as_array)
            .is_some_and(Vec::is_empty)
        {
            "complete".to_owned()
        } else {
            "partial".to_owned()
        },
        detail_levels: BTreeSet::from([AgentDataDetailLevel::Common]),
        records: Vec::new(),
    };
    let records = value.get("records").and_then(Value::as_array).ok_or(())?;
    for (index, daily) in records.iter().enumerate() {
        if !is_daily_record(daily) {
            return Err(());
        }
        index_daily_record(
            daily,
            &format!("/records/{index}"),
            artifact_id,
            &mut parsed,
        )?;
    }
    if let Some(external_records) = value.get("external_records").and_then(Value::as_array) {
        for (index, external) in external_records.iter().enumerate() {
            index_provider_record(
                external,
                &format!("/external_records/{index}"),
                artifact_id,
                &mut parsed,
            )?;
        }
    }
    Ok(parsed)
}

fn is_daily_record(value: &Value) -> bool {
    value.as_object().is_some()
        && value.get("date").and_then(Value::as_str).is_some()
        && (value.get("schema").and_then(Value::as_str) == Some("healthmd.health_data")
            || value.get("type").and_then(Value::as_str) == Some("health-data"))
}

fn index_daily_record(
    value: &Value,
    base_pointer: &str,
    artifact_id: &str,
    parsed: &mut ParsedArtifact,
) -> Result<(), ()> {
    let object = value.as_object().ok_or(())?;
    parsed.detail_levels.insert(AgentDataDetailLevel::Common);
    let owner_date = parse_date(value.get("date")).ok_or(())?;
    let schema = value
        .get("schema")
        .and_then(Value::as_str)
        .unwrap_or("healthmd.health_data");
    let version = value
        .get("schema_version")
        .or_else(|| value.get("schemaVersion"))
        .and_then(Value::as_u64);
    push_schema(&mut parsed.schemas, schema, version);
    let capture_status = value
        .get("raw_capture_status")
        .and_then(Value::as_str)
        .unwrap_or("legacy_unavailable")
        .to_owned();
    parsed.capture_status = merge_capture_status(&parsed.capture_status, &capture_status);

    for (key, child) in object {
        if DAILY_RESERVED_FIELDS.contains(&key.as_str()) {
            continue;
        }
        let pointer = format!("{base_pointer}/{}", escape_pointer(key));
        index_common_value(
            child,
            &pointer,
            artifact_id,
            schema,
            version,
            owner_date,
            &capture_status,
            &mut parsed.records,
        );
    }
    if let Some(archive) = value.get("healthkit_record_archive") {
        index_healthkit_archive(
            archive,
            &format!("{base_pointer}/healthkit_record_archive"),
            artifact_id,
            owner_date,
            &capture_status,
            parsed,
        )?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn index_common_value(
    value: &Value,
    pointer: &str,
    artifact_id: &str,
    schema: &str,
    schema_version: Option<u64>,
    owner_date: NaiveDate,
    capture_status: &str,
    records: &mut Vec<RecordEntry>,
) {
    match value {
        Value::Array(values) => {
            for (index, item) in values.iter().enumerate() {
                let item_pointer = format!("{pointer}/{index}");
                let (start_time, end_time) = record_times(item);
                records.push(new_record(
                    artifact_id,
                    RecordLocator::JsonPointer {
                        pointer: item_pointer,
                    },
                    vec![format!("{schema}#{pointer}")],
                    schema,
                    schema,
                    schema_version,
                    AgentDataDetailLevel::Common,
                    Some(owner_date),
                    start_time,
                    end_time,
                    capture_status,
                ));
            }
        }
        Value::Object(object) => {
            for (key, child) in object {
                index_common_value(
                    child,
                    &format!("{pointer}/{}", escape_pointer(key)),
                    artifact_id,
                    schema,
                    schema_version,
                    owner_date,
                    capture_status,
                    records,
                );
            }
        }
        Value::Null => {}
        _ => records.push(new_record(
            artifact_id,
            RecordLocator::JsonPointer {
                pointer: pointer.to_owned(),
            },
            vec![format!("{schema}#{pointer}")],
            schema,
            schema,
            schema_version,
            AgentDataDetailLevel::Common,
            Some(owner_date),
            None,
            None,
            capture_status,
        )),
    }
}

fn index_healthkit_archive(
    archive: &Value,
    base_pointer: &str,
    artifact_id: &str,
    owner_date: NaiveDate,
    fallback_capture_status: &str,
    parsed: &mut ParsedArtifact,
) -> Result<(), ()> {
    let schema = archive
        .get("schema")
        .and_then(Value::as_str)
        .filter(|value| *value == "healthmd.healthkit_records")
        .ok_or(())?;
    let version = archive.get("schema_version").and_then(Value::as_u64);
    push_schema(&mut parsed.schemas, schema, version);
    parsed.detail_levels.insert(AgentDataDetailLevel::Lossless);
    let capture_status = archive
        .get("capture_status")
        .and_then(Value::as_str)
        .unwrap_or(fallback_capture_status);
    for (collection, fallback) in [
        ("records", "record"),
        ("external_records", "external_record"),
        ("medication_inventory", "medications"),
    ] {
        let Some(values) = archive.get(collection).and_then(Value::as_array) else {
            continue;
        };
        for (index, value) in values.iter().enumerate() {
            let metric_ids = healthkit_metric_ids(value, fallback);
            let (start_time, end_time) = record_times(value);
            parsed.records.push(new_record(
                artifact_id,
                RecordLocator::JsonPointer {
                    pointer: format!("{base_pointer}/{collection}/{index}"),
                },
                metric_ids,
                schema,
                schema,
                version,
                AgentDataDetailLevel::Lossless,
                Some(owner_date),
                start_time,
                end_time,
                capture_status,
            ));
        }
    }
    Ok(())
}

fn healthkit_metric_ids(value: &Value, fallback: &str) -> Vec<String> {
    let mut values = Vec::new();
    for pointer in [
        "/metric_attribution/direct_metric_ids",
        "/metric_attribution/dependency_metric_ids",
        "/selected_metric_ids",
    ] {
        if let Some(ids) = value.pointer(pointer).and_then(Value::as_array) {
            values.extend(
                ids.iter()
                    .filter_map(Value::as_str)
                    .map(|metric| format!("healthmd.healthkit_records#metric:{metric}")),
            );
        }
    }
    if values.is_empty() {
        values.push(format!("healthmd.healthkit_records#kind:{fallback}"));
    }
    values
}

fn index_provider_record(
    value: &Value,
    pointer: &str,
    artifact_id: &str,
    parsed: &mut ParsedArtifact,
) -> Result<(), ()> {
    let schema = value
        .get("schema")
        .and_then(Value::as_str)
        .filter(|value| *value == "healthmd.external_provider_daily")
        .ok_or(())?;
    let version = value.get("schema_version").and_then(Value::as_u64);
    let provider = value
        .get("provider")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or(())?;
    let owner_date = parse_date(value.get("date"));
    push_schema(&mut parsed.schemas, schema, version);
    parsed.detail_levels.insert(AgentDataDetailLevel::Lossless);
    if let Some(payloads) = value.get("payloads").and_then(Value::as_array) {
        for (index, payload) in payloads.iter().enumerate() {
            let name = payload
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("payload");
            let (start_time, end_time) = record_times(payload);
            parsed.records.push(new_record(
                artifact_id,
                RecordLocator::JsonPointer {
                    pointer: format!("{pointer}/payloads/{index}"),
                },
                vec![format!("{schema}#provider:{provider}/payload:{name}")],
                &format!("provider:{provider}"),
                schema,
                version,
                AgentDataDetailLevel::Lossless,
                owner_date,
                start_time,
                end_time,
                "complete",
            ));
        }
    }
    Ok(())
}

fn parse_raw_snapshot(value: &Value, artifact_id: &str) -> Result<ParsedArtifact, ()> {
    if value.pointer("/manifest/status").and_then(Value::as_str) != Some("COMPLETE")
        || value.pointer("/manifest/schema").and_then(Value::as_str)
            != Some("healthmd.raw-snapshot.manifest")
        || value.pointer("/header/version").and_then(Value::as_u64) != Some(1)
        || value.pointer("/manifest/version").and_then(Value::as_u64) != Some(1)
        || value
            .pointer("/header/snapshotId")
            .and_then(Value::as_str)
            .is_none()
        || value.pointer("/header/snapshotId").and_then(Value::as_str)
            != value
                .pointer("/manifest/snapshotId")
                .and_then(Value::as_str)
    {
        return Err(());
    }
    let schema = "healthmd.raw-snapshot";
    let version = value.pointer("/header/version").and_then(Value::as_u64);
    let mut parsed = ParsedArtifact {
        schemas: vec![ArtifactSchema {
            schema: schema.to_owned(),
            schema_version: version,
        }],
        capture_status: "complete".to_owned(),
        detail_levels: BTreeSet::from([AgentDataDetailLevel::Lossless]),
        records: Vec::new(),
    };
    let records = value.get("records").and_then(Value::as_array).ok_or(())?;
    if value
        .pointer("/manifest/recordCount")
        .and_then(Value::as_u64)
        != u64::try_from(records.len()).ok()
    {
        return Err(());
    }
    for (index, record) in records.iter().enumerate() {
        let wire_type = record
            .get("wireType")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or(())?;
        let (start_time, end_time) = record_times(record);
        let owner_date = start_time.map(|time| time.date_naive());
        parsed.records.push(new_record(
            artifact_id,
            RecordLocator::JsonPointer {
                pointer: format!("/records/{index}"),
            },
            vec![format!("{schema}#wire:{wire_type}")],
            schema,
            schema,
            version,
            AgentDataDetailLevel::Lossless,
            owner_date,
            start_time,
            end_time,
            "complete",
        ));
    }
    Ok(parsed)
}

fn parse_raw_changes(value: &Value, artifact_id: &str) -> Result<ParsedArtifact, ()> {
    if value.pointer("/manifest/status").and_then(Value::as_str) != Some("COMPLETE")
        || value.pointer("/manifest/schema").and_then(Value::as_str)
            != Some("healthmd.raw-changes.manifest")
        || value.pointer("/header/version").and_then(Value::as_u64) != Some(1)
        || value.pointer("/manifest/version").and_then(Value::as_u64) != Some(1)
        || value
            .pointer("/header/archiveId")
            .and_then(Value::as_str)
            .is_none()
        || value
            .pointer("/header/chainId")
            .and_then(Value::as_str)
            .is_none()
        || value
            .pointer("/header/sequence")
            .and_then(Value::as_u64)
            .is_none()
        || value.pointer("/header/archiveId").and_then(Value::as_str)
            != value.pointer("/manifest/archiveId").and_then(Value::as_str)
        || value.pointer("/header/chainId").and_then(Value::as_str)
            != value.pointer("/manifest/chainId").and_then(Value::as_str)
        || value.pointer("/header/sequence").and_then(Value::as_u64)
            != value.pointer("/manifest/sequence").and_then(Value::as_u64)
    {
        return Err(());
    }
    let schema = "healthmd.raw-changes";
    let version = value.pointer("/header/version").and_then(Value::as_u64);
    let mut parsed = ParsedArtifact {
        schemas: vec![ArtifactSchema {
            schema: schema.to_owned(),
            schema_version: version,
        }],
        capture_status: "complete".to_owned(),
        detail_levels: BTreeSet::from([AgentDataDetailLevel::Lossless]),
        records: Vec::new(),
    };
    let events = value.get("events").and_then(Value::as_array).ok_or(())?;
    if value
        .pointer("/manifest/eventCount")
        .and_then(Value::as_u64)
        != u64::try_from(events.len()).ok()
    {
        return Err(());
    }
    for (index, event) in events.iter().enumerate() {
        let record = event.get("record").unwrap_or(event);
        let wire_type = record
            .get("wireType")
            .and_then(Value::as_str)
            .or_else(|| event.get("wireType").and_then(Value::as_str))
            .unwrap_or("unknown_deletion");
        let (start_time, end_time) = record_times(record);
        let observed = parse_instant(event.get("observedAt"));
        let start_time = start_time.or(observed);
        parsed.records.push(new_record(
            artifact_id,
            RecordLocator::JsonPointer {
                pointer: format!("/events/{index}"),
            },
            vec![format!("{schema}#wire:{wire_type}")],
            schema,
            schema,
            version,
            AgentDataDetailLevel::Lossless,
            start_time.map(|time| time.date_naive()),
            start_time,
            end_time,
            "complete",
        ));
    }
    Ok(parsed)
}

#[allow(clippy::too_many_lines)]
fn parse_ndjson_artifact(path: &Path, artifact_id: &str) -> Result<Option<ParsedArtifact>, ()> {
    let file = fs::File::open(path).map_err(|_| ())?;
    let mut reader = BufReader::new(file);
    let mut line = Vec::new();
    let mut line_number = 0_usize;
    let mut saw_header = false;
    let mut saw_manifest = false;
    let mut snapshot_id = None;
    let mut record_count = 0_u64;
    let mut parsed = ParsedArtifact::default();
    loop {
        line.clear();
        let count = reader.read_until(b'\n', &mut line).map_err(|_| ())?;
        if count == 0 {
            break;
        }
        line_number += 1;
        if line.len() > MAXIMUM_NDJSON_LINE_BYTES {
            return Err(());
        }
        if line.last() == Some(&b'\n') {
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
        }
        if line.is_empty() || saw_manifest {
            return Err(());
        }
        let value: Value = serde_json::from_slice(&line).map_err(|_| ())?;
        match value.get("kind").and_then(Value::as_str) {
            Some("header") if line_number == 1 => {
                let header = value.get("header").ok_or(())?;
                if header.get("schema").and_then(Value::as_str) != Some("healthmd.raw-snapshot") {
                    return Ok(None);
                }
                saw_header = true;
                if header.get("version").and_then(Value::as_u64) != Some(1) {
                    return Err(());
                }
                snapshot_id = header
                    .get("snapshotId")
                    .and_then(Value::as_str)
                    .map(str::to_owned);
                if snapshot_id.is_none() {
                    return Err(());
                }
                parsed.schemas.push(ArtifactSchema {
                    schema: "healthmd.raw-snapshot".to_owned(),
                    schema_version: header.get("version").and_then(Value::as_u64),
                });
                parsed.capture_status.clear();
                parsed.capture_status.push_str("complete");
                parsed.detail_levels.insert(AgentDataDetailLevel::Lossless);
            }
            Some("record") if saw_header => {
                record_count = record_count.saturating_add(1);
                let record = value.get("record").ok_or(())?;
                let wire_type = record
                    .get("wireType")
                    .and_then(Value::as_str)
                    .filter(|value| !value.is_empty())
                    .ok_or(())?;
                let (start_time, end_time) = record_times(record);
                parsed.records.push(new_record(
                    artifact_id,
                    RecordLocator::NdjsonLine { line: line_number },
                    vec![format!("healthmd.raw-snapshot#wire:{wire_type}")],
                    "healthmd.raw-snapshot",
                    "healthmd.raw-snapshot",
                    parsed
                        .schemas
                        .first()
                        .and_then(|value| value.schema_version),
                    AgentDataDetailLevel::Lossless,
                    start_time.map(|time| time.date_naive()),
                    start_time,
                    end_time,
                    "complete",
                ));
            }
            Some("issue") if saw_header => {}
            Some("manifest") if saw_header => {
                let manifest = value.get("manifest").ok_or(())?;
                if manifest.get("schema").and_then(Value::as_str)
                    != Some("healthmd.raw-snapshot.manifest")
                    || manifest.get("version").and_then(Value::as_u64) != Some(1)
                    || manifest.get("status").and_then(Value::as_str) != Some("COMPLETE")
                    || manifest.get("snapshotId").and_then(Value::as_str) != snapshot_id.as_deref()
                    || manifest.get("recordCount").and_then(Value::as_u64) != Some(record_count)
                {
                    return Err(());
                }
                saw_manifest = true;
            }
            _ => return Err(()),
        }
    }
    if !saw_header || !saw_manifest {
        return Err(());
    }
    Ok(Some(parsed))
}

#[allow(clippy::too_many_arguments)]
fn new_record(
    artifact_id: &str,
    locator: RecordLocator,
    metric_ids: Vec<String>,
    source_id: &str,
    source_schema: &str,
    source_schema_version: Option<u64>,
    detail_level: AgentDataDetailLevel,
    owner_date: Option<NaiveDate>,
    start_time: Option<DateTime<Utc>>,
    end_time: Option<DateTime<Utc>>,
    capture_status: &str,
) -> RecordEntry {
    RecordEntry {
        record_id: String::new(),
        artifact_id: artifact_id.to_owned(),
        locator,
        metric_ids,
        source_id: source_id.to_owned(),
        source_schema: source_schema.to_owned(),
        source_schema_version,
        detail_level,
        owner_date,
        start_time,
        end_time,
        capture_status: capture_status.to_owned(),
    }
}

fn record_times(value: &Value) -> (Option<DateTime<Utc>>, Option<DateTime<Utc>>) {
    let start = [
        "start_date",
        "startDate",
        "startTimeISO",
        "startTime",
        "start_time",
        "timestamp",
        "scheduledDate",
        "fetched_at",
        "observedAt",
    ]
    .iter()
    .find_map(|key| parse_instant(value.get(*key)));
    let end = ["end_date", "endDate", "endTimeISO", "endTime", "end_time"]
        .iter()
        .find_map(|key| parse_instant(value.get(*key)));
    (start, end)
}

fn parse_instant(value: Option<&Value>) -> Option<DateTime<Utc>> {
    let value = value?;
    if let Some(text) = value.as_str() {
        return DateTime::parse_from_rfc3339(text)
            .ok()
            .map(|value| value.with_timezone(&Utc));
    }
    let object = value.as_object()?;
    let seconds = object
        .get("epochSecondExact")
        .and_then(Value::as_str)
        .and_then(|value| value.parse::<i64>().ok())
        .or_else(|| object.get("epochSecond").and_then(Value::as_i64))?;
    let nanos = object
        .get("nano")
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
        .unwrap_or(0);
    DateTime::from_timestamp(seconds, nanos)
}

fn parse_date(value: Option<&Value>) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(value?.as_str()?, "%Y-%m-%d").ok()
}

fn schema_reference(value: &Value, fallback: &str) -> ArtifactSchema {
    ArtifactSchema {
        schema: value
            .get("schema")
            .and_then(Value::as_str)
            .unwrap_or(fallback)
            .to_owned(),
        schema_version: value.get("schema_version").and_then(Value::as_u64),
    }
}

fn push_schema(schemas: &mut Vec<ArtifactSchema>, schema: &str, schema_version: Option<u64>) {
    let value = ArtifactSchema {
        schema: schema.to_owned(),
        schema_version,
    };
    if !schemas.contains(&value) {
        schemas.push(value);
        schemas.sort_by(|left, right| {
            (&left.schema, left.schema_version).cmp(&(&right.schema, right.schema_version))
        });
    }
}

fn merge_capture_status(current: &str, next: &str) -> String {
    if current == "partial" || next == "partial" {
        "partial".to_owned()
    } else if current.is_empty() {
        next.to_owned()
    } else if current == "complete" || next == "complete" {
        "complete".to_owned()
    } else {
        next.to_owned()
    }
}

fn escape_pointer(value: &str) -> String {
    value.replace('~', "~0").replace('/', "~1")
}

fn record_order(left: &RecordEntry, right: &RecordEntry) -> std::cmp::Ordering {
    (
        left.owner_date,
        left.start_time,
        &left.metric_ids,
        &left.source_id,
        &left.artifact_id,
        locator_order(&left.locator),
    )
        .cmp(&(
            right.owner_date,
            right.start_time,
            &right.metric_ids,
            &right.source_id,
            &right.artifact_id,
            locator_order(&right.locator),
        ))
}

fn locator_order(locator: &RecordLocator) -> String {
    match locator {
        RecordLocator::JsonPointer { pointer } => format!("json:{pointer}"),
        RecordLocator::NdjsonLine { line } => format!("ndjson:{line:020}"),
    }
}

fn persist_index(path: &Path, index: &DirectoryIndex) -> Result<(), DataStoreOpenError> {
    let parent = path.parent().ok_or_else(|| {
        DataStoreOpenError::new("the Agent Data index path has no parent directory")
    })?;
    prepare_private_directory(parent)?;
    let mut temporary = NamedTempFile::new_in(parent)
        .map_err(|_| DataStoreOpenError::new("the Agent Data index could not be created"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        temporary
            .as_file()
            .set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|_| DataStoreOpenError::new("the Agent Data index could not be restricted"))?;
    }
    serde_json::to_writer(&mut temporary, index)
        .map_err(|_| DataStoreOpenError::new("the Agent Data index could not be encoded"))?;
    temporary
        .write_all(b"\n")
        .and_then(|()| temporary.as_file().sync_all())
        .map_err(|_| DataStoreOpenError::new("the Agent Data index could not be written"))?;
    temporary
        .persist(path)
        .map_err(|_| DataStoreOpenError::new("the Agent Data index could not be committed"))?;
    Ok(())
}

fn execute_query(
    root: &Path,
    index: &DirectoryIndex,
    grant: &AgentDataGrant,
    cursor_key: &[u8; 32],
    request: &AgentDataQueryRequest,
) -> Result<Value, BackendError> {
    let fingerprint = query_fingerprint(request)?;
    let offset = decode_cursor(
        request.page.cursor.as_deref(),
        &index.index_revision,
        &fingerprint,
        cursor_key,
    )?;
    match &request.operation {
        AgentDataOperation::Catalog => {
            query_catalog(index, grant, request, cursor_key, &fingerprint, offset)
        }
        AgentDataOperation::Records { .. } => query_records(
            root,
            index,
            grant,
            request,
            cursor_key,
            &fingerprint,
            offset,
        ),
        AgentDataOperation::RecordRead { record_id } => query_record_read(
            root,
            index,
            grant,
            request,
            cursor_key,
            &fingerprint,
            offset,
            record_id,
        ),
        AgentDataOperation::Artifacts => {
            query_artifacts(index, grant, request, cursor_key, &fingerprint, offset)
        }
        AgentDataOperation::ArtifactRead { artifact_id } => query_artifact_read(
            root,
            index,
            grant,
            request,
            cursor_key,
            &fingerprint,
            offset,
            artifact_id,
        ),
    }
}

#[derive(Default)]
struct CatalogAggregate {
    count: usize,
    first_date: Option<NaiveDate>,
    last_date: Option<NaiveDate>,
    first_time: Option<DateTime<Utc>>,
    last_time: Option<DateTime<Utc>>,
}

fn query_catalog(
    index: &DirectoryIndex,
    grant: &AgentDataGrant,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
) -> Result<Value, BackendError> {
    let mut aggregates: BTreeMap<(String, String, AgentDataDetailLevel), CatalogAggregate> =
        BTreeMap::new();
    for record in &index.records {
        if !grant.allows_record(&record.scope()) {
            continue;
        }
        for metric_id in &record.metric_ids {
            let aggregate = aggregates
                .entry((
                    metric_id.clone(),
                    record.source_id.clone(),
                    record.detail_level,
                ))
                .or_default();
            aggregate.count += 1;
            update_min_max(
                &mut aggregate.first_date,
                &mut aggregate.last_date,
                record.owner_date,
            );
            update_min_max(
                &mut aggregate.first_time,
                &mut aggregate.last_time,
                record.start_time,
            );
        }
    }
    let values = aggregates
        .into_iter()
        .map(|((metric_id, source_id, detail_level), aggregate)| {
            json!({
                "type": "metric",
                "metric_id": metric_id,
                "source_id": source_id,
                "detail_level": detail_level,
                "record_count": aggregate.count,
                "coverage": {
                    "first_owner_date": aggregate.first_date,
                    "last_owner_date": aggregate.last_date,
                    "first_time": aggregate.first_time,
                    "last_time": aggregate.last_time
                }
            })
        })
        .collect::<Vec<_>>();
    paged_response(
        index,
        request,
        cursor_key,
        fingerprint,
        offset,
        "catalog",
        &values,
    )
}

fn query_records(
    root: &Path,
    index: &DirectoryIndex,
    grant: &AgentDataGrant,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
) -> Result<Value, BackendError> {
    let selected = index
        .records
        .iter()
        .filter(|record| {
            grant.allows_record(&record.scope())
                && request.operation.matches_record(&record.scope())
        })
        .collect::<Vec<_>>();
    if offset > selected.len() {
        return Err(invalid_cursor());
    }
    let artifacts = index
        .artifacts
        .iter()
        .map(|artifact| (artifact.artifact_id.as_str(), artifact))
        .collect::<HashMap<_, _>>();
    let mut cache = HashMap::new();
    let mut items = Vec::new();
    let mut item_bytes = 0_usize;
    let mut consumed = 0_usize;
    for record in selected.iter().skip(offset).take(request.page.max_items) {
        let artifact = artifacts
            .get(record.artifact_id.as_str())
            .copied()
            .ok_or_else(|| backend_failure("healthmd_agent_index_invalid"))?;
        let value = read_record_value(root, artifact, record, &mut cache)?;
        let mut item = record_item(record, &value);
        let mut encoded = encoded_len(&item)?;
        if encoded > request.page.max_bytes {
            item.as_object_mut()
                .ok_or_else(|| backend_failure("healthmd_agent_query_failed"))?
                .remove("value");
            item["inline"] = Value::Bool(false);
            item["read_with"] = Value::String("healthmd_data_record_read".to_owned());
            encoded = encoded_len(&item)?;
        }
        if encoded > request.page.max_bytes {
            return Err(BackendError::new(
                "healthmd_agent_page_too_small",
                "The requested Agent Data page is too small for record metadata.",
            ));
        }
        if !items.is_empty() && item_bytes.saturating_add(encoded) > request.page.max_bytes {
            break;
        }
        item_bytes += encoded;
        items.push(item);
        consumed += 1;
    }
    let next_offset = offset.saturating_add(consumed);
    let next_cursor = (next_offset < selected.len())
        .then(|| encode_cursor(index, fingerprint, next_offset, cursor_key))
        .transpose()?;
    Ok(response(index, "records", &items, next_cursor.as_deref()))
}

#[allow(clippy::too_many_arguments)]
fn query_record_read(
    root: &Path,
    index: &DirectoryIndex,
    grant: &AgentDataGrant,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
    record_id: &str,
) -> Result<Value, BackendError> {
    let record = index
        .records
        .iter()
        .find(|record| record.record_id == record_id)
        .filter(|record| grant.allows_record(&record.scope()))
        .ok_or_else(|| {
            BackendError::new(
                "healthmd_agent_record_unavailable",
                "The requested Agent Data record is unavailable to this grant.",
            )
        })?;
    let artifact = index
        .artifacts
        .iter()
        .find(|artifact| artifact.artifact_id == record.artifact_id)
        .ok_or_else(|| backend_failure("healthmd_agent_index_invalid"))?;
    let mut cache = HashMap::new();
    let value = read_record_value(root, artifact, record, &mut cache)?;
    let bytes =
        serde_json::to_vec(&value).map_err(|_| backend_failure("healthmd_agent_query_failed"))?;
    chunk_response(
        index,
        request,
        cursor_key,
        fingerprint,
        offset,
        &bytes,
        "record_read",
        "record_chunk",
        "record_id",
        record_id,
        "application/json",
    )
}

fn query_artifacts(
    index: &DirectoryIndex,
    grant: &AgentDataGrant,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
) -> Result<Value, BackendError> {
    let values = if grant.allows_full_artifacts() {
        index
            .artifacts
            .iter()
            .map(|artifact| {
                json!({
                    "type": "artifact",
                    "artifact_id": artifact.artifact_id,
                    "byte_count": artifact.byte_count,
                    "media_type": artifact.media_type,
                    "physical_format": artifact.physical_format,
                    "schemas": artifact.schemas,
                    "capture_status": artifact.capture_status,
                    "detail_levels": artifact.detail_levels,
                    "record_count": artifact.record_count
                })
            })
            .collect()
    } else {
        Vec::new()
    };
    paged_response(
        index,
        request,
        cursor_key,
        fingerprint,
        offset,
        "artifacts",
        &values,
    )
}

#[allow(clippy::too_many_arguments)]
fn query_artifact_read(
    root: &Path,
    index: &DirectoryIndex,
    grant: &AgentDataGrant,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
    artifact_id: &str,
) -> Result<Value, BackendError> {
    if !grant.allows_full_artifacts() {
        return Err(BackendError::new(
            "healthmd_agent_bulk_download_denied",
            "The configured Agent Data grant does not permit whole-artifact downloads.",
        ));
    }
    let artifact = index
        .artifacts
        .iter()
        .find(|artifact| artifact.artifact_id == artifact_id)
        .ok_or_else(|| {
            BackendError::new(
                "healthmd_agent_artifact_unavailable",
                "The requested Agent Data artifact is unavailable.",
            )
        })?;
    artifact_chunk_response(
        root,
        artifact,
        index,
        request,
        cursor_key,
        fingerprint,
        offset,
    )
}

fn artifact_chunk_response(
    root: &Path,
    artifact: &ArtifactEntry,
    index: &DirectoryIndex,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
) -> Result<Value, BackendError> {
    if request.page.max_bytes <= CURSOR_RESPONSE_OVERHEAD_BYTES {
        return Err(BackendError::new(
            "healthmd_agent_page_too_small",
            "The requested Agent Data page is too small for a data chunk.",
        ));
    }
    let maximum_raw = ((request.page.max_bytes - CURSOR_RESPONSE_OVERHEAD_BYTES) / 4) * 3;
    let (chunk, total_byte_count) =
        read_verified_artifact_chunk(root, artifact, offset, maximum_raw.max(1))?;
    let end = offset.saturating_add(chunk.len());
    let complete = end == total_byte_count;
    let item = json!({
        "type": "artifact_chunk",
        "artifact_id": artifact.artifact_id,
        "offset": offset,
        "byte_count": chunk.len(),
        "total_byte_count": total_byte_count,
        "media_type": artifact.media_type,
        "encoding": "base64",
        "data": URL_SAFE_NO_PAD.encode(chunk),
        "complete": complete,
        "sha256": artifact.artifact_id
    });
    let next_cursor = (!complete)
        .then(|| encode_cursor(index, fingerprint, end, cursor_key))
        .transpose()?;
    Ok(response(
        index,
        "artifact_read",
        &[item],
        next_cursor.as_deref(),
    ))
}

#[allow(clippy::too_many_arguments)]
fn chunk_response(
    index: &DirectoryIndex,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
    bytes: &[u8],
    operation: &str,
    item_type: &str,
    identifier_name: &str,
    identifier: &str,
    media_type: &str,
) -> Result<Value, BackendError> {
    if offset > bytes.len() || request.page.max_bytes <= CURSOR_RESPONSE_OVERHEAD_BYTES {
        return Err(BackendError::new(
            "healthmd_agent_page_too_small",
            "The requested Agent Data page is too small for a data chunk.",
        ));
    }
    let maximum_raw = ((request.page.max_bytes - CURSOR_RESPONSE_OVERHEAD_BYTES) / 4) * 3;
    let end = offset.saturating_add(maximum_raw.max(1)).min(bytes.len());
    let chunk = &bytes[offset..end];
    let complete = end == bytes.len();
    let mut item = json!({
        "type": item_type,
        "offset": offset,
        "byte_count": chunk.len(),
        "total_byte_count": bytes.len(),
        "media_type": media_type,
        "encoding": "base64",
        "data": URL_SAFE_NO_PAD.encode(chunk),
        "complete": complete,
        "sha256": sha256_hex(bytes)
    });
    item[identifier_name] = Value::String(identifier.to_owned());
    let next_cursor = (!complete)
        .then(|| encode_cursor(index, fingerprint, end, cursor_key))
        .transpose()?;
    Ok(response(index, operation, &[item], next_cursor.as_deref()))
}

fn paged_response(
    index: &DirectoryIndex,
    request: &AgentDataQueryRequest,
    cursor_key: &[u8; 32],
    fingerprint: &str,
    offset: usize,
    operation: &str,
    values: &[Value],
) -> Result<Value, BackendError> {
    if offset > values.len() {
        return Err(invalid_cursor());
    }
    let mut items = Vec::new();
    let mut item_bytes = 0_usize;
    for value in values.iter().skip(offset).take(request.page.max_items) {
        let encoded = encoded_len(value)?;
        if encoded > request.page.max_bytes {
            return Err(BackendError::new(
                "healthmd_agent_page_too_small",
                "The requested Agent Data page is too small for one catalog item.",
            ));
        }
        if !items.is_empty() && item_bytes.saturating_add(encoded) > request.page.max_bytes {
            break;
        }
        item_bytes += encoded;
        items.push(value.clone());
    }
    let next_offset = offset.saturating_add(items.len());
    let next_cursor = (next_offset < values.len())
        .then(|| encode_cursor(index, fingerprint, next_offset, cursor_key))
        .transpose()?;
    Ok(response(index, operation, &items, next_cursor.as_deref()))
}

fn response(
    index: &DirectoryIndex,
    operation: &str,
    items: &[Value],
    next_cursor: Option<&str>,
) -> Value {
    json!({
        "schema": AGENT_QUERY_RESPONSE_SCHEMA,
        "schema_version": 1,
        "operation": operation,
        "receipt": {
            "index_revision": index.index_revision,
            "returned_items": items.len(),
            "source_kind": "directory",
            "policy_enforced": true
        },
        "items": items,
        "next_cursor": next_cursor
    })
}

fn record_item(record: &RecordEntry, value: &Value) -> Value {
    let locator = match &record.locator {
        RecordLocator::JsonPointer { pointer } => {
            json!({"type": "json_pointer", "pointer": pointer})
        }
        RecordLocator::NdjsonLine { line } => json!({"type": "ndjson_line", "line": line}),
    };
    json!({
        "type": "record",
        "record_id": record.record_id,
        "metric_ids": record.metric_ids,
        "source_id": record.source_id,
        "detail_level": record.detail_level,
        "owner_date": record.owner_date,
        "start_time": record.start_time,
        "end_time": record.end_time,
        "capture_status": record.capture_status,
        "artifact": {
            "artifact_id": record.artifact_id,
            "schema": record.source_schema,
            "schema_version": record.source_schema_version
        },
        "locator": locator,
        "inline": true,
        "value": value
    })
}

fn read_record_value(
    root: &Path,
    artifact: &ArtifactEntry,
    record: &RecordEntry,
    cache: &mut HashMap<String, Arc<Value>>,
) -> Result<Value, BackendError> {
    match &record.locator {
        RecordLocator::JsonPointer { pointer } => {
            let document = if let Some(value) = cache.get(&artifact.artifact_id) {
                Arc::clone(value)
            } else {
                let bytes = read_artifact_bytes(root, artifact)?;
                let value: Value = serde_json::from_slice(&bytes)
                    .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
                let value = Arc::new(value);
                cache.insert(artifact.artifact_id.clone(), Arc::clone(&value));
                value
            };
            document
                .pointer(pointer)
                .cloned()
                .ok_or_else(|| backend_failure("healthmd_agent_source_changed"))
        }
        RecordLocator::NdjsonLine { line } => {
            let bytes = read_verified_ndjson_line(root, artifact, *line)?;
            let wrapper: Value = serde_json::from_slice(&bytes)
                .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
            wrapper
                .get("record")
                .cloned()
                .ok_or_else(|| backend_failure("healthmd_agent_source_changed"))
        }
    }
}

fn read_verified_ndjson_line(
    root: &Path,
    artifact: &ArtifactEntry,
    target_line: usize,
) -> Result<Vec<u8>, BackendError> {
    let path = artifact_path(root, artifact)?;
    let file =
        fs::File::open(path).map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
    let mut reader = BufReader::new(file);
    let mut hasher = Sha256::new();
    let mut line = Vec::new();
    let mut selected = None;
    let mut line_number = 0_usize;
    let mut byte_count = 0_u64;
    loop {
        line.clear();
        let count = reader
            .read_until(b'\n', &mut line)
            .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
        if count == 0 {
            break;
        }
        if line.len() > MAXIMUM_NDJSON_LINE_BYTES {
            return Err(backend_failure("healthmd_agent_source_changed"));
        }
        line_number += 1;
        byte_count = byte_count.saturating_add(u64::try_from(count).unwrap_or(u64::MAX));
        hasher.update(&line);
        if line_number == target_line {
            let mut value = line.clone();
            if value.last() == Some(&b'\n') {
                value.pop();
                if value.last() == Some(&b'\r') {
                    value.pop();
                }
            }
            selected = Some(value);
        }
    }
    if byte_count != artifact.byte_count || hex_digest(hasher.finalize()) != artifact.artifact_id {
        return Err(backend_failure("healthmd_agent_source_changed"));
    }
    selected.ok_or_else(|| backend_failure("healthmd_agent_source_changed"))
}

fn read_verified_artifact_chunk(
    root: &Path,
    artifact: &ArtifactEntry,
    offset: usize,
    maximum_bytes: usize,
) -> Result<(Vec<u8>, usize), BackendError> {
    let total_byte_count = usize::try_from(artifact.byte_count)
        .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
    if offset > total_byte_count {
        return Err(invalid_cursor());
    }
    let path = artifact_path(root, artifact)?;
    let mut file =
        fs::File::open(path).map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
    let expected_end = offset.saturating_add(maximum_bytes).min(total_byte_count);
    let mut chunk = Vec::with_capacity(expected_end.saturating_sub(offset));
    let mut hasher = Sha256::new();
    let mut buffer = vec![0_u8; 64 * 1_024];
    let mut position = 0_usize;
    loop {
        let count = file
            .read(&mut buffer)
            .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
        let buffer_end = position.saturating_add(count);
        let copy_start = offset.max(position);
        let copy_end = expected_end.min(buffer_end);
        if copy_start < copy_end {
            chunk.extend_from_slice(&buffer[copy_start - position..copy_end - position]);
        }
        position = buffer_end;
    }
    if position != total_byte_count || hex_digest(hasher.finalize()) != artifact.artifact_id {
        return Err(backend_failure("healthmd_agent_source_changed"));
    }
    Ok((chunk, total_byte_count))
}

fn read_artifact_bytes(root: &Path, artifact: &ArtifactEntry) -> Result<Vec<u8>, BackendError> {
    let path = artifact_path(root, artifact)?;
    let bytes = fs::read(path).map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
    if u64::try_from(bytes.len()).ok() != Some(artifact.byte_count)
        || sha256_hex(&bytes) != artifact.artifact_id
    {
        return Err(backend_failure("healthmd_agent_source_changed"));
    }
    Ok(bytes)
}

fn artifact_path(root: &Path, artifact: &ArtifactEntry) -> Result<PathBuf, BackendError> {
    let path = root.join(&artifact.relative_path);
    let metadata = fs::symlink_metadata(&path)
        .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(backend_failure("healthmd_agent_source_changed"));
    }
    let canonical = path
        .canonicalize()
        .map_err(|_| backend_failure("healthmd_agent_source_changed"))?;
    if !canonical.starts_with(root) {
        return Err(backend_failure("healthmd_agent_source_changed"));
    }
    Ok(canonical)
}

fn query_fingerprint(request: &AgentDataQueryRequest) -> Result<String, BackendError> {
    let mut value = serde_json::to_value(request)
        .map_err(|_| backend_failure("healthmd_agent_query_failed"))?;
    value["page"]["cursor"] = Value::Null;
    let bytes =
        serde_json::to_vec(&value).map_err(|_| backend_failure("healthmd_agent_query_failed"))?;
    Ok(sha256_hex(&bytes))
}

fn encode_cursor(
    index: &DirectoryIndex,
    query_fingerprint: &str,
    offset: usize,
    key: &[u8; 32],
) -> Result<String, BackendError> {
    let payload = CursorPayload {
        version: CURSOR_VERSION,
        index_revision: index.index_revision.clone(),
        query_fingerprint: query_fingerprint.to_owned(),
        offset,
    };
    let bytes =
        serde_json::to_vec(&payload).map_err(|_| backend_failure("healthmd_agent_query_failed"))?;
    let mut mac = HmacSha256::new_from_slice(key)
        .map_err(|_| backend_failure("healthmd_agent_query_failed"))?;
    mac.update(&bytes);
    let signature = mac.finalize().into_bytes();
    Ok(format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(bytes),
        URL_SAFE_NO_PAD.encode(signature)
    ))
}

fn decode_cursor(
    cursor: Option<&str>,
    index_revision: &str,
    query_fingerprint: &str,
    key: &[u8; 32],
) -> Result<usize, BackendError> {
    let Some(cursor) = cursor else {
        return Ok(0);
    };
    let (payload, signature) = cursor.split_once('.').ok_or_else(invalid_cursor)?;
    let payload = URL_SAFE_NO_PAD
        .decode(payload)
        .map_err(|_| invalid_cursor())?;
    let signature = URL_SAFE_NO_PAD
        .decode(signature)
        .map_err(|_| invalid_cursor())?;
    let mut mac = HmacSha256::new_from_slice(key).map_err(|_| invalid_cursor())?;
    mac.update(&payload);
    mac.verify_slice(&signature).map_err(|_| invalid_cursor())?;
    let payload: CursorPayload = serde_json::from_slice(&payload).map_err(|_| invalid_cursor())?;
    if payload.version != CURSOR_VERSION
        || payload.index_revision != index_revision
        || payload.query_fingerprint != query_fingerprint
    {
        return Err(BackendError::new(
            "healthmd_agent_cursor_stale",
            "The Agent Data cursor no longer matches this data store and query.",
        ));
    }
    Ok(payload.offset)
}

fn invalid_cursor() -> BackendError {
    BackendError::new(
        "healthmd_agent_cursor_invalid",
        "The Agent Data cursor is invalid.",
    )
}

fn encoded_len(value: &Value) -> Result<usize, BackendError> {
    serde_json::to_vec(value)
        .map(|bytes| bytes.len())
        .map_err(|_| backend_failure("healthmd_agent_query_failed"))
}

fn update_min_max<T: Ord + Copy>(
    minimum: &mut Option<T>,
    maximum: &mut Option<T>,
    value: Option<T>,
) {
    let Some(value) = value else {
        return;
    };
    if minimum.is_none_or(|current| value < current) {
        *minimum = Some(value);
    }
    if maximum.is_none_or(|current| value > current) {
        *maximum = Some(value);
    }
}

fn hash_file(path: &Path) -> Result<String, std::io::Error> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0_u8; 64 * 1_024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(hex_digest(hasher.finalize()))
}

fn sha256_hex(bytes: &[u8]) -> String {
    hex_digest(Sha256::digest(bytes))
}

fn hex_digest(bytes: impl AsRef<[u8]>) -> String {
    let bytes = bytes.as_ref();
    let mut value = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        let _ = write!(value, "{byte:02x}");
    }
    value
}

fn backend_failure(code: &'static str) -> BackendError {
    BackendError::new(
        code,
        "The Agent Data store could not complete the bounded read.",
    )
    .retryable(code == "healthmd_agent_source_changed")
}

fn open_to_backend(_error: DataStoreOpenError) -> BackendError {
    backend_failure("healthmd_agent_index_failed")
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use healthmd_operations::{
        AGENT_DATA_GRANT_SCHEMA, AGENT_DATA_QUERY_SCHEMA, AGENT_DATA_SCHEMA_VERSION,
        ArtifactStoreBackend, CallerIdentity, HealthDataBackend, QueryDetailLevel,
        QueryPageRequest,
    };
    use tempfile::TempDir;
    use tokio_util::sync::CancellationToken;

    use super::*;

    const APPLE: &str = r#"{
      "schema":"healthmd.health_data","schema_version":8,"date":"2026-03-15",
      "type":"health-data","raw_capture_status":"complete","unit_system":"metric","units":{},
      "activity":{"steps":12345},"heart":{"restingHeartRate":58},
      "healthkit_record_archive":{"schema":"healthmd.healthkit_records","schema_version":1,
        "capture_status":"complete","records":[{"record_kind":"quantity","start_date":"2026-03-15T12:00:00Z",
        "end_date":"2026-03-15T12:00:01Z","selected_metric_ids":["heart_rate_avg"],"payload":{"value":72}}],
        "external_records":[],"medication_inventory":[]}
    }"#;
    const APPLE_API_V2: &str = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../../apps/apple/docs/reference/generated/automation/api-export-v2-provider-sidecar.json"
    ));
    const ANDROID_RAW_SNAPSHOT: &str = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../../apps/android/app/src/test/resources/raw-export/v1/minimal-snapshot.json"
    ));

    fn write_file(path: &Path, contents: &str) {
        let mut file = fs::File::create(path).unwrap();
        file.write_all(contents.as_bytes()).unwrap();
        file.sync_all().unwrap();
    }

    #[allow(clippy::needless_pass_by_value)]
    fn grant(metrics: Value, details: Value, bulk: bool) -> Value {
        json!({
            "schema": AGENT_DATA_GRANT_SCHEMA,
            "schema_version": AGENT_DATA_SCHEMA_VERSION,
            "metrics": metrics,
            "sources": {"type": "all_available"},
            "dates": {"type": "all_available"},
            "times": {"type": "all_available"},
            "detail_levels": details,
            "bulk_download": bulk
        })
    }

    #[allow(clippy::needless_pass_by_value)]
    fn query(operation: Value) -> AgentDataQueryRequest {
        AgentDataQueryRequest::from_value(json!({
            "schema": AGENT_DATA_QUERY_SCHEMA,
            "schema_version": AGENT_DATA_SCHEMA_VERSION,
            "operation": operation,
            "page": {"max_items": 250, "max_bytes": 262_144, "cursor": null}
        }))
        .unwrap()
    }

    fn store(grant_value: Value) -> (TempDir, DirectoryArtifactStore) {
        store_with_artifact(grant_value, "day.json", APPLE)
    }

    #[allow(clippy::needless_pass_by_value)]
    fn store_with_artifact(
        grant_value: Value,
        file_name: &str,
        contents: &str,
    ) -> (TempDir, DirectoryArtifactStore) {
        let temporary = TempDir::new().unwrap();
        let exports = temporary.path().join("exports");
        fs::create_dir(&exports).unwrap();
        let grant_path = temporary.path().join("grant.json");
        let index_path = temporary.path().join("index.json");
        write_file(&exports.join(file_name), contents);
        write_file(&grant_path, &serde_json::to_string(&grant_value).unwrap());
        let store = DirectoryArtifactStore::open(DataServeOptions {
            directory: exports,
            grant: grant_path,
            index: Some(index_path),
        })
        .unwrap();
        (temporary, store)
    }

    fn context() -> CallContext {
        CallContext {
            caller: CallerIdentity::local_read_only(),
            cancellation: CancellationToken::new(),
            session_id: None,
            progress: None,
        }
    }

    #[tokio::test]
    async fn scoped_grant_catalog_and_records_expose_only_steps() {
        let (_temporary, store) = store(grant(
            json!({"type": "explicit", "metric_ids": ["healthmd.health_data#/activity/steps"]}),
            json!(["common"]),
            false,
        ));
        let catalog = store
            .query_page(&context(), query(json!({"type": "catalog"})))
            .await
            .unwrap();
        assert_eq!(catalog["items"].as_array().unwrap().len(), 1);
        assert_eq!(
            catalog["items"][0]["metric_id"],
            "healthmd.health_data#/activity/steps"
        );

        let records = store
            .query_page(
                &context(),
                query(json!({
                    "type": "records",
                    "metrics": {"type": "all_available"},
                    "sources": {"type": "all_available"},
                    "dates": {"type": "all_available"},
                    "times": {"type": "all_available"},
                    "detail_level": "common"
                })),
            )
            .await
            .unwrap();
        assert_eq!(records["items"].as_array().unwrap().len(), 1);
        assert_eq!(records["items"][0]["value"], 12345);
        assert!(
            !serde_json::to_string(&records)
                .unwrap()
                .contains("restingHeartRate")
        );
    }

    #[tokio::test]
    async fn lossless_records_are_independently_gated() {
        let (_temporary, store) = store(grant(
            json!({"type": "all_available"}),
            json!(["common"]),
            false,
        ));
        let records = store
            .query_page(
                &context(),
                query(json!({
                    "type": "records",
                    "metrics": {"type": "all_available"},
                    "sources": {"type": "all_available"},
                    "dates": {"type": "all_available"},
                    "times": {"type": "all_available"},
                    "detail_level": "lossless"
                })),
            )
            .await
            .unwrap();
        assert!(records["items"].as_array().unwrap().is_empty());
    }

    #[tokio::test]
    async fn exact_artifact_reads_require_broad_bulk_grant_and_preserve_bytes() {
        let (_temporary, store) = store(grant(
            json!({"type": "all_available"}),
            json!(["common", "lossless"]),
            true,
        ));
        let artifacts = store
            .query_page(&context(), query(json!({"type": "artifacts"})))
            .await
            .unwrap();
        let artifact_id = artifacts["items"][0]["artifact_id"].as_str().unwrap();
        let response = store
            .query_page(
                &context(),
                query(json!({"type": "artifact_read", "artifact_id": artifact_id})),
            )
            .await
            .unwrap();
        let decoded = URL_SAFE_NO_PAD
            .decode(response["items"][0]["data"].as_str().unwrap())
            .unwrap();
        assert_eq!(decoded, APPLE.as_bytes());
    }

    #[tokio::test]
    async fn shared_backend_adapter_accepts_the_data_contract() {
        let (_temporary, store) = store(grant(
            json!({"type": "all_available"}),
            json!(["common"]),
            false,
        ));
        let backend = ArtifactStoreBackend::new(Arc::new(store));
        let result = backend
            .query_page(
                &context(),
                QueryPageRequest {
                    query: serde_json::to_value(query(json!({"type": "catalog"}))).unwrap(),
                    detail_level: QueryDetailLevel::Summary,
                },
            )
            .await
            .unwrap();
        assert_eq!(result["schema"], AGENT_QUERY_RESPONSE_SCHEMA);
    }

    #[tokio::test]
    async fn production_api_v2_fixture_retains_provider_sidecars_as_lossless_records() {
        let (_temporary, store) = store_with_artifact(
            grant(
                json!({"type": "all_available"}),
                json!(["common", "lossless"]),
                false,
            ),
            "api.json",
            APPLE_API_V2,
        );
        let catalog = store
            .query_page(&context(), query(json!({"type": "catalog"})))
            .await
            .unwrap();
        assert!(catalog["items"].as_array().unwrap().iter().any(|item| {
            item["source_id"] == "provider:whoop" && item["detail_level"] == "lossless"
        }));
    }

    #[tokio::test]
    async fn production_android_empty_snapshot_remains_an_exact_lossless_artifact() {
        let (_temporary, store) = store_with_artifact(
            grant(
                json!({"type": "all_available"}),
                json!(["common", "lossless"]),
                true,
            ),
            "snapshot.json",
            ANDROID_RAW_SNAPSHOT,
        );
        let artifacts = store
            .query_page(&context(), query(json!({"type": "artifacts"})))
            .await
            .unwrap();
        assert_eq!(artifacts["items"].as_array().unwrap().len(), 1);
        assert_eq!(artifacts["items"][0]["detail_levels"], json!(["lossless"]));

        let artifact_id = artifacts["items"][0]["artifact_id"].as_str().unwrap();
        let response = store
            .query_page(
                &context(),
                query(json!({"type": "artifact_read", "artifact_id": artifact_id})),
            )
            .await
            .unwrap();
        let decoded = URL_SAFE_NO_PAD
            .decode(response["items"][0]["data"].as_str().unwrap())
            .unwrap();
        assert_eq!(decoded, ANDROID_RAW_SNAPSHOT.as_bytes());
    }
}
