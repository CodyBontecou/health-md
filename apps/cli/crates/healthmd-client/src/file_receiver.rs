use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{self, Read as _, Write as _},
    path::{Component, Path, PathBuf},
};

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
use unicode_normalization::UnicodeNormalization as _;
use uuid::Uuid;

#[cfg(any(target_os = "linux", target_os = "macos"))]
use rustix::fs::{Mode, OFlags, RenameFlags, openat, renameat_with};

use crate::{
    ClientError,
    job::{JobState, JobStore, ResponseArtifact},
    markdown,
    storage::StorageLayout,
};

const JOURNAL_VERSION: u16 = 2;
const MAXIMUM_MERGE_BYTES: i64 = 64 * 1_024 * 1_024;
const MAXIMUM_PARTITIONS: i64 = 1_000_000;

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
        Ok(Self { root, identity })
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
        let relative = safe_relative_path(relative_path)?;
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
        let relative = safe_relative_path(relative_path)?;
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
        let relative = safe_relative_path(relative_path)?;
        let root = Dir::open_ambient_dir(&self.root, ambient_authority()).map_err(storage_error)?;
        let (parent, name) = open_safe_parent(root, &relative)?;
        if digest_cap_file(&parent, &name)?.as_deref() == Some(expected_after) {
            return Ok(());
        }
        install_stage(&parent, &name, stage, expected_before)?;
        if digest_cap_file(&parent, &name)?.as_deref() != Some(expected_after) {
            return Err(invalid("destination digest failed after commit"));
        }
        Ok(())
    }

    /// Read the current exact digest for idempotent commit recovery.
    ///
    /// # Errors
    ///
    /// Returns an error for changed identity, unsafe paths, or non-regular files.
    pub fn current_digest(&self, relative_path: &str) -> Result<Option<String>, ClientError> {
        self.ensure_identity()?;
        let relative = safe_relative_path(relative_path)?;
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

const fn v2_write_mode(mode: healthmd_protocol::v2::FileWriteMode) -> FileWriteMode {
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
            || accepted_dates.len() > 100_000
            || accepted_dates.windows(2).any(|pair| pair[0] >= pair[1])
            || accepted_dates.iter().any(|date| !is_source_date(date))
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
            let persisted: FileJournal =
                serde_json::from_slice(&fs::read(&path).map_err(storage_error)?)
                    .map_err(|_| invalid("file journal is malformed"))?;
            if persisted.version != JOURNAL_VERSION
                || persisted.request != request
                || persisted.session != session
                || persisted.destination_identity != identity
                || persisted.accepted.peer_binding != accepted.peer_binding
                || persisted.accepted.resolved_date_identifiers
                    != accepted.resolved_date_identifiers
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
        safe_relative_path(&manifest.relative_path)?;
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
                    && destination_collision_key(&saved.relative_path)
                        == destination_collision_key(&manifest.relative_path)
            })
            || (!journal.manifests.contains_key(&manifest.file_id)
                && journal.manifests.len() >= 100_000)
        {
            return Err(invalid("file manifest changed or exceeds receiver limits"));
        }
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
        let path = self
            .session_directory(open.session.job_id.0)?
            .join("file-pending.partition");
        let file = private_file(&path)?;
        file.set_len(0).map_err(storage_error)?;
        file.sync_all().map_err(storage_error)?;
        self.pending = Some(PendingPartition {
            descriptor: descriptor.clone(),
            path,
            next_sequence: 1,
            received_bytes: 0,
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
            || outcome.failed_date_identifiers.len() > 100_000
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
        let payload: FileReceiptPayload =
            serde_json::from_slice(&fs::read(&path).map_err(storage_error)?)
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

fn validate_open(open: &TransferOpen, journal: &FileJournal) -> Result<(), ClientError> {
    let descriptor = &open.partition;
    if descriptor.index < 0
        || descriptor.index >= MAXIMUM_PARTITIONS
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
    let relative = safe_relative_path(&manifest.relative_path)?;
    let capability = Dir::open_ambient_dir(&root, ambient_authority()).map_err(storage_error)?;
    let (parent, name) = open_safe_parent(capability, &relative)?;
    let current = digest_cap_file(&parent, &name)?;
    if let Some(plan) = journal.commit_plans.get(&manifest.file_id).cloned() {
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
            &session_directory(layout, journal.request.job_id.0)?.join(&plan.staged_relative_path),
            current.as_deref(),
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
    install_stage(&parent, &name, &stage, current.as_deref())?;
    if digest_cap_file(&parent, &name)?.as_deref() != Some(&after) {
        return Err(invalid("destination digest failed after commit"));
    }
    let mut committed = plan;
    committed.committed = true;
    journal.commit_plans.insert(manifest.file_id, committed);
    journal.updated_at = Utc::now();
    save_journal(layout, journal)
}

fn build_stage(
    parent: &Dir,
    name: &Path,
    exists: bool,
    source: &Path,
    stage: &Path,
    mode: FileWriteMode,
    append_separator: &[u8],
) -> Result<(), ClientError> {
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
) -> Result<(), ClientError> {
    if digest_cap_file(parent, name)?.as_deref() != expected_before {
        return Err(invalid("destination changed before atomic install"));
    }
    let temporary_name = format!(".healthmd-{}.tmp", Uuid::new_v4());
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    let mut temporary = parent
        .open_with(&temporary_name, &options)
        .map_err(storage_error)?;
    let mut input = File::open(stage).map_err(storage_error)?;
    io::copy(&mut input, &mut temporary).map_err(storage_error)?;
    temporary.sync_all().map_err(storage_error)?;
    if digest_cap_file(parent, name)?.as_deref() != expected_before {
        let _ = parent.remove_file(&temporary_name);
        return Err(invalid("destination changed during atomic install"));
    }
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
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
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    {
        parent
            .rename(&temporary_name, parent, name)
            .map_err(storage_error)?;
        sync_cap_directory(parent)
    }
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
            #[cfg(any(target_os = "linux", target_os = "macos"))]
            {
                let descriptor = openat(
                    &directory,
                    path,
                    OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
                    Mode::empty(),
                )
                .map_err(|error| storage_error(io::Error::from(error)))?;
                directory = Dir::from_std_file(descriptor.into());
            }
            #[cfg(not(any(target_os = "linux", target_os = "macos")))]
            {
                directory = directory.open_dir(path).map_err(storage_error)?;
            }
        }
    }
    Ok((directory, name))
}

fn open_regular_cap_file(directory: &Dir, name: &Path) -> Result<File, ClientError> {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let file: File = openat(
        directory,
        name,
        OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .map_err(rustix_storage_error)?
    .into();
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    let file = directory.open(name).map_err(storage_error)?.into_std();
    if !file.metadata().map_err(storage_error)?.is_file() {
        return Err(invalid("destination path is not a regular file"));
    }
    Ok(file)
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
    let mut output = private_file(&path)?;
    output.set_len(0).map_err(storage_error)?;
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
    save_json(&path, &value)?;
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
    if !path.is_absolute() {
        return Err(invalid("destination must be absolute"));
    }
    let metadata = fs::symlink_metadata(&path).map_err(storage_error)?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(invalid(
            "destination must be an existing non-symlink directory",
        ));
    }
    fs::canonicalize(path).map_err(storage_error)
}

fn destination_identity(root: &Path) -> Result<DestinationIdentity, ClientError> {
    let metadata = fs::metadata(root).map_err(storage_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt as _;
        Ok(DestinationIdentity {
            canonical_path: root.to_string_lossy().into(),
            device: metadata.dev(),
            inode: metadata.ino(),
        })
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt as _;
        let volume_serial_number = metadata
            .volume_serial_number()
            .ok_or_else(|| invalid("destination volume identity is unavailable"))?;
        let file_index = metadata
            .file_index()
            .ok_or_else(|| invalid("destination file identity is unavailable"))?;
        Ok(DestinationIdentity {
            canonical_path: root.to_string_lossy().into(),
            volume_serial_number: Some(volume_serial_number),
            file_index: Some(file_index),
        })
    }
}

fn destination_collision_key(value: &str) -> String {
    value.nfd().flat_map(char::to_lowercase).collect()
}

fn is_source_date(value: &str) -> bool {
    value.len() == 10
        && NaiveDate::parse_from_str(value, "%Y-%m-%d")
            .is_ok_and(|date| date.format("%Y-%m-%d").to_string() == value)
}

fn safe_relative_path(value: &str) -> Result<PathBuf, ClientError> {
    if value.is_empty() || value.len() > 4_096 {
        return Err(invalid("generated relative path is invalid"));
    }
    let path = PathBuf::from(value);
    if path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(invalid("generated relative path is unsafe"));
    }
    Ok(path)
}

fn save_journal(layout: &StorageLayout, journal: &FileJournal) -> Result<(), ClientError> {
    save_json(
        &session_directory(layout, journal.request.job_id.0)?.join("file-journal.json"),
        journal,
    )
}

fn save_json<T: Serialize>(path: &Path, value: &T) -> Result<(), ClientError> {
    let directory = path
        .parent()
        .ok_or_else(|| invalid("durable path has no parent"))?;
    create_private_directory(directory)?;
    let mut temporary = NamedTempFile::new_in(directory).map_err(storage_error)?;
    set_private_file(temporary.as_file())?;
    temporary
        .write_all(&canonical_json(value).map_err(|_| invalid("JSON encoding failed"))?)
        .map_err(storage_error)?;
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
    fs::create_dir_all(path).map_err(storage_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(storage_error)?;
    }
    Ok(())
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

    #[test]
    #[allow(clippy::too_many_lines)]
    fn append_commit_is_digest_bound_and_idempotent() {
        let temporary = TempDir::new().unwrap();
        let destination = temporary.path().join("destination");
        fs::create_dir(&destination).unwrap();
        fs::write(destination.join("daily.md"), b"existing").unwrap();
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
        assert_eq!(fs::read(destination.join("daily.md")).unwrap(), b"existing");
        let receipt = receiver.finalize(&finalize).unwrap();
        assert_eq!(
            fs::read(destination.join("daily.md")).unwrap(),
            b"existing\n\nfresh"
        );
        assert_eq!(receipt.payload.files_written, 1);

        receiver.finalize(&finalize).unwrap();
        assert_eq!(
            fs::read(destination.join("daily.md")).unwrap(),
            b"existing\n\nfresh"
        );
        receiver.acknowledge_peer_completion(job_id.0).unwrap();
        assert_eq!(jobs.load(job_id.0).unwrap().state, JobState::Completed);
    }

    #[test]
    fn source_neutral_destination_adapter_is_idempotent() {
        let temporary = TempDir::new().unwrap();
        let destination_path = temporary.path().join("destination");
        fs::create_dir(&destination_path).unwrap();
        fs::write(destination_path.join("daily.md"), b"existing").unwrap();
        let source = temporary.path().join("source.md");
        let stage = temporary.path().join("stage.md");
        fs::write(&source, b"fresh").unwrap();

        let destination = GeneratedDestination::open(&destination_path).unwrap();
        assert!(is_sha256(&destination.binding_sha256().unwrap()));
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
            b"existing\n\nfresh"
        );
    }

    #[test]
    fn traversal_and_symlink_ancestors_are_rejected() {
        assert!(safe_relative_path("../outside").is_err());
        assert!(safe_relative_path("/absolute").is_err());
        assert_eq!(
            destination_collision_key("Café.md"),
            destination_collision_key("CAFE\u{301}.MD")
        );
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
