//! New encrypted channels recovering only issuer-owned original synthetic job facts.
use super::*;
use crate::agent_host::{
    HostAuthorityStore,
    output::{NativeBinding, OutputTransaction},
};
use std::path::{Path, PathBuf};
use transfer_tests::{TransferCase, payload};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RecoveryCase {
    Exact,
    AfterPlanExpiry,
    BadAccepted,
    BadManifest,
    CorruptPartition,
    WrongFrontier,
    MissingOutput,
    MissingTransfer,
    RevokedHost,
    DeleteOutputAtFinalFence,
    DeleteCheckpointAtFinalFence,
    CorruptPartitionAtFinalFence,
    DeleteLockAtFinalFence,
    CancelAtFinalClock,
}
impl RecoveryCase {
    fn final_fence(self) -> bool {
        matches!(
            self,
            Self::DeleteOutputAtFinalFence
                | Self::DeleteCheckpointAtFinalFence
                | Self::CorruptPartitionAtFinalFence
                | Self::DeleteLockAtFinalFence
        )
    }
    fn before_send(self) -> bool {
        matches!(
            self,
            Self::CorruptPartition
                | Self::WrongFrontier
                | Self::MissingOutput
                | Self::MissingTransfer
                | Self::RevokedHost
        )
    }
}

struct CountedRecoveryTrust<'a> {
    client: &'a DirectClient<MemoryCredentials>,
    calls: AtomicUsize,
    attack: Option<(usize, RecoveryCase, PathBuf, PathBuf, PathBuf)>,
}
#[async_trait::async_trait]
impl CurrentBridgeTrust for CountedRecoveryTrust<'_> {
    async fn require_current(
        &self,
        selected: Option<Uuid>,
        expected: &TrustedClient,
    ) -> Result<(), ClientError> {
        self.client.require_current(selected, expected).await?;
        let count = self.calls.fetch_add(1, Ordering::SeqCst) + 1;
        if let Some((at, case, output, checkpoint, partition)) = &self.attack {
            if count == *at {
                match case {
                    RecoveryCase::DeleteOutputAtFinalFence => std::fs::remove_file(output).unwrap(),
                    RecoveryCase::DeleteCheckpointAtFinalFence => {
                        std::fs::remove_file(checkpoint).unwrap();
                    }
                    RecoveryCase::CorruptPartitionAtFinalFence => {
                        std::fs::write(partition, b"corrupt").unwrap();
                    }
                    RecoveryCase::DeleteLockAtFinalFence => {
                        std::fs::remove_file(output.parent().unwrap().join("outputs.lock"))
                            .unwrap();
                    }
                    _ => unreachable!(),
                }
            }
        }
        Ok(())
    }
}

struct CountedRecoveryClock {
    time: UtcTimestamp,
    calls: AtomicUsize,
    cancel: Option<(usize, CancellationToken)>,
}
impl crate::agent_planning::PlanningClock for CountedRecoveryClock {
    fn now(&self) -> UtcTimestamp {
        let call = self.calls.fetch_add(1, Ordering::SeqCst) + 1;
        if let Some((at, token)) = &self.cancel {
            if call == *at {
                token.cancel();
            }
        }
        self.time.clone()
    }
}

async fn approved_request(store: &HostAuthorityStore, peer: &v4::Peer) -> ExecuteRequest {
    let clock = FixedClock(now());
    let planner = HostPlanner::new(store.clone());
    let mut native = NativeFake::new(peer.clone(), now());
    let plan = planner
        .plan(&mut native, input(peer), &clock)
        .await
        .unwrap();
    store
        .record_local_decision(
            store.revision().await.unwrap(),
            &plan.plan_id,
            &clock,
            &ExplicitFakeLocalConsent,
        )
        .await
        .unwrap();
    native.store_exact_native_decision();
    let approval = planner
        .relay_approval(
            &mut native,
            ApprovalRequest {
                schema: ApprovalRequestSchema::HealthmdAgentApprovalRequest,
                schema_version: 1,
                plan_id: plan.plan_id.clone(),
                request_id: id(21),
                binding: approval_binding(&plan),
            },
            &clock,
        )
        .await
        .unwrap();
    ExecuteRequest {
        schema: ExecuteRequestSchema::HealthmdAgentExecuteRequest,
        schema_version: 1,
        request_id: id(22),
        job_id: id(20),
        idempotency_key: id(19),
        plan,
        approval,
    }
}

async fn retained_fixture(
    store: &HostAuthorityStore,
    output: &Path,
    binding: &NativeBinding,
    prefix: usize,
    case: RecoveryCase,
) -> Vec<u8> {
    let mut transaction =
        OutputTransaction::open(store, binding, || async { Ok(output.to_path_buf()) })
            .await
            .unwrap();
    transaction
        .save(|| async { Ok(output.to_path_buf()) })
        .await
        .unwrap();
    let session_id = id(30);
    let mut frontier = TransferFrontier::new(
        &binding.request.job_id,
        &binding.manifest.request_sha256,
        &document_digest(&binding.manifest).unwrap(),
        &session_id,
    )
    .unwrap();
    let mut records = vec![];
    let mut index = 0_usize;
    for item in &binding.manifest.artifacts {
        let Artifact::Branch1(item) = item else {
            unreachable!()
        };
        for (segment, bytes) in payload(TransferCase::Exact).chunks(9).enumerate() {
            if index >= prefix {
                break;
            }
            let partition = TransferFrontierPartition {
                partition_index: i64::try_from(index).unwrap(),
                transfer_id: id(31 + u64::try_from(index).unwrap()),
                artifact_id: item.artifact_id.clone(),
                artifact_offset: i64::try_from(segment * 9).unwrap(),
                byte_count: i64::try_from(bytes.len()).unwrap(),
                chunk_count: 1,
                sha256: Digest(healthmd_protocol::transfer::sha256_hex(bytes)),
            };
            let name = format!(".output-{}.stage", Uuid::new_v4());
            let mut file = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(transaction.stage_path(&name).unwrap())
                .unwrap();
            std::io::Write::write_all(&mut file, bytes).unwrap();
            file.sync_all().unwrap();
            frontier = frontier.appending(&partition).unwrap();
            records.push(serde_json::json!({"partition":partition,"stage_name":name}));
            index += 1;
        }
    }
    assert_eq!(index, prefix);
    let session = v2::TransferSession {
        session_id: Uuid::parse_str(&session_id.0).unwrap(),
        job_id: Uuid::parse_str(&binding.request.job_id.0).unwrap(),
        request_fingerprint: binding.manifest.request_sha256.0.clone(),
        peer_binding: v2::PeerBinding {
            source_installation_id: Uuid::parse_str(
                &binding.request.plan.intent.peer.source_installation_id.0,
            )
            .unwrap(),
            destination_installation_id: Uuid::parse_str(
                &binding.request.plan.intent.peer.host_installation_id.0,
            )
            .unwrap(),
        },
        partition_target_bytes: 50_331_648,
        created_at: chrono::DateTime::from_timestamp(now().seconds().unwrap(), 0).unwrap(),
    };
    let journal = serde_json::json!({"schema":"healthmd.agent_host_transfer","schema_version":1,
        "job_id":binding.request.job_id,"request_sha256":binding.manifest.request_sha256,
        "manifest_sha256":document_digest(&binding.manifest).unwrap(),"session":session,"partitions":records,
        "frontier_sha256":if case == RecoveryCase::WrongFrontier { Digest("f".repeat(64)) } else {frontier.sha256().clone()},
        "final_ack_may_have_sent":false});
    let bytes = transaction
        .save_transfer(&journal, None, || async { Ok(output.to_path_buf()) })
        .await
        .unwrap();
    if case == RecoveryCase::CorruptPartition {
        let name = journal["partitions"][0]["stage_name"].as_str().unwrap();
        std::fs::write(transaction.stage_path(name).unwrap(), b"corrupt").unwrap();
    }
    bytes
}

async fn recovery_peer(
    port: u16,
    saved: FakeMobileTrust,
    peer: v4::Peer,
    platform: PeerPlatform,
    binding: NativeBinding,
    prefix: usize,
    case: RecoveryCase,
) {
    let (mut channel, negotiation) = output_channel(port, saved, &peer, platform).await;
    let received =
        tokio::time::timeout(Duration::from_secs(3), channel.receive_v4(negotiation)).await;
    if case.before_send() {
        assert!(
            !matches!(received, Ok(Ok(_))),
            "rejected recovery emitted a wire control: {case:?}"
        );
        return;
    }
    let Message::ResumeRequest(request) = received.unwrap().unwrap().message else {
        panic!("only Resume is permitted")
    };
    assert_eq!(request.job_id, binding.request.job_id);
    assert_eq!(request.binding, approval_binding(&binding.request.plan));
    assert_eq!(request.destination, binding.request.plan.intent.destination);
    assert_eq!(request.peer, binding.request.plan.intent.peer);
    assert_eq!(request.request_sha256, binding.manifest.request_sha256);
    assert_eq!(
        request.manifest_sha256,
        document_digest(&binding.manifest).unwrap()
    );
    assert_eq!(request.committed_partition_count, prefix as u64);
    let mut accepted = binding.accepted.clone();
    if case == RecoveryCase::BadAccepted {
        accepted.expires_at = later(&accepted.expires_at, 1);
    }
    channel
        .send_v4(
            &Envelope::new(Message::ExecutionReceipt(Box::new(accepted))),
            negotiation,
        )
        .await
        .unwrap();
    if case == RecoveryCase::BadAccepted {
        transfer_tests::no_response(&mut channel, platform).await;
        return;
    }
    let mut manifest = binding.manifest.clone();
    if case == RecoveryCase::BadManifest {
        manifest.job_id = id(999);
    }
    channel
        .send_v4(
            &Envelope::new(Message::ArtifactManifest(Box::new(manifest))),
            negotiation,
        )
        .await
        .unwrap();
    if case == RecoveryCase::BadManifest {
        transfer_tests::no_response(&mut channel, platform).await;
        return;
    }
    if case.final_fence() || case == RecoveryCase::CancelAtFinalClock {
        transfer_tests::no_response(&mut channel, platform).await;
        return;
    }
    transfer_tests::send_transfer_from(
        &mut channel,
        &binding.request,
        platform,
        TransferCase::Confirmed,
        prefix as u64,
    )
    .await;
}

async fn prepare_rejection(
    store: &HostAuthorityStore,
    request: &ExecuteRequest,
    issuer: &Path,
    checkpoint: &Path,
    case: RecoveryCase,
) {
    if case == RecoveryCase::MissingOutput {
        std::fs::remove_file(issuer.join(format!("output-{}.json", request.job_id.0))).unwrap();
    }
    if case == RecoveryCase::MissingTransfer {
        std::fs::remove_file(checkpoint).unwrap();
    }
    if case == RecoveryCase::RevokedHost {
        store
            .revoke_local(
                store.revision().await.unwrap(),
                &request.plan.authority_references.host.authority_id,
            )
            .await
            .unwrap();
    }
}

async fn finish_recovery(
    owner: &mut crate::agent_bridge::HostExecution<'_, '_, '_>,
    store: &HostAuthorityStore,
    request: &ExecuteRequest,
    output: &Path,
) {
    assert!(matches!(
        OutputTransaction::open_retained(store, &request.job_id).await,
        Err(ClientError::AgentStoreBusy)
    ));
    let received = Box::pin(owner.receive_and_commit()).await.unwrap();
    assert_eq!(received.committed_partition_count, 4);
    assert_eq!(received.receipts.len(), 2);
    let completed = Box::pin(owner.confirm_source_completion()).await.unwrap();
    assert!(completed.source_acknowledged);
    assert_eq!(completed.expires_at, later(&now(), 604_800));
    for path in &request.plan.predicted_paths {
        assert_eq!(
            std::fs::read(output.join(&path.0)).unwrap(),
            payload(TransferCase::Exact)
        );
    }
}

async fn recover_case(
    platform: PeerPlatform,
    prefix: usize,
    case: RecoveryCase,
    final_call: Option<usize>,
) -> (usize, usize) {
    let (_temporary, client, saved, peer) = stored_pair(platform).await;
    let (store, output) = enroll(&client.layout.root, &peer, &now()).await;
    let request = approved_request(&store, &peer).await;
    let binding = transfer_tests::binding(&request, platform, TransferCase::Exact);
    let original = Box::pin(retained_fixture(&store, &output, &binding, prefix, case)).await;
    let issuer = client.layout.root.join("agent-host-v1");
    let checkpoint = issuer.join(format!("transfer-{}.json", request.job_id.0));
    prepare_rejection(&store, &request, &issuer, &checkpoint, case).await;
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let source = tokio::spawn(recovery_peer(
        port,
        saved,
        peer.clone(),
        platform,
        binding,
        prefix,
        case,
    ));
    let cancellation = CancellationToken::new();
    let bridge = connect_bound_bridge(
        &client,
        Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
        &listener,
        Duration::from_secs(10),
        cancellation.clone(),
    )
    .await
    .unwrap();
    let retained: serde_json::Value = serde_json::from_slice(&original).unwrap();
    let partition = retained["journal"]["partitions"]
        .as_array()
        .unwrap()
        .first()
        .map(|record| issuer.join(record["stage_name"].as_str().unwrap()))
        .unwrap_or_default();
    let trust = CountedRecoveryTrust {
        client: &client,
        calls: AtomicUsize::new(0),
        attack: final_call.filter(|_| case.final_fence()).map(|at| {
            (
                at,
                case,
                issuer.join(format!("output-{}.json", request.job_id.0)),
                checkpoint.clone(),
                partition,
            )
        }),
    };
    let mut bridge = bridge.with_test_trust(&trust);
    let clock = CountedRecoveryClock {
        time: if case == RecoveryCase::AfterPlanExpiry {
            later(&request.plan.expires_at, 1)
        } else {
            now()
        },
        calls: AtomicUsize::new(0),
        cancel: final_call
            .filter(|_| case == RecoveryCase::CancelAtFinalClock)
            .map(|at| (at, cancellation)),
    };
    let result = Box::pin(bridge.resume_execution(&store, request.job_id.clone(), &clock)).await;
    let admission_calls = trust.calls.load(Ordering::SeqCst);
    let admission_clock_calls = clock.calls.load(Ordering::SeqCst);
    if let Some(at) = final_call {
        let observed = if case == RecoveryCase::CancelAtFinalClock {
            admission_clock_calls
        } else {
            admission_calls
        };
        assert_eq!(
            observed, at,
            "attack must run at the absolute final callback/clock read"
        );
    }
    if matches!(case, RecoveryCase::Exact | RecoveryCase::AfterPlanExpiry) {
        let mut owner = result.unwrap();
        Box::pin(finish_recovery(&mut owner, &store, &request, &output)).await;
    } else {
        assert!(result.is_err(), "accepted {case:?}");
        if checkpoint.exists() {
            assert_eq!(std::fs::read(&checkpoint).unwrap(), original);
        }
        assert_eq!(std::fs::read_dir(&output).unwrap().count(), 0);
    }
    source.await.unwrap();
    (admission_calls, admission_clock_calls)
}

#[tokio::test]
async fn authenticated_resume_reconstructs_original_prefix_on_new_channels() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for prefix in [0, 1, 2, 4] {
            Box::pin(recover_case(platform, prefix, RecoveryCase::Exact, None)).await;
        }
        Box::pin(recover_case(
            platform,
            1,
            RecoveryCase::AfterPlanExpiry,
            None,
        ))
        .await;
    }
}
#[tokio::test]
async fn authenticated_resume_rejects_changed_or_missing_evidence_without_execute() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            RecoveryCase::BadAccepted,
            RecoveryCase::BadManifest,
            RecoveryCase::CorruptPartition,
            RecoveryCase::WrongFrontier,
            RecoveryCase::MissingOutput,
            RecoveryCase::MissingTransfer,
            RecoveryCase::RevokedHost,
        ] {
            Box::pin(recover_case(platform, 1, case, None)).await;
        }
    }
}

#[tokio::test]
async fn authenticated_resume_rejects_retained_loss_at_absolute_final_callback() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let (final_call, _) = Box::pin(recover_case(platform, 1, RecoveryCase::Exact, None)).await;
        for case in [
            RecoveryCase::DeleteOutputAtFinalFence,
            RecoveryCase::DeleteCheckpointAtFinalFence,
            RecoveryCase::CorruptPartitionAtFinalFence,
            RecoveryCase::DeleteLockAtFinalFence,
        ] {
            Box::pin(recover_case(platform, 1, case, Some(final_call))).await;
        }
    }
}

#[tokio::test]
async fn authenticated_resume_rejects_cancellation_at_absolute_final_clock() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let (_, final_clock) = Box::pin(recover_case(platform, 1, RecoveryCase::Exact, None)).await;
        Box::pin(recover_case(
            platform,
            1,
            RecoveryCase::CancelAtFinalClock,
            Some(final_clock),
        ))
        .await;
    }
}
