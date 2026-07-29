#[cfg(target_os = "macos")]
use std::sync::Mutex;

use async_trait::async_trait;
use secrecy::{ExposeSecret, SecretString};

#[cfg(target_os = "macos")]
use security_framework::os::macos::keychain::SecKeychain;

use crate::ClientError;

// Matches the deployed Swift CLI so macOS users can retain existing pairings.
const SERVICE: &str = "com.codybontecou.obsidianhealth.direct-cli-trust";

#[cfg(target_os = "macos")]
static MACOS_KEYCHAIN_INTERACTION_LOCK: Mutex<()> = Mutex::new(());

/// Keychain Services can otherwise open an authorization dialog from a blocking worker and wait
/// indefinitely after the CLI has lost its terminal/UI context. Serialize the process-global
/// interaction switch and fail immediately instead. Released, stably signed binaries retain normal
/// ACL access; inaccessible legacy/development entries return the stable storage error and must be
/// repaired explicitly rather than hanging or falling back to plaintext.
fn run_noninteractive<T>(
    operation: impl FnOnce() -> Result<T, ClientError>,
) -> Result<T, ClientError> {
    #[cfg(target_os = "macos")]
    {
        let _serial = MACOS_KEYCHAIN_INTERACTION_LOCK.lock().map_err(|_| {
            ClientError::CredentialStore("macOS Keychain access is unavailable".into())
        })?;
        let interaction_was_allowed = SecKeychain::user_interaction_allowed().map_err(|_| {
            ClientError::CredentialStore("macOS Keychain access is unavailable".into())
        })?;
        let _interaction = if interaction_was_allowed {
            Some(SecKeychain::disable_user_interaction().map_err(|_| {
                ClientError::CredentialStore("macOS Keychain access is unavailable".into())
            })?)
        } else {
            None
        };
        operation()
    }
    #[cfg(not(target_os = "macos"))]
    {
        operation()
    }
}

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
        keyring::Entry::new(SERVICE, account).map_err(Self::storage_error)
    }

    #[allow(clippy::needless_pass_by_value)]
    fn storage_error(error: keyring::Error) -> ClientError {
        #[cfg(target_os = "macos")]
        {
            let _ = error;
            ClientError::CredentialStore(
                "macOS Keychain access requires authorization or is unavailable".into(),
            )
        }
        #[cfg(not(target_os = "macos"))]
        {
            ClientError::CredentialStore(error.to_string())
        }
    }
}

#[async_trait]
impl CredentialStore for OsCredentialStore {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        let account = account.to_owned();
        tokio::task::spawn_blocking(move || {
            run_noninteractive(|| {
                let entry = Self::entry(&account)?;
                match entry.get_password() {
                    Ok(value) => Ok(Some(SecretString::from(value))),
                    Err(keyring::Error::NoEntry) => Ok(None),
                    Err(error) => Err(Self::storage_error(error)),
                }
            })
        })
        .await
        .map_err(|error| ClientError::CredentialStore(error.to_string()))?
    }

    async fn set(&self, account: &str, value: SecretString) -> Result<(), ClientError> {
        let account = account.to_owned();
        let value = value.expose_secret().to_owned();
        tokio::task::spawn_blocking(move || {
            run_noninteractive(|| {
                Self::entry(&account)?
                    .set_password(&value)
                    .map_err(Self::storage_error)
            })
        })
        .await
        .map_err(|error| ClientError::CredentialStore(error.to_string()))?
    }

    async fn delete(&self, account: &str) -> Result<(), ClientError> {
        let account = account.to_owned();
        tokio::task::spawn_blocking(move || {
            run_noninteractive(|| {
                let entry = Self::entry(&account)?;
                match entry.delete_credential() {
                    Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                    Err(error) => Err(Self::storage_error(error)),
                }
            })
        })
        .await
        .map_err(|error| ClientError::CredentialStore(error.to_string()))?
    }
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;

    #[test]
    fn keychain_operations_disable_and_restore_interaction() {
        let original = SecKeychain::user_interaction_allowed().unwrap();
        run_noninteractive(|| {
            assert!(!SecKeychain::user_interaction_allowed().unwrap());
            Ok(())
        })
        .unwrap();
        assert_eq!(SecKeychain::user_interaction_allowed().unwrap(), original);
    }
}
