use serde_json::{Value, json};
use uuid::Uuid;

use crate::history::{disclosure_message, validate_response};

pub(crate) const PEER: &str = "00000000-0000-4000-8000-000000000001";
pub(crate) const SOURCE: &str = "00000000-0000-4000-8000-000000000002";

// Synthetic grammar vector, not SDK/physical authorization or a real dataset digest.
pub(crate) fn response() -> Value {
    json!({
        "schema": "healthmd.query_response", "schema_version": 1,
        "items": [], "packet": null,
        "coverage": {"status": "complete_empty", "days_considered": 1, "days_with_values": 0, "missing": []},
        "sources": [], "evidence": [], "limitations": [], "next_cursor": null,
        "metadata": {"existing_metadata": "retained", "history_assessment": {
            "schema": "healthmd.history_assessment", "schema_version": 1,
            "assessment_id": "00000000-0000-4000-8000-000000000003",
            "capture_id": "00000000-0000-4000-8000-000000000004",
            "observed_at": "2026-01-01T00:00:00.123456789Z",
            "capture_completed_at": "2026-01-01T00:00:01.765432100Z",
            "evidence_method": "synthetic_ui_fixture", "producer": "Health.md",
            "platform": "apple_healthkit", "calendar_identifier": "gregorian",
            "time_zone_identifier": "America/Los_Angeles", "boundary_semantics": "sample_end_instant",
            "boundary_equality_physically_verified": false,
            "logical_metrics": {"type": "explicit", "metric_ids": ["steps"]},
            "resolved_metric_ids": ["steps"], "logical_sources": {"type": "all_available"},
            "resolved_source_ids": ["apple_health", "healthmd_summary"], "resolved_provider_ids": [],
            "logical_dates": {"type": "all_available"},
            "resolved_owner_dates": {"count": 1, "digest": "0".repeat(64), "first": "2026-01-01", "last": "2026-01-01"},
            "types": [{"type_id": "HKQuantityTypeIdentifierStepCount", "direct_metric_ids": ["steps"],
                "dependency_metric_ids": [], "dependency_reasons": [], "outcome": "unknown", "intersection": "unknown"}],
            "dataset_digest": "1".repeat(64), "trusted_peer_installation_id": PEER,
            "source_installation_id": SOURCE
        }}
    })
}

fn query() -> Value {
    json!({"metrics": {"type": "explicit", "metric_ids": ["steps"]}, "dates": {"type": "all_available"}})
}

fn valid(value: &Value, query: &Value) -> bool {
    validate_response(value, query, Uuid::parse_str(PEER).unwrap(), Uuid::parse_str(SOURCE).unwrap()).is_ok()
}

#[test]
fn recognized_observation_preserves_metadata_and_never_certifies_capture_coverage() {
    let mut value = response();
    let original = value.clone();
    let shared: Value = serde_json::from_str(include_str!("../../../../../packages/contracts/query-history/v1/synthetic-response.json")).unwrap();
    assert_eq!(shared, value);
    assert!(valid(&shared, &query()));
    assert!(valid(&value, &query()));
    assert_eq!(value, original);
    let message = disclosure_message(&value);
    assert!(message.contains("unknown 1"));
    assert!(message.contains("2026-01-01T00:00:00.123456789Z"));
    assert!(message.contains("America/Los_Angeles"));
    assert!(message.contains("not current permission"));
    assert!(message.contains("No full-history certification"));
    value["coverage"]["status"] = json!("available");
    assert_eq!(disclosure_message(&value), message);
    assert_eq!(value["metadata"]["existing_metadata"], "retained");
}

#[test]
fn absent_and_unknown_version_remain_legacy_or_unsupported_without_mutation() {
    let mut value = response();
    value["metadata"].as_object_mut().unwrap().remove("history_assessment");
    assert!(valid(&value, &query()));
    assert!(disclosure_message(&value).contains("legacy/unassessed"));
    let mut future = response();
    future["metadata"]["history_assessment"] = json!({"schema": "healthmd.history_assessment", "schema_version": 9, "opaque": ["future"]});
    let original = future.clone();
    assert!(valid(&future, &query()));
    assert_eq!(future, original);
    assert!(disclosure_message(&future).contains("unsupported assessment semantics"));
}

#[test]
fn recognized_malformed_outcomes_scope_calendar_and_binding_are_rejected() {
    let mutations = [
        ("/metadata/history_assessment/types/0/outcome", json!("full_history")),
        ("/metadata/history_assessment/types/0/intersection", json!("verified")),
        ("/metadata/history_assessment/types/0/direct_metric_ids", json!(["sleep_total"])),
        ("/metadata/history_assessment/types", json!([])),
        ("/metadata/history_assessment/calendar_identifier", json!("iso8601")),
        ("/metadata/history_assessment/time_zone_identifier", json!("")),
        ("/metadata/history_assessment/platform", json!("android")),
        ("/metadata/history_assessment/dataset_digest", json!("bad")),
        ("/metadata/history_assessment/observed_at", json!("2026-01-01")),
        ("/metadata/history_assessment/trusted_peer_installation_id", json!(SOURCE)),
        ("/metadata/history_assessment/source_installation_id", json!(PEER)),
        ("/metadata/history_assessment/resolved_owner_dates/count", json!(366_001)),
        ("/metadata/history_assessment/logical_dates", json!({"type": "exact", "range": {"start_date": "2026-01-01", "end_date": "2026-01-01"}})),
        ("/metadata/history_assessment", Value::Null),
    ];
    for (pointer, replacement) in mutations {
        let mut value = response();
        *value.pointer_mut(pointer).unwrap() = replacement;
        assert!(!valid(&value, &query()), "{pointer}");
    }
    let mut value = response();
    value["metadata"]["history_assessment"]["types"][0]["sample_end_boundary"] = json!("2026-01-01T00:00:00.000000000Z");
    assert!(!valid(&value, &query()));
}

#[test]
fn limited_boundary_unavailable_failure_and_unassessed_keep_distinct_meanings() {
    for outcome in ["limited", "unknown", "api_unavailable", "assessment_failed", "unassessed"] {
        let mut value = response();
        let row = &mut value["metadata"]["history_assessment"]["types"][0];
        row["outcome"] = json!(outcome);
        if outcome == "limited" {
            row["sample_end_boundary"] = json!("2026-01-01T00:00:00.123456789Z");
            row["intersection"] = json!("potential");
        }
        if outcome == "unassessed" { row["unassessed_reason"] = json!("special_api_eligibility_unverified"); }
        assert!(valid(&value, &query()));
        assert!(disclosure_message(&value).contains("No full-history certification"));
    }
}

#[test]
fn provider_only_scope_and_silent_type_truncation_are_rejected() {
    let mut value = response();
    let receipt = &mut value["metadata"]["history_assessment"];
    receipt["logical_sources"] = json!({"type": "explicit", "source_ids": ["provider_native"], "provider_ids": ["whoop"]});
    receipt["resolved_source_ids"] = json!(["provider_native"]);
    receipt["resolved_provider_ids"] = json!(["whoop"]);
    let mut scoped_query = query();
    scoped_query["sources"] = receipt["logical_sources"].clone();
    assert!(!valid(&value, &scoped_query));
    let mut value = response();
    let row = value["metadata"]["history_assessment"]["types"][0].clone();
    value["metadata"]["history_assessment"]["types"] = json!(vec![row; 513]);
    assert!(!valid(&value, &query()));
}
