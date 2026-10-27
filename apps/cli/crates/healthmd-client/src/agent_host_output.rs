//! Signed host output plans. These records describe exact bytes; they never confer authority.
use super::*;
use healthmd_protocol::v4::{
    Artifact, ArtifactManifest, CommitReceipt, ExecuteRequest, ExecutionReceipt,
};
use std::{
    collections::BTreeSet,
    fs::File,
    path::Path,
    sync::atomic::{AtomicUsize, Ordering},
};

const OUTPUT_MAC_DOMAIN: &[u8] = b"HealthMd.AgentBridge.HostOutputJournal.v1\0";
const OUTPUT_LOCK: &str = "outputs.lock";
const MAX_OUTPUT_JOBS: usize = 64;
#[path = "agent_output_json.rs"]
mod private_json;
const MAX_OUTPUT_BYTES: usize = private_json::MAX_BYTES;
#[path = "agent_completion_evidence.rs"]
mod completion;
pub(crate) use completion::CompletionEvidence;
#[path = "agent_source_confirmation.rs"]
mod source_confirmation;
pub(crate) use source_confirmation::read_source_confirmation;
#[path = "agent_output_stop.rs"]
mod later_stop;
pub(crate) use later_stop::PendingOutputStop;

#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct NativeBinding {
    pub request: ExecuteRequest,
    pub accepted: ExecutionReceipt,
    pub manifest: ArtifactManifest,
}
impl NativeBinding {
    pub fn validate(&self) -> Result<(), ClientError> {
        let request = &self.request;
        request.validate_shape()?;
        v4::validate_execution_receipt(&self.accepted)?;
        v4::validate_artifact_manifest(&self.manifest)?;
        let binding = v4::approval_binding(&request.plan);
        let digest = v4::document_digest(request)?;
        if request.approval.binding != binding
            || self.accepted.binding != binding
            || self.manifest.binding != binding
            || self.accepted.job_id != request.job_id
            || self.manifest.job_id != request.job_id
            || self.accepted.request_sha256 != digest
            || self.manifest.request_sha256 != digest
            || self.accepted.status != v4::ExecutionReceiptStatus::Accepted
            || self.accepted.source_acknowledged
            || self.accepted.artifact_count != 0
            || self.accepted.committed_partition_count != 0
            || self.accepted.manifest_sha256.0 != "0".repeat(64)
            || self.accepted.frontier_sha256.0 != "0".repeat(64)
        {
            return Err(Error::BindingChanged.into());
        }
        let paths = self
            .manifest
            .artifacts
            .iter()
            .map(|artifact| match artifact {
                Artifact::Branch1(artifact) => Ok(artifact.relative_path.clone()),
                _ => Err(Error::UnsupportedCapability),
            })
            .collect::<Result<Vec<_>, _>>()?;
        let predicted = &request.plan.predicted_paths;
        // A successful empty capture has no artifacts by the existing v4 contract.
        // Predicted paths are not permission to fabricate files for absent source data.
        let exact = self.manifest.capture_status == v4::ArtifactManifestCaptureStatus::Complete;
        let ordered = predicted
            .iter()
            .filter(|path| paths.contains(path))
            .cloned()
            .collect::<Vec<_>>();
        if (exact && paths != *predicted) || paths != ordered {
            return Err(Error::BindingChanged.into());
        }
        let mut total_bytes = 0_u64;
        for artifact in &self.manifest.artifacts {
            let Artifact::Branch1(artifact) = artifact else {
                return Err(Error::UnsupportedCapability.into());
            };
            if !request
                .plan
                .predicted_paths
                .contains(&artifact.relative_path)
                || artifact.write_mode != request.plan.effective_settings.write_mode
                || !matches!(
                    (
                        request.plan.effective_settings.formats.as_slice(),
                        &artifact.media_type
                    ),
                    (
                        [v4::OutputSettingsFormatsItem::Json],
                        v4::ArtifactBranch1MediaType::ApplicationJson
                    ) | (
                        [v4::OutputSettingsFormatsItem::Markdown],
                        v4::ArtifactBranch1MediaType::TextMarkdown
                    )
                )
                || serde_json::to_value(&artifact.profile).map_err(private::unavailable)?
                    != serde_json::to_value(&request.plan.effective_settings.output_profile)
                        .map_err(private::unavailable)?
            {
                return Err(Error::BindingChanged.into());
            }
            total_bytes = total_bytes
                .checked_add(artifact.byte_count)
                .ok_or(Error::BindingChanged)?;
            crate::limits::ensure_job_bytes(total_bytes)?;
        }
        Ok(())
    }
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct OutputPlan {
    pub receipt: CommitReceipt,
    pub before_exists: bool,
    pub stage_name: String,
    pub committed: bool,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct OutputJournal {
    version: u64,
    host: ControlUuid,
    binding: NativeBinding,
    plans: Vec<OutputPlan>,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SignedJournal {
    journal: OutputJournal,
    mac: Digest,
}

impl ValidateShape for SignedJournal {
    fn validate_shape(&self) -> Result<(), Error> {
        self.mac.validate_shape()
    }
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SavedExecutionAttempt {
    schema: String,
    schema_version: u64,
    host: ControlUuid,
    request: ExecuteRequest,
    request_sha256: Digest,
    started_at: UtcTimestamp,
    #[serde(skip_serializing_if = "Option::is_none")]
    accepted_receipt: Option<ExecutionReceipt>,
    #[serde(skip_serializing_if = "Option::is_none")]
    cancellation_request: Option<v4::CancelRequest>,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SignedExecutionAttempt {
    attempt: SavedExecutionAttempt,
    mac: Digest,
}

pub(crate) struct OutputAdmission {
    store: HostAuthorityStore,
    dir: cap_std::fs::Dir,
    lock: File,
    key: SecretBox<[u8; 32]>,
    request: ExecuteRequest,
    started_at: UtcTimestamp,
    accepted: Option<ExecutionReceipt>,
    cancellation: Option<v4::CancelRequest>,
    source_confirmed: bool,
    attempt_name: String,
    attempt_bytes: Vec<u8>,
}
impl OutputAdmission {
    /// Existing pre-manifest evidence only. Never create a missing lock, attempt, output
    /// journal or accepted receipt, and never promote a pre-send intent into acceptance.
    pub async fn open_retained_accepted(
        store: &HostAuthorityStore,
        job: &ControlUuid,
        clock: &dyn PlanningClock,
    ) -> Result<Self, ClientError> {
        job.validate_shape()?;
        let key = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
        let dir = store.directory()?;
        let lock = private::open_private(&dir, OUTPUT_LOCK, true, false)?;
        lock.try_lock_exclusive()
            .map_err(|_| ClientError::AgentStoreBusy)?;
        require_absent_job(&dir, job, false)?;
        let attempt_name = format!("attempt-{}.json", job.0);
        let attempt_bytes = private::read_private(&dir, &attempt_name, MAX_OUTPUT_BYTES)?;
        let saved: SignedExecutionAttempt = private_json::decode(&attempt_bytes)?;
        saved.mac.validate_shape()?;
        let attempt = saved.attempt;
        attempt.request.validate_shape()?;
        attempt.started_at.validate_shape()?;
        let now = clock.now();
        now.validate_shape()?;
        let accepted = attempt
            .accepted_receipt
            .as_ref()
            .ok_or(ClientError::AgentAuthorityUnavailable)?;
        validate_accepted(&attempt.request, accepted, clock)?;
        if attempt.schema != "healthmd.agent_host_execution_attempt"
            || attempt.host != store.host
            || attempt.request.job_id != *job
            || attempt.request.plan.intent.peer.host_installation_id != store.host
            || attempt.request_sha256 != v4::document_digest(&attempt.request)?
            || attempt.request.approval.binding != v4::approval_binding(&attempt.request.plan)
            || attempt.request.approval.authority_id
                != attempt
                    .request
                    .plan
                    .authority_references
                    .native
                    .authority_id
            || attempt.started_at > now
            || !matches!(
                (attempt.schema_version, &attempt.cancellation_request),
                (2, None) | (3, Some(_))
            )
        {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        if let Some(cancel) = &attempt.cancellation_request {
            if *cancel != execution_cancel_request(&attempt.request)? {
                return Err(ClientError::AgentAuthorityUnavailable);
            }
        }
        let expected = execution_attempt_bytes(
            &store.host,
            &attempt.request,
            &attempt.started_at,
            Some(accepted),
            attempt.cancellation_request.as_ref(),
            None,
            &key,
        )?;
        let expected: SignedExecutionAttempt = private_json::decode(&expected)?;
        if !healthmd_protocol::crypto::constant_time_equal(
            saved.mac.0.as_bytes(),
            expected.mac.0.as_bytes(),
        ) {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        let admission = Self {
            store: store.clone(),
            dir,
            lock,
            key,
            request: attempt.request,
            started_at: attempt.started_at,
            accepted: attempt.accepted_receipt,
            cancellation: attempt.cancellation_request,
            source_confirmed: false,
            attempt_name,
            attempt_bytes,
        };
        admission.require_current()?;
        Ok(admission)
    }
    pub fn accepted_binding(&self) -> Result<(ExecuteRequest, ExecutionReceipt), ClientError> {
        Ok((
            self.request.clone(),
            self.accepted
                .clone()
                .ok_or(ClientError::AgentAuthorityUnavailable)?,
        ))
    }
    pub async fn reserve<F, Fut>(
        store: &HostAuthorityStore,
        request: &ExecuteRequest,
        clock: &dyn PlanningClock,
        mut fence: F,
    ) -> Result<Self, ClientError>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<PathBuf, ClientError>>,
    {
        request.validate_shape()?;
        let key = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
        fence().await?;
        let dir = store.directory()?;
        let lock = lock_outputs(&dir)?;
        require_absent_job(&dir, &request.job_id, true)?;
        let (entries, jobs, bytes) = scan_output_usage(&dir)?;
        if entries > 8190
            || jobs >= MAX_OUTPUT_JOBS
            || bytes
                .checked_add(2 * MAX_OUTPUT_BYTES as u64)
                .is_none_or(|n| n > crate::limits::MAXIMUM_RETAINED_STORAGE_BYTES)
        {
            return Err(ClientError::AgentStoreFull);
        }
        crate::limits::ensure_available_space(&store.path, 2 * MAX_OUTPUT_BYTES as u64)?;
        let started_at = clock.now();
        started_at.validate_shape()?;
        let attempt_bytes =
            execution_attempt_bytes(&store.host, request, &started_at, None, None, None, &key)?;
        let attempt_name = format!("attempt-{}.json", request.job_id.0);
        private::publish(&dir, &attempt_name, &attempt_bytes, true, || async {
            fence().await?;
            store.directory()?;
            private::require_named_file(&dir, OUTPUT_LOCK, &lock)?;
            require_absent_job(&dir, &request.job_id, true)
        })
        .await?;
        let admission = Self {
            store: store.clone(),
            dir,
            lock,
            key,
            request: request.clone(),
            started_at,
            accepted: None,
            cancellation: None,
            source_confirmed: false,
            attempt_name,
            attempt_bytes,
        };
        admission.require_current()?;
        Ok(admission)
    }
    /// Accepted source evidence is durable before any manifest wait. This is not a terminal
    /// receipt, transfer frontier or new permission, and never renews the original lifetime.
    pub async fn persist_accepted<F, Fut>(
        &mut self,
        accepted: &ExecutionReceipt,
        clock: &dyn PlanningClock,
        mut fence: F,
    ) -> Result<(), ClientError>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<PathBuf, ClientError>>,
    {
        validate_accepted(&self.request, accepted, clock)?;
        if self.accepted.is_some() {
            return Err(Error::BindingChanged.into());
        }
        fence().await?;
        self.require_current()?;
        let bytes = execution_attempt_bytes(
            &self.store.host,
            &self.request,
            &self.started_at,
            Some(accepted),
            None,
            None,
            &self.key,
        )?;
        private::publish(&self.dir, &self.attempt_name, &bytes, false, || async {
            fence().await?;
            validate_accepted(&self.request, accepted, clock)?;
            self.require_current()
        })
        .await?;
        self.attempt_bytes = bytes;
        self.accepted = Some(accepted.clone());
        fence().await?;
        validate_accepted(&self.request, accepted, clock)?;
        // The local exact-byte/root/held-lock proof follows every delaying callback.
        self.require_current()
    }
    /// Stop needs the exact original accepted owner/key/trust, not renewed export permission.
    pub async fn require_stop_current<F, Fut>(
        &self,
        clock: &dyn PlanningClock,
        mut fence: F,
    ) -> Result<(), ClientError>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        let accepted = self.accepted.as_ref().ok_or(Error::BindingChanged)?;
        validate_accepted(&self.request, accepted, clock)?;
        self.require_current()?;
        fence().await?;
        // Key loss/rotation in the delaying trust callback must reject this very
        // pre-write fence, not merely a later post-transmission check.
        let key = key_bytes(
            &self
                .store
                .protected_key
                .load_existing(&self.store.host)
                .await?,
        )?;
        if !healthmd_protocol::crypto::constant_time_equal(
            key.expose_secret(),
            self.key.expose_secret(),
        ) {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        validate_accepted(&self.request, accepted, clock)?;
        self.require_current()
    }

    /// Save pending intent before transmission; never authorizes recapture or terminal output.
    pub async fn persist_cancellation<F, Fut>(
        &mut self,
        clock: &dyn PlanningClock,
        fence: F,
    ) -> Result<v4::CancelRequest, ClientError>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        self.require_stop_current(clock, fence).await?;
        if self.source_confirmed {
            return Err(Error::BindingChanged.into());
        }
        if let Some(request) = &self.cancellation {
            // A retained pending replay is identical evidence, not a new attempt or write.
            return Ok(request.clone());
        }
        let request = execution_cancel_request(&self.request)?;
        let bytes = execution_attempt_bytes(
            &self.store.host,
            &self.request,
            &self.started_at,
            self.accepted.as_ref(),
            Some(&request),
            None,
            &self.key,
        )?;
        self.reserve_attempt_replacement(bytes.len())?;
        private::publish(&self.dir, &self.attempt_name, &bytes, false, || async {
            self.require_stop_current(clock, fence).await
        })
        .await?;
        self.attempt_bytes = bytes;
        self.cancellation = Some(request.clone());
        self.require_stop_current(clock, fence).await?;
        Ok(request)
    }
    fn reserve_attempt_replacement(&self, new_length: usize) -> Result<(), ClientError> {
        let (entries, _, retained) = scan_output_usage(&self.dir)?;
        // Atomic replacement still needs one temporary entry. A retained owner
        // cannot borrow the fresh admission's old reservation after other jobs ran.
        if entries >= 8192 {
            return Err(ClientError::AgentStoreFull);
        }
        if retained
            .saturating_sub(self.attempt_bytes.len() as u64)
            .checked_add(new_length as u64)
            .is_none_or(|n| n > crate::limits::MAXIMUM_RETAINED_STORAGE_BYTES)
        {
            return Err(ClientError::AgentStoreFull);
        }
        crate::limits::ensure_available_space(&self.store.path, new_length as u64)?;
        Ok(())
    }
    /// Save exact source evidence only; it does not verify any host destination contents.
    pub async fn persist_source_confirmation<F, Fut>(
        &mut self,
        receipt: &ExecutionReceipt,
        clock: &dyn PlanningClock,
        cancellation: &tokio_util::sync::CancellationToken,
        fence: F,
    ) -> Result<(), ClientError>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        self.require_stop_current(clock, fence).await?;
        if self.source_confirmed {
            return Err(Error::BindingChanged.into());
        }
        let accepted = self.accepted.as_ref().ok_or(Error::BindingChanged)?;
        let cancel = self.cancellation.as_ref().ok_or(Error::BindingChanged)?;
        validate_source_stop_receipt(&self.request, accepted, receipt)?;
        let confirmed_at = clock.now();
        confirmed_at.validate_shape()?;
        if confirmed_at < self.started_at || confirmed_at >= accepted.expires_at {
            return Err(Error::BindingChanged.into());
        }
        let bytes = execution_attempt_bytes(
            &self.store.host,
            &self.request,
            &self.started_at,
            Some(accepted),
            Some(cancel),
            Some((receipt, &confirmed_at)),
            &self.key,
        )?;
        self.reserve_attempt_replacement(bytes.len())?;
        private::publish(&self.dir, &self.attempt_name, &bytes, false, || async {
            self.require_stop_current(clock, fence).await?;
            // A protected-key callback can suspend after the trust/cancellation fence.
            // The final rename must still observe local cancellation at that boundary.
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            Ok(())
        })
        .await?;
        self.attempt_bytes = bytes;
        self.source_confirmed = true;
        self.require_stop_current(clock, fence).await
    }
    pub fn require_current(&self) -> Result<(), ClientError> {
        self.store.directory()?;
        private::require_named_file(&self.dir, OUTPUT_LOCK, &self.lock)?;
        require_absent_job(&self.dir, &self.request.job_id, false)?;
        if private::read_private(&self.dir, &self.attempt_name, MAX_OUTPUT_BYTES)?
            != self.attempt_bytes
        {
            return Err(Error::BindingChanged.into());
        }
        Ok(())
    }
    pub fn bind(self, binding: &NativeBinding) -> Result<OutputTransaction, ClientError> {
        self.require_current()?;
        if self.cancellation.is_some()
            || self.request != binding.request
            || self.accepted.as_ref() != Some(&binding.accepted)
        {
            return Err(Error::BindingChanged.into());
        }
        OutputTransaction::load_locked(&self.store, binding, self.dir, self.lock, self.key)
    }
}

fn execution_cancel_request(request: &ExecuteRequest) -> Result<v4::CancelRequest, ClientError> {
    let cancel = v4::CancelRequest {
        schema: v4::CancelRequestSchema::HealthmdAgentCancelRequest,
        schema_version: 1,
        approval_id: request.approval.approval_id.clone(),
        authority_id: request.approval.authority_id.clone(),
        job_id: request.job_id.clone(),
        peer: request.plan.intent.peer.clone(),
        request_sha256: v4::document_digest(request)?,
    };
    cancel.validate_shape()?;
    Ok(cancel)
}

// Version 1 remains the immutable pre-send intent. Version 2 additionally binds the
// original authenticated acceptance. Version 3 adds exact pending cancellation intent;
// version 4 adds authenticated source confirmation, never host-output permission.
fn execution_attempt_bytes(
    host: &ControlUuid,
    request: &ExecuteRequest,
    started_at: &UtcTimestamp,
    accepted: Option<&ExecutionReceipt>,
    cancellation: Option<&v4::CancelRequest>,
    source_confirmation: Option<(&ExecutionReceipt, &UtcTimestamp)>,
    key: &SecretBox<[u8; 32]>,
) -> Result<Vec<u8>, ClientError> {
    let mut attempt = serde_json::json!({"schema":"healthmd.agent_host_execution_attempt","schema_version":if source_confirmation.is_some() {4} else if cancellation.is_some() {3} else if accepted.is_some() {2} else {1},
        "host":host,"request":request,"request_sha256":v4::document_digest(request)?,"started_at":started_at});
    if let Some(accepted) = accepted {
        attempt["accepted_receipt"] =
            serde_json::to_value(accepted).map_err(private::unavailable)?;
    }
    if let Some(request) = cancellation {
        if accepted.is_none() {
            return Err(Error::BindingChanged.into());
        }
        attempt["cancellation_request"] =
            serde_json::to_value(request).map_err(private::unavailable)?;
    }
    if let Some((receipt, confirmed_at)) = source_confirmation {
        if accepted.is_none() || cancellation.is_none() {
            return Err(Error::BindingChanged.into());
        }
        attempt["source_receipt"] = serde_json::to_value(receipt).map_err(private::unavailable)?;
        attempt["source_confirmed_at"] =
            serde_json::to_value(confirmed_at).map_err(private::unavailable)?;
    }
    let mut signer =
        Hmac::<Sha256>::new_from_slice(key.expose_secret()).map_err(private::unavailable)?;
    signer.update(if source_confirmation.is_some() {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v4\0"
    } else if cancellation.is_some() {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v3\0"
    } else if accepted.is_some() {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v2\0"
    } else {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v1\0"
    });
    signer.update(&private_json::encode(&attempt)?);
    let mut mac = String::with_capacity(64);
    for byte in signer.finalize().into_bytes() {
        write!(&mut mac, "{byte:02x}").map_err(private::unavailable)?;
    }
    let bytes = private_json::encode(&serde_json::json!({"attempt":attempt,"mac":mac}))?;
    if bytes.len() > MAX_OUTPUT_BYTES {
        return Err(ClientError::AgentStoreFull);
    }
    Ok(bytes)
}

fn validate_source_stop_receipt(
    request: &ExecuteRequest,
    accepted: &ExecutionReceipt,
    receipt: &ExecutionReceipt,
) -> Result<(), ClientError> {
    v4::validate_execution_receipt(receipt)?;
    let no_manifest = receipt.manifest_sha256.0 == "0".repeat(64);
    let no_frontier = receipt.frontier_sha256.0 == "0".repeat(64);
    // The zero digests denote absent public state, not an empty completed manifest.
    if (no_manifest
        && (receipt.status != v4::ExecutionReceiptStatus::Cancelled
            || receipt.artifact_count != 0
            || receipt.committed_partition_count != 0
            || !no_frontier))
        || (!no_manifest && no_frontier)
    {
        return Err(Error::BindingChanged.into());
    }
    if receipt.binding != v4::approval_binding(&request.plan)
        || receipt.job_id != request.job_id
        || receipt.request_sha256 != v4::document_digest(request)?
        || receipt.expires_at != accepted.expires_at
        || !receipt.source_acknowledged
        || !matches!(
            receipt.status,
            v4::ExecutionReceiptStatus::Cancelled
                | v4::ExecutionReceiptStatus::Complete
                | v4::ExecutionReceiptStatus::CompleteEmpty
                | v4::ExecutionReceiptStatus::Partial
        )
    {
        return Err(Error::BindingChanged.into());
    }
    Ok(())
}

fn validate_accepted(
    request: &ExecuteRequest,
    accepted: &ExecutionReceipt,
    clock: &dyn PlanningClock,
) -> Result<(), ClientError> {
    v4::validate_execution_receipt(accepted)?;
    let now = clock.now();
    if accepted.binding != v4::approval_binding(&request.plan)
        || accepted.job_id != request.job_id
        || accepted.request_sha256 != v4::document_digest(request)?
        || accepted.status != v4::ExecutionReceiptStatus::Accepted
        || accepted.source_acknowledged
        || accepted.artifact_count != 0
        || accepted.committed_partition_count != 0
        || accepted.frontier_sha256.0 != "0".repeat(64)
        || accepted.manifest_sha256.0 != "0".repeat(64)
        || accepted.expires_at <= now
        || accepted.expires_at.seconds()? > now.seconds()?.saturating_add(604_800)
    {
        return Err(Error::BindingChanged.into());
    }
    Ok(())
}
pub(crate) struct OutputTransaction {
    store: HostAuthorityStore,
    dir: cap_std::fs::Dir,
    lock: File,
    key: SecretBox<[u8; 32]>,
    name: String,
    journal: OutputJournal,
    persisted: Option<Vec<u8>>,
    attempt: Option<Vec<u8>>,
    is_new: bool,
    stage_slots: AtomicUsize,
}
impl OutputTransaction {
    /// Existing job only: recovery must neither create a lease file nor enroll a new job.
    pub async fn open_retained(
        store: &HostAuthorityStore,
        job: &ControlUuid,
    ) -> Result<Self, ClientError> {
        job.validate_shape()?;
        let key = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
        let dir = store.directory()?;
        let lock = private::open_private(&dir, OUTPUT_LOCK, true, false)?;
        lock.try_lock_exclusive()
            .map_err(|_| ClientError::AgentStoreBusy)?;
        let entries = scan_output_usage(&dir)?.0;
        let (journal, bytes) = read_retained_output(&dir, &store.host, job, &key)?;
        let attempt = read_compatible_execution_attempt(&dir, &store.host, &journal.binding, &key)?;
        let transaction = Self {
            store: store.clone(),
            dir,
            lock,
            key,
            name: format!("output-{}.json", job.0),
            journal,
            persisted: Some(bytes),
            attempt,
            is_new: false,
            stage_slots: AtomicUsize::new(8191 - usize::min(entries, 8191)),
        };
        transaction.require_current()?;
        Ok(transaction)
    }
    pub fn binding(&self) -> &NativeBinding {
        &self.journal.binding
    }
    pub async fn open<F, Fut>(
        store: &HostAuthorityStore,
        binding: &NativeBinding,
        fence: F,
    ) -> Result<Self, ClientError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<PathBuf, ClientError>>,
    {
        binding.validate()?;
        let key = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
        fence().await?;
        let dir = store.directory()?;
        let lock = lock_outputs(&dir)?;
        Self::load_locked(store, binding, dir, lock, key)
    }
    fn load_locked(
        store: &HostAuthorityStore,
        binding: &NativeBinding,
        dir: cap_std::fs::Dir,
        lock: File,
        key: SecretBox<[u8; 32]>,
    ) -> Result<Self, ClientError> {
        binding.validate()?;
        let (entries, jobs, retained_bytes) = scan_output_usage(&dir)?;
        let name = format!("output-{}.json", binding.request.job_id.0);
        let (journal, persisted, is_new) = match dir.symlink_metadata(&name) {
            Ok(_) => {
                let (journal, bytes) =
                    read_retained_output(&dir, &store.host, &binding.request.job_id, &key)?;
                (journal, Some(bytes), false)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                let own_attempt = dir
                    .symlink_metadata(format!("attempt-{}.json", binding.request.job_id.0))
                    .is_ok();
                if entries >= 8192 || (jobs >= MAX_OUTPUT_JOBS && !own_attempt) {
                    return Err(ClientError::AgentStoreFull);
                }
                (
                    OutputJournal {
                        version: 1,
                        host: store.host.clone(),
                        binding: binding.clone(),
                        plans: vec![],
                    },
                    None,
                    true,
                )
            }
            Err(error) => return Err(private::unavailable(error)),
        };
        if journal.version != 1 || journal.host != store.host || journal.binding != *binding {
            return Err(Error::BindingChanged.into());
        }
        validate_plans(&journal)?;
        let attempt = read_compatible_execution_attempt(&dir, &store.host, binding, &key)?;
        if is_new
            && retained_bytes
                .checked_add(MAX_OUTPUT_BYTES as u64)
                .is_none_or(|n| n > crate::limits::MAXIMUM_RETAINED_STORAGE_BYTES)
        {
            return Err(ClientError::AgentStoreFull);
        }
        Ok(Self {
            store: store.clone(),
            dir,
            lock,
            key,
            name,
            journal,
            persisted,
            attempt,
            is_new,
            stage_slots: AtomicUsize::new(8191 - usize::min(entries + usize::from(is_new), 8191)),
        })
    }
    /// Exact private checkpoint publication under the same output-operation lease.
    /// The original v1 output journal remains byte-compatible and independently signed.
    pub async fn save_transfer<T, F, Fut>(
        &self,
        data: &T,
        previous: Option<&[u8]>,
        fence: F,
    ) -> Result<Vec<u8>, ClientError>
    where
        T: Serialize,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<PathBuf, ClientError>>,
    {
        self.save_document(
            "transfer",
            b"HealthMd.AgentBridge.HostTransferJournal.v1\0",
            data,
            previous,
            fence,
        )
        .await
    }
    /// Read existing canonical checkpoint bytes without publishing, repairing or accepting
    /// caller-supplied recovery metadata. Permission and transfer semantics remain separate.
    pub fn read_transfer<T>(&self) -> Result<(T, Vec<u8>), ClientError>
    where
        T: serde::de::DeserializeOwned + Serialize,
    {
        #[derive(Deserialize, Serialize)]
        #[serde(deny_unknown_fields)]
        struct Signed<T> {
            journal: T,
            mac: Digest,
        }
        self.require_current()?;
        let name = format!("transfer-{}.json", self.journal.binding.request.job_id.0);
        let bytes = private::read_private(&self.dir, &name, MAX_OUTPUT_BYTES)?;
        let signed: Signed<T> = private_json::decode(&bytes)?;
        signed.mac.validate_shape()?;
        let mut verifier = Hmac::<Sha256>::new_from_slice(self.key.expose_secret())
            .map_err(private::unavailable)?;
        verifier.update(b"HealthMd.AgentBridge.HostTransferJournal.v1\0");
        verifier.update(self.journal.binding.request.job_id.0.as_bytes());
        verifier.update(&private_json::encode(&signed.journal)?);
        let expected = format!("{:x}", verifier.finalize().into_bytes());
        if !healthmd_protocol::crypto::constant_time_equal(
            expected.as_bytes(),
            signed.mac.0.as_bytes(),
        ) {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        self.require_current()?;
        if private::read_private(&self.dir, &name, MAX_OUTPUT_BYTES)? != bytes {
            return Err(Error::BindingChanged.into());
        }
        Ok((signed.journal, bytes))
    }
    pub async fn save_completion<T, F, Fut>(
        &self,
        data: &T,
        fence: F,
    ) -> Result<Vec<u8>, ClientError>
    where
        T: Serialize,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<PathBuf, ClientError>>,
    {
        let evidence = self.completion_evidence(data, None)?;
        if let Some(bytes) = evidence.bytes() {
            fence().await?;
            self.require_current()?;
            evidence.verify()?;
            return Ok(bytes.to_vec());
        }
        self.save_document(
            "completion",
            b"HealthMd.AgentBridge.HostCompletionJournal.v1\0",
            data,
            None,
            fence,
        )
        .await
    }
    pub fn require_completion(&self, expected: &[u8]) -> Result<(), ClientError> {
        self.require_current()?;
        let name = format!("completion-{}.json", self.journal.binding.request.job_id.0);
        if private::read_private(&self.dir, &name, MAX_OUTPUT_BYTES)? != expected {
            return Err(Error::BindingChanged.into());
        }
        Ok(())
    }
    pub fn require_committed_receipts(
        &self,
        receipts: &[CommitReceipt],
    ) -> Result<(), ClientError> {
        self.require_current()?;
        if self.persisted.is_none()
            || self.journal.plans.len() != receipts.len()
            || self
                .journal
                .plans
                .iter()
                .zip(receipts)
                .any(|(plan, receipt)| !plan.committed || plan.receipt != *receipt)
        {
            return Err(Error::BindingChanged.into());
        }
        Ok(())
    }
    async fn save_document<T, F, Fut>(
        &self,
        prefix: &str,
        domain: &[u8],
        data: &T,
        previous: Option<&[u8]>,
        fence: F,
    ) -> Result<Vec<u8>, ClientError>
    where
        T: Serialize,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<PathBuf, ClientError>>,
    {
        let name = format!("{prefix}-{}.json", self.journal.binding.request.job_id.0);
        let check_previous = || -> Result<(), ClientError> {
            self.require_current()?;
            match (previous, self.dir.symlink_metadata(&name)) {
                (Some(expected), Ok(_))
                    if private::read_private(&self.dir, &name, MAX_OUTPUT_BYTES)? == expected =>
                {
                    Ok(())
                }
                (None, Err(error)) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
                _ => Err(Error::BindingChanged.into()),
            }
        };
        check_previous()?;
        if previous.is_none() {
            self.reserve_stage_entry()?;
        }
        self.reserve_stage_bytes(0)?;
        let bytes = self.signed_document(domain, data)?;
        private::publish(&self.dir, &name, &bytes, previous.is_none(), || async {
            fence().await?;
            check_previous()
        })
        .await?;
        Ok(bytes)
    }
    pub fn plan(&self, id: &ControlUuid) -> Option<&OutputPlan> {
        self.journal
            .plans
            .iter()
            .find(|p| p.receipt.artifact_id == *id)
    }
    pub fn record(&mut self, plan: OutputPlan) -> Result<(), ClientError> {
        if let Some(previous) = self
            .journal
            .plans
            .iter_mut()
            .find(|p| p.receipt.artifact_id == plan.receipt.artifact_id)
        {
            if previous.receipt != plan.receipt
                || previous.before_exists != plan.before_exists
                || previous.stage_name != plan.stage_name
                || (previous.committed && !plan.committed)
            {
                return Err(Error::BindingChanged.into());
            }
            *previous = plan;
        } else {
            self.journal.plans.push(plan);
        }
        validate_plans(&self.journal)
    }
    pub fn require_current(&self) -> Result<(), ClientError> {
        self.store.directory()?;
        private::require_named_file(&self.dir, OUTPUT_LOCK, &self.lock)?;
        let attempt_name = format!("attempt-{}.json", self.journal.binding.request.job_id.0);
        match (&self.attempt, self.dir.symlink_metadata(&attempt_name)) {
            (Some(expected), Ok(_))
                if private::read_private(&self.dir, &attempt_name, MAX_OUTPUT_BYTES)?
                    == *expected => {}
            (None, Err(error)) if error.kind() == std::io::ErrorKind::NotFound => {}
            _ => return Err(Error::BindingChanged.into()),
        }
        match (&self.persisted, self.dir.symlink_metadata(&self.name)) {
            (Some(expected), Ok(_))
                if private::read_private(&self.dir, &self.name, MAX_OUTPUT_BYTES)? == *expected =>
            {
                Ok(())
            }
            (None, Err(error)) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            _ => Err(Error::BindingChanged.into()),
        }
    }
    pub fn stage_path(&self, name: &str) -> Result<PathBuf, ClientError> {
        validate_stage_name(name)?;
        self.require_current()?;
        Ok(self.store.path.join(name))
    }
    pub fn reserve_stage_bytes(&self, bytes: u64) -> Result<(), ClientError> {
        self.store.directory()?;
        let capacity = bytes
            .checked_add(MAX_OUTPUT_BYTES as u64)
            .ok_or(ClientError::AgentStoreFull)?;
        if scan_output_usage(&self.dir)?
            .2
            .checked_add(capacity)
            .is_none_or(|n| n > crate::limits::MAXIMUM_RETAINED_STORAGE_BYTES)
        {
            return Err(ClientError::AgentStoreFull);
        }
        // The private outputs lock already serializes all writers to this issuer store.
        crate::limits::ensure_available_space(&self.store.path, capacity)
    }
    pub fn reserve_stage_entry(&self) -> Result<(), ClientError> {
        self.stage_slots
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            .map(|_| ())
            .map_err(|_| ClientError::AgentStoreFull)
    }

    pub fn directory(&self) -> &cap_std::fs::Dir {
        &self.dir
    }
    pub async fn save<F, Fut>(&mut self, fence: F) -> Result<(), ClientError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<PathBuf, ClientError>>,
    {
        #[derive(Serialize)]
        struct Signed<'a> {
            journal: &'a OutputJournal,
            mac: Digest,
        }
        validate_plans(&self.journal)?;
        let bytes = private_json::encode(&Signed {
            journal: &self.journal,
            mac: output_mac(&self.journal, &self.key)?,
        })?;
        if bytes.len() > MAX_OUTPUT_BYTES {
            return Err(ClientError::AgentStoreFull);
        }
        private::publish(&self.dir, &self.name, &bytes, self.is_new, || async {
            fence().await?;
            self.require_current()?;
            Ok(())
        })
        .await?;
        self.persisted = Some(bytes);
        self.is_new = false;
        self.require_current()
    }
}
// An output journal independently binds authenticated acceptance. An optional older v1
// intent may coexist with it, but a pending/confirmed Stop or contradictory accepted attempt
// must not be ignored. Pin these exact bytes (including absence) across delaying callbacks.
fn read_compatible_execution_attempt(
    dir: &cap_std::fs::Dir,
    host: &ControlUuid,
    binding: &NativeBinding,
    key: &SecretBox<[u8; 32]>,
) -> Result<Option<Vec<u8>>, ClientError> {
    let name = format!("attempt-{}.json", binding.request.job_id.0);
    match dir.symlink_metadata(&name) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(private::unavailable(error)),
        Ok(_) => {}
    }
    let bytes = private::read_private(dir, &name, MAX_OUTPUT_BYTES)?;
    validate_compatible_execution_attempt(&bytes, host, binding, key)?;
    Ok(Some(bytes))
}

fn validate_compatible_execution_attempt(
    bytes: &[u8],
    host: &ControlUuid,
    binding: &NativeBinding,
    key: &SecretBox<[u8; 32]>,
) -> Result<SignedExecutionAttempt, ClientError> {
    let saved: SignedExecutionAttempt = private_json::decode(bytes)?;
    saved.mac.validate_shape()?;
    let attempt = &saved.attempt;
    attempt.started_at.validate_shape()?;
    let compatible = match (
        attempt.schema_version,
        attempt.accepted_receipt.as_ref(),
        attempt.cancellation_request.as_ref(),
    ) {
        (1, None, None) => true,
        (2, Some(accepted), None) => accepted == &binding.accepted,
        _ => false,
    };
    if !compatible
        || attempt.schema != "healthmd.agent_host_execution_attempt"
        || attempt.host != *host
        || attempt.request != binding.request
        || attempt.request_sha256 != v4::document_digest(&binding.request)?
        || attempt.started_at >= binding.accepted.expires_at
    {
        return Err(Error::BindingChanged.into());
    }
    let expected = execution_attempt_bytes(
        host,
        &attempt.request,
        &attempt.started_at,
        attempt.accepted_receipt.as_ref(),
        None,
        None,
        key,
    )?;
    let expected: SignedExecutionAttempt = private_json::decode(&expected)?;
    if !healthmd_protocol::crypto::constant_time_equal(
        saved.mac.0.as_bytes(),
        expected.mac.0.as_bytes(),
    ) {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    Ok(saved)
}

/// Load original immutable metadata by a validated local job ID, never caller-provided
/// request/receipt/frontier facts. The caller owns the existing output lock and must still
/// perform current authority/key/root fences before using this metadata for any operation.
fn read_retained_output(
    dir: &cap_std::fs::Dir,
    host: &ControlUuid,
    job: &ControlUuid,
    key: &SecretBox<[u8; 32]>,
) -> Result<(OutputJournal, Vec<u8>), ClientError> {
    host.validate_shape()?;
    job.validate_shape()?;
    let name = format!("output-{}.json", job.0);
    let bytes = private::read_private(dir, &name, MAX_OUTPUT_BYTES)?;
    let signed: SignedJournal = private_json::decode(&bytes)?;
    let expected = output_mac(&signed.journal, key)?;
    if !healthmd_protocol::crypto::constant_time_equal(
        expected.0.as_bytes(),
        signed.mac.0.as_bytes(),
    ) || signed.journal.version != 1
        || signed.journal.host != *host
        || signed.journal.binding.request.job_id != *job
    {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    validate_plans(&signed.journal)?;
    Ok((signed.journal, bytes))
}

fn lock_outputs(dir: &cap_std::fs::Dir) -> Result<File, ClientError> {
    let lock = match dir.symlink_metadata(OUTPUT_LOCK) {
        Ok(_) => private::open_private(dir, OUTPUT_LOCK, true, false)?,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            if scan_output_usage(dir)?.0 >= 8192 {
                return Err(ClientError::AgentStoreFull);
            }
            private::open_private(dir, OUTPUT_LOCK, true, true)
                .or_else(|_| private::open_private(dir, OUTPUT_LOCK, true, false))?
        }
        Err(error) => return Err(private::unavailable(error)),
    };
    lock.try_lock_exclusive()
        .map_err(|_| ClientError::AgentStoreBusy)?;
    Ok(lock)
}
fn require_absent_job(
    dir: &cap_std::fs::Dir,
    job: &ControlUuid,
    include_attempt: bool,
) -> Result<(), ClientError> {
    for prefix in if include_attempt {
        &["output", "attempt", "transfer", "completion"][..]
    } else {
        &["output", "transfer", "completion"][..]
    } {
        match dir.symlink_metadata(format!("{prefix}-{}.json", job.0)) {
            Ok(_) => return Err(Error::BindingChanged.into()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(private::unavailable(error)),
        }
    }
    Ok(())
}

fn scan_output_usage(dir: &cap_std::fs::Dir) -> Result<(usize, usize, u64), ClientError> {
    let mut entries = 0_usize;
    let mut jobs = BTreeSet::new();
    let mut bytes = 0_u64;
    for entry in dir.entries().map_err(private::unavailable)? {
        entries += 1;
        if entries > 8192 {
            return Err(ClientError::AgentStoreFull);
        }
        let name = entry.map_err(private::unavailable)?.file_name();
        let metadata = dir.symlink_metadata(&name).map_err(private::unavailable)?;
        if !metadata.is_file() {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        bytes = bytes
            .checked_add(metadata.len())
            .ok_or(ClientError::AgentStoreFull)?;
        let text = name.to_string_lossy();
        if let Some(id) = text
            .strip_prefix("output-")
            .or_else(|| text.strip_prefix("attempt-"))
            .and_then(|v| v.strip_suffix(".json"))
        {
            ControlUuid(id.into()).validate_shape()?;
            jobs.insert(id.to_owned());
        }
    }
    if bytes > crate::limits::MAXIMUM_RETAINED_STORAGE_BYTES {
        return Err(ClientError::AgentStoreFull);
    }
    Ok((entries, jobs.len(), bytes))
}

fn output_mac(journal: &OutputJournal, key: &SecretBox<[u8; 32]>) -> Result<Digest, ClientError> {
    let mut mac =
        Hmac::<Sha256>::new_from_slice(key.expose_secret()).map_err(private::unavailable)?;
    mac.update(OUTPUT_MAC_DOMAIN);
    mac.update(&private_json::encode(journal)?);
    let mut encoded = String::with_capacity(64);
    for byte in mac.finalize().into_bytes() {
        write!(&mut encoded, "{byte:02x}").map_err(private::unavailable)?;
    }
    Ok(Digest(encoded))
}
fn validate_stage_name(name: &str) -> Result<(), ClientError> {
    let uuid = name
        .strip_prefix(".output-")
        .and_then(|v| v.strip_suffix(".stage"))
        .ok_or(ClientError::AgentAuthorityUnavailable)?;
    ControlUuid(uuid.into()).validate_shape()?;
    if Path::new(name).components().count() != 1 {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    Ok(())
}
fn validate_plans(journal: &OutputJournal) -> Result<(), ClientError> {
    journal.binding.validate()?;
    if journal.plans.len() > journal.binding.manifest.artifacts.len() {
        return Err(Error::BindingChanged.into());
    }
    let mut ids = BTreeSet::new();
    let mut stages = BTreeSet::new();
    for plan in &journal.plans {
        let receipt = &plan.receipt;
        v4::validate_commit_receipt(receipt, None)?;
        validate_stage_name(&plan.stage_name)?;
        let artifact = journal
            .binding
            .manifest
            .artifacts
            .iter()
            .find_map(|a| match a {
                Artifact::Branch1(a) if a.artifact_id == receipt.artifact_id => Some(a),
                _ => None,
            })
            .ok_or(Error::BindingChanged)?;
        if !ids.insert(receipt.artifact_id.clone())
            || !stages.insert(plan.stage_name.clone())
            || receipt.peer != journal.binding.request.plan.intent.peer
            || receipt.destination != journal.binding.request.plan.intent.destination
            || receipt.job_id != journal.binding.request.job_id
            || receipt.request_sha256 != journal.binding.manifest.request_sha256
            || receipt.manifest_sha256 != v4::document_digest(&journal.binding.manifest)?
            || receipt.relative_path != artifact.relative_path
            || receipt.write_mode != artifact.write_mode
            || receipt.input_sha256 != artifact.sha256
            || receipt.status != v4::CommitReceiptStatus::Committed
            || (!plan.before_exists && receipt.before_sha256.0 != "0".repeat(64))
        {
            return Err(Error::BindingChanged.into());
        }
    }
    Ok(())
}

#[cfg(all(test, unix))]
#[path = "agent_retained_output_tests.rs"]
mod retained_output_tests;
