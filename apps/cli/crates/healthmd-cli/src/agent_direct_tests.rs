//! CLI/portable-MCP public adapters through the actual `DirectAgentBackend`, host store and
//! encrypted loopback transport. Source and consent/keys are synthetic, not native coverage.
#![cfg(unix)] // Positive store/adapter tracers do not imply Windows issuer support.
use super::*;
use healthmd_client as client_crate;
// The byte-identical packaged mirror is enforced by the release regression gate.
#[path = "agent_direct_test_support.rs"]
mod support;
use healthmd_client::{
    agent_host::{NativeProtectedHostKey, ProtectedHostSecret},
    agent_planning::PlanningSource,
    packet::PacketConnection,
    secure_channel::{SecureChannel, SecurePayload},
    storage::StorageLayout,
    trust::{TrustState, TrustStore, TrustedClient},
};
use healthmd_mcp::{HealthMdApplication, JsonRpcSession};
use healthmd_operations::{CallerIdentity, SurfaceProfile};
use healthmd_protocol::{
    crypto,
    encoding::SwiftUuid,
    v2,
    v4::{self, *},
    wire::{
        DirectMessage, PairingRequest, PeerCapabilities, PeerPlatform as WirePlatform, SyncPacket,
        Unlabeled,
    },
};
use std::{
    collections::HashMap,
    sync::{
        Mutex as StdMutex,
        atomic::{AtomicUsize, Ordering},
    },
};
use support::*;
use tokio::{
    net::{TcpListener, TcpStream},
    sync::oneshot,
};
use tokio_util::sync::CancellationToken;

#[derive(Default)]
struct CredentialState {
    values: StdMutex<HashMap<String, ProtectedHostSecret>>,
    reads: AtomicUsize,
    writes: AtomicUsize,
}
#[derive(Clone, Default)]
struct InjectedCredentials(Arc<CredentialState>);
#[async_trait]
impl CredentialStore for InjectedCredentials {
    async fn get(&self, account: &str) -> Result<Option<ProtectedHostSecret>, ClientError> {
        self.0.reads.fetch_add(1, Ordering::SeqCst);
        Ok(self.0.values.lock().unwrap().get(account).cloned())
    }
    async fn set(&self, account: &str, secret: ProtectedHostSecret) -> Result<(), ClientError> {
        self.0.writes.fetch_add(1, Ordering::SeqCst);
        self.0.values.lock().unwrap().insert(account.into(), secret);
        Ok(())
    }
    async fn delete(&self, account: &str) -> Result<(), ClientError> {
        self.0.writes.fetch_add(1, Ordering::SeqCst);
        self.0.values.lock().unwrap().remove(account);
        Ok(())
    }
}
struct ExistingFakeKey(AtomicUsize);
#[async_trait]
impl ProtectedHostKey for ExistingFakeKey {
    async fn load_existing(&self, host: &ControlUuid) -> Result<ProtectedHostSecret, ClientError> {
        self.0.fetch_add(1, Ordering::SeqCst);
        FakeProtectedKey.load_existing(host).await
    }
}
async fn fake_session(
    port: u16,
    native: &NativeFake,
    secret: &[u8],
) -> (SecureChannel, Negotiation) {
    let source_id = SwiftUuid(Uuid::parse_str(&native.peer.source_installation_id.0).unwrap());
    let (private, public) = crypto::ephemeral_key_pair().unwrap();
    let nonce = crypto::random_bytes::<32>().unwrap();
    let stream = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Ok(stream) = TcpStream::connect(("127.0.0.1", port)).await {
                break stream;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    let mut packet = PacketConnection::new(stream);
    packet
        .send(&SyncPacket::PairingRequest(Unlabeled::from(
            PairingRequest {
                protocol_version: 3,
                device_name: "Synthetic source".into(),
                client_public_key: public.to_vec(),
                client_nonce: nonce.to_vec(),
                code_verifier: vec![],
                client_installation_id: Some(source_id),
                trusted_verifier: Some(
                    crypto::trusted_client_verifier(secret, source_id.0, &public, &nonce).to_vec(),
                ),
            },
        )))
        .await
        .unwrap();
    let SyncPacket::PairingResponse(Unlabeled { value: response }) =
        packet.receive().await.unwrap()
    else {
        panic!("expected reconnect response");
    };
    let host = response.mac_installation_id.unwrap();
    assert_eq!(host.0.to_string(), native.peer.host_installation_id.0);
    let shared = crypto::x25519_shared_secret(&private, &response.server_public_key).unwrap();
    let key = crypto::session_key(&shared, &nonce, &response.server_nonce);
    let mut channel = SecureChannel::new(packet, key, host.0, response.mac_name);
    let SecurePayload::Message(hello) = channel.receive().await.unwrap() else {
        panic!("expected hello");
    };
    let DirectMessage::Hello(Unlabeled { value: local }) = *hello else {
        panic!("expected hello");
    };
    assert_eq!(local.protocol_versions, [1, 2, 3, 4]);
    assert!(local.wake.is_none());
    let mut remote = PeerCapabilities::portable_cli_all_versions(source_id);
    remote.protocol_versions = if native.peer.platform == PeerPlatform::Apple {
        vec![1, 3, 4]
    } else {
        vec![2, 4]
    };
    remote.platform = if native.peer.platform == PeerPlatform::Apple {
        WirePlatform::Ios
    } else {
        WirePlatform::Android
    };
    remote.wake = None;
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(remote.clone())))
        .await
        .unwrap();
    if native.peer.platform == PeerPlatform::Android {
        channel
            .send_v2(&v2::Envelope::new(v2::Message::SourceHello(
                v2::SourceHello {
                    source: v2::SourceIdentity {
                        installation_id: source_id.0,
                        platform: v2::SourcePlatform::Android,
                        display_name: "Synthetic source".into(),
                        app_version: "synthetic".into(),
                    },
                    products: vec![],
                    limits: v2::ProtocolLimits {
                        maximum_control_bytes: 2 * 1024 * 1024,
                        maximum_chunk_bytes: 512 * 1024,
                        preferred_partition_bytes: 48 * 1024 * 1024,
                    },
                },
            )))
            .await
            .unwrap();
    }
    let negotiation = v4::negotiate(
        &native.peer.platform,
        &local.protocol_versions,
        &remote.protocol_versions,
        true,
    )
    .unwrap();
    (channel, negotiation)
}
async fn answer_discovery(
    channel: &mut SecureChannel,
    negotiation: Negotiation,
    native: &NativeFake,
) {
    let Message::DiscoveryRequest(request) = channel.receive_v4(negotiation).await.unwrap().message
    else {
        panic!("expected discovery only");
    };
    assert_eq!(request.peer, native.peer);
    channel
        .send_v4(
            &Envelope::new(Message::DiscoveryResponse(Box::new(
                native.discovery(request.request_id),
            ))),
            negotiation,
        )
        .await
        .unwrap();
}
async fn execute_send_base(
    channel: &mut SecureChannel,
    platform: &PeerPlatform,
    apple: DirectMessage,
    android: v2::Message,
) {
    if *platform == PeerPlatform::Apple {
        channel.send(&apple).await.unwrap();
    } else {
        channel.send_v2(&v2::Envelope::new(android)).await.unwrap();
    }
}
async fn execute_expect_base(
    channel: &mut SecureChannel,
    platform: &PeerPlatform,
    apple: DirectMessage,
    android: v2::Message,
) {
    if *platform == PeerPlatform::Apple {
        let SecurePayload::Message(message) = channel.receive().await.unwrap() else {
            panic!("Expected Apple control");
        };
        assert_eq!(*message, apple);
    } else {
        assert_eq!(channel.receive_v2().await.unwrap().message, android);
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ExecutionPeerOutcome {
    Complete,
    DisconnectBeforeFinalize,
    DisconnectThenCancel,
    AcceptedThenCancel,
    AcceptedThenResume,
    UncertainThenResume,
    UncertainThenStop,
    UncertainDirectStop,
    DisconnectAfterFirstPartition,
}

#[derive(Clone)]
struct ExecutedPeerSnapshot {
    request: ExecuteRequest,
    accepted: ExecutionReceipt,
    manifest: ArtifactManifest,
    session: v2::TransferSession,
    last_transfer: Uuid,
    completed: ExecutionReceipt,
}

// One bounded positive peer transcript verifies the actual public backend, both deployed
// base envelopes, durable host output and final source confirmation. Native SDK is synthetic.
#[allow(clippy::too_many_lines)]
async fn answer_approved_execute(
    channel: &mut SecureChannel,
    negotiation: Negotiation,
    native: &mut NativeFake,
    outcome: ExecutionPeerOutcome,
) -> ExecutedPeerSnapshot {
    use healthmd_protocol::models as a;
    let Message::ExecuteRequest(request) = channel.receive_v4(negotiation).await.unwrap().message
    else {
        panic!("Expected Execute only");
    };
    let request = *request;
    let platform = native.peer.platform.clone();
    assert_eq!(request.plan.intent.peer, native.peer);
    let approved = native
        .relay_approval(ApprovalRequest {
            schema: ApprovalRequestSchema::HealthmdAgentApprovalRequest,
            schema_version: 1,
            request_id: id(210),
            plan_id: request.plan.plan_id.clone(),
            binding: approval_binding(&request.plan),
        })
        .await
        .unwrap();
    assert_eq!(request.approval, approved);
    let bytes = b"{\"synthetic\":true}";
    let digest = Digest(healthmd_protocol::transfer::sha256_hex(bytes));
    let accepted = ExecutionReceipt {
        schema: ExecutionReceiptSchema::HealthmdAgentExecutionReceipt,
        schema_version: 1,
        artifact_count: 0,
        binding: approval_binding(&request.plan),
        committed_partition_count: 0,
        expires_at: later(&native.time, 604_800),
        frontier_sha256: Digest("0".repeat(64)),
        job_id: request.job_id.clone(),
        manifest_sha256: Digest("0".repeat(64)),
        request_sha256: document_digest(&request).unwrap(),
        source_acknowledged: false,
        status: ExecutionReceiptStatus::Accepted,
    };
    if !matches!(
        outcome,
        ExecutionPeerOutcome::UncertainThenResume
            | ExecutionPeerOutcome::UncertainThenStop
            | ExecutionPeerOutcome::UncertainDirectStop
    ) {
        channel
            .send_v4(
                &Envelope::new(Message::ExecutionReceipt(Box::new(accepted.clone()))),
                negotiation,
            )
            .await
            .unwrap();
    }
    assert_eq!(request.plan.predicted_paths.len(), 2);
    let manifest = ArtifactManifest {
        schema: ArtifactManifestSchema::HealthmdAgentArtifactManifest,
        schema_version: 1,
        job_id: request.job_id.clone(),
        binding: accepted.binding.clone(),
        request_sha256: accepted.request_sha256.clone(),
        capture_status: ArtifactManifestCaptureStatus::Complete,
        branch_statuses: vec![],
        artifacts: request
            .plan
            .predicted_paths
            .iter()
            .map(|path| {
                Artifact::Branch1(ArtifactBranch1 {
                    artifact_id: ControlUuid(Uuid::new_v4().to_string()),
                    relative_path: path.clone(),
                    byte_count: bytes.len() as u64,
                    sha256: digest.clone(),
                    media_type: ArtifactBranch1MediaType::ApplicationJson,
                    profile: if platform == PeerPlatform::Apple {
                        ArtifactBranch1Profile::AppleV8
                    } else {
                        ArtifactBranch1Profile::AndroidFrozenV4
                    },
                    write_mode: OutputSettingsWriteMode::Overwrite,
                })
            })
            .collect(),
    };
    let session = v2::TransferSession {
        session_id: Uuid::new_v4(),
        job_id: Uuid::parse_str(&request.job_id.0).unwrap(),
        request_fingerprint: accepted.request_sha256.0.clone(),
        peer_binding: v2::PeerBinding {
            source_installation_id: Uuid::parse_str(&native.peer.source_installation_id.0).unwrap(),
            destination_installation_id: Uuid::parse_str(&native.peer.host_installation_id.0)
                .unwrap(),
        },
        partition_target_bytes: 50_331_648,
        created_at: chrono::DateTime::from_timestamp(native.time.seconds().unwrap(), 0).unwrap(),
    };
    if matches!(
        outcome,
        ExecutionPeerOutcome::AcceptedThenCancel
            | ExecutionPeerOutcome::UncertainDirectStop
            | ExecutionPeerOutcome::AcceptedThenResume
            | ExecutionPeerOutcome::UncertainThenResume
            | ExecutionPeerOutcome::UncertainThenStop
    ) {
        // No manifest or base transfer message has crossed this channel. The retained
        // accepted owner must support public Cancel without fabricated output proof.
        return ExecutedPeerSnapshot {
            request,
            completed: ExecutionReceipt {
                status: if matches!(
                    outcome,
                    ExecutionPeerOutcome::AcceptedThenCancel
                        | ExecutionPeerOutcome::UncertainDirectStop
                ) {
                    ExecutionReceiptStatus::Cancelled
                } else {
                    ExecutionReceiptStatus::Accepted
                },
                source_acknowledged: matches!(
                    outcome,
                    ExecutionPeerOutcome::AcceptedThenCancel
                        | ExecutionPeerOutcome::UncertainDirectStop
                ),
                ..accepted.clone()
            },
            accepted,
            manifest,
            session,
            last_transfer: Uuid::nil(),
        };
    }
    channel
        .send_v4(
            &Envelope::new(Message::ArtifactManifest(Box::new(manifest.clone()))),
            negotiation,
        )
        .await
        .unwrap();
    let fingerprint = a::RequestFingerprint {
        version: 1,
        sha256: session.request_fingerprint.clone(),
    };
    execute_send_base(
        channel,
        &platform,
        DirectMessage::TransferSession(Unlabeled::from(a::TransferSession {
            protocol_version: 1,
            session_id: SwiftUuid(session.session_id),
            job_id: SwiftUuid(session.job_id),
            request_fingerprint: fingerprint.clone(),
            peer_binding: a::PeerBinding {
                source_installation_id: SwiftUuid(session.peer_binding.source_installation_id),
                destination_installation_id: SwiftUuid(
                    session.peer_binding.destination_installation_id,
                ),
            },
            partition_target_bytes: 50_331_648,
            created_at: session.created_at,
        })),
        v2::Message::TransferSession(session.clone()),
    )
    .await;
    for artifact in &manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            panic!("Expected daily file");
        };
        let file = Uuid::parse_str(&item.artifact_id.0).unwrap();
        execute_send_base(
            channel,
            &platform,
            DirectMessage::FileManifest(Unlabeled::from(a::FileManifest {
                job_id: SwiftUuid(session.job_id),
                file_id: SwiftUuid(file),
                relative_path: item.relative_path.0.clone(),
                byte_count: i64::try_from(bytes.len()).unwrap(),
                sha256: digest.0.clone(),
                write_mode: a::FileWriteMode::Overwrite,
            })),
            v2::Message::ArtifactManifest(v2::ArtifactManifest {
                job_id: session.job_id,
                artifact_id: file,
                kind: v2::ArtifactKind::GeneratedFile,
                schema: v2::ArtifactSchema {
                    id: "healthmd.generated-files".into(),
                    major: 1,
                },
                media_type: "application/json".into(),
                byte_count: bytes.len() as u64,
                sha256: digest.0.clone(),
                relative_path: Some(item.relative_path.0.clone()),
                write_mode: Some(v2::FileWriteMode::Overwrite),
                logical_checksum_sha256: None,
                snapshot_status: None,
                provider_id: None,
            }),
        )
        .await;
    }
    let manifest_digest = document_digest(&manifest).unwrap();
    let mut frontier = TransferFrontier::new(
        &request.job_id,
        &accepted.request_sha256,
        &manifest_digest,
        &ControlUuid(session.session_id.to_string()),
    )
    .unwrap();
    let mut previous = None;
    let mut last_transfer = Uuid::nil();
    for (index, artifact) in manifest.artifacts.iter().enumerate() {
        let Artifact::Branch1(item) = artifact else {
            panic!("Expected daily file");
        };
        let transfer = Uuid::new_v4();
        last_transfer = transfer;
        send_execution_partition(
            channel,
            &platform,
            &session,
            item,
            index,
            transfer,
            previous.clone(),
        )
        .await;
        frontier = frontier
            .appending(&TransferFrontierPartition {
                partition_index: i64::try_from(index).unwrap(),
                transfer_id: ControlUuid(transfer.to_string()),
                artifact_id: item.artifact_id.clone(),
                artifact_offset: 0,
                byte_count: i64::try_from(bytes.len()).unwrap(),
                chunk_count: 1,
                sha256: digest.clone(),
            })
            .unwrap();
        previous = Some(digest.0.clone());
        if outcome == ExecutionPeerOutcome::DisconnectAfterFirstPartition && index == 0 {
            break;
        }
    }
    if outcome != ExecutionPeerOutcome::Complete {
        // Only this prefix is durably acknowledged; no finalization or source completion
        // has been sent. Dropping this channel must fail Execute.
        let completed = ExecutionReceipt {
            artifact_count: 2,
            committed_partition_count: if outcome
                == ExecutionPeerOutcome::DisconnectAfterFirstPartition
            {
                1
            } else {
                2
            },
            frontier_sha256: frontier.sha256().clone(),
            manifest_sha256: manifest_digest,
            source_acknowledged: true,
            status: ExecutionReceiptStatus::Complete,
            ..accepted.clone()
        };
        return ExecutedPeerSnapshot {
            request,
            accepted,
            manifest,
            session,
            last_transfer,
            completed,
        };
    }
    execute_send_base(
        channel,
        &platform,
        DirectMessage::TransferFinalize(Unlabeled::from(a::TransferFinalize {
            session_id: SwiftUuid(session.session_id),
            job_id: SwiftUuid(session.job_id),
            request_fingerprint: fingerprint,
            total_partitions: 2,
            total_bytes: i64::try_from(bytes.len() * 2).unwrap(),
            final_partition_sha256: previous.clone(),
            outcome: None,
        })),
        v2::Message::TransferFinalize(v2::TransferFinalize {
            session_id: session.session_id,
            job_id: session.job_id,
            request_fingerprint: session.request_fingerprint.clone(),
            total_partitions: 2,
            total_bytes: (bytes.len() * 2) as u64,
            final_partition_sha256: previous.clone(),
        }),
    )
    .await;
    execute_expect_base(
        channel,
        &platform,
        DirectMessage::TransferFinalAcknowledgement(Unlabeled::from(
            a::TransferFinalAcknowledgement {
                session_id: SwiftUuid(session.session_id),
                job_id: SwiftUuid(session.job_id),
                accepted: true,
                total_partitions: 2,
                total_bytes: i64::try_from(bytes.len() * 2).unwrap(),
                final_partition_sha256: previous.clone(),
                response_byte_count: None,
                response_sha256: None,
                message: None,
            },
        )),
        v2::Message::TransferFinalAcknowledgement(v2::TransferFinalAcknowledgement {
            session_id: session.session_id,
            job_id: session.job_id,
            accepted: true,
            total_partitions: 2,
            total_bytes: (bytes.len() * 2) as u64,
            final_partition_sha256: previous,
            response_byte_count: None,
            response_sha256: None,
            message: None,
        }),
    )
    .await;
    for artifact in &manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            panic!("Expected daily file");
        };
        let Message::CommitReceipt(receipt) =
            channel.receive_v4(negotiation).await.unwrap().message
        else {
            panic!("Expected durable commit");
        };
        validate_commit_receipt(&receipt, None).unwrap();
        assert_eq!(receipt.artifact_id, item.artifact_id);
        assert_eq!(receipt.input_sha256, digest);
        assert_eq!(receipt.after_sha256, digest);
        assert_eq!(receipt.manifest_sha256, manifest_digest);
        assert_eq!(receipt.destination, request.plan.intent.destination);
    }
    execute_send_base(
        channel,
        &platform,
        DirectMessage::CompletionConfirmed(a::JobIdPayload {
            job_id: SwiftUuid(session.job_id),
        }),
        v2::Message::CompletionConfirmed(v2::JobPayload {
            job_id: session.job_id,
        }),
    )
    .await;
    let completed = ExecutionReceipt {
        artifact_count: 2,
        committed_partition_count: 2,
        frontier_sha256: frontier.sha256().clone(),
        manifest_sha256: manifest_digest,
        source_acknowledged: true,
        status: ExecutionReceiptStatus::Complete,
        ..accepted.clone()
    };
    channel
        .send_v4(
            &Envelope::new(Message::ExecutionReceipt(Box::new(completed.clone()))),
            negotiation,
        )
        .await
        .unwrap();
    ExecutedPeerSnapshot {
        request,
        accepted,
        manifest,
        session,
        last_transfer,
        completed,
    }
}

// Identical partition exchange for first delivery and an authenticated resumed suffix.
#[allow(clippy::too_many_lines, clippy::too_many_arguments)]
async fn send_execution_partition(
    channel: &mut SecureChannel,
    platform: &PeerPlatform,
    session: &v2::TransferSession,
    item: &ArtifactBranch1,
    index: usize,
    transfer: Uuid,
    previous: Option<String>,
) {
    use healthmd_protocol::models as a;
    let bytes = b"{\"synthetic\":true}";
    let digest = Digest(healthmd_protocol::transfer::sha256_hex(bytes));
    let artifact_id = Uuid::parse_str(&item.artifact_id.0).unwrap();
    let fingerprint = a::RequestFingerprint {
        version: 1,
        sha256: session.request_fingerprint.clone(),
    };
    let part = v2::TransferPartition {
        index: index as u64,
        transfer_id: transfer,
        artifact_id,
        artifact_offset: 0,
        byte_count: bytes.len() as u64,
        chunk_count: 1,
        sha256: digest.0.clone(),
        previous_sha256: previous.clone(),
    };
    execute_send_base(
        channel,
        platform,
        DirectMessage::TransferOpen(Unlabeled::from(a::TransferOpen {
            session: a::TransferSession {
                protocol_version: 1,
                session_id: SwiftUuid(session.session_id),
                job_id: SwiftUuid(session.job_id),
                request_fingerprint: fingerprint.clone(),
                peer_binding: a::PeerBinding {
                    source_installation_id: SwiftUuid(session.peer_binding.source_installation_id),
                    destination_installation_id: SwiftUuid(
                        session.peer_binding.destination_installation_id,
                    ),
                },
                partition_target_bytes: 50_331_648,
                created_at: session.created_at,
            },
            partition: a::TransferPartition {
                index: i64::try_from(index).unwrap(),
                transfer_id: SwiftUuid(transfer),
                source_dates: vec![item.artifact_id.0.clone()],
                item_segment: Some(a::TransferItemSegment {
                    item_id: item.artifact_id.0.clone(),
                    offset: 0,
                    item_byte_count: i64::try_from(bytes.len()).unwrap(),
                    is_final_segment: true,
                }),
                byte_count: i64::try_from(bytes.len()).unwrap(),
                chunk_count: 1,
                sha256: digest.0.clone(),
                previous_sha256: previous.clone(),
            },
        })),
        v2::Message::TransferOpen(v2::TransferOpen {
            session: session.clone(),
            partition: part,
        }),
    )
    .await;
    execute_expect_base(
        channel,
        platform,
        DirectMessage::TransferDisposition(Unlabeled::from(a::TransferDisposition {
            session_id: SwiftUuid(session.session_id),
            job_id: SwiftUuid(session.job_id),
            partition_index: i64::try_from(index).unwrap(),
            partition_sha256: digest.0.clone(),
            disposition: a::TransferDispositionKind::Needed,
            message: None,
        })),
        v2::Message::TransferDisposition(v2::TransferDisposition {
            session_id: session.session_id,
            job_id: session.job_id,
            partition_index: index as u64,
            partition_sha256: digest.0.clone(),
            disposition: v2::TransferDispositionKind::Needed,
            message: None,
        }),
    )
    .await;
    let chunk = a::TransferChunk {
        transfer_id: SwiftUuid(transfer),
        sequence: 1,
        data: bytes.to_vec(),
        sha256: digest.0.clone(),
    };
    channel
        .send_binary_transfer_frame(
            &healthmd_protocol::transfer::encode_binary_chunk(&chunk).unwrap(),
        )
        .await
        .unwrap();
    execute_expect_base(
        channel,
        platform,
        DirectMessage::TransferChunkAcknowledgement(Unlabeled::from(
            a::TransferChunkAcknowledgement {
                transfer_id: SwiftUuid(transfer),
                sequence: 1,
                accepted: true,
                sha256: digest.0.clone(),
                message: None,
            },
        )),
        v2::Message::TransferChunkAcknowledgement(v2::TransferChunkAcknowledgement {
            transfer_id: transfer,
            sequence: 1,
            accepted: true,
            sha256: digest.0.clone(),
            message: None,
        }),
    )
    .await;
    execute_send_base(
        channel,
        platform,
        DirectMessage::TransferPartitionComplete(Unlabeled::from(a::TransferPartitionComplete {
            session_id: SwiftUuid(session.session_id),
            job_id: SwiftUuid(session.job_id),
            partition_index: i64::try_from(index).unwrap(),
            transfer_id: SwiftUuid(transfer),
            partition_sha256: digest.0.clone(),
        })),
        v2::Message::TransferPartitionComplete(v2::TransferPartitionComplete {
            session_id: session.session_id,
            job_id: session.job_id,
            partition_index: index as u64,
            transfer_id: transfer,
            partition_sha256: digest.0.clone(),
        }),
    )
    .await;
    execute_expect_base(
        channel,
        platform,
        DirectMessage::TransferPartitionAcknowledgement(Unlabeled::from(
            a::TransferPartitionAcknowledgement {
                session_id: SwiftUuid(session.session_id),
                job_id: SwiftUuid(session.job_id),
                partition_index: i64::try_from(index).unwrap(),
                transfer_id: SwiftUuid(transfer),
                partition_sha256: digest.0.clone(),
                accepted: true,
                message: None,
            },
        )),
        v2::Message::TransferPartitionAcknowledgement(v2::TransferPartitionAcknowledgement {
            session_id: session.session_id,
            job_id: session.job_id,
            partition_index: index as u64,
            transfer_id: transfer,
            partition_sha256: digest.0.clone(),
            accepted: true,
            message: None,
        }),
    )
    .await;
}

// A fresh authenticated owner must receive the retained final ACK before Resume and
// must reproduce the exact original accepted binding, manifest and terminal receipt.
#[allow(clippy::too_many_lines)]
async fn answer_retained_resume(
    channel: &mut SecureChannel,
    negotiation: Negotiation,
    state: ExecutedPeerSnapshot,
    acceptance_only: bool,
) -> ExecutedPeerSnapshot {
    use healthmd_protocol::models as a;
    let ExecutedPeerSnapshot {
        request,
        accepted,
        manifest,
        session,
        mut last_transfer,
        mut completed,
    } = state;
    let platform = request.plan.intent.peer.platform.clone();
    let bytes = b"{\"synthetic\":true}";
    let digest = Digest(healthmd_protocol::transfer::sha256_hex(bytes));
    if completed.committed_partition_count > 0 {
        execute_expect_base(
            channel,
            &platform,
            DirectMessage::TransferPartitionAcknowledgement(Unlabeled::from(
                a::TransferPartitionAcknowledgement {
                    session_id: SwiftUuid(session.session_id),
                    job_id: SwiftUuid(session.job_id),
                    partition_index: i64::try_from(completed.committed_partition_count - 1)
                        .unwrap(),
                    transfer_id: SwiftUuid(last_transfer),
                    partition_sha256: digest.0.clone(),
                    accepted: true,
                    message: None,
                },
            )),
            v2::Message::TransferPartitionAcknowledgement(v2::TransferPartitionAcknowledgement {
                session_id: session.session_id,
                job_id: session.job_id,
                partition_index: completed.committed_partition_count - 1,
                transfer_id: last_transfer,
                partition_sha256: digest.0.clone(),
                accepted: true,
                message: None,
            }),
        )
        .await;
    }
    let Message::ResumeRequest(resume) = channel.receive_v4(negotiation).await.unwrap().message
    else {
        panic!("Only retained Resume is permitted")
    };
    assert_eq!(resume.job_id, request.job_id);
    assert_eq!(resume.peer, request.plan.intent.peer);
    assert_eq!(resume.binding, approval_binding(&request.plan));
    assert_eq!(resume.destination, request.plan.intent.destination);
    assert_eq!(resume.request_sha256, document_digest(&request).unwrap());
    assert_eq!(
        resume.manifest_sha256,
        if completed.committed_partition_count == 0 {
            Digest("0".repeat(64))
        } else {
            document_digest(&manifest).unwrap()
        }
    );
    assert_eq!(resume.frontier_sha256, completed.frontier_sha256);
    assert_eq!(
        resume.committed_partition_count,
        completed.committed_partition_count
    );
    channel
        .send_v4(
            &Envelope::new(Message::ExecutionReceipt(Box::new(accepted.clone()))),
            negotiation,
        )
        .await
        .unwrap();
    if acceptance_only {
        assert_eq!(completed.committed_partition_count, 0);
        // Acceptance has crossed this channel; no manifest or transfer follows. The host
        // must retain that fact despite Resume failing, then permit explicit same-job Stop.
        return ExecutedPeerSnapshot {
            request,
            manifest,
            session,
            last_transfer,
            completed: ExecutionReceipt {
                status: ExecutionReceiptStatus::Cancelled,
                source_acknowledged: true,
                ..accepted.clone()
            },
            accepted,
        };
    }
    channel
        .send_v4(
            &Envelope::new(Message::ArtifactManifest(Box::new(manifest.clone()))),
            negotiation,
        )
        .await
        .unwrap();
    let fingerprint = a::RequestFingerprint {
        version: 1,
        sha256: session.request_fingerprint.clone(),
    };
    execute_send_base(
        channel,
        &platform,
        DirectMessage::TransferSession(Unlabeled::from(a::TransferSession {
            protocol_version: 1,
            session_id: SwiftUuid(session.session_id),
            job_id: SwiftUuid(session.job_id),
            request_fingerprint: fingerprint.clone(),
            peer_binding: a::PeerBinding {
                source_installation_id: SwiftUuid(session.peer_binding.source_installation_id),
                destination_installation_id: SwiftUuid(
                    session.peer_binding.destination_installation_id,
                ),
            },
            partition_target_bytes: 50_331_648,
            created_at: session.created_at,
        })),
        v2::Message::TransferSession(session.clone()),
    )
    .await;
    for artifact in &manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            panic!("Expected daily file");
        };
        let file = Uuid::parse_str(&item.artifact_id.0).unwrap();
        execute_send_base(
            channel,
            &platform,
            DirectMessage::FileManifest(Unlabeled::from(a::FileManifest {
                job_id: SwiftUuid(session.job_id),
                file_id: SwiftUuid(file),
                relative_path: item.relative_path.0.clone(),
                byte_count: i64::try_from(bytes.len()).unwrap(),
                sha256: digest.0.clone(),
                write_mode: a::FileWriteMode::Overwrite,
            })),
            v2::Message::ArtifactManifest(v2::ArtifactManifest {
                job_id: session.job_id,
                artifact_id: file,
                kind: v2::ArtifactKind::GeneratedFile,
                schema: v2::ArtifactSchema {
                    id: "healthmd.generated-files".into(),
                    major: 1,
                },
                media_type: "application/json".into(),
                byte_count: bytes.len() as u64,
                sha256: digest.0.clone(),
                relative_path: Some(item.relative_path.0.clone()),
                write_mode: Some(v2::FileWriteMode::Overwrite),
                logical_checksum_sha256: None,
                snapshot_status: None,
                provider_id: None,
            }),
        )
        .await;
    }
    let manifest_digest = document_digest(&manifest).unwrap();
    if completed.committed_partition_count < 2 {
        let original_count = completed.committed_partition_count;
        let mut frontier = TransferFrontier::new(
            &request.job_id,
            &accepted.request_sha256,
            &manifest_digest,
            &ControlUuid(session.session_id.to_string()),
        )
        .unwrap();
        for (index, artifact) in manifest.artifacts.iter().enumerate() {
            let Artifact::Branch1(item) = artifact else {
                panic!("Expected daily file")
            };
            let transfer = if (index as u64) < original_count {
                last_transfer
            } else {
                Uuid::new_v4()
            };
            if (index as u64) >= original_count {
                send_execution_partition(
                    channel,
                    &platform,
                    &session,
                    item,
                    index,
                    transfer,
                    if index == 0 {
                        None
                    } else {
                        Some(digest.0.clone())
                    },
                )
                .await;
                last_transfer = transfer;
            }
            frontier = frontier
                .appending(&TransferFrontierPartition {
                    partition_index: i64::try_from(index).unwrap(),
                    transfer_id: ControlUuid(transfer.to_string()),
                    artifact_id: item.artifact_id.clone(),
                    artifact_offset: 0,
                    byte_count: i64::try_from(bytes.len()).unwrap(),
                    chunk_count: 1,
                    sha256: digest.clone(),
                })
                .unwrap();
            if (index as u64) + 1 == original_count {
                assert_eq!(frontier.sha256(), &completed.frontier_sha256);
            }
        }
        completed.committed_partition_count = 2;
        completed.artifact_count = 2;
        completed.frontier_sha256 = frontier.sha256().clone();
        completed.manifest_sha256 = manifest_digest.clone();
        completed.status = ExecutionReceiptStatus::Complete;
        completed.source_acknowledged = true;
    }
    let previous = Some(digest.0.clone());
    execute_send_base(
        channel,
        &platform,
        DirectMessage::TransferFinalize(Unlabeled::from(a::TransferFinalize {
            session_id: SwiftUuid(session.session_id),
            job_id: SwiftUuid(session.job_id),
            request_fingerprint: fingerprint,
            total_partitions: 2,
            total_bytes: i64::try_from(bytes.len() * 2).unwrap(),
            final_partition_sha256: previous.clone(),
            outcome: None,
        })),
        v2::Message::TransferFinalize(v2::TransferFinalize {
            session_id: session.session_id,
            job_id: session.job_id,
            request_fingerprint: session.request_fingerprint.clone(),
            total_partitions: 2,
            total_bytes: (bytes.len() * 2) as u64,
            final_partition_sha256: previous.clone(),
        }),
    )
    .await;
    execute_expect_base(
        channel,
        &platform,
        DirectMessage::TransferFinalAcknowledgement(Unlabeled::from(
            a::TransferFinalAcknowledgement {
                session_id: SwiftUuid(session.session_id),
                job_id: SwiftUuid(session.job_id),
                accepted: true,
                total_partitions: 2,
                total_bytes: i64::try_from(bytes.len() * 2).unwrap(),
                final_partition_sha256: previous.clone(),
                response_byte_count: None,
                response_sha256: None,
                message: None,
            },
        )),
        v2::Message::TransferFinalAcknowledgement(v2::TransferFinalAcknowledgement {
            session_id: session.session_id,
            job_id: session.job_id,
            accepted: true,
            total_partitions: 2,
            total_bytes: (bytes.len() * 2) as u64,
            final_partition_sha256: previous,
            response_byte_count: None,
            response_sha256: None,
            message: None,
        }),
    )
    .await;
    for artifact in &manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            panic!("Expected daily file");
        };
        let Message::CommitReceipt(receipt) =
            channel.receive_v4(negotiation).await.unwrap().message
        else {
            panic!("Expected durable commit");
        };
        validate_commit_receipt(&receipt, None).unwrap();
        assert_eq!(receipt.artifact_id, item.artifact_id);
        assert_eq!(receipt.input_sha256, digest);
        assert_eq!(receipt.after_sha256, digest);
        assert_eq!(receipt.manifest_sha256, manifest_digest);
        assert_eq!(receipt.destination, request.plan.intent.destination);
    }
    execute_send_base(
        channel,
        &platform,
        DirectMessage::CompletionConfirmed(a::JobIdPayload {
            job_id: SwiftUuid(session.job_id),
        }),
        v2::Message::CompletionConfirmed(v2::JobPayload {
            job_id: session.job_id,
        }),
    )
    .await;
    channel
        .send_v4(
            &Envelope::new(Message::ExecutionReceipt(Box::new(completed.clone()))),
            negotiation,
        )
        .await
        .unwrap();
    ExecutedPeerSnapshot {
        request,
        accepted,
        manifest,
        session,
        last_transfer,
        completed,
    }
}

async fn answer_retained_cancel(
    channel: &mut SecureChannel,
    negotiation: Negotiation,
    state: ExecutedPeerSnapshot,
    outcome: ExecutionPeerOutcome,
) {
    let Message::CancelRequest(cancel) = channel.receive_v4(negotiation).await.unwrap().message
    else {
        panic!("Only Cancel permitted; no transfer ACK, Execute or Resume")
    };
    assert_eq!(cancel.job_id, state.request.job_id);
    assert_eq!(cancel.peer, state.request.plan.intent.peer);
    assert_eq!(cancel.approval_id, state.request.approval.approval_id);
    assert_eq!(cancel.authority_id, state.request.approval.authority_id);
    assert_eq!(
        cancel.request_sha256,
        document_digest(&state.request).unwrap()
    );
    let receipt = if outcome == ExecutionPeerOutcome::DisconnectThenCancel {
        ExecutionReceipt {
            status: ExecutionReceiptStatus::Cancelled,
            ..state.completed
        }
    } else {
        state.completed
    };
    channel
        .send_v4(
            &Envelope::new(Message::ExecutionReceipt(Box::new(receipt))),
            negotiation,
        )
        .await
        .unwrap();
}

fn arguments(peer: &Peer) -> Value {
    serde_json::json!({"dates":{"type":"exact","range":{"start_date":"2026-01-01","end_date":"2026-01-02"}},"calendar_timezone":"UTC","metric_ids":["steps"],"output_profile":profile(peer),"subfolder":"","folder_template":"{year}","filename_template":"{date}","destination_binding_id":id(3)})
}
async fn rpc_call(rpc: &JsonRpcSession, name: &str, arguments: Value, id: u64) -> Value {
    let request = serde_json::json!({"jsonrpc":"2.0","id":id,"method":"tools/call","params":{"name":name,"arguments":arguments}});
    let response: Value = serde_json::from_str(
        &rpc.handle(&request.to_string(), CancellationToken::new())
            .await
            .unwrap(),
    )
    .unwrap();
    assert!(response.get("error").is_none());
    assert_eq!(response["result"]["isError"], false);
    serde_json::from_str(response["result"]["content"][0]["text"].as_str().unwrap()).unwrap()
}
fn comparable_plan(mut value: Value) -> Value {
    // Two genuine plan issuances intentionally have distinct nonces/digests, not retargetable IDs.
    value.as_object_mut().unwrap().remove("plan_id");
    value.as_object_mut().unwrap().remove("plan_sha256");
    value["intent"].as_object_mut().unwrap().remove("intent_id");
    value
}

#[tokio::test]
async fn actual_execute_backend_rejects_missing_plan_before_listener_or_output() {
    let temporary = tempfile::TempDir::new().unwrap();
    let root = std::fs::canonicalize(temporary.path()).unwrap();
    let credentials = InjectedCredentials::default();
    let layout = StorageLayout { root: root.clone() };
    healthmd_client::storage::IdentityStore::new(layout.clone())
        .load_or_create(chrono::Utc::now())
        .unwrap();
    let client = Arc::new(
        DirectClient::open_planning_with_credentials(layout, credentials.clone()).unwrap(),
    );
    let source_id = Uuid::new_v4();
    let peer = Peer {
        host_installation_id: ControlUuid(client.identity.installation_id.0.to_string()),
        source_installation_id: ControlUuid(source_id.to_string()),
        platform: PeerPlatform::Apple,
    };
    let (store, output) = enroll(&root, &peer, &SystemPlanningClock.now()).await;
    let mut trust = TrustState::empty(client.identity.installation_id);
    trust
        .save_client(TrustedClient {
            installation_id: SwiftUuid(source_id),
            display_name: "Synthetic source".into(),
            platform: Some(WirePlatform::Ios),
            reconnect_secret: vec![13; 32],
            paired_at: chrono::Utc::now(),
            last_connected_at: chrono::Utc::now(),
            wake: None,
        })
        .unwrap();
    TrustStore::new(credentials.clone())
        .save(&trust)
        .await
        .unwrap();
    let writes = credentials.0.writes.load(Ordering::SeqCst);
    let occupied = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let backend: Arc<dyn HealthDataBackend> = Arc::new(DirectAgentBackend::new(
        client,
        Arc::new(ExistingFakeKey(AtomicUsize::new(0))),
        Some(source_id),
        occupied.local_addr().unwrap().port(),
        Duration::from_secs(5),
        Arc::new(Mutex::new(())),
    ));
    let input = serde_json::json!({"plan_id":id(99),"job_id":id(20),"idempotency_key":id(19),"request_id":id(22)});
    let before = store.revision().await.unwrap();
    let error = crate::mcp::execute_agent_operation(
        backend,
        "healthmd_export_execute",
        &serde_json::to_vec(&input).unwrap(),
        CancellationToken::new(),
    )
    .await
    .unwrap_err();
    assert_eq!(error.code, "approval_required");
    assert_eq!(store.revision().await.unwrap(), before);
    assert_eq!(credentials.0.writes.load(Ordering::SeqCst), writes);
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
}

#[tokio::test]
async fn actual_resume_backend_rejects_missing_job_before_listener_or_output() {
    let temporary = tempfile::TempDir::new().unwrap();
    let root = std::fs::canonicalize(temporary.path()).unwrap();
    let credentials = InjectedCredentials::default();
    let layout = StorageLayout { root: root.clone() };
    healthmd_client::storage::IdentityStore::new(layout.clone())
        .load_or_create(chrono::Utc::now())
        .unwrap();
    let client = Arc::new(
        DirectClient::open_planning_with_credentials(layout, credentials.clone()).unwrap(),
    );
    let source_id = Uuid::new_v4();
    let peer = Peer {
        host_installation_id: ControlUuid(client.identity.installation_id.0.to_string()),
        source_installation_id: ControlUuid(source_id.to_string()),
        platform: PeerPlatform::Apple,
    };
    let (store, output) = enroll(&root, &peer, &SystemPlanningClock.now()).await;
    let mut trust = TrustState::empty(client.identity.installation_id);
    trust
        .save_client(TrustedClient {
            installation_id: SwiftUuid(source_id),
            display_name: "Synthetic source".into(),
            platform: Some(WirePlatform::Ios),
            reconnect_secret: vec![13; 32],
            paired_at: chrono::Utc::now(),
            last_connected_at: chrono::Utc::now(),
            wake: None,
        })
        .unwrap();
    TrustStore::new(credentials.clone())
        .save(&trust)
        .await
        .unwrap();
    let writes = credentials.0.writes.load(Ordering::SeqCst);
    let occupied = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let backend: Arc<dyn HealthDataBackend> = Arc::new(DirectAgentBackend::new(
        client,
        Arc::new(ExistingFakeKey(AtomicUsize::new(0))),
        Some(source_id),
        occupied.local_addr().unwrap().port(),
        Duration::from_secs(5),
        Arc::new(Mutex::new(())),
    ));
    let input = serde_json::json!({"job_id":id(20)});
    let before = store.revision().await.unwrap();
    let error = crate::mcp::execute_agent_operation(
        backend,
        "healthmd_export_execution_resume",
        &serde_json::to_vec(&input).unwrap(),
        CancellationToken::new(),
    )
    .await
    .unwrap_err();
    assert_eq!(error.code, "permission_required");
    assert_eq!(store.revision().await.unwrap(), before);
    assert_eq!(credentials.0.writes.load(Ordering::SeqCst), writes);
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
}

#[tokio::test]
async fn actual_cancel_backend_rejects_missing_job_before_listener_or_output() {
    let temporary = tempfile::TempDir::new().unwrap();
    let root = std::fs::canonicalize(temporary.path()).unwrap();
    let credentials = InjectedCredentials::default();
    let layout = StorageLayout { root: root.clone() };
    healthmd_client::storage::IdentityStore::new(layout.clone())
        .load_or_create(chrono::Utc::now())
        .unwrap();
    let client = Arc::new(
        DirectClient::open_planning_with_credentials(layout, credentials.clone()).unwrap(),
    );
    let source_id = Uuid::new_v4();
    let peer = Peer {
        host_installation_id: ControlUuid(client.identity.installation_id.0.to_string()),
        source_installation_id: ControlUuid(source_id.to_string()),
        platform: PeerPlatform::Apple,
    };
    let (store, output) = enroll(&root, &peer, &SystemPlanningClock.now()).await;
    let mut trust = TrustState::empty(client.identity.installation_id);
    trust
        .save_client(TrustedClient {
            installation_id: SwiftUuid(source_id),
            display_name: "Synthetic source".into(),
            platform: Some(WirePlatform::Ios),
            reconnect_secret: vec![13; 32],
            paired_at: chrono::Utc::now(),
            last_connected_at: chrono::Utc::now(),
            wake: None,
        })
        .unwrap();
    TrustStore::new(credentials.clone())
        .save(&trust)
        .await
        .unwrap();
    let writes = credentials.0.writes.load(Ordering::SeqCst);
    let occupied = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let backend: Arc<dyn HealthDataBackend> = Arc::new(DirectAgentBackend::new(
        client,
        Arc::new(ExistingFakeKey(AtomicUsize::new(0))),
        Some(source_id),
        occupied.local_addr().unwrap().port(),
        Duration::from_secs(5),
        Arc::new(Mutex::new(())),
    ));
    let input = serde_json::json!({"job_id":id(20)});
    let before = store.revision().await.unwrap();
    let error = crate::mcp::execute_agent_operation(
        backend,
        "healthmd_export_execution_cancel",
        &serde_json::to_vec(&input).unwrap(),
        CancellationToken::new(),
    )
    .await
    .unwrap_err();
    assert_eq!(error.code, "permission_required");
    assert_eq!(store.revision().await.unwrap(), before);
    assert_eq!(credentials.0.writes.load(Ordering::SeqCst), writes);
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
}

// Keep both public transports and exact independently established decisions in one tracer.
#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn actual_direct_backend_cli_mcp_execute_and_recover_both_platforms() {
    for (platform, outcome) in [PeerPlatform::Apple, PeerPlatform::Android]
        .into_iter()
        .flat_map(|platform| {
            [
                ExecutionPeerOutcome::Complete,
                ExecutionPeerOutcome::DisconnectBeforeFinalize,
                ExecutionPeerOutcome::DisconnectThenCancel,
                ExecutionPeerOutcome::AcceptedThenCancel,
                ExecutionPeerOutcome::AcceptedThenResume,
                ExecutionPeerOutcome::UncertainThenResume,
                ExecutionPeerOutcome::UncertainThenStop,
                ExecutionPeerOutcome::UncertainDirectStop,
                ExecutionPeerOutcome::DisconnectAfterFirstPartition,
            ]
            .map(|outcome| (platform.clone(), outcome))
        })
    {
        let temporary = tempfile::TempDir::new().unwrap();
        let root = std::fs::canonicalize(temporary.path()).unwrap();
        let credentials = InjectedCredentials::default();
        let layout = StorageLayout { root: root.clone() };
        healthmd_client::storage::IdentityStore::new(layout.clone())
            .load_or_create(chrono::Utc::now())
            .unwrap();
        let client = Arc::new(
            DirectClient::open_planning_with_credentials(layout, credentials.clone()).unwrap(),
        );
        let source_id = Uuid::new_v4();
        let secret = vec![13; 32];
        let peer = Peer {
            host_installation_id: ControlUuid(client.identity.installation_id.0.to_string()),
            source_installation_id: ControlUuid(source_id.to_string()),
            platform: platform.clone(),
        };
        let time = SystemPlanningClock.now();
        let (store, output) = enroll(&root, &peer, &time).await;
        let mut trust = TrustState::empty(client.identity.installation_id);
        trust
            .save_client(TrustedClient {
                installation_id: SwiftUuid(source_id),
                display_name: "Synthetic source".into(),
                platform: Some(if platform == PeerPlatform::Apple {
                    WirePlatform::Ios
                } else {
                    WirePlatform::Android
                }),
                reconnect_secret: secret.clone(),
                paired_at: chrono::Utc::now(),
                last_connected_at: chrono::Utc::now(),
                wake: None,
            })
            .unwrap();
        TrustStore::new(credentials.clone())
            .save(&trust)
            .await
            .unwrap();
        let stored_trust = TrustStore::new(credentials.clone())
            .load(client.identity.installation_id)
            .await
            .unwrap();
        let writes = credentials.0.writes.load(Ordering::SeqCst);
        let probe = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);
        let key = Arc::new(ExistingFakeKey(AtomicUsize::new(0)));
        let backend: Arc<dyn HealthDataBackend> = Arc::new(DirectAgentBackend::new(
            Arc::clone(&client),
            key.clone(),
            Some(source_id),
            port,
            Duration::from_secs(10),
            Arc::new(Mutex::new(())),
        ));
        let app = Arc::new(HealthMdApplication::new(
            Arc::clone(&backend),
            SurfaceProfile::LocalDirect,
        ));
        let rpc = JsonRpcSession::new(app.session(CallerIdentity::local()));
        for profile in [
            SurfaceProfile::LocalReadOnly,
            SurfaceProfile::RemoteReadOnly,
        ] {
            let app = Arc::new(HealthMdApplication::new(Arc::clone(&backend), profile));
            let session = app.session(CallerIdentity::local());
            assert!(!session.list_tools().iter().any(|v| matches!(
                v["name"].as_str(),
                Some(
                    "healthmd_export_plan"
                        | "healthmd_export_approval"
                        | "healthmd_export_execute"
                        | "healthmd_export_execution_resume"
                        | "healthmd_export_execution_cancel"
                )
            )));
            assert!(
                session
                    .call_tool(
                        "healthmd_export_plan",
                        arguments(&peer),
                        CancellationToken::new(),
                        None
                    )
                    .await
                    .is_err()
            );
        }
        let mut invalid = arguments(&peer);
        invalid["approve"] = serde_json::json!(true);
        assert!(
            crate::mcp::execute_agent_operation(
                Arc::clone(&backend),
                "healthmd_export_plan",
                &serde_json::to_vec(&invalid).unwrap(),
                CancellationToken::new()
            )
            .await
            .is_err()
        );
        let mut invalid = arguments(&peer);
        invalid["native_authority_reference"] = Value::Null;
        assert!(
            crate::mcp::execute_agent_operation(
                Arc::clone(&backend),
                "healthmd_export_plan",
                &serde_json::to_vec(&invalid).unwrap(),
                CancellationToken::new()
            )
            .await
            .is_err()
        );
        assert!(
            crate::mcp::execute_agent_operation(
                Arc::clone(&backend),
                "healthmd_export_plan",
                b"\xff",
                CancellationToken::new()
            )
            .await
            .is_err()
        );
        // Strict raw RPC path rejects a duplicate DTO field before backend or native storage.
        let mut duplicate = arguments(&peer).to_string();
        duplicate.pop();
        duplicate.push_str(",\"metric_ids\":[\"steps\"]}");
        let raw = format!(
            "{{\"jsonrpc\":\"2.0\",\"id\":55,\"method\":\"tools/call\",\"params\":{{\"name\":\"healthmd_export_plan\",\"arguments\":{duplicate}}}}}"
        );
        let rejected: Value =
            serde_json::from_str(&rpc.handle(&raw, CancellationToken::new()).await.unwrap())
                .unwrap();
        assert_eq!(rejected["error"]["code"], -32602);
        assert_eq!(key.0.load(Ordering::SeqCst), 0);
        assert_eq!(store.revision().await.unwrap(), 1);

        let (consent_sender, consent_receiver) = oneshot::channel::<()>();
        let source_peer = peer.clone();
        let source = tokio::spawn(async move {
            let mut native = NativeFake::new(source_peer, time);
            for _ in 0..2 {
                let (mut channel, negotiation) = fake_session(port, &native, &secret).await;
                answer_discovery(&mut channel, negotiation, &native).await;
                let Message::PlanRequest(request) =
                    channel.receive_v4(negotiation).await.unwrap().message
                else {
                    panic!("expected plan");
                };
                let plan = native.plan(*request).await.unwrap();
                channel
                    .send_v4(
                        &Envelope::new(Message::PlanResponse(Box::new(plan))),
                        negotiation,
                    )
                    .await
                    .unwrap();
            }
            consent_receiver.await.unwrap();
            native.store_exact_native_decision();
            for index in 0..2 {
                let (mut channel, negotiation) = fake_session(port, &native, &secret).await;
                answer_discovery(&mut channel, negotiation, &native).await;
                if index == 0 {
                    let Message::ApprovalRequest(request) =
                        channel.receive_v4(negotiation).await.unwrap().message
                    else {
                        panic!("expected relay");
                    };
                    let approval = native.relay_approval(*request).await.unwrap();
                    channel
                        .send_v4(
                            &Envelope::new(Message::ApprovalResponse(Box::new(approval))),
                            negotiation,
                        )
                        .await
                        .unwrap();
                }
            }
            let mut executions = Vec::new();
            for _ in 0..2 {
                let (mut channel, negotiation) = fake_session(port, &native, &secret).await;
                executions.push(
                    answer_approved_execute(&mut channel, negotiation, &mut native, outcome).await,
                );
            }
            if !matches!(
                outcome,
                ExecutionPeerOutcome::DisconnectThenCancel
                    | ExecutionPeerOutcome::AcceptedThenCancel
                    | ExecutionPeerOutcome::UncertainDirectStop
            ) {
                for execution in &mut executions {
                    let (mut channel, negotiation) = fake_session(port, &native, &secret).await;
                    *execution = answer_retained_resume(
                        &mut channel,
                        negotiation,
                        execution.clone(),
                        outcome == ExecutionPeerOutcome::UncertainThenStop,
                    )
                    .await;
                }
            }
            for execution in executions {
                let (mut channel, negotiation) = fake_session(port, &native, &secret).await;
                answer_retained_cancel(&mut channel, negotiation, execution, outcome).await;
            }
        });
        let input = arguments(&peer);
        let cli_plan = crate::mcp::execute_agent_operation(
            Arc::clone(&backend),
            "healthmd_export_plan",
            &serde_json::to_vec(&input).unwrap(),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        let mcp_plan = rpc_call(&rpc, "healthmd_export_plan", input, 1).await;
        assert_eq!(
            cli_plan["predicted_paths"],
            serde_json::json!(["2026/2026-01-01.json", "2026/2026-01-02.json"])
        );
        assert_eq!(comparable_plan(cli_plan), comparable_plan(mcp_plan.clone()));
        let plan: ExportPlan = serde_json::from_value(mcp_plan).unwrap();
        store
            .record_local_decision(
                3,
                &plan.plan_id,
                &SystemPlanningClock,
                &ExplicitFakeLocalConsent,
            )
            .await
            .unwrap();
        consent_sender.send(()).unwrap();
        let execution_plan_id = plan.plan_id.clone();
        let execution_paths = plan.predicted_paths.clone();
        let request = ApprovalRequest {
            schema: ApprovalRequestSchema::HealthmdAgentApprovalRequest,
            schema_version: 1,
            plan_id: plan.plan_id.clone(),
            request_id: id(100),
            binding: approval_binding(&plan),
        };
        let cli_approval = crate::mcp::execute_agent_operation(
            Arc::clone(&backend),
            "healthmd_export_approval",
            &serde_json::to_vec(&request).unwrap(),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        let mcp_approval = rpc_call(
            &rpc,
            "healthmd_export_approval",
            serde_json::to_value(request).unwrap(),
            2,
        )
        .await;
        assert_eq!(cli_approval, mcp_approval);
        let cli_input = serde_json::json!({"plan_id":execution_plan_id,"job_id":id(200),"idempotency_key":id(201),"request_id":id(202)});
        let cli_result = crate::mcp::execute_agent_operation(
            Arc::clone(&backend),
            "healthmd_export_execute",
            &serde_json::to_vec(&cli_input).unwrap(),
            CancellationToken::new(),
        )
        .await;
        let cli_execution = if outcome == ExecutionPeerOutcome::Complete {
            cli_result.unwrap()
        } else {
            assert!(
                cli_result.is_err(),
                "Interrupted Execute cannot report completion"
            );
            Value::Null
        };
        let mcp_input = serde_json::json!({"plan_id":execution_plan_id,"job_id":id(203),"idempotency_key":id(204),"request_id":id(205)});
        let mcp_execution = if outcome == ExecutionPeerOutcome::Complete {
            rpc_call(&rpc, "healthmd_export_execute", mcp_input, 3).await
        } else {
            let raw = serde_json::json!({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"healthmd_export_execute","arguments":mcp_input}}).to_string();
            let response: Value =
                serde_json::from_str(&rpc.handle(&raw, CancellationToken::new()).await.unwrap())
                    .unwrap();
            assert!(response.get("error").is_none());
            assert_eq!(
                response["result"]["isError"], true,
                "Interrupted MCP Execute cannot report completion"
            );
            Value::Null
        };
        // Durable host commits can precede source completion. Preserve their exact bytes
        // across reconnect; an interrupted call still cannot return a terminal receipt.
        let before_recovery: Vec<_> = execution_paths
            .iter()
            .enumerate()
            .map(|(index, path)| {
                let path = output.join(&path.0);
                if matches!(
                    outcome,
                    ExecutionPeerOutcome::AcceptedThenCancel
                        | ExecutionPeerOutcome::UncertainDirectStop
                        | ExecutionPeerOutcome::AcceptedThenResume
                        | ExecutionPeerOutcome::UncertainThenResume
                        | ExecutionPeerOutcome::UncertainThenStop
                ) || (outcome == ExecutionPeerOutcome::DisconnectAfterFirstPartition
                    && index == 1)
                {
                    assert!(
                        !path.exists(),
                        "Accepted-only cancellation cannot create output"
                    );
                    None
                } else {
                    let bytes = std::fs::read(path).unwrap();
                    assert_eq!(bytes, b"{\"synthetic\":true}");
                    Some(bytes)
                }
            })
            .collect();
        if matches!(
            outcome,
            ExecutionPeerOutcome::UncertainThenResume
                | ExecutionPeerOutcome::UncertainThenStop
                | ExecutionPeerOutcome::UncertainDirectStop
        ) {
            for job in [id(200), id(203)] {
                let value: Value = serde_json::from_slice(
                    &std::fs::read(
                        root.join("agent-host-v1")
                            .join(format!("attempt-{}.json", job.0)),
                    )
                    .unwrap(),
                )
                .unwrap();
                assert_eq!(value["attempt"]["schema_version"], 1);
                assert!(
                    value["attempt"].get("accepted_receipt").is_none(),
                    "Lost acceptance cannot be invented locally"
                );
            }
        }
        if outcome == ExecutionPeerOutcome::UncertainDirectStop {
            let authority: ControlUuid = serde_json::from_value(
                cli_approval["binding"]["authority_references"]["host"]["authority_id"].clone(),
            )
            .unwrap();
            store
                .revoke_local(store.revision().await.unwrap(), &authority)
                .await
                .unwrap();
        }
        if !matches!(
            outcome,
            ExecutionPeerOutcome::DisconnectThenCancel
                | ExecutionPeerOutcome::AcceptedThenCancel
                | ExecutionPeerOutcome::UncertainDirectStop
        ) {
            let cli_resume = crate::mcp::execute_agent_operation(
                Arc::clone(&backend),
                "healthmd_export_execution_resume",
                &serde_json::to_vec(&serde_json::json!({"job_id":id(200)})).unwrap(),
                CancellationToken::new(),
            )
            .await;
            if outcome == ExecutionPeerOutcome::UncertainThenStop {
                assert!(cli_resume.is_err(), "Acceptance is not completed recovery");
                let raw = serde_json::json!({"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"healthmd_export_execution_resume","arguments":{"job_id":id(203)}}}).to_string();
                let response: Value = serde_json::from_str(
                    &rpc.handle(&raw, CancellationToken::new()).await.unwrap(),
                )
                .unwrap();
                assert!(response.get("error").is_none());
                assert_eq!(response["result"]["isError"], true);
            } else {
                let cli_resume = cli_resume.unwrap();
                let mcp_resume = rpc_call(
                    &rpc,
                    "healthmd_export_execution_resume",
                    serde_json::json!({"job_id":id(203)}),
                    4,
                )
                .await;
                if outcome == ExecutionPeerOutcome::Complete {
                    assert_eq!(cli_resume, cli_execution);
                    assert_eq!(mcp_resume, mcp_execution);
                }
                for result in [&cli_resume, &mcp_resume] {
                    assert_eq!(result["status"], "complete");
                    assert_eq!(result["source_acknowledged"], true);
                    assert_eq!(result["artifact_count"], 2);
                    assert_eq!(result["committed_partition_count"], 2);
                    assert_eq!(result["binding"], cli_approval["binding"]);
                }
            }
        }
        if matches!(
            outcome,
            ExecutionPeerOutcome::UncertainThenResume | ExecutionPeerOutcome::UncertainThenStop
        ) {
            for job in [id(200), id(203)] {
                let value: Value = serde_json::from_slice(
                    &std::fs::read(
                        root.join("agent-host-v1")
                            .join(format!("attempt-{}.json", job.0)),
                    )
                    .unwrap(),
                )
                .unwrap();
                assert_eq!(value["attempt"]["schema_version"], 2);
                assert_eq!(value["attempt"]["accepted_receipt"]["status"], "accepted");
            }
        }
        let cli_cancel = crate::mcp::execute_agent_operation(
            Arc::clone(&backend),
            "healthmd_export_execution_cancel",
            &serde_json::to_vec(&serde_json::json!({"job_id":id(200)})).unwrap(),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        let mcp_cancel = rpc_call(
            &rpc,
            "healthmd_export_execution_cancel",
            serde_json::json!({"job_id":id(203)}),
            5,
        )
        .await;
        for result in [&cli_cancel, &mcp_cancel] {
            assert_eq!(result["schema"], "healthmd.agent_source_stop_result");
            assert_eq!(result["schema_version"], 1);
            assert_eq!(result["output_verified"], false);
            assert_eq!(
                result["source_receipt"]["status"],
                if matches!(
                    outcome,
                    ExecutionPeerOutcome::DisconnectThenCancel
                        | ExecutionPeerOutcome::AcceptedThenCancel
                        | ExecutionPeerOutcome::UncertainDirectStop
                        | ExecutionPeerOutcome::UncertainThenStop
                ) {
                    "cancelled"
                } else {
                    "complete"
                }
            );
            assert_eq!(result["source_receipt"]["source_acknowledged"], true);
            assert_eq!(result["source_receipt"]["binding"], cli_approval["binding"]);
        }
        source.await.unwrap();
        // A second Cancel is a local historical read, even with its listener port occupied.
        let _occupied = TcpListener::bind(("0.0.0.0", port)).await.unwrap();
        let history = crate::mcp::execute_agent_operation(
            Arc::clone(&backend),
            "healthmd_export_execution_cancel",
            &serde_json::to_vec(&serde_json::json!({"job_id":id(200)})).unwrap(),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(history, cli_cancel);
        let history = rpc_call(
            &rpc,
            "healthmd_export_execution_cancel",
            serde_json::json!({"job_id":id(203)}),
            6,
        )
        .await;
        assert_eq!(history, mcp_cancel);
        for (path, before) in execution_paths.iter().zip(&before_recovery) {
            match before {
                Some(bytes) => assert_eq!(&std::fs::read(output.join(&path.0)).unwrap(), bytes),
                None if matches!(
                    outcome,
                    ExecutionPeerOutcome::AcceptedThenCancel
                        | ExecutionPeerOutcome::UncertainDirectStop
                        | ExecutionPeerOutcome::UncertainThenStop
                ) =>
                {
                    assert!(!output.join(&path.0).exists());
                }
                None => assert_eq!(
                    std::fs::read(output.join(&path.0)).unwrap(),
                    b"{\"synthetic\":true}"
                ),
            }
        }
        assert_eq!(
            TrustStore::new(credentials.clone())
                .load(client.identity.installation_id)
                .await
                .unwrap(),
            stored_trust
        );
        assert_eq!(credentials.0.writes.load(Ordering::SeqCst), writes);
        assert!(credentials.0.reads.load(Ordering::SeqCst) >= 16);
        assert!(key.0.load(Ordering::SeqCst) > 0);
        if matches!(
            outcome,
            ExecutionPeerOutcome::AcceptedThenCancel
                | ExecutionPeerOutcome::UncertainThenStop
                | ExecutionPeerOutcome::UncertainDirectStop
        ) {
            assert_eq!(std::fs::read_dir(&output).unwrap().count(), 0);
            for result in [&cli_cancel, &mcp_cancel] {
                assert_eq!(result["source_receipt"]["artifact_count"], 0);
                assert_eq!(result["source_receipt"]["committed_partition_count"], 0);
                assert_eq!(result["source_receipt"]["manifest_sha256"], "0".repeat(64));
                assert_eq!(result["source_receipt"]["frontier_sha256"], "0".repeat(64));
            }
        } else {
            assert_eq!(std::fs::read_dir(output.join("2026")).unwrap().count(), 2);
        }
    }
}

#[tokio::test]
async fn native_key_injection_has_a_separate_read_only_account_not_the_deployed_trust_helper() {
    let credentials = InjectedCredentials::default();
    let host = id(2);
    // Local test seed; no actual native account, UI, provisioning or OS credential operation.
    let account = format!("agent-host-issuer-v1-{}", host.0);
    let secret = FakeProtectedKey.load_existing(&host).await.unwrap();
    credentials.0.values.lock().unwrap().insert(account, secret);
    let key = NativeProtectedHostKey(credentials.clone());
    assert!(key.load_existing(&host).await.is_ok());
    assert_eq!(credentials.0.reads.load(Ordering::SeqCst), 1);
    assert_eq!(credentials.0.writes.load(Ordering::SeqCst), 0);
}
