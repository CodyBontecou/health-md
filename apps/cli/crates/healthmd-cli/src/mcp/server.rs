use std::{
    collections::HashSet,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use healthmd_client::{
    ClientError,
    direct::{DirectClient, SourceStatus, StatusResult},
    file_receiver::FileReceiptPayload,
    job::{JobRecord, JobState},
};
use healthmd_protocol::models::ResponseMode;
use serde_json::{Value, json};
use tokio::sync::{Mutex, watch};
use uuid::Uuid;

use super::{app, chart, tools};

const PROTOCOLS: &[&str] = &["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"];
const MAX_TRAVERSAL_BYTES: usize = 2 * 1_024 * 1_024;
const MAX_TRAVERSAL_PAGES: usize = 4_096;

#[derive(Clone, Copy)]
pub struct Configuration {
    pub device_id: Option<Uuid>,
    pub port: u16,
    pub timeout: Duration,
}

pub struct Server {
    client: Arc<DirectClient>,
    configuration: Configuration,
    ui_enabled: AtomicBool,
    direct_gate: Mutex<()>,
}

impl Server {
    pub fn new(client: DirectClient, configuration: Configuration) -> Self {
        Self {
            client: Arc::new(client),
            configuration,
            ui_enabled: AtomicBool::new(false),
            direct_gate: Mutex::new(()),
        }
    }

    pub async fn handle(
        &self,
        line: &str,
        mut cancellation: watch::Receiver<bool>,
    ) -> Option<String> {
        let request: Value = match serde_json::from_str(line) {
            Ok(value) => value,
            Err(_) => return Some(response_error(Value::Null, -32700, "Parse error")),
        };
        let Some(object) = request.as_object() else {
            return Some(response_error(Value::Null, -32600, "Invalid request"));
        };
        if object.get("jsonrpc").and_then(Value::as_str) != Some("2.0") {
            return Some(response_error(Value::Null, -32600, "Invalid request"));
        }
        let method = object.get("method").and_then(Value::as_str)?;
        let id = object.get("id").cloned()?;
        let params = object.get("params").cloned().unwrap_or_else(|| json!({}));
        let result = match method {
            "initialize" => self.initialize(&params),
            "ping" => Ok(json!({})),
            "tools/list" => Ok(json!({"tools": tools::list(self.ui_enabled())})),
            "resources/list" if self.ui_enabled() => {
                Ok(json!({"resources": [app::resource_declaration()]}))
            }
            "resources/read" if self.ui_enabled() => {
                if params.get("uri").and_then(Value::as_str) == Some(app::RESOURCE_URI) {
                    Ok(json!({"contents": [app::resource_content()]}))
                } else {
                    Err((-32602, "Unknown resource URI"))
                }
            }
            "tools/call" => self.call_tool(&params, &mut cancellation).await,
            _ => Err((-32601, "Method not found")),
        };
        Some(match result {
            Ok(result) => response_success(id, result),
            Err((code, message)) => response_error(id, code, message),
        })
    }

    fn initialize(&self, params: &Value) -> Result<Value, (i64, &'static str)> {
        let version = params
            .get("protocolVersion")
            .and_then(Value::as_str)
            .ok_or((-32602, "Unsupported MCP protocol version"))?;
        if !PROTOCOLS.contains(&version) {
            return Err((-32602, "Unsupported MCP protocol version"));
        }
        let ui = params
            .get("capabilities")
            .and_then(|v| v.get("extensions"))
            .and_then(|v| v.get(app::EXTENSION_ID))
            .and_then(|v| v.get("mimeTypes"))
            .and_then(Value::as_array)
            .is_some_and(|values| {
                values
                    .iter()
                    .any(|value| value.as_str() == Some(app::MIME_TYPE))
            });
        self.ui_enabled.store(ui, Ordering::Release);
        let mut capabilities = json!({"tools": {"listChanged": false}});
        if ui {
            capabilities["resources"] = json!({"subscribe": false, "listChanged": false});
            capabilities["extensions"] =
                json!({app::EXTENSION_ID: {"mimeTypes": [app::MIME_TYPE]}});
        }
        Ok(json!({
            "protocolVersion": version,
            "capabilities": capabilities,
            "serverInfo": {"name": "healthmd-mcp", "version": env!("CARGO_PKG_VERSION")},
            "instructions": "Run `healthmd setup codex` once, keep Health.md foreground on iPhone, and call healthmd_doctor before querying. Use fixed typed tools directly: healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Their input schemas include complete nested selectors and examples; do not invoke shell CLI help or healthmd extract to discover typed query shapes. Queries and exports use only the authenticated direct iPhone channel; no Health.md Mac app is required."
        }))
    }

    async fn call_tool(
        &self,
        params: &Value,
        cancellation: &mut watch::Receiver<bool>,
    ) -> Result<Value, (i64, &'static str)> {
        let name = params
            .get("name")
            .and_then(Value::as_str)
            .ok_or((-32602, "Unknown tool"))?;
        let arguments = params
            .get("arguments")
            .cloned()
            .unwrap_or_else(|| json!({}));
        if !tools::list(false)
            .iter()
            .any(|tool| tool.get("name").and_then(Value::as_str) == Some(name))
        {
            return Err((-32602, "Unknown tool"));
        }
        if matches!(
            name,
            "healthmd_status" | "healthmd_doctor" | "healthmd_capabilities" | "healthmd_metrics"
        ) && arguments
            .as_object()
            .is_none_or(|object| !object.is_empty())
        {
            return Err((-32602, "Invalid tool arguments"));
        }
        match name {
            "healthmd_status" => Ok(self.live_status(cancellation).await),
            "healthmd_doctor" => Ok(self.doctor(cancellation).await),
            "healthmd_capabilities" => Ok(tool_result(capabilities(), false, None, Vec::new())),
            "healthmd_metrics" => Ok(tool_result(metric_catalog(), false, None, Vec::new())),
            "healthmd_export_files" => self.export_files(&arguments, cancellation).await,
            "healthmd_export_job_status" => self.export_status(&arguments),
            "healthmd_export_job_resume" => self.export_resume(&arguments, cancellation).await,
            "healthmd_export_job_cancel" => self.export_cancel(&arguments, cancellation).await,
            _ => self.query(name, &arguments, cancellation).await,
        }
    }

    async fn live_status(&self, cancellation: &mut watch::Receiver<bool>) -> Value {
        let operation = async {
            let _gate = self.direct_gate.lock().await;
            self.client
                .status(
                    self.configuration.device_id,
                    self.configuration.port,
                    self.configuration.timeout,
                )
                .await
        };
        tokio::select! {
            result = operation => match result {
                Ok(result) => tool_result(status_value(&result), false, None, Vec::new()),
                Err(error) => tool_result(safe_error(&error, None), true, None, Vec::new()),
            },
            () = cancelled(cancellation) => tool_result(cancelled_value(None), true, None, Vec::new()),
        }
    }

    async fn doctor(&self, cancellation: &mut watch::Receiver<bool>) -> Value {
        let devices = match self.client.paired_devices().await {
            Ok(devices) => devices,
            Err(error) => return tool_result(safe_error(&error, None), true, None, Vec::new()),
        };
        if devices.is_empty() {
            return tool_result(
                json!({
                    "schema": "healthmd.direct_readiness", "schema_version": 1,
                    "status": "not_paired", "ready": false,
                    "message": "Run `healthmd setup codex`, then approve the QR pairing in the foreground Health.md iPhone app."
                }),
                false,
                None,
                Vec::new(),
            );
        }
        self.live_status(cancellation).await
    }

    async fn query(
        &self,
        name: &str,
        arguments: &Value,
        cancellation: &mut watch::Receiver<bool>,
    ) -> Result<Value, (i64, &'static str)> {
        let invocation = tools::query_invocation(name, arguments)
            .map_err(|_| (-32602, "Invalid tool arguments"))?;
        let operation = self.query_pages(invocation);
        let value = tokio::select! {
            result = operation => match result {
                Ok(value) => value,
                Err(error) => return Ok(tool_result(safe_error(&error, None), true, None, Vec::new())),
            },
            () = cancelled(cancellation) => return Ok(tool_result(cancelled_value(None), true, None, Vec::new())),
        };
        let structured = if self.ui_enabled() && valid_query_result(&value) {
            Some(value.clone())
        } else {
            None
        };
        let additional = if !self.ui_enabled() && name == "healthmd_metric_chart" {
            chart::render(&value).map(|png| json!({"type":"image","data":BASE64_STANDARD.encode(png),"mimeType":"image/png"})).into_iter().collect()
        } else {
            Vec::new()
        };
        Ok(tool_result(value, false, structured, additional))
    }

    async fn query_pages(
        &self,
        mut invocation: tools::QueryInvocation,
    ) -> Result<Value, ClientError> {
        let _gate = self.direct_gate.lock().await;
        let mut pages = Vec::new();
        let mut seen = HashSet::new();
        let mut bytes = 0_usize;
        let mut traversal_complete = true;
        let mut continuation_cursor = None;
        let mut limit_reason = None;
        let page_budget = MAX_TRAVERSAL_BYTES.saturating_sub(16_384);
        loop {
            if invocation.all_pages && pages.len() >= MAX_TRAVERSAL_PAGES {
                traversal_complete = false;
                continuation_cursor = invocation
                    .request
                    .query
                    .pointer("/page/cursor")
                    .and_then(Value::as_str)
                    .map(str::to_owned);
                limit_reason = Some("maximum_pages");
                break;
            }
            let requested_cursor = invocation
                .request
                .query
                .pointer("/page/cursor")
                .and_then(Value::as_str)
                .map(str::to_owned);
            let result = self
                .client
                .query(
                    invocation.request.clone(),
                    self.configuration.device_id,
                    self.configuration.port,
                    self.configuration.timeout,
                )
                .await?;
            let page_bytes = serde_json::to_vec(&result.response)
                .map_err(|_| ClientError::MalformedPacket)?
                .len();
            if bytes.saturating_add(page_bytes) > page_budget {
                if !invocation.all_pages || pages.is_empty() {
                    return Err(ClientError::FrameTooLarge);
                }
                traversal_complete = false;
                continuation_cursor = requested_cursor;
                limit_reason = Some("maximum_aggregate_bytes");
                break;
            }
            bytes += page_bytes;
            let cursor = result
                .response
                .get("next_cursor")
                .and_then(Value::as_str)
                .map(str::to_owned);
            pages.push(result.response);
            if !invocation.all_pages || cursor.is_none() {
                break;
            }
            let cursor = cursor.expect("checked");
            if !seen.insert(cursor.clone()) {
                return Err(ClientError::MalformedPacket);
            }
            invocation.request.request_id = healthmd_protocol::encoding::SwiftUuid(Uuid::new_v4());
            invocation.request.query["page"]["cursor"] = Value::String(cursor);
        }
        if invocation.all_pages {
            let item_count: usize = pages
                .iter()
                .filter_map(|page| page.get("items").and_then(Value::as_array))
                .map(Vec::len)
                .sum();
            let packet_fact_count: usize = pages
                .iter()
                .filter_map(|page| page.pointer("/packet/facts").and_then(Value::as_array))
                .map(Vec::len)
                .sum();
            Ok(
                json!({"schema":"healthmd.mcp_query_pages","schema_version":1,"pages":pages,"receipt":{"page_count":pages.len(),"item_count":item_count,"packet_fact_count":packet_fact_count,"traversal_complete":traversal_complete,"next_cursor":continuation_cursor,"limit_reason":limit_reason}}),
            )
        } else {
            Ok(pages.into_iter().next().expect("one page"))
        }
    }

    fn ui_enabled(&self) -> bool {
        self.ui_enabled.load(Ordering::Acquire)
    }
}

impl Server {
    async fn export_files(
        &self,
        arguments: &Value,
        cancellation: &mut watch::Receiver<bool>,
    ) -> Result<Value, (i64, &'static str)> {
        let invocation =
            tools::export_invocation(arguments).map_err(|_| (-32602, "Invalid tool arguments"))?;
        let job_id = invocation.request.job_id.0;
        let operation = async {
            let _gate = self.direct_gate.lock().await;
            self.client
                .export_files(
                    invocation.request,
                    self.configuration.device_id,
                    self.configuration.port,
                    invocation.timeout,
                )
                .await
        };
        let response = tokio::select! {
            result = operation => match result {
                Ok(result) => export_success(&result.receipt.payload),
                Err(error) => export_error(&error, job_id),
            },
            () = cancelled(cancellation) => cancelled_value(Some(job_id)),
        };
        let is_error = response.get("error").is_some()
            || response
                .get("status")
                .and_then(Value::as_str)
                .is_none_or(|status| {
                    !matches!(
                        status,
                        "success" | "partial_success" | "accepted" | "preparing"
                    )
                });
        Ok(self.export_tool_result("healthmd_export_files", response, is_error))
    }

    fn export_status(&self, arguments: &Value) -> Result<Value, (i64, &'static str)> {
        let (job_id, _) =
            tools::job_id(arguments, false).map_err(|_| (-32602, "Invalid tool arguments"))?;
        let response = match self.client.job_record(job_id) {
            Ok(record) => job_receipt(&record),
            Err(error) => export_error(&error, job_id),
        };
        let is_error = matches!(
            response.get("status").and_then(Value::as_str),
            Some("failure" | "unavailable")
        );
        Ok(self.export_tool_result("healthmd_export_job_status", response, is_error))
    }

    async fn export_resume(
        &self,
        arguments: &Value,
        cancellation: &mut watch::Receiver<bool>,
    ) -> Result<Value, (i64, &'static str)> {
        let (job_id, timeout) =
            tools::job_id(arguments, true).map_err(|_| (-32602, "Invalid tool arguments"))?;
        if self
            .client
            .job_record(job_id)
            .is_ok_and(|record| record.request.response_mode != ResponseMode::WriteFiles)
        {
            return Ok(self.export_tool_result("healthmd_export_job_resume", json!({
                "job_id": job_id, "status": "failure", "message": "This durable job is not a generated-file export."
            }), true));
        }
        let operation = async {
            let _gate = self.direct_gate.lock().await;
            self.client
                .resume_files(
                    job_id,
                    self.configuration.device_id,
                    self.configuration.port,
                    timeout,
                )
                .await
        };
        let response = tokio::select! {
            result = operation => match result {
                Ok(result) => export_success(&result.receipt.payload),
                Err(error) => export_error(&error, job_id),
            },
            () = cancelled(cancellation) => cancelled_value(Some(job_id)),
        };
        let is_error = !matches!(
            response.get("status").and_then(Value::as_str),
            Some("success" | "partial_success")
        );
        Ok(self.export_tool_result("healthmd_export_job_resume", response, is_error))
    }

    async fn export_cancel(
        &self,
        arguments: &Value,
        cancellation: &mut watch::Receiver<bool>,
    ) -> Result<Value, (i64, &'static str)> {
        let (job_id, _) =
            tools::job_id(arguments, false).map_err(|_| (-32602, "Invalid tool arguments"))?;
        // Cancellation must bypass the long-running direct-operation gate. `cancel_job` persists
        // the marker first; the active transfer observes it on its existing authenticated channel.
        let operation = async {
            self.client
                .cancel_job(
                    job_id,
                    self.configuration.device_id,
                    self.configuration.port,
                    self.configuration.timeout,
                )
                .await
        };
        let response = tokio::select! {
            result = operation => match result {
                Ok(()) => json!({"job_id":job_id,"status":"cancelled","message":"The durable direct iPhone export was cancelled."}),
                Err(error) => export_error(&error, job_id),
            },
            () = cancelled(cancellation) => cancelled_value(Some(job_id)),
        };
        let is_error = response.get("error").and_then(Value::as_str)
            == Some("healthmd_request_cancelled")
            || !matches!(
                response.get("status").and_then(Value::as_str),
                Some("cancelled" | "accepted")
            );
        Ok(self.export_tool_result("healthmd_export_job_cancel", response, is_error))
    }

    fn export_tool_result(&self, operation: &str, response: Value, is_error: bool) -> Value {
        let structured = if self.ui_enabled() && valid_export_receipt(&response) {
            Some(
                json!({"schema":"healthmd.mcp_export_result","schema_version":1,"operation":operation,"response":response}),
            )
        } else {
            None
        };
        tool_result(response, is_error, structured, Vec::new())
    }
}

fn export_success(payload: &FileReceiptPayload) -> Value {
    const MAXIMUM_RECEIPT_PATHS: usize = 256;
    let paths: Vec<&String> = payload
        .relative_paths
        .iter()
        .take(MAXIMUM_RECEIPT_PATHS)
        .collect();
    let failed_dates: Vec<&String> = payload
        .failed_date_identifiers
        .iter()
        .take(MAXIMUM_RECEIPT_PATHS)
        .collect();
    json!({
        "job_id": payload.job_id,
        "status": payload.status,
        "message": "Health.md generated and verified the requested files from the iPhone.",
        "destination_path": payload.destination_path,
        "files_written": payload.files_written,
        "total_bytes": payload.total_bytes,
        "relative_paths": paths,
        "relative_path_count": payload.relative_paths.len(),
        "relative_paths_truncated": payload.relative_paths.len() > MAXIMUM_RECEIPT_PATHS,
        "success_count": payload.success_count,
        "total_count": payload.total_count,
        "failed_date_identifiers": failed_dates,
        "failed_date_identifier_count": payload.failed_date_identifiers.len(),
        "failed_date_identifiers_truncated": payload.failed_date_identifiers.len() > MAXIMUM_RECEIPT_PATHS
    })
}

fn job_receipt(record: &JobRecord) -> Value {
    let status = match record.state {
        JobState::Queued
        | JobState::Connecting
        | JobState::Sent
        | JobState::Accepted
        | JobState::Preparing
        | JobState::Transferring
        | JobState::AwaitingPeerAcknowledgement => "preparing",
        JobState::Paused => "timed_out",
        JobState::CancellationPending => "accepted",
        JobState::Completed => "success",
        JobState::Failed => "failure",
        JobState::Cancelled => "cancelled",
    };
    let message = match record.state {
        JobState::Paused => "The direct transfer paused and can be resumed.",
        JobState::Completed => "The durable direct iPhone export completed.",
        JobState::Failed => "The durable direct iPhone export failed.",
        JobState::Cancelled => "The durable direct iPhone export was cancelled.",
        _ => "The durable direct iPhone export has not reached a terminal state.",
    };
    let mut value = json!({
        "job_id": record.request.job_id,
        "status": status,
        "message": message,
        "state": record.state,
        "created_at": record.created_at,
        "updated_at": record.updated_at,
        "expires_at": record.expires_at,
        "processed_days": record.processed_days,
        "total_days": record.total_days,
        "committed_partitions": record.committed_partitions,
        "committed_bytes": record.committed_bytes
    });
    if let Some(destination) = &record.request.destination {
        value["destination_path"] = Value::String(destination.root_path.clone());
    }
    value
}

fn export_error(error: &ClientError, job_id: Uuid) -> Value {
    let mut value = safe_error(error, Some(job_id));
    let object = value.as_object_mut().expect("error object");
    object.insert("job_id".to_owned(), json!(job_id));
    object.insert(
        "status".to_owned(),
        Value::String(
            match error {
                ClientError::ExportPaused(_) => "timed_out",
                ClientError::CancellationPending(_) => "accepted",
                ClientError::JobExpired | ClientError::JobNotResumable(_, _) => "unavailable",
                _ => "failure",
            }
            .to_owned(),
        ),
    );
    object.insert("message".to_owned(), Value::String(match error {
        ClientError::ExportPaused(_) => "The durable transfer paused and can be resumed with this job ID.",
        ClientError::CancellationPending(_) => "Cancellation is durably pending and the active transfer will deliver it on its authenticated channel.",
        _ => "The direct iPhone export did not complete. Inspect this job ID before retrying a mutation.",
    }.to_owned()));
    value
}

fn cancelled_value(job_id: Option<Uuid>) -> Value {
    let mut value = json!({
        "error": "healthmd_request_cancelled",
        "status": if job_id.is_some() { "accepted" } else { "cancelled" },
        "operation_outcome": if job_id.is_some() { "unknown" } else { "cancelled" },
        "message": if job_id.is_some() {
            "The MCP waiter detached. The durable export may still be active; inspect this job ID before retrying."
        } else {
            "The transient direct query waiter was cancelled."
        }
    });
    if let Some(job_id) = job_id {
        value["job_id"] = json!(job_id);
    }
    value
}

fn valid_export_receipt(value: &Value) -> bool {
    value
        .get("job_id")
        .and_then(Value::as_str)
        .and_then(|id| Uuid::parse_str(id).ok())
        .is_some()
        && value.get("message").and_then(Value::as_str).is_some()
        && value
            .get("status")
            .and_then(Value::as_str)
            .is_some_and(|status| {
                matches!(
                    status,
                    "accepted"
                        | "preparing"
                        | "success"
                        | "partial_success"
                        | "failure"
                        | "cancelled"
                        | "unavailable"
                        | "timed_out"
                )
            })
}

fn status_value(result: &StatusResult) -> Value {
    let query = result.peer_capabilities.query.as_ref();
    match &result.status {
        SourceStatus::Ios(source) => {
            let ready = source.app_active
                && source.protected_data_available
                && source.can_trigger_queries.unwrap_or(false);
            json!({
                "schema": "healthmd.direct_readiness", "schema_version": 1,
                "status": if ready { "ready" } else { "unavailable" },
                "ready": ready,
                "message": if ready { "The authenticated direct iPhone query service is ready." } else { "The iPhone direct service is not ready. Keep Health.md foreground with Direct CLI Access enabled." },
                "device_name": source.name,
                "application_protocol_version": result.application_protocol_version,
                "port": result.port,
                "app_active": source.app_active,
                "protected_data_available": source.protected_data_available,
                "export_in_progress": source.export_in_progress,
                "query_in_progress": source.query_in_progress,
                "can_trigger_file_exports": source.can_trigger_file_exports,
                "can_trigger_queries": source.can_trigger_queries,
                "active_job_id": source.active_job_id,
                "active_query_request_id": source.active_query_request_id,
                "query_capabilities": query
            })
        }
        SourceStatus::Android(_) => json!({
            "schema":"healthmd.direct_readiness","schema_version":1,"status":"query_unsupported","ready":false,
            "message":"This paired source does not support the direct iPhone query protocol.",
            "application_protocol_version":result.application_protocol_version,"port":result.port
        }),
    }
}

fn capabilities() -> Value {
    json!({
        "schema": "healthmd.mcp_capabilities",
        "schema_version": 1,
        "transport": "authenticated_encrypted_iphone_direct",
        "requires_mac_app": false,
        "iphone_must_be_foreground": true,
        "direct_port": 17647,
        "operations": ["readiness","metric_catalog","bounded_query","metric_series","sleep_sessions","workout_listing","period_comparison","coverage","evidence","generated_file_export","durable_export_status","durable_export_resume","durable_export_cancel"],
        "query_tool_guidance": {
            "typed_tools_are_preferred": true,
            "sleep": "healthmd_sleep_sessions",
            "workouts": "healthmd_workouts",
            "metric_series": "healthmd_metric_chart",
            "coverage": "healthmd_coverage",
            "advanced_fallback": "healthmd_query",
            "schema_command": "healthmd mcp schema <tool-name>",
            "shell_extract_is_not_typed_query": true,
            "minimal_sleep_arguments": {
                "dates": {"type": "exact", "range": {"start_date": "2026-07-22", "end_date": "2026-07-28"}},
                "all_pages": true
            },
            "example_dates_are_illustrative": true
        },
        "query_limits": {"maximum_days_per_request":366_000,"maximum_compact_context_bytes":67_108_864,"maximum_metric_ids":512,"maximum_page_items":1000,"maximum_page_bytes":1_048_576,"all_available_is_logically_unbounded":true},
        "result_fallbacks": ["authoritative_json","text","png_metric_chart","mcp_app_html"]
    })
}

fn metric_catalog() -> Value {
    let registry: Value =
        serde_json::from_str(include_str!("../../assets/metric-registry-v1.json"))
            .expect("embedded metric registry");
    let metrics: Vec<Value> = registry
        .get("metrics")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|metric| metric.pointer("/apple/status").and_then(Value::as_str) == Some("backed"))
        .map(|metric| {
            let apple = metric.get("apple").unwrap_or(&Value::Null);
            json!({
                "metric_id": metric.get("semantic_id"),
                "display_name": metric.get("reference_name"),
                "category": apple.get("category_id"),
                "unit": apple.get("unit"),
                "default_enabled": apple.get("default_enabled"),
                "status": apple.get("status"),
                "availability_key": apple.get("availability_key")
            })
        })
        .collect();
    json!({"schema":"healthmd.metric_catalog","schema_version":1,"registry_version":registry.get("registry_version"),"metrics":metrics})
}

fn safe_error(error: &ClientError, job_id: Option<Uuid>) -> Value {
    let (code, message) = match error {
        ClientError::DeviceSelectionRequired(devices) if devices.is_empty() => (
            "healthmd_not_paired",
            "No iPhone is paired. Run `healthmd setup codex`.",
        ),
        ClientError::DeviceSelectionRequired(_) => (
            "healthmd_device_ambiguous",
            "More than one iPhone is paired. Configure a device ID.",
        ),
        ClientError::DeviceNotPaired(_) => (
            "healthmd_not_paired",
            "The requested iPhone is not paired. Run `healthmd setup codex` or select a trusted device.",
        ),
        ClientError::QueryUnsupported => (
            "healthmd_query_unsupported",
            "The paired iPhone does not advertise direct query support.",
        ),
        ClientError::QueryRejected { .. } => (
            "healthmd_query_rejected",
            "The iPhone rejected the bounded query. Check dates, metrics, and readiness.",
        ),
        ClientError::ExportPaused(_) => (
            "healthmd_export_paused",
            "The durable export paused and may be resumed.",
        ),
        ClientError::CancellationPending(_) => (
            "healthmd_cancellation_pending",
            "Cancellation is durably pending delivery to the paired iPhone.",
        ),
        ClientError::JobNotFound => ("healthmd_job_not_found", "The durable job was not found."),
        ClientError::JobExpired => ("healthmd_job_expired", "The durable job expired."),
        ClientError::JobNotResumable(_, _) => (
            "healthmd_job_terminal",
            "The durable job cannot be resumed from its current state.",
        ),
        ClientError::TimedOut => ("healthmd_timeout", "The direct iPhone operation timed out."),
        ClientError::FrameTooLarge => (
            "healthmd_response_too_large",
            "The direct response exceeded a bounded MCP or protocol limit.",
        ),
        ClientError::MalformedPacket
        | ClientError::UnexpectedMessage
        | ClientError::ReplayedPacket => (
            "healthmd_protocol_error",
            "The authenticated peer returned an invalid protocol response.",
        ),
        ClientError::InvalidTransfer(_) | ClientError::InvalidJob => (
            "healthmd_integrity_error",
            "The durable transfer failed protocol or artifact integrity validation.",
        ),
        ClientError::Authentication(_) | ClientError::InvalidTrustState => (
            "healthmd_pairing_required",
            "The authenticated direct channel failed. Pair again if this persists.",
        ),
        _ => (
            "healthmd_unavailable",
            "The direct iPhone service is unavailable. Keep Health.md foreground and verify Direct CLI Access.",
        ),
    };
    let mut value = json!({"error":code,"message":message});
    if let ClientError::QueryRejected {
        code, retryable, ..
    } = error
    {
        value["reason_code"] = Value::String(code.clone());
        value["retryable"] = Value::Bool(*retryable);
    }
    if let Some(job_id) = job_id {
        value["job_id"] = json!(job_id);
    }
    value
}

fn valid_query_result(value: &Value) -> bool {
    value.get("schema_version") == Some(&json!(1))
        && value
            .get("schema")
            .and_then(Value::as_str)
            .is_some_and(|schema| {
                matches!(
                    schema,
                    "healthmd.query_response" | "healthmd.mcp_query_pages"
                )
            })
}

#[allow(clippy::needless_pass_by_value)]
fn tool_result(
    text_value: Value,
    is_error: bool,
    structured: Option<Value>,
    additional: Vec<Value>,
) -> Value {
    let text = serde_json::to_string(&text_value)
        .unwrap_or_else(|_| "{\"error\":\"healthmd_encoding_failed\"}".to_owned());
    let mut content = vec![json!({"type":"text","text":text})];
    content.extend(additional);
    let mut result = json!({"content":content,"isError":is_error});
    if let Some(structured) = structured {
        result["structuredContent"] = structured;
    }
    result
}

async fn cancelled(receiver: &mut watch::Receiver<bool>) {
    if *receiver.borrow() {
        return;
    }
    while receiver.changed().await.is_ok() {
        if *receiver.borrow() {
            return;
        }
    }
}

#[allow(clippy::needless_pass_by_value)]
fn response_success(id: Value, result: Value) -> String {
    serde_json::to_string(&json!({"jsonrpc":"2.0","id":id,"result":result})).expect("JSON response")
}

#[allow(clippy::needless_pass_by_value)]
fn response_error(id: Value, code: i64, message: &str) -> String {
    serde_json::to_string(&json!({"jsonrpc":"2.0","id":id,"error":{"code":code,"message":message}}))
        .expect("JSON response")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_portable_tools_and_no_mac_only_tools() {
        let names: Vec<String> = tools::list(false)
            .iter()
            .filter_map(|tool| tool.get("name").and_then(Value::as_str).map(str::to_owned))
            .collect();
        assert_eq!(names.len(), 17);
        assert!(names.contains(&"healthmd_metric_chart".to_owned()));
        assert!(!names.contains(&"healthmd_refresh".to_owned()));
    }

    #[test]
    fn query_tool_schemas_expand_nested_shapes_and_examples() {
        let tools = tools::list(false);
        let sleep = tools
            .iter()
            .find(|tool| tool["name"] == "healthmd_sleep_sessions")
            .expect("sleep tool");
        assert_eq!(
            sleep
                .pointer("/inputSchema/properties/dates/oneOf")
                .and_then(Value::as_array)
                .map(Vec::len),
            Some(2)
        );
        assert_eq!(
            sleep.pointer("/inputSchema/properties/dates/oneOf/0/properties/range/required/0"),
            Some(&json!("start_date"))
        );
        assert_eq!(
            sleep.pointer("/inputSchema/examples/0/all_pages"),
            Some(&json!(true))
        );
        assert_eq!(
            sleep.pointer("/inputSchema/properties/include_naps/default"),
            Some(&json!(false))
        );
        assert_eq!(
            sleep.pointer("/inputSchema/properties/page/required"),
            Some(&json!(["max_items", "max_bytes"]))
        );
        assert!(
            sleep["description"]
                .as_str()
                .is_some_and(|description| description.contains("Do not substitute"))
        );

        let advanced = tools
            .iter()
            .find(|tool| tool["name"] == "healthmd_query")
            .expect("advanced query tool");
        assert_eq!(
            advanced.pointer("/inputSchema/properties/request/properties/schema/enum/0"),
            Some(&json!("healthmd.query_request"))
        );
        assert_eq!(
            advanced
                .pointer("/inputSchema/properties/request/properties/operation/oneOf")
                .and_then(Value::as_array)
                .map(Vec::len),
            Some(8)
        );
    }

    #[test]
    fn capabilities_route_sleep_to_the_typed_tool() {
        let value = capabilities();
        assert_eq!(
            value.pointer("/query_tool_guidance/sleep"),
            Some(&json!("healthmd_sleep_sessions"))
        );
        assert_eq!(
            value.pointer("/query_tool_guidance/minimal_sleep_arguments/dates/type"),
            Some(&json!("exact"))
        );
        assert_eq!(
            value.pointer("/query_tool_guidance/shell_extract_is_not_typed_query"),
            Some(&json!(true))
        );
    }

    #[test]
    fn metric_catalog_projects_reviewed_apple_registry_fields() {
        let catalog = metric_catalog();
        let metrics = catalog["metrics"].as_array().expect("metrics");
        assert_eq!(metrics.len(), 230);
        assert!(metrics.iter().all(|metric| {
            metric["metric_id"].as_str().is_some()
                && metric["display_name"].as_str().is_some()
                && metric["category"].as_str().is_some()
                && metric["unit"].as_str().is_some()
                && metric["status"].as_str().is_some()
        }));
    }

    #[test]
    fn cancellation_pending_is_a_recoverable_receipt_not_false_terminal_success() {
        let job_id = Uuid::new_v4();
        let pending = export_error(&ClientError::CancellationPending(job_id), job_id);
        assert_eq!(pending["status"], "accepted");
        assert_eq!(pending["error"], "healthmd_cancellation_pending");
        assert!(valid_export_receipt(&pending));

        let completed = export_error(
            &ClientError::JobNotResumable(job_id, "completed".to_owned()),
            job_id,
        );
        assert_eq!(completed["status"], "unavailable");
        assert_ne!(completed["status"], "cancelled");
    }

    #[test]
    fn app_resource_is_self_contained_and_exact_mime() {
        assert_eq!(app::MIME_TYPE, "text/html;profile=mcp-app");
        assert!(app::HTML.contains("default-src 'none'"));
        assert!(!app::HTML.contains("<script src="));
    }
}
