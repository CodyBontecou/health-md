use healthmd_core::{render::prepare_scoped_daily_note, semantic::SemanticProfile};

pub(crate) fn scoped_note_patch(android: bool) -> String {
    let profile = if android {
        SemanticProfile::AndroidSleepV6
    } else {
        SemanticProfile::AppleHealthDataV11
    };
    let record = serde_json::json!({
        "schema": "healthmd.health_data", "type": "health-data",
        "schema_version": if android { 6 } else { 11 },
        "schema_profile": if android { "android-sleep-v6" } else { "apple-v11" }, "date": "2026-07-23",
        "time_context": {"calendar_timezone": "UTC", "timestamp_timezone": "UTC",
            "sleep_day_attribution": "morning_ends", "sleep_owner_day_rule": "session_end_date",
            "sleep_interval_clipping": "none"}, "activity": {"steps": 42}
    });
    prepare_scoped_daily_note(
        profile,
        &record.to_string(),
        "---\nsteps: 42\n---\n",
        "---\n---\n## Activity\nCurrent steps.\n",
        &["steps".into()],
        true,
    )
    .unwrap()
}

pub(crate) fn personal_journal() -> String {
    format!(
        "---\r\nnotes: |\r\n  Keep my: multiline YAML\r\n---\r\n{}",
        "Personal journal.\r\n".repeat(500)
    )
}
