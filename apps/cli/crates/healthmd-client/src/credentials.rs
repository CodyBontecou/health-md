use std::{
    env,
    io::{self, Read as _, Write as _},
    process::Stdio,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

#[cfg(target_os = "macos")]
use std::sync::Mutex;

use async_trait::async_trait;
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use sysinfo::{ProcessesToUpdate, System};
use tokio::{
    io::{AsyncReadExt as _, AsyncWriteExt as _},
    process::Command,
    sync::Semaphore,
};

#[cfg(target_os = "macos")]
use security_framework::os::macos::keychain::SecKeychain;

use crate::ClientError;

// Matches the deployed Swift CLI so macOS users can retain existing pairings.
const SERVICE: &str = "com.codybontecou.obsidianhealth.direct-cli-trust";
const TRUST_ACCOUNT: &str = "trust-state-v1";
const HELPER_ARGUMENT: &str = "__credential-helper-v1";
const HELPER_PROTOCOL_VERSION: u16 = 1;
const MAXIMUM_HELPER_FRAME_BYTES: u64 = 1_048_576;
const CREDENTIAL_OPERATION_TIMEOUT: Duration = Duration::from_secs(10);

static CREDENTIAL_HELPER_GATE: Semaphore = Semaphore::const_new(1);

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

#[derive(Clone, Copy, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum HelperOperation {
    Get,
    Set,
    Delete,
    #[cfg(debug_assertions)]
    Probe,
}

impl HelperOperation {
    const fn mutates(self) -> bool {
        matches!(self, Self::Set | Self::Delete)
    }
}

#[derive(Deserialize, Serialize)]
struct HelperRequest {
    version: u16,
    operation: HelperOperation,
    account: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    value: Option<String>,
}

#[derive(Deserialize, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
enum HelperResponse {
    Success {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        value: Option<String>,
    },
    Failure,
}

impl OsCredentialStore {
    /// Exercise the bounded same-executable helper without reading or mutating credentials.
    ///
    /// # Errors
    ///
    /// Returns an error when private helper authentication, IPC, or supervision fails.
    #[cfg(debug_assertions)]
    pub async fn supervision_probe() -> Result<(), ClientError> {
        match Self::supervised(HelperRequest {
            version: HELPER_PROTOCOL_VERSION,
            operation: HelperOperation::Probe,
            account: TRUST_ACCOUNT.into(),
            value: None,
        })
        .await?
        {
            HelperResponse::Success { value: None } => Ok(()),
            HelperResponse::Success { value: Some(_) } | HelperResponse::Failure => Err(
                ClientError::CredentialStore("credential helper probe failed".into()),
            ),
        }
    }

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
            let _ = error;
            ClientError::CredentialStore("the native credential service is unavailable".into())
        }
    }

    fn native_get(account: &str) -> Result<Option<String>, ClientError> {
        run_noninteractive(|| {
            let entry = Self::entry(account)?;
            match entry.get_password() {
                Ok(value) => Ok(Some(value)),
                Err(keyring::Error::NoEntry) => Ok(None),
                Err(error) => Err(Self::storage_error(error)),
            }
        })
    }

    fn native_set(account: &str, value: &str) -> Result<(), ClientError> {
        run_noninteractive(|| {
            Self::entry(account)?
                .set_password(value)
                .map_err(Self::storage_error)
        })
    }

    fn native_delete(account: &str) -> Result<(), ClientError> {
        run_noninteractive(|| {
            let entry = Self::entry(account)?;
            match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                Err(error) => Err(Self::storage_error(error)),
            }
        })
    }

    async fn supervised(request: HelperRequest) -> Result<HelperResponse, ClientError> {
        let operation = request.operation;
        let request_bytes = serde_json::to_vec(&request).map_err(|_| {
            ClientError::CredentialStore("credential request encoding failed".into())
        })?;
        if u64::try_from(request_bytes.len()).unwrap_or(u64::MAX) > MAXIMUM_HELPER_FRAME_BYTES {
            return Err(ClientError::CredentialStore(
                "credential request exceeded its private IPC bound".into(),
            ));
        }

        let dispatched = Arc::new(AtomicBool::new(false));
        let dispatched_in_operation = Arc::clone(&dispatched);
        let result = tokio::time::timeout(CREDENTIAL_OPERATION_TIMEOUT, async move {
            let _permit = CREDENTIAL_HELPER_GATE.acquire().await.map_err(|_| {
                ClientError::CredentialStore("credential helper is unavailable".into())
            })?;
            let executable = env::current_exe().map_err(|_| {
                ClientError::CredentialStore("credential helper is unavailable".into())
            })?;
            let mut child = Command::new(executable)
                .arg(HELPER_ARGUMENT)
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .kill_on_drop(true)
                .env_remove("RUST_BACKTRACE")
                .env_remove("RUST_LOG")
                .spawn()
                .map_err(|_| {
                    ClientError::CredentialStore("credential helper is unavailable".into())
                })?;

            let mut stdin = child.stdin.take().ok_or_else(|| {
                ClientError::CredentialStore("credential helper input is unavailable".into())
            })?;
            stdin.write_all(&request_bytes).await.map_err(|_| {
                ClientError::CredentialStore("credential helper input failed".into())
            })?;
            // Tokio's process-pipe shutdown does not close the inherited handle. Drop the pipe
            // explicitly so the one-shot helper observes EOF and can authenticate the request.
            dispatched_in_operation.store(true, Ordering::Release);
            drop(stdin);

            let stdout = child.stdout.take().ok_or_else(|| {
                ClientError::CredentialStore("credential helper output is unavailable".into())
            })?;
            let read_output = async move {
                let mut output = Vec::new();
                stdout
                    .take(MAXIMUM_HELPER_FRAME_BYTES + 1)
                    .read_to_end(&mut output)
                    .await
                    .map_err(|_| {
                        ClientError::CredentialStore("credential helper output failed".into())
                    })?;
                if u64::try_from(output.len()).unwrap_or(u64::MAX) > MAXIMUM_HELPER_FRAME_BYTES {
                    return Err(ClientError::CredentialStore(
                        "credential helper output exceeded its private IPC bound".into(),
                    ));
                }
                Ok(output)
            };
            let wait_for_child = async {
                child
                    .wait()
                    .await
                    .map_err(|_| ClientError::CredentialStore("credential helper failed".into()))
            };
            let (status, output) = tokio::try_join!(wait_for_child, read_output)?;
            if !status.success() {
                return Err(ClientError::CredentialStore(
                    "credential helper failed".into(),
                ));
            }
            serde_json::from_slice(&output).map_err(|_| {
                ClientError::CredentialStore("credential helper response is invalid".into())
            })
        })
        .await;

        match result {
            Ok(Ok(response)) => Ok(response),
            Ok(Err(error)) if operation.mutates() && dispatched.load(Ordering::Acquire) => {
                let _ = error;
                Err(ClientError::CredentialMutationOutcomeUnknown)
            }
            Ok(Err(error)) => Err(error),
            Err(_) if operation.mutates() && dispatched.load(Ordering::Acquire) => {
                Err(ClientError::CredentialMutationOutcomeUnknown)
            }
            Err(_) => Err(ClientError::CredentialStore(
                "the native credential operation timed out".into(),
            )),
        }
    }
}

#[async_trait]
impl CredentialStore for OsCredentialStore {
    async fn get(&self, account: &str) -> Result<Option<SecretString>, ClientError> {
        validate_account(account)?;
        match Self::supervised(HelperRequest {
            version: HELPER_PROTOCOL_VERSION,
            operation: HelperOperation::Get,
            account: account.to_owned(),
            value: None,
        })
        .await?
        {
            HelperResponse::Success { value } => Ok(value.map(SecretString::from)),
            HelperResponse::Failure => Err(ClientError::CredentialStore(
                "the native credential service is unavailable".into(),
            )),
        }
    }

    async fn set(&self, account: &str, value: SecretString) -> Result<(), ClientError> {
        validate_account(account)?;
        match Self::supervised(HelperRequest {
            version: HELPER_PROTOCOL_VERSION,
            operation: HelperOperation::Set,
            account: account.to_owned(),
            value: Some(value.expose_secret().to_owned()),
        })
        .await?
        {
            HelperResponse::Success { value: None } => Ok(()),
            HelperResponse::Success { value: Some(_) } | HelperResponse::Failure => Err(
                ClientError::CredentialStore("the native credential service is unavailable".into()),
            ),
        }
    }

    async fn delete(&self, account: &str) -> Result<(), ClientError> {
        validate_account(account)?;
        match Self::supervised(HelperRequest {
            version: HELPER_PROTOCOL_VERSION,
            operation: HelperOperation::Delete,
            account: account.to_owned(),
            value: None,
        })
        .await?
        {
            HelperResponse::Success { value: None } => Ok(()),
            HelperResponse::Success { value: Some(_) } | HelperResponse::Failure => Err(
                ClientError::CredentialStore("the native credential service is unavailable".into()),
            ),
        }
    }
}

/// Run the private same-executable credential helper before argument parsing or Tokio startup.
///
/// The returned exit code is `None` for ordinary CLI invocations. The helper accepts one bounded
/// request only from an immediate parent running the same executable image; it never accepts
/// secrets through arguments or environment variables.
#[must_use]
pub fn run_credential_helper_if_requested() -> Option<u8> {
    let mut arguments = env::args_os();
    let _executable = arguments.next();
    if arguments.next().as_deref() != Some(HELPER_ARGUMENT.as_ref()) {
        return None;
    }
    if arguments.next().is_some() || !parent_is_same_executable() {
        return Some(1);
    }
    Some(u8::from(run_credential_helper().is_err()))
}

fn run_credential_helper() -> Result<(), ClientError> {
    let request_bytes = read_bounded(io::stdin().lock(), MAXIMUM_HELPER_FRAME_BYTES)?;
    let request: HelperRequest = serde_json::from_slice(&request_bytes)
        .map_err(|_| ClientError::CredentialStore("credential request is invalid".into()))?;
    validate_helper_request(&request)?;
    let response = match request.operation {
        HelperOperation::Get => match OsCredentialStore::native_get(&request.account) {
            Ok(value) => HelperResponse::Success { value },
            Err(_) => HelperResponse::Failure,
        },
        HelperOperation::Set => match request
            .value
            .as_deref()
            .ok_or_else(|| ClientError::CredentialStore("credential request is invalid".into()))
            .and_then(|value| OsCredentialStore::native_set(&request.account, value))
        {
            Ok(()) => HelperResponse::Success { value: None },
            Err(_) => HelperResponse::Failure,
        },
        HelperOperation::Delete => match OsCredentialStore::native_delete(&request.account) {
            Ok(()) => HelperResponse::Success { value: None },
            Err(_) => HelperResponse::Failure,
        },
        #[cfg(debug_assertions)]
        HelperOperation::Probe => HelperResponse::Success { value: None },
    };
    let response = serde_json::to_vec(&response)
        .map_err(|_| ClientError::CredentialStore("credential response encoding failed".into()))?;
    if u64::try_from(response.len()).unwrap_or(u64::MAX) > MAXIMUM_HELPER_FRAME_BYTES {
        return Err(ClientError::CredentialStore(
            "credential response exceeded its private IPC bound".into(),
        ));
    }
    let mut stdout = io::stdout().lock();
    stdout
        .write_all(&response)
        .map_err(|_| ClientError::CredentialStore("credential response output failed".into()))?;
    stdout
        .flush()
        .map_err(|_| ClientError::CredentialStore("credential response output failed".into()))
}

fn validate_helper_request(request: &HelperRequest) -> Result<(), ClientError> {
    validate_account(&request.account)?;
    let value_shape_is_valid = match request.operation {
        HelperOperation::Get | HelperOperation::Delete => request.value.is_none(),
        #[cfg(debug_assertions)]
        HelperOperation::Probe => request.value.is_none(),
        HelperOperation::Set => request.value.as_ref().is_some_and(|value| {
            u64::try_from(value.len()).unwrap_or(u64::MAX) <= MAXIMUM_HELPER_FRAME_BYTES
        }),
    };
    if request.version != HELPER_PROTOCOL_VERSION || !value_shape_is_valid {
        return Err(ClientError::CredentialStore(
            "credential request is invalid".into(),
        ));
    }
    Ok(())
}

fn validate_account(account: &str) -> Result<(), ClientError> {
    if account != TRUST_ACCOUNT {
        return Err(ClientError::CredentialStore(
            "credential account is not supported".into(),
        ));
    }
    Ok(())
}

fn read_bounded(mut input: impl io::Read, maximum_bytes: u64) -> Result<Vec<u8>, ClientError> {
    let mut bytes = Vec::new();
    input
        .by_ref()
        .take(maximum_bytes + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| ClientError::CredentialStore("credential request input failed".into()))?;
    if u64::try_from(bytes.len()).unwrap_or(u64::MAX) > maximum_bytes {
        return Err(ClientError::CredentialStore(
            "credential request exceeded its private IPC bound".into(),
        ));
    }
    Ok(bytes)
}

fn parent_is_same_executable() -> bool {
    let Ok(current_pid) = sysinfo::get_current_pid() else {
        return false;
    };
    let mut system = System::new();
    system.refresh_processes(ProcessesToUpdate::Some(&[current_pid]), true);
    let Some(parent_pid) = system
        .process(current_pid)
        .and_then(sysinfo::Process::parent)
    else {
        return false;
    };
    system.refresh_processes(ProcessesToUpdate::Some(&[parent_pid]), true);
    let Some(parent_executable) = system.process(parent_pid).and_then(sysinfo::Process::exe) else {
        return false;
    };
    let Ok(current_executable) = env::current_exe() else {
        return false;
    };
    same_file::is_same_file(parent_executable, current_executable).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(target_os = "macos")]
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

    #[test]
    fn helper_protocol_allows_only_the_fixed_trust_account_and_shapes() {
        let valid = HelperRequest {
            version: HELPER_PROTOCOL_VERSION,
            operation: HelperOperation::Set,
            account: TRUST_ACCOUNT.into(),
            value: Some("private".into()),
        };
        assert!(validate_helper_request(&valid).is_ok());

        let mut wrong_account = HelperRequest {
            version: HELPER_PROTOCOL_VERSION,
            operation: HelperOperation::Get,
            account: "arbitrary".into(),
            value: None,
        };
        assert!(validate_helper_request(&wrong_account).is_err());
        wrong_account.account = TRUST_ACCOUNT.into();
        wrong_account.value = Some("unexpected".into());
        assert!(validate_helper_request(&wrong_account).is_err());
    }

    #[test]
    fn helper_frames_are_bounded() {
        let oversized = vec![b'x'; usize::try_from(MAXIMUM_HELPER_FRAME_BYTES + 1).unwrap()];
        assert!(read_bounded(oversized.as_slice(), MAXIMUM_HELPER_FRAME_BYTES).is_err());
    }
}
