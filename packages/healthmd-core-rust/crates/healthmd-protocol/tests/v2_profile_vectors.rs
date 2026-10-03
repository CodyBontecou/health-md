//! Export-profiles decision 10 (v2 mirror): byte-exact reference vectors for
//! the additive `settings_policy = profile` request shape on Android direct
//! v2, frozen in
//! `packages/contracts/direct-protocol/v2/fixtures/profile-policy-reference.json`
//! and verified from both sides (this suite and the Kotlin
//! `ProfilePolicyInteropTest`). Proves the canonical request JSON, the
//! `Envelope` framing, the request fingerprint, and the unnamed-reference
//! omission.

use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::{TimeZone as _, Utc};
use healthmd_protocol::encoding::canonical_json;
use healthmd_protocol::v2::{
    self, DateSelection, DestinationBinding, Envelope, ExportProduct, ExportRequest, Message,
    ProfileReference, SettingsPolicy,
};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
struct ProfilePolicyVectors {
    schema: String,
    schema_version: u32,
    request_json_base64: String,
    envelope_json_base64: String,
    request_fingerprint: String,
    request_unnamed_reference_json_base64: String,
}

fn vectors() -> ProfilePolicyVectors {
    let vectors: ProfilePolicyVectors =
        serde_json::from_str(include_str!("fixtures/profile-policy-reference.json")).unwrap();
    assert_eq!(
        vectors.schema,
        "healthmd.direct_v2_profile_policy_reference"
    );
    assert_eq!(vectors.schema_version, 1);
    vectors
}

fn profile_request() -> ExportRequest {
    ExportRequest {
        job_id: Uuid::parse_str("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee").unwrap(),
        created_at: Utc.timestamp_opt(1_753_343_472, 0).unwrap(),
        expires_at: "2026-07-31T10:11:12Z".parse().unwrap(),
        source_installation_id: Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap(),
        date_selection: DateSelection::Exact {
            start_date: "2026-07-01".into(),
            end_date: "2026-07-02".into(),
        },
        product: ExportProduct::GeneratedFilesV1 {
            settings_policy: SettingsPolicy::Profile,
            profile_reference: Some(ProfileReference {
                profile_id: "99999999-8888-4777-8666-555555555555".into(),
                name: Some("Weekly Sleep".into()),
            }),
        },
        destination: Some(DestinationBinding {
            binding_sha256: "a".repeat(64),
            display_name: "Health Exports".into(),
        }),
    }
}

fn unnamed_reference_request() -> ExportRequest {
    let mut request = profile_request();
    request.product = ExportProduct::GeneratedFilesV1 {
        settings_policy: SettingsPolicy::Profile,
        profile_reference: Some(ProfileReference {
            profile_id: "99999999-8888-4777-8666-555555555555".into(),
            name: None,
        }),
    };
    request
}

#[test]
fn canonical_request_json_matches_frozen_vector() {
    let vectors = vectors();
    let canonical = canonical_json(&profile_request()).unwrap();
    let frozen = STANDARD.decode(vectors.request_json_base64).unwrap();
    assert_eq!(
        canonical, frozen,
        "canonical profile request bytes must match the frozen vector"
    );
}

#[test]
fn request_fingerprint_matches_frozen_vector() {
    let vectors = vectors();
    let fingerprint = v2::request_fingerprint(&profile_request()).unwrap();
    assert_eq!(fingerprint, vectors.request_fingerprint);
}

#[test]
fn envelope_framing_matches_frozen_vector() {
    let vectors = vectors();
    let envelope = Envelope::new(Message::ExportRequest(profile_request()));
    let canonical = canonical_json(&envelope).unwrap();
    let frozen = STANDARD.decode(vectors.envelope_json_base64).unwrap();
    assert_eq!(canonical, frozen);

    let decoded: Envelope = serde_json::from_slice(&frozen).unwrap();
    decoded.validate_version().expect("v2 envelope");
    match decoded.message {
        Message::ExportRequest(request) => {
            assert_eq!(request, profile_request());
            assert_eq!(
                request.product.profile_reference(),
                Some(&ProfileReference {
                    profile_id: "99999999-8888-4777-8666-555555555555".into(),
                    name: Some("Weekly Sleep".into()),
                })
            );
        }
        _ => panic!("expected an export_request message"),
    }
}

#[test]
fn unnamed_reference_matches_frozen_vector() {
    let vectors = vectors();
    let canonical = canonical_json(&unnamed_reference_request()).unwrap();
    let frozen = STANDARD
        .decode(vectors.request_unnamed_reference_json_base64)
        .unwrap();
    assert_eq!(canonical, frozen);
}
