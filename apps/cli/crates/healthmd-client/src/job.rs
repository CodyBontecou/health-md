use std::{
    fs::{self, File},
    io::{self, Write as _},
    path::{Path, PathBuf},
};

use chrono::{DateTime, Duration, Timelike as _, Utc};
use fs2::FileExt as _;
use healthmd_protocol::{
    JOB_LIFETIME_SECONDS,
    encoding::SwiftUuid,
    models::{ExportFailure, ExportRequest, PeerBinding, RequestFingerprint},
    time,
    transfer::is_sha256,
};
use serde::{Deserialize, Serialize};
use tempfile::NamedTempFile;
use uuid::Uuid;

use crate::{
    ClientError,
    limits::{
        MAXIMUM_DATES_PER_JOB, MAXIMUM_JOB_BYTES, MAXIMUM_JOB_RECORD_BYTES,
        MAXIMUM_PARTITIONS_PER_JOB, prepare_private_directory, read_bounded, reserve_new_job,
        reserve_private_storage,
    },
    storage::StorageLayout,
};

const JOB_VERSION: u16 = 1;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum JobState {
    Queued,
    Connecting,
    Sent,
    Accepted,
    Preparing,
    Transferring,
    Paused,
    AwaitingPeerAcknowledgement,
    CancellationPending,
    Completed,
    Failed,
    Cancelled,
}

impl JobState {
    #[must_use]
    pub const fn is_terminal(self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Cancelled)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ResponseArtifact {
    #[serde(rename = "relativePath")]
    pub relative_path: String,
    #[serde(rename = "byteCount")]
    pub byte_count: i64,
    pub sha256: String,
    #[serde(rename = "dateRangeStart")]
    pub date_range_start: String,
    #[serde(rename = "dateRangeEnd")]
    pub date_range_end: String,
    #[serde(rename = "totalDays")]
    pub total_days: i64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct JobRecord {
    pub version: u16,
    pub request: ExportRequest,
    #[serde(rename = "createdAt", with = "time")]
    pub created_at: DateTime<Utc>,
    #[serde(rename = "expiresAt", with = "time")]
    pub expires_at: DateTime<Utc>,
    #[serde(rename = "updatedAt", with = "time")]
    pub updated_at: DateTime<Utc>,
    pub state: JobState,
    #[serde(rename = "peerBinding", skip_serializing_if = "Option::is_none")]
    pub peer_binding: Option<PeerBinding>,
    #[serde(rename = "sessionID", skip_serializing_if = "Option::is_none")]
    pub session_id: Option<SwiftUuid>,
    #[serde(rename = "requestFingerprint", skip_serializing_if = "Option::is_none")]
    pub request_fingerprint: Option<RequestFingerprint>,
    #[serde(rename = "committedPartitions")]
    pub committed_partitions: i64,
    #[serde(rename = "committedBytes")]
    pub committed_bytes: i64,
    #[serde(rename = "processedDays")]
    pub processed_days: i64,
    #[serde(rename = "totalDays", skip_serializing_if = "Option::is_none")]
    pub total_days: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure: Option<ExportFailure>,
    #[serde(rename = "responseArtifact", skip_serializing_if = "Option::is_none")]
    pub response_artifact: Option<ResponseArtifact>,
}

impl JobRecord {
    #[must_use]
    pub fn new(mut request: ExportRequest) -> Self {
        request.created_at = request
            .created_at
            .with_nanosecond(0)
            .unwrap_or(request.created_at);
        let created_at = request.created_at;
        Self {
            version: JOB_VERSION,
            request,
            created_at,
            expires_at: created_at
                .checked_add_signed(Duration::seconds(JOB_LIFETIME_SECONDS))
                .unwrap_or(created_at),
            updated_at: created_at,
            state: JobState::Queued,
            peer_binding: None,
            session_id: None,
            request_fingerprint: None,
            committed_partitions: 0,
            committed_bytes: 0,
            processed_days: 0,
            total_days: None,
            message: None,
            failure: None,
            response_artifact: None,
        }
    }

    /// Validate the complete durable record before read or write.
    ///
    /// # Errors
    ///
    /// Returns an error for inconsistent versions, expiry, identifiers, counters, or artifacts.
    pub fn validate(&self) -> Result<(), ClientError> {
        let valid_artifact = self.response_artifact.as_ref().is_none_or(|artifact| {
            !artifact.relative_path.is_empty()
                && artifact.relative_path.len() <= 255
                && !artifact.relative_path.contains('/')
                && !artifact.relative_path.contains('\\')
                && artifact.byte_count >= 0
                && u64::try_from(artifact.byte_count).is_ok_and(|bytes| bytes <= MAXIMUM_JOB_BYTES)
                && artifact.total_days >= 0
                && usize::try_from(artifact.total_days)
                    .is_ok_and(|days| days <= MAXIMUM_DATES_PER_JOB)
                && is_sha256(&artifact.sha256)
        });
        let valid_failure = self.failure.as_ref().is_none_or(|failure| {
            failure
                .job_id
                .is_none_or(|job_id| job_id == self.request.job_id)
                && safe_durable_message(&failure.message)
        });
        if self.version != JOB_VERSION
            || self.request.job_id == self.session_id.unwrap_or(SwiftUuid(Uuid::nil()))
            || self.created_at != self.request.created_at
            || self
                .created_at
                .checked_add_signed(Duration::seconds(JOB_LIFETIME_SECONDS))
                != Some(self.expires_at)
            || self.updated_at < self.created_at
            || self.committed_partitions < 0
            || u64::try_from(self.committed_partitions)
                .map_or(true, |count| count > MAXIMUM_PARTITIONS_PER_JOB)
            || self.committed_bytes < 0
            || u64::try_from(self.committed_bytes).map_or(true, |bytes| bytes > MAXIMUM_JOB_BYTES)
            || self.processed_days < 0
            || usize::try_from(self.processed_days)
                .map_or(true, |days| days > MAXIMUM_DATES_PER_JOB)
            || self.total_days.is_some_and(|total| {
                total < self.processed_days
                    || usize::try_from(total).map_or(true, |days| days > MAXIMUM_DATES_PER_JOB)
            })
            || self
                .message
                .as_deref()
                .is_some_and(|message| !safe_durable_message(message))
            || !valid_failure
            || !valid_artifact
        {
            return Err(ClientError::InvalidJob);
        }
        Ok(())
    }
}

fn safe_durable_message(value: &str) -> bool {
    !value.is_empty() && value.len() <= 512 && !value.chars().any(char::is_control)
}

#[derive(Debug)]
pub struct JobExecutionGuard {
    pub(crate) _lock: File,
}

#[derive(Clone, Debug)]
pub struct JobStore {
    layout: StorageLayout,
}

impl JobStore {
    /// Open the job store and create its private directory hierarchy.
    ///
    /// # Errors
    ///
    /// Returns an error when private storage cannot be prepared.
    pub fn new(layout: StorageLayout) -> Result<Self, ClientError> {
        layout.prepare()?;
        Ok(Self { layout })
    }

    /// Atomically persist a validated job record with a per-job process lock.
    ///
    /// # Errors
    ///
    /// Returns an error for an invalid record or inaccessible storage.
    pub fn save(&self, record: &JobRecord) -> Result<(), ClientError> {
        record.validate()?;
        let directory = self.job_directory(record.request.job_id.0);
        let path = directory.join("record.json");
        let bytes = healthmd_protocol::encoding::canonical_json(record)
            .map_err(|_| ClientError::InvalidJob)?;
        let byte_count = u64::try_from(bytes.len()).unwrap_or(u64::MAX);
        if byte_count > MAXIMUM_JOB_RECORD_BYTES {
            return Err(ClientError::InvalidJob);
        }
        let _storage_reservation = if path.exists() {
            reserve_private_storage(&self.layout.root, &directory, byte_count)?
        } else {
            reserve_new_job(&self.layout.root, byte_count)?
        };
        create_private_directory(&directory)?;
        let lock = self.lock(record.request.job_id.0, true)?;
        lock.lock_exclusive().map_err(storage_error)?;
        let result = atomic_private_replace(&path, &bytes);
        let _ = fs2::FileExt::unlock(&lock);
        result
    }

    /// Load and validate an unexpired job.
    ///
    /// # Errors
    ///
    /// Returns `JobNotFound`, `JobExpired`, `InvalidJob`, or a storage error.
    pub fn load(&self, job_id: Uuid) -> Result<JobRecord, ClientError> {
        let path = self.job_directory(job_id).join("record.json");
        if !path.exists() {
            return Err(ClientError::JobNotFound);
        }
        let lock = self.lock(job_id, false)?;
        fs2::FileExt::lock_shared(&lock).map_err(storage_error)?;
        let result = self.load_unchecked(job_id);
        let _ = fs2::FileExt::unlock(&lock);
        let record = result?;
        if record.expires_at <= Utc::now() {
            self.cleanup(job_id);
            return Err(ClientError::JobExpired);
        }
        Ok(record)
    }

    /// List all structurally valid records, including expired records for cleanup.
    ///
    /// # Errors
    ///
    /// Returns an error if the job directory cannot be listed.
    pub fn all_records(&self) -> Result<Vec<JobRecord>, ClientError> {
        let directory = self.layout.jobs_dir();
        let mut records = Vec::new();
        for entry in fs::read_dir(directory).map_err(storage_error)? {
            let entry = entry.map_err(storage_error)?;
            let Some(name) = entry.file_name().to_str().map(ToOwned::to_owned) else {
                continue;
            };
            let Ok(job_id) = Uuid::parse_str(&name) else {
                continue;
            };
            if let Ok(record) = self.load_unchecked(job_id) {
                records.push(record);
            }
        }
        records.sort_by_key(|record| record.created_at);
        Ok(records)
    }

    /// Acquire the single cross-process execution lease for a nonterminal job.
    ///
    /// The lease is released when the returned guard is dropped. Status and cancellation markers
    /// remain available while an export process owns this lease.
    ///
    /// # Errors
    ///
    /// Returns `JobBusy` when another process is already executing this job, or a storage error.
    pub fn acquire_execution(&self, job_id: Uuid) -> Result<JobExecutionGuard, ClientError> {
        let _ = self.load(job_id)?;
        let lock = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.job_directory(job_id).join("execution.lock"))
            .map_err(storage_error)?;
        match lock.try_lock_exclusive() {
            Ok(()) => Ok(JobExecutionGuard { _lock: lock }),
            Err(error) if lock_is_contended(&error) => Err(ClientError::JobBusy(job_id)),
            Err(error) => Err(storage_error(error)),
        }
    }

    /// Create a durable cross-process cancellation marker.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is absent/expired or the marker cannot be written.
    pub fn request_cancellation(&self, job_id: Uuid) -> Result<(), ClientError> {
        let _ = self.load(job_id)?;
        let path = self.cancellation_path(job_id);
        let _reservation =
            reserve_private_storage(&self.layout.root, &self.job_directory(job_id), 7)?;
        atomic_private_replace(&path, b"cancel\n")
    }

    #[must_use]
    pub fn cancellation_requested(&self, job_id: Uuid) -> bool {
        self.cancellation_path(job_id).exists()
    }

    pub fn clear_cancellation_request(&self, job_id: Uuid) {
        let _ = fs::remove_file(self.cancellation_path(job_id));
    }

    /// Remove expired job, corpus, and response state.
    ///
    /// # Errors
    ///
    /// Returns an error only when the record directory cannot be enumerated.
    pub fn remove_expired(&self, now: DateTime<Utc>) -> Result<Vec<Uuid>, ClientError> {
        let expired: Vec<_> = self
            .all_records()?
            .into_iter()
            .filter(|record| record.expires_at <= now)
            .map(|record| record.request.job_id.0)
            .collect();
        for id in &expired {
            self.cleanup(*id);
        }
        Ok(expired)
    }

    fn load_unchecked(&self, job_id: Uuid) -> Result<JobRecord, ClientError> {
        let bytes = read_bounded(
            &self.job_directory(job_id).join("record.json"),
            MAXIMUM_JOB_RECORD_BYTES,
            "durable job record exceeds its metadata limit",
        )
        .map_err(|error| {
            if matches!(error, ClientError::InvalidTransfer(_)) {
                ClientError::InvalidJob
            } else {
                error
            }
        })?;
        let record: JobRecord =
            serde_json::from_slice(&bytes).map_err(|_| ClientError::InvalidJob)?;
        record.validate()?;
        if record.request.job_id.0 != job_id {
            return Err(ClientError::InvalidJob);
        }
        Ok(record)
    }

    fn cleanup(&self, job_id: Uuid) {
        let execution_path = self.job_directory(job_id).join("execution.lock");
        let Ok(execution_lock) = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(execution_path)
        else {
            return;
        };
        if execution_lock.try_lock_exclusive().is_err() {
            return;
        }
        let _ = fs2::FileExt::unlock(&execution_lock);
        drop(execution_lock);
        let id = job_id.to_string().to_lowercase();
        for path in [
            self.job_directory(job_id),
            self.layout.corpus_sessions_dir().join(&id),
            self.layout.response_spools_dir().join(&id),
        ] {
            let _ = fs::remove_dir_all(path);
        }
    }

    fn job_directory(&self, job_id: Uuid) -> PathBuf {
        self.layout
            .jobs_dir()
            .join(job_id.to_string().to_lowercase())
    }

    fn cancellation_path(&self, job_id: Uuid) -> PathBuf {
        self.job_directory(job_id).join("cancellation-requested")
    }

    fn lock(&self, job_id: Uuid, create_directory: bool) -> Result<File, ClientError> {
        let directory = self.job_directory(job_id);
        if create_directory {
            create_private_directory(&directory)?;
        }
        fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(directory.join(".lock"))
            .map_err(storage_error)
    }
}

fn create_private_directory(path: &Path) -> Result<(), ClientError> {
    prepare_private_directory(path)
}

fn atomic_private_replace(path: &Path, bytes: &[u8]) -> Result<(), ClientError> {
    let directory = path
        .parent()
        .ok_or_else(|| ClientError::Storage("durable path has no parent".into()))?;
    create_private_directory(directory)?;
    let mut temporary = NamedTempFile::new_in(directory).map_err(storage_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        temporary
            .as_file()
            .set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(storage_error)?;
    }
    temporary.write_all(bytes).map_err(storage_error)?;
    temporary.as_file().sync_all().map_err(storage_error)?;
    temporary
        .persist(path)
        .map_err(|error| storage_error(error.error))?;
    sync_directory(directory).map_err(storage_error)
}

#[cfg(unix)]
fn sync_directory(path: &Path) -> io::Result<()> {
    File::open(path)?.sync_all()
}

#[cfg(windows)]
#[allow(clippy::unnecessary_wraps)]
fn sync_directory(_path: &Path) -> io::Result<()> {
    Ok(())
}

fn lock_is_contended(error: &io::Error) -> bool {
    error.kind() == io::ErrorKind::WouldBlock
        || error.raw_os_error() == fs2::lock_contended_error().raw_os_error()
}

#[allow(clippy::needless_pass_by_value)]
fn storage_error(error: io::Error) -> ClientError {
    ClientError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use healthmd_protocol::{
        models::{DateSelection, ExactDateSelection, ResponseMode, SettingsPolicy},
        wire::RawProfile,
    };
    use tempfile::TempDir;

    use super::*;

    fn request(now: DateTime<Utc>) -> ExportRequest {
        ExportRequest {
            protocol_version: 1,
            job_id: SwiftUuid(Uuid::new_v4()),
            created_at: now,
            date_selection: DateSelection::Exact(ExactDateSelection {
                start: "2026-07-23".into(),
                end: "2026-07-23".into(),
            }),
            settings_policy: SettingsPolicy::RequestedDatesOnly,
            profile_reference: None,
            response_mode: ResponseMode::RawJson,
            raw_profile: Some(RawProfile::CanonicalSourceRecordsV1),
            canonical_selection: None,
            destination: None,
        }
    }

    #[test]
    fn job_round_trips_and_cancellation_is_durable() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let store = JobStore::new(layout).unwrap();
        let now = Utc::now();
        let record = JobRecord::new(request(now));
        let id = record.request.job_id.0;
        store.save(&record).unwrap();
        assert_eq!(store.load(id).unwrap(), record);
        let execution = store.acquire_execution(id).unwrap();
        assert!(matches!(
            store.acquire_execution(id),
            Err(ClientError::JobBusy(busy)) if busy == id
        ));
        drop(execution);
        drop(store.acquire_execution(id).unwrap());
        store.request_cancellation(id).unwrap();
        assert!(store.cancellation_requested(id));
        store.clear_cancellation_request(id);
        assert!(!store.cancellation_requested(id));
    }

    #[test]
    fn extreme_job_timestamps_fail_without_panicking() {
        let record = JobRecord::new(request(DateTime::<Utc>::MAX_UTC));
        assert!(record.validate().is_err());
    }

    #[test]
    fn durable_counters_and_messages_are_bounded() {
        let valid = JobRecord::new(request(Utc::now()));
        let mut excessive_partitions = valid.clone();
        excessive_partitions.committed_partitions =
            i64::try_from(MAXIMUM_PARTITIONS_PER_JOB + 1).unwrap();
        assert!(excessive_partitions.validate().is_err());
        let mut excessive_bytes = valid.clone();
        excessive_bytes.committed_bytes = i64::try_from(MAXIMUM_JOB_BYTES + 1).unwrap();
        assert!(excessive_bytes.validate().is_err());
        let mut excessive_days = valid.clone();
        excessive_days.processed_days = i64::try_from(MAXIMUM_DATES_PER_JOB + 1).unwrap();
        assert!(excessive_days.validate().is_err());
        let mut unsafe_message = valid;
        unsafe_message.message = Some("private\nvalue".into());
        assert!(unsafe_message.validate().is_err());
    }

    #[test]
    fn oversized_job_records_fail_before_write_or_decode() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let store = JobStore::new(layout).unwrap();
        let mut record = JobRecord::new(request(Utc::now()));
        record.message = Some("x".repeat(usize::try_from(MAXIMUM_JOB_RECORD_BYTES).unwrap()));
        assert!(matches!(store.save(&record), Err(ClientError::InvalidJob)));

        let id = record.request.job_id.0;
        let directory = store.job_directory(id);
        create_private_directory(&directory).unwrap();
        fs::write(
            directory.join("record.json"),
            vec![b'x'; usize::try_from(MAXIMUM_JOB_RECORD_BYTES + 1).unwrap()],
        )
        .unwrap();
        assert!(matches!(store.load(id), Err(ClientError::InvalidJob)));
    }

    #[test]
    fn expiration_cleanup_respects_active_execution_lease() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let store = JobStore::new(layout).unwrap();
        let record = JobRecord::new(request(Utc::now()));
        let id = record.request.job_id.0;
        store.save(&record).unwrap();
        let execution = store.acquire_execution(id).unwrap();
        store
            .remove_expired(record.expires_at + Duration::seconds(1))
            .unwrap();
        assert!(store.load(id).is_ok());
        drop(execution);
        store
            .remove_expired(record.expires_at + Duration::seconds(1))
            .unwrap();
        assert!(matches!(store.load(id), Err(ClientError::JobNotFound)));
    }

    #[test]
    fn expired_job_is_removed() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let store = JobStore::new(layout).unwrap();
        let record = JobRecord::new(request(Utc::now() - Duration::days(8)));
        let id = record.request.job_id.0;
        store.save(&record).unwrap();
        assert!(matches!(store.load(id), Err(ClientError::JobExpired)));
        assert!(matches!(store.load(id), Err(ClientError::JobNotFound)));
    }
}
