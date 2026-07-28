use std::{collections::BTreeSet, fs, time::Duration};

use chrono::{NaiveDate, Utc};
use healthmd_protocol::{
    IOS_APPLICATION_PROTOCOL_VERSION,
    encoding::SwiftUuid,
    models::{
        CanonicalSelection, DateSelection, DetailLevel, ExactDateSelection, ExportDestination,
        ExportRequest, SettingsPolicy,
    },
    wire::{DirectQueryDetailLevel, DirectQueryRequest, Empty},
};
use serde_json::{Map, Value, json};
use uuid::Uuid;

use super::app;

const SLEEP_METRICS: &[&str] = &[
    "sleep_total",
    "sleep_bedtime",
    "sleep_wake",
    "sleep_deep",
    "sleep_rem",
    "sleep_core",
    "sleep_awake",
    "sleep_in_bed",
];

#[derive(Debug)]
pub struct QueryInvocation {
    pub request: DirectQueryRequest,
    pub all_pages: bool,
}

#[derive(Debug)]
pub struct ExportInvocation {
    pub request: ExportRequest,
    pub timeout: Duration,
}

pub fn list(ui_enabled: bool) -> Vec<Value> {
    let mut tools: Vec<Value> =
        serde_json::from_str(include_str!("../../assets/mcp-tools-v1.json"))
            .expect("embedded MCP tool catalog must be valid JSON");
    if ui_enabled {
        for tool in &mut tools {
            let name = tool.get("name").and_then(Value::as_str).unwrap_or_default();
            if !matches!(
                name,
                "healthmd_status"
                    | "healthmd_doctor"
                    | "healthmd_capabilities"
                    | "healthmd_metrics"
            ) {
                app::attach_tool_metadata(tool);
            }
        }
    }
    tools
}

#[allow(clippy::too_many_lines)]
pub fn query_invocation(tool: &str, arguments: &Value) -> Result<QueryInvocation, &'static str> {
    let arguments = arguments.as_object().ok_or("arguments must be an object")?;
    let all_pages = match arguments.get("all_pages") {
        Some(value) => value.as_bool().ok_or("all_pages must be a boolean")?,
        None => false,
    };
    let common = [
        "dates",
        "metrics",
        "sources",
        "page",
        "detail_level",
        "all_pages",
    ];
    match tool {
        "healthmd_metric_chart" | "healthmd_workouts" | "healthmd_coverage" => {
            ensure_keys(arguments, &common)?;
        }
        "healthmd_sleep_sessions" => ensure_keys(
            arguments,
            &[
                "dates",
                "metrics",
                "sources",
                "page",
                "detail_level",
                "all_pages",
                "include_naps",
                "window",
            ],
        )?,
        "healthmd_training_alignment" => ensure_keys(
            arguments,
            &[
                "dates",
                "metrics",
                "sources",
                "page",
                "detail_level",
                "all_pages",
                "include_naps",
                "window",
                "workout_activity",
            ],
        )?,
        "healthmd_compare_periods" => ensure_keys(
            arguments,
            &[
                "dates",
                "metrics",
                "sources",
                "page",
                "detail_level",
                "all_pages",
                "first",
                "second",
                "aggregations",
            ],
        )?,
        "healthmd_training_evidence" => ensure_keys(
            arguments,
            &[
                "dates",
                "metrics",
                "sources",
                "page",
                "detail_level",
                "all_pages",
                "detail_ids",
            ],
        )?,
        _ => {}
    }

    let (query, detail_level) = match tool {
        "healthmd_query" | "healthmd_evidence_packet" => {
            ensure_keys(arguments, &["request", "detail_level", "all_pages"])?;
            let request = arguments
                .get("request")
                .and_then(Value::as_object)
                .ok_or("request must be an object")?;
            let detail = detail_level(arguments, "summary")?;
            (Value::Object(request.clone()), detail)
        }
        "healthmd_metric_chart" => {
            typed_query(arguments, json!({"type": "metric_series"}), None, "summary")?
        }
        "healthmd_sleep_sessions" => {
            let mut arguments = arguments.clone();
            merge_sleep_metrics(&mut arguments, false)?;
            let mut operation = json!({
                "type": "sleep_session_listing",
                "include_naps": arguments.get("include_naps").cloned().unwrap_or(Value::Bool(false))
            });
            if let Some(window) = arguments.get("window") {
                operation["window"] = window.clone();
            }
            typed_query(
                &arguments,
                operation,
                Some(explicit_metrics(SLEEP_METRICS.iter().copied())),
                "lossless",
            )?
        }
        "healthmd_training_alignment" => {
            let mut arguments = arguments.clone();
            merge_sleep_metrics(&mut arguments, true)?;
            let mut operation = json!({
                "type": "workout_sleep_alignment",
                "include_naps": arguments.get("include_naps").cloned().unwrap_or(Value::Bool(false))
            });
            if let Some(window) = arguments.get("window") {
                operation["window"] = window.clone();
            }
            if let Some(activity) = arguments.get("workout_activity") {
                operation["workout_activity"] = activity.clone();
            }
            let mut defaults = SLEEP_METRICS.to_vec();
            defaults.push("workouts");
            typed_query(
                &arguments,
                operation,
                Some(explicit_metrics(defaults)),
                "lossless",
            )?
        }
        "healthmd_workouts" => typed_query(
            arguments,
            json!({"type": "workout_listing"}),
            Some(explicit_metrics(["workouts"])),
            "summary",
        )?,
        "healthmd_coverage" => {
            typed_query(arguments, json!({"type": "coverage"}), None, "summary")?
        }
        "healthmd_compare_periods" => {
            let first = arguments.get("first").cloned().ok_or("first is required")?;
            let second = arguments
                .get("second")
                .cloned()
                .ok_or("second is required")?;
            let aggregations = arguments
                .get("aggregations")
                .cloned()
                .ok_or("aggregations are required")?;
            typed_query(
                arguments,
                json!({
                    "type": "period_comparison",
                    "first": first,
                    "second": second,
                    "aggregations": aggregations
                }),
                None,
                "summary",
            )?
        }
        "healthmd_training_evidence" => {
            let detail_ids = arguments
                .get("detail_ids")
                .cloned()
                .unwrap_or_else(|| Value::Array(Vec::new()));
            let has_details = detail_ids
                .as_array()
                .is_none_or(|values| !values.is_empty());
            typed_query(
                arguments,
                json!({
                    "type": "derive_packet",
                    "kind": "training",
                    "detail_ids": detail_ids
                }),
                Some(explicit_metrics(["workouts"])),
                if has_details { "lossless" } else { "summary" },
            )?
        }
        _ => return Err("unknown query tool"),
    };

    let detail_level = match detail_level.as_str() {
        "summary" => DirectQueryDetailLevel::Summary,
        "lossless" => DirectQueryDetailLevel::Lossless,
        _ => return Err("invalid detail level"),
    };
    Ok(QueryInvocation {
        request: DirectQueryRequest {
            protocol_version: healthmd_protocol::IOS_QUERY_APPLICATION_PROTOCOL_VERSION,
            request_id: SwiftUuid(Uuid::new_v4()),
            created_at: Utc::now(),
            detail_level,
            query,
        },
        all_pages,
    })
}

#[allow(clippy::too_many_lines)]
pub fn export_invocation(arguments: &Value) -> Result<ExportInvocation, &'static str> {
    let arguments = arguments.as_object().ok_or("arguments must be an object")?;
    ensure_keys(
        arguments,
        &[
            "date_selection",
            "date_range",
            "settings_policy",
            "metric_ids",
            "categories",
            "all_metrics",
            "detail_level",
            "wait_timeout_seconds",
            "destination",
        ],
    )?;
    let destination = arguments
        .get("destination")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or("destination is required")?;
    let destination_path = std::path::Path::new(destination);
    let metadata = fs::symlink_metadata(destination_path).map_err(|_| "invalid destination")?;
    if !destination_path.is_absolute() || metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err("invalid destination");
    }
    let destination = fs::canonicalize(destination_path)
        .map_err(|_| "invalid destination")?
        .to_str()
        .ok_or("invalid destination")?
        .to_owned();
    let date_selection = match arguments.get("date_selection").and_then(Value::as_str) {
        Some("all_available") if !arguments.contains_key("date_range") => {
            DateSelection::AllAvailable(Empty {})
        }
        Some("explicit_range") => {
            let range = arguments
                .get("date_range")
                .and_then(Value::as_object)
                .ok_or("date_range is required")?;
            ensure_keys(range, &["start", "end"])?;
            let start = range
                .get("start")
                .and_then(Value::as_str)
                .ok_or("invalid start")?;
            let end = range
                .get("end")
                .and_then(Value::as_str)
                .ok_or("invalid end")?;
            let start_date =
                NaiveDate::parse_from_str(start, "%Y-%m-%d").map_err(|_| "invalid start")?;
            let end_date = NaiveDate::parse_from_str(end, "%Y-%m-%d").map_err(|_| "invalid end")?;
            if start_date > end_date {
                return Err("invalid date range");
            }
            DateSelection::Exact(ExactDateSelection {
                start: start.to_owned(),
                end: end.to_owned(),
            })
        }
        _ => return Err("invalid date_selection"),
    };
    let settings_policy = match arguments
        .get("settings_policy")
        .and_then(Value::as_str)
        .unwrap_or("requested_dates_only")
    {
        "requested_dates_only" => SettingsPolicy::RequestedDatesOnly,
        "current_iphone_settings" => SettingsPolicy::CurrentIphoneSettings,
        _ => return Err("invalid settings_policy"),
    };
    let timeout_seconds = arguments
        .get("wait_timeout_seconds")
        .map(number)
        .transpose()?
        .unwrap_or(300.0);
    if !timeout_seconds.is_finite() || !(5.0..=900.0).contains(&timeout_seconds) {
        return Err("invalid wait_timeout_seconds");
    }

    let has_selection = ["metric_ids", "categories", "all_metrics", "detail_level"]
        .iter()
        .any(|key| arguments.contains_key(*key));
    let canonical_selection = if has_selection {
        if settings_policy != SettingsPolicy::RequestedDatesOnly {
            return Err("selection requires requested_dates_only");
        }
        let metric_ids = string_array(arguments.get("metric_ids"), 512)?;
        let categories = string_array(arguments.get("categories"), 64)?;
        let all_metrics = match arguments.get("all_metrics") {
            Some(value) => value.as_bool().ok_or("all_metrics must be a boolean")?,
            None => false,
        };
        if (all_metrics && (!metric_ids.is_empty() || !categories.is_empty()))
            || (!all_metrics && metric_ids.is_empty() && categories.is_empty())
        {
            return Err("invalid metric selection");
        }
        let detail_level = match arguments
            .get("detail_level")
            .and_then(Value::as_str)
            .unwrap_or("summary")
        {
            "summary" => DetailLevel::Summary,
            "lossless" => DetailLevel::Lossless,
            _ => return Err("invalid detail_level"),
        };
        Some(CanonicalSelection {
            metric_ids,
            categories,
            source_ids: vec!["apple_health".to_owned()],
            object_paths: Vec::new(),
            field_pointers: Vec::new(),
            all_metrics,
            detail_level,
        })
    } else {
        None
    };

    Ok(ExportInvocation {
        request: ExportRequest {
            protocol_version: IOS_APPLICATION_PROTOCOL_VERSION,
            job_id: SwiftUuid(Uuid::new_v4()),
            created_at: Utc::now(),
            date_selection,
            settings_policy,
            response_mode: healthmd_protocol::models::ResponseMode::WriteFiles,
            raw_profile: None,
            canonical_selection,
            destination: Some(ExportDestination {
                root_path: destination,
            }),
        },
        timeout: Duration::from_secs_f64(timeout_seconds),
    })
}

pub fn job_id(arguments: &Value, allow_timeout: bool) -> Result<(Uuid, Duration), &'static str> {
    let arguments = arguments.as_object().ok_or("arguments must be an object")?;
    if allow_timeout {
        ensure_keys(arguments, &["job_id", "wait_timeout_seconds"])?;
    } else {
        ensure_keys(arguments, &["job_id"])?;
    }
    let id = arguments
        .get("job_id")
        .and_then(Value::as_str)
        .and_then(|value| Uuid::parse_str(value).ok())
        .ok_or("invalid job_id")?;
    let timeout = if allow_timeout {
        let seconds = arguments
            .get("wait_timeout_seconds")
            .map(number)
            .transpose()?
            .unwrap_or(300.0);
        if !seconds.is_finite() || !(5.0..=900.0).contains(&seconds) {
            return Err("invalid wait_timeout_seconds");
        }
        Duration::from_secs_f64(seconds)
    } else {
        Duration::from_secs(30)
    };
    Ok((id, timeout))
}

#[allow(clippy::needless_pass_by_value)]
fn typed_query(
    arguments: &Map<String, Value>,
    operation: Value,
    default_metrics: Option<Value>,
    default_detail: &str,
) -> Result<(Value, String), &'static str> {
    let dates = arguments
        .get("dates")
        .cloned()
        .ok_or("dates are required")?;
    let metrics = arguments
        .get("metrics")
        .cloned()
        .or(default_metrics)
        .ok_or("metrics are required")?;
    let sources = arguments
        .get("sources")
        .cloned()
        .unwrap_or_else(|| json!({"type": "all_available"}));
    let page = arguments
        .get("page")
        .cloned()
        .unwrap_or_else(|| json!({"max_items": 250, "max_bytes": 262_144, "cursor": null}));
    let detail = detail_level(arguments, default_detail)?;
    Ok((
        json!({
            "schema": "healthmd.query_request",
            "schema_version": 1,
            "metrics": metrics,
            "sources": sources,
            "dates": dates,
            "operation": operation,
            "page": page
        }),
        detail,
    ))
}

fn detail_level(arguments: &Map<String, Value>, fallback: &str) -> Result<String, &'static str> {
    let value = arguments
        .get("detail_level")
        .and_then(Value::as_str)
        .unwrap_or(fallback);
    if matches!(value, "summary" | "lossless") {
        Ok(value.to_owned())
    } else {
        Err("invalid detail_level")
    }
}

fn merge_sleep_metrics(
    arguments: &mut Map<String, Value>,
    include_workouts: bool,
) -> Result<(), &'static str> {
    arguments.insert(
        "detail_level".to_owned(),
        Value::String("lossless".to_owned()),
    );
    let Some(metrics) = arguments.get_mut("metrics") else {
        return Ok(());
    };
    let Some(metrics) = metrics.as_object_mut() else {
        return Err("metrics must be an object");
    };
    if metrics.get("type").and_then(Value::as_str) != Some("explicit") {
        return Ok(());
    }
    let values = metrics
        .get("metric_ids")
        .and_then(Value::as_array)
        .ok_or("metric_ids must be an array")?;
    let mut combined: BTreeSet<String> = values
        .iter()
        .map(|value| value.as_str().map(str::to_owned).ok_or("invalid metric id"))
        .collect::<Result<_, _>>()?;
    combined.extend(SLEEP_METRICS.iter().map(|value| (*value).to_owned()));
    if include_workouts {
        combined.insert("workouts".to_owned());
    }
    metrics.insert(
        "metric_ids".to_owned(),
        Value::Array(combined.into_iter().map(Value::String).collect()),
    );
    Ok(())
}

fn explicit_metrics(values: impl IntoIterator<Item = impl AsRef<str>>) -> Value {
    let values: BTreeSet<String> = values
        .into_iter()
        .map(|value| value.as_ref().to_owned())
        .collect();
    json!({"type": "explicit", "metric_ids": values})
}

fn ensure_keys(object: &Map<String, Value>, allowed: &[&str]) -> Result<(), &'static str> {
    if object.keys().all(|key| allowed.contains(&key.as_str())) {
        Ok(())
    } else {
        Err("unknown argument")
    }
}

fn string_array(value: Option<&Value>, maximum: usize) -> Result<Vec<String>, &'static str> {
    let Some(value) = value else {
        return Ok(Vec::new());
    };
    let values = value.as_array().ok_or("expected string array")?;
    if values.len() > maximum {
        return Err("too many values");
    }
    let mut unique = BTreeSet::new();
    for value in values {
        let value = value
            .as_str()
            .filter(|value| !value.is_empty())
            .ok_or("invalid string")?;
        if !unique.insert(value.to_owned()) {
            return Err("duplicate value");
        }
    }
    Ok(unique.into_iter().collect())
}

fn number(value: &Value) -> Result<f64, &'static str> {
    value.as_f64().ok_or("expected number")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn export_requires_explicit_destination_and_preserves_all_available() {
        let destination = tempfile::tempdir().unwrap();
        let invocation = export_invocation(&json!({
            "date_selection": "all_available",
            "destination": destination.path(),
            "all_metrics": true,
            "detail_level": "lossless"
        }))
        .unwrap();
        assert!(matches!(
            invocation.request.date_selection,
            DateSelection::AllAvailable(_)
        ));
        assert_eq!(
            invocation.request.destination.unwrap().root_path,
            destination.path().canonicalize().unwrap().to_string_lossy()
        );
        assert_eq!(
            invocation.request.canonical_selection.unwrap().detail_level,
            DetailLevel::Lossless
        );
    }

    #[test]
    fn typed_sleep_query_adds_required_metrics_and_lossless_scope() {
        let invocation = query_invocation(
            "healthmd_sleep_sessions",
            &json!({
                "dates": {"type": "all_available"},
                "metrics": {"type": "explicit", "metric_ids": ["heart_rate"]}
            }),
        )
        .unwrap();
        assert_eq!(
            invocation.request.detail_level,
            DirectQueryDetailLevel::Lossless
        );
        let metrics = invocation.request.query["metrics"]["metric_ids"]
            .as_array()
            .unwrap();
        assert!(metrics.contains(&Value::String("sleep_total".to_owned())));
        assert!(metrics.contains(&Value::String("heart_rate".to_owned())));
    }
}
