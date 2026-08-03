use serde_json::Value;

use crate::{SurfaceProfile, apps};

pub use healthmd_operations::registry::{QueryInvocation, job_id, query_invocation};

pub fn list(profile: SurfaceProfile, ui_enabled: bool) -> Vec<Value> {
    let mut operations = healthmd_operations::registry::list(profile);
    if ui_enabled {
        for operation in &mut operations {
            let name = operation
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or_default();
            if !matches!(
                name,
                "healthmd_status"
                    | "healthmd_doctor"
                    | "healthmd_capabilities"
                    | "healthmd_metrics"
                    | "healthmd_pairing_start"
                    | "healthmd_pairing_status"
            ) {
                apps::attach_tool_metadata(operation);
            }
        }
    }
    operations
}

/// Return the generated shared operation catalog or one fixed MCP declaration.
///
/// # Errors
///
/// Returns an error when the requested operation is not exposed by the selected profile.
pub fn tool_catalog(profile: SurfaceProfile, tool_name: Option<&str>) -> Result<Value, String> {
    healthmd_operations::registry::tool_catalog(profile, tool_name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packaged_catalog_is_generated_from_the_shared_registry() {
        let packaged: Vec<Value> =
            serde_json::from_str(include_str!("../assets/mcp-tools-v1.json")).unwrap();
        assert_eq!(
            packaged,
            healthmd_operations::registry::list(SurfaceProfile::LocalDirect)
        );
    }
}
