use healthmd_protocol::{
    encoding::{SwiftUuid, canonical_json},
    models::{FileManifest, FileWriteMode},
    notes::ScopedDailyNotePolicy,
    wire::PeerCapabilities,
};
use uuid::Uuid;

#[test]
fn scoped_policy_matches_swift_and_kotlin_bytes_and_preserves_legacy_omission() {
    let bytes = include_bytes!("fixtures/scoped-note-policy-v1.json");
    let policy: ScopedDailyNotePolicy = serde_json::from_slice(bytes).unwrap();
    assert!(policy.is_valid());
    assert_eq!(canonical_json(&policy).unwrap(), bytes);
    let mut hello = PeerCapabilities::portable_cli(SwiftUuid(Uuid::nil()));
    assert!(
        serde_json::to_value(&hello)
            .unwrap()
            .get("scopedDailyNoteVersions")
            .is_none()
    );
    hello.scoped_daily_note_versions = Some(vec![1]);
    assert_eq!(hello.negotiated_scoped_daily_note_version(&hello), Some(1));
    let mut manifest = FileManifest {
        job_id: SwiftUuid(Uuid::nil()),
        file_id: SwiftUuid(Uuid::nil()),
        relative_path: "Daily/2026-03-08.md".into(),
        byte_count: 42,
        sha256: "a".repeat(64),
        write_mode: FileWriteMode::MergeMarkdownPreservingPreamble,
        scoped_note_policy: None,
    };
    assert!(
        serde_json::to_value(&manifest)
            .unwrap()
            .get("scopedNotePolicy")
            .is_none()
    );
    manifest.scoped_note_policy = Some(policy);
    let json = canonical_json(&manifest).unwrap();
    assert_eq!(
        serde_json::from_slice::<FileManifest>(&json).unwrap(),
        manifest
    );
}
