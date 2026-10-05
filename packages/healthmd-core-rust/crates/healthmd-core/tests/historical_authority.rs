use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_core::{render::RenderSession, semantic::SemanticSession};
use serde_json::Value;
use sha2::{Digest, Sha256};

// Exact git objects from c77024b87170260531f8df8fc5b604ad35375466; never regenerate.
const SEMANTIC: &[u8] = include_bytes!(
    "../../../../contracts/semantic-input/v1/fixtures/historical-pre-v8-c77024b.json"
);
const RENDER: &[u8] =
    include_bytes!("../../../../contracts/render-input/v1/fixtures/historical-pre-v8-c77024b.json");

#[test]
fn historical_semantic_clients_reproduce_original_authority_and_result_bytes() {
    assert_eq!(
        format!("{:x}", Sha256::digest(SEMANTIC)),
        "0f5c8dfc6e52759c7b671082bfd5121253f1907d5af97ad1ec4f2c6bb9fefb7e"
    );
    let fixture: Value = serde_json::from_slice(SEMANTIC).unwrap();
    for case in fixture["cases"].as_array().unwrap() {
        let mut session = SemanticSession::from_json(&serde_json::to_vec(&case["config"]).unwrap())
            .unwrap_or_else(|error| panic!("{}: {error}", case["id"]));
        let mut result = Vec::new();
        for batch in case["batches"].as_array().unwrap() {
            result = session
                .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
                .unwrap();
        }
        assert_eq!(
            format!("{:x}", Sha256::digest(&result)),
            case["expected_result_sha256"].as_str().unwrap(),
            "{}",
            case["id"]
        );
        let result: Value = serde_json::from_slice(&result).unwrap();
        assert_eq!(result["registry_sha256"], case["config"]["registry_sha256"]);
        assert_eq!(result["profile"], case["config"]["profile"]);
    }
}

#[test]
fn historical_render_clients_reproduce_every_original_artifact_byte() {
    assert_eq!(
        format!("{:x}", Sha256::digest(RENDER)),
        "59fee27e488f76da193d8013fba4ff82d76887fe12df45439ea7de286feb4bc3"
    );
    let fixture: Value = serde_json::from_slice(RENDER).unwrap();
    for case in fixture["cases"].as_array().unwrap() {
        let mut session = RenderSession::from_json(
            &serde_json::to_vec(&case["configuration"]).unwrap(),
            &serde_json::to_vec(&case["semantic_result"]).unwrap(),
        )
        .unwrap_or_else(|error| panic!("{}: {error}", case["id"]));
        for batch in case["batches"].as_array().unwrap() {
            session
                .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
                .unwrap();
        }
        let plan = session.finish(|| false).unwrap();
        let expected = case["expected_plan"]["items"].as_array().unwrap();
        assert_eq!(plan.items.len(), expected.len());
        assert_eq!(
            plan.total_byte_count,
            case["expected_plan"]["total_byte_count"].as_u64().unwrap()
        );
        for (actual, expected) in plan.items.iter().zip(expected) {
            assert_eq!(
                actual.artifact_id,
                expected["artifact_id"].as_str().unwrap()
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
fn historical_clients_reject_unknown_and_crossed_authorities() {
    let semantic: Value = serde_json::from_slice(SEMANTIC).unwrap();
    let render: Value = serde_json::from_slice(RENDER).unwrap();
    for hash in [
        String::new(),
        "0".repeat(64),
        healthmd_core::authority::HISTORICAL_REGISTRY_SHA256.to_uppercase(),
    ] {
        let mut config = semantic["cases"][0]["config"].clone();
        config["registry_sha256"] = Value::String(hash.clone());
        assert!(SemanticSession::from_json(&serde_json::to_vec(&config).unwrap()).is_err());
        let mut configuration = render["cases"][0]["configuration"].clone();
        let mut result = render["cases"][0]["semantic_result"].clone();
        configuration["registry_sha256"] = Value::String(hash.clone());
        result["registry_sha256"] = Value::String(hash);
        assert!(
            RenderSession::from_json(
                &serde_json::to_vec(&configuration).unwrap(),
                &serde_json::to_vec(&result).unwrap()
            )
            .is_err()
        );
    }
    let mut incompatible = semantic["cases"][0]["config"].clone();
    incompatible["profile_revision"] = Value::from(2);
    assert!(SemanticSession::from_json(&serde_json::to_vec(&incompatible).unwrap()).is_err());
    incompatible["profile_revision"] = Value::from(1);
    incompatible["profile"] = Value::String("apple_health_data_v8".to_owned());
    assert!(SemanticSession::from_json(&serde_json::to_vec(&incompatible).unwrap()).is_err());
    for hash in ["0".repeat(64), healthmd_core::REGISTRY_SHA256.to_owned()] {
        let case = &render["cases"][0];
        let mut config = case["configuration"].clone();
        config["registry_sha256"] = Value::String(hash);
        assert!(
            RenderSession::from_json(
                &serde_json::to_vec(&config).unwrap(),
                &serde_json::to_vec(&case["semantic_result"]).unwrap()
            )
            .is_err()
        );
    }
}
