//! Exact low-level JSON, CSV, YAML, Markdown, and merge primitives shared by profile modules.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write as _;

use serde_json::Value;

use super::{
    OrderedJsonValue, RenderCsvRow, RenderDailyNote, RenderDay, RenderError, RenderIndividualEntry,
    RenderMetric, RenderSessionConfig,
};
use crate::semantic::SemanticProfile;

pub(crate) fn sorted_metrics(day: &RenderDay) -> Vec<&RenderMetric> {
    let mut metrics = day.metrics.iter().collect::<Vec<_>>();
    metrics.sort_by(|left, right| {
        left.ordinal
            .cmp(&right.ordinal)
            .then(left.output_key.cmp(&right.output_key))
    });
    metrics
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum FrontmatterSurface {
    Markdown,
    Bases,
}

#[allow(clippy::too_many_lines)]
pub(crate) fn render_frontmatter(
    config: &RenderSessionConfig,
    day: &RenderDay,
    surface: FrontmatterSurface,
) -> Result<Vec<u8>, RenderError> {
    let disabled = config
        .disabled_frontmatter_keys
        .iter()
        .collect::<BTreeSet<_>>();
    let mut output = String::from("---\n");
    let apple = config.profile == SemanticProfile::AppleHealthDataV8;
    if apple {
        output.push_str("schema: healthmd.health_data\nschema_version: 8\n");
        output.push_str("time_context:\n  calendar_timezone: ");
        output.push_str(&config.calendar_time_zone);
        output.push_str("\n  timestamp_timezone: UTC\n");
    } else if config.profile == SemanticProfile::AndroidAnalyticalV5 {
        output.push_str("healthmd_schema_profile: android-analytical-v5\n");
    }
    if config.frontmatter.include_date {
        writeln!(
            output,
            "{}: {}",
            config.frontmatter.date_key, day.owner_date
        )
        .map_err(|_| RenderError::SerializationFailed)?;
    }
    if config.frontmatter.include_type {
        writeln!(
            output,
            "{}: {}",
            config.frontmatter.type_key, config.frontmatter.type_value
        )
        .map_err(|_| RenderError::SerializationFailed)?;
    }
    let diagnostic_keys = [
        "raw_capture_status",
        "raw_record_count",
        "raw_query_failure_count",
        "raw_integrity_warning_count",
        "raw_record_schema",
        "raw_record_schema_version",
    ];
    for (key, value) in &config.custom_frontmatter {
        if !apple || !diagnostic_keys.contains(&key.as_str()) {
            writeln!(output, "{key}: {value}").map_err(|_| RenderError::SerializationFailed)?;
        }
    }
    for key in &config.placeholder_frontmatter {
        if !config.custom_frontmatter.contains_key(key)
            && (!apple || !diagnostic_keys.contains(&key.as_str()))
        {
            writeln!(output, "{key}: ").map_err(|_| RenderError::SerializationFailed)?;
        }
    }
    if surface == FrontmatterSurface::Bases {
        let mut fields = day.bases_frontmatter_fields.iter().collect::<Vec<_>>();
        fields.sort_by_key(|field| (field.ordinal, field.key.clone()));
        for field in fields {
            writeln!(output, "{}: {}", field.key, field.value)
                .map_err(|_| RenderError::SerializationFailed)?;
        }
    }
    if apple {
        let default_diagnostics = super::RenderArchiveDiagnostics {
            capture_status: config.raw_capture_status.clone(),
            record_count: 0,
            query_failure_count: 0,
            integrity_warning_count: 0,
            record_schema: None,
            record_schema_version: None,
        };
        let diagnostics = day
            .archive_diagnostics
            .as_ref()
            .unwrap_or(&default_diagnostics);
        writeln!(output, "raw_capture_status: {}", diagnostics.capture_status)
            .map_err(|_| RenderError::SerializationFailed)?;
        writeln!(output, "raw_record_count: {}", diagnostics.record_count)
            .map_err(|_| RenderError::SerializationFailed)?;
        writeln!(
            output,
            "raw_query_failure_count: {}",
            diagnostics.query_failure_count
        )
        .map_err(|_| RenderError::SerializationFailed)?;
        writeln!(
            output,
            "raw_integrity_warning_count: {}",
            diagnostics.integrity_warning_count
        )
        .map_err(|_| RenderError::SerializationFailed)?;
        if let (Some(schema), Some(version)) = (
            &diagnostics.record_schema,
            diagnostics.record_schema_version,
        ) {
            writeln!(output, "raw_record_schema: {schema}")
                .map_err(|_| RenderError::SerializationFailed)?;
            writeln!(output, "raw_record_schema_version: {version}")
                .map_err(|_| RenderError::SerializationFailed)?;
        }
    }

    let mut metrics = sorted_metrics(day);
    if apple {
        metrics.sort_by(|left, right| left.output_key.cmp(&right.output_key));
    }
    for metric in &metrics {
        if !disabled.contains(&metric.output_key) && !disabled.contains(&metric.frontmatter_key) {
            if metric.display_value.contains('\n') {
                writeln!(output, "{}:", metric.frontmatter_key)
                    .map_err(|_| RenderError::SerializationFailed)?;
                for line in metric.display_value.split('\n') {
                    writeln!(output, "{line}").map_err(|_| RenderError::SerializationFailed)?;
                }
            } else {
                writeln!(
                    output,
                    "{}: {}",
                    metric.frontmatter_key, metric.display_value
                )
                .map_err(|_| RenderError::SerializationFailed)?;
            }
        }
    }
    if apple {
        let mut units = vec![
            ("raw_record_count".to_owned(), "records".to_owned()),
            ("raw_query_failure_count".to_owned(), "queries".to_owned()),
            (
                "raw_integrity_warning_count".to_owned(),
                "warnings".to_owned(),
            ),
        ];
        units.extend(
            metrics
                .iter()
                .filter(|metric| {
                    !metric.unit.is_empty()
                        && !disabled.contains(&metric.output_key)
                        && !disabled.contains(&metric.frontmatter_key)
                })
                .map(|metric| (metric.frontmatter_key.clone(), metric.unit.clone())),
        );
        units.sort();
        units.dedup_by(|left, right| left.0 == right.0);
        if !units.is_empty() {
            output.push_str("units:\n");
            for (key, unit) in units {
                writeln!(output, "  {key}: {unit}")
                    .map_err(|_| RenderError::SerializationFailed)?;
            }
        }
    }
    if surface == FrontmatterSurface::Bases {
        let mut blocks = day.bases_frontmatter_blocks.iter().collect::<Vec<_>>();
        blocks.sort_by_key(|block| (block.ordinal, block.key.clone()));
        for block in blocks {
            writeln!(output, "{}:", block.key).map_err(|_| RenderError::SerializationFailed)?;
            for line in &block.lines {
                writeln!(output, "{line}").map_err(|_| RenderError::SerializationFailed)?;
            }
        }
    }
    output.push_str("---\n");
    if surface == FrontmatterSurface::Markdown {
        output.push('\n');
    }
    Ok(output.into_bytes())
}

pub(crate) fn render_markdown(
    config: &RenderSessionConfig,
    day: &RenderDay,
) -> Result<Vec<u8>, RenderError> {
    let mut frontmatter = if config.include_metadata {
        String::from_utf8(render_frontmatter(
            config,
            day,
            FrontmatterSurface::Markdown,
        )?)
        .map_err(|_| RenderError::SerializationFailed)?
    } else {
        String::new()
    };
    if let Some(document) = &day.profile_documents.markdown_body {
        append_line_document(&mut frontmatter, document);
        return Ok(frontmatter.into_bytes());
    }
    let standard = standard_markdown(config, day)?;
    let body = if let Some(template) = &config.markdown.custom_template {
        render_custom_template(template, day, &standard)?
    } else {
        standard
    };
    frontmatter.push_str(&body);
    Ok(frontmatter.into_bytes())
}

fn standard_markdown(config: &RenderSessionConfig, day: &RenderDay) -> Result<String, RenderError> {
    let mut output = format!("# Health Data — {}\n", day.title);
    if config.markdown.include_summary && !day.metrics.is_empty() {
        writeln!(output, "\n{} metrics recorded.", day.metrics.len())
            .map_err(|_| RenderError::SerializationFailed)?;
    }
    let metrics = sorted_metrics(day);
    if config.group_by_category {
        let mut categories: Vec<(u32, String, String, Vec<&RenderMetric>)> = Vec::new();
        for metric in metrics {
            if let Some(category) = categories
                .iter_mut()
                .find(|category| category.1 == metric.category_id)
            {
                category.3.push(metric);
            } else {
                categories.push((
                    metric.ordinal,
                    metric.category_id.clone(),
                    metric.category_label.clone(),
                    vec![metric],
                ));
            }
        }
        categories.sort_by(|left, right| left.0.cmp(&right.0).then(left.1.cmp(&right.1)));
        for (_, category_id, label, values) in categories {
            let emoji = if config.markdown.use_emoji {
                category_emoji(&category_id)
            } else {
                ""
            };
            writeln!(
                output,
                "\n{} {}{}",
                "#".repeat(usize::from(config.markdown.section_header_level)),
                emoji,
                label
            )
            .map_err(|_| RenderError::SerializationFailed)?;
            for metric in values {
                append_metric_line(&mut output, config, metric)?;
            }
        }
    } else {
        writeln!(
            output,
            "\n{} Metrics",
            "#".repeat(usize::from(config.markdown.section_header_level))
        )
        .map_err(|_| RenderError::SerializationFailed)?;
        for metric in metrics {
            append_metric_line(&mut output, config, metric)?;
        }
    }
    let mut blocks = day
        .extensions
        .iter()
        .flat_map(|extension| extension.markdown_blocks.iter())
        .collect::<Vec<_>>();
    blocks.sort_by_key(|block| (block.ordinal, block.heading.clone()));
    for block in blocks {
        writeln!(
            output,
            "\n{} {}",
            "#".repeat(usize::from(config.markdown.section_header_level)),
            block.heading
        )
        .map_err(|_| RenderError::SerializationFailed)?;
        for line in &block.lines {
            writeln!(output, "{line}").map_err(|_| RenderError::SerializationFailed)?;
        }
    }
    Ok(output)
}

fn append_metric_line(
    output: &mut String,
    config: &RenderSessionConfig,
    metric: &RenderMetric,
) -> Result<(), RenderError> {
    write!(
        output,
        "{} **{}:** {}",
        config.markdown.bullet, metric.label, metric.display_value
    )
    .map_err(|_| RenderError::SerializationFailed)?;
    if !metric.unit.is_empty() {
        write!(output, " {}", metric.unit).map_err(|_| RenderError::SerializationFailed)?;
    }
    output.push('\n');
    Ok(())
}

fn render_custom_template(
    template: &str,
    day: &RenderDay,
    all_metrics: &str,
) -> Result<String, RenderError> {
    if template.len() > 64 * 1024 {
        return Err(RenderError::InvalidConfig);
    }
    let mut rendered = template.to_owned();
    let categories = sorted_metrics(day)
        .into_iter()
        .map(|metric| metric.category_id.clone())
        .collect::<BTreeSet<_>>();
    let known = [
        "sleep",
        "activity",
        "heart",
        "vitals",
        "body",
        "nutrition",
        "mindfulness",
        "mobility",
        "hearing",
        "workouts",
        "reproductive_health",
        "cycling",
        "vitamins",
        "minerals",
        "symptoms",
        "medications",
        "other",
    ];
    for category in known {
        rendered = replace_conditional(&rendered, category, categories.contains(category))?;
    }
    rendered = rendered
        .replace("{{date}}", &day.owner_date)
        .replace("{{summary}}", "")
        .replace("{{metrics}}", all_metrics);
    for category in categories {
        let lines = sorted_metrics(day)
            .into_iter()
            .filter(|metric| metric.category_id == category)
            .map(|metric| {
                format!(
                    "- **{}:** {} {}",
                    metric.label, metric.display_value, metric.unit
                )
                .trim_end()
                .to_owned()
            })
            .collect::<Vec<_>>()
            .join("\n");
        rendered = rendered.replace(&format!("{{{{{category}_metrics}}}}"), &lines);
    }
    Ok(rendered)
}

fn replace_conditional(input: &str, section: &str, include: bool) -> Result<String, RenderError> {
    let start = format!("{{{{#{section}}}}}");
    let end = format!("{{{{/{section}}}}}");
    let mut result = input.to_owned();
    loop {
        let Some(start_index) = result.find(&start) else {
            break;
        };
        let content_start = start_index + start.len();
        let Some(relative_end) = result[content_start..].find(&end) else {
            return Err(RenderError::InvalidConfig);
        };
        let end_index = content_start + relative_end;
        let replacement = if include {
            result[content_start..end_index].to_owned()
        } else {
            String::new()
        };
        result.replace_range(start_index..end_index + end.len(), &replacement);
    }
    Ok(result)
}

#[allow(clippy::too_many_lines)]
pub(crate) fn render_csv(
    config: &RenderSessionConfig,
    day: &RenderDay,
    profile: SemanticProfile,
) -> Vec<u8> {
    let mut output = String::from("Date,Category,Metric,Value,Unit,Timestamp\n");
    if let Some(rows) = &day.profile_documents.csv_rows {
        for row in rows {
            output.push_str(
                &row.cells
                    .iter()
                    .map(|cell| csv_field(cell))
                    .collect::<Vec<_>>()
                    .join(","),
            );
            output.push('\n');
        }
        return output.into_bytes();
    }
    if profile == SemanticProfile::AppleHealthDataV8 {
        for row in [
            [
                day.owner_date.as_str(),
                "Metadata",
                "schema",
                "healthmd.health_data",
                "",
                "",
            ],
            [
                day.owner_date.as_str(),
                "Metadata",
                "schema_version",
                "8",
                "",
                "",
            ],
            [
                day.owner_date.as_str(),
                "Metadata",
                "unit_system",
                "metric",
                "",
                "",
            ],
            [
                day.owner_date.as_str(),
                "Metadata",
                "time_context.calendar_timezone",
                config.calendar_time_zone.as_str(),
                "",
                "",
            ],
            [
                day.owner_date.as_str(),
                "Metadata",
                "time_context.timestamp_timezone",
                "UTC",
                "",
                "",
            ],
            [
                day.owner_date.as_str(),
                "Raw HealthKit",
                "Raw Capture Status",
                config.raw_capture_status.as_str(),
                "status",
                "",
            ],
        ] {
            append_csv_row(&mut output, &row);
        }
    } else if profile == SemanticProfile::AndroidAnalyticalV5 {
        append_csv_row(
            &mut output,
            &[
                &day.owner_date,
                "Metadata",
                "Schema Profile",
                "android-analytical-v5",
                "",
                "",
            ],
        );
    }
    for metric in sorted_metrics(day) {
        append_csv_row(
            &mut output,
            &[
                &day.owner_date,
                &metric.category_label,
                &metric.label,
                &metric.display_value,
                &metric.unit,
                metric.timestamp.as_deref().unwrap_or(""),
            ],
        );
    }
    let mut rows = day
        .extensions
        .iter()
        .flat_map(|extension| extension.csv_rows.iter())
        .collect::<Vec<&RenderCsvRow>>();
    rows.sort_by_key(|row| (row.ordinal, row.category.clone(), row.metric.clone()));
    for row in rows {
        append_csv_row(
            &mut output,
            &[
                &row.date,
                &row.category,
                &row.metric,
                &row.value,
                &row.unit,
                &row.timestamp,
            ],
        );
    }
    output.into_bytes()
}

fn append_csv_row(output: &mut String, fields: &[&str]) {
    for (index, field) in fields.iter().enumerate() {
        if index != 0 {
            output.push(',');
        }
        output.push_str(&csv_field(field));
    }
    output.push('\n');
}

fn append_line_document(output: &mut String, document: &super::RenderLineDocument) {
    output.push_str(&document.lines.join("\n"));
    if document.trailing_newline {
        output.push('\n');
    }
}

fn csv_field(value: &str) -> String {
    if value
        .bytes()
        .any(|byte| matches!(byte, b',' | b'"' | b'\r' | b'\n'))
    {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_owned()
    }
}

pub(crate) fn public_json_entries(
    config: &RenderSessionConfig,
    day: &RenderDay,
    profile: SemanticProfile,
) -> Result<Vec<(String, Value)>, RenderError> {
    let mut public_fields: Vec<(u32, String, Value)> = Vec::new();
    for metric in sorted_metrics(day) {
        let Some((top_level, nested_path)) = metric.json_path.split_first() else {
            return Err(RenderError::PresentationMismatch);
        };
        if let Some((_, _, value)) = public_fields
            .iter_mut()
            .find(|(_, key, _)| key == top_level)
        {
            if nested_path.is_empty() {
                return Err(RenderError::PresentationMismatch);
            }
            let Value::Object(object) = value else {
                return Err(RenderError::PresentationMismatch);
            };
            insert_json_value(object, nested_path, metric.public_value.clone())?;
        } else {
            let value = if nested_path.is_empty() {
                metric.public_value.clone()
            } else {
                let mut object = serde_json::Map::new();
                insert_json_value(&mut object, nested_path, metric.public_value.clone())?;
                Value::Object(object)
            };
            public_fields.push((metric.ordinal, top_level.clone(), value));
        }
    }
    public_fields.sort_by(|left, right| left.0.cmp(&right.0).then(left.1.cmp(&right.1)));
    let mut entries = Vec::new();
    match profile {
        SemanticProfile::AppleHealthDataV8 => {
            entries.push((
                "schema".to_owned(),
                Value::String("healthmd.health_data".to_owned()),
            ));
            entries.push(("schema_version".to_owned(), Value::from(8)));
            entries.push(("date".to_owned(), Value::String(day.owner_date.clone())));
            entries.push(("type".to_owned(), Value::String("health-data".to_owned())));
            entries.push(("time_context".to_owned(), serde_json::json!({"calendar_timezone":config.calendar_time_zone,"timestamp_timezone":"UTC"})));
            entries.push(("unit_system".to_owned(), Value::String("metric".to_owned())));
            let units = sorted_metrics(day)
                .into_iter()
                .filter(|metric| !metric.unit.is_empty())
                .map(|metric| {
                    (
                        metric.frontmatter_key.clone(),
                        Value::String(metric.unit.clone()),
                    )
                })
                .collect();
            entries.push(("units".to_owned(), Value::Object(units)));
            entries.push((
                "raw_capture_status".to_owned(),
                Value::String(config.raw_capture_status.clone()),
            ));
        }
        SemanticProfile::AndroidFrozenV4 => {
            entries.push(("date".to_owned(), Value::String(day.owner_date.clone())));
            entries.push(("type".to_owned(), Value::String("health-data".to_owned())));
            entries.push((
                "units".to_owned(),
                Value::String(config.unit_system.id().to_owned()),
            ));
        }
        SemanticProfile::AndroidAnalyticalV5 => {
            entries.push(("date".to_owned(), Value::String(day.owner_date.clone())));
            entries.push(("type".to_owned(), Value::String("health-data".to_owned())));
            entries.push((
                "units".to_owned(),
                Value::String(config.unit_system.id().to_owned()),
            ));
            entries.push((
                "schemaProfile".to_owned(),
                Value::String("android-analytical-v5".to_owned()),
            ));
            entries.push(("schemaVersion".to_owned(), Value::from(5)));
        }
    }
    for (_, key, value) in public_fields {
        entries.push((key, value));
    }
    let mut extension_fields = BTreeMap::new();
    for extension in &day.extensions {
        if let (Some(field), Some(value)) = (&extension.json_field, &extension.json_value) {
            if extension_fields
                .insert(field.clone(), value.clone())
                .is_some()
            {
                return Err(RenderError::PresentationMismatch);
            }
        }
    }
    entries.extend(extension_fields);
    Ok(entries)
}

fn insert_json_value(
    object: &mut serde_json::Map<String, Value>,
    path: &[String],
    value: Value,
) -> Result<(), RenderError> {
    let Some((key, tail)) = path.split_first() else {
        return Err(RenderError::PresentationMismatch);
    };
    if tail.is_empty() {
        if object.insert(key.clone(), value).is_some() {
            return Err(RenderError::PresentationMismatch);
        }
        return Ok(());
    }
    let child = object
        .entry(key.clone())
        .or_insert_with(|| Value::Object(serde_json::Map::new()));
    let Value::Object(child) = child else {
        return Err(RenderError::PresentationMismatch);
    };
    insert_json_value(child, tail, value)
}

pub(crate) fn kotlin_ordered_json(value: &OrderedJsonValue) -> Result<Vec<u8>, RenderError> {
    let mut output = String::new();
    write_ordered_json(&mut output, value, 0, 4, false, false)?;
    Ok(output.into_bytes())
}

pub(crate) fn foundation_ordered_json(value: &OrderedJsonValue) -> Result<Vec<u8>, RenderError> {
    let mut output = String::new();
    write_ordered_json(&mut output, value, 0, 2, true, true)?;
    Ok(output.into_bytes())
}

fn write_ordered_json(
    output: &mut String,
    value: &OrderedJsonValue,
    level: usize,
    width: usize,
    sort_objects: bool,
    foundation_spacing: bool,
) -> Result<(), RenderError> {
    match value {
        OrderedJsonValue::Null => output.push_str("null"),
        OrderedJsonValue::Boolean { value } => {
            output.push_str(if *value { "true" } else { "false" });
        }
        OrderedJsonValue::Number { decimal } => output.push_str(decimal),
        OrderedJsonValue::String { value } => {
            let encoded =
                serde_json::to_string(value).map_err(|_| RenderError::SerializationFailed)?;
            if foundation_spacing {
                output.push_str(&encoded.replace('/', "\\/"));
            } else {
                output.push_str(&encoded);
            }
        }
        OrderedJsonValue::Array { items } => {
            if items.is_empty() {
                if foundation_spacing {
                    output.push_str("[\n\n");
                    ordered_indent(output, level, width);
                    output.push(']');
                } else {
                    output.push_str("[]");
                }
            } else {
                output.push_str("[\n");
                for (index, item) in items.iter().enumerate() {
                    ordered_indent(output, level + 1, width);
                    write_ordered_json(
                        output,
                        item,
                        level + 1,
                        width,
                        sort_objects,
                        foundation_spacing,
                    )?;
                    if index + 1 != items.len() {
                        output.push(',');
                    }
                    output.push('\n');
                }
                ordered_indent(output, level, width);
                output.push(']');
            }
        }
        OrderedJsonValue::Object { entries } => {
            if entries.is_empty() {
                if foundation_spacing {
                    output.push_str("{\n\n");
                    ordered_indent(output, level, width);
                    output.push('}');
                } else {
                    output.push_str("{}");
                }
            } else {
                output.push_str("{\n");
                let mut entries = entries.iter().collect::<Vec<_>>();
                if sort_objects {
                    entries.sort_by(|left, right| foundation_key_cmp(&left.key, &right.key));
                }
                let len = entries.len();
                for (index, entry) in entries.into_iter().enumerate() {
                    ordered_indent(output, level + 1, width);
                    let key = serde_json::to_string(&entry.key)
                        .map_err(|_| RenderError::SerializationFailed)?;
                    if foundation_spacing {
                        output.push_str(&key.replace('/', "\\/"));
                    } else {
                        output.push_str(&key);
                    }
                    output.push_str(if foundation_spacing { " : " } else { ": " });
                    write_ordered_json(
                        output,
                        &entry.value,
                        level + 1,
                        width,
                        sort_objects,
                        foundation_spacing,
                    )?;
                    if index + 1 != len {
                        output.push(',');
                    }
                    output.push('\n');
                }
                ordered_indent(output, level, width);
                output.push('}');
            }
        }
    }
    Ok(())
}

fn ordered_indent(output: &mut String, level: usize, width: usize) {
    output.push_str(&" ".repeat(level * width));
}

pub(crate) fn kotlin_pretty_json(entries: &[(String, Value)]) -> Result<Vec<u8>, RenderError> {
    let mut output = String::from("{\n");
    for (index, (key, value)) in entries.iter().enumerate() {
        output.push_str("    ");
        output.push_str(&serde_json::to_string(key).map_err(|_| RenderError::SerializationFailed)?);
        output.push_str(": ");
        write_kotlin_value(&mut output, value, 1)?;
        if index + 1 != entries.len() {
            output.push(',');
        }
        output.push('\n');
    }
    output.push('}');
    Ok(output.into_bytes())
}

fn write_kotlin_value(
    output: &mut String,
    value: &Value,
    indent: usize,
) -> Result<(), RenderError> {
    match value {
        Value::Null | Value::Bool(_) | Value::Number(_) | Value::String(_) => output
            .push_str(&serde_json::to_string(value).map_err(|_| RenderError::SerializationFailed)?),
        Value::Array(values) => {
            if values.is_empty() {
                output.push_str("[]");
            } else {
                output.push_str("[\n");
                for (index, value) in values.iter().enumerate() {
                    output.push_str(&"    ".repeat(indent + 1));
                    write_kotlin_value(output, value, indent + 1)?;
                    if index + 1 != values.len() {
                        output.push(',');
                    }
                    output.push('\n');
                }
                output.push_str(&"    ".repeat(indent));
                output.push(']');
            }
        }
        Value::Object(values) => {
            if values.is_empty() {
                output.push_str("{}");
            } else {
                output.push_str("{\n");
                for (index, (key, value)) in values.iter().enumerate() {
                    output.push_str(&"    ".repeat(indent + 1));
                    output.push_str(
                        &serde_json::to_string(key)
                            .map_err(|_| RenderError::SerializationFailed)?,
                    );
                    output.push_str(": ");
                    write_kotlin_value(output, value, indent + 1)?;
                    if index + 1 != values.len() {
                        output.push(',');
                    }
                    output.push('\n');
                }
                output.push_str(&"    ".repeat(indent));
                output.push('}');
            }
        }
    }
    Ok(())
}

pub(crate) fn foundation_compact_json(entries: &[(String, Value)]) -> Result<Vec<u8>, RenderError> {
    let object = Value::Object(entries.iter().cloned().collect());
    let mut output = String::new();
    write_foundation_compact_value(&mut output, &object, true)?;
    Ok(output.into_bytes())
}

pub(crate) fn foundation_compact_value_without_escaped_slashes(
    value: &Value,
) -> Result<Vec<u8>, RenderError> {
    let mut output = String::new();
    write_foundation_compact_value(&mut output, value, false)?;
    Ok(output.into_bytes())
}

fn write_foundation_compact_value(
    output: &mut String,
    value: &Value,
    escape_slashes: bool,
) -> Result<(), RenderError> {
    match value {
        Value::Null | Value::Bool(_) | Value::Number(_) | Value::String(_) => {
            if escape_slashes {
                output.push_str(&foundation_json_scalar(value)?);
            } else {
                output.push_str(
                    &serde_json::to_string(value).map_err(|_| RenderError::SerializationFailed)?,
                );
            }
        }
        Value::Array(values) => {
            output.push('[');
            for (index, value) in values.iter().enumerate() {
                if index != 0 {
                    output.push(',');
                }
                write_foundation_compact_value(output, value, escape_slashes)?;
            }
            output.push(']');
        }
        Value::Object(values) => {
            output.push('{');
            let mut values = values.iter().collect::<Vec<_>>();
            values.sort_by(|left, right| foundation_key_cmp(left.0, right.0));
            for (index, (key, value)) in values.into_iter().enumerate() {
                if index != 0 {
                    output.push(',');
                }
                if escape_slashes {
                    output.push_str(&foundation_json_string(key)?);
                } else {
                    output.push_str(
                        &serde_json::to_string(key)
                            .map_err(|_| RenderError::SerializationFailed)?,
                    );
                }
                output.push(':');
                write_foundation_compact_value(output, value, escape_slashes)?;
            }
            output.push('}');
        }
    }
    Ok(())
}

pub(crate) fn foundation_pretty_json(entries: &[(String, Value)]) -> Result<Vec<u8>, RenderError> {
    let object = Value::Object(entries.iter().cloned().collect());
    let mut output = String::new();
    write_foundation_value(&mut output, &object, 0)?;
    Ok(output.into_bytes())
}

fn foundation_json_scalar(value: &Value) -> Result<String, RenderError> {
    if let Value::Number(number) = value {
        if let Some(value) = number.as_i64() {
            return Ok(value.to_string());
        }
        if let Some(value) = number.as_u64() {
            return Ok(value.to_string());
        }
        if let Some(value) = number.as_f64() {
            return Ok(foundation_double(value));
        }
    }
    let encoded = serde_json::to_string(value).map_err(|_| RenderError::SerializationFailed)?;
    Ok(if matches!(value, Value::String(_)) {
        encoded.replace('/', "\\/")
    } else {
        encoded
    })
}

#[allow(clippy::cast_possible_truncation)]
fn foundation_double(value: f64) -> String {
    if value == 0.0 {
        return if value.is_sign_negative() { "-0" } else { "0" }.to_owned();
    }
    let order = value.abs().log10().floor() as i32;
    if !(-4..17).contains(&order) {
        let encoded = format!("{value:.16e}");
        let (mantissa, exponent) = encoded.split_once('e').unwrap_or((&encoded, "0"));
        let mantissa = trim_fraction(mantissa);
        let exponent = exponent.parse::<i32>().unwrap_or(0);
        return format!("{mantissa}e{exponent:+}");
    }
    let precision = usize::try_from(16_i32.saturating_sub(order)).unwrap_or(0);
    let encoded = format!("{value:.precision$}");
    trim_fraction(&encoded).to_owned()
}

fn trim_fraction(value: &str) -> &str {
    if value.contains('.') {
        value.trim_end_matches('0').trim_end_matches('.')
    } else {
        value
    }
}

fn foundation_key_cmp(left: &str, right: &str) -> std::cmp::Ordering {
    left.to_lowercase()
        .cmp(&right.to_lowercase())
        .then_with(|| left.cmp(right))
}

fn foundation_json_string(value: &str) -> Result<String, RenderError> {
    serde_json::to_string(value)
        .map(|encoded| encoded.replace('/', "\\/"))
        .map_err(|_| RenderError::SerializationFailed)
}

fn write_foundation_value(
    output: &mut String,
    value: &Value,
    indent: usize,
) -> Result<(), RenderError> {
    match value {
        Value::Null | Value::Bool(_) | Value::Number(_) | Value::String(_) => {
            output.push_str(&foundation_json_scalar(value)?);
        }
        Value::Array(values) => {
            if values.is_empty() {
                output.push_str("[\n\n]");
                return Ok(());
            }
            output.push_str("[\n");
            for (index, value) in values.iter().enumerate() {
                output.push_str(&" ".repeat(indent + 2));
                write_foundation_value(output, value, indent + 2)?;
                if index + 1 != values.len() {
                    output.push(',');
                }
                output.push('\n');
            }
            output.push_str(&" ".repeat(indent));
            output.push(']');
        }
        Value::Object(values) => {
            if values.is_empty() {
                output.push_str("{\n\n}");
                return Ok(());
            }
            output.push_str("{\n");
            let mut values = values.iter().collect::<Vec<_>>();
            values.sort_by(|left, right| foundation_key_cmp(left.0, right.0));
            let len = values.len();
            for (index, (key, value)) in values.into_iter().enumerate() {
                output.push_str(&" ".repeat(indent + 2));
                output.push_str(&foundation_json_string(key)?);
                output.push_str(" : ");
                write_foundation_value(output, value, indent + 2)?;
                if index + 1 != len {
                    output.push(',');
                }
                output.push('\n');
            }
            output.push_str(&" ".repeat(indent));
            output.push('}');
        }
    }
    Ok(())
}

pub(crate) fn render_individual_entry(
    entry: &RenderIndividualEntry,
) -> Result<Vec<u8>, RenderError> {
    if let Some(document) = &entry.document {
        let mut output = String::new();
        append_line_document(&mut output, document);
        return Ok(output.into_bytes());
    }
    let mut output = String::from("---\n");
    for (key, value) in &entry.frontmatter {
        writeln!(output, "{}: {}", yaml_key(key), yaml_scalar(value))
            .map_err(|_| RenderError::SerializationFailed)?;
    }
    output.push_str("---\n# ");
    output.push_str(&entry.title);
    output.push('\n');
    for line in &entry.body_lines {
        output.push_str(line);
        output.push('\n');
    }
    Ok(output.into_bytes())
}

pub(crate) fn render_daily_note(
    config: &RenderSessionConfig,
    day: &RenderDay,
    note: &RenderDailyNote,
) -> Result<Vec<u8>, RenderError> {
    if let Some(document) = &note.document {
        let mut output = String::new();
        append_line_document(&mut output, document);
        return Ok(output.into_bytes());
    }
    let mut output = String::new();
    if note.include_frontmatter {
        output.push_str(
            &String::from_utf8(render_frontmatter(
                config,
                day,
                FrontmatterSurface::Markdown,
            )?)
            .map_err(|_| RenderError::SerializationFailed)?,
        );
    }
    if note.include_markdown {
        output.push_str(&standard_markdown(config, day)?);
    }
    Ok(output.into_bytes())
}

/// Merge generated app-owned frontmatter and sections while preserving unknown user content.
///
/// # Errors
/// Returns a stable size/encoding error when either bounded document is invalid.
pub fn merge_markdown(existing: &str, generated: &str) -> Result<String, RenderError> {
    super::markdown_merge::merge_profile_markdown(
        SemanticProfile::AppleHealthDataV8,
        existing,
        generated,
        false,
    )
}

fn yaml_key(value: &str) -> String {
    if value
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
    {
        value.to_owned()
    } else {
        yaml_quoted(value)
    }
}

fn yaml_scalar(value: &str) -> String {
    let lower = value.to_ascii_lowercase();
    let unsafe_value = value.is_empty()
        || value.trim() != value
        || value.contains([
            ':', '#', '\n', '\r', '\t', '[', ']', '{', '}', ',', '&', '*', '!', '|', '>', '\'',
            '"', '%', '@', '`',
        ])
        || matches!(
            lower.as_str(),
            "null" | "true" | "false" | "yes" | "no" | "on" | "off" | "~"
        )
        || value.starts_with(['-', '?']) && value.chars().nth(1).is_some_and(char::is_whitespace);
    if unsafe_value {
        yaml_quoted(value)
    } else {
        value.to_owned()
    }
}

fn yaml_quoted(value: &str) -> String {
    format!(
        "\"{}\"",
        value
            .replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
    )
}

fn category_emoji(category: &str) -> &'static str {
    match category {
        "sleep" => "😴 ",
        "activity" => "🏃 ",
        "heart" => "❤️ ",
        "vitals" => "🩺 ",
        "body" => "📏 ",
        "nutrition" => "🍎 ",
        "mindfulness" => "🧘 ",
        "mobility" => "🚶 ",
        "hearing" => "👂 ",
        "workouts" => "💪 ",
        "medications" => "💊 ",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn csv_and_yaml_escape_control_characters() {
        assert_eq!(csv_field("a,\"b\n"), "\"a,\"\"b\n\"");
        assert_eq!(yaml_scalar("a: b"), "\"a: b\"");
        assert_eq!(yaml_scalar("42"), "42");
    }

    #[test]
    fn markdown_merge_is_idempotent_and_preserves_unknown_content() {
        let existing =
            "---\ndate: old\nuser: keep\n---\nPreamble\n\n## Sleep\nold\n\n## Notes\nkeep\n";
        let generated =
            "---\ndate: new\nsteps: 2\n---\n## Sleep\nnew\n\n## Planned Workouts\nplan\n";
        let merged = merge_markdown(existing, generated).unwrap();
        assert!(merged.contains("user: keep"));
        assert!(merged.contains("date: new"));
        assert!(!merged.contains("## Sleep\nold"));
        assert!(merged.contains("## Sleep\nnew"));
        assert!(merged.contains("## Notes\nkeep"));
        assert!(merged.contains("## Planned Workouts\nplan"));
        assert_eq!(merge_markdown(&merged, generated).unwrap(), merged);
    }

    #[test]
    fn nested_json_paths_create_objects_and_reject_conflicts() {
        let mut object = serde_json::Map::new();
        insert_json_value(
            &mut object,
            &["stages".to_owned(), "deep".to_owned()],
            Value::from(42),
        )
        .unwrap();
        assert_eq!(
            Value::Object(object.clone()),
            serde_json::json!({"stages":{"deep":42}})
        );
        assert_eq!(
            insert_json_value(
                &mut object,
                &["stages".to_owned()],
                Value::String("conflict".to_owned()),
            ),
            Err(RenderError::PresentationMismatch)
        );
    }

    #[test]
    fn kotlin_writer_uses_four_space_pretty_output() {
        let bytes = kotlin_pretty_json(&[
            ("date".to_owned(), Value::String("2026-07-25".to_owned())),
            ("activity".to_owned(), serde_json::json!({"steps":1234})),
        ])
        .unwrap();
        assert_eq!(
            String::from_utf8(bytes).unwrap(),
            "{\n    \"date\": \"2026-07-25\",\n    \"activity\": {\n        \"steps\": 1234\n    }\n}"
        );
    }

    #[test]
    fn foundation_compact_writer_sorts_keys_and_escapes_slashes() {
        assert_eq!(
            String::from_utf8(
                foundation_compact_json(&[
                    ("z".to_owned(), Value::String("a/b".to_owned())),
                    ("a".to_owned(), Value::from(1)),
                ])
                .unwrap(),
            )
            .unwrap(),
            r#"{"a":1,"z":"a\/b"}"#
        );
    }

    #[test]
    fn foundation_writer_has_apple_spacing_and_sorted_keys() {
        let bytes = foundation_pretty_json(&[
            ("z".to_owned(), Value::from(1)),
            ("a".to_owned(), Value::from(true)),
        ])
        .unwrap();
        assert_eq!(
            String::from_utf8(bytes).unwrap(),
            "{\n  \"a\" : true,\n  \"z\" : 1\n}"
        );
    }
}
