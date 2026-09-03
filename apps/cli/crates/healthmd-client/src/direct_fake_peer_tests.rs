use std::{collections::HashMap, sync::Mutex, time::Duration};

use async_trait::async_trait;
use base64::Engine as _;
use healthmd_protocol::{
    crypto,
    models::SettingsPolicy,
    v2,
    wire::{
        DirectMessage, DirectQueryCapabilities, DirectQueryDetailLevel, DirectQueryRequest,
        DirectQueryResponse, PairingRequest, PeerCapabilities, PeerPlatform, RawProfile,
        SyncPacket, Unlabeled,
    },
};
use secrecy::{ExposeSecret as _, SecretString};
use tempfile::TempDir;
use tokio::{net::TcpStream, sync::oneshot};

use super::*;
use crate::{
    credentials::CredentialStore,
    packet::PacketConnection,
    secure_channel::{SecureChannel, SecurePayload},
};

#[derive(Default)]
struct MemoryCredentials(Mutex<HashMap<String, String>>);

#[async_trait]
impl CredentialStore for MemoryCredentials {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        Ok(self
            .0
            .lock()
            .expect("memory credential lock")
            .get(account)
            .cloned()
            .map(SecretString::from))
    }

    async fn set(&self, account: &str, value: SecretString) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("memory credential lock")
            .insert(account.into(), value.expose_secret().to_owned());
        Ok(())
    }

    async fn delete(&self, account: &str) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("memory credential lock")
            .remove(account);
        Ok(())
    }
}

struct FakeMobileTrust {
    installation_id: SwiftUuid,
    display_name: String,
    reconnect_secret: Vec<u8>,
}

fn test_client(temporary: &TempDir) -> DirectClient<MemoryCredentials> {
    let layout = StorageLayout {
        root: temporary.path().join("state"),
    };
    let identity = IdentityStore::new(layout.clone())
        .load_or_create(Utc::now())
        .unwrap();
    DirectClient {
        identity,
        layout,
        display_name: "Hermetic test CLI".into(),
        trust_store: TrustStore::new(MemoryCredentials::default()),
    }
}

async fn connect_fake_mobile(
    port: u16,
    protocol_version: i32,
    display_name: &str,
    pairing_code: Option<&str>,
    saved: Option<&FakeMobileTrust>,
) -> (SecureChannel, FakeMobileTrust) {
    let installation_id =
        saved.map_or_else(|| SwiftUuid(Uuid::new_v4()), |value| value.installation_id);
    let (private_key, public_key) = crypto::ephemeral_key_pair().unwrap();
    let nonce = crypto::random_bytes::<32>().unwrap();
    let code_verifier = pairing_code.map_or_else(Vec::new, |code| match protocol_version {
        1 => crypto::pairing_verifier(code, installation_id.0, &public_key, &nonce).to_vec(),
        2 => {
            crypto::android_pairing_verifier(code, installation_id.0, &public_key, &nonce).to_vec()
        }
        3 => crypto::shared_pairing_verifier(code, installation_id.0, &public_key, &nonce).to_vec(),
        _ => panic!("unsupported fake pairing selector"),
    });
    let trusted_verifier = saved.map(|value| {
        crypto::trusted_client_verifier(
            &value.reconnect_secret,
            installation_id.0,
            &public_key,
            &nonce,
        )
        .to_vec()
    });
    let mut last_error = None;
    let mut stream = None;
    for _ in 0..500 {
        match TcpStream::connect(("127.0.0.1", port)).await {
            Ok(connected) => {
                stream = Some(connected);
                break;
            }
            Err(error) => last_error = Some(error),
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    let stream = stream.unwrap_or_else(|| panic!("fake peer could not connect: {last_error:?}"));
    let mut packet = PacketConnection::new(stream);
    packet
        .send(&SyncPacket::PairingRequest(Unlabeled::from(
            PairingRequest {
                protocol_version,
                device_name: display_name.into(),
                client_public_key: public_key.to_vec(),
                client_nonce: nonce.to_vec(),
                code_verifier,
                client_installation_id: Some(installation_id),
                trusted_verifier,
            },
        )))
        .await
        .unwrap();
    let SyncPacket::PairingResponse(Unlabeled { value: response }) =
        packet.receive().await.unwrap()
    else {
        panic!("expected pairing response");
    };
    assert_eq!(response.protocol_version, protocol_version);
    let server_id = response.mac_installation_id.unwrap();
    let shared = crypto::x25519_shared_secret(&private_key, &response.server_public_key).unwrap();
    let session_key = crypto::session_key(&shared, &nonce, &response.server_nonce);
    let reconnect_secret = if let Some(saved) = saved {
        saved.reconnect_secret.clone()
    } else {
        crypto::open(
            response.sealed_reconnect_secret.as_ref().unwrap(),
            &session_key,
        )
        .unwrap()
    };
    (
        SecureChannel::new(packet, session_key, server_id.0, response.mac_name),
        FakeMobileTrust {
            installation_id,
            display_name: display_name.into(),
            reconnect_secret,
        },
    )
}

async fn receive_cli_hello(channel: &mut SecureChannel) -> PeerCapabilities {
    let SecurePayload::Message(message) = channel.receive().await.unwrap() else {
        panic!("expected CLI hello");
    };
    let DirectMessage::Hello(Unlabeled { value }) = *message else {
        panic!("expected CLI hello");
    };
    value
}

fn mobile_capabilities(
    trust: &FakeMobileTrust,
    platform: PeerPlatform,
    versions: Vec<i32>,
    query: Option<DirectQueryCapabilities>,
) -> PeerCapabilities {
    PeerCapabilities {
        protocol_versions: versions,
        platform,
        installation_id: trust.installation_id,
        supported_raw_profiles: vec![RawProfile::CanonicalSourceRecordsV1],
        supports_durable_jobs: true,
        supports_canonical_extraction: true,
        transfer: healthmd_protocol::wire::TransferCapabilities::default(),
        query,
        wake: None,
    }
}

fn android_source_hello(trust: &FakeMobileTrust) -> v2::SourceHello {
    v2::SourceHello {
        source: v2::SourceIdentity {
            installation_id: trust.installation_id.0,
            platform: v2::SourcePlatform::Android,
            display_name: trust.display_name.clone(),
            app_version: "test".into(),
        },
        products: vec![v2::ProductCapability {
            product_id: v2::ProductId::AndroidProviderNativeSnapshotV1,
            artifact_schema: v2::ArtifactSchema {
                id: "healthmd.android_provider_native_snapshot".into(),
                major: 1,
            },
            formats: vec![v2::ArtifactFormat::Json],
            providers: vec!["health_connect".into()],
            settings_policies: Vec::new(),
            supports_resume: true,
        }],
        limits: v2::ProtocolLimits {
            maximum_control_bytes: 2 * 1_024 * 1_024,
            maximum_chunk_bytes: 512 * 1_024,
            preferred_partition_bytes: 48 * 1_024 * 1_024,
        },
    }
}

async fn pair_fake_ios(client: &DirectClient<MemoryCredentials>) -> FakeMobileTrust {
    let (port_sender, port_receiver) = oneshot::channel();
    let pair = client.pair(
        "123456",
        "12345678901234567890",
        0,
        Duration::from_secs(5),
        move |port| port_sender.send(port).unwrap(),
    );
    let peer = async {
        let port = port_receiver.await.unwrap();
        let (mut channel, trust) = connect_fake_mobile(
            port,
            3,
            "Hermetic iPhone",
            Some("12345678901234567890"),
            None,
        )
        .await;
        let _ = receive_cli_hello(&mut channel).await;
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &trust,
                PeerPlatform::Ios,
                vec![1, 3],
                Some(DirectQueryCapabilities::current()),
            ))))
            .await
            .unwrap();
        trust
    };
    let (paired, trust) = tokio::join!(pair, peer);
    paired.unwrap();
    trust
}

async fn respond_with_ios_status(port: u16, trust: &FakeMobileTrust, app_active: bool) {
    let (mut channel, reconnect) =
        connect_fake_mobile(port, 1, &trust.display_name, None, Some(trust)).await;
    let _ = receive_cli_hello(&mut channel).await;
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
            &reconnect,
            PeerPlatform::Ios,
            vec![1, 3],
            Some(DirectQueryCapabilities::current()),
        ))))
        .await
        .unwrap();
    let SecurePayload::Message(message) = channel.receive().await.unwrap() else {
        panic!("expected status request");
    };
    assert!(matches!(*message, DirectMessage::StatusRequest(_)));
    channel
        .send(&DirectMessage::StatusResponse(Unlabeled::from(
            IphoneStatus {
                name: trust.display_name.clone(),
                app_active,
                protected_data_available: app_active,
                export_in_progress: false,
                can_trigger_raw_exports: app_active,
                can_trigger_file_exports: app_active,
                query_in_progress: Some(false),
                can_trigger_queries: Some(app_active),
                active_job_id: None,
                active_query_request_id: None,
                message: None,
            },
        )))
        .await
        .unwrap();
}

async fn pair_fake_android(client: &DirectClient<MemoryCredentials>) -> FakeMobileTrust {
    let (port_sender, port_receiver) = oneshot::channel();
    let pair = client.pair(
        "123456",
        "12345678901234567890",
        0,
        Duration::from_secs(5),
        move |port| port_sender.send(port).unwrap(),
    );
    let peer = async {
        let port = port_receiver.await.unwrap();
        let (mut channel, trust) = connect_fake_mobile(
            port,
            2,
            "Hermetic Android",
            Some("12345678901234567890"),
            None,
        )
        .await;
        let _ = receive_cli_hello(&mut channel).await;
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &trust,
                PeerPlatform::Android,
                vec![2],
                None,
            ))))
            .await
            .unwrap();
        channel
            .send_v2(&v2::Envelope::new(v2::Message::SourceHello(
                android_source_hello(&trust),
            )))
            .await
            .unwrap();
        trust
    };
    let (paired, trust) = tokio::join!(pair, peer);
    paired.unwrap();
    trust
}

async fn respond_with_android_status(port: u16, trust: &FakeMobileTrust, app_active: bool) {
    let (mut channel, reconnect) =
        connect_fake_mobile(port, 2, &trust.display_name, None, Some(trust)).await;
    let _ = receive_cli_hello(&mut channel).await;
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
            &reconnect,
            PeerPlatform::Android,
            vec![2],
            None,
        ))))
        .await
        .unwrap();
    let source_hello = android_source_hello(&reconnect);
    channel
        .send_v2(&v2::Envelope::new(v2::Message::SourceHello(
            source_hello.clone(),
        )))
        .await
        .unwrap();
    let envelope = channel.receive_v2().await.unwrap();
    assert!(matches!(envelope.message, v2::Message::StatusRequest(_)));
    channel
        .send_v2(&v2::Envelope::new(v2::Message::StatusResponse(
            v2::SourceStatus {
                source: source_hello.source,
                app_active,
                protected_data_available: app_active,
                export_in_progress: false,
                available_products: vec![v2::ProductId::AndroidProviderNativeSnapshotV1],
                active_job_id: None,
                message: None,
            },
        )))
        .await
        .unwrap();
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn fake_ios_peer_pairs_shared_v3_then_reconnects_with_v1_for_a_query() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let (port_sender, port_receiver) = oneshot::channel();
    let pair = client.pair(
        "123456",
        "12345678901234567890",
        0,
        Duration::from_secs(5),
        move |port| port_sender.send(port).unwrap(),
    );
    let peer = async {
        let port = port_receiver.await.unwrap();
        let (mut channel, trust) = connect_fake_mobile(
            port,
            3,
            "Hermetic iPhone",
            Some("12345678901234567890"),
            None,
        )
        .await;
        let cli = receive_cli_hello(&mut channel).await;
        assert_eq!(cli.platform, PeerPlatform::Cli);
        assert!(cli.protocol_versions.contains(&1));
        assert!(cli.protocol_versions.contains(&3));
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &trust,
                PeerPlatform::Ios,
                vec![1, 3],
                Some(DirectQueryCapabilities::current()),
            ))))
            .await
            .unwrap();
        trust
    };
    let (paired, trust) = tokio::join!(pair, peer);
    let paired = paired.unwrap();
    assert_eq!(paired.source, SourceKind::Ios);
    assert_eq!(paired.device.installation_id, trust.installation_id);

    let request_id = SwiftUuid(Uuid::new_v4());
    // Query has no listening callback, so reserve a loopback port and let the fake peer retry
    // briefly while the public query method binds it.
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let query_port = probe.local_addr().unwrap().port();
    drop(probe);
    let query = client.query(
        DirectQueryRequest {
            protocol_version: IOS_QUERY_APPLICATION_PROTOCOL_VERSION,
            request_id,
            created_at: Utc::now(),
            detail_level: DirectQueryDetailLevel::Summary,
            query: serde_json::json!({
                "schema": "healthmd.query_request",
                "schema_version": 1,
                "operation": {"type": "coverage"},
                "page": {"max_items": 25, "max_bytes": 65536, "cursor": "opaque-input"}
            }),
        },
        Some(trust.installation_id.0),
        query_port,
        Duration::from_secs(5),
    );
    let peer = async {
        let (mut channel, reconnect) =
            connect_fake_mobile(query_port, 1, &trust.display_name, None, Some(&trust)).await;
        let _ = receive_cli_hello(&mut channel).await;
        let mut query_capabilities = DirectQueryCapabilities::current();
        query_capabilities.maximum_page_items = 10;
        query_capabilities.maximum_page_bytes = 32_768;
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &reconnect,
                PeerPlatform::Ios,
                vec![1, 3],
                Some(query_capabilities),
            ))))
            .await
            .unwrap();
        let SecurePayload::Message(message) = channel.receive().await.unwrap() else {
            panic!("expected query request");
        };
        let DirectMessage::QueryRequest(Unlabeled { value: request }) = *message else {
            panic!("expected query request");
        };
        assert_eq!(request.request_id, request_id);
        assert_eq!(
            request
                .query
                .pointer("/page/max_items")
                .and_then(serde_json::Value::as_u64),
            Some(10)
        );
        assert_eq!(
            request
                .query
                .pointer("/page/max_bytes")
                .and_then(serde_json::Value::as_u64),
            Some(32_768)
        );
        assert_eq!(
            request
                .query
                .pointer("/page/cursor")
                .and_then(serde_json::Value::as_str),
            Some("opaque-input")
        );
        channel
            .send(&DirectMessage::QueryResponse(Unlabeled::from(
                DirectQueryResponse {
                    request_id,
                    response: serde_json::json!({
                        "schema": "healthmd.query_response",
                        "schema_version": 1,
                        "items": [],
                        "coverage": {
                            "status": "complete_empty",
                            "days_considered": 0,
                            "days_with_values": 0,
                            "missing": []
                        },
                        "sources": [],
                        "evidence": [],
                        "next_cursor": "opaque-next",
                        "limitations": []
                    }),
                },
            )))
            .await
            .unwrap();
    };
    let (result, ()) = tokio::join!(query, peer);
    let result = result.unwrap();
    assert_eq!(result.port, query_port);
    assert_eq!(result.response["next_cursor"], "opaque-next");
}

#[tokio::test]
async fn fake_android_peer_pairs_v2_without_downgrading_to_v1() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let (port_sender, port_receiver) = oneshot::channel();
    let pair = client.pair(
        "123456",
        "12345678901234567890",
        0,
        Duration::from_secs(5),
        move |port| port_sender.send(port).unwrap(),
    );
    let peer = async {
        let port = port_receiver.await.unwrap();
        let (mut channel, trust) = connect_fake_mobile(
            port,
            2,
            "Hermetic Android",
            Some("12345678901234567890"),
            None,
        )
        .await;
        let cli = receive_cli_hello(&mut channel).await;
        assert!(cli.protocol_versions.contains(&2));
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &trust,
                PeerPlatform::Android,
                vec![2],
                None,
            ))))
            .await
            .unwrap();
        channel
            .send_v2(&v2::Envelope::new(v2::Message::SourceHello(
                v2::SourceHello {
                    source: v2::SourceIdentity {
                        installation_id: trust.installation_id.0,
                        platform: v2::SourcePlatform::Android,
                        display_name: trust.display_name.clone(),
                        app_version: "test".into(),
                    },
                    products: vec![v2::ProductCapability {
                        product_id: v2::ProductId::AndroidProviderNativeSnapshotV1,
                        artifact_schema: v2::ArtifactSchema {
                            id: "healthmd.android_provider_native_snapshot".into(),
                            major: 1,
                        },
                        formats: vec![v2::ArtifactFormat::Json],
                        providers: vec!["health_connect".into()],
                        settings_policies: Vec::new(),
                        supports_resume: true,
                    }],
                    limits: v2::ProtocolLimits {
                        maximum_control_bytes: 2 * 1_024 * 1_024,
                        maximum_chunk_bytes: 512 * 1_024,
                        preferred_partition_bytes: 48 * 1_024 * 1_024,
                    },
                },
            )))
            .await
            .unwrap();
        trust
    };
    let (paired, trust) = tokio::join!(pair, peer);
    let paired = paired.unwrap();
    assert_eq!(paired.source, SourceKind::Android);
    assert_eq!(paired.device.installation_id, trust.installation_id);
}

async fn respond_with_ios_status_enrolled(
    port: u16,
    trust: &FakeMobileTrust,
    app_active: bool,
    enrollment: Option<&healthmd_protocol::wire::WakeEnrollment>,
) {
    let (mut channel, reconnect) =
        connect_fake_mobile(port, 1, &trust.display_name, None, Some(trust)).await;
    let _ = receive_cli_hello(&mut channel).await;
    let mut capabilities = mobile_capabilities(
        &reconnect,
        PeerPlatform::Ios,
        vec![1, 3],
        Some(DirectQueryCapabilities::current()),
    );
    capabilities.wake =
        enrollment.map(|_| healthmd_protocol::wire::WakeCapabilities { supported: true });
    channel
        .send(&DirectMessage::Hello(Unlabeled::from(capabilities)))
        .await
        .unwrap();
    if let Some(enrollment) = enrollment {
        channel
            .send(&DirectMessage::WakeEnrollment(Unlabeled::from(
                enrollment.clone(),
            )))
            .await
            .unwrap();
    }
    // A rejected (malformed) enrollment makes the CLI close without a status request; only a
    // valid exchange continues to the status round trip.
    match channel.receive().await {
        Ok(SecurePayload::Message(message))
            if matches!(*message, DirectMessage::StatusRequest(_)) => {}
        _ => return,
    }
    channel
        .send(&DirectMessage::StatusResponse(Unlabeled::from(
            IphoneStatus {
                name: trust.display_name.clone(),
                app_active,
                protected_data_available: app_active,
                export_in_progress: false,
                can_trigger_raw_exports: app_active,
                can_trigger_file_exports: app_active,
                query_in_progress: Some(false),
                can_trigger_queries: Some(app_active),
                active_job_id: None,
                active_query_request_id: None,
                message: None,
            },
        )))
        .await
        .unwrap();
}

fn fake_enrollment(wake_id: &str) -> healthmd_protocol::wire::WakeEnrollment {
    healthmd_protocol::wire::WakeEnrollment {
        wake_id: wake_id.to_owned(),
        wake_key: base64::engine::general_purpose::STANDARD.encode([9_u8; 32]),
    }
}

#[tokio::test]
async fn wake_enrollment_round_trips_rotates_and_unpair_removes_it() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let device = trust.installation_id.0;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);

    let first = fake_enrollment("wake-opaque-one");
    let status = client.status(Some(device), port, Duration::from_secs(20));
    let peer = respond_with_ios_status_enrolled(port, &trust, true, Some(&first));
    let (status, ()) = tokio::join!(status, peer);
    assert!(status.is_ok());
    let stored = client
        .wake_credential(device)
        .await
        .unwrap()
        .expect("enrolled");
    assert_eq!(stored.wake_id, "wake-opaque-one");
    assert_eq!(stored.wake_key, vec![9_u8; 32]);

    let second = fake_enrollment("wake-opaque-two");
    let status = client.status(Some(device), port, Duration::from_secs(20));
    let peer = respond_with_ios_status_enrolled(port, &trust, true, Some(&second));
    let (status, ()) = tokio::join!(status, peer);
    assert!(status.is_ok());
    assert_eq!(
        client
            .wake_credential(device)
            .await
            .unwrap()
            .unwrap()
            .wake_id,
        "wake-opaque-two",
        "a later enrollment must rotate the stored material"
    );

    client.unpair(device).await.unwrap();
    assert!(client.wake_credential(device).await.unwrap().is_none());
}

#[tokio::test]
async fn wake_enrollment_without_advertised_support_fails_closed() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let device = trust.installation_id.0;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);

    // The phone does NOT advertise wake, but sends the enrollment anyway: the CLI expects the
    // status response next and must fail closed instead of storing anything.
    let rogue = async {
        let (mut channel, reconnect) =
            connect_fake_mobile(port, 1, &trust.display_name, None, Some(&trust)).await;
        let _ = receive_cli_hello(&mut channel).await;
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &reconnect,
                PeerPlatform::Ios,
                vec![1, 3],
                Some(DirectQueryCapabilities::current()),
            ))))
            .await
            .unwrap();
        channel
            .send(&DirectMessage::WakeEnrollment(Unlabeled::from(
                fake_enrollment("wake-rogue"),
            )))
            .await
            .unwrap();
    };
    let status = client.status(Some(device), port, Duration::from_secs(20));
    let (status, ()) = tokio::join!(status, rogue);
    assert!(matches!(status, Err(ClientError::UnexpectedMessage)));
    assert!(client.wake_credential(device).await.unwrap().is_none());
}

#[tokio::test]
async fn malformed_wake_enrollment_is_rejected_without_persisting() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let device = trust.installation_id.0;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);

    let mut short_key = fake_enrollment("wake-short");
    short_key.wake_key = base64::engine::general_purpose::STANDARD.encode([1_u8; 8]);
    let status = client.status(Some(device), port, Duration::from_secs(20));
    let peer = respond_with_ios_status_enrolled(port, &trust, true, Some(&short_key));
    let (status, ()) = tokio::join!(status, peer);
    assert!(matches!(status, Err(ClientError::UnexpectedMessage)));
    assert!(client.wake_credential(device).await.unwrap().is_none());
}

#[tokio::test]
async fn wake_window_retries_an_inactive_peer_until_it_is_active() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let cancellation = tokio_util::sync::CancellationToken::new();
    let mut progress = Vec::new();
    let wait = client.wait_for_active_source(
        Some(trust.installation_id.0),
        port,
        WakeWindow::from_seconds(3),
        false,
        &cancellation,
        |update| progress.push(update),
    );
    let peer = async {
        respond_with_ios_status(port, &trust, false).await;
        respond_with_ios_status(port, &trust, true).await;
    };
    let (result, ()) = tokio::join!(wait, peer);
    result.unwrap();
    assert_eq!(progress.len(), 1);
    assert_eq!(progress[0].timeout_seconds, 3);
    assert!(!progress[0].message.contains("health"));
}

#[tokio::test]
async fn wake_window_retries_an_inactive_android_peer_until_it_is_active() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_android(&client).await;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let cancellation = tokio_util::sync::CancellationToken::new();
    let mut progress = Vec::new();
    let wait = client.wait_for_active_source(
        Some(trust.installation_id.0),
        port,
        WakeWindow::from_seconds(3),
        false,
        &cancellation,
        |update| progress.push(update),
    );
    let peer = async {
        respond_with_android_status(port, &trust, false).await;
        respond_with_android_status(port, &trust, true).await;
    };
    let (result, ()) = tokio::join!(wait, peer);
    result.unwrap();
    assert_eq!(progress.len(), 1);
    assert!(progress[0].message.contains("Android"));
}

#[tokio::test]
async fn wake_window_retries_an_unreachable_peer_until_it_is_active() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let cancellation = tokio_util::sync::CancellationToken::new();
    let mut progress = Vec::new();
    let started = std::time::Instant::now();
    let wait = client.wait_for_active_source(
        Some(trust.installation_id.0),
        port,
        WakeWindow::from_seconds(3),
        false,
        &cancellation,
        |update| progress.push(update),
    );
    let peer = async {
        tokio::time::sleep(Duration::from_millis(400)).await;
        respond_with_ios_status(port, &trust, true).await;
    };
    let (result, ()) = tokio::join!(wait, peer);
    result.unwrap();
    assert!(started.elapsed() >= Duration::from_millis(250));
    assert_eq!(progress.len(), 1);
    assert_eq!(progress[0].elapsed_seconds, 0);
}

#[tokio::test]
async fn wake_window_expiry_is_bounded_when_the_peer_is_unreachable() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let started = std::time::Instant::now();
    let result = client
        .wait_for_active_source(
            Some(trust.installation_id.0),
            port,
            WakeWindow::from_seconds(1),
            false,
            &tokio_util::sync::CancellationToken::new(),
            |_| {},
        )
        .await;
    assert!(matches!(result, Err(ClientError::TimedOut)));
    assert!(started.elapsed() < Duration::from_secs(2));
}

#[tokio::test]
async fn wake_window_deadline_covers_authenticated_status_exchange() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let wait = async {
        let started = std::time::Instant::now();
        let result = client
            .wait_for_active_source(
                Some(trust.installation_id.0),
                port,
                WakeWindow::from_seconds(1),
                false,
                &tokio_util::sync::CancellationToken::new(),
                |_| {},
            )
            .await;
        (result, started.elapsed())
    };
    let peer = async {
        let (mut channel, _) =
            connect_fake_mobile(port, 1, &trust.display_name, None, Some(&trust)).await;
        let _ = receive_cli_hello(&mut channel).await;
        tokio::time::sleep(Duration::from_millis(1_500)).await;
    };
    let ((result, elapsed), ()) = tokio::join!(wait, peer);
    assert!(matches!(result, Err(ClientError::TimedOut)));
    assert!(elapsed < Duration::from_millis(1_400));
}

#[tokio::test]
async fn wake_window_cancellation_is_not_phone_side_cancellation() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let trust = pair_fake_ios(&client).await;
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let cancellation = tokio_util::sync::CancellationToken::new();
    let cancel = cancellation.clone();
    let trigger = tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(50)).await;
        cancel.cancel();
    });
    let result = client
        .wait_for_active_source(
            Some(trust.installation_id.0),
            port,
            WakeWindow::from_seconds(3),
            false,
            &cancellation,
            |_| {},
        )
        .await;
    trigger.await.unwrap();
    assert!(matches!(result, Err(ClientError::WaitCancelled)));
}

#[tokio::test]
async fn disabled_wake_window_performs_no_network_preflight() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let result = client
        .wait_for_active_source(
            None,
            0,
            WakeWindow::from_seconds(0),
            false,
            &tokio_util::sync::CancellationToken::new(),
            |_| panic!("disabled wake must not report progress"),
        )
        .await;
    result.unwrap();
}

#[test]
fn explicit_cancellation_is_durable_before_the_wake_listener_opens() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let source_id = Uuid::new_v4();
    let request = ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(Uuid::new_v4()),
        created_at: Utc::now(),
        date_selection: DateSelection::AllAvailable(Empty {}),
        settings_policy: SettingsPolicy::RequestedDatesOnly,
        profile_reference: None,
        response_mode: healthmd_protocol::models::ResponseMode::RawJson,
        raw_profile: Some(RawProfile::CanonicalSourceRecordsV1),
        canonical_selection: None,
        destination: None,
    };
    let mut record = JobRecord::new(request);
    record.peer_binding = Some(PeerBinding {
        source_installation_id: SwiftUuid(source_id),
        destination_installation_id: client.identity.installation_id,
    });
    let job_id = record.request.job_id.0;
    let jobs = JobStore::new(client.layout.clone()).unwrap();
    jobs.save(&record).unwrap();

    let wrong_device = Uuid::new_v4();
    assert!(matches!(
        client.request_job_cancellation(job_id, Some(wrong_device)),
        Err(ClientError::DeviceNotPaired(id)) if id == wrong_device
    ));
    assert!(!jobs.cancellation_requested(job_id));

    client
        .request_job_cancellation(job_id, Some(source_id))
        .unwrap();
    assert!(jobs.cancellation_requested(job_id));
    assert_eq!(
        client.job_record(job_id).unwrap().state,
        JobState::CancellationPending
    );
}

#[test]
fn explicit_android_cancellation_is_durable_before_the_wake_listener_opens() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let created_at = Utc::now();
    let source_id = Uuid::new_v4();
    let request = v2::ExportRequest {
        job_id: Uuid::new_v4(),
        created_at,
        expires_at: created_at + chrono::Duration::seconds(JOB_LIFETIME_SECONDS),
        source_installation_id: source_id,
        date_selection: v2::DateSelection::Exact {
            start_date: "2026-07-01".into(),
            end_date: "2026-07-01".into(),
        },
        product: v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
            provider_id: "health_connect".into(),
            format: v2::RawSnapshotFormat::Json,
            scope: v2::RawSnapshotScope::AllAuthorizedSupportedData,
            include_exercise_routes: false,
        },
        destination: None,
    };
    let job_id = request.job_id;
    let jobs = V2JobStore::new(client.layout.clone()).unwrap();
    jobs.save(&V2JobRecord::new(request, None)).unwrap();

    client
        .request_android_job_cancellation(job_id, Some(source_id))
        .unwrap();
    assert!(jobs.cancellation_requested(job_id));
    assert_eq!(
        client.v2_job_record(job_id).unwrap().state,
        JobState::CancellationPending
    );
}

#[tokio::test]
async fn ios_only_pairing_rejects_android_and_removes_new_trust() {
    let temporary = TempDir::new().unwrap();
    let client = test_client(&temporary);
    let (port_sender, port_receiver) = oneshot::channel();
    let pair = client.pair_ios(
        "123456",
        "12345678901234567890",
        0,
        Duration::from_secs(5),
        move |port| port_sender.send(port).unwrap(),
    );
    let peer = async {
        let port = port_receiver.await.unwrap();
        let (mut channel, trust) = connect_fake_mobile(
            port,
            2,
            "Unexpected Android",
            Some("12345678901234567890"),
            None,
        )
        .await;
        let _ = receive_cli_hello(&mut channel).await;
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(mobile_capabilities(
                &trust,
                PeerPlatform::Android,
                vec![2],
                None,
            ))))
            .await
            .unwrap();
    };
    let (result, ()) = tokio::join!(pair, peer);
    assert!(matches!(result, Err(ClientError::Authentication(_))));
    assert!(client.paired_devices().await.unwrap().is_empty());
}
