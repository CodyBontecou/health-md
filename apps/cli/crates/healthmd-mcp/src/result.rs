use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::backend::BackendError;

pub fn backend_error(error: &BackendError) -> Value {
    healthmd_operations::backend_error_value(error)
}

pub fn cancelled(job_id: Option<Uuid>) -> Value {
    healthmd_operations::cancellation_value(job_id)
}

pub fn query_tool_result(
    value: Value,
    is_error: bool,
    ui_enabled: bool,
    include_png: bool,
) -> Value {
    let structured = (ui_enabled && valid_query_result(&value)).then(|| value.clone());
    let additional = if include_png {
        crate::chart::render(&value)
            .map(|png| {
                json!({
                    "type": "image",
                    "data": BASE64_STANDARD.encode(png),
                    "mimeType": "image/png"
                })
            })
            .into_iter()
            .collect()
    } else {
        Vec::new()
    };
    tool_result(value, is_error, structured, additional)
}

pub fn export_tool_result(
    operation: &str,
    value: Value,
    is_error: bool,
    ui_enabled: bool,
) -> Value {
    let structured = (ui_enabled && valid_export_receipt(&value)).then(|| {
        json!({
            "schema": "healthmd.mcp_export_result",
            "schema_version": 1,
            "operation": operation,
            "response": value
        })
    });
    tool_result(value, is_error, structured, Vec::new())
}

#[allow(clippy::needless_pass_by_value)]
pub fn tool_result(
    text_value: Value,
    is_error: bool,
    structured: Option<Value>,
    additional: Vec<Value>,
) -> Value {
    let text = serde_json::to_string(&text_value)
        .unwrap_or_else(|_| "{\"error\":\"healthmd_encoding_failed\"}".to_owned());
    let mut content = vec![json!({"type": "text", "text": text})];
    content.extend(additional);
    let mut result = json!({"content": content, "isError": is_error});
    if let Some(structured) = structured {
        result["structuredContent"] = structured;
    }
    result
}

fn valid_query_result(value: &Value) -> bool {
    healthmd_operations::valid_query_receipt(value)
}

fn valid_export_receipt(value: &Value) -> bool {
    healthmd_operations::valid_export_receipt(value)
}
