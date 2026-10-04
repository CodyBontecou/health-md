use super::*;
use chrono::Timelike as _;
use healthmd_protocol::{
    encoding::SwiftUuid, models::TransferChunk, transfer::encode_binary_chunk,
};
use tempfile::TempDir;

struct Fixture {
    _temporary: TempDir,
    layout: StorageLayout,
    jobs: V2JobStore,
    root: PathBuf,
    request: v2::ExportRequest,
    accepted: v2::ExportAccepted,
    session: v2::TransferSession,
    manifest: v2::ArtifactManifest,
    partition: v2::TransferPartition,
    data: Vec<u8>,
}

impl Fixture {
    #[allow(clippy::too_many_lines)]
    fn new(mode: v2::FileWriteMode) -> Self {
        let temporary = TempDir::new().unwrap();
        let root = temporary.path().join("exports");
        fs::create_dir(&root).unwrap();
        fs::write(root.join("daily.md"), b"User preamble\n\n## Health\nold\n").unwrap();
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let jobs = V2JobStore::new(layout.clone()).unwrap();
        let now = Utc::now().with_nanosecond(0).unwrap();
        let job_id = Uuid::new_v4();
        let source_id = Uuid::new_v4();
        let request = v2::ExportRequest {
            job_id,
            created_at: now,
            expires_at: now + chrono::Duration::days(7),
            source_installation_id: source_id,
            date_selection: v2::DateSelection::AllAvailable,
            product: v2::ExportProduct::GeneratedFilesV1 {
                settings_policy: v2::SettingsPolicy::SavedDeviceSettings,
                profile_reference: None,
            },
            destination: Some(v2::DestinationBinding {
                binding_sha256: GeneratedDestination::open(&root)
                    .unwrap()
                    .binding_sha256()
                    .unwrap(),
                display_name: "exports".into(),
            }),
        };
        jobs.save(&crate::v2_job::V2JobRecord::new(
            request.clone(),
            Some(root.to_str().unwrap().into()),
        ))
        .unwrap();
        let fingerprint = v2::request_fingerprint(&request).unwrap();
        let binding = v2::PeerBinding {
            source_installation_id: source_id,
            destination_installation_id: Uuid::new_v4(),
        };
        let accepted = v2::ExportAccepted {
            job_id,
            accepted_at: now,
            peer_binding: binding.clone(),
            product_id: ProductId::GeneratedFilesV1,
            resolved_range: v2::ResolvedRange {
                start_date: "2026-07-23".into(),
                end_date: "2026-07-23".into(),
                time_zone_id: "UTC".into(),
            },
            provider_id: None,
            settings_snapshot_sha256: Some("2".repeat(64)),
            request_fingerprint: fingerprint.clone(),
        };
        let session = v2::TransferSession {
            session_id: Uuid::new_v4(),
            job_id,
            request_fingerprint: fingerprint,
            peer_binding: binding,
            partition_target_bytes: 32 * 1024 * 1024,
            created_at: now,
        };
        let data = b"## Health\nfresh synthetic generated content with bounded bytes\n".to_vec();
        let artifact_id = Uuid::new_v4();
        let manifest = v2::ArtifactManifest {
            job_id,
            artifact_id,
            kind: ArtifactKind::GeneratedFile,
            schema: v2::ArtifactSchema {
                id: "healthmd.generated-files".into(),
                major: 1,
            },
            media_type: "text/markdown; charset=utf-8".into(),
            byte_count: u64::try_from(data.len()).unwrap(),
            sha256: sha256_hex(&data),
            logical_checksum_sha256: None,
            relative_path: Some("daily.md".into()),
            write_mode: Some(mode),
            snapshot_status: None,
            provider_id: None,
        };
        let partition = v2::TransferPartition {
            index: 0,
            transfer_id: Uuid::new_v4(),
            artifact_id,
            artifact_offset: 0,
            byte_count: manifest.byte_count,
            chunk_count: 1,
            sha256: manifest.sha256.clone(),
            previous_sha256: None,
        };
        Self {
            _temporary: temporary,
            layout,
            jobs,
            root,
            request,
            accepted,
            session,
            manifest,
            partition,
            data,
        }
    }

    fn receiver(&self) -> V2ArtifactReceiver {
        let mut receiver = V2ArtifactReceiver::new(self.layout.clone(), self.jobs.clone());
        receiver
            .prepare(
                self.request.clone(),
                self.accepted.clone(),
                self.session.clone(),
            )
            .unwrap();
        receiver
    }

    fn open(&self) -> v2::TransferOpen {
        v2::TransferOpen {
            session: self.session.clone(),
            partition: self.partition.clone(),
        }
    }

    fn frame(&self) -> Vec<u8> {
        encode_binary_chunk(&TransferChunk {
            transfer_id: SwiftUuid(self.partition.transfer_id),
            sequence: 1,
            data: self.data.clone(),
            sha256: sha256_hex(&self.data),
        })
        .unwrap()
    }

    fn complete(&self) -> v2::TransferPartitionComplete {
        v2::TransferPartitionComplete {
            session_id: self.session.session_id,
            job_id: self.request.job_id,
            partition_index: 0,
            transfer_id: self.partition.transfer_id,
            partition_sha256: self.partition.sha256.clone(),
        }
    }

    fn finalize(&self) -> v2::TransferFinalize {
        v2::TransferFinalize {
            session_id: self.session.session_id,
            job_id: self.request.job_id,
            request_fingerprint: self.session.request_fingerprint.clone(),
            total_partitions: 1,
            total_bytes: self.manifest.byte_count,
            final_partition_sha256: Some(self.manifest.sha256.clone()),
        }
    }

    fn transferred(&self) -> V2ArtifactReceiver {
        let mut receiver = self.receiver();
        receiver.store_manifest(self.manifest.clone()).unwrap();
        receiver.disposition(self.open()).unwrap();
        receiver.receive_binary_frame(&self.frame()).unwrap();
        receiver.commit_partition(&self.complete()).unwrap();
        receiver
    }
}

#[test]
fn all_write_modes_recover_after_commit_without_duplicate_append_or_merge() {
    for mode in [
        v2::FileWriteMode::Overwrite,
        v2::FileWriteMode::Append,
        v2::FileWriteMode::MergeMarkdown,
        v2::FileWriteMode::MergeMarkdownPreservingPreamble,
    ] {
        let fixture = Fixture::new(mode);
        let mut receiver = fixture.transferred();
        receiver.finalize(&fixture.finalize()).unwrap();
        let once = fs::read(fixture.root.join("daily.md")).unwrap();
        assert!(String::from_utf8(once.clone()).unwrap().contains("fresh"));
        // Simulate death after durable destination install, before the mobile confirmation.
        drop(receiver);
        let mut resumed = fixture.receiver();
        resumed.store_manifest(fixture.manifest.clone()).unwrap();
        assert_eq!(
            resumed.disposition(fixture.open()).unwrap().disposition,
            TransferDispositionKind::AlreadyCommitted
        );
        resumed.finalize(&fixture.finalize()).unwrap();
        assert_eq!(fs::read(fixture.root.join("daily.md")).unwrap(), once);
        assert_eq!(
            fixture.jobs.load(fixture.request.job_id).unwrap().state,
            JobState::AwaitingPeerAcknowledgement
        );
        resumed
            .acknowledge_completion(fixture.request.job_id)
            .unwrap();
        let receipt = resumed
            .generated_file_receipt(fixture.request.job_id)
            .unwrap();
        assert_eq!(receipt["relative_paths"], json!(["daily.md"]));
        let path = resumed.receipt(fixture.request.job_id).unwrap().path;
        fs::write(path, b"{}").unwrap();
        assert!(
            resumed
                .generated_file_receipt(fixture.request.job_id)
                .is_err()
        );
    }
}

#[test]
fn interrupted_pending_partition_is_discarded_but_manifest_and_scope_cannot_change() {
    let fixture = Fixture::new(v2::FileWriteMode::Append);
    let mut receiver = fixture.receiver();
    receiver.store_manifest(fixture.manifest.clone()).unwrap();
    receiver.disposition(fixture.open()).unwrap();
    receiver.receive_binary_frame(&fixture.frame()).unwrap();
    drop(receiver); // not yet acknowledged; no destination commit
    let mut resumed = fixture.receiver();
    resumed.store_manifest(fixture.manifest.clone()).unwrap();
    assert_eq!(
        resumed.disposition(fixture.open()).unwrap().disposition,
        TransferDispositionKind::Needed
    );
    let mut changed_manifest = fixture.manifest.clone();
    changed_manifest.write_mode = Some(v2::FileWriteMode::Overwrite);
    assert!(resumed.store_manifest(changed_manifest).is_err());
    let mut changed_request = fixture.request.clone();
    changed_request.date_selection = v2::DateSelection::Exact {
        start_date: "2026-07-23".into(),
        end_date: "2026-07-23".into(),
    };
    assert!(
        resumed
            .prepare(
                changed_request,
                fixture.accepted.clone(),
                fixture.session.clone()
            )
            .is_err()
    );
    assert!(
        !String::from_utf8(fs::read(fixture.root.join("daily.md")).unwrap())
            .unwrap()
            .contains("fresh")
    );
}

#[test]
fn aliases_destination_replacement_and_digest_failures_never_escape_the_binding() {
    let fixture = Fixture::new(v2::FileWriteMode::Append);
    let mut receiver = fixture.receiver();
    receiver.store_manifest(fixture.manifest.clone()).unwrap();
    for alias in ["DAILY.md", "daily.md/child", "../daily.md"] {
        let mut collision = fixture.manifest.clone();
        collision.artifact_id = Uuid::new_v4();
        collision.relative_path = Some(alias.into());
        assert!(receiver.store_manifest(collision).is_err());
    }
    let mut bad_frame = fixture.frame();
    *bad_frame.last_mut().unwrap() ^= 1;
    receiver.disposition(fixture.open()).unwrap();
    assert!(receiver.receive_binary_frame(&bad_frame).is_err());
    let moved = fixture.root.with_file_name("original");
    fs::rename(&fixture.root, &moved).unwrap();
    fs::create_dir(&fixture.root).unwrap();
    let mut rebound = fixture.receiver();
    assert!(rebound.store_manifest(fixture.manifest.clone()).is_err());
    assert!(!fixture.root.join("daily.md").exists());
}

#[test]
fn generated_job_expiry_is_honest_offline_and_does_not_touch_destination() {
    let fixture = Fixture::new(v2::FileWriteMode::Append);
    let mut request = fixture.request.clone();
    request.created_at -= chrono::Duration::days(8);
    request.expires_at -= chrono::Duration::days(8);
    let record =
        crate::v2_job::V2JobRecord::new(request, Some(fixture.root.to_str().unwrap().into()));
    fixture.jobs.save(&record).unwrap();
    assert!(matches!(
        fixture.jobs.load(fixture.request.job_id),
        Err(ClientError::JobExpired)
    ));
    assert!(
        !String::from_utf8(fs::read(fixture.root.join("daily.md")).unwrap())
            .unwrap()
            .contains("fresh")
    );
}

#[test]
fn destination_content_mutation_during_final_delivery_fails_closed() {
    let fixture = Fixture::new(v2::FileWriteMode::Append);
    let mut receiver = fixture.transferred();
    receiver.finalize(&fixture.finalize()).unwrap();
    fs::write(fixture.root.join("daily.md"), b"changed externally").unwrap();
    let mut resumed = fixture.receiver();
    assert!(resumed.finalize(&fixture.finalize()).is_err());
    assert_eq!(
        fs::read(fixture.root.join("daily.md")).unwrap(),
        b"changed externally"
    );
    assert_eq!(
        fixture.jobs.load(fixture.request.job_id).unwrap().state,
        JobState::AwaitingPeerAcknowledgement
    );
}
