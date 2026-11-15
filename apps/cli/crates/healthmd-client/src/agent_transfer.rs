//! Original-session base receiver. Durable byte acknowledgement is not source completion.
use super::*;
use crate::agent_host::output::OutputAdmission;
use healthmd_protocol::{
    v2,
    v4::{TransferFrontier, TransferFrontierPartition},
};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt as _, AsyncSeekExt as _, AsyncWriteExt as _};
#[path = "agent_transfer_wire.rs"]
pub(super) mod wire;
use wire::{Incoming, Response, Session};

/// Exact installed receipts and recomputed received prefix. Final native confirmation is
/// still required before any terminal execution result can be emitted.
#[derive(Clone, Debug)]
pub struct ReceivedArtifacts {
    pub receipts: Vec<CommitReceipt>,
    pub session_id: ControlUuid,
    pub committed_partition_count: u64,
    pub frontier_sha256: Digest,
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PartitionRecord {
    partition: TransferFrontierPartition,
    stage_name: String,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct TransferJournal {
    schema: String,
    schema_version: u64,
    job_id: ControlUuid,
    request_sha256: Digest,
    manifest_sha256: Digest,
    session: Session,
    partitions: Vec<PartitionRecord>,
    frontier_sha256: Digest,
    final_ack_may_have_sent: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    completion_sha256: Option<Digest>,
}
pub(super) struct ResumedTransfer {
    transaction: OutputTransaction,
    journal: TransferJournal,
    checkpoint: Vec<u8>,
}
impl ResumedTransfer {
    async fn open(store: &HostAuthorityStore, job: &ControlUuid) -> Result<Self, ClientError> {
        let transaction = OutputTransaction::open_retained(store, job).await?;
        let (journal, checkpoint) = transaction.read_transfer::<TransferJournal>()?;
        validate_retained_prefix(transaction.binding(), &journal)?;
        TransferGuard::new(&transaction, transaction.binding(), &checkpoint)?.verify()?;
        Ok(Self {
            transaction,
            journal,
            checkpoint,
        })
    }
    fn last_acknowledgement(
        &self,
    ) -> Result<Option<v2::TransferPartitionAcknowledgement>, ClientError> {
        let Some(last) = self.journal.partitions.last() else {
            return Ok(None);
        };
        // The authenticated retained prefix and staged bytes were verified at open and are
        // rechecked by the send guard. Caller count/digest fields cannot synthesize this ACK.
        Ok(Some(v2::TransferPartitionAcknowledgement {
            session_id: self.journal.session.0.session_id,
            job_id: self.journal.session.0.job_id,
            partition_index: u64::try_from(last.partition.partition_index)
                .map_err(private::unavailable)?,
            transfer_id: uuid::Uuid::parse_str(&last.partition.transfer_id.0)
                .map_err(private::unavailable)?,
            partition_sha256: last.partition.sha256.0.clone(),
            accepted: true,
            message: None,
        }))
    }

    async fn replay_last_acknowledgement<F, Fut>(
        &self,
        channel: &mut crate::secure_channel::SecureChannel,
        mut current: F,
    ) -> Result<(), ClientError>
    where
        F: FnMut() -> Fut + Copy + Send,
        Fut: std::future::Future<Output = Result<(), ClientError>> + Send,
    {
        if let Some(acknowledgement) = self.last_acknowledgement()? {
            let bytes = wire::encode_base_response(
                self.transaction.binding(),
                Response::Partition(acknowledgement),
            )?;
            channel
                .send_bridge_plaintext_guarded(&bytes, current)
                .await?;
            current().await?;
        }
        Ok(())
    }

    fn request(&self) -> Result<v4::ResumeRequest, ClientError> {
        let binding = self.transaction.binding();
        Ok(v4::ResumeRequest {
            schema: v4::ResumeRequestSchema::HealthmdAgentResumeRequest,
            schema_version: 1,
            job_id: binding.request.job_id.clone(),
            request_sha256: binding.manifest.request_sha256.clone(),
            manifest_sha256: document_digest(&binding.manifest)?,
            peer: binding.request.plan.intent.peer.clone(),
            binding: approval_binding(&binding.request.plan),
            destination: binding.request.plan.intent.destination.clone(),
            committed_partition_count: self.journal.partitions.len() as u64,
            frontier_sha256: self.journal.frontier_sha256.clone(),
        })
    }
}

pub(crate) struct TransferGuard {
    dir: cap_std::fs::Dir,
    name: String,
    bytes: Vec<u8>,
    partitions: Vec<PartitionRecord>,
    completion: crate::agent_host::output::CompletionEvidence,
    frontiers: Vec<Digest>,
}
impl TransferGuard {
    fn new(
        transaction: &OutputTransaction,
        binding: &NativeBinding,
        expected: &[u8],
    ) -> Result<Self, ClientError> {
        let (journal, bytes) = transaction.read_transfer::<TransferJournal>()?;
        if bytes != expected {
            return Err(Error::BindingChanged.into());
        }
        validate_retained_prefix(binding, &journal)?;
        for record in &journal.partitions {
            let _ = transaction.stage_path(&record.stage_name)?;
        }
        let receipt = super::confirmation::expected_receipt(
            binding,
            journal.partitions.len() as u64,
            &journal.frontier_sha256,
        )?;
        let data = super::confirmation::completion_document(
            binding,
            &ControlUuid(journal.session.0.session_id.to_string()),
            &receipt,
        );
        let completion =
            transaction.completion_evidence(&data, journal.completion_sha256.as_ref())?;
        if completion.is_present() {
            require_completed_journal(transaction, binding, &journal)?;
        }
        let mut frontier = TransferFrontier::new(
            &binding.request.job_id,
            &binding.manifest.request_sha256,
            &document_digest(&binding.manifest)?,
            &ControlUuid(journal.session.0.session_id.to_string()),
        )?;
        let mut frontiers = vec![frontier.sha256().clone()];
        for record in &journal.partitions {
            frontier = frontier.appending(&record.partition)?;
            frontiers.push(frontier.sha256().clone());
        }
        let guard = Self {
            dir: transaction
                .directory()
                .try_clone()
                .map_err(private::unavailable)?,
            name: format!("transfer-{}.json", journal.job_id.0),
            bytes,
            partitions: journal.partitions,
            completion,
            frontiers,
        };
        guard.verify()?;
        Ok(guard)
    }
    /// Retained signed prefix and staged bytes, without opening another output lease.
    pub(crate) fn for_stop(transaction: &OutputTransaction) -> Result<Self, ClientError> {
        let (_, bytes) = transaction.read_transfer::<TransferJournal>()?;
        Self::new(transaction, transaction.binding(), &bytes)
    }
    pub(crate) fn evidence_digests(&self) -> (Digest, Option<Digest>) {
        (
            Digest(healthmd_protocol::transfer::sha256_hex(&self.bytes)),
            self.completion
                .bytes()
                .map(|bytes| Digest(healthmd_protocol::transfer::sha256_hex(bytes))),
        )
    }
    pub(crate) fn validate_stop_frontier(
        &self,
        receipt: &ExecutionReceipt,
    ) -> Result<(), ClientError> {
        let count =
            usize::try_from(receipt.committed_partition_count).map_err(private::unavailable)?;
        if self.frontiers.get(count) != Some(&receipt.frontier_sha256) {
            return Err(Error::BindingChanged.into());
        }
        Ok(())
    }
    pub(crate) fn verify(&self) -> Result<(), ClientError> {
        self.completion.verify()?;
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
        self.completion.verify()
    }
}
fn require_completed_journal(
    transaction: &OutputTransaction,
    binding: &NativeBinding,
    journal: &TransferJournal,
) -> Result<(), ClientError> {
    if !journal.final_ack_may_have_sent {
        return Err(Error::BindingChanged.into());
    }
    let mut receipts = Vec::new();
    for artifact in &binding.manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            return Err(Error::BindingChanged.into());
        };
        let records = journal
            .partitions
            .iter()
            .filter(|record| record.partition.artifact_id == item.artifact_id)
            .collect::<Vec<_>>();
        let bytes = records.iter().try_fold(0_u64, |sum, record| {
            sum.checked_add(
                u64::try_from(record.partition.byte_count).map_err(private::unavailable)?,
            )
            .ok_or_else(|| ClientError::from(Error::BindingChanged))
        })?;
        if records.is_empty() || bytes != item.byte_count {
            return Err(Error::BindingChanged.into());
        }
        receipts.push(
            transaction
                .plan(&item.artifact_id)
                .ok_or(Error::BindingChanged)?
                .receipt
                .clone(),
        );
    }
    transaction.require_committed_receipts(&receipts)
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
impl<'trust> BridgeSession<'trust> {
    /// Read-only local recovery preflight. This verifies the retained signed prefix and
    /// current host authority before an adapter opens a listener; it creates no recovery
    /// state and cannot replace the authenticated source's later validation.
    pub(crate) async fn preflight_retained_resume(
        store: &HostAuthorityStore,
        expected_peer: &v4::Peer,
        job: &ControlUuid,
        clock: &dyn PlanningClock,
        cancellation: &tokio_util::sync::CancellationToken,
    ) -> Result<(), ClientError> {
        expected_peer.validate_shape()?;
        job.validate_shape()?;
        if cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        // Decoder selection only; corrupt later-state evidence must never fall back
        // to the accepted reader or synthesize a missing transfer journal.
        if !store.has_retained_output(job)? {
            let admission = OutputAdmission::open_retained_for_resume(store, job, clock).await?;
            let (request, _) = admission.resumable_binding()?;
            let expiry = admission.resume_observation_expiry()?;
            if request.plan.intent.peer != *expected_peer {
                return Err(Error::BindingChanged.into());
            }
            store
                .require_output_current(&request, Some(&expiry), clock, || async {
                    if cancellation.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    Ok(())
                })
                .await?;
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            return admission.require_resumable_current(clock, cancellation);
        }
        let retained = ResumedTransfer::open(store, job).await?;
        let binding = retained.transaction.binding();
        let guard = TransferGuard::new(&retained.transaction, binding, &retained.checkpoint)?;
        if binding.request.plan.intent.peer != *expected_peer {
            return Err(Error::BindingChanged.into());
        }
        let host = store
            .authorization(
                expected_peer,
                &binding.request.plan.intent.destination.binding_id,
                Some(&binding.request.plan.authority_references.host),
                clock,
            )
            .await?;
        store
            .require_output_current(
                &binding.request,
                Some(&binding.accepted.expires_at),
                clock,
                || async {
                    if cancellation.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    Ok(())
                },
            )
            .await?;
        retained.request()?.validate_shape()?;
        require_resume_lifetime(binding, &host.delegation.expires_at, clock, cancellation)?;
        retained.transaction.require_current()?;
        guard.verify()
    }

    /// Reopen the original immutable host job on this authenticated channel. No caller
    /// request, receipt or frontier replaces retained facts; no fresh Execute is sent.
    /// # Errors
    /// Missing/changed private evidence, current authority, source metadata or prefix rejects.
    pub async fn resume_execution<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        job: ControlUuid,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostExecution<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.cancellation.clone();
        let timeout = self.timeout;
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, Box::pin(self.resume_execution_inner(store, job, clock))) => {
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }
    async fn resume_execution_inner<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        job: ControlUuid,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostExecution<'s, 'h, 'trust>, ClientError> {
        if !store.has_retained_output(&job)? {
            return Box::pin(self.resume_pre_manifest_execution_inner(store, &job, clock)).await;
        }
        Box::pin(self.resume_output_execution_inner(store, job, clock)).await
    }

    async fn resume_output_execution_inner<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        job: ControlUuid,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostExecution<'s, 'h, 'trust>, ClientError> {
        if self.send_interrupted {
            return Err(Error::BindingChanged.into());
        }
        self.send_interrupted = true;
        let retained = ResumedTransfer::open(store, &job).await?;
        let binding = retained.transaction.binding().clone();
        if self.peer != binding.request.plan.intent.peer {
            return Err(Error::BindingChanged.into());
        }
        let host = store
            .authorization(
                &binding.request.plan.intent.peer,
                &binding.request.plan.intent.destination.binding_id,
                Some(&binding.request.plan.authority_references.host),
                clock,
            )
            .await?;
        let resume = retained.request()?;
        let guard = TransferGuard::new(&retained.transaction, &binding, &retained.checkpoint)?;
        let trust = self.trust_fence;
        let expected = &self.expected_trust;
        let selected = self.requested_device;
        let cancellation = &self.cancellation;
        let current = || async {
            store
                .require_output_current(
                    &binding.request,
                    Some(&binding.accepted.expires_at),
                    clock,
                    || async {
                        if cancellation.is_cancelled() {
                            return Err(ClientError::WaitCancelled);
                        }
                        trust.require_current(selected, expected).await?;
                        if cancellation.is_cancelled() {
                            return Err(ClientError::WaitCancelled);
                        }
                        Ok(())
                    },
                )
                .await?;
            retained.transaction.require_current()?;
            guard.verify()?;
            require_resume_lifetime(&binding, &host.delegation.expires_at, clock, cancellation)
        };
        current().await?;
        retained
            .replay_last_acknowledgement(&mut self.channel, current)
            .await?;
        self.channel
            .send_v4_guarded(
                &Envelope::new(Message::ResumeRequest(Box::new(resume))),
                self.negotiation,
                current,
            )
            .await?;
        let received = self.channel.receive_v4(self.negotiation).await?.message;
        current().await?;
        let Message::ExecutionReceipt(accepted) =
            execution_response(received, &binding.request.request_id)?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        if *accepted != binding.accepted {
            return Err(Error::BindingChanged.into());
        }
        let received = self.channel.receive_v4(self.negotiation).await?.message;
        current().await?;
        let Message::ArtifactManifest(manifest) =
            execution_response(received, &binding.request.request_id)?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        if *manifest != binding.manifest {
            return Err(Error::BindingChanged.into());
        }
        self.send_interrupted = false;
        let execution = HostExecution {
            bridge: self,
            store,
            clock,
            binding,
            transfer_started: false,
            resumed: Some(retained),
            received: None,
            confirmation_started: false,
            transfer_guard: Some(guard),
            final_output: None,
        };
        execution.require_current().await?;
        // The last native trust callback may invalidate any retained evidence. No await
        // follows this local tail before ownership is returned to the caller.
        execution.verify_retained_admission()?;
        require_resume_lifetime(
            &execution.binding,
            &host.delegation.expires_at,
            clock,
            &execution.bridge.cancellation,
        )?;
        Ok(execution)
    }
}

pub(super) fn require_resume_lifetime(
    binding: &NativeBinding,
    host_expiry: &v4::UtcTimestamp,
    clock: &dyn PlanningClock,
    cancellation: &tokio_util::sync::CancellationToken,
) -> Result<(), ClientError> {
    let now = clock.now();
    now.validate_shape()?;
    if cancellation.is_cancelled() {
        return Err(ClientError::WaitCancelled);
    }
    if binding.accepted.expires_at <= now || *host_expiry <= now {
        return Err(Error::ApprovalRequired.into());
    }
    Ok(())
}

impl HostExecution<'_, '_, '_> {
    pub(super) fn refresh_completion_guard(
        &mut self,
        transaction: &OutputTransaction,
    ) -> Result<(), ClientError> {
        let (_, checkpoint) = transaction.read_transfer::<TransferJournal>()?;
        if checkpoint
            != self
                .transfer_guard
                .as_ref()
                .ok_or(Error::BindingChanged)?
                .bytes
        {
            return Err(Error::BindingChanged.into());
        }
        self.transfer_guard = Some(TransferGuard::new(transaction, &self.binding, &checkpoint)?);
        Ok(())
    }
    pub(super) async fn pin_completed_transfer(
        &mut self,
        transaction: &OutputTransaction,
        completion: &[u8],
    ) -> Result<(), ClientError> {
        let (mut journal, checkpoint) = transaction.read_transfer::<TransferJournal>()?;
        if checkpoint
            != self
                .transfer_guard
                .as_ref()
                .ok_or(Error::BindingChanged)?
                .bytes
        {
            return Err(Error::BindingChanged.into());
        }
        require_completed_journal(transaction, &self.binding, &journal)?;
        let digest = Digest(healthmd_protocol::transfer::sha256_hex(completion));
        if let Some(previous) = &journal.completion_sha256 {
            if *previous != digest {
                return Err(Error::BindingChanged.into());
            }
            self.transfer_guard
                .as_ref()
                .ok_or(Error::BindingChanged)?
                .verify()?;
            return Ok(());
        }
        journal.completion_sha256 = Some(digest);
        let next = transaction
            .save_transfer(&journal, Some(&checkpoint), || async {
                let root = self.require_current().await?;
                self.transfer_guard
                    .as_ref()
                    .ok_or(Error::BindingChanged)?
                    .verify()?;
                transaction.require_completion(completion)?;
                Ok(root)
            })
            .await?;
        self.transfer_guard = Some(TransferGuard::new(transaction, &self.binding, &next)?);
        Ok(())
    }
    fn verify_retained_admission(&self) -> Result<(), ClientError> {
        self.resumed
            .as_ref()
            .ok_or(Error::BindingChanged)?
            .transaction
            .require_current()?;
        self.transfer_guard
            .as_ref()
            .ok_or(Error::BindingChanged)?
            .verify()
    }
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
        let retained = self.resumed.take();
        let (mut transaction, restored) = if let Some(retained) = retained {
            (
                retained.transaction,
                Some((retained.journal, retained.checkpoint)),
            )
        } else {
            (
                OutputTransaction::open(self.store, &self.binding, || self.require_current())
                    .await?,
                None,
            )
        };
        let Incoming::Session(session) = self.receive_base(&transaction).await? else {
            return Err(ClientError::UnexpectedMessage);
        };
        self.validate_session(&session)?;
        let session_id = ControlUuid(session.0.session_id.to_string());
        let manifest_digest = document_digest(&self.binding.manifest)?;
        let (mut journal, mut checkpoint, mut frontier) =
            if let Some((journal, checkpoint)) = restored {
                if journal.session != session {
                    return Err(Error::BindingChanged.into());
                }
                let frontier = validate_retained_prefix(&self.binding, &journal)?;
                (journal, checkpoint, frontier)
            } else {
                let frontier = TransferFrontier::new(
                    &self.binding.request.job_id,
                    &self.binding.manifest.request_sha256,
                    &manifest_digest,
                    &session_id,
                )?;
                let journal = TransferJournal {
                    schema: "healthmd.agent_host_transfer".into(),
                    schema_version: 1,
                    job_id: self.binding.request.job_id.clone(),
                    request_sha256: self.binding.manifest.request_sha256.clone(),
                    manifest_sha256: manifest_digest,
                    session: session.clone(),
                    partitions: vec![],
                    frontier_sha256: frontier.sha256().clone(),
                    final_ack_may_have_sent: false,
                    completion_sha256: None,
                };
                let checkpoint = transaction
                    .save_transfer(&journal, None, || self.require_current())
                    .await?;
                (journal, checkpoint, frontier)
            };
        for index in 0..self.binding.manifest.artifacts.len() {
            let item = artifact(&self.binding, index)?.clone();
            self.validate_base_manifest(&transaction, &item).await?;
        }
        let mut receipts = vec![];
        let mut total = journal.partitions.iter().try_fold(0_u64, |total, record| {
            total
                .checked_add(
                    u64::try_from(record.partition.byte_count).map_err(private::unavailable)?,
                )
                .ok_or_else(|| ClientError::from(Error::BindingChanged))
        })?;
        let mut previous = journal
            .partitions
            .last()
            .map(|record| record.partition.sha256.0.clone());
        let mut transfer_ids = journal
            .partitions
            .iter()
            .map(|record| {
                uuid::Uuid::parse_str(&record.partition.transfer_id.0).map_err(private::unavailable)
            })
            .collect::<Result<std::collections::BTreeSet<_>, _>>()?;
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
            let restored = self
                .restore_artifact_prefix(&transaction, &journal, &item, &mut output)
                .await?;
            let mut offset = restored.0;
            while offset < item.byte_count || (item.byte_count == 0 && !restored.1) {
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
                self.transfer_guard = Some(TransferGuard::new(
                    &transaction,
                    &self.binding,
                    &checkpoint,
                )?);
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
            // Even a previously committed plan must not bypass validation of the
            // reconstructed original input. Partition hashes alone do not prove it.
            verify_partition_file(
                &assembled.dir,
                &assembled.name,
                &assembled.file,
                item.byte_count,
                &item.sha256.0,
            )?;
            let replay = self
                .commit_artifact_transaction(&mut transaction, &item.artifact_id, &assembled.path)
                .await?;
            let plan = transaction
                .plan(&item.artifact_id)
                .ok_or(Error::BindingChanged)?;
            let mut canonical = replay;
            canonical.status = CommitReceiptStatus::Committed;
            if !plan.committed || canonical != plan.receipt {
                return Err(Error::BindingChanged.into());
            }
            // Source confirmation replays the signed original receipt. The local
            // explicit commit API may separately report AlreadyCommitted.
            receipts.push(plan.receipt.clone());
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
        self.transfer_guard = Some(TransferGuard::new(
            &transaction,
            &self.binding,
            &checkpoint,
        )?);
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
        let received = ReceivedArtifacts {
            receipts,
            session_id,
            committed_partition_count: finalize.total_partitions,
            frontier_sha256: frontier.sha256().clone(),
        };
        self.received = Some(received.clone());
        Ok(received)
    }
    async fn restore_artifact_prefix(
        &self,
        transaction: &OutputTransaction,
        journal: &TransferJournal,
        item: &ArtifactBranch1,
        output: &mut tokio::fs::File,
    ) -> Result<(u64, bool), ClientError> {
        let mut offset = 0_u64;
        let mut found = false;
        for record in journal
            .partitions
            .iter()
            .filter(|record| record.partition.artifact_id == item.artifact_id)
        {
            self.require_current().await?;
            transaction.require_current()?;
            let file =
                private::open_private(transaction.directory(), &record.stage_name, false, false)?;
            let count = u64::try_from(record.partition.byte_count).map_err(private::unavailable)?;
            verify_partition_file(
                transaction.directory(),
                &record.stage_name,
                &file,
                count,
                &record.partition.sha256.0,
            )?;
            let mut input =
                tokio::fs::File::from_std(file.try_clone().map_err(private::unavailable)?);
            // Verification cloned the same open-file description and left its cursor at EOF.
            input.rewind().await.map_err(private::unavailable)?;
            let mut remaining = count;
            let mut buffer = vec![0_u8; 64 * 1024];
            while remaining > 0 {
                self.require_current().await?;
                transaction.require_current()?;
                let wanted = usize::try_from(remaining.min(buffer.len() as u64))
                    .map_err(private::unavailable)?;
                let read = input
                    .read(&mut buffer[..wanted])
                    .await
                    .map_err(private::unavailable)?;
                if read == 0 {
                    return Err(Error::BindingChanged.into());
                }
                output
                    .write_all(&buffer[..read])
                    .await
                    .map_err(private::unavailable)?;
                remaining -= read as u64;
            }
            verify_partition_file(
                transaction.directory(),
                &record.stage_name,
                &file,
                count,
                &record.partition.sha256.0,
            )?;
            offset = offset.checked_add(count).ok_or(Error::BindingChanged)?;
            found = true;
        }
        if found {
            output.flush().await.map_err(private::unavailable)?;
            output.sync_all().await.map_err(private::unavailable)?;
            self.require_current().await?;
            transaction.require_current()?;
            self.transfer_guard
                .as_ref()
                .ok_or(Error::BindingChanged)?
                .verify()?;
        }
        Ok((offset, found))
    }

    fn validate_session(&self, session: &Session) -> Result<(), ClientError> {
        validate_retained_session(&self.binding, session)
    }
    async fn validate_base_manifest(
        &mut self,
        transaction: &OutputTransaction,
        item: &ArtifactBranch1,
    ) -> Result<(), ClientError> {
        let message = self.receive_base(transaction).await?;
        validate_base_manifest_message(item, message)
    }
}

/// Rebuild the trusted host prefix from the original binding and ordered retained rows.
/// A requested count/digest never installs a checkpoint or replaces its original session.
fn validate_retained_prefix(
    binding: &NativeBinding,
    journal: &TransferJournal,
) -> Result<TransferFrontier, ClientError> {
    binding.validate()?;
    validate_retained_session(binding, &journal.session)?;
    let manifest = document_digest(&binding.manifest)?;
    if journal.schema != "healthmd.agent_host_transfer"
        || journal.schema_version != 1
        || journal.job_id != binding.request.job_id
        || journal.request_sha256 != binding.manifest.request_sha256
        || journal.manifest_sha256 != manifest
        || journal.partitions.len() as u64 > crate::limits::MAXIMUM_PARTITIONS_PER_JOB
    {
        return Err(Error::BindingChanged.into());
    }
    let mut frontier = TransferFrontier::new(
        &binding.request.job_id,
        &binding.manifest.request_sha256,
        &manifest,
        &ControlUuid(journal.session.0.session_id.to_string()),
    )?;
    let mut artifact_index = 0;
    let mut offset = 0_u64;
    let mut transfers = std::collections::BTreeSet::new();
    let mut stages = std::collections::BTreeSet::new();
    for (index, record) in journal.partitions.iter().enumerate() {
        let partition = &record.partition;
        partition.validate_shape()?;
        let item = artifact(binding, artifact_index)?;
        let bytes = u64::try_from(partition.byte_count).map_err(private::unavailable)?;
        let end = offset.checked_add(bytes).ok_or(Error::BindingChanged)?;
        if partition.partition_index != i64::try_from(index).map_err(private::unavailable)?
            || partition.artifact_id != item.artifact_id
            || u64::try_from(partition.artifact_offset).map_err(private::unavailable)? != offset
            || end > item.byte_count
            || (bytes == 0 && item.byte_count != 0)
            || u64::try_from(partition.chunk_count).map_err(private::unavailable)?
                != bytes.div_ceil(healthmd_protocol::TRANSFER_FRAME_BYTES as u64)
            || !transfers.insert(&partition.transfer_id)
            || !stages.insert(&record.stage_name)
        {
            return Err(Error::BindingChanged.into());
        }
        frontier = frontier.appending(partition)?;
        offset = end;
        if offset == item.byte_count {
            artifact_index += 1;
            offset = 0;
        }
    }
    if journal.frontier_sha256 != *frontier.sha256()
        || (journal.final_ack_may_have_sent
            && (artifact_index != binding.manifest.artifacts.len() || offset != 0))
    {
        return Err(Error::BindingChanged.into());
    }
    Ok(frontier)
}

pub(super) fn validate_retained_session(
    binding: &NativeBinding,
    session: &Session,
) -> Result<(), ClientError> {
    let peer = &binding.request.plan.intent.peer;
    let value = &session.0;
    ControlUuid(value.session_id.to_string()).validate_shape()?;
    if value.job_id.to_string() != binding.request.job_id.0
        || value.request_fingerprint != binding.manifest.request_sha256.0
        || value.peer_binding.source_installation_id.to_string() != peer.source_installation_id.0
        || value.peer_binding.destination_installation_id.to_string() != peer.host_installation_id.0
        || !(33_554_432..=67_108_864).contains(&value.partition_target_bytes)
        || value.created_at.timestamp_subsec_nanos() != 0
        || value.created_at.timestamp().checked_add(604_800)
            != Some(binding.accepted.expires_at.seconds()?)
    {
        return Err(Error::BindingChanged.into());
    }
    Ok(())
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

#[cfg(all(test, unix))]
#[path = "agent_retained_checkpoint_tests.rs"]
mod retained_prefix_tests;

pub(super) fn validate_base_manifest_message(
    item: &ArtifactBranch1,
    message: Incoming,
) -> Result<(), ClientError> {
    let Incoming::Manifest {
        id,
        path,
        bytes,
        sha256,
        mode,
        android,
    } = message
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
