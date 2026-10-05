//! Actual authenticated encrypted bridge send/receive, with synthetic native peers only.
#![cfg(unix)] // Private host issuer storage intentionally fails closed on Windows.
use super::*;
use crate as client_crate;
use crate::agent_planning::{HostPlanner, PlanningSource};
use healthmd_protocol::v4::{self, *};
use healthmd_protocol::wire::PeerPlatform;
#[path = "../tests/support/agent.rs"]
mod support;
use support::*;

async fn stored_pair(
    platform: PeerPlatform,
) -> (
    TempDir,
    DirectClient<MemoryCredentials>,
    FakeMobileTrust,
    v4::Peer,
) {
    let temporary = TempDir::new().unwrap();
    let mut client = test_client(&temporary);
    client.layout.root = std::fs::canonicalize(&client.layout.root).unwrap();
    let trust = FakeMobileTrust {
        installation_id: SwiftUuid(Uuid::new_v4()),
        display_name: "Synthetic source".into(),
        reconnect_secret: vec![7; 32],
    };
    let mut state = TrustState::empty(client.identity.installation_id);
    state
        .save_client(TrustedClient {
            installation_id: trust.installation_id,
            display_name: trust.display_name.clone(),
            platform: Some(platform),
            reconnect_secret: trust.reconnect_secret.clone(),
            paired_at: Utc::now(),
            last_connected_at: Utc::now(),
            wake: None,
        })
        .unwrap();
    client.trust_store.save(&state).await.unwrap();
    let peer = v4::Peer {
        host_installation_id: ControlUuid(client.identity.installation_id.0.to_string()),
        source_installation_id: ControlUuid(trust.installation_id.0.to_string()),
        platform: if platform == PeerPlatform::Ios {
            v4::PeerPlatform::Apple
        } else {
            v4::PeerPlatform::Android
        },
    };
    (temporary, client, trust, peer)
}

// One coherent authenticated public-seam flow with separate decision and revocation fences.
#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn bridge_real_store_and_encrypted_fake_sources_plan_then_relay_exact_decisions() {
    for (platform, revoke_approval) in [
        (PeerPlatform::Ios, false),
        (PeerPlatform::Android, false),
        (PeerPlatform::Ios, true),
        (PeerPlatform::Android, true),
    ] {
        let (_temporary, client, saved, peer) = stored_pair(platform).await;
        let (store, output) = enroll(&client.layout.root, &peer, &now()).await;
        let before = client.load_trust().await.unwrap();
        let probe = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);
        let (consent_sender, consent_receiver) = oneshot::channel::<()>();
        let (approval_ready, response_ready) = oneshot::channel::<()>();
        let (response_release, approval_release) = oneshot::channel::<()>();
        let source_peer = peer.clone();
        let source = tokio::spawn(async move {
            let (mut channel, trust) =
                connect_fake_mobile(port, 3, &saved.display_name, None, Some(&saved)).await;
            let local = receive_cli_hello(&mut channel).await;
            assert_eq!(local.protocol_versions, [1, 2, 3, 4]);
            assert!(local.wake.is_none());
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
                &source_peer.platform,
                &local.protocol_versions,
                &remote.protocol_versions,
                true,
            )
            .unwrap();
            let mut native = NativeFake::new(source_peer, now());
            let Message::DiscoveryRequest(request) =
                channel.receive_v4(negotiation).await.unwrap().message
            else {
                panic!("expected closed discovery");
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
            let Message::PlanRequest(request) =
                channel.receive_v4(negotiation).await.unwrap().message
            else {
                panic!("expected closed plan");
            };
            let wire = v4::canonical_json(&request).unwrap();
            assert!(!String::from_utf8(wire).unwrap().contains("root_path"));
            let plan = native.plan(*request).await.unwrap();
            channel
                .send_v4(
                    &Envelope::new(Message::PlanResponse(Box::new(plan))),
                    negotiation,
                )
                .await
                .unwrap();
            // Synthetic native local decision is separate from any approval request.
            consent_receiver.await.unwrap();
            native.store_exact_native_decision();
            let Message::DiscoveryRequest(request) =
                channel.receive_v4(negotiation).await.unwrap().message
            else {
                panic!("expected current discovery");
            };
            channel
                .send_v4(
                    &Envelope::new(Message::DiscoveryResponse(Box::new(
                        native.discovery(request.request_id),
                    ))),
                    negotiation,
                )
                .await
                .unwrap();
            let Message::ApprovalRequest(request) =
                channel.receive_v4(negotiation).await.unwrap().message
            else {
                panic!("expected closed relay");
            };
            let approval = native.relay_approval(*request).await.unwrap();
            if revoke_approval {
                approval_ready.send(()).unwrap();
                approval_release.await.unwrap();
            }
            channel
                .send_v4(
                    &Envelope::new(Message::ApprovalResponse(Box::new(approval))),
                    negotiation,
                )
                .await
                .unwrap();
            if !revoke_approval {
                let Message::DiscoveryRequest(request) =
                    channel.receive_v4(negotiation).await.unwrap().message
                else {
                    panic!("expected current discovery before stored approval return");
                };
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
        });
        let mut bridge = client
            .connect_bridge(
                Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
                port,
                Duration::from_secs(10),
                CancellationToken::new(),
            )
            .await
            .unwrap();
        assert_eq!(
            bridge.negotiation().base,
            if platform == PeerPlatform::Ios { 1 } else { 2 }
        );
        assert_eq!(
            bridge.negotiation().iphone_query_v3,
            platform == PeerPlatform::Ios
        );
        let planner = HostPlanner::new(store.clone());
        let plan = planner
            .plan(&mut bridge, input(&peer), &FixedClock(now()))
            .await
            .unwrap();
        assert_eq!(
            plan.predicted_paths,
            [
                RelativePath("2026/2026-01-01.json".into()),
                RelativePath("2026/2026-01-02.json".into())
            ]
        );
        let request = ApprovalRequest {
            schema: ApprovalRequestSchema::HealthmdAgentApprovalRequest,
            schema_version: 1,
            plan_id: plan.plan_id.clone(),
            request_id: id(11),
            binding: approval_binding(&plan),
        };
        assert!(matches!(
            planner
                .relay_approval(&mut bridge, request.clone(), &FixedClock(now()))
                .await,
            Err(ClientError::Agent(Error::ApprovalRequired))
        ));
        store
            .record_local_decision(2, &plan.plan_id, &now(), &ExplicitFakeLocalConsent)
            .await
            .unwrap();
        consent_sender.send(()).unwrap();
        let clock = FixedClock(now());
        let (result, ()) = tokio::join!(
            planner.relay_approval(&mut bridge, request.clone(), &clock),
            async {
                if revoke_approval {
                    response_ready.await.unwrap();
                    client
                        .trust_store
                        .save(&TrustState::empty(client.identity.installation_id))
                        .await
                        .unwrap();
                    response_release.send(()).unwrap();
                }
            }
        );
        if revoke_approval {
            assert!(result.is_err(), "revoked peer retained approval authority");
            assert_eq!(store.revision().await.unwrap(), 3);
        } else {
            let approval = result.unwrap();
            assert_eq!(approval.binding, request.binding);
            assert_eq!(client.load_trust().await.unwrap(), before);
            // Stored approval requires fresh authenticated native discovery and host trust.
            assert_eq!(
                planner
                    .relay_approval(&mut bridge, request.clone(), &clock)
                    .await
                    .unwrap(),
                approval
            );
            client
                .trust_store
                .save(&TrustState::empty(client.identity.installation_id))
                .await
                .unwrap();
            assert!(
                planner
                    .relay_approval(&mut bridge, request, &clock)
                    .await
                    .is_err()
            );
        }
        assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
        source.await.unwrap();
    }
}

#[tokio::test]
async fn revocation_during_actual_encrypted_plan_response_prevents_persistence_and_return() {
    let (_temporary, client, saved, peer) = stored_pair(PeerPlatform::Ios).await;
    let (store, output) = enroll(&client.layout.root, &peer, &now()).await;
    let probe = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let (ready_sender, ready_receiver) = oneshot::channel::<()>();
    let (release_sender, release_receiver) = oneshot::channel::<()>();
    let source_peer = peer.clone();
    let source = tokio::spawn(async move {
        let (mut channel, trust) =
            connect_fake_mobile(port, 3, &saved.display_name, None, Some(&saved)).await;
        let local = receive_cli_hello(&mut channel).await;
        let remote = mobile_capabilities(
            &trust,
            PeerPlatform::Ios,
            vec![1, 3, 4],
            Some(DirectQueryCapabilities::current()),
        );
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(remote.clone())))
            .await
            .unwrap();
        let negotiation = v4::negotiate(
            &source_peer.platform,
            &local.protocol_versions,
            &remote.protocol_versions,
            true,
        )
        .unwrap();
        let mut native = NativeFake::new(source_peer, now());
        let Message::DiscoveryRequest(request) =
            channel.receive_v4(negotiation).await.unwrap().message
        else {
            panic!("expected discovery");
        };
        channel
            .send_v4(
                &Envelope::new(Message::DiscoveryResponse(Box::new(
                    native.discovery(request.request_id),
                ))),
                negotiation,
            )
            .await
            .unwrap();
        let Message::PlanRequest(request) = channel.receive_v4(negotiation).await.unwrap().message
        else {
            panic!("expected plan");
        };
        let plan = native.plan(*request).await.unwrap();
        ready_sender.send(()).unwrap();
        release_receiver.await.unwrap();
        channel
            .send_v4(
                &Envelope::new(Message::PlanResponse(Box::new(plan))),
                negotiation,
            )
            .await
            .unwrap();
    });
    let mut bridge = client
        .connect_bridge(
            Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
            port,
            Duration::from_secs(10),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    let planner = HostPlanner::new(store.clone());
    let clock = FixedClock(now());
    let (result, ()) = tokio::join!(planner.plan(&mut bridge, input(&peer), &clock), async {
        ready_receiver.await.unwrap();
        client
            .trust_store
            .save(&TrustState::empty(client.identity.installation_id))
            .await
            .unwrap();
        release_sender.send(()).unwrap();
    });
    assert!(result.is_err(), "revoked peer retained plan authority");
    assert_eq!(store.revision().await.unwrap(), 1);
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 0);
    source.await.unwrap();
}

#[tokio::test]
async fn old_peers_and_android_without_base_never_receive_a_v4_probe() {
    for (platform, versions) in [
        (PeerPlatform::Ios, vec![1, 3]),
        (PeerPlatform::Android, vec![2]),
        (PeerPlatform::Android, vec![4]),
    ] {
        let (_temporary, client, saved, peer) = stored_pair(platform).await;
        let before = client.load_trust().await.unwrap();
        let probe = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);
        let source = tokio::spawn(async move {
            let (mut channel, trust) =
                connect_fake_mobile(port, 3, &saved.display_name, None, Some(&saved)).await;
            let local = receive_cli_hello(&mut channel).await;
            assert!(local.wake.is_none());
            channel
                .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                    &trust, platform, versions, None,
                ))))
                .await
                .unwrap();
            // EOF without any encrypted payload after hello: not even a discovery probe.
            assert!(
                tokio::time::timeout(Duration::from_secs(2), channel.receive())
                    .await
                    .unwrap()
                    .is_err()
            );
        });
        let result = client
            .connect_bridge(
                Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
                port,
                Duration::from_secs(10),
                CancellationToken::new(),
            )
            .await;
        match result {
            Err(ClientError::Agent(Error::UnsupportedCapability)) => (),
            Err(error) => panic!("unexpected old-peer outcome: {error}"),
            Ok(_) => panic!("old peer accepted bridge"),
        }
        assert_eq!(client.load_trust().await.unwrap(), before);
        source.await.unwrap();
    }
}
