//! Pending Stop owns the existing output lease; it never owns destination publication.
//! Authenticated channel integration is deliberately separate from these private records.
use super::*;

const PENDING_MAC_DOMAIN: &[u8] = b"HealthMd.AgentBridge.HostExecutionAttempt.v5\0";
const TRANSFER_PENDING_MAC_DOMAIN: &[u8] = b"HealthMd.AgentBridge.HostExecutionAttempt.v7\0";
const TRANSFER_CONFIRMED_MAC_DOMAIN: &[u8] = b"HealthMd.AgentBridge.HostExecutionAttempt.v8\0";
const CONFIRMED_MAC_DOMAIN: &[u8] = b"HealthMd.AgentBridge.HostExecutionAttempt.v6\0";

#[derive(Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct TransferStopEvidence {
    transfer_sha256: Digest,
    #[serde(skip_serializing_if = "Option::is_none")]
    completion_sha256: Option<Digest>,
}
impl TransferStopEvidence {
    fn from_guard(guard: &crate::agent_bridge::TransferGuard) -> Self {
        let (transfer_sha256, completion_sha256) = guard.evidence_digests();
        Self {
            transfer_sha256,
            completion_sha256,
        }
    }
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PendingRecord {
    schema: String,
    schema_version: u64,
    host: ControlUuid,
    binding: NativeBinding,
    original_attempt: serde_json::Value,
    output_sha256: Digest,
    cancellation_request: v4::CancelRequest,
    requested_at: UtcTimestamp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    transfer_evidence: Option<TransferStopEvidence>,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SignedPendingRecord {
    attempt: PendingRecord,
    mac: Digest,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ConfirmedRecord {
    schema: String,
    schema_version: u64,
    host: ControlUuid,
    pending: SignedPendingRecord,
    source_receipt: ExecutionReceipt,
    source_confirmed_at: UtcTimestamp,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SignedConfirmedRecord {
    attempt: ConfirmedRecord,
    mac: Digest,
}

struct ObservedAt<'a>(&'a UtcTimestamp);
impl PlanningClock for ObservedAt<'_> {
    fn now(&self) -> UtcTimestamp {
        self.0.clone()
    }
}

pub(crate) struct PendingOutputStop {
    transaction: OutputTransaction,
    request: v4::CancelRequest,
    started_at: UtcTimestamp,
    requested_at: UtcTimestamp,
    transfer_guard: Option<crate::agent_bridge::TransferGuard>,
}

impl PendingOutputStop {
    /// Recover only a pending Stop. No lock/journal is created, no bytes are rewritten,
    /// and the original output/attempt/accepted lifetime cannot be replaced by caller facts.
    pub(crate) fn open_retained<F, Fut>(
        store: &HostAuthorityStore,
        job: &ControlUuid,
        clock: &dyn PlanningClock,
        fence: F,
    ) -> impl std::future::Future<Output = Result<Self, ClientError>>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        Box::pin(Self::open_retained_inner(store, job, clock, fence))
    }

    async fn open_retained_inner<F, Fut>(
        store: &HostAuthorityStore,
        job: &ControlUuid,
        clock: &dyn PlanningClock,
        fence: F,
    ) -> Result<Self, ClientError>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        let transaction = read_stop_transaction(store, job).await?;
        let bytes = transaction.attempt.as_ref().ok_or(Error::BindingChanged)?;
        let signed: SignedPendingRecord = private_json::decode(bytes)?;
        let owner = Self::from_pending(transaction, signed)?;
        owner.require_current(clock, fence).await?;
        Ok(owner)
    }

    /// Choose a decoder from the retained private version, then authenticate that exact
    /// lifecycle before any mutation. A failed decoder never retries another lifecycle.
    pub(crate) async fn prepare_or_open_retained<F, Fut>(
        store: &HostAuthorityStore,
        expected_peer: &v4::Peer,
        job: &ControlUuid,
        clock: &dyn PlanningClock,
        fence: F,
    ) -> Result<Self, ClientError>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        expected_peer.validate_shape()?;
        let transaction = read_stop_transaction(store, job).await?;
        if transaction.binding().request.plan.intent.peer != *expected_peer {
            return Err(Error::BindingChanged.into());
        }
        let bytes = transaction.attempt.as_ref().ok_or(Error::BindingChanged)?;
        let value: serde_json::Value = private_json::decode(bytes)?;
        match value
            .pointer("/attempt/schema_version")
            .and_then(serde_json::Value::as_u64)
        {
            Some(1 | 2) => {
                validate_compatible_execution_attempt(
                    bytes,
                    &store.host,
                    transaction.binding(),
                    &transaction.key,
                )?;
                Box::pin(Self::prepare(transaction, clock, fence)).await
            }
            Some(5 | 7) => {
                let signed: SignedPendingRecord = private_json::decode(bytes)?;
                let owner = Self::from_pending(transaction, signed)?;
                owner.require_current(clock, fence).await?;
                Ok(owner)
            }
            _ => Err(Error::BindingChanged.into()),
        }
    }

    fn from_pending(
        transaction: OutputTransaction,
        pending: SignedPendingRecord,
    ) -> Result<Self, ClientError> {
        let started_at = validate_pending(&pending, &transaction)?;
        let transfer_guard = match &pending.attempt.transfer_evidence {
            Some(expected) => {
                let guard = crate::agent_bridge::TransferGuard::for_stop(&transaction)?;
                if TransferStopEvidence::from_guard(&guard) != *expected {
                    return Err(Error::BindingChanged.into());
                }
                Some(guard)
            }
            None => None,
        };
        Ok(Self {
            transaction,
            request: pending.attempt.cancellation_request,
            started_at,
            requested_at: pending.attempt.requested_at,
            transfer_guard,
        })
    }

    /// Consume an existing persisted output owner. Pre-transfer Stop retains v5 bytes;
    /// retained-transfer Stop uses a separate v7 MAC domain and pins all recovery evidence.
    /// Ordinary output recovery rejects either pending record instead of resuming it.
    pub(crate) fn prepare<F, Fut>(
        transaction: OutputTransaction,
        clock: &dyn PlanningClock,
        fence: F,
    ) -> impl std::future::Future<Output = Result<Self, ClientError>>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        Box::pin(Self::prepare_inner(transaction, clock, fence))
    }

    async fn prepare_inner<F, Fut>(
        transaction: OutputTransaction,
        clock: &dyn PlanningClock,
        fence: F,
    ) -> Result<Self, ClientError>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        let request = execution_cancel_request(&transaction.journal.binding.request)?;
        let original: SignedExecutionAttempt =
            private_json::decode(transaction.attempt.as_ref().ok_or(Error::BindingChanged)?)?;
        let transfer_guard = match transaction
            .dir
            .symlink_metadata(format!("transfer-{}.json", request.job_id.0))
        {
            Ok(_) => Some(crate::agent_bridge::TransferGuard::for_stop(&transaction)?),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(error) => return Err(private::unavailable(error)),
        };
        let mut owner = Self {
            transaction,
            request,
            started_at: original.attempt.started_at,
            requested_at: clock.now(),
            transfer_guard,
        };
        owner.require_current(clock, fence).await?;
        let transaction = &owner.transaction;
        let output = transaction
            .persisted
            .as_ref()
            .ok_or(Error::BindingChanged)?;
        let original = transaction.attempt.as_ref().ok_or(Error::BindingChanged)?;
        // The transaction's constructor already authenticated compatibility and the original
        // request/acceptance. Keep that complete historical record in the new MAC domain.
        let original: serde_json::Value = private_json::decode(original)?;
        owner.requested_at.validate_shape()?;
        let attempt = PendingRecord {
            schema: "healthmd.agent_host_execution_attempt".into(),
            schema_version: if owner.transfer_guard.is_some() { 7 } else { 5 },
            host: transaction.store.host.clone(),
            binding: transaction.journal.binding.clone(),
            original_attempt: original,
            output_sha256: Digest(hex_sha256(output)),
            cancellation_request: owner.request.clone(),
            requested_at: owner.requested_at.clone(),
            transfer_evidence: owner
                .transfer_guard
                .as_ref()
                .map(TransferStopEvidence::from_guard),
        };
        let bytes = private_json::encode(&SignedPendingRecord {
            mac: pending_mac(&attempt, &transaction.key)?,
            attempt,
        })?;
        owner.reserve_replacement(bytes.len())?;
        let name = format!("attempt-{}.json", owner.request.job_id.0);
        private::publish(&owner.transaction.dir, &name, &bytes, false, || async {
            owner.require_current(clock, fence).await
        })
        .await?;
        owner.transaction.attempt = Some(bytes);
        owner.require_current(clock, fence).await?;
        Ok(owner)
    }

    /// Consume pending intent only after the original authenticated source supplied this
    /// exact terminal receipt. This records source facts, never host destination success.
    pub(crate) async fn confirm<F, Fut>(
        mut self,
        receipt: &ExecutionReceipt,
        clock: &dyn PlanningClock,
        cancellation: &tokio_util::sync::CancellationToken,
        fence: F,
    ) -> Result<ExecutionReceipt, ClientError>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        self.require_current(clock, fence).await?;
        if cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        validate_bound_receipt(&self.transaction.journal.binding, receipt)?;
        if let Some(guard) = &self.transfer_guard {
            guard.validate_stop_frontier(receipt)?;
        }
        let confirmed_at = clock.now();
        confirmed_at.validate_shape()?;
        if confirmed_at < self.requested_at
            || confirmed_at >= self.transaction.journal.binding.accepted.expires_at
        {
            return Err(Error::BindingChanged.into());
        }
        let pending: SignedPendingRecord = private_json::decode(
            self.transaction
                .attempt
                .as_ref()
                .ok_or(Error::BindingChanged)?,
        )?;
        validate_pending(&pending, &self.transaction)?;
        let record = ConfirmedRecord {
            schema: "healthmd.agent_host_execution_attempt".into(),
            schema_version: if pending.attempt.schema_version == 7 {
                8
            } else {
                6
            },
            host: self.transaction.store.host.clone(),
            pending,
            source_receipt: receipt.clone(),
            source_confirmed_at: confirmed_at.clone(),
        };
        let bytes = private_json::encode(&SignedConfirmedRecord {
            mac: stop_mac(&record, confirmed_domain(&record)?, &self.transaction.key)?,
            attempt: record,
        })?;
        self.reserve_replacement(bytes.len())?;
        let name = format!("attempt-{}.json", self.request.job_id.0);
        private::publish(&self.transaction.dir, &name, &bytes, false, || async {
            self.require_current(clock, fence).await?;
            if cancellation.is_cancelled() {
                return Err(ClientError::WaitCancelled);
            }
            if clock.now() < confirmed_at {
                return Err(Error::BindingChanged.into());
            }
            self.transaction.require_current()?;
            if let Some(guard) = &self.transfer_guard {
                guard.verify()?;
            }
            Ok(())
        })
        .await?;
        self.transaction.attempt = Some(bytes);
        self.require_current(clock, fence).await?;
        let now = clock.now();
        now.validate_shape()?;
        if cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        if now < confirmed_at {
            return Err(Error::BindingChanged.into());
        }
        self.transaction.require_current()?;
        if let Some(guard) = &self.transfer_guard {
            guard.verify()?;
        }
        Ok(receipt.clone())
    }

    pub(crate) fn request(&self) -> &v4::CancelRequest {
        &self.request
    }

    pub(crate) fn binding(&self) -> &NativeBinding {
        self.transaction.binding()
    }

    /// Original accepted expiry/key/trust and exact local evidence only. Revoking an
    /// export grant must not renew or prohibit Stop on that accepted execution.
    pub(crate) async fn require_current<F, Fut>(
        &self,
        clock: &dyn PlanningClock,
        mut fence: F,
    ) -> Result<(), ClientError>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        self.require_local(clock)?;
        fence().await?;
        let key = key_bytes(
            &self
                .transaction
                .store
                .protected_key
                .load_existing(&self.transaction.store.host)
                .await?,
        )?;
        if !healthmd_protocol::crypto::constant_time_equal(
            key.expose_secret(),
            self.transaction.key.expose_secret(),
        ) {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        self.require_local(clock)
    }

    fn require_local(&self, clock: &dyn PlanningClock) -> Result<(), ClientError> {
        let transaction = &self.transaction;
        transaction.require_current()?;
        if transaction.is_new || transaction.persisted.is_none() || transaction.attempt.is_none() {
            return Err(Error::BindingChanged.into());
        }
        let binding = &transaction.journal.binding;
        validate_accepted(&binding.request, &binding.accepted, clock)?;
        if self.started_at > self.requested_at || self.requested_at > clock.now() {
            return Err(Error::BindingChanged.into());
        }
        transaction.require_current()?;
        if let Some(guard) = &self.transfer_guard {
            return guard.verify();
        }
        for prefix in ["transfer", "completion"] {
            match transaction
                .dir
                .symlink_metadata(format!("{prefix}-{}.json", self.request.job_id.0))
            {
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(private::unavailable(error)),
                Ok(_) => return Err(Error::BindingChanged.into()),
            }
        }
        Ok(())
    }

    fn reserve_replacement(&self, length: usize) -> Result<(), ClientError> {
        if length > MAX_OUTPUT_BYTES {
            return Err(ClientError::AgentStoreFull);
        }
        let (entries, _, retained) = scan_output_usage(&self.transaction.dir)?;
        let old_length = self
            .transaction
            .attempt
            .as_ref()
            .ok_or(Error::BindingChanged)?
            .len();
        if entries >= 8192
            || retained
                .saturating_sub(old_length as u64)
                .checked_add(length as u64)
                .is_none_or(|n| n > crate::limits::MAXIMUM_RETAINED_STORAGE_BYTES)
        {
            return Err(ClientError::AgentStoreFull);
        }
        crate::limits::ensure_available_space(&self.transaction.store.path, length as u64)
    }
}

fn hex_sha256(bytes: &[u8]) -> String {
    use sha2::Digest as _;
    format!("{:x}", Sha256::digest(bytes))
}

fn pending_mac(record: &PendingRecord, key: &SecretBox<[u8; 32]>) -> Result<Digest, ClientError> {
    let domain = match (record.schema_version, record.transfer_evidence.is_some()) {
        (5, false) => PENDING_MAC_DOMAIN,
        (7, true) => TRANSFER_PENDING_MAC_DOMAIN,
        _ => return Err(Error::BindingChanged.into()),
    };
    stop_mac(record, domain, key)
}
fn confirmed_domain(record: &ConfirmedRecord) -> Result<&'static [u8], ClientError> {
    match (record.schema_version, record.pending.attempt.schema_version) {
        (6, 5) => Ok(CONFIRMED_MAC_DOMAIN),
        (8, 7) => Ok(TRANSFER_CONFIRMED_MAC_DOMAIN),
        _ => Err(Error::BindingChanged.into()),
    }
}
fn stop_mac<T: Serialize>(
    record: &T,
    domain: &[u8],
    key: &SecretBox<[u8; 32]>,
) -> Result<Digest, ClientError> {
    let mut signer =
        Hmac::<Sha256>::new_from_slice(key.expose_secret()).map_err(private::unavailable)?;
    signer.update(domain);
    signer.update(&private_json::encode(record)?);
    let mut mac = String::with_capacity(64);
    for byte in signer.finalize().into_bytes() {
        write!(&mut mac, "{byte:02x}").map_err(private::unavailable)?;
    }
    Ok(Digest(mac))
}

async fn read_stop_transaction(
    store: &HostAuthorityStore,
    job: &ControlUuid,
) -> Result<OutputTransaction, ClientError> {
    job.validate_shape()?;
    let key = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
    let dir = store.directory()?;
    let lock = private::open_private(&dir, OUTPUT_LOCK, true, false)?;
    lock.try_lock_exclusive()
        .map_err(|_| ClientError::AgentStoreBusy)?;
    let entries = scan_output_usage(&dir)?.0;
    let (journal, output_bytes) = read_retained_output(&dir, &store.host, job, &key)?;
    let bytes = private::read_private(&dir, &format!("attempt-{}.json", job.0), MAX_OUTPUT_BYTES)?;
    let transaction = OutputTransaction {
        store: store.clone(),
        dir,
        lock,
        key,
        name: format!("output-{}.json", job.0),
        journal,
        persisted: Some(output_bytes),
        attempt: Some(bytes),
        is_new: false,
        stage_slots: AtomicUsize::new(8191 - usize::min(entries, 8191)),
    };
    transaction.require_current()?;
    Ok(transaction)
}

fn validate_pending(
    signed: &SignedPendingRecord,
    transaction: &OutputTransaction,
) -> Result<UtcTimestamp, ClientError> {
    signed.mac.validate_shape()?;
    let record = &signed.attempt;
    record.requested_at.validate_shape()?;
    record.output_sha256.validate_shape()?;
    let output = transaction
        .persisted
        .as_ref()
        .ok_or(Error::BindingChanged)?;
    if record.schema != "healthmd.agent_host_execution_attempt"
        || !matches!(
            (record.schema_version, record.transfer_evidence.is_some()),
            (5, false) | (7, true)
        )
        || record.host != transaction.store.host
        || record.binding != transaction.journal.binding
        || record.output_sha256.0 != hex_sha256(output)
        || record.cancellation_request
            != execution_cancel_request(&transaction.journal.binding.request)?
    {
        return Err(Error::BindingChanged.into());
    }
    let expected = pending_mac(record, &transaction.key)?;
    if !healthmd_protocol::crypto::constant_time_equal(
        signed.mac.0.as_bytes(),
        expected.0.as_bytes(),
    ) {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    let original = validate_compatible_execution_attempt(
        &private_json::encode(&record.original_attempt)?,
        &transaction.store.host,
        &transaction.journal.binding,
        &transaction.key,
    )?;
    Ok(original.attempt.started_at)
}

fn validate_bound_receipt(
    binding: &NativeBinding,
    receipt: &ExecutionReceipt,
) -> Result<(), ClientError> {
    validate_source_stop_receipt(&binding.request, &binding.accepted, receipt)?;
    if receipt.status != v4::ExecutionReceiptStatus::Cancelled {
        let expected = match binding.manifest.capture_status {
            v4::ArtifactManifestCaptureStatus::Complete => v4::ExecutionReceiptStatus::Complete,
            v4::ArtifactManifestCaptureStatus::CompleteEmpty => {
                v4::ExecutionReceiptStatus::CompleteEmpty
            }
            v4::ArtifactManifestCaptureStatus::Partial => v4::ExecutionReceiptStatus::Partial,
            _ => return Err(Error::BindingChanged.into()),
        };
        // Preserved source completion cannot contradict its authenticated capture manifest.
        if receipt.status != expected {
            return Err(Error::BindingChanged.into());
        }
    }
    // Both reviewed native generated-file senders retain one partition per artifact.
    // Cancellation may preserve a prefix; preserved terminal capture commits all artifacts.
    if receipt.manifest_sha256 != v4::document_digest(&binding.manifest)?
        || receipt.artifact_count != binding.manifest.artifacts.len() as u64
        || receipt.committed_partition_count > receipt.artifact_count
        || (receipt.status != v4::ExecutionReceiptStatus::Cancelled
            && receipt.committed_partition_count != receipt.artifact_count)
    {
        return Err(Error::BindingChanged.into());
    }
    Ok(())
}

/// Historical source facts only. No current export grant, active owner, new control or
/// destination verification is returned; original expiry is checked at the observation.
pub(crate) async fn read_confirmed_output_stop<F, Fut>(
    store: &HostAuthorityStore,
    job: &ControlUuid,
    clock: &dyn PlanningClock,
    mut fence: F,
) -> Result<ExecutionReceipt, ClientError>
where
    F: FnMut() -> Fut + Copy,
    Fut: std::future::Future<Output = Result<(), ClientError>>,
{
    let transaction = read_stop_transaction(store, job).await?;
    let bytes = transaction.attempt.as_ref().ok_or(Error::BindingChanged)?;
    let signed: SignedConfirmedRecord = private_json::decode(bytes)?;
    signed.mac.validate_shape()?;
    let record = signed.attempt;
    record.source_confirmed_at.validate_shape()?;
    let now = clock.now();
    now.validate_shape()?;
    if record.schema != "healthmd.agent_host_execution_attempt"
        || !matches!(record.schema_version, 6 | 8)
        || record.host != store.host
        || record.source_confirmed_at > now
        || record.source_confirmed_at < record.pending.attempt.requested_at
    {
        return Err(Error::BindingChanged.into());
    }
    let expected = stop_mac(&record, confirmed_domain(&record)?, &transaction.key)?;
    if !healthmd_protocol::crypto::constant_time_equal(
        signed.mac.0.as_bytes(),
        expected.0.as_bytes(),
    ) {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    validate_bound_receipt(&transaction.journal.binding, &record.source_receipt)?;
    let receipt = record.source_receipt;
    let confirmed_at = record.source_confirmed_at;
    let owner = PendingOutputStop::from_pending(transaction, record.pending)?;
    if let Some(guard) = &owner.transfer_guard {
        guard.validate_stop_frontier(&receipt)?;
    }
    owner
        .require_current(&ObservedAt(&confirmed_at), fence)
        .await?;
    let now = clock.now();
    now.validate_shape()?;
    if now < confirmed_at {
        return Err(Error::BindingChanged.into());
    }
    fence().await?;
    let now = clock.now();
    now.validate_shape()?;
    if now < confirmed_at {
        return Err(Error::BindingChanged.into());
    }
    owner.transaction.require_current()?;
    if let Some(guard) = &owner.transfer_guard {
        guard.verify()?;
    }
    Ok(receipt)
}
