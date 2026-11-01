use healthmd_client::{
    file_receiver::FileReceiver,
    job::{JobRecord, JobStore},
    raw_receiver::RawReceiver,
    storage::StorageLayout,
};
use healthmd_protocol::{
    models::{ExportAccepted, ExportDestination, ExportRequest, ResponseMode, TransferSession},
    transfer::request_fingerprint,
};
use serde::Deserialize;
use serde_json::json;
use tempfile::TempDir;

#[derive(Deserialize)]
struct Fixture {
    request: ExportRequest,
    accepted: ExportAccepted,
    session: TransferSession,
}

#[test]
fn raw_and_file_checkpoints_reject_changed_or_removed_observations() {
    for file_mode in [false, true] {
        let Fixture {
            mut request,
            mut accepted,
            mut session,
        } = serde_json::from_str(include_str!("fixtures/export-history-direct-job-v1.json"))
            .unwrap();
        // The fixture freezes wire evidence, not a live seven-day durable-job lease.
        // Rebase only runtime admission timestamps so this remains a resume test.
        request.created_at =
            chrono::DateTime::from_timestamp(chrono::Utc::now().timestamp(), 0).unwrap();
        session.created_at = request.created_at;
        accepted.accepted_at = request.created_at;
        let temporary = TempDir::new().unwrap();
        let destination = temporary.path().join("vault");
        std::fs::create_dir(&destination).unwrap();
        if file_mode {
            request.response_mode = ResponseMode::WriteFiles;
            request.raw_profile = None;
            request.destination = Some(ExportDestination {
                root_path: destination.to_str().unwrap().to_owned(),
            });
        }
        session.request_fingerprint = request_fingerprint(&request).unwrap();
        let mut evidence =
            serde_json::to_value(accepted.history_observation.as_ref().unwrap()).unwrap();
        evidence["request_binding_sha256"] = json!(session.request_fingerprint.sha256);
        accepted.history_observation = Some(serde_json::from_value(evidence.clone()).unwrap());
        let layout = StorageLayout {
            root: temporary.path().join("state"),
        };
        let jobs = JobStore::new(layout.clone()).unwrap();
        jobs.save(&JobRecord::new(request.clone())).unwrap();
        let mut raw = RawReceiver::new(layout.clone(), jobs.clone());
        let mut files = FileReceiver::new(layout.clone(), jobs);
        let mut prepare = |value: ExportAccepted| {
            if file_mode {
                files.prepare(request.clone(), value, session.clone())
            } else {
                raw.prepare(request.clone(), value, session.clone())
            }
        };
        prepare(accepted.clone()).unwrap();
        prepare(accepted.clone()).unwrap();
        let checkpoint = layout
            .corpus_sessions_dir()
            .join(request.job_id.0.to_string())
            .join(if file_mode {
                "file-journal.json"
            } else {
                "journal.json"
            });
        let saved = std::fs::read(&checkpoint).unwrap();
        let checkpoint_value: serde_json::Value = serde_json::from_slice(&saved).unwrap();
        for version in [if file_mode { 2 } else { 1 }, 999] {
            let mut changed = checkpoint_value.clone();
            changed["version"] = json!(version);
            let bytes = serde_json::to_vec(&changed).unwrap();
            std::fs::write(&checkpoint, &bytes).unwrap();
            assert!(prepare(accepted.clone()).is_err());
            assert_eq!(std::fs::read(&checkpoint).unwrap(), bytes);
        }
        std::fs::write(&checkpoint, saved).unwrap();
        prepare(accepted.clone()).unwrap();
        evidence["observation_id"] = json!("66666666-6666-4666-8666-666666666666");
        let mut changed = accepted.clone();
        changed.history_observation = Some(serde_json::from_value(evidence).unwrap());
        assert!(prepare(changed).is_err());
        accepted.history_observation = None;
        assert!(prepare(accepted).is_err());
    }
}
