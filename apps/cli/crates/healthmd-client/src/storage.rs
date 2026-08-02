use std::{
    env, fs,
    io::{self, Write},
    path::{Path, PathBuf},
};

use chrono::{DateTime, Timelike as _, Utc};
use directories::BaseDirs;
use healthmd_protocol::encoding::SwiftUuid;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    ClientError,
    limits::{prepare_private_directory, reserve_private_storage},
};

const IDENTITY_VERSION: u16 = 1;
const DATA_DIR_ENV: &str = "HEALTHMD_CLI_DATA_DIR";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StorageLayout {
    pub root: PathBuf,
}

impl StorageLayout {
    /// Resolve the per-user data root, honoring `HEALTHMD_CLI_DATA_DIR` for isolation.
    ///
    /// # Errors
    ///
    /// Returns an error if the operating system does not expose a per-user data directory.
    pub fn discover() -> Result<Self, ClientError> {
        if let Some(path) = env::var_os(DATA_DIR_ENV).filter(|value| !value.is_empty()) {
            return Ok(Self { root: path.into() });
        }
        let base = BaseDirs::new().ok_or_else(|| {
            ClientError::Storage("the operating system has no user data directory".into())
        })?;
        Ok(Self {
            root: base
                .data_local_dir()
                .join("Health.md")
                .join("CLI")
                .join("Direct")
                .join("v1"),
        })
    }

    #[must_use]
    pub fn identity_path(&self) -> PathBuf {
        self.root.join("identity.json")
    }

    #[must_use]
    pub fn jobs_dir(&self) -> PathBuf {
        self.root.join("jobs")
    }

    #[must_use]
    pub fn corpus_sessions_dir(&self) -> PathBuf {
        self.root.join("corpus-sessions")
    }

    #[must_use]
    pub fn response_spools_dir(&self) -> PathBuf {
        self.root.join("response-spools")
    }

    #[must_use]
    pub fn v2_jobs_dir(&self) -> PathBuf {
        self.root.join("jobs-v2")
    }

    #[must_use]
    pub fn v2_artifact_spools_dir(&self) -> PathBuf {
        self.root.join("artifact-spools-v2")
    }

    #[must_use]
    pub fn v2_response_spools_dir(&self) -> PathBuf {
        self.root.join("response-spools-v2")
    }

    /// Create the private durable-state directory hierarchy.
    ///
    /// # Errors
    ///
    /// Returns an error when a directory cannot be created or restricted.
    pub fn prepare(&self) -> Result<(), ClientError> {
        for path in [
            &self.root,
            &self.jobs_dir(),
            &self.corpus_sessions_dir(),
            &self.response_spools_dir(),
            &self.v2_jobs_dir(),
            &self.v2_artifact_spools_dir(),
            &self.v2_response_spools_dir(),
        ] {
            create_private_directory(path)?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientIdentity {
    pub version: u16,
    #[serde(rename = "installationID")]
    pub installation_id: SwiftUuid,
    #[serde(with = "healthmd_protocol::time")]
    pub created_at: DateTime<Utc>,
}

impl ClientIdentity {
    #[must_use]
    pub fn new(now: DateTime<Utc>) -> Self {
        Self {
            version: IDENTITY_VERSION,
            installation_id: SwiftUuid(Uuid::new_v4()),
            created_at: now.with_nanosecond(0).unwrap_or(now),
        }
    }

    fn validate(&self) -> Result<(), ClientError> {
        if self.version != IDENTITY_VERSION || self.installation_id.0.is_nil() {
            return Err(ClientError::InvalidIdentity);
        }
        Ok(())
    }
}

pub struct IdentityStore {
    layout: StorageLayout,
}

impl IdentityStore {
    #[must_use]
    pub const fn new(layout: StorageLayout) -> Self {
        Self { layout }
    }

    /// Load the durable installation identity or atomically create it once.
    ///
    /// # Errors
    ///
    /// Returns an error for corrupt identity data or inaccessible storage.
    pub fn load_or_create(&self, now: DateTime<Utc>) -> Result<ClientIdentity, ClientError> {
        self.layout.prepare()?;
        let path = self.layout.identity_path();
        if path.exists() {
            return load_identity(&path);
        }

        let identity = ClientIdentity::new(now);
        let bytes = serde_json::to_vec(&identity).map_err(|error| storage_error(error.into()))?;
        let _reservation = reserve_private_storage(
            &self.layout.root,
            path.parent()
                .ok_or_else(|| ClientError::Storage("identity path has no parent".into()))?,
            u64::try_from(bytes.len()).unwrap_or(u64::MAX),
        )?;
        if atomic_private_write_new(&path, &bytes)? {
            Ok(identity)
        } else {
            load_identity(&path)
        }
    }
}

fn create_private_directory(path: &Path) -> Result<(), ClientError> {
    prepare_private_directory(path)
}

fn load_identity(path: &Path) -> Result<ClientIdentity, ClientError> {
    let bytes = fs::read(path).map_err(storage_error)?;
    let identity: ClientIdentity =
        serde_json::from_slice(&bytes).map_err(|_| ClientError::InvalidIdentity)?;
    identity.validate()?;
    Ok(identity)
}

fn atomic_private_write_new(path: &Path, bytes: &[u8]) -> Result<bool, ClientError> {
    let parent = path
        .parent()
        .ok_or_else(|| ClientError::Storage("identity path has no parent".into()))?;
    let temporary = parent.join(format!(".identity.{}.tmp", Uuid::new_v4()));

    let result = (|| -> io::Result<bool> {
        let mut options = fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt as _;
            options.mode(0o600);
        }
        let mut file = options.open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        match fs::hard_link(&temporary, path) {
            Ok(()) => {
                fs::remove_file(&temporary)?;
                sync_directory(parent)?;
                Ok(true)
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                fs::remove_file(&temporary)?;
                Ok(false)
            }
            Err(error) => Err(error),
        }
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result.map_err(storage_error)
}

#[cfg(unix)]
fn sync_directory(path: &Path) -> io::Result<()> {
    fs::File::open(path)?.sync_all()
}

#[cfg(windows)]
#[allow(clippy::unnecessary_wraps)]
fn sync_directory(_path: &Path) -> io::Result<()> {
    Ok(())
}

#[allow(clippy::needless_pass_by_value)]
fn storage_error(error: io::Error) -> ClientError {
    ClientError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn identity_is_stable_across_loads() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("data"),
        };
        let store = IdentityStore::new(layout);
        let now = "2026-07-24T10:11:12Z".parse().unwrap();

        let first = store.load_or_create(now).unwrap();
        let second = store.load_or_create(Utc::now()).unwrap();
        assert_eq!(first, second);
    }

    #[test]
    fn concurrent_creation_converges_on_one_identity() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("data"),
        };
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let layout = layout.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    IdentityStore::new(layout)
                        .load_or_create(Utc::now())
                        .unwrap()
                })
            })
            .collect();
        let identities: Vec<_> = handles
            .into_iter()
            .map(|handle| handle.join().unwrap())
            .collect();
        assert!(identities.iter().all(|identity| identity == &identities[0]));
    }

    #[test]
    fn corrupt_identity_fails_closed() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("data"),
        };
        layout.prepare().unwrap();
        fs::write(layout.identity_path(), b"not json").unwrap();

        let error = IdentityStore::new(layout)
            .load_or_create(Utc::now())
            .unwrap_err();
        assert!(matches!(error, ClientError::InvalidIdentity));
    }
}
