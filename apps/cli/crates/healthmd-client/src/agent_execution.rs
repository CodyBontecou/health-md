//! Original authenticated session owns execution and host output transactions.
use super::BridgeSession;
use crate::ClientError;
use crate::{
    agent_host::{
        HostAuthorityStore,
        output::{NativeBinding, OutputAdmission, OutputPlan, OutputTransaction},
    },
    agent_planning::PlanningClock,
    agent_private_fs as private,
    file_receiver::GeneratedDestination,
};
use healthmd_protocol::v4::{
    self, Artifact, ArtifactBranch1, ArtifactManifest, CommitReceipt, CommitReceiptSchema,
    CommitReceiptStatus, ControlUuid, Digest, Envelope, Error, ExecuteRequest, ExecutionReceipt,
    ExecutionReceiptStatus, Message, OutputSettingsWriteMode, ValidateShape, approval_binding,
    commit_key, document_digest, validate_commit_receipt,
};
use sha2::Digest as _;
use std::{
    fs::File,
    path::{Path, PathBuf},
};

/// Original authenticated owner after durable acceptance and before the manifest.
/// Dropping this owner abandons the channel; it never means source cancellation.
/// Its private fields cannot be replaced with caller-provided receipt metadata.
pub struct HostAcceptedExecution<'s, 'h, 'trust> {
    bridge: &'s mut BridgeSession<'trust>,
    store: &'h HostAuthorityStore,
    clock: &'h dyn PlanningClock,
    request: ExecuteRequest,
    accepted: ExecutionReceipt,
    admission: OutputAdmission,
}

/// Borrowed original session plus immutable authenticated acceptance/manifest. Caller JSON
/// cannot construct this owner, replace its peer, or install a receipt as permission.
pub struct HostExecution<'s, 'h, 'trust> {
    bridge: &'s mut BridgeSession<'trust>,
    store: &'h HostAuthorityStore,
    clock: &'h dyn PlanningClock,
    binding: NativeBinding,
    transfer_started: bool,
    resumed: Option<transfer::ResumedTransfer>,
    received: Option<ReceivedArtifacts>,
    confirmation_started: bool,
    transfer_guard: Option<transfer::TransferGuard>,
    final_output: Option<(GeneratedDestination, Vec<CommitReceipt>)>,
}
impl Drop for HostExecution<'_, '_, '_> {
    fn drop(&mut self) {
        // An unfinished native transfer belongs to this owner. Never reuse its channel for
        // unrelated controls after dropping execution; immutable recovery needs a new owner.
        self.bridge.send_interrupted = true;
    }
}
impl<'trust> BridgeSession<'trust> {
    /// Start a fresh issued execution and receive authenticated acceptance and manifest.
    /// Existing host journals require separate immutable Resume; they are never recaptured.
    /// Native capture/transfer dispatch must be enabled separately before an installed journey.
    /// # Errors
    /// Missing approval/current authority, wrong binding, invalid metadata or interruption reject.
    pub async fn begin_execution<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        request: ExecuteRequest,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostExecution<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.cancellation.clone();
        let timeout = self.timeout;
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, Box::pin(self.begin_execution_inner(store, request, clock))) => {
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }
    async fn begin_execution_inner<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        request: ExecuteRequest,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostExecution<'s, 'h, 'trust>, ClientError> {
        let accepted = Box::pin(self.begin_accepted_execution_inner(store, request, clock)).await?;
        Box::pin(accepted.wait_manifest_inner()).await
    }

    /// Send Execute and return its original owner once acceptance is durably journaled.
    /// The manifest may still be pending; acceptance is never terminal confirmation.
    /// # Errors
    /// Missing approval, stale authority, invalid acceptance, or interruption reject.
    pub async fn begin_accepted_execution<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        request: ExecuteRequest,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostAcceptedExecution<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.cancellation.clone();
        let timeout = self.timeout;
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, Box::pin(self.begin_accepted_execution_inner(store, request, clock))) => {
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }

    /// Recover a signed accepted attempt that has no manifest/output journal, and request Stop
    /// on this fresh authenticated owner. Caller-supplied receipt/request facts are never used.
    /// Existing pending intent is replayed without rewriting it. This returns pending only.
    /// # Errors
    /// Missing/unsafe/ambiguous evidence, old pre-send intent, changed peer/key/trust, expiry,
    /// an active owner, or later output/transfer state reject without reconstruction.
    pub async fn request_retained_accepted_cancellation<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        job: &ControlUuid,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostPendingCancellation<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.cancellation.clone();
        let timeout = self.timeout;
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, Box::pin(self.request_retained_accepted_cancellation_inner(store, job, clock))) => {
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }
    async fn request_retained_accepted_cancellation_inner<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        job: &ControlUuid,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostPendingCancellation<'s, 'h, 'trust>, ClientError> {
        if self.send_interrupted {
            return Err(Error::BindingChanged.into());
        }
        self.send_interrupted = true;
        let admission = OutputAdmission::open_retained_accepted(store, job, clock).await?;
        let (request, accepted) = admission.accepted_binding()?;
        if self.peer != request.plan.intent.peer {
            return Err(Error::BindingChanged.into());
        }
        let owner = HostAcceptedExecution {
            bridge: self,
            store,
            clock,
            request,
            accepted,
            admission,
        };
        Box::pin(owner.request_cancellation_inner()).await
    }

    async fn begin_accepted_execution_inner<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        request: ExecuteRequest,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostAcceptedExecution<'s, 'h, 'trust>, ClientError> {
        request.validate_shape()?;
        if self.send_interrupted || self.peer != request.plan.intent.peer {
            return Err(Error::BindingChanged.into());
        }
        self.send_interrupted = true;
        let trust = self.trust_fence;
        let expected = &self.expected_trust;
        let selected = self.requested_device;
        let cancellation = &self.cancellation;
        let fence = || async {
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            trust.require_current(selected, expected).await?;
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            Ok(())
        };
        store
            .require_output_current(&request, None, clock, fence)
            .await?;
        let mut admission = OutputAdmission::reserve(store, &request, clock, || async {
            store
                .require_output_current(&request, None, clock, fence)
                .await
        })
        .await?;
        self.channel
            .send_v4_guarded(
                &Envelope::new(Message::ExecuteRequest(Box::new(request.clone()))),
                self.negotiation,
                || async {
                    store
                        .require_output_current(&request, None, clock, fence)
                        .await?;
                    admission.require_current()
                },
            )
            .await?;
        let received = self.channel.receive_v4(self.negotiation).await?.message;
        fence().await?;
        let Message::ExecutionReceipt(accepted) =
            execution_response(received, &request.request_id)?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        admission
            .persist_accepted(&accepted, clock, || async {
                store
                    .require_output_current(&request, Some(&accepted.expires_at), clock, fence)
                    .await
            })
            .await?;
        Ok(HostAcceptedExecution {
            bridge: self,
            store,
            clock,
            request,
            accepted: *accepted,
            admission,
        })
    }
}

/// A durably requested Stop on the original channel. This owner carries no terminal proof.
/// Dropping it or losing the channel leaves the signed pending intent in place.
pub struct HostPendingCancellation<'s, 'h, 'trust> {
    owner: HostAcceptedExecution<'s, 'h, 'trust>,
    request: v4::CancelRequest,
}
/// Authenticated and durably recorded source Stop evidence. Native completion wins unchanged;
/// this does not verify destination contents or authorize any new execution.
pub struct SourceStopConfirmation {
    receipt: ExecutionReceipt,
}
impl HostAuthorityStore {
    /// Inspect authenticated historical source Stop evidence without a source connection.
    /// Expiry is checked at the original observation time; this grants no live authority,
    /// verifies no destination contents and never sends or renews any execution control.
    /// # Errors
    /// Missing, pending, unsafe, corrupt, wrongly bound or future-dated evidence, lost/rotated
    /// protected key, active output ownership or changed files reject without repair.
    pub async fn retained_source_stop_confirmation(
        &self,
        job: &ControlUuid,
        clock: &dyn PlanningClock,
    ) -> Result<SourceStopConfirmation, ClientError> {
        let receipt = crate::agent_host::output::read_source_confirmation(self, job, clock).await?;
        Ok(SourceStopConfirmation { receipt })
    }
}
impl SourceStopConfirmation {
    #[must_use]
    pub fn receipt(&self) -> &ExecutionReceipt {
        &self.receipt
    }
}

impl HostPendingCancellation<'_, '_, '_> {
    /// Exact requested Stop; transmission does not prove source acknowledgement.
    #[must_use]
    pub fn request(&self) -> &v4::CancelRequest {
        &self.request
    }
    /// Receive and durably validate the source's exact terminal Stop receipt.
    /// Unsolicited transfer/manifest traffic is not skipped or treated as confirmation.
    /// # Errors
    /// Interruption, timeout, stale trust/key/evidence, invalid receipt or failed publication
    /// leaves no returned terminal proof. This preserves the source's original status.
    pub async fn wait_source_confirmation(self) -> Result<SourceStopConfirmation, ClientError> {
        let cancellation = self.owner.bridge.cancellation.clone();
        let timeout = self.owner.bridge.timeout;
        tokio::select! {biased;
            ()=cancellation.cancelled()=>Err(ClientError::WaitCancelled),
            result=tokio::time::timeout(timeout,Box::pin(self.wait_source_confirmation_inner()))=>{
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }
    async fn wait_source_confirmation_inner(
        mut self,
    ) -> Result<SourceStopConfirmation, ClientError> {
        let trust = self.owner.bridge.trust_fence;
        let expected = &self.owner.bridge.expected_trust;
        let selected = self.owner.bridge.requested_device;
        let cancellation = &self.owner.bridge.cancellation;
        let fence = || async {
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            trust.require_current(selected, expected).await?;
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            Ok(())
        };
        self.owner
            .admission
            .require_stop_current(self.owner.clock, fence)
            .await?;
        let message = self
            .owner
            .bridge
            .channel
            .receive_v4(self.owner.bridge.negotiation)
            .await?
            .message;
        self.owner
            .admission
            .require_stop_current(self.owner.clock, fence)
            .await?;
        let Message::ExecutionReceipt(receipt) = message else {
            return Err(ClientError::UnexpectedMessage);
        };
        self.owner
            .admission
            .persist_source_confirmation(&receipt, self.owner.clock, cancellation, fence)
            .await?;
        if cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        Ok(SourceStopConfirmation { receipt: *receipt })
    }

    /// Original acceptance evidence, which remains distinct from terminal confirmation.
    #[must_use]
    pub fn acceptance(&self) -> &ExecutionReceipt {
        self.owner.acceptance()
    }
}

impl<'s, 'h, 'trust> HostAcceptedExecution<'s, 'h, 'trust> {
    /// Source acceptance evidence only; this is not a terminal execution receipt.
    #[must_use]
    pub fn acceptance(&self) -> &ExecutionReceipt {
        &self.accepted
    }

    /// Receive the original manifest and convert this sole owner into a transfer owner.
    /// # Errors
    /// Local interruption, stale authority, journal drift or invalid manifest reject.
    pub async fn wait_manifest(self) -> Result<HostExecution<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.bridge.cancellation.clone();
        let timeout = self.bridge.timeout;
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, Box::pin(self.wait_manifest_inner())) => {
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }

    /// Durably request Stop and send its exact binding on this original authenticated channel.
    /// A successful return means pending only, never source-confirmed cancellation.
    /// # Errors
    /// Local cancellation, expiry, stale trust/key/journal, or send failure retain no terminal claim.
    pub async fn request_cancellation(
        self,
    ) -> Result<HostPendingCancellation<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.bridge.cancellation.clone();
        let timeout = self.bridge.timeout;
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, Box::pin(self.request_cancellation_inner())) => {
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }

    async fn request_cancellation_inner(
        mut self,
    ) -> Result<HostPendingCancellation<'s, 'h, 'trust>, ClientError> {
        if self.bridge.peer != self.request.plan.intent.peer {
            return Err(Error::BindingChanged.into());
        }
        let trust = self.bridge.trust_fence;
        let expected = &self.bridge.expected_trust;
        let selected = self.bridge.requested_device;
        let cancellation = &self.bridge.cancellation;
        let fence = || async {
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            trust.require_current(selected, expected).await?;
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            Ok(())
        };
        let request = self
            .admission
            .persist_cancellation(self.clock, fence)
            .await?;
        self.bridge
            .channel
            .send_v4_guarded(
                &Envelope::new(Message::CancelRequest(Box::new(request.clone()))),
                self.bridge.negotiation,
                || async {
                    self.admission
                        .require_stop_current(self.clock, fence)
                        .await?;
                    if cancellation.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    Ok(())
                },
            )
            .await?;
        self.admission
            .require_stop_current(self.clock, fence)
            .await?;
        if cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        Ok(HostPendingCancellation {
            owner: self,
            request,
        })
    }

    async fn require_current(&self) -> Result<(), ClientError> {
        if self.bridge.peer != self.request.plan.intent.peer {
            return Err(Error::BindingChanged.into());
        }
        self.store
            .require_output_current(
                &self.request,
                Some(&self.accepted.expires_at),
                self.clock,
                || async {
                    if self.bridge.cancellation.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    self.bridge
                        .trust_fence
                        .require_current(self.bridge.requested_device, &self.bridge.expected_trust)
                        .await?;
                    if self.bridge.cancellation.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    Ok(())
                },
            )
            .await?;
        self.admission.require_current()
    }

    async fn wait_manifest_inner(self) -> Result<HostExecution<'s, 'h, 'trust>, ClientError> {
        self.require_current().await?;
        let received = self
            .bridge
            .channel
            .receive_v4(self.bridge.negotiation)
            .await?
            .message;
        self.require_current().await?;
        let Message::ArtifactManifest(manifest) =
            execution_response(received, &self.request.request_id)?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        let binding = NativeBinding {
            request: self.request,
            accepted: self.accepted,
            manifest: *manifest,
        };
        binding.validate()?;
        self.bridge.send_interrupted = false;
        let execution = HostExecution {
            bridge: self.bridge,
            store: self.store,
            clock: self.clock,
            binding,
            transfer_started: false,
            resumed: None,
            received: None,
            confirmation_started: false,
            transfer_guard: None,
            final_output: None,
        };
        let mut transaction = self.admission.bind(&execution.binding)?;
        transaction.save(|| execution.require_current()).await?;
        execution.require_current().await?;
        Ok(execution)
    }
}
fn execution_response(message: Message, request: &ControlUuid) -> Result<Message, ClientError> {
    if let Message::Rejected(rejection) = message {
        if rejection.request_id != *request {
            return Err(Error::BindingChanged.into());
        }
        return Err(ClientError::AgentRejected(rejection.code));
    }
    Ok(message)
}
impl HostExecution<'_, '_, '_> {
    async fn require_current(&self) -> Result<PathBuf, ClientError> {
        if self.bridge.send_interrupted || self.bridge.peer != self.binding.request.plan.intent.peer
        {
            return Err(Error::BindingChanged.into());
        }
        let root = self
            .store
            .require_output_current(
                &self.binding.request,
                Some(&self.binding.accepted.expires_at),
                self.clock,
                || async {
                    if self.bridge.cancellation.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    self.bridge
                        .trust_fence
                        .require_current(self.bridge.requested_device, &self.bridge.expected_trust)
                        .await?;
                    if self.bridge.cancellation.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    Ok(())
                },
            )
            .await?;
        if let Some((destination, receipts)) = &self.final_output {
            for receipt in receipts {
                self.verify_installed(destination, receipt)?;
            }
        }
        Ok(root)
    }
    #[must_use]
    pub fn manifest(&self) -> &ArtifactManifest {
        &self.binding.manifest
    }

    /// Validate exact source bytes, journal the immutable output plan, then publish and receipt.
    /// This emits no transfer/final-source acknowledgement and makes no terminal job claim.
    /// # Errors
    /// Revocation, input/destination drift, journal corruption or publication failure reject.
    pub async fn commit_artifact(
        &mut self,
        artifact_id: &ControlUuid,
        input: &Path,
    ) -> Result<CommitReceipt, ClientError> {
        if self.transfer_started {
            return Err(Error::BindingChanged.into());
        }
        let cancellation = self.bridge.cancellation.clone();
        let timeout = self.bridge.timeout;
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, Box::pin(self.commit_artifact_inner(artifact_id, input))) => {
                result.map_err(|_| ClientError::TimedOut)?
            }
        }
    }

    async fn commit_artifact_inner(
        &mut self,
        artifact_id: &ControlUuid,
        input: &Path,
    ) -> Result<CommitReceipt, ClientError> {
        let mut transaction =
            OutputTransaction::open(self.store, &self.binding, || self.require_current()).await?;
        self.commit_artifact_transaction(&mut transaction, artifact_id, input)
            .await
    }
    async fn commit_artifact_transaction(
        &mut self,
        transaction: &mut OutputTransaction,
        artifact_id: &ControlUuid,
        input: &Path,
    ) -> Result<CommitReceipt, ClientError> {
        let root = self.require_current().await?;
        let artifact = self
            .binding
            .manifest
            .artifacts
            .iter()
            .find_map(|a| match a {
                Artifact::Branch1(a) if a.artifact_id == *artifact_id => Some(a.clone()),
                _ => None,
            })
            .ok_or(Error::BindingChanged)?;
        let destination = GeneratedDestination::open(&root)?;
        let mut plan = if let Some(plan) = transaction.plan(artifact_id) {
            plan.clone()
        } else {
            Box::pin(self.prepare_output(transaction, &destination, &artifact, input)).await?
        };
        let installed = destination
            .output_sha256(&artifact.relative_path.0)?
            .as_deref()
            == Some(&plan.receipt.after_sha256.0);
        if plan.committed {
            if !installed {
                return Err(Error::BindingChanged.into());
            }
            self.require_current().await?;
            transaction.require_current()?;
            self.verify_installed(&destination, &plan.receipt)?;
            let mut receipt = plan.receipt;
            receipt.status = CommitReceiptStatus::AlreadyCommitted;
            return Ok(receipt);
        }
        // Save exact before/after/input identity before any destination publication.
        transaction.record(plan.clone())?;
        transaction.save(|| self.require_current()).await?;
        let stage = transaction.stage_path(&plan.stage_name)?;
        if !installed {
            let held =
                private::open_private(transaction.directory(), &plan.stage_name, false, false)?;
            if !held.metadata().map_err(private::unavailable)?.is_file() {
                return Err(Error::BindingChanged.into());
            }
        }
        destination
            .install_stage_guarded(
                &artifact.relative_path.0,
                &stage,
                plan.before_exists
                    .then_some(plan.receipt.before_sha256.0.as_str()),
                &plan.receipt.after_sha256.0,
                || async {
                    self.require_current().await?;
                    transaction.require_current()
                },
            )
            .await?;
        plan.committed = true;
        transaction.record(plan.clone())?;
        transaction
            .save(|| async {
                let root = self.require_current().await?;
                self.verify_installed(&destination, &plan.receipt)?;
                Ok(root)
            })
            .await?;
        self.require_current().await?;
        transaction.require_current()?;
        self.verify_installed(&destination, &plan.receipt)?;
        Ok(plan.receipt)
    }

    fn verify_installed(
        &self,
        destination: &GeneratedDestination,
        receipt: &CommitReceipt,
    ) -> Result<(), ClientError> {
        if destination
            .output_sha256(&receipt.relative_path.0)?
            .as_deref()
            != Some(&receipt.after_sha256.0)
            || self.bridge.cancellation.is_cancelled()
            || self.binding.accepted.expires_at <= self.clock.now()
        {
            return Err(Error::BindingChanged.into());
        }
        Ok(())
    }

    async fn snapshot_input(
        &self,
        transaction: &OutputTransaction,
        artifact: &ArtifactBranch1,
        input: &Path,
    ) -> Result<PrivateOutputFile, ClientError> {
        use tokio::io::{AsyncReadExt as _, AsyncSeekExt as _, AsyncWriteExt as _};
        let source = open_regular_input(input)?;
        if source.metadata().map_err(private::unavailable)?.len() != artifact.byte_count {
            return Err(Error::BindingChanged.into());
        }
        let snapshot = PrivateOutputFile::new(transaction)?;
        let mut source = tokio::fs::File::from_std(source);
        let mut output =
            tokio::fs::File::from_std(snapshot.file.try_clone().map_err(private::unavailable)?);
        let mut buffer = vec![0_u8; 64 * 1024];
        let mut count = 0_u64;
        loop {
            if self.bridge.cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            let n = source
                .read(&mut buffer)
                .await
                .map_err(private::unavailable)?;
            if n == 0 {
                break;
            }
            count = count.checked_add(n as u64).ok_or(Error::BindingChanged)?;
            if count > artifact.byte_count {
                return Err(Error::BindingChanged.into());
            }
            output
                .write_all(&buffer[..n])
                .await
                .map_err(private::unavailable)?;
        }
        output.flush().await.map_err(private::unavailable)?;
        output.sync_all().await.map_err(private::unavailable)?;
        output.rewind().await.map_err(private::unavailable)?;
        let mut hash = sha2::Sha256::new();
        let mut hashed_bytes = 0_u64;
        loop {
            if self.bridge.cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            let n = output
                .read(&mut buffer)
                .await
                .map_err(private::unavailable)?;
            if n == 0 {
                break;
            }
            hashed_bytes = hashed_bytes
                .checked_add(n as u64)
                .ok_or(Error::BindingChanged)?;
            if hashed_bytes > artifact.byte_count {
                return Err(Error::BindingChanged.into());
            }
            hash.update(&buffer[..n]);
        }
        private::require_named_file(&snapshot.dir, &snapshot.name, &snapshot.file)?;
        if count != artifact.byte_count || format!("{:x}", hash.finalize()) != artifact.sha256.0 {
            return Err(Error::BindingChanged.into());
        }
        Ok(snapshot)
    }

    async fn prepare_output(
        &self,
        transaction: &OutputTransaction,
        destination: &GeneratedDestination,
        artifact: &ArtifactBranch1,
        input: &Path,
    ) -> Result<OutputPlan, ClientError> {
        transaction.reserve_stage_bytes(
            artifact
                .byte_count
                .checked_mul(4)
                .ok_or(Error::BindingChanged)?,
        )?;
        let snapshot = self.snapshot_input(transaction, artifact, input).await?;
        let mut output = PrivateOutputFile::new(transaction)?;
        let mode = match artifact.write_mode {
            OutputSettingsWriteMode::Overwrite => healthmd_protocol::v2::FileWriteMode::Overwrite,
            OutputSettingsWriteMode::Append => healthmd_protocol::v2::FileWriteMode::Append,
            OutputSettingsWriteMode::MergeMarkdown => {
                healthmd_protocol::v2::FileWriteMode::MergeMarkdown
            }
            OutputSettingsWriteMode::MergeMarkdownPreservingPreamble => {
                healthmd_protocol::v2::FileWriteMode::MergeMarkdownPreservingPreamble
            }
        };
        let staged = if self.binding.request.plan.intent.peer.platform == v4::PeerPlatform::Android
        {
            destination.prepare_android_stage(
                &artifact.relative_path.0,
                &snapshot.path,
                &output.path,
                mode,
            )?
        } else {
            destination.prepare_stage(
                &artifact.relative_path.0,
                &snapshot.path,
                &output.path,
                mode,
            )?
        };
        let mut receipt = CommitReceipt {
            schema: CommitReceiptSchema::HealthmdAgentCommitReceipt,
            schema_version: 1,
            job_id: self.binding.request.job_id.clone(),
            artifact_id: artifact.artifact_id.clone(),
            peer: self.binding.request.plan.intent.peer.clone(),
            destination: self.binding.request.plan.intent.destination.clone(),
            request_sha256: self.binding.manifest.request_sha256.clone(),
            manifest_sha256: document_digest(&self.binding.manifest)?,
            relative_path: artifact.relative_path.clone(),
            write_mode: artifact.write_mode.clone(),
            input_sha256: artifact.sha256.clone(),
            before_sha256: Digest(
                staged
                    .before_sha256
                    .clone()
                    .unwrap_or_else(|| "0".repeat(64)),
            ),
            after_sha256: Digest(staged.after_sha256),
            commit_key: Digest("0".repeat(64)),
            status: CommitReceiptStatus::Committed,
        };
        receipt.commit_key = commit_key(&receipt)?;
        validate_commit_receipt(&receipt, None)?;
        output.retain = true; // May survive a failed journal publication; explicit cleanup owns it.
        Ok(OutputPlan {
            receipt,
            before_exists: staged.before_sha256.is_some(),
            stage_name: output.name.clone(),
            committed: false,
        })
    }
}
fn open_regular_input(path: &Path) -> Result<File, ClientError> {
    #[cfg(unix)]
    let file: File = rustix::fs::open(
        path,
        rustix::fs::OFlags::RDONLY
            | rustix::fs::OFlags::NONBLOCK
            | rustix::fs::OFlags::NOFOLLOW
            | rustix::fs::OFlags::CLOEXEC,
        rustix::fs::Mode::empty(),
    )
    .map_err(private::unavailable)?
    .into();
    #[cfg(windows)]
    let file = {
        if !std::fs::symlink_metadata(path)
            .map_err(private::unavailable)?
            .is_file()
        {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        File::open(path).map_err(private::unavailable)?
    };
    if !file.metadata().map_err(private::unavailable)?.is_file() {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    Ok(file)
}

struct PrivateOutputFile {
    dir: cap_std::fs::Dir,
    name: String,
    path: PathBuf,
    file: File,
    retain: bool,
}
impl PrivateOutputFile {
    fn new(transaction: &OutputTransaction) -> Result<Self, ClientError> {
        transaction.reserve_stage_entry()?;
        let name = format!(".output-{}.stage", uuid::Uuid::new_v4());
        let path = transaction.stage_path(&name)?;
        let file = private::open_private(transaction.directory(), &name, true, true)?;
        Ok(Self {
            dir: transaction
                .directory()
                .try_clone()
                .map_err(private::unavailable)?,
            name,
            path,
            file,
            retain: false,
        })
    }
}
impl Drop for PrivateOutputFile {
    fn drop(&mut self) {
        if !self.retain {
            let named = self.dir.symlink_metadata(&self.name);
            let held = cap_std::fs::Metadata::from_file(&self.file);
            if let (Ok(named), Ok(held)) = (named, held) {
                use cap_fs_ext::MetadataExt as _;
                if named.dev() == held.dev() && named.ino() == held.ino() {
                    let _ = self.dir.remove_file(&self.name);
                }
            }
        }
    }
}

#[path = "agent_transfer.rs"]
mod transfer;
pub use transfer::ReceivedArtifacts;

#[path = "agent_confirmation.rs"]
mod confirmation;

#[path = "agent_output_cancellation.rs"]
mod output_cancellation;
pub use output_cancellation::HostPendingOutputCancellation;
