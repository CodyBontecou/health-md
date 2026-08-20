//! Canonical, platform-neutral metric/profile registry.

use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{CoreError, REGISTRY_SHA256, REGISTRY_VERSION};

const REGISTRY_BYTES: &[u8] = include_bytes!("../registry/metric-registry-v1.json");

/// Closed set of shipped output profiles represented by registry metadata.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MetricRegistryProfile {
    /// Apple `healthmd.health_data` v8.
    AppleHealthDataV8,
    /// Android byte-frozen iOS-compatible v4.
    AndroidFrozenV4,
    /// Android additive analytical v5.
    AndroidAnalyticalV5,
}

impl MetricRegistryProfile {
    /// Stable internal profile identifier.
    #[must_use]
    pub const fn id(self) -> &'static str {
        match self {
            Self::AppleHealthDataV8 => "apple_health_data_v8",
            Self::AndroidFrozenV4 => "android_frozen_v4",
            Self::AndroidAnalyticalV5 => "android_analytical_v5",
        }
    }
}

/// One ordered native category in a profile snapshot.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RegistryCategory {
    /// Persisted native category identity.
    pub category_id: String,
    /// Stable key resolved by native localization code.
    pub label_key: String,
    /// Zero-based profile order.
    pub ordinal: u32,
}

/// One ordered selectable metric projected for a native platform.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RegistryMetric {
    /// Cross-platform semantic identity. Never persisted by native applications.
    pub semantic_id: String,
    /// Existing platform selection identity. This remains the persistence/public boundary.
    pub selection_id: String,
    /// Stable key resolved by native localization code.
    pub label_key: String,
    /// Invariant English reference label for contract documentation.
    pub reference_name: String,
    /// Existing native category identity.
    pub category_id: String,
    /// Existing selection/source unit label.
    pub unit: String,
    /// Stable source kind (`quantity`, `category`, `workout`, or Android summary kind).
    pub kind: String,
    /// Source aggregation metadata; execution remains native until M4.
    pub source_aggregation: String,
    /// Existing definition-level default flag.
    pub default_enabled: bool,
    /// True when the source is represented only in Apple's lossless archive.
    pub archive_only: bool,
    /// Opaque native capability/OS-availability key.
    pub availability_key: String,
    /// Opaque native authorization-flow key.
    pub authorization_key: String,
    /// Product capability manifest identity.
    pub capability_id: String,
    /// Opaque platform selector identity; native code resolves SDK types.
    pub source_selector: String,
    /// Explicit related semantic identities for aliases/non-equivalent projections.
    pub related_semantic_ids: Vec<String>,
    /// Zero-based profile order.
    pub ordinal: u32,
}

/// One native unavailable/stale selection identity.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RegistryUnavailableMetric {
    /// Existing native selection identity.
    pub selection_id: String,
    /// Existing native category identity.
    pub category_id: String,
    /// Stable native localization key.
    pub label_key: String,
    /// Stable native reason-localization key.
    pub reason_key: String,
}

/// One metadata-only public output projection.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RegistryOutput {
    /// Selection identities that authorize/populate this projection.
    pub selection_ids: Vec<String>,
    /// Output surface identity such as `flat`.
    pub surface: String,
    /// Exact existing output key/path.
    pub key: String,
    /// Exact contract unit, when the current profile declares one.
    pub unit: String,
    /// Existing daily aggregation rule, when declared.
    pub daily_aggregation: String,
    /// Existing roll-up rule, when declared.
    pub rollup: String,
    /// `none` or a stable compatibility alias classification.
    pub alias_kind: String,
    /// True only for an explicitly Android-native field.
    pub platform_native: bool,
    /// Stable opt-in/default condition.
    pub condition: String,
    /// Whether this output is active in the profile's default settings.
    pub enabled_by_default: bool,
    /// Zero-based declaration order within the profile.
    pub ordinal: u32,
}

/// Immutable coarse registry result intended for one native cache fill.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct MetricRegistrySnapshot {
    /// Internal registry contract version.
    pub registry_version: u32,
    /// SHA-256 of the exact embedded canonical registry bytes.
    pub registry_sha256: String,
    /// Stable internal profile identity.
    pub profile_id: String,
    /// Existing product capability-manifest profile identity.
    pub public_profile_id: String,
    /// Existing public schema identity.
    pub public_schema: String,
    /// Existing public schema version.
    pub public_schema_version: u32,
    /// Internal revision of profile metadata.
    pub profile_revision: u32,
    /// Ordered native categories.
    pub categories: Vec<RegistryCategory>,
    /// Ordered selectable native metrics.
    pub metrics: Vec<RegistryMetric>,
    /// Ordered native unavailable/stale metric identities.
    pub unavailable_metrics: Vec<RegistryUnavailableMetric>,
    /// Ordered metadata-only output projections.
    pub outputs: Vec<RegistryOutput>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct RegistryDocument {
    schema: String,
    schema_version: u32,
    registry_version: u32,
    known_capability_ids: Vec<String>,
    available_capability_ids_by_platform: AvailableCapabilities,
    categories: Vec<CategoryRow>,
    metrics: Vec<MetricRow>,
    profiles: Vec<ProfileRow>,
    legacy_unavailable: LegacyUnavailable,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct AvailableCapabilities {
    apple: Vec<String>,
    android: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct CategoryRow {
    platform: String,
    category_id: String,
    label_key: String,
    ordinal: u32,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct MetricRow {
    semantic_id: String,
    reference_name: String,
    capability_id: String,
    equivalence: String,
    apple: PlatformBinding,
    android: PlatformBinding,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PlatformBinding {
    status: String,
    #[serde(default)]
    ordinal: Option<u32>,
    #[serde(default)]
    selection_id: Option<String>,
    #[serde(default)]
    label_key: Option<String>,
    #[serde(default)]
    reference_name: Option<String>,
    #[serde(default)]
    category_id: Option<String>,
    #[serde(default)]
    unit: Option<String>,
    #[serde(default)]
    kind: Option<String>,
    #[serde(default)]
    source_aggregation: Option<String>,
    #[serde(default)]
    archive_only: Option<bool>,
    #[serde(default)]
    default_enabled: Option<bool>,
    #[serde(default)]
    availability_key: Option<String>,
    #[serde(default)]
    source_selector: Option<String>,
    #[serde(default)]
    authorization_key: Option<String>,
    #[serde(default)]
    outputs: Vec<AppleOutputRow>,
    #[serde(default)]
    related_semantic_ids: Vec<String>,
    #[serde(default)]
    reason_key: Option<String>,
    #[serde(default)]
    picker_visibility: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct AppleOutputRow {
    key: String,
    unit: String,
    daily_aggregation: String,
    rollup: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ProfileRow {
    id: String,
    public_profile_id: String,
    public_schema: String,
    public_schema_version: u32,
    profile_revision: u32,
    platform: String,
    ordered_selection_ids: Vec<String>,
    outputs: Vec<ProfileOutputRow>,
    unavailable_selection_ids: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ProfileOutputRow {
    #[serde(default)]
    selection_id: Option<String>,
    #[serde(default)]
    selection_ids: Vec<String>,
    surface: String,
    key: String,
    #[serde(default)]
    unit: String,
    #[serde(default)]
    daily_aggregation: String,
    #[serde(default)]
    rollup: String,
    #[serde(default = "none_alias")]
    alias_kind: String,
    #[serde(default)]
    platform_native: bool,
    #[serde(default = "default_condition")]
    condition: String,
    #[serde(default = "default_true")]
    enabled_by_default: bool,
}

fn none_alias() -> String {
    "none".to_owned()
}
fn default_condition() -> String {
    "default".to_owned()
}
const fn default_true() -> bool {
    true
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct LegacyUnavailable {
    android: Vec<UnavailableRow>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct UnavailableRow {
    selection_id: String,
    label_key: String,
    category_id: String,
    reference_name: String,
    reason: String,
    reason_key: String,
}

static REGISTRY: OnceLock<Result<RegistryDocument, CoreError>> = OnceLock::new();

/// Load, validate, and project one complete registry profile.
///
/// # Errors
///
/// Returns a stable health-free error when the expected version/profile is unsupported or the
/// embedded registry violates its canonical hash/schema/invariants.
pub fn metric_registry_snapshot(
    profile: MetricRegistryProfile,
    expected_registry_version: u32,
) -> Result<MetricRegistrySnapshot, CoreError> {
    if expected_registry_version != REGISTRY_VERSION {
        return Err(CoreError::UnsupportedRegistryVersion);
    }
    let document = REGISTRY
        .get_or_init(|| decode_and_validate(REGISTRY_BYTES, true))
        .as_ref()
        .map_err(|error| *error)?;
    project_snapshot(document, profile)
}

/// Validate exact embedded registry bytes and return deterministic inventory counts.
///
/// # Errors
///
/// Returns [`CoreError::InvalidRegistry`] when any registry invariant fails.
pub fn validate_embedded_registry() -> Result<(u32, u32, u32), CoreError> {
    let document = REGISTRY
        .get_or_init(|| decode_and_validate(REGISTRY_BYTES, true))
        .as_ref()
        .map_err(|error| *error)?;
    let apple = document
        .metrics
        .iter()
        .filter(|metric| metric.apple.status == "backed")
        .count();
    let android = document
        .metrics
        .iter()
        .filter(|metric| metric.android.status == "backed")
        .count();
    Ok((
        u32::try_from(apple).map_err(|_| CoreError::InvalidRegistry)?,
        u32::try_from(android).map_err(|_| CoreError::InvalidRegistry)?,
        u32::try_from(document.profiles.len()).map_err(|_| CoreError::InvalidRegistry)?,
    ))
}

fn decode_and_validate(bytes: &[u8], enforce_hash: bool) -> Result<RegistryDocument, CoreError> {
    if enforce_hash && format!("{:x}", Sha256::digest(bytes)) != REGISTRY_SHA256 {
        return Err(CoreError::InvalidRegistry);
    }
    let value: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| CoreError::InvalidRegistry)?;
    let mut canonical =
        serde_json::to_vec_pretty(&value).map_err(|_| CoreError::InvalidRegistry)?;
    canonical.push(b'\n');
    if canonical != bytes {
        return Err(CoreError::InvalidRegistry);
    }
    let document: RegistryDocument =
        serde_json::from_value(value).map_err(|_| CoreError::InvalidRegistry)?;
    validate_document(&document)?;
    Ok(document)
}

fn validate_document(document: &RegistryDocument) -> Result<(), CoreError> {
    if document.schema != "healthmd.metric_registry"
        || document.schema_version != 1
        || document.registry_version != REGISTRY_VERSION
        || document.profiles.len() != 3
        || document.known_capability_ids.is_empty()
    {
        return Err(CoreError::InvalidRegistry);
    }

    let capabilities: HashSet<&str> = unique_nonempty(&document.known_capability_ids)?;
    let semantic_id_values = document
        .metrics
        .iter()
        .map(|metric| metric.semantic_id.clone())
        .collect::<Vec<_>>();
    let semantic_ids: HashSet<&str> = unique_nonempty(&semantic_id_values)?;
    if document
        .metrics
        .iter()
        .any(|metric| !capabilities.contains(metric.capability_id.as_str()))
    {
        return Err(CoreError::InvalidRegistry);
    }
    let apple_capabilities = unique_nonempty(&document.available_capability_ids_by_platform.apple)?;
    let android_capabilities =
        unique_nonempty(&document.available_capability_ids_by_platform.android)?;
    if apple_capabilities
        .iter()
        .any(|id| !capabilities.contains(id))
        || android_capabilities
            .iter()
            .any(|id| !capabilities.contains(id))
        || document.metrics.iter().any(|metric| {
            (metric.apple.status == "backed"
                && !apple_capabilities.contains(metric.capability_id.as_str()))
                || (metric.android.status == "backed"
                    && !android_capabilities.contains(metric.capability_id.as_str()))
        })
    {
        return Err(CoreError::InvalidRegistry);
    }

    validate_categories(&document.categories)?;
    let apple = validate_platform(document, "apple", |metric| &metric.apple, &semantic_ids)?;
    let android = validate_platform(document, "android", |metric| &metric.android, &semantic_ids)?;
    if apple.len() != 230 || android.len() != 106 {
        return Err(CoreError::InvalidRegistry);
    }

    let profile_id_values = document
        .profiles
        .iter()
        .map(|profile| profile.id.clone())
        .collect::<Vec<_>>();
    let profile_ids: HashSet<&str> = unique_nonempty(&profile_id_values)?;
    if profile_ids
        != HashSet::from([
            "apple_health_data_v8",
            "android_frozen_v4",
            "android_analytical_v5",
        ])
    {
        return Err(CoreError::InvalidRegistry);
    }
    for profile in &document.profiles {
        let selections = if profile.platform == "apple" {
            &apple
        } else if profile.platform == "android" {
            &android
        } else {
            return Err(CoreError::InvalidRegistry);
        };
        validate_profile(profile, selections)?;
    }

    let unavailable_id_values = document
        .legacy_unavailable
        .android
        .iter()
        .map(|metric| metric.selection_id.clone())
        .collect::<Vec<_>>();
    let unavailable_ids: HashSet<&str> = unique_nonempty(&unavailable_id_values)?;
    if unavailable_ids.len() != 102
        || unavailable_ids
            .iter()
            .any(|metric_id| android.contains_key(metric_id))
        || document.legacy_unavailable.android.iter().any(|metric| {
            metric.label_key.is_empty()
                || metric.category_id.is_empty()
                || metric.reference_name.is_empty()
                || metric.reason.is_empty()
                || metric.reason_key.is_empty()
        })
    {
        return Err(CoreError::InvalidRegistry);
    }
    Ok(())
}

fn unique_nonempty(values: &[String]) -> Result<HashSet<&str>, CoreError> {
    let mut result = HashSet::with_capacity(values.len());
    for value in values {
        if value.is_empty() || !result.insert(value.as_str()) {
            return Err(CoreError::InvalidRegistry);
        }
    }
    Ok(result)
}

fn validate_categories(categories: &[CategoryRow]) -> Result<(), CoreError> {
    let mut seen = HashSet::new();
    let mut next = HashMap::<&str, u32>::new();
    for category in categories {
        if category.category_id.is_empty()
            || category.label_key.is_empty()
            || !matches!(category.platform.as_str(), "apple" | "android")
            || !seen.insert((category.platform.as_str(), category.category_id.as_str()))
            || category.ordinal != *next.entry(category.platform.as_str()).or_default()
        {
            return Err(CoreError::InvalidRegistry);
        }
        *next.entry(category.platform.as_str()).or_default() += 1;
    }
    if next.get("apple") != Some(&21) || next.get("android") != Some(&12) {
        return Err(CoreError::InvalidRegistry);
    }
    Ok(())
}

fn validate_platform<'a, F>(
    document: &'a RegistryDocument,
    platform: &str,
    binding: F,
    semantic_ids: &HashSet<&str>,
) -> Result<HashMap<&'a str, &'a MetricRow>, CoreError>
where
    F: Fn(&'a MetricRow) -> &'a PlatformBinding,
{
    let mut selections = HashMap::new();
    let mut ordinals = HashSet::new();
    for metric in &document.metrics {
        let value = binding(metric);
        if !matches!(value.status.as_str(), "backed" | "unavailable") {
            return Err(CoreError::InvalidRegistry);
        }
        if value.status == "unavailable" {
            if value.selection_id.is_some()
                || value.ordinal.is_some()
                || !matches!(
                    value.picker_visibility.as_deref(),
                    Some("hidden" | "listed")
                )
                || value.reason_key.as_deref().is_none_or(str::is_empty)
            {
                return Err(CoreError::InvalidRegistry);
            }
            continue;
        }
        let selection_id = required(value.selection_id.as_deref())?;
        let ordinal = value.ordinal.ok_or(CoreError::InvalidRegistry)?;
        let aggregation = required(value.source_aggregation.as_deref())?;
        let valid_aggregation = if platform == "apple" {
            matches!(
                aggregation,
                "cumulative"
                    | "discreteAvg"
                    | "discreteMin"
                    | "discreteMax"
                    | "mostRecent"
                    | "duration"
                    | "count"
            )
        } else {
            matches!(
                aggregation,
                "sum" | "average" | "minimum" | "maximum" | "latest" | "record_projection"
            )
        };
        if selections.insert(selection_id, metric).is_some()
            || !ordinals.insert(ordinal)
            || required(value.label_key.as_deref())?.is_empty()
            || required(value.category_id.as_deref())?.is_empty()
            || required(value.unit.as_deref()).is_err()
            || !valid_aggregation
            || required(value.availability_key.as_deref())?.is_empty()
            || value.default_enabled.is_none()
            || value.related_semantic_ids.iter().any(|related| {
                related == &metric.semantic_id || !semantic_ids.contains(related.as_str())
            })
        {
            return Err(CoreError::InvalidRegistry);
        }
        if platform == "apple"
            && (required(value.kind.as_deref())?.is_empty()
                || required(value.source_selector.as_deref())?.is_empty()
                || required(value.authorization_key.as_deref())?.is_empty()
                || value.archive_only.is_none()
                || (value.archive_only == Some(true) && !value.outputs.is_empty())
                || (value.archive_only == Some(false) && value.outputs.is_empty()))
        {
            return Err(CoreError::InvalidRegistry);
        }
    }
    if ordinals.len() != selections.len()
        || !(0..u32::try_from(ordinals.len()).map_err(|_| CoreError::InvalidRegistry)?)
            .all(|ordinal| ordinals.contains(&ordinal))
    {
        return Err(CoreError::InvalidRegistry);
    }
    Ok(selections)
}

fn required(value: Option<&str>) -> Result<&str, CoreError> {
    value.ok_or(CoreError::InvalidRegistry)
}

fn validate_profile(
    profile: &ProfileRow,
    selections: &HashMap<&str, &MetricRow>,
) -> Result<(), CoreError> {
    if profile.public_profile_id.is_empty()
        || profile.public_schema != "healthmd.health_data"
        || profile.profile_revision == 0
        || profile.ordered_selection_ids.len() != selections.len()
        || profile
            .ordered_selection_ids
            .iter()
            .enumerate()
            .any(|(ordinal, selection_id)| {
                selections.get(selection_id.as_str()).is_none_or(|metric| {
                    let binding = if profile.platform == "apple" {
                        &metric.apple
                    } else {
                        &metric.android
                    };
                    binding.ordinal != u32::try_from(ordinal).ok()
                })
            })
    {
        return Err(CoreError::InvalidRegistry);
    }
    let unavailable = unique_nonempty(&profile.unavailable_selection_ids)?;
    if (profile.platform == "apple" && !unavailable.is_empty())
        || unavailable
            .iter()
            .any(|metric_id| selections.contains_key(metric_id))
    {
        return Err(CoreError::InvalidRegistry);
    }
    let mut output_paths = HashSet::new();
    for output in &profile.outputs {
        let selection_ids = output_selection_ids_row(output)?;
        if output.surface.is_empty()
            || output.key.is_empty()
            || !output_paths.insert((output.surface.as_str(), output.key.as_str()))
            || selection_ids
                .iter()
                .any(|selection| !selections.contains_key(selection.as_str()))
            || !matches!(output.alias_kind.as_str(), "none" | "legacy_android")
            || !matches!(
                output.condition.as_str(),
                "default" | "legacy_alias_opt_in" | "android_native_opt_in"
            )
            || (output.alias_kind == "legacy_android"
                && (output.condition != "legacy_alias_opt_in" || output.enabled_by_default))
            || (output.condition == "default" && !output.enabled_by_default)
        {
            return Err(CoreError::InvalidRegistry);
        }
        if profile.platform == "apple"
            && (output.unit.is_empty()
                || output.daily_aggregation.is_empty()
                || output.rollup.is_empty()
                || output.platform_native
                || output.alias_kind != "none")
        {
            return Err(CoreError::InvalidRegistry);
        }
    }
    Ok(())
}

fn output_selection_ids_row(output: &ProfileOutputRow) -> Result<Vec<String>, CoreError> {
    match (&output.selection_id, output.selection_ids.is_empty()) {
        (Some(selection), true) if !selection.is_empty() => Ok(vec![selection.clone()]),
        (None, false)
            if output
                .selection_ids
                .iter()
                .all(|selection| !selection.is_empty()) =>
        {
            Ok(output.selection_ids.clone())
        }
        _ => Err(CoreError::InvalidRegistry),
    }
}

// Projection is intentionally one coarse FFI cache-fill operation; keeping field mapping together
// makes omissions visible when the stable record changes.
#[allow(clippy::too_many_lines)]
fn project_snapshot(
    document: &RegistryDocument,
    requested: MetricRegistryProfile,
) -> Result<MetricRegistrySnapshot, CoreError> {
    let profile = document
        .profiles
        .iter()
        .find(|profile| profile.id == requested.id())
        .ok_or(CoreError::UnsupportedRegistryProfile)?;
    let categories = document
        .categories
        .iter()
        .filter(|category| category.platform == profile.platform)
        .map(|category| RegistryCategory {
            category_id: category.category_id.clone(),
            label_key: category.label_key.clone(),
            ordinal: category.ordinal,
        })
        .collect();

    let mut metric_by_selection = HashMap::new();
    for metric in &document.metrics {
        let binding = if profile.platform == "apple" {
            &metric.apple
        } else {
            &metric.android
        };
        if binding.status == "backed" {
            metric_by_selection.insert(
                required(binding.selection_id.as_deref())?,
                (metric, binding),
            );
        }
    }
    let metrics = profile
        .ordered_selection_ids
        .iter()
        .map(|selection_id| {
            let (metric, binding) = metric_by_selection
                .get(selection_id.as_str())
                .ok_or(CoreError::InvalidRegistry)?;
            Ok(RegistryMetric {
                semantic_id: metric.semantic_id.clone(),
                selection_id: selection_id.clone(),
                label_key: required(binding.label_key.as_deref())?.to_owned(),
                reference_name: binding
                    .reference_name
                    .as_ref()
                    .unwrap_or(&metric.reference_name)
                    .clone(),
                category_id: required(binding.category_id.as_deref())?.to_owned(),
                unit: required(binding.unit.as_deref())?.to_owned(),
                kind: binding.kind.clone().unwrap_or_else(|| "summary".to_owned()),
                source_aggregation: required(binding.source_aggregation.as_deref())?.to_owned(),
                default_enabled: binding.default_enabled.ok_or(CoreError::InvalidRegistry)?,
                archive_only: binding.archive_only.unwrap_or(false),
                availability_key: required(binding.availability_key.as_deref())?.to_owned(),
                authorization_key: binding
                    .authorization_key
                    .clone()
                    .unwrap_or_else(|| "native".to_owned()),
                capability_id: metric.capability_id.clone(),
                source_selector: binding
                    .source_selector
                    .clone()
                    .unwrap_or_else(|| selection_id.clone()),
                related_semantic_ids: binding.related_semantic_ids.clone(),
                ordinal: binding.ordinal.ok_or(CoreError::InvalidRegistry)?,
            })
        })
        .collect::<Result<Vec<_>, CoreError>>()?;

    let unavailable_by_id: HashMap<&str, &UnavailableRow> = document
        .legacy_unavailable
        .android
        .iter()
        .map(|metric| (metric.selection_id.as_str(), metric))
        .collect();
    let unavailable_metrics = profile
        .unavailable_selection_ids
        .iter()
        .map(|selection_id| {
            let unavailable = unavailable_by_id
                .get(selection_id.as_str())
                .ok_or(CoreError::InvalidRegistry)?;
            Ok(RegistryUnavailableMetric {
                selection_id: selection_id.clone(),
                category_id: unavailable.category_id.clone(),
                label_key: unavailable.label_key.clone(),
                reason_key: unavailable.reason_key.clone(),
            })
        })
        .collect::<Result<Vec<_>, CoreError>>()?;
    let outputs = profile
        .outputs
        .iter()
        .enumerate()
        .map(|(ordinal, output)| {
            Ok(RegistryOutput {
                selection_ids: output_selection_ids_row(output)?,
                surface: output.surface.clone(),
                key: output.key.clone(),
                unit: output.unit.clone(),
                daily_aggregation: output.daily_aggregation.clone(),
                rollup: output.rollup.clone(),
                alias_kind: output.alias_kind.clone(),
                platform_native: output.platform_native,
                condition: output.condition.clone(),
                enabled_by_default: output.enabled_by_default,
                ordinal: u32::try_from(ordinal).map_err(|_| CoreError::InvalidRegistry)?,
            })
        })
        .collect::<Result<Vec<_>, CoreError>>()?;

    Ok(MetricRegistrySnapshot {
        registry_version: document.registry_version,
        registry_sha256: REGISTRY_SHA256.to_owned(),
        profile_id: profile.id.clone(),
        public_profile_id: profile.public_profile_id.clone(),
        public_schema: profile.public_schema.clone(),
        public_schema_version: profile.public_schema_version,
        profile_revision: profile.profile_revision,
        categories,
        metrics,
        unavailable_metrics,
        outputs,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_and_projects_all_three_profiles() {
        assert_eq!(validate_embedded_registry(), Ok((230, 106, 3)));
        let apple = metric_registry_snapshot(MetricRegistryProfile::AppleHealthDataV8, 1).unwrap();
        let frozen = metric_registry_snapshot(MetricRegistryProfile::AndroidFrozenV4, 1).unwrap();
        let analytical =
            metric_registry_snapshot(MetricRegistryProfile::AndroidAnalyticalV5, 1).unwrap();
        assert_eq!((apple.metrics.len(), apple.outputs.len()), (230, 226));
        assert_eq!(apple.registry_sha256, crate::REGISTRY_SHA256,);
        assert_eq!(
            (
                frozen.metrics.len(),
                frozen.unavailable_metrics.len(),
                frozen.outputs.len()
            ),
            (106, 102, 161)
        );
        assert_eq!(
            (analytical.metrics.len(), analytical.outputs.len()),
            (106, 161)
        );
        assert_eq!(
            frozen
                .metrics
                .iter()
                .map(|metric| &metric.selection_id)
                .collect::<Vec<_>>(),
            analytical
                .metrics
                .iter()
                .map(|metric| &metric.selection_id)
                .collect::<Vec<_>>()
        );
        assert_eq!(
            frozen
                .outputs
                .iter()
                .filter(|output| output.enabled_by_default)
                .count(),
            132
        );
        assert_eq!(
            analytical
                .outputs
                .iter()
                .filter(|output| output.enabled_by_default)
                .count(),
            148
        );
        assert_eq!(
            frozen
                .outputs
                .iter()
                .filter(|output| output.alias_kind == "legacy_android")
                .count(),
            13
        );
    }

    #[test]
    fn projections_match_immutable_pre_cutover_native_baselines() {
        let apple_baseline: serde_json::Value =
            serde_json::from_slice(include_bytes!("../registry/native-baseline-apple-v7.json"))
                .unwrap();
        let android_baseline: serde_json::Value = serde_json::from_slice(include_bytes!(
            "../registry/native-baseline-android-v4-v5.json"
        ))
        .unwrap();
        let apple = metric_registry_snapshot(MetricRegistryProfile::AppleHealthDataV8, 1).unwrap();
        let frozen = metric_registry_snapshot(MetricRegistryProfile::AndroidFrozenV4, 1).unwrap();
        let analytical =
            metric_registry_snapshot(MetricRegistryProfile::AndroidAnalyticalV5, 1).unwrap();

        let baseline_apple_metrics = apple_baseline["metrics"].as_array().unwrap();
        assert_eq!(baseline_apple_metrics.len(), apple.metrics.len());
        for (baseline, projected) in baseline_apple_metrics.iter().zip(&apple.metrics) {
            assert_eq!(baseline["selection_id"], projected.selection_id);
            assert_eq!(baseline["reference_name"], projected.reference_name);
            assert_eq!(baseline["category_id"], projected.category_id);
            assert_eq!(baseline["unit"], projected.unit);
            assert_eq!(baseline["kind"], projected.kind);
            assert_eq!(baseline["source_aggregation"], projected.source_aggregation);
            assert_eq!(baseline["archive_only"], projected.archive_only);
            assert_eq!(baseline["default_enabled"], projected.default_enabled);
            assert_eq!(baseline["availability_key"], projected.availability_key);
            assert_eq!(baseline["source_selector"], projected.source_selector);
        }

        let baseline_android_metrics = android_baseline["metrics"].as_array().unwrap();
        assert_eq!(baseline_android_metrics.len(), frozen.metrics.len());
        for (baseline, projected) in baseline_android_metrics.iter().zip(&frozen.metrics) {
            assert_eq!(baseline["selection_id"], projected.selection_id);
            assert_eq!(baseline["category_id"], projected.category_id);
            assert_eq!(baseline["unit"], projected.unit);
            assert_eq!(baseline["source_aggregation"], projected.source_aggregation);
            assert_eq!(baseline["default_enabled"], projected.default_enabled);
            assert_eq!(baseline["availability_key"], projected.availability_key);
        }
        let baseline_unavailable = android_baseline["unavailable_metrics"]
            .as_array()
            .unwrap()
            .iter()
            .map(|metric| metric["selection_id"].as_str().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(
            baseline_unavailable,
            frozen
                .unavailable_metrics
                .iter()
                .map(|metric| metric.selection_id.as_str())
                .collect::<Vec<_>>()
        );
        let baseline_profiles = android_baseline["profiles"].as_array().unwrap();
        for (baseline, projected) in baseline_profiles.iter().zip([&frozen, &analytical]) {
            assert_eq!(baseline["profile_id"], projected.profile_id);
            assert_eq!(
                baseline["flat_output_keys"].as_array().unwrap(),
                &projected
                    .outputs
                    .iter()
                    .filter(|output| output.enabled_by_default)
                    .map(|output| serde_json::Value::String(output.key.clone()))
                    .collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn rejects_wrong_version_without_parsing_registry() {
        assert_eq!(
            metric_registry_snapshot(MetricRegistryProfile::AppleHealthDataV8, 2),
            Err(CoreError::UnsupportedRegistryVersion)
        );
    }

    #[test]
    fn rejects_mutated_or_noncanonical_registry_bytes() {
        let mut mutated = REGISTRY_BYTES.to_vec();
        mutated[10] ^= 1;
        assert_eq!(
            decode_and_validate(&mutated, true).unwrap_err(),
            CoreError::InvalidRegistry
        );
        let compact: serde_json::Value = serde_json::from_slice(REGISTRY_BYTES).unwrap();
        let compact = serde_json::to_vec(&compact).unwrap();
        assert_eq!(
            decode_and_validate(&compact, false).unwrap_err(),
            CoreError::InvalidRegistry
        );
    }

    #[test]
    fn validator_rejects_duplicate_ids_invalid_aliases_and_contradictory_availability() {
        let original: serde_json::Value = serde_json::from_slice(REGISTRY_BYTES).unwrap();
        for mutate in [
            |value: &mut serde_json::Value| {
                value["metrics"][1]["semantic_id"] = value["metrics"][0]["semantic_id"].clone();
            },
            |value: &mut serde_json::Value| {
                value["profiles"][1]["outputs"][0]["alias_kind"] = serde_json::json!("unknown");
            },
            |value: &mut serde_json::Value| {
                value["metrics"][1]["android"]["status"] = serde_json::json!("backed");
            },
            |value: &mut serde_json::Value| {
                value["metrics"][0]["capability_id"] =
                    serde_json::json!("android.activity-intensity");
            },
            |value: &mut serde_json::Value| {
                value["metrics"][0]["apple"]["source_aggregation"] = serde_json::json!("guessed");
            },
        ] {
            let mut value = original.clone();
            mutate(&mut value);
            let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
            bytes.push(b'\n');
            assert_eq!(
                decode_and_validate(&bytes, false).unwrap_err(),
                CoreError::InvalidRegistry
            );
        }
    }
}
