//! Versioned, deterministic post-capture semantic input and reduction engine.
//!
//! Native code owns HealthKit/Health Connect capture. This module consumes bounded, synthetic or
//! captured facts after that boundary and owns selection filtering, deterministic reduction, unit
//! normalization, shared derivations, and Apple period roll-ups. It performs no I/O.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use chrono::{Datelike, Duration, NaiveDate};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{
    CANONICAL_MODEL_VERSION, CoreError, REGISTRY_SHA256, REGISTRY_VERSION, SEMANTIC_INPUT_VERSION,
    SEMANTIC_RESULT_CORE_API_VERSION,
};

/// Maximum semantic-session configuration size.
pub const MAX_CONFIG_BYTES: usize = 256 * 1024;
/// Maximum one-batch input size.
pub const MAX_BATCH_BYTES: usize = 1024 * 1024;
/// Maximum records in one batch.
pub const MAX_BATCH_RECORDS: usize = 4_096;
/// Maximum serialized bytes for one record.
pub const MAX_RECORD_BYTES: usize = 64 * 1024;
/// Maximum selected native IDs.
pub const MAX_SELECTION_IDS: usize = 512;
/// Maximum records retained by one bounded session.
pub const MAX_SESSION_RECORDS: usize = 100_000;
/// Maximum input bytes accepted over one bounded session.
pub const MAX_SESSION_BYTES: usize = 32 * 1024 * 1024;
/// Maximum distinct owner dates accumulated by one session. Individual batches remain bounded.
pub const MAX_OWNER_DATES: usize = 10_000;
/// Maximum extension references on one record.
pub const MAX_EXTENSIONS_PER_RECORD: usize = 32;
/// Maximum UTF-8 bytes in one opaque extension retention token.
pub const MAX_EXTENSION_TOKEN_BYTES: usize = 128;

const REGISTRY_BYTES: &[u8] = include_bytes!("../registry/metric-registry-v1.json");

/// Closed output profiles. Profiles are never inferred from platform or app version.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticProfile {
    AppleHealthDataV8,
    AndroidFrozenV4,
    AndroidAnalyticalV5,
}

impl SemanticProfile {
    fn id(self) -> &'static str {
        match self {
            Self::AppleHealthDataV8 => "apple_health_data_v8",
            Self::AndroidFrozenV4 => "android_frozen_v4",
            Self::AndroidAnalyticalV5 => "android_analytical_v5",
        }
    }

    fn platform(self) -> &'static str {
        match self {
            Self::AppleHealthDataV8 => "apple",
            Self::AndroidFrozenV4 | Self::AndroidAnalyticalV5 => "android",
        }
    }
}

/// Requested Apple period reductions. Android profiles reject period requests.
#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RollupPeriod {
    IsoWeek,
    CalendarMonth,
    CalendarYear,
    Range,
}

/// Explicit civil bounds for a range reduction. These are operation inputs,
/// not values inferred from successfully received owner dates.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RollupRange {
    pub start_date: String,
    pub end_date: String,
}

/// Immutable configuration for one ephemeral semantic session.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticSessionConfig {
    pub schema: String,
    pub semantic_input_version: u32,
    pub canonical_model_version: u32,
    pub registry_version: u32,
    pub registry_sha256: String,
    pub profile_revision: u32,
    pub session_id: String,
    pub profile: SemanticProfile,
    pub calendar_time_zone: String,
    pub selected_selection_ids: Vec<String>,
    pub disabled_output_keys: Vec<String>,
    pub retain_platform_extensions: bool,
    pub rollup_periods: Vec<RollupPeriod>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rollup_range: Option<RollupRange>,
}

/// One bounded, ordered batch. `final_batch` finalizes daily and period results.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticBatch {
    pub schema: String,
    pub semantic_input_version: u32,
    pub session_id: String,
    pub batch_index: u32,
    pub final_batch: bool,
    pub owner_dates: Vec<String>,
    pub records: Vec<SemanticRecord>,
}

/// Exact instant independent from display formatting or locale.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExactTimestamp {
    pub epoch_seconds: String,
    pub nanoseconds: u32,
    pub source_utc_offset_seconds: Option<i32>,
    pub calendar_utc_offset_seconds: i32,
}

/// Exact numeric representation. Binary values cross FFI as raw IEEE-754 bits.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "representation", rename_all = "snake_case", deny_unknown_fields)]
pub enum ExactNumber {
    Binary64 { bits: String },
    SignedInteger { decimal: String },
    UnsignedInteger { decimal: String },
}

/// Stable internal unit ID. Public labels remain profile renderer metadata.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExactUnit {
    pub id: String,
}

/// Typed semantic value. Missing values are represented by an absent record, never a magic zero.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "value_type", rename_all = "snake_case", deny_unknown_fields)]
pub enum SemanticValue {
    Number {
        number: ExactNumber,
        unit: ExactUnit,
    },
    Text {
        text: String,
    },
    Boolean {
        boolean: bool,
    },
    TextList {
        items: Vec<String>,
    },
}

/// Post-capture fact kind.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticRecordKind {
    Observation,
    SdkAggregate,
    Workout,
    StateOfMind,
    Category,
    ExtensionRef,
}

/// Directly selected records and dependency records use separate attribution.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SelectionAttribution {
    Direct,
    Dependency,
}

/// Deterministic daily reducer selected for one typed fact.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AggregationRule {
    PassThrough,
    Sum,
    Average,
    Minimum,
    Maximum,
    Latest,
    Count,
    DurationSum,
    WeightedAverage,
    Union,
    Histogram,
    TimeOfDay,
}

/// Namespaced token for a native-owned structure that is not safely generalized.
#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticExtensionRef {
    pub namespace: String,
    pub version: u32,
    pub retention_token: String,
    pub selection_ids: Vec<String>,
}

/// One semantic fact. `output_key` names a profile registry projection, not a rendered field.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticRecord {
    pub record_id: String,
    pub source_ordinal: String,
    pub owner_date: String,
    pub semantic_id: String,
    pub selection_ids: Vec<String>,
    pub attribution: SelectionAttribution,
    pub kind: SemanticRecordKind,
    pub output_key: Option<String>,
    pub aggregation: AggregationRule,
    pub start: Option<ExactTimestamp>,
    pub end: Option<ExactTimestamp>,
    pub value: Option<SemanticValue>,
    pub weight: Option<ExactNumber>,
    #[serde(default)]
    pub attributes: BTreeMap<String, SemanticValue>,
    #[serde(default)]
    pub extensions: Vec<SemanticExtensionRef>,
}

/// Session lifecycle represented in canonical results.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticResultState {
    Processing,
    Completed,
    Cancelled,
}

/// One reduced daily typed value.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticDailyValue {
    pub output_key: String,
    pub semantic_id: String,
    pub aggregation: AggregationRule,
    pub value: SemanticValue,
    pub source_record_ids: Vec<String>,
}

/// One owner-date result.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticDayResult {
    pub owner_date: String,
    pub values: Vec<SemanticDailyValue>,
}

/// One period window.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticRollupResult {
    pub period: RollupPeriod,
    pub start_date: String,
    pub end_date: String,
    pub calendar_time_zone: String,
    pub source_dates: Vec<String>,
    pub values: Vec<SemanticRollupValue>,
}

/// Typed roll-up value and statistics; formatting remains native until M5.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticRollupValue {
    pub output_key: String,
    pub rule: String,
    pub primary_value: SemanticValue,
    pub days_counted: u32,
    pub statistics: BTreeMap<String, SemanticValue>,
}

/// Retained native extension reference returned without inspecting its payload.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RetainedSemanticExtension {
    pub owner_date: String,
    pub record_id: String,
    pub extension: SemanticExtensionRef,
}

/// Canonical, health-data-bearing internal result. Production diagnostics use hashes/counts only.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticResult {
    pub schema: String,
    pub semantic_input_version: u32,
    pub canonical_model_version: u32,
    pub core_api_version: u32,
    pub registry_sha256: String,
    pub profile_revision: u32,
    pub session_id: String,
    pub profile: SemanticProfile,
    pub state: SemanticResultState,
    pub next_batch_index: u32,
    pub records_accepted: u64,
    pub records_filtered: u64,
    pub days: Vec<SemanticDayResult>,
    pub rollups: Vec<SemanticRollupResult>,
    pub retained_extensions: Vec<RetainedSemanticExtension>,
}

#[derive(Clone, Debug)]
struct StoredRecord {
    ordinal: u64,
    date: NaiveDate,
    record: SemanticRecord,
}

#[derive(Clone, Debug)]
struct ProfileOutput {
    selection_ids: BTreeSet<String>,
    unit: String,
    daily_aggregation: String,
    rollup: String,
    ordinal: usize,
}

#[derive(Clone, Debug)]
struct ProfileIndex {
    semantic_to_selection: HashMap<String, String>,
    valid_selections: HashSet<String>,
    outputs: HashMap<String, ProfileOutput>,
}

#[derive(Debug, Deserialize)]
struct RawRegistry {
    metrics: Vec<RawMetric>,
    profiles: Vec<RawProfile>,
}

#[derive(Debug, Deserialize)]
struct RawMetric {
    semantic_id: String,
    apple: RawBinding,
    android: RawBinding,
}

#[derive(Debug, Deserialize)]
struct RawBinding {
    status: String,
    selection_id: Option<String>,
    #[serde(default)]
    source_aggregation: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawProfile {
    id: String,
    outputs: Vec<RawOutput>,
}

#[derive(Debug, Deserialize)]
struct RawOutput {
    key: String,
    #[serde(default)]
    selection_id: Option<String>,
    #[serde(default)]
    selection_ids: Vec<String>,
    #[serde(default)]
    unit: String,
    #[serde(default)]
    daily_aggregation: String,
    #[serde(default)]
    rollup: String,
}

/// Ephemeral, bounded semantic session. It contains no persistence or platform handles.
#[derive(Clone)]
pub struct SemanticSession {
    config: SemanticSessionConfig,
    profile: ProfileIndex,
    next_batch_index: u32,
    last_ordinal: Option<u64>,
    last_owner_date: Option<NaiveDate>,
    last_declared_owner_date: Option<NaiveDate>,
    owner_dates: BTreeSet<NaiveDate>,
    record_ids: HashSet<String>,
    records: Vec<StoredRecord>,
    records_filtered: u64,
    bytes_accepted: usize,
    terminal: bool,
}

impl SemanticSession {
    /// Create a session from bounded JSON configuration bytes.
    ///
    /// # Errors
    /// Returns stable, health-free semantic contract/version/profile errors.
    pub fn from_json(config_bytes: &[u8]) -> Result<Self, CoreError> {
        if config_bytes.len() > MAX_CONFIG_BYTES {
            return Err(CoreError::SemanticConfigTooLarge);
        }
        let config: SemanticSessionConfig =
            serde_json::from_slice(config_bytes).map_err(|_| CoreError::InvalidSemanticConfig)?;
        validate_config(&config)?;
        let profile = build_profile_index(config.profile)?;
        if config
            .selected_selection_ids
            .iter()
            .any(|selection| !profile.valid_selections.contains(selection))
            || config
                .disabled_output_keys
                .iter()
                .any(|key| !profile.outputs.contains_key(key))
        {
            return Err(CoreError::InvalidSemanticConfig);
        }
        if config.profile != SemanticProfile::AppleHealthDataV8 && !config.rollup_periods.is_empty()
        {
            return Err(CoreError::UnsupportedSemanticOperation);
        }
        Ok(Self {
            config,
            profile,
            next_batch_index: 0,
            last_ordinal: None,
            last_owner_date: None,
            last_declared_owner_date: None,
            owner_dates: BTreeSet::new(),
            record_ids: HashSet::new(),
            records: Vec::new(),
            records_filtered: 0,
            bytes_accepted: 0,
            terminal: false,
        })
    }

    /// Process one coarse batch and return canonical compact JSON result bytes.
    ///
    /// The cancellation probe is checked before parsing, at least every 64 records, and before
    /// daily/period reduction. A cancellation result is terminal and clears retained records.
    ///
    /// # Errors
    /// Returns stable bounded-input, sequencing, validation, or terminal-session errors.
    pub fn process_batch(
        &mut self,
        batch_bytes: &[u8],
        is_cancelled: impl Fn() -> bool,
    ) -> Result<Vec<u8>, CoreError> {
        let mut working = self.clone();
        let result = working.process_batch_inner(batch_bytes, &is_cancelled);
        if result.is_ok() {
            *self = working;
        }
        result
    }

    fn process_batch_inner(
        &mut self,
        batch_bytes: &[u8],
        is_cancelled: &impl Fn() -> bool,
    ) -> Result<Vec<u8>, CoreError> {
        if self.terminal {
            return Err(CoreError::SemanticSessionTerminal);
        }
        if is_cancelled() {
            return self.cancel_result();
        }
        if batch_bytes.len() > MAX_BATCH_BYTES {
            return Err(CoreError::SemanticBatchTooLarge);
        }
        if self.bytes_accepted.saturating_add(batch_bytes.len()) > MAX_SESSION_BYTES {
            return Err(CoreError::SemanticLimitExceeded);
        }
        let batch: SemanticBatch =
            serde_json::from_slice(batch_bytes).map_err(|_| CoreError::InvalidSemanticBatch)?;
        self.validate_batch_header(&batch)?;
        let declared_owner_dates = self.register_owner_dates(&batch.owner_dates)?;
        if batch.records.len() > MAX_BATCH_RECORDS
            || self.records.len().saturating_add(batch.records.len()) > MAX_SESSION_RECORDS
        {
            return Err(CoreError::SemanticLimitExceeded);
        }

        for (index, record) in batch.records.into_iter().enumerate() {
            if index % 64 == 0 && is_cancelled() {
                return self.cancel_result();
            }
            if serde_json::to_vec(&record)
                .map_err(|_| CoreError::InvalidSemanticBatch)?
                .len()
                > MAX_RECORD_BYTES
            {
                return Err(CoreError::SemanticLimitExceeded);
            }
            let stored = self.validate_record(record, &declared_owner_dates)?;
            if self.should_retain(&stored.record) {
                self.records.push(stored);
            } else {
                self.records_filtered = self.records_filtered.saturating_add(1);
            }
        }

        self.bytes_accepted += batch_bytes.len();
        self.next_batch_index = self.next_batch_index.saturating_add(1);
        if !batch.final_batch {
            return canonical_result_bytes(&self.result(
                SemanticResultState::Processing,
                vec![],
                vec![],
            ));
        }
        if is_cancelled() {
            return self.cancel_result();
        }

        let Some(days) = self.reduce_days(is_cancelled)? else {
            return self.cancel_result();
        };
        if is_cancelled() {
            return self.cancel_result();
        }
        let Some(rollups) = self.reduce_rollups(&days, is_cancelled)? else {
            return self.cancel_result();
        };
        let extensions = self.retained_extensions();
        self.terminal = true;
        canonical_result_bytes(&self.result_with_extensions(
            SemanticResultState::Completed,
            days,
            rollups,
            extensions,
        ))
    }

    fn validate_batch_header(&self, batch: &SemanticBatch) -> Result<(), CoreError> {
        if batch.schema != "healthmd.semantic_input"
            || batch.semantic_input_version != SEMANTIC_INPUT_VERSION
            || batch.session_id != self.config.session_id
        {
            return Err(CoreError::InvalidSemanticBatch);
        }
        if batch.batch_index != self.next_batch_index {
            return Err(CoreError::SemanticSequenceInvalid);
        }
        Ok(())
    }

    fn register_owner_dates(
        &mut self,
        values: &[String],
    ) -> Result<BTreeSet<NaiveDate>, CoreError> {
        if values.len() > MAX_OWNER_DATES {
            return Err(CoreError::SemanticLimitExceeded);
        }
        let mut dates = BTreeSet::new();
        let mut previous = self.last_declared_owner_date;
        for value in values {
            let date = parse_date(value)?;
            if let Some(range) = &self.config.rollup_range {
                let start = parse_date(&range.start_date)?;
                let end = parse_date(&range.end_date)?;
                if date < start || date > end {
                    return Err(CoreError::InvalidSemanticBatch);
                }
            }
            if previous.is_some_and(|prior| date < prior) || !dates.insert(date) {
                return Err(CoreError::SemanticSequenceInvalid);
            }
            previous = Some(date);
            self.owner_dates.insert(date);
        }
        if self.owner_dates.len() > MAX_OWNER_DATES {
            return Err(CoreError::SemanticLimitExceeded);
        }
        self.last_declared_owner_date = previous;
        Ok(dates)
    }

    #[allow(clippy::too_many_lines)]
    fn validate_record(
        &mut self,
        record: SemanticRecord,
        declared_owner_dates: &BTreeSet<NaiveDate>,
    ) -> Result<StoredRecord, CoreError> {
        if !valid_identifier(&record.record_id, 128)
            || !valid_identifier(&record.semantic_id, 128)
            || record.selection_ids.is_empty()
            || record.selection_ids.len() > MAX_SELECTION_IDS
            || record.selection_ids.iter().collect::<HashSet<_>>().len()
                != record.selection_ids.len()
            || record.selection_ids.iter().any(|value| {
                !valid_identifier(value, 128) || !self.profile.valid_selections.contains(value)
            })
            || record.extensions.len() > MAX_EXTENSIONS_PER_RECORD
            || record.attributes.len() > 64
        {
            return Err(CoreError::InvalidSemanticBatch);
        }
        if !self.record_ids.insert(record.record_id.clone()) {
            return Err(CoreError::SemanticSequenceInvalid);
        }
        let ordinal = parse_canonical_u64(&record.source_ordinal)?;
        if self
            .last_ordinal
            .is_some_and(|previous| ordinal <= previous)
        {
            return Err(CoreError::SemanticSequenceInvalid);
        }
        let date = parse_date(&record.owner_date)?;
        if !declared_owner_dates.contains(&date)
            || self.last_owner_date.is_some_and(|previous| date < previous)
        {
            return Err(CoreError::SemanticSequenceInvalid);
        }
        self.last_ordinal = Some(ordinal);
        self.last_owner_date = Some(date);
        self.owner_dates.insert(date);
        if self.owner_dates.len() > MAX_OWNER_DATES {
            return Err(CoreError::SemanticLimitExceeded);
        }

        if let Some(timestamp) = &record.start {
            validate_timestamp(timestamp)?;
        }
        if let Some(timestamp) = &record.end {
            validate_timestamp(timestamp)?;
        }
        if let (Some(start), Some(end)) = (&record.start, &record.end) {
            if timestamp_key(end)? < timestamp_key(start)? {
                return Err(CoreError::InvalidSemanticBatch);
            }
        }
        if let Some(value) = &record.value {
            validate_value(value)?;
        }
        if let Some(weight) = &record.weight {
            validate_number(weight)?;
        }
        for value in record.attributes.values() {
            validate_value(value)?;
        }
        for extension in &record.extensions {
            validate_extension(extension)?;
            if extension
                .selection_ids
                .iter()
                .any(|selection| !record.selection_ids.contains(selection))
            {
                return Err(CoreError::InvalidSemanticBatch);
            }
        }

        let expected_selection = self
            .profile
            .semantic_to_selection
            .get(&record.semantic_id)
            .ok_or(CoreError::InvalidSemanticBatch)?;
        if !record.selection_ids.contains(expected_selection) {
            return Err(CoreError::InvalidSemanticBatch);
        }
        if record.kind == SemanticRecordKind::ExtensionRef {
            if record.output_key.is_some() || record.value.is_some() {
                return Err(CoreError::InvalidSemanticBatch);
            }
        } else {
            if record.aggregation == AggregationRule::PassThrough
                && record.kind != SemanticRecordKind::SdkAggregate
            {
                return Err(CoreError::InvalidSemanticBatch);
            }
            let output_key = record
                .output_key
                .as_ref()
                .ok_or(CoreError::InvalidSemanticBatch)?;
            let output = self
                .profile
                .outputs
                .get(output_key)
                .ok_or(CoreError::InvalidSemanticBatch)?;
            let record_selections = record
                .selection_ids
                .iter()
                .cloned()
                .collect::<BTreeSet<_>>();
            let blood_pressure_pair = record_selections.len() == 2
                && record_selections.iter().any(|id| id.contains("systolic"))
                && record_selections.iter().any(|id| id.contains("diastolic"));
            if !output.selection_ids.contains(expected_selection)
                || (!record_selections.is_subset(&output.selection_ids) && !blood_pressure_pair)
                || record.value.is_none()
            {
                return Err(CoreError::InvalidSemanticBatch);
            }
            validate_aggregation_compatibility(
                record.aggregation,
                reviewed_daily_aggregation(output_key, &output.daily_aggregation),
            )?;
        }

        Ok(StoredRecord {
            ordinal,
            date,
            record,
        })
    }

    fn should_retain(&self, record: &SemanticRecord) -> bool {
        let selected: HashSet<&str> = self
            .config
            .selected_selection_ids
            .iter()
            .map(String::as_str)
            .collect();
        let matching = record
            .selection_ids
            .iter()
            .filter(|selection| selected.contains(selection.as_str()))
            .count();
        if record.kind == SemanticRecordKind::ExtensionRef
            && !self.config.retain_platform_extensions
        {
            return false;
        }
        let output_is_disabled = record
            .output_key
            .as_ref()
            .is_some_and(|key| self.config.disabled_output_keys.contains(key));
        if selected.contains("bmi")
            && !self
                .config
                .disabled_output_keys
                .iter()
                .any(|key| key == "bmi")
            && record
                .selection_ids
                .iter()
                .any(|id| matches!(id.as_str(), "weight" | "height"))
        {
            return true;
        }
        if output_is_disabled {
            return false;
        }
        if record
            .selection_ids
            .iter()
            .any(|id| id.contains("systolic"))
            && record
                .selection_ids
                .iter()
                .any(|id| id.contains("diastolic"))
        {
            return matching == record.selection_ids.len();
        }
        match record.attribution {
            SelectionAttribution::Direct | SelectionAttribution::Dependency => matching > 0,
        }
    }

    fn reduce_days(
        &self,
        is_cancelled: &impl Fn() -> bool,
    ) -> Result<Option<Vec<SemanticDayResult>>, CoreError> {
        let mut grouped: BTreeMap<NaiveDate, BTreeMap<String, Vec<&StoredRecord>>> =
            BTreeMap::new();
        for record in &self.records {
            if record.record.kind == SemanticRecordKind::ExtensionRef {
                continue;
            }
            let key = record
                .record
                .output_key
                .as_ref()
                .ok_or(CoreError::InvalidSemanticBatch)?;
            grouped
                .entry(record.date)
                .or_default()
                .entry(key.clone())
                .or_default()
                .push(record);
        }

        if !self.config.selected_selection_ids.is_empty() {
            for date in &self.owner_dates {
                grouped.entry(*date).or_default();
            }
        }
        let mut days = Vec::with_capacity(grouped.len());
        for (date, outputs) in grouped {
            if is_cancelled() {
                return Ok(None);
            }
            let mut values = Vec::with_capacity(outputs.len() + 1);
            for (key, records) in outputs {
                values.push(reduce_record_group(&self.profile, &key, &records)?);
            }
            self.derive_bmi(&mut values)?;
            let selected = self
                .config
                .selected_selection_ids
                .iter()
                .cloned()
                .collect::<BTreeSet<_>>();
            values.retain(|value| {
                !self.config.disabled_output_keys.contains(&value.output_key)
                    && self
                        .profile
                        .outputs
                        .get(&value.output_key)
                        .is_some_and(|output| !output.selection_ids.is_disjoint(&selected))
            });
            values.sort_by_key(|value| {
                self.profile
                    .outputs
                    .get(&value.output_key)
                    .map_or(usize::MAX, |output| output.ordinal)
            });
            days.push(SemanticDayResult {
                owner_date: date.format("%Y-%m-%d").to_string(),
                values,
            });
        }
        Ok(Some(days))
    }

    fn derive_bmi(&self, values: &mut Vec<SemanticDailyValue>) -> Result<(), CoreError> {
        if values.iter().any(|value| value.output_key == "bmi")
            || !self
                .config
                .selected_selection_ids
                .iter()
                .any(|selection| selection == "bmi")
            || !self.profile.outputs.contains_key("bmi")
            || self
                .config
                .disabled_output_keys
                .iter()
                .any(|key| key == "bmi")
        {
            return Ok(());
        }
        let weight = daily_numeric(values, "weight_kg")?;
        let height = daily_numeric(values, "height_m")?;
        if let (Some(weight), Some(height)) = (weight, height) {
            if height > 0.0 {
                values.push(SemanticDailyValue {
                    output_key: "bmi".to_owned(),
                    semantic_id: "bmi".to_owned(),
                    aggregation: AggregationRule::Latest,
                    value: binary_value(weight / (height * height), "unitless")?,
                    source_record_ids: values
                        .iter()
                        .filter(|value| {
                            value.output_key == "weight_kg" || value.output_key == "height_m"
                        })
                        .flat_map(|value| value.source_record_ids.clone())
                        .collect(),
                });
            }
        }
        Ok(())
    }

    fn reduce_rollups(
        &self,
        days: &[SemanticDayResult],
        is_cancelled: &impl Fn() -> bool,
    ) -> Result<Option<Vec<SemanticRollupResult>>, CoreError> {
        if self.config.rollup_periods.is_empty() {
            return Ok(Some(Vec::new()));
        }
        if self.config.profile != SemanticProfile::AppleHealthDataV8 {
            return Err(CoreError::UnsupportedSemanticOperation);
        }
        let mut results = Vec::new();
        for period in &self.config.rollup_periods {
            if is_cancelled() {
                return Ok(None);
            }
            let mut windows: BTreeMap<(NaiveDate, NaiveDate), Vec<&SemanticDayResult>> =
                BTreeMap::new();
            if *period == RollupPeriod::Range {
                let range = self
                    .config
                    .rollup_range
                    .as_ref()
                    .ok_or(CoreError::InvalidSemanticConfig)?;
                let start = parse_date(&range.start_date)?;
                let end = parse_date(&range.end_date)?;
                let source_days = days
                    .iter()
                    .filter(|day| {
                        parse_date(&day.owner_date).is_ok_and(|date| date >= start && date <= end)
                    })
                    .collect::<Vec<_>>();
                windows.insert((start, end), source_days);
            } else {
                for day in days {
                    let date = parse_date(&day.owner_date)?;
                    windows
                        .entry(period_window(date, *period))
                        .or_default()
                        .push(day);
                }
            }
            for ((start, end), source_days) in windows {
                if is_cancelled() {
                    return Ok(None);
                }
                let mut by_key: BTreeMap<String, Vec<(&str, &SemanticDailyValue)>> =
                    BTreeMap::new();
                for day in &source_days {
                    for value in &day.values {
                        by_key
                            .entry(value.output_key.clone())
                            .or_default()
                            .push((&day.owner_date, value));
                    }
                }
                let mut values = Vec::new();
                for (key, daily) in by_key {
                    let rule = self
                        .profile
                        .outputs
                        .get(&key)
                        .map(|output| output.rollup.as_str())
                        .ok_or(CoreError::InvalidSemanticBatch)?;
                    values.push(reduce_rollup_value(&key, rule, &daily, &source_days)?);
                }
                values.sort_by_key(|value| {
                    self.profile
                        .outputs
                        .get(&value.output_key)
                        .map_or(usize::MAX, |output| output.ordinal)
                });
                if values.is_empty() {
                    continue;
                }
                results.push(SemanticRollupResult {
                    period: *period,
                    start_date: start.format("%Y-%m-%d").to_string(),
                    end_date: end.format("%Y-%m-%d").to_string(),
                    calendar_time_zone: self.config.calendar_time_zone.clone(),
                    source_dates: source_days
                        .iter()
                        .map(|day| day.owner_date.clone())
                        .collect(),
                    values,
                });
            }
        }
        results.sort_by(|left, right| {
            left.start_date
                .cmp(&right.start_date)
                .then(left.period.cmp(&right.period))
        });
        Ok(Some(results))
    }

    fn retained_extensions(&self) -> Vec<RetainedSemanticExtension> {
        if !self.config.retain_platform_extensions {
            return Vec::new();
        }
        let selected = self
            .config
            .selected_selection_ids
            .iter()
            .map(String::as_str)
            .collect::<HashSet<_>>();
        let mut retained = self
            .records
            .iter()
            .flat_map(|stored| {
                stored
                    .record
                    .extensions
                    .iter()
                    .filter(|extension| extension_is_selected(extension, &selected))
                    .cloned()
                    .map(move |extension| RetainedSemanticExtension {
                        owner_date: stored.record.owner_date.clone(),
                        record_id: stored.record.record_id.clone(),
                        extension,
                    })
            })
            .collect::<Vec<_>>();
        retained.sort_by(|left, right| {
            left.owner_date
                .cmp(&right.owner_date)
                .then(left.record_id.cmp(&right.record_id))
                .then(left.extension.cmp(&right.extension))
        });
        retained
    }

    fn result(
        &self,
        state: SemanticResultState,
        days: Vec<SemanticDayResult>,
        rollups: Vec<SemanticRollupResult>,
    ) -> SemanticResult {
        self.result_with_extensions(state, days, rollups, Vec::new())
    }

    fn result_with_extensions(
        &self,
        state: SemanticResultState,
        days: Vec<SemanticDayResult>,
        rollups: Vec<SemanticRollupResult>,
        retained_extensions: Vec<RetainedSemanticExtension>,
    ) -> SemanticResult {
        SemanticResult {
            schema: "healthmd.semantic_result".to_owned(),
            semantic_input_version: SEMANTIC_INPUT_VERSION,
            canonical_model_version: CANONICAL_MODEL_VERSION,
            core_api_version: SEMANTIC_RESULT_CORE_API_VERSION,
            registry_sha256: REGISTRY_SHA256.to_owned(),
            profile_revision: self.config.profile_revision,
            session_id: self.config.session_id.clone(),
            profile: self.config.profile,
            state,
            next_batch_index: self.next_batch_index,
            records_accepted: u64::try_from(self.records.len()).unwrap_or(u64::MAX),
            records_filtered: self.records_filtered,
            days,
            rollups,
            retained_extensions,
        }
    }

    fn cancel_result(&mut self) -> Result<Vec<u8>, CoreError> {
        self.records.clear();
        self.record_ids.clear();
        self.terminal = true;
        canonical_result_bytes(&self.result(SemanticResultState::Cancelled, vec![], vec![]))
    }
}

fn validate_config(config: &SemanticSessionConfig) -> Result<(), CoreError> {
    if config.schema != "healthmd.semantic_session_config"
        || config.semantic_input_version != SEMANTIC_INPUT_VERSION
        || config.canonical_model_version != CANONICAL_MODEL_VERSION
        || config.registry_version != REGISTRY_VERSION
        || config.registry_sha256 != REGISTRY_SHA256
        || !matches!(config.profile_revision, 1 | 2)
        || !valid_identifier(&config.session_id, 128)
        || config.calendar_time_zone.len() > 64
        || config.calendar_time_zone.parse::<chrono_tz::Tz>().is_err()
        || config.selected_selection_ids.len() > MAX_SELECTION_IDS
        || config
            .selected_selection_ids
            .iter()
            .any(|selection| !valid_identifier(selection, 128))
        || config
            .selected_selection_ids
            .iter()
            .collect::<HashSet<_>>()
            .len()
            != config.selected_selection_ids.len()
        || config.disabled_output_keys.len() > MAX_SELECTION_IDS
        || config
            .disabled_output_keys
            .iter()
            .any(|key| !valid_identifier(key, 128))
        || config
            .disabled_output_keys
            .iter()
            .collect::<HashSet<_>>()
            .len()
            != config.disabled_output_keys.len()
        || config.rollup_periods.iter().collect::<BTreeSet<_>>().len()
            != config.rollup_periods.len()
    {
        return Err(CoreError::InvalidSemanticConfig);
    }
    let contains_range = config.rollup_periods.contains(&RollupPeriod::Range);
    if contains_range != config.rollup_range.is_some()
        || (contains_range
            && (config.rollup_periods.len() != 1
                || config.semantic_input_version != SEMANTIC_INPUT_VERSION
                || config.profile_revision != 2
                || config.profile != SemanticProfile::AppleHealthDataV8))
    {
        return Err(CoreError::InvalidSemanticConfig);
    }
    if !contains_range && config.profile_revision != 1 {
        return Err(CoreError::InvalidSemanticConfig);
    }
    if let Some(range) = &config.rollup_range {
        let start = parse_date(&range.start_date)?;
        let end = parse_date(&range.end_date)?;
        let days = (end - start).num_days() + 1;
        let maximum_days =
            i64::try_from(MAX_OWNER_DATES).map_err(|_| CoreError::InvalidSemanticConfig)?;
        if start > end || days <= 0 || days > maximum_days {
            return Err(CoreError::InvalidSemanticConfig);
        }
    }
    Ok(())
}

fn build_profile_index(profile: SemanticProfile) -> Result<ProfileIndex, CoreError> {
    let registry: RawRegistry =
        serde_json::from_slice(REGISTRY_BYTES).map_err(|_| CoreError::InvalidRegistry)?;
    let mut semantic_to_selection = HashMap::new();
    let mut valid_selections = HashSet::new();
    let mut aggregation_by_selection = HashMap::new();
    for metric in registry.metrics {
        let binding = if profile.platform() == "apple" {
            metric.apple
        } else {
            metric.android
        };
        if binding.status == "backed" {
            let selection = binding.selection_id.ok_or(CoreError::InvalidRegistry)?;
            valid_selections.insert(selection.clone());
            if let Some(aggregation) = binding.source_aggregation {
                aggregation_by_selection.insert(selection.clone(), aggregation);
            }
            semantic_to_selection.insert(metric.semantic_id, selection);
        }
    }
    let raw_profile = registry
        .profiles
        .into_iter()
        .find(|candidate| candidate.id == profile.id())
        .ok_or(CoreError::UnsupportedRegistryProfile)?;
    let outputs = raw_profile
        .outputs
        .into_iter()
        .enumerate()
        .map(|(ordinal, output)| {
            let mut selection_ids = output.selection_ids.into_iter().collect::<BTreeSet<_>>();
            if let Some(selection_id) = output.selection_id {
                selection_ids.insert(selection_id);
            }
            let output_key = output.key;
            let unit = if output.unit.is_empty() {
                inferred_android_output_unit(&output_key).to_owned()
            } else {
                output.unit
            };
            let daily_aggregation = if output.daily_aggregation.is_empty() {
                inferred_android_daily_aggregation(
                    &output_key,
                    &selection_ids,
                    &aggregation_by_selection,
                )
            } else {
                output.daily_aggregation
            };
            if !valid_daily_aggregation_metadata(&daily_aggregation) {
                return Err(CoreError::InvalidRegistry);
            }
            Ok((
                output_key,
                ProfileOutput {
                    selection_ids,
                    unit,
                    daily_aggregation,
                    rollup: output.rollup,
                    ordinal,
                },
            ))
        })
        .collect::<Result<HashMap<_, _>, CoreError>>()?;
    Ok(ProfileIndex {
        semantic_to_selection,
        valid_selections,
        outputs,
    })
}

fn valid_daily_aggregation_metadata(value: &str) -> bool {
    matches!(
        value,
        "sum"
            | "average"
            | "minimum"
            | "maximum"
            | "latest"
            | "count"
            | "duration_sum"
            | "weighted_average"
            | "list"
            | "histogram"
            | "time_of_day"
            | "first_time"
            | "last_time"
            | "category_latest"
    )
}

fn inferred_android_daily_aggregation(
    key: &str,
    selection_ids: &BTreeSet<String>,
    source_aggregations: &HashMap<String, String>,
) -> String {
    let fixed = if matches!(
        key,
        "sleep_bedtime"
            | "sleep_wake"
            | "vo2_max_measurement_method"
            | "menstrual_flow"
            | "cervical_mucus"
            | "cervical_mucus_appearance"
            | "cervical_mucus_sensation"
            | "ovulation_test"
            | "intermenstrual_bleeding"
            | "sexual_activity"
            | "protection_used"
    ) {
        Some("latest")
    } else if key.ends_with("_min") || key == "workout_min_heart_rate" {
        Some("minimum")
    } else if key.ends_with("_max") || key == "workout_max_heart_rate" || key == "workout_max_power"
    {
        Some("maximum")
    } else if key.starts_with("workout_avg_")
        || matches!(key, "workout_running_cadence" | "workout_cycling_cadence")
    {
        Some("weighted_average")
    } else if key == "workouts" {
        Some("list")
    } else if matches!(key, "workout_calories" | "workout_distance_km") {
        Some("sum")
    } else if key.ends_with("_count")
        || matches!(
            key,
            "workout_count" | "planned_workout_count" | "medical_resource_count"
        )
    {
        Some("count")
    } else if key.contains("sleep_") && key.ends_with("_hours")
        || matches!(
            key,
            "workout_minutes" | "menstruation_period_days" | "menstruation_period_hours"
        )
    {
        Some("duration_sum")
    } else {
        None
    };
    fixed.map_or_else(
        || {
            selection_ids
                .iter()
                .find_map(|selection| source_aggregations.get(selection))
                .cloned()
                .unwrap_or_else(|| "latest".to_owned())
        },
        str::to_owned,
    )
}

fn inferred_android_output_unit(key: &str) -> &'static str {
    if key == "steps"
        || key.ends_with("_count")
        || matches!(
            key,
            "flights_climbed" | "wheelchair_pushes" | "swimming_strokes"
        )
    {
        "count"
    } else if key == "weight_kg" {
        "kg"
    } else if key == "height_m" {
        "m"
    } else if matches!(key, "walking_speed" | "running_speed") {
        "m/s"
    } else if matches!(key, "steps_cadence" | "steps_cadence_max") {
        "spm"
    } else if key == "vo2_max" {
        "mL/kg/min"
    } else if key.contains("blood_oxygen") || key.ends_with("_percent") {
        "percent"
    } else if key.ends_with("_km") {
        "km"
    } else if key.ends_with("_hours") {
        "hours"
    } else if key.ends_with("_minutes") || key == "workout_minutes" {
        "minutes"
    } else if key.ends_with("_kg") {
        "kg"
    } else if key.ends_with("_mg") {
        "mg"
    } else if key.ends_with("_ug") || key.ends_with("_mcg") {
        "µg"
    } else if key.ends_with("_g") {
        "g"
    } else if key.ends_with("_l") {
        "L"
    } else if key.contains("temperature") {
        "°C"
    } else {
        ""
    }
}

fn reviewed_daily_aggregation<'a>(output_key: &str, registry_value: &'a str) -> &'a str {
    match output_key {
        "workout_max_heart_rate" | "workout_max_power" => "maximum",
        "workout_min_heart_rate" => "minimum",
        _ => registry_value,
    }
}

fn validate_aggregation_compatibility(
    actual: AggregationRule,
    expected: &str,
) -> Result<(), CoreError> {
    if expected.is_empty() || actual == AggregationRule::PassThrough {
        return Ok(());
    }
    let compatible = matches!(
        (actual, expected),
        (AggregationRule::Sum, "sum" | "cumulative")
            | (AggregationRule::Average, "average" | "discreteAvg")
            | (
                AggregationRule::Minimum,
                "minimum" | "discreteMin" | "first_time"
            )
            | (
                AggregationRule::Maximum,
                "maximum" | "discreteMax" | "last_time"
            )
            | (
                AggregationRule::Latest,
                "latest" | "mostRecent" | "category_latest"
            )
            | (AggregationRule::Count, "count")
            | (AggregationRule::DurationSum, "duration_sum" | "duration")
            | (AggregationRule::WeightedAverage, "weighted_average")
            | (AggregationRule::Union, "list")
            | (AggregationRule::Histogram, "histogram")
            | (AggregationRule::TimeOfDay, "time_of_day")
    );
    if compatible {
        Ok(())
    } else {
        Err(CoreError::InvalidSemanticBatch)
    }
}

fn validate_timestamp(timestamp: &ExactTimestamp) -> Result<(), CoreError> {
    let _ = parse_canonical_i64(&timestamp.epoch_seconds)?;
    if timestamp.nanoseconds > 999_999_999
        || !valid_offset(timestamp.source_utc_offset_seconds)
        || !valid_offset(Some(timestamp.calendar_utc_offset_seconds))
    {
        return Err(CoreError::InvalidSemanticBatch);
    }
    Ok(())
}

fn timestamp_key(timestamp: &ExactTimestamp) -> Result<(i64, u32), CoreError> {
    Ok((
        parse_canonical_i64(&timestamp.epoch_seconds)?,
        timestamp.nanoseconds,
    ))
}

fn valid_offset(offset: Option<i32>) -> bool {
    offset.is_none_or(|value| (-64_800..=64_800).contains(&value))
}

fn validate_number(number: &ExactNumber) -> Result<(), CoreError> {
    match number {
        ExactNumber::Binary64 { bits } => {
            if bits.len() != 16
                || !bits
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
            {
                return Err(CoreError::InvalidSemanticBatch);
            }
            let raw = u64::from_str_radix(bits, 16).map_err(|_| CoreError::InvalidSemanticBatch)?;
            if !f64::from_bits(raw).is_finite() {
                return Err(CoreError::InvalidSemanticBatch);
            }
        }
        ExactNumber::SignedInteger { decimal } => {
            let _ = parse_canonical_i128(decimal)?;
        }
        ExactNumber::UnsignedInteger { decimal } => {
            let _ = parse_canonical_u128(decimal)?;
        }
    }
    Ok(())
}

fn validate_value(value: &SemanticValue) -> Result<(), CoreError> {
    match value {
        SemanticValue::Number { number, unit } => {
            validate_number(number)?;
            if !valid_unit(&unit.id) {
                return Err(CoreError::InvalidSemanticBatch);
            }
        }
        SemanticValue::Text { text } => {
            if text.len() > 8_192 {
                return Err(CoreError::SemanticLimitExceeded);
            }
        }
        SemanticValue::Boolean { .. } => {}
        SemanticValue::TextList { items } => {
            if items.len() > 512
                || items.iter().any(|item| item.len() > 512)
                || items.iter().collect::<BTreeSet<_>>().len() != items.len()
            {
                return Err(CoreError::SemanticLimitExceeded);
            }
        }
    }
    Ok(())
}

fn validate_extension(extension: &SemanticExtensionRef) -> Result<(), CoreError> {
    if !valid_identifier(&extension.namespace, 128)
        || extension.version == 0
        || extension.retention_token.is_empty()
        || extension.retention_token.len() > MAX_EXTENSION_TOKEN_BYTES
        || extension.selection_ids.is_empty()
        || extension.selection_ids.len() > MAX_SELECTION_IDS
        || extension.selection_ids.iter().collect::<HashSet<_>>().len()
            != extension.selection_ids.len()
        || extension
            .selection_ids
            .iter()
            .any(|selection| !valid_identifier(selection, 128))
    {
        return Err(CoreError::InvalidSemanticBatch);
    }
    Ok(())
}

fn extension_is_selected(extension: &SemanticExtensionRef, selected: &HashSet<&str>) -> bool {
    let matching = extension
        .selection_ids
        .iter()
        .filter(|selection| selected.contains(selection.as_str()))
        .count();
    if extension
        .selection_ids
        .iter()
        .any(|selection| selection.contains("systolic"))
        && extension
            .selection_ids
            .iter()
            .any(|selection| selection.contains("diastolic"))
    {
        matching == extension.selection_ids.len()
    } else {
        matching > 0
    }
}

fn valid_unit(unit: &str) -> bool {
    matches!(
        unit,
        "unitless"
            | "count"
            | "second"
            | "minute"
            | "hour"
            | "meter"
            | "kilometer"
            | "mile"
            | "meter_per_second"
            | "kilometer_per_hour"
            | "mile_per_hour"
            | "centimeter"
            | "inch"
            | "kilogram"
            | "pound"
            | "kilogram_per_square_meter"
            | "gram"
            | "milligram"
            | "microgram"
            | "liter"
            | "fluid_ounce"
            | "kilocalorie"
            | "kilocalorie_per_hour_kilogram"
            | "beat_per_minute"
            | "breath_per_minute"
            | "millisecond"
            | "ratio_0_1"
            | "percent_0_100"
            | "degree_celsius"
            | "degree_fahrenheit"
            | "millimeter_hg"
            | "milligram_per_deciliter"
            | "international_unit"
            | "watt"
            | "revolution_per_minute"
            | "step_per_minute"
            | "decibel"
            | "microsiemens"
            | "liter_per_minute"
            | "milliliter_per_kilogram_minute"
            | "time_of_day_minute"
    )
}

fn valid_identifier(value: &str, maximum_bytes: usize) -> bool {
    !value.is_empty()
        && value.len() <= maximum_bytes
        && value.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-' | b':' | b'/' | b'@')
        })
}

fn parse_date(value: &str) -> Result<NaiveDate, CoreError> {
    if value.len() != 10 {
        return Err(CoreError::InvalidSemanticBatch);
    }
    let date = NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| CoreError::InvalidSemanticBatch)?;
    if !(1..=9998).contains(&date.year()) || date.format("%Y-%m-%d").to_string() != value {
        return Err(CoreError::InvalidSemanticBatch);
    }
    Ok(date)
}

fn parse_canonical_u64(value: &str) -> Result<u64, CoreError> {
    if !canonical_unsigned(value) {
        return Err(CoreError::InvalidSemanticBatch);
    }
    value.parse().map_err(|_| CoreError::InvalidSemanticBatch)
}

fn parse_canonical_u128(value: &str) -> Result<u128, CoreError> {
    if !canonical_unsigned(value) {
        return Err(CoreError::InvalidSemanticBatch);
    }
    value.parse().map_err(|_| CoreError::InvalidSemanticBatch)
}

fn parse_canonical_i64(value: &str) -> Result<i64, CoreError> {
    if !canonical_signed(value) {
        return Err(CoreError::InvalidSemanticBatch);
    }
    value.parse().map_err(|_| CoreError::InvalidSemanticBatch)
}

fn parse_canonical_i128(value: &str) -> Result<i128, CoreError> {
    if !canonical_signed(value) {
        return Err(CoreError::InvalidSemanticBatch);
    }
    value.parse().map_err(|_| CoreError::InvalidSemanticBatch)
}

fn canonical_unsigned(value: &str) -> bool {
    !value.is_empty()
        && value.bytes().all(|byte| byte.is_ascii_digit())
        && (value == "0" || !value.starts_with('0'))
}

fn canonical_signed(value: &str) -> bool {
    if let Some(unsigned) = value.strip_prefix('-') {
        unsigned != "0" && canonical_unsigned(unsigned)
    } else {
        canonical_unsigned(value)
    }
}

#[allow(clippy::cast_precision_loss)]
fn number_f64(number: &ExactNumber) -> Result<f64, CoreError> {
    validate_number(number)?;
    let value = match number {
        ExactNumber::Binary64 { bits } => {
            let raw = u64::from_str_radix(bits, 16).map_err(|_| CoreError::InvalidSemanticBatch)?;
            f64::from_bits(raw)
        }
        ExactNumber::SignedInteger { decimal } => decimal
            .parse::<i128>()
            .map_err(|_| CoreError::InvalidSemanticBatch)?
            as f64,
        ExactNumber::UnsignedInteger { decimal } => decimal
            .parse::<u128>()
            .map_err(|_| CoreError::InvalidSemanticBatch)?
            as f64,
    };
    if value.is_finite() {
        Ok(value)
    } else {
        Err(CoreError::InvalidSemanticBatch)
    }
}

fn numeric_value(value: &SemanticValue) -> Result<Option<f64>, CoreError> {
    match value {
        SemanticValue::Number { number, .. } => number_f64(number).map(Some),
        _ => Ok(None),
    }
}

fn binary_value(value: f64, unit: &str) -> Result<SemanticValue, CoreError> {
    if !value.is_finite() || !valid_unit(unit) {
        return Err(CoreError::InvalidSemanticBatch);
    }
    Ok(SemanticValue::Number {
        number: ExactNumber::Binary64 {
            bits: format!("{:016x}", value.to_bits()),
        },
        unit: ExactUnit {
            id: unit.to_owned(),
        },
    })
}

fn normalized_value(value: &SemanticValue, target_unit: &str) -> Result<SemanticValue, CoreError> {
    if target_unit.is_empty() {
        return Ok(value.clone());
    }
    let SemanticValue::Number { number, unit } = value else {
        return if target_internal_unit(target_unit).is_some_and(|unit| unit != "unitless") {
            Err(CoreError::InvalidSemanticBatch)
        } else {
            Ok(value.clone())
        };
    };
    let source = unit.id.as_str();
    let target = target_unit;
    let expected_unit = target_internal_unit(target).ok_or(CoreError::InvalidSemanticBatch)?;
    if source == expected_unit {
        return Ok(value.clone());
    }
    let factor = match (source, target) {
        ("ratio_0_1", "%" | "percent") => 100.0,
        ("meter", "km") => 0.001,
        ("meter", "mi") => 0.000_621_371_192_237_334,
        ("centimeter", "m") => 0.01,
        ("inch", "m") => 0.0254,
        ("pound", "kg") => 0.453_592_37,
        ("fluid_ounce", "L") => 0.029_573_529_562_5,
        ("kilometer_per_hour", "m/s") => 1.0 / 3.6,
        ("mile_per_hour", "m/s") => 0.447_04,
        ("second", "min" | "minutes") => 1.0 / 60.0,
        ("second", "hours") => 1.0 / 3_600.0,
        ("degree_fahrenheit", "°C") => {
            return binary_value((number_f64(number)? - 32.0) * (5.0 / 9.0), "degree_celsius");
        }
        _ => return Err(CoreError::InvalidSemanticBatch),
    };
    binary_value(number_f64(number)? * factor, expected_unit)
}

fn target_internal_unit(target: &str) -> Option<&'static str> {
    match target {
        "unitless" | "kg/m²" => Some(if target == "kg/m²" {
            "kilogram_per_square_meter"
        } else {
            "unitless"
        }),
        "steps" | "count" | "entries" | "drinks" | "events" | "falls" | "floors" | "pushes"
        | "sessions" | "strokes" | "uses" => Some("count"),
        "sec" | "second" | "seconds" => Some("second"),
        "min" | "minute" | "minutes" => Some("minute"),
        "hour" | "hours" => Some("hour"),
        "m" => Some("meter"),
        "km" => Some("kilometer"),
        "mi" => Some("mile"),
        "m/s" => Some("meter_per_second"),
        "kg" => Some("kilogram"),
        "g" => Some("gram"),
        "mg" => Some("milligram"),
        "µg" | "mcg" => Some("microgram"),
        "L" | "l" => Some("liter"),
        "kcal" => Some("kilocalorie"),
        "kcal/hr/kg" => Some("kilocalorie_per_hour_kilogram"),
        "bpm" => Some("beat_per_minute"),
        "breaths/min" => Some("breath_per_minute"),
        "ms" => Some("millisecond"),
        "%" | "percent" => Some("percent_0_100"),
        "°C" => Some("degree_celsius"),
        "mmHg" => Some("millimeter_hg"),
        "mg/dL" => Some("milligram_per_deciliter"),
        "IU" => Some("international_unit"),
        "W" => Some("watt"),
        "rpm" => Some("revolution_per_minute"),
        "spm" => Some("step_per_minute"),
        "cm" => Some("centimeter"),
        "dB" => Some("decibel"),
        "µS" => Some("microsiemens"),
        "L/min" => Some("liter_per_minute"),
        "mL/kg/min" => Some("milliliter_per_kilogram_minute"),
        "time" => Some("time_of_day_minute"),
        _ => None,
    }
}

fn reduce_record_group(
    profile: &ProfileIndex,
    key: &str,
    records: &[&StoredRecord],
) -> Result<SemanticDailyValue, CoreError> {
    let first = records.first().ok_or(CoreError::InvalidSemanticBatch)?;
    let rule = first.record.aggregation;
    if records
        .iter()
        .any(|record| record.record.aggregation != rule)
    {
        return Err(CoreError::InvalidSemanticBatch);
    }
    let output = profile
        .outputs
        .get(key)
        .ok_or(CoreError::InvalidSemanticBatch)?;
    let values = records
        .iter()
        .map(|record| {
            record
                .record
                .value
                .as_ref()
                .ok_or(CoreError::InvalidSemanticBatch)
                .and_then(|value| {
                    if matches!(
                        rule,
                        AggregationRule::Count
                            | AggregationRule::Union
                            | AggregationRule::Histogram
                    ) {
                        Ok(value.clone())
                    } else {
                        normalized_value(value, &output.unit)
                    }
                })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let sdk_count = records
        .iter()
        .filter(|record| record.record.kind == SemanticRecordKind::SdkAggregate)
        .count();
    if sdk_count > 0 && records.len() != 1 {
        return Err(CoreError::InvalidSemanticBatch);
    }

    let value = if sdk_count == 1 || rule == AggregationRule::PassThrough {
        values
            .first()
            .cloned()
            .ok_or(CoreError::InvalidSemanticBatch)?
    } else {
        reduce_values(rule, &values, records)?
    };
    let mut source_record_ids = records
        .iter()
        .map(|record| record.record.record_id.clone())
        .collect::<Vec<_>>();
    source_record_ids.sort();
    Ok(SemanticDailyValue {
        output_key: key.to_owned(),
        semantic_id: first.record.semantic_id.clone(),
        aggregation: rule,
        value,
        source_record_ids,
    })
}

#[allow(clippy::too_many_lines)]
fn reduce_values(
    rule: AggregationRule,
    values: &[SemanticValue],
    records: &[&StoredRecord],
) -> Result<SemanticValue, CoreError> {
    match rule {
        AggregationRule::PassThrough => values
            .first()
            .cloned()
            .ok_or(CoreError::InvalidSemanticBatch),
        AggregationRule::Sum | AggregationRule::DurationSum => {
            if let Some(exact) = reduce_exact_integers(values, ExactIntegerOperation::Sum)? {
                return Ok(exact);
            }
            let numbers = numeric_values(values)?;
            let unit = numeric_unit(values)?;
            binary_value(numbers.iter().sum(), unit)
        }
        AggregationRule::Average => {
            let numbers = numeric_values(values)?;
            let unit = numeric_unit(values)?;
            binary_value(
                numbers.iter().sum::<f64>() / bounded_len_f64(numbers.len())?,
                unit,
            )
        }
        AggregationRule::Minimum => {
            if let Some(exact) = reduce_exact_integers(values, ExactIntegerOperation::Minimum)? {
                return Ok(exact);
            }
            let numbers = numeric_values(values)?;
            let unit = numeric_unit(values)?;
            binary_value(numbers.into_iter().fold(f64::INFINITY, f64::min), unit)
        }
        AggregationRule::Maximum => {
            if let Some(exact) = reduce_exact_integers(values, ExactIntegerOperation::Maximum)? {
                return Ok(exact);
            }
            let numbers = numeric_values(values)?;
            let unit = numeric_unit(values)?;
            binary_value(numbers.into_iter().fold(f64::NEG_INFINITY, f64::max), unit)
        }
        AggregationRule::Latest => {
            let (index, _) = records
                .iter()
                .enumerate()
                .max_by_key(|(_, record)| {
                    record
                        .record
                        .end
                        .as_ref()
                        .or(record.record.start.as_ref())
                        .and_then(|timestamp| timestamp_key(timestamp).ok())
                        .map_or((i64::MIN, 0, record.ordinal), |(seconds, nanos)| {
                            (seconds, nanos, record.ordinal)
                        })
                })
                .ok_or(CoreError::InvalidSemanticBatch)?;
            values
                .get(index)
                .cloned()
                .ok_or(CoreError::InvalidSemanticBatch)
        }
        AggregationRule::Count => Ok(SemanticValue::Number {
            number: ExactNumber::UnsignedInteger {
                decimal: values.len().to_string(),
            },
            unit: ExactUnit {
                id: "count".to_owned(),
            },
        }),
        AggregationRule::WeightedAverage => {
            let mut weighted_sum = 0.0;
            let mut total_weight = 0.0;
            let mut unweighted = Vec::new();
            for (value, record) in values.iter().zip(records) {
                let numeric = numeric_value(value)?.ok_or(CoreError::InvalidSemanticBatch)?;
                unweighted.push(numeric);
                let weight = record
                    .record
                    .weight
                    .as_ref()
                    .map(number_f64)
                    .transpose()?
                    .unwrap_or(1.0)
                    .max(0.0);
                weighted_sum += numeric * weight;
                total_weight += weight;
            }
            let result = if total_weight > 0.0 {
                weighted_sum / total_weight
            } else {
                unweighted.iter().sum::<f64>() / bounded_len_f64(unweighted.len())?
            };
            binary_value(result, numeric_unit(values)?)
        }
        AggregationRule::Union => {
            let mut items = BTreeSet::new();
            for value in values {
                match value {
                    SemanticValue::Text { text } => {
                        items.insert(text.clone());
                    }
                    SemanticValue::TextList { items: values } => {
                        items.extend(values.iter().cloned());
                    }
                    _ => return Err(CoreError::InvalidSemanticBatch),
                }
            }
            Ok(SemanticValue::TextList {
                items: items.into_iter().collect(),
            })
        }
        AggregationRule::Histogram => {
            let mut counts = BTreeMap::<String, u64>::new();
            for value in values {
                let SemanticValue::Text { text } = value else {
                    return Err(CoreError::InvalidSemanticBatch);
                };
                *counts.entry(text.clone()).or_default() += 1;
            }
            Ok(SemanticValue::Text {
                text: counts
                    .into_iter()
                    .map(|(item, count)| format!("{item}: {count}"))
                    .collect::<Vec<_>>()
                    .join(", "),
            })
        }
        AggregationRule::TimeOfDay => {
            let numbers = numeric_values(values)?;
            let average = (numbers.iter().sum::<f64>() / bounded_len_f64(numbers.len())?).round();
            binary_value(average, "time_of_day_minute")
        }
    }
}

#[derive(Clone, Copy)]
enum ExactIntegerOperation {
    Sum,
    Minimum,
    Maximum,
}

fn reduce_exact_integers(
    values: &[SemanticValue],
    operation: ExactIntegerOperation,
) -> Result<Option<SemanticValue>, CoreError> {
    let unit = numeric_unit(values)?;
    let mut signed = Vec::new();
    let mut unsigned = Vec::new();
    for value in values {
        let SemanticValue::Number { number, .. } = value else {
            return Ok(None);
        };
        match number {
            ExactNumber::Binary64 { .. } => return Ok(None),
            ExactNumber::SignedInteger { decimal } => signed.push(parse_canonical_i128(decimal)?),
            ExactNumber::UnsignedInteger { decimal } => {
                unsigned.push(parse_canonical_u128(decimal)?);
            }
        }
    }
    let number = if signed.is_empty() {
        let reduced = match operation {
            ExactIntegerOperation::Sum => unsigned
                .into_iter()
                .try_fold(0_u128, u128::checked_add)
                .ok_or(CoreError::InvalidSemanticBatch)?,
            ExactIntegerOperation::Minimum => unsigned
                .into_iter()
                .min()
                .ok_or(CoreError::InvalidSemanticBatch)?,
            ExactIntegerOperation::Maximum => unsigned
                .into_iter()
                .max()
                .ok_or(CoreError::InvalidSemanticBatch)?,
        };
        ExactNumber::UnsignedInteger {
            decimal: reduced.to_string(),
        }
    } else {
        signed.extend(
            unsigned
                .into_iter()
                .map(|value| i128::try_from(value).map_err(|_| CoreError::InvalidSemanticBatch))
                .collect::<Result<Vec<_>, _>>()?,
        );
        let reduced = match operation {
            ExactIntegerOperation::Sum => signed
                .into_iter()
                .try_fold(0_i128, i128::checked_add)
                .ok_or(CoreError::InvalidSemanticBatch)?,
            ExactIntegerOperation::Minimum => signed
                .into_iter()
                .min()
                .ok_or(CoreError::InvalidSemanticBatch)?,
            ExactIntegerOperation::Maximum => signed
                .into_iter()
                .max()
                .ok_or(CoreError::InvalidSemanticBatch)?,
        };
        ExactNumber::SignedInteger {
            decimal: reduced.to_string(),
        }
    };
    Ok(Some(SemanticValue::Number {
        number,
        unit: ExactUnit {
            id: unit.to_owned(),
        },
    }))
}

fn bounded_len_f64(length: usize) -> Result<f64, CoreError> {
    let length = u32::try_from(length).map_err(|_| CoreError::SemanticLimitExceeded)?;
    Ok(f64::from(length))
}

fn numeric_values(values: &[SemanticValue]) -> Result<Vec<f64>, CoreError> {
    let numbers = values
        .iter()
        .map(|value| numeric_value(value)?.ok_or(CoreError::InvalidSemanticBatch))
        .collect::<Result<Vec<_>, _>>()?;
    if numbers.is_empty() {
        Err(CoreError::InvalidSemanticBatch)
    } else {
        Ok(numbers)
    }
}

fn numeric_unit(values: &[SemanticValue]) -> Result<&str, CoreError> {
    let mut unit: Option<&str> = None;
    for value in values {
        let SemanticValue::Number {
            unit: value_unit, ..
        } = value
        else {
            return Err(CoreError::InvalidSemanticBatch);
        };
        if unit.is_some_and(|existing| existing != value_unit.id) {
            return Err(CoreError::InvalidSemanticBatch);
        }
        unit = Some(&value_unit.id);
    }
    unit.ok_or(CoreError::InvalidSemanticBatch)
}

fn daily_numeric(values: &[SemanticDailyValue], key: &str) -> Result<Option<f64>, CoreError> {
    values
        .iter()
        .find(|value| value.output_key == key)
        .map(|value| numeric_value(&value.value)?.ok_or(CoreError::InvalidSemanticBatch))
        .transpose()
}

fn period_window(date: NaiveDate, period: RollupPeriod) -> (NaiveDate, NaiveDate) {
    match period {
        RollupPeriod::IsoWeek => {
            let days = i64::from(date.weekday().num_days_from_monday());
            let start = date - Duration::days(days);
            (start, start + Duration::days(6))
        }
        RollupPeriod::CalendarMonth => {
            let start = NaiveDate::from_ymd_opt(date.year(), date.month(), 1).expect("valid month");
            let next = if date.month() == 12 {
                NaiveDate::from_ymd_opt(date.year() + 1, 1, 1).expect("valid next year")
            } else {
                NaiveDate::from_ymd_opt(date.year(), date.month() + 1, 1).expect("valid next month")
            };
            (start, next - Duration::days(1))
        }
        RollupPeriod::CalendarYear => {
            let start = NaiveDate::from_ymd_opt(date.year(), 1, 1).expect("valid year");
            let next = NaiveDate::from_ymd_opt(date.year() + 1, 1, 1).expect("valid next year");
            (start, next - Duration::days(1))
        }
        RollupPeriod::Range => unreachable!("range windows come from explicit configuration"),
    }
}

#[allow(clippy::too_many_lines)]
fn reduce_rollup_value(
    key: &str,
    rule: &str,
    daily: &[(&str, &SemanticDailyValue)],
    source_days: &[&SemanticDayResult],
) -> Result<SemanticRollupValue, CoreError> {
    let values = daily
        .iter()
        .map(|(_, value)| value.value.clone())
        .collect::<Vec<_>>();
    let days_counted = u32::try_from(values.len()).map_err(|_| CoreError::SemanticLimitExceeded)?;
    let primary = match rule {
        "sum" => reduce_rollup_numeric(&values, NumericRollup::Sum)?,
        "average" => reduce_rollup_numeric(&values, NumericRollup::Average)?,
        "minimum" => reduce_rollup_numeric(&values, NumericRollup::Minimum)?,
        "maximum" => reduce_rollup_numeric(&values, NumericRollup::Maximum)?,
        "weighted_average" => {
            let weights = source_days
                .iter()
                .map(|day| {
                    day.values
                        .iter()
                        .find(|value| value.output_key == "workout_minutes")
                        .map(|value| numeric_value(&value.value))
                        .transpose()
                        .map(|value| value.flatten().unwrap_or(1.0).max(0.0))
                })
                .collect::<Result<Vec<_>, _>>()?;
            let numbers = numeric_values(&values)?;
            let mut total = 0.0;
            let mut weighted = 0.0;
            for ((date, value), number) in daily.iter().zip(numbers.iter()) {
                let index = source_days
                    .iter()
                    .position(|day| day.owner_date == *date)
                    .ok_or(CoreError::InvalidSemanticBatch)?;
                let weight = weights[index];
                weighted += number * weight;
                total += weight;
                let _ = value;
            }
            let result = if total > 0.0 {
                weighted / total
            } else {
                numbers.iter().sum::<f64>() / bounded_len_f64(numbers.len())?
            };
            binary_value(result, numeric_unit(&values)?)?
        }
        "latest" => daily
            .iter()
            .max_by_key(|(date, _)| *date)
            .map(|(_, value)| value.value.clone())
            .ok_or(CoreError::InvalidSemanticBatch)?,
        "union" => reduce_values(AggregationRule::Union, &values, &[])?,
        "histogram" => daily
            .iter()
            .max_by_key(|(date, _)| *date)
            .map(|(_, value)| value.value.clone())
            .ok_or(CoreError::InvalidSemanticBatch)?,
        "time_of_day" => reduce_values(AggregationRule::TimeOfDay, &values, &[])?,
        _ => daily
            .iter()
            .max_by_key(|(date, _)| *date)
            .map(|(_, value)| value.value.clone())
            .ok_or(CoreError::InvalidSemanticBatch)?,
    };

    let mut statistics = BTreeMap::new();
    if values
        .iter()
        .all(|value| matches!(value, SemanticValue::Number { .. }))
    {
        statistics.insert(
            "sum".to_owned(),
            reduce_rollup_numeric(&values, NumericRollup::Sum)?,
        );
        statistics.insert(
            "average_of_daily_values".to_owned(),
            reduce_rollup_numeric(&values, NumericRollup::Average)?,
        );
        statistics.insert(
            "minimum_daily_value".to_owned(),
            reduce_rollup_numeric(&values, NumericRollup::Minimum)?,
        );
        statistics.insert(
            "maximum_daily_value".to_owned(),
            reduce_rollup_numeric(&values, NumericRollup::Maximum)?,
        );
        if let Some((_, latest)) = daily.iter().max_by_key(|(date, _)| *date) {
            statistics.insert("latest".to_owned(), latest.value.clone());
        }
    }
    match rule {
        "weighted_average" => {
            statistics.insert("weighted_average".to_owned(), primary.clone());
        }
        "union" => {
            statistics.insert("union".to_owned(), primary.clone());
            let mut counts = BTreeMap::<String, u64>::new();
            for value in &values {
                match value {
                    SemanticValue::Text { text } => *counts.entry(text.clone()).or_default() += 1,
                    SemanticValue::TextList { items } => {
                        for item in items {
                            *counts.entry(item.clone()).or_default() += 1;
                        }
                    }
                    _ => return Err(CoreError::InvalidSemanticBatch),
                }
            }
            statistics.insert(
                "value_counts".to_owned(),
                SemanticValue::Text {
                    text: counts
                        .into_iter()
                        .map(|(item, count)| format!("{item}: {count}"))
                        .collect::<Vec<_>>()
                        .join(", "),
                },
            );
        }
        "histogram" => {
            statistics.insert(
                "value_counts".to_owned(),
                reduce_values(AggregationRule::Histogram, &values, &[])?,
            );
            if let Some((_, latest)) = daily.iter().max_by_key(|(date, _)| *date) {
                statistics.insert("latest".to_owned(), latest.value.clone());
            }
        }
        "time_of_day" => {
            let numbers = numeric_values(&values)?;
            statistics.insert(
                "earliest_time".to_owned(),
                binary_value(
                    numbers.iter().copied().fold(f64::INFINITY, f64::min),
                    "time_of_day_minute",
                )?,
            );
            statistics.insert(
                "latest_time".to_owned(),
                binary_value(
                    numbers.iter().copied().fold(f64::NEG_INFINITY, f64::max),
                    "time_of_day_minute",
                )?,
            );
            statistics.insert("average_time_of_day".to_owned(), primary.clone());
        }
        _ => {}
    }
    statistics.insert(
        "days_counted".to_owned(),
        SemanticValue::Number {
            number: ExactNumber::UnsignedInteger {
                decimal: days_counted.to_string(),
            },
            unit: ExactUnit {
                id: "count".to_owned(),
            },
        },
    );
    Ok(SemanticRollupValue {
        output_key: key.to_owned(),
        rule: rule.to_owned(),
        primary_value: primary,
        days_counted,
        statistics,
    })
}

#[derive(Clone, Copy)]
enum NumericRollup {
    Sum,
    Average,
    Minimum,
    Maximum,
}

fn reduce_rollup_numeric(
    values: &[SemanticValue],
    operation: NumericRollup,
) -> Result<SemanticValue, CoreError> {
    let exact_operation = match operation {
        NumericRollup::Sum => Some(ExactIntegerOperation::Sum),
        NumericRollup::Minimum => Some(ExactIntegerOperation::Minimum),
        NumericRollup::Maximum => Some(ExactIntegerOperation::Maximum),
        NumericRollup::Average => None,
    };
    if let Some(operation) = exact_operation {
        if let Some(exact) = reduce_exact_integers(values, operation)? {
            return Ok(exact);
        }
    }
    let numbers = numeric_values(values)?;
    let result = match operation {
        NumericRollup::Sum => numbers.iter().sum(),
        NumericRollup::Average => numbers.iter().sum::<f64>() / bounded_len_f64(numbers.len())?,
        NumericRollup::Minimum => numbers.into_iter().fold(f64::INFINITY, f64::min),
        NumericRollup::Maximum => numbers.into_iter().fold(f64::NEG_INFINITY, f64::max),
    };
    binary_value(result, numeric_unit(values)?)
}

fn canonical_result_bytes(result: &SemanticResult) -> Result<Vec<u8>, CoreError> {
    let value = serde_json::to_value(result).map_err(|_| CoreError::InvalidSemanticBatch)?;
    let canonical = canonicalize_value(value);
    serde_json::to_vec(&canonical).map_err(|_| CoreError::InvalidSemanticBatch)
}

fn canonicalize_value(value: Value) -> Value {
    match value {
        Value::Array(values) => Value::Array(values.into_iter().map(canonicalize_value).collect()),
        Value::Object(values) => Value::Object(
            values
                .into_iter()
                .map(|(key, value)| (key, canonicalize_value(value)))
                .collect(),
        ),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Weekday;

    fn number(value: f64, unit: &str) -> SemanticValue {
        binary_value(value, unit).expect("finite number")
    }

    fn config(selected: &[&str], rollups: Vec<RollupPeriod>) -> SemanticSessionConfig {
        SemanticSessionConfig {
            schema: "healthmd.semantic_session_config".to_owned(),
            semantic_input_version: 1,
            canonical_model_version: 1,
            registry_version: 1,
            registry_sha256: REGISTRY_SHA256.to_owned(),
            profile_revision: 1,
            session_id: "semantic-test".to_owned(),
            profile: SemanticProfile::AppleHealthDataV8,
            calendar_time_zone: "America/New_York".to_owned(),
            selected_selection_ids: selected.iter().map(ToString::to_string).collect(),
            disabled_output_keys: vec![],
            retain_platform_extensions: true,
            rollup_periods: rollups,
            rollup_range: None,
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn record(
        id: &str,
        ordinal: u64,
        date: &str,
        semantic_id: &str,
        selection: &str,
        key: &str,
        value: SemanticValue,
        aggregation: AggregationRule,
    ) -> SemanticRecord {
        SemanticRecord {
            record_id: id.to_owned(),
            source_ordinal: ordinal.to_string(),
            owner_date: date.to_owned(),
            semantic_id: semantic_id.to_owned(),
            selection_ids: vec![selection.to_owned()],
            attribution: SelectionAttribution::Direct,
            kind: SemanticRecordKind::Observation,
            output_key: Some(key.to_owned()),
            aggregation,
            start: None,
            end: None,
            value: Some(value),
            weight: None,
            attributes: BTreeMap::new(),
            extensions: vec![],
        }
    }

    fn run(config: SemanticSessionConfig, records: Vec<SemanticRecord>) -> SemanticResult {
        let config_bytes = serde_json::to_vec(&config).expect("config");
        let mut session = SemanticSession::from_json(&config_bytes).expect("session");
        let owner_dates = records
            .iter()
            .map(|record| record.owner_date.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates,
            records,
        };
        let bytes = session
            .process_batch(&serde_json::to_vec(&batch).expect("batch"), || false)
            .expect("result");
        serde_json::from_slice(&bytes).expect("canonical result")
    }

    #[test]
    fn exact_numbers_reject_nonfinite_and_preserve_negative_zero_bits() {
        let negative_zero = ExactNumber::Binary64 {
            bits: "8000000000000000".to_owned(),
        };
        assert!(validate_number(&negative_zero).is_ok());
        assert_eq!(
            number_f64(&negative_zero).expect("number").to_bits(),
            1_u64 << 63
        );
        for bits in ["7ff0000000000000", "fff0000000000000", "7ff8000000000000"] {
            assert_eq!(
                validate_number(&ExactNumber::Binary64 {
                    bits: bits.to_owned()
                }),
                Err(CoreError::InvalidSemanticBatch)
            );
        }
        assert!(
            validate_number(&ExactNumber::UnsignedInteger {
                decimal: "9007199254740993".to_owned(),
            })
            .is_ok()
        );
    }

    #[test]
    fn reviewed_unit_normalization_handles_fraction_and_imperial_inputs() {
        let percent = normalized_value(&number(0.975, "ratio_0_1"), "percent").expect("percent");
        let kilograms = normalized_value(&number(220.462, "pound"), "kg").expect("kg");
        let celsius = normalized_value(&number(98.6, "degree_fahrenheit"), "°C").expect("C");
        let liters = normalized_value(&number(32.0, "fluid_ounce"), "L").expect("liters");
        assert_eq!(numeric_value(&percent).expect("number"), Some(97.5));
        assert!((numeric_value(&kilograms).expect("number").expect("kg") - 100.0).abs() < 0.001);
        assert!(
            (numeric_value(&celsius).expect("number").expect("C") - 37.0).abs()
                < f64::EPSILON * 8.0
        );
        assert!(
            (numeric_value(&liters).expect("number").expect("L") - 0.946_352_946).abs()
                < 0.000_000_001
        );
        assert_eq!(
            normalized_value(&number(1.0, "pound"), "L"),
            Err(CoreError::InvalidSemanticBatch)
        );
        assert_eq!(
            normalized_value(
                &SemanticValue::Text {
                    text: "not-a-count".to_owned(),
                },
                "steps",
            ),
            Err(CoreError::InvalidSemanticBatch)
        );
    }

    #[test]
    fn filters_missing_without_turning_it_into_zero_and_derives_bmi() {
        let result = run(
            config(&["weight", "height", "bmi"], vec![]),
            vec![
                record(
                    "weight-1",
                    1,
                    "2026-03-08",
                    "weight",
                    "weight",
                    "weight_kg",
                    number(81.0, "kilogram"),
                    AggregationRule::Latest,
                ),
                record(
                    "height-1",
                    2,
                    "2026-03-08",
                    "height",
                    "height",
                    "height_m",
                    number(1.8, "meter"),
                    AggregationRule::Latest,
                ),
            ],
        );
        let values = &result.days[0].values;
        assert_eq!(values.len(), 3);
        assert_eq!(daily_numeric(values, "bmi").expect("bmi"), Some(25.0));

        let bmi_only = run(
            config(&["bmi"], vec![]),
            vec![
                record(
                    "weight-dependency",
                    1,
                    "2026-03-08",
                    "weight",
                    "weight",
                    "weight_kg",
                    number(81.0, "kilogram"),
                    AggregationRule::Latest,
                ),
                record(
                    "height-dependency",
                    2,
                    "2026-03-08",
                    "height",
                    "height",
                    "height_m",
                    number(1.8, "meter"),
                    AggregationRule::Latest,
                ),
            ],
        );
        assert_eq!(bmi_only.days[0].values.len(), 1);
        assert_eq!(bmi_only.days[0].values[0].output_key, "bmi");
        assert_eq!(
            daily_numeric(&bmi_only.days[0].values, "bmi").expect("bmi"),
            Some(25.0)
        );
    }

    #[test]
    fn empty_selection_filters_every_record_without_leaking_zeroes() {
        let result = run(
            config(&[], vec![]),
            vec![record(
                "steps-disabled",
                1,
                "2026-01-01",
                "steps",
                "steps",
                "steps",
                number(0.0, "count"),
                AggregationRule::Sum,
            )],
        );
        assert!(result.days.is_empty());
        assert_eq!(result.records_accepted, 0);
        assert_eq!(result.records_filtered, 1);
    }

    #[test]
    fn disabled_outputs_and_extension_retention_policy_fail_closed() {
        let mut session_config = config(&["steps"], vec![]);
        session_config.disabled_output_keys = vec!["steps".to_owned()];
        session_config.retain_platform_extensions = false;
        let mut extension = record(
            "disabled-extension",
            2,
            "2026-01-01",
            "steps",
            "steps",
            "steps",
            number(1.0, "count"),
            AggregationRule::Sum,
        );
        extension.kind = SemanticRecordKind::ExtensionRef;
        extension.output_key = None;
        extension.value = None;
        extension.extensions = vec![SemanticExtensionRef {
            namespace: "apple.future".to_owned(),
            version: 1,
            retention_token: "disabled-extension-token".to_owned(),
            selection_ids: vec!["steps".to_owned()],
        }];
        let result = run(
            session_config,
            vec![
                record(
                    "disabled-steps",
                    1,
                    "2026-01-01",
                    "steps",
                    "steps",
                    "steps",
                    number(1.0, "count"),
                    AggregationRule::Sum,
                ),
                extension,
            ],
        );
        assert_eq!(result.records_filtered, 2);
        assert!(result.days[0].values.is_empty());
        assert!(result.retained_extensions.is_empty());
    }

    #[test]
    fn selection_dependencies_and_blood_pressure_pair_fail_closed() {
        let mut paired = record(
            "bp-1",
            1,
            "2026-01-01",
            "blood_pressure_systolic",
            "blood_pressure_systolic",
            "blood_pressure_systolic",
            number(120.0, "millimeter_hg"),
            AggregationRule::Average,
        );
        paired
            .selection_ids
            .push("blood_pressure_diastolic".to_owned());
        let result = run(config(&["blood_pressure_systolic"], vec![]), vec![paired]);
        assert_eq!(result.days.len(), 1);
        assert!(result.days[0].values.is_empty());
        assert_eq!(result.records_filtered, 1);
    }

    #[test]
    fn semantic_output_and_extension_attribution_cannot_cross_metric_boundaries() {
        let session_config = config(&["steps", "weight"], vec![]);
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&session_config).expect("config"))
                .expect("session");
        let mut malformed = record(
            "cross-metric-record",
            1,
            "2026-01-01",
            "steps",
            "steps",
            "weight_kg",
            number(1.0, "kilogram"),
            AggregationRule::Latest,
        );
        malformed.selection_ids.push("weight".to_owned());
        malformed.extensions.push(SemanticExtensionRef {
            namespace: "apple.future".to_owned(),
            version: 1,
            retention_token: "cross-metric-token".to_owned(),
            selection_ids: vec!["weight".to_owned()],
        });
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: session_config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates: vec!["2026-01-01".to_owned()],
            records: vec![malformed],
        };
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&batch).expect("batch"), || false),
            Err(CoreError::InvalidSemanticBatch)
        );

        let weight_only_config = config(&["weight"], vec![]);
        let mut weight_only_session =
            SemanticSession::from_json(&serde_json::to_vec(&weight_only_config).expect("config"))
                .expect("session");
        let mut leaked_selection = record(
            "selection-leak-record",
            1,
            "2026-01-01",
            "steps",
            "steps",
            "steps",
            number(1.0, "count"),
            AggregationRule::Sum,
        );
        leaked_selection.selection_ids.push("weight".to_owned());
        let leak_batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: weight_only_config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates: vec!["2026-01-01".to_owned()],
            records: vec![leaked_selection],
        };
        assert_eq!(
            weight_only_session
                .process_batch(&serde_json::to_vec(&leak_batch).expect("batch"), || false,),
            Err(CoreError::InvalidSemanticBatch)
        );

        let mut malformed_extension = record(
            "cross-extension-record",
            1,
            "2026-01-01",
            "steps",
            "steps",
            "steps",
            number(1.0, "count"),
            AggregationRule::Sum,
        );
        malformed_extension.extensions.push(SemanticExtensionRef {
            namespace: "apple.future".to_owned(),
            version: 1,
            retention_token: "disabled-weight-token".to_owned(),
            selection_ids: vec!["weight".to_owned()],
        });
        let extension_batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: "semantic-test".to_owned(),
            batch_index: 0,
            final_batch: true,
            owner_dates: vec!["2026-01-01".to_owned()],
            records: vec![malformed_extension],
        };
        assert_eq!(
            session.process_batch(
                &serde_json::to_vec(&extension_batch).expect("batch"),
                || false,
            ),
            Err(CoreError::InvalidSemanticBatch)
        );
    }

    #[test]
    fn android_observations_must_use_rust_profile_aggregation_rules() {
        let mut session_config = config(&["walking_hr"], vec![]);
        session_config.profile = SemanticProfile::AndroidFrozenV4;
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&session_config).expect("config"))
                .expect("session");
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: session_config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates: vec!["2026-01-01".to_owned()],
            records: vec![record(
                "walking-heart-wrong-rule",
                1,
                "2026-01-01",
                "walking_heart_rate",
                "walking_hr",
                "walking_heart_rate",
                number(80.0, "beat_per_minute"),
                AggregationRule::Latest,
            )],
        };
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&batch).expect("batch"), || false),
            Err(CoreError::InvalidSemanticBatch)
        );
    }

    #[test]
    fn duplicate_sdk_aggregate_facts_fail_instead_of_being_recombined() {
        let session_config = config(&["steps"], vec![]);
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&session_config).expect("config"))
                .expect("session");
        let mut first = record(
            "sdk-steps-a",
            1,
            "2026-01-01",
            "steps",
            "steps",
            "steps",
            number(10.0, "count"),
            AggregationRule::PassThrough,
        );
        first.kind = SemanticRecordKind::SdkAggregate;
        let mut second = record(
            "sdk-steps-b",
            2,
            "2026-01-01",
            "steps",
            "steps",
            "steps",
            number(11.0, "count"),
            AggregationRule::PassThrough,
        );
        second.kind = SemanticRecordKind::SdkAggregate;
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: session_config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates: vec!["2026-01-01".to_owned()],
            records: vec![first, second],
        };
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&batch).expect("batch"), || false),
            Err(CoreError::InvalidSemanticBatch)
        );
    }

    #[test]
    fn latest_ties_use_nanoseconds_then_source_ordinal() {
        let timestamp = |nanos| ExactTimestamp {
            epoch_seconds: "1773000000".to_owned(),
            nanoseconds: nanos,
            source_utc_offset_seconds: None,
            calendar_utc_offset_seconds: -14_400,
        };
        let mut first = record(
            "vo2-1",
            1,
            "2026-03-08",
            "vo2_max",
            "vo2_max",
            "vo2_max",
            number(50.0, "milliliter_per_kilogram_minute"),
            AggregationRule::Latest,
        );
        first.start = Some(timestamp(1));
        let mut second = record(
            "vo2-2",
            2,
            "2026-03-08",
            "vo2_max",
            "vo2_max",
            "vo2_max",
            number(42.0, "milliliter_per_kilogram_minute"),
            AggregationRule::Latest,
        );
        second.start = Some(timestamp(2));
        let result = run(config(&["vo2_max"], vec![]), vec![first, second]);
        assert_eq!(
            daily_numeric(&result.days[0].values, "vo2_max").expect("vo2"),
            Some(42.0)
        );
    }

    #[test]
    fn apple_rollups_obey_iso_year_boundaries_and_latest_vo2() {
        let result = run(
            config(&["vo2_max"], vec![RollupPeriod::IsoWeek]),
            vec![
                record(
                    "vo2-a",
                    1,
                    "2025-12-31",
                    "vo2_max",
                    "vo2_max",
                    "vo2_max",
                    number(50.0, "milliliter_per_kilogram_minute"),
                    AggregationRule::Latest,
                ),
                record(
                    "vo2-b",
                    2,
                    "2026-01-01",
                    "vo2_max",
                    "vo2_max",
                    "vo2_max",
                    number(40.0, "milliliter_per_kilogram_minute"),
                    AggregationRule::Latest,
                ),
            ],
        );
        assert_eq!(result.rollups[0].start_date, "2025-12-29");
        assert_eq!(result.rollups[0].end_date, "2026-01-04");
        assert_eq!(
            numeric_value(&result.rollups[0].values[0].primary_value).expect("numeric"),
            Some(40.0)
        );
    }

    #[test]
    fn range_rollup_preserves_requested_bounds_and_successful_empty_days() {
        let mut session_config = config(&["steps"], vec![RollupPeriod::Range]);
        session_config.profile_revision = 2;
        session_config.rollup_range = Some(RollupRange {
            start_date: "2026-07-06".to_owned(),
            end_date: "2026-07-11".to_owned(),
        });
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&session_config).expect("config"))
                .expect("session");
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: session_config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates: vec![
                "2026-07-07".to_owned(),
                "2026-07-08".to_owned(),
                "2026-07-10".to_owned(),
            ],
            records: vec![
                record(
                    "range-steps-a",
                    1,
                    "2026-07-07",
                    "steps",
                    "steps",
                    "steps",
                    number(10.0, "count"),
                    AggregationRule::Sum,
                ),
                record(
                    "range-steps-b",
                    2,
                    "2026-07-10",
                    "steps",
                    "steps",
                    "steps",
                    number(20.0, "count"),
                    AggregationRule::Sum,
                ),
            ],
        };
        let bytes = session
            .process_batch(&serde_json::to_vec(&batch).expect("batch"), || false)
            .expect("result");
        let result: SemanticResult = serde_json::from_slice(&bytes).expect("result");
        let rollup = result.rollups.first().expect("range rollup");
        assert_eq!(rollup.period, RollupPeriod::Range);
        assert_eq!(rollup.start_date, "2026-07-06");
        assert_eq!(rollup.end_date, "2026-07-11");
        assert_eq!(
            rollup.source_dates,
            ["2026-07-07", "2026-07-08", "2026-07-10"]
        );
    }

    #[test]
    fn range_rejects_revision_one_while_calendar_revision_one_remains_valid() {
        let calendar = config(&["steps"], vec![RollupPeriod::IsoWeek]);
        assert!(
            SemanticSession::from_json(&serde_json::to_vec(&calendar).expect("calendar")).is_ok()
        );

        let mut range = config(&["steps"], vec![RollupPeriod::Range]);
        range.rollup_range = Some(RollupRange {
            start_date: "2026-07-06".to_owned(),
            end_date: "2026-07-11".to_owned(),
        });
        assert!(matches!(
            SemanticSession::from_json(&serde_json::to_vec(&range).expect("range")),
            Err(CoreError::InvalidSemanticConfig)
        ));
        range.profile_revision = 2;
        assert!(SemanticSession::from_json(&serde_json::to_vec(&range).expect("range-v2")).is_ok());
    }

    #[test]
    fn range_accepts_exact_limit_and_rejects_limit_plus_one_or_reversed_bounds() {
        let mut range = config(&["steps"], vec![RollupPeriod::Range]);
        range.profile_revision = 2;
        range.rollup_range = Some(RollupRange {
            start_date: "2000-01-01".to_owned(),
            end_date: "2027-05-18".to_owned(),
        });
        assert!(SemanticSession::from_json(&serde_json::to_vec(&range).expect("range")).is_ok());

        range.rollup_range = Some(RollupRange {
            start_date: "2000-01-01".to_owned(),
            end_date: "2027-05-19".to_owned(),
        });
        assert!(matches!(
            SemanticSession::from_json(&serde_json::to_vec(&range).expect("too-large")),
            Err(CoreError::InvalidSemanticConfig)
        ));

        range.rollup_range = Some(RollupRange {
            start_date: "2027-05-18".to_owned(),
            end_date: "2000-01-01".to_owned(),
        });
        assert!(matches!(
            SemanticSession::from_json(&serde_json::to_vec(&range).expect("reversed")),
            Err(CoreError::InvalidSemanticConfig)
        ));
    }

    #[test]
    fn histogram_rollup_uses_latest_category_as_legacy_primary() {
        let first_value = SemanticDailyValue {
            output_key: "menstrual_flow".to_owned(),
            semantic_id: "menstrual_flow".to_owned(),
            aggregation: AggregationRule::Latest,
            value: SemanticValue::Text {
                text: "light".to_owned(),
            },
            source_record_ids: vec!["flow-a".to_owned()],
        };
        let latest_value = SemanticDailyValue {
            value: SemanticValue::Text {
                text: "heavy".to_owned(),
            },
            source_record_ids: vec!["flow-b".to_owned()],
            ..first_value.clone()
        };
        let first_day = SemanticDayResult {
            owner_date: "2026-01-01".to_owned(),
            values: vec![first_value],
        };
        let latest_day = SemanticDayResult {
            owner_date: "2026-01-02".to_owned(),
            values: vec![latest_value],
        };
        let source_days = vec![&first_day, &latest_day];
        let daily = vec![
            (first_day.owner_date.as_str(), &first_day.values[0]),
            (latest_day.owner_date.as_str(), &latest_day.values[0]),
        ];
        let rollup = reduce_rollup_value("menstrual_flow", "histogram", &daily, &source_days)
            .expect("histogram");
        assert_eq!(
            rollup.primary_value,
            SemanticValue::Text {
                text: "heavy".to_owned()
            }
        );
        assert_eq!(
            rollup.statistics.get("value_counts"),
            Some(&SemanticValue::Text {
                text: "heavy: 1, light: 1".to_owned(),
            })
        );
    }

    #[test]
    fn rollup_coverage_includes_declared_empty_days_and_leap_month_bounds() {
        let session_config = config(&["steps"], vec![RollupPeriod::CalendarMonth]);
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&session_config).expect("config"))
                .expect("session");
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: session_config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates: vec![
                "2024-02-28".to_owned(),
                "2024-02-29".to_owned(),
                "2024-03-01".to_owned(),
            ],
            records: vec![record(
                "leap-steps",
                1,
                "2024-02-29",
                "steps",
                "steps",
                "steps",
                number(10.0, "count"),
                AggregationRule::Sum,
            )],
        };
        let bytes = session
            .process_batch(&serde_json::to_vec(&batch).expect("batch"), || false)
            .expect("result");
        let result: SemanticResult = serde_json::from_slice(&bytes).expect("result");
        assert_eq!(result.days.len(), 3);
        assert_eq!(result.rollups.len(), 1);
        assert!(result.days[0].values.is_empty());
        assert_eq!(result.rollups[0].end_date, "2024-02-29");
        assert_eq!(
            result.rollups[0].source_dates,
            vec!["2024-02-28", "2024-02-29"]
        );
        assert_eq!(result.rollups[0].values[0].days_counted, 1);
    }

    #[test]
    fn closed_reducers_cover_minimum_maximum_union_histogram_and_time_of_day() {
        let numbers = vec![
            number(3.0, "unitless"),
            number(1.0, "unitless"),
            number(7.0, "unitless"),
        ];
        assert_eq!(
            numeric_value(&reduce_values(AggregationRule::Minimum, &numbers, &[]).expect("min"))
                .expect("numeric"),
            Some(1.0)
        );
        assert_eq!(
            numeric_value(&reduce_values(AggregationRule::Maximum, &numbers, &[]).expect("max"))
                .expect("numeric"),
            Some(7.0)
        );
        assert_eq!(
            reduce_values(
                AggregationRule::Union,
                &[
                    SemanticValue::TextList {
                        items: vec!["b".to_owned(), "a".to_owned()]
                    },
                    SemanticValue::Text {
                        text: "c".to_owned()
                    },
                ],
                &[],
            )
            .expect("union"),
            SemanticValue::TextList {
                items: vec!["a".to_owned(), "b".to_owned(), "c".to_owned()]
            }
        );
        assert_eq!(
            reduce_values(
                AggregationRule::Histogram,
                &[
                    SemanticValue::Text {
                        text: "light".to_owned()
                    },
                    SemanticValue::Text {
                        text: "heavy".to_owned()
                    },
                    SemanticValue::Text {
                        text: "light".to_owned()
                    },
                ],
                &[],
            )
            .expect("histogram"),
            SemanticValue::Text {
                text: "heavy: 1, light: 2".to_owned()
            }
        );
        let exact_large = vec![
            SemanticValue::Number {
                number: ExactNumber::UnsignedInteger {
                    decimal: "9007199254740993".to_owned(),
                },
                unit: ExactUnit {
                    id: "count".to_owned(),
                },
            },
            SemanticValue::Number {
                number: ExactNumber::UnsignedInteger {
                    decimal: "1".to_owned(),
                },
                unit: ExactUnit {
                    id: "count".to_owned(),
                },
            },
        ];
        assert_eq!(
            reduce_values(AggregationRule::Sum, &exact_large, &[]).expect("exact sum"),
            SemanticValue::Number {
                number: ExactNumber::UnsignedInteger {
                    decimal: "9007199254740994".to_owned(),
                },
                unit: ExactUnit {
                    id: "count".to_owned()
                },
            }
        );
        let times = vec![
            number(60.0, "time_of_day_minute"),
            number(120.0, "time_of_day_minute"),
        ];
        assert_eq!(
            numeric_value(
                &reduce_values(AggregationRule::TimeOfDay, &times, &[]).expect("time of day"),
            )
            .expect("numeric"),
            Some(90.0)
        );
    }

    #[test]
    fn semantic_sessions_enforce_configuration_batch_and_sequence_bounds() {
        for invalid_time_zone in ["not/an-iana-zone", "+05:00"] {
            let mut invalid_zone = config(&["steps"], vec![]);
            invalid_zone.calendar_time_zone = invalid_time_zone.to_owned();
            assert!(matches!(
                SemanticSession::from_json(&serde_json::to_vec(&invalid_zone).expect("config")),
                Err(CoreError::InvalidSemanticConfig)
            ));
        }
        assert!(matches!(
            SemanticSession::from_json(&vec![b' '; MAX_CONFIG_BYTES + 1]),
            Err(CoreError::SemanticConfigTooLarge)
        ));
        let config_bytes = serde_json::to_vec(&config(&["steps"], vec![])).expect("config");
        let mut session = SemanticSession::from_json(&config_bytes).expect("session");
        assert_eq!(
            session.process_batch(&vec![b' '; MAX_BATCH_BYTES + 1], || false),
            Err(CoreError::SemanticBatchTooLarge)
        );
        let mut bad_offset_record = record(
            "bad-offset",
            1,
            "2026-01-01",
            "steps",
            "steps",
            "steps",
            number(1.0, "count"),
            AggregationRule::Sum,
        );
        bad_offset_record.start = Some(ExactTimestamp {
            epoch_seconds: "1767225600".to_owned(),
            nanoseconds: 0,
            source_utc_offset_seconds: Some(64_801),
            calendar_utc_offset_seconds: 0,
        });
        let bad_offset = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: "semantic-test".to_owned(),
            batch_index: 0,
            final_batch: true,
            owner_dates: vec!["2026-01-01".to_owned()],
            records: vec![bad_offset_record],
        };
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&bad_offset).expect("batch"), || false),
            Err(CoreError::InvalidSemanticBatch)
        );
        let out_of_order = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: "semantic-test".to_owned(),
            batch_index: 1,
            final_batch: true,
            owner_dates: vec![],
            records: vec![],
        };
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&out_of_order).expect("batch"), || false),
            Err(CoreError::SemanticSequenceInvalid)
        );
    }

    #[test]
    fn invalid_batch_is_transactional_and_can_be_retried() {
        let bytes = serde_json::to_vec(&config(&["steps"], vec![])).expect("config");
        let mut session = SemanticSession::from_json(&bytes).expect("session");
        assert_eq!(
            session.process_batch(b"not-json", || false),
            Err(CoreError::InvalidSemanticBatch)
        );
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: "semantic-test".to_owned(),
            batch_index: 0,
            final_batch: true,
            owner_dates: vec![],
            records: vec![],
        };
        let result = session
            .process_batch(&serde_json::to_vec(&batch).expect("batch"), || false)
            .expect("retry");
        assert_eq!(
            serde_json::from_slice::<SemanticResult>(&result)
                .expect("result")
                .state,
            SemanticResultState::Completed
        );
    }

    #[test]
    fn cancellation_is_checked_during_day_reduction() {
        use std::cell::Cell;

        let session_config = config(&["steps"], vec![]);
        let mut session =
            SemanticSession::from_json(&serde_json::to_vec(&session_config).expect("config"))
                .expect("session");
        let batch = SemanticBatch {
            schema: "healthmd.semantic_input".to_owned(),
            semantic_input_version: 1,
            session_id: session_config.session_id,
            batch_index: 0,
            final_batch: true,
            owner_dates: vec!["2026-01-01".to_owned()],
            records: vec![record(
                "cancel-reduction",
                1,
                "2026-01-01",
                "steps",
                "steps",
                "steps",
                number(1.0, "count"),
                AggregationRule::Sum,
            )],
        };
        let probes = Cell::new(0_u32);
        let bytes = session
            .process_batch(&serde_json::to_vec(&batch).expect("batch"), || {
                probes.set(probes.get() + 1);
                probes.get() == 4
            })
            .expect("cancel result");
        assert_eq!(
            serde_json::from_slice::<SemanticResult>(&bytes)
                .expect("result")
                .state,
            SemanticResultState::Cancelled
        );
    }

    #[test]
    fn cancellation_is_terminal_and_health_free() {
        let bytes = serde_json::to_vec(&config(&["steps"], vec![])).expect("config");
        let mut session = SemanticSession::from_json(&bytes).expect("session");
        let cancelled = session
            .process_batch(b"not-json", || true)
            .expect("cancelled result");
        let result: SemanticResult = serde_json::from_slice(&cancelled).expect("result");
        assert_eq!(result.state, SemanticResultState::Cancelled);
        assert_eq!(
            session.process_batch(b"{}", || false),
            Err(CoreError::SemanticSessionTerminal)
        );
    }

    #[test]
    fn date_windows_cover_dst_independently_from_offsets() {
        let spring = parse_date("2026-03-08").expect("date");
        let autumn = parse_date("2026-11-01").expect("date");
        assert_eq!(
            period_window(spring, RollupPeriod::IsoWeek).0.weekday(),
            Weekday::Mon
        );
        assert_eq!(
            period_window(autumn, RollupPeriod::IsoWeek).0.weekday(),
            Weekday::Mon
        );
        assert!(
            validate_timestamp(&ExactTimestamp {
                epoch_seconds: "1773000000".to_owned(),
                nanoseconds: 999_999_999,
                source_utc_offset_seconds: Some(20_700),
                calendar_utc_offset_seconds: -14_400,
            })
            .is_ok()
        );
    }
}
