use chrono::{DateTime, Utc};
use healthmd_protocol::encoding::{SwiftUuid, apple_reference_date, data};
use secrecy::{ExposeSecret as _, SecretString};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{ClientError, credentials::CredentialStore};

const TRUST_ACCOUNT: &str = "trust-state-v1";
const RECONNECT_SECRET_BYTES: usize = 32;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TrustedMac {
    #[serde(rename = "installationID")]
    pub installation_id: SwiftUuid,
    #[serde(rename = "displayName")]
    pub display_name: String,
    pub host: String,
    pub port: u16,
    #[serde(rename = "reconnectSecret", with = "data")]
    pub reconnect_secret: Vec<u8>,
    #[serde(rename = "pairedAt", with = "apple_reference_date")]
    pub paired_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TrustedClient {
    #[serde(rename = "installationID")]
    pub installation_id: SwiftUuid,
    #[serde(rename = "displayName")]
    pub display_name: String,
    #[serde(rename = "reconnectSecret", with = "data")]
    pub reconnect_secret: Vec<u8>,
    #[serde(rename = "pairedAt", with = "apple_reference_date")]
    pub paired_at: DateTime<Utc>,
    #[serde(rename = "lastConnectedAt", with = "apple_reference_date")]
    pub last_connected_at: DateTime<Utc>,
}

impl TrustedClient {
    fn is_valid(&self) -> bool {
        !self.installation_id.0.is_nil()
            && !self.display_name.is_empty()
            && self.reconnect_secret.len() == RECONNECT_SECRET_BYTES
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TrustState {
    #[serde(rename = "ownerInstallationID")]
    pub owner_installation_id: SwiftUuid,
    #[serde(rename = "trustedMac", skip_serializing_if = "Option::is_none")]
    pub trusted_mac: Option<TrustedMac>,
    #[serde(rename = "trustedClients")]
    pub trusted_clients: Vec<TrustedClient>,
}

impl TrustState {
    #[must_use]
    pub const fn empty(owner_installation_id: SwiftUuid) -> Self {
        Self {
            owner_installation_id,
            trusted_mac: None,
            trusted_clients: Vec::new(),
        }
    }

    #[must_use]
    pub fn client(&self, installation_id: Uuid) -> Option<&TrustedClient> {
        self.trusted_clients
            .iter()
            .find(|client| client.installation_id.0 == installation_id)
    }

    /// Insert or replace a validated trusted iPhone record.
    ///
    /// # Errors
    ///
    /// Returns an error when the installation ID, display name, or secret is invalid.
    pub fn save_client(&mut self, client: TrustedClient) -> Result<(), ClientError> {
        if !client.is_valid() {
            return Err(ClientError::InvalidTrustState);
        }
        self.trusted_clients
            .retain(|saved| saved.installation_id != client.installation_id);
        self.trusted_clients.push(client);
        Ok(())
    }

    pub fn forget_client(&mut self, installation_id: Uuid) -> bool {
        let original_count = self.trusted_clients.len();
        self.trusted_clients
            .retain(|client| client.installation_id.0 != installation_id);
        self.trusted_clients.len() != original_count
    }

    fn is_valid_for(&self, owner: SwiftUuid) -> bool {
        self.owner_installation_id == owner
            && self.trusted_clients.iter().all(TrustedClient::is_valid)
    }
}

pub struct TrustStore<C> {
    credentials: C,
}

impl<C: CredentialStore> TrustStore<C> {
    #[must_use]
    pub const fn new(credentials: C) -> Self {
        Self { credentials }
    }

    /// Load trust bound to the current installation, resetting mismatched or corrupt state.
    ///
    /// # Errors
    ///
    /// Returns an error when the operating system credential store is unavailable.
    pub async fn load(&self, owner: SwiftUuid) -> Result<TrustState, ClientError> {
        let Some(secret) = self.credentials.get(TRUST_ACCOUNT).await? else {
            return Ok(TrustState::empty(owner));
        };
        match serde_json::from_str::<TrustState>(secret.expose_secret()) {
            Ok(state) if state.is_valid_for(owner) => Ok(state),
            _ => Err(ClientError::InvalidTrustState),
        }
    }

    /// Persist the complete credential record in the OS credential store.
    ///
    /// # Errors
    ///
    /// Returns an error for invalid state, JSON encoding failure, or credential-store failure.
    pub async fn save(&self, state: &TrustState) -> Result<(), ClientError> {
        if !state.is_valid_for(state.owner_installation_id) {
            return Err(ClientError::InvalidTrustState);
        }
        let json = serde_json::to_string(state)
            .map_err(|error| ClientError::CredentialStore(error.to_string()))?;
        self.credentials
            .set(TRUST_ACCOUNT, SecretString::from(json))
            .await
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, sync::Mutex};

    use async_trait::async_trait;

    use super::*;

    #[derive(Default)]
    struct MemoryCredentials(Mutex<HashMap<String, String>>);

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

    #[tokio::test]
    async fn trust_round_trips_with_swift_field_names() {
        let store = TrustStore::new(MemoryCredentials::default());
        let owner = SwiftUuid(Uuid::new_v4());
        let device = SwiftUuid(Uuid::new_v4());
        let now = "2026-07-24T10:11:12Z".parse().unwrap();
        let mut state = TrustState::empty(owner);
        state
            .save_client(TrustedClient {
                installation_id: device,
                display_name: "iPhone".into(),
                reconnect_secret: vec![7; 32],
                paired_at: now,
                last_connected_at: now,
            })
            .unwrap();
        store.save(&state).await.unwrap();

        let loaded = store.load(owner).await.unwrap();
        assert_eq!(loaded, state);
    }

    #[tokio::test]
    async fn mismatched_owner_fails_closed() {
        let store = TrustStore::new(MemoryCredentials::default());
        let first = SwiftUuid(Uuid::new_v4());
        store.save(&TrustState::empty(first)).await.unwrap();
        let second = SwiftUuid(Uuid::new_v4());

        assert!(matches!(
            store.load(second).await,
            Err(ClientError::InvalidTrustState)
        ));
        assert_eq!(store.load(first).await.unwrap(), TrustState::empty(first));
    }
}
