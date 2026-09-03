use chrono::DateTime;
use healthmd_protocol::{
    IOS_QUERY_APPLICATION_PROTOCOL_VERSION,
    encoding::SwiftUuid,
    wire::{
        DirectMessage, DirectQueryCapabilities, DirectQueryDetailLevel, DirectQueryFailure,
        DirectQueryRequest, DirectQueryResponse, PeerCapabilities, PeerPlatform, RawProfile,
        TransferCapabilities, Unlabeled,
    },
};
use serde::Deserialize;
use serde_json::{Value, json};
use uuid::Uuid;

#[derive(Debug, Deserialize)]
struct Fixture {
    schema: String,
    schema_version: i32,
    hello: Value,
    query_request: Value,
    query_response: Value,
    query_rejected: Value,
}

fn fixture() -> Fixture {
    serde_json::from_slice(include_bytes!("fixtures/swift-direct-v3.json"))
        .expect("Swift v3 query fixture must decode")
}

fn request_id() -> SwiftUuid {
    SwiftUuid(Uuid::parse_str("00000000-0000-4000-8000-000000000003").unwrap())
}

#[test]
fn rust_matches_swift_direct_query_v3_fixture() {
    let fixture = fixture();
    assert_eq!(fixture.schema, "healthmd.direct_query_swift_reference");
    assert_eq!(fixture.schema_version, 1);

    let peer = PeerCapabilities {
        protocol_versions: vec![1, IOS_QUERY_APPLICATION_PROTOCOL_VERSION],
        platform: PeerPlatform::Ios,
        installation_id: SwiftUuid(
            Uuid::parse_str("00000000-0000-4000-8000-000000000002").unwrap(),
        ),
        supported_raw_profiles: vec![
            RawProfile::CanonicalSourceRecordsV1,
            RawProfile::HealthDataProjection,
        ],
        supports_durable_jobs: true,
        supports_canonical_extraction: true,
        transfer: TransferCapabilities::default(),
        query: Some(DirectQueryCapabilities::current()),
        wake: None,
    };
    assert_eq!(
        serde_json::to_value(DirectMessage::Hello(Unlabeled::from(peer))).unwrap(),
        fixture.hello
    );

    let request = DirectQueryRequest {
        protocol_version: IOS_QUERY_APPLICATION_PROTOCOL_VERSION,
        request_id: request_id(),
        created_at: DateTime::parse_from_rfc3339("2023-11-14T22:13:20Z")
            .unwrap()
            .to_utc(),
        detail_level: DirectQueryDetailLevel::Summary,
        query: json!({
            "schema": "healthmd.query_request",
            "schema_version": 1,
            "metrics": {"type": "all_available"},
            "sources": {"type": "all_available"},
            "dates": {"type": "all_available"},
            "operation": {"type": "coverage"},
            "page": {"max_items": 250, "max_bytes": 262_144, "cursor": null}
        }),
    };
    assert_eq!(
        serde_json::to_value(DirectMessage::QueryRequest(Unlabeled::from(request))).unwrap(),
        fixture.query_request
    );

    let response = DirectQueryResponse {
        request_id: request_id(),
        response: json!({
            "schema": "healthmd.query_response",
            "schema_version": 1,
            "items": [],
            "packet": null,
            "coverage": {
                "status": "complete_empty",
                "days_considered": 0,
                "days_with_values": 0,
                "missing": []
            },
            "sources": [],
            "evidence": [],
            "next_cursor": null,
            "limitations": [],
            "metadata": {}
        }),
    };
    assert_eq!(
        serde_json::to_value(DirectMessage::QueryResponse(Unlabeled::from(response))).unwrap(),
        fixture.query_response
    );

    let failure = DirectQueryFailure {
        request_id: request_id(),
        code: "query_unavailable".to_owned(),
        message: "The iPhone could not complete the direct query.".to_owned(),
        retryable: true,
    };
    assert_eq!(
        serde_json::to_value(DirectMessage::QueryRejected(Unlabeled::from(failure))).unwrap(),
        fixture.query_rejected
    );
}
