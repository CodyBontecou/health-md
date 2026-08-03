use serde_json::{Map, Value, json};

pub const EXTENSION_ID: &str = "io.modelcontextprotocol/ui";
pub const MIME_TYPE: &str = "text/html;profile=mcp-app";
pub const RESOURCE_URI: &str = "ui://healthmd/query-visualization-v1";
pub const PAIRING_RESOURCE_URI: &str = "ui://healthmd/pairing-qr-v1";
pub const HTML: &str = include_str!("../assets/query-visualization-v1.html");
pub const PAIRING_HTML: &str = include_str!("../assets/pairing-qr-v1.html");

pub fn resource_declaration() -> Value {
    json!({
        "uri": RESOURCE_URI,
        "name": "Health.md query visualization",
        "description": "Interactive factual health charts, coverage, evidence, limitations, and export receipts when supported by the active Health.md data source.",
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

pub fn pairing_resource_declaration() -> Value {
    json!({
        "uri": PAIRING_RESOURCE_URI,
        "name": "Health.md iPhone pairing QR",
        "description": "Inline rendering for the short-lived local iPhone pairing QR image.",
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
    app_resource_content(RESOURCE_URI, HTML)
}

pub fn pairing_resource_content() -> Value {
    app_resource_content(PAIRING_RESOURCE_URI, PAIRING_HTML)
}

fn app_resource_content(uri: &str, html: &str) -> Value {
    json!({
        "uri": uri,
        "mimeType": MIME_TYPE,
        "text": html,
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
    attach_resource_metadata(tool, RESOURCE_URI);
}

pub fn attach_pairing_tool_metadata(tool: &mut Value) {
    attach_resource_metadata(tool, PAIRING_RESOURCE_URI);
}

fn attach_resource_metadata(tool: &mut Value, resource_uri: &str) {
    let Some(object) = tool.as_object_mut() else {
        return;
    };
    let metadata = object
        .entry("_meta")
        .or_insert_with(|| Value::Object(Map::default()));
    if let Some(metadata) = metadata.as_object_mut() {
        metadata.insert(
            "ui".to_owned(),
            json!({"resourceUri": resource_uri, "visibility": ["model"]}),
        );
    }
}
