//! Historical source facts only. No channel, new execution or destination authority is returned.
use super::*;

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SourceConfirmationAttempt {
    schema: String,
    schema_version: u64,
    host: ControlUuid,
    request: ExecuteRequest,
    request_sha256: Digest,
    started_at: UtcTimestamp,
    accepted_receipt: ExecutionReceipt,
    cancellation_request: v4::CancelRequest,
    source_receipt: ExecutionReceipt,
    source_confirmed_at: UtcTimestamp,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SignedSourceConfirmation {
    attempt: SourceConfirmationAttempt,
    mac: Digest,
}
struct ObservedAt<'a>(&'a UtcTimestamp);
impl PlanningClock for ObservedAt<'_> {
    fn now(&self) -> UtcTimestamp {
        self.0.clone()
    }
}

enum ConfirmationReader {
    Accepted,
    Output,
    Uncertain,
}
// Selection grants no authority. Every selected decoder independently authenticates its
// entire record and evidence, and an error never retries another decoder.
fn select_confirmation_reader(
    store: &HostAuthorityStore,
    job: &ControlUuid,
) -> Result<ConfirmationReader, ClientError> {
    let dir = store.directory()?;
    match dir.symlink_metadata(format!("output-{}.json", job.0)) {
        Ok(_) => return Ok(ConfirmationReader::Output),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(private::unavailable(error)),
    }
    let hint: serde_json::Value = private_json::decode(&private::read_private(
        &dir,
        &format!("attempt-{}.json", job.0),
        MAX_OUTPUT_BYTES,
    )?)?;
    Ok(
        if hint
            .pointer("/attempt/schema_version")
            .and_then(serde_json::Value::as_u64)
            == Some(10)
        {
            ConfirmationReader::Uncertain
        } else {
            ConfirmationReader::Accepted
        },
    )
}

pub(crate) async fn read_source_confirmation<F, Fut>(
    store: &HostAuthorityStore,
    job: &ControlUuid,
    clock: &dyn PlanningClock,
    mut fence: F,
) -> Result<ExecutionReceipt, ClientError>
where
    F: FnMut() -> Fut + Copy,
    Fut: std::future::Future<Output = Result<(), ClientError>>,
{
    job.validate_shape()?;
    // File presence selects a decoder only; it never establishes trusted state. Each selected reader
    // independently acquire the original lock and authenticate their complete evidence, then
    // recheck it after the final protected-key await. A raced/unsafe hint fails closed rather
    // than retrying a different format after authentication or binding failure.
    match select_confirmation_reader(store, job)? {
        ConfirmationReader::Output => {
            return later_stop::read_confirmed_output_stop(store, job, clock, fence).await;
        }
        ConfirmationReader::Uncertain => {
            return uncertain_stop::read_confirmed(store, job, clock, fence).await;
        }
        ConfirmationReader::Accepted => {}
    }
    let key = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
    let dir = store.directory()?;
    let lock = private::open_private(&dir, OUTPUT_LOCK, true, false)?;
    lock.try_lock_exclusive()
        .map_err(|_| ClientError::AgentStoreBusy)?;
    require_absent_job(&dir, job, false)?;
    let name = format!("attempt-{}.json", job.0);
    let bytes = private::read_private(&dir, &name, MAX_OUTPUT_BYTES)?;
    let saved: SignedSourceConfirmation = private_json::decode(&bytes)?;
    saved.mac.validate_shape()?;
    let attempt = &saved.attempt;
    attempt.request.validate_shape()?;
    attempt.started_at.validate_shape()?;
    attempt.source_confirmed_at.validate_shape()?;
    let now = clock.now();
    now.validate_shape()?;
    if attempt.schema != "healthmd.agent_host_execution_attempt"
        || attempt.schema_version != 4
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
        || attempt.started_at > attempt.source_confirmed_at
        || attempt.source_confirmed_at > now
        || attempt.cancellation_request != execution_cancel_request(&attempt.request)?
    {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    // Historical inspection deliberately uses the authenticated observation, never a renewed
    // lifetime or current export grant. The resulting receipt cannot become an active owner.
    validate_accepted(
        &attempt.request,
        &attempt.accepted_receipt,
        &ObservedAt(&attempt.source_confirmed_at),
    )?;
    validate_source_stop_receipt(
        &attempt.request,
        &attempt.accepted_receipt,
        &attempt.source_receipt,
    )?;
    let expected = execution_attempt_bytes(
        &store.host,
        &attempt.request,
        &attempt.started_at,
        Some(&attempt.accepted_receipt),
        Some(&attempt.cancellation_request),
        Some((&attempt.source_receipt, &attempt.source_confirmed_at)),
        &key,
    )?;
    let expected: SignedSourceConfirmation = private_json::decode(&expected)?;
    if !healthmd_protocol::crypto::constant_time_equal(
        saved.mac.0.as_bytes(),
        expected.mac.0.as_bytes(),
    ) {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    // The protected reader can delay or call back into external code. Recheck the original
    // key and every local evidence identity after that last await before returning any facts.
    let current = key_bytes(&store.protected_key.load_existing(&store.host).await?)?;
    if !healthmd_protocol::crypto::constant_time_equal(key.expose_secret(), current.expose_secret())
    {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    let now = clock.now();
    now.validate_shape()?;
    if attempt.source_confirmed_at > now {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    // The caller fence follows the final key/time callback while this reader still owns
    // the original lock and exact authenticated local evidence. No await follows it.
    fence().await?;
    let now = clock.now();
    now.validate_shape()?;
    if attempt.source_confirmed_at > now {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    store.directory()?;
    private::require_named_file(&dir, OUTPUT_LOCK, &lock)?;
    require_absent_job(&dir, job, false)?;
    if private::read_private(&dir, &name, MAX_OUTPUT_BYTES)? != bytes {
        return Err(Error::BindingChanged.into());
    }
    Ok(saved.attempt.source_receipt)
}
