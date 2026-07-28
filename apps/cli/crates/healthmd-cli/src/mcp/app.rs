use serde_json::{Map, Value, json};

pub const EXTENSION_ID: &str = "io.modelcontextprotocol/ui";
pub const MIME_TYPE: &str = "text/html;profile=mcp-app";
pub const RESOURCE_URI: &str = "ui://healthmd/query-visualization-v1";
pub const HTML: &str = include_str!("../../assets/query-visualization-v1.html");

pub fn resource_declaration() -> Value {
    json!({
        "uri": RESOURCE_URI,
        "name": "Health.md query visualization",
        "description": "Interactive factual health charts, coverage, evidence, and direct iPhone export receipts.",
        "mimeType": MIME_TYPE,
        "_meta": {
            "ui": {
                "csp": {
                    "connectDomains": [],
                    "resourceDomains": [],
                    "frameDomains": [],
                    "baseUriDomains": []
                },
                "prefersBorder": true
            }
        }
    })
}

pub fn resource_content() -> Value {
    json!({
        "uri": RESOURCE_URI,
        "mimeType": MIME_TYPE,
        "text": HTML,
        "_meta": {
            "ui": {
                "csp": {
                    "connectDomains": [],
                    "resourceDomains": [],
                    "frameDomains": [],
                    "baseUriDomains": []
                },
                "prefersBorder": true
            }
        }
    })
}

pub fn attach_tool_metadata(tool: &mut Value) {
    let Some(object) = tool.as_object_mut() else {
        return;
    };
    let metadata = object
        .entry("_meta")
        .or_insert_with(|| Value::Object(Map::default()));
    if let Some(metadata) = metadata.as_object_mut() {
        metadata.insert(
            "ui".to_owned(),
            json!({"resourceUri": RESOURCE_URI, "visibility": ["model"]}),
        );
    }
}
