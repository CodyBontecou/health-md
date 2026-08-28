use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_core::render::{RenderError, RenderSession};
use serde_json::Value;
use sha2::{Digest, Sha256};

const FIXTURE: &[u8] = include_bytes!("fixtures/render-differential-v1.json");
const FIXTURE_SHA256: &str = "438f1b7c4a9e5fe108edd70d2d479b17f1f4696af5611eb68b0ee4bfde452eb2";
const RANGE_JSON: &[u8] =
    include_bytes!("../../../../contracts/rollup-summary/v9/fixtures/range-v9.json");
const RANGE_CSV: &[u8] =
    include_bytes!("../../../../contracts/rollup-summary/v9/fixtures/range-v9.csv");
const RANGE_MARKDOWN: &[u8] =
    include_bytes!("../../../../contracts/rollup-summary/v9/fixtures/range-v9.md");
const RANGE_BASES: &[u8] =
    include_bytes!("../../../../contracts/rollup-summary/v9/fixtures/range-v9-bases.md");

#[test]
fn all_profile_artifact_plans_match_exact_fixture_bytes() {
    assert_eq!(format!("{:x}", Sha256::digest(FIXTURE)), FIXTURE_SHA256);
    let fixture: Value = serde_json::from_slice(FIXTURE).expect("fixture JSON");
    assert_eq!(fixture["schema"], "healthmd.render_differential");
    for case in fixture["cases"].as_array().expect("cases") {
        let config = serde_json::to_vec(&case["configuration"]).unwrap();
        let semantic = serde_json::to_vec(&case["semantic_result"]).unwrap();
        let mut session = RenderSession::from_json(&config, &semantic).expect("session");
        for batch in case["batches"].as_array().unwrap() {
            session
                .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
                .expect("batch");
        }
        let plan = session.finish(|| false).expect("plan");
        let expected = &case["expected_plan"];
        assert_eq!(plan.schema, expected["schema"].as_str().unwrap());
        assert_eq!(
            plan.artifact_plan_version,
            u32::try_from(expected["artifact_plan_version"].as_u64().unwrap()).unwrap()
        );
        assert_eq!(plan.request_id, expected["request_id"].as_str().unwrap());
        assert_eq!(plan.session_id, expected["session_id"].as_str().unwrap());
        assert_eq!(
            plan.total_byte_count,
            expected["total_byte_count"].as_u64().unwrap()
        );
        let expected_items = expected["items"].as_array().unwrap();
        assert_eq!(plan.items.len(), expected_items.len());
        for (actual, expected) in plan.items.iter().zip(expected_items) {
            assert_eq!(
                actual.artifact_id,
                expected["artifact_id"].as_str().unwrap(),
                "{}/{}",
                case["id"],
                actual.relative_path
            );
            assert_eq!(
                actual.relative_path,
                expected["relative_path"].as_str().unwrap()
            );
            assert_eq!(actual.media_type, expected["media_type"].as_str().unwrap());
            assert_eq!(actual.byte_count, expected["byte_count"].as_u64().unwrap());
            assert_eq!(actual.sha256, expected["sha256"].as_str().unwrap());
            assert_eq!(
                actual.content,
                STANDARD
                    .decode(expected["content_base64"].as_str().unwrap())
                    .unwrap()
            );
        }
    }
}

#[test]
fn canonical_range_v9_contract_fixtures_are_exact_rust_production_output() {
    let fixture: Value = serde_json::from_slice(RANGE_JSON).expect("range JSON fixture");
    let (case, mut configuration, mut semantic) = range_render_case();
    configuration["formats"] = serde_json::json!(["markdown", "obsidian_bases", "json", "csv"]);
    configuration["calendar_time_zone"] = fixture["calendar_timezone"].clone();
    configuration["rollups"] = serde_json::json!({
        "generated_at": fixture["generated_at"],
        "metrics": fixture["metrics"].as_array().expect("metrics").iter().map(|metric| {
            (
                metric["key"].as_str().expect("key").to_owned(),
                serde_json::json!({
                    "key": metric["key"],
                    "canonical_key": metric["canonical_key"],
                    "display_name": metric["display_name"],
                    "category": metric["category"],
                    "unit": metric["unit"],
                    "notes": metric.get("notes").cloned().unwrap_or(Value::Null),
                    "statistic_order": metric["statistics"].as_array().expect("statistics")
                        .iter().map(|value| value["name"].clone()).collect::<Vec<_>>()
                })
            )
        }).collect::<serde_json::Map<_, _>>()
    });
    semantic["days"] = serde_json::json!([]);
    semantic["records_accepted"] = Value::from(0);
    semantic["records_filtered"] = Value::from(0);
    semantic["retained_extensions"] = serde_json::json!([]);
    semantic["rollups"] = serde_json::json!([{
        "period": "range",
        "start_date": fixture["start_date"],
        "end_date": fixture["end_date"],
        "calendar_time_zone": fixture["calendar_timezone"],
        "source_dates": fixture["source_dates"],
        "values": fixture["metrics"].as_array().expect("metrics").iter().map(|metric| {
            let statistics = metric["statistics"].as_array().expect("statistics").iter().map(|statistic| {
                (
                    match statistic["name"].as_str().expect("name") {
                        "daily_average" => "average_of_daily_values".to_owned(),
                        "minimum" => "minimum_daily_value".to_owned(),
                        "maximum" => "maximum_daily_value".to_owned(),
                        name => name.to_owned(),
                    },
                    serde_json::json!({"value_type":"text","text":statistic["value"]})
                )
            }).collect::<serde_json::Map<_, _>>();
            serde_json::json!({
                "output_key": metric["key"],
                "rule": metric["rule"],
                "primary_value": {"value_type":"text","text":metric["primary_value"]},
                "days_counted": metric["days_counted"],
                "statistics": statistics
            })
        }).collect::<Vec<_>>()
    }]);
    let mut session = RenderSession::from_json(
        &serde_json::to_vec(&configuration).unwrap(),
        &serde_json::to_vec(&semantic).unwrap(),
    )
    .expect("range fixture session");
    let mut batch = case["batches"][0].clone();
    batch["days"] = serde_json::json!([]);
    batch["final_batch"] = Value::Bool(true);
    session
        .process_batch(&serde_json::to_vec(&batch).unwrap(), || false)
        .unwrap();
    let plan = session.finish(|| false).expect("range fixture plan");
    for item in plan.items {
        let extension = std::path::Path::new(&item.relative_path)
            .extension()
            .and_then(std::ffi::OsStr::to_str);
        let expected = if extension.is_some_and(|value| value.eq_ignore_ascii_case("csv")) {
            RANGE_CSV
        } else if extension.is_some_and(|value| value.eq_ignore_ascii_case("json")) {
            RANGE_JSON
        } else if item.relative_path.contains("/Bases/") {
            RANGE_BASES
        } else {
            RANGE_MARKDOWN
        };
        assert_eq!(
            format!("{:x}", Sha256::digest(&item.content)),
            format!("{:x}", Sha256::digest(expected)),
            "{} ({} bytes vs {} bytes)",
            item.relative_path,
            item.content.len(),
            expected.len()
        );
    }
}

#[test]
fn apple_range_v9_is_separate_and_keeps_requested_failed_edge_bounds() {
    let (case, configuration, semantic) = range_render_case();
    let mut session = RenderSession::from_json(
        &serde_json::to_vec(&configuration).unwrap(),
        &serde_json::to_vec(&semantic).unwrap(),
    )
    .expect("range render session");
    for batch in case["batches"].as_array().expect("batches") {
        session
            .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
            .expect("batch");
    }
    let plan = session.finish(|| false).expect("range plan");
    let daily = plan
        .items
        .iter()
        .filter(|item| !item.relative_path.contains("/Rollups/"))
        .map(|item| (item.relative_path.as_str(), item.sha256.as_str()))
        .collect::<Vec<_>>();
    let frozen_daily = case["expected_plan"]["items"]
        .as_array()
        .expect("frozen daily items")
        .iter()
        .map(|item| {
            (
                item["relative_path"].as_str().expect("path"),
                item["sha256"].as_str().expect("sha256"),
            )
        })
        .collect::<Vec<_>>();
    assert_eq!(
        daily, frozen_daily,
        "range planning must not change daily v8 bytes"
    );
    let range = plan
        .items
        .iter()
        .filter(|item| item.relative_path.contains("/Rollups/"))
        .map(|item| (item.relative_path.as_str(), item.sha256.as_str()))
        .collect::<Vec<_>>();
    assert_eq!(
        range,
        [
            (
                "Health/Rollups/CSV/Range/2026-07-24_to_2026-07-26.csv",
                "a36069e8c1cd01f0c025f959241037dad6883f0ef2e9038494d6a7776a498729"
            ),
            (
                "Health/Rollups/JSON/Range/2026-07-24_to_2026-07-26.json",
                "20987088ad5f164a2dcd0178859648c28c61fc20ea289047c93b1c5f48e79066"
            ),
            (
                "Health/Rollups/Markdown/Range/2026-07-24_to_2026-07-26.md",
                "c12a1ce5b5d05d45feb1a94362a430d68b20bf201973ad26ee7a9ed20a21ca49"
            ),
            (
                "Health/Rollups/Bases/Range/2026-07-24_to_2026-07-26.md",
                "d6c8dd96ebbefda5d2da5c29be8594559ae6a71d2e31672298e41d331994bb85"
            ),
        ]
    );
}

#[test]
fn apple_range_v9_rejects_invalid_revision_coverage_and_contents() {
    let (case, configuration, semantic) = range_render_case();
    let mut revision_one_config = configuration.clone();
    let mut revision_one_semantic = semantic.clone();
    revision_one_config["profile_revision"] = Value::from(1);
    revision_one_semantic["profile_revision"] = Value::from(1);
    assert_eq!(
        RenderSession::from_json(
            &serde_json::to_vec(&revision_one_config).unwrap(),
            &serde_json::to_vec(&revision_one_semantic).unwrap(),
        )
        .unwrap_err(),
        RenderError::InvalidSemanticResult
    );

    let mut mixed_revision_two = semantic.clone();
    mixed_revision_two["rollups"][0]["period"] = Value::String("iso_week".to_owned());
    assert_eq!(
        RenderSession::from_json(
            &serde_json::to_vec(&configuration).unwrap(),
            &serde_json::to_vec(&mixed_revision_two).unwrap(),
        )
        .unwrap_err(),
        RenderError::InvalidSemanticResult
    );

    let finish_error = |invalid_semantic: &Value| {
        let mut invalid_session = RenderSession::from_json(
            &serde_json::to_vec(&configuration).unwrap(),
            &serde_json::to_vec(invalid_semantic).unwrap(),
        )
        .expect("structurally valid range session");
        for batch in case["batches"].as_array().expect("batches") {
            invalid_session
                .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
                .expect("batch");
        }
        invalid_session.finish(|| false).unwrap_err()
    };

    let mut duplicate_dates = semantic.clone();
    duplicate_dates["rollups"][0]["source_dates"] = serde_json::json!(["2026-07-25", "2026-07-25"]);
    assert_eq!(
        finish_error(&duplicate_dates),
        RenderError::InvalidSemanticResult
    );

    let mut empty_metrics = semantic.clone();
    empty_metrics["rollups"][0]["values"] = serde_json::json!([]);
    assert_eq!(
        finish_error(&empty_metrics),
        RenderError::InvalidSemanticResult
    );

    let mut excessive_metric_coverage = semantic.clone();
    excessive_metric_coverage["rollups"][0]["values"][0]["days_counted"] = Value::from(2);
    assert_eq!(
        finish_error(&excessive_metric_coverage),
        RenderError::InvalidSemanticResult
    );
}

fn range_render_case() -> (Value, Value, Value) {
    let fixture: Value = serde_json::from_slice(FIXTURE).expect("fixture JSON");
    let case = fixture["cases"][0].clone();
    let mut configuration = case["configuration"].clone();
    let mut semantic = case["semantic_result"].clone();
    let daily_step = semantic["days"][0]["values"]
        .as_array()
        .expect("daily values")
        .iter()
        .find(|value| value["output_key"] == "steps")
        .expect("steps")
        .clone();
    configuration["profile_revision"] = Value::from(2);
    semantic["profile_revision"] = Value::from(2);
    configuration["rollups"] = serde_json::json!({
        "generated_at":"2026-07-27T00:00:00Z",
        "metrics":{"steps":{
            "key":"steps","canonical_key":"steps","display_name":"Steps",
            "category":"Activity","unit":"count","notes":null,"statistic_order":["sum"]
        }}
    });
    semantic["rollups"] = serde_json::json!([{
        "period":"range","start_date":"2026-07-24","end_date":"2026-07-26",
        "calendar_time_zone":"Asia/Kathmandu","source_dates":["2026-07-25"],
        "values":[{
            "output_key":"steps","rule":"sum","primary_value":daily_step["value"].clone(),
            "days_counted":1,"statistics":{"sum":daily_step["value"].clone()}
        }]
    }]);
    (case, configuration, semantic)
}

#[test]
fn fixture_rejections_are_transactional_and_health_free() {
    let fixture: Value = serde_json::from_slice(FIXTURE).unwrap();
    let case = &fixture["cases"][0];
    let config = serde_json::to_vec(&case["configuration"]).unwrap();
    let semantic = serde_json::to_vec(&case["semantic_result"]).unwrap();
    let mut session = RenderSession::from_json(&config, &semantic).unwrap();
    let mut invalid = case["batches"][0].clone();
    invalid["days"][0]["metrics"][0]["output_key"] = Value::String("private-value".to_owned());
    let error = session
        .process_batch(&serde_json::to_vec(&invalid).unwrap(), || false)
        .unwrap_err();
    assert_eq!(error, RenderError::PresentationMismatch);
    assert!(!error.to_string().contains("private-value"));
    session
        .process_batch(&serde_json::to_vec(&case["batches"][0]).unwrap(), || false)
        .unwrap();
    assert!(session.finish(|| false).is_ok());

    let mut wrong_version = case["configuration"].clone();
    wrong_version["render_input_version"] = Value::from(2);
    assert_eq!(
        RenderSession::from_json(&serde_json::to_vec(&wrong_version).unwrap(), &semantic)
            .unwrap_err(),
        RenderError::UnsupportedRenderInputVersion,
    );
}
