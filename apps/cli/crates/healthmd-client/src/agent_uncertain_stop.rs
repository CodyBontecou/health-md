//! Stop-only intent recovery. No accepted owner, export grant or destination is reconstructed.
use super::*;

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct StopAttempt {
    schema: String,
    schema_version: u64,
    host: ControlUuid,
    request: ExecuteRequest,
    request_sha256: Digest,
    started_at: UtcTimestamp,
    cancellation_request: v4::CancelRequest,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_receipt: Option<ExecutionReceipt>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_confirmed_at: Option<UtcTimestamp>,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SignedStop {
    attempt: StopAttempt,
    mac: Digest,
}

fn bytes(
    host: &ControlUuid,
    request: &ExecuteRequest,
    started: &UtcTimestamp,
    confirmation: Option<(&ExecutionReceipt, &UtcTimestamp)>,
    key: &SecretBox<[u8; 32]>,
) -> Result<Vec<u8>, ClientError> {
    let attempt = StopAttempt {
        schema: "healthmd.agent_host_execution_attempt".into(),
        schema_version: if confirmation.is_some() { 10 } else { 9 },
        host: host.clone(),
        request: request.clone(),
        request_sha256: v4::document_digest(request)?,
        started_at: started.clone(),
        cancellation_request: execution_cancel_request(request)?,
        source_receipt: confirmation.map(|(receipt, _)| receipt.clone()),
        source_confirmed_at: confirmation.map(|(_, observed)| observed.clone()),
    };
    let mut signer =
        Hmac::<Sha256>::new_from_slice(key.expose_secret()).map_err(private::unavailable)?;
    signer.update(if confirmation.is_some() {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v10\0"
    } else {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v9\0"
    });
    signer.update(&private_json::encode(&attempt)?);
    let mut mac = String::with_capacity(64);
    for byte in signer.finalize().into_bytes() {
        write!(&mut mac, "{byte:02x}").map_err(private::unavailable)?;
    }
    let mac = Digest(mac);
    let bytes = private_json::encode(&SignedStop { attempt, mac })?;
    if bytes.len() > MAX_OUTPUT_BYTES {
        return Err(ClientError::AgentStoreFull);
    }
    Ok(bytes)
}

pub(super) fn pending_bytes(
    host: &ControlUuid,
    request: &ExecuteRequest,
    started: &UtcTimestamp,
    key: &SecretBox<[u8; 32]>,
) -> Result<Vec<u8>, ClientError> {
    bytes(host, request, started, None, key)
}

/// The upper bound limits uncertain lookup only. It never becomes an accepted job expiry.
fn observation_expiry(request: &ExecuteRequest) -> Result<UtcTimestamp, ClientError> {
    let seconds = request
        .plan
        .expires_at
        .seconds()?
        .checked_add(604_800)
        .ok_or(Error::BindingChanged)?;
    let date = chrono::DateTime::from_timestamp(seconds, 0).ok_or(Error::BindingChanged)?;
    Ok(UtcTimestamp(
        date.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
    ))
}
fn lifetime(
    request: &ExecuteRequest,
    started: &UtcTimestamp,
    now: &UtcTimestamp,
) -> Result<(), ClientError> {
    now.validate_shape()?;
    if now < started || *now >= observation_expiry(request)? {
        return Err(Error::BindingChanged.into());
    }
    Ok(())
}
fn terminal(
    request: &ExecuteRequest,
    started: &UtcTimestamp,
    receipt: &ExecutionReceipt,
    observed: &UtcTimestamp,
) -> Result<(), ClientError> {
    validate_source_stop_identity(request, receipt)?;
    lifetime(request, started, observed)?;
    // Only the authenticated source supplies its real lifetime. Reject stale or renewed facts.
    if receipt.expires_at <= *observed
        || receipt.expires_at > observation_expiry(request)?
        || receipt.expires_at.seconds()? > observed.seconds()?.saturating_add(604_800)
    {
        return Err(Error::BindingChanged.into());
    }
    Ok(())
}

pub(crate) struct UncertainStop {
    admission: OutputAdmission,
    cancellation: tokio_util::sync::CancellationToken,
}
impl UncertainStop {
    pub(crate) async fn prepare<F, Fut>(
        store: &HostAuthorityStore,
        peer: &Peer,
        job: &ControlUuid,
        clock: &dyn PlanningClock,
        cancellation: &tokio_util::sync::CancellationToken,
        fence: F,
    ) -> Result<Self, ClientError>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        if cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        let admission = OutputAdmission::open_retained_attempt(
            store,
            job,
            clock,
            RetainedAttemptPurpose::UncertainStop,
        )
        .await?;
        if admission.request.plan.intent.peer != *peer {
            return Err(Error::BindingChanged.into());
        }
        let mut owner = Self {
            admission,
            cancellation: cancellation.clone(),
        };
        owner.require_current(clock, fence).await?;
        if owner.admission.cancellation.is_none() {
            let bytes = pending_bytes(
                &store.host,
                &owner.admission.request,
                &owner.admission.started_at,
                &owner.admission.key,
            )?;
            owner.admission.reserve_attempt_replacement(bytes.len())?;
            private::publish(
                &owner.admission.dir,
                &owner.admission.attempt_name,
                &bytes,
                false,
                || async { owner.require_current(clock, fence).await },
            )
            .await?;
            owner.admission.attempt_bytes = bytes;
            owner.admission.cancellation =
                Some(execution_cancel_request(&owner.admission.request)?);
        }
        owner.require_current(clock, fence).await?;
        Ok(owner)
    }
    pub(crate) fn request(&self) -> Result<v4::CancelRequest, ClientError> {
        self.admission
            .cancellation
            .clone()
            .ok_or(Error::BindingChanged.into())
    }
    pub(crate) async fn require_current<F, Fut>(
        &self,
        clock: &dyn PlanningClock,
        mut fence: F,
    ) -> Result<(), ClientError>
    where
        F: FnMut() -> Fut + Copy,
        Fut: std::future::Future<Output = Result<(), ClientError>>,
    {
        if self.admission.accepted.is_some() || self.admission.source_confirmed {
            return Err(Error::BindingChanged.into());
        }
        lifetime(
            &self.admission.request,
            &self.admission.started_at,
            &clock.now(),
        )?;
        self.admission.require_current()?;
        fence().await?;
        let key = key_bytes(
            &self
                .admission
                .store
                .protected_key
                .load_existing(&self.admission.store.host)
                .await?,
        )?;
        if !healthmd_protocol::crypto::constant_time_equal(
            key.expose_secret(),
            self.admission.key.expose_secret(),
        ) {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
        lifetime(
            &self.admission.request,
            &self.admission.started_at,
            &clock.now(),
        )?;
        if self.cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        self.admission.require_current()
    }
    pub(crate) async fn confirm<F, Fut>(
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
        self.require_current(clock, fence).await?;
        let observed = clock.now();
        terminal(
            &self.admission.request,
            &self.admission.started_at,
            receipt,
            &observed,
        )?;
        let bytes = bytes(
            &self.admission.store.host,
            &self.admission.request,
            &self.admission.started_at,
            Some((receipt, &observed)),
            &self.admission.key,
        )?;
        self.admission.reserve_attempt_replacement(bytes.len())?;
        private::publish(
            &self.admission.dir,
            &self.admission.attempt_name,
            &bytes,
            false,
            || async {
                self.require_current(clock, fence).await?;
                let now = clock.now();
                terminal(
                    &self.admission.request,
                    &self.admission.started_at,
                    receipt,
                    &now,
                )?;
                if now < observed {
                    return Err(Error::BindingChanged.into());
                }
                if cancellation.is_cancelled() {
                    return Err(ClientError::WaitCancelled);
                }
                self.admission.require_current()
            },
        )
        .await?;
        self.admission.attempt_bytes = bytes;
        self.admission.source_confirmed = true;
        // Confirmation is historical source state only. It cannot be reopened as an export owner.
        if cancellation.is_cancelled() {
            return Err(ClientError::WaitCancelled);
        }
        self.admission.require_current()
    }
}

pub(super) async fn read_confirmed<F, Fut>(
    store: &HostAuthorityStore,
    job: &ControlUuid,
    clock: &dyn PlanningClock,
    mut fence: F,
) -> Result<ExecutionReceipt, ClientError>
where
    F: FnMut() -> Fut + Copy,
    Fut: std::future::Future<Output = Result<(), ClientError>>,
{
    let key = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
    let dir = store.directory()?;
    let lock = private::open_private(&dir, OUTPUT_LOCK, true, false)?;
    lock.try_lock_exclusive()
        .map_err(|_| ClientError::AgentStoreBusy)?;
    require_absent_job(&dir, job, false)?;
    let name = format!("attempt-{}.json", job.0);
    let original = private::read_private(&dir, &name, MAX_OUTPUT_BYTES)?;
    let saved: SignedStop = private_json::decode(&original)?;
    let attempt = &saved.attempt;
    saved.mac.validate_shape()?;
    attempt.request.validate_shape()?;
    attempt.started_at.validate_shape()?;
    let observed = attempt
        .source_confirmed_at
        .as_ref()
        .ok_or(Error::BindingChanged)?;
    let receipt = attempt
        .source_receipt
        .as_ref()
        .ok_or(Error::BindingChanged)?;
    observed.validate_shape()?;
    if attempt.schema != "healthmd.agent_host_execution_attempt"
        || attempt.schema_version != 10
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
        || attempt.cancellation_request != execution_cancel_request(&attempt.request)?
    {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    terminal(&attempt.request, &attempt.started_at, receipt, observed)?;
    let expected: SignedStop = private_json::decode(&bytes(
        &store.host,
        &attempt.request,
        &attempt.started_at,
        Some((receipt, observed)),
        &key,
    )?)?;
    if !healthmd_protocol::crypto::constant_time_equal(
        saved.mac.0.as_bytes(),
        expected.mac.0.as_bytes(),
    ) {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    let current = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
    if !healthmd_protocol::crypto::constant_time_equal(key.expose_secret(), current.expose_secret())
    {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    fence().await?;
    let now = clock.now();
    now.validate_shape()?;
    if *observed > now {
        return Err(Error::BindingChanged.into());
    }
    store.directory()?;
    private::require_named_file(&dir, OUTPUT_LOCK, &lock)?;
    require_absent_job(&dir, job, false)?;
    if private::read_private(&dir, &name, MAX_OUTPUT_BYTES)? != original {
        return Err(Error::BindingChanged.into());
    }
    Ok(receipt.clone())
}
