use std::{collections::BTreeSet, fmt};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize, de::Error as _};
use serde_json::Value;

/// Maximum accepted synchronized days in one transaction.
pub const MAX_SYNC_DAYS: usize = 31;
/// Maximum canonical request body represented by [`HostedSyncRequest`].
pub const MAX_SYNC_REQUEST_BYTES: usize = 8 * 1_024 * 1_024;
/// Maximum canonical bytes for one compact context day.
pub const MAX_CONTEXT_DAY_BYTES: usize = 2 * 1_024 * 1_024;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum HostedConsentDetail {
    Summary,
    Lossless,
}

/// Server-side consent policy. Each owner-scoped mutation is exactly the stored revision plus one;
/// only an exact same-revision policy replay is accepted idempotently for outcome reconciliation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct HostedConsentRequest {
    pub revision: u64,
    pub allowed_metric_ids: BTreeSet<String>,
    #[serde(default)]
    pub allowed_source_ids: BTreeSet<String>,
    #[serde(default)]
    pub allowed_provider_ids: BTreeSet<String>,
    pub maximum_detail: HostedConsentDetail,
    pub retention_days: u16,
    #[serde(default)]
    pub expires_at: Option<DateTime<Utc>>,
}

impl<'de> Deserialize<'de> for HostedConsentRequest {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Wire {
            revision: u64,
            allowed_metric_ids: Vec<String>,
            #[serde(default)]
            allowed_source_ids: Vec<String>,
            #[serde(default)]
            allowed_provider_ids: Vec<String>,
            maximum_detail: HostedConsentDetail,
            retention_days: u16,
            #[serde(default)]
            expires_at: Option<DateTime<Utc>>,
        }

        let wire = Wire::deserialize(deserializer)?;
        let metric_count = wire.allowed_metric_ids.len();
        let source_count = wire.allowed_source_ids.len();
        let provider_count = wire.allowed_provider_ids.len();
        let allowed_metric_ids: BTreeSet<String> = wire.allowed_metric_ids.into_iter().collect();
        let allowed_source_ids: BTreeSet<String> = wire.allowed_source_ids.into_iter().collect();
        let allowed_provider_ids: BTreeSet<String> =
            wire.allowed_provider_ids.into_iter().collect();
        if metric_count != allowed_metric_ids.len()
            || source_count != allowed_source_ids.len()
            || provider_count != allowed_provider_ids.len()
        {
            return Err(D::Error::custom("consent identifiers must be unique"));
        }
        Ok(Self {
            revision: wire.revision,
            allowed_metric_ids,
            allowed_source_ids,
            allowed_provider_ids,
            maximum_detail: wire.maximum_detail,
            retention_days: wire.retention_days,
            expires_at: wire.expires_at,
        })
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct HostedConsentRevocationRequest {
    pub expected_revision: u64,
    pub revision: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct HostedConsentResult {
    pub schema: &'static str,
    pub schema_version: u8,
    pub consent_revision: u64,
    pub dataset_revision: u64,
    pub consent_state: &'static str,
    pub synchronized_day_count: usize,
    pub purged_day_count: usize,
}

/// One canonical `healthmd.query_context_day` v1 document and its client digest.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct HostedSyncDay {
    pub digest_sha256: String,
    pub day: Value,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct HostedSyncRequest {
    pub expected_consent_revision: u64,
    pub days: Vec<HostedSyncDay>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct HostedSyncResult {
    pub schema: &'static str,
    pub schema_version: u8,
    pub consent_revision: u64,
    pub dataset_revision: u64,
    pub changed_day_count: usize,
    pub unchanged_day_count: usize,
    pub purged_day_count: usize,
}

/// Owner-only synchronized corpus metadata. Date bounds are health metadata and must not be
/// returned before caller identity and read scope have been verified.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct HostedSyncStatus {
    pub schema: &'static str,
    pub schema_version: u8,
    /// Stable opaque binding for the authenticated issuer/tenant/subject corpus.
    pub owner_binding: String,
    pub ready: bool,
    pub dataset_revision: u64,
    pub consent_revision: Option<u64>,
    pub consent_state: &'static str,
    pub synchronized_day_count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_owner_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_owner_date: Option<String>,
}

/// Health-free lifecycle state for first-party synchronization clients. This intentionally omits
/// retained-day counts, date bounds, readiness, and dataset revisions, which require read scope.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct HostedControlStatus {
    pub schema: &'static str,
    pub schema_version: u8,
    pub owner_binding: String,
    pub consent_revision: Option<u64>,
    pub consent_state: &'static str,
}

/// Stable, health-free hosted failure suitable for an HTTP response or backend conversion.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct HostedError {
    pub code: &'static str,
    pub message: &'static str,
    pub retryable: bool,
}

impl HostedError {
    pub(crate) const fn new(code: &'static str, message: &'static str) -> Self {
        Self {
            code,
            message,
            retryable: false,
        }
    }

    pub(crate) const fn retryable(mut self) -> Self {
        self.retryable = true;
        self
    }
}

impl fmt::Display for HostedError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message)
    }
}

impl std::error::Error for HostedError {}
