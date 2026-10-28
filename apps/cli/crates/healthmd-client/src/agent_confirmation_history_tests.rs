//! Restart inspection preserves historical source facts; it never grants active ownership.
use super::*;
use crate::agent_host::output::OutputAdmission;
use accepted_recovery_tests::inventory;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Case {
    Exact,
    ExpiredNow,
    RevokedGrant,
    Pending,
    MissingAttempt,
    MissingLock,
    UnknownField,
    ExplicitNull,
    DuplicateField,
    WrongMacDomain,
    WrongHost,
    WrongJob,
    WrongRequest,
    WrongApprovalAuthority,
    WrongCancel,
    NoSourceAck,
    PendingSource,
    RenewedExpiry,
    BeforeStart,
    FutureObservation,
    ObservationAtExpiry,
    ActiveOwner,
    LaterOutput,
    Symlink,
    PublicFile,
    KeyRemovedAtFinal,
    KeyRotatedAtFinal,
    CorruptAtFinal,
    DeleteAtFinal,
    LockReplacedAtFinal,
    ClockRollbackAtFinal,
}
impl Case {
    fn succeeds(self) -> bool {
        matches!(self, Self::Exact | Self::ExpiredNow | Self::RevokedGrant)
    }
}
struct HistoryKey {
    key: Arc<MutableOutputKey>,
    remaining: AtomicUsize,
    action: Mutex<Option<Box<dyn FnOnce() + Send>>>,
}
#[async_trait::async_trait]
impl crate::agent_host::ProtectedHostKey for HistoryKey {
    async fn load_existing(
        &self,
        host: &ControlUuid,
    ) -> Result<crate::agent_host::ProtectedHostSecret, ClientError> {
        if self
            .remaining
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            == Ok(1)
        {
            self.action.lock().unwrap().take().unwrap()();
        }
        crate::agent_host::ProtectedHostKey::load_existing(self.key.as_ref(), host).await
    }
}
fn rewrite(path: &std::path::Path, change: impl FnOnce(&mut serde_json::Value)) {
    let mut value: serde_json::Value =
        serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    change(&mut value["attempt"]);
    let domain = if value["attempt"]["schema_version"] == 3 {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v3\0"
    } else {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v4\0"
    };
    let mut mac = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
    mac.update(domain);
    mac.update(&canonical_json(&value["attempt"]).unwrap());
    value["mac"] = format!("{:x}", mac.finalize().into_bytes()).into();
    std::fs::write(path, canonical_json(&value).unwrap()).unwrap();
}
#[allow(clippy::too_many_lines)]
async fn check(platform: PeerPlatform, case: Case) {
    let AcceptedFixture {
        _temporary,
        client,
        peer,
        store,
        output,
        clock,
        request,
        accepted,
        ..
    } = Box::pin(accepted_fixture(platform)).await;
    let clock = Arc::new(clock);
    let raw_key = Arc::new(MutableOutputKey(AtomicUsize::new(0)));
    let key = Arc::new(HistoryKey {
        key: raw_key.clone(),
        remaining: AtomicUsize::new(0),
        action: Mutex::new(None),
    });
    let issuer = client.layout.root.join("agent-host-v1");
    drop(store);
    let store = crate::agent_host::HostAuthorityStore::open_existing(
        issuer.clone(),
        peer.host_installation_id,
        key.clone(),
    )
    .await
    .unwrap();
    let mut admission = OutputAdmission::reserve(&store, &request, clock.as_ref(), || async {
        Ok(output.clone())
    })
    .await
    .unwrap();
    admission
        .persist_accepted(&accepted, clock.as_ref(), || async { Ok(output.clone()) })
        .await
        .unwrap();
    admission
        .persist_cancellation(clock.as_ref(), || async { Ok(()) })
        .await
        .unwrap();
    clock.advance_to(1);
    let mut receipt = accepted.clone();
    receipt.status = ExecutionReceiptStatus::Cancelled;
    receipt.source_acknowledged = true;
    admission
        .persist_source_confirmation(
            &receipt,
            clock.as_ref(),
            &CancellationToken::new(),
            || async { Ok(()) },
        )
        .await
        .unwrap();
    let held = if case == Case::ActiveOwner {
        Some(admission)
    } else {
        drop(admission);
        None
    };
    let path = issuer.join(format!("attempt-{}.json", request.job_id.0));
    match case {
        Case::ExpiredNow => clock.advance_to(604_801),
        Case::RevokedGrant => store
            .revoke_local(
                store.revision().await.unwrap(),
                &request.plan.authority_references.host.authority_id,
            )
            .await
            .unwrap(),
        Case::Pending => rewrite(&path, |v| {
            v["schema_version"] = 3.into();
            let o = v.as_object_mut().unwrap();
            o.remove("source_receipt");
            o.remove("source_confirmed_at");
        }),
        Case::MissingAttempt => std::fs::remove_file(&path).unwrap(),
        Case::MissingLock => std::fs::remove_file(issuer.join("outputs.lock")).unwrap(),
        Case::UnknownField => rewrite(&path, |v| v["unknown"] = true.into()),
        Case::ExplicitNull => rewrite(&path, |v| {
            v["source_confirmed_at"] = serde_json::Value::Null;
        }),
        Case::DuplicateField => {
            let s = String::from_utf8(std::fs::read(&path).unwrap()).unwrap();
            std::fs::write(
                &path,
                s.replacen(
                    "\"schema_version\":4",
                    "\"schema_version\":4,\"schema_version\":4",
                    1,
                ),
            )
            .unwrap();
        }
        Case::WrongMacDomain => {
            let mut v: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
            let mut mac = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
            mac.update(b"HealthMd.AgentBridge.HostExecutionAttempt.v3\0");
            mac.update(&canonical_json(&v["attempt"]).unwrap());
            v["mac"] = format!("{:x}", mac.finalize().into_bytes()).into();
            std::fs::write(&path, canonical_json(&v).unwrap()).unwrap();
        }
        Case::WrongHost => rewrite(&path, |v| v["host"] = serde_json::to_value(id(99)).unwrap()),
        Case::WrongJob => rewrite(&path, |v| {
            v["request"]["job_id"] = serde_json::to_value(id(99)).unwrap();
        }),
        Case::WrongRequest => rewrite(&path, |v| v["request_sha256"] = "f".repeat(64).into()),
        Case::WrongApprovalAuthority => rewrite(&path, |v| {
            v["request"]["approval"]["authority_id"] = serde_json::to_value(id(99)).unwrap();
            let r: ExecuteRequest = serde_json::from_value(v["request"].clone()).unwrap();
            let sha = serde_json::to_value(document_digest(&r).unwrap()).unwrap();
            for name in ["accepted_receipt", "source_receipt", "cancellation_request"] {
                v[name]["request_sha256"] = sha.clone();
            }
            v["request_sha256"] = sha;
        }),
        Case::WrongCancel => rewrite(&path, |v| {
            v["cancellation_request"]["approval_id"] = serde_json::to_value(id(99)).unwrap();
        }),
        Case::NoSourceAck => rewrite(&path, |v| {
            v["source_receipt"]["source_acknowledged"] = false.into();
        }),
        Case::PendingSource => rewrite(&path, |v| {
            v["source_receipt"]["status"] = "cancellation_pending".into();
        }),
        Case::RenewedExpiry => rewrite(&path, |v| {
            v["source_receipt"]["expires_at"] =
                serde_json::to_value(later(&accepted.expires_at, 1)).unwrap();
        }),
        Case::BeforeStart => rewrite(&path, |v| {
            v["started_at"] = serde_json::to_value(later(&now(), 2)).unwrap();
        }),
        Case::FutureObservation => rewrite(&path, |v| {
            v["source_confirmed_at"] = serde_json::to_value(later(&now(), 2)).unwrap();
        }),
        Case::ObservationAtExpiry => {
            rewrite(&path, |v| {
                v["source_confirmed_at"] = serde_json::to_value(&accepted.expires_at).unwrap();
            });
            clock.advance_to(604_800);
        }
        Case::LaterOutput => std::fs::write(
            issuer.join(format!("output-{}.json", request.job_id.0)),
            b"synthetic conflicting later state",
        )
        .unwrap(),
        Case::Symlink => {
            std::fs::remove_file(&path).unwrap();
            let target = client.layout.root.join("sentinel");
            std::fs::write(&target, b"unchanged").unwrap();
            std::os::unix::fs::symlink(target, &path).unwrap();
        }
        Case::PublicFile => {
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        }
        _ => {}
    }
    let final_callback = matches!(
        case,
        Case::KeyRemovedAtFinal
            | Case::KeyRotatedAtFinal
            | Case::CorruptAtFinal
            | Case::DeleteAtFinal
            | Case::LockReplacedAtFinal
            | Case::ClockRollbackAtFinal
    );
    if final_callback {
        let change = path.clone();
        let lock = issuer.join("outputs.lock");
        let changing_key = raw_key.clone();
        let changing_clock = clock.clone();
        *key.action.lock().unwrap() = Some(Box::new(move || match case {
            Case::KeyRemovedAtFinal => changing_key.0.store(1, Ordering::SeqCst),
            Case::KeyRotatedAtFinal => changing_key.0.store(2, Ordering::SeqCst),
            Case::CorruptAtFinal => {
                std::fs::write(change, b"synthetic corrupt historical proof").unwrap();
            }
            Case::DeleteAtFinal => std::fs::remove_file(change).unwrap(),
            Case::LockReplacedAtFinal => {
                std::fs::remove_file(&lock).unwrap();
                std::fs::OpenOptions::new()
                    .create_new(true)
                    .write(true)
                    .mode(0o600)
                    .open(lock)
                    .unwrap();
            }
            _ => changing_clock.advance_to(0),
        }));
        key.remaining.store(2, Ordering::SeqCst);
    }
    let before = inventory(&issuer);
    let result = store
        .retained_source_stop_confirmation(&request.job_id, clock.as_ref())
        .await;
    if case.succeeds() {
        assert_eq!(result.unwrap().receipt(), &receipt);
    } else {
        assert!(result.is_err(), "{case:?}");
    }
    if final_callback {
        assert!(key.action.lock().unwrap().is_none(), "{case:?}");
    }
    match case {
        Case::CorruptAtFinal => assert_eq!(
            std::fs::read(&path).unwrap(),
            b"synthetic corrupt historical proof"
        ),
        Case::DeleteAtFinal => assert!(!path.exists()),
        _ => assert_eq!(
            inventory(&issuer),
            before,
            "inspection must be read-only: {case:?}"
        ),
    }
    assert!(std::fs::read_dir(&output).unwrap().next().is_none());
    drop(held);
}
#[tokio::test]
async fn historical_source_confirmation_survives_restart_expiry_and_revoked_export_permission() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [Case::Exact, Case::ExpiredNow, Case::RevokedGrant] {
            Box::pin(check(platform, case)).await;
        }
    }
}
#[tokio::test]
async fn historical_source_confirmation_rejects_missing_pending_forged_or_conflicting_evidence_without_repair()
 {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::Pending,
            Case::MissingAttempt,
            Case::MissingLock,
            Case::UnknownField,
            Case::ExplicitNull,
            Case::DuplicateField,
            Case::WrongMacDomain,
            Case::WrongHost,
            Case::WrongJob,
            Case::WrongRequest,
            Case::WrongApprovalAuthority,
            Case::WrongCancel,
            Case::NoSourceAck,
            Case::PendingSource,
            Case::RenewedExpiry,
            Case::BeforeStart,
            Case::FutureObservation,
            Case::ObservationAtExpiry,
            Case::ActiveOwner,
            Case::LaterOutput,
            Case::Symlink,
            Case::PublicFile,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}
#[tokio::test]
async fn historical_source_confirmation_rechecks_key_time_lock_and_exact_bytes_after_final_key_callback()
 {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::KeyRemovedAtFinal,
            Case::KeyRotatedAtFinal,
            Case::CorruptAtFinal,
            Case::DeleteAtFinal,
            Case::LockReplacedAtFinal,
            Case::ClockRollbackAtFinal,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}
