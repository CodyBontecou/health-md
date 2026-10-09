use healthmd_core::registry::{MetricRegistryProfile, metric_registry_snapshot};
use healthmd_core::sleep::{
    SleepDayAttribution, SleepProfileError, SleepSource, read_public_sleep_context,
};
use serde_json::{Value, json};

#[test]
fn wake_date_authority_survives_a_daily_document_with_no_sleep_values() {
    let day: Value = serde_json::from_str(include_str!(
        "../../../../contracts/sleep-attribution/v1/fixtures/apple-v11-empty-sleep.json"
    ))
    .expect("synthetic successor fixture");
    let context = read_public_sleep_context(
        SleepSource::Apple,
        11,
        day.get("schema_profile").and_then(Value::as_str),
        day.get("time_context"),
    )
    .expect("approved wake-date metadata must not disappear when sleep is empty");

    assert_eq!(context.attribution, SleepDayAttribution::MorningEnds);
    assert_eq!(
        context.calendar_timezone.as_deref(),
        Some("America/Los_Angeles")
    );
    assert_eq!(context.timestamp_timezone.as_deref(), Some("UTC"));
    assert_eq!(context.successor_profile.as_deref(), Some("apple-v11"));
}

#[test]
fn wake_date_registry_is_separate_from_the_immutable_night_begins_registry() {
    let profile: MetricRegistryProfile = serde_json::from_str("\"apple_health_data_v11\"")
        .expect("explicit successor registry profile");
    let successor = metric_registry_snapshot(profile, 2).expect("versioned successor inventory");
    assert_eq!(successor.public_profile_id, "apple-v11");
    assert_eq!(successor.public_schema_version, 11);
    assert_eq!(successor.registry_version, 2);

    let historical = metric_registry_snapshot(MetricRegistryProfile::AppleHealthDataV8, 1)
        .expect("historical inventory remains available");
    assert_eq!(historical.public_schema_version, 8);
    assert_eq!(historical.registry_version, 1);
    assert_eq!(
        historical.registry_sha256,
        "56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99"
    );
    assert_ne!(successor.registry_sha256, historical.registry_sha256);
}

#[test]
fn android_successor_retains_light_as_distinct_from_apple_core_sleep() {
    let profile: MetricRegistryProfile = serde_json::from_str("\"android_sleep_v6\"").unwrap();
    let snapshot = metric_registry_snapshot(profile, 2).unwrap();
    assert_eq!(snapshot.public_profile_id, "android-sleep-v6");
    assert_eq!(snapshot.public_schema_version, 6);
    let light = snapshot
        .metrics
        .iter()
        .find(|metric| metric.selection_id == "sleep_light")
        .unwrap();
    assert_eq!(light.semantic_id, "sleep_light");
    assert!(
        snapshot
            .outputs
            .iter()
            .any(|output| output.key == "sleep_light_hours" && output.enabled_by_default)
    );
    assert!(
        !snapshot
            .outputs
            .iter()
            .any(|output| output.key == "sleep_core_hours")
    );

    let old = metric_registry_snapshot(MetricRegistryProfile::AndroidAnalyticalV5, 1).unwrap();
    assert!(
        old.outputs
            .iter()
            .any(|output| output.key == "sleep_core_hours")
    );
}

#[test]
fn frozen_daily_versions_cannot_be_relabeled_by_attribution_metadata() {
    let context = json!({
        "calendar_timezone": "UTC", "timestamp_timezone": "UTC",
        "sleep_day_attribution": "morning_ends",
        "sleep_owner_day_rule": "session_end_date", "sleep_interval_clipping": "none"
    });
    for (source, version) in [
        (SleepSource::Apple, 8),
        (SleepSource::Android, 4),
        (SleepSource::Android, 5),
    ] {
        assert_eq!(
            read_public_sleep_context(source, version, None, Some(&context)),
            Err(SleepProfileError::IncompatibleAttribution)
        );
    }
}

#[test]
fn successor_metadata_is_atomic_and_cannot_fall_back_to_night_begins() {
    let valid = json!({
        "calendar_timezone": "America/Los_Angeles", "timestamp_timezone": "UTC",
        "sleep_day_attribution": "morning_ends",
        "sleep_owner_day_rule": "session_end_date", "sleep_interval_clipping": "none"
    });
    for key in [
        "sleep_day_attribution",
        "sleep_owner_day_rule",
        "sleep_interval_clipping",
    ] {
        let mut missing = valid.clone();
        missing.as_object_mut().unwrap().remove(key);
        assert_eq!(
            read_public_sleep_context(SleepSource::Apple, 11, Some("apple-v11"), Some(&missing)),
            Err(SleepProfileError::InvalidMetadata)
        );
        let mut contradictory = valid.clone();
        contradictory[key] = json!("private-invalid-value");
        let error = read_public_sleep_context(
            SleepSource::Apple,
            11,
            Some("apple-v11"),
            Some(&contradictory),
        )
        .unwrap_err();
        assert_eq!(error, SleepProfileError::IncompatibleAttribution);
        assert!(!error.to_string().contains("private-invalid-value"));
    }
    assert_eq!(
        read_public_sleep_context(SleepSource::Apple, 11, None, Some(&valid)),
        Err(SleepProfileError::UnsupportedProfile)
    );
    assert_eq!(
        read_public_sleep_context(
            SleepSource::Apple,
            11,
            Some("android-sleep-v6"),
            Some(&valid)
        ),
        Err(SleepProfileError::UnsupportedProfile)
    );
}

#[test]
fn successor_clock_authority_is_validated_instead_of_using_the_reader_timezone() {
    let mut context = json!({
        "calendar_timezone": "America/Los_Angeles", "timestamp_timezone": "America/Los_Angeles",
        "sleep_day_attribution": "morning_ends",
        "sleep_owner_day_rule": "session_end_date", "sleep_interval_clipping": "none"
    });
    let android = read_public_sleep_context(
        SleepSource::Android,
        6,
        Some("android-sleep-v6"),
        Some(&context),
    )
    .unwrap();
    assert_eq!(
        android.timestamp_timezone.as_deref(),
        Some("America/Los_Angeles")
    );
    assert_eq!(
        read_public_sleep_context(SleepSource::Apple, 11, Some("apple-v11"), Some(&context)),
        Err(SleepProfileError::InvalidTimezone)
    );
    context["timestamp_timezone"] = json!("UTC");
    context["calendar_timezone"] = json!("private-invalid-zone");
    let error = read_public_sleep_context(
        SleepSource::Android,
        6,
        Some("android-sleep-v6"),
        Some(&context),
    )
    .unwrap_err();
    assert_eq!(error.code(), "invalid_sleep_attribution_timezone");
    assert!(!error.to_string().contains("private-invalid-zone"));
}

#[test]
fn historical_absence_preserves_only_the_immutable_night_begins_meaning() {
    for (source, version) in [
        (SleepSource::Apple, 5),
        (SleepSource::Apple, 6),
        (SleepSource::Apple, 7),
        (SleepSource::Apple, 8),
        (SleepSource::Android, 4),
        (SleepSource::Android, 5),
    ] {
        let context = read_public_sleep_context(source, version, None, None).unwrap();
        assert_eq!(context.attribution, SleepDayAttribution::NightBegins);
        assert_eq!(context.successor_profile, None);
        assert_eq!(context.calendar_timezone, None);
    }
}

#[test]
fn wake_date_identity_cannot_reuse_the_whoop_v10_identity() {
    let authority = json!({
        "calendar_timezone": "America/New_York",
        "timestamp_timezone": "UTC",
        "sleep_day_attribution": "morning_ends",
        "sleep_owner_day_rule": "session_end_date",
        "sleep_interval_clipping": "none"
    });
    assert_eq!(
        read_public_sleep_context(SleepSource::Apple, 10, Some("apple-v10"), Some(&authority)),
        Err(SleepProfileError::UnsupportedProfile),
        "The old draft identity is not a qualified sleep profile"
    );
    let context =
        read_public_sleep_context(SleepSource::Apple, 11, Some("apple-v11"), Some(&authority))
            .expect("Wake-date exports need their own versioned identity");
    assert_eq!(context.successor_profile.as_deref(), Some("apple-v11"));
    assert!(serde_json::from_str::<MetricRegistryProfile>("\"apple_health_data_v10\"").is_err());
}
