//! Separate bridge connection path. Old connections/advertisements/highest-version dispatch
//! remain untouched. Existing authentication runs against a frozen read-only trust snapshot.
use std::time::Duration;

use async_trait::async_trait;
use healthmd_protocol::{
    encoding::SwiftUuid,
    v4::{
        self, Approval, ApprovalRequest, ControlUuid, Discovery, DiscoveryRequest,
        DiscoveryRequestSchema, Envelope, Error, ExportPlan, Message, Negotiation, Peer,
        PeerPlatform, PlanRequest,
    },
    wire::{DirectMessage, PeerCapabilities, PeerPlatform as WirePlatform, Unlabeled},
};
use secrecy::{ExposeSecret as _, SecretString};
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;

use crate::agent_planning::PlanningSource;
use crate::{
    ClientError,
    credentials::CredentialStore,
    handshake,
    packet::PacketConnection,
    secure_channel::{SecureChannel, SecurePayload},
    trust::{TrustState, TrustStore, TrustedClient},
};

#[async_trait]
pub(crate) trait CurrentBridgeTrust: Send + Sync {
    async fn require_current(
        &self,
        requested: Option<uuid::Uuid>,
        expected: &TrustedClient,
    ) -> Result<(), ClientError>;
}

pub struct BridgeSession<'a> {
    channel: SecureChannel,
    trust_fence: &'a dyn CurrentBridgeTrust,
    expected_trust: TrustedClient,
    requested_device: Option<uuid::Uuid>,
    peer: Peer,
    negotiation: Negotiation,
    timeout: Duration,
    cancellation: CancellationToken,
    send_interrupted: bool,
}

/// Never forwards a credential mutation. The unchanged reconnect handshake's metadata-only
/// save is verified against exactly the preexisting trust snapshot, then discarded. Unknown
/// records/keys, new pairing, platform/wake/trust changes and deletes always reject.
struct FrozenReconnectTrust(TrustState);
#[async_trait]
impl CredentialStore for FrozenReconnectTrust {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        if account != "trust-state-v1" {
            return Err(ClientError::InvalidTrustState);
        }
        Ok(Some(SecretString::from(
            serde_json::to_string(&self.0).map_err(|_| ClientError::InvalidTrustState)?,
        )))
    }
    async fn set(&self, account: &str, secret: SecretString) -> Result<(), ClientError> {
        if account != "trust-state-v1" {
            return Err(ClientError::InvalidTrustState);
        }
        let mut proposed: TrustState = serde_json::from_slice(secret.expose_secret().as_bytes())
            .map_err(|_| ClientError::InvalidTrustState)?;
        if proposed.trusted_clients.len() != self.0.trusted_clients.len() {
            return Err(ClientError::InvalidTrustState);
        }
        for row in &mut proposed.trusted_clients {
            let original = self
                .0
                .client(row.installation_id.0)
                .ok_or(ClientError::InvalidTrustState)?;
            // These timestamps are copied by the unchanged handler, not remote input.
            // Discard only metadata/binary64 re-encoding drift; never change native trust.
            row.last_connected_at = original.last_connected_at;
            row.paired_at = original.paired_at;
            if let (Some(proposed), Some(original)) = (&mut row.wake, &original.wake) {
                proposed.enrolled_at = original.enrolled_at;
            }
        }
        proposed
            .trusted_clients
            .sort_by_key(|r| r.installation_id.0);
        let mut original = self.0.clone();
        original
            .trusted_clients
            .sort_by_key(|r| r.installation_id.0);
        if proposed != original {
            return Err(ClientError::InvalidTrustState);
        }
        Ok(())
    }
    async fn delete(&self, _: &str) -> Result<(), ClientError> {
        Err(ClientError::InvalidTrustState)
    }
}

impl<'a> BridgeSession<'a> {
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn accept(
        listener: &TcpListener,
        host: SwiftUuid,
        selected: uuid::Uuid,
        trust: TrustState,
        timeout: Duration,
        cancellation: CancellationToken,
        trust_fence: &'a dyn CurrentBridgeTrust,
        requested_device: Option<uuid::Uuid>,
    ) -> Result<Self, ClientError> {
        let expected_trust = trust
            .client(selected)
            .cloned()
            .ok_or(ClientError::InvalidTrustState)?;
        let operation = async {
            trust_fence
                .require_current(requested_device, &expected_trust)
                .await?;
            let (stream, _) = listener.accept().await.map_err(|_| ClientError::TimedOut)?;
            let frozen = TrustStore::new(FrozenReconnectTrust(trust));
            let authenticated = handshake::authenticate(
                PacketConnection::new(stream),
                host,
                "Health.md",
                None,
                &frozen,
                timeout,
            )
            .await?;
            if authenticated.was_new_pairing
                || authenticated.channel.peer_installation_id != selected
            {
                return Err(Error::BindingChanged.into());
            }
            let mut channel = authenticated.channel;
            let mut local = PeerCapabilities::portable_cli_all_versions(host);
            local.protocol_versions.push(4);
            local.wake = None; // no automatic enrollment/nudge on the planning path
            channel
                .send(&DirectMessage::Hello(Unlabeled::from(local.clone())))
                .await?;
            let SecurePayload::Message(message) = channel.receive().await? else {
                return Err(ClientError::UnexpectedMessage);
            };
            let DirectMessage::Hello(Unlabeled { value: remote }) = *message else {
                return Err(ClientError::UnexpectedMessage);
            };
            if remote.installation_id.0 != selected
                || authenticated.device.platform != Some(remote.platform)
            {
                return Err(Error::BindingChanged.into());
            }
            let platform = match remote.platform {
                WirePlatform::Ios => PeerPlatform::Apple,
                WirePlatform::Android => PeerPlatform::Android,
                WirePlatform::Cli => return Err(Error::UnsupportedCapability.into()),
            };
            let negotiation = v4::negotiate(
                &platform,
                &local.protocol_versions,
                &remote.protocol_versions,
                remote
                    .query
                    .as_ref()
                    .is_some_and(|q| q.schema_versions.contains(&1)),
            )?;
            // No discovery probe (nor source-query conversion) for an old peer.
            if !negotiation.agent_v4 {
                return Err(Error::UnsupportedCapability.into());
            }
            if platform == PeerPlatform::Android {
                let source = channel.receive_v2().await?;
                let healthmd_protocol::v2::Message::SourceHello(hello) = source.message else {
                    return Err(ClientError::UnexpectedMessage);
                };
                if hello.source.installation_id != selected
                    || hello.source.platform != healthmd_protocol::v2::SourcePlatform::Android
                {
                    return Err(Error::BindingChanged.into());
                }
            }
            trust_fence
                .require_current(requested_device, &expected_trust)
                .await?;
            Ok(Self {
                channel,
                trust_fence,
                expected_trust,
                requested_device,
                peer: Peer {
                    host_installation_id: ControlUuid(host.0.to_string()),
                    source_installation_id: ControlUuid(selected.to_string()),
                    platform,
                },
                negotiation,
                timeout,
                cancellation: cancellation.clone(),
                send_interrupted: false,
            })
        };
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(timeout, operation) => result.map_err(|_| ClientError::TimedOut)?,
        }
    }

    pub const fn negotiation(&self) -> Negotiation {
        self.negotiation
    }

    async fn exchange(
        &mut self,
        request: Message,
        request_id: &ControlUuid,
    ) -> Result<Message, ClientError> {
        let operation = async {
            if self.send_interrupted {
                return Err(Error::BindingChanged.into());
            }
            self.trust_fence
                .require_current(self.requested_device, &self.expected_trust)
                .await?;
            // Armed before the send future can yield. Errors, timeouts and dropped futures
            // leave this connection unusable: a partial frame/consumed sequence is not retried.
            self.send_interrupted = true;
            let trust = self.trust_fence;
            let requested = self.requested_device;
            let expected = &self.expected_trust;
            self.channel
                .send_v4_guarded(&Envelope::new(request), self.negotiation, || {
                    trust.require_current(requested, expected)
                })
                .await?;
            self.send_interrupted = false;
            let message = self.channel.receive_v4(self.negotiation).await?.message;
            self.trust_fence
                .require_current(self.requested_device, &self.expected_trust)
                .await?;
            if let Message::Rejected(rejection) = message {
                if rejection.request_id != *request_id {
                    return Err(Error::BindingChanged.into());
                }
                return Err(ClientError::AgentRejected(rejection.code));
            }
            Ok(message)
        };
        tokio::select! {
            biased;
            () = self.cancellation.cancelled() => Err(ClientError::WaitCancelled),
            result = tokio::time::timeout(self.timeout, operation) => result.map_err(|_| ClientError::TimedOut)?,
        }
    }
}

#[async_trait]
impl PlanningSource for BridgeSession<'_> {
    async fn require_current(&self) -> Result<(), ClientError> {
        if self.send_interrupted {
            return Err(Error::BindingChanged.into());
        }
        self.trust_fence
            .require_current(self.requested_device, &self.expected_trust)
            .await
    }
    fn peer(&self) -> &Peer {
        &self.peer
    }
    async fn discover(&mut self) -> Result<Discovery, ClientError> {
        let request_id = ControlUuid(uuid::Uuid::new_v4().to_string());
        let request = DiscoveryRequest {
            peer: self.peer.clone(),
            request_id: request_id.clone(),
            schema: DiscoveryRequestSchema::HealthmdAgentDiscoveryRequest,
            schema_version: 1,
        };
        let Message::DiscoveryResponse(discovery) = self
            .exchange(Message::DiscoveryRequest(Box::new(request)), &request_id)
            .await?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        if discovery.peer != self.peer || discovery.request_id != request_id {
            return Err(Error::BindingChanged.into());
        }
        Ok(*discovery)
    }
    async fn plan(&mut self, request: PlanRequest) -> Result<ExportPlan, ClientError> {
        let id = request.request_id.clone();
        let Message::PlanResponse(plan) = self
            .exchange(Message::PlanRequest(Box::new(request)), &id)
            .await?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        Ok(*plan)
    }
    async fn relay_approval(&mut self, request: ApprovalRequest) -> Result<Approval, ClientError> {
        let id = request.request_id.clone();
        let Message::ApprovalResponse(approval) = self
            .exchange(Message::ApprovalRequest(Box::new(request)), &id)
            .await?
        else {
            return Err(ClientError::UnexpectedMessage);
        };
        Ok(*approval)
    }
}
