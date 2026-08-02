#![allow(
    clippy::case_sensitive_file_extension_comparisons,
    clippy::cast_possible_truncation,
    clippy::missing_errors_doc,
    clippy::too_many_lines,
    clippy::unnecessary_wraps,
    clippy::unused_self
)]

use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
};

use cap_fs_ext::{DirExt as _, FollowSymlinks, OpenOptionsFollowExt as _};
#[cfg(not(unix))]
use cap_std::ambient_authority;
#[cfg(unix)]
use cap_std::fs::PermissionsExt as _;
use cap_std::fs::{Dir, OpenOptions as CapOpenOptions, Permissions as CapPermissions};
use chacha20poly1305::{
    ChaCha20Poly1305, Key, Nonce,
    aead::{Aead, KeyInit, Payload},
};
use chrono::{DateTime, Duration, NaiveDate, Utc};
use fs2::FileExt as _;
use hkdf::Hkdf;
use secrecy::{ExposeSecret as _, SecretBox};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest as _, Sha256};
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::backend::CallerIdentity;

use super::models::{
    HostedConsentDetail, HostedConsentRequest, HostedConsentResult, HostedConsentRevocationRequest,
    HostedControlStatus, HostedError, HostedSyncRequest, HostedSyncResult, HostedSyncStatus,
    MAX_CONTEXT_DAY_BYTES, MAX_SYNC_DAYS, MAX_SYNC_REQUEST_BYTES,
};

const STORAGE_SCHEMA: &str = "healthmd.hosted_store";
const STORAGE_VERSION: u8 = 3;
const ANCHOR_SCHEMA: &str = "healthmd.hosted.generation-anchor";
const ANCHOR_VERSION: u8 = 1;
const FILE_MAGIC: &[u8; 6] = b"HMDH01";
const MAX_METRICS_PER_DAY: usize = 4_096;
const MAX_WORKOUTS_PER_DAY: usize = 4_096;
const MAX_SLEEP_SESSIONS_PER_DAY: usize = 4_096;
const MAX_EVIDENCE_PER_DAY: usize = 20_000;
const MAX_LIMITATIONS_PER_DAY: usize = 1_024;
const MAX_NESTED_ARRAY: usize = 20_000;
const MAX_OWNER_PARTITIONS_PER_SWEEP: usize = 100_000;
const ACCOUNT_DELETION_MARKER_SCHEMA: &str = "healthmd.hosted.account-deletion.v1";
const ATOMIC_TEMP_PREFIX: &str = ".healthmd-";
const ATOMIC_TEMP_RANDOM_BYTES: usize = 12;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct DayMetadata {
    pub(super) digest_sha256: String,
    pub(super) storage_sha256: String,
    pub(super) status: String,
    pub(super) size_bytes: u32,
    pub(super) object_filename: String,
    pub(super) interval_end: DateTime<Utc>,
    pub(super) synchronized_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Manifest {
    schema: String,
    schema_version: u8,
    storage_generation: u64,
    pub(super) dataset_revision: u64,
    pub(super) last_consent_revision: u64,
    pub(super) consent: Option<HostedConsentRequest>,
    pub(super) days: BTreeMap<String, DayMetadata>,
}

impl Default for Manifest {
    fn default() -> Self {
        Self {
            schema: STORAGE_SCHEMA.to_owned(),
            schema_version: STORAGE_VERSION,
            storage_generation: 0,
            dataset_revision: 0,
            last_consent_revision: 0,
            consent: None,
            days: BTreeMap::new(),
        }
    }
}

pub(super) struct OwnerCorpus {
    pub(super) partition: String,
    #[cfg(test)]
    pub(super) directory: PathBuf,
    #[cfg(test)]
    pub(super) blobs: PathBuf,
    pub(super) key: [u8; 32],
    kek: [u8; 32],
    anchor_key: [u8; 32],
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(super) enum AnchorState {
    Active,
    Deleted,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct GenerationAnchor {
    schema: String,
    schema_version: u8,
    partition: String,
    generation: u64,
    state: AnchorState,
    manifest_sha256: Option<String>,
}

/// Tenant-aware encrypted hosted snapshot store.
///
/// The root is trusted server configuration. Caller-controlled identity is converted to a keyed
/// 256-bit partition before any path is formed. The in-process gate gives each query an immutable
/// manifest revision while allowing concurrent query readers.
pub struct HostedDataStore {
    #[cfg(test)]
    root: PathBuf,
    root_dir: Dir,
    anchor_dir: Dir,
    master_key: SecretBox<[u8; 32]>,
    _process_lock: File,
    _anchor_lock: File,
    pub(super) gate: RwLock<()>,
}

impl HostedDataStore {
    /// Construct a store with a separately protected monotonic-generation anchor directory.
    /// The anchor directory must not be equal to, inside, or contain the ciphertext directory.
    pub fn new(
        root: impl Into<PathBuf>,
        anchor_root: impl Into<PathBuf>,
        master_key: [u8; 32],
    ) -> Result<Self, HostedError> {
        let root = root.into();
        let anchor_root = anchor_root.into();
        ensure_directory(&root)?;
        ensure_directory(&anchor_root)?;
        let canonical_root = fs::canonicalize(&root).map_err(|_| storage_error())?;
        let canonical_anchor = fs::canonicalize(&anchor_root).map_err(|_| storage_error())?;
        if canonical_root == canonical_anchor
            || canonical_root.starts_with(&canonical_anchor)
            || canonical_anchor.starts_with(&canonical_root)
        {
            return Err(storage_error());
        }
        let expected_root = fs::metadata(&canonical_root).map_err(|_| storage_error())?;
        let expected_anchor = fs::metadata(&canonical_anchor).map_err(|_| storage_error())?;
        let root_dir = open_retained_directory(&canonical_root).map_err(|_| storage_error())?;
        let anchor_dir = open_retained_directory(&canonical_anchor).map_err(|_| storage_error())?;
        let actual_root = root_dir
            .try_clone()
            .and_then(|value| value.into_std_file().metadata())
            .map_err(|_| storage_error())?;
        let actual_anchor = anchor_dir
            .try_clone()
            .and_then(|value| value.into_std_file().metadata())
            .map_err(|_| storage_error())?;
        if !same_file_identity(&expected_root, &actual_root)
            || !same_file_identity(&expected_anchor, &actual_anchor)
        {
            return Err(storage_error());
        }
        let process_lock = open_exclusive_lock(&root_dir, ".healthmd-hosted.lock")?;
        let anchor_lock = open_exclusive_lock(&anchor_dir, ".healthmd-hosted.lock")?;
        cleanup_atomic_temporaries_at(&anchor_dir, MAX_OWNER_PARTITIONS_PER_SWEEP)?;
        Ok(Self {
            #[cfg(test)]
            root: canonical_root,
            root_dir,
            anchor_dir,
            master_key: SecretBox::new(Box::new(master_key)),
            _process_lock: process_lock,
            _anchor_lock: anchor_lock,
            gate: RwLock::new(()),
        })
    }

    #[cfg(test)]
    pub(crate) fn new_test(
        base: impl AsRef<Path>,
        master_key: [u8; 32],
    ) -> Result<Self, HostedError> {
        Self::new(
            base.as_ref().join("ciphertext"),
            base.as_ref().join("generation-anchors"),
            master_key,
        )
    }

    /// Install a newer consent revision, or verify an exact replay, for exactly this caller.
    pub async fn set_consent(
        &self,
        caller: &CallerIdentity,
        request: HostedConsentRequest,
    ) -> Result<HostedConsentResult, HostedError> {
        validate_consent(&request)?;
        let mut owner = self.owner(caller)?;
        let _guard = self.gate.write().await;
        self.prepare_owner(&owner)?;
        self.load_or_create_data_key(&mut owner)?;
        let mut manifest = self.read_manifest(&owner)?;
        self.delete_unreferenced_objects(&owner, &manifest)?;
        let commit_time = Utc::now();
        if request
            .expires_at
            .is_some_and(|expiration| expiration <= commit_time)
        {
            return Err(error(
                "healthmd_consent_invalid",
                "The hosted consent policy is invalid.",
            ));
        }
        if request.revision == manifest.last_consent_revision
            && manifest.consent.as_ref() == Some(&request)
        {
            let synchronized_before = manifest.days.len();
            self.enforce_retention_policy(&owner, &mut manifest, commit_time)?;
            let purged_day_count = synchronized_before.saturating_sub(manifest.days.len());
            return Ok(HostedConsentResult {
                schema: "healthmd.hosted_consent_result",
                schema_version: 1,
                consent_revision: request.revision,
                dataset_revision: manifest.dataset_revision,
                consent_state: "active",
                synchronized_day_count: manifest.days.len(),
                purged_day_count,
            });
        }
        let expected_revision = manifest
            .last_consent_revision
            .checked_add(1)
            .ok_or_else(consent_revision_stale)?;
        if request.revision != expected_revision {
            return Err(consent_revision_stale());
        }

        let removed: Vec<String> = manifest
            .days
            .values()
            .map(|metadata| metadata.object_filename.clone())
            .collect();
        manifest.days.clear();
        manifest.last_consent_revision = request.revision;
        manifest.consent = Some(request.clone());
        manifest.dataset_revision = next_revision(manifest.dataset_revision)?;
        self.rotate_data_key_and_write_manifest(&mut owner, &mut manifest)?;
        self.delete_objects(&owner, &removed)?;

        Ok(HostedConsentResult {
            schema: "healthmd.hosted_consent_result",
            schema_version: 1,
            consent_revision: request.revision,
            dataset_revision: manifest.dataset_revision,
            consent_state: "active",
            synchronized_day_count: manifest.days.len(),
            purged_day_count: removed.len(),
        })
    }

    /// Alias used by hosted route adapters that model consent updates as replacement.
    pub async fn replace_consent(
        &self,
        caller: &CallerIdentity,
        request: HostedConsentRequest,
    ) -> Result<HostedConsentResult, HostedError> {
        self.set_consent(caller, request).await
    }

    /// Revoke consent and purge all owner snapshots.
    pub async fn revoke_consent(
        &self,
        caller: &CallerIdentity,
        request: HostedConsentRevocationRequest,
    ) -> Result<HostedConsentResult, HostedError> {
        let mut owner = self.owner(caller)?;
        let _guard = self.gate.write().await;
        self.prepare_owner(&owner)?;
        self.load_or_create_data_key(&mut owner)?;
        let mut manifest = self.read_manifest(&owner)?;
        self.delete_unreferenced_objects(&owner, &manifest)?;
        let expected_revision = manifest
            .last_consent_revision
            .checked_add(1)
            .ok_or_else(consent_revision_stale)?;
        if manifest.consent.as_ref().map(|value| value.revision) != Some(request.expected_revision)
            || request.expected_revision != manifest.last_consent_revision
            || request.revision != expected_revision
        {
            return Err(consent_revision_stale());
        }
        let removed: Vec<String> = manifest
            .days
            .values()
            .map(|metadata| metadata.object_filename.clone())
            .collect();
        manifest.days.clear();
        manifest.consent = None;
        manifest.last_consent_revision = request.revision;
        manifest.dataset_revision = next_revision(manifest.dataset_revision)?;
        self.rotate_data_key_and_write_manifest(&mut owner, &mut manifest)?;
        self.delete_objects(&owner, &removed)?;
        Ok(HostedConsentResult {
            schema: "healthmd.hosted_consent_result",
            schema_version: 1,
            consent_revision: request.revision,
            dataset_revision: manifest.dataset_revision,
            consent_state: "revoked",
            synchronized_day_count: 0,
            purged_day_count: removed.len(),
        })
    }

    /// Verify and atomically apply up to 31 compact owner-day replacements.
    pub async fn synchronize(
        &self,
        caller: &CallerIdentity,
        request: HostedSyncRequest,
    ) -> Result<HostedSyncResult, HostedError> {
        validate_sync_request_shape(&request)?;
        let mut owner = self.owner(caller)?;
        let _guard = self.gate.write().await;
        self.prepare_owner(&owner)?;
        self.load_or_create_data_key(&mut owner)?;
        let mut manifest = self.read_manifest(&owner)?;
        self.delete_unreferenced_objects(&owner, &manifest)?;
        let now = Utc::now();

        let consent = manifest.consent.clone().ok_or_else(|| {
            error(
                "healthmd_consent_required",
                "Active server-side consent is required before synchronization.",
            )
        })?;
        if consent.revision != request.expected_consent_revision {
            return Err(error(
                "healthmd_consent_revision_stale",
                "The upload consent revision does not match the stored revision.",
            ));
        }
        if consent
            .expires_at
            .is_some_and(|expiration| expiration <= now)
        {
            let removed = self.purge_for_policy(&owner, &mut manifest, Some(&consent), now)?;
            if !removed.is_empty() {
                manifest.dataset_revision = next_revision(manifest.dataset_revision)?;
                self.write_manifest(&owner, &mut manifest)?;
                self.delete_objects(&owner, &removed)?;
            }
            return Err(error(
                "healthmd_consent_expired",
                "Server-side consent has expired.",
            ));
        }

        let mut validated = Vec::with_capacity(request.days.len());
        let mut owner_dates = BTreeSet::new();
        for upload in &request.days {
            let canonical = canonical_json_bytes(&upload.day)?;
            if canonical.len() > MAX_CONTEXT_DAY_BYTES {
                return Err(error(
                    "healthmd_sync_day_too_large",
                    "A synchronized day exceeds the per-day byte limit.",
                ));
            }
            let digest = semantic_json_digest(&upload.day)?;
            if !constant_time_eq(digest.as_bytes(), upload.digest_sha256.as_bytes()) {
                return Err(error(
                    "healthmd_sync_digest_mismatch",
                    "A synchronized day digest did not match the semantic JSON document.",
                ));
            }
            let owner_date = validate_context_day(&upload.day, &consent, now)?;
            let interval_end = parse_timestamp(upload.day.get("interval_end"))?;
            let cutoff = now - Duration::days(i64::from(consent.retention_days));
            if interval_end <= cutoff || interval_end > now + Duration::minutes(5) {
                return Err(error(
                    "healthmd_consent_violation",
                    "Synchronized data is outside the active retention policy.",
                ));
            }
            if !owner_dates.insert(owner_date.clone()) {
                return Err(error(
                    "healthmd_sync_invalid",
                    "The synchronization request contains duplicate owner days.",
                ));
            }
            validated.push((owner_date, interval_end, canonical, digest));
        }

        let removed_by_retention =
            self.purge_for_policy(&owner, &mut manifest, Some(&consent), now)?;
        let mut old_objects = removed_by_retention.clone();
        let mut changed = 0;
        let mut unchanged = 0;
        for (owner_date, interval_end, canonical, digest) in validated {
            if manifest
                .days
                .get(&owner_date)
                .is_some_and(|metadata| metadata.digest_sha256 == digest)
            {
                unchanged += 1;
                continue;
            }
            let filename = format!("{}.day", Uuid::new_v4().simple());
            self.write_day_bytes(&owner, &filename, &canonical)?;
            if let Some(previous) = manifest.days.insert(
                owner_date,
                DayMetadata {
                    digest_sha256: digest,
                    storage_sha256: sha256_hex(&canonical),
                    status: status_of_day_bytes(&canonical)?,
                    size_bytes: u32::try_from(canonical.len()).map_err(|_| internal_error())?,
                    object_filename: filename,
                    interval_end,
                    synchronized_at: now,
                },
            ) {
                old_objects.push(previous.object_filename);
            }
            changed += 1;
        }

        if changed > 0 || !removed_by_retention.is_empty() {
            manifest.dataset_revision = next_revision(manifest.dataset_revision)?;
            self.write_manifest(&owner, &mut manifest)?;
            self.delete_objects(&owner, &old_objects)?;
        }
        Ok(HostedSyncResult {
            schema: "healthmd.hosted_sync_result",
            schema_version: 1,
            consent_revision: consent.revision,
            dataset_revision: manifest.dataset_revision,
            changed_day_count: changed,
            unchanged_day_count: unchanged,
            purged_day_count: removed_by_retention.len(),
        })
    }

    /// Route-friendly alias for [`Self::synchronize`].
    pub async fn upload_days(
        &self,
        caller: &CallerIdentity,
        request: HostedSyncRequest,
    ) -> Result<HostedSyncResult, HostedError> {
        self.synchronize(caller, request).await
    }

    /// Route-friendly alias for [`Self::revoke_consent`].
    pub async fn purge_consent(
        &self,
        caller: &CallerIdentity,
        request: HostedConsentRevocationRequest,
    ) -> Result<HostedConsentResult, HostedError> {
        self.revoke_consent(caller, request).await
    }

    /// Return owner-only bounded synchronization metadata.
    pub async fn status(&self, caller: &CallerIdentity) -> Result<HostedSyncStatus, HostedError> {
        let mut owner = self.owner(caller)?;
        let _guard = self.gate.write().await;
        self.load_existing_data_key(&mut owner)?;
        let mut manifest = self.read_manifest(&owner)?;
        if owner.key != [0_u8; 32] {
            let now = Utc::now();
            self.enforce_retention_policy(&owner, &mut manifest, now)?;
            return Ok(status_from_manifest(&manifest, now, &owner_binding(&owner)));
        }
        Ok(status_from_manifest(
            &manifest,
            Utc::now(),
            &owner_binding(&owner),
        ))
    }

    /// Return health-free owner binding and consent lifecycle state for a first-party sync client.
    pub async fn control_status(
        &self,
        caller: &CallerIdentity,
    ) -> Result<HostedControlStatus, HostedError> {
        let mut owner = self.owner(caller)?;
        let _guard = self.gate.write().await;
        self.load_existing_data_key(&mut owner)?;
        let mut manifest = self.read_manifest(&owner)?;
        if owner.key != [0_u8; 32] {
            self.enforce_retention_policy(&owner, &mut manifest, Utc::now())?;
        }
        Ok(control_status_from_manifest(
            &manifest,
            Utc::now(),
            &owner_binding(&owner),
        ))
    }

    /// Delete the complete keyed corpus partition, including encrypted consent and all key-bound
    /// ciphertext. A durable marker outside the corpus makes interruption recoverable: startup or
    /// the next owner operation completes the whole-directory deletion before serving data.
    /// Repeating deletion is safe.
    pub async fn delete_account(&self, caller: &CallerIdentity) -> Result<(), HostedError> {
        let owner = self.owner(caller)?;
        let _guard = self.gate.write().await;
        let _v1 = ensure_child_directory(&self.root_dir, "v1")?;
        let deletions = ensure_child_directory(&self.root_dir, "deletions")?;
        let anchor = self.deleted_anchor(&owner)?;
        self.write_generation_anchor(&owner, &anchor)?;
        let marker_body = format!("{ACCOUNT_DELETION_MARKER_SCHEMA}\n{}\n", owner.partition);
        atomic_write_at(&deletions, &owner.partition, marker_body.as_bytes())?;
        if !self.recover_account_deletion(&owner)? {
            return Err(storage_error());
        }
        Ok(())
    }

    pub(super) fn owner(&self, caller: &CallerIdentity) -> Result<OwnerCorpus, HostedError> {
        if caller.subject.trim().is_empty() {
            return Err(error(
                "healthmd_identity_invalid",
                "The authenticated caller identity is invalid.",
            ));
        }
        let issuer = caller
            .issuer
            .as_deref()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                error(
                    "healthmd_identity_invalid",
                    "The authenticated caller identity is invalid.",
                )
            })?;
        let mut identity = Vec::new();
        identity.extend_from_slice(b"healthmd-hosted-owner-v2\0");
        identity.extend_from_slice(&(issuer.len() as u64).to_be_bytes());
        identity.extend_from_slice(issuer.as_bytes());
        match &caller.tenant {
            Some(tenant) => {
                identity.push(1);
                identity.extend_from_slice(&(tenant.len() as u64).to_be_bytes());
                identity.extend_from_slice(tenant.as_bytes());
            }
            None => identity.push(0),
        }
        identity.extend_from_slice(&(caller.subject.len() as u64).to_be_bytes());
        identity.extend_from_slice(caller.subject.as_bytes());
        let hkdf = Hkdf::<Sha256>::new(
            Some(b"healthmd-hosted-partition-v1"),
            self.master_key.expose_secret(),
        );
        let mut partition_bytes = [0_u8; 32];
        hkdf.expand(&identity, &mut partition_bytes)
            .map_err(|_| internal_error())?;
        self.corpus_for_partition(hex(&partition_bytes))
    }

    fn corpus_for_partition(&self, partition: String) -> Result<OwnerCorpus, HostedError> {
        if partition.len() != 64
            || !partition
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        {
            return Err(corrupt_error());
        }
        let owner_hkdf =
            Hkdf::<Sha256>::new(Some(partition.as_bytes()), self.master_key.expose_secret());
        let mut kek = [0_u8; 32];
        owner_hkdf
            .expand(b"healthmd-hosted-owner-key-encryption-v1", &mut kek)
            .map_err(|_| internal_error())?;
        let mut anchor_key = [0_u8; 32];
        owner_hkdf
            .expand(b"healthmd-hosted-generation-anchor-v1", &mut anchor_key)
            .map_err(|_| internal_error())?;
        #[cfg(test)]
        let directory = self.root.join("v1").join(&partition);
        Ok(OwnerCorpus {
            #[cfg(test)]
            blobs: directory.join("objects"),
            #[cfg(test)]
            directory,
            partition,
            key: [0_u8; 32],
            kek,
            anchor_key,
        })
    }

    fn read_generation_anchor(
        &self,
        owner: &OwnerCorpus,
    ) -> Result<Option<GenerationAnchor>, HostedError> {
        let Some(metadata) = metadata_at_if_present(&self.anchor_dir, &owner.partition)? else {
            return Ok(None);
        };
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(storage_error());
        }
        let encrypted = read_bounded_at(&self.anchor_dir, &owner.partition, 2_048)?;
        let plaintext = decrypt(
            &owner.anchor_key,
            generation_anchor_aad(owner).as_bytes(),
            &encrypted,
        )?;
        let anchor: GenerationAnchor =
            serde_json::from_slice(&plaintext).map_err(|_| corrupt_error())?;
        let valid_state = match anchor.state {
            AnchorState::Active => anchor.manifest_sha256.as_deref().is_some_and(valid_sha256),
            AnchorState::Deleted => anchor.manifest_sha256.is_none(),
        };
        if anchor.schema != ANCHOR_SCHEMA
            || anchor.schema_version != ANCHOR_VERSION
            || anchor.partition != owner.partition
            || anchor.generation == 0
            || !valid_state
        {
            return Err(corrupt_error());
        }
        Ok(Some(anchor))
    }

    pub(super) fn write_generation_anchor(
        &self,
        owner: &OwnerCorpus,
        anchor: &GenerationAnchor,
    ) -> Result<(), HostedError> {
        cleanup_atomic_temporaries_at(&self.anchor_dir, MAX_OWNER_PARTITIONS_PER_SWEEP)?;
        let plaintext = serde_json::to_vec(anchor).map_err(|_| internal_error())?;
        let encrypted = encrypt(
            &owner.anchor_key,
            generation_anchor_aad(owner).as_bytes(),
            &plaintext,
        )?;
        atomic_write_at(&self.anchor_dir, &owner.partition, &encrypted)
    }

    pub(super) fn deleted_anchor(
        &self,
        owner: &OwnerCorpus,
    ) -> Result<GenerationAnchor, HostedError> {
        let current = self.read_generation_anchor(owner)?;
        if let Some(anchor) = current
            .as_ref()
            .filter(|anchor| anchor.state == AnchorState::Deleted)
        {
            return Ok(anchor.clone());
        }
        let generation = current.map_or(Ok(1), |anchor| next_revision(anchor.generation))?;
        Ok(GenerationAnchor {
            schema: ANCHOR_SCHEMA.to_owned(),
            schema_version: ANCHOR_VERSION,
            partition: owner.partition.clone(),
            generation,
            state: AnchorState::Deleted,
            manifest_sha256: None,
        })
    }

    fn recover_account_deletion(&self, owner: &OwnerCorpus) -> Result<bool, HostedError> {
        let deletions = match self.root_dir.open_dir_nofollow("deletions") {
            Ok(directory) => Some(directory),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(_) => return Err(storage_error()),
        };
        let marker_metadata = deletions.as_ref().map_or(Ok(None), |directory| {
            metadata_at_if_present(directory, &owner.partition)
        })?;
        let anchor_deleted = self
            .read_generation_anchor(owner)?
            .is_some_and(|anchor| anchor.state == AnchorState::Deleted);
        if marker_metadata.is_none() && !anchor_deleted {
            return Ok(false);
        }
        if let (Some(marker_metadata), Some(deletions)) =
            (marker_metadata.as_ref(), deletions.as_ref())
        {
            if marker_metadata.file_type().is_symlink() || !marker_metadata.is_file() {
                return Err(storage_error());
            }
            let expected = format!("{ACCOUNT_DELETION_MARKER_SCHEMA}\n{}\n", owner.partition);
            if read_bounded_at(deletions, &owner.partition, 256)? != expected.as_bytes() {
                return Err(corrupt_error());
            }
        }
        if self.open_owner_directory(owner)?.is_some() {
            self.remove_owner_directory(owner)?;
            if let Ok(v1) = self.root_dir.open_dir_nofollow("v1") {
                sync_cap_directory(&v1)?;
            }
        }
        if marker_metadata.is_some() {
            let deletions = deletions.as_ref().ok_or_else(storage_error)?;
            remove_file_at(deletions, &owner.partition)?;
            sync_cap_directory(deletions)?;
        }
        Ok(true)
    }

    fn recover_pending_account_deletions(&self) -> Result<(), HostedError> {
        let directory = match self.root_dir.open_dir_nofollow("deletions") {
            Ok(directory) => directory,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(_) => return Err(storage_error()),
        };
        cleanup_atomic_temporaries_at(&directory, MAX_OWNER_PARTITIONS_PER_SWEEP)?;
        let entries = directory.entries().map_err(|_| storage_error())?;
        let mut count = 0_usize;
        for entry in entries {
            count = count.checked_add(1).ok_or_else(storage_error)?;
            if count > MAX_OWNER_PARTITIONS_PER_SWEEP {
                return Err(storage_error());
            }
            let entry = entry.map_err(|_| storage_error())?;
            let file_type = entry.file_type().map_err(|_| storage_error())?;
            if file_type.is_symlink() || !file_type.is_file() {
                return Err(storage_error());
            }
            let partition = entry
                .file_name()
                .into_string()
                .map_err(|_| corrupt_error())?;
            if is_atomic_temporary_filename(&partition) {
                directory
                    .remove_file(&partition)
                    .map_err(|_| storage_error())?;
                continue;
            }
            let owner = self.corpus_for_partition(partition)?;
            if !self.recover_account_deletion(&owner)? {
                return Err(storage_error());
            }
        }
        sync_cap_directory(&directory)
    }

    /// Enforce consent expiry and completed-day retention for every persisted owner partition.
    /// Deployments run this once before accepting traffic and on a bounded periodic schedule.
    pub async fn enforce_all_retention(&self) -> Result<u64, HostedError> {
        let _guard = self.gate.write().await;
        self.recover_pending_account_deletions()?;
        let root = match self.root_dir.open_dir_nofollow("v1") {
            Ok(directory) => directory,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(0),
            Err(_) => return Err(storage_error()),
        };
        let entries = root.entries().map_err(|_| storage_error())?;
        let mut count = 0_u64;
        for entry in entries {
            count = count.checked_add(1).ok_or_else(internal_error)?;
            if count as usize > MAX_OWNER_PARTITIONS_PER_SWEEP {
                return Err(storage_error());
            }
            let entry = entry.map_err(|_| storage_error())?;
            let file_type = entry.file_type().map_err(|_| storage_error())?;
            if file_type.is_symlink() || !file_type.is_dir() {
                return Err(storage_error());
            }
            let partition = entry
                .file_name()
                .into_string()
                .map_err(|_| corrupt_error())?;
            let mut owner = self.corpus_for_partition(partition)?;
            self.load_existing_data_key(&mut owner)?;
            let mut manifest = self.read_manifest(&owner)?;
            if owner.key == [0_u8; 32] {
                self.remove_owner_directory(&owner)?;
                sync_cap_directory(&root)?;
            } else {
                self.enforce_retention_policy(&owner, &mut manifest, Utc::now())?;
            }
        }
        Ok(count)
    }

    pub(super) fn load_existing_data_key(
        &self,
        owner: &mut OwnerCorpus,
    ) -> Result<(), HostedError> {
        if self.recover_account_deletion(owner)? {
            owner.key = [0_u8; 32];
            return Ok(());
        }
        self.recover_pending_key_rotation(owner)?;
        let Some(directory) = self.open_owner_directory(owner)? else {
            return Ok(());
        };
        if metadata_at_if_present(&directory, "owner-key.enc")?.is_none() {
            if metadata_at_if_present(&directory, "manifest.enc")?.is_some() {
                return Err(corrupt_error());
            }
            return Ok(());
        }
        let wrapped = read_bounded_at(&directory, "owner-key.enc", 256)?;
        let aad = format!("healthmd.hosted.owner_key/1/{}", owner.partition);
        let plaintext = decrypt(&owner.kek, aad.as_bytes(), &wrapped)?;
        owner.key = <[u8; 32]>::try_from(plaintext.as_slice()).map_err(|_| corrupt_error())?;
        Ok(())
    }

    fn recover_pending_key_rotation(&self, owner: &OwnerCorpus) -> Result<(), HostedError> {
        let anchor = self.read_generation_anchor(owner)?;
        let Some(directory) = self.open_owner_directory(owner)? else {
            return if anchor
                .as_ref()
                .is_some_and(|value| value.state == AnchorState::Active)
            {
                Err(corrupt_error())
            } else {
                Ok(())
            };
        };
        cleanup_atomic_temporaries_at(&directory, 64)?;
        let key_exists = metadata_at_if_present(&directory, "owner-key.next")?.is_some();
        let manifest_exists = metadata_at_if_present(&directory, "manifest.next")?.is_some();
        let current_digest = match metadata_at_if_present(&directory, "manifest.enc")? {
            Some(_) => Some(sha256_hex(&read_bounded_at(
                &directory,
                "manifest.enc",
                MAX_CONTEXT_DAY_BYTES + 128,
            )?)),
            None => None,
        };
        let anchor_matches_current = anchor.as_ref().is_some_and(|anchor| {
            anchor.state == AnchorState::Active
                && anchor.manifest_sha256.as_ref() == current_digest.as_ref()
        });

        if !manifest_exists {
            if key_exists {
                if !anchor_matches_current && anchor.is_some() {
                    return Err(corrupt_error());
                }
                remove_file_at(&directory, "owner-key.next")?;
                sync_cap_directory(&directory)?;
            }
            if anchor.as_ref().is_some_and(|anchor| {
                anchor.state == AnchorState::Active && !anchor_matches_current
            }) {
                return Err(corrupt_error());
            }
            return Ok(());
        }

        let encrypted_manifest =
            read_bounded_at(&directory, "manifest.next", MAX_CONTEXT_DAY_BYTES + 128)?;
        let next_digest = sha256_hex(&encrypted_manifest);
        let anchor_matches_next = anchor.as_ref().is_some_and(|anchor| {
            anchor.state == AnchorState::Active
                && anchor.manifest_sha256.as_deref() == Some(next_digest.as_str())
        });
        if anchor_matches_next {
            if key_exists {
                let wrapped_key = read_bounded_at(&directory, "owner-key.next", 256)?;
                atomic_write_at(&directory, "owner-key.enc", &wrapped_key)?;
            }
            atomic_write_at(&directory, "manifest.enc", &encrypted_manifest)?;
        } else if !anchor_matches_current && anchor.is_some() {
            return Err(corrupt_error());
        }
        remove_file_at(&directory, "manifest.next")?;
        if key_exists {
            remove_file_at(&directory, "owner-key.next")?;
        }
        sync_cap_directory(&directory)
    }

    fn load_or_create_data_key(&self, owner: &mut OwnerCorpus) -> Result<(), HostedError> {
        let owner_directory = self.open_owner_directory(owner)?;
        let recreating_deleted_owner = self
            .read_generation_anchor(owner)?
            .is_some_and(|anchor| anchor.state == AnchorState::Deleted)
            && owner_directory.as_ref().map_or(Ok(true), |directory| {
                Ok(
                    metadata_at_if_present(directory, "owner-key.enc")?.is_none()
                        && metadata_at_if_present(directory, "manifest.enc")?.is_none(),
                )
            })?;
        if !recreating_deleted_owner {
            self.load_existing_data_key(owner)?;
        }
        if owner.key != [0_u8; 32] {
            return Ok(());
        }
        let key: [u8; 32] = rand::random();
        let aad = format!("healthmd.hosted.owner_key/1/{}", owner.partition);
        let wrapped = encrypt(&owner.kek, aad.as_bytes(), &key)?;
        let directory = self
            .open_owner_directory(owner)?
            .ok_or_else(storage_error)?;
        atomic_write_at(&directory, "owner-key.enc", &wrapped)?;
        owner.key = key;
        Ok(())
    }

    fn rotate_data_key_and_write_manifest(
        &self,
        owner: &mut OwnerCorpus,
        manifest: &mut Manifest,
    ) -> Result<(), HostedError> {
        let generation = self.next_storage_generation(owner, manifest.storage_generation)?;
        manifest.storage_generation = generation;
        let key: [u8; 32] = rand::random();
        let key_aad = format!("healthmd.hosted.owner_key/1/{}", owner.partition);
        let wrapped_key = encrypt(&owner.kek, key_aad.as_bytes(), &key)?;
        let plaintext = serde_json::to_vec(manifest).map_err(|_| internal_error())?;
        let encrypted_manifest =
            encrypt(&key, manifest_aad(owner, generation).as_bytes(), &plaintext)?;
        let directory = self
            .open_owner_directory(owner)?
            .ok_or_else(storage_error)?;
        atomic_write_at(&directory, "owner-key.next", &wrapped_key)?;
        atomic_write_at(&directory, "manifest.next", &encrypted_manifest)?;
        self.write_active_anchor(owner, generation, &encrypted_manifest)?;
        atomic_write_at(&directory, "owner-key.enc", &wrapped_key)?;
        atomic_write_at(&directory, "manifest.enc", &encrypted_manifest)?;
        remove_file_at(&directory, "manifest.next")?;
        remove_file_at(&directory, "owner-key.next")?;
        sync_cap_directory(&directory)?;
        owner.key = key;
        Ok(())
    }

    fn next_storage_generation(
        &self,
        owner: &OwnerCorpus,
        manifest_generation: u64,
    ) -> Result<u64, HostedError> {
        let anchor = self.read_generation_anchor(owner)?;
        let anchored_generation = anchor.as_ref().map_or(0, |value| value.generation);
        if anchored_generation != manifest_generation {
            return Err(corrupt_error());
        }
        next_revision(anchored_generation)
    }

    fn write_active_anchor(
        &self,
        owner: &OwnerCorpus,
        generation: u64,
        encrypted_manifest: &[u8],
    ) -> Result<(), HostedError> {
        self.write_generation_anchor(
            owner,
            &GenerationAnchor {
                schema: ANCHOR_SCHEMA.to_owned(),
                schema_version: ANCHOR_VERSION,
                partition: owner.partition.clone(),
                generation,
                state: AnchorState::Active,
                manifest_sha256: Some(sha256_hex(encrypted_manifest)),
            },
        )
    }

    pub(super) fn read_manifest(&self, owner: &OwnerCorpus) -> Result<Manifest, HostedError> {
        let anchor = self.read_generation_anchor(owner)?;
        let directory = self.open_owner_directory(owner)?;
        if directory.as_ref().map_or(Ok(true), |value| {
            Ok(metadata_at_if_present(value, "manifest.enc")?.is_none())
        })? {
            return match anchor {
                Some(anchor) if anchor.state == AnchorState::Active => Err(corrupt_error()),
                Some(anchor) => Ok(Manifest {
                    storage_generation: anchor.generation,
                    ..Manifest::default()
                }),
                None => Ok(Manifest::default()),
            };
        }
        let anchor = anchor
            .filter(|value| value.state == AnchorState::Active)
            .ok_or_else(corrupt_error)?;
        let directory = directory.ok_or_else(corrupt_error)?;
        let bytes = read_bounded_at(&directory, "manifest.enc", MAX_CONTEXT_DAY_BYTES + 128)?;
        if anchor.manifest_sha256.as_deref() != Some(sha256_hex(&bytes).as_str()) {
            return Err(corrupt_error());
        }
        let plaintext = decrypt(
            &owner.key,
            manifest_aad(owner, anchor.generation).as_bytes(),
            &bytes,
        )?;
        let manifest: Manifest = serde_json::from_slice(&plaintext).map_err(|_| corrupt_error())?;
        if manifest.schema != STORAGE_SCHEMA
            || manifest.schema_version != STORAGE_VERSION
            || manifest.storage_generation != anchor.generation
            || manifest.dataset_revision < manifest.last_consent_revision
            || manifest
                .consent
                .as_ref()
                .is_some_and(|consent| consent.revision != manifest.last_consent_revision)
            || (!manifest.days.is_empty() && manifest.consent.is_none())
        {
            return Err(corrupt_error());
        }
        if let Some(consent) = manifest.consent.as_ref() {
            validate_consent_shape(consent).map_err(|_| corrupt_error())?;
        }
        if manifest.days.len() > 3_650 {
            return Err(corrupt_error());
        }
        let mut object_filenames = BTreeSet::new();
        for (owner_date, metadata) in &manifest.days {
            parse_owner_date(owner_date).map_err(|_| corrupt_error())?;
            validate_object_filename(&metadata.object_filename)?;
            if !object_filenames.insert(metadata.object_filename.as_str())
                || !valid_sha256(&metadata.digest_sha256)
                || !valid_sha256(&metadata.storage_sha256)
                || !valid_day_status(&metadata.status)
                || metadata.size_bytes == 0
                || metadata.size_bytes as usize > MAX_CONTEXT_DAY_BYTES
                || metadata.interval_end > metadata.synchronized_at + Duration::minutes(5)
                || metadata.synchronized_at > Utc::now() + Duration::minutes(5)
            {
                return Err(corrupt_error());
            }
        }
        Ok(manifest)
    }

    fn write_manifest(
        &self,
        owner: &OwnerCorpus,
        manifest: &mut Manifest,
    ) -> Result<(), HostedError> {
        let generation = self.next_storage_generation(owner, manifest.storage_generation)?;
        manifest.storage_generation = generation;
        let plaintext = serde_json::to_vec(manifest).map_err(|_| internal_error())?;
        let encrypted = encrypt(
            &owner.key,
            manifest_aad(owner, generation).as_bytes(),
            &plaintext,
        )?;
        let directory = self
            .open_owner_directory(owner)?
            .ok_or_else(storage_error)?;
        atomic_write_at(&directory, "manifest.next", &encrypted)?;
        self.write_active_anchor(owner, generation, &encrypted)?;
        atomic_write_at(&directory, "manifest.enc", &encrypted)?;
        remove_file_at(&directory, "manifest.next")?;
        sync_cap_directory(&directory)
    }

    pub(super) fn read_day(
        &self,
        owner: &OwnerCorpus,
        owner_date: &str,
        metadata: &DayMetadata,
        consent: &HostedConsentRequest,
    ) -> Result<Value, HostedError> {
        validate_object_filename(&metadata.object_filename)?;
        let directory = self.open_owner_blobs(owner)?.ok_or_else(corrupt_error)?;
        let ciphertext = read_bounded_at(
            &directory,
            &metadata.object_filename,
            MAX_CONTEXT_DAY_BYTES + 128,
        )?;
        let plaintext = decrypt(
            &owner.key,
            object_aad(owner, &metadata.object_filename).as_bytes(),
            &ciphertext,
        )?;
        if plaintext.len() != metadata.size_bytes as usize
            || sha256_hex(&plaintext) != metadata.storage_sha256
        {
            return Err(corrupt_error());
        }
        let day: Value = serde_json::from_slice(&plaintext).map_err(|_| corrupt_error())?;
        let validated_owner_date =
            validate_context_day(&day, consent, Utc::now()).map_err(|_| corrupt_error())?;
        let object = day.as_object().ok_or_else(corrupt_error)?;
        let interval_end =
            parse_timestamp(object.get("interval_end")).map_err(|_| corrupt_error())?;
        let status = object
            .get("status")
            .and_then(Value::as_str)
            .ok_or_else(corrupt_error)?;
        if validated_owner_date != owner_date
            || interval_end != metadata.interval_end
            || status != metadata.status
            || semantic_json_digest(&day).map_err(|_| corrupt_error())? != metadata.digest_sha256
        {
            return Err(corrupt_error());
        }
        Ok(day)
    }

    fn write_day_bytes(
        &self,
        owner: &OwnerCorpus,
        filename: &str,
        plaintext: &[u8],
    ) -> Result<(), HostedError> {
        validate_object_filename(filename)?;
        let encrypted = encrypt(
            &owner.key,
            object_aad(owner, filename).as_bytes(),
            plaintext,
        )?;
        let directory = self.open_owner_blobs(owner)?.ok_or_else(storage_error)?;
        atomic_write_at(&directory, filename, &encrypted)
    }

    fn open_owner_directory(&self, owner: &OwnerCorpus) -> Result<Option<Dir>, HostedError> {
        let v1 = match self.root_dir.open_dir_nofollow("v1") {
            Ok(directory) => directory,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(_) => return Err(storage_error()),
        };
        match v1.open_dir_nofollow(&owner.partition) {
            Ok(directory) => Ok(Some(directory)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(storage_error()),
        }
    }

    fn open_owner_blobs(&self, owner: &OwnerCorpus) -> Result<Option<Dir>, HostedError> {
        let Some(directory) = self.open_owner_directory(owner)? else {
            return Ok(None);
        };
        match directory.open_dir_nofollow("objects") {
            Ok(blobs) => Ok(Some(blobs)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(storage_error()),
        }
    }

    fn remove_owner_directory(&self, owner: &OwnerCorpus) -> Result<(), HostedError> {
        let Some(directory) = self.open_owner_directory(owner)? else {
            return Ok(());
        };
        directory.remove_open_dir_all().map_err(|_| storage_error())
    }

    fn delete_objects(&self, owner: &OwnerCorpus, filenames: &[String]) -> Result<(), HostedError> {
        let Some(directory) = self.open_owner_blobs(owner)? else {
            return filenames.is_empty().then_some(()).ok_or_else(storage_error);
        };
        for filename in filenames {
            validate_object_filename(filename)?;
            match directory.remove_file(filename) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(_) => return Err(storage_error()),
            }
        }
        directory
            .try_clone()
            .and_then(|value| value.into_std_file().sync_all())
            .map_err(|_| storage_error())
    }

    fn prepare_owner(&self, owner: &OwnerCorpus) -> Result<(), HostedError> {
        self.recover_account_deletion(owner)?;
        let v1 = ensure_child_directory(&self.root_dir, "v1")?;
        let directory = ensure_child_directory(&v1, &owner.partition)?;
        let _objects = ensure_child_directory(&directory, "objects")?;
        cleanup_atomic_temporaries_at(&directory, 64)?;
        Ok(())
    }

    pub(super) fn delete_unreferenced_objects(
        &self,
        owner: &OwnerCorpus,
        manifest: &Manifest,
    ) -> Result<(), HostedError> {
        let retained: BTreeSet<&str> = manifest
            .days
            .values()
            .map(|metadata| metadata.object_filename.as_str())
            .collect();
        let Some(directory) = self.open_owner_blobs(owner)? else {
            return Ok(());
        };
        for entry in directory.entries().map_err(|_| storage_error())? {
            let entry = entry.map_err(|_| storage_error())?;
            let filename = entry
                .file_name()
                .into_string()
                .map_err(|_| corrupt_error())?;
            let metadata = entry.file_type().map_err(|_| storage_error())?;
            if metadata.is_symlink() || !metadata.is_file() {
                return Err(storage_error());
            }
            if is_atomic_temporary_filename(&filename) {
                directory
                    .remove_file(&filename)
                    .map_err(|_| storage_error())?;
                continue;
            }
            validate_object_filename(&filename)?;
            if !retained.contains(filename.as_str()) {
                directory
                    .remove_file(&filename)
                    .map_err(|_| storage_error())?;
            }
        }
        directory
            .try_clone()
            .and_then(|value| value.into_std_file().sync_all())
            .map_err(|_| storage_error())
    }

    pub(super) fn enforce_retention_policy(
        &self,
        owner: &OwnerCorpus,
        manifest: &mut Manifest,
        now: DateTime<Utc>,
    ) -> Result<(), HostedError> {
        self.delete_unreferenced_objects(owner, manifest)?;
        let consent = manifest.consent.clone();
        let removed = self.purge_for_policy(owner, manifest, consent.as_ref(), now)?;
        if !removed.is_empty() {
            manifest.dataset_revision = next_revision(manifest.dataset_revision)?;
            self.write_manifest(owner, manifest)?;
            self.delete_objects(owner, &removed)?;
        }
        Ok(())
    }

    pub(super) fn purge_for_policy(
        &self,
        _owner: &OwnerCorpus,
        manifest: &mut Manifest,
        consent: Option<&HostedConsentRequest>,
        now: DateTime<Utc>,
    ) -> Result<Vec<String>, HostedError> {
        let Some(consent) = consent else {
            let removed = manifest
                .days
                .values()
                .map(|metadata| metadata.object_filename.clone())
                .collect();
            manifest.days.clear();
            return Ok(removed);
        };
        let expired = consent
            .expires_at
            .is_some_and(|expiration| expiration <= now);
        let cutoff = now - Duration::days(i64::from(consent.retention_days));
        let mut removed = Vec::new();
        manifest.days.retain(|_, metadata| {
            let keep = !expired && metadata.interval_end > cutoff;
            if !keep {
                removed.push(metadata.object_filename.clone());
            }
            keep
        });
        Ok(removed)
    }
}

fn consent_state(manifest: &Manifest, now: DateTime<Utc>) -> &'static str {
    match &manifest.consent {
        None => "missing",
        Some(consent) if consent.expires_at.is_some_and(|value| value <= now) => "expired",
        Some(_) => "active",
    }
}

fn control_status_from_manifest(
    manifest: &Manifest,
    now: DateTime<Utc>,
    owner_binding: &str,
) -> HostedControlStatus {
    HostedControlStatus {
        schema: "healthmd.hosted_control_status",
        schema_version: 1,
        owner_binding: owner_binding.to_owned(),
        consent_revision: manifest
            .consent
            .as_ref()
            .map(|value| value.revision)
            .or_else(|| {
                (manifest.last_consent_revision > 0).then_some(manifest.last_consent_revision)
            }),
        consent_state: consent_state(manifest, now),
    }
}

pub(super) fn status_from_manifest(
    manifest: &Manifest,
    now: DateTime<Utc>,
    owner_binding: &str,
) -> HostedSyncStatus {
    let consent_state = consent_state(manifest, now);
    HostedSyncStatus {
        schema: "healthmd.hosted_sync_status",
        schema_version: 1,
        owner_binding: owner_binding.to_owned(),
        ready: consent_state == "active" && !manifest.days.is_empty(),
        dataset_revision: manifest.dataset_revision,
        consent_revision: manifest
            .consent
            .as_ref()
            .map(|value| value.revision)
            .or_else(|| {
                (manifest.last_consent_revision > 0).then_some(manifest.last_consent_revision)
            }),
        consent_state,
        synchronized_day_count: manifest.days.len(),
        first_owner_date: manifest.days.keys().next().cloned(),
        last_owner_date: manifest.days.keys().next_back().cloned(),
    }
}

fn owner_binding(owner: &OwnerCorpus) -> String {
    let mut material = Vec::with_capacity(41 + owner.partition.len());
    material.extend_from_slice(b"healthmd.hosted.owner-binding.v1\0");
    material.extend_from_slice(owner.partition.as_bytes());
    sha256_hex(&material)
}

fn validate_consent(consent: &HostedConsentRequest) -> Result<(), HostedError> {
    validate_consent_shape(consent)?;
    if consent.expires_at.is_some_and(|value| value <= Utc::now()) {
        return Err(error(
            "healthmd_consent_invalid",
            "The hosted consent policy is invalid.",
        ));
    }
    Ok(())
}

fn validate_consent_shape(consent: &HostedConsentRequest) -> Result<(), HostedError> {
    if consent.revision == 0
        || consent.allowed_metric_ids.is_empty()
        || consent.retention_days == 0
        || consent.retention_days > 3_650
        || consent.allowed_metric_ids.len() > 512
        || consent.allowed_source_ids.len() > 512
        || consent.allowed_provider_ids.len() > 512
        || consent.allowed_metric_ids.iter().any(|value| {
            !valid_consent_identifier(value) || !super::catalog::is_supported_metric(value)
        })
        || consent.allowed_source_ids
            != BTreeSet::from(["apple_health".to_owned(), "healthmd_summary".to_owned()])
        || !consent.allowed_provider_ids.is_empty()
    {
        return Err(error(
            "healthmd_consent_invalid",
            "The hosted consent policy is invalid.",
        ));
    }
    Ok(())
}

fn validate_sync_request_shape(request: &HostedSyncRequest) -> Result<(), HostedError> {
    if request.days.is_empty() || request.days.len() > MAX_SYNC_DAYS {
        return Err(error(
            "healthmd_sync_invalid",
            "The synchronization request has an invalid day count.",
        ));
    }
    let size = serde_json::to_vec(request)
        .map_err(|_| {
            error(
                "healthmd_sync_invalid",
                "The synchronization request is invalid.",
            )
        })?
        .len();
    if size > MAX_SYNC_REQUEST_BYTES {
        return Err(error(
            "healthmd_sync_too_large",
            "The synchronization request exceeds the byte limit.",
        ));
    }
    if request
        .days
        .iter()
        .any(|day| !valid_sha256(&day.digest_sha256))
    {
        return Err(error(
            "healthmd_sync_invalid",
            "The synchronization request contains an invalid digest.",
        ));
    }
    Ok(())
}

fn valid_day_status(value: &str) -> bool {
    matches!(
        value,
        "available"
            | "complete_empty"
            | "partial"
            | "failed"
            | "unsupported"
            | "skipped"
            | "cancelled"
            | "not_requested"
            | "legacy_unavailable"
            | "redacted"
            | "not_synchronized"
    )
}

fn valid_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn validate_context_day(
    day: &Value,
    consent: &HostedConsentRequest,
    now: DateTime<Utc>,
) -> Result<String, HostedError> {
    super::validation::validate_context_day(day, consent, now)?;
    let object = day.as_object().ok_or_else(invalid_day)?;
    if object.get("schema").and_then(Value::as_str) != Some("healthmd.query_context_day")
        || object.get("schema_version").and_then(Value::as_u64) != Some(1)
    {
        return Err(error(
            "healthmd_sync_schema_unsupported",
            "The synchronized context-day schema is unsupported.",
        ));
    }
    let owner_date = object
        .get("owner_date")
        .and_then(Value::as_str)
        .ok_or_else(invalid_day)?;
    let parsed_date = parse_owner_date(owner_date)?;
    let earliest = NaiveDate::from_ymd_opt(1900, 1, 1).ok_or_else(internal_error)?;
    if parsed_date < earliest || parsed_date > now.date_naive() + Duration::days(2) {
        return Err(invalid_day());
    }
    let start = parse_timestamp(object.get("interval_start"))?;
    let end = parse_timestamp(object.get("interval_end"))?;
    let seconds = end.signed_duration_since(start).num_seconds();
    if seconds <= 0 || seconds > 48 * 3_600 {
        return Err(invalid_day());
    }
    let timezone = object
        .get("calendar_timezone")
        .and_then(Value::as_str)
        .ok_or_else(invalid_day)?;
    if timezone.is_empty() || timezone.len() > 128 || timezone.chars().any(char::is_control) {
        return Err(invalid_day());
    }
    let status = object
        .get("status")
        .and_then(Value::as_str)
        .ok_or_else(invalid_day)?;
    if !valid_status(status) {
        return Err(invalid_day());
    }
    validate_array_bound(object, "metrics", MAX_METRICS_PER_DAY)?;
    validate_array_bound(object, "workouts", MAX_WORKOUTS_PER_DAY)?;
    validate_array_bound(object, "sleep_sessions", MAX_SLEEP_SESSIONS_PER_DAY)?;
    validate_array_bound(object, "evidence", MAX_EVIDENCE_PER_DAY)?;
    validate_array_bound(object, "limitations", MAX_LIMITATIONS_PER_DAY)?;

    for metric in array(object, "metrics")? {
        let metric = metric.as_object().ok_or_else(invalid_day)?;
        let id = metric
            .get("metric_id")
            .and_then(Value::as_str)
            .ok_or_else(invalid_day)?;
        if !valid_identifier(id) || !consent.allowed_metric_ids.contains(id) {
            return Err(consent_violation());
        }
        if !metric
            .get("status")
            .and_then(Value::as_str)
            .is_some_and(valid_status)
        {
            return Err(invalid_day());
        }
        validate_string_array(metric.get("evidence_ids"), MAX_NESTED_ARRAY)?;
        validate_optional_array(metric.get("limitations"), MAX_LIMITATIONS_PER_DAY)?;
    }

    let workouts = array(object, "workouts")?;
    if !workouts.is_empty() && !consent.allowed_metric_ids.contains("workouts") {
        return Err(consent_violation());
    }
    for workout in workouts {
        let workout = workout.as_object().ok_or_else(invalid_day)?;
        validate_timestamp_pair(workout.get("start"), workout.get("end"))?;
        validate_string_array(workout.get("evidence_ids"), MAX_NESTED_ARRAY)?;
        if workout
            .get("details")
            .and_then(Value::as_object)
            .is_some_and(|value| !value.is_empty())
            && consent.maximum_detail != HostedConsentDetail::Lossless
        {
            return Err(consent_violation());
        }
    }

    let sessions = array(object, "sleep_sessions")?;
    if !sessions.is_empty() && !consent.allowed_metric_ids.contains("sleep_total") {
        return Err(consent_violation());
    }
    for session in sessions {
        let session = session.as_object().ok_or_else(invalid_day)?;
        validate_timestamp_pair(session.get("start"), session.get("end"))?;
        let intervals = session
            .get("stage_intervals")
            .and_then(Value::as_array)
            .map_or(&[][..], Vec::as_slice);
        if intervals.len() > MAX_NESTED_ARRAY {
            return Err(invalid_day());
        }
        if !intervals.is_empty() && consent.maximum_detail != HostedConsentDetail::Lossless {
            return Err(consent_violation());
        }
        for interval in intervals {
            let interval = interval.as_object().ok_or_else(invalid_day)?;
            validate_timestamp_pair(interval.get("start"), interval.get("end"))?;
        }
        validate_string_array(session.get("evidence_ids"), MAX_NESTED_ARRAY)?;
    }

    for evidence in array(object, "evidence")? {
        let evidence = evidence.as_object().ok_or_else(invalid_day)?;
        let reference = evidence
            .get("reference")
            .and_then(Value::as_object)
            .ok_or_else(invalid_day)?;
        let source = reference
            .get("source_id")
            .and_then(Value::as_str)
            .ok_or_else(invalid_day)?;
        if !consent.allowed_source_ids.contains(source) {
            return Err(consent_violation());
        }
        if let Some(provider) = reference.get("provider_id").and_then(Value::as_str) {
            if !consent.allowed_provider_ids.contains(provider) {
                return Err(consent_violation());
            }
        }
        if evidence.get("value").is_some_and(|value| !value.is_null())
            && consent.maximum_detail != HostedConsentDetail::Lossless
        {
            return Err(consent_violation());
        }
        validate_string_array(evidence.get("metric_ids"), 512)?;
    }
    Ok(owner_date.to_owned())
}

fn parse_owner_date(value: &str) -> Result<NaiveDate, HostedError> {
    if value.len() != 10 {
        return Err(invalid_day());
    }
    let parsed = NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| invalid_day())?;
    if parsed.format("%Y-%m-%d").to_string() != value {
        return Err(invalid_day());
    }
    Ok(parsed)
}

fn parse_timestamp(value: Option<&Value>) -> Result<DateTime<Utc>, HostedError> {
    let value = value.and_then(Value::as_str).ok_or_else(invalid_day)?;
    DateTime::parse_from_rfc3339(value)
        .map(|value| value.with_timezone(&Utc))
        .map_err(|_| invalid_day())
}

fn validate_timestamp_pair(start: Option<&Value>, end: Option<&Value>) -> Result<(), HostedError> {
    let start = parse_timestamp(start)?;
    let end = parse_timestamp(end)?;
    if end <= start {
        return Err(invalid_day());
    }
    Ok(())
}

fn validate_array_bound(
    object: &Map<String, Value>,
    key: &str,
    maximum: usize,
) -> Result<(), HostedError> {
    if object.get(key).is_some_and(|value| !value.is_array())
        || object
            .get(key)
            .and_then(Value::as_array)
            .is_some_and(|value| value.len() > maximum)
    {
        return Err(invalid_day());
    }
    Ok(())
}

fn array<'a>(object: &'a Map<String, Value>, key: &str) -> Result<&'a [Value], HostedError> {
    match object.get(key) {
        None => Ok(&[]),
        Some(Value::Array(values)) => Ok(values),
        Some(_) => Err(invalid_day()),
    }
}

fn validate_optional_array(value: Option<&Value>, maximum: usize) -> Result<(), HostedError> {
    match value {
        None => Ok(()),
        Some(Value::Array(values)) if values.len() <= maximum => Ok(()),
        Some(_) => Err(invalid_day()),
    }
}

fn validate_string_array(value: Option<&Value>, maximum: usize) -> Result<(), HostedError> {
    match value {
        None => Ok(()),
        Some(Value::Array(values))
            if values.len() <= maximum
                && values
                    .iter()
                    .all(|value| value.as_str().is_some_and(valid_identifier)) =>
        {
            Ok(())
        }
        Some(_) => Err(invalid_day()),
    }
}

fn valid_consent_identifier(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value.bytes().enumerate().all(|(index, byte)| {
            byte.is_ascii_lowercase()
                || byte.is_ascii_digit()
                || (index > 0 && matches!(byte, b'.' | b'_' | b'-'))
        })
}

fn valid_identifier(value: &str) -> bool {
    !value.is_empty() && value.len() <= 256 && !value.chars().any(char::is_control)
}

fn valid_status(value: &str) -> bool {
    matches!(
        value,
        "available"
            | "complete_empty"
            | "partial"
            | "failed"
            | "unsupported"
            | "skipped"
            | "cancelled"
            | "not_requested"
            | "legacy_unavailable"
            | "redacted"
            | "not_synchronized"
    )
}

fn canonical_json_bytes(value: &Value) -> Result<Vec<u8>, HostedError> {
    fn sorted(value: &Value) -> Value {
        match value {
            Value::Array(values) => Value::Array(values.iter().map(sorted).collect()),
            Value::Object(values) => {
                let mut keys: Vec<&String> = values.keys().collect();
                keys.sort_unstable();
                let mut result = Map::new();
                for key in keys {
                    result.insert(key.clone(), sorted(&values[key]));
                }
                Value::Object(result)
            }
            other => other.clone(),
        }
    }
    serde_json::to_vec(&sorted(value)).map_err(|_| invalid_day())
}

pub(super) fn semantic_json_digest(value: &Value) -> Result<String, HostedError> {
    fn append_length(output: &mut Vec<u8>, value: usize) -> Result<(), HostedError> {
        let value = u64::try_from(value).map_err(|_| invalid_day())?;
        output.extend_from_slice(&value.to_be_bytes());
        Ok(())
    }

    fn append_bytes(output: &mut Vec<u8>, value: &[u8]) -> Result<(), HostedError> {
        append_length(output, value.len())?;
        output.extend_from_slice(value);
        Ok(())
    }

    fn normalized_float(value: f64) -> Result<String, HostedError> {
        if !value.is_finite() {
            return Err(invalid_day());
        }
        if value == 0.0 {
            return Ok("0".to_owned());
        }
        Ok(format!("{:016x}", value.to_bits()))
    }

    fn append_value(output: &mut Vec<u8>, value: &Value) -> Result<(), HostedError> {
        match value {
            Value::Null => output.push(0),
            Value::Bool(false) => output.push(1),
            Value::Bool(true) => output.push(2),
            Value::Number(number) => {
                output.push(3);
                let representation = if let Some(value) = number.as_i64() {
                    value.to_string()
                } else if let Some(value) = number.as_u64() {
                    value.to_string()
                } else {
                    normalized_float(number.as_f64().ok_or_else(invalid_day)?)?
                };
                append_bytes(output, representation.as_bytes())?;
            }
            Value::String(value) => {
                output.push(4);
                append_bytes(output, value.as_bytes())?;
            }
            Value::Array(values) => {
                output.push(5);
                append_length(output, values.len())?;
                for value in values {
                    append_value(output, value)?;
                }
            }
            Value::Object(values) => {
                output.push(6);
                append_length(output, values.len())?;
                let mut keys: Vec<&String> = values.keys().collect();
                keys.sort_unstable_by(|lhs, rhs| lhs.as_bytes().cmp(rhs.as_bytes()));
                for key in keys {
                    append_bytes(output, key.as_bytes())?;
                    append_value(output, &values[key])?;
                }
            }
        }
        Ok(())
    }

    let mut bytes = b"healthmd.hosted.semantic-json-digest.v1\0".to_vec();
    append_value(&mut bytes, value)?;
    Ok(sha256_hex(&bytes))
}

fn status_of_day_bytes(bytes: &[u8]) -> Result<String, HostedError> {
    serde_json::from_slice::<Value>(bytes)
        .ok()
        .and_then(|value| {
            value
                .get("status")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .ok_or_else(invalid_day)
}

fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

fn hex(bytes: &[u8]) -> String {
    const TABLE: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(TABLE[(byte >> 4) as usize] as char);
        output.push(TABLE[(byte & 0x0f) as usize] as char);
    }
    output
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut difference = 0_u8;
    for (left, right) in left.iter().zip(right) {
        difference |= left ^ right;
    }
    difference == 0
}

fn encrypt(key: &[u8; 32], aad: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, HostedError> {
    let nonce_bytes: [u8; 12] = rand::random();
    let cipher = ChaCha20Poly1305::new(Key::from_slice(key));
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce_bytes),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| internal_error())?;
    let mut output = Vec::with_capacity(FILE_MAGIC.len() + nonce_bytes.len() + ciphertext.len());
    output.extend_from_slice(FILE_MAGIC);
    output.extend_from_slice(&nonce_bytes);
    output.extend_from_slice(&ciphertext);
    Ok(output)
}

fn decrypt(key: &[u8; 32], aad: &[u8], encrypted: &[u8]) -> Result<Vec<u8>, HostedError> {
    if encrypted.len() < FILE_MAGIC.len() + 12 + 16 || &encrypted[..FILE_MAGIC.len()] != FILE_MAGIC
    {
        return Err(corrupt_error());
    }
    let nonce_start = FILE_MAGIC.len();
    let cipher = ChaCha20Poly1305::new(Key::from_slice(key));
    cipher
        .decrypt(
            Nonce::from_slice(&encrypted[nonce_start..nonce_start + 12]),
            Payload {
                msg: &encrypted[nonce_start + 12..],
                aad,
            },
        )
        .map_err(|_| corrupt_error())
}

fn manifest_aad(owner: &OwnerCorpus, generation: u64) -> String {
    format!(
        "healthmd.hosted.manifest/2/{}/{generation}/manifest.enc",
        owner.partition
    )
}

fn generation_anchor_aad(owner: &OwnerCorpus) -> String {
    format!("healthmd.hosted.generation-anchor/1/{}", owner.partition)
}

fn object_aad(owner: &OwnerCorpus, filename: &str) -> String {
    format!(
        "healthmd.query_context_day/1/{}/{filename}",
        owner.partition
    )
}

#[cfg(unix)]
fn open_retained_directory(path: &Path) -> std::io::Result<Dir> {
    // cap-std intentionally uses `O_PATH` for ambient directories on Linux. The store also needs
    // durable directory fsync and permission operations, so retain a read-capable descriptor and
    // verify its identity against the canonical path immediately after opening.
    fs::File::open(path).map(Dir::from_std_file)
}

#[cfg(not(unix))]
fn open_retained_directory(path: &Path) -> std::io::Result<Dir> {
    Dir::open_ambient_dir(path, ambient_authority())
}

#[cfg(unix)]
fn same_file_identity(left: &fs::Metadata, right: &fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt as _;
    left.dev() == right.dev() && left.ino() == right.ino()
}

#[cfg(windows)]
fn same_file_identity(left: &fs::Metadata, right: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt as _;
    left.volume_serial_number() == right.volume_serial_number()
        && left.file_index() == right.file_index()
        && left.file_index().is_some()
}

#[cfg(not(any(unix, windows)))]
fn same_file_identity(_left: &fs::Metadata, _right: &fs::Metadata) -> bool {
    true
}

fn metadata_at_if_present(
    directory: &Dir,
    name: &str,
) -> Result<Option<cap_std::fs::Metadata>, HostedError> {
    match directory.symlink_metadata(name) {
        Ok(metadata) => Ok(Some(metadata)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(storage_error()),
    }
}

fn ensure_child_directory(directory: &Dir, name: &str) -> Result<Dir, HostedError> {
    match directory.open_dir_nofollow(name) {
        Ok(child) => {
            set_cap_directory_permissions(&child)?;
            Ok(child)
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            match directory.create_dir(name) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
                Err(_) => return Err(storage_error()),
            }
            let child = directory
                .open_dir_nofollow(name)
                .map_err(|_| storage_error())?;
            set_cap_directory_permissions(&child)?;
            sync_cap_directory(directory)?;
            Ok(child)
        }
        Err(_) => Err(storage_error()),
    }
}

fn open_file_at_nofollow(
    directory: &Dir,
    name: &str,
    write: bool,
    create: bool,
    create_new: bool,
) -> Result<cap_std::fs::File, HostedError> {
    let mut options = CapOpenOptions::new();
    options
        .read(!write)
        .write(write)
        .create(create)
        .create_new(create_new);
    options.follow(FollowSymlinks::No);
    let file = directory
        .open_with(name, &options)
        .map_err(|_| storage_error())?;
    let metadata = file.metadata().map_err(|_| storage_error())?;
    if !metadata.is_file() {
        return Err(storage_error());
    }
    Ok(file)
}

fn open_exclusive_lock(directory: &Dir, name: &str) -> Result<File, HostedError> {
    let file = open_file_at_nofollow(directory, name, true, true, false)?;
    set_cap_file_permissions(&file)?;
    let file = file.into_std();
    file.try_lock_exclusive().map_err(|_| storage_error())?;
    Ok(file)
}

fn read_bounded_at(directory: &Dir, name: &str, maximum: usize) -> Result<Vec<u8>, HostedError> {
    let mut file = open_file_at_nofollow(directory, name, false, false, false)?;
    let metadata = file.metadata().map_err(|_| storage_error())?;
    if metadata.len() > maximum as u64 {
        return Err(corrupt_error());
    }
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    Read::by_ref(&mut file)
        .take((maximum + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| storage_error())?;
    if bytes.len() > maximum {
        return Err(corrupt_error());
    }
    Ok(bytes)
}

fn atomic_write_at(directory: &Dir, name: &str, bytes: &[u8]) -> Result<(), HostedError> {
    let random: [u8; 6] = rand::random();
    let temporary = format!("{ATOMIC_TEMP_PREFIX}{}", hex(&random));
    let result = (|| {
        let mut file = open_file_at_nofollow(directory, &temporary, true, false, true)?;
        file.write_all(bytes).map_err(|_| storage_error())?;
        file.sync_all().map_err(|_| storage_error())?;
        set_cap_file_permissions(&file)?;
        directory
            .rename(&temporary, directory, name)
            .map_err(|_| storage_error())?;
        sync_cap_directory(directory)
    })();
    if result.is_err() {
        let _ = directory.remove_file(&temporary);
    }
    result
}

fn remove_file_at(directory: &Dir, name: &str) -> Result<(), HostedError> {
    match directory.remove_file(name) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(storage_error()),
    }
}

fn cleanup_atomic_temporaries_at(
    directory: &Dir,
    maximum_entries: usize,
) -> Result<(), HostedError> {
    let mut count = 0_usize;
    let mut changed = false;
    for entry in directory.entries().map_err(|_| storage_error())? {
        count = count.checked_add(1).ok_or_else(storage_error)?;
        if count > maximum_entries {
            return Err(storage_error());
        }
        let entry = entry.map_err(|_| storage_error())?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| corrupt_error())?;
        if is_atomic_temporary_filename(&name) {
            let file_type = entry.file_type().map_err(|_| storage_error())?;
            if file_type.is_symlink() || !file_type.is_file() {
                return Err(storage_error());
            }
            directory.remove_file(&name).map_err(|_| storage_error())?;
            changed = true;
        }
    }
    if changed {
        sync_cap_directory(directory)?;
    }
    Ok(())
}

fn sync_cap_directory(directory: &Dir) -> Result<(), HostedError> {
    directory
        .try_clone()
        .and_then(|value| value.into_std_file().sync_all())
        .map_err(|_| storage_error())
}

#[cfg(unix)]
fn set_cap_file_permissions(file: &cap_std::fs::File) -> Result<(), HostedError> {
    file.set_permissions(CapPermissions::from_mode(0o600))
        .map_err(|_| storage_error())
}

#[cfg(not(unix))]
fn set_cap_file_permissions(_file: &cap_std::fs::File) -> Result<(), HostedError> {
    Ok(())
}

#[cfg(unix)]
fn set_cap_directory_permissions(directory: &Dir) -> Result<(), HostedError> {
    use std::os::unix::fs::PermissionsExt as _;
    // Linux capability directories may use `O_PATH`, where `File::set_permissions` fails.
    // Resolve `.` beneath the retained directory capability so cap-std can use its safe fallback.
    directory
        .set_permissions(
            ".",
            cap_std::fs::Permissions::from_std(fs::Permissions::from_mode(0o700)),
        )
        .map_err(|_| storage_error())
}

#[cfg(not(unix))]
fn set_cap_directory_permissions(_directory: &Dir) -> Result<(), HostedError> {
    Ok(())
}

fn symlink_metadata_if_present(path: &Path) -> Result<Option<fs::Metadata>, HostedError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => Ok(Some(metadata)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(storage_error()),
    }
}

fn ensure_directory(path: &Path) -> Result<(), HostedError> {
    if let Some(metadata) = symlink_metadata_if_present(path)? {
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(storage_error());
        }
    } else {
        fs::create_dir_all(path).map_err(|_| storage_error())?;
    }
    set_directory_permissions(path)?;
    Ok(())
}

#[cfg(test)]
fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), HostedError> {
    let parent = path.parent().ok_or_else(internal_error)?;
    ensure_directory(parent)?;
    let mut temporary = tempfile::Builder::new()
        .prefix(ATOMIC_TEMP_PREFIX)
        .rand_bytes(ATOMIC_TEMP_RANDOM_BYTES)
        .tempfile_in(parent)
        .map_err(|_| storage_error())?;
    temporary.write_all(bytes).map_err(|_| storage_error())?;
    temporary
        .as_file()
        .sync_all()
        .map_err(|_| storage_error())?;
    set_file_permissions(temporary.path())?;
    temporary.persist(path).map_err(|_| storage_error())?;
    sync_parent(path)
}

#[cfg(test)]
fn read_bounded(path: &Path, maximum: usize) -> Result<Vec<u8>, HostedError> {
    let metadata = fs::metadata(path).map_err(|_| storage_error())?;
    if metadata.len() > maximum as u64 {
        return Err(corrupt_error());
    }
    let file = File::open(path).map_err(|_| storage_error())?;
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.take((maximum + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| storage_error())?;
    if bytes.len() > maximum {
        return Err(corrupt_error());
    }
    Ok(bytes)
}

#[cfg(test)]
fn sync_parent(path: &Path) -> Result<(), HostedError> {
    let parent = path.parent().ok_or_else(internal_error)?;
    File::open(parent)
        .and_then(|directory| directory.sync_all())
        .map_err(|_| storage_error())
}

fn is_atomic_temporary_filename(filename: &str) -> bool {
    let Some(random) = filename.strip_prefix(ATOMIC_TEMP_PREFIX) else {
        return false;
    };
    matches!(random.len(), 6 | ATOMIC_TEMP_RANDOM_BYTES)
        && random.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn validate_object_filename(filename: &str) -> Result<(), HostedError> {
    if filename.len() == 36
        && filename.ends_with(".day")
        && filename[..32]
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        Ok(())
    } else {
        Err(corrupt_error())
    }
}

#[cfg(unix)]
fn set_directory_permissions(path: &Path) -> Result<(), HostedError> {
    use std::os::unix::fs::PermissionsExt as _;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(|_| storage_error())
}

#[cfg(not(unix))]
fn set_directory_permissions(_path: &Path) -> Result<(), HostedError> {
    Ok(())
}

#[cfg(all(test, unix))]
fn set_file_permissions(path: &Path) -> Result<(), HostedError> {
    use std::os::unix::fs::PermissionsExt as _;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(|_| storage_error())
}

#[cfg(all(test, not(unix)))]
fn set_file_permissions(_path: &Path) -> Result<(), HostedError> {
    Ok(())
}

fn next_revision(revision: u64) -> Result<u64, HostedError> {
    revision.checked_add(1).ok_or_else(internal_error)
}

fn error(code: &'static str, message: &'static str) -> HostedError {
    HostedError::new(code, message)
}

fn invalid_day() -> HostedError {
    error(
        "healthmd_sync_day_invalid",
        "A synchronized context day is invalid.",
    )
}

fn consent_revision_stale() -> HostedError {
    error(
        "healthmd_consent_revision_stale",
        "The consent revision does not match the stored revision.",
    )
}

fn consent_violation() -> HostedError {
    error(
        "healthmd_consent_violation",
        "Synchronized data exceeds the active consent policy.",
    )
}

fn corrupt_error() -> HostedError {
    error(
        "healthmd_hosted_store_corrupt",
        "The encrypted hosted corpus could not be authenticated.",
    )
}

fn storage_error() -> HostedError {
    HostedError::new(
        "healthmd_storage_unavailable",
        "The encrypted hosted corpus is temporarily unavailable.",
    )
    .retryable()
}

fn internal_error() -> HostedError {
    error(
        "healthmd_hosted_internal",
        "The hosted data operation could not be completed.",
    )
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeSet, sync::Arc, time::Duration as StdDuration};

    use chrono::{Duration, Utc};
    use tempfile::TempDir;

    use super::*;
    use crate::backend::{CallerIdentity, CallerMode};

    fn caller() -> CallerIdentity {
        CallerIdentity {
            subject: "owner".to_owned(),
            tenant: Some("tenant".to_owned()),
            issuer: Some("https://issuer.example".to_owned()),
            scopes: BTreeSet::new(),
            mode: CallerMode::OAuth,
        }
    }

    fn consent() -> HostedConsentRequest {
        HostedConsentRequest {
            revision: 1,
            allowed_metric_ids: BTreeSet::from(["steps".to_owned()]),
            allowed_source_ids: BTreeSet::from([
                "apple_health".to_owned(),
                "healthmd_summary".to_owned(),
            ]),
            allowed_provider_ids: BTreeSet::new(),
            maximum_detail: HostedConsentDetail::Summary,
            retention_days: 30,
            expires_at: Some(Utc::now() + Duration::days(1)),
        }
    }

    #[tokio::test]
    async fn exact_consent_replay_rechecks_expiry_and_enforces_retention() {
        let root = TempDir::new().unwrap();
        let store = Arc::new(HostedDataStore::new_test(root.path(), [30; 32]).unwrap());
        let caller = caller();
        let mut policy = consent();
        policy.expires_at = Some(Utc::now() + Duration::milliseconds(500));
        store.set_consent(&caller, policy.clone()).await.unwrap();

        let guard = store.gate.write().await;
        let replay_store = Arc::clone(&store);
        let replay_caller = caller.clone();
        let replay_policy = policy.clone();
        let replay = tokio::spawn(async move {
            replay_store
                .set_consent(&replay_caller, replay_policy)
                .await
        });
        tokio::time::sleep(StdDuration::from_millis(600)).await;
        drop(guard);
        assert_eq!(
            replay.await.unwrap().unwrap_err().code,
            "healthmd_consent_invalid"
        );

        let root = TempDir::new().unwrap();
        let store = HostedDataStore::new_test(root.path(), [29; 32]).unwrap();
        let mut policy = consent();
        policy.expires_at = Some(Utc::now() + Duration::days(1));
        store.set_consent(&caller, policy.clone()).await.unwrap();
        let mut owner = store.owner(&caller).unwrap();
        store.load_existing_data_key(&mut owner).unwrap();
        let mut manifest = store.read_manifest(&owner).unwrap();
        let old_end = Utc::now() - Duration::days(31);
        manifest.days.insert(
            old_end.date_naive().format("%Y-%m-%d").to_string(),
            DayMetadata {
                digest_sha256: "a".repeat(64),
                storage_sha256: "b".repeat(64),
                status: "complete_empty".to_owned(),
                size_bytes: 1,
                object_filename: format!("{}.day", "c".repeat(32)),
                interval_end: old_end,
                synchronized_at: old_end,
            },
        );
        store.write_manifest(&owner, &mut manifest).unwrap();
        let replay = store.set_consent(&caller, policy).await.unwrap();
        assert_eq!(replay.purged_day_count, 1);
        assert_eq!(replay.synchronized_day_count, 0);
    }

    #[tokio::test]
    async fn authenticated_manifest_invariants_reject_duplicate_objects() {
        let root = TempDir::new().unwrap();
        let store = HostedDataStore::new_test(root.path(), [32; 32]).unwrap();
        let caller = caller();
        store.set_consent(&caller, consent()).await.unwrap();
        let mut owner = store.owner(&caller).unwrap();
        store.load_existing_data_key(&mut owner).unwrap();
        let mut manifest = store.read_manifest(&owner).unwrap();
        let now = Utc::now();
        let metadata = DayMetadata {
            digest_sha256: "a".repeat(64),
            storage_sha256: "b".repeat(64),
            status: "complete_empty".to_owned(),
            size_bytes: 1,
            object_filename: format!("{}.day", "c".repeat(32)),
            interval_end: now,
            synchronized_at: now,
        };
        manifest
            .days
            .insert("2026-01-01".to_owned(), metadata.clone());
        manifest.days.insert("2026-01-02".to_owned(), metadata);
        store.write_manifest(&owner, &mut manifest).unwrap();
        assert_eq!(
            store.read_manifest(&owner).unwrap_err().code,
            "healthmd_hosted_store_corrupt"
        );
    }

    #[tokio::test]
    async fn legacy_manifest_version_is_rejected_fail_closed() {
        let root = TempDir::new().unwrap();
        let store = HostedDataStore::new_test(root.path(), [31; 32]).unwrap();
        let caller = caller();
        store.set_consent(&caller, consent()).await.unwrap();
        let mut owner = store.owner(&caller).unwrap();
        store.load_existing_data_key(&mut owner).unwrap();
        let manifest_path = owner.directory.join("manifest.enc");
        let encrypted = read_bounded(&manifest_path, MAX_CONTEXT_DAY_BYTES).unwrap();
        let generation = store
            .read_generation_anchor(&owner)
            .unwrap()
            .unwrap()
            .generation;
        let plaintext = decrypt(
            &owner.key,
            manifest_aad(&owner, generation).as_bytes(),
            &encrypted,
        )
        .unwrap();
        let mut value: Value = serde_json::from_slice(&plaintext).unwrap();
        value["schema_version"] = Value::from(1);
        let plaintext = serde_json::to_vec(&value).unwrap();
        let encrypted = encrypt(
            &owner.key,
            manifest_aad(&owner, generation).as_bytes(),
            &plaintext,
        )
        .unwrap();
        atomic_write(&manifest_path, &encrypted).unwrap();
        assert_eq!(
            store.read_manifest(&owner).unwrap_err().code,
            "healthmd_hosted_store_corrupt"
        );
    }

    #[test]
    fn deletion_recovery_removes_only_valid_atomic_temporaries() {
        let root = TempDir::new().unwrap();
        let store = HostedDataStore::new_test(root.path(), [33; 32]).unwrap();
        let deletions = root.path().join("ciphertext").join("deletions");
        ensure_directory(&deletions).unwrap();
        let legacy_temporary = deletions.join(".healthmd-Ab12Cd");
        let current_temporary = deletions.join(".healthmd-Ab12Cd34Ef56");
        fs::write(&legacy_temporary, b"incomplete").unwrap();
        fs::write(&current_temporary, b"incomplete").unwrap();

        store.recover_pending_account_deletions().unwrap();
        assert!(!legacy_temporary.exists());
        assert!(!current_temporary.exists());
        assert!(!is_atomic_temporary_filename(".healthmd-invalid!"));
        assert!(!is_atomic_temporary_filename(".healthmd-too-short"));

        let unrelated = deletions.join(".healthmd-invalid!");
        fs::write(&unrelated, b"not a store temporary").unwrap();
        assert_eq!(
            store.recover_pending_account_deletions().unwrap_err().code,
            "healthmd_hosted_store_corrupt"
        );
        assert!(unrelated.exists());
    }

    #[tokio::test]
    async fn pending_key_rotation_recovery_installs_only_complete_pairs() {
        let root = TempDir::new().unwrap();
        let store = HostedDataStore::new_test(root.path(), [32; 32]).unwrap();
        let caller = caller();
        store.set_consent(&caller, consent()).await.unwrap();
        let mut owner = store.owner(&caller).unwrap();
        store.load_existing_data_key(&mut owner).unwrap();
        let manifest = store.read_manifest(&owner).unwrap();

        let next_key = [77_u8; 32];
        let key_aad = format!("healthmd.hosted.owner_key/1/{}", owner.partition);
        let wrapped = encrypt(&owner.kek, key_aad.as_bytes(), &next_key).unwrap();
        let mut next_manifest = manifest.clone();
        next_manifest.storage_generation += 1;
        let plaintext = serde_json::to_vec(&next_manifest).unwrap();
        let encrypted_manifest = encrypt(
            &next_key,
            manifest_aad(&owner, next_manifest.storage_generation).as_bytes(),
            &plaintext,
        )
        .unwrap();
        atomic_write(&owner.directory.join("owner-key.next"), &wrapped).unwrap();
        atomic_write(&owner.directory.join("manifest.next"), &encrypted_manifest).unwrap();
        store
            .write_active_anchor(
                &owner,
                next_manifest.storage_generation,
                &encrypted_manifest,
            )
            .unwrap();

        let mut recovered = store.owner(&caller).unwrap();
        store.load_existing_data_key(&mut recovered).unwrap();
        assert_eq!(recovered.key, next_key);
        assert_eq!(store.read_manifest(&recovered).unwrap().dataset_revision, 1);
        assert!(
            symlink_metadata_if_present(&recovered.directory.join("owner-key.next"))
                .unwrap()
                .is_none()
        );
        assert!(
            symlink_metadata_if_present(&recovered.directory.join("manifest.next"))
                .unwrap()
                .is_none()
        );

        atomic_write(&recovered.directory.join("owner-key.next"), b"incomplete").unwrap();
        let mut key_only = store.owner(&caller).unwrap();
        store.load_existing_data_key(&mut key_only).unwrap();
        assert_eq!(key_only.key, next_key);
        assert!(
            symlink_metadata_if_present(&key_only.directory.join("owner-key.next"))
                .unwrap()
                .is_none()
        );

        atomic_write(&key_only.directory.join("manifest.next"), b"incomplete").unwrap();
        let mut manifest_only = store.owner(&caller).unwrap();
        store.load_existing_data_key(&mut manifest_only).unwrap();
        assert_eq!(manifest_only.key, next_key);
        assert!(
            symlink_metadata_if_present(&manifest_only.directory.join("manifest.next"))
                .unwrap()
                .is_none()
        );
    }

    #[tokio::test]
    async fn anchored_generation_rejects_ciphertext_rollback_and_deleted_corpus_revival() {
        let root = TempDir::new().unwrap();
        let store = HostedDataStore::new_test(root.path(), [41; 32]).unwrap();
        let owner_caller = caller();
        store.set_consent(&owner_caller, consent()).await.unwrap();
        let owner = store.owner(&owner_caller).unwrap();
        let old_key = fs::read(owner.directory.join("owner-key.enc")).unwrap();
        let old_manifest = fs::read(owner.directory.join("manifest.enc")).unwrap();

        let mut replacement = consent();
        replacement.revision = 2;
        store.set_consent(&owner_caller, replacement).await.unwrap();
        atomic_write(&owner.directory.join("owner-key.enc"), &old_key).unwrap();
        atomic_write(&owner.directory.join("manifest.enc"), &old_manifest).unwrap();
        assert_eq!(
            store.status(&owner_caller).await.unwrap_err().code,
            "healthmd_hosted_store_corrupt"
        );

        // Restore the current committed state, delete it, then attempt to revive the old corpus.
        let mut replacement = consent();
        replacement.revision = 3;
        store
            .set_consent(&owner_caller, replacement)
            .await
            .unwrap_err();
        // The rollback detection is fail-closed and cannot be repaired in-band. Use a fresh owner
        // to verify that a retained deleted anchor dominates restored ciphertext.
        let mut deleted_caller = owner_caller.clone();
        deleted_caller.subject = "deleted-owner".to_owned();
        store.set_consent(&deleted_caller, consent()).await.unwrap();
        let deleted_owner = store.owner(&deleted_caller).unwrap();
        let deleted_key = fs::read(deleted_owner.directory.join("owner-key.enc")).unwrap();
        let deleted_manifest = fs::read(deleted_owner.directory.join("manifest.enc")).unwrap();
        store.delete_account(&deleted_caller).await.unwrap();
        ensure_directory(&deleted_owner.directory).unwrap();
        ensure_directory(&deleted_owner.blobs).unwrap();
        atomic_write(&deleted_owner.directory.join("owner-key.enc"), &deleted_key).unwrap();
        atomic_write(
            &deleted_owner.directory.join("manifest.enc"),
            &deleted_manifest,
        )
        .unwrap();
        assert_eq!(
            store
                .status(&deleted_caller)
                .await
                .unwrap()
                .synchronized_day_count,
            0
        );
        assert!(!deleted_owner.directory.exists());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn retained_root_capabilities_ignore_later_path_substitution() {
        let root = TempDir::new().unwrap();
        let data = root.path().join("data");
        let anchors = root.path().join("anchors");
        let moved_data = root.path().join("moved-data");
        let moved_anchors = root.path().join("moved-anchors");
        let store = HostedDataStore::new(&data, &anchors, [41; 32]).unwrap();
        fs::rename(&data, &moved_data).unwrap();
        fs::rename(&anchors, &moved_anchors).unwrap();
        fs::create_dir(&data).unwrap();
        fs::create_dir(&anchors).unwrap();

        let caller = caller();
        store.set_consent(&caller, consent()).await.unwrap();
        assert!(moved_data.join("v1").is_dir());
        assert!(fs::read_dir(&data).unwrap().next().is_none());
        assert!(fs::read_dir(&anchors).unwrap().next().is_none());
        assert!(
            fs::read_dir(&moved_anchors)
                .unwrap()
                .flatten()
                .any(|entry| entry.file_name() != ".healthmd-hosted.lock")
        );
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn retention_never_follows_an_objects_directory_symlink() {
        use std::os::unix::fs::symlink;

        let root = TempDir::new().unwrap();
        let external = TempDir::new().unwrap();
        let store = HostedDataStore::new_test(root.path(), [42; 32]).unwrap();
        let caller = caller();
        store.set_consent(&caller, consent()).await.unwrap();
        let owner = store.owner(&caller).unwrap();
        fs::remove_dir(&owner.blobs).unwrap();
        let external_file = external.path().join("0123456789abcdef0123456789abcdef.day");
        fs::write(&external_file, b"must remain").unwrap();
        symlink(external.path(), &owner.blobs).unwrap();

        assert_eq!(
            store.status(&caller).await.unwrap_err().code,
            "healthmd_storage_unavailable"
        );
        assert_eq!(fs::read(&external_file).unwrap(), b"must remain");
    }

    #[test]
    fn ciphertext_and_generation_anchor_roots_must_be_disjoint() {
        let root = TempDir::new().unwrap();
        let data = root.path().join("data");
        assert_eq!(
            HostedDataStore::new(&data, data.join("anchors"), [43; 32])
                .err()
                .unwrap()
                .code,
            "healthmd_storage_unavailable"
        );

        let data = root.path().join("leased-data");
        let anchors = root.path().join("leased-anchors");
        let _first = HostedDataStore::new(&data, &anchors, [44; 32]).unwrap();
        assert_eq!(
            HostedDataStore::new(&data, &anchors, [44; 32])
                .err()
                .unwrap()
                .code,
            "healthmd_storage_unavailable"
        );
        assert_eq!(
            HostedDataStore::new(root.path().join("other-data"), &anchors, [44; 32])
                .err()
                .unwrap()
                .code,
            "healthmd_storage_unavailable"
        );
    }
}
