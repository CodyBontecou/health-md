#![allow(
    clippy::format_collect,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]

use std::{collections::BTreeSet, fs, path::Path, sync::Arc};

use chrono::{Duration, NaiveDate, Utc};
use serde_json::{Value, json};
use tempfile::TempDir;
use tokio_util::sync::CancellationToken;

use crate::backend::{
    CallContext, CallerIdentity, CallerMode, HealthDataBackend, QueryDetailLevel, QueryPageRequest,
};

use super::{
    HostedConsentDetail, HostedConsentRequest, HostedConsentRevocationRequest, HostedDataBackend,
    HostedDataStore, HostedSyncDay, HostedSyncRequest,
};

#[test]
fn semantic_digest_cross_language_vector() {
    let value: Value = serde_json::from_str(
        r#"{"array":[1,9.9999999999999995e-08,-0,1e+20,1.2344999999999999],"bool":true,"null":null,"object":{"a":"é","z":"line\\nbreak"}}"#,
    )
    .unwrap();
    assert_eq!(
        super::store::semantic_json_digest(&value).unwrap(),
        "5d0d96bafe03fda7bf96bb30e2a2a036c56dc66587199b2b5aaae95b48d63543"
    );
}

#[test]
fn semantic_digest_cross_language_query_value_vector() {
    let value: Value = serde_json::from_str(
        r#"{"values":[{"type":"quantity","unit":"kg","value":1.5},{"seconds":60.25,"type":"duration"},{"type":"count","value":-2},{"type":"string","value":"é"},{"display":"High","identifier":"high","raw_value":7,"type":"category"},{"type":"boolean","value":true},{"type":"timestamp","value":"2026-07-01T12:34:56.000000000Z"},{"type":"date","value":"2026-07-01"},{"type":"array","value":[{"type":"count","value":1},{"type":"boolean","value":false}]}]}"#,
    )
    .unwrap();
    assert_eq!(
        super::store::semantic_json_digest(&value).unwrap(),
        "ed073cb3170128c3f5378e81c209434c213514060e144b8affde5bf9624eab08"
    );
}

#[test]
fn semantic_digest_cross_language_exponent_boundaries() {
    let value: Value = serde_json::from_str(
        r#"{"values":[0.00001,0.000001,1e-7,-0.00001,1e20,1.2345678901234567]}"#,
    )
    .unwrap();
    assert_eq!(
        super::store::semantic_json_digest(&value).unwrap(),
        "2f565ccf5c4028ef12f5860edf88e34647a3fa9a64e9150a6cdc61ef5bf4e989"
    );
}

#[tokio::test]
async fn consent_wire_rejects_duplicate_and_unknown_catalog_identifiers() {
    let duplicate = serde_json::from_value::<HostedConsentRequest>(json!({
        "revision":1,
        "allowed_metric_ids":["steps","steps"],
        "allowed_source_ids":["apple_health","healthmd_summary"],
        "allowed_provider_ids":[],
        "maximum_detail":"summary",
        "retention_days":30
    }));
    assert!(duplicate.is_err());

    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [1; 32]).unwrap();
    let error = store
        .set_consent(
            &caller("tenant", &["health.sync.write"]),
            consent(1, &["not_a_real_metric"], HostedConsentDetail::Summary),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "healthmd_consent_invalid");
}

#[test]
fn summary_projection_removes_every_lossless_field() {
    let mut day = json!({
        "evidence":[{"value":{"type":"count","value":1},"note":"private"}],
        "workouts":[{"details":{"energy":{"type":"count","value":2}}}],
        "sleep_sessions":[{"stage_intervals":[{"stage":"deep"}]}]
    });
    super::evaluator::project_summary_day(&mut day).unwrap();
    assert!(day.pointer("/evidence/0/value").is_none());
    assert!(day.pointer("/evidence/0/note").is_none());
    assert_eq!(day.pointer("/workouts/0/details"), Some(&json!({})));
    assert_eq!(
        day.pointer("/sleep_sessions/0/stage_intervals"),
        Some(&json!([]))
    );
}

fn caller(tenant: &str, scopes: &[&str]) -> CallerIdentity {
    CallerIdentity {
        subject: "owner-subject".to_owned(),
        tenant: Some(tenant.to_owned()),
        issuer: Some("https://issuer.example".to_owned()),
        scopes: scopes.iter().map(|value| (*value).to_owned()).collect(),
        mode: CallerMode::OAuth,
    }
}

fn consent(revision: u64, metrics: &[&str], detail: HostedConsentDetail) -> HostedConsentRequest {
    HostedConsentRequest {
        revision,
        allowed_metric_ids: metrics.iter().map(|value| (*value).to_owned()).collect(),
        allowed_source_ids: BTreeSet::from([
            "apple_health".to_owned(),
            "healthmd_summary".to_owned(),
        ]),
        allowed_provider_ids: BTreeSet::new(),
        maximum_detail: detail,
        retention_days: 30,
        expires_at: Some(Utc::now() + Duration::days(2)),
    }
}

fn synthetic_day(metrics: &[(&str, i64)]) -> Value {
    let now = Utc::now().date_naive();
    // Keep the full noon-to-noon sleep window in the past at every UTC hour.
    let date_value = now - Duration::days(2);
    let end_value = now - Duration::days(1);
    let date = date_value.format("%Y-%m-%d").to_string();
    let start = format!("{date}T00:00:00.000Z");
    let end = format!("{}T00:00:00.000Z", end_value.format("%Y-%m-%d"));
    json!({
        "schema":"healthmd.query_context_day",
        "schema_version":1,
        "owner_date":date,
        "interval_start":start,
        "interval_end":end,
        "calendar_timezone":"UTC",
        "source":{"schema":"fixture","schema_version":1,"digest":"0000000000000000000000000000000000000000000000000000000000000000"},
        "status":"available",
        "metrics":metrics.iter().enumerate().map(|(index,(id,value))| json!({
            "observation_id":format!("observation-{index}"),
            "metric_id":id,
            "display_name":id,
            "value":{"type":"count","value":value},
            "status":"available",
            "daily_aggregation":"sum",
            "evidence_ids":[],
            "limitations":[]
        })).collect::<Vec<_>>(),
        "workouts":[],
        "sleep_sessions":[],
        "evidence":[],
        "limitations":[]
    })
}

fn upload(revision: u64, day: Value) -> HostedSyncRequest {
    let digest_sha256 = super::store::semantic_json_digest(&day).unwrap();
    HostedSyncRequest {
        expected_consent_revision: revision,
        days: vec![HostedSyncDay { digest_sha256, day }],
    }
}

fn query(cursor: Option<String>, max_items: usize) -> QueryPageRequest {
    QueryPageRequest {
        query: json!({
            "schema":"healthmd.query_request",
            "schema_version":1,
            "metrics":{"type":"explicit","metric_ids":["heart_rate_avg","steps"]},
            "sources":{"type":"all_available"},
            "dates":{"type":"all_available"},
            "operation":{"type":"metric_series"},
            "page":{"max_items":max_items,"max_bytes":262_144,"cursor":cursor}
        }),
        detail_level: QueryDetailLevel::Summary,
    }
}

fn context(caller: CallerIdentity) -> CallContext {
    CallContext {
        caller,
        cancellation: CancellationToken::new(),
        session_id: None,
    }
}

fn all_file_bytes(path: &Path, output: &mut Vec<u8>) {
    for entry in fs::read_dir(path).unwrap() {
        let entry = entry.unwrap();
        if entry.file_type().unwrap().is_dir() {
            all_file_bytes(&entry.path(), output);
        } else {
            output.extend(fs::read(entry.path()).unwrap());
        }
    }
}

#[tokio::test]
async fn ciphertext_contains_no_plaintext_health_or_identity() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [7; 32]).unwrap();
    let owner = caller("tenant-secret", &["health.summary.read"]);
    store
        .set_consent(&owner, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    store
        .upload_days(&owner, upload(1, synthetic_day(&[("steps", 987_654)])))
        .await
        .unwrap();

    let mut bytes = Vec::new();
    all_file_bytes(root.path(), &mut bytes);
    let text = String::from_utf8_lossy(&bytes);
    assert!(!text.contains("steps"));
    assert!(!text.contains("987654"));
    assert!(!text.contains("owner-subject"));
    assert!(!text.contains("tenant-secret"));
    assert!(!text.contains(&Utc::now().date_naive().format("%Y-%m-%d").to_string()));
}

#[tokio::test]
async fn compact_day_validation_rejects_unknown_and_summary_lossless_fields() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [17; 32]).unwrap();
    let owner = caller("tenant", &["health.sync.write"]);
    store
        .set_consent(
            &owner,
            consent(
                1,
                &["steps", "workouts", "sleep_total"],
                HostedConsentDetail::Summary,
            ),
        )
        .await
        .unwrap();

    let mut unknown = synthetic_day(&[("steps", 1)]);
    unknown["unrecognized_health_field"] = json!({"value":42});
    assert_eq!(
        store
            .synchronize(&owner, upload(1, unknown))
            .await
            .unwrap_err()
            .code,
        "healthmd_sync_invalid"
    );

    let mut evidence = synthetic_day(&[("steps", 1)]);
    let source = evidence["source"].clone();
    evidence["metrics"][0]["evidence_ids"] = json!(["evidence-1"]);
    evidence["evidence"] = json!([{
        "reference":{
            "evidence_id":"evidence-1",
            "locator":{"type":"summary_key","owner_date":evidence["owner_date"],"key":"steps"},
            "source":source,
            "source_id":"healthmd_summary"
        },
        "note":"must not survive summary consent",
        "metric_ids":["steps"]
    }]);
    assert_eq!(
        store
            .synchronize(&owner, upload(1, evidence))
            .await
            .unwrap_err()
            .code,
        "healthmd_consent_violation"
    );

    let mut unreferenced = synthetic_day(&[("steps", 1)]);
    let source = unreferenced["source"].clone();
    unreferenced["evidence"] = json!([{
        "reference":{
            "evidence_id":"unreferenced",
            "locator":{"type":"summary_key","owner_date":unreferenced["owner_date"],"key":"steps"},
            "source":source,
            "source_id":"healthmd_summary"
        },
        "metric_ids":["steps"]
    }]);
    assert_eq!(
        store
            .synchronize(&owner, upload(1, unreferenced))
            .await
            .unwrap_err()
            .code,
        "healthmd_sync_invalid"
    );

    let mut empty_scope = synthetic_day(&[("steps", 1)]);
    let source = empty_scope["source"].clone();
    empty_scope["metrics"][0]["evidence_ids"] = json!(["empty-scope"]);
    empty_scope["evidence"] = json!([{
        "reference":{
            "evidence_id":"empty-scope",
            "locator":{"type":"summary_key","owner_date":empty_scope["owner_date"],"key":"steps"},
            "source":source,
            "source_id":"healthmd_summary"
        },
        "metric_ids":[]
    }]);
    assert_eq!(
        store
            .synchronize(&owner, upload(1, empty_scope))
            .await
            .unwrap_err()
            .code,
        "healthmd_sync_invalid"
    );

    let mut malformed_workout = synthetic_day(&[]);
    malformed_workout["workouts"] = json!([{
        "workout_id":"workout-1",
        "activity":"walking",
        "start":malformed_workout["interval_start"],
        "end":malformed_workout["interval_end"],
        "details":"not-an-object",
        "evidence_ids":[]
    }]);
    assert_eq!(
        store
            .synchronize(&owner, upload(1, malformed_workout))
            .await
            .unwrap_err()
            .code,
        "healthmd_sync_invalid"
    );

    let mut malformed_sleep = synthetic_day(&[]);
    malformed_sleep["sleep_sessions"] = json!([{
        "session_id":"sleep-1",
        "start":malformed_sleep["interval_start"],
        "end":malformed_sleep["interval_end"],
        "classification":"overnight",
        "completeness":"complete",
        "stage_intervals":"not-an-array",
        "aggregate_stage_durations_seconds":{},
        "evidence_ids":[],
        "limitations":[]
    }]);
    assert_eq!(
        store
            .synchronize(&owner, upload(1, malformed_sleep))
            .await
            .unwrap_err()
            .code,
        "healthmd_sync_invalid"
    );
}

#[tokio::test]
async fn overnight_sleep_uses_noon_window_and_stage_consent() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [21; 32]).unwrap();
    let owner = caller("tenant", &["health.sync.write"]);
    store
        .set_consent(
            &owner,
            consent(1, &["sleep_total"], HostedConsentDetail::Summary),
        )
        .await
        .unwrap();

    let mut day = synthetic_day(&[]);
    let owner_date = day["owner_date"].as_str().unwrap().to_owned();
    let next_date = (NaiveDate::parse_from_str(&owner_date, "%Y-%m-%d").unwrap()
        + Duration::days(1))
    .format("%Y-%m-%d")
    .to_string();
    day["sleep_sessions"] = json!([{
        "session_id":"sleep-overnight",
        "start":format!("{owner_date}T23:00:00.000Z"),
        "end":format!("{next_date}T07:00:00.000Z"),
        "classification":"overnight",
        "completeness":"aggregated",
        "stage_intervals":[],
        "aggregate_stage_durations_seconds":{"asleep_total":25_200.0},
        "evidence_ids":[],
        "limitations":[]
    }]);
    store
        .synchronize(&owner, upload(1, day.clone()))
        .await
        .unwrap();

    store
        .set_consent(
            &owner,
            consent(2, &["sleep_total"], HostedConsentDetail::Summary),
        )
        .await
        .unwrap();
    day["sleep_sessions"][0]["aggregate_stage_durations_seconds"] =
        json!({"asleep_total":25_200.0,"deep":3_600.0});
    assert_eq!(
        store
            .synchronize(&owner, upload(2, day))
            .await
            .unwrap_err()
            .code,
        "healthmd_consent_violation"
    );
}

#[tokio::test]
async fn summary_sleep_uses_aggregate_totals_without_fabricating_zero() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [22; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(
            &owner,
            consent(1, &["sleep_total"], HostedConsentDetail::Summary),
        )
        .await
        .unwrap();
    let mut day = synthetic_day(&[]);
    let owner_date = day["owner_date"].as_str().unwrap().to_owned();
    let next_date = (NaiveDate::parse_from_str(&owner_date, "%Y-%m-%d").unwrap()
        + Duration::days(1))
    .format("%Y-%m-%d")
    .to_string();
    day["sleep_sessions"] = json!([{
        "session_id":"sleep-summary",
        "start":format!("{owner_date}T23:00:00.000Z"),
        "end":format!("{next_date}T07:00:00.000Z"),
        "classification":"overnight",
        "completeness":"aggregated",
        "stage_intervals":[],
        "aggregate_stage_durations_seconds":{"asleep_total":25_200.0},
        "evidence_ids":[],
        "limitations":[]
    }]);
    store.synchronize(&owner, upload(1, day)).await.unwrap();
    let response = HostedDataBackend::new(store)
        .query_page(
            &context(owner),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["sleep_total"]},
                    "sources":{"type":"all_available"},
                    "dates":{"type":"all_available"},
                    "operation":{"type":"sleep_session_listing","include_naps":true},
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Summary,
            },
        )
        .await
        .unwrap();
    assert_eq!(
        response.pointer("/items/0/sleep_session/asleep_duration_seconds"),
        Some(&json!(25_200.0))
    );
    assert_eq!(
        response.pointer("/items/0/sleep_session/observed_duration_seconds"),
        Some(&json!(0.0))
    );
    assert_eq!(
        response.pointer("/items/0/sleep_session/untracked_duration_seconds"),
        Some(&json!(28_800.0))
    );
    assert_eq!(
        response.pointer("/items/0/sleep_session/calendar_dates"),
        Some(&json!([owner_date, next_date]))
    );
    assert_eq!(
        response.pointer("/items/0/sleep_session/local_start"),
        Some(&json!(format!("{owner_date}T23:00:00Z")))
    );
    assert_eq!(
        response.pointer("/items/0/sleep_session/local_end"),
        Some(&json!(format!("{next_date}T07:00:00Z")))
    );
}

#[tokio::test]
async fn selected_metric_failure_is_not_reported_as_complete_empty() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [35; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(&owner, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    let mut day = synthetic_day(&[("steps", 1)]);
    day["metrics"][0]["value"] = Value::Null;
    day["metrics"][0]["status"] = json!("failed");
    store.synchronize(&owner, upload(1, day)).await.unwrap();

    let mut failure_query = query(None, 25);
    failure_query.query["metrics"] = json!({"type":"explicit","metric_ids":["steps"]});
    let response = HostedDataBackend::new(store)
        .query_page(&context(owner), failure_query)
        .await
        .unwrap();
    assert_eq!(
        response.pointer("/coverage/status"),
        Some(&json!("partial"))
    );
    assert_eq!(
        response.pointer("/coverage/missing/0/status"),
        Some(&json!("failed"))
    );
}

#[tokio::test]
async fn exact_coverage_reports_and_compresses_unsynchronized_days() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [23; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(&owner, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    let day = synthetic_day(&[("steps", 1)]);
    let value_date =
        NaiveDate::parse_from_str(day["owner_date"].as_str().unwrap(), "%Y-%m-%d").unwrap();
    store.synchronize(&owner, upload(1, day)).await.unwrap();
    let start = (value_date - Duration::days(15))
        .format("%Y-%m-%d")
        .to_string();
    let end = (value_date + Duration::days(15))
        .format("%Y-%m-%d")
        .to_string();
    let response = HostedDataBackend::new(store)
        .query_page(
            &context(owner),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["steps"]},
                    "sources":{"type":"all_available"},
                    "dates":{"type":"exact","range":{"start_date":start,"end_date":end}},
                    "operation":{"type":"coverage"},
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Summary,
            },
        )
        .await
        .unwrap();
    assert_eq!(
        response.pointer("/coverage/status"),
        Some(&json!("partial"))
    );
    assert_eq!(
        response.pointer("/coverage/days_considered"),
        Some(&json!(31))
    );
    assert_eq!(
        response.pointer("/coverage/days_with_values"),
        Some(&json!(1))
    );
    assert_eq!(
        response.pointer("/coverage/missing/0/status"),
        Some(&json!("not_synchronized"))
    );
    assert_eq!(
        response.pointer("/coverage/missing/1/status"),
        Some(&json!("not_synchronized"))
    );
    assert_eq!(
        response
            .pointer("/coverage/missing")
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        2
    );
}

#[tokio::test]
async fn explicit_source_selection_filters_returned_evidence_references() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [36; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(&owner, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    let mut day = synthetic_day(&[("steps", 1)]);
    let source = day["source"].clone();
    let owner_date = day["owner_date"].clone();
    day["metrics"][0]["evidence_ids"] = json!(["apple", "summary"]);
    day["evidence"] = json!([
        {
            "reference":{
                "evidence_id":"apple",
                "locator":{"type":"summary_key","owner_date":owner_date,"key":"steps"},
                "source":source,
                "source_id":"apple_health"
            },
            "metric_ids":["steps"]
        },
        {
            "reference":{
                "evidence_id":"summary",
                "locator":{"type":"summary_key","owner_date":owner_date,"key":"steps"},
                "source":source,
                "source_id":"healthmd_summary"
            },
            "metric_ids":["steps"]
        }
    ]);
    store.synchronize(&owner, upload(1, day)).await.unwrap();
    let response = HostedDataBackend::new(store)
        .query_page(
            &context(owner),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["steps"]},
                    "sources":{"type":"explicit","source_ids":["healthmd_summary"],"provider_ids":[]},
                    "dates":{"type":"all_available"},
                    "operation":{"type":"metric_series"},
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Summary,
            },
        )
        .await
        .unwrap();
    assert_eq!(
        response.pointer("/items/0/metric/evidence"),
        Some(&json!([{
            "evidence_id":"summary",
            "locator":{"type":"summary_key","owner_date":owner_date,"key":"steps"},
            "source":source,
            "source_id":"healthmd_summary"
        }]))
    );
}

#[tokio::test]
async fn period_comparison_rejects_ranges_outside_top_level_dates() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [34; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(&owner, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    let day = synthetic_day(&[("steps", 1)]);
    let owner_date = day["owner_date"].as_str().unwrap().to_owned();
    let preceding = (NaiveDate::parse_from_str(&owner_date, "%Y-%m-%d").unwrap()
        - Duration::days(1))
    .format("%Y-%m-%d")
    .to_string();
    store.synchronize(&owner, upload(1, day)).await.unwrap();

    let error = HostedDataBackend::new(store)
        .query_page(
            &context(owner),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["steps"]},
                    "sources":{"type":"all_available"},
                    "dates":{"type":"exact","range":{"start_date":owner_date,"end_date":owner_date}},
                    "operation":{
                        "type":"period_comparison",
                        "first":{"start_date":preceding,"end_date":owner_date},
                        "second":{"start_date":owner_date,"end_date":owner_date},
                        "aggregations":[{"metric_id":"steps","kind":"sum"}]
                    },
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Summary,
            },
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "healthmd_query_invalid");
}

#[tokio::test]
async fn workout_and_sleep_coverage_respect_explicit_sources() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [25; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(
            &owner,
            consent(
                1,
                &["workouts", "sleep_total"],
                HostedConsentDetail::Summary,
            ),
        )
        .await
        .unwrap();
    let mut day = synthetic_day(&[]);
    let owner_date = day["owner_date"].as_str().unwrap().to_owned();
    let next_date = (NaiveDate::parse_from_str(&owner_date, "%Y-%m-%d").unwrap()
        + Duration::days(1))
    .format("%Y-%m-%d")
    .to_string();
    day["workouts"] = json!([{
        "workout_id":"workout-without-selected-source",
        "activity":"walking",
        "start":format!("{owner_date}T10:00:00.000Z"),
        "end":format!("{owner_date}T11:00:00.000Z"),
        "details":{},
        "evidence_ids":[]
    }]);
    day["sleep_sessions"] = json!([{
        "session_id":"sleep-without-selected-source",
        "start":format!("{owner_date}T23:00:00.000Z"),
        "end":format!("{next_date}T07:00:00.000Z"),
        "classification":"overnight",
        "completeness":"aggregated",
        "stage_intervals":[],
        "aggregate_stage_durations_seconds":{"asleep_total":25_200.0},
        "evidence_ids":[],
        "limitations":[]
    }]);
    store.synchronize(&owner, upload(1, day)).await.unwrap();
    let backend = HostedDataBackend::new(store);
    let response = backend
        .query_page(
            &context(owner.clone()),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["workouts","sleep_total"]},
                    "sources":{"type":"explicit","source_ids":["healthmd_summary"],"provider_ids":[]},
                    "dates":{"type":"all_available"},
                    "operation":{"type":"coverage"},
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Summary,
            },
        )
        .await
        .unwrap();
    assert_eq!(
        response.pointer("/coverage/status"),
        Some(&json!("complete_empty"))
    );
    assert_eq!(
        response.pointer("/coverage/days_with_values"),
        Some(&json!(0))
    );

    let sleep_response = backend
        .query_page(
            &context(owner),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["sleep_total"]},
                    "sources":{"type":"explicit","source_ids":["healthmd_summary"],"provider_ids":[]},
                    "dates":{"type":"all_available"},
                    "operation":{"type":"sleep_session_listing","include_naps":true},
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Summary,
            },
        )
        .await
        .unwrap();
    assert_eq!(
        sleep_response.pointer("/metadata/source_excluded_session_count"),
        Some(&json!(1))
    );
    assert_eq!(
        sleep_response.pointer("/metadata/excluded_session_count"),
        Some(&json!(1))
    );
}

#[tokio::test]
async fn pending_account_deletion_marker_recovers_after_key_removal() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [24; 32]).unwrap();
    let owner_identity = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(
            &owner_identity,
            consent(1, &["steps"], HostedConsentDetail::Summary),
        )
        .await
        .unwrap();
    store
        .synchronize(&owner_identity, upload(1, synthetic_day(&[("steps", 1)])))
        .await
        .unwrap();
    let owner = store.owner(&owner_identity).unwrap();
    let deletion_anchor = store.deleted_anchor(&owner).unwrap();
    store
        .write_generation_anchor(&owner, &deletion_anchor)
        .unwrap();
    let deletion_directory = root.path().join("ciphertext").join("deletions");
    fs::create_dir_all(&deletion_directory).unwrap();
    fs::write(
        deletion_directory.join(&owner.partition),
        format!("healthmd.hosted.account-deletion.v1\n{}\n", owner.partition),
    )
    .unwrap();
    fs::remove_file(owner.directory.join("owner-key.enc")).unwrap();

    assert_eq!(store.enforce_all_retention().await.unwrap(), 0);
    assert!(!owner.directory.exists());
    assert!(!deletion_directory.join(&owner.partition).exists());
    assert_eq!(
        store
            .status(&owner_identity)
            .await
            .unwrap()
            .synchronized_day_count,
        0
    );
}

#[tokio::test]
async fn legacy_summary_scope_never_exposes_lossless_sleep_intervals() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [28; 32]).unwrap());
    let owner = caller("tenant", &["healthmd:read"]);
    store
        .set_consent(
            &owner,
            consent(
                1,
                &["sleep_total", "sleep_deep"],
                HostedConsentDetail::Lossless,
            ),
        )
        .await
        .unwrap();
    let mut day = synthetic_day(&[]);
    let owner_date = day["owner_date"].as_str().unwrap().to_owned();
    let next_date = (NaiveDate::parse_from_str(&owner_date, "%Y-%m-%d").unwrap()
        + Duration::days(1))
    .format("%Y-%m-%d")
    .to_string();
    day["sleep_sessions"] = json!([{
        "session_id":"legacy-summary-sleep",
        "start":format!("{owner_date}T23:00:00.000Z"),
        "end":format!("{next_date}T07:00:00.000Z"),
        "classification":"overnight",
        "completeness":"complete",
        "stage_intervals":[{
            "stage":"deep",
            "start":format!("{next_date}T01:00:00.000Z"),
            "end":format!("{next_date}T02:00:00.000Z")
        }],
        "aggregate_stage_durations_seconds":{"asleep_total":25_200.0,"deep":3_600.0},
        "evidence_ids":[],
        "limitations":[]
    }]);
    store.synchronize(&owner, upload(1, day)).await.unwrap();
    let backend = HostedDataBackend::new(store);
    let response = backend
        .query_page(
            &context(owner.clone()),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["sleep_total","sleep_deep"]},
                    "sources":{"type":"all_available"},
                    "dates":{"type":"all_available"},
                    "operation":{"type":"sleep_session_listing","include_naps":true},
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Summary,
            },
        )
        .await
        .unwrap();
    assert_eq!(
        response.pointer("/items/0/sleep_session/observed_duration_seconds"),
        Some(&json!(0.0))
    );

    let detail_ids: Vec<String> = (0..=128).map(|index| format!("detail_{index}")).collect();
    let mut detail_owner = owner;
    detail_owner.scopes.insert("health.detail.read".to_owned());
    let error = backend
        .query_page(
            &context(detail_owner),
            QueryPageRequest {
                query: json!({
                    "schema":"healthmd.query_request",
                    "schema_version":1,
                    "metrics":{"type":"explicit","metric_ids":["sleep_total"]},
                    "sources":{"type":"all_available"},
                    "dates":{"type":"all_available"},
                    "operation":{"type":"derive_packet","kind":"training","detail_ids":detail_ids},
                    "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
                }),
                detail_level: QueryDetailLevel::Lossless,
            },
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "healthmd_query_invalid");
}

#[tokio::test]
async fn tenant_and_issuer_partitions_are_isolated() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [8; 32]).unwrap();
    let first = caller("tenant-a", &["health.summary.read"]);
    let second = caller("tenant-b", &["health.summary.read"]);
    let mut other_issuer = caller("tenant-a", &["health.summary.read"]);
    other_issuer.issuer = Some("https://other-issuer.example".to_owned());
    store
        .set_consent(&first, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    store
        .synchronize(&first, upload(1, synthetic_day(&[("steps", 1)])))
        .await
        .unwrap();
    assert_eq!(
        store.status(&first).await.unwrap().synchronized_day_count,
        1
    );
    assert_eq!(
        store.status(&second).await.unwrap().synchronized_day_count,
        0
    );
    assert_eq!(
        store
            .status(&other_issuer)
            .await
            .unwrap()
            .synchronized_day_count,
        0
    );
}

#[tokio::test]
async fn exact_consent_replay_is_idempotent_but_same_revision_conflicts_fail() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [26; 32]).unwrap();
    let owner = caller("tenant", &["health.account.manage"]);
    let policy = consent(1, &["steps"], HostedConsentDetail::Summary);
    let initial = store.set_consent(&owner, policy.clone()).await.unwrap();
    store
        .synchronize(&owner, upload(1, synthetic_day(&[("steps", 1)])))
        .await
        .unwrap();
    let before_replay = store.status(&owner).await.unwrap();

    let replay = store.set_consent(&owner, policy).await.unwrap();
    assert_eq!(replay.dataset_revision, before_replay.dataset_revision);
    assert_eq!(replay.synchronized_day_count, 1);
    assert_eq!(replay.purged_day_count, 0);
    assert!(replay.dataset_revision > initial.dataset_revision);

    let conflict = store
        .set_consent(
            &owner,
            consent(1, &["weight"], HostedConsentDetail::Summary),
        )
        .await
        .unwrap_err();
    assert_eq!(conflict.code, "healthmd_consent_revision_stale");
    assert_eq!(
        store.status(&owner).await.unwrap().synchronized_day_count,
        1
    );
}

#[tokio::test]
async fn consent_and_revocation_revisions_advance_by_exactly_one() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [27; 32]).unwrap();
    let owner = caller("tenant", &["health.account.manage"]);
    store
        .set_consent(&owner, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();

    let jump = store
        .set_consent(&owner, consent(3, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap_err();
    assert_eq!(jump.code, "healthmd_consent_revision_stale");
    let jump = store
        .revoke_consent(
            &owner,
            HostedConsentRevocationRequest {
                expected_revision: 1,
                revision: 3,
            },
        )
        .await
        .unwrap_err();
    assert_eq!(jump.code, "healthmd_consent_revision_stale");

    store
        .revoke_consent(
            &owner,
            HostedConsentRevocationRequest {
                expected_revision: 1,
                revision: 2,
            },
        )
        .await
        .unwrap();
    let jump = store
        .set_consent(
            &owner,
            consent(u64::MAX, &["steps"], HostedConsentDetail::Summary),
        )
        .await
        .unwrap_err();
    assert_eq!(jump.code, "healthmd_consent_revision_stale");
    store
        .set_consent(&owner, consent(3, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
}

#[tokio::test]
async fn consent_is_enforced_and_narrowing_purges_affected_days() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [9; 32]).unwrap();
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(
            &owner,
            consent(
                1,
                &["steps", "heart_rate_avg"],
                HostedConsentDetail::Summary,
            ),
        )
        .await
        .unwrap();
    store
        .synchronize(
            &owner,
            upload(1, synthetic_day(&[("steps", 1), ("heart_rate_avg", 2)])),
        )
        .await
        .unwrap();
    let result = store
        .replace_consent(&owner, consent(2, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    assert_eq!(result.purged_day_count, 1);
    assert_eq!(result.synchronized_day_count, 0);

    let error = store
        .synchronize(&owner, upload(2, synthetic_day(&[("heart_rate_avg", 3)])))
        .await
        .unwrap_err();
    assert_eq!(error.code, "healthmd_consent_violation");
}

#[tokio::test]
async fn upload_is_idempotent_and_delete_removes_wrapped_key_and_corpus() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [10; 32]).unwrap();
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(&owner, consent(1, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    let request = upload(1, synthetic_day(&[("steps", 5)]));
    let first = store.synchronize(&owner, request.clone()).await.unwrap();
    let second = store.synchronize(&owner, request).await.unwrap();
    assert_eq!(second.changed_day_count, 0);
    assert_eq!(second.unchanged_day_count, 1);
    assert_eq!(second.dataset_revision, first.dataset_revision);
    let binding_before_delete = store.status(&owner).await.unwrap().owner_binding;
    assert_eq!(binding_before_delete.len(), 64);
    assert!(
        binding_before_delete
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit())
    );
    store.delete_account(&owner).await.unwrap();
    let deleted_status = store.status(&owner).await.unwrap();
    assert_eq!(deleted_status.synchronized_day_count, 0);
    assert_eq!(deleted_status.owner_binding, binding_before_delete);

    let mut other_owner = owner.clone();
    other_owner.subject = "other-subject".to_owned();
    assert_ne!(
        store.status(&other_owner).await.unwrap().owner_binding,
        deleted_status.owner_binding
    );
}

#[tokio::test]
async fn retention_revocation_and_empty_subject_fail_closed() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [13; 32]).unwrap();
    let owner = caller("tenant", &["health.summary.read"]);
    let mut policy = consent(1, &["steps"], HostedConsentDetail::Summary);
    policy.retention_days = 1;
    store.set_consent(&owner, policy).await.unwrap();

    let mut old_day = synthetic_day(&[("steps", 1)]);
    let old_naive_date = Utc::now().date_naive() - Duration::days(3);
    let old_date = old_naive_date.format("%Y-%m-%d").to_string();
    let old_end = (old_naive_date + Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    old_day["owner_date"] = json!(old_date);
    old_day["interval_start"] = json!(format!("{old_date}T00:00:00.000Z"));
    old_day["interval_end"] = json!(format!("{old_end}T00:00:00.000Z"));
    assert_eq!(
        store
            .synchronize(&owner, upload(1, old_day))
            .await
            .unwrap_err()
            .code,
        "healthmd_consent_violation"
    );

    let owner_directory = fs::read_dir(root.path().join("ciphertext").join("v1"))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let key_before_revoke = fs::read(owner_directory.join("owner-key.enc")).unwrap();

    store
        .revoke_consent(
            &owner,
            HostedConsentRevocationRequest {
                expected_revision: 1,
                revision: 2,
            },
        )
        .await
        .unwrap();
    let revoked_status = store.status(&owner).await.unwrap();
    assert_eq!(revoked_status.consent_state, "missing");
    assert_eq!(revoked_status.consent_revision, Some(2));
    assert_ne!(
        fs::read(owner_directory.join("owner-key.enc")).unwrap(),
        key_before_revoke
    );
    store
        .set_consent(&owner, consent(3, &["steps"], HostedConsentDetail::Summary))
        .await
        .unwrap();
    assert_eq!(
        store.status(&owner).await.unwrap().consent_revision,
        Some(3)
    );

    let mut invalid = owner;
    invalid.subject.clear();
    assert_eq!(
        store.status(&invalid).await.unwrap_err().code,
        "healthmd_identity_invalid"
    );
}

#[tokio::test]
async fn scheduled_retention_sweep_purges_expired_consent_data() {
    let root = TempDir::new().unwrap();
    let store = HostedDataStore::new_test(root.path(), [19; 32]).unwrap();
    let owner = caller("tenant", &["health.sync.write"]);
    let mut policy = consent(1, &["steps"], HostedConsentDetail::Summary);
    policy.expires_at = Some(Utc::now() + Duration::seconds(2));
    store.set_consent(&owner, policy).await.unwrap();
    store
        .synchronize(&owner, upload(1, synthetic_day(&[("steps", 1)])))
        .await
        .unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(2_100)).await;
    assert_eq!(store.enforce_all_retention().await.unwrap(), 1);
    let status = store.status(&owner).await.unwrap();
    assert_eq!(status.consent_state, "expired");
    assert_eq!(status.synchronized_day_count, 0);
}

#[tokio::test]
async fn backend_enforces_scopes_and_cursor_authentication_and_staleness() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [11; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read"]);
    store
        .set_consent(
            &owner,
            consent(
                1,
                &["steps", "heart_rate_avg"],
                HostedConsentDetail::Summary,
            ),
        )
        .await
        .unwrap();
    store
        .synchronize(
            &owner,
            upload(1, synthetic_day(&[("steps", 1), ("heart_rate_avg", 2)])),
        )
        .await
        .unwrap();
    let backend = HostedDataBackend::new(store.clone());

    let denied = caller("tenant", &[]);
    assert_eq!(
        backend.readiness(&context(denied)).await.unwrap_err().code,
        "healthmd_scope_required"
    );
    let first = backend
        .query_page(&context(owner.clone()), query(None, 1))
        .await
        .unwrap();
    let cursor = first
        .get("next_cursor")
        .and_then(Value::as_str)
        .unwrap()
        .to_owned();
    let mut tampered = cursor.clone();
    tampered.push('A');
    assert_eq!(
        backend
            .query_page(&context(owner.clone()), query(Some(tampered), 1))
            .await
            .unwrap_err()
            .code,
        "healthmd_cursor_invalid"
    );

    store
        .synchronize(
            &owner,
            upload(1, synthetic_day(&[("steps", 8), ("heart_rate_avg", 9)])),
        )
        .await
        .unwrap();
    assert_eq!(
        backend
            .query_page(&context(owner), query(Some(cursor), 1))
            .await
            .unwrap_err()
            .code,
        "healthmd_cursor_stale"
    );
}

#[tokio::test]
async fn every_v1_operation_returns_a_valid_response_envelope() {
    let root = TempDir::new().unwrap();
    let store = Arc::new(HostedDataStore::new_test(root.path(), [12; 32]).unwrap());
    let owner = caller("tenant", &["health.summary.read", "health.detail.read"]);
    store
        .set_consent(
            &owner,
            consent(
                1,
                &["steps", "sleep_total", "workouts"],
                HostedConsentDetail::Lossless,
            ),
        )
        .await
        .unwrap();
    store
        .synchronize(&owner, upload(1, synthetic_day(&[("steps", 1)])))
        .await
        .unwrap();
    let backend = HostedDataBackend::new(store);
    let date = Utc::now().date_naive().format("%Y-%m-%d").to_string();
    let range = json!({"start_date":date,"end_date":date});
    let operations = vec![
        json!({"type":"metric_series"}),
        json!({"type":"workout_listing"}),
        json!({"type":"sleep_session_listing","include_naps":true}),
        json!({"type":"source_record_listing"}),
        json!({"type":"coverage"}),
        json!({"type":"period_comparison","first":range,"second":range,"aggregations":[{"metric_id":"steps","kind":"sum"}]}),
        json!({"type":"workout_sleep_alignment","include_naps":false}),
        json!({"type":"derive_packet","kind":"training","detail_ids":[]}),
    ];
    for operation in operations {
        let request = QueryPageRequest {
            query: json!({
                "schema":"healthmd.query_request",
                "schema_version":1,
                "metrics":{"type":"explicit","metric_ids":["steps","sleep_total","workouts"]},
                "sources":{"type":"all_available"},
                "dates":{"type":"all_available"},
                "operation":operation,
                "page":{"max_items":25,"max_bytes":262_144,"cursor":null}
            }),
            detail_level: QueryDetailLevel::Lossless,
        };
        let response = backend
            .query_page(&context(owner.clone()), request)
            .await
            .unwrap();
        assert_eq!(response["schema"], "healthmd.query_response");
        assert_eq!(response["schema_version"], 1);
    }
}
