//! Successor-only sleep profiles. Historical modules are never relabeled.

use std::collections::BTreeMap;

use serde_json::{Value, json};

use super::{
    ApiSettings, OrderedJsonValue, RenderDay, RenderError, RenderFormat, RenderProfileCsvRow,
    RenderSessionConfig, format,
};
use crate::{
    semantic::SemanticResult,
    sleep::{SleepSource, read_public_sleep_context},
};

mod api_record;
pub(super) mod public_numbers;

pub(crate) fn render_day(
    config: &RenderSessionConfig,
    day: &RenderDay,
    output: RenderFormat,
) -> Result<Vec<u8>, RenderError> {
    match output {
        RenderFormat::Markdown => format::render_markdown(config, day),
        RenderFormat::ObsidianBases => {
            format::render_frontmatter(config, day, format::FrontmatterSurface::Bases)
        }
        RenderFormat::Json => {
            if let Some(root) = &day.profile_documents.json_root {
                if config.profile.is_apple() {
                    format::foundation_ordered_json(root)
                } else {
                    format::kotlin_ordered_json(root)
                }
            } else {
                let entries = format::public_json_entries(config, day, config.profile)?;
                if config.profile.is_apple() {
                    format::foundation_pretty_json(&entries)
                } else {
                    format::kotlin_pretty_json(&entries)
                }
            }
        }
        RenderFormat::Csv => Ok(format::render_csv(config, day, config.profile)),
    }
}

pub(crate) fn validate_native_json(
    config: &RenderSessionConfig,
    root: &OrderedJsonValue,
) -> Result<(), RenderError> {
    let bytes = format::kotlin_ordered_json(root)?;
    let value: Value =
        serde_json::from_slice(&bytes).map_err(|_| RenderError::PresentationMismatch)?;
    validate_document_identity(config, &value)
}

fn validate_document_identity(
    config: &RenderSessionConfig,
    value: &Value,
) -> Result<(), RenderError> {
    if value["schema"] != "healthmd.health_data"
        || value["schema_version"] != config.profile.public_schema_version()
        || value["schema_profile"] != config.profile.public_profile_id()
    {
        return Err(RenderError::PresentationMismatch);
    }
    let source = if config.profile.is_apple() {
        SleepSource::Apple
    } else {
        SleepSource::Android
    };
    let context = read_public_sleep_context(
        source,
        config.profile.public_schema_version(),
        value["schema_profile"].as_str(),
        value.get("time_context"),
    )
    .map_err(|_| RenderError::PresentationMismatch)?;
    if context.calendar_timezone.as_deref() != Some(config.calendar_time_zone.as_str()) {
        return Err(RenderError::PresentationMismatch);
    }
    if !config.profile.is_apple()
        && (value
            .get("schemaProfile")
            .is_some_and(|alias| alias != config.profile.public_profile_id())
            || value
                .get("schemaVersion")
                .is_some_and(|alias| alias != config.profile.public_schema_version())
            || value.get("sleep_core_hours").is_some()
            || value.get("sleep").is_some_and(|sleep| {
                sleep.get("coreSleep").is_some() || sleep.get("coreSleepFormatted").is_some()
            }))
    {
        return Err(RenderError::PresentationMismatch);
    }
    Ok(())
}

pub(crate) fn validate_native_csv(
    config: &RenderSessionConfig,
    rows: &[RenderProfileCsvRow],
) -> Result<(), RenderError> {
    let mut metadata = BTreeMap::new();
    for row in rows {
        if row.cells.len() == 6
            && row.cells[1] == "Metadata"
            && metadata
                .insert(row.cells[2].as_str(), row.cells[3].as_str())
                .is_some()
        {
            return Err(RenderError::PresentationMismatch);
        }
    }
    let required = |key| {
        metadata
            .get(key)
            .copied()
            .ok_or(RenderError::PresentationMismatch)
    };
    let version = required("schema_version")?
        .parse::<u32>()
        .map_err(|_| RenderError::PresentationMismatch)?;
    let value = json!({
        "schema":required("schema")?, "schema_version":version, "schema_profile":required("schema_profile")?,
        "time_context":{
            "calendar_timezone":required("time_context.calendar_timezone")?,
            "timestamp_timezone":required("time_context.timestamp_timezone")?,
            "sleep_day_attribution":required("time_context.sleep_day_attribution")?,
            "sleep_owner_day_rule":required("time_context.sleep_owner_day_rule")?,
            "sleep_interval_clipping":required("time_context.sleep_interval_clipping")?
        }
    });
    validate_document_identity(config, &value)
}

pub(crate) fn render_api_record(
    config: &RenderSessionConfig,
    day: &RenderDay,
    semantic: &SemanticResult,
) -> Result<Vec<u8>, RenderError> {
    api_record::render(config, day, semantic)
}

pub(crate) fn render_api_envelope(
    config: &RenderSessionConfig,
    api: &ApiSettings,
    records: &[(String, Vec<u8>)],
) -> Result<Vec<u8>, RenderError> {
    let records = records
        .iter()
        .map(|record| {
            serde_json::from_slice::<Value>(&record.1).map_err(|_| RenderError::SerializationFailed)
        })
        .collect::<Result<Vec<_>, _>>()?;
    let failures = api
        .failed_date_details
        .iter()
        .map(|failure| {
            let mut value = json!({"date":failure.timestamp, "reason":failure.reason});
            if let Some(details) = failure
                .error_details
                .as_ref()
                .filter(|details| !details.trim().is_empty())
            {
                value["errorDetails"] = Value::String(details.clone());
            }
            value
        })
        .collect::<Vec<_>>();
    let mut envelope = json!({
        "schema":"healthmd.api_export", "schema_version":api.envelope_version,
        "daily_record_schema":"healthmd.health_data", "daily_record_schema_version":config.profile.public_schema_version(),
        "daily_record_schema_profile":config.profile.public_profile_id(),
        "daily_record_time_context":{
            "calendar_timezone":config.calendar_time_zone, "timestamp_timezone":"UTC",
            "sleep_day_attribution":"morning_ends", "sleep_owner_day_rule":"session_end_date", "sleep_interval_clipping":"none"
        },
        "exported_at":api.exported_at, "source":api.source,
        "date_range":{"start":api.date_range_start, "end":api.date_range_end},
        "record_count":records.len(), "records":records, "failed_date_details":failures
    });
    if api.envelope_version == 2 {
        envelope["external_record_schema"] = Value::String(
            api.external_record_schema
                .clone()
                .ok_or(RenderError::InvalidConfig)?,
        );
        envelope["external_record_schema_version"] = Value::from(
            api.external_record_schema_version
                .ok_or(RenderError::InvalidConfig)?,
        );
        envelope["external_record_count"] = Value::from(api.external_records.len());
        envelope["external_records"] = Value::Array(
            api.external_records
                .iter()
                .map(|record| record.value.clone())
                .collect(),
        );
    }
    if config.profile.is_apple() {
        format::foundation_compact_value_without_escaped_slashes(&envelope)
    } else {
        format::kotlin_pretty_json(
            &envelope
                .as_object()
                .ok_or(RenderError::SerializationFailed)?
                .iter()
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect::<Vec<_>>(),
        )
    }
}
