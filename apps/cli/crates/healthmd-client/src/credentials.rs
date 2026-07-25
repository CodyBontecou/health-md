use async_trait::async_trait;
use secrecy::{ExposeSecret, SecretString};

use crate::ClientError;

// Matches the deployed Swift CLI so macOS users can retain existing pairings.
const SERVICE: &str = "com.codybontecou.obsidianhealth.direct-cli-trust";

/// Narrow credential boundary so protocol and job tests never touch a user's
/// real Keychain, Secret Service, or Windows Credential Manager.
#[async_trait]
pub trait CredentialStore: Send + Sync {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError>;
    async fn set(&self, account: &str, value: SecretString) -> Result<(), ClientError>;
    async fn delete(&self, account: &str) -> Result<(), ClientError>;
}

#[derive(Clone, Copy, Debug, Default)]
pub struct OsCredentialStore;

impl OsCredentialStore {
    fn entry(account: &str) -> Result<keyring::Entry, ClientError> {
        keyring::Entry::new(SERVICE, account)
            .map_err(|error| ClientError::CredentialStore(error.to_string()))
    }
}

#[async_trait]
impl CredentialStore for OsCredentialStore {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        let account = account.to_owned();
        tokio::task::spawn_blocking(move || {
            let entry = Self::entry(&account)?;
            match entry.get_password() {
                Ok(value) => Ok(Some(SecretString::from(value))),
                Err(keyring::Error::NoEntry) => Ok(None),
                Err(error) => Err(ClientError::CredentialStore(error.to_string())),
            }
        })
        .await
        .map_err(|error| ClientError::CredentialStore(error.to_string()))?
    }

    async fn set(&self, account: &str, value: SecretString) -> Result<(), ClientError> {
        let account = account.to_owned();
        let value = value.expose_secret().to_owned();
        tokio::task::spawn_blocking(move || {
            Self::entry(&account)?
                .set_password(&value)
                .map_err(|error| ClientError::CredentialStore(error.to_string()))
        })
        .await
        .map_err(|error| ClientError::CredentialStore(error.to_string()))?
    }

    async fn delete(&self, account: &str) -> Result<(), ClientError> {
        let account = account.to_owned();
        tokio::task::spawn_blocking(move || {
            let entry = Self::entry(&account)?;
            match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                Err(error) => Err(ClientError::CredentialStore(error.to_string())),
            }
        })
        .await
        .map_err(|error| ClientError::CredentialStore(error.to_string()))?
    }
}
