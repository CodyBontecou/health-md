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

async fn recover_mode(platform: PeerPlatform, mode: OutputSettingsWriteMode) {
    let (_temporary, client, saved, peer) = stored_pair(platform).await;
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
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let source = tokio::spawn(resume_original(
        listener.local_addr().unwrap().port(),
        saved,
        binding,
        receipts.clone(),
        prefix as u64,
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
    let mut owner = Box::pin(bridge.resume_execution(&store, request.job_id, &clock))
        .await
        .unwrap();
    let received = Box::pin(owner.receive_and_commit()).await.unwrap();
    assert_eq!(received.receipts, receipts);
    assert!(
        Box::pin(owner.confirm_source_completion())
            .await
            .unwrap()
            .source_acknowledged
    );
    assert_eq!(std::fs::read(&record).unwrap(), original);
    for path in &request.plan.predicted_paths {
        assert_eq!(std::fs::read(output.join(&path.0)).unwrap(), expected);
    }
    source.await.unwrap();
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
