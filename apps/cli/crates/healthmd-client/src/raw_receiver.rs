use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File},
    io::{self, BufReader, Seek as _, Write as _},
    path::{Path, PathBuf},
};

use chrono::{SecondsFormat, Utc};
use healthmd_protocol::{
    TRANSFER_FRAME_BYTES,
    encoding::canonical_json,
    models::{
        CanonicalSelection, ExportAccepted, ExportRequest, RawDayManifest, ResponseMode,
        TransferChunk, TransferChunkAcknowledgement, TransferDisposition, TransferDispositionKind,
        TransferFinalAcknowledgement, TransferFinalize, TransferOpen, TransferPartition,
        TransferPartitionAcknowledgement, TransferPartitionComplete, TransferSession,
    },
    transfer::{is_sha256, request_fingerprint, sha256_hex},
    wire::RawProfile,
};
use serde::{
    Deserialize, Serialize,
    de::{DeserializeSeed, Error as _, IgnoredAny, MapAccess, SeqAccess, Visitor},
};
use serde_json::{Map, Value, json, value::RawValue};
use sha2::{Digest as _, Sha256};
use tempfile::NamedTempFile;
use uuid::Uuid;

use crate::{
    ClientError,
    job::{JobState, JobStore, ResponseArtifact},
    limits::{
        MAXIMUM_DATES_PER_JOB, MAXIMUM_DURABLE_JSON_BYTES, MAXIMUM_PARTITIONS_PER_JOB,
        StorageReservation, ensure_job_bytes, prepare_private_directory, read_bounded,
        reserve_materialization_storage, reserve_partition_capacity, reserve_private_storage,
    },
    storage::StorageLayout,
};

const JOURNAL_VERSION: u16 = 1;
const MAXIMUM_FIELD_POINTERS: usize = 256;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
struct RawJournal {
    version: u16,
    request: ExportRequest,
    accepted: ExportAccepted,
    session: TransferSession,
    manifests: BTreeMap<String, RawDayManifest>,
    #[serde(rename = "committedPartitions")]
    committed_partitions: Vec<TransferPartition>,
    #[serde(rename = "updatedAt", with = "healthmd_protocol::time")]
    updated_at: chrono::DateTime<Utc>,
}

#[derive(Deserialize)]
struct HealthDataIdentity {
    schema: String,
    schema_version: i64,
    date: String,
    #[serde(default, rename = "raw_capture_status")]
    _raw_capture_status: Option<String>,
    #[serde(default)]
    healthkit_record_archive: Option<HealthKitArchiveIdentity>,
}

#[derive(Deserialize)]
struct HealthKitArchiveIdentity {
    schema: String,
    schema_version: i64,
}

struct PendingPartition {
    descriptor: TransferPartition,
    path: PathBuf,
    next_sequence: i64,
    received_bytes: i64,
    _storage_reservation: StorageReservation,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RawReceiveArtifact {
    pub path: PathBuf,
    pub status: String,
    pub sha256: String,
    pub byte_count: i64,
    pub date_range_start: String,
    pub date_range_end: String,
    pub total_days: i64,
    pub profile: RawProfile,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JsonlExtractionArtifact {
    pub path: PathBuf,
    pub receipt_path: PathBuf,
    pub status: String,
}

pub struct RawReceiver {
    layout: StorageLayout,
    jobs: JobStore,
    journal: Option<RawJournal>,
    pending: Option<PendingPartition>,
}

impl RawReceiver {
    #[must_use]
    pub const fn new(layout: StorageLayout, jobs: JobStore) -> Self {
        Self {
            layout,
            jobs,
            journal: None,
            pending: None,
        }
    }

    /// Create or reopen an immutable direct raw transfer session.
    ///
    /// # Errors
    ///
    /// Returns an error when request/session/binding/dates/fingerprint differ or durable storage
    /// cannot be updated.
    pub fn prepare(
        &mut self,
        request: ExportRequest,
        accepted: ExportAccepted,
        session: TransferSession,
    ) -> Result<(), ClientError> {
        validate_prepare(&request, &accepted, &session)?;
        let directory = self.session_directory(request.job_id.0)?;
        let journal_path = directory.join("journal.json");
        let journal = if journal_path.exists() {
            let persisted = load_journal(&journal_path)?;
            if persisted.version != JOURNAL_VERSION
                || persisted.request != request
                || persisted.session != session
                || persisted.accepted.peer_binding != accepted.peer_binding
                || persisted.accepted.resolved_date_identifiers
                    != accepted.resolved_date_identifiers
                || persisted.accepted.source_device_name != accepted.source_device_name
                || persisted.accepted.source_time_zone_identifier
                    != accepted.source_time_zone_identifier
                || persisted.accepted.resolved_canonical_selection
                    != accepted.resolved_canonical_selection
            {
                return Err(invalid("durable raw session changed"));
            }
            persisted
        } else {
            let created = RawJournal {
                version: JOURNAL_VERSION,
                request,
                accepted,
                session,
                manifests: BTreeMap::new(),
                committed_partitions: Vec::new(),
                updated_at: Utc::now(),
            };
            save_json(&self.layout.root, &journal_path, &created)?;
            created
        };
        validate_persisted_limits(&journal)?;
        let _ = fs::remove_file(directory.join("pending.partition"));
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
                .map_err(|_| invalid("too many resolved dates"))?,
        );
        record.message = Some("iPhone accepted the direct raw export.".into());
        self.jobs.save(&record)
    }

    /// Durably store one immutable day manifest.
    ///
    /// # Errors
    ///
    /// Returns an error for invalid/unexpected/changed manifests or storage failure.
    pub fn store_manifest(&mut self, manifest: RawDayManifest) -> Result<(), ClientError> {
        validate_manifest(&manifest)?;
        let journal = self
            .journal
            .as_mut()
            .ok_or_else(|| invalid("raw receiver is not prepared"))?;
        if manifest.job_id != journal.request.job_id
            || !journal
                .accepted
                .resolved_date_identifiers
                .contains(&manifest.date)
        {
            return Err(invalid("raw manifest contains an unexpected date"));
        }
        if journal
            .manifests
            .get(&manifest.date)
            .is_some_and(|saved| saved != &manifest)
        {
            return Err(invalid("raw manifest changed after persistence"));
        }
        let other_bytes = journal
            .manifests
            .iter()
            .filter(|(date, _)| *date != &manifest.date)
            .try_fold(0_u64, |total, (_, saved)| {
                total
                    .checked_add(
                        u64::try_from(saved.health_data_byte_count)
                            .map_err(|_| invalid("raw manifest byte count is invalid"))?,
                    )
                    .ok_or_else(|| invalid("raw manifest byte total overflow"))
            })?;
        let manifest_bytes = u64::try_from(manifest.health_data_byte_count)
            .map_err(|_| invalid("raw manifest byte count is invalid"))?;
        ensure_job_bytes(
            other_bytes
                .checked_add(manifest_bytes)
                .ok_or_else(|| invalid("raw manifest byte total overflow"))?,
        )?;
        journal.manifests.insert(manifest.date.clone(), manifest);
        journal.updated_at = Utc::now();
        save_journal(&self.layout, journal)
    }

    /// Decide whether an exact partition descriptor is needed or already durable.
    ///
    /// # Errors
    ///
    /// Returns an error for changed/out-of-order/invalid descriptors or storage failure.
    pub fn disposition(&mut self, open: TransferOpen) -> Result<TransferDisposition, ClientError> {
        let layout = self.layout.clone();
        let journal = self
            .journal
            .as_mut()
            .ok_or_else(|| invalid("raw receiver is not prepared"))?;
        validate_open(&open, journal)?;
        let descriptor = open.partition;
        let index =
            usize::try_from(descriptor.index).map_err(|_| invalid("negative partition index"))?;
        if index < journal.committed_partitions.len() {
            if journal.committed_partitions[index] != descriptor {
                return Err(invalid("committed partition descriptor changed"));
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
            return Err(invalid("partition arrived out of order"));
        }
        let directory = layout
            .corpus_sessions_dir()
            .join(open.session.job_id.0.to_string().to_lowercase());
        create_private_directory(&directory)?;
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
        let path = directory.join("pending.partition");
        let file = private_file(&path, false)?;
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

    /// Append and fsync one authenticated binary chunk.
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
            .ok_or_else(|| invalid("no partition is open"))?;
        let chunk_bytes =
            i64::try_from(chunk.data.len()).map_err(|_| invalid("chunk is too large"))?;
        if chunk.transfer_id != pending.descriptor.transfer_id
            || chunk.sequence != pending.next_sequence
            || chunk.data.len() > TRANSFER_FRAME_BYTES
            || sha256_hex(&chunk.data) != chunk.sha256
            || pending.received_bytes + chunk_bytes > pending.descriptor.byte_count
        {
            return Err(invalid("transfer chunk failed validation"));
        }
        let mut file = fs::OpenOptions::new()
            .append(true)
            .open(&pending.path)
            .map_err(storage_error)?;
        file.write_all(&chunk.data).map_err(storage_error)?;
        file.sync_data().map_err(storage_error)?;
        pending.next_sequence += 1;
        pending.received_bytes += chunk_bytes;
        Ok(TransferChunkAcknowledgement {
            transfer_id: chunk.transfer_id,
            sequence: chunk.sequence,
            accepted: true,
            sha256: chunk.sha256,
            message: None,
        })
    }

    /// Verify and atomically commit the pending partition before acknowledging it.
    ///
    /// # Errors
    ///
    /// Returns an error for descriptor/count/digest mismatch or durable storage failure.
    pub fn commit_partition(
        &mut self,
        complete: TransferPartitionComplete,
    ) -> Result<TransferPartitionAcknowledgement, ClientError> {
        let mut journal = self
            .journal
            .take()
            .ok_or_else(|| invalid("raw receiver is not prepared"))?;
        let pending = self
            .pending
            .take()
            .ok_or_else(|| invalid("no partition is open"))?;
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
            return Err(invalid(
                "partition completion does not match received bytes",
            ));
        }
        let (bytes, digest) = inspect_file(&pending.path)?;
        if bytes != pending.descriptor.byte_count || digest != pending.descriptor.sha256 {
            self.journal = Some(journal);
            self.pending = Some(pending);
            return Err(invalid("partition digest does not match descriptor"));
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
                .map(|partition| partition.byte_count),
        )?;
        record.processed_days = completed_day_count(&journal)?;
        record.message = Some(format!(
            "Committed direct corpus partition {}.",
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

    /// Validate the complete corpus and assemble a strict response on disk.
    ///
    /// # Errors
    ///
    /// Returns an error for finalization/corpus/JSON/digest mismatch or storage failure.
    pub fn finalize(
        &mut self,
        finalize: &TransferFinalize,
    ) -> Result<RawReceiveArtifact, ClientError> {
        let journal = self
            .journal
            .as_ref()
            .ok_or_else(|| invalid("raw receiver is not prepared"))?;
        let total_bytes = checked_byte_total(
            journal
                .committed_partitions
                .iter()
                .map(|partition| partition.byte_count),
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
                    .map(|partition| partition.sha256.clone())
        {
            return Err(invalid("finalization does not match durable corpus"));
        }
        validate_complete_corpus(&self.layout, journal)?;
        let artifact = assemble_response(&self.layout, journal)?;

        let mut record = self.jobs.load(journal.request.job_id.0)?;
        record.state = JobState::AwaitingPeerAcknowledgement;
        record.updated_at = Utc::now();
        record.committed_partitions = finalize.total_partitions;
        record.committed_bytes = finalize.total_bytes;
        record.processed_days = artifact.total_days;
        record.total_days = Some(artifact.total_days);
        record.message =
            Some("Direct raw response committed; awaiting iPhone acknowledgement.".into());
        record.response_artifact = Some(ResponseArtifact {
            relative_path: artifact
                .path
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| invalid("response path is invalid"))?
                .into(),
            byte_count: artifact.byte_count,
            sha256: artifact.sha256.clone(),
            date_range_start: artifact.date_range_start.clone(),
            date_range_end: artifact.date_range_end.clone(),
            total_days: artifact.total_days,
        });
        self.jobs.save(&record)?;
        Ok(artifact)
    }

    /// Mark a previously acknowledged artifact complete after iPhone confirmation.
    ///
    /// # Errors
    ///
    /// Returns an error when the job is not awaiting confirmation or cannot be saved.
    pub fn acknowledge_peer_completion(&self, job_id: Uuid) -> Result<(), ClientError> {
        let mut record = self.jobs.load(job_id)?;
        if record.state != JobState::AwaitingPeerAcknowledgement
            || record.response_artifact.is_none()
        {
            return Err(invalid("job is not awaiting peer confirmation"));
        }
        record.state = JobState::Completed;
        record.updated_at = Utc::now();
        record.message = Some("Direct raw export completed and acknowledged by iPhone.".into());
        self.jobs.save(&record)
    }

    /// Reopen and revalidate an already assembled raw response without loading it into memory.
    ///
    /// # Errors
    ///
    /// Returns an error when the job/artifact/journal is missing, changed, or corrupt.
    pub fn artifact(&self, job_id: Uuid) -> Result<RawReceiveArtifact, ClientError> {
        let record = self.jobs.load(job_id)?;
        let saved = record
            .response_artifact
            .ok_or_else(|| invalid("job has no raw response artifact"))?;
        let profile = record
            .request
            .raw_profile
            .ok_or_else(|| invalid("job has no raw profile"))?;
        let path = self
            .layout
            .response_spools_dir()
            .join(job_id.to_string().to_lowercase())
            .join(&saved.relative_path);
        let (byte_count, digest) = inspect_file(&path)?;
        if byte_count != saved.byte_count || digest != saved.sha256 {
            return Err(invalid("saved raw response digest changed"));
        }
        let journal = load_journal(&self.session_directory(job_id)?.join("journal.json"))?;
        Ok(RawReceiveArtifact {
            path,
            status: response_status(&journal),
            sha256: digest,
            byte_count,
            date_range_start: saved.date_range_start,
            date_range_end: saved.date_range_end,
            total_days: saved.total_days,
            profile,
        })
    }

    /// Materialize the canonical extraction envelope from durable projection partitions.
    ///
    /// Full daily documents remain streamed from partition files. Pointer projection is bounded
    /// to one 64 MiB daily document, matching the deployed CLI contract.
    ///
    /// # Errors
    ///
    /// Returns an error when the journal/corpus/pointers are invalid or output cannot be written.
    pub fn extraction(
        &self,
        job_id: Uuid,
        pointers: &[String],
    ) -> Result<RawReceiveArtifact, ClientError> {
        let journal = load_journal(&self.session_directory(job_id)?.join("journal.json"))?;
        let source_versions = validate_complete_corpus(&self.layout, &journal)?;
        assemble_extraction(&self.layout, &journal, pointers, &source_versions)
    }

    /// Materialize canonical extraction as one JSON value per line plus a receipt sidecar.
    ///
    /// # Errors
    ///
    /// Returns an error when extraction validation or bounded streaming conversion fails.
    pub fn extraction_jsonl(
        &self,
        job_id: Uuid,
        pointers: &[String],
    ) -> Result<JsonlExtractionArtifact, ClientError> {
        let journal = load_journal(&self.session_directory(job_id)?.join("journal.json"))?;
        if journal
            .manifests
            .values()
            .any(|manifest| manifest.health_data_byte_count > 64 * 1_024 * 1_024)
        {
            return Err(invalid(
                "one canonical day exceeds the 64 MiB JSONL item bound; use JSON output",
            ));
        }
        let extraction = self.extraction(job_id, pointers)?;
        let (path, receipt_path) = extraction_to_jsonl(&self.layout, &extraction.path)?;
        Ok(JsonlExtractionArtifact {
            path,
            receipt_path,
            status: extraction.status,
        })
    }

    /// Mark a nonterminal raw job cancelled and discard any pending partition handle.
    ///
    /// # Errors
    ///
    /// Returns an error when the job cannot be loaded or saved.
    pub fn cancel(&mut self, job_id: Uuid) -> Result<(), ClientError> {
        let mut record = self.jobs.load(job_id)?;
        record.state = JobState::Cancelled;
        record.updated_at = Utc::now();
        record.message = Some("Direct export cancelled by the CLI.".into());
        self.pending = None;
        self.jobs.save(&record)
    }

    /// Build the positive final acknowledgement for an assembled artifact.
    #[must_use]
    pub fn final_acknowledgement(
        finalize: &TransferFinalize,
        artifact: &RawReceiveArtifact,
    ) -> TransferFinalAcknowledgement {
        TransferFinalAcknowledgement {
            session_id: finalize.session_id,
            job_id: finalize.job_id,
            accepted: true,
            total_partitions: finalize.total_partitions,
            total_bytes: finalize.total_bytes,
            final_partition_sha256: finalize.final_partition_sha256.clone(),
            response_byte_count: Some(artifact.byte_count),
            response_sha256: Some(artifact.sha256.clone()),
            message: Some("CLI durably validated and assembled the strict raw response.".into()),
        }
    }

    fn session_directory(&self, job_id: Uuid) -> Result<PathBuf, ClientError> {
        let directory = self
            .layout
            .corpus_sessions_dir()
            .join(job_id.to_string().to_lowercase());
        create_private_directory(&directory)?;
        Ok(directory)
    }
}

fn validate_prepare(
    request: &ExportRequest,
    accepted: &ExportAccepted,
    session: &TransferSession,
) -> Result<(), ClientError> {
    let dates = &accepted.resolved_date_identifiers;
    let unique: BTreeSet<_> = dates.iter().collect();
    if request.response_mode != ResponseMode::RawJson
        || request.raw_profile.is_none()
        || request.job_id != accepted.job_id
        || request.job_id != session.job_id
        || session.peer_binding != accepted.peer_binding
        || dates.is_empty()
        || dates.len() > MAXIMUM_DATES_PER_JOB
        || dates.windows(2).any(|pair| pair[0] >= pair[1])
        || unique.len() != dates.len()
        || dates.iter().any(|date| !is_source_date(date))
        || !safe_peer_metadata(&accepted.source_device_name, 128)
        || !valid_time_zone(&accepted.source_time_zone_identifier)
        || request_fingerprint(request).map_err(|_| invalid("fingerprint failed"))?
            != session.request_fingerprint
    {
        return Err(invalid("request, acceptance, and session do not agree"));
    }
    Ok(())
}

fn safe_peer_metadata(value: &str, maximum_bytes: usize) -> bool {
    !value.trim().is_empty() && value.len() <= maximum_bytes && !value.chars().any(char::is_control)
}

fn valid_time_zone(value: &str) -> bool {
    value.len() <= 64 && value.parse::<chrono_tz::Tz>().is_ok()
}

fn validate_persisted_limits(journal: &RawJournal) -> Result<(), ClientError> {
    if u64::try_from(journal.committed_partitions.len()).unwrap_or(u64::MAX)
        > MAXIMUM_PARTITIONS_PER_JOB
        || journal.manifests.len() > journal.accepted.resolved_date_identifiers.len()
    {
        return Err(invalid("durable raw journal exceeds receiver limits"));
    }
    for (date, manifest) in &journal.manifests {
        validate_manifest(manifest)?;
        if date != &manifest.date
            || manifest.job_id != journal.request.job_id
            || !journal.accepted.resolved_date_identifiers.contains(date)
        {
            return Err(invalid("durable raw manifest is incompatible"));
        }
    }
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
    let manifest_bytes = journal
        .manifests
        .values()
        .try_fold(0_u64, |total, manifest| {
            total
                .checked_add(
                    u64::try_from(manifest.health_data_byte_count)
                        .map_err(|_| invalid("durable manifest byte count is invalid"))?,
                )
                .ok_or_else(|| invalid("durable manifest byte total overflow"))
        })?;
    ensure_job_bytes(partition_bytes)?;
    ensure_job_bytes(manifest_bytes)
}

fn validate_manifest(manifest: &RawDayManifest) -> Result<(), ClientError> {
    let valid_status = matches!(
        manifest.status.as_str(),
        "complete"
            | "complete_empty"
            | "complete_with_warnings"
            | "partial"
            | "failed"
            | "cancelled"
            | "missing"
    );
    if !is_source_date(&manifest.date)
        || !valid_status
        || manifest.sample_count < 0
        || manifest.record_count < 0
        || manifest.query_status_counts.len() > 5
        || manifest.query_status_counts.iter().any(|(code, count)| {
            !matches!(
                code.as_str(),
                "success" | "failure" | "unsupported" | "skipped" | "cancelled"
            ) || *count < 0
        })
        || manifest.integrity_warning_count < 0
        || manifest.partial_failure_count < 0
        || manifest.integrity_warning_codes.len() > 256
        || manifest.partial_failure_types.len() > 256
        || manifest
            .integrity_warning_codes
            .iter()
            .chain(&manifest.partial_failure_types)
            .any(|code| !is_safe_machine_code(code))
        || manifest
            .capture_status
            .as_deref()
            .is_some_and(|code| !is_safe_machine_code(code))
        || manifest
            .failure_code
            .as_deref()
            .is_some_and(|code| !is_safe_machine_code(code))
        || manifest.health_data_byte_count < 0
        || manifest
            .health_data_sha256
            .as_ref()
            .is_some_and(|digest| !is_sha256(digest))
        || (manifest.health_data_byte_count > 0) != manifest.health_data_sha256.is_some()
    {
        return Err(invalid("raw-day manifest is invalid"));
    }
    Ok(())
}

fn is_safe_machine_code(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'_' | b'-')
        })
}

fn validate_open(open: &TransferOpen, journal: &RawJournal) -> Result<(), ClientError> {
    let descriptor = &open.partition;
    if descriptor.index < 0
        || u64::try_from(descriptor.index).unwrap_or(u64::MAX) >= MAXIMUM_PARTITIONS_PER_JOB
        || descriptor.byte_count < 0
        || descriptor.byte_count > 64 * 1_024 * 1_024
    {
        return Err(invalid("partition descriptor exceeds receiver limits"));
    }
    let Some(segment) = descriptor.item_segment.as_ref() else {
        return Err(invalid("raw partition has no logical item segment"));
    };
    let expected_previous = journal
        .committed_partitions
        .last()
        .map(|partition| partition.sha256.as_str());
    let expected_chunks = if descriptor.byte_count == 0 {
        0
    } else {
        (descriptor.byte_count + i64::try_from(TRANSFER_FRAME_BYTES).unwrap() - 1)
            / i64::try_from(TRANSFER_FRAME_BYTES).unwrap()
    };
    let segment_end = segment.offset.checked_add(descriptor.byte_count);
    let valid = open.session == journal.session
        && descriptor.chunk_count == expected_chunks
        && is_sha256(&descriptor.sha256)
        && descriptor
            .previous_sha256
            .as_ref()
            .is_none_or(|value| is_sha256(value))
        && descriptor.source_dates == [segment.item_id.clone()]
        && segment.offset >= 0
        && segment.item_byte_count >= 0
        && segment_end.is_some_and(|end| end <= segment.item_byte_count)
        && segment.is_final_segment == (segment_end == Some(segment.item_byte_count))
        && journal
            .manifests
            .get(&segment.item_id)
            .is_some_and(|manifest| {
                manifest.health_data_byte_count == segment.item_byte_count
                    && manifest.health_data_sha256.is_some()
            })
        && (usize::try_from(descriptor.index).ok() != Some(journal.committed_partitions.len())
            || descriptor.previous_sha256.as_deref() == expected_previous);
    if !valid {
        return Err(invalid("partition descriptor is invalid"));
    }
    Ok(())
}

#[allow(clippy::too_many_lines)]
fn validate_complete_corpus(
    layout: &StorageLayout,
    journal: &RawJournal,
) -> Result<BTreeMap<String, i64>, ClientError> {
    if journal.manifests.len() != journal.accepted.resolved_date_identifiers.len() {
        return Err(invalid("not every date has a manifest"));
    }
    let mut by_date: BTreeMap<&str, Vec<&TransferPartition>> = BTreeMap::new();
    let mut source_versions = BTreeMap::new();
    let validation_directory = layout
        .corpus_sessions_dir()
        .join(journal.request.job_id.0.to_string().to_lowercase());
    let mut logical_day: Option<NamedTempFile> = None;
    let mut source_schema_version: Option<i64> = None;
    for partition in &journal.committed_partitions {
        let segment = partition
            .item_segment
            .as_ref()
            .ok_or_else(|| invalid("partition has no segment"))?;
        by_date.entry(&segment.item_id).or_default().push(partition);
    }
    for date in &journal.accepted.resolved_date_identifiers {
        let manifest = journal
            .manifests
            .get(date)
            .ok_or_else(|| invalid("date manifest is missing"))?;
        let descriptors = by_date.get(date.as_str()).cloned().unwrap_or_default();
        if manifest.health_data_byte_count == 0 {
            if !descriptors.is_empty() || manifest.health_data_sha256.is_some() {
                return Err(invalid("empty date has transfer partitions"));
            }
            continue;
        }
        let _storage_reservation = reserve_materialization_storage(
            &layout.root,
            &validation_directory,
            u64::try_from(manifest.health_data_byte_count)
                .map_err(|_| invalid("logical day byte count is invalid"))?,
        )?;
        let logical_day = match &mut logical_day {
            Some(file) => file,
            slot @ None => {
                slot.insert(NamedTempFile::new_in(&validation_directory).map_err(storage_error)?)
            }
        };
        set_private_file(logical_day.as_file())?;
        logical_day
            .as_file_mut()
            .set_len(0)
            .map_err(storage_error)?;
        logical_day
            .as_file_mut()
            .seek(io::SeekFrom::Start(0))
            .map_err(storage_error)?;
        let mut offset = 0_i64;
        for descriptor in &descriptors {
            let segment = descriptor.item_segment.as_ref().unwrap();
            if segment.offset != offset
                || segment.item_byte_count != manifest.health_data_byte_count
            {
                return Err(invalid("logical day segment is discontinuous"));
            }
            let path = partition_path(layout, journal.request.job_id.0, descriptor.index)?;
            let mut input = File::open(path).map_err(storage_error)?;
            io::copy(&mut input, logical_day.as_file_mut()).map_err(storage_error)?;
            offset += descriptor.byte_count;
        }
        logical_day
            .as_file_mut()
            .seek(io::SeekFrom::Start(0))
            .map_err(storage_error)?;
        let mut hasher = Sha256::new();
        io::copy(logical_day.as_file_mut(), &mut HashWriter(&mut hasher)).map_err(storage_error)?;
        if offset != manifest.health_data_byte_count
            || descriptors
                .last()
                .and_then(|partition| partition.item_segment.as_ref())
                .is_none_or(|segment| !segment.is_final_segment)
            || hex(&hasher.finalize()) != manifest.health_data_sha256.as_deref().unwrap_or_default()
        {
            return Err(invalid("logical day digest is incomplete"));
        }
        logical_day
            .as_file_mut()
            .seek(io::SeekFrom::Start(0))
            .map_err(storage_error)?;
        let mut deserializer =
            serde_json::Deserializer::from_reader(BufReader::new(logical_day.as_file_mut()));
        let identity = HealthDataIdentity::deserialize(&mut deserializer)
            .map_err(|_| invalid("logical day is not a healthmd.health_data document"))?;
        deserializer
            .end()
            .map_err(|_| invalid("logical day has trailing JSON"))?;
        if identity.schema != "healthmd.health_data"
            || !matches!(identity.schema_version, 7 | 8)
            || identity.date != manifest.date
        {
            return Err(invalid("logical day identity does not match its manifest"));
        }
        if source_schema_version.is_some_and(|version| version != identity.schema_version) {
            return Err(invalid(
                "logical days use mixed health data schema versions",
            ));
        }
        source_schema_version = Some(identity.schema_version);
        let expects_archive = journal.request.raw_profile
            == Some(RawProfile::CanonicalSourceRecordsV1)
            || journal
                .accepted
                .resolved_canonical_selection
                .as_ref()
                .is_some_and(|selection| {
                    selection.detail_level == healthmd_protocol::models::DetailLevel::Lossless
                });
        match (expects_archive, identity.healthkit_record_archive) {
            (true, Some(archive))
                if archive.schema == "healthmd.healthkit_records"
                    && archive.schema_version == 1 => {}
            (true, _) => {
                return Err(invalid(
                    "logical day is missing its canonical record archive",
                ));
            }
            (false, None) => {}
            (false, Some(_)) => {
                return Err(invalid(
                    "logical day contains an unrequested record archive",
                ));
            }
        }
        // A direct export request is immutable, so every retained daily document in one corpus
        // must use the same source schema version. Reject mixed corpora rather than publishing an
        // ambiguous protocol-v1 scalar or pretending either version describes the whole job.
        if source_versions
            .values()
            .next()
            .is_some_and(|version| *version != identity.schema_version)
        {
            return Err(invalid("corpus mixes source schema versions"));
        }
        source_versions.insert(manifest.date.clone(), identity.schema_version);
    }
    Ok(source_versions)
}

struct BoundedWriter<W> {
    inner: W,
    written: u64,
    maximum: u64,
}

impl<W> BoundedWriter<W> {
    const fn new(inner: W, maximum: u64) -> Self {
        Self {
            inner,
            written: 0,
            maximum,
        }
    }

    const fn get_ref(&self) -> &W {
        &self.inner
    }

    fn into_inner(self) -> W {
        self.inner
    }
}

impl<W: io::Write> io::Write for BoundedWriter<W> {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        let count = u64::try_from(buffer.len()).unwrap_or(u64::MAX);
        if self
            .written
            .checked_add(count)
            .is_none_or(|total| total > self.maximum)
        {
            return Err(io::Error::other("bounded direct output exceeded its limit"));
        }
        let written = self.inner.write(buffer)?;
        self.written = self
            .written
            .checked_add(u64::try_from(written).unwrap_or(u64::MAX))
            .ok_or_else(|| io::Error::other("bounded direct output byte total overflow"))?;
        Ok(written)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.inner.flush()
    }
}

struct HashWriter<'a>(&'a mut Sha256);

impl io::Write for HashWriter<'_> {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.0.update(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

struct ExtractionEnvelopeSeed<'a, W> {
    output: &'a mut W,
    receipt: &'a mut Option<Box<RawValue>>,
}

impl<'de, W: io::Write> DeserializeSeed<'de> for ExtractionEnvelopeSeed<'_, W> {
    type Value = ();

    fn deserialize<D: serde::Deserializer<'de>>(self, deserializer: D) -> Result<(), D::Error> {
        deserializer.deserialize_map(ExtractionEnvelopeVisitor {
            output: self.output,
            receipt: self.receipt,
        })
    }
}

struct ExtractionEnvelopeVisitor<'a, W> {
    output: &'a mut W,
    receipt: &'a mut Option<Box<RawValue>>,
}

impl<'de, W: io::Write> Visitor<'de> for ExtractionEnvelopeVisitor<'_, W> {
    type Value = ();

    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("a canonical extraction result object")
    }

    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
        let mut saw_data = false;
        while let Some(key) = map.next_key::<String>()? {
            match key.as_str() {
                "health_data" | "projections" if !saw_data => {
                    saw_data = true;
                    map.next_value_seed(JsonlArraySeed {
                        output: self.output,
                    })?;
                }
                "health_data" | "projections" => {
                    return Err(A::Error::custom("duplicate extraction data array"));
                }
                "receipt" if self.receipt.is_none() => {
                    *self.receipt = Some(map.next_value::<Box<RawValue>>()?);
                }
                "receipt" => return Err(A::Error::custom("duplicate extraction receipt")),
                _ => {
                    map.next_value::<IgnoredAny>()?;
                }
            }
        }
        if !saw_data || self.receipt.is_none() {
            return Err(A::Error::custom("extraction data or receipt is missing"));
        }
        Ok(())
    }
}

struct JsonlArraySeed<'a, W> {
    output: &'a mut W,
}

impl<'de, W: io::Write> DeserializeSeed<'de> for JsonlArraySeed<'_, W> {
    type Value = ();

    fn deserialize<D: serde::Deserializer<'de>>(self, deserializer: D) -> Result<(), D::Error> {
        deserializer.deserialize_seq(JsonlArrayVisitor {
            output: self.output,
        })
    }
}

struct JsonlArrayVisitor<'a, W> {
    output: &'a mut W,
}

impl<'de, W: io::Write> Visitor<'de> for JsonlArrayVisitor<'_, W> {
    type Value = ();

    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("an extraction data array")
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut sequence: A) -> Result<(), A::Error> {
        while let Some(raw) = sequence.next_element::<Box<RawValue>>()? {
            let value: Value = serde_json::from_str(raw.get()).map_err(A::Error::custom)?;
            serde_json::to_writer(&mut *self.output, &value).map_err(A::Error::custom)?;
            self.output.write_all(b"\n").map_err(A::Error::custom)?;
        }
        Ok(())
    }
}

fn extraction_to_jsonl(
    layout: &StorageLayout,
    source: &Path,
) -> Result<(PathBuf, PathBuf), ClientError> {
    let directory = source
        .parent()
        .ok_or_else(|| invalid("extraction path has no parent"))?;
    let source_bytes = fs::metadata(source).map_err(storage_error)?.len();
    let output_budget = source_bytes
        .checked_add(MAXIMUM_DURABLE_JSON_BYTES)
        .ok_or_else(|| invalid("JSONL output byte budget overflow"))?;
    ensure_job_bytes(output_budget)?;
    let _storage_reservation =
        reserve_materialization_storage(&layout.root, directory, output_budget)?;
    let output = NamedTempFile::new_in(directory).map_err(storage_error)?;
    let receipt_output = NamedTempFile::new_in(directory).map_err(storage_error)?;
    set_private_file(output.as_file())?;
    set_private_file(receipt_output.as_file())?;
    let mut output = BoundedWriter::new(output, output_budget);
    let mut receipt_output = BoundedWriter::new(receipt_output, MAXIMUM_DURABLE_JSON_BYTES);
    let input = File::open(source).map_err(storage_error)?;
    let mut deserializer = serde_json::Deserializer::from_reader(BufReader::new(input));
    let mut receipt = None;
    ExtractionEnvelopeSeed {
        output: &mut output,
        receipt: &mut receipt,
    }
    .deserialize(&mut deserializer)
    .map_err(|_| invalid("canonical extraction could not be converted to JSONL"))?;
    deserializer
        .end()
        .map_err(|_| invalid("canonical extraction has trailing JSON"))?;
    let receipt = receipt.ok_or_else(|| invalid("canonical extraction receipt is missing"))?;
    receipt_output
        .write_all(receipt.get().as_bytes())
        .and_then(|()| receipt_output.write_all(b"\n"))
        .map_err(storage_error)?;
    output
        .get_ref()
        .as_file()
        .sync_all()
        .map_err(storage_error)?;
    receipt_output
        .get_ref()
        .as_file()
        .sync_all()
        .map_err(storage_error)?;
    let output_path = directory.join("extraction.jsonl");
    let receipt_path = directory.join("extraction.receipt.json");
    output
        .into_inner()
        .persist(&output_path)
        .map_err(|error| storage_error(error.error))?;
    receipt_output
        .into_inner()
        .persist(&receipt_path)
        .map_err(|error| storage_error(error.error))?;
    sync_directory(directory).map_err(storage_error)?;
    Ok((output_path, receipt_path))
}

fn validated_source_schema_version(
    layout: &StorageLayout,
    journal: &RawJournal,
    manifests: &[&RawDayManifest],
) -> Result<i64, ClientError> {
    let mut version = None;
    for manifest in manifests {
        if manifest.health_data_byte_count == 0 {
            continue;
        }
        let day = read_day(layout, journal, &manifest.date)?;
        let identity: HealthDataIdentity =
            serde_json::from_slice(&day).map_err(|_| invalid("canonical day is invalid JSON"))?;
        if identity.schema != "healthmd.health_data" || !matches!(identity.schema_version, 7 | 8) {
            return Err(invalid("canonical day schema version is unsupported"));
        }
        if version.is_some_and(|value| value != identity.schema_version) {
            return Err(invalid(
                "logical days use mixed health data schema versions",
            ));
        }
        version = Some(identity.schema_version);
    }
    // An all-missing extraction contains no daily document from which to derive
    // a version. Current Apple peers advertise v8; retained documents never use
    // this fallback because their exact version is read above.
    Ok(version.unwrap_or(8))
}

#[allow(clippy::too_many_lines)]
fn assemble_extraction(
    layout: &StorageLayout,
    journal: &RawJournal,
    pointers: &[String],
    source_versions: &BTreeMap<String, i64>,
) -> Result<RawReceiveArtifact, ClientError> {
    if journal.request.raw_profile != Some(RawProfile::HealthDataProjection) {
        return Err(invalid("job is not a canonical projection"));
    }
    if pointers.len() > MAXIMUM_FIELD_POINTERS {
        return Err(invalid("too many canonical JSON pointers"));
    }
    for pointer in pointers {
        validate_pointer(pointer)?;
    }
    let dates = &journal.accepted.resolved_date_identifiers;
    let manifests: Vec<_> = dates
        .iter()
        .map(|date| journal.manifests.get(date).expect("corpus was validated"))
        .collect();
    let status = response_status(journal);
    let source_schema_version = validated_source_schema_version(layout, journal, &manifests)?;
    let directory = layout
        .response_spools_dir()
        .join(journal.request.job_id.0.to_string().to_lowercase());
    create_private_directory(&directory)?;
    remove_if_present(&directory.join("extraction.json"))?;
    remove_if_present(&directory.join("extraction.receipt.json"))?;
    let output_budget = corpus_output_budget(journal)?;
    let _storage_reservation =
        reserve_materialization_storage(&layout.root, &directory, output_budget)?;
    let output = NamedTempFile::new_in(&directory).map_err(storage_error)?;
    set_private_file(output.as_file())?;
    let mut output = BoundedWriter::new(output, output_budget);
    let data_key = if pointers.is_empty() {
        "health_data"
    } else {
        "projections"
    };
    write!(
        output,
        "{{\"protocol\":\"healthmd.extract_result\",\"protocol_version\":1,\"{data_key}\":["
    )
    .map_err(storage_error)?;
    let mut emitted = 0_usize;
    for manifest in &manifests {
        if manifest.health_data_byte_count == 0 {
            continue;
        }
        if emitted > 0 {
            output.write_all(b",").map_err(storage_error)?;
        }
        if pointers.is_empty() {
            copy_day(layout, journal, &manifest.date, &mut output)?;
        } else {
            if manifest.health_data_byte_count > 64 * 1_024 * 1_024 {
                return Err(invalid(
                    "one canonical day exceeds the 64 MiB field-projection bound",
                ));
            }
            let day = read_day(layout, journal, &manifest.date)?;
            let source: Value = serde_json::from_slice(&day)
                .map_err(|_| invalid("canonical day is invalid JSON"))?;
            let complete = matches!(
                manifest.status.as_str(),
                "complete" | "complete_empty" | "complete_with_warnings"
            );
            let mut selections = Vec::with_capacity(pointers.len());
            let mut selection_bytes = 0_u64;
            for pointer in pointers {
                let selection = source.pointer(pointer).map_or_else(
                    || {
                        json!({
                            "pointer": pointer,
                            "status": if complete { "complete_empty" } else { manifest.status.as_str() }
                        })
                    },
                    |value| json!({ "pointer": pointer, "status": "available", "value": value }),
                );
                let encoded = canonical_json(&selection)
                    .map_err(|_| invalid("projection selection encoding failed"))?;
                selection_bytes = selection_bytes
                    .checked_add(u64::try_from(encoded.len()).unwrap_or(u64::MAX))
                    .ok_or_else(|| invalid("projection selection byte total overflow"))?;
                if selection_bytes > MAXIMUM_DURABLE_JSON_BYTES {
                    return Err(invalid("one canonical projection exceeds 64 MiB"));
                }
                selections.push(selection);
            }
            let source_version = source_versions
                .get(&manifest.date)
                .ok_or_else(|| invalid("validated source version is missing"))?;
            if source.get("schema_version").and_then(Value::as_i64) != Some(*source_version) {
                return Err(invalid("validated source version changed"));
            }
            let projection = json!({
                "source": {
                    "schema": source["schema"],
                    "schema_version": source_version,
                    "date": source["date"],
                    "raw_capture_status": source.get("raw_capture_status").cloned().unwrap_or(Value::Null)
                },
                "selections": selections
            });
            output
                .write_all(
                    &canonical_json(&projection)
                        .map_err(|_| invalid("projection JSON encoding failed"))?,
                )
                .map_err(storage_error)?;
        }
        emitted += 1;
    }

    let selection = journal
        .accepted
        .resolved_canonical_selection
        .as_ref()
        .ok_or_else(|| invalid("resolved canonical selection is missing"))?;
    let receipt_days: Vec<_> = manifests
        .iter()
        .map(|manifest| {
            let mut day = Map::new();
            day.insert(
                "health_data_retained".into(),
                json!(manifest.health_data_byte_count > 0),
            );
            day.insert("date".into(), json!(manifest.date));
            day.insert("status".into(), json!(manifest.status));
            if let Some(source_version) = source_versions.get(&manifest.date) {
                day.insert("source_schema".into(), json!("healthmd.health_data"));
                day.insert("source_schema_version".into(), json!(source_version));
            }
            if let Some(value) = &manifest.failure_code {
                day.insert("failure_code".into(), json!(value));
            }
            day.insert("sample_count".into(), json!(manifest.sample_count));
            day.insert("record_count".into(), json!(manifest.record_count));
            if !manifest.query_status_counts.is_empty() {
                day.insert(
                    "query_status_counts".into(),
                    json!(manifest.query_status_counts),
                );
            }
            day.insert(
                "integrity_warning_count".into(),
                json!(manifest.integrity_warning_count),
            );
            if !manifest.integrity_warning_codes.is_empty() {
                day.insert(
                    "integrity_warning_codes".into(),
                    json!(manifest.integrity_warning_codes),
                );
            }
            day.insert(
                "partial_failure_count".into(),
                json!(manifest.partial_failure_count),
            );
            if !manifest.partial_failure_types.is_empty() {
                day.insert(
                    "partial_failure_types".into(),
                    json!(manifest.partial_failure_types),
                );
            }
            Value::Object(day)
        })
        .collect();
    let missing: Vec<_> = manifests
        .iter()
        .filter(|manifest| manifest.status == "missing")
        .map(|manifest| manifest.date.clone())
        .collect();
    let summary = capture_summary(&manifests)?;
    let distinct_source_versions: BTreeSet<_> = source_versions.values().copied().collect();
    // Protocol-v1 receipts historically always exposed the scalar v7 source version. Empty day
    // manifests contain no source document identity, so preserve that backward-compatible scalar
    // for an all-empty corpus while the plural field explicitly records that no version was
    // evidenced. A non-empty homogeneous corpus uses its validated source version.
    let source_schema_version = distinct_source_versions.first().copied().unwrap_or(7);
    let receipt = json!({
        "protocol": "healthmd.extract_receipt",
        "protocol_version": 1,
        "status": status,
        "source_schema": "healthmd.health_data",
        "source_schema_version": source_schema_version,
        "source_schema_versions": distinct_source_versions,
        "selection": {
            "metric_ids": selection.metric_ids,
            "source_ids": selection.source_ids,
            "detail_level": match selection.detail_level {
                healthmd_protocol::models::DetailLevel::Summary => "summary",
                healthmd_protocol::models::DetailLevel::Lossless => "lossless",
            },
            "object_paths": selection.object_paths,
            "field_pointers": selection.field_pointers
        },
        "days": receipt_days,
        "missing_dates": missing,
        "capture_summary": summary,
        "date_range": {
            "start": dates.first().cloned().unwrap_or_default(),
            "end": dates.last().cloned().unwrap_or_default()
        },
        "total_requested_days": dates.len()
    });
    output.write_all(b"],\"receipt\":").map_err(storage_error)?;
    output
        .write_all(&canonical_json(&receipt).map_err(|_| invalid("receipt JSON failed"))?)
        .map_err(storage_error)?;
    output.write_all(b"}\n").map_err(storage_error)?;
    output
        .get_ref()
        .as_file()
        .sync_all()
        .map_err(storage_error)?;
    let destination = directory.join("extraction.json");
    output
        .into_inner()
        .persist(&destination)
        .map_err(|error| storage_error(error.error))?;
    sync_directory(&directory).map_err(storage_error)?;
    validate_json_file(&destination)?;
    let (byte_count, digest) = inspect_file(&destination)?;
    Ok(RawReceiveArtifact {
        path: destination,
        status,
        sha256: digest,
        byte_count,
        date_range_start: dates.first().cloned().unwrap_or_default(),
        date_range_end: dates.last().cloned().unwrap_or_default(),
        total_days: i64::try_from(dates.len()).map_err(|_| invalid("too many dates"))?,
        profile: RawProfile::HealthDataProjection,
    })
}

fn copy_day(
    layout: &StorageLayout,
    journal: &RawJournal,
    date: &str,
    output: &mut impl io::Write,
) -> Result<(), ClientError> {
    for descriptor in journal.committed_partitions.iter().filter(|partition| {
        partition
            .item_segment
            .as_ref()
            .map(|segment| segment.item_id.as_str())
            == Some(date)
    }) {
        let mut input = File::open(partition_path(
            layout,
            journal.request.job_id.0,
            descriptor.index,
        )?)
        .map_err(storage_error)?;
        io::copy(&mut input, output).map_err(storage_error)?;
    }
    Ok(())
}

fn read_day(
    layout: &StorageLayout,
    journal: &RawJournal,
    date: &str,
) -> Result<Vec<u8>, ClientError> {
    let manifest = journal
        .manifests
        .get(date)
        .ok_or_else(|| invalid("day manifest is missing"))?;
    let capacity = usize::try_from(manifest.health_data_byte_count)
        .map_err(|_| invalid("daily document is too large"))?;
    let mut bytes = Vec::with_capacity(capacity);
    copy_day(layout, journal, date, &mut bytes)?;
    if bytes.len() != capacity {
        return Err(invalid("daily document is incomplete"));
    }
    Ok(bytes)
}

fn validate_pointer(pointer: &str) -> Result<(), ClientError> {
    if pointer.is_empty()
        || !pointer.starts_with('/')
        || pointer.len() > 1_024
        || pointer.bytes().any(|byte| byte.is_ascii_control())
    {
        return Err(invalid("canonical JSON pointer is invalid"));
    }
    let mut bytes = pointer.bytes();
    while let Some(byte) = bytes.next() {
        if byte == b'~' && !matches!(bytes.next(), Some(b'0' | b'1')) {
            return Err(invalid("canonical JSON pointer escape is invalid"));
        }
    }
    Ok(())
}

fn corpus_output_budget(journal: &RawJournal) -> Result<u64, ClientError> {
    let corpus_bytes = journal
        .manifests
        .values()
        .try_fold(0_u64, |total, manifest| {
            total
                .checked_add(
                    u64::try_from(manifest.health_data_byte_count)
                        .map_err(|_| invalid("raw manifest byte count is invalid"))?,
                )
                .ok_or_else(|| invalid("raw corpus byte total overflow"))
        })?;
    let budget = corpus_bytes
        .checked_add(MAXIMUM_DURABLE_JSON_BYTES)
        .ok_or_else(|| invalid("raw output byte budget overflow"))?;
    ensure_job_bytes(budget)?;
    Ok(budget)
}

fn response_status(journal: &RawJournal) -> String {
    if journal.manifests.values().any(|manifest| {
        matches!(
            manifest.status.as_str(),
            "partial" | "failed" | "cancelled" | "missing"
        )
    }) {
        "partial_success".into()
    } else {
        "success".into()
    }
}

#[allow(clippy::too_many_lines)]
fn assemble_response(
    layout: &StorageLayout,
    journal: &RawJournal,
) -> Result<RawReceiveArtifact, ClientError> {
    let profile = journal
        .request
        .raw_profile
        .ok_or_else(|| invalid("raw profile is missing"))?;
    let dates = &journal.accepted.resolved_date_identifiers;
    let manifests: Vec<_> = dates
        .iter()
        .map(|date| journal.manifests.get(date).expect("corpus was validated"))
        .collect();
    let response_status = response_status(journal);
    let directory = layout
        .response_spools_dir()
        .join(journal.request.job_id.0.to_string().to_lowercase());
    create_private_directory(&directory)?;
    let destination = directory.join("response.json");
    remove_if_present(&destination)?;
    let output_budget = corpus_output_budget(journal)?;
    let _storage_reservation =
        reserve_materialization_storage(&layout.root, &directory, output_budget)?;
    let output = NamedTempFile::new_in(&directory).map_err(storage_error)?;
    set_private_file(output.as_file())?;
    let mut output = BoundedWriter::new(output, output_budget);

    write!(
        output,
        "{{\"job_id\":{},\"message\":{},\"status\":{},\"raw_result\":{{",
        json_string(&journal.request.job_id.0.to_string().to_lowercase())?,
        json_string("iPhone direct raw export completed.")?,
        json_string(&response_status)?
    )
    .map_err(storage_error)?;
    write!(
        output,
        "\"schema\":\"healthmd.raw_result\",\"schema_version\":1,\"profile\":{}",
        json_string(raw_profile_name(profile))?
    )
    .map_err(storage_error)?;
    if let Some(selection) = &journal.accepted.resolved_canonical_selection {
        write!(
            output,
            ",\"canonical_selection\":{}",
            canonical_selection_json(selection)?
        )
        .map_err(storage_error)?;
    }
    let created = journal
        .request
        .created_at
        .to_rfc3339_opts(SecondsFormat::Millis, true);
    write!(output, ",\"created_at\":{},\"source_device_name\":{},\"date_range\":{{\"start\":{},\"end\":{}}},\"total_requested_days\":{},\"days\":[",
        json_string(&created)?,
        json_string(&journal.accepted.source_device_name)?,
        json_string(dates.first().map_or("", String::as_str))?,
        json_string(dates.last().map_or("", String::as_str))?,
        dates.len()
    ).map_err(storage_error)?;

    for (day_index, manifest) in manifests.iter().enumerate() {
        if day_index > 0 {
            output.write_all(b",").map_err(storage_error)?;
        }
        let mut day = day_value(manifest);
        let Value::Object(ref mut object) = day else {
            unreachable!()
        };
        let health_data = manifest.health_data_byte_count > 0;
        if health_data {
            object.insert("health_data".into(), Value::Null);
        }
        let mut encoded = canonical_json(&day).map_err(|_| invalid("day JSON failed"))?;
        if health_data {
            let marker = b"\"health_data\":null";
            let position = find_subslice(&encoded, marker)
                .ok_or_else(|| invalid("health-data insertion point is missing"))?;
            output
                .write_all(&encoded[..position])
                .map_err(storage_error)?;
            output
                .write_all(b"\"health_data\":")
                .map_err(storage_error)?;
            let descriptors = journal.committed_partitions.iter().filter(|partition| {
                partition
                    .item_segment
                    .as_ref()
                    .map(|segment| &segment.item_id)
                    == Some(&manifest.date)
            });
            for descriptor in descriptors {
                let mut input = File::open(partition_path(
                    layout,
                    journal.request.job_id.0,
                    descriptor.index,
                )?)
                .map_err(storage_error)?;
                io::copy(&mut input, &mut output).map_err(storage_error)?;
            }
            output
                .write_all(&encoded[position + marker.len()..])
                .map_err(storage_error)?;
        } else {
            output.write_all(&encoded).map_err(storage_error)?;
        }
        encoded.clear();
    }

    let missing: Vec<_> = manifests
        .iter()
        .filter(|manifest| manifest.status == "missing")
        .map(|manifest| manifest.date.clone())
        .collect();
    write!(
        output,
        "],\"capture_summary\":{},\"missing_dates\":{}}}}}",
        canonical_json(&capture_summary(&manifests)?)
            .map_err(|_| invalid("summary JSON failed"))?
            .iter()
            .map(|byte| char::from(*byte))
            .collect::<String>(),
        canonical_json(&missing)
            .map_err(|_| invalid("missing-date JSON failed"))?
            .iter()
            .map(|byte| char::from(*byte))
            .collect::<String>()
    )
    .map_err(storage_error)?;
    output
        .get_ref()
        .as_file()
        .sync_all()
        .map_err(storage_error)?;
    output
        .into_inner()
        .persist(&destination)
        .map_err(|error| storage_error(error.error))?;
    sync_directory(&directory).map_err(storage_error)?;
    validate_json_file(&destination)?;
    let (byte_count, digest) = inspect_file(&destination)?;
    Ok(RawReceiveArtifact {
        path: destination,
        status: response_status,
        sha256: digest,
        byte_count,
        date_range_start: dates.first().cloned().unwrap_or_default(),
        date_range_end: dates.last().cloned().unwrap_or_default(),
        total_days: i64::try_from(dates.len()).map_err(|_| invalid("too many dates"))?,
        profile,
    })
}

fn day_value(manifest: &RawDayManifest) -> Value {
    let mut object = Map::new();
    object.insert("date".into(), json!(manifest.date));
    object.insert("status".into(), json!(manifest.status));
    if let Some(value) = &manifest.capture_status {
        object.insert("capture_status".into(), json!(value));
    }
    object.insert("sample_count".into(), json!(manifest.sample_count));
    object.insert("record_count".into(), json!(manifest.record_count));
    object.insert(
        "query_status_counts".into(),
        json!(manifest.query_status_counts),
    );
    object.insert(
        "integrity_warning_count".into(),
        json!(manifest.integrity_warning_count),
    );
    object.insert(
        "integrity_warning_codes".into(),
        json!(manifest.integrity_warning_codes),
    );
    object.insert(
        "partial_failure_count".into(),
        json!(manifest.partial_failure_count),
    );
    object.insert(
        "partial_failure_types".into(),
        json!(manifest.partial_failure_types),
    );
    if let Some(value) = &manifest.failure_code {
        object.insert("failure_code".into(), json!(value));
    }
    Value::Object(object)
}

fn capture_summary(manifests: &[&RawDayManifest]) -> Result<Value, ClientError> {
    let mut status_counts: BTreeMap<&str, i64> = BTreeMap::new();
    let mut query_counts: BTreeMap<String, i64> =
        ["success", "failure", "unsupported", "skipped", "cancelled"]
            .into_iter()
            .map(|key| (key.into(), 0))
            .collect();
    let mut samples = 0_i64;
    let mut records = 0_i64;
    let mut warnings = 0_i64;
    let mut partial_failures = 0_i64;
    for manifest in manifests {
        let status = status_counts.entry(&manifest.status).or_default();
        *status = status
            .checked_add(1)
            .ok_or_else(|| invalid("capture summary count overflow"))?;
        samples = samples
            .checked_add(manifest.sample_count)
            .ok_or_else(|| invalid("sample count overflow"))?;
        records = records
            .checked_add(manifest.record_count)
            .ok_or_else(|| invalid("record count overflow"))?;
        warnings = warnings
            .checked_add(manifest.integrity_warning_count)
            .ok_or_else(|| invalid("warning count overflow"))?;
        partial_failures = partial_failures
            .checked_add(manifest.partial_failure_count)
            .ok_or_else(|| invalid("partial failure count overflow"))?;
        for (key, count) in &manifest.query_status_counts {
            let aggregate = query_counts.entry(key.clone()).or_default();
            *aggregate = aggregate
                .checked_add(*count)
                .ok_or_else(|| invalid("query status count overflow"))?;
        }
    }
    Ok(json!({
        "retained_day_count": manifests.iter().filter(|manifest| manifest.health_data_byte_count > 0).count(),
        "complete_day_count": status_counts.get("complete").copied().unwrap_or(0),
        "complete_empty_day_count": status_counts.get("complete_empty").copied().unwrap_or(0),
        "warning_day_count": status_counts.get("complete_with_warnings").copied().unwrap_or(0),
        "partial_day_count": status_counts.get("partial").copied().unwrap_or(0),
        "failed_day_count": status_counts.get("failed").copied().unwrap_or(0),
        "cancelled_day_count": status_counts.get("cancelled").copied().unwrap_or(0),
        "missing_day_count": status_counts.get("missing").copied().unwrap_or(0),
        "sample_count": samples,
        "record_count": records,
        "query_status_counts": query_counts,
        "integrity_warning_count": warnings,
        "partial_failure_count": partial_failures,
        "day_status_counts": status_counts
    }))
}

fn canonical_selection_json(selection: &CanonicalSelection) -> Result<String, ClientError> {
    let value = json!({
        "metric_ids": selection.metric_ids,
        "source_ids": selection.source_ids,
        "detail_level": match selection.detail_level {
            healthmd_protocol::models::DetailLevel::Summary => "summary",
            healthmd_protocol::models::DetailLevel::Lossless => "lossless",
        },
        "object_paths": selection.object_paths,
        "field_pointers": selection.field_pointers
    });
    String::from_utf8(canonical_json(&value).map_err(|_| invalid("selection JSON failed"))?)
        .map_err(|_| invalid("selection JSON is not UTF-8"))
}

fn raw_profile_name(profile: RawProfile) -> &'static str {
    match profile {
        RawProfile::CanonicalSourceRecordsV1 => "canonical_source_records_v1",
        RawProfile::HealthDataProjection => "health_data_projection",
    }
}

fn json_string(value: &str) -> Result<String, ClientError> {
    serde_json::to_string(value).map_err(|_| invalid("JSON string encoding failed"))
}

fn completed_day_count(journal: &RawJournal) -> Result<i64, ClientError> {
    let completed: BTreeSet<_> = journal
        .committed_partitions
        .iter()
        .filter_map(|partition| {
            partition
                .item_segment
                .as_ref()
                .filter(|segment| segment.is_final_segment)
                .map(|segment| segment.item_id.clone())
        })
        .chain(
            journal
                .manifests
                .values()
                .filter(|manifest| manifest.health_data_byte_count == 0)
                .map(|manifest| manifest.date.clone()),
        )
        .collect();
    i64::try_from(completed.len()).map_err(|_| invalid("too many completed dates"))
}

fn load_journal(path: &Path) -> Result<RawJournal, ClientError> {
    serde_json::from_slice(&read_bounded(
        path,
        MAXIMUM_DURABLE_JSON_BYTES,
        "raw journal exceeds the durable metadata limit",
    )?)
    .map_err(|_| invalid("raw journal is malformed"))
}

fn save_journal(layout: &StorageLayout, journal: &RawJournal) -> Result<(), ClientError> {
    let directory = layout
        .corpus_sessions_dir()
        .join(journal.request.job_id.0.to_string().to_lowercase());
    create_private_directory(&directory)?;
    save_json(&layout.root, &directory.join("journal.json"), journal)
}

fn save_json<T: Serialize>(storage_root: &Path, path: &Path, value: &T) -> Result<(), ClientError> {
    let bytes = canonical_json(value).map_err(|_| invalid("durable JSON encoding failed"))?;
    let byte_count = u64::try_from(bytes.len()).unwrap_or(u64::MAX);
    if byte_count > MAXIMUM_DURABLE_JSON_BYTES {
        return Err(invalid("durable JSON exceeds the metadata limit"));
    }
    let directory = path
        .parent()
        .ok_or_else(|| invalid("durable path has no parent"))?;
    create_private_directory(directory)?;
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

fn validate_json_file(path: &Path) -> Result<(), ClientError> {
    let input = File::open(path).map_err(storage_error)?;
    let mut deserializer = serde_json::Deserializer::from_reader(BufReader::new(input));
    IgnoredAny::deserialize(&mut deserializer)
        .map_err(|_| invalid("assembled raw response is not valid JSON"))?;
    deserializer
        .end()
        .map_err(|_| invalid("assembled raw response has trailing JSON"))
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
    let mut file = File::open(path).map_err(storage_error)?;
    let mut hasher = Sha256::new();
    let bytes = io::copy(&mut file, &mut HashWriter(&mut hasher)).map_err(storage_error)?;
    Ok((
        i64::try_from(bytes).map_err(|_| invalid("file is too large"))?,
        hex(&hasher.finalize()),
    ))
}

fn partition_path(
    layout: &StorageLayout,
    job_id: Uuid,
    index: i64,
) -> Result<PathBuf, ClientError> {
    if index < 0 {
        return Err(invalid("negative partition index"));
    }
    let directory = layout
        .corpus_sessions_dir()
        .join(job_id.to_string().to_lowercase());
    create_private_directory(&directory)?;
    Ok(directory.join(format!("partition-{index:08}.bin")))
}

fn create_private_directory(path: &Path) -> Result<(), ClientError> {
    prepare_private_directory(path)
}

fn private_file(path: &Path, append: bool) -> Result<File, ClientError> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).append(append);
    if !append {
        options.truncate(true);
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    options.open(path).map_err(storage_error)
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

#[cfg(unix)]
fn sync_directory(path: &Path) -> io::Result<()> {
    File::open(path)?.sync_all()
}

#[cfg(windows)]
#[allow(clippy::unnecessary_wraps)]
fn sync_directory(_path: &Path) -> io::Result<()> {
    Ok(())
}

fn is_source_date(value: &str) -> bool {
    value.len() == 10 && chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d").is_ok()
}

fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
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

#[allow(clippy::needless_pass_by_value)]
fn storage_error(error: io::Error) -> ClientError {
    ClientError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use chrono::Timelike as _;
    use healthmd_protocol::{
        encoding::SwiftUuid,
        models::{
            CanonicalSelection, DateSelection, DetailLevel, ExactDateSelection, ExportAccepted,
            PeerBinding, SettingsPolicy, TransferItemSegment,
        },
    };
    use tempfile::TempDir;

    use super::*;
    use crate::job::{JobRecord, JobStore};

    #[test]
    fn bounded_output_and_peer_metadata_fail_closed() {
        let mut output = BoundedWriter::new(Vec::new(), 4);
        output.write_all(b"1234").unwrap();
        assert!(output.write_all(b"5").is_err());
        assert!(safe_peer_metadata("iPhone", 128));
        assert!(!safe_peer_metadata("private\nvalue", 128));
        assert!(valid_time_zone("America/Los_Angeles"));
        assert!(!valid_time_zone("private health value"));
        assert!(is_safe_machine_code("permission_required"));
        assert!(!is_safe_machine_code("PRIVATE VALUE"));
    }

    struct TestCorpus {
        _temporary: TempDir,
        receiver: RawReceiver,
        job_id: Uuid,
    }

    #[allow(clippy::too_many_lines)]
    fn test_corpus(source_schema_versions: &[Option<i64>]) -> TestCorpus {
        let dates = ["2026-07-23", "2026-07-24"];
        assert!(!source_schema_versions.is_empty() && source_schema_versions.len() <= dates.len());
        let dates: Vec<String> = dates[..source_schema_versions.len()]
            .iter()
            .map(ToString::to_string)
            .collect();
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let jobs = JobStore::new(layout.clone()).unwrap();
        let created_at = Utc::now().with_nanosecond(0).unwrap();
        let job_id = SwiftUuid(Uuid::new_v4());
        let selection = CanonicalSelection {
            metric_ids: vec!["sleep_total".into()],
            categories: vec!["Sleep".into()],
            source_ids: vec!["apple_health".into()],
            object_paths: Vec::new(),
            field_pointers: Vec::new(),
            all_metrics: false,
            detail_level: DetailLevel::Summary,
        };
        let request = ExportRequest {
            protocol_version: 1,
            job_id,
            created_at,
            date_selection: DateSelection::Exact(ExactDateSelection {
                start: dates.first().unwrap().clone(),
                end: dates.last().unwrap().clone(),
            }),
            settings_policy: SettingsPolicy::RequestedDatesOnly,
            profile_reference: None,
            response_mode: ResponseMode::RawJson,
            raw_profile: Some(RawProfile::HealthDataProjection),
            canonical_selection: Some(selection.clone()),
            destination: None,
        };
        jobs.save(&JobRecord::new(request.clone())).unwrap();
        let binding = PeerBinding {
            source_installation_id: SwiftUuid(Uuid::new_v4()),
            destination_installation_id: SwiftUuid(Uuid::new_v4()),
        };
        let accepted = ExportAccepted {
            job_id,
            accepted_at: created_at,
            peer_binding: binding.clone(),
            resolved_date_identifiers: dates.clone(),
            source_device_name: "iPhone".into(),
            source_time_zone_identifier: "UTC".into(),
            resolved_canonical_selection: Some(selection),
        };
        let session = TransferSession {
            protocol_version: 1,
            session_id: SwiftUuid(Uuid::new_v4()),
            job_id,
            request_fingerprint: request_fingerprint(&request).unwrap(),
            peer_binding: binding,
            partition_target_bytes: 48 * 1024 * 1024,
            created_at,
        };
        let mut receiver = RawReceiver::new(layout, jobs);
        receiver
            .prepare(request, accepted, session.clone())
            .unwrap();
        let mut previous_sha256 = None;
        let mut partition_index = 0;
        for (date, source_schema_version) in dates.iter().zip(source_schema_versions) {
            let payload = source_schema_version.map(|source_schema_version| {
                serde_json::to_vec_pretty(&json!({
                    "schema": "healthmd.health_data",
                    "schema_version": source_schema_version,
                    "date": date,
                    "raw_capture_status": "complete"
                }))
                .unwrap()
            });
            let payload_digest = payload.as_ref().map(|payload| sha256_hex(payload));
            let status = if payload.is_some() {
                "complete"
            } else {
                "complete_empty"
            };
            receiver
                .store_manifest(RawDayManifest {
                    job_id,
                    date: date.clone(),
                    status: status.into(),
                    capture_status: Some(status.into()),
                    sample_count: 0,
                    record_count: 0,
                    query_status_counts: BTreeMap::new(),
                    integrity_warning_count: 0,
                    integrity_warning_codes: Vec::new(),
                    partial_failure_count: 0,
                    partial_failure_types: Vec::new(),
                    failure_code: None,
                    health_data_byte_count: payload
                        .as_ref()
                        .map_or(0, |payload| i64::try_from(payload.len()).unwrap()),
                    health_data_sha256: payload_digest.clone(),
                })
                .unwrap();
            let Some(payload) = payload else {
                continue;
            };
            let payload_digest = payload_digest.unwrap();
            let transfer_id = SwiftUuid(Uuid::new_v4());
            let partition = TransferPartition {
                index: partition_index,
                transfer_id,
                source_dates: vec![date.clone()],
                byte_count: i64::try_from(payload.len()).unwrap(),
                chunk_count: 1,
                sha256: payload_digest.clone(),
                previous_sha256: previous_sha256.clone(),
                item_segment: Some(TransferItemSegment {
                    item_id: date.clone(),
                    offset: 0,
                    item_byte_count: i64::try_from(payload.len()).unwrap(),
                    is_final_segment: true,
                }),
            };
            receiver
                .disposition(TransferOpen {
                    session: session.clone(),
                    partition,
                })
                .unwrap();
            receiver
                .receive_chunk(TransferChunk {
                    transfer_id,
                    sequence: 1,
                    data: payload,
                    sha256: payload_digest.clone(),
                })
                .unwrap();
            receiver
                .commit_partition(TransferPartitionComplete {
                    session_id: session.session_id,
                    job_id,
                    partition_index,
                    transfer_id,
                    partition_sha256: payload_digest.clone(),
                })
                .unwrap();
            partition_index += 1;
            previous_sha256 = Some(payload_digest);
        }
        TestCorpus {
            _temporary: temporary,
            receiver,
            job_id: job_id.0,
        }
    }

    fn assert_receipt_versions(receipt: &Value, scalar: i64, plural: &[i64]) {
        assert_eq!(receipt["protocol_version"], 1);
        assert_eq!(receipt["source_schema_version"], scalar);
        assert_eq!(receipt["source_schema_versions"], json!(plural));
    }

    #[test]
    fn all_empty_corpus_preserves_v1_scalar_and_records_no_evidenced_versions() {
        let corpus = test_corpus(&[None, None]);
        let json_artifact = corpus.receiver.extraction(corpus.job_id, &[]).unwrap();
        let json: Value = serde_json::from_slice(&fs::read(json_artifact.path).unwrap()).unwrap();
        assert_eq!(json["health_data"], json!([]));
        assert_receipt_versions(&json["receipt"], 7, &[]);
        assert!(
            json["receipt"]["days"]
                .as_array()
                .unwrap()
                .iter()
                .all(|day| day.get("source_schema_version").is_none())
        );

        let jsonl = corpus
            .receiver
            .extraction_jsonl(corpus.job_id, &[])
            .unwrap();
        assert!(fs::read_to_string(jsonl.path).unwrap().is_empty());
        let receipt: Value =
            serde_json::from_slice(&fs::read(jsonl.receipt_path).unwrap()).unwrap();
        assert_receipt_versions(&receipt, 7, &[]);
    }

    #[test]
    fn empty_day_and_retained_v8_day_report_only_the_evidenced_version() {
        let corpus = test_corpus(&[None, Some(8)]);
        let json_artifact = corpus.receiver.extraction(corpus.job_id, &[]).unwrap();
        let json: Value = serde_json::from_slice(&fs::read(json_artifact.path).unwrap()).unwrap();
        assert_eq!(json["health_data"].as_array().unwrap().len(), 1);
        assert_receipt_versions(&json["receipt"], 8, &[8]);
        let days = json["receipt"]["days"].as_array().unwrap();
        assert!(days[0].get("source_schema_version").is_none());
        assert_eq!(days[1]["source_schema_version"], 8);

        let jsonl = corpus
            .receiver
            .extraction_jsonl(corpus.job_id, &[])
            .unwrap();
        assert_eq!(fs::read_to_string(jsonl.path).unwrap().lines().count(), 1);
        let receipt: Value =
            serde_json::from_slice(&fs::read(jsonl.receipt_path).unwrap()).unwrap();
        assert_receipt_versions(&receipt, 8, &[8]);
        let days = receipt["days"].as_array().unwrap();
        assert!(days[0].get("source_schema_version").is_none());
        assert_eq!(days[1]["source_schema_version"], 8);
    }

    #[test]
    fn homogeneous_v7_and_v8_corpora_report_evidenced_versions_in_json_and_jsonl() {
        for source_schema_version in [7, 8] {
            let corpus = test_corpus(&[Some(source_schema_version), Some(source_schema_version)]);
            let json_artifact = corpus.receiver.extraction(corpus.job_id, &[]).unwrap();
            let json: Value =
                serde_json::from_slice(&fs::read(json_artifact.path).unwrap()).unwrap();
            assert_eq!(json["health_data"].as_array().unwrap().len(), 2);
            assert_receipt_versions(
                &json["receipt"],
                source_schema_version,
                &[source_schema_version],
            );

            let jsonl = corpus
                .receiver
                .extraction_jsonl(corpus.job_id, &[])
                .unwrap();
            assert_eq!(fs::read_to_string(jsonl.path).unwrap().lines().count(), 2);
            let receipt: Value =
                serde_json::from_slice(&fs::read(jsonl.receipt_path).unwrap()).unwrap();
            assert_receipt_versions(&receipt, source_schema_version, &[source_schema_version]);
        }
    }

    #[test]
    fn mixed_v7_v8_corpus_is_rejected_for_json_and_jsonl() {
        let corpus = test_corpus(&[Some(7), Some(8)]);
        for error in [
            corpus.receiver.extraction(corpus.job_id, &[]).unwrap_err(),
            corpus
                .receiver
                .extraction_jsonl(corpus.job_id, &[])
                .unwrap_err(),
        ] {
            assert!(matches!(
                error,
                ClientError::InvalidTransfer(message)
                    if message == "corpus mixes source schema versions"
            ));
        }
    }

    #[test]
    fn shipped_apple_daily_schema_versions_survive_raw_and_extract_receipts() {
        assert_one_day_corpus_schema_version(7);
        assert_one_day_corpus_schema_version(8);
    }

    #[allow(clippy::too_many_lines)]
    fn assert_one_day_corpus_schema_version(source_schema_version: i64) {
        let temporary = TempDir::new().unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let jobs = JobStore::new(layout.clone()).unwrap();
        let created_at = Utc::now().with_nanosecond(0).unwrap();
        let job_id = SwiftUuid(Uuid::new_v4());
        let selection = CanonicalSelection {
            metric_ids: vec!["sleep_total".into()],
            categories: vec!["Sleep".into()],
            source_ids: vec!["apple_health".into()],
            object_paths: Vec::new(),
            field_pointers: Vec::new(),
            all_metrics: false,
            detail_level: DetailLevel::Summary,
        };
        let request = ExportRequest {
            protocol_version: 1,
            job_id,
            created_at,
            date_selection: DateSelection::Exact(ExactDateSelection {
                start: "2026-07-23".into(),
                end: "2026-07-23".into(),
            }),
            settings_policy: SettingsPolicy::RequestedDatesOnly,
            profile_reference: None,
            response_mode: ResponseMode::RawJson,
            raw_profile: Some(RawProfile::HealthDataProjection),
            canonical_selection: Some(selection.clone()),
            destination: None,
        };
        jobs.save(&JobRecord::new(request.clone())).unwrap();
        let binding = PeerBinding {
            source_installation_id: SwiftUuid(Uuid::new_v4()),
            destination_installation_id: SwiftUuid(Uuid::new_v4()),
        };
        let accepted = ExportAccepted {
            job_id,
            accepted_at: created_at,
            peer_binding: binding.clone(),
            resolved_date_identifiers: vec!["2026-07-23".into()],
            source_device_name: "iPhone".into(),
            source_time_zone_identifier: "UTC".into(),
            resolved_canonical_selection: Some(selection),
        };
        let fingerprint = request_fingerprint(&request).unwrap();
        let session = TransferSession {
            protocol_version: 1,
            session_id: SwiftUuid(Uuid::new_v4()),
            job_id,
            request_fingerprint: fingerprint.clone(),
            peer_binding: binding,
            partition_target_bytes: 48 * 1024 * 1024,
            created_at,
        };
        let payload = serde_json::to_vec_pretty(&json!({
            "schema": "healthmd.health_data",
            "schema_version": source_schema_version,
            "date": "2026-07-23",
            "raw_capture_status": "complete"
        }))
        .unwrap();
        let payload_digest = sha256_hex(&payload);
        let manifest = RawDayManifest {
            job_id,
            date: "2026-07-23".into(),
            status: "complete".into(),
            capture_status: Some("complete".into()),
            sample_count: 0,
            record_count: 0,
            query_status_counts: BTreeMap::new(),
            integrity_warning_count: 0,
            integrity_warning_codes: Vec::new(),
            partial_failure_count: 0,
            partial_failure_types: Vec::new(),
            failure_code: None,
            health_data_byte_count: i64::try_from(payload.len()).unwrap(),
            health_data_sha256: Some(payload_digest.clone()),
        };
        let transfer_id = SwiftUuid(Uuid::new_v4());
        let partition = TransferPartition {
            index: 0,
            transfer_id,
            source_dates: vec!["2026-07-23".into()],
            byte_count: i64::try_from(payload.len()).unwrap(),
            chunk_count: 1,
            sha256: payload_digest.clone(),
            previous_sha256: None,
            item_segment: Some(TransferItemSegment {
                item_id: "2026-07-23".into(),
                offset: 0,
                item_byte_count: i64::try_from(payload.len()).unwrap(),
                is_final_segment: true,
            }),
        };

        let mut receiver = RawReceiver::new(layout.clone(), jobs.clone());
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
        receiver
            .receive_chunk(TransferChunk {
                transfer_id,
                sequence: 1,
                data: payload.clone(),
                sha256: payload_digest.clone(),
            })
            .unwrap();
        receiver
            .commit_partition(TransferPartitionComplete {
                session_id: session.session_id,
                job_id,
                partition_index: 0,
                transfer_id,
                partition_sha256: payload_digest.clone(),
            })
            .unwrap();
        fs::write(partition_path(&layout, job_id.0, 0).unwrap(), b"corrupt").unwrap();
        let mut resumed = RawReceiver::new(layout, jobs.clone());
        resumed.prepare(request, accepted, session.clone()).unwrap();
        assert_eq!(
            resumed
                .disposition(TransferOpen {
                    session: session.clone(),
                    partition: partition.clone(),
                })
                .unwrap()
                .disposition,
            TransferDispositionKind::Needed
        );
        resumed
            .receive_chunk(TransferChunk {
                transfer_id,
                sequence: 1,
                data: payload,
                sha256: payload_digest.clone(),
            })
            .unwrap();
        resumed
            .commit_partition(TransferPartitionComplete {
                session_id: session.session_id,
                job_id,
                partition_index: 0,
                transfer_id,
                partition_sha256: payload_digest.clone(),
            })
            .unwrap();
        receiver = resumed;
        receiver.journal.as_mut().unwrap().request.raw_profile =
            Some(RawProfile::CanonicalSourceRecordsV1);
        assert!(
            validate_complete_corpus(&receiver.layout, receiver.journal.as_ref().unwrap()).is_err()
        );
        receiver.journal.as_mut().unwrap().request.raw_profile =
            Some(RawProfile::HealthDataProjection);
        assert!(checked_byte_total([i64::MAX, 1]).is_err());
        let artifact = receiver
            .finalize(&TransferFinalize {
                session_id: session.session_id,
                job_id,
                request_fingerprint: fingerprint,
                total_partitions: 1,
                total_bytes: partition.byte_count,
                final_partition_sha256: Some(payload_digest),
                outcome: None,
            })
            .unwrap();
        let response: Value = serde_json::from_slice(&fs::read(&artifact.path).unwrap()).unwrap();
        assert_eq!(response["status"], "success");
        assert_eq!(
            response["raw_result"]["days"][0]["health_data"]["schema"],
            "healthmd.health_data"
        );
        assert_eq!(
            response["raw_result"]["days"][0]["health_data"]["schema_version"],
            source_schema_version
        );
        let extraction = receiver.extraction(job_id.0, &["/schema".into()]).unwrap();
        let extraction: Value =
            serde_json::from_slice(&fs::read(extraction.path).unwrap()).unwrap();
        assert_eq!(extraction["protocol"], "healthmd.extract_result");
        assert_eq!(
            extraction["projections"][0]["selections"][0]["value"],
            "healthmd.health_data"
        );
        assert_eq!(
            extraction["projections"][0]["source"]["schema_version"],
            source_schema_version
        );
        assert_eq!(
            extraction["receipt"]["source_schema_version"],
            source_schema_version
        );
        assert_eq!(
            extraction["receipt"]["source_schema_versions"],
            json!([source_schema_version])
        );
        assert_eq!(
            extraction["receipt"]["days"][0]["source_schema_version"],
            source_schema_version
        );
        let jsonl = receiver
            .extraction_jsonl(job_id.0, &["/schema".into()])
            .unwrap();
        let data = fs::read_to_string(jsonl.path).unwrap();
        assert_eq!(data.lines().count(), 1);
        assert_eq!(
            serde_json::from_str::<Value>(data.lines().next().unwrap()).unwrap()["selections"][0]["value"],
            "healthmd.health_data"
        );
        let receipt: Value =
            serde_json::from_slice(&fs::read(jsonl.receipt_path).unwrap()).unwrap();
        assert_eq!(receipt["protocol"], "healthmd.extract_receipt");
        assert_eq!(receipt["source_schema_version"], source_schema_version);
        assert_eq!(
            receipt["days"][0]["source_schema_version"],
            source_schema_version
        );
        let canonical_jsonl = receiver.extraction_jsonl(job_id.0, &[]).unwrap();
        let canonical_data = fs::read_to_string(canonical_jsonl.path).unwrap();
        assert_eq!(canonical_data.lines().count(), 1);
        assert_eq!(
            serde_json::from_str::<Value>(canonical_data.lines().next().unwrap()).unwrap()["schema"],
            "healthmd.health_data"
        );
        receiver.acknowledge_peer_completion(job_id.0).unwrap();
        assert_eq!(jobs.load(job_id.0).unwrap().state, JobState::Completed);
    }
}
