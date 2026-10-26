//! Source receipt facts only: no host destination success or new capture permission.
use super::*;
use crate::agent_host::output::OutputAdmission;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Case {
    Cancelled,
    Complete,
    CompleteEmpty,
    Partial,
    NoAck,
    PendingStatus,
    PartialNoAck,
    PausedWithAck,
    FailedWithAck,
    WrongJob,
    WrongScope,
    WrongRequest,
    RenewedExpiry,
    MissingManifest,
    MissingFrontier,
    CompletionWithoutManifest,
    UnsolicitedManifest,
    JournalCorrupt,
    JournalDelete,
    ExpiredAtFinalFence,
    CancelledDuringPublicationKeyRead,
}
impl Case {
    fn succeeds(self) -> bool {
        matches!(
            self,
            Self::Cancelled | Self::Complete | Self::CompleteEmpty | Self::Partial
        )
    }
}
// Simulate local cancellation during the final asynchronous protected-key callback.
struct CancellingConfirmationKey {
    remaining: AtomicUsize,
    cancellation: CancellationToken,
}
#[async_trait::async_trait]
impl crate::agent_host::ProtectedHostKey for CancellingConfirmationKey {
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
#[allow(clippy::too_many_lines)]
async fn check(platform: PeerPlatform, case: Case) {
    let AcceptedFixture {
        _temporary,
        client,
        saved,
        peer,
        store,
        output,
        clock,
        request,
        accepted,
    } = Box::pin(accepted_fixture(platform)).await;
    let clock = Arc::new(clock);
    let cancellation = CancellationToken::new();
    let cancelling_key = Arc::new(CancellingConfirmationKey {
        remaining: AtomicUsize::new(0),
        cancellation: cancellation.clone(),
    });
    let store = if case == Case::CancelledDuringPublicationKeyRead {
        crate::agent_host::HostAuthorityStore::open_existing(
            client.layout.root.join("agent-host-v1"),
            peer.host_installation_id.clone(),
            cancelling_key.clone(),
        )
        .await
        .unwrap()
    } else {
        store
    };
    let mut admission = OutputAdmission::reserve(&store, &request, clock.as_ref(), || async {
        Ok(output.clone())
    })
    .await
    .unwrap();
    admission
        .persist_accepted(&accepted, clock.as_ref(), || async { Ok(output.clone()) })
        .await
        .unwrap();
    drop(admission);
    let path = client
        .layout
        .root
        .join("agent-host-v1")
        .join(format!("attempt-{}.json", request.job_id.0));
    let mut receipt = accepted.clone();
    receipt.source_acknowledged = true;
    receipt.status = ExecutionReceiptStatus::Cancelled;
    match case {
        Case::Complete => {
            receipt.status = ExecutionReceiptStatus::Complete;
            receipt.artifact_count = 2;
            receipt.committed_partition_count = 2;
            receipt.manifest_sha256 = Digest("a".repeat(64));
            receipt.frontier_sha256 = Digest("b".repeat(64));
        }
        Case::CompleteEmpty => {
            receipt.status = ExecutionReceiptStatus::CompleteEmpty;
            receipt.manifest_sha256 = Digest("a".repeat(64));
            receipt.frontier_sha256 = Digest("b".repeat(64));
        }
        Case::Partial => {
            receipt.status = ExecutionReceiptStatus::Partial;
            receipt.artifact_count = 2;
            receipt.manifest_sha256 = Digest("a".repeat(64));
            receipt.frontier_sha256 = Digest("b".repeat(64));
        }
        Case::NoAck => receipt.source_acknowledged = false,
        Case::PendingStatus => {
            receipt.status = ExecutionReceiptStatus::CancellationPending;
            receipt.source_acknowledged = false;
        }
        Case::PartialNoAck | Case::PausedWithAck | Case::FailedWithAck => {
            receipt.manifest_sha256 = Digest("a".repeat(64));
            receipt.frontier_sha256 = Digest("b".repeat(64));
            receipt.status = match case {
                Case::PartialNoAck => ExecutionReceiptStatus::Partial,
                Case::PausedWithAck => ExecutionReceiptStatus::Paused,
                _ => ExecutionReceiptStatus::Failed,
            };
            if case == Case::PartialNoAck {
                receipt.source_acknowledged = false;
            }
        }
        Case::WrongJob => receipt.job_id = id(99),
        Case::WrongScope => receipt.binding.plan_sha256 = Digest("f".repeat(64)),
        Case::WrongRequest => receipt.request_sha256 = Digest("f".repeat(64)),
        Case::RenewedExpiry => receipt.expires_at = later(&receipt.expires_at, 1),
        Case::MissingManifest => receipt.artifact_count = 1,
        Case::MissingFrontier => receipt.manifest_sha256 = Digest("a".repeat(64)),
        Case::CompletionWithoutManifest => receipt.status = ExecutionReceiptStatus::CompleteEmpty,
        _ => {}
    }
    let expected = receipt.clone();
    let source_request = request.clone();
    let source_peer = peer.clone();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let (release, wait) = oneshot::channel();
    let source = tokio::spawn(async move {
        let (mut channel, negotiation) = output_channel(port, saved, &source_peer, platform).await;
        let Message::CancelRequest(cancel) = channel.receive_v4(negotiation).await.unwrap().message
        else {
            panic!("Only original Stop permitted");
        };
        assert_eq!(cancel.job_id, source_request.job_id);
        assert_eq!(
            cancel.request_sha256,
            document_digest(&source_request).unwrap()
        );
        let message = if case == Case::UnsolicitedManifest {
            Message::ArtifactManifest(Box::new(
                synthetic_binding(&source_request, platform).manifest,
            ))
        } else {
            Message::ExecutionReceipt(Box::new(receipt))
        };
        // Keep authenticated framing but let the actual host reject semantically invalid receipts.
        channel
            .send_bridge_plaintext_guarded(
                &canonical_json(&Envelope::new(message)).unwrap(),
                || async { Ok(()) },
            )
            .await
            .unwrap();
        let _ = wait.await;
        assert!(
            tokio::time::timeout(Duration::from_millis(100), channel.receive_v4(negotiation))
                .await
                .is_err(),
            "Confirmation must not emit controls, ACKs or output commits"
        );
    });
    let adversarial = AdversarialOutputTrust::new(&client);
    let bridge = connect_bound_bridge(
        &client,
        Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
        &listener,
        Duration::from_secs(10),
        cancellation,
    )
    .await
    .unwrap();
    let mut bridge = bridge.with_test_trust(&adversarial);
    let pending = bridge
        .request_retained_accepted_cancellation(&store, &request.job_id, clock.as_ref())
        .await
        .unwrap();
    let before = std::fs::read(&path).unwrap();
    if matches!(
        case,
        Case::JournalCorrupt | Case::JournalDelete | Case::ExpiredAtFinalFence
    ) {
        let observe = path.clone();
        let change = path.clone();
        let advancing = clock.clone();
        adversarial.arm_when(
            move || {
                std::fs::read(&observe)
                    .ok()
                    .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
                    .is_some_and(|v| v["attempt"]["schema_version"] == 4)
            },
            move || match case {
                Case::JournalDelete => std::fs::remove_file(change).unwrap(),
                Case::JournalCorrupt => {
                    std::fs::write(change, b"synthetic corrupted source proof").unwrap();
                }
                _ => advancing.advance_to(604_800),
            },
        );
    }
    if case == Case::CancelledDuringPublicationKeyRead {
        // Before receive, after receive, before persistence, then final publication guard.
        cancelling_key.remaining.store(4, Ordering::SeqCst);
    }
    let result = pending.wait_source_confirmation().await;
    if case == Case::CancelledDuringPublicationKeyRead {
        assert!(cancelling_key.cancellation.is_cancelled());
        assert_eq!(cancelling_key.remaining.load(Ordering::SeqCst), 0);
    }
    if case.succeeds() {
        let confirmed = result.unwrap();
        assert_eq!(confirmed.receipt(), &expected);
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(value["attempt"]["schema_version"], 4);
        assert_eq!(
            value["attempt"]["source_receipt"],
            serde_json::to_value(&expected).unwrap()
        );
        assert_eq!(
            value["attempt"]["source_confirmed_at"],
            serde_json::to_value(now()).unwrap()
        );
        assert_eq!(
            value["attempt"]["started_at"],
            serde_json::to_value(now()).unwrap()
        );
        assert_eq!(
            value["attempt"]["accepted_receipt"],
            serde_json::to_value(&accepted).unwrap()
        );
        let mut mac = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
        mac.update(b"HealthMd.AgentBridge.HostExecutionAttempt.v4\0");
        mac.update(&canonical_json(&value["attempt"]).unwrap());
        assert_eq!(value["mac"], format!("{:x}", mac.finalize().into_bytes()));
        // Old pending recovery must not reinterpret source-confirmed metadata as another request.
        assert!(
            OutputAdmission::open_retained_accepted(&store, &request.job_id, clock.as_ref())
                .await
                .is_err()
        );
    } else {
        assert!(result.is_err(), "{case:?}");
        if matches!(
            case,
            Case::JournalCorrupt | Case::JournalDelete | Case::ExpiredAtFinalFence
        ) {
            assert!(adversarial.action.lock().unwrap().is_none());
            match case {
                Case::JournalDelete => assert!(!path.exists()),
                Case::JournalCorrupt => assert_eq!(
                    std::fs::read(&path).unwrap(),
                    b"synthetic corrupted source proof"
                ),
                _ => assert_eq!(
                    serde_json::from_slice::<serde_json::Value>(&std::fs::read(&path).unwrap())
                        .unwrap()["attempt"]["schema_version"],
                    4
                ),
            }
        } else {
            assert_eq!(std::fs::read(&path).unwrap(), before);
        }
    }
    assert!(std::fs::read_dir(&output).unwrap().next().is_none());
    let issuer = client.layout.root.join("agent-host-v1");
    for prefix in ["output", "transfer", "completion"] {
        assert!(
            !issuer
                .join(format!("{prefix}-{}.json", request.job_id.0))
                .exists()
        );
    }
    assert!(bridge.discover().await.is_err());
    let _ = release.send(());
    source.await.unwrap();
}
#[tokio::test]
async fn source_stop_confirmation_preserves_source_status_and_saves_bound_private_proof() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::Cancelled,
            Case::Complete,
            Case::CompleteEmpty,
            Case::Partial,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}
#[tokio::test]
async fn source_stop_confirmation_rejects_missing_ack_wrong_binding_status_expiry_or_unsolicited_data()
 {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::NoAck,
            Case::PendingStatus,
            Case::PartialNoAck,
            Case::PausedWithAck,
            Case::FailedWithAck,
            Case::WrongJob,
            Case::WrongScope,
            Case::WrongRequest,
            Case::RenewedExpiry,
            Case::MissingManifest,
            Case::MissingFrontier,
            Case::CompletionWithoutManifest,
            Case::UnsolicitedManifest,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}
#[tokio::test]
async fn source_stop_confirmation_rechecks_exact_evidence_and_expiry_after_final_callback() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::JournalCorrupt,
            Case::JournalDelete,
            Case::ExpiredAtFinalFence,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn source_stop_confirmation_cancellation_during_final_key_read_leaves_pending_evidence() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        Box::pin(check(platform, Case::CancelledDuringPublicationKeyRead)).await;
    }
}
