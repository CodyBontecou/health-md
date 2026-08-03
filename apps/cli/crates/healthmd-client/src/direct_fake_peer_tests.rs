use std::{collections::HashMap, sync::Mutex, time::Duration};

use async_trait::async_trait;
use healthmd_protocol::{
    crypto, v2,
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
    let code_verifier = pairing_code.map_or_else(Vec::new, |code| {
        if protocol_version == 2 {
            crypto::android_pairing_verifier(code, installation_id.0, &public_key, &nonce).to_vec()
        } else {
            crypto::pairing_verifier(code, installation_id.0, &public_key, &nonce).to_vec()
        }
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
    }
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn fake_ios_peer_pairs_v1_then_serves_a_v3_query_page() {
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
        let (mut channel, trust) =
            connect_fake_mobile(port, 1, "Hermetic iPhone", Some("123456"), None).await;
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
