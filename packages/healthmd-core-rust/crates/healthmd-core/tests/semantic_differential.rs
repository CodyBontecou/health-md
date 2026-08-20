use healthmd_core::{CoreError, semantic::SemanticSession};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};

const FIXTURE_BYTES: &[u8] = include_bytes!("fixtures/semantic-differential-v1.json");

#[derive(Debug, Deserialize)]
struct Fixture {
    schema: String,
    #[serde(rename = "fixture_version")]
    format_version: u32,
    semantic_input_version: u32,
    canonical_model_version: u32,
    registry_sha256: String,
    cases: Vec<Case>,
    rejection_cases: Vec<RejectionCase>,
}

#[derive(Debug, Deserialize)]
struct Case {
    id: String,
    features: Vec<String>,
    config: Value,
    batches: Vec<Value>,
    expected_result_sha256: String,
}

#[derive(Debug, Deserialize)]
struct RejectionCase {
    id: String,
    expected_error: String,
    feature: String,
}

fn run_case(case: &Case) -> Vec<u8> {
    let config = serde_json::to_vec(&case.config).expect("fixture config");
    let mut session = SemanticSession::from_json(&config).expect("valid fixture session");
    let mut result = Vec::new();
    for batch in &case.batches {
        result = session
            .process_batch(&serde_json::to_vec(batch).expect("fixture batch"), || false)
            .expect("valid fixture batch");
    }
    result
}

#[test]
#[allow(clippy::too_many_lines)]
fn canonical_cross_language_cases_match_exact_result_hashes() {
    let fixture: Fixture = serde_json::from_slice(FIXTURE_BYTES).expect("fixture JSON");
    assert_eq!(fixture.schema, "healthmd.semantic_differential_fixture");
    assert_eq!(fixture.format_version, 1);
    assert_eq!(fixture.semantic_input_version, 1);
    assert_eq!(fixture.canonical_model_version, 1);
    assert_eq!(fixture.registry_sha256, healthmd_core::REGISTRY_SHA256);
    assert_eq!(fixture.cases.len(), 3);

    let mut covered = fixture
        .cases
        .iter()
        .flat_map(|case| case.features.iter().map(String::as_str))
        .collect::<Vec<_>>();
    covered.extend(
        fixture
            .rejection_cases
            .iter()
            .map(|case| case.feature.as_str()),
    );
    for required in [
        "missing-versus-zero",
        "nanoseconds",
        "nullable-source-offset",
        "non-hour-offset",
        "dst-offset-transition",
        "iso-week-year-boundary",
        "blood-pressure-dependency",
        "state-of-mind-independent-views",
        "sleep-stage-platform-differences",
        "android-percentage-fraction",
        "vo2-latest-lower-value",
        "workout-duration-weighting",
        "unknown-extension-retention",
        "batch-boundary-invariance",
        "reject-nan-and-infinity",
        "batch-order-and-bounds",
        "cancellation-and-terminal-state",
    ] {
        assert!(
            covered.contains(&required),
            "missing fixture coverage: {required}"
        );
    }

    for case in &fixture.cases {
        let result = run_case(case);
        let actual = format!("{:x}", Sha256::digest(&result));
        assert_eq!(actual, case.expected_result_sha256, "case {}", case.id);
        let decoded: Value = serde_json::from_slice(&result).expect("result JSON");
        assert_eq!(decoded["state"], "completed");
        assert_eq!(decoded["core_api_version"], 3);
        assert_eq!(decoded["profile_revision"], 1);
        match case.id.as_str() {
            "apple-required-differentials" => {
                assert_eq!(decoded["records_filtered"], 2);
                let mut merged = case.batches[0].clone();
                merged["final_batch"] = Value::Bool(true);
                let mut records = merged["records"].as_array().expect("records").clone();
                records.extend(
                    case.batches[1]["records"]
                        .as_array()
                        .expect("records")
                        .clone(),
                );
                merged["records"] = Value::Array(records);
                let mut owner_dates = merged["owner_dates"]
                    .as_array()
                    .expect("owner dates")
                    .clone();
                owner_dates.extend(
                    case.batches[1]["owner_dates"]
                        .as_array()
                        .expect("owner dates")
                        .clone(),
                );
                owner_dates.sort_by_key(Value::to_string);
                owner_dates.dedup();
                merged["owner_dates"] = Value::Array(owner_dates);
                let merged_case = Case {
                    id: "merged-boundary-check".to_owned(),
                    features: vec![],
                    config: case.config.clone(),
                    batches: vec![merged],
                    expected_result_sha256: String::new(),
                };
                let merged_result: Value =
                    serde_json::from_slice(&run_case(&merged_case)).expect("merged result");
                assert_eq!(merged_result["days"], decoded["days"]);
                assert_eq!(merged_result["rollups"], decoded["rollups"]);
                assert_eq!(
                    merged_result["retained_extensions"],
                    decoded["retained_extensions"]
                );
                assert_eq!(decoded["days"].as_array().map(Vec::len), Some(4));
                for transition_date in ["2026-03-08", "2026-11-01"] {
                    assert!(decoded["days"].as_array().expect("days").iter().any(|day| {
                        day["owner_date"] == transition_date
                            && day["values"].as_array().is_some_and(|values| {
                                values.iter().any(|value| value["output_key"] == "steps")
                            })
                    }));
                }
                assert_eq!(decoded["rollups"][0]["start_date"], "2025-12-29");
                assert_eq!(decoded["rollups"][0]["end_date"], "2026-01-04");
                assert_eq!(
                    decoded["retained_extensions"].as_array().map(Vec::len),
                    Some(1)
                );
                let latest_vo2 = decoded["rollups"][0]["values"]
                    .as_array()
                    .and_then(|values| values.iter().find(|value| value["output_key"] == "vo2_max"))
                    .expect("VO2 rollup");
                assert_eq!(
                    latest_vo2["primary_value"]["number"]["bits"],
                    "4044000000000000"
                );
            }
            "android-fraction-and-exact-time" => {
                let values = decoded["days"][0]["values"].as_array().expect("values");
                for value in values.iter().filter(|value| {
                    matches!(
                        value["output_key"].as_str(),
                        Some("blood_oxygen" | "body_fat_percent")
                    )
                }) {
                    assert_eq!(value["value"]["unit"]["id"], "percent_0_100");
                }
                assert!(values.iter().any(|value| {
                    value["output_key"] == "sleep_deep_hours"
                        && value["value"]["unit"]["id"] == "hour"
                }));
                assert!(
                    !values
                        .iter()
                        .any(|value| value["output_key"] == "sleep_light_hours")
                );
            }
            "android-analytical-native-field" => {
                assert_eq!(decoded["profile"], "android_analytical_v5");
                assert_eq!(
                    decoded["days"][0]["values"][0]["output_key"],
                    "total_calories"
                );
            }
            _ => panic!("unreviewed differential case"),
        }
    }
}

#[test]
fn rejection_cases_are_enforced_without_private_values_in_errors() {
    let fixture: Fixture = serde_json::from_slice(FIXTURE_BYTES).expect("fixture JSON");
    let errors = fixture
        .rejection_cases
        .iter()
        .map(|case| (case.id.as_str(), case.expected_error.as_str()))
        .collect::<Vec<_>>();
    assert!(errors.contains(&("nonfinite-binary64", "invalid_semantic_batch")));
    assert!(errors.contains(&("sequence-and-limit-contract", "semantic_sequence_invalid")));
    assert!(errors.contains(&("cancellation-terminal", "semantic_session_terminal")));

    let apple = &fixture.cases[0];
    let config_bytes = serde_json::to_vec(&apple.config).expect("config");
    let mut invalid_session = SemanticSession::from_json(&config_bytes).expect("session");
    let mut nonfinite = apple.batches[0].clone();
    nonfinite["final_batch"] = Value::Bool(true);
    nonfinite["records"][0]["value"]["number"]["bits"] =
        Value::String("7ff8000000000000".to_owned());
    assert_eq!(
        invalid_session.process_batch(
            &serde_json::to_vec(&nonfinite).expect("nonfinite batch"),
            || false,
        ),
        Err(CoreError::InvalidSemanticBatch)
    );
    let mut out_of_order = apple.batches[0].clone();
    out_of_order["batch_index"] = Value::from(1);
    assert_eq!(
        invalid_session.process_batch(
            &serde_json::to_vec(&out_of_order).expect("sequence batch"),
            || false,
        ),
        Err(CoreError::SemanticSequenceInvalid)
    );

    let mut session = SemanticSession::from_json(&config_bytes).expect("session");
    let cancelled = session
        .process_batch(b"private-health-value", || true)
        .expect("cancel result");
    assert_eq!(
        serde_json::from_slice::<Value>(&cancelled).expect("JSON")["state"],
        "cancelled"
    );
    assert_eq!(
        session.process_batch(b"{}", || false),
        Err(CoreError::SemanticSessionTerminal)
    );
    assert_eq!(
        CoreError::SemanticSessionTerminal.code(),
        "semantic_session_terminal"
    );
    assert!(
        !CoreError::InvalidSemanticBatch
            .to_string()
            .contains("private")
    );
}
