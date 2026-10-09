//! Successor merge authority is checked independently of the frozen historical merge policies.

use serde_json::{Map, Value};

use super::{
    FrontmatterDocument, FrontmatterPropertyKey, PhysicalLine, frontmatter_document,
    is_yaml_trivia, merge_with_parser, property_blocks, property_header, validate,
};
use crate::{
    render::RenderError,
    semantic::SemanticProfile,
    sleep::{PublicSleepContext, SleepSource, read_public_sleep_context},
};

mod document;

const VISIBLE_ATTRIBUTION: &str =
    "> Health.md sleep attribution: `morning_ends` (Morning ends); whole sessions by wake-up date.";
const CONTEXT_KEYS: [&str; 5] = [
    "calendar_timezone",
    "timestamp_timezone",
    "sleep_day_attribution",
    "sleep_owner_day_rule",
    "sleep_interval_clipping",
];

#[derive(Eq, PartialEq)]
struct MergeAuthority {
    context: PublicSleepContext,
    has_frontmatter: bool,
}

pub(super) fn merge(
    profile: SemanticProfile,
    existing: &str,
    generated: &str,
    preserve_preamble: bool,
) -> Result<String, RenderError> {
    let incoming = authority(profile, generated)?;
    if existing.trim().is_empty() {
        return Ok(generated.to_owned());
    }
    // A headerless old export, a draft promise or a surface change is not migration authority.
    // Changing Include Metadata on an existing export requires an explicit overwrite.
    if authority(profile, existing)? != incoming {
        return Err(RenderError::PresentationMismatch);
    }
    // Reuse the physically safe property-block splice, not Android's historical flat YAML map.
    // The new Android profile retains user preamble; Apple retains its explicit injection choice.
    let generated = document::preserve_filled_placeholders(generated)?;
    let output = merge_with_parser(
        existing,
        &generated,
        preserve_preamble || !profile.is_apple(),
        document::parse,
    )?;
    validate(&output, "")?;
    if authority(profile, &output)? != incoming {
        return Err(RenderError::PresentationMismatch);
    }
    Ok(output)
}

fn authority(profile: SemanticProfile, text: &str) -> Result<MergeAuthority, RenderError> {
    if let Some(document) = frontmatter_document(text) {
        frontmatter_authority(profile, &document)
    } else {
        visible_authority(profile, text)
    }
}

fn frontmatter_authority(
    profile: SemanticProfile,
    document: &FrontmatterDocument,
) -> Result<MergeAuthority, RenderError> {
    let blocks = property_blocks(&document.content).ok_or(RenderError::PresentationMismatch)?;
    let mut identity = Map::new();
    for block in blocks {
        let FrontmatterPropertyKey::String(key) = &block.key else {
            continue;
        };
        if CONTEXT_KEYS.contains(&key.as_str())
            || key.starts_with("time_context.")
            || (!profile.is_apple() && key == "sleep_core_hours")
        {
            return Err(RenderError::PresentationMismatch);
        }
        if !matches!(
            key.as_str(),
            "schema" | "schema_version" | "schema_profile" | "time_context"
        ) {
            // Historical aliases must not survive next to a contradictory successor identity.
            if matches!(
                key.as_str(),
                "healthmd_schema_profile" | "schemaProfile" | "schemaVersion"
            ) {
                validate_alias(profile, key, &document.content[block.range.clone()])?;
            }
            continue;
        }
        let lines = &document.content[block.range];
        let value = if key == "time_context" {
            context_mapping(lines)?
        } else if key == "schema_version" {
            let scalar = scalar_property(lines)?;
            Value::from(
                scalar
                    .parse::<u32>()
                    .map_err(|_| RenderError::PresentationMismatch)?,
            )
        } else {
            Value::String(scalar_property(lines)?)
        };
        if identity.insert(key.clone(), value).is_some() {
            return Err(RenderError::PresentationMismatch);
        }
    }
    if identity.len() != 4
        || identity.get("schema").and_then(Value::as_str) != Some("healthmd.health_data")
        || identity.get("schema_version").and_then(Value::as_u64)
            != Some(u64::from(profile.public_schema_version()))
        || identity.get("schema_profile").and_then(Value::as_str)
            != Some(profile.public_profile_id())
    {
        return Err(RenderError::PresentationMismatch);
    }
    let context = validated_context(profile, identity.get("time_context"))?;
    // A copied visible declaration cannot override or contradict frontmatter authority.
    if document
        .suffix
        .iter()
        .any(|line| line.content.starts_with("> Health.md sleep attribution:"))
    {
        return Err(RenderError::PresentationMismatch);
    }
    Ok(MergeAuthority {
        context,
        has_frontmatter: true,
    })
}

fn validate_alias(
    profile: SemanticProfile,
    key: &str,
    lines: &[PhysicalLine],
) -> Result<(), RenderError> {
    let value = scalar_property(lines)?;
    let valid = if key == "schemaVersion" {
        value.parse::<u32>().ok() == Some(profile.public_schema_version())
    } else {
        value == profile.public_profile_id()
    };
    if valid {
        Ok(())
    } else {
        Err(RenderError::PresentationMismatch)
    }
}

fn context_mapping(lines: &[PhysicalLine]) -> Result<Value, RenderError> {
    let header = property_header(&lines[0].content).ok_or(RenderError::PresentationMismatch)?;
    if !header.value.trim().is_empty() && !header.value.trim().starts_with('#') {
        return Err(RenderError::PresentationMismatch);
    }
    let mut context = Map::new();
    for line in &lines[1..] {
        if is_yaml_trivia(&line.content) {
            continue;
        }
        let property = line
            .content
            .strip_prefix("  ")
            .ok_or(RenderError::PresentationMismatch)?;
        let header = property_header(property).ok_or(RenderError::PresentationMismatch)?;
        let FrontmatterPropertyKey::String(key) = header.key else {
            return Err(RenderError::PresentationMismatch);
        };
        if !CONTEXT_KEYS.contains(&key.as_str())
            || context
                .insert(key, Value::String(scalar(&header.value)?))
                .is_some()
        {
            return Err(RenderError::PresentationMismatch);
        }
    }
    if context.len() != CONTEXT_KEYS.len() {
        return Err(RenderError::PresentationMismatch);
    }
    Ok(Value::Object(context))
}

fn scalar_property(lines: &[PhysicalLine]) -> Result<String, RenderError> {
    if lines[1..].iter().any(|line| !is_yaml_trivia(&line.content)) {
        return Err(RenderError::PresentationMismatch);
    }
    let header = property_header(&lines[0].content).ok_or(RenderError::PresentationMismatch)?;
    scalar(&header.value)
}

fn scalar(value: &str) -> Result<String, RenderError> {
    let value = value.trim();
    if value.starts_with('"') {
        return serde_json::from_str::<String>(value)
            .map_err(|_| RenderError::PresentationMismatch);
    }
    if let Some(value) = value
        .strip_prefix('\'')
        .and_then(|value| value.strip_suffix('\''))
    {
        return Ok(value.replace("''", "'"));
    }
    let value = value
        .split_once(" #")
        .map_or(value, |(scalar, _)| scalar)
        .trim_end();
    if value.is_empty()
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_./+-".contains(&byte))
    {
        return Err(RenderError::PresentationMismatch);
    }
    Ok(value.to_owned())
}

fn visible_authority(profile: SemanticProfile, text: &str) -> Result<MergeAuthority, RenderError> {
    let lines = text.lines().collect::<Vec<_>>();
    if lines.first().copied() != Some(VISIBLE_ATTRIBUTION) {
        return Err(RenderError::PresentationMismatch);
    }
    let declaration = lines.get(1).ok_or(RenderError::PresentationMismatch)?;
    let parts = declaration.split('`').collect::<Vec<_>>();
    if parts.len() != 11 {
        return Err(RenderError::PresentationMismatch);
    }
    let expected = format!(
        "> Profile: `{}`; calendar timezone: `{}`; timestamp timezone: `{}`; owner rule: `session_end_date`; clipping: `none`.",
        profile.public_profile_id(),
        parts[3],
        parts[5],
    );
    if **declaration != expected {
        return Err(RenderError::PresentationMismatch);
    }
    let preamble = document::parse(text).preamble;
    if preamble
        .lines()
        .filter(|line| line.starts_with("> Health.md sleep attribution:"))
        .count()
        != 1
        || preamble
            .lines()
            .filter(|line| line.starts_with("> Profile:"))
            .count()
            != 1
    {
        return Err(RenderError::PresentationMismatch);
    }
    let context = serde_json::json!({
        "calendar_timezone":parts[3], "timestamp_timezone":parts[5],
        "sleep_day_attribution":"morning_ends", "sleep_owner_day_rule":"session_end_date",
        "sleep_interval_clipping":"none"
    });
    Ok(MergeAuthority {
        context: validated_context(profile, Some(&context))?,
        has_frontmatter: false,
    })
}

fn validated_context(
    profile: SemanticProfile,
    value: Option<&Value>,
) -> Result<PublicSleepContext, RenderError> {
    read_public_sleep_context(
        if profile.is_apple() {
            SleepSource::Apple
        } else {
            SleepSource::Android
        },
        profile.public_schema_version(),
        Some(profile.public_profile_id()),
        value,
    )
    .map_err(|_| RenderError::PresentationMismatch)
}
