//! Authenticated synthetic native execution; no phone APIs or real health data.
use super::*;
use crate::agent_bridge::CurrentBridgeTrust;
use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};
use std::sync::{
    Mutex,
    atomic::{AtomicUsize, Ordering},
};

#[path = "agent_transfer_tests.rs"]
mod transfer_tests;
struct AdversarialOutputTrust<'a> {
    inner: &'a dyn CurrentBridgeTrust,
    remaining: AtomicUsize,
    action: Mutex<Option<Box<dyn FnOnce() + Send>>>,
    trigger: Mutex<Option<Box<dyn Fn() -> bool + Send>>>,
}
impl<'a> AdversarialOutputTrust<'a> {
    fn new(inner: &'a dyn CurrentBridgeTrust) -> Self {
        Self {
            inner,
            remaining: AtomicUsize::new(0),
            action: Mutex::new(None),
            trigger: Mutex::new(None),
        }
    }
    fn arm_when(
        &self,
        trigger: impl Fn() -> bool + Send + 'static,
        action: impl FnOnce() + Send + 'static,
    ) {
        *self.trigger.lock().unwrap() = Some(Box::new(trigger));
        *self.action.lock().unwrap() = Some(Box::new(action));
    }
    fn arm(&self, count: usize, action: impl FnOnce() + Send + 'static) {
        *self.action.lock().unwrap() = Some(Box::new(action));
        self.remaining.store(count, Ordering::SeqCst);
    }
}
#[async_trait::async_trait]
impl CurrentBridgeTrust for AdversarialOutputTrust<'_> {
    async fn require_current(
        &self,
        requested: Option<Uuid>,
        expected: &TrustedClient,
    ) -> Result<(), ClientError> {
        self.inner.require_current(requested, expected).await?;
        if self
            .remaining
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            == Ok(1)
            || self
                .trigger
                .lock()
                .unwrap()
                .as_ref()
                .is_some_and(|trigger| trigger())
        {
            self.trigger.lock().unwrap().take();
            let action = self.action.lock().unwrap().take().unwrap();
            tokio::task::yield_now().await;
            action();
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum OutputCase {
    Transfer(transfer_tests::TransferCase),
    ExactReplay,
    WrongAccepted,
    WrongManifest,
    WrongInput,
    NonregularInput,
    FifoInput,
    RevokedTrust,
    RevokedHost,
    CorruptJournal,
    ChangedOutput,
    OmittedPath,
    ReorderedPaths,
    IssuerReplacement,
    LockReplacement,
    OutputLockReplacement,
    FullStoreBeforeSend,
    TransferBeforeSend,
    RestoredJournalBeforeSend,
    ConcurrentAdmission,
    NativeRejection,
    WrongRejectionID,
    EditDuringCommitFence,
    EditDuringReplayFence,
}

fn synthetic_binding(
    request: &ExecuteRequest,
    platform: PeerPlatform,
) -> crate::agent_host::output::NativeBinding {
    let accepted = ExecutionReceipt {
        schema: ExecutionReceiptSchema::HealthmdAgentExecutionReceipt,
        schema_version: 1,
        job_id: request.job_id.clone(),
        binding: approval_binding(&request.plan),
        request_sha256: document_digest(request).unwrap(),
        manifest_sha256: Digest("0".repeat(64)),
        frontier_sha256: Digest("0".repeat(64)),
        artifact_count: 0,
        committed_partition_count: 0,
        source_acknowledged: false,
        status: ExecutionReceiptStatus::Accepted,
        expires_at: later(&now(), 604_800),
    };
    let manifest = ArtifactManifest {
        schema: ArtifactManifestSchema::HealthmdAgentArtifactManifest,
        schema_version: 1,
        job_id: request.job_id.clone(),
        binding: approval_binding(&request.plan),
        request_sha256: document_digest(request).unwrap(),
        branch_statuses: vec![],
        capture_status: ArtifactManifestCaptureStatus::Complete,
        artifacts: request
            .plan
            .predicted_paths
            .iter()
            .zip([id(23), id(24)])
            .map(|(path, id)| {
                Artifact::Branch1(ArtifactBranch1 {
                    artifact_id: id,
                    relative_path: path.clone(),
                    byte_count: 18,
                    sha256: Digest(healthmd_protocol::transfer::sha256_hex(
                        b"{\"synthetic\":true}",
                    )),
                    media_type: ArtifactBranch1MediaType::ApplicationJson,
                    profile: if platform == PeerPlatform::Ios {
                        ArtifactBranch1Profile::AppleV8
                    } else {
                        ArtifactBranch1Profile::AndroidFrozenV4
                    },
                    write_mode: OutputSettingsWriteMode::Overwrite,
                })
            })
            .collect(),
    };
    crate::agent_host::output::NativeBinding {
        request: request.clone(),
        accepted,
        manifest,
    }
}
fn signed_restored_journal(request: &ExecuteRequest, platform: PeerPlatform) -> Vec<u8> {
    use hmac::Mac as _;
    let journal = serde_json::json!({"version":1,"host":request.plan.intent.peer.host_installation_id,
        "binding":synthetic_binding(request,platform),"plans":[]});
    let mut signer = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
    signer.update(b"HealthMd.AgentBridge.HostOutputJournal.v1\0");
    signer.update(&canonical_json(&journal).unwrap());
    let mac = format!("{:x}", signer.finalize().into_bytes());
    canonical_json(&serde_json::json!({"journal":journal,"mac":mac})).unwrap()
}

// Keep the independently constructed synthetic native transcript visible for review.
#[allow(clippy::too_many_lines)]
async fn output_peer(
    port: u16,
    saved: FakeMobileTrust,
    peer: v4::Peer,
    platform: PeerPlatform,
    case: OutputCase,
    mut release: oneshot::Receiver<()>,
    admission_gate: Option<(oneshot::Sender<()>, oneshot::Receiver<()>)>,
) {
    let (mut channel, trust) =
        connect_fake_mobile(port, 3, &saved.display_name, None, Some(&saved)).await;
    let local = receive_cli_hello(&mut channel).await;
    let versions = if platform == PeerPlatform::Ios {
        vec![1, 3, 4]
    } else {
        vec![2, 4]
    };
    let remote = mobile_capabilities(
        &trust,
        platform,
        versions,
        if platform == PeerPlatform::Ios {
            Some(DirectQueryCapabilities::current())
        } else {
            None
        },
    );
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(remote.clone())))
        .await
        .unwrap();
    if platform == PeerPlatform::Android {
        channel
            .send_v2(&v2::Envelope::new(v2::Message::SourceHello(
                android_source_hello(&trust),
            )))
            .await
            .unwrap();
    }
    let negotiation = v4::negotiate(
        &peer.platform,
        &local.protocol_versions,
        &remote.protocol_versions,
        true,
    )
    .unwrap();
    let mut native = NativeFake::new(peer.clone(), now());
    loop {
        let received = tokio::select! {
            _=&mut release=>return,
            result=channel.receive_v4(negotiation)=>result,
        };
        let response = match received.unwrap().message {
            Message::DiscoveryRequest(request) => {
                Message::DiscoveryResponse(Box::new(native.discovery(request.request_id)))
            }
            Message::PlanRequest(request) => {
                Message::PlanResponse(Box::new(native.plan(*request).await.unwrap()))
            }
            Message::ApprovalRequest(request) => {
                // Explicit synthetic local native decision, independent of host JSON.
                native.store_exact_native_decision();
                Message::ApprovalResponse(Box::new(native.relay_approval(*request).await.unwrap()))
            }
            Message::ExecuteRequest(request) => {
                assert!(
                    !matches!(
                        case,
                        OutputCase::FullStoreBeforeSend
                            | OutputCase::TransferBeforeSend
                            | OutputCase::RestoredJournalBeforeSend
                    ),
                    "freshness rejection must precede complete Execute delivery"
                );
                if let Some((ready, resume)) = admission_gate {
                    ready.send(()).unwrap();
                    resume.await.unwrap();
                }
                assert_eq!(native.issued.as_ref(), Some(&request.plan));
                assert_eq!(request.approval.binding, approval_binding(&request.plan));
                if matches!(
                    case,
                    OutputCase::NativeRejection | OutputCase::WrongRejectionID
                ) {
                    let rejection = AgentError {
                        schema: AgentErrorSchema::HealthmdAgentError,
                        schema_version: 1,
                        request_id: if case == OutputCase::WrongRejectionID {
                            id(28)
                        } else {
                            request.request_id.clone()
                        },
                        code: AgentErrorCode::PermissionRequired,
                        retryable: false,
                    };
                    channel
                        .send_v4(
                            &Envelope::new(Message::Rejected(Box::new(rejection))),
                            negotiation,
                        )
                        .await
                        .unwrap();
                    let _ = release.await;
                    return;
                }
                let mut accepted = synthetic_binding(&request, platform).accepted;
                if case == OutputCase::WrongAccepted {
                    accepted.request_sha256 = Digest("1".repeat(64));
                }
                channel
                    .send_v4(
                        &Envelope::new(Message::ExecutionReceipt(Box::new(accepted))),
                        negotiation,
                    )
                    .await
                    .unwrap();
                if case == OutputCase::WrongAccepted {
                    let _ = release.await;
                    return;
                }
                let mut manifest = if let OutputCase::Transfer(transfer_case) = case {
                    transfer_tests::binding(&request, platform, transfer_case).manifest
                } else {
                    synthetic_binding(&request, platform).manifest
                };
                if case == OutputCase::OmittedPath {
                    manifest.artifacts.pop();
                }
                if case == OutputCase::ReorderedPaths {
                    manifest.artifacts.reverse();
                }
                if case == OutputCase::WrongManifest {
                    manifest.job_id = id(25);
                }
                channel
                    .send_v4(
                        &Envelope::new(Message::ArtifactManifest(Box::new(manifest))),
                        negotiation,
                    )
                    .await
                    .unwrap();
                if let OutputCase::Transfer(transfer_case) = case {
                    transfer_tests::send_transfer(&mut channel, &request, platform, transfer_case)
                        .await;
                    if transfer_case == transfer_tests::TransferCase::Disconnect {
                        return;
                    }
                    if !matches!(
                        transfer_case,
                        transfer_tests::TransferCase::Exact | transfer_tests::TransferCase::Large
                    ) {
                        transfer_tests::no_response(&mut channel, platform).await;
                    }
                }
                let _ = release.await;
                return;
            }
            other => panic!("unexpected synthetic execution control: {other:?}"),
        };
        channel
            .send_v4(&Envelope::new(response), negotiation)
            .await
            .unwrap();
    }
}

// One coherent authenticated lifecycle with explicit negative-case assertions.
#[allow(clippy::too_many_lines)]
async fn check_output_case(platform: PeerPlatform, case: OutputCase) {
    let (_temporary, client, saved, peer) = stored_pair(platform).await;
    let (store, output) = enroll(&client.layout.root, &peer, &now()).await;
    let probe = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let (release, wait) = oneshot::channel();
    let (admission_ready, ready) = oneshot::channel();
    let (resume, await_resume) = oneshot::channel();
    let gate = (case == OutputCase::ConcurrentAdmission).then_some((admission_ready, await_resume));
    let source = tokio::spawn(output_peer(
        port,
        saved,
        peer.clone(),
        platform,
        case,
        wait,
        gate,
    ));
    let adversarial_trust = AdversarialOutputTrust::new(&client);
    let bridge = client
        .connect_bridge(
            Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
            port,
            Duration::from_secs(10),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    let mut bridge = bridge.with_test_trust(&adversarial_trust);
    let planner = HostPlanner::new(store.clone());
    let clock = AdvancingClock::new();
    let plan = planner
        .plan(&mut bridge, input(&peer), &clock)
        .await
        .unwrap();
    store
        .record_local_decision(2, &plan.plan_id, &clock, &ExplicitFakeLocalConsent)
        .await
        .unwrap();
    let approval = planner
        .relay_approval(
            &mut bridge,
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
    let request = ExecuteRequest {
        schema: ExecuteRequestSchema::HealthmdAgentExecuteRequest,
        schema_version: 1,
        plan,
        approval,
        request_id: id(22),
        job_id: id(20),
        idempotency_key: id(19),
    };
    if case == OutputCase::FullStoreBeforeSend {
        let issuer = client.layout.root.join("agent-host-v1");
        let count = std::fs::read_dir(&issuer).unwrap().count();
        for i in count..8192 {
            std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(issuer.join(format!("quota-fixture-{i}")))
                .unwrap();
        }
    }
    if case == OutputCase::TransferBeforeSend {
        let path = client
            .layout
            .root
            .join("agent-host-v1")
            .join(format!("transfer-{}.json", request.job_id.0));
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(path)
            .unwrap();
    }
    if case == OutputCase::RestoredJournalBeforeSend {
        let journal = client
            .layout
            .root
            .join("agent-host-v1")
            .join(format!("output-{}.json", request.job_id.0));
        let bytes = signed_restored_journal(&request, platform);
        adversarial_trust.arm(4, move || {
            std::fs::write(&journal, bytes).unwrap();
            std::fs::set_permissions(journal, std::fs::Permissions::from_mode(0o600)).unwrap();
        });
    }
    let retry_request = request.clone();
    let host_authority = request.plan.authority_references.host.authority_id.clone();
    let result = if case == OutputCase::ConcurrentAdmission {
        let (result, ()) = tokio::join!(
            Box::pin(bridge.begin_execution(&store, request, &clock)),
            async {
                ready.await.unwrap();
                let path = client
                    .layout
                    .root
                    .join("agent-host-v1")
                    .join(format!("attempt-{}.json", retry_request.job_id.0));
                let before = std::fs::read(&path).unwrap();
                let competing = crate::agent_host::output::OutputAdmission::reserve(
                    &store,
                    &retry_request,
                    &clock,
                    || async { Ok(output.clone()) },
                )
                .await;
                assert!(matches!(competing, Err(ClientError::AgentStoreBusy)));
                assert_eq!(std::fs::read(path).unwrap(), before);
                resume.send(()).unwrap();
            }
        );
        result
    } else {
        Box::pin(bridge.begin_execution(&store, request, &clock)).await
    };
    if matches!(
        case,
        OutputCase::WrongAccepted
            | OutputCase::WrongManifest
            | OutputCase::OmittedPath
            | OutputCase::ReorderedPaths
            | OutputCase::FullStoreBeforeSend
            | OutputCase::TransferBeforeSend
            | OutputCase::RestoredJournalBeforeSend
            | OutputCase::NativeRejection
            | OutputCase::WrongRejectionID
    ) {
        assert!(result.is_err());
        if case == OutputCase::NativeRejection {
            assert!(matches!(
                &result,
                Err(ClientError::AgentRejected(
                    AgentErrorCode::PermissionRequired
                ))
            ));
        }
        if case == OutputCase::WrongRejectionID {
            assert!(matches!(
                &result,
                Err(ClientError::Agent(Error::BindingChanged))
            ));
        }
        assert_eq!(std::fs::read_dir(&output).unwrap().count(), 0);
        if matches!(
            case,
            OutputCase::WrongAccepted
                | OutputCase::WrongManifest
                | OutputCase::OmittedPath
                | OutputCase::ReorderedPaths
                | OutputCase::NativeRejection
                | OutputCase::WrongRejectionID
        ) {
            let issuer = client.layout.root.join("agent-host-v1");
            let attempt: serde_json::Value = serde_json::from_slice(
                &std::fs::read(issuer.join(format!("attempt-{}.json", retry_request.job_id.0)))
                    .unwrap(),
            )
            .unwrap();
            assert_eq!(
                attempt["attempt"]["schema"],
                "healthmd.agent_host_execution_attempt"
            );
            assert_eq!(
                attempt["attempt"]["request"],
                serde_json::to_value(&retry_request).unwrap()
            );
            assert!(
                !issuer
                    .join(format!("output-{}.json", retry_request.job_id.0))
                    .exists()
            );
        }
        if case == OutputCase::TransferBeforeSend {
            let issuer = client.layout.root.join("agent-host-v1");
            assert!(!issuer.join(format!("attempt-{}.json", id(20).0)).exists());
            assert!(!issuer.join(format!("output-{}.json", id(20).0)).exists());
            assert_eq!(
                std::fs::metadata(issuer.join(format!("transfer-{}.json", id(20).0)))
                    .unwrap()
                    .len(),
                0
            );
        }
        if case == OutputCase::FullStoreBeforeSend {
            let issuer = client.layout.root.join("agent-host-v1");
            assert_eq!(std::fs::read_dir(&issuer).unwrap().count(), 8192);
            assert!(!issuer.join(format!("output-{}.json", id(20).0)).exists());
            assert!(!issuer.join(format!("attempt-{}.json", id(20).0)).exists());
        }
    } else {
        let mut owner = result.unwrap();
        if let OutputCase::Transfer(transfer_case) = case {
            if transfer_case == transfer_tests::TransferCase::Quota {
                let issuer = client.layout.root.join("agent-host-v1");
                let count = std::fs::read_dir(&issuer).unwrap().count();
                for i in count..8191 {
                    std::fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .mode(0o600)
                        .open(issuer.join(format!("quota-transfer-{i}")))
                        .unwrap();
                }
            }
            if matches!(
                transfer_case,
                transfer_tests::TransferCase::PartitionTamper
                    | transfer_tests::TransferCase::PartitionFifo
                    | transfer_tests::TransferCase::CheckpointDelete
                    | transfer_tests::TransferCase::FinalPrefixDelete
                    | transfer_tests::TransferCase::FinalOutputEdit
            ) {
                let journal = client
                    .layout
                    .root
                    .join("agent-host-v1")
                    .join(format!("transfer-{}.json", retry_request.job_id.0));
                let observed = journal.clone();
                let final_stage = matches!(
                    transfer_case,
                    transfer_tests::TransferCase::FinalPrefixDelete
                        | transfer_tests::TransferCase::FinalOutputEdit
                );
                let output_path = match &owner.manifest().artifacts[0] {
                    Artifact::Branch1(item) => output.join(&item.relative_path.0),
                    _ => unreachable!(),
                };
                adversarial_trust.arm_when(
                    move || {
                        std::fs::read(&observed)
                            .ok()
                            .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
                            .is_some_and(|j| {
                                if final_stage {
                                    j["journal"]["final_ack_may_have_sent"] == true
                                } else {
                                    j["journal"]["partitions"]
                                        .as_array()
                                        .is_some_and(|a| a.len() == 1)
                                }
                            })
                    },
                    move || {
                        let saved_checkpoint: serde_json::Value =
                            serde_json::from_slice(&std::fs::read(&journal).unwrap()).unwrap();
                        let stage = journal.parent().unwrap().join(
                            saved_checkpoint["journal"]["partitions"][0]["stage_name"]
                                .as_str()
                                .unwrap(),
                        );
                        match transfer_case {
                            transfer_tests::TransferCase::PartitionTamper => {
                                std::fs::write(stage, b"bad bytes").unwrap();
                            }
                            transfer_tests::TransferCase::PartitionFifo => {
                                std::fs::remove_file(&stage).unwrap();
                                assert!(
                                    std::process::Command::new("mkfifo")
                                        .arg("-m")
                                        .arg("600")
                                        .arg(stage)
                                        .status()
                                        .unwrap()
                                        .success()
                                );
                            }
                            transfer_tests::TransferCase::CheckpointDelete => {
                                std::fs::remove_file(journal).unwrap();
                            }
                            transfer_tests::TransferCase::FinalPrefixDelete => {
                                std::fs::remove_file(stage).unwrap();
                            }
                            transfer_tests::TransferCase::FinalOutputEdit => {
                                std::fs::write(output_path, b"independent edit").unwrap();
                            }
                            _ => unreachable!(),
                        }
                    },
                );
            }
            let expected = owner.manifest().clone();
            let result = Box::pin(owner.receive_and_commit()).await;
            let issuer = client.layout.root.join("agent-host-v1");
            if matches!(
                transfer_case,
                transfer_tests::TransferCase::Exact | transfer_tests::TransferCase::Large
            ) {
                let received = result.unwrap();
                assert_eq!(received.receipts.len(), 2);
                let expected_payload = transfer_tests::payload(transfer_case);
                let part_bytes = if transfer_case == transfer_tests::TransferCase::Large {
                    expected_payload.len()
                } else {
                    9
                };
                let count = expected_payload.len().div_ceil(part_bytes) * 2;
                assert_eq!(received.committed_partition_count, count as u64);
                let mut frontier = TransferFrontier::new(
                    &retry_request.job_id,
                    &document_digest(&retry_request).unwrap(),
                    &document_digest(&expected).unwrap(),
                    &id(30),
                )
                .unwrap();
                let mut index = 0_usize;
                for item in &expected.artifacts {
                    let Artifact::Branch1(item) = item else {
                        unreachable!()
                    };
                    for (part_index, segment) in expected_payload.chunks(part_bytes).enumerate() {
                        frontier = frontier
                            .appending(&TransferFrontierPartition {
                                partition_index: i64::try_from(index).unwrap(),
                                transfer_id: id(31 + index as u64),
                                artifact_id: item.artifact_id.clone(),
                                artifact_offset: i64::try_from(part_index * part_bytes).unwrap(),
                                byte_count: i64::try_from(segment.len()).unwrap(),
                                chunk_count: i64::try_from(
                                    segment
                                        .len()
                                        .div_ceil(healthmd_protocol::TRANSFER_FRAME_BYTES),
                                )
                                .unwrap(),
                                sha256: Digest(healthmd_protocol::transfer::sha256_hex(segment)),
                            })
                            .unwrap();
                        index += 1;
                    }
                }
                assert_eq!(received.frontier_sha256, *frontier.sha256());
                for receipt in &received.receipts {
                    validate_commit_receipt(receipt, None).unwrap();
                    assert_eq!(
                        std::fs::read(output.join(&receipt.relative_path.0)).unwrap(),
                        expected_payload
                    );
                }
                let journal: serde_json::Value = serde_json::from_slice(
                    &std::fs::read(
                        issuer.join(format!("transfer-{}.json", retry_request.job_id.0)),
                    )
                    .unwrap(),
                )
                .unwrap();
                assert_eq!(
                    journal["journal"]["partitions"].as_array().unwrap().len(),
                    count
                );
                assert_eq!(journal["journal"]["final_ack_may_have_sent"], true);
                for record in journal["journal"]["partitions"].as_array().unwrap() {
                    let name = record["stage_name"].as_str().unwrap();
                    assert_eq!(
                        std::fs::metadata(issuer.join(name)).unwrap().len(),
                        record["partition"]["byte_count"].as_u64().unwrap()
                    );
                }
            } else {
                assert!(result.is_err(), "{transfer_case:?}");
                if !matches!(
                    transfer_case,
                    transfer_tests::TransferCase::BadFinalize
                        | transfer_tests::TransferCase::FinalPrefixDelete
                        | transfer_tests::TransferCase::FinalOutputEdit
                ) {
                    for item in expected.artifacts {
                        let Artifact::Branch1(item) = item else {
                            unreachable!()
                        };
                        assert!(!output.join(item.relative_path.0).exists());
                    }
                }
                let journal = issuer.join(format!("transfer-{}.json", retry_request.job_id.0));
                if journal.exists() {
                    let json: serde_json::Value =
                        serde_json::from_slice(&std::fs::read(journal).unwrap()).unwrap();
                    if !matches!(
                        transfer_case,
                        transfer_tests::TransferCase::FinalPrefixDelete
                            | transfer_tests::TransferCase::FinalOutputEdit
                    ) {
                        assert_eq!(json["journal"]["final_ack_may_have_sent"], false);
                    }
                }
            }
            if matches!(
                transfer_case,
                transfer_tests::TransferCase::PartitionTamper
                    | transfer_tests::TransferCase::PartitionFifo
                    | transfer_tests::TransferCase::CheckpointDelete
                    | transfer_tests::TransferCase::FinalPrefixDelete
                    | transfer_tests::TransferCase::FinalOutputEdit
            ) {
                assert!(adversarial_trust.action.lock().unwrap().is_none());
            }
            assert!(owner.receive_and_commit().await.is_err());
            drop(owner);
            assert!(bridge.discover().await.is_err());
            let _ = release.send(());
            source.await.unwrap();
            return;
        }
        let artifact = match &owner.manifest().artifacts[0] {
            Artifact::Branch1(a) => a.clone(),
            _ => unreachable!(),
        };
        let input = client.layout.root.join("synthetic-output.json");
        std::fs::write(
            &input,
            if case == OutputCase::WrongInput {
                b"wrong input".as_slice()
            } else {
                b"{\"synthetic\":true}".as_slice()
            },
        )
        .unwrap();
        if case == OutputCase::NonregularInput {
            assert!(
                crate::agent_host::output::OutputAdmission::reserve(
                    &store,
                    &retry_request,
                    &clock,
                    || async { Ok(output.clone()) }
                )
                .await
                .is_err()
            );
            let mut changed_request = retry_request.clone();
            changed_request.idempotency_key = id(29);
            assert!(
                crate::agent_host::output::OutputAdmission::reserve(
                    &store,
                    &changed_request,
                    &clock,
                    || async { Ok(output.clone()) }
                )
                .await
                .is_err()
            );
            std::fs::remove_file(&input).unwrap();
            std::fs::create_dir(&input).unwrap();
        }
        if case == OutputCase::FifoInput {
            std::fs::remove_file(&input).unwrap();
            assert!(
                std::process::Command::new("mkfifo")
                    .arg("-m")
                    .arg("600")
                    .arg(&input)
                    .status()
                    .unwrap()
                    .success()
            );
        }
        let journal = client
            .layout
            .root
            .join("agent-host-v1")
            .join(format!("output-{}.json", id(20).0));
        match case {
            OutputCase::IssuerReplacement => {
                let issuer = client.layout.root.join("agent-host-v1");
                let retired = client.layout.root.join("retired-issuer");
                adversarial_trust.arm(5, move || {
                    std::fs::rename(&issuer, &retired).unwrap();
                    std::fs::create_dir(&issuer).unwrap();
                    std::fs::set_permissions(&issuer, std::fs::Permissions::from_mode(0o700))
                        .unwrap();
                });
            }
            OutputCase::LockReplacement | OutputCase::OutputLockReplacement => {
                let lock = client
                    .layout
                    .root
                    .join(if case == OutputCase::OutputLockReplacement {
                        "agent-host-v1/outputs.lock"
                    } else {
                        "agent-host-v1/issuer.lock"
                    });
                adversarial_trust.arm(5, move || {
                    std::fs::remove_file(&lock).unwrap();
                    std::fs::write(&lock, b"").unwrap();
                    std::fs::set_permissions(&lock, std::fs::Permissions::from_mode(0o600))
                        .unwrap();
                });
            }
            OutputCase::EditDuringCommitFence => {
                let output_file = output.join(&artifact.relative_path.0);
                adversarial_trust.arm(7, move || {
                    std::fs::write(output_file, b"independent edit").unwrap();
                });
            }
            OutputCase::RevokedTrust => client
                .trust_store
                .save(&TrustState::empty(client.identity.installation_id))
                .await
                .unwrap(),
            OutputCase::RevokedHost => store
                .revoke_local(store.revision().await.unwrap(), &host_authority)
                .await
                .unwrap(),
            OutputCase::CorruptJournal => {
                let mut bytes = std::fs::read(&journal).unwrap();
                bytes[0] = b'[';
                std::fs::write(&journal, bytes).unwrap();
            }
            _ => {}
        }
        if matches!(
            case,
            OutputCase::WrongInput
                | OutputCase::NonregularInput
                | OutputCase::FifoInput
                | OutputCase::RevokedTrust
                | OutputCase::RevokedHost
                | OutputCase::CorruptJournal
                | OutputCase::IssuerReplacement
                | OutputCase::LockReplacement
                | OutputCase::OutputLockReplacement
        ) {
            assert!(
                owner
                    .commit_artifact(&artifact.artifact_id, &input)
                    .await
                    .is_err()
            );
            assert!(!output.join(&artifact.relative_path.0).exists());
        } else if case == OutputCase::EditDuringCommitFence {
            assert!(
                owner
                    .commit_artifact(&artifact.artifact_id, &input)
                    .await
                    .is_err()
            );
            assert_eq!(
                std::fs::read(output.join(&artifact.relative_path.0)).unwrap(),
                b"independent edit"
            );
            let signed: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&journal).unwrap()).unwrap();
            assert_eq!(signed["journal"]["plans"][0]["committed"], false);
        } else {
            // The source's immutable accepted lifetime survives the short planning deadline.
            clock.advance_to(301);
            let receipt = owner
                .commit_artifact(&artifact.artifact_id, &input)
                .await
                .unwrap();
            assert_eq!(receipt.status, CommitReceiptStatus::Committed);
            assert_eq!(receipt.before_sha256.0, "0".repeat(64));
            validate_commit_receipt(&receipt, None).unwrap();
            assert_eq!(
                std::fs::read(output.join(&artifact.relative_path.0)).unwrap(),
                b"{\"synthetic\":true}"
            );
            let signed: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&journal).unwrap()).unwrap();
            assert_eq!(signed["journal"]["plans"][0]["committed"], true);
            assert_eq!(
                signed["journal"]["plans"][0]["receipt"],
                serde_json::to_value(&receipt).unwrap()
            );
            std::fs::remove_file(&input).unwrap();
            if case == OutputCase::EditDuringReplayFence {
                let output_file = output.join(&artifact.relative_path.0);
                adversarial_trust.arm(3, move || {
                    std::fs::write(output_file, b"independent edit").unwrap();
                });
                assert!(
                    owner
                        .commit_artifact(&artifact.artifact_id, &input)
                        .await
                        .is_err()
                );
                assert_eq!(
                    std::fs::read(output.join(&artifact.relative_path.0)).unwrap(),
                    b"independent edit"
                );
            } else if case == OutputCase::ChangedOutput {
                std::fs::write(output.join(&artifact.relative_path.0), b"independent edit")
                    .unwrap();
                assert!(
                    owner
                        .commit_artifact(&artifact.artifact_id, &input)
                        .await
                        .is_err()
                );
                assert_eq!(
                    std::fs::read(output.join(&artifact.relative_path.0)).unwrap(),
                    b"independent edit"
                );
            } else {
                let replay = owner
                    .commit_artifact(&artifact.artifact_id, &input)
                    .await
                    .unwrap();
                assert_eq!(replay.status, CommitReceiptStatus::AlreadyCommitted);
                assert_eq!(replay.commit_key, receipt.commit_key);
                validate_commit_receipt(&replay, Some(&receipt)).unwrap();
            }
        }
        drop(owner);
        assert!(bridge.discover().await.is_err());
    }
    let _ = release.send(());
    source.await.unwrap();
}
#[tokio::test]
async fn authenticated_output_commits_signed_exact_receipts_and_fenced_replay() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check_output_case(platform, OutputCase::ExactReplay)).await;
    }
}
#[tokio::test]
async fn authenticated_output_rejects_wrong_acceptance_manifest_and_input() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::WrongAccepted,
            OutputCase::WrongManifest,
            OutputCase::WrongInput,
            OutputCase::OmittedPath,
            OutputCase::ReorderedPaths,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}
#[tokio::test]
async fn authenticated_output_rejects_revocation_corruption_and_changed_installed_bytes() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::RevokedTrust,
            OutputCase::RevokedHost,
            OutputCase::CorruptJournal,
            OutputCase::ChangedOutput,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn authenticated_output_rejects_retired_issuer_and_replaced_lock_during_fence() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::IssuerReplacement,
            OutputCase::LockReplacement,
            OutputCase::OutputLockReplacement,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}
#[tokio::test]
async fn authenticated_output_rechecks_exact_bytes_after_commit_and_replay_fences() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::EditDuringCommitFence,
            OutputCase::EditDuringReplayFence,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn authenticated_output_rejects_directory_and_unconnected_fifo_without_blocking() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [OutputCase::NonregularInput, OutputCase::FifoInput] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn authenticated_output_admission_rejects_full_store_and_journal_appearing_before_send() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::FullStoreBeforeSend,
            OutputCase::RestoredJournalBeforeSend,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn authenticated_output_admission_serializes_competing_original_attempts() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check_output_case(platform, OutputCase::ConcurrentAdmission)).await;
    }
}

#[tokio::test]
async fn authenticated_output_preserves_exact_native_rejection_and_rejects_wrong_request_id() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [OutputCase::NativeRejection, OutputCase::WrongRejectionID] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn authenticated_output_admission_rejects_retained_transfer_before_execute() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check_output_case(platform, OutputCase::TransferBeforeSend)).await;
    }
}
