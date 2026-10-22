use healthmd_core::{
    registry::{MetricRegistryProfile, metric_registry_snapshot},
    semantic::SemanticSession,
};
use serde_json::{Value, json};

const RANGE_HASH: &str = "0136dc5096e7cfc7030ec92286f1bbe9422e8b0bbbc0fa16924d45fe9124d337";
const ORIGINAL_HASH: &str = "709df0ae9f583e82627bc5439c4385905a5d85000e4322a0384cfe96b35a8f78";

fn input(version: u32, minutes: bool) -> (Value, Value) {
    let source: Value = serde_json::from_slice(include_bytes!(
        "../../../../contracts/render-input/v2/fixtures/native-android-v6-handoff.json"
    ))
    .unwrap();
    let mut config = source["semantic_configuration"].clone();
    config["profile"] = json!("apple_health_data_v11");
    config["registry_version"] = json!(version);
    config["registry_sha256"] = json!(if version == 3 {
        RANGE_HASH
    } else {
        ORIGINAL_HASH
    });
    config["profile_revision"] = json!(2);
    config["selected_selection_ids"] = json!(["workouts"]);
    config["disabled_output_keys"] = if minutes {
        json!([])
    } else {
        json!(["workout_minutes", "workout_count", "workouts"])
    };
    config["rollup_periods"] = json!(["range"]);
    config["rollup_range"] = json!({"start_date":"2026-07-24", "end_date":"2026-07-27"});
    let mut batch = source["semantic_batches"][0].clone();
    batch["owner_dates"] = json!(["2026-07-25", "2026-07-26"]);
    let mut records = vec![];
    for (
        index,
        (date, hr, power, high_hr, low_hr, high_power, hr_seconds, power_seconds, total_minutes),
    ) in [
        ("2026-07-25", 100, 100, 200, 50, 400, 600, 1800, 60),
        ("2026-07-26", 200, 300, 190, 55, 900, 1800, 600, 120),
    ]
    .into_iter()
    .enumerate()
    {
        for (key, value, unit, weight) in [
            (
                "workout_avg_heart_rate",
                hr,
                "beat_per_minute",
                Some(hr_seconds),
            ),
            ("workout_avg_power", power, "watt", Some(power_seconds)),
            ("workout_max_heart_rate", high_hr, "beat_per_minute", None),
            ("workout_min_heart_rate", low_hr, "beat_per_minute", None),
            ("workout_max_power", high_power, "watt", None),
            ("workout_minutes", total_minutes, "minute", None),
        ] {
            if !minutes && key == "workout_minutes" {
                continue;
            }
            let mut record = source["semantic_batches"][0]["records"][0].clone();
            record["record_id"] = json!(format!("workout-{index}-{key}"));
            record["source_ordinal"] = json!((records.len() + 1).to_string());
            record["owner_date"] = json!(date);
            record["semantic_id"] = json!("workouts");
            record["selection_ids"] = json!(["workouts"]);
            record["output_key"] = json!(key);
            record["value"] = json!({"value_type":"number", "number":{"representation":"signed_integer", "decimal":value.to_string()}, "unit":{"id":unit}});
            record["weight"] = weight.map_or(Value::Null, |value: i32| json!({"representation":"signed_integer", "decimal":value.to_string()}));
            records.push(record);
        }
    }
    batch["records"] = json!(records);
    (config, batch)
}

fn result(config: &Value, batch: &Value) -> Value {
    let mut session = SemanticSession::from_json(&serde_json::to_vec(config).unwrap()).unwrap();
    serde_json::from_slice(
        &session
            .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
            .unwrap(),
    )
    .unwrap()
}

fn number(value: &Value) -> f64 {
    let value = &value["number"];
    if value["representation"] == "binary64" {
        f64::from_bits(u64::from_str_radix(value["bits"].as_str().unwrap(), 16).unwrap())
    } else {
        value["decimal"].as_str().unwrap().parse().unwrap()
    }
}

#[test]
fn explicit_range_authority_uses_metric_specific_duration_and_extrema_independently_of_visible_minutes()
 {
    for minutes in [false, true] {
        let (config, batch) = input(3, minutes);
        let output = result(&config, &batch);
        for (key, expected, rule) in [
            ("workout_avg_heart_rate", 175.0, "weighted_average"),
            ("workout_avg_power", 150.0, "weighted_average"),
            ("workout_max_heart_rate", 200.0, "maximum"),
            ("workout_min_heart_rate", 50.0, "minimum"),
            ("workout_max_power", 900.0, "maximum"),
        ] {
            let actual = output["rollups"][0]["values"]
                .as_array()
                .unwrap()
                .iter()
                .find(|v| v["output_key"] == key)
                .unwrap();
            assert!(
                (number(&actual["primary_value"]) - expected).abs() < f64::EPSILON,
                "{key} minutes={minutes}"
            );
            assert_eq!(actual["rule"], rule);
            assert_eq!(actual["days_counted"], 2);
        }
        if minutes {
            let duration = output["rollups"][0]["values"]
                .as_array()
                .unwrap()
                .iter()
                .find(|v| v["output_key"] == "workout_minutes")
                .unwrap();
            assert_eq!(
                number(&duration["primary_value"]).to_bits(),
                180.0_f64.to_bits()
            );
            assert_eq!(duration["rule"], "sum");
        }
        if !minutes {
            assert!(!output["days"].as_array().unwrap().iter().any(|day| {
                day["values"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|v| v["output_key"] == "workout_minutes")
            }));
        }
    }
}

#[test]
fn registry_two_still_replays_its_original_sum_rules() {
    let (config, batch) = input(2, true);
    let output = result(&config, &batch);
    let values = output["rollups"][0]["values"].as_array().unwrap();
    for (key, expected) in [
        ("workout_max_heart_rate", 390.0),
        ("workout_min_heart_rate", 105.0),
        ("workout_max_power", 1300.0),
    ] {
        let actual = values.iter().find(|v| v["output_key"] == key).unwrap();
        assert_eq!(actual["rule"], "sum");
        assert!((number(&actual["primary_value"]) - expected).abs() < f64::EPSILON);
    }
}

#[test]
fn registry_three_is_explicit_and_cannot_relabel_historical_authorities() {
    for profile in [
        MetricRegistryProfile::AppleHealthDataV11,
        MetricRegistryProfile::AndroidSleepV6,
    ] {
        let snapshot = metric_registry_snapshot(profile, 3).unwrap();
        assert_eq!(snapshot.registry_sha256, RANGE_HASH);
        assert_eq!(
            metric_registry_snapshot(profile, 2)
                .unwrap()
                .registry_sha256,
            ORIGINAL_HASH
        );
    }
    assert!(metric_registry_snapshot(MetricRegistryProfile::AppleHealthDataV8, 3).is_err());
    for (version, hash) in [(3, ORIGINAL_HASH), (2, RANGE_HASH), (1, RANGE_HASH)] {
        let (mut config, _) = input(version, true);
        config["registry_sha256"] = json!(hash);
        assert!(SemanticSession::from_json(&serde_json::to_vec(&config).unwrap()).is_err());
    }
}

#[test]
fn range_metric_weights_must_be_positive_and_rejection_preserves_batch_frontier() {
    let (config, batch) = input(3, false);
    for weight in [
        Value::Null,
        json!({"representation":"signed_integer", "decimal":"0"}),
        json!({"representation":"signed_integer", "decimal":"-1"}),
    ] {
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&config).unwrap()).unwrap();
        let mut invalid = batch.clone();
        invalid["records"][0]["weight"] = weight;
        assert!(
            session
                .process_batch(&serde_json::to_vec(&invalid).unwrap(), || false)
                .is_err()
        );
        assert!(
            session
                .process_batch(&serde_json::to_vec(&batch).unwrap(), || false)
                .is_ok()
        );
    }
}

fn render_inputs() -> (Value, Value, Value) {
    let fixture: Value = serde_json::from_slice(include_bytes!(
        "../../../../contracts/render-input/v2/fixtures/native-android-v6-handoff.json"
    ))
    .unwrap();
    let (config, batch) = input(3, false);
    let semantic = result(&config, &batch);
    let snapshot = metric_registry_snapshot(MetricRegistryProfile::AppleHealthDataV11, 3).unwrap();
    let mut render_config = fixture["render_configuration"].clone();
    for key in [
        "profile",
        "profile_revision",
        "registry_version",
        "registry_sha256",
    ] {
        render_config[key] = config[key].clone();
    }
    let mut presentations = serde_json::Map::new();
    let mut days = vec![];
    for source in semantic["days"].as_array().unwrap() {
        let mut day = fixture["render_batches"][0]["days"][0].clone();
        day["owner_date"] = source["owner_date"].clone();
        day["title"] = source["owner_date"].clone();
        let mut metrics = vec![];
        for (ordinal, value) in source["values"].as_array().unwrap().iter().enumerate() {
            let key = value["output_key"].as_str().unwrap();
            let output = snapshot.outputs.iter().find(|o| o.key == key).unwrap();
            let mut metric = fixture["render_batches"][0]["days"][0]["metrics"][0].clone();
            metric["output_key"] = json!(key);
            metric["category_id"] = json!("workouts");
            metric["category_label"] = json!("Workouts");
            metric["label"] = json!(key);
            metric["frontmatter_key"] = json!(key);
            metric["json_path"] = json!(["workouts", key]);
            metric["public_value"] =
                if value["value"]["number"]["representation"] == "signed_integer" {
                    json!(
                        value["value"]["number"]["decimal"]
                            .as_str()
                            .unwrap()
                            .parse::<i64>()
                            .unwrap()
                    )
                } else {
                    json!(number(&value["value"]))
                };
            metric["display_value"] = json!(number(&value["value"]).to_string());
            metric["unit"] = json!(output.unit);
            metric["ordinal"] = json!(ordinal);
            metrics.push(metric);
            presentations.insert(key.to_owned(), json!({"key":key, "canonical_key":key, "display_name":key, "category":"Workouts", "unit":output.unit, "statistic_order":[], "notes":null}));
        }
        day["metrics"] = json!(metrics);
        days.push(day);
    }
    render_config["rollups"] =
        json!({"generated_at":"2026-07-28T12:00:00Z", "metrics":presentations});
    let mut render_batch = fixture["render_batches"][0].clone();
    render_batch["days"] = json!(days);
    (render_config, render_batch, semantic)
}

#[test]
fn new_range_rules_are_identified_in_every_public_format_and_cannot_be_relabelled() {
    use healthmd_core::render::RenderSession;
    let (mut render_config, render_batch, semantic) = render_inputs();
    let mut renderer = RenderSession::from_json(
        &serde_json::to_vec(&render_config).unwrap(),
        &serde_json::to_vec(&semantic).unwrap(),
    )
    .unwrap();
    renderer
        .process_batch(&serde_json::to_vec(&render_batch).unwrap(), || false)
        .unwrap();
    let plan = renderer.finish(|| false).unwrap();
    let summaries = plan
        .items
        .iter()
        .filter(|item| item.relative_path.contains("/rollups/Range/"))
        .collect::<Vec<_>>();
    assert_eq!(summaries.len(), 4);
    for item in summaries {
        let text = String::from_utf8(item.content.clone()).unwrap();
        if has_extension(&item.relative_path, "json") {
            let document: Value = serde_json::from_str(&text).unwrap();
            assert_eq!(document["schema_version"], 11);
            assert_eq!(document["rollup_rules_version"], 12);
            let heart = document["metrics"]
                .as_array()
                .unwrap()
                .iter()
                .find(|m| m["key"] == "workout_avg_heart_rate")
                .unwrap();
            assert_eq!(heart["primary_value"], "175");
        } else if has_extension(&item.relative_path, "csv") {
            assert!(text.contains("healthmd.rollup_summary,11,healthmd.health_data,11,12,"));
        } else {
            assert!(text.contains("rollup_rules_version: 12"));
        }
    }
    render_config["registry_version"] = json!(2);
    render_config["registry_sha256"] = json!(ORIGINAL_HASH);
    assert!(
        RenderSession::from_json(
            &serde_json::to_vec(&render_config).unwrap(),
            &serde_json::to_vec(&semantic).unwrap()
        )
        .is_err()
    );
}

#[test]
fn rules_twelve_preserve_nonterminating_binary64_results_in_public_range_values() {
    use healthmd_core::render::RenderSession;
    let (config, batch) = input(3, false);
    let mut batch = batch;
    batch["records"][0]["weight"]["decimal"] = json!("1000");
    let semantic = result(&config, &batch);
    let (render_config, mut render_batch, _) = render_inputs();
    // Daily values are unchanged; only their measured durations differ.
    let mut renderer = RenderSession::from_json(
        &serde_json::to_vec(&render_config).unwrap(),
        &serde_json::to_vec(&semantic).unwrap(),
    )
    .unwrap();
    render_batch["session_id"] = config["session_id"].clone();
    renderer
        .process_batch(&serde_json::to_vec(&render_batch).unwrap(), || false)
        .unwrap();
    let plan = renderer.finish(|| false).unwrap();
    let item = plan
        .items
        .iter()
        .find(|item| {
            item.relative_path.contains("/rollups/Range/")
                && has_extension(&item.relative_path, "json")
        })
        .unwrap();
    let public: Value = serde_json::from_slice(&item.content).unwrap();
    let actual = public["metrics"]
        .as_array()
        .unwrap()
        .iter()
        .find(|metric| metric["key"] == "workout_avg_heart_rate")
        .unwrap()["primary_value"]
        .as_str()
        .unwrap()
        .parse::<f64>()
        .unwrap();
    let expected = (100.0_f64 * 1000.0 + 200.0 * 1800.0) / 2800.0;
    assert_eq!(actual.to_bits(), expected.to_bits());
}

fn has_extension(path: &str, expected: &str) -> bool {
    std::path::Path::new(path)
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case(expected))
}
