use std::{
    fs::{self, File},
    io::{self, Write as _},
    path::{Path, PathBuf},
};

use chrono::{DateTime, Duration, Utc};
use fs2::FileExt as _;
use healthmd_protocol::{
    JOB_LIFETIME_SECONDS,
    transfer::is_sha256,
    v2::{self, ExportProduct},
};
use serde::{Deserialize, Serialize};
use tempfile::NamedTempFile;
use uuid::Uuid;

use crate::{
    ClientError,
    job::{JobExecutionGuard, JobState},
    limits::{
        MAXIMUM_JOB_BYTES, MAXIMUM_JOB_RECORD_BYTES, MAXIMUM_PARTITIONS_PER_JOB,
        prepare_private_directory, read_bounded, reserve_new_job, reserve_private_storage,
    },
    storage::StorageLayout,
};

const JOB_VERSION: u16 = 2;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct V2ResponseArtifact {
    pub path: String,
    pub byte_count: u64,
    pub sha256: String,
    pub product_id: v2::ProductId,
    pub status: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct V2JobRecord {
    pub version: u16,
    pub request: v2::ExportRequest,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub destination_root: Option<String>,
    pub state: JobState,
    pub updated_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer_binding: Option<v2::PeerBinding>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<Uuid>,
    pub committed_partitions: u64,
    pub committed_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure: Option<v2::ExportFailure>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_artifact: Option<V2ResponseArtifact>,
}

impl V2JobRecord {
    #[must_use]
    pub fn new(request: v2::ExportRequest, destination_root: Option<String>) -> Self {
        Self {
            version: JOB_VERSION,
            updated_at: request.created_at,
            request,
            destination_root,
            state: JobState::Queued,
            peer_binding: None,
            session_id: None,
            committed_partitions: 0,
            committed_bytes: 0,
            message: None,
            failure: None,
            response_artifact: None,
        }
    }

    /// Validate durable Android direct-job invariants.
    ///
    /// # Errors
    ///
    /// Returns an error for inconsistent IDs, lifetime, destination, counters, or response data.
    pub fn validate(&self) -> Result<(), ClientError> {
        let generated = matches!(self.request.product, ExportProduct::GeneratedFilesV1 { .. });
        let destination_valid = if generated {
            self.request
                .destination
                .as_ref()
                .is_some_and(|destination| {
                    is_sha256(&destination.binding_sha256)
                        && !destination.display_name.is_empty()
                        && destination.display_name.len() <= 255
                        && !destination.display_name.contains('/')
                        && !destination.display_name.contains('\\')
                        && !destination.display_name.chars().any(char::is_control)
                })
                && self.destination_root.as_ref().is_some_and(|path| {
                    !path.is_empty() && path.len() <= 32_767 && !path.chars().any(char::is_control)
                })
        } else {
            self.request.destination.is_none() && self.destination_root.is_none()
        };
        let response_valid = self.response_artifact.as_ref().is_none_or(|artifact| {
            !artifact.path.is_empty()
                && artifact.path.len() <= 32_767
                && !artifact.path.chars().any(char::is_control)
                && artifact.byte_count <= MAXIMUM_JOB_BYTES
                && is_sha256(&artifact.sha256)
                && artifact.product_id == self.request.product.product_id()
                && safe_machine_code(&artifact.status)
        });
        let failure_valid = self.failure.as_ref().is_none_or(|failure| {
            failure
                .job_id
                .is_none_or(|job_id| job_id == self.request.job_id)
                && safe_durable_message(&failure.public_message)
                && failure.details.is_empty()
        });
        if self.version != JOB_VERSION
            || self.request.job_id.is_nil()
            || self.request.source_installation_id.is_nil()
            || self
                .request
                .created_at
                .checked_add_signed(Duration::seconds(JOB_LIFETIME_SECONDS))
                != Some(self.request.expires_at)
            || self.updated_at < self.request.created_at
            || self.committed_partitions > MAXIMUM_PARTITIONS_PER_JOB
            || self.committed_bytes > MAXIMUM_JOB_BYTES
            || self
                .message
                .as_deref()
                .is_some_and(|message| !safe_durable_message(message))
            || !failure_valid
            || !destination_valid
            || !response_valid
        {
            return Err(ClientError::InvalidJob);
        }
        Ok(())
    }
}

fn safe_durable_message(value: &str) -> bool {
    !value.is_empty() && value.len() <= 512 && !value.chars().any(char::is_control)
}

fn safe_machine_code(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
}

#[derive(Clone, Debug)]
pub struct V2JobStore {
    layout: StorageLayout,
}

impl V2JobStore {
    /// Open the Android v2 durable job store.
    ///
    /// # Errors
    ///
    /// Returns an error when private storage cannot be prepared.
    pub fn new(layout: StorageLayout) -> Result<Self, ClientError> {
        layout.prepare()?;
        Ok(Self { layout })
    }

    /// Atomically persist a validated job.
    ///
    /// # Errors
    ///
    /// Returns an error for invalid state or inaccessible storage.
    pub fn save(&self, record: &V2JobRecord) -> Result<(), ClientError> {
        record.validate()?;
        let directory = self.job_directory(record.request.job_id);
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
        let lock = self.lock(record.request.job_id, true)?;
        lock.lock_exclusive().map_err(storage_error)?;
        let result = atomic_private_replace(&path, &bytes);
        let _ = fs2::FileExt::unlock(&lock);
        result
    }

    /// Load an unexpired v2 job.
    ///
    /// # Errors
    ///
    /// Returns not-found, expired, invalid-job, or storage errors.
    pub fn load(&self, job_id: Uuid) -> Result<V2JobRecord, ClientError> {
        let path = self.job_directory(job_id).join("record.json");
        if !path.exists() {
            return Err(ClientError::JobNotFound);
        }
        let lock = self.lock(job_id, false)?;
        fs2::FileExt::lock_shared(&lock).map_err(storage_error)?;
        let result = self.load_unchecked(job_id);
        let _ = fs2::FileExt::unlock(&lock);
        let record = result?;
        if record.request.expires_at <= Utc::now() {
            let _ = self.cleanup(job_id);
            return Err(ClientError::JobExpired);
        }
        Ok(record)
    }

    /// Acquire the single process execution lease for a v2 job.
    ///
    /// # Errors
    ///
    /// Returns `JobBusy` or storage errors.
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

    /// Add a durable cancellation marker.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is unavailable or storage fails.
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

    /// Mark a v2 job cancelled and remove retained health-data spools.
    ///
    /// # Errors
    ///
    /// Returns an error when the job or durable record cannot be updated.
    pub fn mark_cancelled(&self, job_id: Uuid) -> Result<(), ClientError> {
        let mut record = self.load(job_id)?;
        record.state = JobState::Cancelled;
        record.updated_at = Utc::now();
        record.message = Some("Android direct export was cancelled.".into());
        self.save(&record)?;
        self.clear_cancellation_request(job_id);
        let _ = fs::remove_dir_all(
            self.layout
                .v2_artifact_spools_dir()
                .join(job_id.to_string().to_lowercase()),
        );
        Ok(())
    }

    /// Remove expired v2 jobs and associated private artifacts.
    ///
    /// # Errors
    ///
    /// Returns an error if the jobs directory cannot be enumerated.
    pub fn remove_expired(&self, now: DateTime<Utc>) -> Result<Vec<Uuid>, ClientError> {
        let mut expired = Vec::new();
        for entry in fs::read_dir(self.layout.v2_jobs_dir()).map_err(storage_error)? {
            let entry = entry.map_err(storage_error)?;
            let Some(name) = entry.file_name().to_str().map(ToOwned::to_owned) else {
                continue;
            };
            let Ok(job_id) = Uuid::parse_str(&name) else {
                continue;
            };
            if self
                .load_unchecked(job_id)
                .is_ok_and(|record| record.request.expires_at <= now)
            {
                expired.push(job_id);
            }
        }
        expired.retain(|job_id| self.cleanup(*job_id));
        Ok(expired)
    }

    pub fn cleanup(&self, job_id: Uuid) -> bool {
        let execution_path = self.job_directory(job_id).join("execution.lock");
        let Ok(execution) = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(execution_path)
        else {
            return false;
        };
        if execution.try_lock_exclusive().is_err() {
            return false;
        }
        for directory in [
            self.job_directory(job_id),
            self.layout
                .v2_artifact_spools_dir()
                .join(job_id.to_string().to_lowercase()),
            self.layout
                .v2_response_spools_dir()
                .join(job_id.to_string().to_lowercase()),
        ] {
            let _ = fs::remove_dir_all(directory);
        }
        true
    }

    fn load_unchecked(&self, job_id: Uuid) -> Result<V2JobRecord, ClientError> {
        let bytes = read_bounded(
            &self.job_directory(job_id).join("record.json"),
            MAXIMUM_JOB_RECORD_BYTES,
            "durable v2 job record exceeds its metadata limit",
        )
        .map_err(|error| {
            if matches!(error, ClientError::InvalidTransfer(_)) {
                ClientError::InvalidJob
            } else {
                error
            }
        })?;
        let record: V2JobRecord =
            serde_json::from_slice(&bytes).map_err(|_| ClientError::InvalidJob)?;
        record.validate()?;
        if record.request.job_id != job_id {
            return Err(ClientError::InvalidJob);
        }
        Ok(record)
    }

    fn job_directory(&self, job_id: Uuid) -> PathBuf {
        self.layout
            .v2_jobs_dir()
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
    use healthmd_protocol::v2::{
        DateSelection, ExportProduct, RawSnapshotFormat, RawSnapshotScope,
    };

    use super::*;

    fn request(created_at: DateTime<Utc>) -> v2::ExportRequest {
        v2::ExportRequest {
            job_id: Uuid::new_v4(),
            created_at,
            expires_at: created_at + Duration::seconds(JOB_LIFETIME_SECONDS),
            source_installation_id: Uuid::new_v4(),
            date_selection: DateSelection::Exact {
                start_date: "2026-07-01".into(),
                end_date: "2026-07-01".into(),
            },
            product: ExportProduct::AndroidProviderNativeSnapshotV1 {
                provider_id: "health_connect".into(),
                format: RawSnapshotFormat::Json,
                scope: RawSnapshotScope::AllAuthorizedSupportedData,
                include_exercise_routes: false,
            },
            destination: None,
        }
    }

    #[test]
    fn android_durable_counters_and_messages_are_bounded() {
        let valid = V2JobRecord::new(request(Utc::now()), None);
        let mut excessive_partitions = valid.clone();
        excessive_partitions.committed_partitions = MAXIMUM_PARTITIONS_PER_JOB + 1;
        assert!(excessive_partitions.validate().is_err());
        let mut excessive_bytes = valid.clone();
        excessive_bytes.committed_bytes = MAXIMUM_JOB_BYTES + 1;
        assert!(excessive_bytes.validate().is_err());
        let mut unsafe_message = valid;
        unsafe_message.message = Some("private\nvalue".into());
        assert!(unsafe_message.validate().is_err());
    }

    #[test]
    fn android_job_requires_the_exact_seven_day_lifetime() {
        let now = Utc::now();
        let valid = V2JobRecord::new(request(now), None);
        assert!(valid.validate().is_ok());

        let mut too_long = valid.clone();
        too_long.request.expires_at += Duration::seconds(1);
        assert!(too_long.validate().is_err());

        let mut too_short = valid;
        too_short.request.expires_at -= Duration::seconds(1);
        assert!(too_short.validate().is_err());
    }
}
