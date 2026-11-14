//! Original host owner accepts terminal execution only after native confirmation and receipt.
use super::transfer::wire::Incoming;
use super::*;
impl HostExecution<'_, '_, '_> {
    /// Receive, durably commit and obtain exact native confirmation on this original session.
    /// # Errors
    /// Any metadata/authority/output drift, interrupted transport or storage failure rejects.
    pub async fn receive_confirmed_execution(&mut self) -> Result<ExecutionReceipt, ClientError> {
        self.receive_and_commit().await?;
        self.confirm_source_completion().await
    }
    /// Send only this owner's durably committed receipts, then require both original base
    /// confirmation and the exact v4 source receipt. Caller DTOs cannot supply completion facts.
    /// # Errors
    /// No received transfer, repeat/interrupted attempt, lost authority, or changed binding rejects.
    pub async fn confirm_source_completion(&mut self) -> Result<ExecutionReceipt, ClientError> {
        if self.confirmation_started || self.received.is_none() {
            return Err(Error::BindingChanged.into());
        }
        self.confirmation_started = true;
        let cancel = self.bridge.cancellation.clone();
        let timeout = self.bridge.timeout;
        let result = tokio::select! {
            biased;
            ()=cancel.cancelled()=>Err(ClientError::WaitCancelled),
            result=tokio::time::timeout(timeout,Box::pin(self.confirm_source_completion_inner()))=>result.map_err(|_|ClientError::TimedOut)?,
        };
        if result.is_err() {
            self.bridge.send_interrupted = true;
        }
        result
    }
    async fn confirm_source_completion_inner(&mut self) -> Result<ExecutionReceipt, ClientError> {
        let received = self.received.clone().ok_or(Error::BindingChanged)?;
        let host_expiry = self
            .store
            .authorization(
                &self.binding.request.plan.intent.peer,
                &self.binding.request.plan.intent.destination.binding_id,
                Some(&self.binding.request.plan.authority_references.host),
                self.clock,
            )
            .await?
            .delegation
            .expires_at;

        self.require_current().await?;
        let transaction =
            OutputTransaction::open(self.store, &self.binding, || self.require_current()).await?;
        self.require_completion_evidence(&transaction, &received.receipts)?;
        for receipt in &received.receipts {
            let envelope = Envelope::new(Message::CommitReceipt(Box::new(receipt.clone())));
            let bytes = v4::canonical_json(&envelope)?;
            v4::decode_envelope(&bytes, self.bridge.negotiation)?;
            self.send_transfer_control_bytes(&transaction, &bytes, true)
                .await?;
        }
        let Incoming::Confirmation(job) = self.receive_base(&transaction).await? else {
            return Err(ClientError::UnexpectedMessage);
        };
        if job != self.binding.request.job_id {
            return Err(Error::BindingChanged.into());
        }
        let message = self
            .bridge
            .channel
            .receive_v4(self.bridge.negotiation)
            .await?
            .message;
        self.require_current().await?;
        transaction.require_current()?;
        let Message::ExecutionReceipt(receipt) = message else {
            return Err(ClientError::UnexpectedMessage);
        };
        v4::validate_execution_receipt(&receipt)?;
        let expected = expected_receipt(
            &self.binding,
            received.committed_partition_count,
            &received.frontier_sha256,
        )?;
        if *receipt != expected {
            return Err(Error::BindingChanged.into());
        }
        let completion = completion_document(&self.binding, &received.session_id, &expected);
        let completion_bytes = transaction
            .save_completion(&completion, || async {
                let root = self.require_current().await?;
                self.require_completion_evidence(&transaction, &received.receipts)?;
                Ok(root)
            })
            .await?;
        self.refresh_completion_guard(&transaction)?;
        self.pin_completed_transfer(&transaction, &completion_bytes)
            .await?;
        self.require_current().await?;
        self.require_completion_evidence(&transaction, &received.receipts)?;
        transaction.require_completion(&completion_bytes)?;
        // No await or file hashing follows the final cancellation/deadline sample.
        super::transfer::require_resume_lifetime(
            &self.binding,
            &host_expiry,
            self.clock,
            &self.bridge.cancellation,
        )?;
        Ok(*receipt)
    }
    fn require_completion_evidence(
        &self,
        transaction: &OutputTransaction,
        receipts: &[CommitReceipt],
    ) -> Result<(), ClientError> {
        transaction.require_committed_receipts(receipts)?;
        self.transfer_guard
            .as_ref()
            .ok_or(Error::BindingChanged)?
            .verify()?;
        let (destination, installed) = self.final_output.as_ref().ok_or(Error::BindingChanged)?;
        if installed != receipts {
            return Err(Error::BindingChanged.into());
        }
        for receipt in receipts {
            if destination
                .output_sha256(&receipt.relative_path.0)?
                .as_deref()
                != Some(&receipt.after_sha256.0)
            {
                return Err(Error::BindingChanged.into());
            }
        }
        Ok(())
    }
}

pub(super) fn expected_receipt(
    binding: &NativeBinding,
    partition_count: u64,
    frontier: &Digest,
) -> Result<ExecutionReceipt, ClientError> {
    let status = match binding.manifest.capture_status {
        v4::ArtifactManifestCaptureStatus::Complete => ExecutionReceiptStatus::Complete,
        v4::ArtifactManifestCaptureStatus::CompleteEmpty => ExecutionReceiptStatus::CompleteEmpty,
        v4::ArtifactManifestCaptureStatus::Partial => ExecutionReceiptStatus::Partial,
        _ => return Err(Error::BindingChanged.into()),
    };
    Ok(ExecutionReceipt {
        schema: v4::ExecutionReceiptSchema::HealthmdAgentExecutionReceipt,
        schema_version: 1,
        job_id: binding.request.job_id.clone(),
        binding: binding.accepted.binding.clone(),
        request_sha256: binding.manifest.request_sha256.clone(),
        manifest_sha256: document_digest(&binding.manifest)?,
        frontier_sha256: frontier.clone(),
        artifact_count: binding.manifest.artifacts.len() as u64,
        committed_partition_count: partition_count,
        source_acknowledged: true,
        status,
        expires_at: binding.accepted.expires_at.clone(),
    })
}

pub(super) fn completion_document(
    binding: &NativeBinding,
    session: &ControlUuid,
    receipt: &ExecutionReceipt,
) -> serde_json::Value {
    serde_json::json!({"schema":"healthmd.agent_host_completion","schema_version":1,
        "binding":binding,"session_id":session,"source_confirmation":binding.request.job_id,"receipt":receipt})
}
