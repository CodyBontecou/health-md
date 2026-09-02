use serde_json::{Value, json};
use uuid::Uuid;

use crate::BackendError;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OperationOutcome {
    Success,
    Failure,
    Cancelled,
}

#[derive(Clone, Debug, PartialEq)]
pub struct OperationReceipt {
    pub value: Value,
    pub outcome: OperationOutcome,
}

impl OperationReceipt {
    pub const fn success(value: Value) -> Self {
        Self {
            value,
            outcome: OperationOutcome::Success,
        }
    }

    pub const fn failure(value: Value) -> Self {
        Self {
            value,
            outcome: OperationOutcome::Failure,
        }
    }

    pub const fn cancelled(value: Value) -> Self {
        Self {
            value,
            outcome: OperationOutcome::Cancelled,
        }
    }

    pub const fn is_error(&self) -> bool {
        !matches!(self.outcome, OperationOutcome::Success)
    }
}

pub fn backend_error_value(error: &BackendError) -> Value {
    let mut value = json!({
        "error": error.code,
        "message": error.message
    });
    if let Some(job_id) = error.job_id {
        value["job_id"] = json!(job_id);
    }
    if let Some(seconds) = error.wake_window_seconds {
        value["wake_window_seconds"] = Value::from(seconds);
    }
    value
}

pub fn cancellation_value(job_id: Option<Uuid>) -> Value {
    let mut value = json!({
        "error": "healthmd_request_cancelled",
        "status": if job_id.is_some() { "accepted" } else { "cancelled" },
        "operation_outcome": if job_id.is_some() { "unknown" } else { "cancelled" },
        "message": if job_id.is_some() {
            "The MCP waiter detached. The durable export may still be active; inspect this job ID before retrying."
        } else {
            "The transient health query waiter was cancelled."
        }
    });
    if let Some(job_id) = job_id {
        value["job_id"] = json!(job_id);
    }
    value
}

pub fn valid_query_receipt(value: &Value) -> bool {
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

pub fn valid_export_receipt(value: &Value) -> bool {
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
