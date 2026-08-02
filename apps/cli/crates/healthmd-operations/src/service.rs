use std::{collections::HashSet, sync::Arc};

use serde_json::{Value, json};

use crate::{
    BackendError, CallContext, HealthDataBackend, OperationLimits, QueryPageRequest,
    SurfaceProfile, registry::QueryInvocation,
};

/// Shared application service used by CLI and MCP adapters.
pub struct HealthOperations {
    backend: Arc<dyn HealthDataBackend>,
    profile: SurfaceProfile,
    limits: OperationLimits,
}

impl HealthOperations {
    pub fn new(backend: Arc<dyn HealthDataBackend>, profile: SurfaceProfile) -> Self {
        Self {
            backend,
            profile,
            limits: OperationLimits::default(),
        }
    }

    #[must_use]
    pub fn with_limits(mut self, limits: OperationLimits) -> Self {
        self.limits = limits;
        self
    }

    pub const fn profile(&self) -> SurfaceProfile {
        self.profile
    }

    pub const fn limits(&self) -> OperationLimits {
        self.limits
    }

    pub fn backend(&self) -> &Arc<dyn HealthDataBackend> {
        &self.backend
    }

    pub fn list_operations(&self) -> Vec<Value> {
        crate::registry::list(self.profile)
    }

    pub fn operation_exists(&self, name: &str) -> bool {
        self.list_operations()
            .iter()
            .any(|operation| operation.get("name").and_then(Value::as_str) == Some(name))
    }

    /// Execute an already-normalized query operation with bounded cursor traversal.
    ///
    /// # Errors
    ///
    /// Returns a stable backend error when the source rejects a page, emits a cursor cycle, or the
    /// aggregate response exceeds its transport-neutral bound.
    #[allow(clippy::too_many_lines)]
    pub async fn query(
        &self,
        context: &CallContext,
        mut invocation: QueryInvocation,
    ) -> Result<Value, BackendError> {
        let mut pages = Vec::new();
        let mut seen = HashSet::new();
        if let Some(cursor) = invocation
            .query
            .pointer("/page/cursor")
            .and_then(Value::as_str)
        {
            seen.insert(cursor.to_owned());
        }
        let mut bytes = 0_usize;
        let mut traversal_complete = true;
        let mut continuation_cursor = None;
        let mut limit_reason = None;
        let page_budget = self.limits.maximum_traversal_bytes.saturating_sub(16_384);

        loop {
            if invocation.all_pages && pages.len() >= self.limits.maximum_traversal_pages {
                traversal_complete = false;
                continuation_cursor = invocation
                    .query
                    .pointer("/page/cursor")
                    .and_then(Value::as_str)
                    .map(str::to_owned);
                limit_reason = Some("maximum_pages");
                break;
            }
            let requested_cursor = invocation
                .query
                .pointer("/page/cursor")
                .and_then(Value::as_str)
                .map(str::to_owned);
            let response = self
                .backend
                .query_page(
                    context,
                    QueryPageRequest {
                        query: invocation.query.clone(),
                        detail_level: invocation.detail_level,
                    },
                )
                .await?;
            let page_bytes = serde_json::to_vec(&response)
                .map_err(|_| {
                    BackendError::new(
                        "healthmd_encoding_failed",
                        "The Health.md response could not be encoded.",
                    )
                })?
                .len();
            if bytes.saturating_add(page_bytes) > page_budget {
                if !invocation.all_pages || pages.is_empty() {
                    return Err(BackendError::new(
                        "healthmd_response_too_large",
                        "The response exceeded the bounded MCP aggregate limit.",
                    ));
                }
                traversal_complete = false;
                continuation_cursor = requested_cursor;
                limit_reason = Some("maximum_aggregate_bytes");
                break;
            }
            bytes += page_bytes;
            let cursor = response
                .get("next_cursor")
                .and_then(Value::as_str)
                .map(str::to_owned);
            pages.push(response);
            if !invocation.all_pages || cursor.is_none() {
                break;
            }
            let Some(cursor) = cursor else {
                break;
            };
            if !seen.insert(cursor.clone()) {
                return Err(BackendError::new(
                    "healthmd_protocol_error",
                    "The Health.md source returned an invalid pagination cursor cycle.",
                ));
            }
            invocation.query["page"]["cursor"] = Value::String(cursor);
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
            Ok(json!({
                "schema": "healthmd.mcp_query_pages",
                "schema_version": 1,
                "pages": pages,
                "receipt": {
                    "page_count": pages.len(),
                    "item_count": item_count,
                    "packet_fact_count": packet_fact_count,
                    "traversal_complete": traversal_complete,
                    "next_cursor": continuation_cursor,
                    "limit_reason": limit_reason
                }
            }))
        } else {
            pages.into_iter().next().ok_or_else(|| {
                BackendError::new(
                    "healthmd_protocol_error",
                    "The Health.md source returned no query page.",
                )
            })
        }
    }
}
