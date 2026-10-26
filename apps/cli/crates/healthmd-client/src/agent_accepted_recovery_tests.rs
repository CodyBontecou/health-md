//! Existing-only accepted journal recovery and exact encrypted Stop, never recapture.
use super::*;
use crate::agent_host::output::OutputAdmission;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Case {
    Accepted,
    Pending,
    PendingFullEntries,
    FullEntries,
    RoomForTemporary,
    PlanExpired,
    RevokedGrant,
    PreSend,
    MissingAttempt,
    MissingLock,
    UnknownField,
    NullOptional,
    WrongMac,
    WrongHost,
    WrongApprovalBinding,
    WrongApprovalAuthority,
    WrongCancel,
    DuplicateField,
    Expired,
    ActiveOwner,
    LaterOutput,
    Symlink,
}
impl Case {
    fn sends(self) -> bool {
        matches!(
            self,
            Self::Accepted
                | Self::Pending
                | Self::PendingFullEntries
                | Self::RoomForTemporary
                | Self::PlanExpired
                | Self::RevokedGrant
        )
    }
}
pub(super) fn inventory(path: &std::path::Path) -> BTreeMap<String, Vec<u8>> {
    std::fs::read_dir(path)
        .unwrap()
        .map(|entry| {
            let entry = entry.unwrap();
            let bytes = if entry.file_type().unwrap().is_symlink() {
                b"symlink".to_vec()
            } else {
                std::fs::read(entry.path()).unwrap()
            };
            (entry.file_name().to_str().unwrap().to_owned(), bytes)
        })
        .collect()
}
fn rewrite(path: &std::path::Path, change: impl FnOnce(&mut serde_json::Value)) {
    let mut value: serde_json::Value =
        serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    change(&mut value["attempt"]);
    let mut mac = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
    mac.update(if value["attempt"]["schema_version"] == 3 {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v3\0"
    } else {
        b"HealthMd.AgentBridge.HostExecutionAttempt.v2\0"
    });
    mac.update(&canonical_json(&value["attempt"]).unwrap());
    value["mac"] = format!("{:x}", mac.finalize().into_bytes()).into();
    std::fs::write(path, canonical_json(&value).unwrap()).unwrap();
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
    let mut admission =
        OutputAdmission::reserve(&store, &request, &clock, || async { Ok(output.clone()) })
            .await
            .unwrap();
    if case != Case::PreSend {
        admission
            .persist_accepted(&accepted, &clock, || async { Ok(output.clone()) })
            .await
            .unwrap();
    }
    if matches!(
        case,
        Case::Pending | Case::PendingFullEntries | Case::WrongCancel
    ) {
        admission
            .persist_cancellation(&clock, || async { Ok(()) })
            .await
            .unwrap();
    }
    let held = if case == Case::ActiveOwner {
        Some(admission)
    } else {
        drop(admission);
        None
    };
    let issuer = client.layout.root.join("agent-host-v1");
    let name = format!("attempt-{}.json", request.job_id.0);
    let path = issuer.join(&name);
    match case {
        Case::PlanExpired => clock.advance_to(301),
        Case::RevokedGrant => store
            .revoke_local(
                store.revision().await.unwrap(),
                &request.plan.authority_references.host.authority_id,
            )
            .await
            .unwrap(),
        Case::MissingAttempt => std::fs::remove_file(&path).unwrap(),
        Case::MissingLock => std::fs::remove_file(issuer.join("outputs.lock")).unwrap(),
        Case::UnknownField => rewrite(&path, |v| v["unknown"] = true.into()),
        Case::NullOptional => rewrite(&path, |v| {
            v["cancellation_request"] = serde_json::Value::Null;
        }),
        Case::WrongMac => {
            let mut value: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
            value["mac"] = "0".repeat(64).into();
            std::fs::write(&path, canonical_json(&value).unwrap()).unwrap();
        }
        Case::WrongHost => rewrite(&path, |v| v["host"] = serde_json::to_value(id(99)).unwrap()),
        Case::WrongApprovalBinding | Case::WrongApprovalAuthority => rewrite(&path, |v| {
            if case == Case::WrongApprovalBinding {
                v["request"]["approval"]["binding"]["plan_sha256"] = "0".repeat(64).into();
            } else {
                v["request"]["approval"]["authority_id"] = serde_json::to_value(id(99)).unwrap();
            }
            let changed: ExecuteRequest = serde_json::from_value(v["request"].clone()).unwrap();
            let sha = serde_json::to_value(document_digest(&changed).unwrap()).unwrap();
            v["request_sha256"] = sha.clone();
            v["accepted_receipt"]["request_sha256"] = sha;
        }),
        Case::WrongCancel => rewrite(&path, |v| {
            v["cancellation_request"]["approval_id"] = serde_json::to_value(id(99)).unwrap();
        }),
        Case::DuplicateField => {
            let value = String::from_utf8(std::fs::read(&path).unwrap()).unwrap();
            std::fs::write(
                &path,
                value.replacen(
                    "\"schema_version\":2",
                    "\"schema_version\":2,\"schema_version\":2",
                    1,
                ),
            )
            .unwrap();
        }
        Case::Expired => clock.advance_to(604_800),
        Case::LaterOutput => std::fs::write(
            issuer.join(format!("output-{}.json", request.job_id.0)),
            b"synthetic later output state",
        )
        .unwrap(),
        Case::Symlink => {
            std::fs::remove_file(&path).unwrap();
            let target = client.layout.root.join("synthetic-sentinel");
            std::fs::write(&target, b"unchanged").unwrap();
            std::os::unix::fs::symlink(target, &path).unwrap();
        }
        _ => {}
    }
    if matches!(
        case,
        Case::FullEntries | Case::PendingFullEntries | Case::RoomForTemporary
    ) {
        let limit = if case == Case::RoomForTemporary {
            8191
        } else {
            8192
        };
        let count = std::fs::read_dir(&issuer).unwrap().count();
        for index in count..limit {
            std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(issuer.join(format!("retained-quota-{index}")))
                .unwrap();
        }
        assert_eq!(std::fs::read_dir(&issuer).unwrap().count(), limit);
    }
    let before = inventory(&issuer);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let (release, wait) = oneshot::channel();
    let expected = request.clone();
    let source_peer = peer.clone();
    let source = tokio::spawn(async move {
        let (mut channel, negotiation) = output_channel(port, saved, &source_peer, platform).await;
        if case.sends() {
            let Message::CancelRequest(cancel) =
                channel.receive_v4(negotiation).await.unwrap().message
            else {
                panic!("Recovery may send only exact Cancel, never Execute/Resume/planning");
            };
            assert_eq!(cancel.job_id, expected.job_id);
            assert_eq!(cancel.peer, expected.plan.intent.peer);
            assert_eq!(cancel.approval_id, expected.approval.approval_id);
            assert_eq!(cancel.authority_id, expected.approval.authority_id);
            assert_eq!(cancel.request_sha256, document_digest(&expected).unwrap());
            let _ = wait.await;
        } else {
            tokio::select! {biased;
                packet=channel.receive_v4(negotiation)=>panic!("Invalid retained evidence sent a frame: {}",packet.is_ok()),
                _=wait=>{}
            }
        }
        assert!(
            tokio::time::timeout(Duration::from_millis(100), channel.receive_v4(negotiation))
                .await
                .is_err(),
            "Recovery must send no extra frames"
        );
    });
    let mut bridge = connect_bound_bridge(
        &client,
        Some(Uuid::parse_str(&peer.source_installation_id.0).unwrap()),
        &listener,
        Duration::from_secs(10),
        CancellationToken::new(),
    )
    .await
    .unwrap();
    let result = bridge
        .request_retained_accepted_cancellation(&store, &request.job_id, &clock)
        .await;
    if case.sends() {
        let pending = result.unwrap();
        assert_eq!(pending.acceptance(), &accepted);
        assert_eq!(pending.request().job_id, request.job_id);
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(value["attempt"]["schema_version"], 3);
        assert_eq!(
            value["attempt"]["started_at"],
            serde_json::to_value(now()).unwrap()
        );
        drop(pending);
    } else {
        assert!(result.is_err(), "{case:?}");
    }
    let after = inventory(&issuer);
    for (key, value) in &before {
        if key != &name || !case.sends() || matches!(case, Case::Pending | Case::PendingFullEntries)
        {
            assert_eq!(after.get(key), Some(value), "{case:?}/{key}");
        }
    }
    assert_eq!(
        after.keys().collect::<Vec<_>>(),
        before.keys().collect::<Vec<_>>()
    );
    if case == Case::Symlink {
        assert_eq!(
            std::fs::read(client.layout.root.join("synthetic-sentinel")).unwrap(),
            b"unchanged"
        );
    }
    assert!(std::fs::read_dir(&output).unwrap().next().is_none());
    assert!(bridge.discover().await.is_err());
    let _ = release.send(());
    source.await.unwrap();
    drop(held);
}
#[tokio::test]
async fn retained_accepted_stop_uses_original_scope_and_pending_replay_without_execute() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::Accepted,
            Case::Pending,
            Case::PlanExpired,
            Case::RevokedGrant,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}
#[tokio::test]
async fn retained_accepted_stop_rejects_missing_ambiguous_changed_or_unaccepted_evidence_without_repair()
 {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::PreSend,
            Case::MissingAttempt,
            Case::MissingLock,
            Case::UnknownField,
            Case::NullOptional,
            Case::WrongMac,
            Case::WrongHost,
            Case::WrongApprovalBinding,
            Case::WrongApprovalAuthority,
            Case::WrongCancel,
            Case::DuplicateField,
            Case::Expired,
            Case::ActiveOwner,
            Case::LaterOutput,
            Case::Symlink,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}

#[tokio::test]
async fn retained_accepted_stop_reserves_publication_slot_but_pending_replay_needs_none() {
    for platform in [PeerPlatform::Ios, PeerPlatform::Android] {
        for case in [
            Case::FullEntries,
            Case::PendingFullEntries,
            Case::RoomForTemporary,
        ] {
            Box::pin(check(platform, case)).await;
        }
    }
}
