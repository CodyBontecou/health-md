//! Negative source gate only: no Windows issuer-storage promotion. Not run on macOS.
#![cfg(windows)]
use async_trait::async_trait;
use healthmd_client::{
    ClientError,
    agent_host::{HostAuthorityStore, ProtectedHostKey, ProtectedHostSecret},
};
use healthmd_protocol::v4::ControlUuid;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

struct NoNativeRead(AtomicUsize);
#[async_trait]
impl ProtectedHostKey for NoNativeRead {
    async fn load_existing(&self, _: &ControlUuid) -> Result<ProtectedHostSecret, ClientError> {
        self.0.fetch_add(1, Ordering::SeqCst);
        Err(ClientError::AgentAuthorityUnavailable)
    }
}
#[tokio::test]
async fn windows_issuer_identity_is_unavailable_before_key_or_record_access() {
    let temporary = tempfile::TempDir::new().unwrap();
    let key = Arc::new(NoNativeRead(AtomicUsize::new(0)));
    let result = HostAuthorityStore::open_existing(
        temporary.path().to_path_buf(),
        ControlUuid("00000000-0000-4000-8000-000000000002".into()),
        key.clone(),
    )
    .await;
    assert!(matches!(
        result,
        Err(ClientError::AgentAuthorityUnavailable)
    ));
    assert_eq!(key.0.load(Ordering::SeqCst), 0);
    assert_eq!(std::fs::read_dir(temporary.path()).unwrap().count(), 0);
}
