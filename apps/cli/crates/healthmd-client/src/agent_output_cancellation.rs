//! The original output owner can Stop without renewing its revoked export grant.
use super::*;
use crate::agent_host::output::PendingOutputStop;
use crate::secure_channel::AgentPayload;
#[path = "agent_output_cancel_prelude.rs"]
mod prelude;

/// Durable output Stop intent on its original authenticated source channel.
/// Dropping it abandons that channel and retains pending intent, never terminal proof.
pub struct HostPendingOutputCancellation<'s, 'h, 'trust> {
    owner: HostExecution<'s, 'h, 'trust>,
    pending: PendingOutputStop,
}
impl<'s, 'h, 'trust> HostExecution<'s, 'h, 'trust> {
    /// Request Stop after the manifest and before receiving any transfer data.
    /// # Errors
    /// Started/resumed transfer, changed original evidence, lost trust/key, expiry,
    /// cancellation or uncertain transmission rejects without source completion.
    pub async fn request_cancellation(
        self,
    ) -> Result<HostPendingOutputCancellation<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.bridge.cancellation.clone();
        let timeout = self.bridge.timeout;
        tokio::select! { biased;
            ()=cancellation.cancelled()=>Err(ClientError::WaitCancelled),
            result=tokio::time::timeout(timeout,Box::pin(self.request_output_cancellation_inner()))=>result.map_err(|_|ClientError::TimedOut)?,
        }
    }
    async fn request_output_cancellation_inner(
        self,
    ) -> Result<HostPendingOutputCancellation<'s, 'h, 'trust>, ClientError> {
        if self.transfer_started
            || self.resumed.is_some()
            || self.received.is_some()
            || self.confirmation_started
            || self.transfer_guard.is_some()
            || self.final_output.is_some()
            || self.bridge.send_interrupted
            || self.bridge.peer != self.binding.request.plan.intent.peer
        {
            return Err(Error::BindingChanged.into());
        }
        // Any failed/dropped send leaves this channel unavailable for unrelated work.
        self.bridge.send_interrupted = true;
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
        fence().await?;
        let transaction =
            OutputTransaction::open_retained(self.store, &self.binding.request.job_id).await?;
        if transaction.binding() != &self.binding {
            return Err(Error::BindingChanged.into());
        }
        let pending = Box::pin(PendingOutputStop::prepare(transaction, self.clock, fence)).await?;
        self.bridge
            .channel
            .send_v4_guarded(
                &Envelope::new(Message::CancelRequest(Box::new(pending.request().clone()))),
                self.bridge.negotiation,
                || pending.require_current(self.clock, fence),
            )
            .await?;
        pending.require_current(self.clock, fence).await?;
        Ok(HostPendingOutputCancellation {
            owner: self,
            pending,
        })
    }
}
impl HostPendingOutputCancellation<'_, '_, '_> {
    #[must_use]
    pub fn request(&self) -> &v4::CancelRequest {
        self.pending.request()
    }
    /// Await exact source confirmation, validating only the native's bounded queued metadata.
    /// # Errors
    /// Unrelated or reordered controls, data, invalid receipt, changed evidence/trust/key,
    /// expiry or interruption leave no returned terminal proof and send no transfer ACK.
    pub async fn wait_source_confirmation(self) -> Result<SourceStopConfirmation, ClientError> {
        let cancellation = self.owner.bridge.cancellation.clone();
        let timeout = self.owner.bridge.timeout;
        tokio::select! { biased;
            ()=cancellation.cancelled()=>Err(ClientError::WaitCancelled),
            result=tokio::time::timeout(timeout,Box::pin(self.wait_inner()))=>result.map_err(|_|ClientError::TimedOut)?,
        }
    }
    async fn wait_inner(self) -> Result<SourceStopConfirmation, ClientError> {
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
        let mut prelude = prelude::Prelude::default();
        loop {
            self.pending
                .require_current(self.owner.clock, fence)
                .await?;
            let payload = self
                .owner
                .bridge
                .channel
                .receive_agent_payload(self.owner.bridge.negotiation)
                .await?;
            self.pending
                .require_current(self.owner.clock, fence)
                .await?;
            if let AgentPayload::Agent(envelope) = payload {
                let Message::ExecutionReceipt(receipt) = envelope.message else {
                    return Err(ClientError::UnexpectedMessage);
                };
                let receipt = self
                    .pending
                    .confirm(&receipt, self.owner.clock, cancellation, fence)
                    .await?;
                return Ok(SourceStopConfirmation { receipt });
            }
            if matches!(payload, AgentPayload::BinaryTransferFrame(_)) {
                return Err(ClientError::UnexpectedMessage);
            }
            let message = transfer::wire::decode_base_payload(payload, &self.owner.binding)?;
            prelude.accept(&self.owner.binding, message)?;
        }
    }
}

impl<'trust> BridgeSession<'trust> {
    /// Replay only the original durable output Stop on a newly authenticated channel.
    /// No Execute, Resume, replacement binding or fresh export grant is admitted.
    /// # Errors
    /// Missing/pending-incompatible evidence, wrong peer, stale trust/key, original expiry,
    /// local cancellation or transmission uncertainty reject without terminal proof.
    pub async fn request_retained_output_cancellation<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        job: &ControlUuid,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostPendingOutputCancellation<'s, 'h, 'trust>, ClientError> {
        let cancellation = self.cancellation.clone();
        let timeout = self.timeout;
        tokio::select! { biased;
            ()=cancellation.cancelled()=>Err(ClientError::WaitCancelled),
            result=tokio::time::timeout(timeout,Box::pin(self.retained_output_stop_inner(store,job,clock)))=>result.map_err(|_|ClientError::TimedOut)?,
        }
    }
    async fn retained_output_stop_inner<'s, 'h>(
        &'s mut self,
        store: &'h HostAuthorityStore,
        job: &ControlUuid,
        clock: &'h dyn PlanningClock,
    ) -> Result<HostPendingOutputCancellation<'s, 'h, 'trust>, ClientError> {
        if self.send_interrupted {
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
        let pending = PendingOutputStop::open_retained(store, job, clock, fence).await?;
        let binding = pending.binding().clone();
        if self.peer != binding.request.plan.intent.peer {
            return Err(Error::BindingChanged.into());
        }
        self.channel
            .send_v4_guarded(
                &Envelope::new(Message::CancelRequest(Box::new(pending.request().clone()))),
                self.negotiation,
                || pending.require_current(clock, fence),
            )
            .await?;
        pending.require_current(clock, fence).await?;
        let owner = HostExecution {
            bridge: self,
            store,
            clock,
            binding,
            transfer_started: false,
            resumed: None,
            received: None,
            confirmation_started: false,
            transfer_guard: None,
            final_output: None,
        };
        Ok(HostPendingOutputCancellation { owner, pending })
    }
}
