//! Capture-scoped patches for personal notes; historical whole-document mergers stay unchanged.

use super::{
    FrontmatterPropertyKey, PhysicalLine, RenderError, append_lines, apple_merge,
    apple_merge_frontmatter, frontmatter_document, property_blocks, render_frontmatter_envelope,
    validate, wake_date::scalar_property,
};
use crate::{
    semantic::SemanticProfile,
    sleep::{SleepSource, read_public_sleep_context},
};
use serde::{
    Deserialize, Deserializer,
    de::{self, IgnoredAny, MapAccess, Visitor},
};
use serde_json::{Map, Value};
use std::{collections::HashSet, fmt::Write};

const KIND_KEY: &str = "healthmd_injection_kind";
const CAPTURE_KEY: &str = "healthmd_daily_injection_v1";
const NIGHT_CAPTURE_KEY: &str = "healthmd_daily_injection_v2";

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct NightClock {
    calendar_timezone: String,
    timestamp_timezone: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct NightEnvelope {
    kind: String,
    version: u32,
    record_profile: String,
    time_context: NightClock,
    record_json: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope {
    kind: String,
    version: u32,
    record_json: String,
}

/// Project selected generated properties and optional sections into a scoped
/// personal-note patch. Inputs are artifacts from one accepted native plan.
///
/// # Errors
/// Rejects invalid identity, unsafe/duplicate property names and ambiguous YAML.
pub fn prepare_scoped_daily_note(
    profile: SemanticProfile,
    record_json: &str,
    bases: &str,
    markdown: &str,
    selected_properties: &[String],
    inject_sections: bool,
) -> Result<String, RenderError> {
    validate(record_json, bases)?;
    validate(markdown, "")?;
    validate_capture(profile, record_json)?;
    let envelope = serde_json::json!({"kind":"healthmd_daily_capture", "version":1, "record_json":record_json});
    prepare_patch(
        bases,
        markdown,
        selected_properties,
        inject_sections,
        "daily_capture_v1",
        CAPTURE_KEY,
        &envelope,
    )
}

/// Scope an unchanged historical Android native record with its captured local clock.
///
/// # Errors
/// Rejects unsupported historical profiles, conflicting inner authority or invalid clocks.
pub fn prepare_scoped_android_night_note(
    profile: SemanticProfile,
    record_json: &str,
    calendar_timezone: &str,
    bases: &str,
    markdown: &str,
    selected_properties: &[String],
    inject_sections: bool,
) -> Result<String, RenderError> {
    validate(record_json, bases)?;
    validate(markdown, "")?;
    validate_night_capture(profile, record_json, calendar_timezone)?;
    let envelope = serde_json::json!({"kind":"healthmd_daily_capture", "version":2,
        "record_profile":profile.public_profile_id(), "record_json":record_json,
        "time_context":{"calendar_timezone":calendar_timezone,"timestamp_timezone":calendar_timezone}});
    prepare_patch(
        bases,
        markdown,
        selected_properties,
        inject_sections,
        "daily_capture_v2",
        NIGHT_CAPTURE_KEY,
        &envelope,
    )
}

fn prepare_patch(
    bases: &str,
    markdown: &str,
    selected_properties: &[String],
    inject_sections: bool,
    kind: &str,
    capture_key: &str,
    envelope: &Value,
) -> Result<String, RenderError> {
    let names: HashSet<&str> = selected_properties.iter().map(String::as_str).collect();
    if names.len() != selected_properties.len()
        || names.len() > 512
        || names.iter().any(|key| {
            key.is_empty()
                || key.len() > 128
                || matches!(*key, KIND_KEY | CAPTURE_KEY | NIGHT_CAPTURE_KEY)
        })
    {
        return Err(RenderError::PresentationMismatch);
    }
    let document = frontmatter_document(bases).ok_or(RenderError::PresentationMismatch)?;
    let blocks = property_blocks(&document.content).ok_or(RenderError::PresentationMismatch)?;
    let mut seen = HashSet::new();
    let mut output = String::from("---\n");
    for block in blocks {
        let FrontmatterPropertyKey::String(key) = block.key else {
            continue;
        };
        if !names.contains(key.as_str()) {
            continue;
        }
        if !seen.insert(key) {
            return Err(RenderError::PresentationMismatch);
        }
        append_lines(&mut output, &document.content[block.range]);
        if !output.ends_with('\n') {
            output.push('\n');
        }
    }
    let quoted =
        serde_json::to_string(&envelope.to_string()).map_err(|_| RenderError::InvalidArtifact)?;
    writeln!(
        output,
        "{KIND_KEY}: {kind}\n{capture_key}: {quoted}\n{}: null\n---",
        if capture_key == CAPTURE_KEY {
            NIGHT_CAPTURE_KEY
        } else {
            CAPTURE_KEY
        }
    )
    .map_err(|_| RenderError::InvalidArtifact)?;
    if inject_sections {
        if let Some(document) = frontmatter_document(markdown) {
            append_lines(&mut output, &document.suffix);
        } else {
            output.push_str(markdown);
        }
    }
    validate(&output, "")?;
    Ok(output)
}

/// Merge one independently versioned capture into a personal note without
/// assigning its daily profile to retained personal/historical properties.
///
/// # Errors
/// Rejects unsupported capture authority, registered whole-export destinations,
/// ambiguous YAML and the managed merger's bounded input/output sizes.
pub fn merge_scoped_daily_note(
    profile: SemanticProfile,
    existing: &str,
    patch: &str,
    inject_sections: bool,
) -> Result<String, RenderError> {
    validate(existing, patch)?;
    let mut incoming = frontmatter_document(patch).ok_or(RenderError::PresentationMismatch)?;
    let blocks = property_blocks(&incoming.content).ok_or(RenderError::PresentationMismatch)?;
    let mut kind = None;
    let mut capture = None;
    let mut night_capture = None;
    for block in blocks {
        let FrontmatterPropertyKey::String(key) = block.key else {
            continue;
        };
        let target = match key.as_str() {
            KIND_KEY => &mut kind,
            CAPTURE_KEY => &mut capture,
            NIGHT_CAPTURE_KEY => &mut night_capture,
            _ => continue,
        };
        if target.is_some() {
            return Err(RenderError::PresentationMismatch);
        }
        *target = Some(scalar_property(&incoming.content[block.range])?);
    }
    match kind.as_deref() {
        Some("daily_capture_v1") => {
            let envelope: Envelope = serde_json::from_str(
                capture
                    .as_deref()
                    .ok_or(RenderError::PresentationMismatch)?,
            )
            .map_err(|_| RenderError::PresentationMismatch)?;
            if envelope.kind != "healthmd_daily_capture" || envelope.version != 1 {
                return Err(RenderError::PresentationMismatch);
            }
            validate_capture(profile, &envelope.record_json)?;
        }
        Some("daily_capture_v2") => {
            let envelope: NightEnvelope = serde_json::from_str(
                night_capture
                    .as_deref()
                    .ok_or(RenderError::PresentationMismatch)?,
            )
            .map_err(|_| RenderError::PresentationMismatch)?;
            if envelope.kind != "healthmd_daily_capture"
                || envelope.version != 2
                || envelope.record_profile != profile.public_profile_id()
                || envelope.time_context.calendar_timezone
                    != envelope.time_context.timestamp_timezone
            {
                return Err(RenderError::PresentationMismatch);
            }
            validate_night_capture(
                profile,
                &envelope.record_json,
                &envelope.time_context.calendar_timezone,
            )?;
        }
        _ => return Err(RenderError::PresentationMismatch),
    }
    let (inactive_key, inactive_value) = if kind.as_deref() == Some("daily_capture_v1") {
        (NIGHT_CAPTURE_KEY, night_capture.as_deref())
    } else {
        (CAPTURE_KEY, capture.as_deref())
    };
    if inactive_value.is_some_and(|value| value != "null") {
        return Err(RenderError::PresentationMismatch);
    }
    if inactive_value.is_none() {
        incoming.content.push(PhysicalLine {
            content: format!("{inactive_key}: null"),
            ending: "\n",
        });
    }
    let mut normalized_patch = render_frontmatter_envelope(&incoming);
    append_lines(&mut normalized_patch, &incoming.suffix);
    let patch = normalized_patch.as_str();
    reject_whole_export(existing)?;
    reject_whole_export(patch)?;
    let output = if inject_sections {
        apple_merge(existing, patch, true)?
    } else {
        let generated = render_frontmatter_envelope(&incoming);
        if let Some(document) = frontmatter_document(existing) {
            let mut result =
                apple_merge_frontmatter(&render_frontmatter_envelope(&document), &generated)?;
            append_lines(&mut result, &document.suffix);
            result
        } else if existing.is_empty() {
            generated
        } else {
            format!("{generated}\n{existing}")
        }
    };
    validate(&output, "")?;
    Ok(output)
}

fn reject_whole_export(text: &str) -> Result<(), RenderError> {
    if let Some(document) = frontmatter_document(text) {
        let blocks = property_blocks(&document.content).ok_or(RenderError::PresentationMismatch)?;
        for block in blocks {
            if block.key == FrontmatterPropertyKey::String("schema".into())
                && scalar_property(&document.content[block.range]).is_ok_and(|schema| {
                    matches!(
                        schema.as_str(),
                        "healthmd.health_data" | "healthmd.health_rollup"
                    )
                })
            {
                return Err(RenderError::PresentationMismatch);
            }
        }
    }
    Ok(())
}

// Skip metric arrays instead of materializing a second native-record graph.
// Duplicate root keys and metadata aliases cannot disappear before validation.
struct CaptureHeader(Map<String, Value>);
impl<'de> Deserialize<'de> for CaptureHeader {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct HeaderVisitor;
        impl<'de> Visitor<'de> for HeaderVisitor {
            type Value = CaptureHeader;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("a capture record")
            }
            fn visit_map<M: MapAccess<'de>>(self, mut map: M) -> Result<Self::Value, M::Error> {
                let mut seen = HashSet::new();
                let mut header = Map::new();
                while let Some(key) = map.next_key::<String>()? {
                    if !seen.insert(key.clone()) || key == "healthkit_record_archive" {
                        return Err(de::Error::custom("invalid capture authority"));
                    }
                    if matches!(
                        key.as_str(),
                        "schema"
                            | "schema_version"
                            | "schema_profile"
                            | "type"
                            | "date"
                            | "time_context"
                            | "schemaVersion"
                            | "schemaProfile"
                            | "timeContext"
                    ) {
                        let value: Value = map.next_value()?;
                        if value.to_string().len() > 4096 {
                            return Err(de::Error::custom("invalid capture authority"));
                        }
                        header.insert(key, value);
                    } else {
                        let _: IgnoredAny = map.next_value()?;
                    }
                }
                Ok(CaptureHeader(header))
            }
        }
        deserializer.deserialize_map(HeaderVisitor)
    }
}

fn validate_capture(profile: SemanticProfile, json: &str) -> Result<(), RenderError> {
    // V1's inner record declares its own clock. Frozen Android historical
    // records need independently qualified outer-clock authority.
    if !profile.is_wake_date() && profile != SemanticProfile::AppleHealthDataV8 {
        return Err(RenderError::PresentationMismatch);
    }
    let CaptureHeader(header) =
        serde_json::from_str(json).map_err(|_| RenderError::PresentationMismatch)?;
    let fail = || RenderError::PresentationMismatch;
    if ["schemaVersion", "schemaProfile", "timeContext"]
        .iter()
        .any(|key| header.contains_key(*key))
        || header.get("schema").and_then(Value::as_str) != Some("healthmd.health_data")
        || header.get("type").and_then(Value::as_str) != Some("health-data")
        || header.get("schema_version").and_then(Value::as_u64)
            != Some(u64::from(profile.public_schema_version()))
    {
        return Err(fail());
    }
    let identity = match header.get("schema_profile") {
        None => None,
        Some(Value::String(value)) => Some(value.as_str()),
        _ => return Err(fail()),
    };
    if profile == SemanticProfile::AppleHealthDataV8 && identity.is_some() {
        return Err(fail());
    }
    let context = read_public_sleep_context(
        if profile.is_apple() {
            SleepSource::Apple
        } else {
            SleepSource::Android
        },
        profile.public_schema_version(),
        identity,
        header.get("time_context"),
    )
    .map_err(|_| fail())?;
    let calendar = context.calendar_timezone.as_deref().ok_or_else(fail)?;
    let timestamp = context.timestamp_timezone.as_deref().ok_or_else(fail)?;
    if calendar.len() > 128
        || calendar.parse::<chrono_tz::Tz>().is_err()
        || (timestamp != "UTC" && (profile.is_apple() || timestamp != calendar))
    {
        return Err(fail());
    }
    let date = header
        .get("date")
        .and_then(Value::as_str)
        .ok_or_else(fail)?;
    let parsed = chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d").map_err(|_| fail())?;
    if date.len() != 10 || parsed.format("%Y-%m-%d").to_string() != date {
        return Err(fail());
    }
    Ok(())
}

fn validate_night_capture(
    profile: SemanticProfile,
    json: &str,
    zone: &str,
) -> Result<(), RenderError> {
    let fail = || RenderError::PresentationMismatch;
    if !matches!(
        profile,
        SemanticProfile::AndroidFrozenV4 | SemanticProfile::AndroidAnalyticalV5
    ) || zone.len() > 128
        || zone.parse::<chrono_tz::Tz>().is_err()
    {
        return Err(fail());
    }
    let CaptureHeader(header) = serde_json::from_str(json).map_err(|_| fail())?;
    if header.get("type").and_then(Value::as_str) != Some("health-data")
        || [
            "schema",
            "schema_version",
            "schema_profile",
            "time_context",
            "timeContext",
        ]
        .iter()
        .any(|key| header.contains_key(*key))
    {
        return Err(fail());
    }
    match profile {
        SemanticProfile::AndroidFrozenV4 => {
            if header.contains_key("schemaVersion") || header.contains_key("schemaProfile") {
                return Err(fail());
            }
        }
        SemanticProfile::AndroidAnalyticalV5 => {
            if header.get("schemaVersion").and_then(Value::as_u64) != Some(5)
                || header.get("schemaProfile").and_then(Value::as_str)
                    != Some("android-analytical-v5")
            {
                return Err(fail());
            }
        }
        _ => return Err(fail()),
    }
    let date = header
        .get("date")
        .and_then(Value::as_str)
        .ok_or_else(fail)?;
    let parsed = chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d").map_err(|_| fail())?;
    if date.len() != 10 || parsed.format("%Y-%m-%d").to_string() != date {
        return Err(fail());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn historical_android_capture_keeps_native_bytes_and_explicit_clock_across_toggles() {
        for profile in [
            SemanticProfile::AndroidFrozenV4,
            SemanticProfile::AndroidAnalyticalV5,
        ] {
            let json = if profile == SemanticProfile::AndroidFrozenV4 {
                "{\n \"date\":\"2026-03-08\",\"type\":\"health-data\",\"units\":\"metric\",\"activity\":{\"steps\":42}\n}"
            } else {
                "{\n \"date\":\"2026-03-08\",\"type\":\"health-data\",\"schemaVersion\":5,\"schemaProfile\":\"android-analytical-v5\",\"activity\":{\"steps\":42}\n}"
            };
            for sections in [false, true] {
                let night_patch = prepare_scoped_android_night_note(
                    profile,
                    json,
                    "America/New_York",
                    "---\nsteps: 42\nsleep_deep_hours: 99\n---\n",
                    "## Activity\nCurrent steps\n",
                    &["steps".into()],
                    sections,
                )
                .unwrap();
                let personal = "---\r\nnotes: |\r\n  Keep my journal\r\nsleep_deep_hours: 9\r\n---\r\nIntroduction\r\n## Journal\r\nKeep this section\r\n";
                let morning = merge_scoped_daily_note(
                    SemanticProfile::AndroidSleepV6,
                    personal,
                    &patch(SemanticProfile::AndroidSleepV6),
                    true,
                )
                .unwrap();
                let night =
                    merge_scoped_daily_note(profile, &morning, &night_patch, sections).unwrap();
                assert!(night.contains("notes: |\r\n  Keep my journal\r\n"));
                assert!(night.contains("sleep_deep_hours: 9\r\n"));
                assert!(night.contains("Keep this section"));
                assert!(night.contains("healthmd_daily_injection_v1: null"));
                let document = frontmatter_document(&night).unwrap();
                let blocks = property_blocks(&document.content).unwrap();
                let envelope = blocks
                    .into_iter()
                    .find(|b| b.key == FrontmatterPropertyKey::String(NIGHT_CAPTURE_KEY.into()))
                    .unwrap();
                let value = scalar_property(&document.content[envelope.range]).unwrap();
                let envelope: NightEnvelope = serde_json::from_str(&value).unwrap();
                assert_eq!(envelope.record_json, json);
                assert_eq!(envelope.time_context.calendar_timezone, "America/New_York");
                let restored = merge_scoped_daily_note(
                    SemanticProfile::AndroidSleepV6,
                    &night,
                    &patch(SemanticProfile::AndroidSleepV6),
                    sections,
                )
                .unwrap();
                assert!(restored.contains("healthmd_daily_injection_v2: null"));
            }
            for zone in ["", "Not/AZone", "+04:00"] {
                assert!(
                    prepare_scoped_android_night_note(
                        profile,
                        json,
                        zone,
                        "---\nsteps: 42\n---\n",
                        "",
                        &[],
                        false
                    )
                    .is_err()
                );
            }
            assert!(
                prepare_scoped_daily_note(profile, json, "---\nsteps: 42\n---\n", "", &[], false)
                    .is_err()
            );
            for invalid in [
                json.replace("2026-03-08", "2026-02-30"),
                json.replacen('{', "{\"time_context\":{},", 1),
                json.replacen('{', "{\"schema_version\":4,", 1),
                json.replacen('{', "{\"date\":\"2026-03-08\",", 1),
                json.replace("schemaVersion\":5", "schemaVersion\":4"),
            ] {
                if invalid != json {
                    assert!(
                        prepare_scoped_android_night_note(
                            profile,
                            &invalid,
                            "America/New_York",
                            "---\n---\n",
                            "",
                            &[],
                            false
                        )
                        .is_err()
                    );
                }
            }
        }
    }

    #[test]
    fn scoped_note_projection_keeps_only_selected_properties_and_exact_record_text() {
        let profile = SemanticProfile::AndroidSleepV6;
        let original = patch(profile);
        let document = frontmatter_document(&original).unwrap();
        let block = property_blocks(&document.content)
            .unwrap()
            .into_iter()
            .find(|block| block.key == FrontmatterPropertyKey::String(CAPTURE_KEY.into()))
            .unwrap();
        let envelope: Envelope =
            serde_json::from_str(&scalar_property(&document.content[block.range]).unwrap())
                .unwrap();
        let bases = "---\nsteps: 42\nunselected: 99\nnotes: |\n  Selected multiline value\n---\n";
        for sections in [false, true] {
            let projected = prepare_scoped_daily_note(
                profile,
                &envelope.record_json,
                bases,
                "---\ntype: health-data\n---\n## Activity\nNew activity.\n",
                &["steps".into(), "notes".into()],
                sections,
            )
            .unwrap();
            assert!(!projected.contains("unselected:"));
            assert!(projected.contains("notes: |\n  Selected multiline value\n"));
            assert_eq!(projected.contains("## Activity"), sections);
            let merged =
                merge_scoped_daily_note(profile, "Personal introduction.\n", &projected, sections)
                    .unwrap();
            assert!(merged.contains("Personal introduction."));
            assert!(!merged.contains("type: health-data"));
        }
        for names in [
            vec![CAPTURE_KEY.into()],
            vec!["steps".into(), "steps".into()],
        ] {
            assert!(
                prepare_scoped_daily_note(profile, &envelope.record_json, bases, "", &names, false)
                    .is_err()
            );
        }
        let duplicate = "---\nsteps: 1\nsteps: 42\n---\n";
        assert!(
            prepare_scoped_daily_note(
                profile,
                &envelope.record_json,
                duplicate,
                "",
                &["steps".into()],
                false
            )
            .is_err()
        );
    }
    fn patch(profile: SemanticProfile) -> String {
        let context = if profile.is_wake_date() {
            json!({"calendar_timezone":"America/New_York","timestamp_timezone":"UTC",
            "sleep_day_attribution":"morning_ends","sleep_owner_day_rule":"session_end_date","sleep_interval_clipping":"none"})
        } else {
            json!({"calendar_timezone":"America/New_York","timestamp_timezone":"UTC"})
        };
        let mut record = json!({"schema":"healthmd.health_data","type":"health-data","schema_version":profile.public_schema_version(),
            "date":"2026-03-08","time_context":context,"activity":{"steps":42}});
        if profile.is_wake_date() {
            record["schema_profile"] = profile.public_profile_id().into();
        }
        let envelope =
            json!({"kind":"healthmd_daily_capture","version":1,"record_json":record.to_string()})
                .to_string();
        format!(
            "---\nsteps: 42\n{KIND_KEY}: daily_capture_v1\n{CAPTURE_KEY}: {}\n---\n## Activity\nNew activity.\n",
            serde_json::to_string(&envelope).unwrap()
        )
    }
    #[test]
    fn scoped_note_preserves_personal_yaml_and_body_for_known_inner_profiles() {
        let existing = "---\r\ntitle: Personal\r\nnotes: |\r\n  Keep my: multiline YAML\r\nsteps: 1\r\n---\r\nMy own preamble.\r\n## Thoughts\r\nMy journal.\r\n## Activity\r\nOld activity.\r\n";
        for profile in [
            SemanticProfile::AppleHealthDataV8,
            SemanticProfile::AppleHealthDataV11,
            SemanticProfile::AndroidSleepV6,
        ] {
            for sections in [false, true] {
                let merged =
                    merge_scoped_daily_note(profile, existing, &patch(profile), sections).unwrap();
                assert!(merged.contains("notes: |\r\n  Keep my: multiline YAML\r\n"));
                assert!(merged.contains("My own preamble.\r\n## Thoughts\r\nMy journal."));
                assert!(merged.contains("steps: 42\r\n"));
                assert_eq!(merged.contains("Old activity."), !sections);
                assert_eq!(merged.contains("New activity."), sections);
                assert!(merged.contains("healthmd_daily_injection_v1:"));
            }
        }
    }
    #[test]
    fn scoped_note_rejects_whole_export_roles_and_invalid_capture_authority() {
        let profile = SemanticProfile::AndroidSleepV6;
        let valid = patch(profile);
        for existing in [
            "---\nschema: healthmd.health_data\nschema_version: 4\n---\nExisting",
            "---\nschema: healthmd.health_rollup\n---\nExisting",
        ] {
            assert!(merge_scoped_daily_note(profile, existing, &valid, false).is_err());
        }
        for invalid in [
            valid.replace("daily_capture_v1", "daily_capture_v2"),
            valid.replace("android-sleep-v6", "apple-v11"),
            valid.replace("America/New_York", "Invalid/Timezone"),
            valid.replace("2026-03-08", "2026-02-30"),
            valid.replace("healthmd_daily_capture", "unknown_capture"),
        ] {
            assert!(merge_scoped_daily_note(profile, "Personal", &invalid, true).is_err());
        }
        assert!(
            merge_scoped_daily_note(
                SemanticProfile::AppleHealthDataV11,
                "Personal",
                &valid,
                false
            )
            .is_err()
        );
        assert!(
            merge_scoped_daily_note(SemanticProfile::AndroidFrozenV4, "Personal", &valid, false)
                .is_err()
        );
        assert!(
            merge_scoped_daily_note(
                profile,
                "---\n? [ambiguous, key]\n: value\n---\nPersonal",
                &valid,
                true
            )
            .is_err()
        );
    }
}
