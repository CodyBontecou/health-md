//! Read-only, distinct native issuer-key account. No provisioning, write, delete or plaintext
//! fallback. The deployed trust helper accepts only its old fixed account and is untouched.
use async_trait::async_trait;
use secrecy::SecretString;
use tokio::sync::Semaphore;

use crate::{ClientError, credentials::CredentialStore};

static KEY_READ_GATE: Semaphore = Semaphore::const_new(1);

pub struct NativeHostKeyReader;
#[async_trait]
impl CredentialStore for NativeHostKeyReader {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        let host = account
            .strip_prefix("agent-host-issuer-v1-")
            .ok_or(ClientError::AgentAuthorityUnavailable)?;
        healthmd_protocol::v4::ValidateShape::validate_shape(&healthmd_protocol::v4::ControlUuid(
            host.into(),
        ))?;
        let account = account.to_owned();
        tokio::time::timeout(std::time::Duration::from_secs(10), async move {
            let permit = KEY_READ_GATE
                .acquire()
                .await
                .map_err(|_| ClientError::AgentAuthorityUnavailable)?;
            tokio::task::spawn_blocking(move || {
                let _permit = permit;
                read_native(&account)
            })
            .await
            .map_err(|_| ClientError::AgentAuthorityUnavailable)?
        })
        .await
        .map_err(|_| ClientError::AgentAuthorityUnavailable)?
    }
    async fn set(&self, _: &str, _: SecretString) -> Result<(), ClientError> {
        Err(ClientError::AgentAuthorityUnavailable)
    }
    async fn delete(&self, _: &str) -> Result<(), ClientError> {
        Err(ClientError::AgentAuthorityUnavailable)
    }
}

fn read_native(account: &str) -> Result<Option<SecretString>, ClientError> {
    #[cfg(target_os = "macos")]
    let _interaction = {
        use security_framework::os::macos::keychain::SecKeychain;
        let serial = crate::credentials::MACOS_KEYCHAIN_INTERACTION_LOCK
            .lock()
            .map_err(|_| ClientError::AgentAuthorityUnavailable)?;
        let allowed = SecKeychain::user_interaction_allowed()
            .map_err(|_| ClientError::AgentAuthorityUnavailable)?;
        let disabled = if allowed {
            Some(
                SecKeychain::disable_user_interaction()
                    .map_err(|_| ClientError::AgentAuthorityUnavailable)?,
            )
        } else {
            None
        };
        (serial, disabled)
    };
    let entry = keyring::Entry::new("com.codybontecou.healthmd.agent-host-issuer-v1", account)
        .map_err(|_| ClientError::AgentAuthorityUnavailable)?;
    match entry.get_password() {
        Ok(value) => Ok(Some(SecretString::from(value))),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(_) => Err(ClientError::AgentAuthorityUnavailable),
    }
}
