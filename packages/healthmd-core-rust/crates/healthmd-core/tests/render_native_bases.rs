use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_core::render::RenderSession;
use serde_json::Value;
use sha2::{Digest, Sha256};

const FIXTURE: &[u8] = include_bytes!("fixtures/native-android-bases-requests-v1.json");
const FIXTURE_SHA256: &str = "ca2ae035f280801c60e4bb6e3fff9f03a2c88022ce567ceed579b2ec49c3eb75";
const FULL_FIXTURE: &[u8] = include_bytes!("fixtures/native-android-render-requests-v1.json");
const FULL_FIXTURE_SHA256: &str =
    "4bdea95a034887e0869049537fbed77210fd2a619033bbdad37de2e4b7a72e67";

#[test]
fn all_android_profile_formats_match_independent_native_bytes() {
    assert_eq!(
        format!("{:x}", Sha256::digest(FULL_FIXTURE)),
        FULL_FIXTURE_SHA256
    );
    let fixture: Value = serde_json::from_slice(FULL_FIXTURE).expect("full fixture JSON");
    assert_eq!(fixture["schema"], "healthmd.native_render_requests");
    for case in fixture["cases"].as_array().expect("cases") {
        let config = serde_json::to_vec(&case["configuration"]).unwrap();
        let semantic = serde_json::to_vec(&case["semantic_result"]).unwrap();
        let mut session = RenderSession::from_json(&config, &semantic).expect("render session");
        for batch in case["batches"].as_array().unwrap() {
            session
                .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
                .expect("render batch");
        }
        let plan = session.finish(|| false).expect("artifact plan");
        let expected = case["expected_outputs"].as_array().unwrap();
        assert_eq!(plan.items.len(), expected.len(), "{}", case["id"]);
        for (item, expected) in plan.items.iter().zip(expected) {
            let bytes = STANDARD
                .decode(expected["bytes_base64"].as_str().unwrap())
                .unwrap();
            assert_eq!(
                item.relative_path, expected["relative_path"],
                "{}",
                case["id"]
            );
            assert_eq!(item.media_type, expected["media_type"], "{}", case["id"]);
            assert_eq!(item.content, bytes, "{}/{}", case["id"], expected["format"]);
            assert_eq!(item.byte_count, expected["byte_count"].as_u64().unwrap());
            assert_eq!(item.sha256, expected["sha256"].as_str().unwrap());
        }
    }
}

#[test]
fn android_profile_bases_match_independent_native_bytes() {
    assert_eq!(format!("{:x}", Sha256::digest(FIXTURE)), FIXTURE_SHA256);
    let fixture: Value = serde_json::from_slice(FIXTURE).expect("fixture JSON");
    assert_eq!(fixture["schema"], "healthmd.native_render_requests");
    for case in fixture["cases"].as_array().expect("cases") {
        let config = serde_json::to_vec(&case["configuration"]).unwrap();
        let semantic = serde_json::to_vec(&case["semantic_result"]).unwrap();
        let mut session = RenderSession::from_json(&config, &semantic).expect("render session");
        for batch in case["batches"].as_array().unwrap() {
            session
                .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
                .expect("render batch");
        }
        let plan = session.finish(|| false).expect("artifact plan");
        assert_eq!(plan.items.len(), 1, "{}", case["id"]);
        let item = &plan.items[0];
        let expected = STANDARD
            .decode(case["expected_bytes_base64"].as_str().unwrap())
            .unwrap();
        assert_eq!(item.relative_path, case["expected_relative_path"]);
        assert_eq!(item.media_type, case["expected_media_type"]);
        assert_eq!(item.content, expected, "{}", case["id"]);
        assert_eq!(
            item.byte_count,
            case["expected_byte_count"].as_u64().unwrap()
        );
        assert_eq!(item.sha256, case["expected_sha256"].as_str().unwrap());
    }
}
