//! Synthetic retained output Stop ownership. No native transport or terminal proof implied.
use super::*;
use crate::agent_host::output::{
    NativeBinding, OutputAdmission, OutputTransaction, PendingOutputStop,
};

// Exercise the public recovery entry point for every corruption, key, clock and binding
// control below, rather than qualifying only the internal version-6 reader.
async fn read_output_stop_history(
    store: &crate::agent_host::HostAuthorityStore,
    job: &ControlUuid,
    clock: &dyn crate::agent_planning::PlanningClock,
) -> Result<ExecutionReceipt, ClientError> {
    Ok(
        Box::pin(store.retained_source_stop_confirmation(job, clock))
            .await?
            .receipt()
            .clone(),
    )
}

async fn output_transaction(f: &AcceptedFixture, platform: PeerPlatform) -> OutputTransaction {
    output_transaction_with_binding(f, synthetic_binding(&f.request, platform)).await
}

pub(super) async fn output_transaction_with_binding(
    f: &AcceptedFixture,
    binding: NativeBinding,
) -> OutputTransaction {
    let mut admission = OutputAdmission::reserve(&f.store, &f.request, &f.clock, || async {
        Ok(f.output.clone())
    })
    .await
    .unwrap();
    admission
        .persist_accepted(&f.accepted, &f.clock, || async { Ok(f.output.clone()) })
        .await
        .unwrap();
    let mut transaction = admission.bind(&binding).unwrap();
    transaction
        .save(|| async { Ok(f.output.clone()) })
        .await
        .unwrap();
    transaction
}
fn journal(f: &AcceptedFixture, prefix: &str) -> std::path::PathBuf {
    f.client
        .layout
        .root
        .join("agent-host-v1")
        .join(format!("{prefix}-{}.json", f.request.job_id.0))
}

#[tokio::test]
async fn output_stop_preserves_output_and_original_attempt_but_blocks_resume() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = accepted_fixture(platform).await;
        let transaction = output_transaction(&f, platform).await;
        let output = std::fs::read(journal(&f, "output")).unwrap();
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
            .await
            .unwrap();
        assert_eq!(owner.request().job_id, f.request.job_id);
        assert_eq!(
            owner.request().request_sha256,
            document_digest(&f.request).unwrap()
        );
        assert_eq!(std::fs::read(journal(&f, "output")).unwrap(), output);
        let pending: serde_json::Value =
            serde_json::from_slice(&std::fs::read(journal(&f, "attempt")).unwrap()).unwrap();
        assert_eq!(pending["attempt"]["schema_version"], 5);
        assert_eq!(
            pending["attempt"]["original_attempt"],
            serde_json::from_slice::<serde_json::Value>(&original).unwrap()
        );
        assert_eq!(
            pending["attempt"]["binding"]["accepted"]["expires_at"],
            serde_json::to_value(&f.accepted.expires_at).unwrap()
        );
        assert!(!journal(&f, "transfer").exists());
        assert!(!journal(&f, "completion").exists());
        assert!(matches!(
            OutputTransaction::open_retained(&f.store, &f.request.job_id).await,
            Err(ClientError::AgentStoreBusy)
        ));
        drop(owner);
        // The original output reader cannot silently resume a pending Stop after restart.
        assert!(
            OutputTransaction::open_retained(&f.store, &f.request.job_id)
                .await
                .is_err()
        );
        assert!(
            OutputAdmission::open_retained_accepted(&f.store, &f.request.job_id, &f.clock)
                .await
                .is_err()
        );
    }
}

#[tokio::test]
async fn output_stop_rejects_existing_transfer_and_preserves_attempt() {
    for prefix in ["transfer", "completion"] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        let transaction = output_transaction(&f, PeerPlatform::Ios).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        std::fs::write(journal(&f, prefix), b"synthetic untrusted checkpoint").unwrap();
        assert!(
            PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    }
}

#[tokio::test]
async fn output_stop_rechecks_output_and_transfer_after_trust_callback() {
    for prefix in ["output", "transfer", "completion"] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        let transaction = output_transaction(&f, PeerPlatform::Ios).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        let changed = journal(&f, prefix);
        let fence = || async {
            std::fs::write(&changed, b"synthetic callback drift").unwrap();
            Ok(())
        };
        assert!(
            PendingOutputStop::prepare(transaction, &f.clock, fence)
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    }
}

#[tokio::test]
async fn output_stop_never_publishes_when_original_peer_trust_fails() {
    let f = accepted_fixture(PeerPlatform::Android).await;
    let transaction = output_transaction(&f, PeerPlatform::Android).await;
    let original = std::fs::read(journal(&f, "attempt")).unwrap();
    assert!(
        PendingOutputStop::prepare(transaction, &f.clock, || async {
            Err(ClientError::AgentAuthorityUnavailable)
        })
        .await
        .is_err()
    );
    assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
}

#[tokio::test]
async fn output_stop_remains_available_after_export_delegation_revocation() {
    let f = accepted_fixture(PeerPlatform::Ios).await;
    let transaction = output_transaction(&f, PeerPlatform::Ios).await;
    f.store
        .revoke_local(
            f.store.revision().await.unwrap(),
            &f.request.plan.authority_references.host.authority_id,
        )
        .await
        .unwrap();
    let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
        .await
        .unwrap();
    assert_eq!(
        owner.request().request_sha256,
        document_digest(&f.request).unwrap()
    );
    assert!(!journal(&f, "completion").exists());
}

#[tokio::test]
async fn output_stop_rechecks_key_after_trust_callback() {
    for state in [1, 2] {
        let mut f = accepted_fixture(PeerPlatform::Ios).await;
        let key = Arc::new(MutableOutputKey(AtomicUsize::new(0)));
        f.store = crate::agent_host::HostAuthorityStore::open_existing(
            f.client.layout.root.join("agent-host-v1"),
            f.peer.host_installation_id.clone(),
            key.clone(),
        )
        .await
        .unwrap();
        let transaction = output_transaction(&f, PeerPlatform::Ios).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        assert!(
            PendingOutputStop::prepare(transaction, &f.clock, || async {
                key.0.store(state, Ordering::SeqCst);
                Ok(())
            })
            .await
            .is_err()
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    }
}

#[tokio::test]
async fn output_stop_rejects_expiry_and_clock_rollback_after_callback() {
    for seconds in [-1, 604_800] {
        let f = accepted_fixture(PeerPlatform::Android).await;
        let transaction = output_transaction(&f, PeerPlatform::Android).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        assert!(
            PendingOutputStop::prepare(transaction, &f.clock, || async {
                f.clock.advance_to(seconds);
                Ok(())
            })
            .await
            .is_err()
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    }
}

async fn pending_checkpoint(f: &AcceptedFixture, platform: PeerPlatform) {
    let transaction = output_transaction(f, platform).await;
    drop(
        PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
            .await
            .unwrap(),
    );
}

#[tokio::test]
async fn retained_output_stop_recovers_exact_pending_intent_without_rewriting_files() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = accepted_fixture(platform).await;
        pending_checkpoint(&f, platform).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        let output = std::fs::read(journal(&f, "output")).unwrap();
        let owner =
            PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                Ok(())
            })
            .await
            .unwrap();
        assert_eq!(
            owner.request().request_sha256,
            document_digest(&f.request).unwrap()
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
        assert_eq!(std::fs::read(journal(&f, "output")).unwrap(), output);
        assert!(matches!(
            PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                Ok(())
            })
            .await,
            Err(ClientError::AgentStoreBusy)
        ));
        assert!(!journal(&f, "transfer").exists());
        assert!(!journal(&f, "completion").exists());
    }
}

async fn sign_pending_fixture(f: &AcceptedFixture, value: &mut serde_json::Value) {
    sign_stop_fixture(f, value, b"HealthMd.AgentBridge.HostExecutionAttempt.v5\0").await;
}
async fn sign_stop_fixture(f: &AcceptedFixture, value: &mut serde_json::Value, domain: &[u8]) {
    use base64::Engine as _;
    use hmac::Mac as _;
    use secrecy::ExposeSecret as _;
    let secret = crate::agent_host::ProtectedHostKey::load_existing(
        &FakeProtectedKey,
        &f.peer.host_installation_id,
    )
    .await
    .unwrap();
    let key = base64::engine::general_purpose::STANDARD
        .decode(secret.expose_secret())
        .unwrap();
    let mut signer = hmac::Hmac::<sha2::Sha256>::new_from_slice(&key).unwrap();
    signer.update(domain);
    signer.update(&serde_json::to_vec(&value["attempt"]).unwrap());
    value["mac"] = serde_json::Value::String(format!("{:x}", signer.finalize().into_bytes()));
}

#[tokio::test]
async fn retained_output_stop_authenticates_original_attempt_and_output_binding() {
    for change in [
        "inner_mac",
        "request",
        "cancel",
        "output_digest",
        "version",
        "future",
        "outer_mac",
    ] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        pending_checkpoint(&f, PeerPlatform::Ios).await;
        let mut record: serde_json::Value =
            serde_json::from_slice(&std::fs::read(journal(&f, "attempt")).unwrap()).unwrap();
        match change {
            "inner_mac" => record["attempt"]["original_attempt"]["mac"] = "0".repeat(64).into(),
            "request" => record["attempt"]["binding"]["request"]["job_id"] = id(99).0.into(),
            "cancel" => {
                record["attempt"]["cancellation_request"]["request_sha256"] = "1".repeat(64).into();
            }
            "output_digest" => record["attempt"]["output_sha256"] = "2".repeat(64).into(),
            "version" => record["attempt"]["schema_version"] = 4.into(),
            "future" => {
                record["attempt"]["requested_at"] = serde_json::to_value(later(&now(), 1)).unwrap();
            }
            "outer_mac" => {}
            _ => unreachable!(),
        }
        // Give malformed metadata a valid new-format outer MAC: inner authentication and
        // bound output checks must still reject it independently of transport authenticity.
        sign_pending_fixture(&f, &mut record).await;
        if change == "outer_mac" {
            record["mac"] = "3".repeat(64).into();
        }
        let changed = serde_json::to_vec(&record).unwrap();
        std::fs::write(journal(&f, "attempt"), &changed).unwrap();
        assert!(
            PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                Ok(())
            })
            .await
            .is_err(),
            "accepted mutation: {change}"
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), changed);
    }
}

#[tokio::test]
async fn retained_output_stop_does_not_create_missing_owned_records() {
    for prefix in ["lock", "attempt", "output"] {
        let f = accepted_fixture(PeerPlatform::Android).await;
        pending_checkpoint(&f, PeerPlatform::Android).await;
        let path = if prefix == "lock" {
            f.client.layout.root.join("agent-host-v1/outputs.lock")
        } else {
            journal(&f, prefix)
        };
        std::fs::remove_file(&path).unwrap();
        assert!(
            PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                Ok(())
            })
            .await
            .is_err()
        );
        assert!(!path.exists(), "recreated missing {prefix}");
    }
}

#[tokio::test]
async fn retained_output_stop_rechecks_files_after_delaying_trust_callback() {
    for prefix in ["output", "attempt", "transfer", "completion"] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        pending_checkpoint(&f, PeerPlatform::Ios).await;
        let changed = journal(&f, prefix);
        assert!(
            PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                std::fs::write(&changed, b"synthetic retained drift").unwrap();
                Ok(())
            })
            .await
            .is_err()
        );
    }
}

fn issuer_entries(f: &AcceptedFixture) -> std::collections::BTreeSet<std::ffi::OsString> {
    std::fs::read_dir(f.client.layout.root.join("agent-host-v1"))
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .collect()
}

#[tokio::test]
async fn dropping_output_stop_before_rename_preserves_resumable_original_and_removes_only_stage() {
    let f = accepted_fixture(PeerPlatform::Ios).await;
    let transaction = output_transaction(&f, PeerPlatform::Ios).await;
    let original = std::fs::read(journal(&f, "attempt")).unwrap();
    let output = std::fs::read(journal(&f, "output")).unwrap();
    let before = issuer_entries(&f);
    let calls = AtomicUsize::new(0);
    let entered = tokio::sync::Notify::new();
    let mut task = Box::pin(PendingOutputStop::prepare(
        transaction,
        &f.clock,
        || async {
            if calls.fetch_add(1, Ordering::SeqCst) == 1 {
                entered.notify_one();
                std::future::pending::<()>().await;
            }
            Ok(())
        },
    ));
    tokio::select! {
        biased;
        _ = &mut task => panic!("Stop checkpoint unexpectedly finished before interruption"),
        () = entered.notified() => {},
    }
    assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    assert_eq!(issuer_entries(&f).len(), before.len() + 1);
    drop(task);
    assert_eq!(issuer_entries(&f), before);
    assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    assert_eq!(std::fs::read(journal(&f, "output")).unwrap(), output);
    assert!(
        OutputTransaction::open_retained(&f.store, &f.request.job_id)
            .await
            .is_ok()
    );
    assert!(
        PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
            Ok(())
        })
        .await
        .is_err()
    );
}

#[tokio::test]
async fn dropping_output_stop_after_rename_retains_pending_without_terminal_proof() {
    let f = accepted_fixture(PeerPlatform::Android).await;
    let transaction = output_transaction(&f, PeerPlatform::Android).await;
    let original = std::fs::read(journal(&f, "attempt")).unwrap();
    let output = std::fs::read(journal(&f, "output")).unwrap();
    let before = issuer_entries(&f);
    let calls = AtomicUsize::new(0);
    let entered = tokio::sync::Notify::new();
    let mut task = Box::pin(PendingOutputStop::prepare(
        transaction,
        &f.clock,
        || async {
            if calls.fetch_add(1, Ordering::SeqCst) == 2 {
                entered.notify_one();
                std::future::pending::<()>().await;
            }
            Ok(())
        },
    ));
    tokio::select! {
        biased;
        _ = &mut task => panic!("Stop checkpoint unexpectedly finished before interruption"),
        () = entered.notified() => {},
    }
    let published = std::fs::read(journal(&f, "attempt")).unwrap();
    assert_ne!(published, original);
    let pending: serde_json::Value = serde_json::from_slice(&published).unwrap();
    assert_eq!(pending["attempt"]["schema_version"], 5);
    assert!(pending["attempt"].get("source_receipt").is_none());
    drop(task);
    assert_eq!(issuer_entries(&f), before);
    assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), published);
    assert_eq!(std::fs::read(journal(&f, "output")).unwrap(), output);
    assert!(
        OutputTransaction::open_retained(&f.store, &f.request.job_id)
            .await
            .is_err()
    );
    let owner = PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
        Ok(())
    })
    .await
    .unwrap();
    assert_eq!(owner.request().job_id, f.request.job_id);
    assert!(!journal(&f, "completion").exists());
}

#[tokio::test]
async fn output_stop_reserves_one_publication_entry_but_retained_pending_needs_none() {
    for limit in [8191, 8192] {
        let f = accepted_fixture(PeerPlatform::Android).await;
        let transaction = output_transaction(&f, PeerPlatform::Android).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        let root = f.client.layout.root.join("agent-host-v1");
        for index in issuer_entries(&f).len()..limit {
            std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(root.join(format!("synthetic-output-stop-quota-{index}")))
                .unwrap();
        }
        let before = issuer_entries(&f);
        let result = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) }).await;
        if limit == 8192 {
            assert!(matches!(result, Err(ClientError::AgentStoreFull)));
            assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
        } else {
            drop(result.unwrap());
            std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(root.join("synthetic-output-stop-last-slot"))
                .unwrap();
            let pending = std::fs::read(journal(&f, "attempt")).unwrap();
            let full = issuer_entries(&f);
            assert_eq!(full.len(), 8192);
            let owner =
                PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                    Ok(())
                })
                .await
                .unwrap();
            assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), pending);
            assert_eq!(issuer_entries(&f), full);
            drop(owner);
            std::fs::remove_file(root.join("synthetic-output-stop-last-slot")).unwrap();
        }
        assert_eq!(issuer_entries(&f), before);
    }
}

#[tokio::test]
async fn empty_source_manifest_is_compatible_with_predicted_paths_without_fabricating_files() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = accepted_fixture(platform).await;
        let mut binding = synthetic_binding(&f.request, platform);
        assert!(!binding.request.plan.predicted_paths.is_empty());
        binding.manifest.capture_status = ArtifactManifestCaptureStatus::CompleteEmpty;
        binding.manifest.artifacts.clear();
        v4::validate_artifact_manifest(&binding.manifest).unwrap();
        binding
            .validate()
            .expect("A legitimate empty source result must not fabricate predicted files");
    }
}

fn bound_stop_receipt(binding: &NativeBinding, status: ExecutionReceiptStatus) -> ExecutionReceipt {
    let mut receipt = binding.accepted.clone();
    receipt.status = status;
    receipt.source_acknowledged = true;
    receipt.manifest_sha256 = document_digest(&binding.manifest).unwrap();
    receipt.frontier_sha256 = Digest("a".repeat(64));
    receipt.artifact_count = binding.manifest.artifacts.len() as u64;
    receipt.committed_partition_count = if receipt.status == ExecutionReceiptStatus::Cancelled {
        0
    } else {
        receipt.artifact_count
    };
    receipt
}

#[tokio::test]
async fn output_stop_preserves_source_terminal_status_and_historical_facts_after_expiry() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for status in [
            ExecutionReceiptStatus::Cancelled,
            ExecutionReceiptStatus::Complete,
            ExecutionReceiptStatus::CompleteEmpty,
            ExecutionReceiptStatus::Partial,
        ] {
            let f = accepted_fixture(platform).await;
            let mut binding = synthetic_binding(&f.request, platform);
            if status == ExecutionReceiptStatus::CompleteEmpty {
                binding.manifest.capture_status = ArtifactManifestCaptureStatus::CompleteEmpty;
                binding.manifest.artifacts.clear();
            } else if status == ExecutionReceiptStatus::Partial {
                binding.manifest.capture_status = ArtifactManifestCaptureStatus::Partial;
            }
            let receipt = bound_stop_receipt(&binding, status);
            let transaction = output_transaction_with_binding(&f, binding).await;
            let original_output = std::fs::read(journal(&f, "output")).unwrap();
            let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
                .await
                .unwrap();
            let confirmed = owner
                .confirm(&receipt, &f.clock, &CancellationToken::new(), || async {
                    Ok(())
                })
                .await
                .unwrap();
            assert_eq!(confirmed, receipt);
            let original = std::fs::read(journal(&f, "attempt")).unwrap();
            let value: serde_json::Value = serde_json::from_slice(&original).unwrap();
            assert_eq!(value["attempt"]["schema_version"], 6);
            assert_eq!(
                read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                    .await
                    .unwrap(),
                receipt
            );
            assert!(
                PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                    Ok(())
                })
                .await
                .is_err()
            );
            assert!(
                OutputTransaction::open_retained(&f.store, &f.request.job_id)
                    .await
                    .is_err()
            );
            f.store
                .revoke_local(
                    f.store.revision().await.unwrap(),
                    &f.request.plan.authority_references.host.authority_id,
                )
                .await
                .unwrap();
            f.clock.advance_to(604_800);
            assert_eq!(
                f.store
                    .retained_source_stop_confirmation(&f.request.job_id, &f.clock)
                    .await
                    .unwrap()
                    .receipt(),
                &receipt
            );
            assert_eq!(
                read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                    .await
                    .unwrap(),
                receipt
            );
            assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
            assert_eq!(
                std::fs::read(journal(&f, "output")).unwrap(),
                original_output
            );
            assert!(!journal(&f, "completion").exists());
            assert!(!journal(&f, "transfer").exists());
        }
    }
}

#[tokio::test]
async fn output_stop_does_not_confirm_pending_wrong_or_unacknowledged_receipts() {
    for change in [
        "no_ack",
        "pending",
        "wrong_job",
        "wrong_manifest",
        "wrong_count",
        "renewed_expiry",
        "contradictory_status",
    ] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        let binding = synthetic_binding(&f.request, PeerPlatform::Ios);
        let mut receipt = bound_stop_receipt(&binding, ExecutionReceiptStatus::Cancelled);
        let transaction = output_transaction_with_binding(&f, binding).await;
        let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
            .await
            .unwrap();
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        match change {
            "no_ack" => receipt.source_acknowledged = false,
            "pending" => {
                receipt.status = ExecutionReceiptStatus::CancellationPending;
                receipt.source_acknowledged = false;
            }
            "wrong_job" => receipt.job_id = id(99),
            "wrong_manifest" => receipt.manifest_sha256 = Digest("b".repeat(64)),
            "wrong_count" => receipt.artifact_count += 1,
            "renewed_expiry" => receipt.expires_at = later(&receipt.expires_at, 1),
            "contradictory_status" => receipt.status = ExecutionReceiptStatus::Partial,
            _ => unreachable!(),
        }
        assert!(
            owner
                .confirm(&receipt, &f.clock, &CancellationToken::new(), || async {
                    Ok(())
                })
                .await
                .is_err(),
            "accepted {change}"
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
        assert!(
            read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                .await
                .is_err()
        );
        assert!(
            PendingOutputStop::open_retained(&f.store, &f.request.job_id, &f.clock, || async {
                Ok(())
            })
            .await
            .is_ok()
        );
    }
}

#[tokio::test]
async fn output_stop_still_rejects_incomplete_nonempty_success_and_nonempty_empty_capture() {
    let f = accepted_fixture(PeerPlatform::Ios).await;
    let mut missing = synthetic_binding(&f.request, PeerPlatform::Ios);
    missing.manifest.artifacts.pop();
    assert!(missing.validate().is_err());
    let mut contradictory = synthetic_binding(&f.request, PeerPlatform::Ios);
    contradictory.manifest.capture_status = ArtifactManifestCaptureStatus::CompleteEmpty;
    assert!(contradictory.validate().is_err());
}

struct CancellingOutputStopKey {
    remaining: AtomicUsize,
    cancellation: CancellationToken,
}
#[async_trait::async_trait]
impl crate::agent_host::ProtectedHostKey for CancellingOutputStopKey {
    async fn load_existing(
        &self,
        host: &ControlUuid,
    ) -> Result<crate::agent_host::ProtectedHostSecret, ClientError> {
        if self
            .remaining
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            == Ok(1)
        {
            self.cancellation.cancel();
        }
        crate::agent_host::ProtectedHostKey::load_existing(&FakeProtectedKey, host).await
    }
}

#[tokio::test]
async fn output_stop_confirmation_cannot_return_after_cancellation_in_key_callback() {
    for read in [1, 2, 3] {
        let mut f = accepted_fixture(PeerPlatform::Ios).await;
        let cancellation = CancellationToken::new();
        let key = Arc::new(CancellingOutputStopKey {
            remaining: AtomicUsize::new(0),
            cancellation: cancellation.clone(),
        });
        f.store = crate::agent_host::HostAuthorityStore::open_existing(
            f.client.layout.root.join("agent-host-v1"),
            f.peer.host_installation_id.clone(),
            key.clone(),
        )
        .await
        .unwrap();
        let binding = synthetic_binding(&f.request, PeerPlatform::Ios);
        let receipt = bound_stop_receipt(&binding, ExecutionReceiptStatus::Cancelled);
        let transaction = output_transaction_with_binding(&f, binding).await;
        let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
            .await
            .unwrap();
        let pending = std::fs::read(journal(&f, "attempt")).unwrap();
        key.remaining.store(read, Ordering::SeqCst);
        assert!(matches!(
            owner
                .confirm(&receipt, &f.clock, &cancellation, || async { Ok(()) })
                .await,
            Err(ClientError::WaitCancelled)
        ));
        if read < 3 {
            assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), pending);
            assert!(
                read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                    .await
                    .is_err()
            );
        } else {
            // The real receipt was durably observed before local cancellation; historical
            // source facts remain inspectable, but this cancelled call returned no proof.
            assert_eq!(
                read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                    .await
                    .unwrap(),
                receipt
            );
        }
        assert!(!journal(&f, "completion").exists());
    }
}

async fn confirmed_checkpoint(f: &AcceptedFixture) -> ExecutionReceipt {
    let binding = synthetic_binding(&f.request, PeerPlatform::Ios);
    let receipt = bound_stop_receipt(&binding, ExecutionReceiptStatus::Cancelled);
    let transaction = output_transaction_with_binding(f, binding).await;
    let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
        .await
        .unwrap();
    owner
        .confirm(&receipt, &f.clock, &CancellationToken::new(), || async {
            Ok(())
        })
        .await
        .unwrap()
}

#[tokio::test]
async fn historical_output_stop_rejects_forged_facts_even_with_valid_outer_mac() {
    for change in [
        "no_ack",
        "wrong_job",
        "wrong_manifest",
        "wrong_count",
        "pending_mac",
        "future",
        "before_intent",
        "outer_mac",
    ] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        Box::pin(confirmed_checkpoint(&f)).await;
        let mut value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(journal(&f, "attempt")).unwrap()).unwrap();
        match change {
            "no_ack" => value["attempt"]["source_receipt"]["source_acknowledged"] = false.into(),
            "wrong_job" => value["attempt"]["source_receipt"]["job_id"] = id(99).0.into(),
            "wrong_manifest" => {
                value["attempt"]["source_receipt"]["manifest_sha256"] = "b".repeat(64).into();
            }
            "wrong_count" => value["attempt"]["source_receipt"]["artifact_count"] = 99.into(),
            "pending_mac" => value["attempt"]["pending"]["mac"] = "0".repeat(64).into(),
            "future" => {
                value["attempt"]["source_confirmed_at"] =
                    serde_json::to_value(later(&now(), 1)).unwrap();
            }
            "before_intent" => {
                value["attempt"]["source_confirmed_at"] =
                    serde_json::to_value(later(&now(), -1)).unwrap();
            }
            "outer_mac" => {}
            _ => unreachable!(),
        }
        sign_stop_fixture(
            &f,
            &mut value,
            b"HealthMd.AgentBridge.HostExecutionAttempt.v6\0",
        )
        .await;
        if change == "outer_mac" {
            value["mac"] = "c".repeat(64).into();
        }
        let changed = serde_json::to_vec(&value).unwrap();
        std::fs::write(journal(&f, "attempt"), &changed).unwrap();
        assert!(
            read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                .await
                .is_err(),
            "accepted {change}"
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), changed);
    }
}

#[tokio::test]
async fn historical_output_stop_resamples_current_time_after_last_key_await() {
    for seconds in [-1, 604_800] {
        let mut f = accepted_fixture(PeerPlatform::Ios).await;
        let clock = Arc::new(AdvancingClock::new());
        let key = Arc::new(DelayedProtectedKey::new(clock.clone()));
        f.store = crate::agent_host::HostAuthorityStore::open_existing(
            f.client.layout.root.join("agent-host-v1"),
            f.peer.host_installation_id.clone(),
            key.clone(),
        )
        .await
        .unwrap();
        let receipt = Box::pin(confirmed_checkpoint(&f)).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        key.arm(2, seconds);
        let result = read_output_stop_history(&f.store, &f.request.job_id, clock.as_ref()).await;
        assert_eq!(key.delays.load(Ordering::SeqCst), 1);
        if seconds < 0 {
            assert!(result.is_err());
        } else {
            assert_eq!(result.unwrap(), receipt);
        }
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    }
}

#[tokio::test]
async fn historical_output_stop_requires_the_original_protected_key() {
    for state in [1, 2] {
        let mut f = accepted_fixture(PeerPlatform::Ios).await;
        let key = Arc::new(MutableOutputKey(AtomicUsize::new(0)));
        f.store = crate::agent_host::HostAuthorityStore::open_existing(
            f.client.layout.root.join("agent-host-v1"),
            f.peer.host_installation_id.clone(),
            key.clone(),
        )
        .await
        .unwrap();
        Box::pin(confirmed_checkpoint(&f)).await;
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        key.0.store(state, Ordering::SeqCst);
        assert!(
            read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    }
}

fn manifest_for_terminal_status(
    f: &AcceptedFixture,
    status: &ExecutionReceiptStatus,
) -> NativeBinding {
    let mut binding = synthetic_binding(&f.request, PeerPlatform::Ios);
    if *status == ExecutionReceiptStatus::CompleteEmpty {
        binding.manifest.capture_status = ArtifactManifestCaptureStatus::CompleteEmpty;
        binding.manifest.artifacts.clear();
    } else if *status == ExecutionReceiptStatus::Partial {
        binding.manifest.capture_status = ArtifactManifestCaptureStatus::Partial;
    }
    binding
}
fn invalid_committed_count(receipt: &ExecutionReceipt) -> u64 {
    if matches!(
        receipt.status,
        ExecutionReceiptStatus::Cancelled | ExecutionReceiptStatus::CompleteEmpty
    ) {
        receipt.artifact_count + 1
    } else {
        0
    }
}

#[tokio::test]
async fn output_stop_rejects_contradictory_committed_counts_before_confirmation() {
    for status in [
        ExecutionReceiptStatus::Cancelled,
        ExecutionReceiptStatus::Complete,
        ExecutionReceiptStatus::Partial,
        ExecutionReceiptStatus::CompleteEmpty,
    ] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        let binding = manifest_for_terminal_status(&f, &status);
        let mut receipt = bound_stop_receipt(&binding, status);
        receipt.committed_partition_count = invalid_committed_count(&receipt);
        let transaction = output_transaction_with_binding(&f, binding).await;
        let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
            .await
            .unwrap();
        let original = std::fs::read(journal(&f, "attempt")).unwrap();
        assert!(
            owner
                .confirm(&receipt, &f.clock, &CancellationToken::new(), || async {
                    Ok(())
                })
                .await
                .is_err(),
            "accepted contradictory committed count"
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), original);
    }
}

#[tokio::test]
async fn output_stop_rejects_contradictory_committed_counts_in_historical_facts() {
    for status in [
        ExecutionReceiptStatus::Cancelled,
        ExecutionReceiptStatus::Complete,
        ExecutionReceiptStatus::Partial,
        ExecutionReceiptStatus::CompleteEmpty,
    ] {
        let f = accepted_fixture(PeerPlatform::Ios).await;
        let binding = manifest_for_terminal_status(&f, &status);
        let mut receipt = bound_stop_receipt(&binding, status);
        if receipt.status != ExecutionReceiptStatus::Cancelled {
            receipt.committed_partition_count = receipt.artifact_count;
        }
        let invalid_count = invalid_committed_count(&receipt);
        let transaction = output_transaction_with_binding(&f, binding).await;
        let owner = PendingOutputStop::prepare(transaction, &f.clock, || async { Ok(()) })
            .await
            .unwrap();
        owner
            .confirm(&receipt, &f.clock, &CancellationToken::new(), || async {
                Ok(())
            })
            .await
            .unwrap();
        let mut value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(journal(&f, "attempt")).unwrap()).unwrap();
        value["attempt"]["source_receipt"]["committed_partition_count"] = invalid_count.into();
        sign_stop_fixture(
            &f,
            &mut value,
            b"HealthMd.AgentBridge.HostExecutionAttempt.v6\0",
        )
        .await;
        let changed = serde_json::to_vec(&value).unwrap();
        std::fs::write(journal(&f, "attempt"), &changed).unwrap();
        assert!(
            read_output_stop_history(&f.store, &f.request.job_id, &f.clock)
                .await
                .is_err(),
            "historical reader accepted contradictory committed count"
        );
        assert_eq!(std::fs::read(journal(&f, "attempt")).unwrap(), changed);
    }
}
