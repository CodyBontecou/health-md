use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_core::render::{RenderError, RenderSession};
use serde_json::Value;
use sha2::{Digest, Sha256};

const FIXTURE: &[u8] = include_bytes!("fixtures/render-differential-v1.json");
const FIXTURE_SHA256: &str = "7c394c1aeda97c597afc1d1a6a3890671b1fc2f4b49b036bc060456b73e074d6";

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
fn apple_range_v9_is_separate_and_keeps_requested_failed_edge_bounds() {
    let fixture: Value = serde_json::from_slice(FIXTURE).expect("fixture JSON");
    let case = &fixture["cases"][0];
    let mut configuration = case["configuration"].clone();
    let mut semantic = case["semantic_result"].clone();
    let daily_step = semantic["days"][0]["values"]
        .as_array()
        .expect("daily values")
        .iter()
        .find(|value| value["output_key"] == "steps")
        .expect("steps")
        .clone();
    configuration["rollups"] = serde_json::json!({
        "generated_at":"2026-07-27T00:00:00Z",
        "metrics":{
            "steps":{
                "key":"steps","canonical_key":"steps","display_name":"Steps",
                "category":"Activity","unit":"count","notes":null,
                "statistic_order":["sum"]
            }
        }
    });
    semantic["rollups"] = serde_json::json!([{
        "period":"range",
        "start_date":"2026-07-24",
        "end_date":"2026-07-26",
        "calendar_time_zone":"Asia/Kathmandu",
        "source_dates":["2026-07-25"],
        "values":[{
            "output_key":"steps","rule":"sum",
            "primary_value":daily_step["value"].clone(),
            "days_counted":1,
            "statistics":{"sum":daily_step["value"].clone()}
        }]
    }]);

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
                "67703d45d8aa730d82bc94d0c01058471331f71c31ee8de6c4480787c8c605c6"
            ),
            (
                "Health/Rollups/JSON/Range/2026-07-24_to_2026-07-26.json",
                "72388dc94cb4537630b0c71a74e7fb965b0b5bdf41a7d0afd9efa30606185aec"
            ),
            (
                "Health/Rollups/Markdown/Range/2026-07-24_to_2026-07-26.md",
                "9c2358d6f7447a3607f71c6a66644ca898622fc4b7c03b18fcc2521e1d1c435a"
            ),
            (
                "Health/Rollups/Bases/Range/2026-07-24_to_2026-07-26.md",
                "a87b83a0b9fae409dfc86a4485369674e1cd8ea4ef73fed4f4843471ac21e37f"
            ),
        ]
    );
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
