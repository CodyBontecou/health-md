use std::{collections::HashMap, sync::Mutex, time::Duration};

use async_trait::async_trait;
use chrono::Timelike as _;
use healthmd_client::{
    ClientError,
    credentials::CredentialStore,
    handshake::{AuthenticatedConnection, authenticate},
    packet::PacketConnection,
    secure_channel::{SecurePayload, V2SecurePayload},
    storage::StorageLayout,
    trust::TrustStore,
    v2_job::{V2JobRecord, V2JobStore},
    v2_receiver::V2ArtifactReceiver,
};
use healthmd_protocol::{
    encoding::SwiftUuid,
    v2,
    wire::{DirectMessage, PeerCapabilities, PeerPlatform, Unlabeled},
};
use secrecy::{ExposeSecret as _, SecretString};
use tempfile::TempDir;
use tokio::net::TcpListener;
use uuid::Uuid;

#[derive(Clone, Default)]
struct MemoryCredentials(std::sync::Arc<Mutex<HashMap<String, String>>>);

#[async_trait]
impl CredentialStore for MemoryCredentials {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        Ok(self
            .0
            .lock()
            .unwrap()
            .get(account)
            .cloned()
            .map(SecretString::from))
    }

    async fn set(&self, account: &str, value: SecretString) -> Result<(), ClientError> {
        self.0
            .lock()
            .unwrap()
            .insert(account.into(), value.expose_secret().to_owned());
        Ok(())
    }

    async fn delete(&self, account: &str) -> Result<(), ClientError> {
        self.0.lock().unwrap().remove(account);
        Ok(())
    }
}

/// Manual cross-language gate. Run this ignored listener in the background, then run the Android
/// `LiveCliInteropTest` with matching `HEALTHMD_LIVE_DIRECT_PORT` and pairing code variables.
#[tokio::test]
#[ignore = "requires the Kotlin live interoperability test"]
#[allow(clippy::too_many_lines)]
async fn accepts_android_pairing_and_v2_negotiation() {
    let port = std::env::var("HEALTHMD_LIVE_DIRECT_PORT")
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(18_647);
    let pairing_code = std::env::var("HEALTHMD_LIVE_PAIRING_CODE")
        .unwrap_or_else(|_| "12345678901234567890".into());
    let listener = TcpListener::bind(("127.0.0.1", port)).await.unwrap();
    eprintln!("ANDROID_LIVE_LISTENER_READY:{port}");
    let (stream, _) = listener.accept().await.unwrap();
    let server_id = SwiftUuid(Uuid::parse_str("01234567-89ab-4cde-8fab-0123456789ab").unwrap());
    let store = TrustStore::new(MemoryCredentials::default());
    let mut connection = authenticate(
        PacketConnection::new(stream),
        server_id,
        "Rust live-test CLI",
        Some(("123456", &pairing_code)),
        &store,
        Duration::from_secs(30),
    )
    .await
    .unwrap();

    connection
        .channel
        .send(&DirectMessage::Hello(Unlabeled::from(
            PeerCapabilities::portable_cli_all_versions(server_id),
        )))
        .await
        .unwrap();
    let SecurePayload::Message(message) = connection.channel.receive().await.unwrap() else {
        panic!("expected Android negotiation hello");
    };
    let DirectMessage::Hello(Unlabeled { value: hello }) = *message else {
        panic!("expected Android negotiation hello");
    };
    assert_eq!(hello.platform, PeerPlatform::Android);
    assert_eq!(hello.protocol_versions, vec![2]);
    assert_eq!(hello.installation_id.0, connection.device.installation_id.0);

    let envelope = connection.channel.receive_v2().await.unwrap();
    let v2::Message::SourceHello(source) = envelope.message else {
        panic!("expected Android source capabilities");
    };
    assert_eq!(source.source.platform, v2::SourcePlatform::Android);
    assert_eq!(
        source.source.installation_id,
        connection.device.installation_id.0
    );
    assert!(
        source
            .products
            .iter()
            .any(|product| product.product_id == v2::ProductId::AndroidProviderNativeSnapshotV1)
    );

    connection
        .channel
        .send_v2(&v2::Envelope::new(v2::Message::StatusRequest(
            v2::StatusRequest {
                requested_at: chrono::Utc::now(),
            },
        )))
        .await
        .unwrap();
    let response = connection.channel.receive_v2().await.unwrap();
    let v2::Message::StatusResponse(status) = response.message else {
        panic!("expected Android status response");
    };
    assert_eq!(
        status.source.installation_id,
        connection.device.installation_id.0
    );
    assert!(
        status
            .available_products
            .contains(&v2::ProductId::AndroidProviderNativeSnapshotV1)
    );

    let now = chrono::Utc::now()
        .with_nanosecond(0)
        .expect("zero nanoseconds are valid");
    let request = v2::ExportRequest {
        job_id: Uuid::new_v4(),
        created_at: now,
        expires_at: now + chrono::Duration::days(7),
        source_installation_id: connection.device.installation_id.0,
        date_selection: v2::DateSelection::Exact {
            start_date: "2026-07-23".into(),
            end_date: "2026-07-23".into(),
        },
        product: v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
            provider_id: "health_connect".into(),
            format: v2::RawSnapshotFormat::Json,
            scope: v2::RawSnapshotScope::AllAuthorizedSupportedData,
            include_exercise_routes: false,
        },
        destination: None,
    };
    let temporary = TempDir::new().unwrap();
    let layout = StorageLayout {
        root: temporary.path().join("state"),
    };
    let jobs = V2JobStore::new(layout.clone()).unwrap();
    jobs.save(&V2JobRecord::new(request.clone(), None)).unwrap();
    let mut receiver = V2ArtifactReceiver::new(layout, jobs);
    connection
        .channel
        .send_v2(&v2::Envelope::new(v2::Message::ExportRequest(
            request.clone(),
        )))
        .await
        .unwrap();

    let mut accepted = None;
    loop {
        match connection.channel.receive_v2_payload().await.unwrap() {
            V2SecurePayload::BinaryTransferFrame(frame) => {
                let acknowledgement = receiver.receive_binary_frame(&frame).unwrap();
                connection
                    .channel
                    .send_v2(&v2::Envelope::new(
                        v2::Message::TransferChunkAcknowledgement(acknowledgement),
                    ))
                    .await
                    .unwrap();
            }
            V2SecurePayload::Message(envelope) => match envelope.message {
                v2::Message::ExportAccepted(value) => accepted = Some(value),
                v2::Message::TransferSession(session) => receiver
                    .prepare(request.clone(), accepted.clone().unwrap(), session)
                    .unwrap(),
                v2::Message::ArtifactManifest(manifest) => {
                    receiver.store_manifest(manifest).unwrap();
                }
                v2::Message::TransferOpen(open) => {
                    let disposition = receiver.disposition(open).unwrap();
                    connection
                        .channel
                        .send_v2(&v2::Envelope::new(v2::Message::TransferDisposition(
                            disposition,
                        )))
                        .await
                        .unwrap();
                }
                v2::Message::TransferPartitionComplete(complete) => {
                    let acknowledgement = receiver.commit_partition(&complete).unwrap();
                    connection
                        .channel
                        .send_v2(&v2::Envelope::new(
                            v2::Message::TransferPartitionAcknowledgement(acknowledgement),
                        ))
                        .await
                        .unwrap();
                }
                v2::Message::TransferFinalize(finalize) => {
                    let acknowledgement = receiver.finalize(&finalize).unwrap();
                    connection
                        .channel
                        .send_v2(&v2::Envelope::new(
                            v2::Message::TransferFinalAcknowledgement(acknowledgement),
                        ))
                        .await
                        .unwrap();
                }
                v2::Message::CompletionConfirmed(payload) => {
                    receiver.acknowledge_completion(payload.job_id).unwrap();
                    let receipt = receiver.receipt(payload.job_id).unwrap();
                    assert_eq!(receipt.status, "success");
                    assert!(receipt.byte_count > 0);
                    break;
                }
                other => panic!("unexpected Android transfer message: {other:?}"),
            },
        }
    }
}

async fn accept_ui_connection(
    listener: &TcpListener,
    server_id: &SwiftUuid,
    trust_store: &TrustStore<MemoryCredentials>,
    pairing_codes: Option<(&str, &str)>,
) -> Result<AuthenticatedConnection, ClientError> {
    let stream = loop {
        let (stream, _) = tokio::time::timeout(Duration::from_secs(60), listener.accept())
            .await
            .map_err(|_| ClientError::TimedOut)?
            .map_err(|error| ClientError::Connection(error.to_string()))?;
        let mut prefix = [0_u8; 8];
        let is_http_probe = matches!(
            tokio::time::timeout(Duration::from_secs(5), stream.peek(&mut prefix)).await,
            Ok(Ok(count)) if count >= 4
                && matches!(&prefix[..4], b"GET " | b"HEAD" | b"POST" | b"PUT ")
        );
        if is_http_probe {
            eprintln!("ANDROID_UI_E2E_NON_PROTOCOL_PROBE_IGNORED");
            continue;
        }
        break stream;
    };
    authenticate(
        PacketConnection::new(stream),
        *server_id,
        "Rust Android UI E2E CLI",
        pairing_codes,
        trust_store,
        Duration::from_secs(30),
    )
    .await
}

async fn negotiate_ui_connection(
    connection: &mut AuthenticatedConnection,
    server_id: &SwiftUuid,
) -> v2::SourceHello {
    connection
        .channel
        .send(&DirectMessage::Hello(Unlabeled::from(
            PeerCapabilities::portable_cli_all_versions(*server_id),
        )))
        .await
        .unwrap();
    let SecurePayload::Message(message) = connection.channel.receive().await.unwrap() else {
        panic!("expected Android negotiation hello");
    };
    let DirectMessage::Hello(Unlabeled { value: hello }) = *message else {
        panic!("expected Android negotiation hello");
    };
    assert_eq!(hello.platform, PeerPlatform::Android);
    assert_eq!(hello.protocol_versions, vec![2]);
    assert_eq!(hello.installation_id.0, connection.device.installation_id.0);

    let envelope = connection.channel.receive_v2().await.unwrap();
    let v2::Message::SourceHello(source) = envelope.message else {
        panic!("expected Android source capabilities");
    };
    assert_eq!(source.source.platform, v2::SourcePlatform::Android);
    assert_eq!(
        source.source.installation_id,
        connection.device.installation_id.0
    );
    assert!(
        source
            .products
            .iter()
            .any(|product| product.product_id == v2::ProductId::AndroidProviderNativeSnapshotV1)
    );
    source
}

/// Physical/emulator app gate. The Android instrumentation test drives Settings -> Direct CLI,
/// while this listener verifies wrong-code rejection, pairing, reconnect, disconnect, status,
/// forget, and code-based re-pair without requesting or retaining health payloads.
#[tokio::test]
#[ignore = "requires the Android Direct CLI UI instrumentation test"]
async fn accepts_android_ui_pair_reconnect_disconnect_status_and_repair() {
    let bind_address =
        std::env::var("HEALTHMD_ANDROID_UI_E2E_BIND").unwrap_or_else(|_| "127.0.0.1".into());
    let port = std::env::var("HEALTHMD_ANDROID_UI_E2E_PORT")
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(18_648);
    let pairing_code = std::env::var("HEALTHMD_ANDROID_UI_E2E_PAIRING_CODE")
        .unwrap_or_else(|_| "12345678901234567890".into());
    assert_eq!(pairing_code.len(), 20);
    assert!(pairing_code.bytes().all(|byte| byte.is_ascii_digit()));

    let listener = TcpListener::bind((bind_address.as_str(), port))
        .await
        .unwrap();
    eprintln!("ANDROID_UI_E2E_LISTENER_READY:{port}");

    let server_id = SwiftUuid(Uuid::parse_str("11234567-89ab-4cde-8fab-0123456789ab").unwrap());
    let store = TrustStore::new(MemoryCredentials::default());

    let wrong_leading_digit = if pairing_code.as_bytes()[0] == b'0' {
        '1'
    } else {
        '0'
    };
    let wrong_code = format!("{wrong_leading_digit}{}", &pairing_code[1..]);
    let rejected = accept_ui_connection(
        &listener,
        &server_id,
        &store,
        Some(("123456", &pairing_code)),
    )
    .await;
    match rejected {
        Err(ClientError::Authentication(_)) => {
            assert_ne!(wrong_code, pairing_code);
            eprintln!("ANDROID_UI_E2E_WRONG_CODE_REJECTED");
        }
        Ok(_) => panic!("wrong pairing code was unexpectedly accepted"),
        Err(error) => panic!("expected wrong-code authentication rejection, got {error:?}"),
    }

    let mut paired = accept_ui_connection(
        &listener,
        &server_id,
        &store,
        Some(("123456", &pairing_code)),
    )
    .await
    .unwrap();
    assert!(paired.was_new_pairing);
    let first_device_id = paired.device.installation_id;
    negotiate_ui_connection(&mut paired, &server_id).await;
    drop(paired);
    eprintln!("ANDROID_UI_E2E_PAIRED");

    let mut disconnect = accept_ui_connection(&listener, &server_id, &store, None)
        .await
        .unwrap();
    assert!(!disconnect.was_new_pairing);
    assert_eq!(disconnect.device.installation_id, first_device_id);
    negotiate_ui_connection(&mut disconnect, &server_id).await;
    eprintln!("ANDROID_UI_E2E_DISCONNECT_READY");
    let closed = tokio::time::timeout(Duration::from_secs(60), disconnect.channel.receive_v2())
        .await
        .expect("Android did not disconnect within the bounded UI test window");
    assert!(closed.is_err());
    eprintln!("ANDROID_UI_E2E_DISCONNECTED");

    let mut status = accept_ui_connection(&listener, &server_id, &store, None)
        .await
        .unwrap();
    assert!(!status.was_new_pairing);
    assert_eq!(status.device.installation_id, first_device_id);
    negotiate_ui_connection(&mut status, &server_id).await;
    status
        .channel
        .send_v2(&v2::Envelope::new(v2::Message::StatusRequest(
            v2::StatusRequest {
                requested_at: chrono::Utc::now(),
            },
        )))
        .await
        .unwrap();
    let response = status.channel.receive_v2().await.unwrap();
    let v2::Message::StatusResponse(source_status) = response.message else {
        panic!("expected Android status response");
    };
    assert_eq!(source_status.source.installation_id, first_device_id.0);
    assert!(source_status.app_active);
    drop(status);
    eprintln!("ANDROID_UI_E2E_STATUS_COMPLETE");

    let mut repaired = accept_ui_connection(
        &listener,
        &server_id,
        &store,
        Some(("123456", &pairing_code)),
    )
    .await
    .unwrap();
    assert!(repaired.was_new_pairing);
    assert_eq!(repaired.device.installation_id, first_device_id);
    negotiate_ui_connection(&mut repaired, &server_id).await;
    eprintln!("ANDROID_UI_E2E_COMPLETE");
}
