use std::{
    fs::{self, File},
    io::{self, Write as _},
    path::{Path, PathBuf},
};

use chrono::{DateTime, Utc};
use fs2::FileExt as _;
use healthmd_protocol::{
    transfer::is_sha256,
    v2::{self, ExportProduct},
};
use serde::{Deserialize, Serialize};
use tempfile::NamedTempFile;
use uuid::Uuid;

use crate::{
    ClientError,
    job::{JobExecutionGuard, JobState},
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
            self.request.destination.is_some()
                && self
                    .destination_root
                    .as_ref()
                    .is_some_and(|path| !path.is_empty())
        } else {
            self.request.destination.is_none() && self.destination_root.is_none()
        };
        let response_valid = self.response_artifact.as_ref().is_none_or(|artifact| {
            !artifact.path.is_empty()
                && is_sha256(&artifact.sha256)
                && artifact.product_id == self.request.product.product_id()
                && !artifact.status.is_empty()
        });
        if self.version != JOB_VERSION
            || self.request.job_id.is_nil()
            || self.request.source_installation_id.is_nil()
            || self.request.created_at >= self.request.expires_at
            || self.updated_at < self.request.created_at
            || !destination_valid
            || !response_valid
        {
            return Err(ClientError::InvalidJob);
        }
        Ok(())
    }
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
        create_private_directory(&directory)?;
        let lock = self.lock(record.request.job_id, true)?;
        lock.lock_exclusive().map_err(storage_error)?;
        let bytes = healthmd_protocol::encoding::canonical_json(record)
            .map_err(|_| ClientError::InvalidJob)?;
        let result = atomic_private_replace(&directory.join("record.json"), &bytes);
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
        atomic_private_replace(&self.cancellation_path(job_id), b"cancel\n")
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
        let bytes =
            fs::read(self.job_directory(job_id).join("record.json")).map_err(storage_error)?;
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
    fs::create_dir_all(path).map_err(storage_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(storage_error)?;
    }
    Ok(())
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
