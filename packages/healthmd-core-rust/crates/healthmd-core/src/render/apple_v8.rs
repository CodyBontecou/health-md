//! Apple `healthmd.health_data` v8 profile renderer.

use serde_json::Value;

use super::{
    ApiSettings, RenderDay, RenderError, RenderFormat, RenderSessionConfig,
    artifact_plan::ArtifactPlanBuilder, format,
};
use crate::semantic::SemanticResult;
#[cfg(test)]
use crate::semantic::{ExactNumber, SemanticValue};

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
        RenderFormat::Json => day.profile_documents.json_root.as_ref().map_or_else(
            || {
                format::foundation_pretty_json(&format::public_json_entries(
                    config,
                    day,
                    config.profile,
                )?)
            },
            format::foundation_ordered_json,
        ),
        RenderFormat::Csv => Ok(format::render_csv(config, day, config.profile)),
    }
}

pub(crate) fn add_rollups(
    builder: &mut ArtifactPlanBuilder,
    config: &RenderSessionConfig,
    semantic: &SemanticResult,
) -> Result<(), RenderError> {
    super::apple_rollup_v8::add_rollups(builder, config, semantic)
}

pub(crate) fn render_api_record(
    config: &RenderSessionConfig,
    day: &RenderDay,
) -> Result<Vec<u8>, RenderError> {
    format::foundation_compact_json(&format::public_json_entries(config, day, config.profile)?)
}

#[allow(clippy::too_many_lines)]
pub(crate) fn render_api_envelope(
    api: &ApiSettings,
    records: &[(String, Vec<u8>)],
) -> Result<Vec<u8>, RenderError> {
    let encode = |value: Value| format::foundation_compact_value_without_escaped_slashes(&value);
    let failures = api
        .failed_date_details
        .iter()
        .map(|failure| {
            let mut value = serde_json::Map::new();
            value.insert("date".to_owned(), Value::String(failure.timestamp.clone()));
            value.insert("reason".to_owned(), Value::String(failure.reason.clone()));
            if let Some(details) = failure
                .error_details
                .as_ref()
                .filter(|value| !value.trim().is_empty())
            {
                value.insert("errorDetails".to_owned(), Value::String(details.clone()));
            }
            encode(Value::Object(value))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let mut members = vec![
        (
            "schema".to_owned(),
            encode(Value::String("healthmd.api_export".to_owned()))?,
        ),
        (
            "schema_version".to_owned(),
            encode(Value::from(api.envelope_version))?,
        ),
        (
            "daily_record_schema".to_owned(),
            encode(Value::String("healthmd.health_data".to_owned()))?,
        ),
        (
            "daily_record_schema_version".to_owned(),
            encode(Value::from(8))?,
        ),
        (
            "exported_at".to_owned(),
            encode(Value::String(api.exported_at.clone()))?,
        ),
        (
            "source".to_owned(),
            encode(Value::String(api.source.clone()))?,
        ),
        (
            "date_range".to_owned(),
            encode(serde_json::json!({"start":api.date_range_start,"end":api.date_range_end}))?,
        ),
        (
            "record_count".to_owned(),
            encode(Value::from(
                u64::try_from(records.len()).map_err(|_| RenderError::LimitExceeded)?,
            ))?,
        ),
        (
            "records".to_owned(),
            compact_raw_array(records.iter().map(|record| record.1.as_slice())),
        ),
        (
            "failed_date_details".to_owned(),
            compact_raw_array(failures.iter().map(Vec::as_slice)),
        ),
    ];
    if api.envelope_version == 2 {
        let external = api
            .external_records
            .iter()
            .map(|record| encode(record.value.clone()))
            .collect::<Result<Vec<_>, _>>()?;
        members.extend([
            (
                "external_record_schema".to_owned(),
                encode(Value::String(
                    api.external_record_schema
                        .clone()
                        .ok_or(RenderError::InvalidConfig)?,
                ))?,
            ),
            (
                "external_record_schema_version".to_owned(),
                encode(Value::from(
                    api.external_record_schema_version
                        .ok_or(RenderError::InvalidConfig)?,
                ))?,
            ),
            (
                "external_record_count".to_owned(),
                encode(Value::from(external.len()))?,
            ),
            (
                "external_records".to_owned(),
                compact_raw_array(external.iter().map(Vec::as_slice)),
            ),
        ]);
    }
    members.sort_by(|left, right| {
        left.0
            .to_lowercase()
            .cmp(&right.0.to_lowercase())
            .then_with(|| left.0.cmp(&right.0))
    });
    let mut output = Vec::new();
    output.push(b'{');
    for (index, (key, value)) in members.into_iter().enumerate() {
        if index != 0 {
            output.push(b',');
        }
        output.extend_from_slice(
            &serde_json::to_vec(&key).map_err(|_| RenderError::SerializationFailed)?,
        );
        output.push(b':');
        output.extend_from_slice(&value);
    }
    output.push(b'}');
    Ok(output)
}

fn compact_raw_array<'a>(values: impl Iterator<Item = &'a [u8]>) -> Vec<u8> {
    let mut output = vec![b'['];
    for (index, value) in values.enumerate() {
        if index != 0 {
            output.push(b',');
        }
        output.extend_from_slice(value);
    }
    output.push(b']');
    output
}

#[cfg(test)]
fn semantic_value(value: &SemanticValue) -> Result<Value, RenderError> {
    match value {
        SemanticValue::Number { number, .. } => match number {
            ExactNumber::Binary64 { bits } => {
                let raw =
                    u64::from_str_radix(bits, 16).map_err(|_| RenderError::SerializationFailed)?;
                serde_json::Number::from_f64(f64::from_bits(raw))
                    .map(Value::Number)
                    .ok_or(RenderError::SerializationFailed)
            }
            ExactNumber::SignedInteger { decimal } => decimal
                .parse::<i64>()
                .map(Value::from)
                .map_err(|_| RenderError::SerializationFailed),
            ExactNumber::UnsignedInteger { decimal } => decimal
                .parse::<u64>()
                .map(Value::from)
                .map_err(|_| RenderError::SerializationFailed),
        },
        SemanticValue::Text { text } => Ok(Value::String(text.clone())),
        SemanticValue::Boolean { boolean } => Ok(Value::Bool(*boolean)),
        SemanticValue::TextList { items } => Ok(Value::Array(
            items.iter().cloned().map(Value::String).collect(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn semantic_numbers_retain_integer_and_binary_values() {
        let integer = SemanticValue::Number {
            number: ExactNumber::UnsignedInteger {
                decimal: "9007199254740993".to_owned(),
            },
            unit: crate::semantic::ExactUnit {
                id: "count".to_owned(),
            },
        };
        assert_eq!(
            semantic_value(&integer).unwrap().to_string(),
            "9007199254740993"
        );
        let negative_zero = SemanticValue::Number {
            number: ExactNumber::Binary64 {
                bits: "8000000000000000".to_owned(),
            },
            unit: crate::semantic::ExactUnit {
                id: "unitless".to_owned(),
            },
        };
        assert_eq!(
            semantic_value(&negative_zero)
                .unwrap()
                .as_f64()
                .unwrap()
                .to_bits(),
            1 << 63
        );
    }
}
