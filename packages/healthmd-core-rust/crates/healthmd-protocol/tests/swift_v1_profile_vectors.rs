//! Export-profiles decision 10: byte-exact Swift reference vectors for the
//! additive `settings_policy = profile` request shape, frozen from the Swift
//! `HealthMdConnectionCore` implementation (see
//! `HealthMdConnectionCoreTests.testProfilePolicyMatchesSwiftReferenceFixture`).
//! Values deliberately interlock with `profile_policy.rs` so both suites prove
//! the same wire bytes: canonical request JSON, the `DirectMessage` envelope,
//! the request fingerprint, and the unnamed-reference omission.

use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::{TimeZone as _, Utc};
use healthmd_protocol::{
    encoding::{SwiftUuid, canonical_json},
    foundation::apple_v1_request_fingerprint,
    models::{
        DateSelection, ExactDateSelection, ExportRequest, ProfileReference, ResponseMode,
        SettingsPolicy,
    },
    transfer::request_fingerprint,
    wire::{DirectMessage, Unlabeled},
};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
struct ProfilePolicyVectors {
    schema: String,
    schema_version: u32,
    profile_request_json_base64: String,
    profile_request_message_json_base64: String,
    profile_request_fingerprint: String,
    profile_request_unnamed_reference_json_base64: String,
}

fn vectors() -> ProfilePolicyVectors {
    serde_json::from_str(include_str!("fixtures/profile-policy-swift-reference.json")).unwrap()
}

fn profile_request() -> ExportRequest {
    ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(Uuid::parse_str("00000000-0000-4000-8000-00000000000B").unwrap()),
        created_at: Utc.timestamp_opt(1_700_000_000, 0).unwrap(),
        date_selection: DateSelection::Exact(ExactDateSelection {
            start: "2026-08-01".into(),
            end: "2026-08-07".into(),
        }),
        settings_policy: SettingsPolicy::Profile,
        profile_reference: Some(ProfileReference {
            profile_id: "11111111-2222-4333-8444-555555555555".into(),
            name: Some("Weekly Sleep".into()),
        }),
        response_mode: ResponseMode::WriteFiles,
        raw_profile: None,
        canonical_selection: None,
        destination: None,
    }
}

fn unnamed_reference_request() -> ExportRequest {
    let mut request = profile_request();
    let reference = request.profile_reference.as_mut().unwrap();
    reference.name = None;
    request
}

#[test]
fn rust_matches_swift_profile_request_bytes_and_fingerprint() {
    let fixture = vectors();
    assert_eq!(
        fixture.schema,
        "healthmd.direct_profile_policy_swift_reference"
    );
    assert_eq!(fixture.schema_version, 1);

    let request = profile_request();
    let swift_bytes = STANDARD
        .decode(&fixture.profile_request_json_base64)
        .unwrap();
    assert_eq!(
        canonical_json(&request).unwrap(),
        swift_bytes,
        "Rust canonical request bytes must match the frozen Swift vectors"
    );

    let fingerprint = request_fingerprint(&request).unwrap();
    assert_eq!(fingerprint.sha256, fixture.profile_request_fingerprint);
    assert_eq!(
        apple_v1_request_fingerprint(&swift_bytes).unwrap(),
        fixture.profile_request_fingerprint,
        "the shared v1 foundation must accept the Swift profile request bytes"
    );

    let message = canonical_json(&DirectMessage::ExportRequest(Unlabeled::from(request))).unwrap();
    assert_eq!(
        message,
        STANDARD
            .decode(&fixture.profile_request_message_json_base64)
            .unwrap(),
        "Rust message envelope bytes must match the frozen Swift vectors"
    );
}

#[test]
fn rust_matches_swift_unnamed_reference_bytes() {
    let fixture = vectors();
    let request = unnamed_reference_request();
    let swift_bytes = STANDARD
        .decode(&fixture.profile_request_unnamed_reference_json_base64)
        .unwrap();
    let rust_bytes = canonical_json(&request).unwrap();
    let omitted: serde_json::Value = serde_json::from_slice(&rust_bytes).unwrap();
    assert!(omitted["profileReference"].get("name").is_none());
    assert_eq!(rust_bytes, swift_bytes);
}

#[test]
fn swift_profile_bytes_decode_into_current_rust_model() {
    let fixture = vectors();
    let named: ExportRequest = serde_json::from_slice(
        &STANDARD
            .decode(&fixture.profile_request_json_base64)
            .unwrap(),
    )
    .unwrap();
    assert_eq!(named, profile_request());

    let unnamed: ExportRequest = serde_json::from_slice(
        &STANDARD
            .decode(&fixture.profile_request_unnamed_reference_json_base64)
            .unwrap(),
    )
    .unwrap();
    assert_eq!(unnamed, unnamed_reference_request());
}
