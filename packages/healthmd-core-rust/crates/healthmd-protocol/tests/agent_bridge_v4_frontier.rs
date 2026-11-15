//! Independent Python vectors exercise actual Rust frontier state, never native commit evidence.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_protocol::v4::*;
use serde_json::Value;

fn fixture() -> Value {
    serde_json::from_str(include_str!("fixtures/agent-transfer-frontier-v1.json")).unwrap()
}
fn compute(case: &Value) -> Result<Vec<String>, Error> {
    let seed = &case["seed"];
    let mut frontier = TransferFrontier::new(
        &ControlUuid(seed["job_id"].as_str().unwrap().into()),
        &Digest(seed["request_sha256"].as_str().unwrap().into()),
        &Digest(seed["manifest_sha256"].as_str().unwrap().into()),
        &ControlUuid(seed["session_id"].as_str().unwrap().into()),
    )?;
    let mut actual = vec![frontier.sha256().0.clone()];
    let raw: Vec<Vec<u8>> = if let Some(raw) = case["raw_partitions_base64"].as_array() {
        raw.iter()
            .map(|v| STANDARD.decode(v.as_str().unwrap()).unwrap())
            .collect()
    } else {
        case["partitions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| serde_json::to_vec(v).unwrap())
            .collect()
    };
    for (index, bytes) in raw.iter().enumerate() {
        let partition: TransferFrontierPartition = decode_typed(bytes)?;
        frontier = frontier.appending(&partition)?;
        assert_eq!(
            frontier.committed_partition_count(),
            i64::try_from(index + 1).unwrap()
        );
        actual.push(frontier.sha256().0.clone());
    }
    Ok(actual)
}
#[test]
fn independent_frontier_vectors_and_raw_negatives() {
    let bundle = fixture();
    let cases = bundle["cases"].as_array().unwrap();
    assert!(cases.len() > 30);
    for case in cases {
        match compute(case) {
            Ok(actual) => {
                assert_eq!(case["expected"], "valid", "{}", case["id"]);
                assert_eq!(
                    serde_json::to_value(&actual).unwrap(),
                    case["prefix_sha256"],
                    "{}",
                    case["id"]
                );
                for (encoded, digest) in case["canonical_base64"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .zip(actual)
                {
                    assert_eq!(
                        sha256_hex(&STANDARD.decode(encoded.as_str().unwrap()).unwrap()),
                        digest
                    );
                }
            }
            Err(error) => assert_eq!(
                error.to_string(),
                case["expected"].as_str().unwrap(),
                "{}",
                case["id"]
            ),
        }
    }
}
#[test]
fn computed_prefix_is_immutable_and_rejects_duplicate_or_skipped_index() {
    let bundle = fixture();
    let case = bundle["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "two-artifacts")
        .unwrap();
    let seed = &case["seed"];
    let original = TransferFrontier::new(
        &ControlUuid(seed["job_id"].as_str().unwrap().into()),
        &Digest(seed["request_sha256"].as_str().unwrap().into()),
        &Digest(seed["manifest_sha256"].as_str().unwrap().into()),
        &ControlUuid(seed["session_id"].as_str().unwrap().into()),
    )
    .unwrap();
    let rows: Vec<TransferFrontierPartition> = case["partitions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| decode_typed(&serde_json::to_vec(v).unwrap()).unwrap())
        .collect();
    let next = original.appending(&rows[0]).unwrap();
    assert_eq!(original.committed_partition_count(), 0);
    assert_eq!(next.committed_partition_count(), 1);
    assert_eq!(next.appending(&rows[0]), Err(Error::BindingChanged));
    assert_eq!(original.appending(&rows[1]), Err(Error::BindingChanged));
    assert_eq!(
        next.appending(&rows[1]).unwrap().sha256().0,
        case["prefix_sha256"][2].as_str().unwrap()
    );
}
