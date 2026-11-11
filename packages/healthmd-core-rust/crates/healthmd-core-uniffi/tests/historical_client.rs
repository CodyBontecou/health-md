use healthmd_core_uniffi::{
    CoreMetricRegistryProfile, create_render_session, create_semantic_session,
    get_metric_registry_at_authority,
};
use serde_json::Value;

const SEMANTIC: &[u8] = include_bytes!(
    "../../../../contracts/semantic-input/v1/fixtures/historical-pre-v8-c77024b.json"
);
const RENDER: &[u8] =
    include_bytes!("../../../../contracts/render-input/v1/fixtures/historical-pre-v8-c77024b.json");

#[test]
fn coarse_native_clients_keep_original_authority_through_semantics_and_rendering() {
    let semantic: Value = serde_json::from_slice(SEMANTIC).unwrap();
    let render: Value = serde_json::from_slice(RENDER).unwrap();
    for (semantic_case, render_case) in semantic["cases"]
        .as_array()
        .unwrap()
        .iter()
        .zip(render["cases"].as_array().unwrap())
    {
        let profile = match semantic_case["config"]["profile"].as_str().unwrap() {
            "apple_health_data_v7" => CoreMetricRegistryProfile::AppleHealthDataV7,
            "android_frozen_v4" => CoreMetricRegistryProfile::AndroidFrozenV4,
            "android_analytical_v5" => CoreMetricRegistryProfile::AndroidAnalyticalV5,
            _ => panic!("unreviewed profile"),
        };
        let hash = semantic_case["config"]["registry_sha256"].as_str().unwrap();
        let snapshot = get_metric_registry_at_authority(profile, 1, hash.to_owned()).unwrap();
        assert_eq!(snapshot.registry_sha256, hash);
        let session =
            create_semantic_session(&serde_json::to_vec(&semantic_case["config"]).unwrap())
                .unwrap();
        let mut result = Vec::new();
        for batch in semantic_case["batches"].as_array().unwrap() {
            result = session
                .process_batch(&serde_json::to_vec(batch).unwrap())
                .unwrap();
        }
        let result: Value = serde_json::from_slice(&result).unwrap();
        assert_eq!(result["registry_sha256"], hash);
        let session = create_render_session(
            &serde_json::to_vec(&render_case["configuration"]).unwrap(),
            &serde_json::to_vec(&render_case["semantic_result"]).unwrap(),
        )
        .unwrap();
        for batch in render_case["batches"].as_array().unwrap() {
            session
                .process_batch(&serde_json::to_vec(batch).unwrap())
                .unwrap();
        }
        let plan = session.finish().unwrap();
        assert_eq!(plan.profile, profile);
        for (actual, expected) in plan
            .items
            .iter()
            .zip(render_case["expected_plan"]["items"].as_array().unwrap())
        {
            assert_eq!(actual.sha256, expected["sha256"].as_str().unwrap());
            assert_eq!(actual.byte_count, expected["byte_count"].as_u64().unwrap());
        }
        assert!(get_metric_registry_at_authority(profile, 1, "0".repeat(64)).is_err());
    }
}
