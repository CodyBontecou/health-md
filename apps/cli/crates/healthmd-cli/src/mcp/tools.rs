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
    enrich_query_schemas(&mut tools);
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

fn enrich_query_schemas(tools: &mut [Value]) {
    for tool in tools {
        let name = tool
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned();
        let Some(schema) = tool.get_mut("inputSchema").and_then(Value::as_object_mut) else {
            continue;
        };
        let Some(properties) = schema.get_mut("properties").and_then(Value::as_object_mut) else {
            continue;
        };
        if matches!(
            name.as_str(),
            "healthmd_metric_chart"
                | "healthmd_sleep_sessions"
                | "healthmd_training_alignment"
                | "healthmd_workouts"
                | "healthmd_coverage"
                | "healthmd_compare_periods"
                | "healthmd_training_evidence"
        ) {
            properties.insert("dates".to_owned(), date_selection_schema());
            properties.insert("metrics".to_owned(), metric_selection_schema());
            properties.insert("sources".to_owned(), source_selection_schema());
            properties.insert("page".to_owned(), page_controls_schema());
        }
        if matches!(
            name.as_str(),
            "healthmd_sleep_sessions" | "healthmd_training_alignment"
        ) {
            properties.insert("window".to_owned(), sleep_window_schema());
            properties.insert(
                "include_naps".to_owned(),
                json!({
                    "type": "boolean",
                    "default": false,
                    "description": "Include nap sessions. The typed tool defaults to false when omitted."
                }),
            );
        }
        if name == "healthmd_compare_periods" {
            properties.insert("first".to_owned(), date_range_schema());
            properties.insert("second".to_owned(), date_range_schema());
            properties.insert("aggregations".to_owned(), aggregation_array_schema());
        }
        if matches!(name.as_str(), "healthmd_query" | "healthmd_evidence_packet") {
            properties.insert("request".to_owned(), query_request_schema());
        }
        if let Some(examples) = tool_examples(&name) {
            schema.insert("examples".to_owned(), examples);
        }
    }
}

fn date_range_schema() -> Value {
    json!({
        "type": "object",
        "description": "Inclusive Health.md calendar-date range. Resolve relative phrases such as last week to concrete dates before calling.",
        "additionalProperties": false,
        "required": ["start_date", "end_date"],
        "properties": {
            "start_date": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$", "description": "Inclusive yyyy-MM-dd start date."},
            "end_date": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$", "description": "Inclusive yyyy-MM-dd end date."}
        }
    })
}

fn date_selection_schema() -> Value {
    json!({
        "type": "object",
        "description": "Choose exactly one shape: {type:'exact',range:{start_date:'yyyy-MM-dd',end_date:'yyyy-MM-dd'}} or {type:'all_available'}. Dates are inclusive. Examples are illustrative; resolve the user's requested dates.",
        "oneOf": [
            {
                "type": "object",
                "additionalProperties": false,
                "required": ["type", "range"],
                "properties": {
                    "type": {"type": "string", "enum": ["exact"]},
                    "range": date_range_schema()
                }
            },
            {
                "type": "object",
                "additionalProperties": false,
                "required": ["type"],
                "properties": {"type": {"type": "string", "enum": ["all_available"]}}
            }
        ],
        "examples": [
            {"type": "exact", "range": {"start_date": "2026-07-22", "end_date": "2026-07-28"}},
            {"type": "all_available"}
        ]
    })
}

fn metric_selection_schema() -> Value {
    json!({
        "type": "object",
        "description": "Choose {type:'explicit',metric_ids:[...]} using canonical IDs from healthmd_metrics, or {type:'all_available'}. Typed sleep/workout tools supply their required metrics when this field is omitted.",
        "oneOf": [
            {
                "type": "object",
                "additionalProperties": false,
                "required": ["type", "metric_ids"],
                "properties": {
                    "type": {"type": "string", "enum": ["explicit"]},
                    "metric_ids": {"type": "array", "minItems": 1, "maxItems": 512, "uniqueItems": true, "items": {"type": "string"}}
                }
            },
            {
                "type": "object",
                "additionalProperties": false,
                "required": ["type"],
                "properties": {"type": {"type": "string", "enum": ["all_available"]}}
            }
        ],
        "examples": [
            {"type": "explicit", "metric_ids": ["sleep_total", "sleep_bedtime", "sleep_wake"]},
            {"type": "all_available"}
        ]
    })
}

fn source_selection_schema() -> Value {
    json!({
        "type": "object",
        "description": "Usually omit this field or use all_available. For direct iPhone filtering use explicit source_ids apple_health and/or healthmd_summary; provider_ids are not available on this path.",
        "oneOf": [
            {
                "type": "object",
                "additionalProperties": false,
                "required": ["type", "source_ids"],
                "properties": {
                    "type": {"type": "string", "enum": ["explicit"]},
                    "source_ids": {"type": "array", "minItems": 1, "uniqueItems": true, "items": {"type": "string", "enum": ["apple_health", "healthmd_summary"]}},
                    "provider_ids": {"type": "array", "maxItems": 0, "items": {"type": "string"}}
                }
            },
            {
                "type": "object",
                "additionalProperties": false,
                "required": ["type"],
                "properties": {"type": {"type": "string", "enum": ["all_available"]}}
            }
        ],
        "default": {"type": "all_available"},
        "examples": [{"type": "all_available"}, {"type": "explicit", "source_ids": ["apple_health"]}]
    })
}

fn page_controls_schema() -> Value {
    json!({
        "type": "object",
        "description": "Optional per-page wire bounds. Omit for defaults. Cursors are opaque: return an exact next_cursor unchanged, or set all_pages=true on the tool.",
        "additionalProperties": false,
        "required": ["max_items", "max_bytes"],
        "properties": {
            "max_items": {"type": "integer", "minimum": 1, "maximum": 1000, "default": 250},
            "max_bytes": {"type": "integer", "minimum": 1, "maximum": 1_048_576, "default": 262_144},
            "cursor": {"type": ["string", "null"], "default": null, "description": "Opaque continuation cursor returned by Health.md; never construct or alter it."}
        },
        "default": {"max_items": 250, "max_bytes": 262_144, "cursor": null}
    })
}

fn sleep_window_schema() -> Value {
    json!({
        "type": "object",
        "description": "Optional fixed session-relative physiology window.",
        "additionalProperties": false,
        "required": ["start_offset_seconds", "duration_seconds"],
        "properties": {
            "start_offset_seconds": {"type": "number", "minimum": 0, "default": 0},
            "duration_seconds": {"type": "number", "exclusiveMinimum": 0, "maximum": 86400}
        }
    })
}

fn aggregation_array_schema() -> Value {
    json!({
        "type": "array",
        "minItems": 1,
        "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["metric_id", "kind"],
            "properties": {
                "metric_id": {"type": "string"},
                "kind": {"type": "string", "enum": ["sum", "average", "minimum", "maximum", "latest", "count", "duration_sum"]},
                "expected_unit": {"type": "string", "description": "Optional exact unit assertion from healthmd_metrics."}
            }
        }
    })
}

fn operation_schema() -> Value {
    let simple = |name: &str| {
        json!({
            "type": "object",
            "additionalProperties": false,
            "required": ["type"],
            "properties": {"type": {"type": "string", "enum": [name]}}
        })
    };
    json!({
        "type": "object",
        "description": "Fixed factual query operation. Prefer the corresponding typed MCP tool when one exists.",
        "oneOf": [
            simple("metric_series"),
            simple("workout_listing"),
            simple("source_record_listing"),
            simple("coverage"),
            {
                "type": "object", "additionalProperties": false, "required": ["type"],
                "properties": {"type": {"type": "string", "enum": ["sleep_session_listing"]}, "window": sleep_window_schema(), "include_naps": {"type": "boolean", "default": true}}
            },
            {
                "type": "object", "additionalProperties": false, "required": ["type"],
                "properties": {"type": {"type": "string", "enum": ["workout_sleep_alignment"]}, "window": sleep_window_schema(), "workout_activity": {"type": "string"}, "include_naps": {"type": "boolean", "default": false}}
            },
            {
                "type": "object", "additionalProperties": false, "required": ["type", "first", "second", "aggregations"],
                "properties": {"type": {"type": "string", "enum": ["period_comparison"]}, "first": date_range_schema(), "second": date_range_schema(), "aggregations": aggregation_array_schema()}
            },
            {
                "type": "object", "additionalProperties": false, "required": ["type", "kind"],
                "properties": {"type": {"type": "string", "enum": ["derive_packet"]}, "kind": {"type": "string", "enum": ["daily_wellness", "training", "doctor_visit"]}, "detail_ids": {"type": "array", "uniqueItems": true, "items": {"type": "string"}}}
            }
        ]
    })
}

fn query_request_schema() -> Value {
    json!({
        "type": "object",
        "description": "Complete healthmd.query_request/1. Prefer typed tools such as healthmd_sleep_sessions; use this advanced shape only when no typed tool matches.",
        "additionalProperties": false,
        "required": ["schema", "schema_version", "metrics", "dates", "operation", "page"],
        "properties": {
            "schema": {"type": "string", "enum": ["healthmd.query_request"]},
            "schema_version": {"type": "integer", "enum": [1]},
            "metrics": metric_selection_schema(),
            "sources": source_selection_schema(),
            "dates": date_selection_schema(),
            "operation": operation_schema(),
            "page": page_controls_schema()
        }
    })
}

fn tool_examples(name: &str) -> Option<Value> {
    let dates =
        json!({"type": "exact", "range": {"start_date": "2026-07-22", "end_date": "2026-07-28"}});
    let examples = match name {
        "healthmd_sleep_sessions" | "healthmd_workouts" | "healthmd_training_evidence" => {
            json!([{ "dates": dates, "all_pages": true }])
        }
        "healthmd_metric_chart" | "healthmd_coverage" => json!([{
            "dates": dates,
            "metrics": {"type": "explicit", "metric_ids": ["sleep_total"]},
            "all_pages": true
        }]),
        "healthmd_training_alignment" => {
            json!([{ "dates": dates, "include_naps": false, "all_pages": true }])
        }
        "healthmd_compare_periods" => json!([{
            "dates": {"type": "exact", "range": {"start_date": "2026-07-01", "end_date": "2026-07-14"}},
            "metrics": {"type": "explicit", "metric_ids": ["sleep_total"]},
            "first": {"start_date": "2026-07-01", "end_date": "2026-07-07"},
            "second": {"start_date": "2026-07-08", "end_date": "2026-07-14"},
            "aggregations": [{"metric_id": "sleep_total", "kind": "average", "expected_unit": "min"}],
            "all_pages": true
        }]),
        "healthmd_query" | "healthmd_evidence_packet" => json!([{
            "request": {
                "schema": "healthmd.query_request", "schema_version": 1,
                "metrics": {"type": "explicit", "metric_ids": ["sleep_total"]},
                "sources": {"type": "all_available"}, "dates": dates,
                "operation": {"type": "metric_series"},
                "page": {"max_items": 250, "max_bytes": 262_144, "cursor": null}
            },
            "all_pages": true
        }]),
        _ => return None,
    };
    Some(examples)
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
