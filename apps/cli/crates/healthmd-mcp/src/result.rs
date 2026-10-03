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
    let mut additional: Vec<Value> = if include_png {
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
    if !is_error && valid_query_result(&value) {
        let pages = value.get("pages").and_then(Value::as_array);
        let pages = pages.map_or_else(|| vec![&value], |pages| pages.iter().collect());
        let messages: std::collections::BTreeSet<_> =
            pages.into_iter().map(history_disclosure).collect();
        for message in messages {
            additional.push(json!({"type": "text", "text": message}));
        }
    }
    // Keep original JSON/structured content and image positions unchanged.
    // This text-only query disclosure does not modify shared generated HTML,
    // packet metadata, raw/file results, or Mac-side receipt/status contracts.
    tool_result(value, is_error, structured, additional)
}

fn history_disclosure(page: &Value) -> &'static str {
    let Some(receipt) = page.pointer("/metadata/history_assessment") else {
        return "History: legacy/unassessed. Completed capture and empty results do not prove full history.";
    };
    if !receipt.is_object() {
        return "History: invalid supplied evidence; historical access is unverified.";
    }
    if receipt["schema"] != "healthmd.history_assessment" || receipt["schema_version"] != 1 {
        return "History: unsupported assessment semantics, preserved opaquely; historical access is unverified.";
    }
    // This vendor-neutral presenter has no authenticated request/peer context.
    // Even a schema-only object must not acquire observation endorsement. The
    // direct backend validates its own receipt; other backends need their own
    // validation. Preserve the original data, with a conservative generic label.
    "History: supplied assessment metadata is unverified by this presenter; it is not current permission or full-history certification. See original metadata for timestamp, scope and sample-END evidence. Completed capture and empty results do not prove full history."
}

pub fn pairing_start_tool_result(value: Value, png: Vec<u8>) -> Value {
    let image = json!({
        "type": "image",
        "data": BASE64_STANDARD.encode(png),
        "mimeType": "image/png"
    });
    tool_result(value, false, None, vec![image])
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

#[cfg(test)]
mod history_disclosure_tests {
    use super::*;

    fn complete_fixture() -> Value {
        let fixture = include_str!("test-fixtures/history-assessment-v1.json");
        serde_json::from_str(fixture).unwrap()
    }

    #[test]
    fn complete_receipt_grouped_pages_and_images_keep_original_positions_without_endorsement() {
        let mut value = complete_fixture();
        value["items"] = json!([{"type": "metric", "metric": {
            "metric_id": "steps", "owner_date": "2026-01-01", "status": "available",
            "value": {"type": "count", "value": 1}
        }}]);
        let supplied = query_tool_result(value.clone(), false, true, true);
        assert_eq!(supplied["structuredContent"], value);
        assert_eq!(
            serde_json::from_str::<Value>(supplied["content"][0]["text"].as_str().unwrap())
                .unwrap(),
            value
        );
        assert_eq!(supplied["content"][1]["type"], "image");
        assert!(
            supplied["content"][2]["text"]
                .as_str()
                .unwrap()
                .contains("unverified by this presenter")
        );
        let error = query_tool_result(value.clone(), true, false, true);
        assert_eq!(error["isError"], true);
        assert!(error.get("structuredContent").is_none());
        assert_eq!(error["content"][1], supplied["content"][1]);
        assert_eq!(error["content"].as_array().unwrap().len(), 2);
        let mut malformed = value.clone();
        malformed["metadata"]["history_assessment"] = json!({"schema": "healthmd.history_assessment", "schema_version": 1, "types": "bad", "logical_dates": null});
        let mut legacy = value.clone();
        legacy["metadata"]
            .as_object_mut()
            .unwrap()
            .remove("history_assessment");
        let grouped = json!({"schema": "healthmd.mcp_query_pages", "schema_version": 1, "pages": [value, malformed, legacy]});
        let result = query_tool_result(grouped.clone(), false, true, true);
        assert_eq!(result["structuredContent"], grouped);
        assert_eq!(
            serde_json::from_str::<Value>(result["content"][0]["text"].as_str().unwrap()).unwrap(),
            grouped
        );
        assert_eq!(result["content"][1]["type"], "image");
        let messages: Vec<_> = result["content"]
            .as_array()
            .unwrap()
            .iter()
            .skip(2)
            .map(|entry| entry["text"].as_str().unwrap())
            .collect();
        assert!(
            messages
                .iter()
                .any(|message| message.contains("legacy/unassessed"))
        );
        assert!(
            messages
                .iter()
                .any(|message| message.contains("unverified by this presenter"))
        );
        assert!(
            messages
                .iter()
                .all(|message| !message.contains("supplied capture-time observation"))
        );
    }

    #[test]
    fn text_disclosure_preserves_original_json_and_structured_query_data() {
        let value = json!({
            "schema": "healthmd.query_response", "schema_version": 1,
            "items": [], "coverage": {"status": "complete_empty"}, "metadata": {"existing": "retained"}
        });
        let result = query_tool_result(value.clone(), false, true, false);
        assert_eq!(result["structuredContent"], value);
        assert_eq!(
            serde_json::from_str::<Value>(result["content"][0]["text"].as_str().unwrap()).unwrap(),
            value
        );
        assert!(
            result["content"][1]["text"]
                .as_str()
                .unwrap()
                .contains("legacy/unassessed")
        );
        assert!(
            result["content"][1]["text"]
                .as_str()
                .unwrap()
                .contains("do not prove full history")
        );
    }

    #[test]
    fn generic_presenter_never_endorses_schema_only_or_supplied_receipt_without_context() {
        for (receipt, expected) in [
            (
                json!({"schema": "healthmd.history_assessment", "schema_version": 9}),
                "unsupported",
            ),
            (Value::Null, "invalid supplied evidence"),
            (
                json!({"schema": "healthmd.history_assessment", "schema_version": 1}),
                "unverified by this presenter",
            ),
            (
                json!({"schema": "healthmd.history_assessment", "schema_version": 1, "types": [{"outcome": "limited", "sample_end_boundary": "bad"}]}),
                "unverified by this presenter",
            ),
        ] {
            let value = json!({"schema": "healthmd.query_response", "schema_version": 1,
                "metadata": {"history_assessment": receipt}});
            let result = query_tool_result(value.clone(), false, true, false);
            assert_eq!(result["structuredContent"], value);
            assert!(
                result["content"][1]["text"]
                    .as_str()
                    .unwrap()
                    .contains(expected)
            );
        }
    }
}
