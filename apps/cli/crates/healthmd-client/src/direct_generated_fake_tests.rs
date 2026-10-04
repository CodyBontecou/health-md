//! Hermetic mobile dispatch/pairing/lifecycle coverage; all bytes and credentials are synthetic.
use super::*;
use chrono::Timelike as _;
use healthmd_protocol::{
    models::{ExportDestination, ProfileReference},
    transfer::{encode_binary_chunk, sha256_hex},
};

fn free_port() -> u16 {
    std::net::TcpListener::bind(("127.0.0.1", 0))
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

fn file_request(destination: &std::path::Path) -> ExportRequest {
    ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(Uuid::new_v4()),
        created_at: Utc::now().with_nanosecond(0).unwrap(),
        date_selection: DateSelection::Exact(healthmd_protocol::models::ExactDateSelection {
            start: "2026-07-23".into(),
            end: "2026-07-23".into(),
        }),
        settings_policy: SettingsPolicy::RequestedDatesOnly,
        profile_reference: None,
        response_mode: ResponseMode::WriteFiles,
        raw_profile: None,
        canonical_selection: None,
        destination: Some(ExportDestination {
            root_path: destination.to_str().unwrap().into(),
        }),
    }
}

fn generated_hello(trust: &FakeMobileTrust, policies: Vec<v2::SettingsPolicy>) -> v2::SourceHello {
    let mut hello = android_source_hello(trust);
    hello.products.push(v2::ProductCapability {
        product_id: v2::ProductId::GeneratedFilesV1,
        artifact_schema: v2::ArtifactSchema {
            id: "healthmd.generated-files".into(),
            major: 1,
        },
        formats: vec![v2::ArtifactFormat::Markdown],
        providers: vec![],
        settings_policies: policies,
        supports_resume: true,
    });
    hello
}

async fn android_channel(
    port: u16,
    trust: &FakeMobileTrust,
    policies: Vec<v2::SettingsPolicy>,
) -> SecureChannel {
    let (mut channel, _) =
        connect_fake_mobile(port, 2, &trust.display_name, None, Some(trust)).await;
    let _ = receive_cli_hello(&mut channel).await;
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
            trust,
            PeerPlatform::Android,
            vec![2],
            None,
        ))))
        .await
        .unwrap();
    channel
        .send_v2(&v2::Envelope::new(v2::Message::SourceHello(
            generated_hello(trust, policies),
        )))
        .await
        .unwrap();
    channel
}

#[tokio::test]
async fn first_mobile_pairing_supports_both_sources_and_preserves_all_selectors() {
    for (platform, selector) in [
        (PeerPlatform::Ios, 1),
        (PeerPlatform::Ios, 3),
        (PeerPlatform::Android, 2),
        (PeerPlatform::Android, 3),
    ] {
        let temporary = TempDir::new().unwrap();
        let client = test_client(&temporary);
        let (sender, receiver) = oneshot::channel();
        let pair = client.pair_first_mobile(
            "123456",
            "12345678901234567890",
            0,
            Duration::from_secs(2),
            move |port| sender.send(port).unwrap(),
        );
        let peer = async {
            let port = receiver.await.unwrap();
            let code = if selector == 1 {
                "123456"
            } else {
                "12345678901234567890"
            };
            let (mut channel, trust) =
                connect_fake_mobile(port, selector, "Synthetic phone", Some(code), None).await;
            let _ = receive_cli_hello(&mut channel).await;
            channel
                .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                    &trust,
                    platform,
                    if platform == PeerPlatform::Android {
                        vec![2]
                    } else {
                        vec![1]
                    },
                    None,
                ))))
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
        };
        let (result, ()) = tokio::join!(pair, peer);
        let result = result.unwrap();
        assert_eq!(
            result.source.wire_name(),
            if platform == PeerPlatform::Android {
                "android"
            } else {
                "ios"
            }
        );
        assert_eq!(client.paired_devices().await.unwrap().len(), 1);
        assert_eq!(
            client.selected_source(None).await.unwrap().platform,
            Some(platform)
        );
    }
}

async fn send_rejected_code(port: u16, code: &str) {
    let id = Uuid::new_v4();
    let (_, public) = crypto::ephemeral_key_pair().unwrap();
    let nonce = crypto::random_bytes::<32>().unwrap();
    let mut packet = PacketConnection::new(TcpStream::connect(("127.0.0.1", port)).await.unwrap());
    packet
        .send(&SyncPacket::PairingRequest(Unlabeled::from(
            PairingRequest {
                protocol_version: 3,
                device_name: "Rejected fixture".into(),
                client_public_key: public.to_vec(),
                client_nonce: nonce.to_vec(),
                code_verifier: crypto::shared_pairing_verifier(code, id, &public, &nonce).to_vec(),
                client_installation_id: Some(SwiftUuid(id)),
                trusted_verifier: None,
            },
        )))
        .await
        .unwrap();
    assert!(matches!(
        packet.receive().await.unwrap(),
        SyncPacket::PairingRejected(_)
    ));
}

#[tokio::test]
async fn first_mobile_wrong_expired_and_interrupted_pairing_never_create_trust() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let (sender, receiver) = oneshot::channel();
    let pair = client.pair_first_mobile(
        "123456",
        "12345678901234567890",
        0,
        Duration::from_millis(150),
        move |port| sender.send(port).unwrap(),
    );
    let peer = async {
        send_rejected_code(receiver.await.unwrap(), "00000000000000000000").await;
    };
    let (result, ()) = tokio::join!(pair, peer);
    assert!(matches!(result, Err(ClientError::TimedOut)));
    assert!(client.paired_devices().await.unwrap().is_empty());
    // An interrupted listener and an expired (closed) listener cannot write trust.
    let port = free_port();
    let cancellation = CancellationToken::new();
    let pair = client.pair_first_mobile(
        "123456",
        "12345678901234567890",
        port,
        Duration::from_secs(2),
        |_| cancellation.cancel(),
    );
    tokio::select! { _ = pair => panic!("pairing should be interrupted"), () = cancellation.cancelled() => {} }
    assert!(TcpStream::connect(("127.0.0.1", port)).await.is_err());
    assert!(client.paired_devices().await.unwrap().is_empty());
}

#[tokio::test]
async fn onboarding_race_and_ambiguous_selection_never_switch_sources() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let ios = pair_fake_ios(&client).await;
    let (sender, receiver) = oneshot::channel();
    let pair = client.pair_first_mobile(
        "123456",
        "12345678901234567890",
        0,
        Duration::from_secs(2),
        move |port| sender.send(port).unwrap(),
    );
    let peer = async {
        send_rejected_code(receiver.await.unwrap(), "12345678901234567890").await;
    };
    let (result, ()) = tokio::join!(pair, peer);
    assert!(matches!(result, Err(ClientError::PairingConflict)));
    assert_eq!(
        client.selected_source(None).await.unwrap().installation_id,
        ios.installation_id
    );
    let android = pair_fake_android(&client).await;
    assert!(
        matches!(client.prepare_generated_files(file_request(temporary.path()), true, None).await,
        Err(ClientError::DeviceSelectionRequired(devices)) if devices.len() == 2)
    );
    let plan = client
        .prepare_generated_files(
            file_request(temporary.path()),
            true,
            Some(android.installation_id.0),
        )
        .await
        .unwrap();
    assert_eq!(plan.source_id(), android.installation_id.0);
}

#[tokio::test]
async fn older_android_profile_policy_is_rejected_before_export_fields_are_sent() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_android(&client).await;
    let mut request = file_request(temporary.path());
    request.settings_policy = SettingsPolicy::Profile;
    request.profile_reference = Some(ProfileReference {
        profile_id: "11111111-2222-4333-8444-555555555555".into(),
        name: None,
    });
    let plan = client
        .prepare_generated_files(request, false, None)
        .await
        .unwrap();
    let port = free_port();
    let export = client.export_generated_files(plan, port, Duration::from_secs(2));
    let peer = async {
        let mut channel =
            android_channel(port, &trust, vec![v2::SettingsPolicy::SavedDeviceSettings]).await;
        assert!(channel.receive_v2().await.is_err()); // no unsupported envelope reached the peer
    };
    let (result, ()) = tokio::join!(export, peer);
    assert!(matches!(result, Err(ClientError::ExportUnsupported)));
}

#[tokio::test]
async fn android_unknown_and_blocked_profiles_fail_closed_without_settings_fallback() {
    for rejection in ["profile_not_found", "profile_requires_rebind"] {
        let temporary = TempDir::new().unwrap();
        let client = test_client(&temporary);
        let trust = pair_fake_android(&client).await;
        let mut request = file_request(temporary.path());
        request.settings_policy = SettingsPolicy::Profile;
        request.profile_reference = Some(ProfileReference {
            profile_id: "11111111-2222-4333-8444-555555555555".into(),
            name: Some("Display Only".into()),
        });
        let job_id = request.job_id.0;
        let plan = client
            .prepare_generated_files(request, false, None)
            .await
            .unwrap();
        let port = free_port();
        let export = client.export_generated_files(plan, port, Duration::from_secs(2));
        let peer = async {
            let mut channel =
                android_channel(port, &trust, vec![v2::SettingsPolicy::Profile]).await;
            let v2::Message::ExportRequest(request) = channel.receive_v2().await.unwrap().message
            else {
                panic!("expected profile request")
            };
            assert!(matches!(
                request.product,
                v2::ExportProduct::GeneratedFilesV1 {
                    settings_policy: v2::SettingsPolicy::Profile,
                    ..
                }
            ));
            channel
                .send_v2(&v2::Envelope::new(v2::Message::ExportRejected(
                    v2::ExportFailure {
                        job_id: Some(job_id),
                        code: v2::ErrorCode::InvalidRequest,
                        phase: v2::ExportPhase::Validating,
                        retryable: false,
                        public_message: "Profile request rejected.".into(),
                        details: std::collections::BTreeMap::from([(
                            "reason".into(),
                            vec![rejection.into()],
                        )]),
                    },
                )))
                .await
                .unwrap();
            assert!(channel.receive_v2().await.is_err()); // no saved-settings retry
        };
        let (result, ()) = tokio::join!(export, peer);
        assert!(matches!(result, Err(ClientError::InvalidTransfer(_))));
        assert_eq!(
            client.v2_job_record(job_id).unwrap().state,
            JobState::Failed
        );
        assert!(client.android_generated_file_receipt(job_id).is_err());
    }
}

#[derive(Clone)]
struct FileTransfer {
    accepted: v2::ExportAccepted,
    session: v2::TransferSession,
    manifest: v2::ArtifactManifest,
    partition: v2::TransferPartition,
    data: Vec<u8>,
    finalize: v2::TransferFinalize,
}

impl FileTransfer {
    fn new(request: &v2::ExportRequest, destination_id: Uuid) -> Self {
        let fingerprint = v2::request_fingerprint(request).unwrap();
        let binding = v2::PeerBinding {
            source_installation_id: request.source_installation_id,
            destination_installation_id: destination_id,
        };
        let data = b"fresh".to_vec();
        let digest = sha256_hex(&data);
        let session = v2::TransferSession {
            session_id: Uuid::new_v4(),
            job_id: request.job_id,
            request_fingerprint: fingerprint.clone(),
            peer_binding: binding.clone(),
            partition_target_bytes: 32 * 1024 * 1024,
            created_at: request.created_at,
        };
        let artifact_id = Uuid::new_v4();
        Self {
            accepted: v2::ExportAccepted {
                job_id: request.job_id,
                accepted_at: request.created_at,
                peer_binding: binding,
                product_id: v2::ProductId::GeneratedFilesV1,
                resolved_range: v2::ResolvedRange {
                    start_date: "2026-07-23".into(),
                    end_date: "2026-07-23".into(),
                    time_zone_id: "UTC".into(),
                },
                provider_id: None,
                settings_snapshot_sha256: Some("2".repeat(64)),
                request_fingerprint: fingerprint.clone(),
            },
            manifest: v2::ArtifactManifest {
                job_id: request.job_id,
                artifact_id,
                kind: v2::ArtifactKind::GeneratedFile,
                schema: v2::ArtifactSchema {
                    id: "healthmd.generated-files".into(),
                    major: 1,
                },
                media_type: "text/markdown; charset=utf-8".into(),
                byte_count: 5,
                sha256: digest.clone(),
                logical_checksum_sha256: None,
                relative_path: Some("daily.md".into()),
                write_mode: Some(v2::FileWriteMode::Append),
                snapshot_status: None,
                provider_id: None,
            },
            partition: v2::TransferPartition {
                index: 0,
                transfer_id: Uuid::new_v4(),
                artifact_id,
                artifact_offset: 0,
                byte_count: 5,
                chunk_count: 1,
                sha256: digest.clone(),
                previous_sha256: None,
            },
            finalize: v2::TransferFinalize {
                session_id: session.session_id,
                job_id: request.job_id,
                request_fingerprint: fingerprint,
                total_partitions: 1,
                total_bytes: 5,
                final_partition_sha256: Some(digest),
            },
            session,
            data,
        }
    }

    async fn send_partition(&self, channel: &mut SecureChannel, replay: bool) {
        channel
            .send_v2(&v2::Envelope::new(v2::Message::ExportAccepted(
                self.accepted.clone(),
            )))
            .await
            .unwrap();
        channel
            .send_v2(&v2::Envelope::new(v2::Message::TransferSession(
                self.session.clone(),
            )))
            .await
            .unwrap();
        channel
            .send_v2(&v2::Envelope::new(v2::Message::ArtifactManifest(
                self.manifest.clone(),
            )))
            .await
            .unwrap();
        channel
            .send_v2(&v2::Envelope::new(v2::Message::TransferOpen(
                v2::TransferOpen {
                    session: self.session.clone(),
                    partition: self.partition.clone(),
                },
            )))
            .await
            .unwrap();
        let v2::Message::TransferDisposition(disposition) =
            channel.receive_v2().await.unwrap().message
        else {
            panic!("expected disposition")
        };
        assert_eq!(
            disposition.disposition,
            if replay {
                v2::TransferDispositionKind::AlreadyCommitted
            } else {
                v2::TransferDispositionKind::Needed
            }
        );
        if !replay {
            channel
                .send_binary_transfer_frame(
                    &encode_binary_chunk(&healthmd_protocol::models::TransferChunk {
                        transfer_id: SwiftUuid(self.partition.transfer_id),
                        sequence: 1,
                        data: self.data.clone(),
                        sha256: self.partition.sha256.clone(),
                    })
                    .unwrap(),
                )
                .await
                .unwrap();
            assert!(matches!(
                channel.receive_v2().await.unwrap().message,
                v2::Message::TransferChunkAcknowledgement(_)
            ));
            channel
                .send_v2(&v2::Envelope::new(v2::Message::TransferPartitionComplete(
                    v2::TransferPartitionComplete {
                        session_id: self.session.session_id,
                        job_id: self.session.job_id,
                        partition_index: 0,
                        transfer_id: self.partition.transfer_id,
                        partition_sha256: self.partition.sha256.clone(),
                    },
                )))
                .await
                .unwrap();
            assert!(matches!(
                channel.receive_v2().await.unwrap().message,
                v2::Message::TransferPartitionAcknowledgement(_)
            ));
        }
    }
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn android_generated_dispatch_pause_resume_receipt_idempotency_and_cancel() {
    let temporary = TempDir::new().unwrap();
    let destination = temporary.path().join("exports");
    std::fs::create_dir(&destination).unwrap();
    std::fs::write(destination.join("daily.md"), b"old").unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_android(&client).await;
    let input = file_request(&destination);
    let job_id = input.job_id.0;
    let plan = client
        .prepare_generated_files(input, true, None)
        .await
        .unwrap();
    let port = free_port();
    let export = client.export_generated_files(plan, port, Duration::from_secs(2));
    let peer = async {
        let mut channel =
            android_channel(port, &trust, vec![v2::SettingsPolicy::SavedDeviceSettings]).await;
        let v2::Message::ExportRequest(request) = channel.receive_v2().await.unwrap().message
        else {
            panic!("expected v2 request")
        };
        assert!(matches!(
            request.product,
            v2::ExportProduct::GeneratedFilesV1 {
                settings_policy: v2::SettingsPolicy::SavedDeviceSettings,
                ..
            }
        ));
        assert!(
            !String::from_utf8(healthmd_protocol::encoding::canonical_json(&request).unwrap())
                .unwrap()
                .contains(temporary.path().to_str().unwrap())
        );
        let fixture = FileTransfer::new(&request, client.identity.installation_id.0);
        fixture.send_partition(&mut channel, false).await;
        fixture // dropping the socket is not mobile cancellation
    };
    let (result, fixture) = tokio::join!(export, peer);
    assert!(matches!(result, Err(ClientError::ExportPaused(id)) if id == job_id));
    assert_eq!(
        client.v2_job_record(job_id).unwrap().state,
        JobState::Paused
    );
    assert_eq!(
        client.v2_job_record(job_id).unwrap().committed_partitions,
        1
    );
    assert_eq!(std::fs::read(destination.join("daily.md")).unwrap(), b"old");
    assert!(matches!(
        client
            .resume_android(job_id, Some(Uuid::new_v4()), port, Duration::from_secs(2))
            .await,
        Err(ClientError::DeviceNotPaired(_))
    ));
    let resume = client.resume_android(job_id, None, port, Duration::from_secs(2));
    let peer = async {
        let mut channel =
            android_channel(port, &trust, vec![v2::SettingsPolicy::SavedDeviceSettings]).await;
        let v2::Message::ExportRequest(request) = channel.receive_v2().await.unwrap().message
        else {
            panic!("expected saved request")
        };
        assert_eq!(request, client.v2_job_record(job_id).unwrap().request);
        fixture.send_partition(&mut channel, true).await;
        channel
            .send_v2(&v2::Envelope::new(v2::Message::TransferFinalize(
                fixture.finalize.clone(),
            )))
            .await
            .unwrap();
        assert!(matches!(
            channel.receive_v2().await.unwrap().message,
            v2::Message::TransferFinalAcknowledgement(_)
        ));
        channel
            .send_v2(&v2::Envelope::new(v2::Message::CompletionConfirmed(
                v2::JobPayload { job_id },
            )))
            .await
            .unwrap();
    };
    let (resumed, ()) = tokio::join!(resume, peer);
    resumed.unwrap();
    assert_eq!(
        std::fs::read(destination.join("daily.md")).unwrap(),
        b"old\nfresh"
    );
    assert_eq!(
        client.v2_job_record(job_id).unwrap().state,
        JobState::Completed
    );
    let receipt = client.android_generated_file_receipt(job_id).unwrap();
    assert_eq!(receipt["files_written"], 1);
    assert_eq!(receipt["settings_policy"], "saved_device_settings");
    client
        .resume_android(job_id, None, 0, Duration::from_secs(2))
        .await
        .unwrap(); // offline/idempotent
    assert_eq!(
        client.android_generated_file_receipt(job_id).unwrap(),
        receipt
    );
    assert_eq!(
        std::fs::read(destination.join("daily.md")).unwrap(),
        b"old\nfresh"
    );
    let mut next = client.v2_job_record(job_id).unwrap();
    next.request.job_id = Uuid::new_v4();
    next.state = JobState::Paused;
    next.response_artifact = None;
    let cancel_id = next.request.job_id;
    V2JobStore::new(client.layout.clone())
        .unwrap()
        .save(&next)
        .unwrap();
    client
        .request_android_job_cancellation(cancel_id, Some(trust.installation_id.0))
        .unwrap();
    assert_eq!(
        client.v2_job_record(cancel_id).unwrap().state,
        JobState::CancellationPending
    );
    let cancel = client.cancel_android_job(
        cancel_id,
        Some(trust.installation_id.0),
        port,
        Duration::from_secs(2),
    );
    let peer = async {
        let mut channel =
            android_channel(port, &trust, vec![v2::SettingsPolicy::SavedDeviceSettings]).await;
        assert!(
            matches!(channel.receive_v2().await.unwrap().message, v2::Message::Cancel(v2::JobPayload { job_id }) if job_id == cancel_id)
        );
        channel
            .send_v2(&v2::Envelope::new(v2::Message::CancelAcknowledged(
                v2::JobPayload { job_id: cancel_id },
            )))
            .await
            .unwrap();
    };
    let (cancelled, ()) = tokio::join!(cancel, peer);
    cancelled.unwrap();
    assert_eq!(
        client.v2_job_record(cancel_id).unwrap().state,
        JobState::Cancelled
    );
}

#[tokio::test]
async fn older_ios_selector_capability_is_checked_before_export_fields_are_sent() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let mut request = file_request(temporary.path());
    request.canonical_selection = Some(healthmd_protocol::models::CanonicalSelection {
        metric_ids: vec!["sleep_total".into()],
        categories: vec![],
        source_ids: vec!["apple_health".into()],
        object_paths: vec![],
        field_pointers: vec![],
        all_metrics: false,
        detail_level: healthmd_protocol::models::DetailLevel::Summary,
    });
    let plan = client
        .prepare_generated_files(request, false, None)
        .await
        .unwrap();
    let port = free_port();
    let export = client.export_generated_files(plan, port, Duration::from_secs(2));
    let peer = async {
        let (mut channel, _) =
            connect_fake_mobile(port, 1, &trust.display_name, None, Some(&trust)).await;
        let _ = receive_cli_hello(&mut channel).await;
        let mut capabilities = mobile_capabilities(&trust, PeerPlatform::Ios, vec![1], None);
        capabilities.supports_canonical_extraction = false;
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(capabilities)))
            .await
            .unwrap();
        assert!(channel.receive().await.is_err());
    };
    let (result, ()) = tokio::join!(export, peer);
    assert!(matches!(result, Err(ClientError::ExportUnsupported)));
}

#[tokio::test]
async fn ios_generated_dispatch_preserves_v1_request_without_android_fallback() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let request = file_request(temporary.path());
    let plan = client
        .prepare_generated_files(request.clone(), true, None)
        .await
        .unwrap();
    let port = free_port();
    let export = client.export_generated_files(plan, port, Duration::from_secs(2));
    let peer = async {
        let (mut channel, _) =
            connect_fake_mobile(port, 1, &trust.display_name, None, Some(&trust)).await;
        let _ = receive_cli_hello(&mut channel).await;
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &trust,
                PeerPlatform::Ios,
                vec![1],
                None,
            ))))
            .await
            .unwrap();
        let SecurePayload::Message(message) = channel.receive().await.unwrap() else {
            panic!("expected v1 request")
        };
        let DirectMessage::ExportRequest(Unlabeled { value }) = *message else {
            panic!("wrong dispatcher")
        };
        assert_eq!(value, request);
        channel
            .send(&DirectMessage::ExportRejected(Unlabeled::from(
                healthmd_protocol::models::ExportFailure {
                    job_id: Some(request.job_id),
                    reason: healthmd_protocol::models::ExportFailureReason::InvalidRequest,
                    message: "Synthetic rejection.".into(),
                },
            )))
            .await
            .unwrap();
    };
    let (result, ()) = tokio::join!(export, peer);
    assert!(result.is_err());
    assert_eq!(client.paired_devices().await.unwrap().len(), 1);
    assert_eq!(
        client.selected_source_kind(None).await.unwrap(),
        SourceKind::Ios
    );
}
