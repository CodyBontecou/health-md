//! Hermetic retained-prefix recovery controls; independent synthetic native metadata only.
use super::*;
use crate::agent_planning::HostPlanner;
use crate::agent_test_support as support;
use healthmd_protocol::v4::PeerPlatform;
use healthmd_protocol::v4::*;

fn uuid(number: u64) -> ControlUuid {
    ControlUuid(format!("00000000-0000-4000-8000-{number:012x}"))
}
async fn request() -> (
    tempfile::TempDir,
    crate::agent_host::HostAuthorityStore,
    PathBuf,
    ExecuteRequest,
) {
    let temporary = tempfile::TempDir::new().unwrap();
    let peer = support::peer(PeerPlatform::Android);
    let (store, output) = support::enroll(temporary.path(), &peer, &support::now()).await;
    let planner = HostPlanner::new(store.clone());
    let plan = planner
        .plan(
            &mut support::NativeFake::new(peer.clone(), support::now()),
            support::input(&peer),
            &support::FixedClock(support::now()),
        )
        .await
        .unwrap();
    let request = ExecuteRequest {
        schema: ExecuteRequestSchema::HealthmdAgentExecuteRequest,
        schema_version: 1,
        approval: Approval {
            schema: ApprovalSchema::HealthmdAgentApproval,
            schema_version: 1,
            approval_id: uuid(700),
            authority_id: uuid(4),
            approved_at: support::now(),
            binding: approval_binding(&plan),
            rights: vec![ApprovalRightsItem::ExportExecute],
        },
        plan,
        job_id: uuid(701),
        request_id: uuid(702),
        idempotency_key: uuid(703),
    };
    (temporary, store, output, request)
}
fn native_binding(request: ExecuteRequest) -> NativeBinding {
    let accepted = ExecutionReceipt {
        schema: ExecutionReceiptSchema::HealthmdAgentExecutionReceipt,
        schema_version: 1,
        job_id: request.job_id.clone(),
        binding: approval_binding(&request.plan),
        request_sha256: document_digest(&request).unwrap(),
        manifest_sha256: Digest("0".repeat(64)),
        frontier_sha256: Digest("0".repeat(64)),
        artifact_count: 0,
        committed_partition_count: 0,
        source_acknowledged: false,
        status: ExecutionReceiptStatus::Accepted,
        expires_at: support::later(&support::now(), 604_800),
    };
    let manifest = ArtifactManifest {
        schema: ArtifactManifestSchema::HealthmdAgentArtifactManifest,
        schema_version: 1,
        job_id: request.job_id.clone(),
        binding: accepted.binding.clone(),
        request_sha256: accepted.request_sha256.clone(),
        branch_statuses: vec![],
        capture_status: ArtifactManifestCaptureStatus::Complete,
        artifacts: request
            .plan
            .predicted_paths
            .iter()
            .enumerate()
            .map(|(i, path)| {
                Artifact::Branch1(ArtifactBranch1 {
                    artifact_id: uuid(100 + i as u64),
                    relative_path: path.clone(),
                    byte_count: 6,
                    sha256: Digest(healthmd_protocol::transfer::sha256_hex(b"xxxxxx")),
                    media_type: ArtifactBranch1MediaType::ApplicationJson,
                    profile: serde_json::from_value(
                        serde_json::to_value(&request.plan.effective_settings.output_profile)
                            .unwrap(),
                    )
                    .unwrap(),
                    write_mode: request.plan.effective_settings.write_mode.clone(),
                })
            })
            .collect(),
    };
    let binding = NativeBinding {
        request,
        accepted,
        manifest,
    };
    binding.validate().unwrap();
    assert_eq!(binding.manifest.artifacts.len(), 2);
    binding
}
fn journal(binding: &NativeBinding) -> TransferJournal {
    let peer = &binding.request.plan.intent.peer;
    let session = Session(v2::TransferSession {
        session_id: uuid::Uuid::parse_str(&uuid(200).0).unwrap(),
        job_id: uuid::Uuid::parse_str(&binding.request.job_id.0).unwrap(),
        request_fingerprint: binding.manifest.request_sha256.0.clone(),
        peer_binding: v2::PeerBinding {
            source_installation_id: uuid::Uuid::parse_str(&peer.source_installation_id.0).unwrap(),
            destination_installation_id: uuid::Uuid::parse_str(&peer.host_installation_id.0)
                .unwrap(),
        },
        partition_target_bytes: 50_331_648,
        created_at: chrono::DateTime::parse_from_rfc3339("2026-01-03T00:00:00Z")
            .unwrap()
            .to_utc(),
    });
    let manifest_sha256 = document_digest(&binding.manifest).unwrap();
    let mut journal = TransferJournal {
        schema: "healthmd.agent_host_transfer".into(),
        schema_version: 1,
        job_id: binding.request.job_id.clone(),
        request_sha256: binding.manifest.request_sha256.clone(),
        manifest_sha256,
        session,
        partitions: vec![],
        frontier_sha256: Digest("0".repeat(64)),
        final_ack_may_have_sent: false,
    };
    for (index, item_index, offset, count) in [(0, 0, 0, 3), (1, 0, 3, 3), (2, 1, 0, 6)] {
        journal.partitions.push(PartitionRecord {
            partition: TransferFrontierPartition {
                partition_index: index,
                transfer_id: uuid(300 + u64::try_from(index).unwrap()),
                artifact_id: artifact(binding, item_index).unwrap().artifact_id.clone(),
                artifact_offset: offset,
                byte_count: count,
                chunk_count: 1,
                sha256: Digest(healthmd_protocol::transfer::sha256_hex(&vec![
                    b'x';
                    usize::try_from(count).unwrap()
                ])),
            },
            stage_name: format!(
                ".output-{}.stage",
                uuid(400 + u64::try_from(index).unwrap()).0
            ),
        });
    }
    rehash(binding, &mut journal);
    journal
}
async fn fixture() -> (NativeBinding, TransferJournal) {
    let (_, _, _, request) = request().await;
    let binding = native_binding(request);
    let journal = journal(&binding);
    (binding, journal)
}
fn rehash(binding: &NativeBinding, journal: &mut TransferJournal) {
    let mut frontier = TransferFrontier::new(
        &binding.request.job_id,
        &binding.manifest.request_sha256,
        &document_digest(&binding.manifest).unwrap(),
        &ControlUuid(journal.session.0.session_id.to_string()),
    )
    .unwrap();
    for record in &journal.partitions {
        frontier = frontier.appending(&record.partition).unwrap();
    }
    journal.frontier_sha256 = frontier.sha256().clone();
}
#[tokio::test]
async fn retained_prefix_accepts_only_contiguous_original_artifact_coverage() {
    for count in 0..=3 {
        let (binding, mut journal) = fixture().await;
        journal.partitions.truncate(count);
        rehash(&binding, &mut journal);
        let frontier = validate_retained_prefix(&binding, &journal).unwrap();
        assert_eq!(*frontier.sha256(), journal.frontier_sha256);
        journal.final_ack_may_have_sent = true;
        assert_eq!(
            validate_retained_prefix(&binding, &journal).is_ok(),
            count == 3
        );
    }
}
#[tokio::test]
async fn retained_prefix_rejects_rehashed_metadata_substitution_and_aliases() {
    for case in 0..14 {
        let (binding, mut journal) = fixture().await;
        match case {
            0 => journal.schema_version = 2,
            1 => journal.schema.push('x'),
            2 => journal.job_id = uuid(999),
            3 => journal.request_sha256 = Digest("f".repeat(64)),
            4 => journal.manifest_sha256 = Digest("f".repeat(64)),
            5 => journal.session.0.peer_binding.source_installation_id = uuid::Uuid::new_v4(),
            6 => journal.session.0.created_at += chrono::Duration::seconds(1),
            7 => journal.partitions[1].partition.artifact_offset = 2,
            8 => journal.partitions[1].partition.artifact_id = uuid(101),
            9 => {
                journal.partitions[1].partition.transfer_id =
                    journal.partitions[0].partition.transfer_id.clone();
            }
            10 => journal.partitions[1].stage_name = journal.partitions[0].stage_name.clone(),
            11 => journal.partitions[1].partition.byte_count = 4,
            12 => journal.partitions[1].partition.chunk_count = 0,
            13 => journal.partitions[1].partition.byte_count = 0,
            _ => unreachable!(),
        }
        // A self-consistent digest cannot legitimize a changed original identity or range.
        rehash(&binding, &mut journal);
        assert!(
            validate_retained_prefix(&binding, &journal).is_err(),
            "case {case}"
        );
    }
    let (binding, mut journal) = fixture().await;
    journal.frontier_sha256 = Digest("f".repeat(64));
    assert!(validate_retained_prefix(&binding, &journal).is_err());
}

#[tokio::test]
async fn signed_checkpoint_rejects_wrong_job_domain_and_ambiguous_bytes_without_repair() {
    use hmac::Mac as _;
    let (_temporary, store, output, request) = request().await;
    let binding = native_binding(request);
    let journal = journal(&binding);
    let mut transaction =
        OutputTransaction::open(&store, &binding, || async { Ok(output.clone()) })
            .await
            .unwrap();
    transaction
        .save(|| async { Ok(output.clone()) })
        .await
        .unwrap();
    let original = transaction
        .save_transfer(&journal, None, || async { Ok(output.clone()) })
        .await
        .unwrap();
    let (loaded, bytes) = transaction.read_transfer::<TransferJournal>().unwrap();
    assert_eq!(bytes, original);
    validate_retained_prefix(&binding, &loaded).unwrap();
    let name = format!("transfer-{}.json", binding.request.job_id.0);
    for case in 0..7 {
        let mut document: serde_json::Value = serde_json::from_slice(&original).unwrap();
        match case {
            0 => document["mac"] = serde_json::json!("f".repeat(64)),
            1 | 2 => {
                // Correct synthetic key and unchanged body, but wrong job/domain context.
                let mut mac = hmac::Hmac::<sha2::Sha256>::new_from_slice(&[41; 32]).unwrap();
                mac.update(if case == 1 {
                    b"HealthMd.AgentBridge.HostCompletionJournal.v1\0"
                } else {
                    b"HealthMd.AgentBridge.HostTransferJournal.v1\0"
                });
                mac.update(
                    if case == 2 {
                        uuid(999).0
                    } else {
                        binding.request.job_id.0.clone()
                    }
                    .as_bytes(),
                );
                mac.update(&v4::canonical_json(&journal).unwrap());
                document["mac"] = serde_json::json!(format!("{:x}", mac.finalize().into_bytes()));
            }
            3 => document["journal"]["caller_frontier"] = serde_json::json!(0),
            4 => document["journal"]["partitions"][0]["caller_field"] = serde_json::json!(true),
            _ => (),
        }
        let mut changed = v4::canonical_json(&document).unwrap();
        if case == 5 {
            changed.extend_from_slice(b"\n");
        }
        if case == 6 {
            let raw = String::from_utf8(changed).unwrap();
            changed = raw
                .replacen(
                    "\"schema_version\":1",
                    "\"schema_version\":1,\"schema_version\":1",
                    1,
                )
                .into_bytes();
        }
        transaction.directory().write(&name, &changed).unwrap();
        assert!(
            transaction.read_transfer::<TransferJournal>().is_err(),
            "case {case}"
        );
        assert_eq!(transaction.directory().read(&name).unwrap(), changed);
        transaction.directory().write(&name, &original).unwrap();
        assert_eq!(
            transaction.read_transfer::<TransferJournal>().unwrap().1,
            original
        );
    }
}
