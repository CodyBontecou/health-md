//! CLI/portable-MCP public adapters through the actual `DirectAgentBackend`, host store and
//! encrypted loopback transport. Source and consent/keys are synthetic, not native coverage.
#![cfg(unix)] // Positive store/adapter tracers do not imply Windows issuer support.
use super::*;
use healthmd_client as client_crate;
#[path = "../../healthmd-client/tests/support/agent.rs"]
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

// Keep both public transports and exact independently established decisions in one tracer.
#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn actual_direct_backend_cli_mcp_plan_semantics_and_exact_approval_parity_both_platforms() {
    for platform in [PeerPlatform::Apple, PeerPlatform::Android] {
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
                Some("healthmd_export_plan" | "healthmd_export_approval")
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
                &SystemPlanningClock.now(),
                &ExplicitFakeLocalConsent,
            )
            .await
            .unwrap();
        consent_sender.send(()).unwrap();
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
        source.await.unwrap();
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
        assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
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
