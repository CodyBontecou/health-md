//! Python specification candidates are read-only; codec agreement is not native authority.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_protocol::v4::{canonical_json, parse_strict, sha256_hex};
use serde_json::Value;

fn fixture() -> Value {
    serde_json::from_str(include_str!(
        "../../../../contracts/agent-bridge/v1/fixtures/conformance.json"
    ))
    .expect("synthetic fixture must parse")
}

#[test]
fn generic_codec_agrees_with_all_58_python_candidates() {
    let fixture = fixture();
    let vectors = fixture["canonical_vectors"].as_array().unwrap();
    assert_eq!(vectors.len(), 58);
    for (index, vector) in vectors.iter().enumerate() {
        let bytes = canonical_json(&vector["value"]).unwrap();
        assert_eq!(
            STANDARD.encode(&bytes),
            vector["canonical_base64"],
            "vector {index}"
        );
        assert_eq!(sha256_hex(&bytes), vector["sha256"], "vector {index}");
        assert_eq!(
            parse_strict(&bytes).unwrap(),
            vector["value"],
            "vector {index}"
        );
    }
}

#[test]
fn raw_parser_rejects_before_duplicate_key_loss_or_float_coercion() {
    for raw in [
        br#"{"a":1,"a":2}"#.as_slice(),
        br#"{"a":{"x":1,"\u0078":2}}"#,
        br#"{"a":1.0}"#,
        br#"{"a":1e0}"#,
        br#"{"a":"\ud800"}"#,
        br#"{"a":NaN}"#,
        b"{\"a\":\"\xff\"}",
        b"{}{}",
    ] {
        let error = parse_strict(raw).unwrap_err();
        assert_eq!(error.to_string(), "invalid_request");
        assert_eq!(format!("{error:?}"), "InvalidRequest");
    }
}

#[test]
fn canonical_unicode_codepoint_order_and_lossless_integer() {
    let raw = "{\"😀\":1,\"\u{e000}\":2,\"é\":\"e\u{301}/\",\"version\":9223372036854775807}";
    let value = parse_strict(raw.as_bytes()).unwrap();
    assert_eq!(value["version"].as_i64(), Some(i64::MAX));
    assert_eq!(
        String::from_utf8(canonical_json(&value).unwrap()).unwrap(),
        "{\"version\":9223372036854775807,\"é\":\"e\u{301}/\",\"\u{e000}\":2,\"😀\":1}"
    );
}
