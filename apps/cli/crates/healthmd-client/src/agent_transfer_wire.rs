//! Bridge adaptation of deployed base controls. No new base fields or discriminators.
use super::*;
use crate::secure_channel::AgentPayload;
use healthmd_protocol::{
    encoding::SwiftUuid,
    models as apple, v2,
    wire::{DirectMessage, Unlabeled},
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub(in crate::agent_bridge::execution) struct Session(pub v2::TransferSession);
#[derive(Clone, Debug)]
pub(in crate::agent_bridge::execution) enum Incoming {
    Session(Session),
    Manifest {
        id: ControlUuid,
        path: String,
        bytes: u64,
        sha256: String,
        mode: v2::FileWriteMode,
        android: Option<v2::ArtifactManifest>,
    },
    Open {
        session: Session,
        partition: v2::TransferPartition,
        apple_segment: Option<apple::TransferItemSegment>,
    },
    Chunk(apple::TransferChunk),
    Complete(v2::TransferPartitionComplete),
    Finalize(v2::TransferFinalize),
    Confirmation(ControlUuid),
}
pub(in crate::agent_bridge::execution) enum Response {
    Disposition(v2::TransferDisposition),
    Chunk(v2::TransferChunkAcknowledgement),
    Partition(v2::TransferPartitionAcknowledgement),
    Final(v2::TransferFinalAcknowledgement),
}
fn number(value: i64) -> Result<u64, ClientError> {
    value.try_into().map_err(|_| Error::BindingChanged.into())
}
fn session(value: apple::TransferSession) -> Result<Session, ClientError> {
    if value.protocol_version != 1 || value.request_fingerprint.version != 1 {
        return Err(Error::BindingChanged.into());
    }
    Ok(Session(v2::TransferSession {
        session_id: value.session_id.0,
        job_id: value.job_id.0,
        request_fingerprint: value.request_fingerprint.sha256,
        peer_binding: v2::PeerBinding {
            source_installation_id: value.peer_binding.source_installation_id.0,
            destination_installation_id: value.peer_binding.destination_installation_id.0,
        },
        partition_target_bytes: number(value.partition_target_bytes)?,
        created_at: value.created_at,
    }))
}
fn mode(value: apple::FileWriteMode) -> v2::FileWriteMode {
    match value {
        apple::FileWriteMode::Overwrite => v2::FileWriteMode::Overwrite,
        apple::FileWriteMode::Append => v2::FileWriteMode::Append,
        apple::FileWriteMode::MergeMarkdown => v2::FileWriteMode::MergeMarkdown,
        apple::FileWriteMode::MergeMarkdownPreservingPreamble => {
            v2::FileWriteMode::MergeMarkdownPreservingPreamble
        }
    }
}
impl HostExecution<'_, '_, '_> {
    // Both deployed closed-envelope adaptations stay explicit at this boundary.
    #[allow(clippy::too_many_lines)]
    pub(in crate::agent_bridge::execution) async fn receive_base(
        &mut self,
        transaction: &OutputTransaction,
    ) -> Result<Incoming, ClientError> {
        self.require_current().await?;
        transaction.require_current()?;
        let payload = self
            .bridge
            .channel
            .receive_agent_payload(self.bridge.negotiation)
            .await?;
        let message = decode_base_payload(payload, &self.binding)?;
        self.require_current().await?;
        transaction.require_current()?;
        Ok(message)
    }
    // Both base schemas are mapped field-for-field before the common guarded write.
    pub(super) async fn send_base(
        &mut self,
        transaction: &OutputTransaction,
        response: Response,
    ) -> Result<(), ClientError> {
        let durable_ack = matches!(&response, Response::Partition(_) | Response::Final(_));
        let plaintext = encode_base_response(&self.binding, response)?;
        self.send_transfer_control_bytes(transaction, &plaintext, durable_ack)
            .await
    }
    pub(in crate::agent_bridge::execution) async fn send_transfer_control_bytes(
        &mut self,
        transaction: &OutputTransaction,
        plaintext: &[u8],
        durable_ack: bool,
    ) -> Result<(), ClientError> {
        let transfer_guard = &self.transfer_guard;
        let final_output = &self.final_output;
        let store = self.store;
        let clock = self.clock;
        let request = &self.binding.request;
        let expires = &self.binding.accepted.expires_at;
        let trust = self.bridge.trust_fence;
        let expected = &self.bridge.expected_trust;
        let selected = self.bridge.requested_device;
        let cancellation = &self.bridge.cancellation;
        self.bridge
            .channel
            .send_bridge_plaintext_guarded(plaintext, || async {
                store
                    .require_output_current(request, Some(expires), clock, || async {
                        if cancellation.is_cancelled() {
                            return Err(ClientError::WaitCancelled);
                        }
                        trust.require_current(selected, expected).await?;
                        if cancellation.is_cancelled() {
                            return Err(ClientError::WaitCancelled);
                        }
                        Ok(())
                    })
                    .await?;
                transaction.require_current()?;
                if durable_ack {
                    transfer_guard
                        .as_ref()
                        .ok_or(Error::BindingChanged)?
                        .verify()?;
                }
                if let Some((destination, receipts)) = final_output {
                    for receipt in receipts {
                        if destination
                            .output_sha256(&receipt.relative_path.0)?
                            .as_deref()
                            != Some(&receipt.after_sha256.0)
                        {
                            return Err(Error::BindingChanged.into());
                        }
                    }
                }
                if cancellation.is_cancelled() || expires <= &clock.now() {
                    return Err(Error::BindingChanged.into());
                }
                Ok(())
            })
            .await
    }
}

pub(in crate::agent_bridge::execution) fn decode_base_payload(
    payload: AgentPayload,
    binding: &NativeBinding,
) -> Result<Incoming, ClientError> {
    let message = if binding.request.plan.intent.peer.platform == v4::PeerPlatform::Apple {
        match payload {
            AgentPayload::BinaryTransferFrame(bytes) => Incoming::Chunk(
                healthmd_protocol::transfer::decode_binary_chunk(&bytes)
                    .map_err(|_| Error::BindingChanged)?,
            ),
            AgentPayload::Apple(message) => decode_apple_message(*message, binding)?,
            _ => return Err(ClientError::UnexpectedMessage),
        }
    } else {
        match payload {
            AgentPayload::BinaryTransferFrame(bytes) => Incoming::Chunk(
                healthmd_protocol::transfer::decode_binary_chunk(&bytes)
                    .map_err(|_| Error::BindingChanged)?,
            ),
            AgentPayload::Android(message) => match message.message {
                v2::Message::TransferSession(value) => Incoming::Session(Session(value)),
                v2::Message::ArtifactManifest(value) => {
                    if value.job_id.to_string() != binding.request.job_id.0 {
                        return Err(Error::BindingChanged.into());
                    }
                    Incoming::Manifest {
                        id: ControlUuid(value.artifact_id.to_string()),
                        path: value.relative_path.clone().ok_or(Error::BindingChanged)?,
                        bytes: value.byte_count,
                        sha256: value.sha256.clone(),
                        mode: value.write_mode.ok_or(Error::BindingChanged)?,
                        android: Some(value),
                    }
                }
                v2::Message::TransferOpen(value) => Incoming::Open {
                    session: Session(value.session),
                    partition: value.partition,
                    apple_segment: None,
                },
                v2::Message::TransferPartitionComplete(value) => Incoming::Complete(value),
                v2::Message::TransferFinalize(value) => Incoming::Finalize(value),
                v2::Message::CompletionConfirmed(value) => {
                    Incoming::Confirmation(ControlUuid(value.job_id.to_string()))
                }
                _ => return Err(ClientError::UnexpectedMessage),
            },
            _ => return Err(ClientError::UnexpectedMessage),
        }
    };
    Ok(message)
}

fn decode_apple_message(
    message: DirectMessage,
    binding: &NativeBinding,
) -> Result<Incoming, ClientError> {
    Ok(match message {
        DirectMessage::TransferSession(Unlabeled { value }) => Incoming::Session(session(value)?),
        DirectMessage::FileManifest(Unlabeled { value }) => {
            if value.job_id.0.to_string() != binding.request.job_id.0 {
                return Err(Error::BindingChanged.into());
            }
            Incoming::Manifest {
                id: ControlUuid(value.file_id.0.to_string()),
                path: value.relative_path,
                bytes: number(value.byte_count)?,
                sha256: value.sha256,
                mode: mode(value.write_mode),
                android: None,
            }
        }
        DirectMessage::TransferOpen(Unlabeled { value }) => {
            let segment = value.partition.item_segment.ok_or(Error::BindingChanged)?;
            let id = ControlUuid(segment.item_id.clone());
            id.validate_shape()?;
            if value.partition.source_dates != [segment.item_id.clone()] {
                return Err(Error::BindingChanged.into());
            }
            Incoming::Open {
                session: session(value.session)?,
                partition: v2::TransferPartition {
                    index: number(value.partition.index)?,
                    transfer_id: value.partition.transfer_id.0,
                    artifact_id: Uuid::parse_str(&id.0).map_err(private::unavailable)?,
                    artifact_offset: number(segment.offset)?,
                    byte_count: number(value.partition.byte_count)?,
                    chunk_count: number(value.partition.chunk_count)?,
                    sha256: value.partition.sha256,
                    previous_sha256: value.partition.previous_sha256,
                },
                apple_segment: Some(segment),
            }
        }
        DirectMessage::TransferPartitionComplete(Unlabeled { value }) => {
            Incoming::Complete(v2::TransferPartitionComplete {
                session_id: value.session_id.0,
                job_id: value.job_id.0,
                partition_index: number(value.partition_index)?,
                transfer_id: value.transfer_id.0,
                partition_sha256: value.partition_sha256,
            })
        }
        DirectMessage::CompletionConfirmed(value) => {
            Incoming::Confirmation(ControlUuid(value.job_id.0.to_string()))
        }
        DirectMessage::TransferFinalize(Unlabeled { value }) => {
            if value.request_fingerprint.version != 1 {
                return Err(Error::BindingChanged.into());
            }
            Incoming::Finalize(v2::TransferFinalize {
                session_id: value.session_id.0,
                job_id: value.job_id.0,
                request_fingerprint: value.request_fingerprint.sha256,
                total_partitions: number(value.total_partitions)?,
                total_bytes: number(value.total_bytes)?,
                final_partition_sha256: value.final_partition_sha256,
            })
        }
        _ => return Err(ClientError::UnexpectedMessage),
    })
}

pub(in crate::agent_bridge::execution) fn encode_base_response(
    binding: &NativeBinding,
    response: Response,
) -> Result<Vec<u8>, ClientError> {
    let plaintext = if binding.request.plan.intent.peer.platform == v4::PeerPlatform::Apple {
        let message = match response {
            Response::Disposition(v) => {
                DirectMessage::TransferDisposition(Unlabeled::from(apple::TransferDisposition {
                    session_id: SwiftUuid(v.session_id),
                    job_id: SwiftUuid(v.job_id),
                    partition_index: v.partition_index.try_into().map_err(private::unavailable)?,
                    partition_sha256: v.partition_sha256,
                    disposition: match v.disposition {
                        v2::TransferDispositionKind::Needed => {
                            apple::TransferDispositionKind::Needed
                        }
                        v2::TransferDispositionKind::AlreadyCommitted => {
                            apple::TransferDispositionKind::AlreadyCommitted
                        }
                        v2::TransferDispositionKind::Rejected => {
                            apple::TransferDispositionKind::Rejected
                        }
                    },
                    message: None,
                }))
            }
            Response::Chunk(v) => DirectMessage::TransferChunkAcknowledgement(Unlabeled::from(
                apple::TransferChunkAcknowledgement {
                    transfer_id: SwiftUuid(v.transfer_id),
                    sequence: i64::from(v.sequence),
                    accepted: v.accepted,
                    sha256: v.sha256,
                    message: None,
                },
            )),
            Response::Partition(v) => DirectMessage::TransferPartitionAcknowledgement(
                Unlabeled::from(apple::TransferPartitionAcknowledgement {
                    session_id: SwiftUuid(v.session_id),
                    job_id: SwiftUuid(v.job_id),
                    partition_index: v.partition_index.try_into().map_err(private::unavailable)?,
                    transfer_id: SwiftUuid(v.transfer_id),
                    partition_sha256: v.partition_sha256,
                    accepted: v.accepted,
                    message: None,
                }),
            ),
            Response::Final(v) => DirectMessage::TransferFinalAcknowledgement(Unlabeled::from(
                apple::TransferFinalAcknowledgement {
                    session_id: SwiftUuid(v.session_id),
                    job_id: SwiftUuid(v.job_id),
                    accepted: v.accepted,
                    total_partitions: v
                        .total_partitions
                        .try_into()
                        .map_err(private::unavailable)?,
                    total_bytes: v.total_bytes.try_into().map_err(private::unavailable)?,
                    final_partition_sha256: v.final_partition_sha256,
                    response_byte_count: None,
                    response_sha256: None,
                    message: None,
                },
            )),
        };
        healthmd_protocol::encoding::canonical_json(&message).map_err(private::unavailable)?
    } else {
        let message = match response {
            Response::Disposition(v) => v2::Message::TransferDisposition(v),
            Response::Chunk(v) => v2::Message::TransferChunkAcknowledgement(v),
            Response::Partition(v) => v2::Message::TransferPartitionAcknowledgement(v),
            Response::Final(v) => v2::Message::TransferFinalAcknowledgement(v),
        };
        healthmd_protocol::encoding::canonical_json(&v2::Envelope::new(message))
            .map_err(private::unavailable)?
    };
    Ok(plaintext)
}
