use chrono::Utc;
use healthmd_protocol::{
    crypto,
    encoding::SwiftUuid,
    wire::{PairingRejected, PairingResponse, SyncPacket, Unlabeled},
};

use crate::{
    ClientError,
    credentials::CredentialStore,
    packet::PacketConnection,
    secure_channel::SecureChannel,
    trust::{TrustStore, TrustedClient},
};

pub struct AuthenticatedConnection {
    pub channel: SecureChannel,
    pub device: TrustedClient,
    pub was_new_pairing: bool,
    pub pairing_protocol_version: i32,
}

/// Authenticate one mobile-initiated direct connection and persist trust before responding.
///
/// # Errors
///
/// Returns an error for incompatible/malformed handshakes, invalid credentials, unavailable
/// secure storage, cryptographic failure, or TCP failure.
pub async fn authenticate<C: CredentialStore>(
    mut packet: PacketConnection,
    owner_installation_id: SwiftUuid,
    server_display_name: &str,
    pairing_codes: Option<(&str, &str)>,
    trust_store: &TrustStore<C>,
) -> Result<AuthenticatedConnection, ClientError> {
    let result = authenticate_inner(
        &mut packet,
        owner_installation_id,
        server_display_name,
        pairing_codes,
        trust_store,
    )
    .await;

    match result {
        Ok((session_key, device, was_new_pairing, pairing_protocol_version)) => {
            Ok(AuthenticatedConnection {
                channel: SecureChannel::new(
                    packet,
                    session_key,
                    device.installation_id.0,
                    device.display_name.clone(),
                ),
                device,
                was_new_pairing,
                pairing_protocol_version,
            })
        }
        Err(error) => {
            let rejection = SyncPacket::PairingRejected(Unlabeled::from(PairingRejected {
                reason: error.to_string(),
            }));
            let _ = packet.send(&rejection).await;
            Err(error)
        }
    }
}

#[allow(clippy::too_many_lines)]
async fn authenticate_inner<C: CredentialStore>(
    packet: &mut PacketConnection,
    owner_installation_id: SwiftUuid,
    server_display_name: &str,
    pairing_codes: Option<(&str, &str)>,
    trust_store: &TrustStore<C>,
) -> Result<([u8; 32], TrustedClient, bool, i32), ClientError> {
    let SyncPacket::PairingRequest(Unlabeled { value: request }) = packet.receive().await? else {
        return Err(authentication_error("expected a pairing request"));
    };
    if !matches!(request.protocol_version, 1 | 2) {
        return Err(authentication_error(
            "incompatible pairing protocol version",
        ));
    }
    let client_id = request
        .client_installation_id
        .ok_or_else(|| authentication_error("missing mobile installation ID"))?;
    if request.client_public_key.len() != 32 || request.client_nonce.len() != 32 {
        return Err(authentication_error("invalid mobile key material"));
    }

    let mut state = trust_store.load(owner_installation_id).await?;
    let existing = state.client(client_id.0).cloned();
    let trusted_reconnect = existing.as_ref().is_some_and(|saved| {
        request.trusted_verifier.as_ref().is_some_and(|verifier| {
            crypto::constant_time_equal(
                verifier,
                &crypto::trusted_client_verifier(
                    &saved.reconnect_secret,
                    client_id.0,
                    &request.client_public_key,
                    &request.client_nonce,
                ),
            )
        })
    });

    let normalized_code = pairing_codes.map(|(ios, android)| {
        if request.protocol_version == 2 {
            normalize_pairing_code(android)
        } else {
            normalize_pairing_code(ios)
        }
    });
    let required_code_length = if request.protocol_version == 2 { 20 } else { 6 };
    let code_pairing = normalized_code.as_ref().is_some_and(|code| {
        code.len() == required_code_length
            && request.code_verifier.len() == 32
            && crypto::constant_time_equal(
                &request.code_verifier,
                &if request.protocol_version == 2 {
                    crypto::android_pairing_verifier(
                        code,
                        client_id.0,
                        &request.client_public_key,
                        &request.client_nonce,
                    )
                } else {
                    crypto::pairing_verifier(
                        code,
                        client_id.0,
                        &request.client_public_key,
                        &request.client_nonce,
                    )
                },
            )
    });

    let reconnect_secret = if trusted_reconnect {
        existing
            .as_ref()
            .expect("trusted reconnect has an existing record")
            .reconnect_secret
            .clone()
    } else if code_pairing {
        crypto::random_bytes::<32>().map_err(crypto_error)?.to_vec()
    } else {
        return Err(authentication_error(
            "the pairing code or saved credential is invalid",
        ));
    };

    let (private_key, server_public_key) = crypto::ephemeral_key_pair().map_err(crypto_error)?;
    let server_nonce = crypto::random_bytes::<32>().map_err(crypto_error)?;
    let shared_secret = crypto::x25519_shared_secret(&private_key, &request.client_public_key)
        .map_err(crypto_error)?;
    let session_key = crypto::session_key(&shared_secret, &request.client_nonce, &server_nonce);
    let sealed_reconnect_secret =
        crypto::seal(&reconnect_secret, &session_key).map_err(crypto_error)?;

    let verifier = if trusted_reconnect {
        crypto::trusted_server_verifier(
            &reconnect_secret,
            client_id.0,
            &request.client_public_key,
            &request.client_nonce,
            owner_installation_id.0,
            &server_public_key,
            &server_nonce,
        )
    } else {
        let code = normalized_code
            .as_deref()
            .expect("code pairing has a normalized code");
        if request.protocol_version == 2 {
            crypto::android_pairing_server_verifier(
                code,
                client_id.0,
                &request.client_public_key,
                &request.client_nonce,
                owner_installation_id.0,
                &server_public_key,
                &server_nonce,
                &sealed_reconnect_secret,
            )
        } else {
            crypto::pairing_server_verifier(
                code,
                client_id.0,
                &request.client_public_key,
                &request.client_nonce,
                owner_installation_id.0,
                &server_public_key,
                &server_nonce,
                &sealed_reconnect_secret,
            )
        }
    };

    let now = Utc::now();
    let device = TrustedClient {
        installation_id: client_id,
        display_name: request.device_name,
        platform: existing.as_ref().and_then(|saved| saved.platform).or(Some(
            if request.protocol_version == 2 {
                healthmd_protocol::wire::PeerPlatform::Android
            } else {
                healthmd_protocol::wire::PeerPlatform::Ios
            },
        )),
        reconnect_secret,
        paired_at: existing.as_ref().map_or(now, |saved| saved.paired_at),
        last_connected_at: now,
    };
    state.save_client(device.clone())?;
    trust_store.save(&state).await?;

    packet
        .send(&SyncPacket::PairingResponse(Unlabeled::from(
            PairingResponse {
                protocol_version: request.protocol_version,
                mac_name: server_display_name.into(),
                server_public_key: server_public_key.to_vec(),
                server_nonce: server_nonce.to_vec(),
                mac_installation_id: Some(owner_installation_id),
                authentication_verifier: Some(verifier.to_vec()),
                sealed_reconnect_secret: Some(sealed_reconnect_secret),
            },
        )))
        .await?;

    Ok((
        session_key,
        device,
        !trusted_reconnect,
        request.protocol_version,
    ))
}

#[must_use]
pub fn normalize_pairing_code(code: &str) -> String {
    code.chars().filter(char::is_ascii_digit).collect()
}

fn authentication_error(message: &str) -> ClientError {
    ClientError::Authentication(message.into())
}

#[allow(clippy::needless_pass_by_value)]
fn crypto_error(error: crypto::CryptoError) -> ClientError {
    ClientError::Authentication(error.to_string())
}

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        sync::{Arc, Mutex},
    };

    use async_trait::async_trait;
    use healthmd_protocol::wire::{PairingRequest, SyncPacket};
    use secrecy::{ExposeSecret as _, SecretString};
    use tokio::net::{TcpListener, TcpStream};
    use uuid::Uuid;

    use super::*;

    #[derive(Clone, Default)]
    struct MemoryCredentials(Arc<Mutex<HashMap<String, String>>>);

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

    #[test]
    fn pairing_code_normalization_is_ascii_only() {
        assert_eq!(normalize_pairing_code("123 456"), "123456");
        assert_eq!(normalize_pairing_code("１２３456"), "456");
    }

    #[tokio::test]
    async fn iphone_can_complete_pairing_and_decrypt_reconnect_secret() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let credentials = MemoryCredentials::default();
        let server_credentials = credentials.clone();
        let server_id = SwiftUuid(Uuid::new_v4());
        let client_id = SwiftUuid(Uuid::new_v4());
        let code = "123456";

        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let store = TrustStore::new(server_credentials);
            authenticate(
                PacketConnection::new(stream),
                server_id,
                "healthmd CLI",
                Some((code, "12345678901234567890")),
                &store,
            )
            .await
            .unwrap()
        });

        let mut packet = PacketConnection::new(TcpStream::connect(address).await.unwrap());
        let (client_private, client_public) = crypto::ephemeral_key_pair().unwrap();
        let client_nonce = [9_u8; 32];
        let code_verifier =
            crypto::pairing_verifier(code, client_id.0, &client_public, &client_nonce);
        packet
            .send(&SyncPacket::PairingRequest(Unlabeled::from(
                PairingRequest {
                    protocol_version: 1,
                    device_name: "Test iPhone".into(),
                    client_public_key: client_public.to_vec(),
                    client_nonce: client_nonce.to_vec(),
                    code_verifier: code_verifier.to_vec(),
                    client_installation_id: Some(client_id),
                    trusted_verifier: None,
                },
            )))
            .await
            .unwrap();

        let SyncPacket::PairingResponse(Unlabeled { value: response }) =
            packet.receive().await.unwrap()
        else {
            panic!("expected pairing response");
        };
        let shared =
            crypto::x25519_shared_secret(&client_private, &response.server_public_key).unwrap();
        let session_key = crypto::session_key(&shared, &client_nonce, &response.server_nonce);
        let sealed = response.sealed_reconnect_secret.as_ref().unwrap();
        let reconnect_secret = crypto::open(sealed, &session_key).unwrap();
        assert_eq!(reconnect_secret.len(), 32);
        let expected = crypto::pairing_server_verifier(
            code,
            client_id.0,
            &client_public,
            &client_nonce,
            response.mac_installation_id.unwrap().0,
            &response.server_public_key,
            &response.server_nonce,
            sealed,
        );
        assert!(crypto::constant_time_equal(
            response.authentication_verifier.as_ref().unwrap(),
            &expected
        ));

        let authenticated = server.await.unwrap();
        assert_eq!(authenticated.device.installation_id, client_id);
        let state = TrustStore::new(credentials).load(server_id).await.unwrap();
        assert_eq!(
            state.client(client_id.0).unwrap().reconnect_secret,
            reconnect_secret
        );
    }
}
