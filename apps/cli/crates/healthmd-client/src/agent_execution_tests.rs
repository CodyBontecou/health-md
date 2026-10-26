//! Authenticated synthetic native execution; no phone APIs or real health data.
use super::*;
use crate::agent_bridge::CurrentBridgeTrust;
use crate::agent_planning::PlanningClock as _;
use hmac::Mac as _;
use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};

#[path = "agent_transfer_tests.rs"]
mod transfer_tests;
struct MutableOutputKey(AtomicUsize);
#[async_trait::async_trait]
impl crate::agent_host::ProtectedHostKey for MutableOutputKey {
    async fn load_existing(
        &self,
        host: &ControlUuid,
    ) -> Result<crate::agent_host::ProtectedHostSecret, ClientError> {
        use base64::Engine as _;
        match self.0.load(Ordering::SeqCst) {
            1 => Err(ClientError::AgentAuthorityUnavailable),
            2 => Ok(crate::agent_host::ProtectedHostSecret::from(
                base64::engine::general_purpose::STANDARD.encode([42; 32]),
            )),
            _ => crate::agent_host::ProtectedHostKey::load_existing(&FakeProtectedKey, host).await,
        }
    }
}

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
    AcceptedBeforeManifest,
    ExplicitAcceptedBeforeManifest,
    DropAcceptedBeforeManifest,
    AcceptedOwnerJournalDrift,
    AcceptedOwnerRevokedTrust,
    HostCancelPending,
    HostCancelRevokedGrant,
    HostCancelCorruptPending,
    HostCancelRevokedTrust,
    HostCancelKeyRemovedAtSend,
    HostCancelKeyRotatedAtSend,
    AcceptedJournalCorrupt,
    AcceptedJournalDelete,
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
    let journal = serde_json::json!({"version":1,"host":request.plan.intent.peer.host_installation_id,
        "binding":synthetic_binding(request,platform),"plans":[]});
    let mut signer = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
    signer.update(b"HealthMd.AgentBridge.HostOutputJournal.v1\0");
    signer.update(&canonical_json(&journal).unwrap());
    let mac = format!("{:x}", signer.finalize().into_bytes());
    canonical_json(&serde_json::json!({"journal":journal,"mac":mac})).unwrap()
}

async fn output_channel(
    port: u16,
    saved: FakeMobileTrust,
    peer: &v4::Peer,
    platform: PeerPlatform,
) -> (SecureChannel, Negotiation) {
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
    (channel, negotiation)
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
    mut admission_gate: Option<(oneshot::Sender<()>, oneshot::Receiver<()>)>,
) {
    let (mut channel, negotiation) = output_channel(port, saved, &peer, platform).await;
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
                if case == OutputCase::ConcurrentAdmission {
                    if let Some((ready, resume)) = admission_gate.take() {
                        ready.send(()).unwrap();
                        resume.await.unwrap();
                    }
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
                if matches!(
                    case,
                    OutputCase::HostCancelPending
                        | OutputCase::HostCancelRevokedGrant
                        | OutputCase::HostCancelCorruptPending
                        | OutputCase::HostCancelRevokedTrust
                        | OutputCase::HostCancelKeyRemovedAtSend
                        | OutputCase::HostCancelKeyRotatedAtSend
                ) {
                    if let Some((ready, _resume)) = admission_gate.take() {
                        ready.send(()).unwrap();
                    }
                    if matches!(
                        case,
                        OutputCase::HostCancelPending | OutputCase::HostCancelRevokedGrant
                    ) {
                        let Message::CancelRequest(cancel) =
                            channel.receive_v4(negotiation).await.unwrap().message
                        else {
                            panic!("exact original Cancel required before any manifest");
                        };
                        assert_eq!(cancel.approval_id, request.approval.approval_id);
                        assert_eq!(cancel.authority_id, request.approval.authority_id);
                        assert_eq!(cancel.job_id, request.job_id);
                        assert_eq!(cancel.peer, request.plan.intent.peer);
                        assert_eq!(cancel.request_sha256, document_digest(&request).unwrap());
                        let _ = release.await;
                    } else {
                        tokio::select! {
                            biased;
                            packet = channel.receive_v4(negotiation) => panic!("unverified Cancel crossed wire: {}", packet.is_ok()),
                            _ = release => {}
                        }
                        assert!(
                            tokio::time::timeout(
                                Duration::from_millis(100),
                                channel.receive_v4(negotiation)
                            )
                            .await
                            .is_err(),
                            "failed intent/trust proof must send zero frames"
                        );
                    }
                    return;
                }
                if matches!(
                    case,
                    OutputCase::AcceptedBeforeManifest
                        | OutputCase::ExplicitAcceptedBeforeManifest
                        | OutputCase::DropAcceptedBeforeManifest
                        | OutputCase::AcceptedOwnerJournalDrift
                        | OutputCase::AcceptedOwnerRevokedTrust
                ) {
                    if let Some((ready, resume)) = admission_gate.take() {
                        ready.send(()).unwrap();
                        resume.await.unwrap();
                    }
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
                    if matches!(
                        transfer_case,
                        transfer_tests::TransferCase::Disconnect
                            | transfer_tests::TransferCase::MissingSourceReceipt
                    ) {
                        return;
                    }
                    if !matches!(
                        transfer_case,
                        transfer_tests::TransferCase::Exact
                            | transfer_tests::TransferCase::Large
                            | transfer_tests::TransferCase::Confirmed
                    ) {
                        if transfer_case.confirms() {
                            let received = tokio::time::timeout(
                                Duration::from_millis(100),
                                channel.receive_v4(negotiation),
                            )
                            .await;
                            assert!(
                                !matches!(received, Ok(Ok(_))),
                                "rejected confirmation must not emit a v4 host commit"
                            );
                        } else {
                            transfer_tests::no_response(&mut channel, platform).await;
                        }
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
    let mutable_key = Arc::new(MutableOutputKey(AtomicUsize::new(0)));
    let (store, output) = if matches!(
        case,
        OutputCase::HostCancelKeyRemovedAtSend | OutputCase::HostCancelKeyRotatedAtSend
    ) {
        enroll_with_key(
            &client.layout.root,
            &peer,
            delegation(&peer, AuthorityReferenceIssuer::AuthorizedHost, &now()),
            mutable_key.clone(),
        )
        .await
    } else {
        enroll(&client.layout.root, &peer, &now()).await
    };
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let (release, wait) = oneshot::channel();
    let (admission_ready, ready) = oneshot::channel();
    let (resume, await_resume) = oneshot::channel();
    let gate = matches!(
        case,
        OutputCase::ConcurrentAdmission
            | OutputCase::AcceptedBeforeManifest
            | OutputCase::ExplicitAcceptedBeforeManifest
            | OutputCase::DropAcceptedBeforeManifest
            | OutputCase::AcceptedOwnerJournalDrift
            | OutputCase::AcceptedOwnerRevokedTrust
            | OutputCase::HostCancelPending
            | OutputCase::HostCancelRevokedGrant
            | OutputCase::HostCancelCorruptPending
            | OutputCase::HostCancelRevokedTrust
            | OutputCase::HostCancelKeyRemovedAtSend
            | OutputCase::HostCancelKeyRotatedAtSend
    )
    .then_some((admission_ready, await_resume));
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
    let bridge = connect_bound_bridge(
        &client,
        Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
        &listener,
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
    if matches!(
        case,
        OutputCase::AcceptedJournalCorrupt | OutputCase::AcceptedJournalDelete
    ) {
        let path = client
            .layout
            .root
            .join("agent-host-v1")
            .join(format!("attempt-{}.json", request.job_id.0));
        let observed = path.clone();
        adversarial_trust.arm_when(
            move || {
                std::fs::read(&observed)
                    .ok()
                    .and_then(|bytes| serde_json::from_slice::<serde_json::Value>(&bytes).ok())
                    .is_some_and(|value| value["attempt"].get("accepted_receipt").is_some())
            },
            move || {
                if case == OutputCase::AcceptedJournalDelete {
                    std::fs::remove_file(path).unwrap();
                } else {
                    std::fs::write(path, b"synthetic corrupt acceptance").unwrap();
                }
            },
        );
    }
    let retry_request = request.clone();
    let host_authority = request.plan.authority_references.host.authority_id.clone();
    if matches!(
        case,
        OutputCase::HostCancelPending
            | OutputCase::HostCancelRevokedGrant
            | OutputCase::HostCancelCorruptPending
            | OutputCase::HostCancelRevokedTrust
            | OutputCase::HostCancelKeyRemovedAtSend
            | OutputCase::HostCancelKeyRotatedAtSend
    ) {
        let owner = Box::pin(bridge.begin_accepted_execution(&store, request, &clock))
            .await
            .unwrap();
        ready.await.unwrap();
        let path = client
            .layout
            .root
            .join("agent-host-v1")
            .join(format!("attempt-{}.json", retry_request.job_id.0));
        let original = std::fs::read(&path).unwrap();
        if case == OutputCase::HostCancelRevokedGrant {
            store
                .revoke_local(store.revision().await.unwrap(), &host_authority)
                .await
                .unwrap();
        } else if case == OutputCase::HostCancelRevokedTrust {
            client
                .trust_store
                .save(&TrustState::empty(client.identity.installation_id))
                .await
                .unwrap();
        } else if matches!(
            case,
            OutputCase::HostCancelKeyRemovedAtSend | OutputCase::HostCancelKeyRotatedAtSend
        ) {
            let observe = path.clone();
            let key = mutable_key.clone();
            let calls = AtomicUsize::new(0);
            adversarial_trust.arm_when(
                move || {
                    let pending = std::fs::read(&observe)
                        .ok()
                        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
                        .is_some_and(|v| v["attempt"].get("cancellation_request").is_some());
                    // Readback is first, length-prefix authorization second; mutate
                    // the current protected key in the payload pre-write callback.
                    pending && calls.fetch_add(1, Ordering::SeqCst) == 2
                },
                move || {
                    key.0.store(
                        if case == OutputCase::HostCancelKeyRemovedAtSend {
                            1
                        } else {
                            2
                        },
                        Ordering::SeqCst,
                    );
                },
            );
        } else if case == OutputCase::HostCancelCorruptPending {
            let observe = path.clone();
            let corrupt = path.clone();
            adversarial_trust.arm_when(
                move || {
                    std::fs::read(&observe)
                        .ok()
                        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
                        .is_some_and(|v| v["attempt"].get("cancellation_request").is_some())
                },
                move || {
                    std::fs::write(corrupt, b"synthetic corrupted stop intent").unwrap();
                },
            );
        }
        let pending = owner.request_cancellation().await;
        if matches!(
            case,
            OutputCase::HostCancelPending | OutputCase::HostCancelRevokedGrant
        ) {
            let pending = pending.unwrap();
            assert_eq!(
                pending.acceptance(),
                &synthetic_binding(&retry_request, platform).accepted
            );
            assert_eq!(pending.request().job_id, retry_request.job_id);
            let bytes = std::fs::read(&path).unwrap();
            let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(value["attempt"]["schema_version"], 3);
            assert_eq!(
                value["attempt"]["cancellation_request"],
                serde_json::to_value(pending.request()).unwrap()
            );
            assert_eq!(
                value["attempt"]["accepted_receipt"],
                serde_json::to_value(pending.acceptance()).unwrap()
            );
            assert_eq!(
                value["attempt"]["started_at"],
                serde_json::to_value(clock.now()).unwrap()
            );
            let mut mac = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
            mac.update(b"HealthMd.AgentBridge.HostExecutionAttempt.v3\0");
            mac.update(&canonical_json(&value["attempt"]).unwrap());
            assert_eq!(value["mac"], format!("{:x}", mac.finalize().into_bytes()));
            assert_eq!(
                std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
            assert!(matches!(
                crate::agent_host::output::OutputAdmission::reserve(
                    &store,
                    &retry_request,
                    &clock,
                    || async { Ok(output.clone()) }
                )
                .await,
                Err(ClientError::AgentStoreBusy)
            ));
            drop(pending);
            assert_eq!(std::fs::read(&path).unwrap(), bytes);
        } else {
            assert!(pending.is_err());
            if case == OutputCase::HostCancelRevokedTrust {
                assert_eq!(std::fs::read(&path).unwrap(), original);
            } else if case == OutputCase::HostCancelCorruptPending {
                assert_eq!(
                    std::fs::read(&path).unwrap(),
                    b"synthetic corrupted stop intent"
                );
            } else {
                assert!(adversarial_trust.action.lock().unwrap().is_none());
                let value: serde_json::Value =
                    serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
                assert_eq!(value["attempt"]["schema_version"], 3);
                assert!(value["attempt"].get("cancellation_request").is_some());
            }
        }
        assert!(
            !path
                .with_file_name(format!("output-{}.json", retry_request.job_id.0))
                .exists()
        );
        assert!(
            !path
                .with_file_name(format!("completion-{}.json", retry_request.job_id.0))
                .exists()
        );
        assert!(bridge.discover().await.is_err());
        let _ = release.send(());
        source.await.unwrap();
        return;
    }
    let result = if matches!(
        case,
        OutputCase::ExplicitAcceptedBeforeManifest
            | OutputCase::DropAcceptedBeforeManifest
            | OutputCase::AcceptedOwnerJournalDrift
            | OutputCase::AcceptedOwnerRevokedTrust
    ) {
        let accepted = tokio::time::timeout(
            Duration::from_secs(5),
            Box::pin(bridge.begin_accepted_execution(&store, request, &clock)),
        )
        .await
        .expect("Acceptance must return while the source manifest is blocked")
        .unwrap();
        ready.await.unwrap();
        assert_eq!(
            accepted.acceptance(),
            &synthetic_binding(&retry_request, platform).accepted
        );
        let path = client
            .layout
            .root
            .join("agent-host-v1")
            .join(format!("attempt-{}.json", retry_request.job_id.0));
        let before = std::fs::read(&path).unwrap();
        let record: serde_json::Value = serde_json::from_slice(&before).unwrap();
        assert_eq!(record["attempt"]["schema_version"], 2);
        assert_eq!(
            record["attempt"]["accepted_receipt"],
            serde_json::to_value(accepted.acceptance()).unwrap()
        );
        assert!(
            !path
                .with_file_name(format!("output-{}.json", retry_request.job_id.0))
                .exists()
        );
        assert!(matches!(
            crate::agent_host::output::OutputAdmission::reserve(
                &store,
                &retry_request,
                &clock,
                || async { Ok(output.clone()) }
            )
            .await,
            Err(ClientError::AgentStoreBusy)
        ));
        assert_eq!(std::fs::read(&path).unwrap(), before);
        if matches!(
            case,
            OutputCase::AcceptedOwnerJournalDrift | OutputCase::AcceptedOwnerRevokedTrust
        ) {
            if case == OutputCase::AcceptedOwnerJournalDrift {
                std::fs::write(&path, b"synthetic changed acceptance").unwrap();
            } else {
                client
                    .trust_store
                    .save(&TrustState::empty(client.identity.installation_id))
                    .await
                    .unwrap();
            }
            let retained = std::fs::read(&path).unwrap();
            assert!(
                tokio::time::timeout(Duration::from_secs(5), Box::pin(accepted.wait_manifest()))
                    .await
                    .expect("Stale acceptance must reject before waiting for a blocked manifest")
                    .is_err()
            );
            assert!(bridge.discover().await.is_err());
            assert_eq!(std::fs::read(&path).unwrap(), retained);
            assert!(
                !path
                    .with_file_name(format!("output-{}.json", retry_request.job_id.0))
                    .exists()
            );
            let _ = resume.send(());
            let _ = release.send(());
            source.await.unwrap();
            return;
        }
        if case == OutputCase::DropAcceptedBeforeManifest {
            drop(accepted);
            assert!(bridge.discover().await.is_err());
            assert_eq!(std::fs::read(&path).unwrap(), before);
            assert!(
                !path
                    .with_file_name(format!("output-{}.json", retry_request.job_id.0))
                    .exists()
            );
            let _ = resume.send(());
            let _ = release.send(());
            source.await.unwrap();
            return;
        }
        resume.send(()).unwrap();
        accepted.wait_manifest().await
    } else if matches!(
        case,
        OutputCase::ConcurrentAdmission | OutputCase::AcceptedBeforeManifest
    ) {
        let (result, ()) = tokio::join!(
            Box::pin(bridge.begin_execution(&store, request, &clock)),
            async {
                ready.await.unwrap();
                let path = client
                    .layout
                    .root
                    .join("agent-host-v1")
                    .join(format!("attempt-{}.json", retry_request.job_id.0));
                if case == OutputCase::AcceptedBeforeManifest {
                    let attempt = tokio::time::timeout(Duration::from_secs(5), async {
                        loop {
                            let bytes = std::fs::read(&path).unwrap();
                            let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
                            if value["attempt"].get("accepted_receipt").is_some() {
                                break value;
                            }
                            tokio::time::sleep(Duration::from_millis(10)).await;
                        }
                    })
                    .await
                    .expect("Source acceptance must be durable while the manifest is blocked");
                    let record = &attempt["attempt"];
                    assert_eq!(record["schema_version"], 2);
                    assert_eq!(
                        record["request"],
                        serde_json::to_value(&retry_request).unwrap()
                    );
                    assert_eq!(
                        record["accepted_receipt"],
                        serde_json::to_value(synthetic_binding(&retry_request, platform).accepted)
                            .unwrap()
                    );
                    assert_eq!(
                        record["started_at"],
                        serde_json::to_value(clock.now()).unwrap()
                    );
                    assert!(
                        !path
                            .with_file_name(format!("output-{}.json", retry_request.job_id.0))
                            .exists()
                    );
                    assert_eq!(
                        std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                        0o600
                    );
                    let mut signer = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
                    signer.update(b"HealthMd.AgentBridge.HostExecutionAttempt.v2\0");
                    signer.update(&canonical_json(record).unwrap());
                    assert_eq!(
                        attempt["mac"],
                        format!("{:x}", signer.finalize().into_bytes())
                    );
                }
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
            | OutputCase::AcceptedJournalCorrupt
            | OutputCase::AcceptedJournalDelete
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
            if matches!(
                case,
                OutputCase::WrongAccepted
                    | OutputCase::NativeRejection
                    | OutputCase::WrongRejectionID
            ) {
                assert_eq!(attempt["attempt"]["schema_version"], 1);
                assert!(attempt["attempt"].get("accepted_receipt").is_none());
            } else {
                assert_eq!(attempt["attempt"]["schema_version"], 2);
                assert_eq!(
                    attempt["attempt"]["accepted_receipt"],
                    serde_json::to_value(synthetic_binding(&retry_request, platform).accepted)
                        .unwrap()
                );
            }
            assert!(
                !issuer
                    .join(format!("output-{}.json", retry_request.job_id.0))
                    .exists()
            );
        }
        if matches!(
            case,
            OutputCase::AcceptedJournalCorrupt | OutputCase::AcceptedJournalDelete
        ) {
            let issuer = client.layout.root.join("agent-host-v1");
            let path = issuer.join(format!("attempt-{}.json", retry_request.job_id.0));
            if case == OutputCase::AcceptedJournalDelete {
                assert!(!path.exists());
            } else {
                assert_eq!(
                    std::fs::read(path).unwrap(),
                    b"synthetic corrupt acceptance"
                );
            }
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
            let issuer = client.layout.root.join("agent-host-v1");
            let prior_output = if transfer_case
                == transfer_tests::TransferCase::OutputJournalRollbackDuringConfirmation
            {
                Some(
                    std::fs::read(issuer.join(format!("output-{}.json", retry_request.job_id.0)))
                        .unwrap(),
                )
            } else {
                None
            };
            let result = Box::pin(owner.receive_and_commit()).await;
            if transfer_case.confirms() {
                let received = result.unwrap();
                assert_eq!(received.receipts.len(), 2);
                if transfer_case == transfer_tests::TransferCase::OutputEditDuringConfirmation {
                    let path = output.join(&received.receipts[0].relative_path.0);
                    adversarial_trust.arm(1, move || {
                        std::fs::write(path, b"independent edit").unwrap();
                    });
                }
                if matches!(
                    transfer_case,
                    transfer_tests::TransferCase::OutputJournalDeleteDuringConfirmation
                        | transfer_tests::TransferCase::OutputJournalCorruptDuringConfirmation
                ) {
                    let path = issuer.join(format!("output-{}.json", retry_request.job_id.0));
                    // After the owner and transaction have loaded valid durable evidence,
                    // mutate it in the final trust callback of the first actual receipt send.
                    adversarial_trust.arm(3, move || {
                        if transfer_case
                            == transfer_tests::TransferCase::OutputJournalDeleteDuringConfirmation
                        {
                            std::fs::remove_file(path).unwrap();
                        } else {
                            std::fs::write(path, b"corrupt").unwrap();
                        }
                    });
                }
                if matches!(
                    transfer_case,
                    transfer_tests::TransferCase::CompletionDeleteAtReturn
                        | transfer_tests::TransferCase::CompletionCorruptAtReturn
                ) {
                    let path = issuer.join(format!("completion-{}.json", retry_request.job_id.0));
                    let trigger = path.clone();
                    adversarial_trust.arm_when(
                        move || trigger.exists(),
                        move || {
                            if transfer_case
                                == transfer_tests::TransferCase::CompletionDeleteAtReturn
                            {
                                std::fs::remove_file(path).unwrap();
                            } else {
                                std::fs::write(path, b"corrupt").unwrap();
                            }
                        },
                    );
                }
                if let Some(previous) = prior_output {
                    let path = issuer.join(format!("output-{}.json", retry_request.job_id.0));
                    // Restore authentic older signed evidence after the completed journal was loaded.
                    adversarial_trust.arm(3, move || {
                        std::fs::write(path, previous).unwrap();
                    });
                }
                let confirmed = Box::pin(owner.confirm_source_completion()).await;
                let path = issuer.join(format!("completion-{}.json", retry_request.job_id.0));
                if transfer_case == transfer_tests::TransferCase::Confirmed {
                    let receipt = confirmed.unwrap();
                    assert!(receipt.source_acknowledged);
                    assert_eq!(receipt.status, ExecutionReceiptStatus::Complete);
                    assert_eq!(receipt.frontier_sha256, received.frontier_sha256);
                    let saved: serde_json::Value =
                        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
                    assert_eq!(
                        saved["journal"]["receipt"],
                        serde_json::to_value(receipt).unwrap()
                    );
                    assert_eq!(
                        saved["journal"]["source_confirmation"],
                        serde_json::to_value(&retry_request.job_id).unwrap()
                    );
                } else {
                    assert!(confirmed.is_err());
                    if transfer_case == transfer_tests::TransferCase::CompletionCorruptAtReturn {
                        assert_eq!(std::fs::read(&path).unwrap(), b"corrupt");
                    } else {
                        assert!(!path.exists());
                    }
                }
                assert!(owner.confirm_source_completion().await.is_err());
                drop(owner);
                assert!(bridge.discover().await.is_err());
                let _ = release.send(());
                source.await.unwrap();
                return;
            }
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
async fn authenticated_acceptance_is_durable_before_manifest_read() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check_output_case(
            platform,
            OutputCase::AcceptedBeforeManifest,
        ))
        .await;
    }
}

#[tokio::test]
async fn authenticated_acceptance_rejects_final_callback_corruption_without_repair() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::AcceptedJournalCorrupt,
            OutputCase::AcceptedJournalDelete,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
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

#[path = "agent_resume_tests.rs"]
mod resume_tests;

#[tokio::test]
async fn explicit_accepted_owner_returns_before_manifest_and_holds_original_admission() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check_output_case(
            platform,
            OutputCase::ExplicitAcceptedBeforeManifest,
        ))
        .await;
    }
}

#[tokio::test]
async fn dropping_accepted_owner_abandons_channel_without_terminal_or_output_claim() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check_output_case(
            platform,
            OutputCase::DropAcceptedBeforeManifest,
        ))
        .await;
    }
}

#[tokio::test]
async fn accepted_owner_rejects_journal_drift_and_revocation_before_manifest_wait() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::AcceptedOwnerJournalDrift,
            OutputCase::AcceptedOwnerRevokedTrust,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn host_cancel_send_persists_bound_pending_intent_without_terminal_claim() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::HostCancelPending,
            OutputCase::HostCancelRevokedGrant,
            OutputCase::HostCancelCorruptPending,
            OutputCase::HostCancelRevokedTrust,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn host_cancel_send_rejects_key_removal_or_rotation_in_payload_fence() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            OutputCase::HostCancelKeyRemovedAtSend,
            OutputCase::HostCancelKeyRotatedAtSend,
        ] {
            Box::pin(check_output_case(platform, case)).await;
        }
    }
}
