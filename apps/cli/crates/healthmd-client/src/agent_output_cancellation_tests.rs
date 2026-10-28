//! Original-session output Stop over both real encrypted synthetic native envelopes.
use super::*;
use healthmd_protocol::{
    encoding::SwiftUuid,
    models as a, v2,
    wire::{DirectMessage, Unlabeled},
};
use transfer_tests::{apple_session, send};
#[derive(Clone, Copy, Debug, PartialEq)]
enum Case {
    Immediate,
    Retained,
    DropOwner,
    LocalCancel,
    Session,
    OneManifest,
    Full,
    Empty,
    RevokedGrant,
    WrongSession,
    WrongManifest,
    WrongOpen,
    Extra,
    Binary,
    NoAck,
}
impl Case {
    fn succeeds(self) -> bool {
        matches!(
            self,
            Self::Immediate
                | Self::Retained
                | Self::Session
                | Self::OneManifest
                | Self::Full
                | Self::Empty
                | Self::RevokedGrant
        )
    }
}
async fn queued(
    channel: &mut SecureChannel,
    platform: PeerPlatform,
    binding: &crate::agent_host::output::NativeBinding,
    case: Case,
) {
    if matches!(case, Case::Immediate | Case::NoAck | Case::Retained) {
        return;
    }
    let peer = &binding.request.plan.intent.peer;
    let mut session = v2::TransferSession {
        session_id: Uuid::parse_str(&id(30).0).unwrap(),
        job_id: Uuid::parse_str(&binding.request.job_id.0).unwrap(),
        request_fingerprint: binding.manifest.request_sha256.0.clone(),
        peer_binding: v2::PeerBinding {
            source_installation_id: Uuid::parse_str(&peer.source_installation_id.0).unwrap(),
            destination_installation_id: Uuid::parse_str(&peer.host_installation_id.0).unwrap(),
        },
        partition_target_bytes: 50_331_648,
        created_at: chrono::DateTime::from_timestamp(
            binding.accepted.expires_at.seconds().unwrap() - 604_800,
            0,
        )
        .unwrap(),
    };
    if case == Case::WrongSession {
        session.request_fingerprint = "f".repeat(64);
    }
    send(
        channel,
        platform,
        DirectMessage::TransferSession(Unlabeled::from(apple_session(&session))),
        v2::Message::TransferSession(session.clone()),
    )
    .await;
    if case == Case::Session || case == Case::WrongSession {
        return;
    }
    for item in &binding.manifest.artifacts {
        let Artifact::Branch1(item) = item else {
            unreachable!()
        };
        let path = if case == Case::WrongManifest {
            "unrelated.json".into()
        } else {
            item.relative_path.0.clone()
        };
        let file_id = Uuid::parse_str(&item.artifact_id.0).unwrap();
        send(
            channel,
            platform,
            DirectMessage::FileManifest(Unlabeled::from(a::FileManifest {
                job_id: SwiftUuid(session.job_id),
                file_id: SwiftUuid(file_id),
                relative_path: path.clone(),
                byte_count: i64::try_from(item.byte_count).unwrap(),
                sha256: item.sha256.0.clone(),
                write_mode: serde_json::from_value(serde_json::to_value(&item.write_mode).unwrap())
                    .unwrap(),
            })),
            v2::Message::ArtifactManifest(v2::ArtifactManifest {
                job_id: session.job_id,
                artifact_id: file_id,
                kind: v2::ArtifactKind::GeneratedFile,
                schema: v2::ArtifactSchema {
                    id: "healthmd.generated-files".into(),
                    major: 1,
                },
                media_type: serde_json::to_value(&item.media_type)
                    .unwrap()
                    .as_str()
                    .unwrap()
                    .into(),
                byte_count: item.byte_count,
                sha256: item.sha256.0.clone(),
                relative_path: Some(path),
                write_mode: Some(
                    serde_json::from_value(serde_json::to_value(&item.write_mode).unwrap())
                        .unwrap(),
                ),
                logical_checksum_sha256: None,
                snapshot_status: None,
                provider_id: None,
            }),
        )
        .await;
        if matches!(case, Case::OneManifest | Case::WrongManifest) {
            return;
        }
    }
    queued_open(channel, platform, binding, case, session).await;
}
async fn queued_open(
    channel: &mut SecureChannel,
    platform: PeerPlatform,
    binding: &crate::agent_host::output::NativeBinding,
    case: Case,
    session: v2::TransferSession,
) {
    if let Some(Artifact::Branch1(item)) = binding.manifest.artifacts.first() {
        let partition = v2::TransferPartition {
            index: u64::from(case == Case::WrongOpen),
            transfer_id: Uuid::parse_str(&id(31).0).unwrap(),
            artifact_id: Uuid::parse_str(&item.artifact_id.0).unwrap(),
            artifact_offset: 0,
            byte_count: item.byte_count,
            chunk_count: item
                .byte_count
                .div_ceil(healthmd_protocol::TRANSFER_FRAME_BYTES as u64),
            sha256: item.sha256.0.clone(),
            previous_sha256: None,
        };
        for _ in 0..if case == Case::Extra { 2 } else { 1 } {
            send(
                channel,
                platform,
                DirectMessage::TransferOpen(Unlabeled::from(a::TransferOpen {
                    session: apple_session(&session),
                    partition: a::TransferPartition {
                        index: i64::try_from(partition.index).unwrap(),
                        transfer_id: SwiftUuid(partition.transfer_id),
                        source_dates: vec![item.artifact_id.0.clone()],
                        byte_count: i64::try_from(partition.byte_count).unwrap(),
                        chunk_count: i64::try_from(partition.chunk_count).unwrap(),
                        sha256: partition.sha256.clone(),
                        previous_sha256: None,
                        item_segment: Some(a::TransferItemSegment {
                            item_id: item.artifact_id.0.clone(),
                            offset: 0,
                            item_byte_count: i64::try_from(item.byte_count).unwrap(),
                            is_final_segment: true,
                        }),
                    },
                })),
                v2::Message::TransferOpen(v2::TransferOpen {
                    session: session.clone(),
                    partition: partition.clone(),
                }),
            )
            .await;
        }
        if case == Case::Binary {
            channel
                .send_binary_transfer_frame(b"HMDDIRCTsynthetic-unexpected-data")
                .await
                .unwrap();
        }
    } else {
        send(
            channel,
            platform,
            DirectMessage::TransferFinalize(Unlabeled::from(a::TransferFinalize {
                session_id: SwiftUuid(session.session_id),
                job_id: SwiftUuid(session.job_id),
                request_fingerprint: a::RequestFingerprint {
                    version: 1,
                    sha256: session.request_fingerprint.clone(),
                },
                total_partitions: 0,
                total_bytes: 0,
                final_partition_sha256: None,
                outcome: None,
            })),
            v2::Message::TransferFinalize(v2::TransferFinalize {
                session_id: session.session_id,
                job_id: session.job_id,
                request_fingerprint: session.request_fingerprint,
                total_partitions: 0,
                total_bytes: 0,
                final_partition_sha256: None,
            }),
        )
        .await;
    }
}

async fn check(platform: PeerPlatform, case: Case) {
    let f = accepted_fixture(platform).await;
    let mut binding = synthetic_binding(&f.request, platform);
    if case == Case::Empty {
        binding.manifest.capture_status = v4::ArtifactManifestCaptureStatus::CompleteEmpty;
        binding.manifest.artifacts.clear();
    }
    let mut receipt = binding.accepted.clone();
    receipt.status = ExecutionReceiptStatus::Cancelled;
    receipt.source_acknowledged = case != Case::NoAck;
    receipt.artifact_count = binding.manifest.artifacts.len() as u64;
    receipt.manifest_sha256 = document_digest(&binding.manifest).unwrap();
    receipt.frontier_sha256 = Digest("a".repeat(64));
    if case == Case::Retained {
        let transaction =
            output_stop_tests::output_transaction_with_binding(&f, binding.clone()).await;
        drop(
            crate::agent_host::output::PendingOutputStop::prepare(
                transaction,
                &f.clock,
                || async { Ok(()) },
            )
            .await
            .unwrap(),
        );
    }
    let expected = receipt.clone();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let (release, wait) = oneshot::channel();
    let saved = FakeMobileTrust {
        installation_id: f.saved.installation_id,
        display_name: f.saved.display_name.clone(),
        reconnect_secret: f.saved.reconnect_secret.clone(),
    };
    let source = tokio::spawn(Box::pin(serve_source(
        port,
        saved,
        SourceCase {
            binding,
            receipt,
            platform,
            case,
        },
        wait,
    )));

    let cancellation = CancellationToken::new();
    let mut bridge = connect_bound_bridge(
        &f.client,
        Some(Uuid::parse_str(&f.peer.source_installation_id.0).unwrap()),
        &listener,
        Duration::from_secs(10),
        cancellation.clone(),
    )
    .await
    .unwrap();
    let pending = if case == Case::Retained {
        revoke_host_grant(&f).await;
        bridge
            .request_retained_output_cancellation(&f.store, &f.request.job_id, &f.clock)
            .await
            .unwrap()
    } else {
        let execution = bridge
            .begin_execution(&f.store, f.request.clone(), &f.clock)
            .await
            .unwrap();
        if case == Case::RevokedGrant {
            revoke_host_grant(&f).await;
        }
        execution.request_cancellation().await.unwrap()
    };
    assert_eq!(pending.request().job_id, f.request.job_id);
    let result = if case == Case::DropOwner {
        drop(pending);
        Err(ClientError::WaitCancelled)
    } else {
        if case == Case::LocalCancel {
            cancellation.cancel();
        }
        pending.wait_source_confirmation().await
    };
    Box::pin(assert_host_evidence(&f, platform, case, result, &expected)).await;
    assert!(
        crate::agent_planning::PlanningSource::discover(&mut bridge)
            .await
            .is_err()
    );
    let _ = release.send(());
    source.await.unwrap();
}
#[tokio::test]
async fn original_output_stop_confirms_only_bound_source_facts_without_any_transfer_ack() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::Immediate,
            Case::Retained,
            Case::DropOwner,
            Case::LocalCancel,
            Case::Session,
            Case::OneManifest,
            Case::Full,
            Case::Empty,
            Case::RevokedGrant,
            Case::WrongSession,
            Case::WrongManifest,
            Case::WrongOpen,
            Case::Extra,
            Case::Binary,
            Case::NoAck,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}

struct SourceCase {
    binding: crate::agent_host::output::NativeBinding,
    receipt: ExecutionReceipt,
    platform: PeerPlatform,
    case: Case,
}
async fn serve_source(
    port: u16,
    saved: FakeMobileTrust,
    setup: SourceCase,
    wait: oneshot::Receiver<()>,
) {
    let SourceCase {
        binding,
        receipt,
        platform,
        case,
    } = setup;
    let request = binding.request.clone();
    let source_peer = request.plan.intent.peer.clone();

    let (mut channel, n) = output_channel(port, saved, &source_peer, platform).await;
    if case != Case::Retained {
        let Message::ExecuteRequest(execute) = channel.receive_v4(n).await.unwrap().message else {
            panic!("expected exact execution");
        };
        assert_eq!(*execute, request);
        channel
            .send_v4_guarded(
                &Envelope::new(Message::ExecutionReceipt(Box::new(
                    binding.accepted.clone(),
                ))),
                n,
                || async { Ok(()) },
            )
            .await
            .unwrap();
        channel
            .send_v4_guarded(
                &Envelope::new(Message::ArtifactManifest(Box::new(
                    binding.manifest.clone(),
                ))),
                n,
                || async { Ok(()) },
            )
            .await
            .unwrap();
    }
    queued(&mut channel, platform, &binding, case).await;
    let Message::CancelRequest(cancel) = channel.receive_v4(n).await.unwrap().message else {
        panic!("Only Stop permitted; no disposition/ACK");
    };
    assert_eq!(cancel.job_id, request.job_id);
    assert_eq!(cancel.request_sha256, document_digest(&request).unwrap());
    channel
        .send_bridge_plaintext_guarded(
            &canonical_json(&Envelope::new(Message::ExecutionReceipt(Box::new(receipt)))).unwrap(),
            || async { Ok(()) },
        )
        .await
        .unwrap();
    let _ = wait.await;
    assert!(
        tokio::time::timeout(Duration::from_millis(50), channel.receive_agent_payload(n))
            .await
            .is_err(),
        "Stop must emit no further message, even malformed or base ACK"
    );
}

async fn assert_host_evidence(
    f: &AcceptedFixture,
    platform: PeerPlatform,
    case: Case,
    result: Result<crate::agent_bridge::SourceStopConfirmation, ClientError>,
    expected: &ExecutionReceipt,
) {
    let attempt = f
        .client
        .layout
        .root
        .join("agent-host-v1")
        .join(format!("attempt-{}.json", f.request.job_id.0));
    let value: serde_json::Value =
        serde_json::from_slice(&std::fs::read(attempt).unwrap()).unwrap();
    if case.succeeds() {
        assert_eq!(result.unwrap().receipt(), expected);
        assert_eq!(value["attempt"]["schema_version"], 6);
        assert_eq!(
            f.store
                .retained_source_stop_confirmation(&f.request.job_id, &f.clock)
                .await
                .unwrap()
                .receipt(),
            expected
        );
    } else {
        assert!(result.is_err(), "accepted {platform:?} {case:?}");
        assert_eq!(value["attempt"]["schema_version"], 5);
    }
    for prefix in ["transfer", "completion"] {
        assert!(
            !f.client
                .layout
                .root
                .join("agent-host-v1")
                .join(format!("{prefix}-{}.json", f.request.job_id.0))
                .exists()
        );
    }
    assert_eq!(std::fs::read_dir(&f.output).unwrap().count(), 0);
}

async fn revoke_host_grant(f: &AcceptedFixture) {
    f.store
        .revoke_local(
            f.store.revision().await.unwrap(),
            &f.request.plan.authority_references.host.authority_id,
        )
        .await
        .unwrap();
}
