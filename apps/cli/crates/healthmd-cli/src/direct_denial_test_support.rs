//! Hermetic encrypted protocol-v2 denial journey shared by CLI and MCP adapter tests.
use std::{
    collections::{BTreeMap, HashMap},
    sync::{Arc, Mutex},
    time::Duration,
};

use async_trait::async_trait;
use chrono::{Timelike as _, Utc};
use healthmd_client::{
    ClientError,
    credentials::CredentialStore,
    direct::DirectClient,
    job::JobState,
    packet::PacketConnection,
    secure_channel::{SecureChannel, SecurePayload},
    storage::StorageLayout,
    trust::{TrustState, TrustStore, TrustedClient},
};
use healthmd_protocol::{
    crypto,
    encoding::SwiftUuid,
    v2,
    wire::{DirectMessage, PairingRequest, PeerCapabilities, PeerPlatform, SyncPacket, Unlabeled},
};
use secrecy::SecretString;
use uuid::Uuid;

#[derive(Clone, Default)]
struct MemoryCredentials(Arc<Mutex<HashMap<String, SecretString>>>);

#[async_trait]
impl CredentialStore for MemoryCredentials {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        Ok(self.0.lock().unwrap().get(account).cloned())
    }
    async fn set(&self, account: &str, value: SecretString) -> Result<(), ClientError> {
        self.0.lock().unwrap().insert(account.into(), value);
        Ok(())
    }
    async fn delete(&self, account: &str) -> Result<(), ClientError> {
        self.0.lock().unwrap().remove(account);
        Ok(())
    }
}

#[allow(clippy::too_many_lines)]
pub(crate) async fn encrypted_denial(malformed: bool) -> (ClientError, Uuid) {
    let temporary = tempfile::tempdir().unwrap();
    let credentials = MemoryCredentials::default();
    let client = DirectClient::with_credentials(
        StorageLayout {
            root: temporary.path().join("state"),
        },
        credentials.clone(),
    )
    .unwrap();
    let source_id = Uuid::new_v4();
    let secret = crypto::random_bytes::<32>().unwrap();
    let now = Utc::now().with_nanosecond(0).unwrap();
    let mut trust = TrustState::empty(client.identity.installation_id);
    trust
        .save_client(TrustedClient {
            installation_id: SwiftUuid(source_id),
            display_name: "Synthetic Android".into(),
            platform: Some(PeerPlatform::Android),
            reconnect_secret: secret.to_vec(),
            paired_at: now,
            last_connected_at: now,
            wake: None,
        })
        .unwrap();
    TrustStore::new(credentials).save(&trust).await.unwrap();
    let destination = temporary.path().join("destination");
    std::fs::create_dir(&destination).unwrap();
    let request = v2::ExportRequest {
        job_id: Uuid::new_v4(),
        created_at: now,
        expires_at: now + chrono::Duration::days(7),
        source_installation_id: source_id,
        date_selection: v2::DateSelection::Exact {
            start_date: "2026-07-01".into(),
            end_date: "2026-07-01".into(),
        },
        product: v2::ExportProduct::GeneratedFilesV1 {
            settings_policy: v2::SettingsPolicy::RequestedScope,
            profile_reference: None,
        },
        destination: Some(v2::DestinationBinding {
            binding_sha256: "a".repeat(64),
            display_name: "destination".into(),
        }),
    };
    let probe = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let port = probe.local_addr().unwrap().port();
    drop(probe);
    let export = client.export_android(
        request.clone(),
        Some(destination.clone()),
        Some(source_id),
        port,
        Duration::from_secs(5),
    );
    let peer = async {
        let stream = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let Ok(stream) = tokio::net::TcpStream::connect(("127.0.0.1", port)).await {
                    break stream;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        let mut packet = PacketConnection::new(stream);
        let (private, public) = crypto::ephemeral_key_pair().unwrap();
        let nonce = crypto::random_bytes::<32>().unwrap();
        packet
            .send(&SyncPacket::PairingRequest(Unlabeled::from(
                PairingRequest {
                    protocol_version: 2,
                    device_name: "Synthetic Android".into(),
                    client_public_key: public.to_vec(),
                    client_nonce: nonce.to_vec(),
                    code_verifier: vec![],
                    client_installation_id: Some(SwiftUuid(source_id)),
                    trusted_verifier: Some(
                        crypto::trusted_client_verifier(&secret, source_id, &public, &nonce)
                            .to_vec(),
                    ),
                },
            )))
            .await
            .unwrap();
        let SyncPacket::PairingResponse(Unlabeled { value: response }) =
            packet.receive().await.unwrap()
        else {
            panic!("expected authenticated reconnect response");
        };
        let shared = crypto::x25519_shared_secret(&private, &response.server_public_key).unwrap();
        let key = crypto::session_key(&shared, &nonce, &response.server_nonce);
        let mut channel = SecureChannel::new(
            packet,
            key,
            response.mac_installation_id.unwrap().0,
            response.mac_name,
        );
        channel
            .send(&DirectMessage::Hello(Unlabeled::from(PeerCapabilities {
                protocol_versions: vec![2],
                platform: PeerPlatform::Android,
                installation_id: SwiftUuid(source_id),
                supported_raw_profiles: vec![],
                supports_durable_jobs: true,
                supports_canonical_extraction: false,
                transfer: Default::default(),
                query: None,
                wake: None,
                export_history_observation_versions: None,
                scoped_daily_note_versions: None,
            })))
            .await
            .unwrap();
        assert!(matches!(
            channel.receive().await.unwrap(),
            SecurePayload::Message(_)
        ));
        channel
            .send_v2(&v2::Envelope::new(v2::Message::SourceHello(
                v2::SourceHello {
                    source: v2::SourceIdentity {
                        installation_id: source_id,
                        platform: v2::SourcePlatform::Android,
                        display_name: "Synthetic Android".into(),
                        app_version: "test".into(),
                    },
                    products: vec![v2::ProductCapability {
                        product_id: v2::ProductId::GeneratedFilesV1,
                        artifact_schema: v2::ArtifactSchema {
                            id: "healthmd.generated_files".into(),
                            major: 1,
                        },
                        formats: vec![v2::ArtifactFormat::Markdown],
                        providers: vec![],
                        settings_policies: vec![v2::SettingsPolicy::RequestedScope],
                        supports_resume: true,
                    }],
                    limits: v2::ProtocolLimits {
                        maximum_control_bytes: 2 * 1024 * 1024,
                        maximum_chunk_bytes: 512 * 1024,
                        preferred_partition_bytes: 48 * 1024 * 1024,
                    },
                },
            )))
            .await
            .unwrap();
        assert_eq!(
            channel.receive_v2().await.unwrap().message,
            v2::Message::ExportRequest(request.clone())
        );
        channel
            .send_v2(&v2::Envelope::new(v2::Message::ExportRejected(
                v2::ExportFailure {
                    job_id: Some(request.job_id),
                    code: v2::ErrorCode::QuotaExhausted,
                    phase: v2::ExportPhase::Preparing,
                    retryable: false,
                    public_message: if malformed {
                        "invalid\nmessage".into()
                    } else {
                        "synthetic-private-message".into()
                    },
                    details: BTreeMap::from([(
                        "private".into(),
                        vec!["synthetic-private-detail".into()],
                    )]),
                },
            )))
            .await
            .unwrap();
    };
    let (result, ()) = tokio::join!(export, peer);
    let error = result.unwrap_err();
    let record = client.v2_job_record(request.job_id).unwrap();
    assert_eq!(record.committed_bytes, 0);
    assert_eq!(record.committed_partitions, 0);
    assert_eq!(std::fs::read_dir(destination).unwrap().count(), 0);
    assert!(!error.to_string().contains("synthetic-private"));
    if malformed {
        assert!(matches!(error, ClientError::InvalidTransfer(_)));
        assert_eq!(record.state, JobState::Paused);
        assert!(record.failure.is_none());
    } else {
        assert!(matches!(error, ClientError::ExportRejected(_)));
        assert_eq!(record.state, JobState::Failed);
        let failure = record.failure.unwrap();
        assert_eq!(failure.code, v2::ErrorCode::QuotaExhausted);
        assert_eq!(failure.phase, v2::ExportPhase::Preparing);
        assert!(!failure.retryable);
        assert!(failure.details.is_empty());
        assert!(!failure.public_message.contains("synthetic-private"));
        assert!(matches!(
            client
                .resume_android(
                    request.job_id,
                    Some(source_id),
                    port,
                    Duration::from_secs(1)
                )
                .await,
            Err(ClientError::JobNotResumable(_, _))
        ));
    }
    (error, request.job_id)
}
