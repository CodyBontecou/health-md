//! Exact Apple v8 roll-up bytes and paths.

use std::{collections::BTreeMap, fmt::Write as _};

use chrono::{Datelike, NaiveDate};
use serde_json::Value;

use super::{
    RenderError, RenderFormat, RenderSessionConfig, RequestedWriteMode, RollupMetricPresentation,
    WriteMode,
    artifact_plan::{ArtifactPlanBuilder, validate_relative_path},
    format,
};
use crate::semantic::{
    ExactNumber, RollupPeriod, SemanticResult, SemanticRollupResult, SemanticValue,
};

struct Metric<'a> {
    presentation: &'a RollupMetricPresentation,
    rule: &'a str,
    primary: String,
    days_counted: u32,
    statistics: Vec<(&'a str, String)>,
}

pub(crate) fn add_rollups(
    builder: &mut ArtifactPlanBuilder,
    config: &RenderSessionConfig,
    semantic: &SemanticResult,
) -> Result<(), RenderError> {
    if semantic.rollups.is_empty() {
        return Ok(());
    }
    config.rollups.as_ref().ok_or(RenderError::InvalidConfig)?;
    let mut rollups = semantic.rollups.iter().collect::<Vec<_>>();
    rollups.sort_by(|left, right| {
        left.start_date
            .cmp(&right.start_date)
            .then(left.period.cmp(&right.period))
    });
    let formats = super::ordered_formats(config.profile, &config.formats);
    for rollup in rollups {
        if rollup.period == RollupPeriod::Range {
            continue;
        }
        let period_id = period_identifier(rollup)?;
        for output_format in &formats {
            let content = render(config, rollup, *output_format)?;
            let format_folder = config.paths.format_folders.for_format(*output_format);
            let same_markdown_folder = format_folder == config.paths.format_folders.markdown;
            let suffix = if *output_format == RenderFormat::ObsidianBases && same_markdown_folder {
                config.paths.bases_suffix.as_str()
            } else {
                ""
            };
            let filename = format!("{period_id}{suffix}.{}", output_format.extension());
            let path = super::join_relative(&[
                &config.paths.base_directory,
                &config.paths.rollup_directory,
                format_folder,
                period_folder(rollup.period),
                &filename,
            ]);
            validate_relative_path(&path)?;
            builder.add(
                path,
                output_format.media_type(),
                normalized_rollup_write_mode(config.write_mode, *output_format),
                content,
            )?;
        }
    }
    Ok(())
}

fn normalized_rollup_write_mode(requested: RequestedWriteMode, format: RenderFormat) -> WriteMode {
    match requested {
        RequestedWriteMode::Append => WriteMode::Append,
        RequestedWriteMode::Update if format == RenderFormat::Markdown => WriteMode::MarkdownMerge,
        RequestedWriteMode::Overwrite | RequestedWriteMode::Update => WriteMode::Overwrite,
    }
}

fn render(
    config: &RenderSessionConfig,
    rollup: &SemanticRollupResult,
    output: RenderFormat,
) -> Result<Vec<u8>, RenderError> {
    let settings = config.rollups.as_ref().ok_or(RenderError::InvalidConfig)?;
    let period_id = period_identifier(rollup)?;
    let days_expected = days_expected(rollup)?;
    let days_counted = u32::try_from(
        rollup
            .source_dates
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
    )
    .map_err(|_| RenderError::LimitExceeded)?;
    let coverage = if days_expected == 0 {
        0.0
    } else {
        f64::from(days_counted) / f64::from(days_expected) * 100.0
    };
    let mut metrics = rollup
        .values
        .iter()
        .map(|value| {
            let presentation = settings
                .metrics
                .get(&value.output_key)
                .ok_or(RenderError::PresentationMismatch)?;
            let mut statistics = Vec::new();
            for name in &presentation.statistic_order {
                let semantic_name = match name.as_str() {
                    "daily_average" => "average_of_daily_values",
                    "minimum" => "minimum_daily_value",
                    "maximum" => "maximum_daily_value",
                    other => other,
                };
                if let Some(statistic) = value.statistics.get(semantic_name) {
                    let mut display = display_value(statistic)?;
                    if name == "value_counts" {
                        display = normalize_value_counts(&display);
                    }
                    statistics.push((name.as_str(), display));
                }
            }
            Ok(Metric {
                presentation,
                rule: &value.rule,
                primary: display_value(&value.primary_value)?,
                days_counted: value.days_counted,
                statistics,
            })
        })
        .collect::<Result<Vec<_>, RenderError>>()?;
    metrics.sort_by(|left, right| {
        left.presentation
            .category
            .cmp(&right.presentation.category)
            .then(
                left.presentation
                    .display_name
                    .cmp(&right.presentation.display_name),
            )
            .then(left.presentation.key.cmp(&right.presentation.key))
    });
    let context = Context {
        rollup,
        period_id,
        days_expected,
        days_counted,
        coverage,
        generated_at: &settings.generated_at,
        metrics,
    };
    match output {
        RenderFormat::Markdown => Ok(render_markdown(&context)),
        RenderFormat::ObsidianBases => Ok(render_bases(&context)),
        RenderFormat::Json => render_json(&context),
        RenderFormat::Csv => Ok(render_csv(&context)),
    }
}

struct Context<'a> {
    rollup: &'a SemanticRollupResult,
    period_id: String,
    days_expected: u32,
    days_counted: u32,
    coverage: f64,
    generated_at: &'a str,
    metrics: Vec<Metric<'a>>,
}

fn render_json(context: &Context<'_>) -> Result<Vec<u8>, RenderError> {
    let metrics = context.metrics.iter().map(metric_json).collect::<Vec<_>>();
    let mut categories: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for metric in &context.metrics {
        categories
            .entry(metric.presentation.category.clone())
            .or_default()
            .push(metric_json(metric));
    }
    let units = context
        .metrics
        .iter()
        .filter(|metric| !metric.presentation.unit.is_empty())
        .map(|metric| {
            (
                metric.presentation.key.clone(),
                Value::String(metric.presentation.unit.clone()),
            )
        })
        .collect::<serde_json::Map<_, _>>();
    let mut bytes = format::foundation_pretty_json(&[
        (
            "schema".to_owned(),
            Value::String("healthmd.rollup_summary".to_owned()),
        ),
        ("schema_version".to_owned(), Value::from(8)),
        ("type".to_owned(), Value::String("health_rollup".to_owned())),
        (
            "rollup_period".to_owned(),
            Value::String(period_id(context.rollup.period).to_owned()),
        ),
        (
            "period_id".to_owned(),
            Value::String(context.period_id.clone()),
        ),
        (
            "start_date".to_owned(),
            Value::String(context.rollup.start_date.clone()),
        ),
        (
            "end_date".to_owned(),
            Value::String(context.rollup.end_date.clone()),
        ),
        (
            "days_expected".to_owned(),
            Value::from(context.days_expected),
        ),
        ("days_counted".to_owned(), Value::from(context.days_counted)),
        (
            "coverage_percent".to_owned(),
            finite_json(context.coverage)?,
        ),
        (
            "source_schema".to_owned(),
            Value::String("healthmd.health_data".to_owned()),
        ),
        ("source_schema_version".to_owned(), Value::from(8)),
        ("rollup_rules_version".to_owned(), Value::from(8)),
        (
            "generated_at".to_owned(),
            Value::String(context.generated_at.to_owned()),
        ),
        (
            "source_dates".to_owned(),
            Value::Array(sorted_source_dates(context.rollup)),
        ),
        ("units".to_owned(), Value::Object(units)),
        ("metrics".to_owned(), Value::Array(metrics)),
        (
            "categories".to_owned(),
            Value::Object(
                categories
                    .into_iter()
                    .map(|(key, values)| (key, Value::Array(values)))
                    .collect(),
            ),
        ),
    ])?;
    bytes.push(b'\n');
    Ok(bytes)
}

fn metric_json(metric: &Metric<'_>) -> Value {
    let mut value = serde_json::Map::new();
    value.insert(
        "key".to_owned(),
        Value::String(metric.presentation.key.clone()),
    );
    value.insert(
        "canonical_key".to_owned(),
        Value::String(metric.presentation.canonical_key.clone()),
    );
    value.insert(
        "display_name".to_owned(),
        Value::String(metric.presentation.display_name.clone()),
    );
    value.insert(
        "category".to_owned(),
        Value::String(metric.presentation.category.clone()),
    );
    value.insert(
        "unit".to_owned(),
        Value::String(metric.presentation.unit.clone()),
    );
    value.insert("rule".to_owned(), Value::String(metric.rule.to_owned()));
    value.insert(
        "primary_value".to_owned(),
        Value::String(metric.primary.clone()),
    );
    value.insert("days_counted".to_owned(), Value::from(metric.days_counted));
    value.insert(
        "statistics".to_owned(),
        Value::Array(
            metric
                .statistics
                .iter()
                .map(|(name, value)| serde_json::json!({"name":name,"value":value}))
                .collect(),
        ),
    );
    if let Some(notes) = &metric.presentation.notes {
        value.insert("notes".to_owned(), Value::String(notes.clone()));
    }
    Value::Object(value)
}

fn render_csv(context: &Context<'_>) -> Vec<u8> {
    let mut output = String::from(
        "Period,Period ID,Start Date,End Date,Days Expected,Days Counted,Coverage Percent,Category,Metric,Key,Canonical Key,Primary Value,Unit,Metric Days Counted,Rule,Statistic,Statistic Value,Notes\n",
    );
    for metric in &context.metrics {
        let common = [
            period_id(context.rollup.period).to_owned(),
            context.period_id.clone(),
            context.rollup.start_date.clone(),
            context.rollup.end_date.clone(),
            context.days_expected.to_string(),
            context.days_counted.to_string(),
            format_number(context.coverage),
            metric.presentation.category.clone(),
            metric.presentation.display_name.clone(),
            metric.presentation.key.clone(),
            metric.presentation.canonical_key.clone(),
            metric.primary.clone(),
            metric.presentation.unit.clone(),
            metric.days_counted.to_string(),
            metric.rule.to_owned(),
        ];
        append_csv_row(
            &mut output,
            common.iter().map(String::as_str).chain([
                "primary",
                metric.primary.as_str(),
                metric.presentation.notes.as_deref().unwrap_or(""),
            ]),
        );
        for (name, value) in &metric.statistics {
            append_csv_row(
                &mut output,
                common.iter().map(String::as_str).chain([
                    *name,
                    value.as_str(),
                    metric.presentation.notes.as_deref().unwrap_or(""),
                ]),
            );
        }
    }
    output.into_bytes()
}

#[allow(clippy::too_many_lines)]
fn render_markdown(context: &Context<'_>) -> Vec<u8> {
    let period = period_id(context.rollup.period);
    let display_period = period_display(context.rollup.period);
    let mut lines = vec![
        "---".to_owned(),
        "schema: healthmd.rollup_summary".to_owned(),
        "schema_version: 8".to_owned(),
        "type: health_rollup".to_owned(),
        format!("rollup_period: {period}"),
        format!("period_id: {}", context.period_id),
        format!("start_date: {}", context.rollup.start_date),
        format!("end_date: {}", context.rollup.end_date),
        format!("days_expected: {}", context.days_expected),
        format!("days_counted: {}", context.days_counted),
        format!("coverage_percent: {}", format_number(context.coverage)),
        "source_schema: healthmd.health_data".to_owned(),
        "source_schema_version: 8".to_owned(),
        "rollup_rules_version: 8".to_owned(),
        format!("generated_at: {}", context.generated_at),
    ];
    let dates = sorted_source_date_strings(context.rollup);
    if !dates.is_empty() {
        lines.push("source_dates:".to_owned());
        lines.extend(dates.iter().map(|date| format!("  - {date}")));
    }
    let units = sorted_units(&context.metrics);
    if !units.is_empty() {
        lines.push("units:".to_owned());
        lines.extend(units.iter().map(|(key, unit)| format!("  {key}: {unit}")));
    }
    lines.extend([
        "---".to_owned(),
        String::new(),
        format!("# {display_period} Health Summary — {}", context.period_id),
        String::new(),
        format!(
            "Generated from {} HealthKit daily aggregate snapshot{} in this {} period.",
            context.days_counted,
            if context.days_counted == 1 { "" } else { "s" },
            display_period.to_lowercase()
        ),
        String::new(),
        "## Coverage".to_owned(),
        String::new(),
        format!(
            "- **Period:** {} → {}",
            context.rollup.start_date, context.rollup.end_date
        ),
        format!(
            "- **Days counted:** {} / {} ({}%)",
            context.days_counted,
            context.days_expected,
            format_number(context.coverage)
        ),
        format!(
            "- **Missing days:** {}",
            context.days_expected.saturating_sub(context.days_counted)
        ),
        "- **Rule source:** `_healthmd_data_dictionary.json` schema v8".to_owned(),
    ]);
    if !dates.is_empty() {
        lines.push(format!("- **Source dates:** {}", dates.join(", ")));
    }
    let categories = context
        .metrics
        .iter()
        .map(|metric| metric.presentation.category.as_str())
        .collect::<std::collections::BTreeSet<_>>();
    for category in categories {
        let mut metrics = context
            .metrics
            .iter()
            .filter(|metric| metric.presentation.category == category)
            .collect::<Vec<_>>();
        metrics.sort_by(|left, right| {
            left.presentation
                .display_name
                .cmp(&right.presentation.display_name)
                .then(left.presentation.key.cmp(&right.presentation.key))
        });
        lines.extend([
            String::new(),
            format!("## {category}"),
            String::new(),
            "| Metric | Key | Value | Unit | Days | Rule |".to_owned(),
            "|---|---:|---:|---|---:|---|".to_owned(),
        ]);
        for metric in &metrics {
            lines.push(format!(
                "| {} | `{}` | {} | {} | {}/{} | {} |",
                table_escape(&metric.presentation.display_name),
                metric.presentation.key,
                table_escape(&metric.primary),
                table_escape(&metric.presentation.unit),
                metric.days_counted,
                context.days_expected,
                metric.rule
            ));
        }
        let statistic_rows = metrics
            .iter()
            .flat_map(|metric| {
                metric
                    .statistics
                    .iter()
                    .map(move |statistic| (*metric, statistic))
            })
            .collect::<Vec<_>>();
        if !statistic_rows.is_empty() {
            lines.extend([
                String::new(),
                "<details>".to_owned(),
                format!("<summary>{category} statistics</summary>"),
                String::new(),
                "| Key | Statistic | Value |".to_owned(),
                "|---|---:|---:|".to_owned(),
            ]);
            for (metric, (name, value)) in statistic_rows {
                lines.push(format!(
                    "| `{}` | {} | {} |",
                    metric.presentation.key,
                    table_escape(name),
                    table_escape(value)
                ));
            }
            lines.extend([String::new(), "</details>".to_owned()]);
        }
    }
    lines.extend([
        String::new(),
        "## Roll-up notes".to_owned(),
        String::new(),
        "- Missing daily values are ignored and reported through the days-counted columns.".to_owned(),
        "- Daily averages divide by days with data, not by calendar days.".to_owned(),
        "- Weighted workout metrics use daily workout duration when available, then fall back to unweighted daily values.".to_owned(),
        "- Summary files are derived artifacts and can be regenerated from HealthKit daily aggregates plus the data dictionary.".to_owned(),
    ]);
    (lines.join("\n") + "\n").into_bytes()
}

fn render_bases(context: &Context<'_>) -> Vec<u8> {
    let period = period_id(context.rollup.period);
    let title = format!(
        "{} Health Summary — {}",
        period_display(context.rollup.period),
        context.period_id
    );
    let mut lines = vec![
        "---".to_owned(),
        "schema: healthmd.rollup_summary".to_owned(),
        "schema_version: 8".to_owned(),
        "type: health_rollup".to_owned(),
        format!("rollup_period: {period}"),
        format!("period_id: {}", yaml_quoted(&context.period_id)),
        format!("title: {}", yaml_quoted(&title)),
        format!("start_date: {}", context.rollup.start_date),
        format!("end_date: {}", context.rollup.end_date),
        format!("days_expected: {}", context.days_expected),
        format!("days_counted: {}", context.days_counted),
        format!("coverage_percent: {}", format_number(context.coverage)),
        "source_schema: healthmd.health_data".to_owned(),
        "source_schema_version: 8".to_owned(),
        "rollup_rules_version: 8".to_owned(),
        format!("generated_at: {}", context.generated_at),
    ];
    let dates = sorted_source_date_strings(context.rollup);
    if !dates.is_empty() {
        lines.push("source_dates:".to_owned());
        lines.extend(dates.iter().map(|date| format!("  - {date}")));
    }
    let units = sorted_units(&context.metrics);
    if !units.is_empty() {
        lines.push("units:".to_owned());
        lines.extend(
            units
                .iter()
                .map(|(key, unit)| format!("  {key}: {}", yaml_quoted(unit))),
        );
    }
    lines.push("rollup_metrics:".to_owned());
    let mut metrics = context.metrics.iter().collect::<Vec<_>>();
    metrics.sort_by(|left, right| left.presentation.key.cmp(&right.presentation.key));
    for metric in metrics {
        lines.extend([
            format!("  {}:", metric.presentation.key),
            format!("    value: {}", yaml_quoted(&metric.primary)),
            format!("    unit: {}", yaml_quoted(&metric.presentation.unit)),
            format!(
                "    category: {}",
                yaml_quoted(&metric.presentation.category)
            ),
            format!(
                "    display_name: {}",
                yaml_quoted(&metric.presentation.display_name)
            ),
            format!("    canonical_key: {}", metric.presentation.canonical_key),
            format!("    rule: {}", metric.rule),
            format!("    days_counted: {}", metric.days_counted),
        ]);
        if !metric.statistics.is_empty() {
            lines.push("    statistics:".to_owned());
            lines.extend(
                metric
                    .statistics
                    .iter()
                    .map(|(name, value)| format!("      {name}: {}", yaml_quoted(value))),
            );
        }
        if let Some(notes) = &metric.presentation.notes {
            lines.push(format!("    notes: {}", yaml_quoted(notes)));
        }
    }
    lines.extend([
        "---".to_owned(),
        String::new(),
        format!("# {title}"),
        String::new(),
        "Structured roll-up summary for Obsidian Bases. Query `rollup_metrics` and top-level period fields from the YAML frontmatter.".to_owned(),
    ]);
    (lines.join("\n") + "\n").into_bytes()
}

fn period_identifier(rollup: &SemanticRollupResult) -> Result<String, RenderError> {
    let start = NaiveDate::parse_from_str(&rollup.start_date, "%Y-%m-%d")
        .map_err(|_| RenderError::InvalidSemanticResult)?;
    Ok(match rollup.period {
        RollupPeriod::IsoWeek => format!(
            "{:04}-W{:02}",
            start.iso_week().year(),
            start.iso_week().week()
        ),
        RollupPeriod::CalendarMonth => format!("{:04}-{:02}", start.year(), start.month()),
        RollupPeriod::CalendarYear => format!("{:04}", start.year()),
        RollupPeriod::Range => return Err(RenderError::InvalidSemanticResult),
    })
}

fn days_expected(rollup: &SemanticRollupResult) -> Result<u32, RenderError> {
    let start = NaiveDate::parse_from_str(&rollup.start_date, "%Y-%m-%d")
        .map_err(|_| RenderError::InvalidSemanticResult)?;
    let end = NaiveDate::parse_from_str(&rollup.end_date, "%Y-%m-%d")
        .map_err(|_| RenderError::InvalidSemanticResult)?;
    let days = end.signed_duration_since(start).num_days() + 1;
    u32::try_from(days).map_err(|_| RenderError::InvalidSemanticResult)
}

fn period_id(period: RollupPeriod) -> &'static str {
    match period {
        RollupPeriod::IsoWeek => "weekly",
        RollupPeriod::CalendarMonth => "monthly",
        RollupPeriod::CalendarYear => "yearly",
        RollupPeriod::Range => unreachable!("range roll-ups use the v9 renderer"),
    }
}

fn period_display(period: RollupPeriod) -> &'static str {
    match period {
        RollupPeriod::IsoWeek => "Weekly",
        RollupPeriod::CalendarMonth => "Monthly",
        RollupPeriod::CalendarYear => "Yearly",
        RollupPeriod::Range => unreachable!("range roll-ups use the v9 renderer"),
    }
}

fn period_folder(period: RollupPeriod) -> &'static str {
    period_display(period)
}

fn display_value(value: &SemanticValue) -> Result<String, RenderError> {
    match value {
        SemanticValue::Number { number, .. } => match number {
            ExactNumber::Binary64 { bits } => {
                let bits = u64::from_str_radix(bits, 16)
                    .map_err(|_| RenderError::InvalidSemanticResult)?;
                Ok(format_number(f64::from_bits(bits)))
            }
            ExactNumber::SignedInteger { decimal } | ExactNumber::UnsignedInteger { decimal } => {
                decimal
                    .parse::<f64>()
                    .map(format_number)
                    .map_err(|_| RenderError::InvalidSemanticResult)
            }
        },
        SemanticValue::Text { text } => Ok(text.clone()),
        SemanticValue::Boolean { boolean } => Ok(boolean.to_string()),
        SemanticValue::TextList { items } => Ok(format!(
            "[{}]",
            items
                .iter()
                .map(|item| normalize_list_item(item))
                .collect::<Vec<_>>()
                .join(", ")
        )),
    }
}

fn normalize_list_item(value: &str) -> String {
    value.trim().trim_matches(['\'', '"']).to_owned()
}

fn normalize_value_counts(value: &str) -> String {
    value.rsplit_once(": ").map_or_else(
        || value.trim().to_owned(),
        |(item, count)| format!("{}: {count}", normalize_list_item(item)),
    )
}

fn format_number(value: f64) -> String {
    if !value.is_finite() {
        return String::new();
    }
    let mut value = format!("{value:.2}");
    while value.ends_with('0') {
        value.pop();
    }
    if value.ends_with('.') {
        value.pop();
    }
    let (sign, unsigned) = value
        .strip_prefix('-')
        .map_or(("", value.as_str()), |rest| ("-", rest));
    let (integer, fraction) = unsigned
        .split_once('.')
        .map_or((unsigned, None), |(a, b)| (a, Some(b)));
    let mut grouped = String::new();
    for (index, character) in integer.chars().rev().enumerate() {
        if index != 0 && index % 3 == 0 {
            grouped.push(',');
        }
        grouped.push(character);
    }
    let integer = grouped.chars().rev().collect::<String>();
    fraction.map_or_else(
        || format!("{sign}{integer}"),
        |fraction| format!("{sign}{integer}.{fraction}"),
    )
}

fn finite_json(value: f64) -> Result<Value, RenderError> {
    serde_json::Number::from_f64(value)
        .map(Value::Number)
        .ok_or(RenderError::SerializationFailed)
}

fn sorted_source_dates(rollup: &SemanticRollupResult) -> Vec<Value> {
    sorted_source_date_strings(rollup)
        .into_iter()
        .map(Value::String)
        .collect()
}

fn sorted_source_date_strings(rollup: &SemanticRollupResult) -> Vec<String> {
    let mut dates = rollup.source_dates.clone();
    dates.sort();
    dates
}

fn sorted_units(metrics: &[Metric<'_>]) -> Vec<(String, String)> {
    let mut units = metrics
        .iter()
        .filter(|metric| !metric.presentation.unit.is_empty())
        .map(|metric| {
            (
                metric.presentation.key.clone(),
                metric.presentation.unit.clone(),
            )
        })
        .collect::<Vec<_>>();
    units.sort();
    units
}

fn append_csv_row<'a>(output: &mut String, values: impl Iterator<Item = &'a str>) {
    for (index, value) in values.enumerate() {
        if index != 0 {
            output.push(',');
        }
        output.push_str(&csv_escape(value));
    }
    output.push('\n');
}

fn csv_escape(value: &str) -> String {
    if value.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_owned()
    }
}

fn table_escape(value: &str) -> String {
    let normalized = value.replace("\r\n", "\n").replace('\r', "\n");
    let mut output = String::new();
    for character in normalized.chars() {
        match character {
            '\n' => output.push_str("<br>"),
            '<' => output.push_str("&lt;"),
            '>' => output.push_str("&gt;"),
            '|' => output.push_str("\\|"),
            character if character.is_control() => {
                let _ = write!(output, "\\u{:04X}", u32::from(character));
            }
            character => output.push(character),
        }
    }
    output
}

fn yaml_quoted(value: &str) -> String {
    let mut output = String::from("\"");
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\u{0008}' => output.push_str("\\b"),
            '\t' => output.push_str("\\t"),
            '\n' => output.push_str("\\n"),
            '\u{000c}' => output.push_str("\\f"),
            '\r' => output.push_str("\\r"),
            character if character.is_control() => {
                let _ = write!(output, "\\u{:04X}", u32::from(character));
            }
            character => output.push(character),
        }
    }
    output.push('"');
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_number_table_and_yaml_formatting_are_stable() {
        assert_eq!(format_number(1234.0), "1,234");
        assert_eq!(format_number(12.345), "12.35");
        assert_eq!(table_escape("a|b\nc"), "a\\|b<br>c");
        assert_eq!(yaml_quoted("a\"b\n"), "\"a\\\"b\\n\"");
    }
}
