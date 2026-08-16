use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_core::render::{RenderError, RenderSession};
use serde_json::Value;
use sha2::{Digest, Sha256};

const FIXTURE: &[u8] = include_bytes!("fixtures/render-differential-v1.json");
const FIXTURE_SHA256: &str = "03a3c4499358dec37bf76269e62ccfd5a1b7fc2a8fd9aa43f0bee713c1d28a22";

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
