use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{self, Read as _, Write as _},
    path::{Component, Path, PathBuf},
};

use cap_fs_ext::{DirExt as _, FollowSymlinks, OpenOptionsFollowExt as _};
use cap_std::{
    ambient_authority,
    fs::{Dir, OpenOptions},
};
use chrono::{NaiveDate, Utc};
use healthmd_protocol::{
    TRANSFER_FRAME_BYTES,
    encoding::{SwiftUuid, canonical_json},
    models::{
        ExportAccepted, ExportOutcome, ExportRequest, FileManifest, FileWriteMode, ResponseMode,
        TransferChunk, TransferChunkAcknowledgement, TransferDisposition, TransferDispositionKind,
        TransferFinalAcknowledgement, TransferFinalize, TransferOpen, TransferPartition,
        TransferPartitionAcknowledgement, TransferPartitionComplete, TransferSession,
    },
    transfer::{is_sha256, request_fingerprint, sha256_hex},
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest as _, Sha256};
use tempfile::NamedTempFile;
use uuid::Uuid;

#[cfg(any(target_os = "linux", target_os = "macos"))]
use rustix::fs::{Mode, OFlags, RenameFlags, openat, renameat_with};

use crate::{
    ClientError,
    generated_path::{generated_paths_conflict, validate_generated_relative_path},
    job::{JobState, JobStore, ResponseArtifact},
    limits::{
        MAXIMUM_DATES_PER_JOB, MAXIMUM_DURABLE_JSON_BYTES, MAXIMUM_GENERATED_FILES_PER_JOB,
        MAXIMUM_PARTITIONS_PER_JOB, StorageReservation, ensure_available_space, ensure_job_bytes,
        prepare_private_directory, read_bounded, reserve_materialization_storage,
        reserve_output_capacity, reserve_partition_capacity, reserve_private_storage,
    },
    markdown,
    storage::StorageLayout,
};

const JOURNAL_VERSION: u16 = 2;
const MAXIMUM_MERGE_BYTES: i64 = 64 * 1_024 * 1_024;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
struct DestinationIdentity {
    canonical_path: String,
    #[cfg(unix)]
    device: u64,
    #[cfg(unix)]
    inode: u64,
    #[cfg(windows)]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    volume_serial_number: Option<u32>,
    #[cfg(windows)]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    file_index: Option<u64>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
struct CommitPlan {
    #[serde(rename = "fileID")]
    file_id: SwiftUuid,
    #[serde(rename = "destinationRelativePath")]
    destination_relative_path: String,
    #[serde(rename = "beforeSHA256", skip_serializing_if = "Option::is_none")]
    before_sha256: Option<String>,
    #[serde(rename = "afterSHA256")]
    after_sha256: String,
    #[serde(rename = "stagedRelativePath")]
    staged_relative_path: String,
    committed: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
struct FileJournal {
    version: u16,
    request: ExportRequest,
    accepted: ExportAccepted,
    session: TransferSession,
    #[serde(rename = "destinationIdentity")]
    destination_identity: DestinationIdentity,
    manifests: BTreeMap<SwiftUuid, FileManifest>,
    #[serde(rename = "committedPartitions")]
    committed_partitions: Vec<TransferPartition>,
    #[serde(rename = "commitPlans")]
    commit_plans: BTreeMap<SwiftUuid, CommitPlan>,
    #[serde(skip_serializing_if = "Option::is_none")]
    outcome: Option<ExportOutcome>,
    #[serde(rename = "updatedAt", with = "healthmd_protocol::time")]
    updated_at: chrono::DateTime<Utc>,
}

struct PendingPartition {
    descriptor: TransferPartition,
    path: PathBuf,
    next_sequence: i64,
    received_bytes: i64,
    _storage_reservation: StorageReservation,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct FileReceiptPayload {
    #[serde(rename = "job_id")]
    pub job_id: SwiftUuid,
    pub status: String,
    #[serde(rename = "destination_path")]
    pub destination_path: String,
    #[serde(rename = "files_written")]
    pub files_written: i64,
    #[serde(rename = "total_bytes")]
    pub total_bytes: i64,
    #[serde(rename = "relative_paths")]
    pub relative_paths: Vec<String>,
    #[serde(rename = "success_count")]
    pub success_count: i64,
    #[serde(rename = "total_count")]
    pub total_count: i64,
    #[serde(rename = "failed_date_identifiers")]
    pub failed_date_identifiers: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FileExportReceipt {
    pub payload: FileReceiptPayload,
    pub response_path: PathBuf,
    pub response_byte_count: i64,
    pub response_sha256: String,
}

/// Source-neutral capability wrapper around the hardened generated-file commit engine.
pub struct GeneratedDestination {
    root: PathBuf,
    identity: DestinationIdentity,
    private_storage_root: Option<PathBuf>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GeneratedStage {
    pub before_sha256: Option<String>,
    pub after_sha256: String,
}

impl GeneratedDestination {
    /// Open and bind an existing absolute non-symlink destination directory.
    ///
    /// # Errors
    ///
    /// Returns an error when the destination is unsafe or inaccessible.
    pub fn open(path: &Path) -> Result<Self, ClientError> {
        let path_text = path
            .to_str()
            .ok_or_else(|| invalid("destination must be valid UTF-8"))?;
        let root = validated_root(path_text)?;
        let identity = destination_identity(&root)?;
        Ok(Self {
            root,
            identity,
            private_storage_root: None,
        })
    }

    #[must_use]
    pub(crate) fn with_private_storage_root(mut self, root: &Path) -> Self {
        self.private_storage_root = Some(root.to_owned());
        self
    }

    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Opaque digest suitable for binding a mobile request to this destination.
    ///
    /// # Errors
    ///
    /// Returns an error only if the internal identity cannot be serialized.
    pub fn binding_sha256(&self) -> Result<String, ClientError> {
        canonical_json(&self.identity)
            .map(|bytes| sha256_hex(&bytes))
            .map_err(|_| invalid("destination identity encoding failed"))
    }

    /// Build the exact destination output in a private stage without mutating the destination.
    ///
    /// # Errors
    ///
    /// Returns an error for unsafe paths, changed destination identity, invalid Markdown, or I/O.
    pub fn prepare_stage(
        &self,
        relative_path: &str,
        source: &Path,
        stage: &Path,
        mode: healthmd_protocol::v2::FileWriteMode,
    ) -> Result<GeneratedStage, ClientError> {
        self.ensure_identity()?;
        let relative = validate_generated_relative_path(relative_path)?;
        let root = Dir::open_ambient_dir(&self.root, ambient_authority()).map_err(storage_error)?;
        let (parent, name) = open_safe_parent(root, &relative)?;
        let before_sha256 = digest_cap_file(&parent, &name)?;
        build_stage(
            &parent,
            &name,
            before_sha256.is_some(),
            source,
            stage,
            v2_write_mode(mode),
            b"\n\n",
            self.private_storage_root.as_deref(),
        )?;
        let (_, after_sha256) = inspect_file(stage)?;
        Ok(GeneratedStage {
            before_sha256,
            after_sha256,
        })
    }

    /// Build an Android-parity stage using the single-newline append separator.
    ///
    /// # Errors
    ///
    /// Returns the same errors as [`Self::prepare_stage`].
    pub fn prepare_android_stage(
        &self,
        relative_path: &str,
        source: &Path,
        stage: &Path,
        mode: healthmd_protocol::v2::FileWriteMode,
    ) -> Result<GeneratedStage, ClientError> {
        self.ensure_identity()?;
        let relative = validate_generated_relative_path(relative_path)?;
        let root = Dir::open_ambient_dir(&self.root, ambient_authority()).map_err(storage_error)?;
        let (parent, name) = open_safe_parent(root, &relative)?;
        let before_sha256 = digest_cap_file(&parent, &name)?;
        build_stage(
            &parent,
            &name,
            before_sha256.is_some(),
            source,
            stage,
            v2_write_mode(mode),
            b"\n",
            self.private_storage_root.as_deref(),
        )?;
        let (_, after_sha256) = inspect_file(stage)?;
        Ok(GeneratedStage {
            before_sha256,
            after_sha256,
        })
    }

    /// Install a prepared stage iff the destination still has the expected digest.
    ///
    /// # Errors
    ///
    /// Returns an error when the destination identity/content changed or atomic install fails.
    pub fn install_stage(
        &self,
        relative_path: &str,
        stage: &Path,
        expected_before: Option<&str>,
        expected_after: &str,
    ) -> Result<(), ClientError> {
        self.ensure_identity()?;
        let relative = validate_generated_relative_path(relative_path)?;
        let root = Dir::open_ambient_dir(&self.root, ambient_authority()).map_err(storage_error)?;
        let (parent, name) = open_safe_parent(root, &relative)?;
        if digest_cap_file(&parent, &name)?.as_deref() == Some(expected_after) {
            return Ok(());
        }
        install_stage(
            &parent,
            &name,
            stage,
            expected_before,
            expected_after,
            &self.root.join(&relative),
            self.private_storage_root.as_deref(),
        )?;
        if digest_cap_file(&parent, &name)?.as_deref() != Some(expected_after) {
            return Err(invalid("destination digest failed after commit"));
        }
        Ok(())
    }

    /// Validate destination-dependent stage amplification before accepting transfer partitions.
    ///
    /// Append and Markdown merge are admitted only when the existing destination is no larger than
    /// the incoming artifact, keeping all private input, assembly, and stage copies inside the
    /// four-copy lifecycle reservation.
    ///
    /// # Errors
    ///
    /// Returns an error for an unsafe path, changed destination, or excessive stage amplification.
    pub(crate) fn validate_stage_admission(
        &self,
        relative_path: &str,
        source_bytes: u64,
        mode: FileWriteMode,
        append_separator_bytes: u64,
    ) -> Result<(), ClientError> {
        self.ensure_identity()?;
        ensure_job_bytes(source_bytes)?;
        let relative = validate_generated_relative_path(relative_path)?;
        let root = Dir::open_ambient_dir(&self.root, ambient_authority()).map_err(storage_error)?;
        let Some((parent, name)) = open_existing_safe_parent(root, &relative)? else {
            return Ok(());
        };
        let existing_bytes = existing_cap_file_size(&parent, &name)?.unwrap_or(0);
        if mode != FileWriteMode::Overwrite && existing_bytes > source_bytes {
            return Err(invalid(
                "existing destination exceeds bounded stage amplification",
            ));
        }
        let separator_bytes = if existing_bytes > 0 && mode == FileWriteMode::Append {
            append_separator_bytes
        } else {
            0
        };
        let stage_bytes = source_bytes
            .checked_add(if mode == FileWriteMode::Overwrite {
                0
            } else {
                existing_bytes
            })
            .and_then(|bytes| bytes.checked_add(separator_bytes))
            .ok_or_else(|| invalid("generated stage byte total overflow"))?;
        ensure_job_bytes(stage_bytes)
    }

    /// Read the current exact digest for idempotent commit recovery.
    ///
    /// # Errors
    ///
    /// Returns an error for changed identity, unsafe paths, or non-regular files.
    pub fn current_digest(&self, relative_path: &str) -> Result<Option<String>, ClientError> {
        self.ensure_identity()?;
        let relative = validate_generated_relative_path(relative_path)?;
        let root = Dir::open_ambient_dir(&self.root, ambient_authority()).map_err(storage_error)?;
        let (parent, name) = open_safe_parent(root, &relative)?;
        digest_cap_file(&parent, &name)
    }

    fn ensure_identity(&self) -> Result<(), ClientError> {
        if destination_identity(&validated_root(
            self.root
                .to_str()
                .ok_or_else(|| invalid("destination must be valid UTF-8"))?,
        )?)? != self.identity
        {
            return Err(invalid("destination identity changed"));
        }
        Ok(())
    }
}

pub(crate) const fn v2_write_mode(mode: healthmd_protocol::v2::FileWriteMode) -> FileWriteMode {
    match mode {
        healthmd_protocol::v2::FileWriteMode::Overwrite => FileWriteMode::Overwrite,
        healthmd_protocol::v2::FileWriteMode::Append => FileWriteMode::Append,
        healthmd_protocol::v2::FileWriteMode::MergeMarkdown => FileWriteMode::MergeMarkdown,
        healthmd_protocol::v2::FileWriteMode::MergeMarkdownPreservingPreamble => {
            FileWriteMode::MergeMarkdownPreservingPreamble
        }
    }
}

pub struct FileReceiver {
    layout: StorageLayout,
    jobs: JobStore,
    journal: Option<FileJournal>,
    pending: Option<PendingPartition>,
}

impl FileReceiver {
    #[must_use]
    pub const fn new(layout: StorageLayout, jobs: JobStore) -> Self {
        Self {
            layout,
            jobs,
            journal: None,
            pending: None,
        }
    }

    /// Create or reopen an immutable direct generated-file transfer.
    ///
    /// # Errors
    ///
    /// Returns an error for changed request/session/destination or inaccessible storage.
    pub fn prepare(
        &mut self,
        request: ExportRequest,
        accepted: ExportAccepted,
        session: TransferSession,
    ) -> Result<(), ClientError> {
        let destination = request
            .destination
            .as_ref()
            .ok_or_else(|| invalid("file request has no destination"))?;
        let accepted_dates = &accepted.resolved_date_identifiers;
        if request.response_mode != ResponseMode::WriteFiles
            || request.raw_profile.is_some()
            || request.job_id != accepted.job_id
            || request.job_id != session.job_id
            || session.peer_binding != accepted.peer_binding
            || accepted_dates.is_empty()
            || accepted_dates.len() > MAXIMUM_DATES_PER_JOB
            || accepted_dates.windows(2).any(|pair| pair[0] >= pair[1])
            || accepted_dates.iter().any(|date| !is_source_date(date))
            || !safe_peer_metadata(&accepted.source_device_name, 128)
            || !valid_time_zone(&accepted.source_time_zone_identifier)
            || request_fingerprint(&request).map_err(|_| invalid("fingerprint failed"))?
                != session.request_fingerprint
        {
            return Err(invalid(
                "file request, acceptance, and session do not agree",
            ));
        }
        let root = validated_root(&destination.root_path)?;
        let identity = destination_identity(&root)?;
        let directory = self.session_directory(request.job_id.0)?;
        let path = directory.join("file-journal.json");
        let journal = if path.exists() {
            let persisted = load_journal(&path)?;
            if persisted.version != JOURNAL_VERSION
                || persisted.request != request
                || persisted.session != session
                || persisted.destination_identity != identity
                || persisted.accepted.peer_binding != accepted.peer_binding
                || persisted.accepted.resolved_date_identifiers
                    != accepted.resolved_date_identifiers
                || persisted.accepted.source_device_name != accepted.source_device_name
                || persisted.accepted.source_time_zone_identifier
                    != accepted.source_time_zone_identifier
                || persisted.accepted.resolved_canonical_selection
                    != accepted.resolved_canonical_selection
            {
                return Err(invalid("durable file session changed"));
            }
            persisted
        } else {
            let journal = FileJournal {
                version: JOURNAL_VERSION,
                request,
                accepted,
                session,
                destination_identity: identity,
                manifests: BTreeMap::new(),
                committed_partitions: Vec::new(),
                commit_plans: BTreeMap::new(),
                outcome: None,
                updated_at: Utc::now(),
            };
            save_journal(&self.layout, &journal)?;
            journal
        };
        validate_persisted_limits(&journal)?;
        let _ = fs::remove_file(directory.join("file-pending.partition"));
        self.pending = None;
        self.journal = Some(journal.clone());
        let mut record = self.jobs.load(journal.request.job_id.0)?;
        record.state = JobState::Preparing;
        record.updated_at = Utc::now();
        record.peer_binding = Some(journal.session.peer_binding.clone());
        record.session_id = Some(journal.session.session_id);
        record.request_fingerprint = Some(journal.session.request_fingerprint.clone());
        record.total_days = Some(
            i64::try_from(journal.accepted.resolved_date_identifiers.len())
                .map_err(|_| invalid("too many dates"))?,
        );
        record.message = Some("iPhone accepted the direct file export.".into());
        self.jobs.save(&record)
    }

    /// Durably store an immutable safe file manifest.
    ///
    /// # Errors
    ///
    /// Returns an error for unsafe paths, bad digest/count, changed manifest, or storage failure.
    pub fn store_manifest(&mut self, manifest: FileManifest) -> Result<(), ClientError> {
        validate_generated_relative_path(&manifest.relative_path)?;
        if manifest.byte_count < 0 || !is_sha256(&manifest.sha256) {
            return Err(invalid("file manifest is invalid"));
        }
        let journal = self
            .journal
            .as_mut()
            .ok_or_else(|| invalid("file receiver is not prepared"))?;
        if manifest.job_id != journal.request.job_id
            || journal
                .manifests
                .get(&manifest.file_id)
                .is_some_and(|saved| saved != &manifest)
            || journal.manifests.values().any(|saved| {
                saved.file_id != manifest.file_id
                    && generated_paths_conflict(&saved.relative_path, &manifest.relative_path)
            })
            || (!journal.manifests.contains_key(&manifest.file_id)
                && journal.manifests.len() >= MAXIMUM_GENERATED_FILES_PER_JOB)
        {
            return Err(invalid("file manifest changed or exceeds receiver limits"));
        }
        let other_bytes = journal
            .manifests
            .iter()
            .filter(|(file_id, _)| **file_id != manifest.file_id)
            .try_fold(0_u64, |total, (_, saved)| {
                total
                    .checked_add(
                        u64::try_from(saved.byte_count)
                            .map_err(|_| invalid("file manifest byte count is invalid"))?,
                    )
                    .ok_or_else(|| invalid("file manifest byte total overflow"))
            })?;
        let manifest_bytes = u64::try_from(manifest.byte_count)
            .map_err(|_| invalid("file manifest byte count is invalid"))?;
        ensure_job_bytes(
            other_bytes
                .checked_add(manifest_bytes)
                .ok_or_else(|| invalid("file manifest byte total overflow"))?,
        )?;
        let binding = journal
            .request
            .destination
            .as_ref()
            .ok_or_else(|| invalid("generated-file destination binding is missing"))?;
        let destination = GeneratedDestination::open(Path::new(&binding.root_path))?
            .with_private_storage_root(&self.layout.root);
        destination.validate_stage_admission(
            &manifest.relative_path,
            manifest_bytes,
            manifest.write_mode,
            2,
        )?;
        journal.manifests.insert(manifest.file_id, manifest);
        journal.updated_at = Utc::now();
        save_journal(&self.layout, journal)
    }

    /// Decide whether an exact file partition is needed or already committed.
    ///
    /// # Errors
    ///
    /// Returns an error for changed/out-of-order/invalid descriptors or storage failure.
    pub fn disposition(&mut self, open: TransferOpen) -> Result<TransferDisposition, ClientError> {
        let layout = self.layout.clone();
        let journal = self
            .journal
            .as_mut()
            .ok_or_else(|| invalid("file receiver is not prepared"))?;
        validate_open(&open, journal)?;
        let descriptor = open.partition;
        let index =
            usize::try_from(descriptor.index).map_err(|_| invalid("negative partition index"))?;
        if index < journal.committed_partitions.len() {
            if journal.committed_partitions[index] != descriptor {
                return Err(invalid("committed file partition changed"));
            }
            let durable = partition_matches(
                &partition_path(&self.layout, open.session.job_id.0, descriptor.index)?,
                &descriptor,
            )?;
            if durable {
                return Ok(TransferDisposition {
                    session_id: open.session.session_id,
                    job_id: open.session.job_id,
                    partition_index: descriptor.index,
                    partition_sha256: descriptor.sha256,
                    disposition: TransferDispositionKind::AlreadyCommitted,
                    message: Some(
                        "Partition already committed by the durable CLI receiver.".into(),
                    ),
                });
            }
            let stale: Vec<_> = journal.committed_partitions.drain(index..).collect();
            for partition in stale {
                remove_if_present(&partition_path(
                    &self.layout,
                    open.session.job_id.0,
                    partition.index,
                )?)?;
            }
            journal.updated_at = Utc::now();
            save_journal(&self.layout, journal)?;
        }
        if index != journal.committed_partitions.len() {
            return Err(invalid("file partition arrived out of order"));
        }
        let directory = session_directory(&layout, open.session.job_id.0)?;
        let committed_bytes =
            journal
                .committed_partitions
                .iter()
                .try_fold(0_u64, |total, partition| {
                    total
                        .checked_add(
                            u64::try_from(partition.byte_count)
                                .map_err(|_| invalid("partition byte count is invalid"))?,
                        )
                        .ok_or_else(|| invalid("partition byte total overflow"))
                })?;
        let storage_reservation = reserve_partition_capacity(
            &layout.root,
            &directory,
            committed_bytes,
            u64::try_from(descriptor.byte_count)
                .map_err(|_| invalid("partition byte count is invalid"))?,
        )?;
        let path = directory.join("file-pending.partition");
        let file = private_file(&path)?;
        file.set_len(0).map_err(storage_error)?;
        file.sync_all().map_err(storage_error)?;
        self.pending = Some(PendingPartition {
            descriptor: descriptor.clone(),
            path,
            next_sequence: 1,
            received_bytes: 0,
            _storage_reservation: storage_reservation,
        });
        Ok(TransferDisposition {
            session_id: open.session.session_id,
            job_id: open.session.job_id,
            partition_index: descriptor.index,
            partition_sha256: descriptor.sha256,
            disposition: TransferDispositionKind::Needed,
            message: None,
        })
    }

    /// Append and fsync one authenticated binary file chunk.
    ///
    /// # Errors
    ///
    /// Returns an error for sequence/ID/digest/size mismatch or storage failure.
    pub fn receive_chunk(
        &mut self,
        chunk: TransferChunk,
    ) -> Result<TransferChunkAcknowledgement, ClientError> {
        let pending = self
            .pending
            .as_mut()
            .ok_or_else(|| invalid("no file partition is open"))?;
        let count = i64::try_from(chunk.data.len()).map_err(|_| invalid("chunk too large"))?;
        if chunk.transfer_id != pending.descriptor.transfer_id
            || chunk.sequence != pending.next_sequence
            || chunk.data.len() > TRANSFER_FRAME_BYTES
            || sha256_hex(&chunk.data) != chunk.sha256
            || pending.received_bytes + count > pending.descriptor.byte_count
        {
            return Err(invalid("file chunk failed validation"));
        }
        let mut output = fs::OpenOptions::new()
            .append(true)
            .open(&pending.path)
            .map_err(storage_error)?;
        output.write_all(&chunk.data).map_err(storage_error)?;
        output.sync_data().map_err(storage_error)?;
        pending.next_sequence += 1;
        pending.received_bytes += count;
        Ok(TransferChunkAcknowledgement {
            transfer_id: chunk.transfer_id,
            sequence: chunk.sequence,
            accepted: true,
            sha256: chunk.sha256,
            message: None,
        })
    }

    /// Verify and commit one complete file partition to the durable spool.
    ///
    /// # Errors
    ///
    /// Returns an error for completion/count/digest mismatch or storage failure.
    pub fn commit_partition(
        &mut self,
        complete: TransferPartitionComplete,
    ) -> Result<TransferPartitionAcknowledgement, ClientError> {
        let mut journal = self
            .journal
            .take()
            .ok_or_else(|| invalid("file receiver is not prepared"))?;
        let pending = self
            .pending
            .take()
            .ok_or_else(|| invalid("no file partition is open"))?;
        if complete.session_id != journal.session.session_id
            || complete.job_id != journal.request.job_id
            || complete.partition_index != pending.descriptor.index
            || complete.transfer_id != pending.descriptor.transfer_id
            || complete.partition_sha256 != pending.descriptor.sha256
            || pending.next_sequence - 1 != pending.descriptor.chunk_count
            || pending.received_bytes != pending.descriptor.byte_count
        {
            self.journal = Some(journal);
            self.pending = Some(pending);
            return Err(invalid("file partition completion mismatch"));
        }
        let (bytes, digest) = inspect_file(&pending.path)?;
        if bytes != pending.descriptor.byte_count || digest != pending.descriptor.sha256 {
            self.journal = Some(journal);
            self.pending = Some(pending);
            return Err(invalid("file partition digest mismatch"));
        }
        let destination = partition_path(
            &self.layout,
            journal.request.job_id.0,
            pending.descriptor.index,
        )?;
        let _ = fs::remove_file(&destination);
        fs::rename(&pending.path, &destination).map_err(storage_error)?;
        journal
            .committed_partitions
            .push(pending.descriptor.clone());
        journal.updated_at = Utc::now();
        save_journal(&self.layout, &journal)?;
        let mut record = self.jobs.load(journal.request.job_id.0)?;
        record.state = JobState::Transferring;
        record.updated_at = Utc::now();
        record.committed_partitions = i64::try_from(journal.committed_partitions.len())
            .map_err(|_| invalid("too many partitions"))?;
        record.committed_bytes = checked_byte_total(
            journal
                .committed_partitions
                .iter()
                .map(|part| part.byte_count),
        )?;
        record.message = Some(format!(
            "Committed direct file partition {}.",
            pending.descriptor.index + 1
        ));
        self.jobs.save(&record)?;
        self.journal = Some(journal);
        Ok(TransferPartitionAcknowledgement {
            session_id: complete.session_id,
            job_id: complete.job_id,
            partition_index: complete.partition_index,
            transfer_id: complete.transfer_id,
            partition_sha256: complete.partition_sha256,
            accepted: true,
            message: None,
        })
    }

    /// Validate, transactionally commit generated files, and persist a receipt.
    ///
    /// # Errors
    ///
    /// Returns an error for incomplete corpus/finalization, destination mutation, unsafe paths,
    /// merge bounds, or storage failure.
    #[allow(clippy::too_many_lines)]
    pub fn finalize(
        &mut self,
        finalize: &TransferFinalize,
    ) -> Result<FileExportReceipt, ClientError> {
        let mut journal = self
            .journal
            .take()
            .ok_or_else(|| invalid("file receiver is not prepared"))?;
        let total_bytes = checked_byte_total(
            journal
                .committed_partitions
                .iter()
                .map(|part| part.byte_count),
        )?;
        ensure_job_bytes(
            u64::try_from(total_bytes)
                .map_err(|_| invalid("final transfer byte count is invalid"))?,
        )?;
        if finalize.session_id != journal.session.session_id
            || finalize.job_id != journal.request.job_id
            || finalize.request_fingerprint != journal.session.request_fingerprint
            || finalize.total_partitions
                != i64::try_from(journal.committed_partitions.len())
                    .map_err(|_| invalid("too many partitions"))?
            || finalize.total_bytes != total_bytes
            || finalize.final_partition_sha256
                != journal
                    .committed_partitions
                    .last()
                    .map(|part| part.sha256.clone())
        {
            self.journal = Some(journal);
            return Err(invalid("file finalization mismatch"));
        }
        validate_complete_corpus(&self.layout, &journal)?;
        let resolved_count = i64::try_from(journal.accepted.resolved_date_identifiers.len())
            .map_err(|_| invalid("too many accepted dates"))?;
        let outcome = finalize.outcome.clone().unwrap_or(ExportOutcome {
            status: "success".into(),
            success_count: resolved_count,
            total_count: resolved_count,
            failed_date_identifiers: Vec::new(),
        });
        let unique_failures: std::collections::BTreeSet<_> =
            outcome.failed_date_identifiers.iter().collect();
        if !matches!(outcome.status.as_str(), "success" | "partial_success")
            || outcome.success_count < 0
            || outcome.total_count != resolved_count
            || outcome.total_count < outcome.success_count
            || i64::try_from(outcome.failed_date_identifiers.len()).ok()
                != Some(outcome.total_count - outcome.success_count)
            || (outcome.status == "success"
                && (outcome.success_count != outcome.total_count
                    || !outcome.failed_date_identifiers.is_empty()))
            || (outcome.status == "partial_success" && outcome.success_count == outcome.total_count)
            || outcome.failed_date_identifiers.len() > MAXIMUM_DATES_PER_JOB
            || unique_failures.len() != outcome.failed_date_identifiers.len()
            || outcome
                .failed_date_identifiers
                .iter()
                .any(|date| !journal.accepted.resolved_date_identifiers.contains(date))
        {
            self.journal = Some(journal);
            return Err(invalid("file outcome is invalid"));
        }
        journal.outcome = Some(outcome.clone());
        let mut manifests: Vec<_> = journal.manifests.values().cloned().collect();
        manifests.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
        for manifest in &manifests {
            commit_file(&self.layout, manifest, &mut journal)?;
        }
        let receipt = make_receipt(&self.layout, &journal)?;
        let mut record = self.jobs.load(journal.request.job_id.0)?;
        record.state = JobState::AwaitingPeerAcknowledgement;
        record.updated_at = Utc::now();
        record.committed_partitions = finalize.total_partitions;
        record.committed_bytes = finalize.total_bytes;
        record.processed_days = outcome.success_count;
        record.total_days = Some(outcome.total_count);
        record.message =
            Some("Direct file receipt committed; awaiting iPhone acknowledgement.".into());
        record.response_artifact = Some(ResponseArtifact {
            relative_path: receipt
                .response_path
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| invalid("receipt path is invalid"))?
                .into(),
            byte_count: receipt.response_byte_count,
            sha256: receipt.response_sha256.clone(),
            date_range_start: journal
                .accepted
                .resolved_date_identifiers
                .first()
                .cloned()
                .unwrap_or_default(),
            date_range_end: journal
                .accepted
                .resolved_date_identifiers
                .last()
                .cloned()
                .unwrap_or_default(),
            total_days: record.total_days.unwrap_or_default(),
        });
        self.jobs.save(&record)?;
        self.journal = Some(journal);
        Ok(receipt)
    }

    /// Mark the committed file job complete after iPhone confirms the final acknowledgement.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is not awaiting confirmation or cannot be saved.
    pub fn acknowledge_peer_completion(&self, job_id: Uuid) -> Result<(), ClientError> {
        let mut record = self.jobs.load(job_id)?;
        if record.state != JobState::AwaitingPeerAcknowledgement
            || record.response_artifact.is_none()
        {
            return Err(invalid("file job is not awaiting peer confirmation"));
        }
        record.state = JobState::Completed;
        record.updated_at = Utc::now();
        record.message = Some("Direct file export completed and acknowledged by iPhone.".into());
        self.jobs.save(&record)
    }

    /// Reopen and digest-validate a durable generated-file receipt.
    ///
    /// # Errors
    ///
    /// Returns an error when the job/receipt is absent, malformed, changed, or inaccessible.
    pub fn receipt(&self, job_id: Uuid) -> Result<FileExportReceipt, ClientError> {
        let record = self.jobs.load(job_id)?;
        let artifact = record
            .response_artifact
            .ok_or_else(|| invalid("file receipt is missing"))?;
        let path = self
            .layout
            .response_spools_dir()
            .join(job_id.to_string().to_lowercase())
            .join(artifact.relative_path);
        let (bytes, digest) = inspect_file(&path)?;
        if bytes != artifact.byte_count || digest != artifact.sha256 {
            return Err(invalid("file receipt digest changed"));
        }
        let payload: FileReceiptPayload = serde_json::from_slice(&read_bounded(
            &path,
            MAXIMUM_DURABLE_JSON_BYTES,
            "file receipt exceeds the durable metadata limit",
        )?)
        .map_err(|_| invalid("file receipt is malformed"))?;
        Ok(FileExportReceipt {
            payload,
            response_path: path,
            response_byte_count: bytes,
            response_sha256: digest,
        })
    }

    #[must_use]
    pub fn final_acknowledgement(
        finalize: &TransferFinalize,
        receipt: &FileExportReceipt,
    ) -> TransferFinalAcknowledgement {
        TransferFinalAcknowledgement {
            session_id: finalize.session_id,
            job_id: finalize.job_id,
            accepted: true,
            total_partitions: finalize.total_partitions,
            total_bytes: finalize.total_bytes,
            final_partition_sha256: finalize.final_partition_sha256.clone(),
            response_byte_count: Some(receipt.response_byte_count),
            response_sha256: Some(receipt.response_sha256.clone()),
            message: Some("CLI committed generated files to the explicit destination.".into()),
        }
    }

    fn session_directory(&self, job_id: Uuid) -> Result<PathBuf, ClientError> {
        session_directory(&self.layout, job_id)
    }
}

fn safe_peer_metadata(value: &str, maximum_bytes: usize) -> bool {
    !value.trim().is_empty() && value.len() <= maximum_bytes && !value.chars().any(char::is_control)
}

fn valid_time_zone(value: &str) -> bool {
    value.len() <= 64 && value.parse::<chrono_tz::Tz>().is_ok()
}

fn validate_persisted_limits(journal: &FileJournal) -> Result<(), ClientError> {
    if journal.manifests.len() > MAXIMUM_GENERATED_FILES_PER_JOB
        || journal.commit_plans.len() > journal.manifests.len()
        || u64::try_from(journal.committed_partitions.len()).unwrap_or(u64::MAX)
            > MAXIMUM_PARTITIONS_PER_JOB
    {
        return Err(invalid("durable file journal exceeds receiver limits"));
    }
    let manifests: Vec<_> = journal.manifests.iter().collect();
    for (index, (file_id, manifest)) in manifests.iter().enumerate() {
        if **file_id != manifest.file_id
            || manifest.job_id != journal.request.job_id
            || manifest.byte_count < 0
            || !is_sha256(&manifest.sha256)
        {
            return Err(invalid("durable file manifest is invalid"));
        }
        validate_generated_relative_path(&manifest.relative_path)?;
        if manifests.iter().skip(index + 1).any(|(_, other)| {
            generated_paths_conflict(&manifest.relative_path, &other.relative_path)
        }) {
            return Err(invalid("durable generated destinations collide"));
        }
    }
    for (file_id, plan) in &journal.commit_plans {
        let manifest = journal
            .manifests
            .get(file_id)
            .ok_or_else(|| invalid("durable file commit plan has no manifest"))?;
        let expected_stage = format!("file-output-{}.stage", file_id.0.to_string().to_lowercase());
        if *file_id != plan.file_id
            || plan.destination_relative_path != manifest.relative_path
            || plan.staged_relative_path != expected_stage
            || plan
                .before_sha256
                .as_ref()
                .is_some_and(|digest| !is_sha256(digest))
            || !is_sha256(&plan.after_sha256)
        {
            return Err(invalid("durable file commit plan is invalid"));
        }
    }
    let manifest_bytes = journal
        .manifests
        .values()
        .try_fold(0_u64, |total, manifest| {
            total
                .checked_add(
                    u64::try_from(manifest.byte_count)
                        .map_err(|_| invalid("durable manifest byte count is invalid"))?,
                )
                .ok_or_else(|| invalid("durable manifest byte total overflow"))
        })?;
    let partition_bytes =
        journal
            .committed_partitions
            .iter()
            .try_fold(0_u64, |total, partition| {
                total
                    .checked_add(
                        u64::try_from(partition.byte_count)
                            .map_err(|_| invalid("durable partition byte count is invalid"))?,
                    )
                    .ok_or_else(|| invalid("durable partition byte total overflow"))
            })?;
    ensure_job_bytes(manifest_bytes)?;
    ensure_job_bytes(partition_bytes)
}

fn validate_open(open: &TransferOpen, journal: &FileJournal) -> Result<(), ClientError> {
    let descriptor = &open.partition;
    if descriptor.index < 0
        || u64::try_from(descriptor.index).unwrap_or(u64::MAX) >= MAXIMUM_PARTITIONS_PER_JOB
        || descriptor.byte_count < 0
        || descriptor.byte_count > 64 * 1_024 * 1_024
    {
        return Err(invalid("file partition descriptor exceeds receiver limits"));
    }
    let segment = descriptor
        .item_segment
        .as_ref()
        .ok_or_else(|| invalid("file partition has no segment"))?;
    let file_id =
        Uuid::parse_str(&segment.item_id).map_err(|_| invalid("file segment ID is invalid"))?;
    let manifest = journal
        .manifests
        .get(&SwiftUuid(file_id))
        .ok_or_else(|| invalid("file manifest is missing"))?;
    let expected_chunks = if descriptor.byte_count == 0 {
        0
    } else {
        (descriptor.byte_count + i64::try_from(TRANSFER_FRAME_BYTES).unwrap() - 1)
            / i64::try_from(TRANSFER_FRAME_BYTES).unwrap()
    };
    let expected_previous = journal
        .committed_partitions
        .last()
        .map(|part| part.sha256.as_str());
    let segment_end = segment.offset.checked_add(descriptor.byte_count);
    let valid = open.session == journal.session
        && descriptor.chunk_count == expected_chunks
        && is_sha256(&descriptor.sha256)
        && descriptor.source_dates == [segment.item_id.clone()]
        && manifest.byte_count == segment.item_byte_count
        && segment.offset >= 0
        && segment_end.is_some_and(|end| end <= segment.item_byte_count)
        && segment.is_final_segment == (segment_end == Some(segment.item_byte_count))
        && (usize::try_from(descriptor.index).ok() != Some(journal.committed_partitions.len())
            || descriptor.previous_sha256.as_deref() == expected_previous);
    if !valid {
        return Err(invalid("file partition descriptor is invalid"));
    }
    Ok(())
}

fn validate_complete_corpus(
    layout: &StorageLayout,
    journal: &FileJournal,
) -> Result<(), ClientError> {
    let mut grouped: BTreeMap<SwiftUuid, Vec<&TransferPartition>> = BTreeMap::new();
    for descriptor in &journal.committed_partitions {
        let id = descriptor
            .item_segment
            .as_ref()
            .and_then(|segment| Uuid::parse_str(&segment.item_id).ok())
            .map(SwiftUuid)
            .ok_or_else(|| invalid("file partition item ID is invalid"))?;
        if !journal.manifests.contains_key(&id) {
            return Err(invalid("file partition has no manifest"));
        }
        grouped.entry(id).or_default().push(descriptor);
    }
    for manifest in journal.manifests.values() {
        let descriptors = grouped.get(&manifest.file_id).cloned().unwrap_or_default();
        if manifest.byte_count == 0 {
            if !descriptors.is_empty() || manifest.sha256 != sha256_hex(&[]) {
                return Err(invalid("empty file has invalid partitions"));
            }
            continue;
        }
        let mut offset = 0_i64;
        let mut hasher = Sha256::new();
        for descriptor in &descriptors {
            let segment = descriptor.item_segment.as_ref().unwrap();
            if segment.offset != offset || segment.item_byte_count != manifest.byte_count {
                return Err(invalid("file segments are discontinuous"));
            }
            let mut input = File::open(partition_path(
                layout,
                journal.request.job_id.0,
                descriptor.index,
            )?)
            .map_err(storage_error)?;
            io::copy(&mut input, &mut HashWriter(&mut hasher)).map_err(storage_error)?;
            offset += descriptor.byte_count;
        }
        if offset != manifest.byte_count
            || descriptors
                .last()
                .and_then(|part| part.item_segment.as_ref())
                .is_none_or(|segment| !segment.is_final_segment)
            || hex(&hasher.finalize()) != manifest.sha256
        {
            return Err(invalid("file corpus digest is incomplete"));
        }
    }
    Ok(())
}

#[allow(clippy::too_many_lines)]
fn commit_file(
    layout: &StorageLayout,
    manifest: &FileManifest,
    journal: &mut FileJournal,
) -> Result<(), ClientError> {
    let root_path = &journal
        .request
        .destination
        .as_ref()
        .ok_or_else(|| invalid("destination missing"))?
        .root_path;
    let root = validated_root(root_path)?;
    if destination_identity(&root)? != journal.destination_identity {
        return Err(invalid("destination root identity changed"));
    }
    let relative = validate_generated_relative_path(&manifest.relative_path)?;
    let capability = Dir::open_ambient_dir(&root, ambient_authority()).map_err(storage_error)?;
    let (parent, name) = open_safe_parent(capability, &relative)?;
    let current = digest_cap_file(&parent, &name)?;
    if let Some(plan) = journal.commit_plans.get(&manifest.file_id).cloned() {
        let staged = session_directory(layout, journal.request.job_id.0)?.join(format!(
            "file-output-{}.stage",
            manifest.file_id.0.to_string().to_lowercase()
        ));
        let (staged_bytes, staged_digest) = inspect_file(&staged)?;
        ensure_job_bytes(
            u64::try_from(staged_bytes)
                .map_err(|_| invalid("staged file byte count is invalid"))?,
        )?;
        if staged_digest != plan.after_sha256 {
            return Err(invalid("durable file commit stage digest changed"));
        }
        if current.as_deref() == Some(&plan.after_sha256) {
            if !plan.committed {
                let mut committed = plan;
                committed.committed = true;
                journal.commit_plans.insert(manifest.file_id, committed);
                save_journal(layout, journal)?;
            }
            return Ok(());
        }
        if current != plan.before_sha256 {
            return Err(invalid("destination changed during file commit"));
        }
        install_stage(
            &parent,
            &name,
            &staged,
            current.as_deref(),
            &plan.after_sha256,
            &root.join(&relative),
            Some(&layout.root),
        )?;
        if digest_cap_file(&parent, &name)?.as_deref() != Some(&plan.after_sha256) {
            return Err(invalid("destination digest failed after commit"));
        }
        let mut committed = plan;
        committed.committed = true;
        journal.commit_plans.insert(manifest.file_id, committed);
        save_journal(layout, journal)?;
        return Ok(());
    }

    let source = assemble_source(layout, journal, manifest)?;
    let stage_name = format!(
        "file-output-{}.stage",
        manifest.file_id.0.to_string().to_lowercase()
    );
    let stage = session_directory(layout, journal.request.job_id.0)?.join(&stage_name);
    build_stage(
        &parent,
        &name,
        current.is_some(),
        &source,
        &stage,
        manifest.write_mode,
        b"\n\n",
        Some(&layout.root),
    )?;
    let (_, after) = inspect_file(&stage)?;
    let plan = CommitPlan {
        file_id: manifest.file_id,
        destination_relative_path: manifest.relative_path.clone(),
        before_sha256: current.clone(),
        after_sha256: after.clone(),
        staged_relative_path: stage_name,
        committed: false,
    };
    journal.commit_plans.insert(manifest.file_id, plan.clone());
    journal.updated_at = Utc::now();
    save_journal(layout, journal)?;
    install_stage(
        &parent,
        &name,
        &stage,
        current.as_deref(),
        &after,
        &root.join(&relative),
        Some(&layout.root),
    )?;
    if digest_cap_file(&parent, &name)?.as_deref() != Some(&after) {
        return Err(invalid("destination digest failed after commit"));
    }
    let mut committed = plan;
    committed.committed = true;
    journal.commit_plans.insert(manifest.file_id, committed);
    journal.updated_at = Utc::now();
    save_journal(layout, journal)
}

#[allow(clippy::too_many_arguments)]
fn build_stage(
    parent: &Dir,
    name: &Path,
    exists: bool,
    source: &Path,
    stage: &Path,
    mode: FileWriteMode,
    append_separator: &[u8],
    private_storage_root: Option<&Path>,
) -> Result<(), ClientError> {
    let source_bytes = fs::metadata(source).map_err(storage_error)?.len();
    let existing_bytes = if exists && mode != FileWriteMode::Overwrite {
        open_regular_cap_file(parent, name)?
            .metadata()
            .map_err(storage_error)?
            .len()
    } else {
        0
    };
    if mode != FileWriteMode::Overwrite && existing_bytes > source_bytes {
        return Err(invalid(
            "existing destination exceeds bounded stage amplification",
        ));
    }
    let separator_bytes = if exists && mode == FileWriteMode::Append {
        u64::try_from(append_separator.len()).unwrap_or(u64::MAX)
    } else {
        0
    };
    let stage_bytes = source_bytes
        .checked_add(existing_bytes)
        .and_then(|bytes| bytes.checked_add(separator_bytes))
        .ok_or_else(|| invalid("generated stage byte total overflow"))?;
    ensure_job_bytes(stage_bytes)?;
    let stage_parent = stage
        .parent()
        .ok_or_else(|| invalid("generated stage has no parent"))?;
    let _storage_reservation = if let Some(storage_root) = private_storage_root {
        Some(reserve_materialization_storage(
            storage_root,
            stage_parent,
            stage_bytes,
        )?)
    } else {
        ensure_available_space(stage_parent, stage_bytes)?;
        None
    };
    let mut output = private_file(stage)?;
    output.set_len(0).map_err(storage_error)?;
    match mode {
        FileWriteMode::Append if exists => {
            let mut current = open_regular_cap_file(parent, name)?;
            io::copy(&mut current, &mut output).map_err(storage_error)?;
            output.write_all(append_separator).map_err(storage_error)?;
        }
        FileWriteMode::MergeMarkdown | FileWriteMode::MergeMarkdownPreservingPreamble if exists => {
            if fs::metadata(source).map_err(storage_error)?.len()
                > u64::try_from(MAXIMUM_MERGE_BYTES).unwrap()
            {
                return Err(invalid("Markdown merge exceeds 64 MiB"));
            }
            let source_bytes = fs::read(source).map_err(storage_error)?;
            let current = open_regular_cap_file(parent, name)?;
            let mut existing = Vec::new();
            current
                .take(u64::try_from(MAXIMUM_MERGE_BYTES + 1).unwrap())
                .read_to_end(&mut existing)
                .map_err(storage_error)?;
            if i64::try_from(existing.len()).unwrap_or(i64::MAX) > MAXIMUM_MERGE_BYTES
                || i64::try_from(source_bytes.len()).unwrap_or(i64::MAX) > MAXIMUM_MERGE_BYTES
            {
                return Err(invalid("Markdown merge exceeds 64 MiB"));
            }
            let existing = String::from_utf8(existing)
                .map_err(|_| invalid("existing Markdown is not UTF-8"))?;
            let new = String::from_utf8(source_bytes)
                .map_err(|_| invalid("generated Markdown is not UTF-8"))?;
            let merged = markdown::merge(
                &existing,
                &new,
                mode == FileWriteMode::MergeMarkdownPreservingPreamble,
            );
            if u64::try_from(merged.len()).unwrap_or(u64::MAX) > stage_bytes {
                return Err(invalid("Markdown merge exceeds its admitted stage size"));
            }
            output.write_all(merged.as_bytes()).map_err(storage_error)?;
            output.sync_all().map_err(storage_error)?;
            return Ok(());
        }
        _ => {}
    }
    let mut input = File::open(source).map_err(storage_error)?;
    io::copy(&mut input, &mut output).map_err(storage_error)?;
    output.sync_all().map_err(storage_error)
}

fn install_stage(
    parent: &Dir,
    name: &Path,
    stage: &Path,
    expected_before: Option<&str>,
    expected_after: &str,
    destination_path: &Path,
    private_storage_root: Option<&Path>,
) -> Result<(), ClientError> {
    if digest_cap_file(parent, name)?.as_deref() != expected_before {
        return Err(invalid("destination changed before atomic install"));
    }
    let stage_bytes = fs::metadata(stage).map_err(storage_error)?.len();
    ensure_job_bytes(stage_bytes)?;
    let destination_parent = destination_path
        .parent()
        .ok_or_else(|| invalid("destination file has no parent"))?;
    let _output_reservation = if let Some(storage_root) = private_storage_root {
        Some(reserve_output_capacity(
            storage_root,
            destination_parent,
            stage_bytes,
        )?)
    } else {
        ensure_available_space(destination_parent, stage_bytes)?;
        None
    };

    #[cfg(windows)]
    {
        let destination_parent = destination_path
            .parent()
            .ok_or_else(|| invalid("destination file has no parent"))?;
        let mut temporary = NamedTempFile::new_in(destination_parent).map_err(storage_error)?;
        set_private_file(temporary.as_file())?;
        fs2::FileExt::allocate(temporary.as_file(), stage_bytes).map_err(storage_error)?;
        let mut input = File::open(stage).map_err(storage_error)?;
        io::copy(&mut input, &mut temporary).map_err(storage_error)?;
        temporary
            .as_file()
            .set_len(stage_bytes)
            .map_err(storage_error)?;
        temporary.as_file().sync_all().map_err(storage_error)?;
        if digest_seekable(temporary.as_file_mut())? != expected_after {
            return Err(invalid("staged destination digest changed"));
        }
        if digest_cap_file(parent, name)?.as_deref() != expected_before {
            return Err(invalid("destination changed during atomic install"));
        }
        if let Some(expected_before) = expected_before {
            replace_existing_windows(
                temporary,
                destination_path,
                expected_before,
                expected_after,
                parent,
                name,
            )?;
        } else {
            temporary
                .persist_noclobber(destination_path)
                .map_err(|error| storage_error(error.error))?;
        }
        sync_cap_directory(parent)
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
        let temporary_name = format!(".healthmd-{}.tmp", Uuid::new_v4());
        let mut options = OpenOptions::new();
        options.read(true).write(true).create_new(true);
        let mut temporary = parent
            .open_with(&temporary_name, &options)
            .map_err(storage_error)?
            .into_std();
        fs2::FileExt::allocate(&temporary, stage_bytes).map_err(storage_error)?;
        let mut input = File::open(stage).map_err(storage_error)?;
        io::copy(&mut input, &mut temporary).map_err(storage_error)?;
        temporary.set_len(stage_bytes).map_err(storage_error)?;
        temporary.sync_all().map_err(storage_error)?;
        if digest_seekable(&mut temporary)? != expected_after {
            let _ = parent.remove_file(&temporary_name);
            return Err(invalid("staged destination digest changed"));
        }
        if digest_cap_file(parent, name)?.as_deref() != expected_before {
            let _ = parent.remove_file(&temporary_name);
            return Err(invalid("destination changed during atomic install"));
        }
        if let Some(expected_before) = expected_before {
            exchange_existing_stage(parent, &temporary_name, name, expected_before)
        } else {
            renameat_with(
                parent,
                temporary_name.as_str(),
                parent,
                name,
                RenameFlags::NOREPLACE,
            )
            .map_err(rustix_storage_error)?;
            sync_cap_directory(parent)
        }
    }
}

#[cfg(windows)]
fn windows_verbatim_text(path: &Path) -> Result<String, ClientError> {
    let text = path
        .to_str()
        .ok_or_else(|| invalid("Windows destination path is not UTF-8"))?;
    if text.starts_with(r"\\?\") {
        Ok(text.into())
    } else if let Some(unc) = text.strip_prefix(r"\\") {
        Ok(format!(r"\\?\UNC\{unc}"))
    } else {
        Ok(format!(r"\\?\{text}"))
    }
}

#[cfg(windows)]
fn replace_existing_windows(
    temporary: NamedTempFile,
    destination: &Path,
    expected_before: &str,
    expected_after: &str,
    parent: &Dir,
    name: &Path,
) -> Result<(), ClientError> {
    let directory = destination
        .parent()
        .ok_or_else(|| invalid("destination file has no parent"))?;
    let backup = directory.join(format!(".healthmd-backup-{}.tmp", Uuid::new_v4()));
    let replacement = temporary.into_temp_path();
    let destination_text = windows_verbatim_text(destination)?;
    let replacement_text = windows_verbatim_text(&replacement)?;
    let backup_text = windows_verbatim_text(&backup)?;
    let flags = winsafe::co::REPLACEFILE::WRITE_THROUGH;
    winsafe::ReplaceFile(
        &destination_text,
        &replacement_text,
        Some(&backup_text),
        flags,
    )
    .map_err(|_| invalid("atomic Windows destination replacement failed"))?;

    let Ok((_, displaced_digest)) = inspect_file(&backup) else {
        return Err(invalid(
            "atomic Windows replacement could not validate the displaced file; backup retained",
        ));
    };
    if displaced_digest == expected_before {
        fs::remove_file(&backup).map_err(storage_error)?;
        return Ok(());
    }
    if digest_cap_file(parent, name)?.as_deref() != Some(expected_after) {
        return Err(invalid(
            "destination changed during Windows replacement; displaced backup retained",
        ));
    }

    let installed_backup = directory.join(format!(".healthmd-replaced-{}.tmp", Uuid::new_v4()));
    let installed_backup_text = windows_verbatim_text(&installed_backup)?;
    winsafe::ReplaceFile(
        &destination_text,
        &backup_text,
        Some(&installed_backup_text),
        flags,
    )
    .map_err(|_| {
        invalid("destination changed during Windows replacement; rollback backup retained")
    })?;
    fs::remove_file(&installed_backup).map_err(storage_error)?;
    if digest_cap_file(parent, name)?.as_deref() != Some(displaced_digest.as_str()) {
        return Err(invalid("Windows destination rollback integrity failed"));
    }
    Err(invalid(
        "destination changed during atomic Windows replacement",
    ))
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
fn exchange_existing_stage(
    parent: &Dir,
    temporary_name: &str,
    name: &Path,
    expected_before: &str,
) -> Result<(), ClientError> {
    renameat_with(parent, temporary_name, parent, name, RenameFlags::EXCHANGE)
        .map_err(rustix_storage_error)?;
    if digest_cap_file(parent, Path::new(temporary_name))?.as_deref() != Some(expected_before) {
        if renameat_with(parent, temporary_name, parent, name, RenameFlags::EXCHANGE).is_err() {
            return Err(invalid(
                "destination changed during atomic exchange; displaced file was retained",
            ));
        }
        parent.remove_file(temporary_name).map_err(storage_error)?;
        sync_cap_directory(parent)?;
        return Err(invalid("destination changed during atomic exchange"));
    }
    parent.remove_file(temporary_name).map_err(storage_error)?;
    sync_cap_directory(parent)
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
fn sync_cap_directory(directory: &Dir) -> Result<(), ClientError> {
    // cap-std may hold Linux directories through O_PATH. fsync on that descriptor returns EBADF,
    // so open a real read-only directory descriptor relative to the capability before syncing.
    let descriptor = openat(
        directory,
        ".",
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .map_err(rustix_storage_error)?;
    let file: File = descriptor.into();
    file.sync_all().map_err(storage_error)
}

#[cfg(windows)]
#[allow(clippy::unnecessary_wraps)]
fn sync_cap_directory(_directory: &Dir) -> Result<(), ClientError> {
    // Windows directory handles opened by cap-std cannot be flushed as regular files. The staged
    // file itself is synced before the atomic rename; there is no portable directory fsync here.
    Ok(())
}

fn open_safe_parent(mut directory: Dir, relative: &Path) -> Result<(Dir, PathBuf), ClientError> {
    let name = relative
        .file_name()
        .ok_or_else(|| invalid("relative path has no filename"))?
        .into();
    if let Some(parent) = relative.parent() {
        for component in parent.components() {
            let Component::Normal(component) = component else {
                return Err(invalid("unsafe path component"));
            };
            let path = Path::new(component);
            match directory.symlink_metadata(path) {
                Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => {
                    return Err(invalid("destination ancestor is not a regular directory"));
                }
                Ok(_) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    directory.create_dir(path).map_err(storage_error)?;
                }
                Err(error) => return Err(storage_error(error)),
            }
            directory = directory.open_dir_nofollow(path).map_err(storage_error)?;
            let metadata = directory
                .try_clone()
                .map_err(storage_error)?
                .into_std_file()
                .metadata()
                .map_err(storage_error)?;
            if metadata_is_reparse_point(&metadata) || !metadata.is_dir() {
                return Err(invalid("destination ancestor is not a regular directory"));
            }
        }
    }
    Ok((directory, name))
}

fn open_existing_safe_parent(
    mut directory: Dir,
    relative: &Path,
) -> Result<Option<(Dir, PathBuf)>, ClientError> {
    let name = relative
        .file_name()
        .ok_or_else(|| invalid("relative path has no filename"))?
        .into();
    if let Some(parent) = relative.parent() {
        for component in parent.components() {
            let Component::Normal(component) = component else {
                return Err(invalid("unsafe path component"));
            };
            let path = Path::new(component);
            match directory.symlink_metadata(path) {
                Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => {
                    return Err(invalid("destination ancestor is not a regular directory"));
                }
                Ok(_) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
                Err(error) => return Err(storage_error(error)),
            }
            directory = directory.open_dir_nofollow(path).map_err(storage_error)?;
            let metadata = directory
                .try_clone()
                .map_err(storage_error)?
                .into_std_file()
                .metadata()
                .map_err(storage_error)?;
            if metadata_is_reparse_point(&metadata) || !metadata.is_dir() {
                return Err(invalid("destination ancestor is not a regular directory"));
            }
        }
    }
    Ok(Some((directory, name)))
}

fn open_regular_cap_file(directory: &Dir, name: &Path) -> Result<File, ClientError> {
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No);
    let file = directory
        .open_with(name, &options)
        .map_err(storage_error)?
        .into_std();
    let metadata = file.metadata().map_err(storage_error)?;
    if metadata_is_reparse_point(&metadata) || !metadata.is_file() {
        return Err(invalid("destination path is not a regular file"));
    }
    Ok(file)
}

fn existing_cap_file_size(directory: &Dir, name: &Path) -> Result<Option<u64>, ClientError> {
    match directory.symlink_metadata(name) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(storage_error(error)),
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(invalid("destination path is not a regular file"))
        }
        Ok(_) => open_regular_cap_file(directory, name)
            .and_then(|file| file.metadata().map_err(storage_error))
            .map(|metadata| Some(metadata.len())),
    }
}

fn digest_cap_file(directory: &Dir, name: &Path) -> Result<Option<String>, ClientError> {
    match directory.symlink_metadata(name) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(storage_error(error)),
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(invalid("destination path is not a regular file"))
        }
        Ok(_) => {
            let mut input = open_regular_cap_file(directory, name)?;
            let mut hasher = Sha256::new();
            io::copy(&mut input, &mut HashWriter(&mut hasher)).map_err(storage_error)?;
            Ok(Some(hex(&hasher.finalize())))
        }
    }
}

fn assemble_source(
    layout: &StorageLayout,
    journal: &FileJournal,
    manifest: &FileManifest,
) -> Result<PathBuf, ClientError> {
    let path = session_directory(layout, journal.request.job_id.0)?.join(format!(
        "file-source-{}.bin",
        manifest.file_id.0.to_string().to_lowercase()
    ));
    if path.exists() {
        let (bytes, digest) = inspect_file(&path)?;
        if bytes == manifest.byte_count && digest == manifest.sha256 {
            return Ok(path);
        }
    }
    let _storage_reservation = reserve_materialization_storage(
        &layout.root,
        path.parent()
            .ok_or_else(|| invalid("assembled file has no parent"))?,
        u64::try_from(manifest.byte_count)
            .map_err(|_| invalid("assembled file byte count is invalid"))?,
    )?;
    let mut output = private_file(&path)?;
    output.set_len(0).map_err(storage_error)?;
    if manifest.byte_count == 0 {
        output.sync_all().map_err(storage_error)?;
        return Ok(path);
    }
    for descriptor in journal.committed_partitions.iter().filter(|part| {
        part.item_segment
            .as_ref()
            .map(|segment| segment.item_id.as_str())
            == Some(&manifest.file_id.0.to_string().to_lowercase())
    }) {
        let mut input = File::open(partition_path(
            layout,
            journal.request.job_id.0,
            descriptor.index,
        )?)
        .map_err(storage_error)?;
        io::copy(&mut input, &mut output).map_err(storage_error)?;
    }
    output.sync_all().map_err(storage_error)?;
    let (bytes, digest) = inspect_file(&path)?;
    if bytes != manifest.byte_count || digest != manifest.sha256 {
        return Err(invalid("assembled generated file digest mismatch"));
    }
    Ok(path)
}

fn make_receipt(
    layout: &StorageLayout,
    journal: &FileJournal,
) -> Result<FileExportReceipt, ClientError> {
    let outcome = journal
        .outcome
        .as_ref()
        .ok_or_else(|| invalid("file outcome missing"))?;
    let destination = journal
        .request
        .destination
        .as_ref()
        .ok_or_else(|| invalid("destination missing"))?;
    let mut relative_paths: Vec<_> = journal
        .manifests
        .values()
        .map(|file| file.relative_path.clone())
        .collect();
    relative_paths.sort();
    let payload = FileReceiptPayload {
        job_id: journal.request.job_id,
        status: outcome.status.clone(),
        destination_path: destination.root_path.clone(),
        files_written: i64::try_from(journal.manifests.len())
            .map_err(|_| invalid("too many files"))?,
        total_bytes: checked_byte_total(journal.manifests.values().map(|file| file.byte_count))?,
        relative_paths,
        success_count: outcome.success_count,
        total_count: outcome.total_count,
        failed_date_identifiers: outcome.failed_date_identifiers.clone(),
    };
    let directory = layout
        .response_spools_dir()
        .join(journal.request.job_id.0.to_string().to_lowercase());
    create_private_directory(&directory)?;
    let path = directory.join("file-receipt.json");
    let mut value =
        serde_json::to_value(&payload).map_err(|_| invalid("receipt encoding failed"))?;
    let object = value
        .as_object_mut()
        .ok_or_else(|| invalid("receipt is not an object"))?;
    object.insert("backend".into(), json!("direct"));
    object.insert(
        "message".into(),
        json!("iPhone export files were committed to the explicit destination."),
    );
    save_json(&layout.root, &path, &value)?;
    let (bytes, digest) = inspect_file(&path)?;
    Ok(FileExportReceipt {
        payload,
        response_path: path,
        response_byte_count: bytes,
        response_sha256: digest,
    })
}

fn validated_root(value: &str) -> Result<PathBuf, ClientError> {
    let path = PathBuf::from(value);
    if !path.is_absolute() || !windows_root_is_supported(value, &path) {
        return Err(invalid("destination must be a supported absolute path"));
    }
    let metadata = fs::symlink_metadata(&path).map_err(storage_error)?;
    if metadata.file_type().is_symlink()
        || metadata_is_reparse_point(&metadata)
        || !metadata.is_dir()
    {
        return Err(invalid(
            "destination must be an existing non-symlink directory",
        ));
    }
    // Windows std canonicalization returns a verbatim `\\?\` path. `dunce` preserves the
    // resolved object while returning a form that can safely pass through this validation again
    // during resume and destination-identity checks.
    let canonical = dunce::canonicalize(path).map_err(storage_error)?;
    let canonical_metadata = fs::symlink_metadata(&canonical).map_err(storage_error)?;
    if canonical_metadata.file_type().is_symlink()
        || metadata_is_reparse_point(&canonical_metadata)
        || !canonical_metadata.is_dir()
    {
        return Err(invalid(
            "destination must resolve to a non-symlink directory",
        ));
    }
    Ok(canonical)
}

#[cfg(not(windows))]
const fn windows_root_is_supported(_value: &str, _path: &Path) -> bool {
    true
}

#[cfg(windows)]
fn windows_root_is_supported(value: &str, path: &Path) -> bool {
    use std::path::Prefix;

    if value.starts_with(r"\\?\") || value.starts_with(r"\\.\") {
        return false;
    }
    let mut components = path.components();
    let Some(Component::Prefix(prefix)) = components.next() else {
        return false;
    };
    if !matches!(prefix.kind(), Prefix::Disk(_) | Prefix::UNC(_, _)) {
        return false;
    }
    matches!(components.next(), Some(Component::RootDir))
}

#[cfg(not(windows))]
const fn metadata_is_reparse_point(_metadata: &fs::Metadata) -> bool {
    false
}

#[cfg(windows)]
fn metadata_is_reparse_point(metadata: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt as _;

    const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0000_0400;
    metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
}

fn destination_identity(root: &Path) -> Result<DestinationIdentity, ClientError> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt as _;
        let metadata = fs::metadata(root).map_err(storage_error)?;
        Ok(DestinationIdentity {
            canonical_path: root.to_string_lossy().into(),
            device: metadata.dev(),
            inode: metadata.ino(),
        })
    }
    #[cfg(windows)]
    {
        let identity = file_id::get_low_res_file_id(root).map_err(storage_error)?;
        let file_id::FileId::LowRes {
            volume_serial_number,
            file_index,
        } = identity
        else {
            return Err(invalid("destination file identity is unavailable"));
        };
        Ok(DestinationIdentity {
            canonical_path: root.to_string_lossy().into(),
            volume_serial_number: Some(volume_serial_number),
            file_index: Some(file_index),
        })
    }
}

fn is_source_date(value: &str) -> bool {
    value.len() == 10
        && NaiveDate::parse_from_str(value, "%Y-%m-%d")
            .is_ok_and(|date| date.format("%Y-%m-%d").to_string() == value)
}

fn load_journal(path: &Path) -> Result<FileJournal, ClientError> {
    serde_json::from_slice(&read_bounded(
        path,
        MAXIMUM_DURABLE_JSON_BYTES,
        "file journal exceeds the durable metadata limit",
    )?)
    .map_err(|_| invalid("file journal is malformed"))
}

fn save_journal(layout: &StorageLayout, journal: &FileJournal) -> Result<(), ClientError> {
    save_json(
        &layout.root,
        &session_directory(layout, journal.request.job_id.0)?.join("file-journal.json"),
        journal,
    )
}

fn save_json<T: Serialize>(storage_root: &Path, path: &Path, value: &T) -> Result<(), ClientError> {
    let directory = path
        .parent()
        .ok_or_else(|| invalid("durable path has no parent"))?;
    create_private_directory(directory)?;
    let bytes = canonical_json(value).map_err(|_| invalid("JSON encoding failed"))?;
    let byte_count = u64::try_from(bytes.len()).unwrap_or(u64::MAX);
    if byte_count > MAXIMUM_DURABLE_JSON_BYTES {
        return Err(invalid("durable JSON exceeds the metadata limit"));
    }
    let _storage_reservation = reserve_private_storage(storage_root, directory, byte_count)?;
    let mut temporary = NamedTempFile::new_in(directory).map_err(storage_error)?;
    set_private_file(temporary.as_file())?;
    temporary.write_all(&bytes).map_err(storage_error)?;
    temporary.as_file().sync_all().map_err(storage_error)?;
    temporary
        .persist(path)
        .map_err(|error| storage_error(error.error))?;
    sync_directory(directory).map_err(storage_error)
}

fn session_directory(layout: &StorageLayout, job_id: Uuid) -> Result<PathBuf, ClientError> {
    let path = layout
        .corpus_sessions_dir()
        .join(job_id.to_string().to_lowercase());
    create_private_directory(&path)?;
    Ok(path)
}

fn partition_path(
    layout: &StorageLayout,
    job_id: Uuid,
    index: i64,
) -> Result<PathBuf, ClientError> {
    if index < 0 {
        return Err(invalid("negative partition index"));
    }
    Ok(session_directory(layout, job_id)?.join(format!("file-partition-{index:08}.bin")))
}

fn partition_matches(path: &Path, descriptor: &TransferPartition) -> Result<bool, ClientError> {
    match fs::symlink_metadata(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(storage_error(error)),
        Ok(metadata) if !metadata.file_type().is_file() => Ok(false),
        Ok(_) => {
            let (bytes, digest) = inspect_file(path)?;
            Ok(bytes == descriptor.byte_count && digest == descriptor.sha256)
        }
    }
}

fn remove_if_present(path: &Path) -> Result<(), ClientError> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(storage_error(error)),
    }
}

fn digest_seekable(file: &mut (impl io::Read + io::Seek)) -> Result<String, ClientError> {
    file.rewind().map_err(storage_error)?;
    let mut hasher = Sha256::new();
    io::copy(file, &mut HashWriter(&mut hasher)).map_err(storage_error)?;
    Ok(hex(&hasher.finalize()))
}

fn inspect_file(path: &Path) -> Result<(i64, String), ClientError> {
    let mut input = File::open(path).map_err(storage_error)?;
    let mut hasher = Sha256::new();
    let bytes = io::copy(&mut input, &mut HashWriter(&mut hasher)).map_err(storage_error)?;
    Ok((
        i64::try_from(bytes).map_err(|_| invalid("file too large"))?,
        hex(&hasher.finalize()),
    ))
}

struct HashWriter<'a>(&'a mut Sha256);
impl io::Write for HashWriter<'_> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0.update(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn create_private_directory(path: &Path) -> Result<(), ClientError> {
    prepare_private_directory(path)
}

fn private_file(path: &Path) -> Result<File, ClientError> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    options.open(path).map_err(storage_error)
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

#[cfg(unix)]
fn set_private_file(file: &File) -> Result<(), ClientError> {
    use std::os::unix::fs::PermissionsExt as _;
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(storage_error)
}
#[cfg(windows)]
#[allow(clippy::unnecessary_wraps)]
fn set_private_file(_file: &File) -> Result<(), ClientError> {
    Ok(())
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    bytes.iter().fold(String::new(), |mut output, byte| {
        write!(output, "{byte:02x}").expect("writing to a string succeeds");
        output
    })
}
fn checked_byte_total(values: impl IntoIterator<Item = i64>) -> Result<i64, ClientError> {
    values.into_iter().try_fold(0_i64, |total, value| {
        total
            .checked_add(value)
            .ok_or_else(|| invalid("transfer byte total overflow"))
    })
}

fn invalid(message: &str) -> ClientError {
    ClientError::InvalidTransfer(message.into())
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
#[allow(clippy::needless_pass_by_value)]
fn rustix_storage_error(error: rustix::io::Errno) -> ClientError {
    storage_error(io::Error::from_raw_os_error(error.raw_os_error()))
}

#[allow(clippy::needless_pass_by_value)]
fn storage_error(error: io::Error) -> ClientError {
    ClientError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use chrono::Timelike as _;
    use healthmd_protocol::{
        encoding::SwiftUuid,
        models::{
            DateSelection, ExactDateSelection, ExportDestination, PeerBinding, SettingsPolicy,
            TransferItemSegment,
        },
        transfer::request_fingerprint,
    };
    use tempfile::TempDir;

    use super::*;
    use crate::job::{JobRecord, JobStore};

    #[cfg(windows)]
    #[test]
    fn windows_destination_identity_detects_same_path_directory_replacement() {
        let temporary = TempDir::new().unwrap();
        let destination = temporary.path().join("destination");
        let moved = temporary.path().join("moved");
        fs::create_dir(&destination).unwrap();
        let original = destination_identity(&destination).unwrap();
        fs::rename(&destination, &moved).unwrap();
        fs::create_dir(&destination).unwrap();
        let replacement = destination_identity(&destination).unwrap();
        assert_ne!(original, replacement);
    }

    #[cfg(windows)]
    #[test]
    fn windows_canonical_destination_round_trips_through_policy() {
        let temporary = TempDir::new().unwrap();
        let destination = temporary.path().join("destination");
        fs::create_dir(&destination).unwrap();
        let first = GeneratedDestination::open(&destination).unwrap();
        assert!(!first.root().to_string_lossy().starts_with(r"\\?\"));
        assert!(
            windows_verbatim_text(first.root())
                .unwrap()
                .starts_with(r"\\?\")
        );
        let second = GeneratedDestination::open(first.root()).unwrap();
        assert_eq!(first.identity, second.identity);
    }

    #[cfg(windows)]
    #[test]
    fn windows_atomic_install_replaces_and_detects_destination_changes() {
        let temporary = TempDir::new().unwrap();
        let destination_root = temporary.path().join("destination");
        let destination = destination_root.join("daily.md");
        let stage = temporary.path().join("stage");
        fs::create_dir(&destination_root).unwrap();
        fs::write(&destination, b"original").unwrap();
        fs::write(&stage, b"replacement").unwrap();
        let capability = Dir::open_ambient_dir(&destination_root, ambient_authority()).unwrap();
        let (parent, name) = open_safe_parent(capability, Path::new("daily.md")).unwrap();
        install_stage(
            &parent,
            &name,
            &stage,
            Some(&sha256_hex(b"original")),
            &sha256_hex(b"replacement"),
            &destination,
            None,
        )
        .unwrap();
        assert_eq!(fs::read(&destination).unwrap(), b"replacement");

        fs::write(&destination, b"changed by another process").unwrap();
        assert!(
            install_stage(
                &parent,
                &name,
                &stage,
                Some(&sha256_hex(b"replacement")),
                &sha256_hex(b"replacement"),
                &destination,
                None,
            )
            .is_err()
        );
        assert_eq!(
            fs::read(&destination).unwrap(),
            b"changed by another process"
        );

        let mut raced_stage = NamedTempFile::new_in(&destination_root).unwrap();
        raced_stage.write_all(b"replacement").unwrap();
        raced_stage.as_file().sync_all().unwrap();
        assert!(
            replace_existing_windows(
                raced_stage,
                &destination,
                &sha256_hex(b"original"),
                &sha256_hex(b"replacement"),
                &parent,
                &name,
            )
            .is_err()
        );
        assert_eq!(
            fs::read(&destination).unwrap(),
            b"changed by another process"
        );
    }

    #[cfg(windows)]
    #[test]
    fn windows_destination_policy_rejects_ambiguous_namespaces_and_reparse_points() {
        assert!(windows_root_is_supported(
            r"C:\healthmd",
            Path::new(r"C:\healthmd")
        ));
        assert!(windows_root_is_supported(
            r"\\server\share\healthmd",
            Path::new(r"\\server\share\healthmd")
        ));
        for value in [
            r"C:healthmd",
            r"\healthmd",
            r"\\?\C:\healthmd",
            r"\\.\C:\healthmd",
        ] {
            assert!(!windows_root_is_supported(value, Path::new(value)));
        }

        let temporary = TempDir::new().unwrap();
        let destination = temporary.path().join("destination");
        let target = temporary.path().join("target");
        fs::create_dir(&target).unwrap();
        if std::os::windows::fs::symlink_dir(&target, &destination).is_ok() {
            assert!(validated_root(destination.to_str().unwrap()).is_err());
            fs::remove_dir(&destination).unwrap();
        }

        let junction = temporary.path().join("junction");
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&junction)
            .arg(&target)
            .status()
            .unwrap();
        assert!(status.success());
        assert!(validated_root(junction.to_str().unwrap()).is_err());
    }

    #[test]
    #[allow(clippy::too_many_lines)]
    fn append_commit_is_digest_bound_and_idempotent() {
        let temporary = TempDir::new().unwrap();
        let destination = temporary.path().join("destination");
        fs::create_dir(&destination).unwrap();
        fs::write(destination.join("daily.md"), b"old").unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let jobs = JobStore::new(layout.clone()).unwrap();
        let now = Utc::now().with_nanosecond(0).unwrap();
        let job_id = SwiftUuid(Uuid::new_v4());
        let request = ExportRequest {
            protocol_version: 1,
            job_id,
            created_at: now,
            date_selection: DateSelection::Exact(ExactDateSelection {
                start: "2026-07-23".into(),
                end: "2026-07-23".into(),
            }),
            settings_policy: SettingsPolicy::RequestedDatesOnly,
            response_mode: ResponseMode::WriteFiles,
            raw_profile: None,
            canonical_selection: None,
            destination: Some(ExportDestination {
                root_path: destination.to_string_lossy().into(),
            }),
        };
        jobs.save(&JobRecord::new(request.clone())).unwrap();
        let binding = PeerBinding {
            source_installation_id: SwiftUuid(Uuid::new_v4()),
            destination_installation_id: SwiftUuid(Uuid::new_v4()),
        };
        let accepted = ExportAccepted {
            job_id,
            accepted_at: now,
            peer_binding: binding.clone(),
            resolved_date_identifiers: vec!["2026-07-23".into()],
            source_device_name: "iPhone".into(),
            source_time_zone_identifier: "UTC".into(),
            resolved_canonical_selection: None,
        };
        let fingerprint = request_fingerprint(&request).unwrap();
        let session = TransferSession {
            protocol_version: 1,
            session_id: SwiftUuid(Uuid::new_v4()),
            job_id,
            request_fingerprint: fingerprint.clone(),
            peer_binding: binding,
            partition_target_bytes: 48 * 1024 * 1024,
            created_at: now,
        };
        let data = b"fresh".to_vec();
        let digest = sha256_hex(&data);
        let file_id = SwiftUuid(Uuid::new_v4());
        let manifest = FileManifest {
            job_id,
            file_id,
            relative_path: "daily.md".into(),
            byte_count: i64::try_from(data.len()).unwrap(),
            sha256: digest.clone(),
            write_mode: FileWriteMode::Append,
        };
        let transfer_id = SwiftUuid(Uuid::new_v4());
        let partition = TransferPartition {
            index: 0,
            transfer_id,
            source_dates: vec![file_id.0.to_string().to_lowercase()],
            byte_count: manifest.byte_count,
            chunk_count: 1,
            sha256: digest.clone(),
            previous_sha256: None,
            item_segment: Some(TransferItemSegment {
                item_id: file_id.0.to_string().to_lowercase(),
                offset: 0,
                item_byte_count: manifest.byte_count,
                is_final_segment: true,
            }),
        };
        let finalize = TransferFinalize {
            session_id: session.session_id,
            job_id,
            request_fingerprint: fingerprint,
            total_partitions: 1,
            total_bytes: manifest.byte_count,
            final_partition_sha256: Some(digest.clone()),
            outcome: Some(ExportOutcome {
                status: "success".into(),
                success_count: 1,
                total_count: 1,
                failed_date_identifiers: Vec::new(),
            }),
        };

        let mut receiver = FileReceiver::new(layout.clone(), jobs.clone());
        receiver
            .prepare(request.clone(), accepted.clone(), session.clone())
            .unwrap();
        receiver.store_manifest(manifest.clone()).unwrap();
        let mut duplicate_path = manifest.clone();
        duplicate_path.file_id = SwiftUuid(Uuid::new_v4());
        assert!(receiver.store_manifest(duplicate_path).is_err());
        let mut case_conflict = manifest.clone();
        case_conflict.file_id = SwiftUuid(Uuid::new_v4());
        case_conflict.relative_path = "DAILY.md".into();
        assert!(receiver.store_manifest(case_conflict).is_err());
        receiver
            .disposition(TransferOpen {
                session: session.clone(),
                partition: partition.clone(),
            })
            .unwrap();
        receiver
            .receive_chunk(TransferChunk {
                transfer_id,
                sequence: 1,
                data: data.clone(),
                sha256: digest.clone(),
            })
            .unwrap();
        receiver
            .commit_partition(TransferPartitionComplete {
                session_id: finalize.session_id,
                job_id,
                partition_index: 0,
                transfer_id,
                partition_sha256: digest.clone(),
            })
            .unwrap();
        fs::write(partition_path(&layout, job_id.0, 0).unwrap(), b"corrupt").unwrap();
        let mut resumed = FileReceiver::new(layout, jobs.clone());
        resumed.prepare(request, accepted, session.clone()).unwrap();
        assert_eq!(
            resumed
                .disposition(TransferOpen { session, partition })
                .unwrap()
                .disposition,
            TransferDispositionKind::Needed
        );
        resumed
            .receive_chunk(TransferChunk {
                transfer_id,
                sequence: 1,
                data,
                sha256: digest.clone(),
            })
            .unwrap();
        resumed
            .commit_partition(TransferPartitionComplete {
                session_id: finalize.session_id,
                job_id,
                partition_index: 0,
                transfer_id,
                partition_sha256: digest,
            })
            .unwrap();
        receiver = resumed;
        let mut invalid_outcome = finalize.clone();
        invalid_outcome.outcome = Some(ExportOutcome {
            status: "partial_success".into(),
            success_count: 1,
            total_count: 1,
            failed_date_identifiers: Vec::new(),
        });
        assert!(receiver.finalize(&invalid_outcome).is_err());
        assert_eq!(fs::read(destination.join("daily.md")).unwrap(), b"old");
        let receipt = receiver.finalize(&finalize).unwrap();
        assert_eq!(
            fs::read(destination.join("daily.md")).unwrap(),
            b"old\n\nfresh"
        );
        assert_eq!(receipt.payload.files_written, 1);

        receiver.finalize(&finalize).unwrap();
        assert_eq!(
            fs::read(destination.join("daily.md")).unwrap(),
            b"old\n\nfresh"
        );
        receiver.acknowledge_peer_completion(job_id.0).unwrap();
        assert_eq!(jobs.load(job_id.0).unwrap().state, JobState::Completed);
    }

    #[test]
    fn source_neutral_destination_adapter_is_idempotent() {
        let temporary = TempDir::new().unwrap();
        let destination_path = temporary.path().join("destination");
        fs::create_dir(&destination_path).unwrap();
        fs::write(destination_path.join("daily.md"), b"old").unwrap();
        let source = temporary.path().join("source.md");
        let stage = temporary.path().join("stage.md");
        fs::write(&source, b"fresh").unwrap();

        let destination = GeneratedDestination::open(&destination_path).unwrap();
        assert!(is_sha256(&destination.binding_sha256().unwrap()));
        assert!(
            destination
                .validate_stage_admission("daily.md", 5, FileWriteMode::Append, 2)
                .is_ok()
        );
        assert!(
            destination
                .validate_stage_admission("missing/daily.md", 5, FileWriteMode::Append, 2)
                .is_ok()
        );
        assert!(!destination_path.join("missing").exists());
        fs::write(destination_path.join("daily.md"), b"grew after admission").unwrap();
        assert!(
            destination
                .prepare_stage(
                    "daily.md",
                    &source,
                    &stage,
                    healthmd_protocol::v2::FileWriteMode::Append,
                )
                .is_err()
        );
        fs::write(destination_path.join("daily.md"), b"old").unwrap();
        let prepared = destination
            .prepare_stage(
                "daily.md",
                &source,
                &stage,
                healthmd_protocol::v2::FileWriteMode::Append,
            )
            .unwrap();
        fs::write(&stage, b"tampered after preparation").unwrap();
        assert!(
            destination
                .install_stage(
                    "daily.md",
                    &stage,
                    prepared.before_sha256.as_deref(),
                    &prepared.after_sha256,
                )
                .is_err()
        );
        assert_eq!(fs::read(destination_path.join("daily.md")).unwrap(), b"old");
        let prepared = destination
            .prepare_stage(
                "daily.md",
                &source,
                &stage,
                healthmd_protocol::v2::FileWriteMode::Append,
            )
            .unwrap();
        destination
            .install_stage(
                "daily.md",
                &stage,
                prepared.before_sha256.as_deref(),
                &prepared.after_sha256,
            )
            .unwrap();
        destination
            .install_stage(
                "daily.md",
                &stage,
                prepared.before_sha256.as_deref(),
                &prepared.after_sha256,
            )
            .unwrap();
        assert_eq!(
            fs::read(destination_path.join("daily.md")).unwrap(),
            b"old\n\nfresh"
        );
    }

    #[test]
    fn traversal_and_symlink_ancestors_are_rejected() {
        assert!(validate_generated_relative_path("../outside").is_err());
        assert!(validate_generated_relative_path("/absolute").is_err());
        assert!(generated_paths_conflict("Café.md", "CAFE\u{301}.MD"));
        #[cfg(unix)]
        {
            let temporary = TempDir::new().unwrap();
            let root = Dir::open_ambient_dir(temporary.path(), ambient_authority()).unwrap();
            std::os::unix::fs::symlink("/tmp", temporary.path().join("link")).unwrap();
            assert!(open_safe_parent(root, Path::new("link/escape.json")).is_err());
            std::os::unix::fs::symlink("/etc/passwd", temporary.path().join("file-link")).unwrap();
            let root = Dir::open_ambient_dir(temporary.path(), ambient_authority()).unwrap();
            assert!(digest_cap_file(&root, Path::new("file-link")).is_err());

            fs::write(temporary.path().join("destination.md"), b"concurrent").unwrap();
            fs::write(temporary.path().join(".stage.tmp"), b"generated").unwrap();
            assert!(
                exchange_existing_stage(
                    &root,
                    ".stage.tmp",
                    Path::new("destination.md"),
                    &sha256_hex(b"original")
                )
                .is_err()
            );
            assert_eq!(
                fs::read(temporary.path().join("destination.md")).unwrap(),
                b"concurrent"
            );
            assert!(!temporary.path().join(".stage.tmp").exists());
        }
        assert!(checked_byte_total([i64::MAX, 1]).is_err());
    }
}
