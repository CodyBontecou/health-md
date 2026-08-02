use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_protocol::{
    crypto,
    encoding::canonical_json,
    foundation::{
        PairingProfile, ProtocolFoundationError, android_v2_request_fingerprint,
        canonicalize_android_v2_envelope, verify_pairing_client_transcript,
    },
    v2::{
        DateSelection, Empty, Envelope, ExportProduct, ExportRequest, Message, RawSnapshotFormat,
        RawSnapshotScope, StatusRequest, request_fingerprint,
    },
};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
struct KotlinVectors {
    client_public_key_hex: String,
    client_nonce_hex: String,
    android_pairing_code: String,
    android_pairing_verifier_hex: String,
    request_json_base64: String,
    request_fingerprint: String,
    status_request_envelope_json_base64: String,
}

fn vectors() -> KotlinVectors {
    serde_json::from_str(include_str!("fixtures/kotlin-direct-v2.json")).unwrap()
}

fn request() -> ExportRequest {
    ExportRequest {
        job_id: Uuid::parse_str("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee").unwrap(),
        created_at: "2026-07-24T10:11:12Z".parse().unwrap(),
        expires_at: "2026-07-31T10:11:12Z".parse().unwrap(),
        source_installation_id: Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap(),
        date_selection: DateSelection::Exact {
            start_date: "2026-07-01".into(),
            end_date: "2026-07-02".into(),
        },
        product: ExportProduct::AndroidProviderNativeSnapshotV1 {
            provider_id: "health_connect".into(),
            format: RawSnapshotFormat::Ndjson,
            scope: RawSnapshotScope::SelectedRecordTypes {
                selected_metric_ids: vec!["sleep".into(), "steps".into()],
            },
            include_exercise_routes: false,
        },
        destination: None,
    }
}

fn decode_hex(value: &str) -> Vec<u8> {
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}

#[test]
fn android_pairing_v2_matches_kotlin_fixture() {
    let fixture = vectors();
    let client_public_key = decode_hex(&fixture.client_public_key_hex);
    let client_nonce = decode_hex(&fixture.client_nonce_hex);
    let expected = decode_hex(&fixture.android_pairing_verifier_hex);
    assert_eq!(
        crypto::android_pairing_verifier(
            &fixture.android_pairing_code,
            Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap(),
            &client_public_key,
            &client_nonce,
        ),
        expected.as_slice()
    );
    assert!(
        verify_pairing_client_transcript(
            PairingProfile::AndroidV2,
            &fixture.android_pairing_code,
            "abcdefab-cdef-4abc-8def-abcdefabcdef",
            &client_public_key,
            &client_nonce,
            &expected,
        )
        .unwrap()
    );
}

#[test]
fn rust_v2_request_matches_kotlin_fixture() {
    let fixture = vectors();
    let request = request();
    assert_eq!(
        canonical_json(&request).unwrap(),
        STANDARD.decode(fixture.request_json_base64).unwrap()
    );
    assert_eq!(
        request_fingerprint(&request).unwrap(),
        fixture.request_fingerprint
    );
}

#[test]
fn protocol_foundation_accepts_only_exact_v2_request_and_envelope_bytes() {
    let fixture = vectors();
    let request_bytes = STANDARD.decode(&fixture.request_json_base64).unwrap();
    assert_eq!(
        android_v2_request_fingerprint(&request_bytes).unwrap(),
        fixture.request_fingerprint
    );

    let envelope_bytes = STANDARD
        .decode(&fixture.status_request_envelope_json_base64)
        .unwrap();
    assert_eq!(
        canonicalize_android_v2_envelope(&envelope_bytes).unwrap(),
        envelope_bytes
    );

    let pretty = serde_json::to_vec_pretty(
        &serde_json::from_slice::<serde_json::Value>(&request_bytes).unwrap(),
    )
    .unwrap();
    assert_eq!(
        android_v2_request_fingerprint(&pretty),
        Err(ProtocolFoundationError::NonCanonicalJson)
    );

    let mut unknown: serde_json::Value = serde_json::from_slice(&request_bytes).unwrap();
    unknown["unknown_health_free_field"] = serde_json::json!(true);
    assert_eq!(
        android_v2_request_fingerprint(&canonical_json(&unknown).unwrap()),
        Err(ProtocolFoundationError::UnknownField)
    );

    let mut wrong_version: serde_json::Value = serde_json::from_slice(&envelope_bytes).unwrap();
    wrong_version["protocol_version"] = serde_json::json!(1);
    assert_eq!(
        canonicalize_android_v2_envelope(&canonical_json(&wrong_version).unwrap()),
        Err(ProtocolFoundationError::UnsupportedProtocolVersion)
    );

    let mut unknown_envelope: serde_json::Value = serde_json::from_slice(&envelope_bytes).unwrap();
    unknown_envelope["unknown_health_free_field"] = serde_json::json!(true);
    assert_eq!(
        canonicalize_android_v2_envelope(&canonical_json(&unknown_envelope).unwrap()),
        Err(ProtocolFoundationError::UnknownField)
    );
}

#[test]
fn foundation_matches_kotlin_defaults_null_policy_and_signed_ranges() {
    let source_hello = br#"{"payload":{"limits":{"maximum_chunk_bytes":524288,"maximum_control_bytes":262144,"preferred_partition_bytes":50331648},"products":[{"artifact_schema":{"id":"healthmd.generated-files","major":1},"formats":["markdown"],"product_id":"generated_files_v1","providers":[],"settings_policies":[],"supports_resume":true}],"source":{"app_version":"1.0","display_name":"Android","installation_id":"11111111-2222-4333-8444-555555555555","platform":"android"}},"protocol_version":2,"type":"source_hello"}"#;
    assert_eq!(
        canonicalize_android_v2_envelope(source_hello).unwrap(),
        source_hello
    );

    let failure = br#"{"payload":{"code":"internal_failure","details":{},"phase":"preparing","public_message":"Failed safely.","retryable":false},"protocol_version":2,"type":"export_rejected"}"#;
    assert_eq!(canonicalize_android_v2_envelope(failure).unwrap(), failure);

    let explicit_null = br#"{"payload":{"active_job_id":null,"app_active":true,"available_products":[],"export_in_progress":false,"protected_data_available":true,"source":{"app_version":"1.0","display_name":"Android","installation_id":"11111111-2222-4333-8444-555555555555","platform":"android"}},"protocol_version":2,"type":"status_response"}"#;
    assert_eq!(
        canonicalize_android_v2_envelope(explicit_null),
        Err(ProtocolFoundationError::NonCanonicalJson)
    );

    let int_overflow = br#"{"payload":{"accepted":true,"sequence":2147483648,"sha256":"0000000000000000000000000000000000000000000000000000000000000000","transfer_id":"11111111-2222-4333-8444-555555555555"},"protocol_version":2,"type":"transfer_chunk_acknowledgement"}"#;
    assert_eq!(
        canonicalize_android_v2_envelope(int_overflow),
        Err(ProtocolFoundationError::InvalidAndroidEnvelope)
    );

    let long_overflow = br#"{"payload":{"job_id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","request_fingerprint":"0000000000000000000000000000000000000000000000000000000000000000","session_id":"11111111-2222-4333-8444-555555555555","total_bytes":9223372036854775808,"total_partitions":1},"protocol_version":2,"type":"transfer_finalize"}"#;
    assert_eq!(
        canonicalize_android_v2_envelope(long_overflow),
        Err(ProtocolFoundationError::InvalidAndroidEnvelope)
    );
}

#[test]
fn rust_v2_envelope_matches_kotlin_fixture() {
    let fixture = vectors();
    let message = Envelope::new(Message::StatusRequest(StatusRequest {
        requested_at: "2026-07-24T10:11:12Z".parse().unwrap(),
    }));
    assert_eq!(
        canonical_json(&message).unwrap(),
        STANDARD
            .decode(fixture.status_request_envelope_json_base64)
            .unwrap()
    );
}

#[test]
fn v2_ping_has_an_explicit_empty_payload() {
    let encoded = canonical_json(&Envelope::new(Message::Ping(Empty {}))).unwrap();
    assert_eq!(
        encoded,
        br#"{"payload":{},"protocol_version":2,"type":"ping"}"#
    );
}
