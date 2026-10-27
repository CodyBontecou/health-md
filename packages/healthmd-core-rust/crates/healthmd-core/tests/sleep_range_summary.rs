use healthmd_core::{
    SLEEP_REGISTRY_SHA256,
    render::RenderSession,
    semantic::{SemanticResult, SemanticSession},
};
use serde_json::{Value, json};

#[test]
fn apple_wake_date_range_preserves_requested_bounds_empty_days_and_public_authority() {
    let input: Value = serde_json::from_slice(include_bytes!(
        "../../../../contracts/render-input/v2/fixtures/native-android-v6-handoff.json"
    ))
    .unwrap();
    let mut config = input["semantic_configuration"].clone();
    config["profile"] = json!("apple_health_data_v11");
    config["profile_revision"] = json!(2);
    config["calendar_time_zone"] = json!("America/New_York");
    config["selected_selection_ids"] = json!(["sleep_total"]);
    config["rollup_periods"] = json!(["range"]);
    config["rollup_range"] = json!({"start_date":"2026-10-31", "end_date":"2026-11-03"});
    let mut batch = input["semantic_batches"][0].clone();
    batch["owner_dates"] = json!(["2026-11-01", "2026-11-02"]);
    let mut record = batch["records"][0].clone();
    record["owner_date"] = json!("2026-11-01");
    batch["records"] = json!([record]);
    let mut session = SemanticSession::from_json(&serde_json::to_vec(&config).unwrap())
        .expect("Apple v11 range capability");
    let semantic_bytes = session
        .process_batch(&serde_json::to_vec(&batch).unwrap(), || false)
        .unwrap();
    let semantic: SemanticResult = serde_json::from_slice(&semantic_bytes).unwrap();
    assert_eq!(semantic.rollups.len(), 1);
    let range = &semantic.rollups[0];
    assert_eq!(range.start_date, "2026-10-31");
    assert_eq!(range.end_date, "2026-11-03");
    assert_eq!(range.source_dates, ["2026-11-01", "2026-11-02"]);
    assert_eq!(range.values[0].days_counted, 1);

    let mut render_config = input["render_configuration"].clone();
    render_config["profile"] = config["profile"].clone();
    render_config["profile_revision"] = json!(2);
    render_config["registry_sha256"] = json!(SLEEP_REGISTRY_SHA256);
    render_config["calendar_time_zone"] = config["calendar_time_zone"].clone();
    render_config["rollups"] = json!({"generated_at":"2026-11-04T12:00:00Z", "metrics": {
        "sleep_total_hours": {"key":"sleep_total_hours", "canonical_key":"sleep_total_hours",
        "display_name":"Total Sleep", "category":"Sleep", "unit":"hours",
        "statistic_order":["daily_average", "minimum", "maximum"], "notes":null}
    }});
    let mut render_batch = input["render_batches"][0].clone();
    let mut day = render_batch["days"][0].clone();
    day["owner_date"] = json!("2026-11-01");
    day["title"] = json!("2026-11-01");
    day["metrics"] = json!([day["metrics"][0].clone()]);
    let mut empty = day.clone();
    empty["owner_date"] = json!("2026-11-02");
    empty["title"] = json!("2026-11-02");
    empty["metrics"] = json!([]);
    render_batch["days"] = json!([day, empty]);
    let mut renderer = RenderSession::from_json(
        &serde_json::to_vec(&render_config).unwrap(),
        &serde_json::to_vec(&semantic).unwrap(),
    )
    .expect("successor range renderer");
    renderer
        .process_batch(&serde_json::to_vec(&render_batch).unwrap(), || false)
        .unwrap();
    let plan = renderer.finish(|| false).unwrap();
    let summaries = plan
        .items
        .iter()
        .filter(|item| item.relative_path.contains("/rollups/Range/"))
        .collect::<Vec<_>>();
    assert_eq!(summaries.len(), 4);
    for item in summaries {
        if let Ok(directory) = std::env::var("HEALTHMD_WAKE_DATE_RANGE_FIXTURE_DIR") {
            let suffix = if item.relative_path.ends_with("-bases.md") {
                "-bases.md"
            } else if has_extension(&item.relative_path, "md") {
                ".md"
            } else if has_extension(&item.relative_path, "csv") {
                ".csv"
            } else {
                ".json"
            };
            std::fs::create_dir_all(&directory).unwrap();
            std::fs::write(
                std::path::Path::new(&directory).join(format!("range-v11{suffix}")),
                &item.content,
            )
            .unwrap();
        }
        let text = std::str::from_utf8(&item.content)
            .unwrap()
            .replace("\\/", "/");
        assert!(text.contains("morning_ends"));
        assert!(text.contains("session_end_date"));
        assert!(text.contains("America/New_York"));
        assert!(text.contains("apple-v11"));
        if has_extension(&item.relative_path, "json") {
            let summary: Value = serde_json::from_slice(&item.content).unwrap();
            assert_eq!(summary["schema_version"], 11);
            assert_eq!(summary["source_schema_version"], 11);
            assert_eq!(summary["rollup_rules_version"], 11);
            assert_eq!(summary["days_expected"], 4);
            assert_eq!(summary["days_counted"], 2);
            assert_eq!(summary["coverage_percent"], 50.0);
            assert_eq!(summary["metrics"][0]["primary_value"], "8.25");
            assert_eq!(summary["time_context"]["sleep_interval_clipping"], "none");
        }
    }
}

fn has_extension(path: &str, expected: &str) -> bool {
    std::path::Path::new(path)
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case(expected))
}

#[test]
fn successor_range_authority_does_not_admit_calendar_or_downgraded_sessions() {
    let input: Value = serde_json::from_slice(include_bytes!(
        "../../../../contracts/render-input/v2/fixtures/native-android-v6-handoff.json"
    ))
    .unwrap();
    let mut config = input["semantic_configuration"].clone();
    config["profile"] = json!("apple_health_data_v11");
    config["rollup_periods"] = json!(["iso_week"]);
    assert!(SemanticSession::from_json(&serde_json::to_vec(&config).unwrap()).is_err());
    config["rollup_periods"] = json!(["range"]);
    config["rollup_range"] = json!({"start_date":"2026-10-31", "end_date":"2026-11-03"});
    config["profile_revision"] = json!(1);
    assert!(SemanticSession::from_json(&serde_json::to_vec(&config).unwrap()).is_err());
    config["profile_revision"] = json!(2);
    config["semantic_input_version"] = json!(1);
    assert!(SemanticSession::from_json(&serde_json::to_vec(&config).unwrap()).is_err());
}
