use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::{TimeZone as _, Utc};
use healthmd_protocol::{
    crypto,
    encoding::{SwiftUuid, canonical_json},
    foundation::{
        ProtocolFoundationError, apple_v1_request_fingerprint, canonicalize_apple_v1_message,
    },
    models::{
        CanonicalSelection, DateSelection, DetailLevel, ExactDateSelection, ExportRequest,
        ResponseMode, SettingsPolicy, TransferChunk,
    },
    transfer::{encode_binary_chunk, request_fingerprint, sha256_hex},
    wire::{DirectMessage, RawProfile, SyncPacket, Unlabeled},
};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
struct SwiftVectors {
    pairing_verifier_hex: String,
    pairing_packet_json_base64: String,
    request_json_base64: String,
    request_message_json_base64: String,
    request_fingerprint: String,
    binary_frame_base64: String,
}

fn vectors() -> SwiftVectors {
    serde_json::from_str(include_str!("fixtures/swift-direct-v1.json")).unwrap()
}

fn request() -> ExportRequest {
    ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(Uuid::parse_str("00000000-0000-4000-8000-000000000001").unwrap()),
        created_at: Utc.timestamp_opt(1_700_000_000, 0).unwrap(),
        date_selection: DateSelection::Exact(ExactDateSelection {
            start: "2026-07-01".into(),
            end: "2026-07-07".into(),
        }),
        settings_policy: SettingsPolicy::RequestedDatesOnly,
        response_mode: ResponseMode::RawJson,
        raw_profile: Some(RawProfile::HealthDataProjection),
        canonical_selection: Some(CanonicalSelection {
            metric_ids: vec!["sleep_total".into()],
            categories: vec!["Sleep".into()],
            source_ids: vec!["apple_health".into()],
            object_paths: vec!["/sleep".into()],
            field_pointers: Vec::new(),
            all_metrics: false,
            detail_level: DetailLevel::Summary,
        }),
        destination: None,
    }
}

#[test]
fn rust_matches_swift_pairing_proof_and_decodes_packet() {
    let fixture = vectors();
    let client_id = Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap();
    let proof = crypto::pairing_verifier("123 456", client_id, &[7; 32], &[9; 32]);
    assert_eq!(hex(&proof), fixture.pairing_verifier_hex);

    let swift_packet = STANDARD.decode(fixture.pairing_packet_json_base64).unwrap();
    assert!(matches!(
        serde_json::from_slice::<SyncPacket>(&swift_packet).unwrap(),
        SyncPacket::PairingRequest(_)
    ));
}

#[test]
fn rust_canonical_request_and_fingerprint_match_swift() {
    let fixture = vectors();
    let request = request();
    assert_eq!(
        canonical_json(&request).unwrap(),
        STANDARD.decode(fixture.request_json_base64).unwrap()
    );
    assert_eq!(
        request_fingerprint(&request).unwrap().sha256,
        fixture.request_fingerprint
    );
    assert_eq!(
        canonical_json(&DirectMessage::ExportRequest(Unlabeled::from(request))).unwrap(),
        STANDARD
            .decode(fixture.request_message_json_base64)
            .unwrap()
    );
}

#[test]
fn protocol_foundation_accepts_only_the_exact_swift_request_and_preserves_message_bytes() {
    let fixture = vectors();
    let request_bytes = STANDARD.decode(&fixture.request_json_base64).unwrap();
    assert_eq!(
        apple_v1_request_fingerprint(&request_bytes).unwrap(),
        fixture.request_fingerprint
    );

    let message_bytes = STANDARD
        .decode(&fixture.request_message_json_base64)
        .unwrap();
    assert_eq!(
        canonicalize_apple_v1_message(&message_bytes).unwrap(),
        message_bytes
    );
    let mut unknown_message: serde_json::Value = serde_json::from_slice(&message_bytes).unwrap();
    unknown_message["exportRequest"]["_0"]["unknownHealthFreeField"] = serde_json::json!(true);
    assert_eq!(
        canonicalize_apple_v1_message(&canonical_json(&unknown_message).unwrap()),
        Err(ProtocolFoundationError::UnknownField)
    );

    let mut noncanonical = b" ".to_vec();
    noncanonical.extend_from_slice(&request_bytes);
    assert_eq!(
        apple_v1_request_fingerprint(&noncanonical),
        Err(ProtocolFoundationError::NonCanonicalJson)
    );

    let mut unknown: serde_json::Value = serde_json::from_slice(&request_bytes).unwrap();
    unknown["unknownHealthFreeField"] = serde_json::json!(true);
    assert_eq!(
        apple_v1_request_fingerprint(&canonical_json(&unknown).unwrap()),
        Err(ProtocolFoundationError::UnknownField)
    );

    let mut wrong_version: serde_json::Value = serde_json::from_slice(&request_bytes).unwrap();
    wrong_version["protocolVersion"] = serde_json::json!(2);
    assert_eq!(
        apple_v1_request_fingerprint(&canonical_json(&wrong_version).unwrap()),
        Err(ProtocolFoundationError::UnsupportedProtocolVersion)
    );
}

#[test]
fn rust_binary_frame_matches_swift_byte_for_byte() {
    let fixture = vectors();
    let data = vec![0xab; 32];
    let chunk = TransferChunk {
        transfer_id: SwiftUuid(Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap()),
        sequence: 1,
        sha256: sha256_hex(&data),
        data,
    };
    assert_eq!(
        encode_binary_chunk(&chunk).unwrap(),
        STANDARD.decode(fixture.binary_frame_base64).unwrap()
    );
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    bytes.iter().fold(String::new(), |mut output, byte| {
        write!(output, "{byte:02x}").expect("writing to a string succeeds");
        output
    })
}
