/// Portable bounds applied independently of CLI or MCP transport framing.
pub const MAXIMUM_QUERY_DAYS: usize = 366_000;
pub const MAXIMUM_METRIC_IDS: usize = 512;
pub const MAXIMUM_CATEGORIES: usize = 64;
pub const MAXIMUM_PAGE_ITEMS: usize = 1_000;
pub const MAXIMUM_PAGE_BYTES: usize = 1_048_576;
pub const DEFAULT_PAGE_ITEMS: usize = 250;
pub const DEFAULT_PAGE_BYTES: usize = 262_144;
pub const DEFAULT_EXPORT_TIMEOUT_SECONDS: u64 = 300;
pub const MINIMUM_EXPORT_TIMEOUT_SECONDS: u64 = 5;
pub const MAXIMUM_EXPORT_TIMEOUT_SECONDS: u64 = 900;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OperationLimits {
    pub maximum_traversal_bytes: usize,
    pub maximum_traversal_pages: usize,
}

impl Default for OperationLimits {
    fn default() -> Self {
        Self {
            maximum_traversal_bytes: 2 * 1_024 * 1_024,
            maximum_traversal_pages: 4_096,
        }
    }
}
