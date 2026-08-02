use std::{collections::BTreeSet, fs, path::Path, time::Duration};

use chrono::{DateTime, Duration as ChronoDuration, NaiveDate, Utc};
use healthmd_protocol::{
    encoding::SwiftUuid,
    models::{
        CanonicalSelection, DateSelection, DetailLevel, ExactDateSelection, ExportDestination,
        ExportRequest, ResponseMode, SettingsPolicy,
    },
};
use serde_json::{Map, Value};
use uuid::Uuid;

use crate::limits::{
    DEFAULT_EXPORT_TIMEOUT_SECONDS, MAXIMUM_CATEGORIES, MAXIMUM_EXPORT_TIMEOUT_SECONDS,
    MAXIMUM_METRIC_IDS, MINIMUM_EXPORT_TIMEOUT_SECONDS,
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationInputError {
    pub code: &'static str,
    pub message: &'static str,
}

impl OperationInputError {
    const fn invalid(message: &'static str) -> Self {
        Self {
            code: "healthmd_invalid_arguments",
            message,
        }
    }
}

impl std::fmt::Display for OperationInputError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.message)
    }
}

impl std::error::Error for OperationInputError {}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct DateOptions {
    pub yesterday: bool,
    pub last: Option<u32>,
    pub from: Option<String>,
    pub to: Option<String>,
    pub all: bool,
}

impl DateOptions {
    /// Resolve human-oriented date options against an explicit local calendar date.
    ///
    /// # Errors
    ///
    /// Fails unless exactly one valid selection is present.
    pub fn resolve(&self, today: NaiveDate) -> Result<DateSelection, OperationInputError> {
        if self.from.is_some() != self.to.is_some() {
            return Err(OperationInputError::invalid(
                "--from and --to must be provided together",
            ));
        }
        let selected_ranges = usize::from(self.all)
            + usize::from(self.yesterday)
            + usize::from(self.last.is_some())
            + usize::from(self.from.is_some());
        if selected_ranges != 1 {
            return Err(OperationInputError::invalid(
                "choose exactly one date range: --yesterday, --last, --from/--to, or --all",
            ));
        }
        if self.all {
            return Ok(DateSelection::AllAvailable(
                healthmd_protocol::wire::Empty {},
            ));
        }
        let (start, end) = if self.yesterday {
            let yesterday = today
                .checked_sub_signed(ChronoDuration::days(1))
                .ok_or_else(|| {
                    OperationInputError::invalid("date range is outside the supported calendar")
                })?;
            (yesterday, yesterday)
        } else if let Some(days) = self.last {
            if days == 0 {
                return Err(OperationInputError::invalid(
                    "--last must be greater than zero",
                ));
            }
            let start = today
                .checked_sub_signed(ChronoDuration::days(i64::from(days)))
                .ok_or_else(|| {
                    OperationInputError::invalid("--last is outside the supported calendar")
                })?;
            let end = today
                .checked_sub_signed(ChronoDuration::days(1))
                .ok_or_else(|| {
                    OperationInputError::invalid("date range is outside the supported calendar")
                })?;
            (start, end)
        } else if let (Some(start), Some(end)) = (&self.from, &self.to) {
            let start = parse_date(start, "--from must be YYYY-MM-DD")?;
            let end = parse_date(end, "--to must be YYYY-MM-DD")?;
            if start > end {
                return Err(OperationInputError::invalid(
                    "--from must not be after --to",
                ));
            }
            (start, end)
        } else {
            return Err(OperationInputError::invalid(
                "choose one date range: --yesterday, --last, --from/--to, or --all",
            ));
        };
        Ok(exact_date_selection(start, end))
    }

    pub fn exact(start: String, end: String) -> Self {
        Self {
            from: Some(start),
            to: Some(end),
            ..Self::default()
        }
    }

    pub const fn all_available() -> Self {
        Self {
            yesterday: false,
            last: None,
            from: None,
            to: None,
            all: true,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum SelectionDetail {
    #[default]
    Summary,
    Lossless,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct SelectionOptions {
    pub metric_ids: Vec<String>,
    pub categories: Vec<String>,
    pub all_metrics: bool,
    pub detail: SelectionDetail,
    pub object_paths: Vec<String>,
    pub field_pointers: Vec<String>,
    pub source_ids: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExtractSelection {
    pub selection: CanonicalSelection,
    pub projection_pointers: Vec<String>,
}

impl SelectionOptions {
    /// Normalize generated-file selection and saved-settings policy.
    ///
    /// # Errors
    ///
    /// Fails for ambiguous selectors or unsupported generated-file sources.
    pub fn generated_files(
        &self,
        use_device_settings: bool,
    ) -> Result<Option<CanonicalSelection>, OperationInputError> {
        if !self.object_paths.is_empty() || !self.field_pointers.is_empty() {
            return Err(OperationInputError::invalid(
                "--object and --field are available only with extract",
            ));
        }
        let metrics = sorted_unique(&self.metric_ids);
        let categories = sorted_unique(&self.categories);
        if self.all_metrics && (!metrics.is_empty() || !categories.is_empty()) {
            return Err(OperationInputError::invalid(
                "--all-metrics cannot be combined with --metric or --category",
            ));
        }
        let selection_requested = self.all_metrics
            || !metrics.is_empty()
            || !categories.is_empty()
            || !self.source_ids.is_empty();
        if use_device_settings && selection_requested {
            return Err(OperationInputError::invalid(
                "request-scoped selection cannot use --use-device-settings",
            ));
        }
        let sources = apple_sources(&self.source_ids, "generated-file selection")?;
        Ok(selection_requested.then_some(CanonicalSelection {
            metric_ids: metrics,
            categories,
            source_ids: sources,
            object_paths: Vec::new(),
            field_pointers: Vec::new(),
            all_metrics: self.all_metrics,
            detail_level: self.detail.into(),
        }))
    }

    /// Normalize canonical extraction selectors and projection pointers.
    ///
    /// # Errors
    ///
    /// Fails for unknown object aliases, malformed JSON Pointers, or an empty/ambiguous selection.
    pub fn extract(&self) -> Result<ExtractSelection, OperationInputError> {
        let mut categories = self.categories.clone();
        let mut object_paths = Vec::new();
        let mut requires_lossless = self.detail == SelectionDetail::Lossless;
        for object in &self.object_paths {
            let resolved = canonical_object_path(object)?;
            object_paths.push(resolved.0);
            if let Some(category) = resolved.1 {
                categories.push(category);
            }
            requires_lossless |= resolved.2;
        }
        for pointer in &self.field_pointers {
            validate_canonical_pointer(pointer)?;
            requires_lossless |= pointer.starts_with("/healthkit_record_archive");
        }
        let metrics = sorted_unique(&self.metric_ids);
        let categories = sorted_unique(&categories);
        let object_paths = sorted_unique(&object_paths);
        let fields = sorted_unique(&self.field_pointers);
        if self.all_metrics && (!metrics.is_empty() || !categories.is_empty()) {
            return Err(OperationInputError::invalid(
                "--all-metrics cannot be combined with --metric or --category",
            ));
        }
        if !self.all_metrics && metrics.is_empty() && categories.is_empty() {
            return Err(OperationInputError::invalid(
                "extract requires --metric, --category, a category object, or --all-metrics",
            ));
        }
        let sources = apple_sources(&self.source_ids, "canonical extraction")?;
        let mut projection_pointers = object_paths.clone();
        projection_pointers.extend(fields.clone());
        projection_pointers.sort();
        projection_pointers.dedup();
        Ok(ExtractSelection {
            selection: CanonicalSelection {
                metric_ids: metrics,
                categories,
                source_ids: sources,
                object_paths,
                field_pointers: fields,
                all_metrics: self.all_metrics,
                detail_level: if requires_lossless {
                    DetailLevel::Lossless
                } else {
                    DetailLevel::Summary
                },
            },
            projection_pointers,
        })
    }
}

impl From<SelectionDetail> for DetailLevel {
    fn from(value: SelectionDetail) -> Self {
        match value {
            SelectionDetail::Summary => Self::Summary,
            SelectionDetail::Lossless => Self::Lossless,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GeneratedFileExportInput {
    pub dates: DateOptions,
    pub selection: SelectionOptions,
    pub use_device_settings: bool,
    pub destination: String,
    pub timeout: Duration,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GeneratedFileExportInvocation {
    pub request: ExportRequest,
    pub timeout: Duration,
}

impl GeneratedFileExportInput {
    /// Build the exact direct-protocol request used by both CLI and MCP adapters.
    ///
    /// # Errors
    ///
    /// Fails when dates, selection, timeout, or destination are invalid.
    pub fn build(
        &self,
        job_id: Uuid,
        created_at: DateTime<Utc>,
        today: NaiveDate,
    ) -> Result<GeneratedFileExportInvocation, OperationInputError> {
        if !(Duration::from_secs(MINIMUM_EXPORT_TIMEOUT_SECONDS)
            ..=Duration::from_secs(MAXIMUM_EXPORT_TIMEOUT_SECONDS))
            .contains(&self.timeout)
        {
            return Err(OperationInputError::invalid(
                "export timeout must be between 5 and 900 seconds",
            ));
        }
        if self.destination.is_empty() || !Path::new(&self.destination).is_absolute() {
            return Err(OperationInputError::invalid(
                "destination must be an existing absolute directory",
            ));
        }
        Ok(GeneratedFileExportInvocation {
            request: ExportRequest {
                protocol_version: 1,
                job_id: SwiftUuid(job_id),
                created_at,
                date_selection: self.dates.resolve(today)?,
                settings_policy: if self.use_device_settings {
                    SettingsPolicy::CurrentIphoneSettings
                } else {
                    SettingsPolicy::RequestedDatesOnly
                },
                response_mode: ResponseMode::WriteFiles,
                raw_profile: None,
                canonical_selection: self.selection.generated_files(self.use_device_settings)?,
                destination: Some(ExportDestination {
                    root_path: self.destination.clone(),
                }),
            },
            timeout: self.timeout,
        })
    }
}

/// Parse and normalize the structured generated-file operation used by MCP.
///
/// # Errors
///
/// Fails closed for unknown keys, malformed dates, unsafe destinations, or invalid selectors.
#[allow(clippy::too_many_lines)]
pub fn generated_file_export_from_value(
    arguments: &Value,
    job_id: Uuid,
    created_at: DateTime<Utc>,
    today: NaiveDate,
) -> Result<GeneratedFileExportInvocation, OperationInputError> {
    let arguments = arguments
        .as_object()
        .ok_or_else(|| OperationInputError::invalid("arguments must be an object"))?;
    ensure_keys(
        arguments,
        &[
            "date_selection",
            "date_range",
            "settings_policy",
            "metric_ids",
            "categories",
            "all_metrics",
            "detail_level",
            "wait_timeout_seconds",
            "destination",
        ],
    )?;
    let destination = arguments
        .get("destination")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| OperationInputError::invalid("destination is required"))?;
    let destination = canonical_destination(destination)?;
    let dates = match arguments.get("date_selection").and_then(Value::as_str) {
        Some("all_available") if !arguments.contains_key("date_range") => {
            DateOptions::all_available()
        }
        Some("explicit_range") => {
            let range = arguments
                .get("date_range")
                .and_then(Value::as_object)
                .ok_or_else(|| OperationInputError::invalid("date_range is required"))?;
            ensure_keys(range, &["start", "end"])?;
            DateOptions::exact(
                required_string(range, "start")?.to_owned(),
                required_string(range, "end")?.to_owned(),
            )
        }
        _ => {
            return Err(OperationInputError::invalid("invalid date_selection"));
        }
    };
    let use_device_settings = match arguments
        .get("settings_policy")
        .and_then(Value::as_str)
        .unwrap_or("requested_dates_only")
    {
        "requested_dates_only" => false,
        "current_iphone_settings" => true,
        _ => return Err(OperationInputError::invalid("invalid settings_policy")),
    };
    let timeout_seconds = arguments
        .get("wait_timeout_seconds")
        .map(number)
        .transpose()?
        .unwrap_or_else(|| Duration::from_secs(DEFAULT_EXPORT_TIMEOUT_SECONDS).as_secs_f64());
    if !timeout_seconds.is_finite() || timeout_seconds <= 0.0 {
        return Err(OperationInputError::invalid("invalid wait_timeout_seconds"));
    }
    let timeout = Duration::from_secs_f64(timeout_seconds);
    if !(Duration::from_secs(MINIMUM_EXPORT_TIMEOUT_SECONDS)
        ..=Duration::from_secs(MAXIMUM_EXPORT_TIMEOUT_SECONDS))
        .contains(&timeout)
    {
        return Err(OperationInputError::invalid("invalid wait_timeout_seconds"));
    }
    let has_selection = ["metric_ids", "categories", "all_metrics", "detail_level"]
        .iter()
        .any(|key| arguments.contains_key(*key));
    let selection = SelectionOptions {
        metric_ids: string_array(arguments, "metric_ids", MAXIMUM_METRIC_IDS)?,
        categories: string_array(arguments, "categories", MAXIMUM_CATEGORIES)?,
        all_metrics: optional_bool(arguments, "all_metrics")?.unwrap_or(false),
        detail: match arguments
            .get("detail_level")
            .and_then(Value::as_str)
            .unwrap_or("summary")
        {
            "summary" => SelectionDetail::Summary,
            "lossless" => SelectionDetail::Lossless,
            _ => return Err(OperationInputError::invalid("invalid detail_level")),
        },
        ..SelectionOptions::default()
    };
    if has_selection
        && !selection.all_metrics
        && selection.metric_ids.is_empty()
        && selection.categories.is_empty()
    {
        return Err(OperationInputError::invalid("invalid metric selection"));
    }
    if has_selection && use_device_settings {
        return Err(OperationInputError::invalid(
            "selection requires requested_dates_only",
        ));
    }
    GeneratedFileExportInput {
        dates,
        selection,
        use_device_settings,
        destination,
        timeout,
    }
    .build(job_id, created_at, today)
}

/// Resolve an existing absolute non-symlink directory to its canonical UTF-8 path.
///
/// # Errors
///
/// Fails when the path is missing, relative, a symlink, not a directory, or not UTF-8.
pub fn canonical_destination(destination: &str) -> Result<String, OperationInputError> {
    let path = Path::new(destination);
    let metadata = fs::symlink_metadata(path)
        .map_err(|_| OperationInputError::invalid("invalid destination"))?;
    if !path.is_absolute() || metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(OperationInputError::invalid("invalid destination"));
    }
    fs::canonicalize(path)
        .map_err(|_| OperationInputError::invalid("invalid destination"))?
        .to_str()
        .map(str::to_owned)
        .ok_or_else(|| OperationInputError::invalid("invalid destination"))
}

/// Resolve a supported extraction alias or validate an explicit JSON Pointer.
///
/// # Errors
///
/// Fails for unknown aliases or malformed pointers.
pub fn canonical_object_path(
    value: &str,
) -> Result<(String, Option<String>, bool), OperationInputError> {
    if value.starts_with('/') {
        validate_canonical_pointer(value)?;
        return Ok((
            value.to_owned(),
            None,
            value.starts_with("/healthkit_record_archive"),
        ));
    }
    let normalized = value.to_lowercase().replace('_', "-");
    let top_level = match normalized.as_str() {
        "sleep" => Some(("/sleep", "Sleep")),
        "activity" => Some(("/activity", "Activity")),
        "heart" => Some(("/heart", "Heart")),
        "vitals" => Some(("/vitals", "Vitals")),
        "body" => Some(("/body", "Body Measurements")),
        "nutrition" => Some(("/nutrition", "Nutrition")),
        "mindfulness" => Some(("/mindfulness", "Mindfulness")),
        "mobility" => Some(("/mobility", "Mobility")),
        "hearing" => Some(("/hearing", "Hearing")),
        "reproductive-health" => Some(("/reproductiveHealth", "Reproductive Health")),
        "cycling" => Some(("/cyclingPerformance", "Cycling")),
        "vitamins" => Some(("/vitamins", "Vitamins")),
        "minerals" => Some(("/minerals", "Minerals")),
        "symptoms" => Some(("/symptoms", "Symptoms")),
        "medications" => Some(("/medications", "Medications")),
        "other" => Some(("/other", "Other")),
        "workouts" => Some(("/workouts", "Workouts")),
        _ => None,
    };
    if let Some((path, category)) = top_level {
        return Ok((path.to_owned(), Some(category.to_owned()), false));
    }
    let archive = match normalized.as_str() {
        "archive" => Some("/healthkit_record_archive"),
        "records" => Some("/healthkit_record_archive/records"),
        "external-records" => Some("/healthkit_record_archive/external_records"),
        "query-results" => Some("/healthkit_record_archive/query_manifest/results"),
        "warnings" => Some("/healthkit_record_archive/integrity_warnings"),
        _ => None,
    };
    archive.map_or_else(
        || {
            Err(OperationInputError::invalid(
                "unknown canonical object or JSON Pointer",
            ))
        },
        |path| Ok((path.to_owned(), None, true)),
    )
}

/// Validate the bounded RFC 6901 pointer subset accepted by canonical extraction.
///
/// # Errors
///
/// Fails for relative, oversized, control-character, or malformed-escape pointers.
pub fn validate_canonical_pointer(pointer: &str) -> Result<(), OperationInputError> {
    if pointer.is_empty()
        || !pointer.starts_with('/')
        || pointer.len() > 1_024
        || pointer.bytes().any(|byte| byte.is_ascii_control())
    {
        return Err(OperationInputError::invalid(
            "canonical JSON Pointer must begin with / and contain no control characters",
        ));
    }
    let mut bytes = pointer.bytes();
    while let Some(byte) = bytes.next() {
        if byte == b'~' && !matches!(bytes.next(), Some(b'0' | b'1')) {
            return Err(OperationInputError::invalid(
                "canonical JSON Pointer contains an invalid ~ escape",
            ));
        }
    }
    Ok(())
}

fn exact_date_selection(start: NaiveDate, end: NaiveDate) -> DateSelection {
    DateSelection::Exact(ExactDateSelection {
        start: start.format("%Y-%m-%d").to_string(),
        end: end.format("%Y-%m-%d").to_string(),
    })
}

fn parse_date(value: &str, message: &'static str) -> Result<NaiveDate, OperationInputError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| OperationInputError::invalid(message))
}

fn sorted_unique(values: &[String]) -> Vec<String> {
    values
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn apple_sources(
    values: &[String],
    operation: &'static str,
) -> Result<Vec<String>, OperationInputError> {
    if values.is_empty() {
        return Ok(vec!["apple_health".to_owned()]);
    }
    let sources = sorted_unique(values);
    if sources.len() != 1 || sources[0] != "apple_health" {
        return Err(OperationInputError::invalid(match operation {
            "generated-file selection" => {
                "generated-file selection currently supports only --source apple_health"
            }
            _ => "canonical extraction currently supports only --source apple_health",
        }));
    }
    Ok(sources)
}

fn ensure_keys(object: &Map<String, Value>, allowed: &[&str]) -> Result<(), OperationInputError> {
    if object.keys().all(|key| allowed.contains(&key.as_str())) {
        Ok(())
    } else {
        Err(OperationInputError::invalid("unknown argument"))
    }
}

fn required_string<'a>(
    object: &'a Map<String, Value>,
    key: &str,
) -> Result<&'a str, OperationInputError> {
    object
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| OperationInputError::invalid("expected string"))
}

fn string_array(
    object: &Map<String, Value>,
    key: &str,
    maximum: usize,
) -> Result<Vec<String>, OperationInputError> {
    let Some(value) = object.get(key) else {
        return Ok(Vec::new());
    };
    let values = value
        .as_array()
        .ok_or_else(|| OperationInputError::invalid("expected string array"))?;
    if values.len() > maximum {
        return Err(OperationInputError::invalid("too many values"));
    }
    let mut unique = BTreeSet::new();
    for value in values {
        let value = value
            .as_str()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| OperationInputError::invalid("invalid string"))?;
        if !unique.insert(value.to_owned()) {
            return Err(OperationInputError::invalid("duplicate value"));
        }
    }
    Ok(unique.into_iter().collect())
}

fn optional_bool(
    object: &Map<String, Value>,
    key: &str,
) -> Result<Option<bool>, OperationInputError> {
    object
        .get(key)
        .map(|value| {
            value
                .as_bool()
                .ok_or_else(|| OperationInputError::invalid("expected boolean"))
        })
        .transpose()
}

fn number(value: &Value) -> Result<f64, OperationInputError> {
    value
        .as_f64()
        .ok_or_else(|| OperationInputError::invalid("expected number"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn date_options_are_exclusive_and_deterministic() {
        let today = NaiveDate::from_ymd_opt(2026, 8, 1).unwrap();
        assert_eq!(
            DateOptions {
                last: Some(7),
                ..DateOptions::default()
            }
            .resolve(today)
            .unwrap(),
            DateSelection::Exact(ExactDateSelection {
                start: "2026-07-25".to_owned(),
                end: "2026-07-31".to_owned(),
            })
        );
        assert!(
            DateOptions {
                yesterday: true,
                all: true,
                ..DateOptions::default()
            }
            .resolve(today)
            .is_err()
        );
    }

    #[test]
    fn generated_and_extract_selection_share_canonical_rules() {
        let selection = SelectionOptions {
            metric_ids: vec!["sleep_total".to_owned(), "sleep_total".to_owned()],
            source_ids: vec!["apple_health".to_owned()],
            ..SelectionOptions::default()
        };
        assert_eq!(
            selection
                .generated_files(false)
                .unwrap()
                .unwrap()
                .metric_ids,
            vec!["sleep_total"]
        );
        assert_eq!(
            selection.extract().unwrap().selection.metric_ids,
            vec!["sleep_total"]
        );
    }

    #[test]
    fn pointer_validation_rejects_ambiguous_escapes() {
        assert!(validate_canonical_pointer("/sleep/~0valid").is_ok());
        assert!(validate_canonical_pointer("/sleep/~2invalid").is_err());
    }

    #[test]
    fn typed_cli_and_structured_mcp_export_inputs_normalize_identically() {
        let destination = tempfile::tempdir().unwrap();
        let destination = destination.path().canonicalize().unwrap();
        let destination_text = destination.to_string_lossy().into_owned();
        let job_id = Uuid::new_v4();
        let created_at = Utc::now();
        let today = NaiveDate::from_ymd_opt(2026, 8, 1).unwrap();
        let cli = GeneratedFileExportInput {
            dates: DateOptions::exact("2026-07-01".to_owned(), "2026-07-31".to_owned()),
            selection: SelectionOptions {
                metric_ids: vec!["sleep_total".to_owned()],
                detail: SelectionDetail::Lossless,
                ..SelectionOptions::default()
            },
            use_device_settings: false,
            destination: destination_text.clone(),
            timeout: Duration::from_secs(300),
        }
        .build(job_id, created_at, today)
        .unwrap();
        let mcp = generated_file_export_from_value(
            &serde_json::json!({
                "date_selection": "explicit_range",
                "date_range": {"start": "2026-07-01", "end": "2026-07-31"},
                "destination": destination_text,
                "metric_ids": ["sleep_total"],
                "detail_level": "lossless"
            }),
            job_id,
            created_at,
            today,
        )
        .unwrap();
        assert_eq!(cli, mcp);
    }

    #[test]
    fn structured_export_parser_preserves_scope_and_rejects_unsafe_paths() {
        let destination = tempfile::tempdir().unwrap();
        let invocation = generated_file_export_from_value(
            &serde_json::json!({
                "date_selection": "all_available",
                "destination": destination.path(),
                "all_metrics": true,
                "detail_level": "lossless"
            }),
            Uuid::nil(),
            Utc::now(),
            NaiveDate::from_ymd_opt(2026, 8, 1).unwrap(),
        )
        .unwrap();
        assert!(matches!(
            invocation.request.date_selection,
            DateSelection::AllAvailable(_)
        ));
        assert_eq!(
            invocation.request.destination.unwrap().root_path,
            destination.path().canonicalize().unwrap().to_string_lossy()
        );
        assert_eq!(
            invocation.request.canonical_selection.unwrap().detail_level,
            DetailLevel::Lossless
        );
        assert!(
            generated_file_export_from_value(
                &serde_json::json!({
                    "date_selection": "all_available",
                    "destination": "relative",
                    "all_metrics": true
                }),
                Uuid::nil(),
                Utc::now(),
                NaiveDate::from_ymd_opt(2026, 8, 1).unwrap(),
            )
            .is_err()
        );

        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            let root = tempfile::tempdir().unwrap();
            let destination = root.path().join("destination");
            fs::create_dir(&destination).unwrap();
            let link = root.path().join("link");
            symlink(&destination, &link).unwrap();
            assert!(
                generated_file_export_from_value(
                    &serde_json::json!({
                        "date_selection": "all_available",
                        "destination": link,
                        "all_metrics": true
                    }),
                    Uuid::nil(),
                    Utc::now(),
                    NaiveDate::from_ymd_opt(2026, 8, 1).unwrap(),
                )
                .is_err()
            );
        }
    }
}
