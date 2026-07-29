//! Frozen Android compatibility-v4 renderer. Historical quirks are isolated here.

use std::fmt::Write as _;

use serde_json::Value;

use super::{
    ApiSettings, OrderedJsonEntry, OrderedJsonValue, RenderDay, RenderError, RenderFormat,
    RenderSessionConfig, format,
};

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
                format::kotlin_pretty_json(&format::public_json_entries(
                    config,
                    day,
                    config.profile,
                )?)
            },
            format::kotlin_ordered_json,
        ),
        RenderFormat::Csv => Ok(format::render_csv(config, day, config.profile)),
    }
}

pub(crate) fn render_api_record(
    config: &RenderSessionConfig,
    day: &RenderDay,
) -> Result<Vec<u8>, RenderError> {
    if let Some(OrderedJsonValue::Object { entries: local }) = &day.profile_documents.json_root {
        let mut entries = local
            .iter()
            .filter(|entry| {
                !matches!(
                    entry.key.as_str(),
                    "schema" | "schema_version" | "time_context" | "unit_system" | "units"
                )
            })
            .cloned()
            .collect::<Vec<_>>();
        entries.extend([
            ordered_string("schema", "healthmd.health_data"),
            OrderedJsonEntry {
                key: "schema_version".to_owned(),
                value: OrderedJsonValue::Number {
                    decimal: "4".to_owned(),
                },
            },
            OrderedJsonEntry {
                key: "time_context".to_owned(),
                value: OrderedJsonValue::Object {
                    entries: vec![
                        ordered_string("calendar_timezone", &config.calendar_time_zone),
                        ordered_string("timestamp_timezone", "UTC"),
                    ],
                },
            },
            ordered_string("unit_system", "metric"),
            OrderedJsonEntry {
                key: "units".to_owned(),
                value: OrderedJsonValue::Object {
                    entries: {
                        let mut units = format::sorted_metrics(day)
                            .into_iter()
                            .filter(|metric| !metric.unit.is_empty())
                            .map(|metric| ordered_string(&metric.output_key, &metric.unit))
                            .collect::<Vec<_>>();
                        units.sort_by(|left, right| left.key.cmp(&right.key));
                        units
                    },
                },
            },
        ]);
        return format::kotlin_ordered_json(&OrderedJsonValue::Object { entries });
    }
    let local = format::public_json_entries(config, day, config.profile)?;
    let mut entries = local
        .into_iter()
        .filter(|(key, _)| {
            !matches!(
                key.as_str(),
                "schema" | "schema_version" | "time_context" | "unit_system" | "units"
            )
        })
        .collect::<Vec<_>>();
    entries.extend([
        ("schema".to_owned(), Value::String("healthmd.health_data".to_owned())),
        ("schema_version".to_owned(), Value::from(4)),
        (
            "time_context".to_owned(),
            serde_json::json!({"calendar_timezone":config.calendar_time_zone,"timestamp_timezone":"UTC"}),
        ),
        ("unit_system".to_owned(), Value::String("metric".to_owned())),
        (
            "units".to_owned(),
            Value::Object(
                format::sorted_metrics(day)
                    .into_iter()
                    .filter(|metric| !metric.unit.is_empty())
                    .map(|metric| (metric.output_key.clone(), Value::String(metric.unit.clone())))
                    .collect(),
            ),
        ),
    ]);
    format::kotlin_pretty_json(&entries)
}

fn ordered_string(key: &str, value: &str) -> OrderedJsonEntry {
    OrderedJsonEntry {
        key: key.to_owned(),
        value: OrderedJsonValue::String {
            value: value.to_owned(),
        },
    }
}

pub(crate) fn render_api_envelope(
    api: &ApiSettings,
    records: &[(String, Vec<u8>)],
) -> Result<Vec<u8>, RenderError> {
    if api.envelope_version != 1 {
        return Err(RenderError::UnsupportedOperation);
    }
    let scalar =
        |value: &str| serde_json::to_string(value).map_err(|_| RenderError::SerializationFailed);
    let date_range = format::kotlin_pretty_json(&[
        (
            "start".to_owned(),
            Value::String(api.date_range_start.clone()),
        ),
        ("end".to_owned(), Value::String(api.date_range_end.clone())),
    ])?;
    let mut output = String::from("{\n");
    for (key, value) in [
        ("schema", scalar("healthmd.api_export")?),
        ("schema_version", "1".to_owned()),
        ("daily_record_schema", scalar("healthmd.health_data")?),
        ("daily_record_schema_version", "4".to_owned()),
        ("exported_at", scalar(&api.exported_at)?),
        ("source", scalar("android")?),
    ] {
        writeln!(output, "    {}: {value},", scalar(key)?)
            .map_err(|_| RenderError::SerializationFailed)?;
    }
    write!(output, "    {}: ", scalar("date_range")?)
        .map_err(|_| RenderError::SerializationFailed)?;
    push_inline_nested(&mut output, &date_range, 4)?;
    output.push_str(",\n");
    writeln!(
        output,
        "    {}: {},",
        scalar("record_count")?,
        records.len()
    )
    .map_err(|_| RenderError::SerializationFailed)?;
    write!(output, "    {}: ", scalar("records")?).map_err(|_| RenderError::SerializationFailed)?;
    push_raw_array(
        &mut output,
        records.iter().map(|record| record.1.as_slice()),
    )?;
    output.push_str(",\n");
    write!(output, "    {}: ", scalar("failed_date_details")?)
        .map_err(|_| RenderError::SerializationFailed)?;
    let failures = api
        .failed_date_details
        .iter()
        .map(|failure| {
            let mut fields = vec![
                ("date".to_owned(), Value::String(failure.timestamp.clone())),
                ("reason".to_owned(), Value::String(failure.reason.clone())),
            ];
            if let Some(details) = failure
                .error_details
                .as_ref()
                .filter(|value| !value.trim().is_empty())
            {
                fields.push(("errorDetails".to_owned(), Value::String(details.clone())));
            }
            format::kotlin_pretty_json(&fields)
        })
        .collect::<Result<Vec<_>, _>>()?;
    push_raw_array(&mut output, failures.iter().map(Vec::as_slice))?;
    output.push_str("\n}");
    Ok(output.into_bytes())
}

fn push_inline_nested(
    output: &mut String,
    bytes: &[u8],
    continuation_indent: usize,
) -> Result<(), RenderError> {
    let value = std::str::from_utf8(bytes).map_err(|_| RenderError::SerializationFailed)?;
    let continuation = format!("\n{}", " ".repeat(continuation_indent));
    output.push_str(&value.replace('\n', &continuation));
    Ok(())
}

fn push_raw_array<'a>(
    output: &mut String,
    values: impl Iterator<Item = &'a [u8]>,
) -> Result<(), RenderError> {
    let values = values.collect::<Vec<_>>();
    if values.is_empty() {
        output.push_str("[]");
        return Ok(());
    }
    output.push_str("[\n");
    for (index, value) in values.iter().enumerate() {
        let value = std::str::from_utf8(value).map_err(|_| RenderError::SerializationFailed)?;
        for line in value.split('\n') {
            output.push_str("        ");
            output.push_str(line);
            output.push('\n');
        }
        if index + 1 != values.len() {
            let insert = output.len().saturating_sub(1);
            output.insert(insert, ',');
        }
    }
    output.push_str("    ]");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_v1_pins_frozen_daily_schema_v4() {
        let api = ApiSettings {
            enabled: true,
            envelope_version: 1,
            exported_at: "2026-07-25T00:00:00Z".to_owned(),
            source: "android".to_owned(),
            date_range_start: "2026-07-25".to_owned(),
            date_range_end: "2026-07-25".to_owned(),
            failed_date_details: Vec::new(),
            external_record_schema: None,
            external_record_schema_version: None,
            external_records: Vec::new(),
            max_days_per_batch: 7,
            max_encoded_bytes: 8 * 1024 * 1024,
        };
        let output = render_api_envelope(
            &api,
            &[(
                "2026-07-25".to_owned(),
                br#"{"date":"2026-07-25"}"#.to_vec(),
            )],
        )
        .unwrap();
        let text = String::from_utf8(output).unwrap();
        assert!(text.contains("\"daily_record_schema_version\": 4"));
        assert!(!text.contains("android-analytical-v5"));
    }
}
