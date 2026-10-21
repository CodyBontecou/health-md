//! Original-session base receiver. Durable byte acknowledgement is not source completion.
use super::*;
use healthmd_protocol::{
    v2,
    v4::{TransferFrontier, TransferFrontierPartition},
};
use serde::Serialize;
use tokio::io::{AsyncReadExt as _, AsyncSeekExt as _, AsyncWriteExt as _};
#[path = "agent_transfer_wire.rs"]
mod wire;
use wire::{Incoming, Response, Session};

/// Exact installed receipts and recomputed received prefix. Final native confirmation is
/// still required before any terminal execution result can be emitted.
#[derive(Debug)]
pub struct ReceivedArtifacts {
    pub receipts: Vec<CommitReceipt>,
    pub session_id: ControlUuid,
    pub committed_partition_count: u64,
    pub frontier_sha256: Digest,
}
#[derive(Clone, Serialize)]
struct PartitionRecord {
    partition: TransferFrontierPartition,
    stage_name: String,
}
#[derive(Serialize)]
struct TransferJournal {
    schema: &'static str,
    schema_version: u64,
    job_id: ControlUuid,
    request_sha256: Digest,
    manifest_sha256: Digest,
    session: Session,
    partitions: Vec<PartitionRecord>,
    frontier_sha256: Digest,
    final_ack_may_have_sent: bool,
}
pub(super) struct TransferGuard {
    dir: cap_std::fs::Dir,
    name: String,
    bytes: Vec<u8>,
    partitions: Vec<PartitionRecord>,
}
impl TransferGuard {
    fn new(
        transaction: &OutputTransaction,
        journal: &TransferJournal,
        bytes: &[u8],
    ) -> Result<Self, ClientError> {
        Ok(Self {
            dir: transaction
                .directory()
                .try_clone()
                .map_err(private::unavailable)?,
            name: format!("transfer-{}.json", journal.job_id.0),
            bytes: bytes.to_vec(),
            partitions: journal.partitions.clone(),
        })
    }
    pub(super) fn verify(&self) -> Result<(), ClientError> {
        if private::read_private(&self.dir, &self.name, 64 * 1024 * 1024)? != self.bytes {
            return Err(Error::BindingChanged.into());
        }
        for record in &self.partitions {
            let file = private::open_private(&self.dir, &record.stage_name, false, false)?;
            verify_partition_file(
                &self.dir,
                &record.stage_name,
                &file,
                u64::try_from(record.partition.byte_count).map_err(private::unavailable)?,
                &record.partition.sha256.0,
            )?;
        }
        Ok(())
    }
}
fn artifact(binding: &NativeBinding, index: usize) -> Result<&ArtifactBranch1, ClientError> {
    match binding.manifest.artifacts.get(index) {
        Some(Artifact::Branch1(value)) => Ok(value),
        _ => Err(Error::BindingChanged.into()),
    }
}
fn expected_mode(mode: &OutputSettingsWriteMode) -> v2::FileWriteMode {
    match mode {
        OutputSettingsWriteMode::Overwrite => v2::FileWriteMode::Overwrite,
        OutputSettingsWriteMode::Append => v2::FileWriteMode::Append,
        OutputSettingsWriteMode::MergeMarkdown => v2::FileWriteMode::MergeMarkdown,
        OutputSettingsWriteMode::MergeMarkdownPreservingPreamble => {
            v2::FileWriteMode::MergeMarkdownPreservingPreamble
        }
    }
}
impl HostExecution<'_, '_, '_> {
    /// Receive the original source's base transfer, persist verified partitions before their
    /// acknowledgements, and durably commit every exact output before final acknowledgement.
    /// Dropping/failing this future makes this execution unusable; immutable Resume is separate.
    /// # Errors
    /// Changed metadata, byte corruption, lost authority, storage limits or interruption reject.
    pub async fn receive_and_commit(&mut self) -> Result<ReceivedArtifacts, ClientError> {
        if self.transfer_started {
            return Err(Error::BindingChanged.into());
        }
        self.transfer_started = true;
        let cancellation = self.bridge.cancellation.clone();
        let timeout = self.bridge.timeout;
        let result = tokio::select! {
            biased;
            ()=cancellation.cancelled()=>Err(ClientError::WaitCancelled),
            result=tokio::time::timeout(timeout,Box::pin(self.receive_and_commit_inner()))=>result.map_err(|_|ClientError::TimedOut)?,
        };
        if result.is_err() {
            self.bridge.send_interrupted = true;
        }
        result
    }
    // Keep the original-session state machine and durable-ACK ordering in one audited flow.
    #[allow(clippy::too_many_lines)]
    async fn receive_and_commit_inner(&mut self) -> Result<ReceivedArtifacts, ClientError> {
        let mut transaction =
            OutputTransaction::open(self.store, &self.binding, || self.require_current()).await?;
        let Incoming::Session(session) = self.receive_base(&transaction).await? else {
            return Err(ClientError::UnexpectedMessage);
        };
        self.validate_session(&session)?;
        let session_id = ControlUuid(session.0.session_id.to_string());
        let manifest_digest = document_digest(&self.binding.manifest)?;
        let mut frontier = TransferFrontier::new(
            &self.binding.request.job_id,
            &self.binding.manifest.request_sha256,
            &manifest_digest,
            &session_id,
        )?;
        let mut journal = TransferJournal {
            schema: "healthmd.agent_host_transfer",
            schema_version: 1,
            job_id: self.binding.request.job_id.clone(),
            request_sha256: self.binding.manifest.request_sha256.clone(),
            manifest_sha256: manifest_digest,
            session: session.clone(),
            partitions: vec![],
            frontier_sha256: frontier.sha256().clone(),
            final_ack_may_have_sent: false,
        };
        let mut checkpoint = transaction
            .save_transfer(&journal, None, || self.require_current())
            .await?;
        for index in 0..self.binding.manifest.artifacts.len() {
            let item = artifact(&self.binding, index)?.clone();
            self.validate_base_manifest(&transaction, &item).await?;
        }
        let mut receipts = vec![];
        let mut total = 0_u64;
        let mut previous = None;
        let mut transfer_ids = std::collections::BTreeSet::new();
        for index in 0..self.binding.manifest.artifacts.len() {
            let item = artifact(&self.binding, index)?.clone();
            transaction.reserve_stage_bytes(
                item.byte_count
                    .checked_mul(6)
                    .ok_or(Error::BindingChanged)?,
            )?;
            let mut assembled = PrivateOutputFile::new(&transaction)?;
            let mut output = tokio::fs::File::from_std(
                assembled.file.try_clone().map_err(private::unavailable)?,
            );
            let mut offset = 0_u64;
            loop {
                let Incoming::Open {
                    session: opened,
                    partition,
                    apple_segment,
                } = self.receive_base(&transaction).await?
                else {
                    return Err(ClientError::UnexpectedMessage);
                };
                if opened != session
                    || partition.index != journal.partitions.len() as u64
                    || partition.index >= crate::limits::MAXIMUM_PARTITIONS_PER_JOB
                    || partition.artifact_id.to_string() != item.artifact_id.0
                    || partition.artifact_offset != offset
                    || partition.byte_count > 67_108_864
                    || partition.byte_count > item.byte_count - offset
                    || partition.chunk_count
                        != partition
                            .byte_count
                            .div_ceil(healthmd_protocol::TRANSFER_FRAME_BYTES as u64)
                    || partition.previous_sha256 != previous
                    || !transfer_ids.insert(partition.transfer_id)
                    || (partition.byte_count == 0 && item.byte_count != 0)
                {
                    return Err(Error::BindingChanged.into());
                }
                let descriptor = TransferFrontierPartition {
                    partition_index: i64::try_from(partition.index)
                        .map_err(private::unavailable)?,
                    transfer_id: ControlUuid(partition.transfer_id.to_string()),
                    artifact_id: item.artifact_id.clone(),
                    artifact_offset: i64::try_from(offset).map_err(private::unavailable)?,
                    byte_count: i64::try_from(partition.byte_count)
                        .map_err(private::unavailable)?,
                    chunk_count: i64::try_from(partition.chunk_count)
                        .map_err(private::unavailable)?,
                    sha256: Digest(partition.sha256.clone()),
                };
                descriptor.validate_shape()?;
                if let Some(segment) = apple_segment {
                    if segment.item_byte_count
                        != i64::try_from(item.byte_count).map_err(private::unavailable)?
                        || segment.is_final_segment
                            != (offset + partition.byte_count == item.byte_count)
                    {
                        return Err(Error::BindingChanged.into());
                    }
                }
                let mut pending = PrivateOutputFile::new(&transaction)?;
                let mut bytes = tokio::fs::File::from_std(
                    pending.file.try_clone().map_err(private::unavailable)?,
                );
                self.send_base(
                    &transaction,
                    Response::Disposition(v2::TransferDisposition {
                        session_id: session.0.session_id,
                        job_id: session.0.job_id,
                        partition_index: partition.index,
                        partition_sha256: partition.sha256.clone(),
                        disposition: v2::TransferDispositionKind::Needed,
                        message: None,
                    }),
                )
                .await?;
                let mut received = 0_u64;
                for sequence in 1..=partition.chunk_count {
                    let Incoming::Chunk(chunk) = self.receive_base(&transaction).await? else {
                        return Err(ClientError::UnexpectedMessage);
                    };
                    let wanted = (partition.byte_count - received)
                        .min(healthmd_protocol::TRANSFER_FRAME_BYTES as u64);
                    if chunk.transfer_id.0 != partition.transfer_id
                        || chunk.sequence
                            != i64::try_from(sequence).map_err(private::unavailable)?
                        || chunk.data.len() as u64 != wanted
                    {
                        return Err(Error::BindingChanged.into());
                    }
                    bytes
                        .write_all(&chunk.data)
                        .await
                        .map_err(private::unavailable)?;
                    received += wanted;
                    self.send_base(
                        &transaction,
                        Response::Chunk(v2::TransferChunkAcknowledgement {
                            transfer_id: partition.transfer_id,
                            sequence: u32::try_from(sequence).map_err(private::unavailable)?,
                            accepted: true,
                            sha256: chunk.sha256,
                            message: None,
                        }),
                    )
                    .await?;
                }
                let Incoming::Complete(complete) = self.receive_base(&transaction).await? else {
                    return Err(ClientError::UnexpectedMessage);
                };
                if complete.session_id != session.0.session_id
                    || complete.job_id != session.0.job_id
                    || complete.partition_index != partition.index
                    || complete.transfer_id != partition.transfer_id
                    || complete.partition_sha256 != partition.sha256
                    || received != partition.byte_count
                {
                    return Err(Error::BindingChanged.into());
                }
                bytes.flush().await.map_err(private::unavailable)?;
                bytes.sync_all().await.map_err(private::unavailable)?;
                bytes.rewind().await.map_err(private::unavailable)?;
                let mut hash = sha2::Sha256::new();
                let mut read = 0_u64;
                let mut buffer = vec![0_u8; 64 * 1024];
                loop {
                    self.require_current().await?;
                    transaction.require_current()?;
                    let n = bytes
                        .read(&mut buffer)
                        .await
                        .map_err(private::unavailable)?;
                    if n == 0 {
                        break;
                    }
                    read = read.checked_add(n as u64).ok_or(Error::BindingChanged)?;
                    if read > partition.byte_count {
                        return Err(Error::BindingChanged.into());
                    }
                    hash.update(&buffer[..n]);
                    output
                        .write_all(&buffer[..n])
                        .await
                        .map_err(private::unavailable)?;
                }
                private::require_named_file(&pending.dir, &pending.name, &pending.file)?;
                if read != partition.byte_count
                    || format!("{:x}", hash.finalize()) != partition.sha256
                {
                    return Err(Error::BindingChanged.into());
                }
                output.flush().await.map_err(private::unavailable)?;
                output.sync_all().await.map_err(private::unavailable)?;
                private::require_named_file(&assembled.dir, &assembled.name, &assembled.file)?;
                frontier = frontier.appending(&descriptor)?;
                journal.partitions.push(PartitionRecord {
                    partition: descriptor,
                    stage_name: pending.name.clone(),
                });
                journal.frontier_sha256 = frontier.sha256().clone();
                // Retain exact original partition bytes if publication may have completed before interruption.
                pending.retain = true;
                assembled.retain = true;
                checkpoint = transaction
                    .save_transfer(&journal, Some(&checkpoint), || async {
                        let root = self.require_current().await?;
                        verify_partition_file(
                            &pending.dir,
                            &pending.name,
                            &pending.file,
                            partition.byte_count,
                            &partition.sha256,
                        )?;
                        if self.bridge.cancellation.is_cancelled()
                            || self.binding.accepted.expires_at <= self.clock.now()
                        {
                            return Err(Error::BindingChanged.into());
                        }
                        Ok(root)
                    })
                    .await?;
                self.transfer_guard =
                    Some(TransferGuard::new(&transaction, &journal, &checkpoint)?);
                self.send_base(
                    &transaction,
                    Response::Partition(v2::TransferPartitionAcknowledgement {
                        session_id: complete.session_id,
                        job_id: complete.job_id,
                        partition_index: complete.partition_index,
                        transfer_id: complete.transfer_id,
                        partition_sha256: complete.partition_sha256,
                        accepted: true,
                        message: None,
                    }),
                )
                .await?;
                previous = Some(partition.sha256);
                offset += partition.byte_count;
                total = total
                    .checked_add(partition.byte_count)
                    .ok_or(Error::BindingChanged)?;
                if offset == item.byte_count {
                    break;
                }
            }
            drop(output);
            receipts.push(
                self.commit_artifact_transaction(
                    &mut transaction,
                    &item.artifact_id,
                    &assembled.path,
                )
                .await?,
            );
        }
        let Incoming::Finalize(finalize) = self.receive_base(&transaction).await? else {
            return Err(ClientError::UnexpectedMessage);
        };
        if finalize.session_id != session.0.session_id
            || finalize.job_id != session.0.job_id
            || finalize.request_fingerprint != self.binding.manifest.request_sha256.0
            || finalize.total_partitions != journal.partitions.len() as u64
            || finalize.total_bytes != total
            || finalize.final_partition_sha256 != previous
        {
            return Err(Error::BindingChanged.into());
        }
        // Recheck every installed artifact immediately before recording/sending the base final acknowledgement.
        let root = self.require_current().await?;
        let destination = GeneratedDestination::open(&root)?;
        for receipt in &receipts {
            self.verify_installed(&destination, receipt)?;
        }
        for record in &journal.partitions {
            self.require_current().await?;
            transaction.require_current()?;
            let _ = transaction.stage_path(&record.stage_name)?;
            let file =
                private::open_private(transaction.directory(), &record.stage_name, false, false)?;
            verify_partition_file(
                transaction.directory(),
                &record.stage_name,
                &file,
                u64::try_from(record.partition.byte_count).map_err(private::unavailable)?,
                &record.partition.sha256.0,
            )?;
        }
        self.final_output = Some((destination, receipts.clone()));
        journal.final_ack_may_have_sent = true;
        let checkpoint = transaction
            .save_transfer(&journal, Some(&checkpoint), || self.require_current())
            .await?;
        self.transfer_guard = Some(TransferGuard::new(&transaction, &journal, &checkpoint)?);
        self.send_base(
            &transaction,
            Response::Final(v2::TransferFinalAcknowledgement {
                session_id: finalize.session_id,
                job_id: finalize.job_id,
                accepted: true,
                total_partitions: finalize.total_partitions,
                total_bytes: total,
                final_partition_sha256: previous,
                response_byte_count: None,
                response_sha256: None,
                message: None,
            }),
        )
        .await?;
        self.require_current().await?;
        transaction.require_current()?;
        self.transfer_guard
            .as_ref()
            .ok_or(Error::BindingChanged)?
            .verify()?;
        Ok(ReceivedArtifacts {
            receipts,
            session_id,
            committed_partition_count: finalize.total_partitions,
            frontier_sha256: frontier.sha256().clone(),
        })
    }
    fn validate_session(&self, session: &Session) -> Result<(), ClientError> {
        let peer = &self.binding.request.plan.intent.peer;
        let value = &session.0;
        ControlUuid(value.session_id.to_string()).validate_shape()?;
        if value.job_id.to_string() != self.binding.request.job_id.0
            || value.request_fingerprint != self.binding.manifest.request_sha256.0
            || value.peer_binding.source_installation_id.to_string()
                != peer.source_installation_id.0
            || value.peer_binding.destination_installation_id.to_string()
                != peer.host_installation_id.0
            || !(33_554_432..=67_108_864).contains(&value.partition_target_bytes)
            || value.created_at.timestamp_subsec_nanos() != 0
            || value.created_at.timestamp().checked_add(604_800)
                != Some(self.binding.accepted.expires_at.seconds()?)
        {
            return Err(Error::BindingChanged.into());
        }
        Ok(())
    }
    async fn validate_base_manifest(
        &mut self,
        transaction: &OutputTransaction,
        item: &ArtifactBranch1,
    ) -> Result<(), ClientError> {
        let Incoming::Manifest {
            id,
            path,
            bytes,
            sha256,
            mode,
            android,
        } = self.receive_base(transaction).await?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        if id != item.artifact_id
            || path != item.relative_path.0
            || bytes != item.byte_count
            || sha256 != item.sha256.0
            || mode != expected_mode(&item.write_mode)
        {
            return Err(Error::BindingChanged.into());
        }
        if let Some(base) = android {
            let media = serde_json::to_value(&item.media_type).map_err(private::unavailable)?;
            if base.kind != v2::ArtifactKind::GeneratedFile
                || base.schema.id != "healthmd.generated-files"
                || base.schema.major != 1
                || Some(base.media_type.as_str()) != media.as_str()
                || base.logical_checksum_sha256.is_some()
                || base.snapshot_status.is_some()
                || base.provider_id.is_some()
            {
                return Err(Error::BindingChanged.into());
            }
        }
        Ok(())
    }
}

fn verify_partition_file(
    dir: &cap_std::fs::Dir,
    name: &str,
    file: &File,
    length: u64,
    digest: &str,
) -> Result<(), ClientError> {
    use std::io::{Read as _, Seek as _};
    private::require_named_file(dir, name, file)?;
    if file.metadata().map_err(private::unavailable)?.len() != length {
        return Err(Error::BindingChanged.into());
    }
    let mut held = file.try_clone().map_err(private::unavailable)?;
    held.rewind().map_err(private::unavailable)?;
    let mut buffer = vec![0_u8; 64 * 1024];
    let mut count = 0_u64;
    let mut hash = sha2::Sha256::new();
    loop {
        let n = held.read(&mut buffer).map_err(private::unavailable)?;
        if n == 0 {
            break;
        }
        count = count.checked_add(n as u64).ok_or(Error::BindingChanged)?;
        if count > length {
            return Err(Error::BindingChanged.into());
        }
        hash.update(&buffer[..n]);
    }
    private::require_named_file(dir, name, file)?;
    if count != length || format!("{:x}", hash.finalize()) != digest {
        return Err(Error::BindingChanged.into());
    }
    Ok(())
}
