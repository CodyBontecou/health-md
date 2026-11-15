//! Hermetic retained-prefix recovery controls; independent synthetic native metadata only.
use crate::agent_host::output::NativeBinding;
use crate::agent_planning::HostPlanner;
use crate::agent_test_support as support;
use healthmd_protocol::v4::PeerPlatform;
use healthmd_protocol::v4::*;
use std::path::PathBuf;

pub(crate) fn uuid(number: u64) -> ControlUuid {
    ControlUuid(format!("00000000-0000-4000-8000-{number:012x}"))
}
pub(crate) async fn request() -> (
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
pub(crate) fn native_binding(request: ExecuteRequest) -> NativeBinding {
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
