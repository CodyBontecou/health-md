use healthmd_core::{
    SLEEP_REGISTRY_SHA256,
    render::{ArtifactPlan, RenderError, RenderSession, merge_profile_markdown},
    semantic::SemanticProfile,
    semantic::SemanticSession,
};
use serde_json::{Value, json};

// Reuse captured synthetic presentation facts, not old expected output or production data.
fn apple_successor_input() -> (Value, Value, Vec<Value>) {
    let fixture: Value =
        serde_json::from_slice(include_bytes!("fixtures/render-differential-v1.json")).unwrap();
    let case = &fixture["cases"][0];
    let mut config = case["configuration"].clone();
    let mut result = case["semantic_result"].clone();
    config["profile"] = json!("apple_health_data_v11");
    config["registry_version"] = json!(2);
    config["registry_sha256"] = json!(SLEEP_REGISTRY_SHA256);
    result["profile"] = config["profile"].clone();
    result["registry_sha256"] = config["registry_sha256"].clone();
    result["sleep_capture_context"] = json!({
        "schema_profile": "apple-v11", "calendar_timezone": "Asia/Kathmandu",
        "sleep_day_attribution": "morning_ends", "sleep_owner_day_rule": "session_end_date",
        "sleep_interval_clipping": "none"
    });
    let mut batches = case["batches"].as_array().unwrap().clone();
    pin_successor_contracts(&mut config, &mut result, &mut batches);
    (config, result, batches)
}

fn android_successor_input() -> (Value, Value, Vec<Value>) {
    let fixture: Value =
        serde_json::from_slice(include_bytes!("fixtures/render-differential-v1.json")).unwrap();
    let case = &fixture["cases"][2];
    let mut config = case["configuration"].clone();
    let mut result = case["semantic_result"].clone();
    let mut batches = case["batches"].as_array().unwrap().clone();
    config["profile"] = json!("android_sleep_v6");
    config["registry_version"] = json!(2);
    config["registry_sha256"] = json!(SLEEP_REGISTRY_SHA256);
    result["profile"] = config["profile"].clone();
    result["registry_sha256"] = config["registry_sha256"].clone();
    result["sleep_capture_context"] = json!({
        "schema_profile":"android-sleep-v6", "calendar_timezone":"Asia/Kathmandu",
        "sleep_day_attribution":"morning_ends", "sleep_owner_day_rule":"session_end_date",
        "sleep_interval_clipping":"none"
    });
    result["days"][0]["values"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "aggregation":"sum", "output_key":"sleep_light_hours", "semantic_id":"sleep_light",
            "source_record_ids":["native-light"], "value":{"value_type":"number",
            "number":{"representation":"binary64", "bits":"4011000000000000"}, "unit":{"id":"hour"}}
        }));
    batches[0]["days"][0]["metrics"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "category_id":"sleep", "category_label":"Sleep", "display_value":"4.25",
            "frontmatter_key":"sleep_light_hours", "json_path":["sleep","lightSleep"],
            "label":"Light Sleep", "ordinal":2, "output_key":"sleep_light_hours",
            "public_value":4.25, "timestamp":null, "unit":"hours"
        }));
    pin_successor_contracts(&mut config, &mut result, &mut batches);
    (config, result, batches)
}

fn pin_successor_contracts(config: &mut Value, result: &mut Value, batches: &mut [Value]) {
    config["canonical_model_version"] = json!(2);
    config["render_input_version"] = json!(2);
    config["artifact_plan_version"] = json!(2);
    result["canonical_model_version"] = json!(2);
    result["semantic_input_version"] = json!(2);
    result["core_api_version"] = json!(4);
    for batch in batches {
        batch["render_input_version"] = json!(2);
    }
}

fn has_extension(path: &str, expected: &str) -> bool {
    std::path::Path::new(path)
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case(expected))
}

fn ordered(value: &Value) -> Value {
    match value {
        Value::Null => json!({"value_type":"null"}),
        Value::Bool(value) => json!({"value_type":"boolean", "value":value}),
        Value::Number(value) => json!({"value_type":"number", "decimal":value.to_string()}),
        Value::String(value) => json!({"value_type":"string", "value":value}),
        Value::Array(items) => {
            json!({"value_type":"array", "items":items.iter().map(ordered).collect::<Vec<_>>()})
        }
        Value::Object(entries) => {
            json!({"value_type":"object", "entries":entries.iter().map(|(key,value)| json!({"key":key,"value":ordered(value)})).collect::<Vec<_>>()})
        }
    }
}

fn render(config: &Value, semantic: &Value, batches: &[Value]) -> ArtifactPlan {
    let mut session = RenderSession::from_json(
        &serde_json::to_vec(config).unwrap(),
        &serde_json::to_vec(semantic).unwrap(),
    )
    .expect("explicit successor render session");
    for batch in batches {
        session
            .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
            .expect("captured presentation facts");
    }
    session
        .finish(|| false)
        .expect("self-describing successor artifacts")
}

#[test]
fn successor_render_binding_keeps_exact_binary64_round_trips() {
    for input in [apple_successor_input, android_successor_input] {
        let converted_height = 175.1_f64 * 0.01;
        for value in [
            23.551_020_408_163_264_f64,
            72.125 / (converted_height * converted_height),
            1.75125,
            1.234_125,
            -0.0,
        ] {
            let (config, mut semantic, mut batches) = input();
            let record = &mut semantic["days"][0]["values"][0];
            let output_key = record["output_key"].clone();
            record["value"]["number"] = json!({
                "representation":"binary64", "bits":format!("{:016x}", value.to_bits())
            });
            let metric = batches[0]["days"][0]["metrics"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .find(|metric| metric["output_key"] == output_key)
                .unwrap();
            metric["public_value"] = json!(value);
            metric["display_value"] = json!(value.to_string());
            let mut session = RenderSession::from_json(
                &serde_json::to_vec(&config).unwrap(),
                &serde_json::to_vec(&semantic).unwrap(),
            )
            .unwrap();
            session
                .process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false)
                .expect("successor public number must match the exact completed binary64 value");
            session.finish(|| false).unwrap();
        }
    }
}

#[test]
fn successor_decimal_parsing_never_loosens_exact_semantic_binding_or_json_grammar() {
    for input in [apple_successor_input, android_successor_input] {
        for invalid in [
            json!(23.551_020_408_163_267_f64),
            json!("23.551020408163264"),
            Value::Null,
        ] {
            let (config, mut semantic, mut batches) = input();
            let expected = 23.551_020_408_163_264_f64;
            let record = &mut semantic["days"][0]["values"][0];
            let output_key = record["output_key"].clone();
            record["value"]["number"] = json!({
                "representation":"binary64", "bits":format!("{:016x}", expected.to_bits())
            });
            let metric = batches[0]["days"][0]["metrics"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .find(|metric| metric["output_key"] == output_key)
                .unwrap();
            metric["public_value"] = invalid;
            let mut session = RenderSession::from_json(
                &serde_json::to_vec(&config).unwrap(),
                &serde_json::to_vec(&semantic).unwrap(),
            )
            .unwrap();
            assert_eq!(
                session.process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false),
                Err(RenderError::PresentationMismatch)
            );
        }
        let (config, semantic, batches) = input();
        let bytes = serde_json::to_string(&batches[0]).unwrap().replacen(
            "\"public_value\":",
            "\"public_value\":0,\"public_value\":",
            1,
        );
        let mut session = RenderSession::from_json(
            &serde_json::to_vec(&config).unwrap(),
            &serde_json::to_vec(&semantic).unwrap(),
        )
        .unwrap();
        assert_eq!(
            session.process_batch(bytes.as_bytes(), || false),
            Err(RenderError::InvalidBatch)
        );
    }
}

#[test]
fn native_android_v6_handoffs_replay_without_legacy_aliases_or_clock_reinterpretation() {
    let fixture: Value = serde_json::from_slice(include_bytes!(
        "../../../../contracts/render-input/v2/fixtures/native-android-v6-handoff.json"
    ))
    .unwrap();
    let mut semantic = SemanticSession::from_json(
        &serde_json::to_vec(&fixture["semantic_configuration"]).unwrap(),
    )
    .unwrap();
    let mut result = None;
    for batch in fixture["semantic_batches"].as_array().unwrap() {
        result = Some(
            semantic
                .process_batch(&serde_json::to_vec(batch).unwrap(), || false)
                .expect("native Kotlin successor SDK facts"),
        );
    }
    let actual: Value = serde_json::from_slice(&result.unwrap()).unwrap();
    let mut expected = fixture["expected_semantic_result"].clone();
    expected["selected_output_keys"] = json!([
        "sleep_bedtime",
        "sleep_light_hours",
        "sleep_total_hours",
        "sleep_wake",
        "steps"
    ]);
    assert_eq!(actual, expected);
    let plan = render(
        &fixture["render_configuration"],
        &actual,
        fixture["render_batches"].as_array().unwrap(),
    );
    assert_eq!(plan.artifact_plan_version, 2);
    assert_eq!(plan.items.len(), 4);
    let plan_fixture = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../contracts/render-input/v2/fixtures/core-android-v6-artifact-plan.json"
    );
    let mut plan_bytes = serde_json::to_vec(&plan).unwrap();
    plan_bytes.push(b'\n');
    if std::env::var("HEALTHMD_UPDATE_WAKE_DATE_CORE_PLAN_FIXTURE").as_deref() == Ok("1") {
        std::fs::write(plan_fixture, &plan_bytes).unwrap();
    } else {
        assert_eq!(std::fs::read(plan_fixture).unwrap(), plan_bytes);
    }
    for item in &plan.items {
        let text = std::str::from_utf8(&item.content).unwrap();
        assert!(!text.contains("sleep_core_hours"));
        assert!(text.contains("morning_ends"));
        assert!(text.contains("Asia/Kathmandu"));
        if has_extension(&item.relative_path, "json") {
            let record: Value = serde_json::from_slice(&item.content).unwrap();
            assert_eq!(record["schema_profile"], "android-sleep-v6");
            assert_eq!(record["schema_version"], 6);
            assert_eq!(record["sleep"]["sleep_light_hours"], 4.25);
            assert_eq!(record["sleep"]["sleep_total_hours"], 8.25);
            assert_eq!(record["activity"]["steps"], 1234);
        }
        if has_extension(&item.relative_path, "md") && !item.relative_path.contains("-bases") {
            assert!(
                !text.starts_with("---"),
                "metadata-off remains frontmatter-free"
            );
        }
    }
}

#[test]
fn successor_markdown_merge_keeps_user_yaml_and_prose_without_losing_authority() {
    for (mut config, semantic, batches) in [apple_successor_input(), android_successor_input()] {
        config["formats"] = json!(["markdown"]);
        let profile: SemanticProfile = serde_json::from_value(config["profile"].clone()).unwrap();
        for metadata in [true, false] {
            config["include_metadata"] = json!(metadata);
            let plan = render(&config, &semantic, &batches);
            let generated = std::str::from_utf8(&plan.items[0].content).unwrap();
            let mut existing = generated.replace("1234", "987");
            if metadata {
                existing = existing.replacen(
                    "---\n",
                    "---\nuser_notes: |-\n  Private local prose\n  second line\ntags:\n- daily\n",
                    1,
                );
            }
            existing.push_str("\n## Notes\nKeep this note exactly.\n");
            let merged = merge_profile_markdown(profile, &existing, generated, true)
                .expect("matching explicit successor authority");
            assert!(merged.contains("1234"));
            assert!(!merged.contains("987"));
            assert!(merged.contains("## Notes\nKeep this note exactly.\n"));
            assert!(merged.contains("morning_ends"));
            assert!(merged.contains("Asia/Kathmandu"));
            if metadata {
                assert!(merged.contains(
                    "user_notes: |-\n  Private local prose\n  second line\ntags:\n- daily\n"
                ));
            } else {
                assert!(!merged.starts_with("---"));
            }
            assert_eq!(
                merge_profile_markdown(profile, "", generated, false).unwrap(),
                generated
            );
        }
    }
}

#[test]
fn successor_merge_preserves_filled_placeholders_and_fenced_user_notes() {
    for (mut config, semantic, batches) in [apple_successor_input(), android_successor_input()] {
        config["formats"] = json!(["markdown"]);
        config["include_metadata"] = json!(true);
        let profile: SemanticProfile = serde_json::from_value(config["profile"].clone()).unwrap();
        let plan = render(&config, &semantic, &batches);
        let generated = std::str::from_utf8(&plan.items[0].content).unwrap();
        let fenced_notes = "\n## Notes\n```markdown\n## Activity\nThis is literal example code, not a managed section.\n```\nKeep the prose after the fence.\n";
        let existing = generated
            .replace("notes: \n", "notes: |-\n  Keep this filled placeholder.\n")
            + fenced_notes;
        let merged = merge_profile_markdown(profile, &existing, generated, true).unwrap();
        assert!(merged.contains("notes: |-\n  Keep this filled placeholder.\n"));
        assert!(merged.ends_with(fenced_notes));
    }
}

#[test]
fn successor_merge_rejects_mixed_profiles_clocks_surfaces_and_ambiguous_authority() {
    for (mut config, semantic, batches) in [apple_successor_input(), android_successor_input()] {
        config["formats"] = json!(["markdown"]);
        let profile: SemanticProfile = serde_json::from_value(config["profile"].clone()).unwrap();
        config["include_metadata"] = json!(true);
        let with_metadata = render(&config, &semantic, &batches).items.remove(0).content;
        let generated = std::str::from_utf8(&with_metadata).unwrap();
        let mut invalid = vec![
            generated.replace("Asia/Kathmandu", "UTC"),
            generated.replace("morning_ends", "night_begins"),
            generated.replace("session_end_date", "source_start_date"),
            generated.replace("  sleep_interval_clipping: none\n", ""),
            generated.replacen("---\n", "---\nschema_version: 8\n", 1),
            generated.replacen(
                "---\n",
                "---\n\"schema_profile\": android-analytical-v5\n",
                1,
            ),
            generated.replace("time_context:\n", "time_context: &clock\n"),
            generated.replacen("---\n", "---\nsleep_day_attribution: night_begins\n", 1),
            generated.replacen(
                "---\n",
                "---\nhealthmd_schema_profile: android-analytical-v5\n",
                1,
            ),
            "## Sleep\nOld unversioned export\n".to_owned(),
        ];
        if profile == SemanticProfile::AndroidSleepV6 {
            invalid.push(generated.replacen("---\n", "---\nsleep_core_hours: 4.25\n", 1));
        }
        for existing in invalid {
            assert_eq!(
                merge_profile_markdown(profile, &existing, generated, true),
                Err(RenderError::PresentationMismatch)
            );
        }
        config["include_metadata"] = json!(false);
        let without_metadata = render(&config, &semantic, &batches).items.remove(0).content;
        let visible = std::str::from_utf8(&without_metadata).unwrap();
        for (existing, incoming) in [(generated, visible), (visible, generated)] {
            assert_eq!(
                merge_profile_markdown(profile, existing, incoming, true),
                Err(RenderError::PresentationMismatch)
            );
        }
        for invalid in [
            visible.replace("Asia/Kathmandu", "UTC"),
            visible.replace("morning_ends", "night_begins"),
            format!(
                "{}\n{visible}",
                visible.lines().take(2).collect::<Vec<_>>().join("\n")
            ),
        ] {
            assert_eq!(
                merge_profile_markdown(profile, &invalid, visible, true),
                Err(RenderError::PresentationMismatch)
            );
        }
        assert_eq!(
            merge_profile_markdown(profile, visible, "", true),
            Err(RenderError::PresentationMismatch)
        );
    }
}

#[test]
fn successors_never_widen_historical_handoff_versions() {
    for (config, semantic, batches) in [apple_successor_input(), android_successor_input()] {
        let plan = render(&config, &semantic, &batches);
        assert_eq!(plan.artifact_plan_version, 2);
        for key in [
            "render_input_version",
            "canonical_model_version",
            "artifact_plan_version",
            "registry_version",
        ] {
            let mut old = config.clone();
            old[key] = json!(1);
            assert!(
                RenderSession::from_json(
                    &serde_json::to_vec(&old).unwrap(),
                    &serde_json::to_vec(&semantic).unwrap()
                )
                .is_err(),
                "closed legacy {key}"
            );
        }
        for key in ["semantic_input_version", "canonical_model_version"] {
            let mut old = semantic.clone();
            old[key] = json!(1);
            assert!(
                RenderSession::from_json(
                    &serde_json::to_vec(&config).unwrap(),
                    &serde_json::to_vec(&old).unwrap()
                )
                .is_err(),
                "closed legacy {key}"
            );
        }
        let mut session = RenderSession::from_json(
            &serde_json::to_vec(&config).unwrap(),
            &serde_json::to_vec(&semantic).unwrap(),
        )
        .unwrap();
        let mut old = batches[0].clone();
        old["render_input_version"] = json!(1);
        assert_eq!(
            session
                .process_batch(&serde_json::to_vec(&old).unwrap(), || false)
                .unwrap_err(),
            RenderError::SequenceInvalid
        );
    }
}

#[test]
fn supplied_native_csv_keeps_rows_and_rejects_incomplete_or_conflicting_authority() {
    let (mut config, semantic, mut batches) = apple_successor_input();
    config["formats"] = json!(["csv"]);
    let mut rows = [
        ("schema", "healthmd.health_data"),
        ("schema_version", "11"),
        ("schema_profile", "apple-v11"),
        ("time_context.calendar_timezone", "Asia/Kathmandu"),
        ("time_context.timestamp_timezone", "UTC"),
        ("time_context.sleep_day_attribution", "morning_ends"),
        ("time_context.sleep_owner_day_rule", "session_end_date"),
        ("time_context.sleep_interval_clipping", "none"),
    ]
    .into_iter()
    .map(|(key, value)| json!({"cells":["2026-07-25","Metadata",key,value,"",""]}))
    .collect::<Vec<_>>();
    rows.push(json!({"cells":["2026-07-25","Activity","Steps","1234","count",""]}));
    rows.push(json!({"cells":["2026-07-25","Body","Body Fat Percentage","20.5","percent",""]}));
    batches[0]["days"][0]["profile_documents"] = json!({
        "semantic_output_keys":["steps","body_fat_percent"], "markdown_body":null,
        "csv_rows":rows, "json_root":null
    });
    let plan = render(&config, &semantic, &batches);
    let text = std::str::from_utf8(&plan.items[0].content).unwrap();
    assert!(text.starts_with("Date,Category,Metric,Value,Unit,Timestamp\n2026-07-25,Metadata,schema,healthmd.health_data,,\n"));
    assert!(text.ends_with(
        "2026-07-25,Activity,Steps,1234,count,\n2026-07-25,Body,Body Fat Percentage,20.5,percent,\n"
    ));
    let mut mixed = batches[0].clone();
    mixed["days"][0]["native_details"] = json!({"output_keys":["steps"],"csv_rows":[{"date":"2026-07-25","category":"Activity Detail","metric":"Steps sample","value":"1","unit":"steps","timestamp":"2026-07-25T00:00:00Z","ordinal":0}],"markdown_blocks":[],"bases_frontmatter_blocks":[]});
    let mut mixed_session = RenderSession::from_json(
        &serde_json::to_vec(&config).unwrap(),
        &serde_json::to_vec(&semantic).unwrap(),
    )
    .unwrap();
    assert_eq!(
        mixed_session
            .process_batch(&serde_json::to_vec(&mixed).unwrap(), || false)
            .unwrap_err(),
        RenderError::PresentationMismatch,
        "Native document rows cannot silently bypass requested detail facts"
    );
    for index in 0..8 {
        let mut invalid = batches[0].clone();
        invalid["days"][0]["profile_documents"]["csv_rows"][index]["cells"][3] =
            json!("private-invalid-value");
        let mut session = RenderSession::from_json(
            &serde_json::to_vec(&config).unwrap(),
            &serde_json::to_vec(&semantic).unwrap(),
        )
        .unwrap();
        assert_eq!(
            session
                .process_batch(&serde_json::to_vec(&invalid).unwrap(), || false)
                .unwrap_err(),
            RenderError::PresentationMismatch
        );
    }
}

#[test]
fn successor_authority_cannot_be_overridden_by_custom_fields_or_metric_paths() {
    let (config, semantic, batches) = apple_successor_input();
    for key in [
        "schema_profile",
        "sleep_day_attribution",
        "sleep_owner_day_rule",
        "sleep_interval_clipping",
    ] {
        for customization in [
            "custom_frontmatter",
            "placeholder_frontmatter",
            "disabled_frontmatter_keys",
        ] {
            let mut invalid = config.clone();
            if customization == "custom_frontmatter" {
                invalid[customization][key] = json!("private-invalid-value");
            } else {
                invalid[customization]
                    .as_array_mut()
                    .unwrap()
                    .push(json!(key));
            }
            assert_eq!(
                RenderSession::from_json(
                    &serde_json::to_vec(&invalid).unwrap(),
                    &serde_json::to_vec(&semantic).unwrap()
                )
                .unwrap_err(),
                RenderError::InvalidConfig
            );
        }
        for field in ["date_key", "type_key"] {
            let mut invalid = config.clone();
            invalid["frontmatter"][field] = json!(key);
            assert_eq!(
                RenderSession::from_json(
                    &serde_json::to_vec(&invalid).unwrap(),
                    &serde_json::to_vec(&semantic).unwrap()
                )
                .unwrap_err(),
                RenderError::InvalidConfig
            );
        }
    }
    let mut invalid = batches[0].clone();
    invalid["days"][0]["metrics"][0]["json_path"] = json!(["schema_profile"]);
    let mut session = RenderSession::from_json(
        &serde_json::to_vec(&config).unwrap(),
        &serde_json::to_vec(&semantic).unwrap(),
    )
    .unwrap();
    assert_eq!(
        session
            .process_batch(&serde_json::to_vec(&invalid).unwrap(), || false)
            .unwrap_err(),
        RenderError::PresentationMismatch
    );
}

#[test]
fn supplied_native_json_retains_its_payload_but_cannot_relabel_historical_authority() {
    let (mut config, semantic, mut batches) = apple_successor_input();
    config["formats"] = json!(["json"]);
    let native = json!({
        "schema":"healthmd.health_data", "schema_version":11, "schema_profile":"apple-v11",
        "date":"2026-07-25", "time_context":{
            "calendar_timezone":"Asia/Kathmandu", "timestamp_timezone":"UTC",
            "sleep_day_attribution":"morning_ends", "sleep_owner_day_rule":"session_end_date", "sleep_interval_clipping":"none"
        },
        "steps":1234, "body_fat_percent":20.5, "opaque_native_details":{"nested":["synthetic",42]}
    });
    batches[0]["days"][0]["profile_documents"] = json!({
        "semantic_output_keys":["steps","body_fat_percent"], "markdown_body":null,
        "csv_rows":null, "json_root":ordered(&native)
    });
    let plan = render(&config, &semantic, &batches);
    assert_eq!(
        serde_json::from_slice::<Value>(&plan.items[0].content).unwrap(),
        native
    );
    for (field, bad) in [
        ("schema_version", json!(8)),
        ("schema_profile", json!("apple-v8")),
        (
            "time_context",
            json!({"calendar_timezone":"UTC","timestamp_timezone":"UTC"}),
        ),
    ] {
        let mut wrong = native.clone();
        wrong[field] = bad;
        let mut invalid = batches[0].clone();
        invalid["days"][0]["profile_documents"]["json_root"] = ordered(&wrong);
        let mut session = RenderSession::from_json(
            &serde_json::to_vec(&config).unwrap(),
            &serde_json::to_vec(&semantic).unwrap(),
        )
        .unwrap();
        assert_eq!(
            session
                .process_batch(&serde_json::to_vec(&invalid).unwrap(), || false)
                .unwrap_err(),
            RenderError::PresentationMismatch
        );
        assert!(
            session
                .process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false)
                .is_ok(),
            "Metadata rejection must be transactional"
        );
    }
}

fn enable_successor_api(config: &mut Value, source: &str) {
    config["api"] = json!({
        "enabled":true, "envelope_version":1, "exported_at":"2026-07-25T00:00:00Z",
        "source":source, "date_range_start":"2026-07-25", "date_range_end":"2026-07-25",
        "failed_date_details":[], "external_record_schema":null, "external_record_schema_version":null,
        "external_records":[], "max_days_per_batch":7, "max_encoded_bytes":8_388_608
    });
}

#[test]
fn successor_api_retains_prepared_canonical_native_records_but_never_relabels_local_documents() {
    for (mut config, semantic, mut batches, source) in [
        {
            let (c, s, b) = apple_successor_input();
            (c, s, b, "ios")
        },
        {
            let (c, s, b) = android_successor_input();
            (c, s, b, "android")
        },
    ] {
        config["formats"] = json!(["json"]);
        let local_plan = render(&config, &semantic, &batches);
        let mut native: Value = serde_json::from_slice(&local_plan.items[0].content).unwrap();
        native["native_payload"] =
            json!({"source_record_ids":["synthetic-record"], "details":{"retained":true}});
        native["units"] =
            json!({"steps":"count", "body_fat_percent":"percent", "native_only":"count"});
        if source == "android" {
            native["units"]["sleep_light_hours"] = json!("hours");
        }
        let keys = batches[0]["days"][0]["metrics"]
            .as_array()
            .unwrap()
            .iter()
            .map(|metric| metric["output_key"].clone())
            .collect::<Vec<_>>();
        batches[0]["days"][0]["profile_documents"] = json!({
            "semantic_output_keys":keys, "markdown_body":null, "csv_rows":null, "json_root":ordered(&native)
        });
        enable_successor_api(&mut config, source);
        let plan = render(&config, &semantic, &batches);
        let envelope: Value = serde_json::from_slice(
            &plan
                .items
                .iter()
                .find(|item| item.relative_path.starts_with("api/"))
                .unwrap()
                .content,
        )
        .unwrap();
        let record = &envelope["records"][0];
        assert_eq!(record["native_payload"], native["native_payload"]);
        assert_eq!(record["activity"], native["activity"]);
        assert_eq!(record["body"], native["body"]);
        assert_eq!(record["units"]["native_only"], "count");
        assert_eq!(record["unit_system"], "metric");
        assert_eq!(
            record["time_context"],
            envelope["daily_record_time_context"]
        );
        let mut invalid = vec![];
        for (key, value) in [
            ("unit_system", json!("imperial")),
            ("date", json!("2026-07-24")),
        ] {
            let mut root = native.clone();
            root[key] = value;
            invalid.push(root);
        }
        let mut changed = native.clone();
        changed["activity"]["steps"] = json!(999);
        invalid.push(changed);
        let mut changed = native.clone();
        changed["units"]["steps"] = json!("lb");
        invalid.push(changed);
        if source == "android" {
            let mut local = native.clone();
            local["time_context"]["timestamp_timezone"] = json!("Asia/Kathmandu");
            invalid.push(local);
        }
        for root in invalid {
            let mut changed = batches.clone();
            changed[0]["days"][0]["profile_documents"]["json_root"] = ordered(&root);
            let mut session = RenderSession::from_json(
                &serde_json::to_vec(&config).unwrap(),
                &serde_json::to_vec(&semantic).unwrap(),
            )
            .unwrap();
            session
                .process_batch(&serde_json::to_vec(&changed[0]).unwrap(), || false)
                .unwrap();
            assert_eq!(
                session.finish(|| false),
                Err(RenderError::PresentationMismatch)
            );
        }
    }
}

#[test]
fn generated_successor_api_units_come_from_registry_authority_not_presentation_labels() {
    let (mut config, semantic, mut batches) = android_successor_input();
    config["formats"] = json!(["json"]);
    config["unit_system"] = json!("imperial");
    enable_successor_api(&mut config, "android");
    for metric in batches[0]["days"][0]["metrics"].as_array_mut().unwrap() {
        metric["unit"] = json!("private-presentation-only-unit");
    }
    let plan = render(&config, &semantic, &batches);
    let item = plan
        .items
        .iter()
        .find(|item| item.relative_path.starts_with("api/"))
        .unwrap();
    let envelope: Value = serde_json::from_slice(&item.content).unwrap();
    let record = &envelope["records"][0];
    assert_eq!(record["activity"]["steps"], 1234);
    assert_eq!(record["sleep"]["lightSleep"], 4.25);
    // Registry v2 declares "steps" (proved equivalent to the reduced count unit).
    assert_eq!(record["units"]["steps"], "steps");
    assert_eq!(record["units"]["body_fat_percent"], "%");
    assert_eq!(record["units"]["sleep_light_hours"], "hours");
    assert!(
        !std::str::from_utf8(&item.content)
            .unwrap()
            .contains("private-presentation-only-unit")
    );
}

#[test]
fn wake_date_api_envelopes_keep_profile_and_clock_including_failure_only_batches() {
    for (mut config, mut semantic, mut batches, version, profile, source) in [
        {
            let (c, s, b) = apple_successor_input();
            (c, s, b, 11, "apple-v11", "ios")
        },
        {
            let (c, s, b) = android_successor_input();
            (c, s, b, 6, "android-sleep-v6", "android")
        },
    ] {
        config["formats"] = json!(["json"]);
        config["api"] = json!({
            "enabled":true, "envelope_version":1, "exported_at":"2026-07-25T00:00:00Z",
            "source":source, "date_range_start":"2026-07-25", "date_range_end":"2026-07-25",
            "failed_date_details":[], "external_record_schema":null, "external_record_schema_version":null,
            "external_records":[], "max_days_per_batch":7, "max_encoded_bytes":8_388_608
        });
        for failure_only in [false, true] {
            if failure_only {
                semantic["days"] = json!([]);
                batches[0]["days"] = json!([]);
                config["api"]["failed_date_details"] = json!([{
                    "owner_date":"2026-07-25", "timestamp":"2026-07-24T18:15:00Z",
                    "reason":"health_data_unavailable", "error_details":null
                }]);
            }
            let plan = render(&config, &semantic, &batches);
            let item = plan
                .items
                .iter()
                .find(|item| item.relative_path.starts_with("api/"))
                .unwrap();
            let envelope: Value = serde_json::from_slice(&item.content).unwrap();
            assert_eq!(envelope["schema"], "healthmd.api_export");
            assert_eq!(
                envelope["schema_version"], 1,
                "Envelope version is independent of daily version"
            );
            assert_eq!(envelope["daily_record_schema_version"], version);
            assert_eq!(envelope["daily_record_schema_profile"], profile);
            assert_eq!(
                envelope["daily_record_time_context"],
                json!({
                    "calendar_timezone":"Asia/Kathmandu", "timestamp_timezone":"UTC",
                    "sleep_day_attribution":"morning_ends", "sleep_owner_day_rule":"session_end_date",
                    "sleep_interval_clipping":"none"
                })
            );
            assert_eq!(envelope["record_count"], i32::from(!failure_only));
            if !failure_only {
                let record = &envelope["records"][0];
                assert_eq!(record["schema_version"], version);
                assert_eq!(record["schema_profile"], profile);
                assert_eq!(
                    record["time_context"],
                    envelope["daily_record_time_context"]
                );
                assert_eq!(record["unit_system"], "metric");
            }
        }
    }
}

#[test]
fn android_wake_date_outputs_are_versioned_and_do_not_alias_light_to_core() {
    let (config, semantic, batches) = android_successor_input();
    let plan = render(&config, &semantic, &batches);
    assert_eq!(plan.items.len(), 4);
    for item in plan.items {
        let text = std::str::from_utf8(&item.content).unwrap();
        assert!(text.contains("morning_ends"));
        assert!(text.contains("android-sleep-v6"));
        assert!(!text.contains("android-analytical-v5"));
        assert!(!text.contains("sleep_core_hours"));
        if has_extension(&item.relative_path, "json") {
            let doc: Value = serde_json::from_slice(&item.content).unwrap();
            assert_eq!(doc["schema"], "healthmd.health_data");
            assert_eq!(doc["schema_version"], 6);
            assert_eq!(doc["schema_profile"], "android-sleep-v6");
            assert_eq!(doc["schemaProfile"], "android-sleep-v6");
            assert_eq!(doc["schemaVersion"], 6);
            assert_eq!(doc["sleep"]["lightSleep"], 4.25);
            assert!(doc["sleep"].get("coreSleep").is_none());
        }
    }
}

#[test]
fn completed_wake_date_semantics_prevent_renderer_timezone_reinterpretation() {
    let config = json!({
        "schema":"healthmd.semantic_session_config", "semantic_input_version":2,
        "canonical_model_version":2, "registry_version":2, "registry_sha256":SLEEP_REGISTRY_SHA256,
        "profile_revision":1, "session_id":"clock-authority", "profile":"apple_health_data_v11",
        "calendar_time_zone":"America/Los_Angeles", "selected_selection_ids":[],
        "disabled_output_keys":[], "retain_platform_extensions":false, "rollup_periods":[]
    });
    let mut session = SemanticSession::from_json(&serde_json::to_vec(&config).unwrap()).unwrap();
    let batch = json!({
        "schema":"healthmd.semantic_input", "semantic_input_version":2, "session_id":"clock-authority",
        "batch_index":0, "final_batch":true, "owner_dates":["2026-07-25"], "records":[]
    });
    let result = session
        .process_batch(&serde_json::to_vec(&batch).unwrap(), || false)
        .unwrap();
    let result: Value = serde_json::from_slice(&result).unwrap();
    assert_eq!(
        result["sleep_capture_context"],
        json!({
            "schema_profile":"apple-v11", "calendar_timezone":"America/Los_Angeles",
            "sleep_day_attribution":"morning_ends", "sleep_owner_day_rule":"session_end_date",
            "sleep_interval_clipping":"none"
        })
    );
    let (mut render_config, _, _) = apple_successor_input();
    render_config["session_id"] = json!("clock-authority");
    // Asia/Kathmandu is a valid timezone, but not the timezone in which owner dates were captured.
    assert_eq!(
        RenderSession::from_json(
            &serde_json::to_vec(&render_config).unwrap(),
            &serde_json::to_vec(&result).unwrap()
        )
        .unwrap_err(),
        RenderError::InvalidConfig
    );
    render_config["calendar_time_zone"] = json!("America/Los_Angeles");
    assert!(
        RenderSession::from_json(
            &serde_json::to_vec(&render_config).unwrap(),
            &serde_json::to_vec(&result).unwrap()
        )
        .is_ok()
    );
}

#[test]
fn apple_wake_date_json_identifies_its_authority_even_with_no_sleep_values() {
    let (mut config, semantic, batches) = apple_successor_input();
    config["formats"] = json!(["json"]);
    let plan = render(&config, &semantic, &batches);
    assert_eq!(plan.items.len(), 1);
    let doc: Value = serde_json::from_slice(&plan.items[0].content).unwrap();
    assert_eq!(doc["schema"], "healthmd.health_data");
    assert_eq!(doc["schema_version"], 11);
    assert_eq!(doc["schema_profile"], "apple-v11");
    assert_eq!(
        doc["time_context"],
        json!({
            "calendar_timezone": "Asia/Kathmandu", "timestamp_timezone": "UTC",
            "sleep_day_attribution": "morning_ends",
            "sleep_owner_day_rule": "session_end_date", "sleep_interval_clipping": "none"
        })
    );
    assert_eq!(doc["activity"]["steps"], 1234);
}

#[test]
fn apple_wake_date_formats_keep_attribution_when_metadata_is_disabled() {
    let (mut config, semantic, batches) = apple_successor_input();
    for metadata in [true, false] {
        config["include_metadata"] = json!(metadata);
        let plan = render(&config, &semantic, &batches);
        assert_eq!(plan.items.len(), 4);
        for item in &plan.items {
            let text = std::str::from_utf8(&item.content).unwrap();
            if has_extension(&item.relative_path, "json") {
                let doc: Value = serde_json::from_slice(&item.content).unwrap();
                assert_eq!(doc["schema_version"], 11);
                assert_eq!(doc["time_context"]["sleep_day_attribution"], "morning_ends");
            } else if has_extension(&item.relative_path, "csv") {
                for (key, value) in [
                    ("schema_version", "11"),
                    ("schema_profile", "apple-v11"),
                    ("time_context.calendar_timezone", "Asia/Kathmandu"),
                    ("time_context.timestamp_timezone", "UTC"),
                    ("time_context.sleep_day_attribution", "morning_ends"),
                    ("time_context.sleep_owner_day_rule", "session_end_date"),
                    ("time_context.sleep_interval_clipping", "none"),
                ] {
                    assert!(
                        text.contains(&format!(",Metadata,{key},{value},,")),
                        "{key}: {text}"
                    );
                }
            } else if item.relative_path.contains("/Bases/") || metadata {
                assert!(text.starts_with("---\n"));
                for field in [
                    "schema_version: 11",
                    "schema_profile: apple-v11",
                    "sleep_day_attribution: morning_ends",
                    "sleep_owner_day_rule: session_end_date",
                    "sleep_interval_clipping: none",
                ] {
                    assert!(text.contains(field), "{field}: {text}");
                }
            } else {
                assert!(!text.starts_with("---\n"), "Do not re-enable frontmatter");
                for field in [
                    "Morning ends",
                    "morning_ends",
                    "whole sessions",
                    "apple-v11",
                    "Asia/Kathmandu",
                    "UTC",
                    "session_end_date",
                    "none",
                ] {
                    assert!(text.contains(field), "{field}: {text}");
                }
            }
        }
    }
}

#[test]
fn successor_native_details_preserve_exact_rows_without_changing_machine_summaries() {
    for input in [apple_successor_input, android_successor_input] {
        let (config, semantic, mut batches) = input();
        let original = render(&config, &semantic, &batches);
        batches[0]["days"][0]["native_details"] = json!({
            "output_keys":["steps"],
            "csv_rows":[{"date":"2026-07-25","category":"Activity Detail","metric":"Steps sample",
                "value":"1234.125","unit":"steps","timestamp":"2026-07-24T23:45:00.123456789Z","ordinal":0}],
            "markdown_blocks":[{"heading":"Activity Samples","lines":["1234.125 steps at 2026-07-24T23:45:00.123456789Z"],"ordinal":0}],
            "bases_frontmatter_blocks":[{"key":"activity_samples","lines":["  - value: 1234.125","    timestamp: 2026-07-24T23:45:00.123456789Z"],"ordinal":0}]
        });
        let mut quoted_batches = batches.clone();
        quoted_batches[0]["days"][0]["native_details"]["bases_frontmatter_blocks"][0]["key"] =
            json!("activity samples: exact");
        let quoted = render(&config, &semantic, &quoted_batches);
        let quoted_bases = quoted
            .items
            .iter()
            .find(|item| item.relative_path.contains("/Bases/"))
            .unwrap();
        assert!(
            String::from_utf8(quoted_bases.content.clone())
                .unwrap()
                .contains("\"activity samples: exact\":\n")
        );
        let mut custom_config = config.clone();
        custom_config["markdown"]["custom_template"] =
            json!("# Personal {{date}}\n{{activity_metrics}}\n");
        let custom_plan = render(&custom_config, &semantic, &batches);
        let custom_markdown = custom_plan
            .items
            .iter()
            .find(|item| item.relative_path.contains("/Markdown/"))
            .unwrap();
        let custom_text = String::from_utf8(custom_markdown.content.clone()).unwrap();
        assert!(custom_text.contains("# Personal"));
        assert_eq!(
            custom_text.matches("Activity Samples").count(),
            1,
            "Custom templates cannot discard or duplicate requested detail blocks"
        );
        let plan = render(&config, &semantic, &batches);
        for item in &plan.items {
            let text = String::from_utf8(item.content.clone()).unwrap();
            if has_extension(&item.relative_path, "csv") {
                assert!(text.contains("2026-07-25,Activity Detail,Steps sample,1234.125,steps,2026-07-24T23:45:00.123456789Z"));
            } else if item.relative_path.contains("/Bases/")
                || item.relative_path.ends_with("-bases.md")
            {
                assert!(text.contains("activity_samples:\n  - value: 1234.125"));
            } else if has_extension(&item.relative_path, "md") {
                assert!(text.contains("Activity Samples"), "{}", item.relative_path);
                assert!(text.contains("2026-07-24T23:45:00.123456789Z"));
            } else if has_extension(&item.relative_path, "json") {
                let before = original
                    .items
                    .iter()
                    .find(|old| old.relative_path == item.relative_path)
                    .unwrap();
                assert_eq!(
                    item.content, before.content,
                    "Detail presentation must not rewrite the public JSON projection"
                );
            }
        }
    }
}

#[test]
fn successor_native_details_reject_wrong_owner_unselected_outputs_and_invalid_instants_transactionally()
 {
    for input in [apple_successor_input, android_successor_input] {
        for mutation in [
            "owner",
            "selection",
            "timestamp",
            "duplicate",
            "null",
            "reserved",
            "limit",
            "block_limit",
            "yaml_escape",
            "yaml_multiline",
            "native_markdown",
        ] {
            let (config, semantic, mut batches) = input();
            let mut details = json!({"output_keys":["steps"],"csv_rows":[{"date":"2026-07-25","category":"Activity Detail","metric":"Steps sample","value":"1234.125","unit":"steps","timestamp":"2026-07-24T23:45:00.123456789Z","ordinal":0}],"markdown_blocks":[],"bases_frontmatter_blocks":[]});
            match mutation {
                "owner" => details["csv_rows"][0]["date"] = json!("2026-07-24"),
                "selection" => details["output_keys"] = json!(["unselected"]),
                "timestamp" => {
                    details["csv_rows"][0]["timestamp"] = json!("2026-07-25T05:30:00+05:45");
                }
                "duplicate" => details["output_keys"] = json!(["steps", "steps"]),
                "null" => details = Value::Null,
                "reserved" => {
                    details["bases_frontmatter_blocks"] =
                        json!([{"key":"units","lines":["  steps: false"],"ordinal":0}]);
                }
                "limit" => {
                    details["csv_rows"] = Value::Array(vec![details["csv_rows"][0].clone(); 4097]);
                }
                "native_markdown" => {
                    let keys = batches[0]["days"][0]["metrics"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|metric| metric["output_key"].clone())
                        .collect::<Vec<_>>();
                    batches[0]["days"][0]["profile_documents"] = json!({"semantic_output_keys":keys,"markdown_body":{"lines":["Native body"],"trailing_newline":true},"csv_rows":null,"json_root":null});
                }
                "yaml_escape" => {
                    details["bases_frontmatter_blocks"] =
                        json!([{"key":"samples","lines":["schema_version: 0"],"ordinal":0}]);
                }
                "yaml_multiline" => {
                    details["bases_frontmatter_blocks"] = json!([{"key":"samples","lines":["  - value: 1\nschema_version: 0"],"ordinal":0}]);
                }
                "block_limit" => {
                    details["markdown_blocks"] = Value::Array(
                        (0..4097)
                            .map(
                                |ordinal| json!({"heading":"Samples","lines":[],"ordinal":ordinal}),
                            )
                            .collect(),
                    );
                }
                _ => unreachable!(),
            }
            batches[0]["days"][0]["native_details"] = details;
            let mut session = RenderSession::from_json(
                &serde_json::to_vec(&config).unwrap(),
                &serde_json::to_vec(&semantic).unwrap(),
            )
            .unwrap();
            assert!(
                session
                    .process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false)
                    .is_err(),
                "{mutation}"
            );
            batches[0]["days"][0]
                .as_object_mut()
                .unwrap()
                .remove("native_details");
            if mutation == "native_markdown" {
                batches[0]["days"][0]
                    .as_object_mut()
                    .unwrap()
                    .remove("profile_documents");
            }
            session
                .process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false)
                .expect("Rejected detail batch must not advance the accepted frontier");
            session.finish(|| false).unwrap();
        }
    }
}

#[test]
fn successor_detail_blocks_cannot_shadow_archive_diagnostics() {
    for input in [apple_successor_input, android_successor_input] {
        for key in [
            "raw_record_count",
            "raw_query_failure_count",
            "raw_integrity_warning_count",
            "raw_record_schema",
            "raw_record_schema_version",
        ] {
            let (config, semantic, mut batches) = input();
            batches[0]["days"][0]["native_details"] = json!({
                "output_keys":["steps"], "csv_rows":[], "markdown_blocks":[],
                "bases_frontmatter_blocks":[{"key":key,"lines":["  forged: true"],"ordinal":0}]
            });
            let mut session = RenderSession::from_json(
                &serde_json::to_vec(&config).unwrap(),
                &serde_json::to_vec(&semantic).unwrap(),
            )
            .unwrap();
            assert_eq!(
                session.process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false),
                Err(RenderError::PresentationMismatch),
                "detail key {key} must not shadow generated archive metadata"
            );
            batches[0]["days"][0]
                .as_object_mut()
                .unwrap()
                .remove("native_details");
            session
                .process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false)
                .expect("metadata collision must not advance the accepted frontier");
            session.finish(|| false).unwrap();
        }
    }
}

#[test]
fn selected_details_survive_unavailable_summaries_without_fabricating_values() {
    let fixture: Value = serde_json::from_slice(include_bytes!(
        "../../../../contracts/render-input/v2/fixtures/native-android-v6-handoff.json"
    ))
    .unwrap();
    for input in [apple_successor_input, android_successor_input] {
        let (mut config, _, mut batches) = input();
        let mut semantic_config = fixture["semantic_configuration"].clone();
        semantic_config["profile"] = config["profile"].clone();
        semantic_config["session_id"] = config["session_id"].clone();
        semantic_config["selected_selection_ids"] = json!(["sleep_total"]);
        let mut source = fixture["semantic_batches"][0].clone();
        source["session_id"] = config["session_id"].clone();
        source["records"] = json!([]);
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&semantic_config).unwrap()).unwrap();
        let result = session
            .process_batch(&serde_json::to_vec(&source).unwrap(), || false)
            .unwrap();
        let semantic: Value = serde_json::from_slice(&result).unwrap();
        assert!(semantic["days"][0]["values"].as_array().unwrap().is_empty());
        assert!(
            semantic["selected_output_keys"]
                .as_array()
                .unwrap()
                .contains(&json!("sleep_total_hours"))
        );
        batches[0]["days"][0]["metrics"] = json!([]);
        batches[0]["days"][0]["profile_documents"] = json!({"semantic_output_keys":[],"markdown_body":null,"csv_rows":null,"json_root":null});
        batches[0]["days"][0]["native_details"] = json!({"output_keys":["sleep_total_hours"],"csv_rows":[{"date":"2026-07-25","category":"Sleep Detail","metric":"Sleep Stage","value":"synthetic-source-interval","unit":"seconds","timestamp":"2026-07-25T01:00:00Z","ordinal":0}],"markdown_blocks":[],"bases_frontmatter_blocks":[]});
        config["formats"] = json!(["csv"]);
        let plan = render(&config, &semantic, &batches);
        let text = std::str::from_utf8(&plan.items[0].content).unwrap();
        assert!(text.contains("synthetic-source-interval"));
        assert!(!text.contains(",Total Sleep,"));
        for selection in [
            json!([]),
            json!(["unknown_output"]),
            json!(["sleep_total_hours", "sleep_total_hours"]),
        ] {
            let mut rejected = semantic.clone();
            rejected["selected_output_keys"] = selection;
            match RenderSession::from_json(
                &serde_json::to_vec(&config).unwrap(),
                &serde_json::to_vec(&rejected).unwrap(),
            ) {
                Ok(mut renderer) => assert_eq!(
                    renderer.process_batch(&serde_json::to_vec(&batches[0]).unwrap(), || false),
                    Err(RenderError::PresentationMismatch)
                ),
                Err(error) => assert_eq!(error, RenderError::PresentationMismatch),
            }
        }
        semantic_config["disabled_output_keys"] = json!(["sleep_total_hours"]);
        let mut disabled =
            SemanticSession::from_json(&serde_json::to_vec(&semantic_config).unwrap()).unwrap();
        let result: Value = serde_json::from_slice(
            &disabled
                .process_batch(&serde_json::to_vec(&source).unwrap(), || false)
                .unwrap(),
        )
        .unwrap();
        assert!(
            !result["selected_output_keys"]
                .as_array()
                .unwrap()
                .contains(&json!("sleep_total_hours"))
        );
    }
}
