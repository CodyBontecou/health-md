use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_protocol::{
    crypto,
    encoding::canonical_json,
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
    assert_eq!(
        crypto::android_pairing_verifier(
            &fixture.android_pairing_code,
            Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap(),
            &decode_hex(&fixture.client_public_key_hex),
            &decode_hex(&fixture.client_nonce_hex),
        ),
        decode_hex(&fixture.android_pairing_verifier_hex).as_slice()
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
