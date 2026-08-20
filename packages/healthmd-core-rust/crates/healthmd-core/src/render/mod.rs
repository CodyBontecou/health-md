//! Versioned deterministic profile rendering and destination-neutral artifact planning.
//!
//! The render boundary consumes only a completed semantic result plus explicit presentation facts
//! from the same frozen native capture. It owns no capture, filesystem, network, clock, locale, or
//! destination behavior.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::{
    CANONICAL_MODEL_VERSION, REGISTRY_SHA256, REGISTRY_VERSION,
    semantic::{ExactNumber, SemanticProfile, SemanticResult, SemanticResultState, SemanticValue},
};

mod android_analytical_v5;
mod android_frozen_v4;
mod apple_range_rollup_v9;
mod apple_rollup_v8;
mod apple_v8;
pub mod artifact_plan;
mod format;
mod markdown_merge;
pub mod stream;

pub use artifact_plan::{ArtifactPlan, ArtifactPlanItem, validate_relative_path};
pub use format::merge_markdown;
pub use markdown_merge::merge_profile_markdown;
pub use stream::{
    LosslessArtifactStream, StreamArtifactConfig, StreamArtifactPlanItem, StreamDescriptor,
    StreamFinish, StreamMode,
};

/// Version of the strict native-to-core render input.
pub const RENDER_INPUT_VERSION: u32 = 1;
/// Version of the destination-neutral artifact plan.
pub const ARTIFACT_PLAN_VERSION: u32 = 1;
/// Revision of all three profile renderers, including managed-Markdown merge behavior.
pub const RENDER_PROFILE_REVISION: u32 = 2;
/// Maximum render configuration bytes.
pub const MAX_RENDER_CONFIG_BYTES: usize = 256 * 1024;
/// Maximum completed semantic-result bytes.
pub const MAX_SEMANTIC_RESULT_BYTES: usize = 32 * 1024 * 1024;
/// Maximum one render batch.
pub const MAX_RENDER_BATCH_BYTES: usize = 2 * 1024 * 1024;
/// Maximum facts and extension payloads in one batch.
pub const MAX_RENDER_FACTS_PER_BATCH: usize = 4_096;
/// Maximum owner dates accumulated by one render session (~27 years).
pub const MAX_RENDER_DATES: usize = 10_000;
/// Maximum owner dates in one bounded render batch.
pub const MAX_RENDER_BATCH_DATES: usize = 400;
/// Maximum inline artifacts in a plan.
pub const MAX_ARTIFACTS: usize = 4_096;
/// Maximum bytes in one inline artifact.
pub const MAX_ARTIFACT_BYTES: usize = 8 * 1024 * 1024;
/// Maximum total inline output bytes. Larger source layers use `LosslessArtifactStream`.
pub const MAX_INLINE_OUTPUT_BYTES: usize = 32 * 1024 * 1024;

const MAX_TEXT_BYTES: usize = 64 * 1024;
const MAX_EXTENSION_PAYLOAD_BYTES: usize = 1024 * 1024;

/// Stable health-free render failures.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq)]
pub enum RenderError {
    #[error("render configuration exceeds the size limit")]
    ConfigTooLarge,
    #[error("render configuration is invalid")]
    InvalidConfig,
    #[error("completed semantic result exceeds the size limit")]
    SemanticResultTooLarge,
    #[error("completed semantic result is invalid")]
    InvalidSemanticResult,
    #[error("render input version is unsupported")]
    UnsupportedRenderInputVersion,
    #[error("artifact plan version is unsupported")]
    UnsupportedArtifactPlanVersion,
    #[error("render profile revision is unsupported")]
    UnsupportedProfileRevision,
    #[error("render batch exceeds the size limit")]
    BatchTooLarge,
    #[error("render batch is invalid")]
    InvalidBatch,
    #[error("render input sequence is invalid")]
    SequenceInvalid,
    #[error("render input exceeds a limit")]
    LimitExceeded,
    #[error("render presentation does not match semantic output")]
    PresentationMismatch,
    #[error("render extension payload is not retained")]
    ExtensionNotRetained,
    #[error("render extension selection is invalid")]
    ExtensionSelectionInvalid,
    #[error("render operation is unsupported for the profile")]
    UnsupportedOperation,
    #[error("artifact path is invalid")]
    InvalidPath,
    #[error("artifact paths collide")]
    PathCollision,
    #[error("artifact is invalid")]
    InvalidArtifact,
    #[error("artifact exceeds the inline size limit")]
    ArtifactTooLarge,
    #[error("artifact count exceeds the limit")]
    ArtifactLimitExceeded,
    #[error("inline output exceeds the size limit")]
    InlineOutputTooLarge,
    #[error("render session is terminal")]
    SessionTerminal,
    #[error("render operation was cancelled")]
    Cancelled,
    #[error("stream item is invalid")]
    InvalidStreamItem,
    #[error("stream item exceeds the size limit")]
    StreamItemTooLarge,
    #[error("stream exceeds the size limit")]
    StreamTooLarge,
    #[error("stream sequence is invalid")]
    StreamSequenceInvalid,
    #[error("stream is terminal")]
    StreamTerminal,
    #[error("render serialization failed")]
    SerializationFailed,
}

impl RenderError {
    /// Stable machine code safe for logs and durable jobs.
    pub const fn code(self) -> &'static str {
        match self {
            Self::ConfigTooLarge => "render_config_too_large",
            Self::InvalidConfig => "invalid_render_config",
            Self::SemanticResultTooLarge => "semantic_result_too_large",
            Self::InvalidSemanticResult => "invalid_semantic_result",
            Self::UnsupportedRenderInputVersion => "unsupported_render_input_version",
            Self::UnsupportedArtifactPlanVersion => "unsupported_artifact_plan_version",
            Self::UnsupportedProfileRevision => "unsupported_render_profile_revision",
            Self::BatchTooLarge => "render_batch_too_large",
            Self::InvalidBatch => "invalid_render_batch",
            Self::SequenceInvalid => "render_sequence_invalid",
            Self::LimitExceeded => "render_limit_exceeded",
            Self::PresentationMismatch => "render_presentation_mismatch",
            Self::ExtensionNotRetained => "render_extension_not_retained",
            Self::ExtensionSelectionInvalid => "render_extension_selection_invalid",
            Self::UnsupportedOperation => "unsupported_render_operation",
            Self::InvalidPath => "invalid_artifact_path",
            Self::PathCollision => "artifact_path_collision",
            Self::InvalidArtifact => "invalid_artifact",
            Self::ArtifactTooLarge => "artifact_too_large",
            Self::ArtifactLimitExceeded => "artifact_limit_exceeded",
            Self::InlineOutputTooLarge => "inline_output_too_large",
            Self::SessionTerminal => "render_session_terminal",
            Self::Cancelled => "render_cancelled",
            Self::InvalidStreamItem => "invalid_stream_item",
            Self::StreamItemTooLarge => "stream_item_too_large",
            Self::StreamTooLarge => "stream_too_large",
            Self::StreamSequenceInvalid => "stream_sequence_invalid",
            Self::StreamTerminal => "stream_terminal",
            Self::SerializationFailed => "render_serialization_failed",
        }
    }
}

/// Closed artifact formats.
#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RenderFormat {
    Markdown,
    ObsidianBases,
    Json,
    Csv,
}

impl RenderFormat {
    pub(crate) const fn id(self) -> &'static str {
        match self {
            Self::Markdown => "markdown",
            Self::ObsidianBases => "obsidian_bases",
            Self::Json => "json",
            Self::Csv => "csv",
        }
    }

    pub(crate) const fn extension(self) -> &'static str {
        match self {
            Self::Markdown | Self::ObsidianBases => "md",
            Self::Json => "json",
            Self::Csv => "csv",
        }
    }

    pub(crate) const fn media_type(self) -> &'static str {
        match self {
            Self::Markdown | Self::ObsidianBases => "text/markdown; charset=utf-8",
            Self::Json => "application/json",
            Self::Csv => "text/csv; charset=utf-8",
        }
    }
}

/// User-level write request before format-specific normalization.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RequestedWriteMode {
    Overwrite,
    Append,
    Update,
}

/// Exact destination-neutral write operation.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum WriteMode {
    Overwrite,
    Append,
    MarkdownMerge,
    ApiPost,
}

impl WriteMode {
    pub(crate) const fn id(self) -> &'static str {
        match self {
            Self::Overwrite => "overwrite",
            Self::Append => "append",
            Self::MarkdownMerge => "markdown_merge",
            Self::ApiPost => "api_post",
        }
    }
}

/// Metric/imperial presentation selection. Apple machine JSON remains canonical metric.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UnitSystem {
    Metric,
    Imperial,
}

impl UnitSystem {
    pub(crate) const fn id(self) -> &'static str {
        match self {
            Self::Metric => "metric",
            Self::Imperial => "imperial",
        }
    }
}

/// Markdown presentation settings frozen by native code.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MarkdownSettings {
    pub use_emoji: bool,
    pub section_header_level: u8,
    pub bullet: String,
    pub include_summary: bool,
    pub custom_template: Option<String>,
}

/// Profile-independent path settings. All values remain logical relative components.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FormatFolders {
    pub markdown: String,
    pub obsidian_bases: String,
    pub json: String,
    pub csv: String,
}

impl FormatFolders {
    fn for_format(&self, format: RenderFormat) -> &str {
        match format {
            RenderFormat::Markdown => &self.markdown,
            RenderFormat::ObsidianBases => &self.obsidian_bases,
            RenderFormat::Json => &self.json,
            RenderFormat::Csv => &self.csv,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct PathSettings {
    pub base_directory: String,
    pub filename_template: String,
    pub folder_template: String,
    pub format_folders: FormatFolders,
    pub rollup_directory: String,
    pub bases_suffix: String,
}

/// One native capture failure retained in an API envelope.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ApiFailureDetail {
    pub owner_date: String,
    pub timestamp: String,
    pub reason: String,
    pub error_details: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ApiExternalRecord {
    pub owner_date: String,
    pub value: Value,
}

/// Explicit API envelope inputs. Networking and URL/authentication remain native.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ApiSettings {
    pub enabled: bool,
    pub envelope_version: u32,
    pub exported_at: String,
    pub source: String,
    pub date_range_start: String,
    pub date_range_end: String,
    pub failed_date_details: Vec<ApiFailureDetail>,
    pub external_record_schema: Option<String>,
    pub external_record_schema_version: Option<u32>,
    pub external_records: Vec<ApiExternalRecord>,
    pub max_days_per_batch: u32,
    pub max_encoded_bytes: u64,
}

/// Frozen frontmatter key settings. Native code freezes user-controlled names; profile renderers
/// own ordering and byte assembly.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FrontmatterSettings {
    pub include_date: bool,
    pub date_key: String,
    pub include_type: bool,
    pub type_key: String,
    pub type_value: String,
}

/// Frozen public metadata for one Apple roll-up output key.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RollupMetricPresentation {
    pub key: String,
    pub canonical_key: String,
    pub display_name: String,
    pub category: String,
    pub unit: String,
    pub notes: Option<String>,
    pub statistic_order: Vec<String>,
}

/// Explicit clock/presentation facts for deterministic Apple roll-up rendering.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RollupRenderSettings {
    pub generated_at: String,
    pub metrics: BTreeMap<String, RollupMetricPresentation>,
}

/// Frozen render configuration for one semantic result.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderSessionConfig {
    pub schema: String,
    pub render_input_version: u32,
    pub artifact_plan_version: u32,
    pub canonical_model_version: u32,
    pub registry_version: u32,
    pub registry_sha256: String,
    pub profile_revision: u32,
    pub render_profile_revision: u32,
    pub request_id: String,
    pub session_id: String,
    pub profile: SemanticProfile,
    pub calendar_time_zone: String,
    pub locale: String,
    pub formats: Vec<RenderFormat>,
    pub unit_system: UnitSystem,
    pub include_metadata: bool,
    pub group_by_category: bool,
    pub include_platform_extensions: bool,
    pub raw_capture_status: String,
    pub write_mode: RequestedWriteMode,
    pub markdown: MarkdownSettings,
    pub frontmatter: FrontmatterSettings,
    pub custom_frontmatter: BTreeMap<String, String>,
    pub placeholder_frontmatter: Vec<String>,
    pub disabled_frontmatter_keys: Vec<String>,
    pub paths: PathSettings,
    pub rollups: Option<RollupRenderSettings>,
    pub api: Option<ApiSettings>,
}

/// One exact typed CSV row supplied for an accepted profile extension.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderCsvRow {
    pub date: String,
    pub category: String,
    pub metric: String,
    pub value: String,
    pub unit: String,
    pub timestamp: String,
    pub ordinal: u32,
}

/// Structured Markdown extension block.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderMarkdownBlock {
    pub heading: String,
    pub lines: Vec<String>,
    pub ordinal: u32,
}

/// Native attachment bytes. Large attachments use the stream API instead.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderAttachment {
    pub relative_path: String,
    pub media_type: String,
    pub bytes_base64: String,
    pub ordinal: u32,
}

/// Payload for one M4-retained native extension token.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderExtensionPayload {
    pub retention_token: String,
    pub selection_ids: Vec<String>,
    pub ordinal: u32,
    pub json_field: Option<String>,
    pub json_value: Option<Value>,
    pub csv_rows: Vec<RenderCsvRow>,
    pub markdown_blocks: Vec<RenderMarkdownBlock>,
    pub attachments: Vec<RenderAttachment>,
}

/// One accepted semantic output plus all otherwise-unrecoverable presentation facts.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderMetric {
    pub output_key: String,
    pub category_id: String,
    pub category_label: String,
    pub label: String,
    pub frontmatter_key: String,
    pub json_path: Vec<String>,
    pub public_value: Value,
    pub display_value: String,
    pub unit: String,
    pub timestamp: Option<String>,
    pub ordinal: u32,
}

/// One planned individual Markdown entry.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderIndividualEntry {
    pub entry_id: String,
    pub output_keys: Vec<String>,
    pub relative_path: String,
    pub title: String,
    pub frontmatter: BTreeMap<String, String>,
    pub body_lines: Vec<String>,
    pub ordinal: u32,
    #[serde(default)]
    pub document: Option<RenderLineDocument>,
}

/// One Daily Note injection plan. Destination reading/commit remains native.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderDailyNote {
    pub relative_path: String,
    pub output_keys: Vec<String>,
    pub include_frontmatter: bool,
    pub include_markdown: bool,
    #[serde(default)]
    pub document: Option<RenderLineDocument>,
}

/// One ordered scalar field used only by the Bases frontmatter surface.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderFrontmatterField {
    pub key: String,
    pub value: String,
    pub ordinal: u32,
}

/// One structured frontmatter field whose child lines already contain profile-native indentation.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderFrontmatterBlock {
    pub key: String,
    pub lines: Vec<String>,
    pub ordinal: u32,
}

/// Apple source-archive diagnostics that are public frontmatter/format facts.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderArchiveDiagnostics {
    pub capture_status: String,
    pub record_count: u64,
    pub query_failure_count: u64,
    pub integrity_warning_count: u64,
    pub record_schema: Option<String>,
    pub record_schema_version: Option<u32>,
}

/// One JSON value with explicit object-member order for profile-specific serializers.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "value_type", rename_all = "snake_case", deny_unknown_fields)]
pub enum OrderedJsonValue {
    Null,
    Boolean { value: bool },
    Number { decimal: String },
    String { value: String },
    Array { items: Vec<OrderedJsonValue> },
    Object { entries: Vec<OrderedJsonEntry> },
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct OrderedJsonEntry {
    pub key: String,
    pub value: OrderedJsonValue,
}

/// A line-oriented document body. Rust owns deterministic newline assembly.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderLineDocument {
    pub lines: Vec<String>,
    pub trailing_newline: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderProfileCsvRow {
    pub cells: Vec<String>,
}

/// Frozen native presentation facts consumed by profile renderers.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderProfileDocuments {
    pub semantic_output_keys: Vec<String>,
    pub markdown_body: Option<RenderLineDocument>,
    pub csv_rows: Option<Vec<RenderProfileCsvRow>>,
    pub json_root: Option<OrderedJsonValue>,
}

/// Presentation facts for one semantic owner date.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderDay {
    pub owner_date: String,
    pub title: String,
    pub archive_diagnostics: Option<RenderArchiveDiagnostics>,
    pub bases_frontmatter_fields: Vec<RenderFrontmatterField>,
    pub bases_frontmatter_blocks: Vec<RenderFrontmatterBlock>,
    pub metrics: Vec<RenderMetric>,
    pub extensions: Vec<RenderExtensionPayload>,
    pub individual_entries: Vec<RenderIndividualEntry>,
    pub daily_note: Option<RenderDailyNote>,
    #[serde(default)]
    pub profile_documents: RenderProfileDocuments,
}

/// Transactional ordered render batch.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderBatch {
    pub schema: String,
    pub render_input_version: u32,
    pub session_id: String,
    pub batch_index: u32,
    pub final_batch: bool,
    pub days: Vec<RenderDay>,
}

/// Health-free receipt for one accepted batch.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RenderBatchReceipt {
    pub next_batch_index: u32,
    pub days_accepted: u32,
    pub facts_accepted: u32,
    pub final_batch: bool,
}

/// Bounded ephemeral render session.
#[derive(Clone, Debug)]
pub struct RenderSession {
    config: RenderSessionConfig,
    semantic: SemanticResult,
    semantic_outputs: HashMap<String, HashMap<String, crate::semantic::SemanticDailyValue>>,
    presentation_categories: HashMap<String, BTreeSet<String>>,
    retained_extensions: HashMap<String, (String, BTreeSet<String>)>,
    consumed_extensions: HashSet<String>,
    days: BTreeMap<String, RenderDay>,
    next_batch_index: u32,
    final_batch_seen: bool,
    bytes_accepted: usize,
    terminal: bool,
}

impl RenderSession {
    /// Create a strict render session from configuration and a completed semantic result.
    ///
    /// # Errors
    /// Returns a stable version, bound, profile, or semantic-result validation error.
    pub fn from_json(
        config_bytes: &[u8],
        semantic_result_bytes: &[u8],
    ) -> Result<Self, RenderError> {
        if config_bytes.len() > MAX_RENDER_CONFIG_BYTES {
            return Err(RenderError::ConfigTooLarge);
        }
        if semantic_result_bytes.len() > MAX_SEMANTIC_RESULT_BYTES {
            return Err(RenderError::SemanticResultTooLarge);
        }
        let config: RenderSessionConfig =
            serde_json::from_slice(config_bytes).map_err(|_| RenderError::InvalidConfig)?;
        let semantic: SemanticResult = serde_json::from_slice(semantic_result_bytes)
            .map_err(|_| RenderError::InvalidSemanticResult)?;
        validate_config(&config, &semantic)?;
        let semantic_outputs = semantic
            .days
            .iter()
            .map(|day| {
                (
                    day.owner_date.clone(),
                    day.values
                        .iter()
                        .cloned()
                        .map(|value| (value.output_key.clone(), value))
                        .collect(),
                )
            })
            .collect();
        let presentation_categories = profile_presentation_categories(config.profile)?;
        let retained_extensions = semantic
            .retained_extensions
            .iter()
            .map(|value| {
                (
                    value.extension.retention_token.clone(),
                    (
                        value.owner_date.clone(),
                        value.extension.selection_ids.iter().cloned().collect(),
                    ),
                )
            })
            .collect();
        Ok(Self {
            config,
            semantic,
            semantic_outputs,
            presentation_categories,
            retained_extensions,
            consumed_extensions: HashSet::new(),
            days: BTreeMap::new(),
            next_batch_index: 0,
            final_batch_seen: false,
            bytes_accepted: 0,
            terminal: false,
        })
    }

    /// Accept one bounded render batch transactionally.
    ///
    /// # Errors
    /// Returns a stable sequence, cancellation, bound, or presentation-validation error.
    pub fn process_batch(
        &mut self,
        batch_bytes: &[u8],
        is_cancelled: impl Fn() -> bool,
    ) -> Result<RenderBatchReceipt, RenderError> {
        if self.terminal {
            return Err(RenderError::SessionTerminal);
        }
        if is_cancelled() {
            self.terminal = true;
            return Err(RenderError::Cancelled);
        }
        if batch_bytes.len() > MAX_RENDER_BATCH_BYTES {
            return Err(RenderError::BatchTooLarge);
        }
        let batch: RenderBatch =
            serde_json::from_slice(batch_bytes).map_err(|_| RenderError::InvalidBatch)?;
        if batch.schema != "healthmd.render_input"
            || batch.render_input_version != RENDER_INPUT_VERSION
            || batch.session_id != self.config.session_id
            || batch.batch_index != self.next_batch_index
            || self.final_batch_seen
            || batch.days.len() > MAX_RENDER_BATCH_DATES
        {
            return Err(RenderError::SequenceInvalid);
        }
        let fact_count = batch
            .days
            .iter()
            .try_fold(0usize, |count, day| {
                count
                    .checked_add(day.metrics.len())
                    .and_then(|value| value.checked_add(day.extensions.len()))
            })
            .ok_or(RenderError::LimitExceeded)?;
        if fact_count > MAX_RENDER_FACTS_PER_BATCH {
            return Err(RenderError::LimitExceeded);
        }
        let next_bytes = self
            .bytes_accepted
            .checked_add(batch_bytes.len())
            .ok_or(RenderError::LimitExceeded)?;
        if next_bytes > MAX_SEMANTIC_RESULT_BYTES {
            return Err(RenderError::LimitExceeded);
        }

        let mut staged_days = self.days.clone();
        let mut staged_tokens = self.consumed_extensions.clone();
        for day in &batch.days {
            if is_cancelled() {
                self.terminal = true;
                return Err(RenderError::Cancelled);
            }
            validate_day(
                day,
                &self.config,
                &self.semantic_outputs,
                &self.presentation_categories,
                &self.retained_extensions,
                &mut staged_tokens,
            )?;
            if staged_days
                .insert(day.owner_date.clone(), day.clone())
                .is_some()
            {
                return Err(RenderError::SequenceInvalid);
            }
        }
        if staged_days.len() > MAX_RENDER_DATES {
            return Err(RenderError::LimitExceeded);
        }
        self.days = staged_days;
        self.consumed_extensions = staged_tokens;
        self.bytes_accepted = next_bytes;
        self.next_batch_index = self
            .next_batch_index
            .checked_add(1)
            .ok_or(RenderError::LimitExceeded)?;
        self.final_batch_seen = batch.final_batch;
        Ok(RenderBatchReceipt {
            next_batch_index: self.next_batch_index,
            days_accepted: u32::try_from(batch.days.len())
                .map_err(|_| RenderError::LimitExceeded)?,
            facts_accepted: u32::try_from(fact_count).map_err(|_| RenderError::LimitExceeded)?,
            final_batch: batch.final_batch,
        })
    }

    /// Finalize deterministic profile bytes and an artifact plan.
    ///
    /// # Errors
    /// Returns a stable sequence, cancellation, rendering, path, or output-bound error.
    pub fn finish(&mut self, is_cancelled: impl Fn() -> bool) -> Result<ArtifactPlan, RenderError> {
        if self.terminal {
            return Err(RenderError::SessionTerminal);
        }
        if is_cancelled() {
            self.terminal = true;
            return Err(RenderError::Cancelled);
        }
        if !self.final_batch_seen
            || self.days.len() != self.semantic.days.len()
            || self
                .semantic
                .days
                .iter()
                .any(|day| !self.days.contains_key(&day.owner_date))
        {
            return Err(RenderError::SequenceInvalid);
        }
        let result = render_plan(&self.config, &self.semantic, &self.days, &is_cancelled);
        if matches!(result, Err(RenderError::Cancelled)) {
            self.terminal = true;
        }
        if result.is_ok() {
            self.terminal = true;
        }
        result
    }
}

fn profile_presentation_categories(
    profile: SemanticProfile,
) -> Result<HashMap<String, BTreeSet<String>>, RenderError> {
    let registry_profile = match profile {
        SemanticProfile::AppleHealthDataV8 => {
            crate::registry::MetricRegistryProfile::AppleHealthDataV8
        }
        SemanticProfile::AndroidFrozenV4 => crate::registry::MetricRegistryProfile::AndroidFrozenV4,
        SemanticProfile::AndroidAnalyticalV5 => {
            crate::registry::MetricRegistryProfile::AndroidAnalyticalV5
        }
    };
    let snapshot = crate::registry::metric_registry_snapshot(registry_profile, REGISTRY_VERSION)
        .map_err(|_| RenderError::InvalidConfig)?;
    let categories_by_selection = snapshot
        .metrics
        .into_iter()
        .map(|metric| {
            (
                metric.selection_id,
                renderer_category_id(&metric.category_id),
            )
        })
        .collect::<HashMap<_, _>>();
    snapshot
        .outputs
        .into_iter()
        .map(|output| {
            let categories = output
                .selection_ids
                .iter()
                .filter_map(|selection| categories_by_selection.get(selection).cloned())
                .collect::<BTreeSet<_>>();
            if categories.is_empty() {
                Err(RenderError::InvalidConfig)
            } else {
                Ok((output.key, categories))
            }
        })
        .collect()
}

fn renderer_category_id(value: &str) -> String {
    match value {
        "Body Measurements" => return "body".to_owned(),
        "Reproductive" | "Reproductive Health" => return "reproductive_health".to_owned(),
        _ => {}
    }
    value
        .chars()
        .flat_map(char::to_lowercase)
        .map(|character| {
            if character.is_alphanumeric() {
                character
            } else {
                '_'
            }
        })
        .collect::<String>()
        .split('_')
        .filter(|component| !component.is_empty())
        .collect::<Vec<_>>()
        .join("_")
}

#[allow(clippy::too_many_lines)]
fn validate_config(
    config: &RenderSessionConfig,
    semantic: &SemanticResult,
) -> Result<(), RenderError> {
    if config.render_input_version != RENDER_INPUT_VERSION {
        return Err(RenderError::UnsupportedRenderInputVersion);
    }
    if config.artifact_plan_version != ARTIFACT_PLAN_VERSION {
        return Err(RenderError::UnsupportedArtifactPlanVersion);
    }
    if config.render_profile_revision != RENDER_PROFILE_REVISION
        || !matches!(config.profile_revision, 1 | 2)
    {
        return Err(RenderError::UnsupportedProfileRevision);
    }
    if config.schema != "healthmd.render_session_config"
        || config.canonical_model_version != CANONICAL_MODEL_VERSION
        || config.registry_version != REGISTRY_VERSION
        || config.registry_sha256 != REGISTRY_SHA256
        || semantic.schema != "healthmd.semantic_result"
        || semantic.canonical_model_version != CANONICAL_MODEL_VERSION
        || semantic.registry_sha256 != REGISTRY_SHA256
        || semantic.profile_revision != config.profile_revision
        || semantic.session_id != config.session_id
        || semantic.profile != config.profile
        || semantic.state != SemanticResultState::Completed
        || config.locale != "en-US"
        || validate_identifier(&config.request_id).is_err()
        || validate_identifier(&config.session_id).is_err()
        || config.calendar_time_zone.is_empty()
        || config.formats.is_empty()
        || config.formats.len() > 4
        || config.raw_capture_status.len() > 32
        || config.markdown.section_header_level == 0
        || config.markdown.section_header_level > 6
        || config.markdown.bullet.is_empty()
        || config.markdown.bullet.len() > 8
        || validate_identifier(&config.frontmatter.date_key).is_err()
        || validate_identifier(&config.frontmatter.type_key).is_err()
        || validate_optional_small_text(&config.frontmatter.type_value).is_err()
        || config.custom_frontmatter.len() > 256
        || config.placeholder_frontmatter.len() > 256
        || config.disabled_frontmatter_keys.len() > 512
    {
        return Err(RenderError::InvalidConfig);
    }
    if config.calendar_time_zone.parse::<chrono_tz::Tz>().is_err()
        || semantic
            .rollups
            .iter()
            .any(|rollup| rollup.calendar_time_zone != config.calendar_time_zone)
    {
        return Err(RenderError::InvalidConfig);
    }
    if config.profile != SemanticProfile::AppleHealthDataV8
        && (!semantic.rollups.is_empty() || config.rollups.is_some())
    {
        return Err(RenderError::UnsupportedOperation);
    }
    let semantic_rollup_keys = semantic
        .rollups
        .iter()
        .flat_map(|rollup| rollup.values.iter().map(|value| value.output_key.as_str()))
        .collect::<BTreeSet<_>>();
    if semantic_rollup_keys.is_empty() {
        if let Some(settings) = &config.rollups {
            if chrono::DateTime::parse_from_rfc3339(&settings.generated_at).is_err() {
                return Err(RenderError::InvalidConfig);
            }
        }
    } else {
        let settings = config.rollups.as_ref().ok_or(RenderError::InvalidConfig)?;
        if chrono::DateTime::parse_from_rfc3339(&settings.generated_at).is_err()
            || settings.metrics.len() != semantic_rollup_keys.len()
            || semantic_rollup_keys
                .iter()
                .any(|key| !settings.metrics.contains_key(*key))
        {
            return Err(RenderError::InvalidConfig);
        }
        for presentation in settings.metrics.values() {
            for text in [
                &presentation.key,
                &presentation.canonical_key,
                &presentation.display_name,
                &presentation.category,
            ] {
                validate_small_text(text)?;
            }
            validate_optional_small_text(&presentation.unit)?;
            if let Some(notes) = &presentation.notes {
                validate_optional_small_text(notes)?;
            }
            let statistic_order = presentation.statistic_order.iter().collect::<HashSet<_>>();
            if statistic_order.len() != presentation.statistic_order.len() {
                return Err(RenderError::InvalidConfig);
            }
            for statistic in &presentation.statistic_order {
                validate_small_text(statistic)?;
            }
        }
    }
    if !matches!(
        config.raw_capture_status.as_str(),
        "complete" | "partial" | "not_requested" | "legacy_unavailable"
    ) {
        return Err(RenderError::InvalidConfig);
    }
    if let Some(api) = &config.api {
        let range_start = NaiveDate::parse_from_str(&api.date_range_start, "%Y-%m-%d");
        let range_end = NaiveDate::parse_from_str(&api.date_range_end, "%Y-%m-%d");
        if !api.enabled
            || api.envelope_version == 0
            || api.max_days_per_batch == 0
            || api.max_days_per_batch > 7
            || api.max_encoded_bytes == 0
            || chrono::DateTime::parse_from_rfc3339(&api.exported_at).is_err()
            || validate_identifier(&api.source).is_err()
            || range_start.is_err()
            || range_end.is_err()
            || range_start.ok() > range_end.ok()
            || api.failed_date_details.len() > MAX_RENDER_DATES
            || api.external_records.len() > MAX_RENDER_DATES
            || api.external_record_schema.is_some() != api.external_record_schema_version.is_some()
        {
            return Err(RenderError::InvalidConfig);
        }
        for failure in &api.failed_date_details {
            if NaiveDate::parse_from_str(&failure.owner_date, "%Y-%m-%d").is_err()
                || chrono::DateTime::parse_from_rfc3339(&failure.timestamp).is_err()
                || validate_identifier(&failure.reason).is_err()
            {
                return Err(RenderError::InvalidConfig);
            }
            if let Some(details) = &failure.error_details {
                validate_optional_small_text(details)?;
            }
        }
        for external in &api.external_records {
            if NaiveDate::parse_from_str(&external.owner_date, "%Y-%m-%d").is_err() {
                return Err(RenderError::InvalidConfig);
            }
            validate_public_value(&external.value, 0)?;
        }
        if config.profile == SemanticProfile::AndroidAnalyticalV5
            || (config.profile == SemanticProfile::AndroidFrozenV4
                && (!api.external_records.is_empty()
                    || api.external_record_schema.is_some()
                    || api.envelope_version != 1
                    || api.source != "android"))
            || (config.profile == SemanticProfile::AppleHealthDataV8
                && ((api.envelope_version == 1
                    && (!api.external_records.is_empty() || api.external_record_schema.is_some()))
                    || (api.envelope_version == 2 && api.external_record_schema.is_none())
                    || !matches!(api.envelope_version, 1 | 2)))
        {
            return Err(RenderError::UnsupportedOperation);
        }
    }
    let formats: BTreeSet<_> = config.formats.iter().copied().collect();
    if formats.len() != config.formats.len() {
        return Err(RenderError::InvalidConfig);
    }
    let reserved_frontmatter = reserved_frontmatter_keys();
    let mut configured_frontmatter = HashSet::new();
    for text in config
        .custom_frontmatter
        .keys()
        .chain(config.placeholder_frontmatter.iter())
    {
        validate_small_text(text)?;
        if reserved_frontmatter.contains(text.as_str()) || !configured_frontmatter.insert(text) {
            return Err(RenderError::InvalidConfig);
        }
    }
    let mut disabled_frontmatter = HashSet::new();
    for text in &config.disabled_frontmatter_keys {
        validate_small_text(text)?;
        if reserved_frontmatter.contains(text.as_str())
            || !disabled_frontmatter.insert(text)
            || configured_frontmatter.contains(text)
        {
            return Err(RenderError::InvalidConfig);
        }
    }
    for value in config.custom_frontmatter.values() {
        validate_optional_small_text(value)?;
    }
    validate_date_template(&config.paths.filename_template, false)?;
    validate_date_template(&config.paths.folder_template, true)?;
    if !config.paths.bases_suffix.is_empty() {
        validate_template_component(&config.paths.bases_suffix)?;
    }
    for component in [
        &config.paths.base_directory,
        &config.paths.rollup_directory,
        &config.paths.format_folders.markdown,
        &config.paths.format_folders.obsidian_bases,
        &config.paths.format_folders.json,
        &config.paths.format_folders.csv,
    ] {
        if !component.is_empty() {
            if component.contains(['{', '}']) {
                return Err(RenderError::InvalidConfig);
            }
            validate_relative_path(component)?;
        }
    }
    Ok(())
}

#[allow(clippy::too_many_lines)]
fn validate_day(
    day: &RenderDay,
    config: &RenderSessionConfig,
    semantic_outputs: &HashMap<String, HashMap<String, crate::semantic::SemanticDailyValue>>,
    presentation_categories: &HashMap<String, BTreeSet<String>>,
    retained: &HashMap<String, (String, BTreeSet<String>)>,
    consumed: &mut HashSet<String>,
) -> Result<(), RenderError> {
    NaiveDate::parse_from_str(&day.owner_date, "%Y-%m-%d")
        .map_err(|_| RenderError::InvalidBatch)?;
    let accepted = semantic_outputs
        .get(&day.owner_date)
        .ok_or(RenderError::PresentationMismatch)?;
    if day.title.len() > MAX_TEXT_BYTES {
        return Err(RenderError::LimitExceeded);
    }
    match (config.profile, &day.archive_diagnostics) {
        (SemanticProfile::AppleHealthDataV8, Some(diagnostics)) => {
            if !matches!(
                diagnostics.capture_status.as_str(),
                "complete" | "partial" | "not_requested" | "legacy_unavailable"
            ) || diagnostics.record_schema.is_some()
                != diagnostics.record_schema_version.is_some()
            {
                return Err(RenderError::InvalidBatch);
            }
            if let Some(schema) = &diagnostics.record_schema {
                validate_small_text(schema)?;
            }
        }
        (_, None) => {}
        (_, Some(_)) => return Err(RenderError::InvalidBatch),
    }
    let mut keys = HashSet::new();
    let mut ordinals = HashSet::new();
    let mut frontmatter_keys = HashSet::new();
    let mut json_top_level = HashSet::new();
    let reserved_frontmatter = reserved_frontmatter_keys();
    let reserved_json = reserved_json_keys();
    for metric in &day.metrics {
        let semantic_value = accepted
            .get(&metric.output_key)
            .ok_or(RenderError::PresentationMismatch)?;
        let allowed_categories = presentation_categories
            .get(&metric.output_key)
            .ok_or(RenderError::PresentationMismatch)?;
        if !allowed_categories.contains(&metric.category_id)
            || !public_value_matches(&metric.public_value, &semantic_value.value)?
            || !keys.insert(metric.output_key.clone())
            || !ordinals.insert(metric.ordinal)
            || !frontmatter_keys.insert(metric.frontmatter_key.clone())
            || reserved_frontmatter.contains(metric.frontmatter_key.as_str())
            || metric.json_path.is_empty()
            || metric.json_path.len() > 3
        {
            return Err(RenderError::PresentationMismatch);
        }
        for text in [
            &metric.output_key,
            &metric.category_id,
            &metric.category_label,
            &metric.label,
            &metric.frontmatter_key,
            &metric.display_value,
        ] {
            validate_small_text(text)?;
        }
        validate_optional_small_text(&metric.unit)?;
        for path in &metric.json_path {
            validate_small_text(path)?;
        }
        let top_level = metric
            .json_path
            .first()
            .ok_or(RenderError::PresentationMismatch)?;
        if reserved_json.contains(top_level.as_str()) {
            return Err(RenderError::PresentationMismatch);
        }
        json_top_level.insert(top_level.clone());
        validate_public_value(&metric.public_value, 0)?;
    }
    if keys.len() != accepted.len() || accepted.keys().any(|key| !keys.contains(key)) {
        return Err(RenderError::PresentationMismatch);
    }
    let mut bases_frontmatter_keys = HashSet::new();
    for field in &day.bases_frontmatter_fields {
        validate_small_text(&field.key)?;
        validate_optional_small_text(&field.value)?;
        if !bases_frontmatter_keys.insert(field.key.clone()) {
            return Err(RenderError::InvalidBatch);
        }
    }
    let mut frontmatter_block_keys = HashSet::new();
    for block in &day.bases_frontmatter_blocks {
        validate_small_text(&block.key)?;
        if !frontmatter_block_keys.insert(block.key.clone())
            || bases_frontmatter_keys.contains(&block.key)
            || block.lines.is_empty()
            || block.lines.len() > 4_096
        {
            return Err(RenderError::InvalidBatch);
        }
        for line in &block.lines {
            validate_optional_small_text(line)?;
        }
    }
    for extension in &day.extensions {
        if !config.include_platform_extensions {
            return Err(RenderError::ExtensionNotRetained);
        }
        let (extension_owner_date, selected) = retained
            .get(&extension.retention_token)
            .ok_or(RenderError::ExtensionNotRetained)?;
        if extension_owner_date != &day.owner_date {
            return Err(RenderError::ExtensionNotRetained);
        }
        if !consumed.insert(extension.retention_token.clone()) {
            return Err(RenderError::ExtensionNotRetained);
        }
        let payload_selections: BTreeSet<_> = extension.selection_ids.iter().cloned().collect();
        if payload_selections.len() != extension.selection_ids.len()
            || &payload_selections != selected
        {
            return Err(RenderError::ExtensionSelectionInvalid);
        }
        let encoded =
            serde_json::to_vec(extension).map_err(|_| RenderError::SerializationFailed)?;
        if encoded.len() > MAX_EXTENSION_PAYLOAD_BYTES {
            return Err(RenderError::LimitExceeded);
        }
        if extension.json_field.is_some() != extension.json_value.is_some() {
            return Err(RenderError::InvalidBatch);
        }
        if let Some(field) = &extension.json_field {
            validate_small_text(field)?;
            if reserved_json.contains(field.as_str()) || !json_top_level.insert(field.clone()) {
                return Err(RenderError::PresentationMismatch);
            }
        }
        if let Some(value) = &extension.json_value {
            validate_public_value(value, 0)?;
        }
        for row in &extension.csv_rows {
            for value in [
                &row.date,
                &row.category,
                &row.metric,
                &row.value,
                &row.unit,
                &row.timestamp,
            ] {
                validate_optional_small_text(value)?;
            }
        }
        for block in &extension.markdown_blocks {
            validate_small_text(&block.heading)?;
            for line in &block.lines {
                validate_optional_small_text(line)?;
            }
        }
        for attachment in &extension.attachments {
            validate_relative_path(&attachment.relative_path)?;
            validate_small_text(&attachment.media_type)?;
        }
    }
    let mut entry_ids = HashSet::new();
    for entry in &day.individual_entries {
        validate_relative_path(&entry.relative_path)?;
        validate_small_text(&entry.entry_id)?;
        validate_optional_small_text(&entry.title)?;
        if !entry_ids.insert(entry.entry_id.clone()) {
            return Err(RenderError::InvalidBatch);
        }
        if entry.frontmatter.len() > 256 || entry.body_lines.len() > 4_096 {
            return Err(RenderError::LimitExceeded);
        }
        let output_keys = entry.output_keys.iter().collect::<HashSet<_>>();
        if output_keys.is_empty()
            || output_keys.len() != entry.output_keys.len()
            || output_keys
                .iter()
                .any(|key| !accepted.contains_key(key.as_str()))
        {
            return Err(RenderError::PresentationMismatch);
        }
        for (key, value) in &entry.frontmatter {
            validate_small_text(key)?;
            validate_optional_small_text(value)?;
        }
        for line in &entry.body_lines {
            validate_optional_small_text(line)?;
        }
        if let Some(document) = &entry.document {
            validate_line_document(document)?;
        }
    }
    let has_profile_document = day.profile_documents.markdown_body.is_some()
        || day.profile_documents.csv_rows.is_some()
        || day.profile_documents.json_root.is_some();
    if has_profile_document {
        let supplied = day
            .profile_documents
            .semantic_output_keys
            .iter()
            .cloned()
            .collect::<BTreeSet<_>>();
        let expected = accepted.keys().cloned().collect::<BTreeSet<_>>();
        if supplied.len() != day.profile_documents.semantic_output_keys.len()
            || supplied != expected
        {
            return Err(RenderError::PresentationMismatch);
        }
    } else if !day.profile_documents.semantic_output_keys.is_empty() {
        return Err(RenderError::PresentationMismatch);
    }
    if let Some(document) = &day.profile_documents.markdown_body {
        if document.lines.len() > 16_384 {
            return Err(RenderError::LimitExceeded);
        }
        for line in &document.lines {
            validate_optional_small_text(line)?;
        }
    }
    if let Some(rows) = &day.profile_documents.csv_rows {
        if rows.len() > 100_000 {
            return Err(RenderError::LimitExceeded);
        }
        for row in rows {
            if !matches!(row.cells.len(), 5 | 6) {
                return Err(RenderError::InvalidBatch);
            }
            for cell in &row.cells {
                validate_optional_small_text(cell)?;
            }
        }
    }
    if let Some(root) = &day.profile_documents.json_root {
        validate_ordered_json(root, 0)?;
    }
    if let Some(note) = &day.daily_note {
        validate_relative_path(&note.relative_path)?;
        if !note.include_frontmatter && !note.include_markdown {
            return Err(RenderError::InvalidBatch);
        }
        let output_keys = note.output_keys.iter().collect::<HashSet<_>>();
        if output_keys.is_empty()
            || output_keys.len() != note.output_keys.len()
            || output_keys
                .iter()
                .any(|key| !accepted.contains_key(key.as_str()))
        {
            return Err(RenderError::PresentationMismatch);
        }
        if let Some(document) = &note.document {
            validate_line_document(document)?;
        }
    }
    Ok(())
}

fn validate_line_document(document: &RenderLineDocument) -> Result<(), RenderError> {
    if document.lines.len() > 16_384 {
        return Err(RenderError::LimitExceeded);
    }
    for line in &document.lines {
        validate_optional_small_text(line)?;
    }
    Ok(())
}

fn validate_ordered_json(value: &OrderedJsonValue, depth: usize) -> Result<(), RenderError> {
    if depth > 64 {
        return Err(RenderError::LimitExceeded);
    }
    match value {
        OrderedJsonValue::Null | OrderedJsonValue::Boolean { .. } => Ok(()),
        OrderedJsonValue::Number { decimal } => {
            let parsed =
                serde_json::from_str::<Value>(decimal).map_err(|_| RenderError::InvalidBatch)?;
            if !parsed.is_number() || decimal.len() > 64 {
                return Err(RenderError::InvalidBatch);
            }
            Ok(())
        }
        OrderedJsonValue::String { value } => validate_optional_small_text(value),
        OrderedJsonValue::Array { items } => {
            if items.len() > 100_000 {
                return Err(RenderError::LimitExceeded);
            }
            for item in items {
                validate_ordered_json(item, depth + 1)?;
            }
            Ok(())
        }
        OrderedJsonValue::Object { entries } => {
            if entries.len() > 4_096 {
                return Err(RenderError::LimitExceeded);
            }
            let mut keys = HashSet::new();
            for entry in entries {
                validate_small_text(&entry.key)?;
                if !keys.insert(&entry.key) {
                    return Err(RenderError::InvalidBatch);
                }
                validate_ordered_json(&entry.value, depth + 1)?;
            }
            Ok(())
        }
    }
}

fn public_value_matches(public: &Value, semantic: &SemanticValue) -> Result<bool, RenderError> {
    match semantic {
        SemanticValue::Number { number, .. } => {
            let Value::Number(public) = public else {
                return Ok(false);
            };
            match number {
                ExactNumber::Binary64 { bits } => {
                    let raw = u64::from_str_radix(bits, 16)
                        .map_err(|_| RenderError::InvalidSemanticResult)?;
                    let expected = f64::from_bits(raw);
                    Ok(public
                        .as_f64()
                        .is_some_and(|value| value.to_bits() == expected.to_bits()))
                }
                ExactNumber::SignedInteger { decimal } => {
                    let expected = decimal
                        .parse::<i64>()
                        .map_err(|_| RenderError::InvalidSemanticResult)?;
                    Ok(public.as_i64() == Some(expected))
                }
                ExactNumber::UnsignedInteger { decimal } => {
                    let expected = decimal
                        .parse::<u64>()
                        .map_err(|_| RenderError::InvalidSemanticResult)?;
                    Ok(public.as_u64() == Some(expected))
                }
            }
        }
        SemanticValue::Text { text } => Ok(public.as_str() == Some(text)),
        SemanticValue::Boolean { boolean } => Ok(public.as_bool() == Some(*boolean)),
        SemanticValue::TextList { items } => Ok(public.as_array().is_some_and(|values| {
            values.len() == items.len()
                && values
                    .iter()
                    .zip(items)
                    .all(|(value, item)| value.as_str() == Some(item))
        })),
    }
}

fn validate_public_value(value: &Value, depth: usize) -> Result<(), RenderError> {
    if depth > 32 {
        return Err(RenderError::InvalidBatch);
    }
    match value {
        Value::Null | Value::Bool(_) | Value::Number(_) => Ok(()),
        Value::String(text) => validate_small_text(text),
        Value::Array(values) => {
            if values.len() > 4_096 {
                return Err(RenderError::LimitExceeded);
            }
            for value in values {
                validate_public_value(value, depth + 1)?;
            }
            Ok(())
        }
        Value::Object(values) => {
            if values.len() > 4_096 {
                return Err(RenderError::LimitExceeded);
            }
            for (key, value) in values {
                validate_small_text(key)?;
                validate_public_value(value, depth + 1)?;
            }
            Ok(())
        }
    }
}

fn validate_identifier(value: &str) -> Result<(), RenderError> {
    if value.is_empty()
        || value.len() > 128
        || value.contains(['/', '\\', '\0', '{', '}'])
        || value.chars().any(char::is_control)
    {
        Err(RenderError::InvalidConfig)
    } else {
        Ok(())
    }
}

fn validate_small_text(value: &str) -> Result<(), RenderError> {
    if value.is_empty() || value.len() > MAX_TEXT_BYTES || value.contains('\0') {
        Err(RenderError::InvalidBatch)
    } else {
        Ok(())
    }
}

fn validate_optional_small_text(value: &str) -> Result<(), RenderError> {
    if value.len() > MAX_TEXT_BYTES || value.contains('\0') {
        Err(RenderError::InvalidBatch)
    } else {
        Ok(())
    }
}

fn reserved_frontmatter_keys() -> BTreeSet<&'static str> {
    [
        "schema",
        "schema_version",
        "healthmd_schema_profile",
        "date",
        "type",
        "raw_capture_status",
        "time_context",
        "unit_system",
        "units",
    ]
    .into_iter()
    .collect()
}

fn reserved_json_keys() -> BTreeSet<&'static str> {
    [
        "schema",
        "schema_version",
        "schemaProfile",
        "schemaVersion",
        "date",
        "type",
        "time_context",
        "unit_system",
        "units",
        "raw_capture_status",
    ]
    .into_iter()
    .collect()
}

fn validate_date_template(value: &str, allow_path: bool) -> Result<(), RenderError> {
    if (!allow_path && value.is_empty()) || value.len() > 4_096 || value.contains(['\\', '\0']) {
        return Err(RenderError::InvalidConfig);
    }
    if value.is_empty() {
        return Ok(());
    }
    let sample = NaiveDate::from_ymd_opt(2026, 7, 25).ok_or(RenderError::InvalidConfig)?;
    let resolved =
        resolve_date_template(value, sample, "profile").map_err(|_| RenderError::InvalidConfig)?;
    if !allow_path && resolved.contains('/') {
        return Err(RenderError::InvalidConfig);
    }
    validate_relative_path(&resolved).map_err(|_| RenderError::InvalidConfig)
}

fn validate_template_component(value: &str) -> Result<(), RenderError> {
    if value.is_empty()
        || value.len() > 256
        || value.contains('/')
        || value.contains('\\')
        || value.contains('\0')
    {
        return Err(RenderError::InvalidConfig);
    }
    Ok(())
}

fn render_plan(
    config: &RenderSessionConfig,
    semantic: &SemanticResult,
    days: &BTreeMap<String, RenderDay>,
    is_cancelled: &impl Fn() -> bool,
) -> Result<ArtifactPlan, RenderError> {
    let mut builder = artifact_plan::ArtifactPlanBuilder::new(
        &config.request_id,
        &config.session_id,
        config.profile,
    );
    let formats = ordered_formats(config.profile, &config.formats);
    let mut daily_json = Vec::new();
    for day in days.values() {
        if is_cancelled() {
            return Err(RenderError::Cancelled);
        }
        for format in &formats {
            let content = render_day(config, day, *format)?;
            let path = daily_path(config, day, *format)?;
            builder.add(
                path,
                format.media_type(),
                normalized_write_mode(config.write_mode, *format),
                content,
            )?;
        }
        if config.api.as_ref().is_some_and(|api| api.enabled) {
            daily_json.push((day.owner_date.clone(), render_api_record(config, day)?));
        }
        add_entries_and_note(&mut builder, config, day)?;
        for extension in &day.extensions {
            let mut attachments = extension.attachments.clone();
            attachments
                .sort_by_key(|attachment| (attachment.ordinal, attachment.relative_path.clone()));
            for attachment in attachments {
                use base64::Engine as _;
                let bytes = base64::engine::general_purpose::STANDARD
                    .decode(attachment.bytes_base64)
                    .map_err(|_| RenderError::InvalidArtifact)?;
                builder.add(
                    attachment.relative_path,
                    &attachment.media_type,
                    WriteMode::Overwrite,
                    bytes,
                )?;
            }
        }
    }
    if config.profile == SemanticProfile::AppleHealthDataV8 {
        apple_v8::add_rollups(&mut builder, config, semantic)?;
    }
    if let Some(api) = &config.api {
        if api.enabled {
            add_api_batches(&mut builder, config, api, &daily_json)?;
        }
    }
    builder.finish()
}

fn render_day(
    config: &RenderSessionConfig,
    day: &RenderDay,
    format: RenderFormat,
) -> Result<Vec<u8>, RenderError> {
    match config.profile {
        SemanticProfile::AppleHealthDataV8 => apple_v8::render_day(config, day, format),
        SemanticProfile::AndroidFrozenV4 => android_frozen_v4::render_day(config, day, format),
        SemanticProfile::AndroidAnalyticalV5 => {
            android_analytical_v5::render_day(config, day, format)
        }
    }
}

fn ordered_formats(profile: SemanticProfile, requested: &[RenderFormat]) -> Vec<RenderFormat> {
    let mut formats = requested.to_vec();
    match profile {
        SemanticProfile::AppleHealthDataV8 => formats.sort_by_key(|format| format.id()),
        SemanticProfile::AndroidFrozenV4 | SemanticProfile::AndroidAnalyticalV5 => formats
            .sort_by_key(|format| match format {
                RenderFormat::Markdown => 0,
                RenderFormat::ObsidianBases => 1,
                RenderFormat::Json => 2,
                RenderFormat::Csv => 3,
            }),
    }
    formats
}

fn normalized_write_mode(requested: RequestedWriteMode, format: RenderFormat) -> WriteMode {
    match requested {
        RequestedWriteMode::Append => WriteMode::Append,
        RequestedWriteMode::Update if format == RenderFormat::Markdown => WriteMode::MarkdownMerge,
        RequestedWriteMode::Overwrite | RequestedWriteMode::Update => WriteMode::Overwrite,
    }
}

fn daily_path(
    config: &RenderSessionConfig,
    day: &RenderDay,
    format: RenderFormat,
) -> Result<String, RenderError> {
    let date = NaiveDate::parse_from_str(&day.owner_date, "%Y-%m-%d")
        .map_err(|_| RenderError::InvalidPath)?;
    let profile = profile_id(config.profile);
    let mut name = resolve_date_template(&config.paths.filename_template, date, profile)?;
    if name.is_empty() || name.contains('/') {
        return Err(RenderError::InvalidPath);
    }
    let folder = resolve_date_template(&config.paths.folder_template, date, profile)?;
    let format_folder = config.paths.format_folders.for_format(format);
    if format == RenderFormat::ObsidianBases
        && config.formats.contains(&RenderFormat::Markdown)
        && format_folder == config.paths.format_folders.markdown
    {
        name.push_str(&config.paths.bases_suffix);
    }
    name.push('.');
    name.push_str(format.extension());
    let path = join_relative(&[&config.paths.base_directory, format_folder, &folder, &name]);
    validate_relative_path(&path)?;
    Ok(path)
}

fn resolve_date_template(
    template: &str,
    date: NaiveDate,
    profile: &str,
) -> Result<String, RenderError> {
    const WEEKDAYS: [&str; 7] = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
    ];
    const MONTHS: [&str; 12] = [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December",
    ];
    let month_index = usize::try_from(date.month0()).map_err(|_| RenderError::InvalidPath)?;
    let weekday_index = usize::try_from(date.weekday().num_days_from_monday())
        .map_err(|_| RenderError::InvalidPath)?;
    let mut value = template.to_owned();
    for (marker, replacement) in [
        (
            "{date}",
            format!("{:04}-{:02}-{:02}", date.year(), date.month(), date.day()),
        ),
        ("{year}", format!("{:04}", date.year())),
        ("{YR}", format!("{:02}", date.year().rem_euclid(100))),
        ("{month}", format!("{:02}", date.month())),
        ("{day}", format!("{:02}", date.day())),
        ("{weekday}", WEEKDAYS[weekday_index].to_owned()),
        ("{monthName}", MONTHS[month_index].to_owned()),
        ("{quarter}", format!("Q{}", (date.month() - 1) / 3 + 1)),
        ("{profile}", profile.to_owned()),
    ] {
        value = value.replace(marker, &replacement);
    }
    if value.contains(['{', '}']) {
        return Err(RenderError::InvalidPath);
    }
    Ok(value)
}

fn join_relative(parts: &[&str]) -> String {
    parts
        .iter()
        .filter(|part| !part.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join("/")
}

fn add_entries_and_note(
    builder: &mut artifact_plan::ArtifactPlanBuilder,
    config: &RenderSessionConfig,
    day: &RenderDay,
) -> Result<(), RenderError> {
    let mut entries = day.individual_entries.clone();
    entries.sort_by_key(|entry| (entry.ordinal, entry.entry_id.clone()));
    for entry in entries {
        let bytes = format::render_individual_entry(&entry)?;
        builder.add(
            entry.relative_path,
            "text/markdown; charset=utf-8",
            WriteMode::Overwrite,
            bytes,
        )?;
    }
    if let Some(note) = &day.daily_note {
        let bytes = format::render_daily_note(config, day, note)?;
        builder.add(
            note.relative_path.clone(),
            "text/markdown; charset=utf-8",
            WriteMode::MarkdownMerge,
            bytes,
        )?;
    }
    Ok(())
}

type ApiOutcome = (String, Option<(String, Vec<u8>)>);

fn add_api_batches(
    builder: &mut artifact_plan::ArtifactPlanBuilder,
    config: &RenderSessionConfig,
    api: &ApiSettings,
    records: &[(String, Vec<u8>)],
) -> Result<(), RenderError> {
    let range_start = NaiveDate::parse_from_str(&api.date_range_start, "%Y-%m-%d")
        .map_err(|_| RenderError::InvalidConfig)?;
    let range_end = NaiveDate::parse_from_str(&api.date_range_end, "%Y-%m-%d")
        .map_err(|_| RenderError::InvalidConfig)?;
    let records_by_date = records
        .iter()
        .map(|record| (record.0.as_str(), record))
        .collect::<HashMap<_, _>>();
    if records_by_date.len() != records.len() {
        return Err(RenderError::InvalidConfig);
    }
    let failures_by_date = api
        .failed_date_details
        .iter()
        .map(|failure| (failure.owner_date.as_str(), failure))
        .collect::<HashMap<_, _>>();
    if failures_by_date.len() != api.failed_date_details.len() {
        return Err(RenderError::InvalidConfig);
    }
    let mut outcomes = Vec::new();
    let mut date = range_start;
    loop {
        let owner_date = date.format("%Y-%m-%d").to_string();
        let record = records_by_date.get(owner_date.as_str()).copied();
        let failure = failures_by_date.get(owner_date.as_str()).copied();
        if record.is_some() == failure.is_some() {
            return Err(RenderError::InvalidConfig);
        }
        outcomes.push((owner_date, record.cloned()));
        if date == range_end {
            break;
        }
        date = date.succ_opt().ok_or(RenderError::InvalidConfig)?;
        if outcomes.len() >= MAX_RENDER_DATES {
            return Err(RenderError::LimitExceeded);
        }
    }
    let outcome_dates = outcomes
        .iter()
        .map(|outcome| outcome.0.as_str())
        .collect::<HashSet<_>>();
    if records
        .iter()
        .any(|record| !outcome_dates.contains(record.0.as_str()))
        || api
            .failed_date_details
            .iter()
            .any(|failure| !outcome_dates.contains(failure.owner_date.as_str()))
        || api.external_records.iter().any(|external| {
            !records_by_date.contains_key(external.owner_date.as_str())
                || !outcome_dates.contains(external.owner_date.as_str())
        })
    {
        return Err(RenderError::InvalidConfig);
    }

    let max_days =
        usize::try_from(api.max_days_per_batch).map_err(|_| RenderError::InvalidConfig)?;
    let mut start = 0usize;
    let mut batch_index = 0u32;
    while start < outcomes.len() {
        let mut chosen_end = start;
        for end in start + 1..=outcomes.len().min(start + max_days) {
            let (scoped, scoped_records) = scoped_api_batch(api, &outcomes[start..end]);
            let bytes = render_api_envelope(config, &scoped, &scoped_records)?;
            let exceeds = u64::try_from(bytes.len()).map_err(|_| RenderError::ArtifactTooLarge)?
                > api.max_encoded_bytes;
            if exceeds && end > start + 1 {
                break;
            }
            chosen_end = end;
            if exceeds {
                break;
            }
        }
        if chosen_end == start {
            return Err(RenderError::InvalidConfig);
        }
        let (scoped, scoped_records) = scoped_api_batch(api, &outcomes[start..chosen_end]);
        let content = render_api_envelope(config, &scoped, &scoped_records)?;
        let path = format!("api/{}-{batch_index:04}.json", config.request_id);
        builder.add(path, "application/json", WriteMode::ApiPost, content)?;
        start = chosen_end;
        batch_index = batch_index
            .checked_add(1)
            .ok_or(RenderError::ArtifactLimitExceeded)?;
    }
    Ok(())
}

fn scoped_api_batch(
    api: &ApiSettings,
    outcomes: &[ApiOutcome],
) -> (ApiSettings, Vec<(String, Vec<u8>)>) {
    let dates = outcomes
        .iter()
        .map(|outcome| outcome.0.as_str())
        .collect::<HashSet<_>>();
    let mut scoped = api.clone();
    scoped.date_range_start = outcomes
        .first()
        .map_or_else(String::new, |outcome| outcome.0.clone());
    scoped.date_range_end = outcomes
        .last()
        .map_or_else(String::new, |outcome| outcome.0.clone());
    scoped
        .failed_date_details
        .retain(|failure| dates.contains(failure.owner_date.as_str()));
    scoped
        .external_records
        .retain(|record| dates.contains(record.owner_date.as_str()));
    let records = outcomes
        .iter()
        .filter_map(|outcome| outcome.1.clone())
        .collect();
    (scoped, records)
}

fn render_api_record(
    config: &RenderSessionConfig,
    day: &RenderDay,
) -> Result<Vec<u8>, RenderError> {
    match config.profile {
        SemanticProfile::AppleHealthDataV8 => apple_v8::render_api_record(config, day),
        SemanticProfile::AndroidFrozenV4 => android_frozen_v4::render_api_record(config, day),
        SemanticProfile::AndroidAnalyticalV5 => Err(RenderError::UnsupportedOperation),
    }
}

fn render_api_envelope(
    config: &RenderSessionConfig,
    api: &ApiSettings,
    records: &[(String, Vec<u8>)],
) -> Result<Vec<u8>, RenderError> {
    match config.profile {
        SemanticProfile::AppleHealthDataV8 => apple_v8::render_api_envelope(api, records),
        SemanticProfile::AndroidFrozenV4 => android_frozen_v4::render_api_envelope(api, records),
        SemanticProfile::AndroidAnalyticalV5 => Err(RenderError::UnsupportedOperation),
    }
}

pub(crate) const fn profile_id(profile: SemanticProfile) -> &'static str {
    match profile {
        SemanticProfile::AppleHealthDataV8 => "apple_health_data_v8",
        SemanticProfile::AndroidFrozenV4 => "android_frozen_v4",
        SemanticProfile::AndroidAnalyticalV5 => "android_analytical_v5",
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn errors_have_stable_health_free_codes() {
        let private = "private-health-value";
        for error in [
            RenderError::InvalidConfig,
            RenderError::PresentationMismatch,
            RenderError::InvalidPath,
            RenderError::Cancelled,
        ] {
            assert!(!error.to_string().contains(private));
            assert!(!error.code().is_empty());
        }
    }

    #[test]
    fn format_order_and_update_mode_are_profile_specific() {
        let formats = vec![
            RenderFormat::Csv,
            RenderFormat::Markdown,
            RenderFormat::Json,
            RenderFormat::ObsidianBases,
        ];
        assert_eq!(
            ordered_formats(SemanticProfile::AppleHealthDataV8, &formats),
            vec![
                RenderFormat::Csv,
                RenderFormat::Json,
                RenderFormat::Markdown,
                RenderFormat::ObsidianBases,
            ]
        );
        assert_eq!(
            ordered_formats(SemanticProfile::AndroidFrozenV4, &formats),
            vec![
                RenderFormat::Markdown,
                RenderFormat::ObsidianBases,
                RenderFormat::Json,
                RenderFormat::Csv
            ]
        );
        assert_eq!(
            normalized_write_mode(RequestedWriteMode::Update, RenderFormat::Markdown),
            WriteMode::MarkdownMerge
        );
        assert_eq!(
            normalized_write_mode(RequestedWriteMode::Update, RenderFormat::Json),
            WriteMode::Overwrite
        );
    }

    #[test]
    fn all_profiles_render_all_formats_deterministically() {
        for profile in [
            SemanticProfile::AppleHealthDataV8,
            SemanticProfile::AndroidFrozenV4,
            SemanticProfile::AndroidAnalyticalV5,
        ] {
            let first = complete_plan(profile);
            let second = complete_plan(profile);
            assert_eq!(first, second);
            let expected_count = if profile == SemanticProfile::AndroidFrozenV4 {
                5
            } else {
                4
            };
            assert_eq!(first.items.len(), expected_count);
            assert!(
                first
                    .items
                    .iter()
                    .all(|item| item.byte_count == item.content.len() as u64)
            );
            assert!(
                first
                    .items
                    .iter()
                    .all(|item| item.sha256.len() == 64 && item.artifact_id.len() == 64)
            );
            let json = first
                .items
                .iter()
                .find(|item| {
                    std::path::Path::new(&item.relative_path)
                        .extension()
                        .is_some_and(|extension| extension.eq_ignore_ascii_case("json"))
                        && !item.relative_path.starts_with("api/")
                })
                .unwrap();
            let text = String::from_utf8(json.content.clone()).unwrap();
            match profile {
                SemanticProfile::AppleHealthDataV8 => {
                    assert!(text.contains("\"schema\" : \"healthmd.health_data\""));
                    assert!(text.contains("\"schema_version\" : 8"));
                }
                SemanticProfile::AndroidFrozenV4 => assert!(!text.contains("schemaProfile")),
                SemanticProfile::AndroidAnalyticalV5 => {
                    assert!(text.contains("\"schemaProfile\": \"android-analytical-v5\""));
                    assert!(text.contains("\"schemaVersion\": 5"));
                }
            }
        }
    }

    #[test]
    fn date_templates_and_bases_collision_suffix_match_native_paths() {
        let (config, semantic) = input_bytes(SemanticProfile::AppleHealthDataV8);
        let mut value: Value = serde_json::from_slice(&config).unwrap();
        value["formats"] = json!(["markdown", "obsidian_bases"]);
        value["paths"]["filename_template"] =
            json!("{YR}-{month}-{day}-{weekday}-{monthName}-{quarter}");
        value["paths"]["folder_template"] = json!("{year}/{month}");
        let mut session =
            RenderSession::from_json(&serde_json::to_vec(&value).unwrap(), &semantic).unwrap();
        session
            .process_batch(&serde_json::to_vec(&render_batch()).unwrap(), || false)
            .unwrap();
        let paths = session
            .finish(|| false)
            .unwrap()
            .items
            .into_iter()
            .map(|item| item.relative_path)
            .collect::<Vec<_>>();
        assert_eq!(
            paths,
            [
                "Health/2026/07/26-07-25-Saturday-July-Q3.md",
                "Health/2026/07/26-07-25-Saturday-July-Q3-bases.md",
            ]
        );

        value["paths"]["format_folders"]["markdown"] = json!("Markdown");
        value["paths"]["format_folders"]["obsidian_bases"] = json!("Bases");
        let mut session =
            RenderSession::from_json(&serde_json::to_vec(&value).unwrap(), &semantic).unwrap();
        session
            .process_batch(&serde_json::to_vec(&render_batch()).unwrap(), || false)
            .unwrap();
        let paths = session
            .finish(|| false)
            .unwrap()
            .items
            .into_iter()
            .map(|item| item.relative_path)
            .collect::<Vec<_>>();
        assert!(
            paths
                .iter()
                .any(|path| path.ends_with("/26-07-25-Saturday-July-Q3.md"))
        );
        assert!(!paths.iter().any(|path| path.contains("-bases.md")));

        value["paths"]["filename_template"] = json!("{unknown}");
        assert_eq!(
            RenderSession::from_json(&serde_json::to_vec(&value).unwrap(), &semantic).unwrap_err(),
            RenderError::InvalidConfig
        );
    }

    #[test]
    fn extension_payloads_require_retained_tokens_and_selection_overlap() {
        let (mut config, mut semantic) = input_bytes(SemanticProfile::AppleHealthDataV8);
        let mut config_value: Value = serde_json::from_slice(&config).unwrap();
        config_value["include_platform_extensions"] = Value::Bool(true);
        config = serde_json::to_vec(&config_value).unwrap();
        let mut semantic_value: Value = serde_json::from_slice(&semantic).unwrap();
        semantic_value["retained_extensions"] = json!([{
            "owner_date":"2026-07-25","record_id":"extension-record",
            "extension":{"namespace":"apple.healthkit_archive","version":1,"retention_token":"retained-token","selection_ids":["steps"]}
        }]);
        semantic = serde_json::to_vec(&semantic_value).unwrap();
        let mut batch = render_batch();
        batch["days"][0]["extensions"] = json!([{
            "retention_token":"retained-token","selection_ids":["weight"],"ordinal":0,
            "json_field":null,"json_value":null,"csv_rows":[],"markdown_blocks":[],"attachments":[]
        }]);
        let mut session = RenderSession::from_json(&config, &semantic).unwrap();
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&batch).unwrap(), || false),
            Err(RenderError::ExtensionSelectionInvalid)
        );
        batch["days"][0]["extensions"][0]["selection_ids"] = json!(["steps", "weight"]);
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&batch).unwrap(), || false),
            Err(RenderError::ExtensionSelectionInvalid)
        );
        batch["days"][0]["extensions"][0]["selection_ids"] = json!(["steps"]);
        session
            .process_batch(&serde_json::to_vec(&batch).unwrap(), || false)
            .unwrap();
        assert!(session.finish(|| false).is_ok());
    }

    #[test]
    fn every_semantic_output_requires_one_presentation_fact() {
        let (config, semantic) = input_bytes(SemanticProfile::AppleHealthDataV8);
        let mut batch = render_batch();
        batch["days"][0]["metrics"] = json!([]);
        let mut session = RenderSession::from_json(&config, &semantic).unwrap();
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&batch).unwrap(), || false),
            Err(RenderError::PresentationMismatch)
        );
    }

    #[test]
    fn rich_profile_documents_are_bound_to_the_exact_semantic_output_set() {
        let (config, semantic) = input_bytes(SemanticProfile::AndroidFrozenV4);
        let mut invalid = render_batch();
        invalid["days"][0]["profile_documents"] = json!({
            "semantic_output_keys":["private_output"],
            "markdown_body":{"lines":["private"],"trailing_newline":true},
            "csv_rows":null,
            "json_root":null
        });
        let mut session = RenderSession::from_json(&config, &semantic).unwrap();
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&invalid).unwrap(), || false),
            Err(RenderError::PresentationMismatch)
        );
        invalid["days"][0]["profile_documents"]["semantic_output_keys"] = json!(["steps"]);
        assert!(
            session
                .process_batch(&serde_json::to_vec(&invalid).unwrap(), || false)
                .is_ok()
        );
    }

    #[test]
    fn invalid_batches_are_transactional_and_cancellation_is_terminal() {
        let (config, semantic) = input_bytes(SemanticProfile::AppleHealthDataV8);
        let mut session = RenderSession::from_json(&config, &semantic).unwrap();
        let mut invalid = render_batch();
        invalid["days"][0]["metrics"][0]["output_key"] =
            Value::String("private_invalid".to_owned());
        assert_eq!(
            session.process_batch(&serde_json::to_vec(&invalid).unwrap(), || false),
            Err(RenderError::PresentationMismatch)
        );
        assert_eq!(
            session
                .process_batch(&serde_json::to_vec(&render_batch()).unwrap(), || false)
                .unwrap()
                .next_batch_index,
            1
        );

        let mut cancelled = RenderSession::from_json(&config, &semantic).unwrap();
        assert_eq!(
            cancelled.process_batch(b"private payload", || true),
            Err(RenderError::Cancelled)
        );
        assert_eq!(
            cancelled.process_batch(b"{}", || false),
            Err(RenderError::SessionTerminal)
        );
    }

    #[test]
    fn individual_entries_and_daily_notes_plan_attested_exact_documents() {
        let (config, semantic) = input_bytes(SemanticProfile::AndroidFrozenV4);
        let mut batch = render_batch();
        batch["days"][0]["individual_entries"] = json!([{
            "entry_id":"steps-1",
            "output_keys":["steps"],
            "relative_path":"health/entries/steps-1.md",
            "title":"Steps",
            "frontmatter":{},
            "body_lines":[],
            "ordinal":0,
            "document":{"lines":["---","metric: steps","---","","# Steps","","- **Value:** 1234 count"],"trailing_newline":true}
        }]);
        batch["days"][0]["daily_note"] = json!({
            "relative_path":"Daily/2026-07-25.md",
            "output_keys":["steps"],
            "include_frontmatter":true,
            "include_markdown":true,
            "document":{"lines":["---","steps: 1234","---","","## Activity","- **Steps:** 1234"],"trailing_newline":true}
        });
        let mut session = RenderSession::from_json(&config, &semantic).unwrap();
        session
            .process_batch(&serde_json::to_vec(&batch).unwrap(), || false)
            .unwrap();
        let plan = session.finish(|| false).unwrap();
        let entry = plan
            .items
            .iter()
            .find(|item| item.relative_path == "health/entries/steps-1.md")
            .unwrap();
        assert_eq!(
            entry.content,
            b"---\nmetric: steps\n---\n\n# Steps\n\n- **Value:** 1234 count\n"
        );
        let note = plan
            .items
            .iter()
            .find(|item| item.relative_path == "Daily/2026-07-25.md")
            .unwrap();
        assert_eq!(note.write_mode, WriteMode::MarkdownMerge);
        assert_eq!(
            note.content,
            b"---\nsteps: 1234\n---\n\n## Activity\n- **Steps:** 1234\n"
        );
    }

    #[test]
    fn api_batches_include_failure_only_days_and_scope_exact_ranges() {
        let (config_bytes, _) = input_bytes(SemanticProfile::AndroidFrozenV4);
        let config: RenderSessionConfig = serde_json::from_slice(&config_bytes).unwrap();
        let mut api = config.api.clone().unwrap();
        api.date_range_start = "2026-07-25".to_owned();
        api.date_range_end = "2026-07-27".to_owned();
        api.max_days_per_batch = 2;
        api.failed_date_details = vec![ApiFailureDetail {
            owner_date: "2026-07-26".to_owned(),
            timestamp: "2026-07-26T00:00:00Z".to_owned(),
            reason: "no_health_data".to_owned(),
            error_details: None,
        }];
        let records = vec![
            ("2026-07-25".to_owned(), b"{}".to_vec()),
            ("2026-07-27".to_owned(), b"{}".to_vec()),
        ];
        let mut builder = artifact_plan::ArtifactPlanBuilder::new(
            &config.request_id,
            &config.session_id,
            config.profile,
        );
        add_api_batches(&mut builder, &config, &api, &records).unwrap();
        let plan = builder.finish().unwrap();
        assert_eq!(plan.items.len(), 2);
        let first = String::from_utf8(plan.items[0].content.clone()).unwrap();
        assert!(first.contains("\"start\": \"2026-07-25\""));
        assert!(first.contains("\"end\": \"2026-07-26\""));
        assert!(first.contains("\"record_count\": 1"));
        assert!(first.contains("\"reason\": \"no_health_data\""));
        let second = String::from_utf8(plan.items[1].content.clone()).unwrap();
        assert!(second.contains("\"start\": \"2026-07-27\""));
        assert!(!second.contains("no_health_data"));

        api.max_days_per_batch = 7;
        api.max_encoded_bytes = 1;
        let mut byte_bounded = artifact_plan::ArtifactPlanBuilder::new(
            &config.request_id,
            &config.session_id,
            config.profile,
        );
        add_api_batches(&mut byte_bounded, &config, &api, &records).unwrap();
        assert_eq!(byte_bounded.finish().unwrap().items.len(), 3);

        api.max_encoded_bytes = 8_388_608;
        api.date_range_start = "2026-07-26".to_owned();
        api.date_range_end = "2026-07-26".to_owned();
        let mut failure_only = artifact_plan::ArtifactPlanBuilder::new(
            &config.request_id,
            &config.session_id,
            config.profile,
        );
        add_api_batches(&mut failure_only, &config, &api, &[]).unwrap();
        assert_eq!(failure_only.finish().unwrap().items.len(), 1);
    }

    fn complete_plan(profile: SemanticProfile) -> ArtifactPlan {
        let (config, semantic) = input_bytes(profile);
        let mut session = RenderSession::from_json(&config, &semantic).unwrap();
        session
            .process_batch(&serde_json::to_vec(&render_batch()).unwrap(), || false)
            .unwrap();
        session.finish(|| false).unwrap()
    }

    fn input_bytes(profile: SemanticProfile) -> (Vec<u8>, Vec<u8>) {
        let profile_name = profile_id(profile);
        let api = if profile == SemanticProfile::AndroidFrozenV4 {
            json!({"enabled":true,"envelope_version":1,"exported_at":"2026-07-25T00:00:00Z","source":"android","date_range_start":"2026-07-25","date_range_end":"2026-07-25","failed_date_details":[],"external_record_schema":null,"external_record_schema_version":null,"external_records":[],"max_days_per_batch":7,"max_encoded_bytes":8_388_608})
        } else {
            Value::Null
        };
        let config = json!({
            "schema":"healthmd.render_session_config","render_input_version":1,"artifact_plan_version":1,
            "canonical_model_version":1,"registry_version":1,"registry_sha256":REGISTRY_SHA256,
            "profile_revision":1,"render_profile_revision":2,"request_id":"render-test","session_id":"render-session",
            "profile":profile_name,"calendar_time_zone":"UTC","locale":"en-US",
            "formats":["csv","markdown","json","obsidian_bases"],"unit_system":"metric",
            "include_metadata":true,"group_by_category":true,"include_platform_extensions":false,
            "raw_capture_status":"not_requested","write_mode":"update",
            "markdown":{"use_emoji":false,"section_header_level":2,"bullet":"-","include_summary":false,"custom_template":null},
            "frontmatter":{"include_date":true,"date_key":"date","include_type":true,"type_key":"type","type_value":"health-data"},
            "custom_frontmatter":{},"placeholder_frontmatter":[],"disabled_frontmatter_keys":[],
            "paths":{"base_directory":"Health","filename_template":"{date}","folder_template":"","format_folders":{"markdown":"","obsidian_bases":"","json":"","csv":""},"rollup_directory":"Rollups","bases_suffix":"-bases"},
            "rollups":null,"api":api
        });
        let semantic = json!({
            "schema":"healthmd.semantic_result","semantic_input_version":1,"canonical_model_version":1,"core_api_version":3,
            "registry_sha256":REGISTRY_SHA256,"profile_revision":1,"session_id":"render-session","profile":profile_name,
            "state":"completed","next_batch_index":1,"records_accepted":1,"records_filtered":0,
            "days":[{"owner_date":"2026-07-25","values":[{"output_key":"steps","semantic_id":"steps","aggregation":"sum","value":{"value_type":"number","number":{"representation":"unsigned_integer","decimal":"1234"},"unit":{"id":"count"}},"source_record_ids":["record-1"]}]}],
            "rollups":[],"retained_extensions":[]
        });
        (
            serde_json::to_vec(&config).unwrap(),
            serde_json::to_vec(&semantic).unwrap(),
        )
    }

    fn render_batch() -> Value {
        json!({
            "schema":"healthmd.render_input","render_input_version":1,"session_id":"render-session","batch_index":0,"final_batch":true,
            "days":[{"owner_date":"2026-07-25","title":"2026-07-25","archive_diagnostics":null,"bases_frontmatter_fields":[],"bases_frontmatter_blocks":[],"metrics":[{
                "output_key":"steps","category_id":"activity","category_label":"Activity","label":"Steps",
                "frontmatter_key":"steps","json_path":["activity","steps"],"public_value":1234,"display_value":"1234",
                "unit":"count","timestamp":null,"ordinal":1
            }],"extensions":[],"individual_entries":[],"daily_note":null}]
        })
    }
}
