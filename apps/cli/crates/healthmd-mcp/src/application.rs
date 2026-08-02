use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use healthmd_operations::{
    CallContext, CallerIdentity, HealthDataBackend, HealthOperations, OperationLimits,
    QueryDetailLevel, SurfaceProfile,
};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{apps, catalog, result};

pub type ApplicationLimits = OperationLimits;

pub struct HealthMdApplication {
    operations: HealthOperations,
}

impl HealthMdApplication {
    pub fn new(backend: Arc<dyn HealthDataBackend>, profile: SurfaceProfile) -> Self {
        Self {
            operations: HealthOperations::new(backend, profile),
        }
    }

    #[must_use]
    pub fn with_limits(mut self, limits: ApplicationLimits) -> Self {
        self.operations = self.operations.with_limits(limits);
        self
    }

    pub const fn profile(&self) -> SurfaceProfile {
        self.operations.profile()
    }

    pub fn session(self: &Arc<Self>, caller: CallerIdentity) -> HealthMdSession {
        HealthMdSession {
            application: Arc::clone(self),
            caller,
            ui_enabled: AtomicBool::new(false),
        }
    }

    /// Return the complete fixed catalog or one named tool schema.
    ///
    /// # Errors
    ///
    /// Returns an error when `tool_name` is not in the fixed profile catalog.
    pub fn tool_catalog(&self, tool_name: Option<&str>) -> Result<Value, String> {
        catalog::tool_catalog(self.profile(), tool_name)
    }

    pub fn list_tools(&self, ui_enabled: bool) -> Vec<Value> {
        catalog::list(self.profile(), ui_enabled)
    }

    fn tool_exists(&self, name: &str) -> bool {
        self.list_tools(false)
            .iter()
            .any(|tool| tool.get("name").and_then(Value::as_str) == Some(name))
    }

    async fn query_pages(
        &self,
        context: &CallContext,
        invocation: catalog::QueryInvocation,
    ) -> Result<Value, crate::BackendError> {
        self.operations.query(context, invocation).await
    }
}

pub struct HealthMdSession {
    application: Arc<HealthMdApplication>,
    caller: CallerIdentity,
    ui_enabled: AtomicBool,
}

impl HealthMdSession {
    pub fn set_ui_enabled(&self, enabled: bool) {
        self.ui_enabled.store(enabled, Ordering::Release);
    }

    pub fn ui_enabled(&self) -> bool {
        self.ui_enabled.load(Ordering::Acquire)
    }

    pub fn caller(&self) -> &CallerIdentity {
        &self.caller
    }

    pub fn list_tools(&self) -> Vec<Value> {
        self.application.list_tools(self.ui_enabled())
    }

    pub fn list_resources(&self) -> Vec<Value> {
        if self.ui_enabled() {
            vec![apps::resource_declaration()]
        } else {
            Vec::new()
        }
    }

    /// Read a negotiated MCP Apps resource.
    ///
    /// # Errors
    ///
    /// Returns method-not-found unless UI support was negotiated and `uri` is fixed.
    pub fn read_resource(&self, uri: &str) -> Result<Value, ApplicationError> {
        if self.ui_enabled() && uri == apps::RESOURCE_URI {
            Ok(apps::resource_content())
        } else {
            Err(ApplicationError::method_not_found("Unknown resource URI"))
        }
    }

    pub fn instructions(&self) -> String {
        self.application
            .operations
            .backend()
            .capabilities()
            .instructions
    }

    /// Execute one fixed MCP tool within this caller session.
    ///
    /// # Errors
    ///
    /// Returns a stable application error for invalid scope, arguments, cancellation, or backend
    /// failure.
    pub async fn call_tool(
        &self,
        name: &str,
        arguments: Value,
        cancellation: CancellationToken,
        session_id: Option<String>,
    ) -> Result<Value, ApplicationError> {
        self.call_tool_as(
            self.caller.clone(),
            name,
            arguments,
            cancellation,
            session_id,
        )
        .await
    }

    /// Execute a tool with a transport-authenticated caller. HTTP adapters use this after token
    /// verification; local stdio uses the session's fixed caller through [`Self::call_tool`].
    ///
    /// # Errors
    ///
    /// Returns a stable application error for invalid scope, arguments, cancellation, or backend
    /// failure.
    pub async fn call_tool_as(
        &self,
        caller: CallerIdentity,
        name: &str,
        arguments: Value,
        cancellation: CancellationToken,
        session_id: Option<String>,
    ) -> Result<Value, ApplicationError> {
        if !self.application.tool_exists(name) {
            return Err(ApplicationError::invalid_params("Unknown tool"));
        }
        if !caller.has_scope("health.summary.read") && !caller.has_scope("healthmd:read") {
            return Err(ApplicationError::forbidden(
                "The caller lacks the required health summary scope.",
            ));
        }
        if matches!(
            name,
            "healthmd_status" | "healthmd_doctor" | "healthmd_capabilities" | "healthmd_metrics"
        ) && arguments
            .as_object()
            .is_none_or(|object| !object.is_empty())
        {
            return Err(ApplicationError::invalid_params("Invalid tool arguments"));
        }
        let context = CallContext {
            caller,
            cancellation: cancellation.clone(),
            session_id,
        };
        match name {
            "healthmd_status" => {
                let value = cancellable_readiness(
                    self.application.operations.backend().readiness(&context),
                    &cancellation,
                )
                .await;
                Ok(value)
            }
            "healthmd_doctor" => {
                let value = cancellable_readiness(
                    self.application.operations.backend().doctor(&context),
                    &cancellation,
                )
                .await;
                Ok(value)
            }
            "healthmd_capabilities" => Ok(result::tool_result(
                capabilities_value(&self.application),
                false,
                None,
                Vec::new(),
            )),
            "healthmd_metrics" => Ok(result::tool_result(
                metric_catalog(),
                false,
                None,
                Vec::new(),
            )),
            "healthmd_export_files" => self.start_export(&context, &arguments).await,
            "healthmd_export_job_status" => self.export_status(&context, &arguments).await,
            "healthmd_export_job_resume" => self.resume_export(&context, &arguments).await,
            "healthmd_export_job_cancel" => self.cancel_export(&context, &arguments).await,
            _ => self.query(name, &arguments, &context).await,
        }
    }

    async fn query(
        &self,
        name: &str,
        arguments: &Value,
        context: &CallContext,
    ) -> Result<Value, ApplicationError> {
        let invocation = catalog::query_invocation(name, arguments)
            .map_err(|_| ApplicationError::invalid_params("Invalid tool arguments"))?;
        if self.application.profile() == SurfaceProfile::Hosted
            && invocation.detail_level == QueryDetailLevel::Lossless
            && !context.caller.has_scope("health.detail.read")
        {
            return Err(ApplicationError::forbidden(
                "The caller lacks the required health detail scope.",
            ));
        }
        let value = tokio::select! {
            result = self.application.query_pages(context, invocation) => match result {
                Ok(value) => value,
                Err(error) => return Ok(result::query_tool_result(
                    result::backend_error(&error), true, self.ui_enabled(), false,
                )),
            },
            () = context.cancellation.cancelled() => return Ok(result::query_tool_result(
                result::cancelled(None), true, self.ui_enabled(), false,
            )),
        };
        Ok(result::query_tool_result(
            value,
            false,
            self.ui_enabled(),
            !self.ui_enabled() && name == "healthmd_metric_chart",
        ))
    }

    async fn start_export(
        &self,
        context: &CallContext,
        arguments: &Value,
    ) -> Result<Value, ApplicationError> {
        self.require_local_export(&context.caller)?;
        let job_id = Uuid::new_v4();
        let value = tokio::select! {
            response = self.application.operations.backend().start_export(context, job_id, arguments) => {
                match response {
                    Ok(value) => value,
                    Err(error) => export_error_value(&error, job_id),
                }
            },
            () = context.cancellation.cancelled() => result::cancelled(Some(job_id)),
        };
        let is_error = !matches!(
            value.get("status").and_then(Value::as_str),
            Some("success" | "partial_success" | "accepted" | "preparing")
        );
        Ok(result::export_tool_result(
            "healthmd_export_files",
            value,
            is_error,
            self.ui_enabled(),
        ))
    }

    async fn export_status(
        &self,
        context: &CallContext,
        arguments: &Value,
    ) -> Result<Value, ApplicationError> {
        self.require_local_export(&context.caller)?;
        let (job_id, _) = catalog::job_id(arguments, false)
            .map_err(|_| ApplicationError::invalid_params("Invalid tool arguments"))?;
        let value = self
            .application
            .operations
            .backend()
            .export_status(context, job_id)
            .await
            .unwrap_or_else(|error| export_error_value(&error, job_id));
        let is_error = matches!(
            value.get("status").and_then(Value::as_str),
            Some("failure" | "unavailable")
        );
        Ok(result::export_tool_result(
            "healthmd_export_job_status",
            value,
            is_error,
            self.ui_enabled(),
        ))
    }

    async fn resume_export(
        &self,
        context: &CallContext,
        arguments: &Value,
    ) -> Result<Value, ApplicationError> {
        self.require_local_export(&context.caller)?;
        let (job_id, _) = catalog::job_id(arguments, true)
            .map_err(|_| ApplicationError::invalid_params("Invalid tool arguments"))?;
        let value = tokio::select! {
            response = self.application.operations.backend().resume_export(context, job_id, arguments) => {
                response.unwrap_or_else(|error| export_error_value(&error, job_id))
            },
            () = context.cancellation.cancelled() => result::cancelled(Some(job_id)),
        };
        let is_error = !matches!(
            value.get("status").and_then(Value::as_str),
            Some("success" | "partial_success")
        );
        Ok(result::export_tool_result(
            "healthmd_export_job_resume",
            value,
            is_error,
            self.ui_enabled(),
        ))
    }

    async fn cancel_export(
        &self,
        context: &CallContext,
        arguments: &Value,
    ) -> Result<Value, ApplicationError> {
        self.require_local_export(&context.caller)?;
        let (job_id, _) = catalog::job_id(arguments, false)
            .map_err(|_| ApplicationError::invalid_params("Invalid tool arguments"))?;
        let value = tokio::select! {
            response = self.application.operations.backend().cancel_export(context, job_id) => {
                response.unwrap_or_else(|error| export_error_value(&error, job_id))
            },
            () = context.cancellation.cancelled() => result::cancelled(Some(job_id)),
        };
        let is_error = value.get("error").and_then(Value::as_str)
            == Some("healthmd_request_cancelled")
            || !matches!(
                value.get("status").and_then(Value::as_str),
                Some("cancelled" | "accepted")
            );
        Ok(result::export_tool_result(
            "healthmd_export_job_cancel",
            value,
            is_error,
            self.ui_enabled(),
        ))
    }

    fn require_local_export(&self, caller: &CallerIdentity) -> Result<(), ApplicationError> {
        if self.application.profile().exposes_local_exports()
            && self
                .application
                .operations
                .backend()
                .capabilities()
                .supports_local_file_exports
            && caller.has_scope("healthmd:export")
        {
            Ok(())
        } else {
            Err(ApplicationError::invalid_params("Unknown tool"))
        }
    }
}

async fn cancellable_readiness<F>(future: F, cancellation: &CancellationToken) -> Value
where
    F: Future<Output = Result<Value, crate::BackendError>>,
{
    tokio::select! {
        response = future => match response {
            Ok(value) => result::tool_result(value, false, None, Vec::new()),
            Err(error) => result::tool_result(result::backend_error(&error), true, None, Vec::new()),
        },
        () = cancellation.cancelled() => result::tool_result(
            result::cancelled(None), true, None, Vec::new(),
        ),
    }
}

fn capabilities_value(application: &HealthMdApplication) -> Value {
    let backend = application.operations.backend().capabilities();
    json!({
        "schema": "healthmd.mcp_capabilities",
        "schema_version": 1,
        "surface_profile": match application.profile() {
            SurfaceProfile::LocalDirect => "local_direct",
            SurfaceProfile::RemoteReadOnly => "remote_read_only",
            SurfaceProfile::Hosted => "hosted",
        },
        "source_kind": backend.source_kind,
        "transport": backend.transport,
        "requires_mac_app": false,
        "iphone_must_be_foreground": backend.requires_foreground_source,
        "requires_foreground_source": backend.requires_foreground_source,
        "supports_queries": backend.supports_queries,
        "supports_local_file_exports": application.profile().exposes_local_exports()
            && backend.supports_local_file_exports,
        "operations": application
            .list_tools(false)
            .into_iter()
            .filter_map(|tool| tool.get("name").and_then(Value::as_str).map(str::to_owned))
            .collect::<Vec<_>>(),
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
                "dates": {
                    "type": "exact",
                    "range": {
                        "start_date": "2026-07-22",
                        "end_date": "2026-07-28"
                    }
                },
                "all_pages": true
            },
            "example_dates_are_illustrative": true
        },
        "query_limits": {
            "maximum_days_per_request": healthmd_operations::limits::MAXIMUM_QUERY_DAYS,
            "maximum_metric_ids": healthmd_operations::limits::MAXIMUM_METRIC_IDS,
            "maximum_page_items": healthmd_operations::limits::MAXIMUM_PAGE_ITEMS,
            "maximum_page_bytes": healthmd_operations::limits::MAXIMUM_PAGE_BYTES,
            "maximum_all_pages": application.operations.limits().maximum_traversal_pages,
            "maximum_aggregate_bytes": application.operations.limits().maximum_traversal_bytes,
            "all_available_is_logically_unbounded": true
        },
        "result_fallbacks": ["authoritative_json", "text", "png_metric_chart", "mcp_app_html"]
    })
}

fn metric_catalog() -> Value {
    let registry: Value = serde_json::from_str(include_str!("../assets/metric-registry-v1.json"))
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
    json!({
        "schema": "healthmd.metric_catalog",
        "schema_version": 1,
        "registry_version": registry.get("registry_version"),
        "metrics": metrics
    })
}

fn export_error_value(error: &crate::BackendError, job_id: Uuid) -> Value {
    let mut value = result::backend_error(error);
    value["job_id"] = json!(job_id);
    value["status"] = Value::String(
        match error.code.as_str() {
            "healthmd_export_paused" => "timed_out",
            "healthmd_cancellation_pending" => "accepted",
            "healthmd_job_expired" | "healthmd_job_terminal" => "unavailable",
            _ => "failure",
        }
        .to_owned(),
    );
    value
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ApplicationError {
    pub code: i64,
    pub message: &'static str,
}

impl ApplicationError {
    const fn invalid_params(message: &'static str) -> Self {
        Self {
            code: -32_602,
            message,
        }
    }

    const fn method_not_found(message: &'static str) -> Self {
        Self {
            code: -32_601,
            message,
        }
    }

    const fn forbidden(message: &'static str) -> Self {
        Self {
            code: -32_003,
            message,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::VecDeque, sync::Mutex};

    use async_trait::async_trait;

    use super::*;
    use crate::{BackendCapabilities, BackendError, QueryPageRequest};

    struct ScriptedBackend {
        pages: Mutex<VecDeque<Result<Value, BackendError>>>,
        requests: Mutex<Vec<QueryPageRequest>>,
    }

    impl ScriptedBackend {
        fn new(pages: impl IntoIterator<Item = Result<Value, BackendError>>) -> Arc<Self> {
            Arc::new(Self {
                pages: Mutex::new(pages.into_iter().collect()),
                requests: Mutex::new(Vec::new()),
            })
        }
    }

    #[async_trait]
    impl HealthDataBackend for ScriptedBackend {
        fn capabilities(&self) -> BackendCapabilities {
            BackendCapabilities {
                source_kind: "fixture".to_owned(),
                transport: "fixture".to_owned(),
                supports_queries: true,
                supports_local_file_exports: false,
                requires_foreground_source: false,
                instructions: "Use the Health.md fixture.".to_owned(),
            }
        }

        async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
            Ok(json!({"schema":"healthmd.readiness","schema_version":1,"ready":true}))
        }

        async fn doctor(&self, context: &CallContext) -> Result<Value, BackendError> {
            self.readiness(context).await
        }

        async fn query_page(
            &self,
            _context: &CallContext,
            request: QueryPageRequest,
        ) -> Result<Value, BackendError> {
            self.requests.lock().unwrap().push(request);
            self.pages
                .lock()
                .unwrap()
                .pop_front()
                .expect("scripted query page")
        }
    }

    fn raw_query_arguments(all_pages: bool) -> Value {
        json!({
            "request": {
                "schema": "healthmd.query_request",
                "schema_version": 1,
                "operation": {"type": "coverage"},
                "dates": {"type": "all_available"},
                "metrics": {"type": "explicit", "metric_ids": ["steps"]},
                "sources": {"type": "all_available"},
                "page": {"max_items": 25, "max_bytes": 262_144, "cursor": null}
            },
            "all_pages": all_pages
        })
    }

    fn page(items: usize, next_cursor: Option<&str>) -> Value {
        json!({
            "schema": "healthmd.query_response",
            "schema_version": 1,
            "items": (0..items).map(|index| json!({"index": index})).collect::<Vec<_>>(),
            "next_cursor": next_cursor
        })
    }

    #[tokio::test]
    async fn remote_profile_traverses_cursors_without_exposing_exports() {
        let backend = ScriptedBackend::new([Ok(page(2, Some("opaque-a"))), Ok(page(3, None))]);
        let application = Arc::new(HealthMdApplication::new(
            backend.clone(),
            SurfaceProfile::RemoteReadOnly,
        ));
        let session = application.session(CallerIdentity::loopback());
        assert_eq!(session.list_tools().len(), 13);
        assert!(session.list_tools().iter().all(|tool| {
            !tool["name"]
                .as_str()
                .is_some_and(|name| name.starts_with("healthmd_export_"))
        }));

        let result = session
            .call_tool(
                "healthmd_query",
                raw_query_arguments(true),
                CancellationToken::new(),
                Some("test-session".to_owned()),
            )
            .await
            .unwrap();
        let text: Value = serde_json::from_str(
            result
                .pointer("/content/0/text")
                .and_then(Value::as_str)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(text.pointer("/receipt/page_count"), Some(&json!(2)));
        assert_eq!(text.pointer("/receipt/item_count"), Some(&json!(5)));
        let requests = backend.requests.lock().unwrap();
        assert_eq!(requests.len(), 2);
        assert_eq!(
            requests[1].query.pointer("/page/cursor"),
            Some(&json!("opaque-a"))
        );
    }

    #[tokio::test]
    async fn resumed_traversal_never_resubmits_a_nonadvancing_cursor() {
        let backend = ScriptedBackend::new([Ok(page(1, Some("opaque-resume")))]);
        let application = Arc::new(HealthMdApplication::new(
            backend.clone(),
            SurfaceProfile::RemoteReadOnly,
        ));
        let session = application.session(CallerIdentity::loopback());
        let mut arguments = raw_query_arguments(true);
        arguments["request"]["page"]["cursor"] = json!("opaque-resume");

        let result = session
            .call_tool(
                "healthmd_query",
                arguments,
                CancellationToken::new(),
                Some("resumed-session".to_owned()),
            )
            .await
            .unwrap();
        let text: Value = serde_json::from_str(
            result
                .pointer("/content/0/text")
                .and_then(Value::as_str)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(text["error"], "healthmd_protocol_error");
        assert_eq!(result["isError"], true);
        let requests = backend.requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        assert_eq!(
            requests[0].query.pointer("/page/cursor"),
            Some(&json!("opaque-resume"))
        );
    }

    #[tokio::test]
    async fn blocked_query_observes_transport_cancellation() {
        struct BlockingBackend;

        #[async_trait]
        impl HealthDataBackend for BlockingBackend {
            fn capabilities(&self) -> BackendCapabilities {
                BackendCapabilities {
                    source_kind: "fixture".to_owned(),
                    transport: "fixture".to_owned(),
                    supports_queries: true,
                    supports_local_file_exports: false,
                    requires_foreground_source: false,
                    instructions: "Use the fixture.".to_owned(),
                }
            }

            async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
                std::future::pending().await
            }

            async fn doctor(&self, _context: &CallContext) -> Result<Value, BackendError> {
                std::future::pending().await
            }

            async fn query_page(
                &self,
                _context: &CallContext,
                _request: QueryPageRequest,
            ) -> Result<Value, BackendError> {
                std::future::pending().await
            }
        }

        let application = Arc::new(HealthMdApplication::new(
            Arc::new(BlockingBackend),
            SurfaceProfile::RemoteReadOnly,
        ));
        let session = application.session(CallerIdentity::loopback());
        let cancellation = CancellationToken::new();
        let cancelling = cancellation.clone();
        let call = session.call_tool(
            "healthmd_query",
            raw_query_arguments(false),
            cancellation,
            None,
        );
        let cancel = async move {
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
            cancelling.cancel();
        };
        let (result, ()) = tokio::join!(call, cancel);
        let result = result.unwrap();
        let text: Value = serde_json::from_str(
            result
                .pointer("/content/0/text")
                .and_then(Value::as_str)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(text["error"], "healthmd_request_cancelled");
        assert_eq!(text["operation_outcome"], "cancelled");
        assert_eq!(result["isError"], true);
    }

    #[test]
    fn mcp_app_negotiation_is_session_scoped() {
        let backend = ScriptedBackend::new([]);
        let application = Arc::new(HealthMdApplication::new(
            backend,
            SurfaceProfile::RemoteReadOnly,
        ));
        let ui = application.session(CallerIdentity::loopback());
        let text = application.session(CallerIdentity::loopback());
        ui.set_ui_enabled(true);

        assert_eq!(ui.list_resources().len(), 1);
        assert!(text.list_resources().is_empty());
        assert!(ui.list_tools().iter().any(|tool| {
            tool.pointer("/_meta/ui/resourceUri") == Some(&json!(apps::RESOURCE_URI))
        }));
        assert!(
            text.list_tools()
                .iter()
                .all(|tool| tool.pointer("/_meta/ui").is_none())
        );
    }

    #[tokio::test]
    async fn hosted_calls_accept_standard_summary_scope_and_reject_sync_only_tokens() {
        let backend = ScriptedBackend::new([]);
        let application = Arc::new(HealthMdApplication::new(backend, SurfaceProfile::Hosted));
        let summary = application.session(CallerIdentity {
            subject: "owner".to_owned(),
            tenant: Some("tenant".to_owned()),
            issuer: Some("https://issuer.example".to_owned()),
            scopes: std::collections::BTreeSet::from(["health.summary.read".to_owned()]),
            mode: crate::CallerMode::OAuth,
        });
        assert!(
            summary
                .call_tool(
                    "healthmd_capabilities",
                    json!({}),
                    CancellationToken::new(),
                    None,
                )
                .await
                .is_ok()
        );

        let sync_only = application.session(CallerIdentity {
            subject: "owner".to_owned(),
            tenant: Some("tenant".to_owned()),
            issuer: Some("https://issuer.example".to_owned()),
            scopes: std::collections::BTreeSet::from(["health.sync.write".to_owned()]),
            mode: crate::CallerMode::OAuth,
        });
        let error = sync_only
            .call_tool(
                "healthmd_capabilities",
                json!({}),
                CancellationToken::new(),
                None,
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, -32_003);
    }

    #[tokio::test]
    async fn remote_profile_rejects_local_export_tools_before_backend_dispatch() {
        let backend = ScriptedBackend::new([]);
        let application = Arc::new(HealthMdApplication::new(
            backend,
            SurfaceProfile::RemoteReadOnly,
        ));
        let session = application.session(CallerIdentity::loopback());
        let error = session
            .call_tool(
                "healthmd_export_files",
                json!({}),
                CancellationToken::new(),
                None,
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, -32_602);
        assert_eq!(error.message, "Unknown tool");
    }
}
