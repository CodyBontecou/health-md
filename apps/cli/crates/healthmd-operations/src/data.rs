use std::collections::BTreeSet;

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::limits::{MAXIMUM_METRIC_IDS, MAXIMUM_PAGE_BYTES, MAXIMUM_PAGE_ITEMS};

pub const AGENT_DATA_GRANT_SCHEMA: &str = "healthmd.agent_data_grant";
pub const AGENT_DATA_QUERY_SCHEMA: &str = "healthmd.agent_data_query";
pub const AGENT_QUERY_RESPONSE_SCHEMA: &str = "healthmd.agent_query_response";
pub const AGENT_DATA_SCHEMA_VERSION: u16 = 1;

const MAXIMUM_SOURCE_IDS: usize = 128;
const MAXIMUM_IDENTIFIER_BYTES: usize = 512;
const MAXIMUM_SOURCE_ID_BYTES: usize = 128;
const MAXIMUM_CURSOR_BYTES: usize = 8_192;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AgentDataGrant {
    pub schema: String,
    pub schema_version: u16,
    pub metrics: AgentDataMetricSelection,
    pub sources: AgentDataSourceSelection,
    pub dates: AgentDataDateSelection,
    pub times: AgentDataTimeSelection,
    pub detail_levels: Vec<AgentDataDetailLevel>,
    pub bulk_download: bool,
}

impl AgentDataGrant {
    /// Decode and validate the public grant contract.
    ///
    /// # Errors
    ///
    /// Returns a health-free stable reason when the value is not Agent Data Grant v1.
    pub fn from_value(value: Value) -> Result<Self, &'static str> {
        let grant: Self = serde_json::from_value(value).map_err(|_| "invalid agent data grant")?;
        grant.validate()?;
        Ok(grant)
    }

    /// Validate bounds and interval ordering that JSON Schema cannot express alone.
    ///
    /// # Errors
    ///
    /// Returns a health-free stable reason for an invalid grant.
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.schema != AGENT_DATA_GRANT_SCHEMA
            || self.schema_version != AGENT_DATA_SCHEMA_VERSION
        {
            return Err("unsupported agent data grant contract");
        }
        self.metrics.validate()?;
        self.sources.validate()?;
        self.dates.validate()?;
        self.times.validate()?;
        let levels = self.detail_levels.iter().copied().collect::<BTreeSet<_>>();
        if levels.is_empty() || levels.len() != self.detail_levels.len() {
            return Err("invalid agent data detail levels");
        }
        Ok(())
    }

    #[must_use]
    pub fn allows_record(&self, scope: &AgentDataRecordScope<'_>) -> bool {
        self.detail_levels.contains(&scope.detail_level)
            && self.metrics.allows_all(scope.metric_ids)
            && self.sources.matches(scope.source_id)
            && self.dates.matches(scope.owner_date)
            && self.times.matches(scope.start_time, scope.end_time)
    }

    #[must_use]
    pub fn allows_full_artifacts(&self) -> bool {
        self.bulk_download
            && self.metrics.is_all_available()
            && self.sources.is_all_available()
            && self.dates.is_all_available()
            && self.times.is_all_available()
            && self.detail_levels.iter().copied().collect::<BTreeSet<_>>()
                == BTreeSet::from([AgentDataDetailLevel::Common, AgentDataDetailLevel::Lossless])
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum AgentDataMetricSelection {
    AllAvailable,
    Explicit { metric_ids: Vec<String> },
}

impl AgentDataMetricSelection {
    fn validate(&self) -> Result<(), &'static str> {
        match self {
            Self::AllAvailable => Ok(()),
            Self::Explicit { metric_ids } => validate_identifiers(
                metric_ids,
                MAXIMUM_METRIC_IDS,
                MAXIMUM_IDENTIFIER_BYTES,
                "invalid agent data metric selection",
            ),
        }
    }

    #[must_use]
    pub const fn is_all_available(&self) -> bool {
        matches!(self, Self::AllAvailable)
    }

    #[must_use]
    pub fn matches(&self, metric_id: &str) -> bool {
        match self {
            Self::AllAvailable => true,
            Self::Explicit { metric_ids } => metric_ids.iter().any(|value| value == metric_id),
        }
    }

    #[must_use]
    pub fn allows_all(&self, metric_ids: &[String]) -> bool {
        !metric_ids.is_empty() && metric_ids.iter().all(|value| self.matches(value))
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum AgentDataSourceSelection {
    AllAvailable,
    Explicit { source_ids: Vec<String> },
}

impl AgentDataSourceSelection {
    fn validate(&self) -> Result<(), &'static str> {
        match self {
            Self::AllAvailable => Ok(()),
            Self::Explicit { source_ids } => validate_identifiers(
                source_ids,
                MAXIMUM_SOURCE_IDS,
                MAXIMUM_SOURCE_ID_BYTES,
                "invalid agent data source selection",
            ),
        }
    }

    #[must_use]
    pub const fn is_all_available(&self) -> bool {
        matches!(self, Self::AllAvailable)
    }

    #[must_use]
    pub fn matches(&self, source_id: &str) -> bool {
        match self {
            Self::AllAvailable => true,
            Self::Explicit { source_ids } => source_ids.iter().any(|value| value == source_id),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum AgentDataDateSelection {
    AllAvailable,
    Exact {
        start_date: NaiveDate,
        end_date: NaiveDate,
    },
}

impl AgentDataDateSelection {
    fn validate(&self) -> Result<(), &'static str> {
        if let Self::Exact {
            start_date,
            end_date,
        } = self
        {
            if start_date > end_date {
                return Err("invalid agent data date range");
            }
        }
        Ok(())
    }

    #[must_use]
    pub const fn is_all_available(&self) -> bool {
        matches!(self, Self::AllAvailable)
    }

    #[must_use]
    pub fn matches(&self, owner_date: Option<NaiveDate>) -> bool {
        match self {
            Self::AllAvailable => true,
            Self::Exact {
                start_date,
                end_date,
            } => owner_date.is_some_and(|date| date >= *start_date && date <= *end_date),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum AgentDataTimeSelection {
    AllAvailable,
    Exact {
        start_inclusive: DateTime<Utc>,
        end_exclusive: DateTime<Utc>,
    },
}

impl AgentDataTimeSelection {
    fn validate(&self) -> Result<(), &'static str> {
        if let Self::Exact {
            start_inclusive,
            end_exclusive,
        } = self
        {
            if start_inclusive >= end_exclusive {
                return Err("invalid agent data time range");
            }
        }
        Ok(())
    }

    #[must_use]
    pub const fn is_all_available(&self) -> bool {
        matches!(self, Self::AllAvailable)
    }

    #[must_use]
    pub fn matches(
        &self,
        record_start: Option<DateTime<Utc>>,
        record_end: Option<DateTime<Utc>>,
    ) -> bool {
        match self {
            Self::AllAvailable => true,
            Self::Exact {
                start_inclusive,
                end_exclusive,
            } => {
                let Some(start) = record_start.or(record_end) else {
                    return false;
                };
                let end = record_end.unwrap_or(start);
                if end > start {
                    start < *end_exclusive && end > *start_inclusive
                } else {
                    start >= *start_inclusive && start < *end_exclusive
                }
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentDataDetailLevel {
    Common,
    Lossless,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AgentDataQueryRequest {
    pub schema: String,
    pub schema_version: u16,
    pub operation: AgentDataOperation,
    pub page: AgentDataPage,
}

impl AgentDataQueryRequest {
    /// Decode and validate the public query contract.
    ///
    /// # Errors
    ///
    /// Returns a health-free stable reason when the query is invalid.
    pub fn from_value(value: Value) -> Result<Self, &'static str> {
        let request: Self =
            serde_json::from_value(value).map_err(|_| "invalid agent data query")?;
        request.validate()?;
        Ok(request)
    }

    /// Validate contract identity, selectors, bounds, and operation identifiers.
    ///
    /// # Errors
    ///
    /// Returns a health-free stable reason when validation fails.
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.schema != AGENT_DATA_QUERY_SCHEMA
            || self.schema_version != AGENT_DATA_SCHEMA_VERSION
        {
            return Err("unsupported agent data query contract");
        }
        self.page.validate()?;
        match &self.operation {
            AgentDataOperation::Catalog | AgentDataOperation::Artifacts => Ok(()),
            AgentDataOperation::Records {
                metrics,
                sources,
                dates,
                times,
                ..
            } => {
                metrics.validate()?;
                sources.validate()?;
                dates.validate()?;
                times.validate()
            }
            AgentDataOperation::RecordRead { record_id } => validate_digest(record_id),
            AgentDataOperation::ArtifactRead { artifact_id } => validate_digest(artifact_id),
        }
    }

    #[must_use]
    pub const fn operation_name(&self) -> &'static str {
        match self.operation {
            AgentDataOperation::Catalog => "catalog",
            AgentDataOperation::Records { .. } => "records",
            AgentDataOperation::RecordRead { .. } => "record_read",
            AgentDataOperation::Artifacts => "artifacts",
            AgentDataOperation::ArtifactRead { .. } => "artifact_read",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum AgentDataOperation {
    Catalog,
    Records {
        metrics: AgentDataMetricSelection,
        sources: AgentDataSourceSelection,
        dates: AgentDataDateSelection,
        times: AgentDataTimeSelection,
        detail_level: AgentDataDetailLevel,
    },
    RecordRead {
        record_id: String,
    },
    Artifacts,
    ArtifactRead {
        artifact_id: String,
    },
}

impl AgentDataOperation {
    #[must_use]
    pub fn matches_record(&self, scope: &AgentDataRecordScope<'_>) -> bool {
        let Self::Records {
            metrics,
            sources,
            dates,
            times,
            detail_level,
        } = self
        else {
            return false;
        };
        *detail_level == scope.detail_level
            && scope.metric_ids.iter().any(|value| metrics.matches(value))
            && sources.matches(scope.source_id)
            && dates.matches(scope.owner_date)
            && times.matches(scope.start_time, scope.end_time)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AgentDataPage {
    pub max_items: usize,
    pub max_bytes: usize,
    pub cursor: Option<String>,
}

impl Default for AgentDataPage {
    fn default() -> Self {
        Self {
            max_items: crate::limits::DEFAULT_PAGE_ITEMS,
            max_bytes: crate::limits::DEFAULT_PAGE_BYTES,
            cursor: None,
        }
    }
}

impl AgentDataPage {
    fn validate(&self) -> Result<(), &'static str> {
        if self.max_items == 0
            || self.max_items > MAXIMUM_PAGE_ITEMS
            || self.max_bytes == 0
            || self.max_bytes > MAXIMUM_PAGE_BYTES
            || self
                .cursor
                .as_ref()
                .is_some_and(|value| value.len() > MAXIMUM_CURSOR_BYTES)
        {
            return Err("invalid agent data page bounds");
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug)]
pub struct AgentDataRecordScope<'a> {
    pub metric_ids: &'a [String],
    pub source_id: &'a str,
    pub detail_level: AgentDataDetailLevel,
    pub owner_date: Option<NaiveDate>,
    pub start_time: Option<DateTime<Utc>>,
    pub end_time: Option<DateTime<Utc>>,
}

fn validate_identifiers(
    values: &[String],
    maximum_count: usize,
    maximum_bytes: usize,
    message: &'static str,
) -> Result<(), &'static str> {
    let unique = values.iter().collect::<BTreeSet<_>>();
    if values.is_empty()
        || values.len() > maximum_count
        || unique.len() != values.len()
        || values.iter().any(|value| {
            value.is_empty() || value.len() > maximum_bytes || value.chars().any(char::is_control)
        })
    {
        return Err(message);
    }
    Ok(())
}

fn validate_digest(value: &str) -> Result<(), &'static str> {
    if value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        Ok(())
    } else {
        Err("invalid agent data identifier")
    }
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone as _;
    use serde_json::json;

    use super::*;

    const GRANT_FIXTURE: &str = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../../packages/contracts/agent-data/v1/fixtures/grant-explicit.json"
    ));
    const QUERY_FIXTURE: &str = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../../packages/contracts/agent-data/v1/fixtures/query-records.json"
    ));

    #[test]
    fn explicit_grant_requires_every_attributed_metric() {
        let grant = AgentDataGrant::from_value(json!({
            "schema": AGENT_DATA_GRANT_SCHEMA,
            "schema_version": 1,
            "metrics": {"type": "explicit", "metric_ids": ["steps"]},
            "sources": {"type": "all_available"},
            "dates": {"type": "all_available"},
            "times": {"type": "all_available"},
            "detail_levels": ["lossless"],
            "bulk_download": false
        }))
        .unwrap();
        let metric_ids = vec!["steps".to_owned(), "distance".to_owned()];
        assert!(!grant.allows_record(&AgentDataRecordScope {
            metric_ids: &metric_ids,
            source_id: "apple_health",
            detail_level: AgentDataDetailLevel::Lossless,
            owner_date: None,
            start_time: None,
            end_time: None,
        }));
    }

    #[test]
    fn scoped_instants_exclude_records_without_time() {
        let selection = AgentDataTimeSelection::Exact {
            start_inclusive: Utc.with_ymd_and_hms(2026, 3, 15, 0, 0, 0).unwrap(),
            end_exclusive: Utc.with_ymd_and_hms(2026, 3, 16, 0, 0, 0).unwrap(),
        };
        assert!(!selection.matches(None, None));
        assert!(selection.matches(
            Some(Utc.with_ymd_and_hms(2026, 3, 15, 12, 0, 0).unwrap()),
            None
        ));
    }

    #[test]
    fn whole_artifacts_require_an_explicit_unrestricted_grant() {
        let grant = AgentDataGrant::from_value(json!({
            "schema": AGENT_DATA_GRANT_SCHEMA,
            "schema_version": 1,
            "metrics": {"type": "all_available"},
            "sources": {"type": "all_available"},
            "dates": {"type": "all_available"},
            "times": {"type": "all_available"},
            "detail_levels": ["common", "lossless"],
            "bulk_download": true
        }))
        .unwrap();
        assert!(grant.allows_full_artifacts());
    }

    #[test]
    fn public_contract_fixtures_decode_through_the_runtime_types() {
        let grant = AgentDataGrant::from_value(serde_json::from_str(GRANT_FIXTURE).unwrap());
        assert!(grant.is_ok());
        let query = AgentDataQueryRequest::from_value(serde_json::from_str(QUERY_FIXTURE).unwrap())
            .unwrap();
        assert_eq!(query.operation_name(), "records");
    }
}
