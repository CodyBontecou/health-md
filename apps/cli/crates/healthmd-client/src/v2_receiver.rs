use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{self, BufRead as _, BufReader, Read as _, Write as _},
    path::{Component, Path, PathBuf},
};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::Utc;
use healthmd_protocol::{
    TRANSFER_FRAME_BYTES,
    encoding::canonical_json,
    transfer::{decode_binary_chunk, is_sha256, sha256_hex},
    v2::{
        self, ArtifactKind, ArtifactManifest, ProductId, TransferChunkAcknowledgement,
        TransferDisposition, TransferDispositionKind, TransferFinalAcknowledgement,
        TransferFinalize, TransferOpen, TransferPartitionAcknowledgement,
        TransferPartitionComplete, TransferSession,
    },
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use tempfile::NamedTempFile;
use unicode_normalization::UnicodeNormalization as _;
use uuid::Uuid;

use crate::{
    ClientError,
    file_receiver::GeneratedDestination,
    job::JobState,
    storage::StorageLayout,
    v2_job::{V2JobStore, V2ResponseArtifact},
};

const JOURNAL_VERSION: u16 = 2;
const MAXIMUM_ARTIFACTS: usize = 100_000;
const MAXIMUM_PARTITIONS: u64 = 1_000_000;
const MAXIMUM_NDJSON_LINE_BYTES: u64 = 64 * 1_024 * 1_024;
const MAXIMUM_IN_MEMORY_JSON_BYTES: u64 = 64 * 1_024 * 1_024;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
struct CommitPlan {
    artifact_id: Uuid,
    relative_path: String,
    before_sha256: Option<String>,
    after_sha256: String,
    stage_path: String,
    committed: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
struct ReceiverJournal {
    version: u16,
    request: v2::ExportRequest,
    accepted: v2::ExportAccepted,
    session: TransferSession,
    manifests: BTreeMap<Uuid, ArtifactManifest>,
    committed_partitions: Vec<v2::TransferPartition>,
    commit_plans: BTreeMap<Uuid, CommitPlan>,
    updated_at: chrono::DateTime<Utc>,
}

struct PendingPartition {
    descriptor: v2::TransferPartition,
    path: PathBuf,
    replacement_index: Option<usize>,
    next_sequence: u32,
    received_bytes: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct V2ArtifactReceipt {
    pub path: PathBuf,
    pub byte_count: u64,
    pub sha256: String,
    pub status: String,
    pub product_id: ProductId,
}

pub struct V2ArtifactReceiver {
    layout: StorageLayout,
    jobs: V2JobStore,
    journal: Option<ReceiverJournal>,
    pending: Option<PendingPartition>,
    deadline: Option<std::time::Instant>,
}

impl V2ArtifactReceiver {
    #[must_use]
    pub const fn new(layout: StorageLayout, jobs: V2JobStore) -> Self {
        Self {
            layout,
            jobs,
            journal: None,
            pending: None,
            deadline: None,
        }
    }

    pub fn set_deadline(&mut self, deadline: std::time::Instant) {
        self.deadline = Some(deadline);
    }

    /// Create or reopen an immutable Android transfer session.
    ///
    /// # Errors
    ///
    /// Returns an error when request, acceptance, session, or durable state disagree.
    pub fn prepare(
        &mut self,
        request: v2::ExportRequest,
        accepted: v2::ExportAccepted,
        session: TransferSession,
    ) -> Result<(), ClientError> {
        let fingerprint = v2::request_fingerprint(&request)
            .map_err(|_| invalid("v2 request fingerprint failed"))?;
        if request.job_id != accepted.job_id
            || request.job_id != session.job_id
            || request.source_installation_id != accepted.peer_binding.source_installation_id
            || accepted.peer_binding != session.peer_binding
            || accepted.product_id != request.product.product_id()
            || accepted.request_fingerprint != fingerprint
            || session.request_fingerprint != fingerprint
            || session.partition_target_bytes < 32 * 1_024 * 1_024
            || session.partition_target_bytes > 64 * 1_024 * 1_024
        {
            return Err(invalid("v2 request, acceptance, and session do not agree"));
        }

        let directory = self.session_directory(request.job_id)?;
        let path = directory.join("receiver-journal.json");
        let journal = if path.exists() {
            let persisted: ReceiverJournal =
                serde_json::from_slice(&fs::read(&path).map_err(storage_error)?)
                    .map_err(|_| invalid("v2 receiver journal is malformed"))?;
            if persisted.version != JOURNAL_VERSION
                || persisted.request != request
                || persisted.accepted != accepted
                || persisted.session != session
            {
                return Err(invalid("durable v2 transfer session changed"));
            }
            persisted
        } else {
            let created = ReceiverJournal {
                version: JOURNAL_VERSION,
                request,
                accepted,
                session,
                manifests: BTreeMap::new(),
                committed_partitions: Vec::new(),
                commit_plans: BTreeMap::new(),
                updated_at: Utc::now(),
            };
            save_json(&path, &created)?;
            created
        };
        let _ = fs::remove_file(directory.join("pending.partition"));
        self.pending = None;
        self.journal = Some(journal.clone());

        let mut record = self.jobs.load(journal.request.job_id)?;
        if record.state != JobState::AwaitingPeerAcknowledgement {
            record.state = JobState::Preparing;
            record.updated_at = Utc::now();
            record.message = Some("Android accepted the direct export.".into());
        }
        record.peer_binding = Some(journal.session.peer_binding.clone());
        record.session_id = Some(journal.session.session_id);
        self.jobs.save(&record)
    }

    /// Persist one immutable artifact manifest.
    ///
    /// # Errors
    ///
    /// Returns an error for invalid product metadata, unsafe paths, collisions, or changes.
    pub fn store_manifest(&mut self, manifest: ArtifactManifest) -> Result<(), ClientError> {
        validate_manifest(&manifest)?;
        let journal = self
            .journal
            .as_mut()
            .ok_or_else(|| invalid("v2 receiver is not prepared"))?;
        let maximum_manifests = match journal.request.product.product_id() {
            ProductId::AndroidProviderNativeSnapshotV1 => 1,
            ProductId::GeneratedFilesV1 => 4_096,
            ProductId::AndroidDailyRecordsV1 => 0,
        };
        if manifest.job_id != journal.request.job_id
            || !manifest_matches_product(&manifest, journal.request.product.product_id())
            || !manifest_matches_request(&manifest, journal)
            || journal
                .manifests
                .get(&manifest.artifact_id)
                .is_some_and(|saved| saved != &manifest)
            || (!journal.manifests.contains_key(&manifest.artifact_id)
                && journal.manifests.len() >= maximum_manifests.min(MAXIMUM_ARTIFACTS))
        {
            return Err(invalid("artifact manifest changed or is incompatible"));
        }
        if let Some(relative_path) = &manifest.relative_path {
            safe_relative_path(relative_path)?;
            let collision = destination_collision_key(relative_path);
            if journal.manifests.values().any(|saved| {
                saved.artifact_id != manifest.artifact_id
                    && saved.relative_path.as_ref().is_some_and(|path| {
                        let saved = destination_collision_key(path);
                        saved == collision
                            || saved
                                .strip_prefix(&collision)
                                .is_some_and(|suffix| suffix.starts_with('/'))
                            || collision
                                .strip_prefix(&saved)
                                .is_some_and(|suffix| suffix.starts_with('/'))
                    })
            }) {
                return Err(invalid("generated artifact destination collision"));
            }
        }
        journal.manifests.insert(manifest.artifact_id, manifest);
        journal.updated_at = Utc::now();
        save_journal(&self.layout, journal)
    }

    /// Decide whether an exact v2 partition is needed or already committed.
    ///
    /// # Errors
    ///
    /// Returns an error for invalid, changed, out-of-order, or overlapping partitions.
    pub fn disposition(&mut self, open: TransferOpen) -> Result<TransferDisposition, ClientError> {
        let journal = self
            .journal
            .as_mut()
            .ok_or_else(|| invalid("v2 receiver is not prepared"))?;
        validate_open(&open, journal)?;
        let descriptor = open.partition;
        let index = usize::try_from(descriptor.index)
            .map_err(|_| invalid("partition index does not fit this platform"))?;
        let replacement_index = if let Some(existing) = journal.committed_partitions.get(index) {
            if existing != &descriptor {
                return Err(invalid("committed v2 partition changed"));
            }
            let committed_path =
                partition_path(&self.layout, journal.request.job_id, descriptor.index)?;
            if partition_matches(&committed_path, &descriptor)? {
                return Ok(TransferDisposition {
                    session_id: journal.session.session_id,
                    job_id: journal.request.job_id,
                    partition_index: descriptor.index,
                    partition_sha256: descriptor.sha256,
                    disposition: TransferDispositionKind::AlreadyCommitted,
                    message: None,
                });
            }
            let _ = fs::remove_file(committed_path);
            Some(index)
        } else {
            None
        };
        if (replacement_index.is_none() && index != journal.committed_partitions.len())
            || self.pending.is_some()
        {
            return Err(invalid("v2 partitions must be globally contiguous"));
        }
        let path = self
            .layout
            .v2_artifact_spools_dir()
            .join(journal.request.job_id.to_string().to_lowercase())
            .join("pending.partition");
        let _ = fs::remove_file(&path);
        let file = private_file(&path)?;
        file.set_len(0).map_err(storage_error)?;
        file.sync_all().map_err(storage_error)?;
        self.pending = Some(PendingPartition {
            descriptor: descriptor.clone(),
            path,
            replacement_index,
            next_sequence: 1,
            received_bytes: 0,
        });
        Ok(TransferDisposition {
            session_id: journal.session.session_id,
            job_id: journal.request.job_id,
            partition_index: descriptor.index,
            partition_sha256: descriptor.sha256,
            disposition: TransferDispositionKind::Needed,
            message: None,
        })
    }

    /// Validate and append one deployed binary transfer frame.
    ///
    /// # Errors
    ///
    /// Returns an error for wrong IDs/order/hash/count or an overflowing partition.
    pub fn receive_binary_frame(
        &mut self,
        frame: &[u8],
    ) -> Result<TransferChunkAcknowledgement, ClientError> {
        let chunk = decode_binary_chunk(frame)
            .map_err(|_| invalid("Android binary transfer frame is invalid"))?;
        let pending = self
            .pending
            .as_mut()
            .ok_or_else(|| invalid("no v2 partition is open"))?;
        let sequence = u32::try_from(chunk.sequence)
            .map_err(|_| invalid("binary chunk sequence is invalid"))?;
        if chunk.transfer_id.0 != pending.descriptor.transfer_id
            || sequence != pending.next_sequence
            || chunk.data.len() > TRANSFER_FRAME_BYTES
            || sha256_hex(&chunk.data) != chunk.sha256
        {
            return Err(invalid("Android binary chunk changed or is out of order"));
        }
        let chunk_bytes =
            u64::try_from(chunk.data.len()).map_err(|_| invalid("binary chunk is too large"))?;
        let next_bytes = pending
            .received_bytes
            .checked_add(chunk_bytes)
            .ok_or_else(|| invalid("partition byte count overflow"))?;
        if next_bytes > pending.descriptor.byte_count {
            return Err(invalid("binary chunk exceeds partition byte count"));
        }
        let mut output = fs::OpenOptions::new()
            .append(true)
            .open(&pending.path)
            .map_err(storage_error)?;
        output.write_all(&chunk.data).map_err(storage_error)?;
        pending.received_bytes = next_bytes;
        pending.next_sequence = pending
            .next_sequence
            .checked_add(1)
            .ok_or_else(|| invalid("binary chunk sequence overflow"))?;
        Ok(TransferChunkAcknowledgement {
            transfer_id: pending.descriptor.transfer_id,
            sequence,
            accepted: true,
            sha256: chunk.sha256,
            message: None,
        })
    }

    /// Durably commit a completed pending partition.
    ///
    /// # Errors
    ///
    /// Returns an error when completion metadata or exact bytes do not match.
    pub fn commit_partition(
        &mut self,
        complete: &TransferPartitionComplete,
    ) -> Result<TransferPartitionAcknowledgement, ClientError> {
        let journal = self
            .journal
            .as_mut()
            .ok_or_else(|| invalid("v2 receiver is not prepared"))?;
        let pending = self
            .pending
            .take()
            .ok_or_else(|| invalid("no v2 partition is open"))?;
        if complete.session_id != journal.session.session_id
            || complete.job_id != journal.request.job_id
            || complete.partition_index != pending.descriptor.index
            || complete.transfer_id != pending.descriptor.transfer_id
            || complete.partition_sha256 != pending.descriptor.sha256
            || pending.received_bytes != pending.descriptor.byte_count
            || u64::from(pending.next_sequence - 1) != pending.descriptor.chunk_count
        {
            return Err(invalid(
                "v2 partition completion does not match pending bytes",
            ));
        }
        // Flush through a writable handle. Windows rejects FlushFileBuffers on the read-only
        // handle returned by File::open even though reading and hashing the partition succeeds.
        fs::OpenOptions::new()
            .write(true)
            .open(&pending.path)
            .and_then(|file| file.sync_all())
            .map_err(storage_error)?;
        let (bytes, digest) = inspect_file(&pending.path)?;
        if bytes != pending.descriptor.byte_count || digest != pending.descriptor.sha256 {
            return Err(invalid("v2 partition digest mismatch"));
        }
        let final_path = partition_path(
            &self.layout,
            journal.request.job_id,
            pending.descriptor.index,
        )?;
        fs::rename(&pending.path, &final_path).map_err(storage_error)?;
        sync_directory(
            final_path
                .parent()
                .ok_or_else(|| invalid("partition path has no parent"))?,
        )
        .map_err(storage_error)?;
        if let Some(index) = pending.replacement_index {
            journal.committed_partitions[index] = pending.descriptor.clone();
        } else {
            journal
                .committed_partitions
                .push(pending.descriptor.clone());
        }
        journal.updated_at = Utc::now();
        save_journal(&self.layout, journal)?;

        let mut record = self.jobs.load(journal.request.job_id)?;
        record.state = JobState::Transferring;
        record.updated_at = Utc::now();
        record.committed_partitions = u64::try_from(journal.committed_partitions.len())
            .map_err(|_| invalid("too many committed partitions"))?;
        record.committed_bytes = journal
            .committed_partitions
            .iter()
            .try_fold(0_u64, |total, value| total.checked_add(value.byte_count))
            .ok_or_else(|| invalid("committed byte count overflow"))?;
        record.message = Some("Receiving Android export artifacts.".into());
        self.jobs.save(&record)?;
        Ok(TransferPartitionAcknowledgement {
            session_id: journal.session.session_id,
            job_id: journal.request.job_id,
            partition_index: pending.descriptor.index,
            transfer_id: pending.descriptor.transfer_id,
            partition_sha256: pending.descriptor.sha256,
            accepted: true,
            message: None,
        })
    }

    /// Validate all artifacts and durably commit the product response.
    ///
    /// # Errors
    ///
    /// Returns an error for incomplete transfer graphs, artifact validation, or destination commit.
    pub fn finalize(
        &mut self,
        finalize: &TransferFinalize,
    ) -> Result<TransferFinalAcknowledgement, ClientError> {
        self.ensure_before_deadline()?;
        let mut journal = self
            .journal
            .clone()
            .ok_or_else(|| invalid("v2 receiver is not prepared"))?;
        validate_finalize(finalize, &journal)?;
        let receipt = match journal.request.product.product_id() {
            ProductId::AndroidProviderNativeSnapshotV1 => self.finalize_raw_snapshot(&journal)?,
            ProductId::GeneratedFilesV1 => self.finalize_generated_files(&mut journal)?,
            ProductId::AndroidDailyRecordsV1 => {
                return Err(invalid(
                    "Android daily-record extraction is not implemented",
                ));
            }
        };
        journal.updated_at = Utc::now();
        save_journal(&self.layout, &journal)?;
        self.journal = Some(journal.clone());

        let mut record = self.jobs.load(journal.request.job_id)?;
        record.state = JobState::AwaitingPeerAcknowledgement;
        record.updated_at = Utc::now();
        record.message = Some("Android export validated and committed.".into());
        record.response_artifact = Some(V2ResponseArtifact {
            path: receipt.path.to_string_lossy().into(),
            byte_count: receipt.byte_count,
            sha256: receipt.sha256.clone(),
            product_id: receipt.product_id,
            status: receipt.status.clone(),
        });
        self.jobs.save(&record)?;
        Ok(TransferFinalAcknowledgement {
            session_id: journal.session.session_id,
            job_id: journal.request.job_id,
            accepted: true,
            total_partitions: finalize.total_partitions,
            total_bytes: finalize.total_bytes,
            final_partition_sha256: finalize.final_partition_sha256.clone(),
            response_byte_count: Some(receipt.byte_count),
            response_sha256: Some(receipt.sha256),
            message: Some("Android export validated and committed.".into()),
        })
    }

    /// Mark completion only after Android confirms the final acknowledgement.
    ///
    /// # Errors
    ///
    /// Returns an error when the durable job is not awaiting confirmation.
    pub fn acknowledge_completion(&self, job_id: Uuid) -> Result<(), ClientError> {
        let mut record = self.jobs.load(job_id)?;
        if record.state != JobState::AwaitingPeerAcknowledgement
            && record.state != JobState::Completed
        {
            return Err(invalid("v2 completion arrived in an invalid state"));
        }
        record.state = JobState::Completed;
        record.updated_at = Utc::now();
        record.message = Some("Android confirmed direct export completion.".into());
        self.jobs.save(&record)?;
        let _ = fs::remove_dir_all(
            self.layout
                .v2_artifact_spools_dir()
                .join(job_id.to_string().to_lowercase()),
        );
        Ok(())
    }

    /// Return a completed or awaiting-confirmation response artifact.
    ///
    /// # Errors
    ///
    /// Returns an error when no valid response exists.
    pub fn receipt(&self, job_id: Uuid) -> Result<V2ArtifactReceipt, ClientError> {
        let record = self.jobs.load(job_id)?;
        if !matches!(
            record.state,
            JobState::AwaitingPeerAcknowledgement | JobState::Completed
        ) {
            return Err(ClientError::JobNotResumable(
                job_id,
                format!("{:?}", record.state).to_lowercase(),
            ));
        }
        let artifact = record
            .response_artifact
            .ok_or_else(|| invalid("v2 response artifact is missing"))?;
        let path = PathBuf::from(artifact.path);
        let (byte_count, sha256) = inspect_file(&path)?;
        if byte_count != artifact.byte_count || sha256 != artifact.sha256 {
            return Err(invalid("v2 response artifact changed"));
        }
        Ok(V2ArtifactReceipt {
            path,
            byte_count,
            sha256,
            status: artifact.status,
            product_id: artifact.product_id,
        })
    }

    fn finalize_raw_snapshot(
        &self,
        journal: &ReceiverJournal,
    ) -> Result<V2ArtifactReceipt, ClientError> {
        if journal.manifests.len() != 1 {
            return Err(invalid(
                "raw snapshot transfer must contain exactly one artifact",
            ));
        }
        let manifest = journal
            .manifests
            .values()
            .next()
            .ok_or_else(|| invalid("raw snapshot manifest is missing"))?;
        let assembled = assemble_artifact(&self.layout, journal, manifest, self.deadline)?;
        self.ensure_before_deadline()?;
        validate_android_snapshot(
            &assembled,
            manifest,
            &journal.request,
            &journal.accepted,
            self.deadline,
        )?;
        self.ensure_before_deadline()?;
        let response_directory = self.response_directory(journal.request.job_id)?;
        let extension = if manifest.media_type == "application/x-ndjson" {
            "ndjson"
        } else {
            "json"
        };
        let response_path = response_directory.join(format!("android-raw-snapshot.{extension}"));
        atomic_private_copy(&assembled, &response_path, self.deadline)?;
        let (byte_count, sha256) = inspect_file(&response_path)?;
        let status = match manifest.snapshot_status.as_deref() {
            Some("PARTIAL" | "partial") => "partial_success",
            Some("COMPLETE" | "complete") => "success",
            _ => return Err(invalid("raw snapshot has no completed terminal status")),
        };
        Ok(V2ArtifactReceipt {
            path: response_path,
            byte_count,
            sha256,
            status: status.into(),
            product_id: ProductId::AndroidProviderNativeSnapshotV1,
        })
    }

    fn finalize_generated_files(
        &self,
        journal: &mut ReceiverJournal,
    ) -> Result<V2ArtifactReceipt, ClientError> {
        if journal.manifests.is_empty() {
            return Err(invalid("generated-file transfer has no artifacts"));
        }
        let record = self.jobs.load(journal.request.job_id)?;
        let destination_root = record
            .destination_root
            .as_ref()
            .ok_or_else(|| invalid("generated-file destination is missing"))?;
        let destination = GeneratedDestination::open(Path::new(destination_root))?;
        let binding = journal
            .request
            .destination
            .as_ref()
            .ok_or_else(|| invalid("generated-file destination binding is missing"))?;
        if destination.binding_sha256()? != binding.binding_sha256 {
            return Err(invalid("generated-file destination binding changed"));
        }

        let manifests: Vec<_> = journal.manifests.values().cloned().collect();
        for manifest in &manifests {
            self.ensure_before_deadline()?;
            let relative_path = manifest
                .relative_path
                .as_ref()
                .ok_or_else(|| invalid("generated file has no relative path"))?;
            let mode = manifest
                .write_mode
                .ok_or_else(|| invalid("generated file has no write mode"))?;
            let source = assemble_artifact(&self.layout, journal, manifest, self.deadline)?;
            let stage = self
                .session_directory(journal.request.job_id)?
                .join(format!("commit-{}.stage", manifest.artifact_id));
            let plan = if let Some(plan) = journal.commit_plans.get(&manifest.artifact_id) {
                plan.clone()
            } else {
                let prepared =
                    destination.prepare_android_stage(relative_path, &source, &stage, mode)?;
                let plan = CommitPlan {
                    artifact_id: manifest.artifact_id,
                    relative_path: relative_path.clone(),
                    before_sha256: prepared.before_sha256,
                    after_sha256: prepared.after_sha256,
                    stage_path: stage.to_string_lossy().into(),
                    committed: false,
                };
                journal
                    .commit_plans
                    .insert(manifest.artifact_id, plan.clone());
                journal.updated_at = Utc::now();
                save_journal(&self.layout, journal)?;
                plan
            };
            self.ensure_before_deadline()?;
            let current = destination.current_digest(&plan.relative_path)?;
            if current.as_deref() != Some(&plan.after_sha256) {
                if current != plan.before_sha256 {
                    return Err(invalid("generated destination changed before commit"));
                }
                destination.install_stage(
                    &plan.relative_path,
                    Path::new(&plan.stage_path),
                    plan.before_sha256.as_deref(),
                    &plan.after_sha256,
                )?;
            }
            let mut committed = plan;
            committed.committed = true;
            journal.commit_plans.insert(manifest.artifact_id, committed);
            journal.updated_at = Utc::now();
            save_journal(&self.layout, journal)?;
        }

        let mut paths: Vec<_> = manifests
            .iter()
            .filter_map(|manifest| manifest.relative_path.clone())
            .collect();
        paths.sort();
        let payload = json!({
            "schema": "healthmd.android_direct_file_receipt",
            "schema_version": 1,
            "backend": "direct",
            "platform": "android",
            "job_id": journal.request.job_id,
            "status": "success",
            "destination_path": destination.root(),
            "files_written": paths.len(),
            "relative_paths": paths,
            "message": "Android export files were committed to the explicit destination."
        });
        let response_path = self
            .response_directory(journal.request.job_id)?
            .join("file-receipt.json");
        save_json(&response_path, &payload)?;
        let (byte_count, sha256) = inspect_file(&response_path)?;
        Ok(V2ArtifactReceipt {
            path: response_path,
            byte_count,
            sha256,
            status: "success".into(),
            product_id: ProductId::GeneratedFilesV1,
        })
    }

    fn ensure_before_deadline(&self) -> Result<(), ClientError> {
        if self
            .deadline
            .is_some_and(|deadline| std::time::Instant::now() >= deadline)
        {
            return Err(ClientError::TimedOut);
        }
        Ok(())
    }

    fn session_directory(&self, job_id: Uuid) -> Result<PathBuf, ClientError> {
        let path = self
            .layout
            .v2_artifact_spools_dir()
            .join(job_id.to_string().to_lowercase());
        create_private_directory(&path)?;
        Ok(path)
    }

    fn response_directory(&self, job_id: Uuid) -> Result<PathBuf, ClientError> {
        let path = self
            .layout
            .v2_response_spools_dir()
            .join(job_id.to_string().to_lowercase());
        create_private_directory(&path)?;
        Ok(path)
    }
}

fn validate_manifest(manifest: &ArtifactManifest) -> Result<(), ClientError> {
    if manifest.job_id.is_nil()
        || manifest.artifact_id.is_nil()
        || manifest.byte_count == 0
        || manifest.media_type.is_empty()
        || manifest.media_type.len() > 128
        || manifest.schema.id.len() > 128
        || manifest
            .provider_id
            .as_ref()
            .is_some_and(|value| value.len() > 128)
        || manifest
            .relative_path
            .as_ref()
            .is_some_and(|value| value.len() > 4_096)
        || !is_sha256(&manifest.sha256)
        || manifest
            .logical_checksum_sha256
            .as_ref()
            .is_some_and(|digest| !is_sha256(digest))
    {
        return Err(invalid("artifact manifest is invalid"));
    }
    match manifest.kind {
        ArtifactKind::RawSnapshot => {
            if manifest.schema.id != "healthmd.raw-snapshot"
                || manifest.schema.major != 1
                || !matches!(
                    manifest.media_type.as_str(),
                    "application/vnd.healthmd.raw-snapshot+json" | "application/x-ndjson"
                )
                || manifest.relative_path.is_some()
                || manifest.write_mode.is_some()
                || manifest.logical_checksum_sha256.is_none()
                || !matches!(
                    manifest.snapshot_status.as_deref(),
                    Some("COMPLETE" | "PARTIAL")
                )
                || manifest.provider_id.as_deref().is_none_or(str::is_empty)
            {
                return Err(invalid("raw snapshot artifact manifest is invalid"));
            }
        }
        ArtifactKind::GeneratedFile => {
            if manifest.schema.id != "healthmd.generated-files"
                || manifest.schema.major != 1
                || !matches!(
                    manifest.media_type.as_str(),
                    "text/markdown; charset=utf-8"
                        | "application/json"
                        | "text/csv; charset=utf-8"
                        | "application/yaml; charset=utf-8"
                )
                || manifest.relative_path.is_none()
                || manifest.write_mode.is_none()
                || manifest.snapshot_status.is_some()
                || manifest.provider_id.is_some()
            {
                return Err(invalid("generated-file artifact manifest is invalid"));
            }
        }
        ArtifactKind::DailyRecords => {
            if manifest.schema.id != "healthmd.health_data" || manifest.schema.major != 4 {
                return Err(invalid("daily-record artifact manifest is invalid"));
            }
        }
    }
    Ok(())
}

fn manifest_matches_request(manifest: &ArtifactManifest, journal: &ReceiverJournal) -> bool {
    match &journal.request.product {
        v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
            provider_id,
            format,
            ..
        } => {
            let expected_media = match format {
                v2::RawSnapshotFormat::Json => "application/vnd.healthmd.raw-snapshot+json",
                v2::RawSnapshotFormat::Ndjson => "application/x-ndjson",
            };
            manifest.provider_id.as_deref() == Some(provider_id)
                && journal.accepted.provider_id.as_deref() == Some(provider_id)
                && manifest.media_type == expected_media
                && manifest.relative_path.is_none()
                && manifest.write_mode.is_none()
        }
        v2::ExportProduct::GeneratedFilesV1 { .. } => {
            manifest.provider_id.is_none()
                && manifest.logical_checksum_sha256.is_none()
                && manifest.snapshot_status.is_none()
                && manifest.relative_path.is_some()
                && manifest.write_mode.is_some()
        }
        v2::ExportProduct::AndroidDailyRecordsV1 { .. } => false,
    }
}

const fn manifest_matches_product(manifest: &ArtifactManifest, product: ProductId) -> bool {
    matches!(
        (manifest.kind, product),
        (
            ArtifactKind::RawSnapshot,
            ProductId::AndroidProviderNativeSnapshotV1
        ) | (ArtifactKind::GeneratedFile, ProductId::GeneratedFilesV1)
            | (ArtifactKind::DailyRecords, ProductId::AndroidDailyRecordsV1)
    )
}

fn validate_open(open: &TransferOpen, journal: &ReceiverJournal) -> Result<(), ClientError> {
    let descriptor = &open.partition;
    if open.session != journal.session
        || descriptor.index >= MAXIMUM_PARTITIONS
        || descriptor.transfer_id.is_nil()
        || descriptor.artifact_id.is_nil()
        || descriptor.byte_count == 0
        || descriptor.byte_count > journal.session.partition_target_bytes
        || descriptor.chunk_count == 0
        || descriptor.chunk_count
            != descriptor
                .byte_count
                .div_ceil(u64::try_from(TRANSFER_FRAME_BYTES).expect("chunk limit fits u64"))
        || !is_sha256(&descriptor.sha256)
        || descriptor
            .previous_sha256
            .as_ref()
            .is_some_and(|digest| !is_sha256(digest))
        || !journal.manifests.contains_key(&descriptor.artifact_id)
        || journal.committed_partitions.iter().any(|saved| {
            saved.transfer_id == descriptor.transfer_id && saved.index != descriptor.index
        })
    {
        return Err(invalid("v2 transfer partition is invalid"));
    }
    let expected_previous = descriptor
        .index
        .checked_sub(1)
        .and_then(|index| usize::try_from(index).ok())
        .and_then(|index| journal.committed_partitions.get(index))
        .map(|partition| partition.sha256.as_str());
    if descriptor.previous_sha256.as_deref() != expected_previous {
        return Err(invalid("v2 partition digest chain changed"));
    }
    let expected_offset = journal
        .committed_partitions
        .iter()
        .filter(|partition| {
            partition.artifact_id == descriptor.artifact_id && partition.index < descriptor.index
        })
        .try_fold(0_u64, |total, partition| {
            total.checked_add(partition.byte_count)
        })
        .ok_or_else(|| invalid("artifact offset overflow"))?;
    let manifest = journal
        .manifests
        .get(&descriptor.artifact_id)
        .ok_or_else(|| invalid("partition artifact is missing"))?;
    if descriptor.artifact_offset != expected_offset
        || descriptor
            .artifact_offset
            .checked_add(descriptor.byte_count)
            .is_none_or(|end| end > manifest.byte_count)
    {
        return Err(invalid("v2 partition artifact range is invalid"));
    }
    Ok(())
}

fn validate_finalize(
    finalize: &TransferFinalize,
    journal: &ReceiverJournal,
) -> Result<(), ClientError> {
    let fingerprint = v2::request_fingerprint(&journal.request)
        .map_err(|_| invalid("v2 request fingerprint failed"))?;
    let total_partitions = u64::try_from(journal.committed_partitions.len())
        .map_err(|_| invalid("too many partitions"))?;
    let total_bytes = journal
        .committed_partitions
        .iter()
        .try_fold(0_u64, |total, partition| {
            total.checked_add(partition.byte_count)
        })
        .ok_or_else(|| invalid("transfer byte count overflow"))?;
    let manifest_bytes = journal
        .manifests
        .values()
        .try_fold(0_u64, |total, manifest| {
            total.checked_add(manifest.byte_count)
        })
        .ok_or_else(|| invalid("manifest byte count overflow"))?;
    if finalize.session_id != journal.session.session_id
        || finalize.job_id != journal.request.job_id
        || finalize.request_fingerprint != fingerprint
        || finalize.total_partitions != total_partitions
        || finalize.total_bytes != total_bytes
        || total_bytes != manifest_bytes
        || finalize.final_partition_sha256.as_deref()
            != journal
                .committed_partitions
                .last()
                .map(|partition| partition.sha256.as_str())
        || journal.manifests.is_empty()
    {
        return Err(invalid(
            "v2 transfer finalization does not match durable state",
        ));
    }
    for manifest in journal.manifests.values() {
        let covered = journal
            .committed_partitions
            .iter()
            .filter(|partition| partition.artifact_id == manifest.artifact_id)
            .try_fold(0_u64, |total, partition| {
                total.checked_add(partition.byte_count)
            })
            .ok_or_else(|| invalid("artifact coverage overflow"))?;
        if covered != manifest.byte_count {
            return Err(invalid("artifact transfer is incomplete"));
        }
    }
    Ok(())
}

fn assemble_artifact(
    layout: &StorageLayout,
    journal: &ReceiverJournal,
    manifest: &ArtifactManifest,
    deadline: Option<std::time::Instant>,
) -> Result<PathBuf, ClientError> {
    let directory = layout
        .v2_artifact_spools_dir()
        .join(journal.request.job_id.to_string().to_lowercase());
    let path = directory.join(format!("artifact-{}.bin", manifest.artifact_id));
    if path.exists() {
        let (bytes, digest) = inspect_file(&path)?;
        if bytes == manifest.byte_count && digest == manifest.sha256 {
            return Ok(path);
        }
    }
    let mut output = private_file(&path)?;
    output.set_len(0).map_err(storage_error)?;
    for partition in journal
        .committed_partitions
        .iter()
        .filter(|partition| partition.artifact_id == manifest.artifact_id)
    {
        ensure_deadline(deadline)?;
        let mut input = File::open(partition_path(
            layout,
            journal.request.job_id,
            partition.index,
        )?)
        .map_err(storage_error)?;
        io::copy(&mut input, &mut output).map_err(storage_error)?;
    }
    output.sync_all().map_err(storage_error)?;
    let (bytes, digest) = inspect_file(&path)?;
    if bytes != manifest.byte_count || digest != manifest.sha256 {
        return Err(invalid("assembled v2 artifact digest mismatch"));
    }
    Ok(path)
}

fn validate_android_snapshot(
    path: &Path,
    artifact: &ArtifactManifest,
    request: &v2::ExportRequest,
    accepted: &v2::ExportAccepted,
    deadline: Option<std::time::Instant>,
) -> Result<(), ClientError> {
    if artifact.media_type == "application/x-ndjson" {
        validate_android_ndjson(path, artifact, request, accepted, deadline)
    } else {
        validate_android_json(path, artifact, request, accepted, deadline)
    }
}

fn validate_android_ndjson(
    path: &Path,
    artifact: &ArtifactManifest,
    request: &v2::ExportRequest,
    accepted: &v2::ExportAccepted,
    deadline: Option<std::time::Instant>,
) -> Result<(), ClientError> {
    let input = File::open(path).map_err(storage_error)?;
    let mut reader = BufReader::new(input);
    let mut line = String::new();
    let mut line_index = 0_u64;
    let mut saw_manifest = false;
    let mut header: Option<Value> = None;
    let mut manifest: Option<Value> = None;
    let mut logical = Sha256::new();
    let mut record_count = 0_u64;
    let mut issue_count = 0_u64;
    let mut type_counts = BTreeMap::<String, u64>::new();
    loop {
        ensure_deadline(deadline)?;
        line.clear();
        let count = reader
            .by_ref()
            .take(MAXIMUM_NDJSON_LINE_BYTES + 1)
            .read_line(&mut line)
            .map_err(storage_error)?;
        if count == 0 {
            break;
        }
        if u64::try_from(count).unwrap_or(u64::MAX) > MAXIMUM_NDJSON_LINE_BYTES
            || !line.ends_with('\n')
            || line.trim().is_empty()
            || saw_manifest
        {
            return Err(invalid("Android NDJSON snapshot framing is invalid"));
        }
        let value: Value = serde_json::from_str(line.trim_end_matches('\n'))
            .map_err(|_| invalid("Android NDJSON snapshot contains malformed JSON"))?;
        let kind = value
            .get("kind")
            .and_then(Value::as_str)
            .ok_or_else(|| invalid("Android NDJSON item has no kind"))?;
        match (line_index, kind) {
            (0, "header") if exact_object_keys(&value, &["kind", "header"]) => {
                let item = value
                    .get("header")
                    .cloned()
                    .ok_or_else(|| invalid("snapshot header is missing"))?;
                update_logical_digest(&mut logical, "header", &normalized_logical_header(&item)?)?;
                header = Some(item);
            }
            (_, "record") if exact_object_keys(&value, &["kind", "record"]) => {
                let record = value
                    .get("record")
                    .ok_or_else(|| invalid("Android raw record is missing"))?;
                validate_raw_record(record)?;
                validate_route_policy(record, request)?;
                update_logical_digest(&mut logical, "record", record)?;
                let wire_type = record
                    .get("wireType")
                    .and_then(Value::as_str)
                    .expect("validated raw record wire type");
                let count = type_counts.entry(wire_type.to_owned()).or_default();
                *count = count
                    .checked_add(1)
                    .ok_or_else(|| invalid("Android type count overflow"))?;
                record_count = record_count
                    .checked_add(1)
                    .ok_or_else(|| invalid("Android record count overflow"))?;
            }
            (_, "issue") if exact_object_keys(&value, &["kind", "issue"]) => {
                let issue = value
                    .get("issue")
                    .ok_or_else(|| invalid("Android raw issue is missing"))?;
                validate_raw_issue(issue)?;
                update_logical_digest(&mut logical, "issue", issue)?;
                issue_count = issue_count
                    .checked_add(1)
                    .ok_or_else(|| invalid("Android issue count overflow"))?;
            }
            (_, "manifest") if exact_object_keys(&value, &["kind", "manifest"]) => {
                manifest = value.get("manifest").cloned();
                saw_manifest = true;
            }
            _ => return Err(invalid("Android NDJSON snapshot item order is invalid")),
        }
        line_index = line_index
            .checked_add(1)
            .ok_or_else(|| invalid("Android NDJSON line count overflow"))?;
    }
    validate_snapshot_integrity(
        header
            .as_ref()
            .ok_or_else(|| invalid("snapshot header is missing"))?,
        manifest
            .as_ref()
            .ok_or_else(|| invalid("snapshot manifest is missing"))?,
        artifact,
        record_count,
        issue_count,
        logical,
        &type_counts,
        request,
        accepted,
    )
}

fn validate_android_json(
    path: &Path,
    artifact: &ArtifactManifest,
    request: &v2::ExportRequest,
    accepted: &v2::ExportAccepted,
    deadline: Option<std::time::Instant>,
) -> Result<(), ClientError> {
    if fs::metadata(path).map_err(storage_error)?.len() > MAXIMUM_IN_MEMORY_JSON_BYTES {
        return Err(invalid(
            "Android JSON snapshot exceeds the 64 MiB validation limit; request NDJSON",
        ));
    }
    ensure_deadline(deadline)?;
    let input = File::open(path).map_err(storage_error)?;
    let snapshot: Value = serde_json::from_reader(BufReader::new(input))
        .map_err(|_| invalid("Android JSON snapshot is malformed or incomplete"))?;
    ensure_deadline(deadline)?;
    if !exact_object_keys(&snapshot, &["header", "records", "issues", "manifest"]) {
        return Err(invalid("Android JSON snapshot envelope is invalid"));
    }
    let header = snapshot
        .get("header")
        .ok_or_else(|| invalid("snapshot header is missing"))?;
    let records = snapshot
        .get("records")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid("Android snapshot records are invalid"))?;
    let issues = snapshot
        .get("issues")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid("Android snapshot issues are invalid"))?;
    let manifest = snapshot
        .get("manifest")
        .ok_or_else(|| invalid("snapshot manifest is missing"))?;
    let mut logical = Sha256::new();
    let mut type_counts = BTreeMap::<String, u64>::new();
    update_logical_digest(&mut logical, "header", &normalized_logical_header(header)?)?;
    for record in records {
        validate_raw_record(record)?;
        validate_route_policy(record, request)?;
        update_logical_digest(&mut logical, "record", record)?;
        let wire_type = record
            .get("wireType")
            .and_then(Value::as_str)
            .expect("validated raw record wire type");
        let count = type_counts.entry(wire_type.to_owned()).or_default();
        *count = count
            .checked_add(1)
            .ok_or_else(|| invalid("Android type count overflow"))?;
    }
    for issue in issues {
        validate_raw_issue(issue)?;
        update_logical_digest(&mut logical, "issue", issue)?;
    }
    validate_snapshot_integrity(
        header,
        manifest,
        artifact,
        u64::try_from(records.len()).map_err(|_| invalid("Android record count overflow"))?,
        u64::try_from(issues.len()).map_err(|_| invalid("Android issue count overflow"))?,
        logical,
        &type_counts,
        request,
        accepted,
    )
}

#[allow(clippy::too_many_arguments)]
fn validate_snapshot_integrity(
    header: &Value,
    manifest: &Value,
    artifact: &ArtifactManifest,
    record_count: u64,
    issue_count: u64,
    logical: Sha256,
    observed_type_counts: &BTreeMap<String, u64>,
    request: &v2::ExportRequest,
    accepted: &v2::ExportAccepted,
) -> Result<(), ClientError> {
    validate_snapshot_identity(header, manifest, artifact, request, accepted)?;
    validate_selected_health_connect_types(request, artifact, observed_type_counts)?;
    validate_selected_health_connect_reports(request, artifact, manifest)?;
    let manifest_record_count = manifest.get("recordCount").and_then(Value::as_u64);
    let manifest_issue_count = manifest.get("issueCount").and_then(Value::as_u64);
    let logical_sha256 = encode_hex(&logical.finalize());
    let declared_logical = manifest
        .get("logicalChecksumSha256")
        .and_then(Value::as_str);
    let snapshot_id_matches = header.get("snapshotId") == manifest.get("snapshotId");
    if manifest_record_count != Some(record_count)
        || manifest_issue_count != Some(issue_count)
        || declared_logical != Some(logical_sha256.as_str())
        || !snapshot_id_matches
    {
        return Err(invalid(
            "Android raw snapshot accounting or logical checksum is invalid",
        ));
    }
    let manifest_object = manifest
        .as_object()
        .ok_or_else(|| invalid("Android raw manifest is not an object"))?;
    for required in [
        "schema",
        "version",
        "snapshotId",
        "status",
        "completedAt",
        "recordCount",
        "issueCount",
        "duplicateCount",
        "identityCollisionCount",
        "typeCounts",
        "typeReports",
        "logicalChecksumSha256",
        "manifestChecksumSha256",
        "artifactChecksumSha256",
    ] {
        if !manifest_object.contains_key(required) {
            return Err(invalid("Android raw manifest is missing required metadata"));
        }
    }
    let declared_type_counts = manifest
        .get("typeCounts")
        .and_then(parse_type_counts)
        .ok_or_else(|| invalid("Android raw manifest type counts are invalid"))?;
    if &declared_type_counts != observed_type_counts {
        return Err(invalid(
            "Android raw manifest type counts do not match records",
        ));
    }
    let reported_type_counts = manifest
        .get("typeReports")
        .and_then(parse_report_record_counts)
        .ok_or_else(|| invalid("Android raw manifest type reports are invalid"))?;
    if &reported_type_counts != observed_type_counts {
        return Err(invalid("Android raw type reports do not match records"));
    }
    let declared_manifest = manifest
        .get("manifestChecksumSha256")
        .and_then(Value::as_str)
        .ok_or_else(|| invalid("Android raw manifest checksum is missing"))?;
    let mut checksum_value = manifest.clone();
    let checksum_object = checksum_value
        .as_object_mut()
        .ok_or_else(|| invalid("Android raw manifest is not an object"))?;
    checksum_object.remove("manifestChecksumSha256");
    checksum_object.remove("artifactChecksumSha256");
    let manifest_sha256 = sha256_hex(
        &canonical_json(&checksum_value)
            .map_err(|_| invalid("Android raw manifest canonicalization failed"))?,
    );
    if declared_manifest != manifest_sha256 {
        return Err(invalid("Android raw manifest checksum is invalid"));
    }
    Ok(())
}

fn validate_selected_health_connect_types(
    request: &v2::ExportRequest,
    artifact: &ArtifactManifest,
    observed: &BTreeMap<String, u64>,
) -> Result<(), ClientError> {
    let v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
        scope:
            v2::RawSnapshotScope::SelectedRecordTypes {
                selected_metric_ids,
            },
        ..
    } = &request.product
    else {
        return Ok(());
    };
    if artifact.provider_id.as_deref() != Some("health_connect") {
        return Ok(());
    }
    if observed
        .keys()
        .any(|wire_type| !health_connect_wire_is_selected(wire_type, selected_metric_ids))
    {
        return Err(invalid(
            "Android raw snapshot contains an out-of-scope record type",
        ));
    }
    Ok(())
}

fn validate_selected_health_connect_reports(
    request: &v2::ExportRequest,
    artifact: &ArtifactManifest,
    manifest: &Value,
) -> Result<(), ClientError> {
    let v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
        scope:
            v2::RawSnapshotScope::SelectedRecordTypes {
                selected_metric_ids,
            },
        ..
    } = &request.product
    else {
        return Ok(());
    };
    if artifact.provider_id.as_deref() != Some("health_connect") {
        return Ok(());
    }
    let reports = manifest
        .get("typeReports")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid("Android raw type reports are invalid"))?;
    for report in reports {
        let object = report
            .as_object()
            .ok_or_else(|| invalid("Android raw type report is invalid"))?;
        let wire_type = object
            .get("wireType")
            .and_then(Value::as_str)
            .ok_or_else(|| invalid("Android raw type report wire type is invalid"))?;
        let status = object
            .get("status")
            .and_then(Value::as_str)
            .ok_or_else(|| invalid("Android raw type report status is invalid"))?;
        if health_connect_wire_is_selected(wire_type, selected_metric_ids)
            == (status == "not_selected")
        {
            return Err(invalid("Android raw type report selection is inconsistent"));
        }
    }
    Ok(())
}

#[allow(clippy::too_many_lines)]
fn health_connect_wire_is_selected(wire_type: &str, selected: &[String]) -> bool {
    let metrics: &[&str] = match wire_type {
        "steps" => &["steps"],
        "heart_rate" => &["avg_hr", "min_hr", "max_hr"],
        "sleep_session" => &[
            "sleep_total",
            "sleep_deep",
            "sleep_rem",
            "sleep_light",
            "sleep_awake",
            "sleep_in_bed",
        ],
        "exercise_session" => &[
            "exercise_minutes",
            "cycling_distance",
            "swimming_distance",
            "swimming_strokes",
            "wheelchair_distance",
            "downhill_snow_distance",
            "walking_hr",
            "running_speed",
            "running_power",
            "workouts",
        ],
        "distance" => &[
            "distance",
            "cycling_distance",
            "swimming_distance",
            "wheelchair_distance",
            "downhill_snow_distance",
        ],
        "active_calories_burned" => &["active_calories"],
        "total_calories_burned" => &["total_calories"],
        "basal_metabolic_rate" => &["basal_calories"],
        "blood_pressure" => &["bp_systolic", "bp_diastolic"],
        "blood_glucose" => &["blood_glucose"],
        "body_fat" => &["body_fat"],
        "body_temperature" => &["body_temp"],
        "height" => &["height", "bmi"],
        "weight" => &["weight", "bmi"],
        "oxygen_saturation" => &["blood_oxygen"],
        "respiratory_rate" => &["respiratory_rate"],
        "heart_rate_variability_rmssd" => &["hrv"],
        "nutrition" => &[
            "dietary_energy",
            "protein",
            "carbs",
            "fat",
            "saturated_fat",
            "monounsaturated_fat",
            "polyunsaturated_fat",
            "unsaturated_fat",
            "trans_fat",
            "fiber",
            "sugar",
            "sodium",
            "potassium",
            "calcium",
            "iron",
            "magnesium",
            "zinc",
            "phosphorus",
            "iodine",
            "selenium",
            "copper",
            "manganese",
            "chromium",
            "molybdenum",
            "chloride",
            "vitamin_a",
            "vitamin_b6",
            "vitamin_b12",
            "vitamin_c",
            "vitamin_d",
            "vitamin_e",
            "vitamin_k",
            "thiamin",
            "riboflavin",
            "niacin",
            "folate",
            "folic_acid",
            "pantothenic_acid",
            "biotin",
            "cholesterol",
            "caffeine",
            "energy_from_fat",
            "nutrition_meals",
        ],
        "hydration" => &["water"],
        "floors_climbed" => &["flights_climbed"],
        "lean_body_mass" => &["lean_mass"],
        "resting_heart_rate" => &["resting_hr"],
        "speed" => &["walking_speed", "running_speed"],
        "vo2_max" => &["vo2_max"],
        "elevation_gained" => &["elevation_gained"],
        "wheelchair_pushes" => &["wheelchair_pushes"],
        "power" => &["power_avg", "power_max", "running_power"],
        "basal_body_temperature" => &["basal_body_temp"],
        "body_water_mass" => &["body_water_mass"],
        "bone_mass" => &["bone_mass"],
        "skin_temperature" => &["skin_temperature"],
        "cervical_mucus" => &["cervical_mucus"],
        "intermenstrual_bleeding" => &["intermenstrual_bleeding"],
        "menstruation_flow" => &["menstrual_flow"],
        "menstruation_period" => &["menstruation_periods", "menstruation_period_days"],
        "ovulation_test" => &["ovulation_test"],
        "sexual_activity" => &["sexual_activity"],
        "cycling_pedaling_cadence" => &["cycling_cadence"],
        "steps_cadence" => &["steps_cadence"],
        "mindfulness_session" => &["mindful_minutes", "mindful_sessions"],
        "planned_exercise_session" => &["planned_workouts"],
        "activity_intensity" => &["activity_intensity_minutes"],
        "medical_resource" => &["medical_resources"],
        _ => return false,
    };
    metrics
        .iter()
        .any(|metric| selected.iter().any(|value| value == metric))
}

fn parse_type_counts(value: &Value) -> Option<BTreeMap<String, u64>> {
    let values = value.as_array()?;
    let mut counts = BTreeMap::new();
    let mut previous: Option<&str> = None;
    for value in values {
        let object = value.as_object()?;
        if object.len() != 2 || !object.contains_key("wireType") || !object.contains_key("count") {
            return None;
        }
        let wire_type = object.get("wireType")?.as_str()?;
        if previous.is_some_and(|saved| saved >= wire_type) {
            return None;
        }
        let count = object.get("count")?.as_u64()?;
        counts.insert(wire_type.to_owned(), count);
        previous = Some(wire_type);
    }
    Some(counts)
}

fn parse_report_record_counts(value: &Value) -> Option<BTreeMap<String, u64>> {
    let values = value.as_array()?;
    let mut counts = BTreeMap::<String, u64>::new();
    let mut previous: Option<&str> = None;
    for value in values {
        let object = value.as_object()?;
        for required in [
            "typeKey",
            "wireType",
            "status",
            "recordCount",
            "issueCount",
            "permission",
            "feature",
            "rangeBehavior",
            "message",
        ] {
            if !object.contains_key(required) {
                return None;
            }
        }
        let type_key = object.get("typeKey")?.as_str()?;
        if previous.is_some_and(|saved| saved >= type_key) {
            return None;
        }
        previous = Some(type_key);
        let status = object.get("status")?.as_str()?;
        if !matches!(
            status,
            "exported"
                | "not_selected"
                | "permission_not_granted"
                | "feature_unavailable"
                | "history_permission_missing"
                | "read_error"
                | "unsupported_by_provider"
        ) {
            return None;
        }
        let wire_type = object.get("wireType")?.as_str()?;
        let count = object.get("recordCount")?.as_u64()?;
        let issue_count = object.get("issueCount")?.as_u64()?;
        if status != "exported" && count != 0 {
            return None;
        }
        if status == "not_selected" && issue_count != 0 {
            return None;
        }
        if !matches!(
            object.get("rangeBehavior")?.as_str()?,
            "instant" | "overlap" | "unbounded_non_temporal"
        ) {
            return None;
        }
        for optional in ["permission", "feature", "message"] {
            let value = object.get(optional)?;
            if !value.is_null() && value.as_str().is_none() {
                return None;
            }
        }
        let total = counts.entry(wire_type.to_owned()).or_default();
        *total = total.checked_add(count)?;
    }
    counts.retain(|_, count| *count != 0);
    Some(counts)
}

fn encode_hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    bytes.iter().fold(String::new(), |mut output, byte| {
        write!(output, "{byte:02x}").expect("writing to a string succeeds");
        output
    })
}

fn update_logical_digest(
    digest: &mut Sha256,
    kind: &str,
    value: &Value,
) -> Result<(), ClientError> {
    digest.update(kind.as_bytes());
    digest.update([0]);
    digest.update(
        canonical_json(value).map_err(|_| invalid("Android raw item canonicalization failed"))?,
    );
    digest.update(b"\n");
    Ok(())
}

fn normalized_logical_header(header: &Value) -> Result<Value, ClientError> {
    let mut normalized = header.clone();
    normalized
        .get_mut("request")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| invalid("Android raw request metadata is invalid"))?
        .insert("format".into(), Value::String("JSON".into()));
    Ok(normalized)
}

fn validate_raw_record(value: &Value) -> Result<(), ClientError> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid("Android raw record is not an object"))?;
    for required in [
        "wireType",
        "nativeIdentity",
        "recordKind",
        "source",
        "startTime",
        "endTime",
        "startZoneOffsetSeconds",
        "endZoneOffsetSeconds",
        "metadata",
        "fields",
        "providerPayload",
        "hash",
    ] {
        if !object.contains_key(required) {
            return Err(invalid("Android raw record is missing required metadata"));
        }
    }
    let record_kind = object.get("recordKind").and_then(Value::as_str);
    let declared_hash = object.get("hash").and_then(Value::as_str);
    if object.get("wireType").and_then(Value::as_str).is_none()
        || object
            .get("nativeIdentity")
            .and_then(Value::as_str)
            .is_none()
        || !matches!(
            record_kind,
            Some("health_connect_record" | "provider_payload")
        )
        || object.get("source").and_then(Value::as_object).is_none()
        || object.get("fields").and_then(Value::as_object).is_none()
        || declared_hash.is_none_or(|digest| !is_sha256(digest))
    {
        return Err(invalid("Android raw record metadata has invalid types"));
    }
    let expected_hash = if record_kind == Some("provider_payload") {
        let payload = object
            .get("providerPayload")
            .and_then(Value::as_object)
            .ok_or_else(|| invalid("Android provider payload metadata is invalid"))?;
        let response_bytes = payload
            .get("responseBytesBase64")
            .and_then(Value::as_str)
            .and_then(|encoded| STANDARD.decode(encoded).ok())
            .ok_or_else(|| invalid("Android provider payload bytes are invalid"))?;
        let response_sha256 = sha256_hex(&response_bytes);
        if payload.get("responseSha256").and_then(Value::as_str) != Some(response_sha256.as_str()) {
            return Err(invalid("Android provider payload checksum is invalid"));
        }
        response_sha256
    } else {
        let mut unhashed = value.clone();
        unhashed
            .as_object_mut()
            .expect("validated record object")
            .remove("hash");
        sha256_hex(
            &canonical_json(&unhashed)
                .map_err(|_| invalid("Android raw record canonicalization failed"))?,
        )
    };
    if declared_hash != Some(expected_hash.as_str()) {
        return Err(invalid("Android raw record checksum is invalid"));
    }
    Ok(())
}

fn validate_route_policy(record: &Value, request: &v2::ExportRequest) -> Result<(), ClientError> {
    let routes_allowed = matches!(
        request.product,
        v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
            include_exercise_routes: true,
            ..
        }
    );
    let contains_route = record.get("wireType").and_then(Value::as_str) == Some("exercise_session")
        && record
            .get("fields")
            .and_then(Value::as_object)
            .is_some_and(|fields| fields.contains_key("route"));
    if !routes_allowed && contains_route {
        return Err(invalid(
            "Android raw snapshot violates the exercise-route policy",
        ));
    }
    Ok(())
}

fn validate_raw_issue(value: &Value) -> Result<(), ClientError> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid("Android raw issue is not an object"))?;
    for required in ["code", "message", "severity", "recordType", "retryable"] {
        if !object.contains_key(required) {
            return Err(invalid("Android raw issue is missing required metadata"));
        }
    }
    if object.get("code").and_then(Value::as_str).is_none()
        || object.get("message").and_then(Value::as_str).is_none()
        || !matches!(
            object.get("severity").and_then(Value::as_str),
            Some("INFO" | "WARNING" | "ERROR")
        )
        || object.get("retryable").and_then(Value::as_bool).is_none()
    {
        return Err(invalid("Android raw issue metadata has invalid types"));
    }
    Ok(())
}

fn exact_object_keys(value: &Value, expected: &[&str]) -> bool {
    value.as_object().is_some_and(|object| {
        object.len() == expected.len() && expected.iter().all(|key| object.contains_key(*key))
    })
}

fn validate_snapshot_identity(
    header: &Value,
    manifest: &Value,
    artifact: &ArtifactManifest,
    request: &v2::ExportRequest,
    accepted: &v2::ExportAccepted,
) -> Result<(), ClientError> {
    let schema = header.get("schema").and_then(Value::as_str);
    let version = header.get("version").and_then(Value::as_u64);
    let provider = header
        .pointer("/capabilities/providerId")
        .and_then(Value::as_str);
    let manifest_schema = manifest.get("schema").and_then(Value::as_str);
    let manifest_version = manifest.get("version").and_then(Value::as_u64);
    let status = manifest.get("status").and_then(Value::as_str);
    let logical = manifest
        .get("logicalChecksumSha256")
        .and_then(Value::as_str);
    let raw_request = header.get("request").and_then(Value::as_object);
    let calendar_zone = raw_request
        .and_then(|value| value.get("calendarZoneId"))
        .and_then(Value::as_str);
    let start_date = raw_request
        .and_then(|value| value.get("startTime"))
        .and_then(|value| raw_instant_date(value, calendar_zone?));
    let end_date = raw_request
        .and_then(|value| value.get("endTime"))
        .and_then(|value| raw_exclusive_end_date(value, calendar_zone?));
    let (expected_format, expected_scope, expected_metrics, expected_routes) =
        match &request.product {
            v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
                format,
                scope,
                include_exercise_routes,
                ..
            } => {
                let format = match format {
                    v2::RawSnapshotFormat::Json => "JSON",
                    v2::RawSnapshotFormat::Ndjson => "NDJSON",
                };
                let (scope, metrics) = match scope {
                    v2::RawSnapshotScope::AllAuthorizedSupportedData => {
                        ("ALL_AUTHORIZED_SUPPORTED_DATA", Vec::new())
                    }
                    v2::RawSnapshotScope::SelectedRecordTypes {
                        selected_metric_ids,
                    } => ("SELECTED_RECORD_TYPES", selected_metric_ids.clone()),
                };
                (format, scope, metrics, *include_exercise_routes)
            }
            _ => return Err(invalid("Android raw request product changed")),
        };
    let embedded_metrics = raw_request
        .and_then(|value| value.get("selectedMetricIds"))
        .and_then(Value::as_array)
        .and_then(|values| {
            values
                .iter()
                .map(Value::as_str)
                .map(|value| value.map(ToOwned::to_owned))
                .collect::<Option<Vec<_>>>()
        });
    if schema != Some("healthmd.raw-snapshot")
        || version != Some(1)
        || manifest_schema != Some("healthmd.raw-snapshot.manifest")
        || manifest_version != Some(1)
        || provider != artifact.provider_id.as_deref()
        || status != artifact.snapshot_status.as_deref()
        || logical != artifact.logical_checksum_sha256.as_deref()
        || logical.is_none_or(|digest| !is_sha256(digest))
        || accepted.provider_id.as_deref() != artifact.provider_id.as_deref()
        || calendar_zone != Some(accepted.resolved_range.time_zone_id.as_str())
        || raw_request
            .and_then(|value| value.get("format"))
            .and_then(Value::as_str)
            != Some(expected_format)
        || raw_request
            .and_then(|value| value.get("scope"))
            .and_then(Value::as_str)
            != Some(expected_scope)
        || embedded_metrics.as_deref() != Some(expected_metrics.as_slice())
        || raw_request
            .and_then(|value| value.get("includeExerciseRoutes"))
            .and_then(Value::as_bool)
            != Some(expected_routes)
        || start_date.as_deref() != Some(accepted.resolved_range.start_date.as_str())
        || end_date.as_deref() != Some(accepted.resolved_range.end_date.as_str())
    {
        return Err(invalid(
            "Android raw snapshot identity does not match its manifest",
        ));
    }
    Ok(())
}

fn raw_instant(value: &Value) -> Option<chrono::DateTime<Utc>> {
    let object = value.as_object()?;
    let epoch = object.get("epochSecond").and_then(|value| {
        value
            .as_str()
            .and_then(|text| text.parse::<i64>().ok())
            .or_else(|| value.as_i64())
    })?;
    let nano = object.get("nano")?.as_u64()?;
    chrono::DateTime::from_timestamp(epoch, u32::try_from(nano).ok()?)
}

fn raw_instant_date(value: &Value, zone: &str) -> Option<String> {
    let zone = zone.parse::<chrono_tz::Tz>().ok()?;
    raw_instant(value).map(|instant| instant.with_timezone(&zone).date_naive().to_string())
}

fn raw_exclusive_end_date(value: &Value, zone: &str) -> Option<String> {
    let zone = zone.parse::<chrono_tz::Tz>().ok()?;
    raw_instant(value)
        .and_then(|instant| instant.checked_sub_signed(chrono::Duration::nanoseconds(1)))
        .map(|instant| instant.with_timezone(&zone).date_naive().to_string())
}

fn safe_relative_path(value: &str) -> Result<PathBuf, ClientError> {
    if value.is_empty()
        || value.len() > 4_096
        || value.contains(['\\', '\0', ':'])
        || value.chars().any(char::is_control)
        || value.split('/').any(|segment| {
            segment.is_empty()
                || matches!(segment, "." | "..")
                || segment.ends_with(['.', ' '])
                || is_windows_reserved_name(segment)
        })
    {
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

fn is_windows_reserved_name(segment: &str) -> bool {
    let stem = segment.split('.').next().unwrap_or(segment);
    matches!(
        stem.to_ascii_uppercase().as_str(),
        "CON"
            | "PRN"
            | "AUX"
            | "NUL"
            | "COM1"
            | "COM2"
            | "COM3"
            | "COM4"
            | "COM5"
            | "COM6"
            | "COM7"
            | "COM8"
            | "COM9"
            | "LPT1"
            | "LPT2"
            | "LPT3"
            | "LPT4"
            | "LPT5"
            | "LPT6"
            | "LPT7"
            | "LPT8"
            | "LPT9"
    )
}

fn destination_collision_key(value: &str) -> String {
    value.nfd().flat_map(char::to_lowercase).collect()
}

fn save_journal(layout: &StorageLayout, journal: &ReceiverJournal) -> Result<(), ClientError> {
    save_json(
        &layout
            .v2_artifact_spools_dir()
            .join(journal.request.job_id.to_string().to_lowercase())
            .join("receiver-journal.json"),
        journal,
    )
}

fn save_json<T: Serialize>(path: &Path, value: &T) -> Result<(), ClientError> {
    let bytes = canonical_json(value).map_err(|_| invalid("JSON encoding failed"))?;
    atomic_private_replace(path, &bytes)
}

fn partition_path(
    layout: &StorageLayout,
    job_id: Uuid,
    index: u64,
) -> Result<PathBuf, ClientError> {
    if index >= MAXIMUM_PARTITIONS {
        return Err(invalid("partition index exceeds the receiver limit"));
    }
    Ok(layout
        .v2_artifact_spools_dir()
        .join(job_id.to_string().to_lowercase())
        .join(format!("partition-{index:08}.bin")))
}

fn partition_matches(path: &Path, descriptor: &v2::TransferPartition) -> Result<bool, ClientError> {
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

fn inspect_file(path: &Path) -> Result<(u64, String), ClientError> {
    let mut input = File::open(path).map_err(storage_error)?;
    let mut hasher = Sha256::new();
    let bytes = io::copy(&mut input, &mut HashWriter(&mut hasher)).map_err(storage_error)?;
    Ok((bytes, format!("{:x}", hasher.finalize())))
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
    let parent = path
        .parent()
        .ok_or_else(|| invalid("private file path has no parent"))?;
    create_private_directory(parent)?;
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    options.open(path).map_err(storage_error)
}

fn atomic_private_replace(path: &Path, bytes: &[u8]) -> Result<(), ClientError> {
    let directory = path
        .parent()
        .ok_or_else(|| invalid("durable path has no parent"))?;
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

fn atomic_private_copy(
    source: &Path,
    destination: &Path,
    deadline: Option<std::time::Instant>,
) -> Result<(), ClientError> {
    let directory = destination
        .parent()
        .ok_or_else(|| invalid("response path has no parent"))?;
    create_private_directory(directory)?;
    let mut temporary = NamedTempFile::new_in(directory).map_err(storage_error)?;
    let mut input = File::open(source).map_err(storage_error)?;
    let mut buffer = vec![0_u8; 128 * 1_024];
    loop {
        ensure_deadline(deadline)?;
        let count = input.read(&mut buffer).map_err(storage_error)?;
        if count == 0 {
            break;
        }
        temporary
            .write_all(&buffer[..count])
            .map_err(storage_error)?;
    }
    temporary.as_file().sync_all().map_err(storage_error)?;
    temporary
        .persist(destination)
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

fn ensure_deadline(deadline: Option<std::time::Instant>) -> Result<(), ClientError> {
    if deadline.is_some_and(|deadline| std::time::Instant::now() >= deadline) {
        return Err(ClientError::TimedOut);
    }
    Ok(())
}

fn invalid(message: &str) -> ClientError {
    ClientError::InvalidTransfer(message.into())
}

#[allow(clippy::needless_pass_by_value)]
fn storage_error(error: io::Error) -> ClientError {
    ClientError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, Timelike as _};
    use healthmd_protocol::{
        encoding::SwiftUuid,
        models::TransferChunk,
        transfer::encode_binary_chunk,
        v2::{
            ArtifactSchema, DateSelection, ExportProduct, PeerBinding, RawSnapshotFormat,
            RawSnapshotScope, ResolvedRange,
        },
    };
    use tempfile::TempDir;

    use super::*;
    use crate::v2_job::V2JobRecord;

    #[test]
    #[allow(clippy::too_many_lines)]
    fn android_raw_snapshot_transfer_is_durable_and_validated() {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("data"),
        };
        let jobs = V2JobStore::new(layout.clone()).unwrap();
        let now = Utc::now().with_nanosecond(0).unwrap();
        let source_id = Uuid::new_v4();
        let destination_id = Uuid::new_v4();
        let job_id = Uuid::new_v4();
        let snapshot_id = "0123456789abcdef0123456789abcdef";
        let header = json!({
            "schema": "healthmd.raw-snapshot",
            "version": 1,
            "snapshotId": snapshot_id,
            "createdAt": {"epochSecond": "1784764800", "nano": 0},
            "request": {
                "format": "JSON",
                "scope": "ALL_AUTHORIZED_SUPPORTED_DATA",
                "startTime": {"epochSecond": "1782864000", "nano": 0},
                "endTime": {"epochSecond": "1782950400", "nano": 0},
                "selectedMetricIds": [],
                "pageSize": 1000,
                "includeExerciseRoutes": false,
                "calendarZoneId": "UTC"
            },
            "capabilities": {
                "sdkVersion": "test",
                "available": true,
                "providerId": "health_connect",
                "fidelityLevel": "HEALTH_CONNECT_API_PROJECTED",
                "grantedPermissions": [],
                "availableFeatures": [],
                "historicalReadGranted": true,
                "nonTransactional": true,
                "preservesSourceUnits": false,
                "preservesUnknownSdkFields": false
            }
        });
        let mut logical = Sha256::new();
        update_logical_digest(&mut logical, "header", &header).unwrap();
        let logical_checksum = encode_hex(&logical.finalize());
        let mut raw_manifest = json!({
            "schema": "healthmd.raw-snapshot.manifest",
            "version": 1,
            "snapshotId": snapshot_id,
            "status": "COMPLETE",
            "completedAt": {"epochSecond": "1784764801", "nano": 0},
            "recordCount": 0,
            "issueCount": 0,
            "duplicateCount": 0,
            "identityCollisionCount": 0,
            "typeCounts": [],
            "typeReports": [],
            "logicalChecksumSha256": logical_checksum
        });
        let manifest_checksum = sha256_hex(&canonical_json(&raw_manifest).unwrap());
        let manifest_object = raw_manifest.as_object_mut().unwrap();
        manifest_object.insert("manifestChecksumSha256".into(), json!(manifest_checksum));
        manifest_object.insert("artifactChecksumSha256".into(), Value::Null);
        let snapshot = serde_json::to_vec(&json!({
            "header": header,
            "records": [],
            "issues": [],
            "manifest": raw_manifest
        }))
        .unwrap();
        let request = v2::ExportRequest {
            job_id,
            created_at: now,
            expires_at: now + Duration::days(7),
            source_installation_id: source_id,
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
        };
        jobs.save(&V2JobRecord::new(request.clone(), None)).unwrap();
        let fingerprint = v2::request_fingerprint(&request).unwrap();
        let binding = PeerBinding {
            source_installation_id: source_id,
            destination_installation_id: destination_id,
        };
        let accepted = v2::ExportAccepted {
            job_id,
            accepted_at: now,
            peer_binding: binding.clone(),
            product_id: ProductId::AndroidProviderNativeSnapshotV1,
            resolved_range: ResolvedRange {
                start_date: "2026-07-01".into(),
                end_date: "2026-07-01".into(),
                time_zone_id: "UTC".into(),
            },
            provider_id: Some("health_connect".into()),
            settings_snapshot_sha256: None,
            request_fingerprint: fingerprint.clone(),
        };
        let session = TransferSession {
            session_id: Uuid::new_v4(),
            job_id,
            request_fingerprint: fingerprint.clone(),
            peer_binding: binding,
            partition_target_bytes: 32 * 1_024 * 1_024,
            created_at: now,
        };
        let artifact_id = Uuid::new_v4();
        let artifact_sha = sha256_hex(&snapshot);
        let manifest = ArtifactManifest {
            job_id,
            artifact_id,
            kind: ArtifactKind::RawSnapshot,
            schema: ArtifactSchema {
                id: "healthmd.raw-snapshot".into(),
                major: 1,
            },
            media_type: "application/vnd.healthmd.raw-snapshot+json".into(),
            byte_count: u64::try_from(snapshot.len()).unwrap(),
            sha256: artifact_sha.clone(),
            logical_checksum_sha256: Some(logical_checksum),
            relative_path: None,
            write_mode: None,
            snapshot_status: Some("COMPLETE".into()),
            provider_id: Some("health_connect".into()),
        };
        let transfer_id = Uuid::new_v4();
        let partition = v2::TransferPartition {
            index: 0,
            transfer_id,
            artifact_id,
            artifact_offset: 0,
            byte_count: u64::try_from(snapshot.len()).unwrap(),
            chunk_count: 1,
            sha256: artifact_sha.clone(),
            previous_sha256: None,
        };

        let mut receiver = V2ArtifactReceiver::new(layout.clone(), jobs.clone());
        receiver
            .prepare(request.clone(), accepted.clone(), session.clone())
            .unwrap();
        receiver.store_manifest(manifest.clone()).unwrap();
        assert_eq!(
            receiver
                .disposition(TransferOpen {
                    session: session.clone(),
                    partition: partition.clone(),
                })
                .unwrap()
                .disposition,
            TransferDispositionKind::Needed
        );
        let frame = encode_binary_chunk(&TransferChunk {
            transfer_id: SwiftUuid(transfer_id),
            sequence: 1,
            data: snapshot.clone(),
            sha256: artifact_sha.clone(),
        })
        .unwrap();
        receiver.receive_binary_frame(&frame).unwrap();
        let complete = TransferPartitionComplete {
            session_id: session.session_id,
            job_id,
            partition_index: 0,
            transfer_id,
            partition_sha256: artifact_sha.clone(),
        };
        receiver.commit_partition(&complete).unwrap();

        fs::write(partition_path(&layout, job_id, 0).unwrap(), b"corrupt").unwrap();
        let mut resumed = V2ArtifactReceiver::new(layout, jobs.clone());
        resumed.prepare(request, accepted, session.clone()).unwrap();
        resumed.store_manifest(manifest).unwrap();
        assert_eq!(
            resumed
                .disposition(TransferOpen {
                    session: session.clone(),
                    partition,
                })
                .unwrap()
                .disposition,
            TransferDispositionKind::Needed
        );
        resumed.receive_binary_frame(&frame).unwrap();
        resumed.commit_partition(&complete).unwrap();
        receiver = resumed;

        let acknowledgement = receiver
            .finalize(&TransferFinalize {
                session_id: session.session_id,
                job_id,
                request_fingerprint: fingerprint,
                total_partitions: 1,
                total_bytes: u64::try_from(snapshot.len()).unwrap(),
                final_partition_sha256: Some(artifact_sha),
            })
            .unwrap();
        assert!(acknowledgement.accepted);
        receiver.acknowledge_completion(job_id).unwrap();
        let receipt = receiver.receipt(job_id).unwrap();
        assert_eq!(fs::read(receipt.path).unwrap(), snapshot);
        assert_eq!(jobs.load(job_id).unwrap().state, JobState::Completed);
    }

    #[test]
    #[allow(clippy::too_many_lines)]
    fn android_generated_file_transfer_commits_with_v2_destination_binding() {
        let temporary = TempDir::new().unwrap();
        let destination_path = temporary.path().join("destination");
        fs::create_dir(&destination_path).unwrap();
        fs::write(destination_path.join("daily.md"), b"existing").unwrap();
        let destination = GeneratedDestination::open(&destination_path).unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("data"),
        };
        let jobs = V2JobStore::new(layout.clone()).unwrap();
        let now = Utc::now().with_nanosecond(0).unwrap();
        let source_id = Uuid::new_v4();
        let destination_id = Uuid::new_v4();
        let job_id = Uuid::new_v4();
        let request = v2::ExportRequest {
            job_id,
            created_at: now,
            expires_at: now + Duration::days(7),
            source_installation_id: source_id,
            date_selection: DateSelection::Exact {
                start_date: "2026-07-23".into(),
                end_date: "2026-07-23".into(),
            },
            product: ExportProduct::GeneratedFilesV1 {
                settings_policy: v2::SettingsPolicy::SavedDeviceSettings,
            },
            destination: Some(v2::DestinationBinding {
                binding_sha256: destination.binding_sha256().unwrap(),
                display_name: "destination".into(),
            }),
        };
        jobs.save(&V2JobRecord::new(
            request.clone(),
            Some(destination_path.to_string_lossy().into()),
        ))
        .unwrap();
        let fingerprint = v2::request_fingerprint(&request).unwrap();
        let binding = PeerBinding {
            source_installation_id: source_id,
            destination_installation_id: destination_id,
        };
        let accepted = v2::ExportAccepted {
            job_id,
            accepted_at: now,
            peer_binding: binding.clone(),
            product_id: ProductId::GeneratedFilesV1,
            resolved_range: ResolvedRange {
                start_date: "2026-07-23".into(),
                end_date: "2026-07-23".into(),
                time_zone_id: "UTC".into(),
            },
            provider_id: None,
            settings_snapshot_sha256: Some("2".repeat(64)),
            request_fingerprint: fingerprint.clone(),
        };
        let session = TransferSession {
            session_id: Uuid::new_v4(),
            job_id,
            request_fingerprint: fingerprint.clone(),
            peer_binding: binding,
            partition_target_bytes: 32 * 1_024 * 1_024,
            created_at: now,
        };
        let data = b"fresh".to_vec();
        let digest = sha256_hex(&data);
        let artifact_id = Uuid::new_v4();
        let manifest = ArtifactManifest {
            job_id,
            artifact_id,
            kind: ArtifactKind::GeneratedFile,
            schema: ArtifactSchema {
                id: "healthmd.generated-files".into(),
                major: 1,
            },
            media_type: "text/markdown; charset=utf-8".into(),
            byte_count: u64::try_from(data.len()).unwrap(),
            sha256: digest.clone(),
            logical_checksum_sha256: None,
            relative_path: Some("daily.md".into()),
            write_mode: Some(v2::FileWriteMode::Append),
            snapshot_status: None,
            provider_id: None,
        };
        let transfer_id = Uuid::new_v4();
        let partition = v2::TransferPartition {
            index: 0,
            transfer_id,
            artifact_id,
            artifact_offset: 0,
            byte_count: u64::try_from(data.len()).unwrap(),
            chunk_count: 1,
            sha256: digest.clone(),
            previous_sha256: None,
        };
        let mut receiver = V2ArtifactReceiver::new(layout, jobs.clone());
        receiver
            .prepare(request, accepted, session.clone())
            .unwrap();
        receiver.store_manifest(manifest).unwrap();
        receiver
            .disposition(TransferOpen {
                session: session.clone(),
                partition,
            })
            .unwrap();
        receiver
            .receive_binary_frame(
                &encode_binary_chunk(&TransferChunk {
                    transfer_id: SwiftUuid(transfer_id),
                    sequence: 1,
                    data: data.clone(),
                    sha256: digest.clone(),
                })
                .unwrap(),
            )
            .unwrap();
        receiver
            .commit_partition(&TransferPartitionComplete {
                session_id: session.session_id,
                job_id,
                partition_index: 0,
                transfer_id,
                partition_sha256: digest.clone(),
            })
            .unwrap();
        receiver
            .finalize(&TransferFinalize {
                session_id: session.session_id,
                job_id,
                request_fingerprint: fingerprint,
                total_partitions: 1,
                total_bytes: u64::try_from(data.len()).unwrap(),
                final_partition_sha256: Some(digest),
            })
            .unwrap();
        assert_eq!(
            fs::read(destination_path.join("daily.md")).unwrap(),
            b"existing\nfresh"
        );
        receiver.acknowledge_completion(job_id).unwrap();
        assert_eq!(jobs.load(job_id).unwrap().state, JobState::Completed);
    }

    #[test]
    fn raw_snapshot_validation_rejects_placeholder_records_and_issues() {
        assert!(validate_raw_record(&Value::Null).is_err());
        assert!(validate_raw_record(&json!({"wireType": "StepsRecord"})).is_err());
        assert!(validate_raw_issue(&json!({"code": "read_error"})).is_err());
    }

    #[test]
    fn generated_relative_paths_reject_aliases_and_traversal() {
        assert!(safe_relative_path("../private.json").is_err());
        assert!(safe_relative_path("folder\\private.json").is_err());
        assert!(safe_relative_path("folder//private.json").is_err());
        assert!(safe_relative_path("folder/./private.json").is_err());
        assert!(safe_relative_path("CON.json").is_err());
        assert!(safe_relative_path("folder/health.md").is_ok());
    }
}
