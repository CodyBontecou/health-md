//! Real host commits followed by a new authenticated channel and full retained prefix.
use super::*;

const BEFORE: &[u8] = b"Original preamble\n\n## Steps\n\n- old\n\n## Notes\n\n- keep\n";

fn before(mode: &OutputSettingsWriteMode) -> &'static [u8] {
    if *mode == OutputSettingsWriteMode::Append {
        b"seed"
    } else {
        BEFORE
    }
}

fn transfer_case(mode: &OutputSettingsWriteMode) -> TransferCase {
    if *mode == OutputSettingsWriteMode::Append {
        TransferCase::Confirmed
    } else {
        TransferCase::MarkdownConfirmed
    }
}

async fn configured_request(
    client: &DirectClient<MemoryCredentials>,
    peer: &v4::Peer,
    mode: &OutputSettingsWriteMode,
) -> (HostAuthorityStore, PathBuf, ExecuteRequest, NativeBinding) {
    let format = if *mode == OutputSettingsWriteMode::Append {
        OutputSettingsFormatsItem::Json
    } else {
        OutputSettingsFormatsItem::Markdown
    };
    let configure = |grant: &mut ExportDelegation| {
        grant.bounds.write_modes = vec![mode.clone()];
        grant.bounds.formats = vec![format.clone()];
    };
    let mut host = delegation(peer, AuthorityReferenceIssuer::AuthorizedHost, &now());
    configure(&mut host);
    let (store, output) = enroll_with_key(
        &client.layout.root,
        peer,
        host,
        std::sync::Arc::new(FakeProtectedKey),
    )
    .await;
    let mut native = NativeFake::new(peer.clone(), now());
    configure(native.stored_native.as_mut().unwrap());
    let mut plan_input = input(peer);
    plan_input.settings.write_mode = mode.clone();
    plan_input.settings.formats = vec![format];
    let request = Box::pin(approved_request_with(&store, &mut native, plan_input)).await;
    let mut binding = transfer_tests::binding(&request, peer_platform(peer), transfer_case(mode));
    for artifact in &mut binding.manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            unreachable!()
        };
        item.write_mode = mode.clone();
        if *mode != OutputSettingsWriteMode::Append {
            item.media_type = ArtifactBranch1MediaType::TextMarkdown;
        }
    }
    binding.validate().unwrap();
    (store, output, request, binding)
}

fn peer_platform(peer: &v4::Peer) -> PeerPlatform {
    if peer.platform == v4::PeerPlatform::Apple {
        PeerPlatform::Ios
    } else {
        PeerPlatform::Android
    }
}

async fn accept_original(
    port: u16,
    saved: FakeMobileTrust,
    binding: NativeBinding,
    wait: oneshot::Receiver<()>,
) {
    let peer = &binding.request.plan.intent.peer;
    let (mut channel, negotiation) = output_channel(port, saved, peer, peer_platform(peer)).await;
    assert_eq!(
        channel.receive_v4(negotiation).await.unwrap().message,
        Message::ExecuteRequest(Box::new(binding.request.clone()))
    );
    channel
        .send_v4(
            &Envelope::new(Message::ExecutionReceipt(Box::new(binding.accepted))),
            negotiation,
        )
        .await
        .unwrap();
    channel
        .send_v4(
            &Envelope::new(Message::ArtifactManifest(Box::new(binding.manifest))),
            negotiation,
        )
        .await
        .unwrap();
    let _ = wait.await;
}

async fn commit_original(
    client: &DirectClient<MemoryCredentials>,
    saved: &FakeMobileTrust,
    store: &HostAuthorityStore,
    output: &Path,
    binding: &NativeBinding,
) -> Vec<CommitReceipt> {
    let peer = &binding.request.plan.intent.peer;
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let (release, wait) = oneshot::channel();
    let source = tokio::spawn(accept_original(
        listener.local_addr().unwrap().port(),
        FakeMobileTrust {
            installation_id: saved.installation_id,
            display_name: saved.display_name.clone(),
            reconnect_secret: saved.reconnect_secret.clone(),
        },
        binding.clone(),
        wait,
    ));
    let mut bridge = connect_bound_bridge(
        client,
        Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
        &listener,
        Duration::from_secs(10),
        CancellationToken::new(),
    )
    .await
    .unwrap();
    let clock = FixedClock(now());
    let mut owner = Box::pin(bridge.begin_execution(store, binding.request.clone(), &clock))
        .await
        .unwrap();
    let input = client.layout.root.join("synthetic-original-input");
    std::fs::write(
        &input,
        payload(transfer_case(
            &binding.request.plan.effective_settings.write_mode,
        )),
    )
    .unwrap();
    let mut receipts = vec![];
    for artifact in &binding.manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            unreachable!()
        };
        let target = output.join(&item.relative_path.0);
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(
            &target,
            before(&binding.request.plan.effective_settings.write_mode),
        )
        .unwrap();
        let receipt = owner
            .commit_artifact(&item.artifact_id, &input)
            .await
            .unwrap();
        assert_eq!(receipt.status, CommitReceiptStatus::Committed);
        assert_eq!(
            receipt.before_sha256.0,
            healthmd_protocol::transfer::sha256_hex(before(
                &binding.request.plan.effective_settings.write_mode
            ))
        );
        assert_eq!(
            receipt.after_sha256.0,
            healthmd_protocol::transfer::sha256_hex(&std::fs::read(target).unwrap())
        );
        receipts.push(receipt);
    }
    drop(owner);
    release.send(()).unwrap();
    source.await.unwrap();
    receipts
}

async fn resume_original(
    port: u16,
    saved: FakeMobileTrust,
    binding: NativeBinding,
    receipts: Vec<CommitReceipt>,
    prefix: u64,
) {
    let peer = &binding.request.plan.intent.peer;
    let platform = peer_platform(peer);
    let (mut channel, negotiation) = output_channel(port, saved, peer, platform).await;
    expect_resume_ack(
        &mut channel,
        negotiation,
        &binding,
        prefix,
        &payload(transfer_case(
            &binding.request.plan.effective_settings.write_mode,
        )),
    )
    .await;
    let Message::ResumeRequest(resume) = channel.receive_v4(negotiation).await.unwrap().message
    else {
        panic!("Resume only")
    };
    assert_eq!(resume.job_id, binding.request.job_id);
    assert_eq!(resume.binding, approval_binding(&binding.request.plan));
    assert_eq!(resume.committed_partition_count, prefix);
    assert_eq!(resume.request_sha256, binding.manifest.request_sha256);
    assert_eq!(
        resume.manifest_sha256,
        document_digest(&binding.manifest).unwrap()
    );
    channel
        .send_v4(
            &Envelope::new(Message::ExecutionReceipt(Box::new(
                binding.accepted.clone(),
            ))),
            negotiation,
        )
        .await
        .unwrap();
    channel
        .send_v4(
            &Envelope::new(Message::ArtifactManifest(Box::new(
                binding.manifest.clone(),
            ))),
            negotiation,
        )
        .await
        .unwrap();
    let request = binding.request.clone();
    let case = transfer_case(&request.plan.effective_settings.write_mode);
    transfer_tests::send_transfer_with_original(
        &mut channel,
        &request,
        platform,
        case,
        prefix,
        binding,
        Some(&receipts),
    )
    .await;
}

fn expected_output(platform: PeerPlatform, mode: &OutputSettingsWriteMode) -> Vec<u8> {
    match mode {
        OutputSettingsWriteMode::Append => {
            let mut expected = b"seed".to_vec();
            expected.extend_from_slice(if platform == PeerPlatform::Ios {
                b"\n\n"
            } else {
                b"\n"
            });
            expected.extend(payload(TransferCase::Confirmed));
            expected
        }
        OutputSettingsWriteMode::MergeMarkdown => {
            b"Fresh preamble\n\n## Steps\n\n- 42 synthetic steps in the recovered day\n\n## Notes\n\n- keep\n\n".to_vec()
        }
        OutputSettingsWriteMode::MergeMarkdownPreservingPreamble => {
            b"Original preamble\n\n## Steps\n\n- 42 synthetic steps in the recovered day\n\n## Notes\n\n- keep\n\n".to_vec()
        }
        OutputSettingsWriteMode::Overwrite => unreachable!(),
    }
}

struct CompletedFixture {
    _temporary: TempDir,
    client: DirectClient<MemoryCredentials>,
    saved: FakeMobileTrust,
    store: HostAuthorityStore,
    output: PathBuf,
    binding: NativeBinding,
    receipts: Vec<CommitReceipt>,
    prefix: u64,
}

#[derive(Clone, Copy, Debug)]
enum FinalAttack {
    Cancel,
    HostExpiry,
    JobExpiry,
}
struct CompletionClock {
    calls: AtomicUsize,
    attack: Option<(usize, FinalAttack)>,
    cancellation: CancellationToken,
}
impl crate::agent_planning::PlanningClock for CompletionClock {
    fn now(&self) -> UtcTimestamp {
        let call = self.calls.fetch_add(1, Ordering::SeqCst) + 1;
        if let Some((at, attack)) = self.attack {
            if call == at {
                return match attack {
                    FinalAttack::Cancel => {
                        self.cancellation.cancel();
                        now()
                    }
                    FinalAttack::HostExpiry => later(&now(), 1800),
                    FinalAttack::JobExpiry => later(&now(), 604_800),
                };
            }
        }
        now()
    }
}

async fn resume_once(
    client: &DirectClient<MemoryCredentials>,
    saved: &FakeMobileTrust,
    store: &HostAuthorityStore,
    binding: &NativeBinding,
    receipts: &[CommitReceipt],
    prefix: u64,
    attack: Option<(usize, FinalAttack)>,
) -> usize {
    let peer = &binding.request.plan.intent.peer;
    let cancellation = CancellationToken::new();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let source = tokio::spawn(resume_original(
        listener.local_addr().unwrap().port(),
        FakeMobileTrust {
            installation_id: saved.installation_id,
            display_name: saved.display_name.clone(),
            reconnect_secret: saved.reconnect_secret.clone(),
        },
        binding.clone(),
        receipts.to_vec(),
        prefix,
    ));
    let mut bridge = connect_bound_bridge(
        client,
        Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
        &listener,
        Duration::from_secs(10),
        cancellation.clone(),
    )
    .await
    .unwrap();
    let clock = CompletionClock {
        calls: AtomicUsize::new(0),
        attack,
        cancellation,
    };
    let mut owner =
        Box::pin(bridge.resume_execution(store, binding.request.job_id.clone(), &clock))
            .await
            .unwrap();
    let received = Box::pin(owner.receive_and_commit()).await.unwrap();
    assert_eq!(&received.receipts, receipts);
    let confirmed = Box::pin(owner.confirm_source_completion()).await;
    if let Some((at, kind)) = attack {
        assert_eq!(clock.calls.load(Ordering::SeqCst), at);
        match kind {
            FinalAttack::Cancel => assert!(
                matches!(confirmed, Err(ClientError::WaitCancelled)),
                "final-clock cancellation returned {confirmed:?}"
            ),
            FinalAttack::HostExpiry | FinalAttack::JobExpiry => assert!(
                matches!(confirmed, Err(ClientError::Agent(Error::ApprovalRequired))),
                "final-clock expiry returned {confirmed:?}"
            ),
        }
    } else {
        assert!(confirmed.unwrap().source_acknowledged);
    }
    source.await.unwrap();
    clock.calls.load(Ordering::SeqCst)
}

async fn recover_mode(platform: PeerPlatform, mode: OutputSettingsWriteMode) -> CompletedFixture {
    let (temporary, client, saved, peer) = stored_pair(platform).await;
    let (store, output, request, binding) = configured_request(&client, &peer, &mode).await;
    let receipts = Box::pin(commit_original(&client, &saved, &store, &output, &binding)).await;
    let expected = expected_output(platform, &mode);
    for path in &request.plan.predicted_paths {
        assert_eq!(std::fs::read(output.join(&path.0)).unwrap(), expected);
    }
    let data = payload(transfer_case(&mode));
    let prefix = data.chunks(9).count() * binding.manifest.artifacts.len();
    Box::pin(retained_fixture_with_payload(
        &store,
        &output,
        &binding,
        prefix,
        RecoveryCase::Exact,
        &data,
    ))
    .await;
    let record = client
        .layout
        .root
        .join("agent-host-v1")
        .join(format!("output-{}.json", request.job_id.0));
    let original = std::fs::read(&record).unwrap();
    let completion = record.with_file_name(format!("completion-{}.json", request.job_id.0));
    let checkpoint = record.with_file_name(format!("transfer-{}.json", request.job_id.0));
    for _ in 0..2 {
        let previous = std::fs::read(&completion).ok();
        let previous_checkpoint = std::fs::read(&checkpoint).unwrap();
        Box::pin(resume_once(
            &client,
            &saved,
            &store,
            &binding,
            &receipts,
            prefix as u64,
            None,
        ))
        .await;
        if let Some(bytes) = previous {
            assert_eq!(std::fs::read(&completion).unwrap(), bytes);
            assert_eq!(std::fs::read(&checkpoint).unwrap(), previous_checkpoint);
        }
        assert_eq!(std::fs::read(&record).unwrap(), original);
        for path in &request.plan.predicted_paths {
            assert_eq!(std::fs::read(output.join(&path.0)).unwrap(), expected);
        }
    }
    CompletedFixture {
        _temporary: temporary,
        client,
        saved,
        store,
        output,
        binding,
        receipts,
        prefix: prefix as u64,
    }
}

#[tokio::test]
async fn authenticated_resume_applies_committed_append_and_markdown_merges_once() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for mode in [
            OutputSettingsWriteMode::Append,
            OutputSettingsWriteMode::MergeMarkdown,
            OutputSettingsWriteMode::MergeMarkdownPreservingPreamble,
        ] {
            Box::pin(recover_mode(platform, mode)).await;
        }
    }
}

#[tokio::test]
async fn requested_write_mode_requires_native_advertisement() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for mode in [
            OutputSettingsWriteMode::Append,
            OutputSettingsWriteMode::MergeMarkdown,
        ] {
            let (_temporary, client, _saved, peer) = stored_pair(platform).await;
            let (store, _output, request, _binding) =
                configured_request(&client, &peer, &mode).await;
            let mut plan_input = input(&peer);
            plan_input.settings = request.plan.effective_settings;
            let mut native = NativeFake::new(peer.clone(), now());
            let planner = HostPlanner::new(store);
            assert!(matches!(
                planner
                    .plan(&mut native, plan_input.clone(), &FixedClock(now()))
                    .await,
                Err(ClientError::Agent(Error::UnsupportedCapability))
            ));
            if mode == OutputSettingsWriteMode::MergeMarkdown {
                // Advertise the requested mode but keep Markdown unavailable independently.
                native.stored_native.as_mut().unwrap().bounds.write_modes = vec![mode];
                assert!(matches!(
                    planner
                        .plan(&mut native, plan_input, &FixedClock(now()))
                        .await,
                    Err(ClientError::Agent(Error::UnsupportedCapability))
                ));
            }
        }
    }
}

#[tokio::test]
async fn requested_append_does_not_widen_stored_host_grant() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let (_temporary, client, _saved, peer) = stored_pair(platform).await;
        let (store, _output) = enroll(&client.layout.root, &peer, &now()).await;
        let mut plan_input = input(&peer);
        plan_input.settings.write_mode = OutputSettingsWriteMode::Append;
        assert!(matches!(
            HostPlanner::new(store)
                .plan(
                    &mut NativeFake::new(peer, now()),
                    plan_input,
                    &FixedClock(now())
                )
                .await,
            Err(ClientError::Agent(Error::ApprovalRequired))
        ));
    }
}

async fn reject_changed_media_type(platform: PeerPlatform, mode: OutputSettingsWriteMode) {
    let (_temporary, client, saved, peer) = stored_pair(platform).await;
    let (store, output, request, mut binding) = configured_request(&client, &peer, &mode).await;
    for artifact in &mut binding.manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            unreachable!()
        };
        item.media_type = if mode == OutputSettingsWriteMode::Append {
            ArtifactBranch1MediaType::TextMarkdown
        } else {
            ArtifactBranch1MediaType::ApplicationJson
        };
    }
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let (release, wait) = oneshot::channel();
    let source = tokio::spawn(accept_original(
        listener.local_addr().unwrap().port(),
        saved,
        binding,
        wait,
    ));
    let mut bridge = connect_bound_bridge(
        &client,
        Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
        &listener,
        Duration::from_secs(10),
        CancellationToken::new(),
    )
    .await
    .unwrap();
    let clock = FixedClock(now());
    let result = Box::pin(bridge.begin_execution(&store, request, &clock)).await;
    assert!(matches!(
        result,
        Err(ClientError::Agent(Error::BindingChanged))
    ));
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
    release.send(()).unwrap();
    source.await.unwrap();
}

#[tokio::test]
async fn authenticated_execution_rejects_media_type_different_from_approved_format() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for mode in [
            OutputSettingsWriteMode::Append,
            OutputSettingsWriteMode::MergeMarkdown,
        ] {
            Box::pin(reject_changed_media_type(platform, mode)).await;
        }
    }
}

#[derive(Clone, Copy)]
enum CompletionDamage {
    Missing,
    Corrupt,
    WrongReference,
}

async fn reject_completed_reconnect(fixture: CompletedFixture, damage: CompletionDamage) {
    let job = &fixture.binding.request.job_id;
    let issuer = fixture.client.layout.root.join("agent-host-v1");
    let path = issuer.join(format!("completion-{}.json", job.0));
    let checkpoint = issuer.join(format!("transfer-{}.json", job.0));
    match damage {
        CompletionDamage::Missing => std::fs::remove_file(&path).unwrap(),
        CompletionDamage::Corrupt => std::fs::write(&path, b"corrupt").unwrap(),
        CompletionDamage::WrongReference => {
            let transaction = OutputTransaction::open_retained(&fixture.store, job)
                .await
                .unwrap();
            let (mut journal, bytes) = transaction.read_transfer::<serde_json::Value>().unwrap();
            journal["completion_sha256"] = serde_json::json!(Digest("f".repeat(64)));
            transaction
                .save_transfer(&journal, Some(&bytes), || async {
                    Ok(fixture.output.clone())
                })
                .await
                .unwrap();
        }
    }
    let after = std::fs::read(&path).ok();
    let original_checkpoint = std::fs::read(&checkpoint).unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = fixture.binding.request.plan.intent.peer.clone();
    let selected = Uuid::parse_str(&peer.source_installation_id.0).unwrap();
    let source = tokio::spawn(async move {
        let (mut channel, negotiation) =
            output_channel(port, fixture.saved, &peer, peer_platform(&peer)).await;
        let received =
            tokio::time::timeout(Duration::from_millis(150), channel.receive_v4(negotiation)).await;
        assert!(
            !matches!(received, Ok(Ok(_))),
            "invalid completed evidence emitted a control"
        );
    });
    let mut bridge = connect_bound_bridge(
        &fixture.client,
        Some(selected),
        &listener,
        Duration::from_secs(10),
        CancellationToken::new(),
    )
    .await
    .unwrap();
    let clock = FixedClock(now());
    assert!(
        Box::pin(bridge.resume_execution(&fixture.store, job.clone(), &clock))
            .await
            .is_err()
    );
    assert_eq!(std::fs::read(&path).ok(), after);
    assert_eq!(std::fs::read(&checkpoint).unwrap(), original_checkpoint);
    for artifact in &fixture.binding.manifest.artifacts {
        let Artifact::Branch1(item) = artifact else {
            unreachable!()
        };
        assert_eq!(
            std::fs::read(fixture.output.join(&item.relative_path.0)).unwrap(),
            expected_output(
                peer_platform(&fixture.binding.request.plan.intent.peer),
                &item.write_mode
            )
        );
    }
    source.await.unwrap();
}

#[tokio::test]
async fn completed_resume_rejects_lost_changed_or_mismatched_completion_without_repair() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for damage in [
            CompletionDamage::Missing,
            CompletionDamage::Corrupt,
            CompletionDamage::WrongReference,
        ] {
            let fixture = Box::pin(recover_mode(platform, OutputSettingsWriteMode::Append)).await;
            Box::pin(reject_completed_reconnect(fixture, damage)).await;
        }
    }
}

#[tokio::test]
async fn completed_resume_rejects_cancellation_and_expiry_at_absolute_final_clock() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let fixture = Box::pin(recover_mode(platform, OutputSettingsWriteMode::Append)).await;
        let final_call = Box::pin(resume_once(
            &fixture.client,
            &fixture.saved,
            &fixture.store,
            &fixture.binding,
            &fixture.receipts,
            fixture.prefix,
            None,
        ))
        .await;
        for kind in [
            FinalAttack::Cancel,
            FinalAttack::HostExpiry,
            FinalAttack::JobExpiry,
        ] {
            Box::pin(resume_once(
                &fixture.client,
                &fixture.saved,
                &fixture.store,
                &fixture.binding,
                &fixture.receipts,
                fixture.prefix,
                Some((final_call, kind)),
            ))
            .await;
        }
    }
}

#[tokio::test]
async fn completed_resume_reuses_exact_record_published_before_checkpoint_reference() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let fixture = Box::pin(recover_mode(platform, OutputSettingsWriteMode::Append)).await;
        let job = &fixture.binding.request.job_id;
        let issuer = fixture.client.layout.root.join("agent-host-v1");
        let completion = issuer.join(format!("completion-{}.json", job.0));
        let original = std::fs::read(&completion).unwrap();
        {
            let transaction = OutputTransaction::open_retained(&fixture.store, job)
                .await
                .unwrap();
            let (mut journal, checkpoint) =
                transaction.read_transfer::<serde_json::Value>().unwrap();
            assert!(
                journal
                    .as_object_mut()
                    .unwrap()
                    .remove("completion_sha256")
                    .is_some()
            );
            transaction
                .save_transfer(&journal, Some(&checkpoint), || async {
                    Ok(fixture.output.clone())
                })
                .await
                .unwrap();
        }
        Box::pin(resume_once(
            &fixture.client,
            &fixture.saved,
            &fixture.store,
            &fixture.binding,
            &fixture.receipts,
            fixture.prefix,
            None,
        ))
        .await;
        assert_eq!(std::fs::read(&completion).unwrap(), original);
        let transaction = OutputTransaction::open_retained(&fixture.store, job)
            .await
            .unwrap();
        let (journal, _) = transaction.read_transfer::<serde_json::Value>().unwrap();
        assert_eq!(
            journal["completion_sha256"],
            healthmd_protocol::transfer::sha256_hex(&original)
        );
    }
}

#[tokio::test]
async fn host_resume_api_preflights_immutable_job_and_confirms_without_reapplying_output() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = Box::pin(recover_mode(platform, OutputSettingsWriteMode::Append)).await;
        let planner = HostPlanner::new(f.store.clone());
        let peer = &f.binding.request.plan.intent.peer;
        let job = &f.binding.request.job_id;
        let clock = AdvancingClock::new();
        let cancellation = CancellationToken::new();
        let root = f.client.layout.root.join("agent-host-v1");
        let retained = |prefix: &str| root.join(format!("{prefix}-{}.json", job.0));
        let paths = [
            retained("output"),
            retained("transfer"),
            retained("completion"),
        ];
        let before: Vec<_> = paths.iter().map(|p| std::fs::read(p).unwrap()).collect();
        planner
            .preflight_retained_resume(peer, job, &clock, &cancellation)
            .await
            .unwrap();
        let mut wrong_peer = peer.clone();
        wrong_peer.source_installation_id = id(199);
        assert!(matches!(
            planner
                .preflight_retained_resume(&wrong_peer, job, &clock, &cancellation)
                .await,
            Err(ClientError::Agent(Error::BindingChanged))
        ));
        assert!(
            planner
                .preflight_retained_resume(peer, &id(198), &clock, &cancellation)
                .await
                .is_err()
        );
        let cancelled = CancellationToken::new();
        cancelled.cancel();
        assert!(matches!(
            planner
                .preflight_retained_resume(peer, job, &clock, &cancelled)
                .await,
            Err(ClientError::WaitCancelled)
        ));
        for (path, original) in paths.iter().zip(&before) {
            assert_eq!(&std::fs::read(path).unwrap(), original);
        }
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let source = tokio::spawn(resume_original(
            listener.local_addr().unwrap().port(),
            FakeMobileTrust {
                installation_id: f.saved.installation_id,
                display_name: f.saved.display_name.clone(),
                reconnect_secret: f.saved.reconnect_secret.clone(),
            },
            f.binding.clone(),
            f.receipts.clone(),
            f.prefix,
        ));
        let mut bridge = connect_bound_bridge(
            &f.client,
            Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
            &listener,
            Duration::from_secs(10),
            cancellation.clone(),
        )
        .await
        .unwrap();
        let receipt = Box::pin(planner.resume_retained(&mut bridge, job.clone(), &clock))
            .await
            .unwrap();
        assert!(receipt.source_acknowledged);
        assert_eq!(&receipt.job_id, job);
        source.await.unwrap();
        for (path, original) in paths.iter().zip(&before) {
            assert_eq!(&std::fs::read(path).unwrap(), original);
        }
        for path in &f.binding.request.plan.predicted_paths {
            assert_eq!(
                std::fs::read(f.output.join(&path.0)).unwrap(),
                expected_output(platform, &OutputSettingsWriteMode::Append)
            );
        }
        let original = std::fs::read(&paths[1]).unwrap();
        std::fs::write(&paths[1], b"corrupt retained prefix").unwrap();
        assert!(
            planner
                .preflight_retained_resume(peer, job, &clock, &cancellation)
                .await
                .is_err()
        );
        assert_eq!(
            std::fs::read(&paths[1]).unwrap(),
            b"corrupt retained prefix"
        );
        std::fs::write(&paths[1], original).unwrap();
    }
}

struct RecoveryDriftClock {
    path: PathBuf,
    changed: std::sync::atomic::AtomicBool,
}
impl crate::agent_planning::PlanningClock for RecoveryDriftClock {
    fn now(&self) -> v4::UtcTimestamp {
        if !self.changed.swap(true, Ordering::SeqCst) {
            std::fs::write(&self.path, b"callback-time recovery drift").unwrap();
        }
        now()
    }
}
#[tokio::test]
async fn host_resume_preflight_rejects_retained_drift_during_authority_callbacks() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = Box::pin(recover_mode(platform, OutputSettingsWriteMode::Append)).await;
        let planner = HostPlanner::new(f.store.clone());
        let peer = &f.binding.request.plan.intent.peer;
        let job = &f.binding.request.job_id;
        for prefix in ["transfer", "completion"] {
            let path = f
                .client
                .layout
                .root
                .join("agent-host-v1")
                .join(format!("{prefix}-{}.json", job.0));
            let original = std::fs::read(&path).unwrap();
            let clock = RecoveryDriftClock {
                path: path.clone(),
                changed: std::sync::atomic::AtomicBool::new(false),
            };
            assert!(
                planner
                    .preflight_retained_resume(peer, job, &clock, &CancellationToken::new())
                    .await
                    .is_err(),
                "{prefix} drift after initial read must reject before listener admission"
            );
            assert!(clock.changed.load(Ordering::SeqCst));
            assert_eq!(
                std::fs::read(&path).unwrap(),
                b"callback-time recovery drift"
            );
            std::fs::write(&path, original).unwrap();
        }
    }
}

async fn retained_stop_fixture(platform: PeerPlatform) -> CompletedFixture {
    let (temporary, client, saved, peer) = stored_pair(platform).await;
    let (store, output, _request, binding) =
        configured_request(&client, &peer, &OutputSettingsWriteMode::Append).await;
    let receipts = Box::pin(commit_original(&client, &saved, &store, &output, &binding)).await;
    let data = payload(TransferCase::Confirmed);
    Box::pin(retained_fixture_with_payload(
        &store,
        &output,
        &binding,
        1,
        RecoveryCase::Exact,
        &data,
    ))
    .await;
    CompletedFixture {
        _temporary: temporary,
        client,
        saved,
        store,
        output,
        binding,
        receipts,
        prefix: 1,
    }
}
fn transfer_stop_receipt(f: &CompletedFixture) -> ExecutionReceipt {
    let path = f
        .client
        .layout
        .root
        .join("agent-host-v1")
        .join(format!("transfer-{}.json", f.binding.request.job_id.0));
    let journal: serde_json::Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    ExecutionReceipt {
        status: ExecutionReceiptStatus::Cancelled,
        source_acknowledged: true,
        artifact_count: f.binding.manifest.artifacts.len() as u64,
        manifest_sha256: document_digest(&f.binding.manifest).unwrap(),
        committed_partition_count: f.prefix,
        frontier_sha256: serde_json::from_value(journal["journal"]["frontier_sha256"].clone())
            .unwrap(),
        ..f.binding.accepted.clone()
    }
}

#[tokio::test]
async fn retained_transfer_stop_persists_exact_prefix_and_confirms_without_renewing_export_grants()
{
    use crate::agent_host::output::PendingOutputStop;
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = Box::pin(retained_stop_fixture(platform)).await;
        let job = &f.binding.request.job_id;
        let root = f.client.layout.root.join("agent-host-v1");
        let record = |prefix: &str| root.join(format!("{prefix}-{}.json", job.0));
        let output = std::fs::read(record("output")).unwrap();
        let transfer = std::fs::read(record("transfer")).unwrap();
        let receipt = transfer_stop_receipt(&f);
        let clock = AdvancingClock::new();
        let transaction = OutputTransaction::open_retained(&f.store, job)
            .await
            .unwrap();
        f.store
            .revoke_local(
                f.store.revision().await.unwrap(),
                &f.binding
                    .request
                    .plan
                    .authority_references
                    .host
                    .authority_id,
            )
            .await
            .unwrap();
        let pending = PendingOutputStop::prepare(transaction, &clock, || async { Ok(()) })
            .await
            .unwrap();
        let request = pending.request().clone();
        let bytes = std::fs::read(record("attempt")).unwrap();
        let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(value["attempt"]["schema_version"], 7);
        assert_eq!(
            value["attempt"]["transfer_evidence"]["transfer_sha256"],
            healthmd_protocol::transfer::sha256_hex(&transfer)
        );
        assert!(value["attempt"].get("source_receipt").is_none());
        drop(pending);
        assert!(
            OutputTransaction::open_retained(&f.store, job)
                .await
                .is_err()
        );
        let replay = PendingOutputStop::open_retained(&f.store, job, &clock, || async { Ok(()) })
            .await
            .unwrap();
        assert_eq!(replay.request(), &request);
        assert_eq!(std::fs::read(record("attempt")).unwrap(), bytes);
        let confirmed = replay
            .confirm(&receipt, &clock, &CancellationToken::new(), || async {
                Ok(())
            })
            .await
            .unwrap();
        assert_eq!(confirmed, receipt);
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(record("attempt")).unwrap()).unwrap();
        assert_eq!(value["attempt"]["schema_version"], 8);
        assert_eq!(std::fs::read(record("output")).unwrap(), output);
        assert_eq!(std::fs::read(record("transfer")).unwrap(), transfer);
        assert!(!record("completion").exists());
        assert_eq!(
            f.store
                .retained_source_stop_confirmation(job, &clock)
                .await
                .unwrap()
                .receipt(),
            &receipt
        );
        for path in &f.binding.request.plan.predicted_paths {
            assert_eq!(
                std::fs::read(f.output.join(&path.0)).unwrap(),
                expected_output(platform, &OutputSettingsWriteMode::Append)
            );
        }
    }
}

#[tokio::test]
async fn retained_transfer_stop_rejects_stage_drift_and_wrong_native_frontier_without_repair() {
    use crate::agent_host::output::PendingOutputStop;
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = Box::pin(retained_stop_fixture(platform)).await;
        let job = &f.binding.request.job_id;
        let root = f.client.layout.root.join("agent-host-v1");
        let attempt = root.join(format!("attempt-{}.json", job.0));
        let transfer = root.join(format!("transfer-{}.json", job.0));
        let journal: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&transfer).unwrap()).unwrap();
        let stage = root.join(
            journal["journal"]["partitions"][0]["stage_name"]
                .as_str()
                .unwrap(),
        );
        let original_stage = std::fs::read(&stage).unwrap();
        let original_attempt = std::fs::read(&attempt).unwrap();
        let clock = AdvancingClock::new();
        let transaction = OutputTransaction::open_retained(&f.store, job)
            .await
            .unwrap();
        assert!(
            PendingOutputStop::prepare(transaction, &clock, || async {
                std::fs::write(&stage, b"changed").unwrap();
                Ok(())
            })
            .await
            .is_err()
        );
        assert_eq!(std::fs::read(&attempt).unwrap(), original_attempt);
        std::fs::write(&stage, &original_stage).unwrap();
        let transaction = OutputTransaction::open_retained(&f.store, job)
            .await
            .unwrap();
        let pending = PendingOutputStop::prepare(transaction, &clock, || async { Ok(()) })
            .await
            .unwrap();
        let pending_bytes = std::fs::read(&attempt).unwrap();
        let mut wrong = transfer_stop_receipt(&f);
        wrong.frontier_sha256 = Digest("f".repeat(64));
        assert!(
            pending
                .confirm(&wrong, &clock, &CancellationToken::new(), || async {
                    Ok(())
                })
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(&attempt).unwrap(), pending_bytes);
        std::fs::write(&stage, b"changed").unwrap();
        assert!(
            PendingOutputStop::open_retained(&f.store, job, &clock, || async { Ok(()) })
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(&attempt).unwrap(), pending_bytes);
    }
}

struct StopPublicationDriftClock {
    stage: PathBuf,
    armed: std::sync::atomic::AtomicBool,
    calls: AtomicUsize,
    changed: std::sync::atomic::AtomicBool,
}
impl crate::agent_planning::PlanningClock for StopPublicationDriftClock {
    fn now(&self) -> v4::UtcTimestamp {
        if self.armed.load(Ordering::SeqCst) && self.calls.fetch_add(1, Ordering::SeqCst) == 2 {
            std::fs::write(&self.stage, b"publication-boundary drift").unwrap();
            self.changed.store(true, Ordering::SeqCst);
        }
        now()
    }
}
#[tokio::test]
async fn retained_transfer_stop_publication_clock_drift_preserves_pending_intent() {
    use crate::agent_host::output::PendingOutputStop;
    let f = Box::pin(retained_stop_fixture(PeerPlatform::Android)).await;
    let job = &f.binding.request.job_id;
    let root = f.client.layout.root.join("agent-host-v1");
    let attempt = root.join(format!("attempt-{}.json", job.0));
    let transfer = root.join(format!("transfer-{}.json", job.0));
    let journal: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&transfer).unwrap()).unwrap();
    let stage = root.join(
        journal["journal"]["partitions"][0]["stage_name"]
            .as_str()
            .unwrap(),
    );
    let receipt = transfer_stop_receipt(&f);
    let transaction = OutputTransaction::open_retained(&f.store, job)
        .await
        .unwrap();
    let pending =
        PendingOutputStop::prepare(transaction, &AdvancingClock::new(), || async { Ok(()) })
            .await
            .unwrap();
    let pending_bytes = std::fs::read(&attempt).unwrap();
    let clock = StopPublicationDriftClock {
        stage,
        armed: std::sync::atomic::AtomicBool::new(false),
        calls: AtomicUsize::new(0),
        changed: std::sync::atomic::AtomicBool::new(false),
    };
    assert!(
        pending
            .confirm(&receipt, &clock, &CancellationToken::new(), || async {
                if std::fs::read_dir(&root).unwrap().any(|entry| {
                    let name = entry.unwrap().file_name();
                    let name = name.to_str().unwrap();
                    name.starts_with(".issuer-")
                        && std::path::Path::new(name)
                            .extension()
                            .and_then(|ext| ext.to_str())
                            .is_some_and(|ext| ext.eq_ignore_ascii_case("tmp"))
                }) {
                    clock.armed.store(true, Ordering::SeqCst);
                }
                Ok(())
            })
            .await
            .is_err()
    );
    assert!(
        clock.changed.load(Ordering::SeqCst),
        "must reach the final staged-publication clock callback"
    );
    assert_eq!(
        std::fs::read(&attempt).unwrap(),
        pending_bytes,
        "rejected publication must preserve pending v7 instead of installing v8"
    );
}

fn sign_transfer_stop_test_record(value: &mut serde_json::Value, domain: &[u8]) {
    use hmac::Mac as _;
    // Dedicated synthetic issuer key; no native credential store or user data.
    let mut mac = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
    mac.update(domain);
    mac.update(&canonical_json(&value["attempt"]).unwrap());
    value["mac"] = format!("{:x}", mac.finalize().into_bytes()).into();
}
#[tokio::test]
async fn retained_transfer_stop_rejects_validly_signed_domain_downgrades_and_substituted_evidence()
{
    use crate::agent_host::output::PendingOutputStop;
    let f = Box::pin(retained_stop_fixture(PeerPlatform::Android)).await;
    let job = &f.binding.request.job_id;
    let path = f
        .client
        .layout
        .root
        .join("agent-host-v1")
        .join(format!("attempt-{}.json", job.0));
    let clock = AdvancingClock::new();
    let transaction = OutputTransaction::open_retained(&f.store, job)
        .await
        .unwrap();
    let pending = PendingOutputStop::prepare(transaction, &clock, || async { Ok(()) })
        .await
        .unwrap();
    let bytes = std::fs::read(&path).unwrap();
    drop(pending);
    let mut positive: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    sign_transfer_stop_test_record(
        &mut positive,
        b"HealthMd.AgentBridge.HostExecutionAttempt.v7\0",
    );
    assert_eq!(
        canonical_json(&positive).unwrap(),
        bytes,
        "test signer must reproduce the real v7 MAC"
    );
    for case in 0..3 {
        let mut value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let domain: &[u8] = match case {
            0 => b"HealthMd.AgentBridge.HostExecutionAttempt.v5\0",
            1 => {
                value["attempt"]["schema_version"] = 5.into();
                value["attempt"]
                    .as_object_mut()
                    .unwrap()
                    .remove("transfer_evidence");
                b"HealthMd.AgentBridge.HostExecutionAttempt.v5\0"
            }
            _ => {
                value["attempt"]["transfer_evidence"]["transfer_sha256"] = "0".repeat(64).into();
                b"HealthMd.AgentBridge.HostExecutionAttempt.v7\0"
            }
        };
        sign_transfer_stop_test_record(&mut value, domain);
        let changed = canonical_json(&value).unwrap();
        std::fs::write(&path, &changed).unwrap();
        assert!(
            PendingOutputStop::open_retained(&f.store, job, &clock, || async { Ok(()) })
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(&path).unwrap(), changed);
    }
    std::fs::write(&path, &bytes).unwrap();
    let pending = PendingOutputStop::open_retained(&f.store, job, &clock, || async { Ok(()) })
        .await
        .unwrap();
    pending
        .confirm(
            &transfer_stop_receipt(&f),
            &clock,
            &CancellationToken::new(),
            || async { Ok(()) },
        )
        .await
        .unwrap();
    let bytes = std::fs::read(&path).unwrap();
    let mut positive: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    sign_transfer_stop_test_record(
        &mut positive,
        b"HealthMd.AgentBridge.HostExecutionAttempt.v8\0",
    );
    assert_eq!(
        canonical_json(&positive).unwrap(),
        bytes,
        "test signer must reproduce the real v8 MAC"
    );
    for case in 0..2 {
        let mut value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let domain: &[u8] = if case == 0 {
            value["attempt"]["schema_version"] = 6.into();
            b"HealthMd.AgentBridge.HostExecutionAttempt.v6\0"
        } else {
            value["attempt"]["source_receipt"]["frontier_sha256"] = "f".repeat(64).into();
            b"HealthMd.AgentBridge.HostExecutionAttempt.v8\0"
        };
        sign_transfer_stop_test_record(&mut value, domain);
        let changed = canonical_json(&value).unwrap();
        std::fs::write(&path, &changed).unwrap();
        assert!(
            Box::pin(f.store.retained_source_stop_confirmation(job, &clock))
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(&path).unwrap(), changed);
    }
}

#[tokio::test]
async fn retained_transfer_stop_rejects_completion_evidence_drift_before_publication() {
    use crate::agent_host::output::PendingOutputStop;
    let f = Box::pin(recover_mode(
        PeerPlatform::Ios,
        OutputSettingsWriteMode::Append,
    ))
    .await;
    let job = &f.binding.request.job_id;
    let root = f.client.layout.root.join("agent-host-v1");
    let attempt = root.join(format!("attempt-{}.json", job.0));
    let completion = root.join(format!("completion-{}.json", job.0));
    let original_attempt = std::fs::read(&attempt).unwrap();
    let transaction = OutputTransaction::open_retained(&f.store, job)
        .await
        .unwrap();
    assert!(
        PendingOutputStop::prepare(transaction, &AdvancingClock::new(), || async {
            std::fs::write(&completion, b"completion callback drift").unwrap();
            Ok(())
        })
        .await
        .is_err()
    );
    assert_eq!(std::fs::read(&attempt).unwrap(), original_attempt);
    assert_eq!(
        std::fs::read(&completion).unwrap(),
        b"completion callback drift"
    );
}
