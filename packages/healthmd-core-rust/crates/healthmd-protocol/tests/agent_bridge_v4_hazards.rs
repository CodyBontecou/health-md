use healthmd_protocol::v4::*;
use serde_json::{Value, json};

fn invalid(raw: &[u8]) {
    assert_eq!(parse_strict(raw).unwrap_err(), Error::InvalidRequest);
}

#[test]
fn signed_unsigned_integer_edges_and_negative_zero_policy() {
    for raw in [
        "-9223372036854775808",
        "9223372036854775807",
        "18446744073709551615",
        "9007199254740993",
    ] {
        assert_eq!(
            canonical_json(&parse_strict(raw.as_bytes()).unwrap()).unwrap(),
            raw.as_bytes()
        );
    }
    for raw in [
        "-9223372036854775809",
        "18446744073709551616",
        "-0.0",
        "0e0",
        "-0e0",
        "01",
        "-01",
        "+1",
    ] {
        invalid(raw.as_bytes());
    }
    assert_eq!(canonical_json(&parse_strict(b"-0").unwrap()).unwrap(), b"0");
    assert_eq!(
        canonical_json(&parse_strict(br#"{"decimal":"-0"}"#).unwrap()).unwrap(),
        br#"{"decimal":"-0"}"#
    );
    assert!(canonical_json(&json!({"float": -0.0})).is_err());
    for number in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, -0.0, 0.0] {
        assert_eq!(
            canonical_json(&[number]).unwrap_err(),
            Error::InvalidRequest
        );
    }
    for field in [Value::Bool(false), json!(0.0), Value::Null, json!(-1)] {
        let mut raw = json!({"health_reads":0,"earliest_date_reads":0,"content_preview_reads":0,"output_writes":0,"quota_consumed":0,"settings_mutations":0,"credential_enrollments":0,"wake_enrollments":0});
        raw["health_reads"] = field;
        assert_eq!(
            decode_typed::<ZeroSideEffects>(&serde_json::to_vec(&raw).unwrap()).unwrap_err(),
            Error::InvalidRequest
        );
    }
}

#[test]
fn raw_outer_depth_node_string_and_collection_bounds() {
    invalid(&vec![b' '; 2 * 1024 * 1024 + 1]);
    invalid(format!("{}0{}", "[".repeat(25), "]".repeat(25)).as_bytes());
    assert!(parse_strict(format!("{}0{}", "[".repeat(24), "]".repeat(24)).as_bytes()).is_ok());
    invalid(format!("[{}]", vec!["0"; 4097].join(",")).as_bytes());
    let object = (0..513)
        .map(|i| format!("\"k{i}\":0"))
        .collect::<Vec<_>>()
        .join(",");
    invalid(format!("{{{object}}}").as_bytes());
    invalid(format!("\"{}\"", "é".repeat(65_537)).as_bytes());
    assert!(parse_strict(format!("\"{}\"", "é".repeat(65_536)).as_bytes()).is_ok());
    // Each key and child counts as a node; this is under the 2MiB outer limit.
    let row = format!("[{}]", vec!["0"; 65].join(","));
    invalid(format!("[{}]", vec![row; 4096].join(",")).as_bytes());
    for raw in [
        br#"{"x":null,"x":null}"#.as_slice(),
        br#""\udc00""#,
        br#""\ud800x""#,
        b"\"\xc0\x80\"",
        b"\"\xed\xa0\x80\"",
        b"Infinity",
        b"-Infinity",
    ] {
        invalid(raw);
    }
    assert_eq!(parse_strict(br#""\ud83d\ude00""#).unwrap(), json!("😀"));
}

#[test]
fn binary64_exact_rational_ties_even_and_negative_floor_split() {
    for (bits, expected) in [
        ("0000000000000000", (0, 0)),
        ("8000000000000000", (0, 0)),
        ("0000000000000001", (0, 0)),
        ("8000000000000001", (0, 0)),
        ("3f50000000000000", (0, 976_562)), // 976562.5, even down
        ("3f68000000000000", (0, 2_929_688)), // 2929687.5, even up
        ("bf50000000000000", (-1, 999_023_438)),
        ("bf68000000000000", (-1, 997_070_312)),
    ] {
        assert_eq!(binary64_nanosecond_view(bits).unwrap(), expected);
        let time = ExactTime::SourceBinary64Seconds {
            epoch_second: expected.0,
            nanosecond: expected.1,
            source_binary64_bits: bits.to_owned(),
            source_offset_seconds: NullableOffset(None),
        };
        validate_exact_time(&time).unwrap();
        let bytes = canonical_json(&time).unwrap();
        let roundtrip: ExactTime = decode_typed(&bytes).unwrap();
        assert_eq!(time, roundtrip);
    }
    for bits in [
        "7ff0000000000000",
        "fff0000000000000",
        "7ff8000000000000",
        "7fefffffffffffff",
        "3F50000000000000",
    ] {
        assert_eq!(
            binary64_nanosecond_view(bits).unwrap_err(),
            Error::InvalidRequest
        );
    }
    let raw = br#"{"epoch_second":0,"nanosecond":976563,"precision":"source_binary64_seconds","source_binary64_bits":"3f50000000000000","source_offset_seconds":null}"#;
    let time: ExactTime = decode_typed(raw).unwrap();
    assert_eq!(
        validate_exact_time(&time).unwrap_err(),
        Error::InvalidRequest
    );
    for raw in [br#"{"epoch_second":0,"nanosecond":0,"precision":"source_nanoseconds"}"#.as_slice(),
        br#"{"epoch_second":0,"nanosecond":true,"precision":"source_nanoseconds","source_offset_seconds":null}"#,
        br#"{"epoch_second":0,"nanosecond":0,"precision":"source_seconds","source_binary64_bits":"0000000000000000","source_offset_seconds":null}"#] {
        assert_eq!(decode_typed::<ExactTime>(raw).unwrap_err(),Error::InvalidRequest);
    }
}

fn identity(version: Value) -> Value {
    let mut value = json!({"source_id":"health_connect","provider_id":"health_connect","identity_kind":"native",
        "record_type":"androidx.health.connect.client.records.StepsRecord","record_id":"synthetic-record",
        "metadata_status":{"client_record_id":"absent","client_record_version":"available","last_modified":"available"},
        "last_modified":{"epoch_second":0,"nanosecond":1,"precision":"source_nanoseconds","source_offset_seconds":null}});
    value["client_record_version"] = version;
    value
}
#[test]
fn native_client_versions_and_metadata_omissions_are_lossless() {
    for version in [0_u64, 9_007_199_254_740_993, i64::MAX as u64] {
        let original = identity(json!(version));
        let typed: NativeIdentity = decode_typed(&serde_json::to_vec(&original).unwrap()).unwrap();
        validate_native_identity(&typed).unwrap();
        assert_eq!(
            parse_strict(&canonical_json(&typed).unwrap()).unwrap(),
            original
        );
    }
    for version in [
        json!(-1),
        json!(i64::MAX as u64 + 1),
        json!(true),
        json!(1.0),
        Value::Null,
    ] {
        assert_eq!(
            decode_typed::<NativeIdentity>(&serde_json::to_vec(&identity(version)).unwrap())
                .unwrap_err(),
            Error::InvalidRequest
        );
    }
    let mut absent = identity(json!(0));
    absent
        .as_object_mut()
        .unwrap()
        .remove("client_record_version");
    let typed: NativeIdentity = decode_typed(&serde_json::to_vec(&absent).unwrap()).unwrap();
    assert_eq!(
        validate_native_identity(&typed).unwrap_err(),
        Error::InvalidRequest
    );
    let mut fabricated = identity(json!(0));
    fabricated["source_id"] = json!("apple_health");
    fabricated["provider_id"] = json!("apple_health");
    assert!(decode_typed::<NativeIdentity>(&serde_json::to_vec(&fabricated).unwrap()).is_err());
    let mut child = identity(json!(0));
    child["identity_kind"] = json!("derived_child");
    child["parent_record_id"] = json!("synthetic-parent");
    child["parent_record_type"] = json!("androidx.health.connect.client.records.HeartRateRecord");
    let typed: NativeIdentity = decode_typed(&serde_json::to_vec(&child).unwrap()).unwrap();
    assert_eq!(
        validate_native_identity(&typed).unwrap_err(),
        Error::InvalidRequest
    );
    let mut null = identity(json!(0));
    null["origin"] = Value::Null;
    assert_eq!(
        decode_typed::<NativeIdentity>(&serde_json::to_vec(&null).unwrap()).unwrap_err(),
        Error::InvalidRequest
    );
}

struct CountedDepth<'a> {
    remaining: u32,
    visits: &'a std::cell::Cell<usize>,
}
impl serde::Serialize for CountedDepth<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeSeq as _;
        self.visits.set(self.visits.get() + 1);
        if self.remaining == 0 {
            return serializer.serialize_u64(0);
        }
        let mut sequence = serializer.serialize_seq(Some(1))?;
        sequence.serialize_element(&Self {
            remaining: self.remaining - 1,
            visits: self.visits,
        })?;
        sequence.end()
    }
}
struct CountedString<'a> {
    value: &'a str,
    visits: &'a std::cell::Cell<usize>,
}
impl serde::Serialize for CountedString<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.visits.set(self.visits.get() + 1);
        serializer.serialize_str(self.value)
    }
}
#[test]
fn canonical_serialization_stops_before_deep_recursion_or_unbounded_output() {
    let visits = std::cell::Cell::new(0);
    assert_eq!(
        canonical_json(&CountedDepth {
            remaining: 32,
            visits: &visits
        })
        .unwrap_err(),
        Error::InvalidRequest
    );
    assert!(visits.get() <= 26);
    visits.set(0);
    let text = "x".repeat(65_536);
    let strings: Vec<_> = (0..100)
        .map(|_| CountedString {
            value: &text,
            visits: &visits,
        })
        .collect();
    assert_eq!(canonical_json(&strings).unwrap_err(), Error::InvalidRequest);
    assert!(
        visits.get() < 200,
        "raw byte writer must stop before serializing every value twice"
    );
}

#[test]
fn negotiated_base_versions_are_not_highest_extension() {
    let legacy = healthmd_protocol::wire::PeerCapabilities::portable_cli_all_versions(
        healthmd_protocol::encoding::SwiftUuid(uuid::Uuid::nil()),
    );
    assert_eq!(legacy.protocol_versions, vec![1, 2, 3]);
    assert_eq!(healthmd_protocol::CURRENT_PROTOCOL_VERSION, 1);
    assert_eq!(healthmd_protocol::ANDROID_PAIRING_PROTOCOL_VERSION, 2);
    assert_eq!(healthmd_protocol::SHARED_PAIRING_PROTOCOL_VERSION, 3);
    assert_eq!(healthmd_protocol::DEFAULT_MANUAL_IP_PORT, 17_647);
    assert_eq!(healthmd_protocol::MAXIMUM_PACKET_BYTES, 2 * 1024 * 1024);
    assert_eq!(
        negotiate(&PeerPlatform::Apple, &[1, 2, 3, 4], &[1, 3, 4], true).unwrap(),
        Negotiation {
            base: 1,
            iphone_query_v3: true,
            agent_v4: true
        }
    );
    assert_eq!(
        negotiate(&PeerPlatform::Android, &[1, 2, 3, 4], &[2, 4], true).unwrap(),
        Negotiation {
            base: 2,
            iphone_query_v3: false,
            agent_v4: true
        }
    );
    assert_eq!(
        negotiate(&PeerPlatform::Android, &[1], &[2, 4], false).unwrap_err(),
        Error::UnsupportedCapability
    );
    assert_eq!(
        negotiate(&PeerPlatform::Android, &[1, 4], &[1, 4], false).unwrap_err(),
        Error::UnsupportedCapability
    );
    assert!(
        !negotiate(&PeerPlatform::Apple, &[1, 4], &[1], false)
            .unwrap()
            .agent_v4
    );
    assert!(
        !negotiate(&PeerPlatform::Apple, &[1, 3, 4], &[1, 3, 4], false)
            .unwrap()
            .iphone_query_v3
    );
    assert_eq!(
        decode_envelope(
            b"not-json",
            Negotiation {
                base: 2,
                iphone_query_v3: false,
                agent_v4: false
            }
        )
        .unwrap_err(),
        Error::UnsupportedCapability
    );
    for kind in ["control_request", "query_request", "query_cancel"] {
        let raw =
            serde_json::to_vec(&json!({"protocol_version":4,"type":kind,"payload":{}})).unwrap();
        assert_eq!(
            decode_envelope(
                &raw,
                Negotiation {
                    base: 2,
                    iphone_query_v3: false,
                    agent_v4: true
                }
            )
            .unwrap_err(),
            Error::UnsupportedCapability
        );
    }
}
