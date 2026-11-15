//! Original signed uncertainty can request Stop; only native facts can confirm it.
use super::*;

#[tokio::test]
async fn uncertain_stop_requires_exact_encrypted_native_ack_and_preserves_offline_history() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for mode in [
            "current",
            "revoked_grant",
            "missing_destination",
            "expired_plan",
            "completed_before_stop",
            "wrong_job",
            "accepted_only",
            "renewed",
            "expired_receipt",
        ] {
            let f = uncertain_stop_fixture(platform, mode).await;
            let receipt = uncertain_stop_receipt(&f.request, &f.accepted, &f.clock, mode);
            let valid = matches!(
                mode,
                "current"
                    | "revoked_grant"
                    | "missing_destination"
                    | "expired_plan"
                    | "completed_before_stop"
            );
            let expected_receipt = receipt.clone();
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let port = listener.local_addr().unwrap().port();
            let expected = f.request.clone();
            let source_peer = f.peer.clone();
            let source =
                reply_to_uncertain_stop(port, f.saved, source_peer, platform, expected, receipt);
            let planner = HostPlanner::new(f.store.clone());
            let job = &f.request.job_id;
            assert_pending_uncertain_stop(&planner, &f.peer, job, &f.clock).await;
            let issuer = f.client.layout.root.join("agent-host-v1");
            let path = issuer.join(format!("attempt-{}.json", job.0));
            let pending = std::fs::read(&path).unwrap();
            // A repeated request preserves the original pending bytes, with no live export check.
            assert_pending_uncertain_stop(&planner, &f.peer, job, &f.clock).await;
            assert_eq!(std::fs::read(&path).unwrap(), pending);
            let mut bridge = connect_bound_bridge(
                &f.client,
                Some(Uuid::parse_str(&f.peer.source_installation_id.0).unwrap()),
                &listener,
                Duration::from_secs(10),
                CancellationToken::new(),
            )
            .await
            .unwrap();
            let result = planner.cancel_retained(&mut bridge, job, &f.clock).await;
            assert_eq!(result.is_ok(), valid, "{platform:?}/{mode}");
            source.await.unwrap();
            if valid {
                assert_eq!(result.unwrap().receipt(), &expected_receipt);
                assert_uncertain_stop_history(
                    &planner,
                    &f.peer,
                    &f.clock,
                    job,
                    &expected_receipt,
                    &path,
                )
                .await;
            } else {
                assert_eq!(
                    std::fs::read(&path).unwrap(),
                    pending,
                    "Forged proof must preserve pending uncertainty"
                );
            }
            assert!(
                OutputAdmission::open_retained_accepted(&f.store, job, &f.clock)
                    .await
                    .is_err()
            );
            assert!(
                OutputAdmission::open_retained_for_resume(&f.store, job, &f.clock)
                    .await
                    .is_err()
            );
            if mode == "missing_destination" {
                assert!(!f.output.exists());
            } else {
                assert_eq!(std::fs::read_dir(&f.output).unwrap().count(), 0);
            }
        }
    }
}

async fn assert_pending_uncertain_stop(
    planner: &HostPlanner,
    peer: &Peer,
    job: &ControlUuid,
    clock: &AdvancingClock,
) {
    assert!(
        planner
            .prepare_retained_cancellation(peer, job, clock, &CancellationToken::new(), || async {
                Ok(())
            })
            .await
            .unwrap()
            .is_none()
    );
}

async fn uncertain_stop_fixture(platform: PeerPlatform, mode: &str) -> AcceptedFixture {
    let f = Box::pin(accepted_fixture(platform)).await;
    let admission = OutputAdmission::reserve(&f.store, &f.request, &f.clock, || async {
        Ok(f.output.clone())
    })
    .await
    .unwrap();
    drop(admission);
    match mode {
        "revoked_grant" => f
            .store
            .revoke_local(
                f.store.revision().await.unwrap(),
                &f.request.plan.authority_references.host.authority_id,
            )
            .await
            .unwrap(),
        "missing_destination" => std::fs::remove_dir(&f.output).unwrap(),
        "expired_plan" => f.clock.advance_to(301),
        _ => {}
    }
    f
}

fn uncertain_stop_receipt(
    request: &ExecuteRequest,
    accepted: &ExecutionReceipt,
    clock: &AdvancingClock,
    mode: &str,
) -> ExecutionReceipt {
    let mut receipt = accepted.clone();
    receipt.status = ExecutionReceiptStatus::Cancelled;
    receipt.source_acknowledged = true;
    match mode {
        "completed_before_stop" => {
            receipt.status = ExecutionReceiptStatus::CompleteEmpty;
            receipt.manifest_sha256 = Digest("1".repeat(64));
            receipt.frontier_sha256 = Digest("2".repeat(64));
        }
        "wrong_job" => receipt.job_id = id(99),
        "accepted_only" => {
            receipt.status = ExecutionReceiptStatus::Accepted;
            receipt.source_acknowledged = false;
        }
        "renewed" => {
            receipt.expires_at = UtcTimestamp(
                chrono::DateTime::from_timestamp(
                    request.plan.expires_at.seconds().unwrap() + 604_801,
                    0,
                )
                .unwrap()
                .to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
            );
        }
        "expired_receipt" => receipt.expires_at = clock.now(),
        _ => {}
    }
    receipt
}

fn reply_to_uncertain_stop(
    port: u16,
    saved: FakeMobileTrust,
    source_peer: Peer,
    platform: PeerPlatform,
    expected: ExecuteRequest,
    receipt: ExecutionReceipt,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let (mut channel, negotiation) = output_channel(port, saved, &source_peer, platform).await;
        let Message::CancelRequest(cancel) = channel.receive_v4(negotiation).await.unwrap().message
        else {
            panic!("Uncertainty may send exact Cancel only; never Execute/Resume or planning");
        };
        assert_eq!(cancel.job_id, expected.job_id);
        assert_eq!(cancel.peer, expected.plan.intent.peer);
        assert_eq!(cancel.approval_id, expected.approval.approval_id);
        assert_eq!(cancel.authority_id, expected.approval.authority_id);
        assert_eq!(cancel.request_sha256, document_digest(&expected).unwrap());
        channel
            .send_v4(
                &Envelope::new(Message::ExecutionReceipt(Box::new(receipt))),
                negotiation,
            )
            .await
            .unwrap();
        assert!(
            tokio::time::timeout(Duration::from_millis(100), channel.receive_v4(negotiation))
                .await
                .is_err(),
            "No extra request or recapture"
        );
    })
}

async fn assert_uncertain_stop_history(
    planner: &HostPlanner,
    peer: &Peer,
    clock: &AdvancingClock,
    job: &ControlUuid,
    expected_receipt: &ExecutionReceipt,
    path: &std::path::Path,
) {
    let confirmed = std::fs::read(path).unwrap();
    let value: serde_json::Value = serde_json::from_slice(&confirmed).unwrap();
    assert_eq!(value["attempt"]["schema_version"], 10);
    assert!(value["attempt"].get("accepted_receipt").is_none());
    clock.advance_to(604_801);
    let historical = planner
        .prepare_retained_cancellation(peer, job, clock, &CancellationToken::new(), || async {
            Ok(())
        })
        .await
        .unwrap()
        .unwrap();
    assert_eq!(historical.receipt(), expected_receipt);
    assert_eq!(std::fs::read(path).unwrap(), confirmed);
}

struct StopCallbackClock {
    time: UtcTimestamp,
    calls: AtomicUsize,
    trigger: usize,
    cancellation: CancellationToken,
    replace: Option<std::path::PathBuf>,
}
impl crate::agent_planning::PlanningClock for StopCallbackClock {
    fn now(&self) -> UtcTimestamp {
        if self.calls.fetch_add(1, Ordering::SeqCst) + 1 == self.trigger {
            if let Some(path) = &self.replace {
                std::fs::write(path, b"synthetic-final-clock-replacement").unwrap();
            } else {
                self.cancellation.cancel();
            }
        }
        self.time.clone()
    }
}

#[tokio::test]
async fn uncertain_stop_review_preparation_callbacks_preserve_original_intent() {
    use crate::agent_host::output::UncertainStop;
    let mut outcomes = Vec::new();
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for mode in ["key_in_fence", "cancel_in_clock"] {
            let f = Box::pin(accepted_fixture(platform)).await;
            drop(
                OutputAdmission::reserve(&f.store, &f.request, &f.clock, || async {
                    Ok(f.output.clone())
                })
                .await
                .unwrap(),
            );
            let path = f.client.layout.root.join("agent-host-v1");
            let key = Arc::new(MutableOutputKey(AtomicUsize::new(0)));
            let store = crate::agent_host::HostAuthorityStore::open_existing(
                path.clone(),
                f.peer.host_installation_id.clone(),
                key.clone(),
            )
            .await
            .unwrap();
            let before = inventory(&path);
            let token = CancellationToken::new();
            let clock = StopCallbackClock {
                time: f.clock.now(),
                calls: AtomicUsize::new(0),
                trigger: if mode == "cancel_in_clock" {
                    5
                } else {
                    usize::MAX
                },
                cancellation: token.clone(),
                replace: None,
            };
            let fences = AtomicUsize::new(0);
            let result = UncertainStop::prepare(
                &store,
                &f.peer,
                &f.request.job_id,
                &clock,
                &token,
                || async {
                    if fences.fetch_add(1, Ordering::SeqCst) + 1 == 2 && mode == "key_in_fence" {
                        key.0.store(2, Ordering::SeqCst);
                    }
                    if token.is_cancelled() {
                        return Err(ClientError::WaitCancelled);
                    }
                    Ok(())
                },
            )
            .await;
            let rejected = result.is_err();
            drop(result);
            outcomes.push((
                format!("{platform:?}/{mode}"),
                rejected && inventory(&path) == before,
            ));
        }
    }
    assert!(
        outcomes.iter().all(|(_, ok)| *ok),
        "Final callback must not publish pending Stop: {outcomes:?}"
    );
}

#[tokio::test]
async fn uncertain_stop_review_confirmation_preserves_final_clock_replacement() {
    use crate::agent_host::output::UncertainStop;
    let mut outcomes = Vec::new();
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        let f = Box::pin(accepted_fixture(platform)).await;
        drop(
            OutputAdmission::reserve(&f.store, &f.request, &f.clock, || async {
                Ok(f.output.clone())
            })
            .await
            .unwrap(),
        );
        let token = CancellationToken::new();
        let mut owner = UncertainStop::prepare(
            &f.store,
            &f.peer,
            &f.request.job_id,
            &f.clock,
            &token,
            || async { Ok(()) },
        )
        .await
        .unwrap();
        let path = f
            .client
            .layout
            .root
            .join("agent-host-v1")
            .join(format!("attempt-{}.json", f.request.job_id.0));
        let clock = StopCallbackClock {
            time: f.clock.now(),
            calls: AtomicUsize::new(0),
            trigger: 6,
            cancellation: token.clone(),
            replace: Some(path.clone()),
        };
        let mut receipt = f.accepted.clone();
        receipt.status = ExecutionReceiptStatus::Cancelled;
        receipt.source_acknowledged = true;
        let result = owner
            .confirm(&receipt, &clock, &token, || async { Ok(()) })
            .await;
        drop(owner);
        outcomes.push((
            platform,
            result.is_err() && std::fs::read(path).unwrap() == b"synthetic-final-clock-replacement",
        ));
    }
    assert!(
        outcomes.iter().all(|(_, ok)| *ok),
        "Final clock mutation must survive rejected confirmation: {outcomes:?}"
    );
}
