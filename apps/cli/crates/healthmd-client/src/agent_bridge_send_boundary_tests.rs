//! Production encrypted relay over real loopback TCP; synthetic backing trust only.
use std::{future::poll_fn, task::Poll};

use super::*;
use crate::agent_bridge::BridgeSession;

// This valid closed input exercises transport bounds, not native customization support.
// Its small synthetic values are never printed, and it does not request capture/execution.
fn large_plan_request(peer: &v4::Peer) -> PlanRequest {
    let native = delegation(peer, AuthorityReferenceIssuer::NativeSource, &now());
    let host = delegation(peer, AuthorityReferenceIssuer::AuthorizedHost, &now());
    let mut output = settings(peer);
    output.presentation.frontmatter.custom_fields = (0..128)
        .map(|number| FrontmatterCustomFieldsItem {
            key: SemanticId(format!("synthetic{number:03}")),
            value: "x".repeat(4096),
        })
        .collect();
    PlanRequest {
        schema: PlanRequestSchema::HealthmdAgentPlanRequest,
        schema_version: 1,
        request_id: id(90),
        authority_id: native.authority_id,
        authority_revision: native.grant_revision,
        host_authority_reference: delegation_reference(&host).unwrap(),
        capability_sha256: NativeFake::new(peer.clone(), now())
            .discovery(id(10))
            .capability_sha256,
        intent: ExportIntent {
            schema: ExportIntentSchema::HealthmdAgentExportIntent,
            schema_version: 1,
            intent_id: id(91),
            peer: peer.clone(),
            destination: Destination {
                binding_id: id(3),
                host_installation_id: peer.host_installation_id.clone(),
                identity_sha256: Digest("0".repeat(64)),
                revision: 1,
            },
            calendar_timezone: CalendarZone("UTC".into()),
            timestamp_timezone: ExportIntentTimestampTimezone::Utc,
            dates: input(peer).dates,
            capture_scope: Capture {
                compatibility_detail: CaptureCompatibilityDetail::Summary,
                native_archive: Archive::None {},
                selection: Selection {
                    all_metrics: false,
                    metric_ids: vec![SemanticId("steps".into())],
                    category_ids: vec![],
                    provider_ids: vec![],
                    source_ids: vec![SemanticId(
                        if peer.platform == v4::PeerPlatform::Apple {
                            "apple_health"
                        } else {
                            "health_connect"
                        }
                        .into(),
                    )],
                },
            },
            product: ExportIntentProduct {
                kind: ExportIntentProductType::GeneratedFiles,
            },
            settings_policy: Policy::Explicit {
                settings: Box::new(output),
            },
        },
    }
}

#[allow(clippy::too_many_lines)]
#[tokio::test]
async fn revoked_backing_trust_during_suspended_send_never_delivers_a_complete_request() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let (_temporary, client, saved, peer) = stored_pair(platform).await;
        let before = client.load_trust().await.unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        // Real kernel backpressure, inherited by the accepted socket. No send mock/hook.
        socket2::SockRef::from(&listener)
            .set_send_buffer_size(1024)
            .unwrap();
        let port = listener.local_addr().unwrap().port();
        let (drain_sender, drain_receiver) = oneshot::channel::<()>();
        let (partial_sender, partial_receiver) = oneshot::channel::<()>();
        let source_peer = peer.clone();
        let source = tokio::spawn(async move {
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
                (platform == PeerPlatform::Ios).then(DirectQueryCapabilities::current),
            );
            let negotiation = v4::negotiate(
                &source_peer.platform,
                &local.protocol_versions,
                &remote.protocol_versions,
                true,
            )
            .unwrap();
            channel
                .send(&DirectMessage::Hello(Unlabeled::from(remote)))
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
            drain_receiver.await.unwrap();
            let mut receiving = Box::pin(channel.receive_v4(negotiation));
            // Drain everything already submitted while the host send future stays unpolled.
            // A complete packet here would be a response-wait test, not a send-boundary test.
            tokio::select! {
                result = &mut receiving => {
                    assert!(result.is_err(), "request was fully transmitted before revocation");
                    panic!("send failed before the synthetic trust revocation");
                }
                () = tokio::time::sleep(Duration::from_millis(100)) => (),
            }
            partial_sender.send(()).unwrap();
            tokio::time::timeout(Duration::from_secs(5), receiving)
                .await
                .expect("sender must close or finish within the bounded test")
                .is_ok()
        });
        let selected = Uuid::parse_str(&peer.source_installation_id.0).unwrap();
        let mut bridge = BridgeSession::accept(
            &listener,
            client.identity.installation_id,
            selected,
            client.load_trust().await.unwrap(),
            Duration::from_secs(5),
            CancellationToken::new(),
            &client,
            Some(selected),
        )
        .await
        .unwrap();
        let request = large_plan_request(&peer);
        let bytes = v4::canonical_json(&Envelope::new(Message::PlanRequest(Box::new(
            request.clone(),
        ))))
        .unwrap();
        assert!(bytes.len() > 512 * 1024);
        v4::decode_envelope(&bytes, bridge.negotiation()).unwrap();
        let result = {
            let mut sending = bridge.plan(request);
            // Observe an actual suspension in the production relay, not a timed sleep.
            poll_fn(|cx| match sending.as_mut().poll(cx) {
                Poll::Pending => Poll::Ready(()),
                Poll::Ready(_) => panic!("the undrained large request did not suspend"),
            })
            .await;
            drain_sender.send(()).unwrap();
            partial_receiver.await.unwrap();
            client
                .trust_store
                .save(&TrustState::empty(client.identity.installation_id))
                .await
                .unwrap();
            assert!(
                client
                    .load_trust()
                    .await
                    .unwrap()
                    .trusted_clients
                    .is_empty()
            );
            sending.await
        };
        client.trust_store.save(&before).await.unwrap();
        // Even restored trust cannot reinterpret an already-partial frame as a new RPC.
        assert!(matches!(
            bridge.discover().await,
            Err(ClientError::Agent(Error::BindingChanged))
        ));
        drop(bridge);
        let received_complete = source.await.unwrap();
        assert!(
            !received_complete,
            "revoked source received a complete encrypted request after send suspension"
        );
        assert!(matches!(
            result,
            Err(ClientError::Agent(Error::ApprovalRequired))
        ));
    }
}

struct BufferedPeer<'a> {
    bridge: BridgeSession<'a>,
    drain: oneshot::Sender<()>,
    partial: oneshot::Receiver<()>,
    source: tokio::task::JoinHandle<bool>,
}

// A real synthetic peer at the external network boundary. In the positive control it
// rejects the unsupported custom settings, then serves a separate valid discovery RPC.
#[allow(clippy::too_many_lines)]
async fn buffered_peer<'a>(
    client: &'a DirectClient<MemoryCredentials>,
    saved: FakeMobileTrust,
    peer: &v4::Peer,
    reply: bool,
) -> BufferedPeer<'a> {
    let platform = if peer.platform == v4::PeerPlatform::Apple {
        PeerPlatform::Ios
    } else {
        PeerPlatform::Android
    };
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    socket2::SockRef::from(&listener)
        .set_send_buffer_size(1024)
        .unwrap();
    let port = listener.local_addr().unwrap().port();
    let (drain, drain_receiver) = oneshot::channel();
    let (partial_sender, partial) = oneshot::channel();
    let source_peer = peer.clone();
    let source = tokio::spawn(async move {
        let (mut channel, trust) =
            connect_fake_mobile(port, 3, &saved.display_name, None, Some(&saved)).await;
        let local = receive_cli_hello(&mut channel).await;
        let remote = mobile_capabilities(
            &trust,
            platform,
            if platform == PeerPlatform::Ios {
                vec![1, 3, 4]
            } else {
                vec![2, 4]
            },
            (platform == PeerPlatform::Ios).then(DirectQueryCapabilities::current),
        );
        let negotiation = v4::negotiate(
            &source_peer.platform,
            &local.protocol_versions,
            &remote.protocol_versions,
            true,
        )
        .unwrap();
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(remote)))
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
        drain_receiver.await.unwrap();
        let received = {
            let mut receiving = Box::pin(channel.receive_v4(negotiation));
            tokio::select! {
                _ = &mut receiving => panic!("request finished before the send barrier"),
                () = tokio::time::sleep(Duration::from_millis(100)) => (),
            }
            partial_sender.send(()).unwrap();
            tokio::time::timeout(Duration::from_secs(5), receiving)
                .await
                .unwrap()
        };
        if !reply {
            return received.is_ok();
        }
        let Message::PlanRequest(request) = received.unwrap().message else {
            panic!("expected the unchanged closed plan request");
        };
        assert!(
            *request == large_plan_request(&source_peer),
            "guarded transport changed the typed request"
        );
        channel
            .send_v4(
                &Envelope::new(Message::Rejected(Box::new(AgentError {
                    schema: AgentErrorSchema::HealthmdAgentError,
                    schema_version: 1,
                    code: AgentErrorCode::UnsupportedCapability,
                    request_id: request.request_id,
                    retryable: false,
                }))),
                negotiation,
            )
            .await
            .unwrap();
        let Message::DiscoveryRequest(request) =
            channel.receive_v4(negotiation).await.unwrap().message
        else {
            panic!("healthy complete send must preserve the next RPC sequence");
        };
        channel
            .send_v4(
                &Envelope::new(Message::DiscoveryResponse(Box::new(
                    NativeFake::new(source_peer, now()).discovery(request.request_id),
                ))),
                negotiation,
            )
            .await
            .unwrap();
        true
    });
    let selected = Uuid::parse_str(&peer.source_installation_id.0).unwrap();
    let bridge = BridgeSession::accept(
        &listener,
        client.identity.installation_id,
        selected,
        client.load_trust().await.unwrap(),
        Duration::from_secs(5),
        CancellationToken::new(),
        client,
        Some(selected),
    )
    .await
    .unwrap();
    BufferedPeer {
        bridge,
        drain,
        partial,
        source,
    }
}

#[tokio::test]
async fn healthy_suspended_send_preserves_exact_request_and_next_rpc_sequence() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let (_temporary, client, saved, peer) = stored_pair(platform).await;
        let before = client.load_trust().await.unwrap();
        let BufferedPeer {
            mut bridge,
            drain,
            partial,
            source,
        } = buffered_peer(&client, saved, &peer, true).await;
        let result = {
            let mut sending = bridge.plan(large_plan_request(&peer));
            poll_fn(|cx| match sending.as_mut().poll(cx) {
                Poll::Pending => Poll::Ready(()),
                Poll::Ready(_) => panic!("expected an actual suspended send"),
            })
            .await;
            drain.send(()).unwrap();
            partial.await.unwrap();
            sending.await
        };
        assert!(matches!(
            result,
            Err(ClientError::AgentRejected(
                AgentErrorCode::UnsupportedCapability
            ))
        ));
        assert_eq!(bridge.discover().await.unwrap().peer, peer);
        assert_eq!(client.load_trust().await.unwrap(), before);
        drop(bridge);
        assert!(source.await.unwrap());
    }
}

#[tokio::test]
async fn dropping_a_suspended_send_makes_the_bridge_unusable_without_delivering_a_request() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let (_temporary, client, saved, peer) = stored_pair(platform).await;
        let before = client.load_trust().await.unwrap();
        let BufferedPeer {
            mut bridge,
            drain,
            partial,
            source,
        } = buffered_peer(&client, saved, &peer, false).await;
        {
            let mut sending = bridge.plan(large_plan_request(&peer));
            poll_fn(|cx| match sending.as_mut().poll(cx) {
                Poll::Pending => Poll::Ready(()),
                Poll::Ready(_) => panic!("expected an actual suspended send"),
            })
            .await;
            drain.send(()).unwrap();
            partial.await.unwrap();
            // Drop the real public RPC future while the packet is still incomplete.
        }
        assert!(matches!(
            bridge.require_current().await,
            Err(ClientError::Agent(Error::BindingChanged))
        ));
        assert!(matches!(
            bridge.discover().await,
            Err(ClientError::Agent(Error::BindingChanged))
        ));
        assert_eq!(client.load_trust().await.unwrap(), before);
        drop(bridge);
        assert!(!source.await.unwrap());
    }
}
