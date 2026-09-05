//! Application-seam gate for Agent Data surface separation.
//!
//! The bin-driven gate in `healthmd-cli` freezes the offline catalogs. This
//! suite proves the complementary dispatch property at the application seam:
//! a `DataReadOnly` application lists exactly the five Agent Data tools,
//! dispatches Agent Data queries to the backend, and rejects every direct
//! tool call with `Unknown tool` before the backend is contacted.

use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use healthmd_mcp::{
    BackendCapabilities, BackendError, CallContext, CallerIdentity, HealthDataBackend,
    HealthMdApplication, QueryPageRequest, SurfaceProfile,
};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

const DATA_TOOLS: &[&str] = &[
    "healthmd_data_catalog",
    "healthmd_data_records",
    "healthmd_data_record_read",
    "healthmd_data_artifacts",
    "healthmd_data_artifact_read",
];

const DIRECT_TOOLS: &[&str] = &[
    "healthmd_status",
    "healthmd_doctor",
    "healthmd_capabilities",
    "healthmd_metrics",
    "healthmd_metric_chart",
    "healthmd_sleep_sessions",
    "healthmd_training_alignment",
    "healthmd_workouts",
    "healthmd_coverage",
    "healthmd_compare_periods",
    "healthmd_training_evidence",
    "healthmd_query",
    "healthmd_evidence_packet",
    "healthmd_pairing_start",
    "healthmd_pairing_status",
    "healthmd_export_files",
    "healthmd_export_job_status",
    "healthmd_export_job_resume",
    "healthmd_export_job_cancel",
];

/// Records every backend contact so pre-dispatch rejection is observable.
#[derive(Default)]
struct RecordingBackend {
    contacts: Mutex<Vec<&'static str>>,
    queries: Mutex<Vec<Value>>,
}

impl RecordingBackend {
    fn backend_contacts(&self) -> usize {
        self.contacts.lock().expect("contacts lock").len()
    }

    fn recorded_queries(&self) -> Vec<Value> {
        self.queries.lock().expect("queries lock").clone()
    }

    fn record(&self, method: &'static str) {
        self.contacts.lock().expect("contacts lock").push(method);
    }
}

#[async_trait]
impl HealthDataBackend for RecordingBackend {
    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            source_kind: "fixture".to_owned(),
            transport: "fixture".to_owned(),
            supports_queries: true,
            supports_local_file_exports: false,
            requires_foreground_source: false,
            instructions: "Use the Agent Data separation fixture.".to_owned(),
        }
    }

    async fn readiness(&self, _context: &CallContext) -> Result<Value, BackendError> {
        self.record("readiness");
        Ok(json!({"schema": "healthmd.readiness", "schema_version": 1, "ready": false}))
    }

    async fn doctor(&self, _context: &CallContext) -> Result<Value, BackendError> {
        self.record("doctor");
        Ok(json!({"schema": "healthmd.readiness", "schema_version": 1, "ready": false}))
    }

    async fn query_page(
        &self,
        _context: &CallContext,
        request: QueryPageRequest,
    ) -> Result<Value, BackendError> {
        self.record("query_page");
        self.queries
            .lock()
            .expect("queries lock")
            .push(request.query);
        Ok(json!({
            "schema": "healthmd.query_response",
            "schema_version": 1,
            "items": [],
            "next_cursor": null
        }))
    }
}

fn data_session(backend: &Arc<RecordingBackend>) -> healthmd_mcp::HealthMdSession {
    let application = Arc::new(HealthMdApplication::new(
        Arc::clone(backend) as Arc<dyn HealthDataBackend>,
        SurfaceProfile::DataReadOnly,
    ));
    application.session(CallerIdentity::loopback())
}

#[test]
fn data_profile_lists_exactly_the_five_agent_data_tools() {
    let backend = Arc::new(RecordingBackend::default());
    let session = data_session(&backend);
    let tools = session.list_tools();
    let mut names: Vec<&str> = tools
        .iter()
        .map(|tool| tool["name"].as_str().expect("tool name"))
        .collect();
    names.sort_unstable();
    let mut expected = DATA_TOOLS.to_vec();
    expected.sort_unstable();
    assert_eq!(names, expected);
    assert_eq!(backend.backend_contacts(), 0);
}

#[tokio::test]
async fn data_profile_rejects_every_direct_tool_before_backend_contact() {
    let backend = Arc::new(RecordingBackend::default());
    let session = data_session(&backend);
    for name in DIRECT_TOOLS {
        let error = session
            .call_tool(name, json!({}), CancellationToken::new(), None)
            .await
            .expect_err("direct tools must not dispatch on the data surface");
        assert_eq!(error.code, -32_602, "{name}");
        assert_eq!(error.message, "Unknown tool", "{name}");
    }
    assert_eq!(
        backend.backend_contacts(),
        0,
        "direct rejection must precede every backend contact"
    );
}

#[tokio::test]
async fn agent_data_catalog_dispatch_stays_on_the_agent_data_query_path() {
    let backend = Arc::new(RecordingBackend::default());
    let session = data_session(&backend);
    let result = session
        .call_tool(
            "healthmd_data_catalog",
            json!({}),
            CancellationToken::new(),
            None,
        )
        .await
        .expect("Agent Data catalog dispatch");
    assert_ne!(result["isError"], Value::Bool(true));

    let queries = backend.recorded_queries();
    assert_eq!(queries.len(), 1, "one bounded page per non-traversal call");
    assert_eq!(queries[0]["schema"], "healthmd.agent_data_query");
    assert_eq!(queries[0]["schema_version"], 1);
    assert_eq!(
        queries[0].pointer("/operation/type"),
        Some(&json!("catalog"))
    );
    assert_eq!(
        queries[0].pointer("/page"),
        Some(&json!({"max_items": 250, "max_bytes": 262_144, "cursor": null}))
    );
}
