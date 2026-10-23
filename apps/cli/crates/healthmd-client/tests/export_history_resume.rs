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
        let mut files = FileReceiver::new(layout, jobs);
        let mut prepare = |value: ExportAccepted| {
            if file_mode {
                files.prepare(request.clone(), value, session.clone())
            } else {
                raw.prepare(request.clone(), value, session.clone())
            }
        };
        prepare(accepted.clone()).unwrap();
        prepare(accepted.clone()).unwrap();
        evidence["observation_id"] = json!("66666666-6666-4666-8666-666666666666");
        let mut changed = accepted.clone();
        changed.history_observation = Some(serde_json::from_value(evidence).unwrap());
        assert!(prepare(changed).is_err());
        accepted.history_observation = None;
        assert!(prepare(accepted).is_err());
    }
}
