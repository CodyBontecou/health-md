use std::{collections::BTreeSet, time::Duration};

use serde_json::{Map, Value, json};
use uuid::Uuid;

use crate::{
    QueryDetailLevel, SurfaceProfile,
    limits::{
        DEFAULT_EXPORT_TIMEOUT_SECONDS, DEFAULT_PAGE_BYTES, DEFAULT_PAGE_ITEMS, MAXIMUM_CATEGORIES,
        MAXIMUM_EXPORT_TIMEOUT_SECONDS, MAXIMUM_METRIC_IDS, MAXIMUM_PAGE_BYTES, MAXIMUM_PAGE_ITEMS,
        MINIMUM_EXPORT_TIMEOUT_SECONDS,
    },
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OperationKind {
    Readiness,
    Catalog,
    Query,
    Export,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OperationDefinition {
    pub name: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub kind: OperationKind,
    pub local_only: bool,
}

const OPERATION_DEFINITIONS: &[OperationDefinition] = &[
    OperationDefinition {
        name: "healthmd_status",
        title: "Check Health.md readiness",
        description: "Check paired foreground iPhone readiness over the authenticated direct channel.",
        kind: OperationKind::Readiness,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_doctor",
        title: "Diagnose Health.md readiness",
        description: "Diagnose local direct pairing and foreground iPhone query/export readiness with actionable next steps.",
        kind: OperationKind::Readiness,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_capabilities",
        title: "List Health.md capabilities",
        description: "List portable direct-query, evidence, export, and pagination capabilities, plus typed-tool routing guidance and a minimal sleep-query example.",
        kind: OperationKind::Catalog,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_metrics",
        title: "List Health.md metrics",
        description: "List canonical queryable metric IDs, categories, units, and availability requirements.",
        kind: OperationKind::Catalog,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_metric_chart",
        title: "Chart a health metric",
        description: "Preferred operation for factual metric-series questions. Supply dates and canonical metrics; results retain units, coverage, missingness, evidence, and limitations.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_sleep_sessions",
        title: "List sleep sessions",
        description: "Preferred operation for sleep questions. Canonical sleep metrics and lossless session detail are supplied automatically. Supports an optional fixed session-relative physiology window.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_training_alignment",
        title: "Align workouts and sleep",
        description: "Align workouts with nearest preceding and following sleep sessions using factual timing only.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_workouts",
        title: "List workouts",
        description: "List factual workout sessions for an explicit or all-available date selection.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_coverage",
        title: "Inspect health data coverage",
        description: "Inspect factual metric/date coverage and explicit missingness.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_compare_periods",
        title: "Compare health periods",
        description: "Compare two exact periods using explicit per-metric aggregation semantics.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_training_evidence",
        title: "Build training evidence",
        description: "Create a factual training evidence packet with selected workout details.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_query",
        title: "Run a typed health query",
        description: "Advanced fallback for a complete healthmd.query_request/1 when no typed operation matches.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_evidence_packet",
        title: "Build a health evidence packet",
        description: "Advanced fallback for a directly scoped factual evidence packet.",
        kind: OperationKind::Query,
        local_only: false,
    },
    OperationDefinition {
        name: "healthmd_export_files",
        title: "Export Health.md files",
        description: "After explicit user approval, run a durable connected-iPhone generated-file export into an explicit existing desktop destination.",
        kind: OperationKind::Export,
        local_only: true,
    },
    OperationDefinition {
        name: "healthmd_export_job_status",
        title: "Check export status",
        description: "Inspect a durable generated-file export job and its destination/progress receipt.",
        kind: OperationKind::Export,
        local_only: true,
    },
    OperationDefinition {
        name: "healthmd_export_job_resume",
        title: "Resume a Health.md export",
        description: "After explicit user approval, resume the exact immutable durable generated-file export job.",
        kind: OperationKind::Export,
        local_only: true,
    },
    OperationDefinition {
        name: "healthmd_export_job_cancel",
        title: "Cancel a Health.md export",
        description: "After explicit user approval, explicitly cancel a durable generated-file export job. This cannot be undone.",
        kind: OperationKind::Export,
        local_only: true,
    },
];

pub const fn definitions() -> &'static [OperationDefinition] {
    OPERATION_DEFINITIONS
}

pub fn definition(name: &str) -> Option<&'static OperationDefinition> {
    OPERATION_DEFINITIONS
        .iter()
        .find(|definition| definition.name == name)
}

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

#[derive(Clone, Debug, PartialEq)]
pub struct QueryInvocation {
    pub query: Value,
    pub detail_level: QueryDetailLevel,
    pub all_pages: bool,
}

pub fn list(profile: SurfaceProfile) -> Vec<Value> {
    let mut tools = base_operation_declarations();
    if !profile.exposes_local_exports() {
        tools.retain(|tool| {
            !tool
                .get("name")
                .and_then(Value::as_str)
                .is_some_and(|name| name.starts_with("healthmd_export_"))
        });
    }
    enrich_query_schemas(&mut tools, profile);
    enrich_common_metadata(&mut tools);
    tools
}

/// Return the fixed tool catalog or one named tool schema for offline discovery.
///
/// # Errors
///
/// Returns an error when the requested name is absent from the selected surface profile.
pub fn tool_catalog(profile: SurfaceProfile, tool_name: Option<&str>) -> Result<Value, String> {
    let tools = list(profile);
    let guidance = json!({
        "typed_tools_are_preferred": true,
        "sleep_tool": "healthmd_sleep_sessions",
        "workout_tool": "healthmd_workouts",
        "metric_series_tool": "healthmd_metric_chart",
        "note": "MCP tools and `healthmd query <operation> --arguments <JSON>` use this same registry. The shell `healthmd extract` command returns a different canonical projection."
    });
    if let Some(name) = tool_name {
        let tool = tools
            .into_iter()
            .find(|tool| tool.get("name").and_then(Value::as_str) == Some(name))
            .ok_or_else(|| format!("unknown fixed MCP tool: {name}"))?;
        return Ok(json!({
            "schema": "healthmd.mcp_tool_schema",
            "schema_version": 1,
            "guidance": guidance,
            "tool": tool
        }));
    }
    Ok(json!({
        "schema": "healthmd.mcp_tool_catalog",
        "schema_version": 1,
        "guidance": guidance,
        "tools": tools
    }))
}

fn base_operation_declarations() -> Vec<Value> {
    OPERATION_DEFINITIONS
        .iter()
        .map(|operation| {
            let mut declaration = json!({
                "name": operation.name,
                "description": operation.description,
                "inputSchema": base_input_schema(operation.name)
            });
            match operation.name {
                "healthmd_export_files" | "healthmd_export_job_resume" => {
                    declaration["_meta"] = json!({"anthropic/requiresUserInteraction": true});
                    declaration["annotations"] = mutating_annotations(false);
                }
                "healthmd_export_job_cancel" => {
                    declaration["_meta"] = json!({"anthropic/requiresUserInteraction": true});
                    declaration["annotations"] = mutating_annotations(true);
                }
                "healthmd_export_job_status" => {
                    declaration["annotations"] = json!({
                        "readOnlyHint": true,
                        "destructiveHint": false,
                        "idempotentHint": true,
                        "openWorldHint": false
                    });
                }
                _ => {}
            }
            declaration
        })
        .collect()
}

fn base_input_schema(name: &str) -> Value {
    match name {
        "healthmd_status" | "healthmd_doctor" | "healthmd_capabilities" | "healthmd_metrics" => {
            empty_schema()
        }
        "healthmd_metric_chart" | "healthmd_coverage" => {
            query_base_schema(&["dates", "metrics"], Map::new())
        }
        "healthmd_workouts" => query_base_schema(&["dates"], Map::new()),
        "healthmd_sleep_sessions" => query_base_schema(
            &["dates"],
            Map::from_iter([
                ("include_naps".to_owned(), json!({"type": "boolean"})),
                ("window".to_owned(), sleep_window_schema()),
            ]),
        ),
        "healthmd_training_alignment" => query_base_schema(
            &["dates"],
            Map::from_iter([
                ("include_naps".to_owned(), json!({"type": "boolean"})),
                ("window".to_owned(), sleep_window_schema()),
                ("workout_activity".to_owned(), json!({"type": "string"})),
            ]),
        ),
        "healthmd_compare_periods" => query_base_schema(
            &["dates", "metrics", "first", "second", "aggregations"],
            Map::from_iter([
                ("first".to_owned(), date_range_schema()),
                ("second".to_owned(), date_range_schema()),
                ("aggregations".to_owned(), aggregation_array_schema()),
            ]),
        ),
        "healthmd_training_evidence" => query_base_schema(
            &["dates"],
            Map::from_iter([("detail_ids".to_owned(), detail_ids_schema())]),
        ),
        "healthmd_query" | "healthmd_evidence_packet" => json!({
            "type": "object",
            "additionalProperties": false,
            "required": ["request"],
            "properties": {
                "request": {"type": "object", "description": "Versioned Health.md request object"},
                "detail_level": {"type": "string", "enum": ["summary", "lossless"]},
                "all_pages": {"type": "boolean"}
            }
        }),
        "healthmd_export_files" => export_files_schema(),
        "healthmd_export_job_status" | "healthmd_export_job_cancel" => job_schema(false),
        "healthmd_export_job_resume" => job_schema(true),
        _ => empty_schema(),
    }
}

fn empty_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": [],
        "properties": {}
    })
}

fn query_base_schema(required: &[&str], extras: Map<String, Value>) -> Value {
    let mut properties = Map::from_iter([
        (
            "all_pages".to_owned(),
            json!({
                "type": "boolean",
                "description": "Traverse opaque cursors within bounded aggregate limits and return healthmd.mcp_query_pages/1"
            }),
        ),
        ("dates".to_owned(), json!({"type": "object"})),
        (
            "detail_level".to_owned(),
            json!({"type": "string", "enum": ["summary", "lossless"]}),
        ),
        ("metrics".to_owned(), json!({"type": "object"})),
        ("page".to_owned(), json!({"type": "object"})),
        ("sources".to_owned(), json!({"type": "object"})),
    ]);
    properties.extend(extras);
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": required,
        "properties": properties
    })
}

fn export_files_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["date_selection", "destination"],
        "properties": {
            "date_selection": {"type": "string", "enum": ["explicit_range", "all_available"]},
            "date_range": {
                "type": "object", "additionalProperties": false, "required": ["start", "end"],
                "properties": {
                    "start": {"type": "string", "description": "Inclusive yyyy-MM-dd start date"},
                    "end": {"type": "string", "description": "Inclusive yyyy-MM-dd end date"}
                }
            },
            "settings_policy": {"type": "string", "enum": ["requested_dates_only", "current_iphone_settings"]},
            "metric_ids": {"type": "array", "maxItems": MAXIMUM_METRIC_IDS, "uniqueItems": true, "items": {"type": "string"}},
            "categories": {"type": "array", "maxItems": MAXIMUM_CATEGORIES, "uniqueItems": true, "items": {"type": "string"}},
            "all_metrics": {"type": "boolean"},
            "detail_level": {"type": "string", "enum": ["summary", "lossless"]},
            "wait_timeout_seconds": {"type": "number", "minimum": MINIMUM_EXPORT_TIMEOUT_SECONDS, "maximum": MAXIMUM_EXPORT_TIMEOUT_SECONDS},
            "destination": {"type": "string", "description": "Existing absolute destination directory. It is validated and bound durably before transfer."}
        }
    })
}

fn job_schema(allow_timeout: bool) -> Value {
    let mut properties = Map::from_iter([("job_id".to_owned(), json!({"type": "string"}))]);
    if allow_timeout {
        properties.insert(
            "wait_timeout_seconds".to_owned(),
            json!({"type": "number", "minimum": MINIMUM_EXPORT_TIMEOUT_SECONDS, "maximum": MAXIMUM_EXPORT_TIMEOUT_SECONDS}),
        );
    }
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["job_id"],
        "properties": properties
    })
}

fn mutating_annotations(idempotent: bool) -> Value {
    json!({
        "readOnlyHint": false,
        "destructiveHint": true,
        "idempotentHint": idempotent,
        "openWorldHint": false
    })
}

fn enrich_common_metadata(tools: &mut [Value]) {
    for tool in tools {
        let Some(object) = tool.as_object_mut() else {
            continue;
        };
        let Some(operation) = object
            .get("name")
            .and_then(Value::as_str)
            .and_then(definition)
        else {
            continue;
        };
        object.insert(
            "title".to_owned(),
            Value::String(operation.title.to_owned()),
        );
        if operation.kind != OperationKind::Export {
            object.insert(
                "annotations".to_owned(),
                json!({
                    "readOnlyHint": true,
                    "destructiveHint": false,
                    "idempotentHint": true,
                    "openWorldHint": false
                }),
            );
        }
    }
}

fn enrich_query_schemas(tools: &mut [Value], profile: SurfaceProfile) {
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
            properties.insert("sources".to_owned(), source_selection_schema(profile));
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
            properties.insert("request".to_owned(), query_request_schema(profile));
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
                    "metric_ids": {"type": "array", "minItems": 1, "maxItems": MAXIMUM_METRIC_IDS, "uniqueItems": true, "items": {"type": "string"}}
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

fn source_selection_schema(profile: SurfaceProfile) -> Value {
    let (description, source_ids, maximum_providers) = if profile == SurfaceProfile::Hosted {
        (
            "Usually omit this field or use all_available. Hosted corpora can be filtered by stable source IDs and authorized provider IDs.",
            json!({"type": "string", "enum": ["apple_health", "healthmd_summary", "provider_native", "healthmd_diagnostics"]}),
            64,
        )
    } else {
        (
            "Usually omit this field or use all_available. The direct iPhone path supports apple_health and healthmd_summary; provider IDs are unavailable.",
            json!({"type": "string", "enum": ["apple_health", "healthmd_summary"]}),
            0,
        )
    };
    json!({
        "type": "object",
        "description": description,
        "oneOf": [
            {
                "type": "object",
                "additionalProperties": false,
                "required": ["type", "source_ids"],
                "properties": {
                    "type": {"type": "string", "enum": ["explicit"]},
                    "source_ids": {"type": "array", "minItems": 1, "uniqueItems": true, "items": source_ids},
                    "provider_ids": {"type": "array", "maxItems": maximum_providers, "uniqueItems": true, "items": {"type": "string", "minLength": 1, "maxLength": 128}}
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
            "max_items": {"type": "integer", "minimum": 1, "maximum": MAXIMUM_PAGE_ITEMS, "default": DEFAULT_PAGE_ITEMS},
            "max_bytes": {"type": "integer", "minimum": 1, "maximum": MAXIMUM_PAGE_BYTES, "default": DEFAULT_PAGE_BYTES},
            "cursor": {"type": ["string", "null"], "default": null, "description": "Opaque continuation cursor returned by Health.md; never construct or alter it."}
        },
        "default": {"max_items": DEFAULT_PAGE_ITEMS, "max_bytes": DEFAULT_PAGE_BYTES, "cursor": null}
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

fn detail_ids_schema() -> Value {
    json!({
        "type": "array",
        "maxItems": 128,
        "uniqueItems": true,
        "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 128,
            "pattern": "^[A-Za-z0-9_.-]+$"
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
                "properties": {"type": {"type": "string", "enum": ["derive_packet"]}, "kind": {"type": "string", "enum": ["daily_wellness", "training", "doctor_visit"]}, "detail_ids": detail_ids_schema()}
            }
        ]
    })
}

fn query_request_schema(profile: SurfaceProfile) -> Value {
    json!({
        "type": "object",
        "description": "Complete healthmd.query_request/1. Prefer typed tools such as healthmd_sleep_sessions; use this advanced shape only when no typed tool matches.",
        "additionalProperties": false,
        "required": ["schema", "schema_version", "metrics", "dates", "operation", "page"],
        "properties": {
            "schema": {"type": "string", "enum": ["healthmd.query_request"]},
            "schema_version": {"type": "integer", "enum": [1]},
            "metrics": metric_selection_schema(),
            "sources": source_selection_schema(profile),
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
                "page": {"max_items": DEFAULT_PAGE_ITEMS, "max_bytes": DEFAULT_PAGE_BYTES, "cursor": null}
            },
            "all_pages": true
        }]),
        _ => return None,
    };
    Some(examples)
}

/// Normalize one fixed typed operation into the canonical query request used by every adapter.
///
/// # Errors
///
/// Fails for unknown operations, unknown keys, missing required fields, or invalid detail values.
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
        "summary" => QueryDetailLevel::Summary,
        "lossless" => QueryDetailLevel::Lossless,
        _ => return Err("invalid detail level"),
    };
    Ok(QueryInvocation {
        query,
        detail_level,
        all_pages,
    })
}

/// Normalize a durable-job identifier and optional bounded wait timeout.
///
/// # Errors
///
/// Fails for unknown fields, malformed UUIDs, or a timeout outside the shared bounds.
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
            .unwrap_or_else(|| Duration::from_secs(DEFAULT_EXPORT_TIMEOUT_SECONDS).as_secs_f64());
        if !seconds.is_finite() || seconds <= 0.0 {
            return Err("invalid wait_timeout_seconds");
        }
        let timeout = Duration::from_secs_f64(seconds);
        if !(Duration::from_secs(MINIMUM_EXPORT_TIMEOUT_SECONDS)
            ..=Duration::from_secs(MAXIMUM_EXPORT_TIMEOUT_SECONDS))
            .contains(&timeout)
        {
            return Err("invalid wait_timeout_seconds");
        }
        timeout
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
        .unwrap_or_else(|| json!({"max_items": DEFAULT_PAGE_ITEMS, "max_bytes": DEFAULT_PAGE_BYTES, "cursor": null}));
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

fn number(value: &Value) -> Result<f64, &'static str> {
    value.as_f64().ok_or("expected number")
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert_eq!(invocation.detail_level, QueryDetailLevel::Lossless);
        let metrics = invocation.query["metrics"]["metric_ids"]
            .as_array()
            .unwrap();
        assert!(metrics.contains(&Value::String("sleep_total".to_owned())));
        assert!(metrics.contains(&Value::String("heart_rate".to_owned())));
    }

    #[test]
    fn hosted_catalog_advertises_provider_filters_without_changing_direct_contract() {
        let hosted = list(SurfaceProfile::Hosted);
        let direct = list(SurfaceProfile::RemoteReadOnly);
        let hosted_query = hosted
            .iter()
            .find(|tool| tool["name"] == "healthmd_metric_chart")
            .unwrap();
        let direct_query = direct
            .iter()
            .find(|tool| tool["name"] == "healthmd_metric_chart")
            .unwrap();
        assert_eq!(
            hosted_query.pointer(
                "/inputSchema/properties/sources/oneOf/0/properties/provider_ids/maxItems"
            ),
            Some(&json!(64))
        );
        assert_eq!(
            direct_query.pointer(
                "/inputSchema/properties/sources/oneOf/0/properties/provider_ids/maxItems"
            ),
            Some(&json!(0))
        );
    }

    #[test]
    fn remote_catalog_is_read_only_and_excludes_local_exports() {
        let tools = list(SurfaceProfile::RemoteReadOnly);
        assert_eq!(tools.len(), 13);
        assert!(tools.iter().all(|tool| {
            tool.pointer("/annotations/readOnlyHint") == Some(&Value::Bool(true))
                && tool.get("title").and_then(Value::as_str).is_some()
                && !tool["name"]
                    .as_str()
                    .is_some_and(|name| name.starts_with("healthmd_export_"))
        }));
    }
}
