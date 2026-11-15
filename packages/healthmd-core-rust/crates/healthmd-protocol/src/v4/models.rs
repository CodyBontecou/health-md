//! Explicit closed serde DTOs for the bounded v4 foundation.
//! Field grammar is derived from the reviewed frozen agent/query v1 schemas.
//! `decode_typed` checks raw bytes and `validate_shape`; contextual semantics are separate.
use super::semantics::scalars::{
    CalendarZone, CivilDate, ControlUuid, Digest, FilenameTemplate, NativeTypeId, NullableOffset,
    RelativePath, SemanticId, UtcTimestamp, valid_lower_hex, valid_pointer,
};
use super::{Error, ValidateShape, shape, unique};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CaptureCompatibilityDetail {
    #[serde(rename = "summary")]
    Summary,
    #[serde(rename = "selected_time_series")]
    SelectedTimeSeries,
}
impl ValidateShape for CaptureCompatibilityDetail {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArchiveAndroidProviderNativeSnapshotV1Format {
    #[serde(rename = "json")]
    Json,
    #[serde(rename = "ndjson")]
    Ndjson,
}
impl ValidateShape for ArchiveAndroidProviderNativeSnapshotV1Format {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArchiveAndroidProviderNativeSnapshotV1RecordScope {
    #[serde(rename = "selected")]
    Selected,
    #[serde(rename = "all_authorized_supported")]
    AllAuthorizedSupported,
}
impl ValidateShape for ArchiveAndroidProviderNativeSnapshotV1RecordScope {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum Archive {
    #[serde(rename = "none")]
    None {},
    #[serde(rename = "apple_healthkit_canonical_v1")]
    AppleHealthkitCanonicalV1 {},
    #[serde(rename = "android_provider_native_snapshot_v1")]
    AndroidProviderNativeSnapshotV1 {
        format: ArchiveAndroidProviderNativeSnapshotV1Format,
        include_exercise_routes: bool,
        provider_id: SemanticId,
        record_scope: ArchiveAndroidProviderNativeSnapshotV1RecordScope,
    },
}
impl ValidateShape for Archive {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::None {} | Self::AppleHealthkitCanonicalV1 {} => Ok(()),
            Self::AndroidProviderNativeSnapshotV1 {
                format,
                include_exercise_routes: _,
                provider_id,
                record_scope,
            } => {
                (*format).validate_shape()?;
                (*provider_id).validate_shape()?;
                (*record_scope).validate_shape()?;
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Selection {
    pub all_metrics: bool,
    pub category_ids: Vec<SemanticId>,
    pub metric_ids: Vec<SemanticId>,
    pub provider_ids: Vec<SemanticId>,
    pub source_ids: Vec<SemanticId>,
}
impl ValidateShape for Selection {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.category_ids.len() <= 32)?;
        shape(unique(&self.category_ids))?;
        for item in &self.category_ids {
            item.validate_shape()?;
        }
        shape(self.metric_ids.len() <= 256)?;
        shape(unique(&self.metric_ids))?;
        for item in &self.metric_ids {
            item.validate_shape()?;
        }
        shape(self.provider_ids.len() <= 16)?;
        shape(unique(&self.provider_ids))?;
        for item in &self.provider_ids {
            item.validate_shape()?;
        }
        shape(!self.source_ids.is_empty())?;
        shape(self.source_ids.len() <= 16)?;
        shape(unique(&self.source_ids))?;
        for item in &self.source_ids {
            item.validate_shape()?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Capture {
    pub compatibility_detail: CaptureCompatibilityDetail,
    pub native_archive: Archive,
    pub selection: Selection,
}
impl ValidateShape for Capture {
    fn validate_shape(&self) -> Result<(), Error> {
        self.compatibility_detail.validate_shape()?;
        self.native_archive.validate_shape()?;
        self.selection.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Range {
    pub end_date: CivilDate,
    pub start_date: CivilDate,
}
impl ValidateShape for Range {
    fn validate_shape(&self) -> Result<(), Error> {
        self.end_date.validate_shape()?;
        self.start_date.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum Dates {
    #[serde(rename = "exact")]
    Exact { range: Range },
    #[serde(rename = "all_available")]
    AllAvailable {},
    #[serde(rename = "past_complete_days")]
    PastCompleteDays { anchor_date: CivilDate, days: u64 },
}
impl ValidateShape for Dates {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::Exact { range } => {
                (*range).validate_shape()?;
                Ok(())
            }
            Self::AllAvailable {} => Ok(()),
            Self::PastCompleteDays { anchor_date, days } => {
                (*anchor_date).validate_shape()?;
                shape((*days) >= 1)?;
                shape((*days) <= 3650)?;
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Destination {
    pub binding_id: ControlUuid,
    pub host_installation_id: ControlUuid,
    pub identity_sha256: Digest,
    pub revision: u64,
}
impl ValidateShape for Destination {
    fn validate_shape(&self) -> Result<(), Error> {
        self.binding_id.validate_shape()?;
        self.host_installation_id.validate_shape()?;
        self.identity_sha256.validate_shape()?;
        shape(self.revision >= 1)?;
        shape(self.revision <= 2_147_483_647)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum PeerPlatform {
    #[serde(rename = "apple")]
    Apple,
    #[serde(rename = "android")]
    Android,
}
impl ValidateShape for PeerPlatform {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Peer {
    pub host_installation_id: ControlUuid,
    pub platform: PeerPlatform,
    pub source_installation_id: ControlUuid,
}
impl ValidateShape for Peer {
    fn validate_shape(&self) -> Result<(), Error> {
        self.host_installation_id.validate_shape()?;
        self.platform.validate_shape()?;
        self.source_installation_id.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportIntentProductType {
    #[serde(rename = "generated_files")]
    GeneratedFiles,
}
impl ValidateShape for ExportIntentProductType {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportIntentProduct {
    #[serde(rename = "type")]
    pub kind: ExportIntentProductType,
}
impl ValidateShape for ExportIntentProduct {
    fn validate_shape(&self) -> Result<(), Error> {
        self.kind.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportIntentSchema {
    #[serde(rename = "healthmd.agent_export_intent")]
    HealthmdAgentExportIntent,
}
impl ValidateShape for ExportIntentSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct DailyNotes {
    pub create_if_missing: bool,
    pub enabled: bool,
    pub filename_template: FilenameTemplate,
    pub folder_template: RelativePath,
    pub only: bool,
    pub section_ids: Vec<SemanticId>,
}
impl ValidateShape for DailyNotes {
    fn validate_shape(&self) -> Result<(), Error> {
        self.filename_template.validate_shape()?;
        self.folder_template.validate_shape()?;
        shape(self.section_ids.len() <= 64)?;
        shape(unique(&self.section_ids))?;
        for item in &self.section_ids {
            item.validate_shape()?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DictionaryProfileDictionaryV1Format {
    #[serde(rename = "json")]
    Json,
    #[serde(rename = "markdown")]
    Markdown,
}
impl ValidateShape for DictionaryProfileDictionaryV1Format {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum Dictionary {
    #[serde(rename = "none")]
    None {},
    #[serde(rename = "profile_dictionary_v1")]
    ProfileDictionaryV1 {
        filename_template: FilenameTemplate,
        format: DictionaryProfileDictionaryV1Format,
    },
}
impl ValidateShape for Dictionary {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::None {} => Ok(()),
            Self::ProfileDictionaryV1 {
                filename_template,
                format,
            } => {
                (*filename_template).validate_shape()?;
                (*format).validate_shape()?;
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum OutputSettingsFormatsItem {
    #[serde(rename = "csv")]
    Csv,
    #[serde(rename = "json")]
    Json,
    #[serde(rename = "markdown")]
    Markdown,
    #[serde(rename = "obsidian_bases")]
    ObsidianBases,
}
impl ValidateShape for OutputSettingsFormatsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct IndividualEntries {
    pub category_folders: bool,
    pub enabled: bool,
    pub filename_template: FilenameTemplate,
    pub folder_template: RelativePath,
    pub metric_ids: Vec<SemanticId>,
}
impl ValidateShape for IndividualEntries {
    fn validate_shape(&self) -> Result<(), Error> {
        self.filename_template.validate_shape()?;
        self.folder_template.validate_shape()?;
        shape(self.metric_ids.len() <= 256)?;
        shape(unique(&self.metric_ids))?;
        for item in &self.metric_ids {
            item.validate_shape()?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum OutputSettingsOutputProfile {
    #[serde(rename = "apple-v8")]
    AppleV8,
    #[serde(rename = "android-frozen-v4")]
    AndroidFrozenV4,
    #[serde(rename = "android-analytical-v5")]
    AndroidAnalyticalV5,
}
impl ValidateShape for OutputSettingsOutputProfile {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum PackagingZipManifest {
    #[serde(rename = "healthmd.agent_artifact_manifest/1")]
    HealthmdAgentArtifactManifest1,
}
impl ValidateShape for PackagingZipManifest {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum Packaging {
    #[serde(rename = "loose_files")]
    LooseFiles {},
    #[serde(rename = "zip")]
    Zip {
        filename_template: FilenameTemplate,
        include_loose_files: bool,
        manifest: PackagingZipManifest,
        max_entries: u64,
        max_uncompressed_bytes: u64,
    },
}
impl ValidateShape for Packaging {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::LooseFiles {} => Ok(()),
            Self::Zip {
                filename_template,
                include_loose_files: _,
                manifest,
                max_entries,
                max_uncompressed_bytes,
            } => {
                (*filename_template).validate_shape()?;
                (*manifest).validate_shape()?;
                shape((*max_entries) >= 1)?;
                shape((*max_entries) <= 4096)?;
                shape((*max_uncompressed_bytes) >= 1)?;
                shape((*max_uncompressed_bytes) <= 1_073_741_824)?;
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum PresentationDisplayUnits {
    #[serde(rename = "metric")]
    Metric,
    #[serde(rename = "imperial")]
    Imperial,
}
impl ValidateShape for PresentationDisplayUnits {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FrontmatterCustomFieldsItem {
    pub key: SemanticId,
    pub value: String,
}
impl ValidateShape for FrontmatterCustomFieldsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        self.key.validate_shape()?;
        shape(self.value.chars().count() <= 4096)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Frontmatter {
    pub custom_fields: Vec<FrontmatterCustomFieldsItem>,
    pub enabled_field_ids: Vec<SemanticId>,
    pub include_capture_diagnostics: bool,
    pub include_units: bool,
}
impl ValidateShape for Frontmatter {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.custom_fields.len() <= 128)?;
        for item in &self.custom_fields {
            item.validate_shape()?;
        }
        shape(self.enabled_field_ids.len() <= 256)?;
        shape(unique(&self.enabled_field_ids))?;
        for item in &self.enabled_field_ids {
            item.validate_shape()?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum PresentationMachineUnits {
    #[serde(rename = "canonical")]
    Canonical,
}
impl ValidateShape for PresentationMachineUnits {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum MarkdownStyle {
    #[serde(rename = "tables")]
    Tables,
    #[serde(rename = "lists")]
    Lists,
}
impl ValidateShape for MarkdownStyle {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Markdown {
    pub custom_template: String,
    pub placeholder_ids: Vec<SemanticId>,
    pub style: MarkdownStyle,
}
impl ValidateShape for Markdown {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.custom_template.chars().count() <= 65_536)?;
        shape(self.placeholder_ids.len() <= 128)?;
        shape(unique(&self.placeholder_ids))?;
        for item in &self.placeholder_ids {
            item.validate_shape()?;
        }
        self.style.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Presentation {
    pub display_units: PresentationDisplayUnits,
    pub frontmatter: Frontmatter,
    pub group_by_category: bool,
    pub include_metadata: bool,
    pub locale: String,
    pub machine_units: PresentationMachineUnits,
    pub markdown: Markdown,
}
impl ValidateShape for Presentation {
    fn validate_shape(&self) -> Result<(), Error> {
        self.display_units.validate_shape()?;
        self.frontmatter.validate_shape()?;
        shape(self.locale.chars().count() >= 1)?;
        shape(self.locale.chars().count() <= 64)?;
        self.machine_units.validate_shape()?;
        self.markdown.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum OutputSettingsWriteMode {
    #[serde(rename = "overwrite")]
    Overwrite,
    #[serde(rename = "append")]
    Append,
    #[serde(rename = "merge_markdown")]
    MergeMarkdown,
    #[serde(rename = "merge_markdown_preserving_preamble")]
    MergeMarkdownPreservingPreamble,
}
impl ValidateShape for OutputSettingsWriteMode {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct OutputSettings {
    pub daily_notes: DailyNotes,
    pub dictionary: Dictionary,
    pub filename_template: FilenameTemplate,
    pub folder_template: RelativePath,
    pub formats: Vec<OutputSettingsFormatsItem>,
    pub individual_entries: IndividualEntries,
    pub output_profile: OutputSettingsOutputProfile,
    pub packaging: Packaging,
    pub presentation: Presentation,
    pub subfolder: RelativePath,
    pub write_mode: OutputSettingsWriteMode,
}
impl ValidateShape for OutputSettings {
    fn validate_shape(&self) -> Result<(), Error> {
        self.daily_notes.validate_shape()?;
        self.dictionary.validate_shape()?;
        self.filename_template.validate_shape()?;
        self.folder_template.validate_shape()?;
        shape(!self.formats.is_empty())?;
        shape(self.formats.len() <= 4)?;
        shape(unique(&self.formats))?;
        for item in &self.formats {
            item.validate_shape()?;
        }
        self.individual_entries.validate_shape()?;
        self.output_profile.validate_shape()?;
        self.packaging.validate_shape()?;
        self.presentation.validate_shape()?;
        self.subfolder.validate_shape()?;
        self.write_mode.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum Policy {
    #[serde(rename = "explicit")]
    Explicit { settings: Box<OutputSettings> },
    #[serde(rename = "saved_device_settings")]
    SavedDeviceSettings { expected_revision: u64 },
    #[serde(rename = "profile")]
    Profile {
        expected_revision: u64,
        profile_id: ControlUuid,
    },
}
impl ValidateShape for Policy {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::Explicit { settings } => {
                (*settings).validate_shape()?;
                Ok(())
            }
            Self::SavedDeviceSettings { expected_revision } => {
                shape((*expected_revision) >= 1)?;
                shape((*expected_revision) <= 2_147_483_647)?;
                Ok(())
            }
            Self::Profile {
                expected_revision,
                profile_id,
            } => {
                shape((*expected_revision) >= 1)?;
                shape((*expected_revision) <= 2_147_483_647)?;
                (*profile_id).validate_shape()?;
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportIntentTimestampTimezone {
    #[serde(rename = "UTC")]
    Utc,
}
impl ValidateShape for ExportIntentTimestampTimezone {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportIntent {
    pub calendar_timezone: CalendarZone,
    pub capture_scope: Capture,
    pub dates: Dates,
    pub destination: Destination,
    pub intent_id: ControlUuid,
    pub peer: Peer,
    pub product: ExportIntentProduct,
    pub schema: ExportIntentSchema,
    pub schema_version: u64,
    pub settings_policy: Policy,
    pub timestamp_timezone: ExportIntentTimestampTimezone,
}
impl ValidateShape for ExportIntent {
    fn validate_shape(&self) -> Result<(), Error> {
        self.calendar_timezone.validate_shape()?;
        self.capture_scope.validate_shape()?;
        self.dates.validate_shape()?;
        self.destination.validate_shape()?;
        self.intent_id.validate_shape()?;
        self.peer.validate_shape()?;
        self.product.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        self.settings_policy.validate_shape()?;
        self.timestamp_timezone.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum AuthorityReferenceIssuer {
    #[serde(rename = "native_source")]
    NativeSource,
    #[serde(rename = "authorized_host")]
    AuthorizedHost,
}
impl ValidateShape for AuthorityReferenceIssuer {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AuthorityReference {
    pub authority_id: ControlUuid,
    pub grant_revision: u64,
    pub grant_sha256: Digest,
    pub issuer: AuthorityReferenceIssuer,
}
impl ValidateShape for AuthorityReference {
    fn validate_shape(&self) -> Result<(), Error> {
        self.authority_id.validate_shape()?;
        shape(self.grant_revision >= 1)?;
        shape(self.grant_revision <= 2_147_483_647)?;
        self.grant_sha256.validate_shape()?;
        self.issuer.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AuthorityReferences {
    pub host: AuthorityReference,
    pub native: AuthorityReference,
}
impl ValidateShape for AuthorityReferences {
    fn validate_shape(&self) -> Result<(), Error> {
        self.host.validate_shape()?;
        self.native.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum OriginOrigin {
    #[serde(rename = "request")]
    Request,
    #[serde(rename = "saved_device_settings")]
    SavedDeviceSettings,
    #[serde(rename = "profile")]
    Profile,
    #[serde(rename = "resolved_calendar")]
    ResolvedCalendar,
    #[serde(rename = "catalog")]
    Catalog,
}
impl ValidateShape for OriginOrigin {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Origin {
    pub origin: OriginOrigin,
    pub pointer: String,
    pub revision: u64,
}
impl ValidateShape for Origin {
    fn validate_shape(&self) -> Result<(), Error> {
        self.origin.validate_shape()?;
        shape(self.pointer.chars().count() >= 1)?;
        shape(self.pointer.chars().count() <= 256)?;
        shape(self.revision <= 2_147_483_647)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportPlanPathPrediction {
    #[serde(rename = "exact_requested_days")]
    ExactRequestedDays,
    #[serde(rename = "template_only_all_available")]
    TemplateOnlyAllAvailable,
    #[serde(rename = "deferred_native_entries")]
    DeferredNativeEntries,
}
impl ValidateShape for ExportPlanPathPrediction {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum RevisionDomain {
    #[serde(rename = "device_settings")]
    DeviceSettings,
    #[serde(rename = "native_profile")]
    NativeProfile,
    #[serde(rename = "local_recipe")]
    LocalRecipe,
    #[serde(rename = "host_schedule")]
    HostSchedule,
    #[serde(rename = "native_schedule")]
    NativeSchedule,
    #[serde(rename = "native_destination")]
    NativeDestination,
    #[serde(rename = "native_credential_reference")]
    NativeCredentialReference,
}
impl ValidateShape for RevisionDomain {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Revision {
    pub domain: RevisionDomain,
    pub object_id: ControlUuid,
    pub revision: u64,
    pub sha256: Digest,
}
impl ValidateShape for Revision {
    fn validate_shape(&self) -> Result<(), Error> {
        self.domain.validate_shape()?;
        self.object_id.validate_shape()?;
        shape(self.revision >= 1)?;
        shape(self.revision <= 2_147_483_647)?;
        self.sha256.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportPlanSchema {
    #[serde(rename = "healthmd.agent_export_plan")]
    HealthmdAgentExportPlan,
}
impl ValidateShape for ExportPlanSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ZeroSideEffects {
    pub content_preview_reads: u64,
    pub credential_enrollments: u64,
    pub earliest_date_reads: u64,
    pub health_reads: u64,
    pub output_writes: u64,
    pub quota_consumed: u64,
    pub settings_mutations: u64,
    pub wake_enrollments: u64,
}
impl ValidateShape for ZeroSideEffects {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.content_preview_reads == 0)?;
        shape(self.credential_enrollments == 0)?;
        shape(self.earliest_date_reads == 0)?;
        shape(self.health_reads == 0)?;
        shape(self.output_writes == 0)?;
        shape(self.quota_consumed == 0)?;
        shape(self.settings_mutations == 0)?;
        shape(self.wake_enrollments == 0)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportPlan {
    pub authority_references: AuthorityReferences,
    pub capability_sha256: Digest,
    pub effective_settings: OutputSettings,
    pub expires_at: UtcTimestamp,
    pub intent: ExportIntent,
    pub issued_at: UtcTimestamp,
    pub limitations: Vec<SemanticId>,
    pub origins: Vec<Origin>,
    pub path_prediction: ExportPlanPathPrediction,
    pub plan_id: ControlUuid,
    pub plan_sha256: Digest,
    pub predicted_paths: Vec<RelativePath>,
    pub required_actions: Vec<SemanticId>,
    pub resolved_dates: Dates,
    pub resolved_metric_ids: Vec<SemanticId>,
    pub revisions: Vec<Revision>,
    pub schema: ExportPlanSchema,
    pub schema_version: u64,
    pub scope_sha256: Digest,
    pub settings_sha256: Digest,
    pub side_effects: ZeroSideEffects,
}
impl ValidateShape for ExportPlan {
    fn validate_shape(&self) -> Result<(), Error> {
        self.authority_references.validate_shape()?;
        self.capability_sha256.validate_shape()?;
        self.effective_settings.validate_shape()?;
        self.expires_at.validate_shape()?;
        self.intent.validate_shape()?;
        self.issued_at.validate_shape()?;
        shape(self.limitations.len() <= 64)?;
        shape(unique(&self.limitations))?;
        for item in &self.limitations {
            item.validate_shape()?;
        }
        shape(!self.origins.is_empty())?;
        shape(self.origins.len() <= 512)?;
        for item in &self.origins {
            item.validate_shape()?;
        }
        self.path_prediction.validate_shape()?;
        self.plan_id.validate_shape()?;
        self.plan_sha256.validate_shape()?;
        shape(self.predicted_paths.len() <= 4096)?;
        shape(unique(&self.predicted_paths))?;
        for item in &self.predicted_paths {
            item.validate_shape()?;
        }
        shape(self.required_actions.len() <= 16)?;
        shape(unique(&self.required_actions))?;
        for item in &self.required_actions {
            item.validate_shape()?;
        }
        self.resolved_dates.validate_shape()?;
        shape(!self.resolved_metric_ids.is_empty())?;
        shape(self.resolved_metric_ids.len() <= 256)?;
        shape(unique(&self.resolved_metric_ids))?;
        for item in &self.resolved_metric_ids {
            item.validate_shape()?;
        }
        shape(self.revisions.len() <= 16)?;
        for item in &self.revisions {
            item.validate_shape()?;
        }
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        self.scope_sha256.validate_shape()?;
        self.settings_sha256.validate_shape()?;
        self.side_effects.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryRequestSchema {
    #[serde(rename = "healthmd.agent_discovery_request")]
    HealthmdAgentDiscoveryRequest,
}
impl ValidateShape for DiscoveryRequestSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct DiscoveryRequest {
    pub peer: Peer,
    pub request_id: ControlUuid,
    pub schema: DiscoveryRequestSchema,
    pub schema_version: u64,
}
impl ValidateShape for DiscoveryRequest {
    fn validate_shape(&self) -> Result<(), Error> {
        self.peer.validate_shape()?;
        self.request_id.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Budgets {
    pub cursor_idle_seconds: u64,
    pub cursor_lifetime_seconds: u64,
    pub max_calendar_days: u64,
    pub max_capture_seconds: u64,
    pub max_page_bytes: u64,
    pub max_page_items: u64,
    pub max_snapshot_bytes: u64,
}
impl ValidateShape for Budgets {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.cursor_idle_seconds >= 1)?;
        shape(self.cursor_idle_seconds <= 600)?;
        shape(self.cursor_lifetime_seconds >= 1)?;
        shape(self.cursor_lifetime_seconds <= 3600)?;
        shape(self.max_calendar_days >= 1)?;
        shape(self.max_calendar_days <= 366_000)?;
        shape(self.max_capture_seconds >= 1)?;
        shape(self.max_capture_seconds <= 120)?;
        shape(self.max_page_bytes >= 1024)?;
        shape(self.max_page_bytes <= 1_048_576)?;
        shape(self.max_page_items >= 1)?;
        shape(self.max_page_items <= 1000)?;
        shape(self.max_snapshot_bytes >= 1024)?;
        shape(self.max_snapshot_bytes <= 67_108_864)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryConfigurationProtection {
    #[serde(rename = "locked")]
    Locked,
    #[serde(rename = "unlocked_native")]
    UnlockedNative,
}
impl ValidateShape for DiscoveryConfigurationProtection {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryControlOperationsItem {
    #[serde(rename = "local_recipe.list")]
    LocalRecipeList,
    #[serde(rename = "local_recipe.get")]
    LocalRecipeGet,
    #[serde(rename = "local_recipe.create")]
    LocalRecipeCreate,
    #[serde(rename = "local_recipe.update")]
    LocalRecipeUpdate,
    #[serde(rename = "local_recipe.delete")]
    LocalRecipeDelete,
    #[serde(rename = "local_recipe.run")]
    LocalRecipeRun,
    #[serde(rename = "local_recipe.plan")]
    LocalRecipePlan,
    #[serde(rename = "native_profile.list")]
    NativeProfileList,
    #[serde(rename = "native_profile.get")]
    NativeProfileGet,
    #[serde(rename = "native_profile.create")]
    NativeProfileCreate,
    #[serde(rename = "native_profile.update")]
    NativeProfileUpdate,
    #[serde(rename = "native_profile.activate")]
    NativeProfileActivate,
    #[serde(rename = "native_profile.delete")]
    NativeProfileDelete,
    #[serde(rename = "native_profile.plan")]
    NativeProfilePlan,
    #[serde(rename = "host_schedule.list")]
    HostScheduleList,
    #[serde(rename = "host_schedule.get")]
    HostScheduleGet,
    #[serde(rename = "host_schedule.create")]
    HostScheduleCreate,
    #[serde(rename = "host_schedule.update")]
    HostScheduleUpdate,
    #[serde(rename = "host_schedule.pause")]
    HostSchedulePause,
    #[serde(rename = "host_schedule.delete")]
    HostScheduleDelete,
    #[serde(rename = "host_schedule.run_now")]
    HostScheduleRunNow,
    #[serde(rename = "host_schedule.plan")]
    HostSchedulePlan,
    #[serde(rename = "native_schedule.inspect")]
    NativeScheduleInspect,
    #[serde(rename = "native_schedule.update")]
    NativeScheduleUpdate,
    #[serde(rename = "native_schedule.enable")]
    NativeScheduleEnable,
    #[serde(rename = "native_schedule.disable")]
    NativeScheduleDisable,
    #[serde(rename = "native_schedule.inspect_pending")]
    NativeScheduleInspectPending,
    #[serde(rename = "native_schedule.discard_pending")]
    NativeScheduleDiscardPending,
    #[serde(rename = "native_schedule.plan")]
    NativeSchedulePlan,
    #[serde(rename = "native_destination.inspect")]
    NativeDestinationInspect,
    #[serde(rename = "native_destination.update")]
    NativeDestinationUpdate,
    #[serde(rename = "native_destination.plan")]
    NativeDestinationPlan,
}
impl ValidateShape for DiscoveryControlOperationsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryEntitlement {
    #[serde(rename = "satisfied")]
    Satisfied,
    #[serde(rename = "required")]
    Required,
}
impl ValidateShape for DiscoveryEntitlement {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryFeaturesItem {
    #[serde(rename = "explicit_settings")]
    ExplicitSettings,
    #[serde(rename = "zero_health_plan")]
    ZeroHealthPlan,
    #[serde(rename = "bound_execution")]
    BoundExecution,
    #[serde(rename = "source_query")]
    SourceQuery,
    #[serde(rename = "source_projection")]
    SourceProjection,
    #[serde(rename = "native_profile_control")]
    NativeProfileControl,
    #[serde(rename = "native_schedule_control")]
    NativeScheduleControl,
    #[serde(rename = "native_destination_control")]
    NativeDestinationControl,
    #[serde(rename = "control_plan")]
    ControlPlan,
    #[serde(rename = "zip")]
    Zip,
    #[serde(rename = "profile_dictionary")]
    ProfileDictionary,
}
impl ValidateShape for DiscoveryFeaturesItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryLifecycle {
    #[serde(rename = "iphone_foreground_protected_data")]
    IphoneForegroundProtectedData,
    #[serde(rename = "android_user_started_service_after_first_unlock")]
    AndroidUserStartedServiceAfterFirstUnlock,
}
impl ValidateShape for DiscoveryLifecycle {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryNativeGrants {
    #[serde(rename = "satisfied")]
    Satisfied,
    #[serde(rename = "required")]
    Required,
    #[serde(rename = "unverified")]
    Unverified,
}
impl ValidateShape for DiscoveryNativeGrants {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum OutputSupportNativeArchiveProductsItem {
    #[serde(rename = "none")]
    None,
    #[serde(rename = "apple_healthkit_canonical_v1")]
    AppleHealthkitCanonicalV1,
    #[serde(rename = "android_provider_native_snapshot_v1")]
    AndroidProviderNativeSnapshotV1,
}
impl ValidateShape for OutputSupportNativeArchiveProductsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum OutputSupportPathTokensItem {
    #[serde(rename = "year")]
    Year,
    #[serde(rename = "month")]
    Month,
    #[serde(rename = "day")]
    Day,
    #[serde(rename = "date")]
    Date,
    #[serde(rename = "metric")]
    Metric,
    #[serde(rename = "category")]
    Category,
    #[serde(rename = "record_id")]
    RecordId,
}
impl ValidateShape for OutputSupportPathTokensItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct OutputSupport {
    pub compatibility_detail: Vec<CaptureCompatibilityDetail>,
    pub formats: Vec<OutputSettingsFormatsItem>,
    pub max_artifacts: u64,
    pub max_path_bytes: u64,
    pub native_archive_products: Vec<OutputSupportNativeArchiveProductsItem>,
    pub path_tokens: Vec<OutputSupportPathTokensItem>,
    pub setting_pointers: Vec<String>,
    pub write_modes: Vec<OutputSettingsWriteMode>,
}
impl ValidateShape for OutputSupport {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.compatibility_detail.len() <= 2)?;
        shape(unique(&self.compatibility_detail))?;
        for item in &self.compatibility_detail {
            item.validate_shape()?;
        }
        shape(self.formats.len() <= 4)?;
        shape(unique(&self.formats))?;
        for item in &self.formats {
            item.validate_shape()?;
        }
        shape(self.max_artifacts >= 1)?;
        shape(self.max_artifacts <= 4096)?;
        shape(self.max_path_bytes >= 1)?;
        shape(self.max_path_bytes <= 4096)?;
        shape(self.native_archive_products.len() <= 3)?;
        shape(unique(&self.native_archive_products))?;
        for item in &self.native_archive_products {
            item.validate_shape()?;
        }
        shape(self.path_tokens.len() <= 7)?;
        shape(unique(&self.path_tokens))?;
        for item in &self.path_tokens {
            item.validate_shape()?;
        }
        shape(self.setting_pointers.len() <= 512)?;
        shape(unique(&self.setting_pointers))?;
        for item in &self.setting_pointers {
            shape(item.chars().count() >= 1)?;
            shape(item.chars().count() <= 256)?;
            shape(valid_pointer(item))?;
        }
        shape(self.write_modes.len() <= 4)?;
        shape(unique(&self.write_modes))?;
        for item in &self.write_modes {
            item.validate_shape()?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryProjectionProductsItem {
    #[serde(rename = "android_source_projection_v1")]
    AndroidSourceProjectionV1,
}
impl ValidateShape for DiscoveryProjectionProductsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum QueryCatalogFeatureStatusesItemStatus {
    #[serde(rename = "available")]
    Available,
    #[serde(rename = "unavailable")]
    Unavailable,
    #[serde(rename = "error")]
    Error,
    #[serde(rename = "unverified")]
    Unverified,
}
impl ValidateShape for QueryCatalogFeatureStatusesItemStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct QueryCatalogFeatureStatusesItem {
    pub feature: SemanticId,
    pub status: QueryCatalogFeatureStatusesItemStatus,
}
impl ValidateShape for QueryCatalogFeatureStatusesItem {
    fn validate_shape(&self) -> Result<(), Error> {
        self.feature.validate_shape()?;
        self.status.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CoverageHistoryFeatureStatus {
    #[serde(rename = "available")]
    Available,
    #[serde(rename = "unavailable")]
    Unavailable,
    #[serde(rename = "error")]
    Error,
    #[serde(rename = "not_applicable")]
    NotApplicable,
}
impl ValidateShape for CoverageHistoryFeatureStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CoverageHistoryState {
    #[serde(rename = "full_granted")]
    FullGranted,
    #[serde(rename = "bounded")]
    Bounded,
    #[serde(rename = "unverified")]
    Unverified,
    #[serde(rename = "not_applicable")]
    NotApplicable,
}
impl ValidateShape for CoverageHistoryState {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CoverageHistory {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub boundary: Option<CivilDate>,
    pub feature_status: CoverageHistoryFeatureStatus,
    pub state: CoverageHistoryState,
}
impl ValidateShape for CoverageHistory {
    fn validate_shape(&self) -> Result<(), Error> {
        if let Some(value) = &self.boundary {
            (*value).validate_shape()?;
        }
        self.feature_status.validate_shape()?;
        self.state.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CoverageMissingItemReason {
    #[serde(rename = "no_records")]
    NoRecords,
    #[serde(rename = "unsupported")]
    Unsupported,
    #[serde(rename = "permission_required")]
    PermissionRequired,
    #[serde(rename = "history_limited")]
    HistoryLimited,
    #[serde(rename = "history_unverified")]
    HistoryUnverified,
    #[serde(rename = "failure")]
    Failure,
    #[serde(rename = "skipped")]
    Skipped,
    #[serde(rename = "cancelled")]
    Cancelled,
}
impl ValidateShape for CoverageMissingItemReason {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CoverageMissingItem {
    pub metric_id: SemanticId,
    pub range: Range,
    pub reason: CoverageMissingItemReason,
}
impl ValidateShape for CoverageMissingItem {
    fn validate_shape(&self) -> Result<(), Error> {
        self.metric_id.validate_shape()?;
        self.range.validate_shape()?;
        self.reason.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CoverageStatus {
    #[serde(rename = "complete")]
    Complete,
    #[serde(rename = "complete_empty")]
    CompleteEmpty,
    #[serde(rename = "partial")]
    Partial,
    #[serde(rename = "unavailable")]
    Unavailable,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "cancelled")]
    Cancelled,
}
impl ValidateShape for CoverageStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Coverage {
    pub days_considered: u64,
    pub days_with_values: u64,
    pub history: CoverageHistory,
    pub missing: Vec<CoverageMissingItem>,
    pub missing_count: u64,
    pub missing_truncated: bool,
    pub status: CoverageStatus,
}
impl ValidateShape for Coverage {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.days_considered <= 366_000)?;
        shape(self.days_with_values <= 366_000)?;
        self.history.validate_shape()?;
        shape(self.missing.len() <= 64)?;
        for item in &self.missing {
            item.validate_shape()?;
        }
        shape(self.missing_count <= 2_147_483_647)?;
        self.status.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CatalogItemAvailability {
    #[serde(rename = "planned")]
    Planned,
    #[serde(rename = "unavailable")]
    Unavailable,
    #[serde(rename = "supported")]
    Supported,
    #[serde(rename = "permission_required")]
    PermissionRequired,
    #[serde(rename = "feature_unavailable")]
    FeatureUnavailable,
    #[serde(rename = "history_unverified")]
    HistoryUnverified,
}
impl ValidateShape for CatalogItemAvailability {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CatalogItemOwnerRule {
    #[serde(rename = "civil_day_aggregate")]
    CivilDayAggregate,
    #[serde(rename = "source_start_civil_day")]
    SourceStartCivilDay,
    #[serde(rename = "noon_to_noon_additive_native")]
    NoonToNoonAdditiveNative,
    #[serde(rename = "source_start_noon_journal")]
    SourceStartNoonJournal,
}
impl ValidateShape for CatalogItemOwnerRule {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CatalogItemRegistryEquivalence {
    #[serde(rename = "platform_exact_or_unavailable")]
    PlatformExactOrUnavailable,
    #[serde(rename = "mapped_alias")]
    MappedAlias,
    #[serde(rename = "platform_distinct")]
    PlatformDistinct,
}
impl ValidateShape for CatalogItemRegistryEquivalence {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CatalogItemStatisticsItem {
    #[serde(rename = "sum")]
    Sum,
    #[serde(rename = "average")]
    Average,
    #[serde(rename = "minimum")]
    Minimum,
    #[serde(rename = "maximum")]
    Maximum,
    #[serde(rename = "latest")]
    Latest,
    #[serde(rename = "count")]
    Count,
    #[serde(rename = "duration_sum")]
    DurationSum,
}
impl ValidateShape for CatalogItemStatisticsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CatalogItemType {
    #[serde(rename = "catalog_metric")]
    CatalogMetric,
}
impl ValidateShape for CatalogItemType {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CatalogItem {
    pub availability: CatalogItemAvailability,
    pub evidence_value_support: bool,
    pub feature_gate: String,
    pub metric_id: SemanticId,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub native_record_type: Option<NativeTypeId>,
    pub owner_rule: CatalogItemOwnerRule,
    pub registry_equivalence: CatalogItemRegistryEquivalence,
    pub source_statistic: String,
    pub statistics: Vec<CatalogItemStatisticsItem>,
    pub target_or_reason: String,
    #[serde(rename = "type")]
    pub kind: CatalogItemType,
    pub unit: String,
}
impl ValidateShape for CatalogItem {
    fn validate_shape(&self) -> Result<(), Error> {
        self.availability.validate_shape()?;
        shape(self.feature_gate.chars().count() <= 128)?;
        self.metric_id.validate_shape()?;
        if let Some(value) = &self.native_record_type {
            (*value).validate_shape()?;
        }
        self.owner_rule.validate_shape()?;
        self.registry_equivalence.validate_shape()?;
        shape(self.source_statistic.chars().count() >= 1)?;
        shape(self.source_statistic.chars().count() <= 128)?;
        shape(!self.statistics.is_empty())?;
        shape(self.statistics.len() <= 7)?;
        shape(unique(&self.statistics))?;
        for item in &self.statistics {
            item.validate_shape()?;
        }
        shape(self.target_or_reason.chars().count() >= 1)?;
        shape(self.target_or_reason.chars().count() <= 256)?;
        self.kind.validate_shape()?;
        shape(self.unit.chars().count() >= 1)?;
        shape(self.unit.chars().count() <= 32)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum QueryCatalogProviderAvailability {
    #[serde(rename = "available")]
    Available,
    #[serde(rename = "unavailable")]
    Unavailable,
    #[serde(rename = "update_required")]
    UpdateRequired,
    #[serde(rename = "unverified")]
    Unverified,
}
impl ValidateShape for QueryCatalogProviderAvailability {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum QueryCatalogSchema {
    #[serde(rename = "healthmd.source_query_catalog")]
    HealthmdSourceQueryCatalog,
}
impl ValidateShape for QueryCatalogSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum QueryCatalogSourceId {
    #[serde(rename = "apple_health")]
    AppleHealth,
    #[serde(rename = "health_connect")]
    HealthConnect,
    #[serde(rename = "provider_native")]
    ProviderNative,
}
impl ValidateShape for QueryCatalogSourceId {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct QueryCatalog {
    pub budgets: Budgets,
    pub feature_statuses: Vec<QueryCatalogFeatureStatusesItem>,
    pub history: Coverage,
    pub metrics: Vec<CatalogItem>,
    pub operations: Vec<SemanticId>,
    pub peer: Peer,
    pub provider_availability: QueryCatalogProviderAvailability,
    pub provider_id: SemanticId,
    pub provider_version: String,
    pub schema: QueryCatalogSchema,
    pub schema_version: u64,
    pub sdk_version: String,
    pub source_id: QueryCatalogSourceId,
}
impl ValidateShape for QueryCatalog {
    fn validate_shape(&self) -> Result<(), Error> {
        self.budgets.validate_shape()?;
        shape(self.feature_statuses.len() <= 32)?;
        for item in &self.feature_statuses {
            item.validate_shape()?;
        }
        self.history.validate_shape()?;
        shape(self.metrics.len() <= 256)?;
        for item in &self.metrics {
            item.validate_shape()?;
        }
        shape(self.operations.len() <= 9)?;
        shape(unique(&self.operations))?;
        for item in &self.operations {
            item.validate_shape()?;
        }
        self.peer.validate_shape()?;
        self.provider_availability.validate_shape()?;
        self.provider_id.validate_shape()?;
        shape(self.provider_version.chars().count() >= 1)?;
        shape(self.provider_version.chars().count() <= 128)?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        shape(self.sdk_version.chars().count() >= 1)?;
        shape(self.sdk_version.chars().count() <= 64)?;
        self.source_id.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoveryRequiredActionsItem {
    #[serde(rename = "open_mobile_app")]
    OpenMobileApp,
    #[serde(rename = "unlock_mobile")]
    UnlockMobile,
    #[serde(rename = "grant_health_access")]
    GrantHealthAccess,
    #[serde(rename = "grant_history_access")]
    GrantHistoryAccess,
    #[serde(rename = "native_configuration_unlock")]
    NativeConfigurationUnlock,
    #[serde(rename = "native_destination_rebind")]
    NativeDestinationRebind,
    #[serde(rename = "purchase_required")]
    PurchaseRequired,
}
impl ValidateShape for DiscoveryRequiredActionsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoverySchema {
    #[serde(rename = "healthmd.agent_discovery")]
    HealthmdAgentDiscovery,
}
impl ValidateShape for DiscoverySchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DiscoverySettingsPoliciesItem {
    #[serde(rename = "explicit")]
    Explicit,
    #[serde(rename = "saved_device_settings")]
    SavedDeviceSettings,
    #[serde(rename = "profile")]
    Profile,
}
impl ValidateShape for DiscoverySettingsPoliciesItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Discovery {
    pub authority_references: Vec<AuthorityReference>,
    pub budgets: Budgets,
    pub capability_revision: u64,
    pub capability_sha256: Digest,
    pub configuration_protection: DiscoveryConfigurationProtection,
    pub control_operations: Vec<DiscoveryControlOperationsItem>,
    pub entitlement: DiscoveryEntitlement,
    pub expires_at: UtcTimestamp,
    pub features: Vec<DiscoveryFeaturesItem>,
    pub issued_at: UtcTimestamp,
    pub lifecycle: DiscoveryLifecycle,
    pub native_grants: DiscoveryNativeGrants,
    pub output_profiles: Vec<OutputSettingsOutputProfile>,
    pub output_support: OutputSupport,
    pub peer: Peer,
    pub projection_catalog_sha256: Digest,
    pub projection_products: Vec<DiscoveryProjectionProductsItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub projection_source_catalog: Option<QueryCatalog>,
    pub query_catalog_sha256: Digest,
    pub query_operations: Vec<SemanticId>,
    pub request_id: ControlUuid,
    pub required_actions: Vec<DiscoveryRequiredActionsItem>,
    pub schema: DiscoverySchema,
    pub schema_version: u64,
    pub settings_policies: Vec<DiscoverySettingsPoliciesItem>,
    pub source_calendar_timezone: CalendarZone,
}
impl ValidateShape for Discovery {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.authority_references.len() <= 32)?;
        for item in &self.authority_references {
            item.validate_shape()?;
        }
        self.budgets.validate_shape()?;
        shape(self.capability_revision >= 1)?;
        shape(self.capability_revision <= 2_147_483_647)?;
        self.capability_sha256.validate_shape()?;
        self.configuration_protection.validate_shape()?;
        shape(self.control_operations.len() <= 64)?;
        shape(unique(&self.control_operations))?;
        for item in &self.control_operations {
            item.validate_shape()?;
        }
        self.entitlement.validate_shape()?;
        self.expires_at.validate_shape()?;
        shape(self.features.len() <= 11)?;
        shape(unique(&self.features))?;
        for item in &self.features {
            item.validate_shape()?;
        }
        self.issued_at.validate_shape()?;
        self.lifecycle.validate_shape()?;
        self.native_grants.validate_shape()?;
        shape(self.output_profiles.len() <= 3)?;
        shape(unique(&self.output_profiles))?;
        for item in &self.output_profiles {
            item.validate_shape()?;
        }
        self.output_support.validate_shape()?;
        self.peer.validate_shape()?;
        self.projection_catalog_sha256.validate_shape()?;
        shape(self.projection_products.len() <= 1)?;
        shape(unique(&self.projection_products))?;
        for item in &self.projection_products {
            item.validate_shape()?;
        }
        if let Some(value) = &self.projection_source_catalog {
            (*value).validate_shape()?;
        }
        self.query_catalog_sha256.validate_shape()?;
        shape(self.query_operations.len() <= 9)?;
        shape(unique(&self.query_operations))?;
        for item in &self.query_operations {
            item.validate_shape()?;
        }
        self.request_id.validate_shape()?;
        shape(self.required_actions.len() <= 16)?;
        shape(unique(&self.required_actions))?;
        for item in &self.required_actions {
            item.validate_shape()?;
        }
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        shape(self.settings_policies.len() <= 3)?;
        shape(unique(&self.settings_policies))?;
        for item in &self.settings_policies {
            item.validate_shape()?;
        }
        self.source_calendar_timezone.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum PlanRequestSchema {
    #[serde(rename = "healthmd.agent_plan_request")]
    HealthmdAgentPlanRequest,
}
impl ValidateShape for PlanRequestSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct PlanRequest {
    pub authority_id: ControlUuid,
    pub authority_revision: u64,
    pub capability_sha256: Digest,
    pub host_authority_reference: AuthorityReference,
    pub intent: ExportIntent,
    pub request_id: ControlUuid,
    pub schema: PlanRequestSchema,
    pub schema_version: u64,
}
impl ValidateShape for PlanRequest {
    fn validate_shape(&self) -> Result<(), Error> {
        self.authority_id.validate_shape()?;
        shape(self.authority_revision >= 1)?;
        shape(self.authority_revision <= 2_147_483_647)?;
        self.capability_sha256.validate_shape()?;
        self.host_authority_reference.validate_shape()?;
        self.intent.validate_shape()?;
        self.request_id.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Binding {
    pub authority_references: AuthorityReferences,
    pub capability_sha256: Digest,
    pub destination: Destination,
    pub expires_at: UtcTimestamp,
    pub peer: Peer,
    pub plan_sha256: Digest,
    pub revisions: Vec<Revision>,
    pub scope_sha256: Digest,
    pub settings_sha256: Digest,
}
impl ValidateShape for Binding {
    fn validate_shape(&self) -> Result<(), Error> {
        self.authority_references.validate_shape()?;
        self.capability_sha256.validate_shape()?;
        self.destination.validate_shape()?;
        self.expires_at.validate_shape()?;
        self.peer.validate_shape()?;
        self.plan_sha256.validate_shape()?;
        shape(self.revisions.len() <= 16)?;
        for item in &self.revisions {
            item.validate_shape()?;
        }
        self.scope_sha256.validate_shape()?;
        self.settings_sha256.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ApprovalRequestSchema {
    #[serde(rename = "healthmd.agent_approval_request")]
    HealthmdAgentApprovalRequest,
}
impl ValidateShape for ApprovalRequestSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ApprovalRequest {
    pub binding: Binding,
    pub plan_id: ControlUuid,
    pub request_id: ControlUuid,
    pub schema: ApprovalRequestSchema,
    pub schema_version: u64,
}
impl ValidateShape for ApprovalRequest {
    fn validate_shape(&self) -> Result<(), Error> {
        self.binding.validate_shape()?;
        self.plan_id.validate_shape()?;
        self.request_id.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ApprovalRightsItem {
    #[serde(rename = "export_execute")]
    ExportExecute,
}
impl ValidateShape for ApprovalRightsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ApprovalSchema {
    #[serde(rename = "healthmd.agent_approval")]
    HealthmdAgentApproval,
}
impl ValidateShape for ApprovalSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Approval {
    pub approval_id: ControlUuid,
    pub approved_at: UtcTimestamp,
    pub authority_id: ControlUuid,
    pub binding: Binding,
    pub rights: Vec<ApprovalRightsItem>,
    pub schema: ApprovalSchema,
    pub schema_version: u64,
}
impl ValidateShape for Approval {
    fn validate_shape(&self) -> Result<(), Error> {
        self.approval_id.validate_shape()?;
        self.approved_at.validate_shape()?;
        self.authority_id.validate_shape()?;
        self.binding.validate_shape()?;
        shape(!self.rights.is_empty())?;
        shape(self.rights.len() <= 1)?;
        shape(unique(&self.rights))?;
        for item in &self.rights {
            item.validate_shape()?;
        }
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExecuteRequestSchema {
    #[serde(rename = "healthmd.agent_execute_request")]
    HealthmdAgentExecuteRequest,
}
impl ValidateShape for ExecuteRequestSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExecuteRequest {
    pub approval: Approval,
    pub idempotency_key: ControlUuid,
    pub job_id: ControlUuid,
    pub plan: ExportPlan,
    pub request_id: ControlUuid,
    pub schema: ExecuteRequestSchema,
    pub schema_version: u64,
}
impl ValidateShape for ExecuteRequest {
    fn validate_shape(&self) -> Result<(), Error> {
        self.approval.validate_shape()?;
        self.idempotency_key.validate_shape()?;
        self.job_id.validate_shape()?;
        self.plan.validate_shape()?;
        self.request_id.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CancelRequestSchema {
    #[serde(rename = "healthmd.agent_cancel_request")]
    HealthmdAgentCancelRequest,
}
impl ValidateShape for CancelRequestSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CancelRequest {
    pub approval_id: ControlUuid,
    pub authority_id: ControlUuid,
    pub job_id: ControlUuid,
    pub peer: Peer,
    pub request_sha256: Digest,
    pub schema: CancelRequestSchema,
    pub schema_version: u64,
}
impl ValidateShape for CancelRequest {
    fn validate_shape(&self) -> Result<(), Error> {
        self.approval_id.validate_shape()?;
        self.authority_id.validate_shape()?;
        self.job_id.validate_shape()?;
        self.peer.validate_shape()?;
        self.request_sha256.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ResumeRequestSchema {
    #[serde(rename = "healthmd.agent_resume_request")]
    HealthmdAgentResumeRequest,
}
impl ValidateShape for ResumeRequestSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ResumeRequest {
    pub binding: Binding,
    pub committed_partition_count: u64,
    pub destination: Destination,
    pub frontier_sha256: Digest,
    pub job_id: ControlUuid,
    pub manifest_sha256: Digest,
    pub peer: Peer,
    pub request_sha256: Digest,
    pub schema: ResumeRequestSchema,
    pub schema_version: u64,
}
impl ValidateShape for ResumeRequest {
    fn validate_shape(&self) -> Result<(), Error> {
        self.binding.validate_shape()?;
        shape(self.committed_partition_count <= 2_147_483_647)?;
        self.destination.validate_shape()?;
        self.frontier_sha256.validate_shape()?;
        self.job_id.validate_shape()?;
        self.manifest_sha256.validate_shape()?;
        self.peer.validate_shape()?;
        self.request_sha256.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactBranch1MediaType {
    #[serde(rename = "application/json")]
    ApplicationJson,
    #[serde(rename = "application/x-ndjson")]
    ApplicationXNdjson,
    #[serde(rename = "text/csv")]
    TextCsv,
    #[serde(rename = "text/markdown")]
    TextMarkdown,
    #[serde(rename = "application/zip")]
    ApplicationZip,
}
impl ValidateShape for ArtifactBranch1MediaType {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactBranch1Profile {
    #[serde(rename = "apple-v8")]
    AppleV8,
    #[serde(rename = "android-frozen-v4")]
    AndroidFrozenV4,
    #[serde(rename = "android-analytical-v5")]
    AndroidAnalyticalV5,
    #[serde(rename = "apple-healthkit-canonical-v1")]
    AppleHealthkitCanonicalV1,
    #[serde(rename = "android-provider-native-snapshot-v1")]
    AndroidProviderNativeSnapshotV1,
    #[serde(rename = "profile-dictionary-v1")]
    ProfileDictionaryV1,
    #[serde(rename = "zip-container-v1")]
    ZipContainerV1,
}
impl ValidateShape for ArtifactBranch1Profile {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactBranch1 {
    pub artifact_id: ControlUuid,
    pub byte_count: u64,
    pub media_type: ArtifactBranch1MediaType,
    pub profile: ArtifactBranch1Profile,
    pub relative_path: RelativePath,
    pub sha256: Digest,
    pub write_mode: OutputSettingsWriteMode,
}
impl ValidateShape for ArtifactBranch1 {
    fn validate_shape(&self) -> Result<(), Error> {
        self.artifact_id.validate_shape()?;
        shape(self.byte_count <= 1_099_511_627_776)?;
        self.media_type.validate_shape()?;
        self.profile.validate_shape()?;
        self.relative_path.validate_shape()?;
        self.sha256.validate_shape()?;
        self.write_mode.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactBranch2MediaType {
    #[serde(rename = "application/json")]
    ApplicationJson,
}
impl ValidateShape for ArtifactBranch2MediaType {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactBranch2Profile {
    #[serde(rename = "android-source-projection-v1")]
    AndroidSourceProjectionV1,
}
impl ValidateShape for ArtifactBranch2Profile {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactBranch2WriteMode {
    #[serde(rename = "overwrite")]
    Overwrite,
}
impl ValidateShape for ArtifactBranch2WriteMode {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactBranch2 {
    pub artifact_id: ControlUuid,
    pub byte_count: u64,
    pub media_type: ArtifactBranch2MediaType,
    pub profile: ArtifactBranch2Profile,
    pub relative_path: RelativePath,
    pub sha256: Digest,
    pub write_mode: ArtifactBranch2WriteMode,
}
impl ValidateShape for ArtifactBranch2 {
    fn validate_shape(&self) -> Result<(), Error> {
        self.artifact_id.validate_shape()?;
        shape(self.byte_count <= 1_099_511_627_776)?;
        self.media_type.validate_shape()?;
        self.profile.validate_shape()?;
        self.relative_path.validate_shape()?;
        self.sha256.validate_shape()?;
        self.write_mode.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactBranch3MediaType {
    #[serde(rename = "application/x-ndjson")]
    ApplicationXNdjson,
}
impl ValidateShape for ArtifactBranch3MediaType {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactBranch3WriteMode {
    #[serde(rename = "overwrite")]
    Overwrite,
    #[serde(rename = "append")]
    Append,
}
impl ValidateShape for ArtifactBranch3WriteMode {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactBranch3 {
    pub artifact_id: ControlUuid,
    pub byte_count: u64,
    pub media_type: ArtifactBranch3MediaType,
    pub profile: ArtifactBranch2Profile,
    pub relative_path: RelativePath,
    pub sha256: Digest,
    pub write_mode: ArtifactBranch3WriteMode,
}
impl ValidateShape for ArtifactBranch3 {
    fn validate_shape(&self) -> Result<(), Error> {
        self.artifact_id.validate_shape()?;
        shape(self.byte_count <= 1_099_511_627_776)?;
        self.media_type.validate_shape()?;
        self.profile.validate_shape()?;
        self.relative_path.validate_shape()?;
        self.sha256.validate_shape()?;
        self.write_mode.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(untagged)]
pub enum Artifact {
    Branch1(ArtifactBranch1),
    Branch2(ArtifactBranch2),
    Branch3(ArtifactBranch3),
}
impl ValidateShape for Artifact {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::Branch1(value) => value.validate_shape(),
            Self::Branch2(value) => value.validate_shape(),
            Self::Branch3(value) => value.validate_shape(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactManifestBranchStatusesItemStatus {
    #[serde(rename = "success")]
    Success,
    #[serde(rename = "unsupported")]
    Unsupported,
    #[serde(rename = "skipped")]
    Skipped,
    #[serde(rename = "failure")]
    Failure,
    #[serde(rename = "cancelled")]
    Cancelled,
}
impl ValidateShape for ArtifactManifestBranchStatusesItemStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactManifestBranchStatusesItem {
    pub record_count: u64,
    pub selector_id: SemanticId,
    pub status: ArtifactManifestBranchStatusesItemStatus,
}
impl ValidateShape for ArtifactManifestBranchStatusesItem {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.record_count <= 2_147_483_647)?;
        self.selector_id.validate_shape()?;
        self.status.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactManifestCaptureStatus {
    #[serde(rename = "complete")]
    Complete,
    #[serde(rename = "complete_empty")]
    CompleteEmpty,
    #[serde(rename = "partial")]
    Partial,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "cancelled")]
    Cancelled,
}
impl ValidateShape for ArtifactManifestCaptureStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ArtifactManifestSchema {
    #[serde(rename = "healthmd.agent_artifact_manifest")]
    HealthmdAgentArtifactManifest,
}
impl ValidateShape for ArtifactManifestSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactManifest {
    pub artifacts: Vec<Artifact>,
    pub binding: Binding,
    pub branch_statuses: Vec<ArtifactManifestBranchStatusesItem>,
    pub capture_status: ArtifactManifestCaptureStatus,
    pub job_id: ControlUuid,
    pub request_sha256: Digest,
    pub schema: ArtifactManifestSchema,
    pub schema_version: u64,
}
impl ValidateShape for ArtifactManifest {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.artifacts.len() <= 4096)?;
        for item in &self.artifacts {
            item.validate_shape()?;
        }
        self.binding.validate_shape()?;
        shape(self.branch_statuses.len() <= 256)?;
        for item in &self.branch_statuses {
            item.validate_shape()?;
        }
        self.capture_status.validate_shape()?;
        self.job_id.validate_shape()?;
        self.request_sha256.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CommitReceiptSchema {
    #[serde(rename = "healthmd.agent_commit_receipt")]
    HealthmdAgentCommitReceipt,
}
impl ValidateShape for CommitReceiptSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CommitReceiptStatus {
    #[serde(rename = "committed")]
    Committed,
    #[serde(rename = "already_committed")]
    AlreadyCommitted,
    #[serde(rename = "conflict")]
    Conflict,
}
impl ValidateShape for CommitReceiptStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CommitReceipt {
    pub after_sha256: Digest,
    pub artifact_id: ControlUuid,
    pub before_sha256: Digest,
    pub commit_key: Digest,
    pub destination: Destination,
    pub input_sha256: Digest,
    pub job_id: ControlUuid,
    pub manifest_sha256: Digest,
    pub peer: Peer,
    pub relative_path: RelativePath,
    pub request_sha256: Digest,
    pub schema: CommitReceiptSchema,
    pub schema_version: u64,
    pub status: CommitReceiptStatus,
    pub write_mode: OutputSettingsWriteMode,
}
impl ValidateShape for CommitReceipt {
    fn validate_shape(&self) -> Result<(), Error> {
        self.after_sha256.validate_shape()?;
        self.artifact_id.validate_shape()?;
        self.before_sha256.validate_shape()?;
        self.commit_key.validate_shape()?;
        self.destination.validate_shape()?;
        self.input_sha256.validate_shape()?;
        self.job_id.validate_shape()?;
        self.manifest_sha256.validate_shape()?;
        self.peer.validate_shape()?;
        self.relative_path.validate_shape()?;
        self.request_sha256.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        self.status.validate_shape()?;
        self.write_mode.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExecutionReceiptSchema {
    #[serde(rename = "healthmd.agent_execution_receipt")]
    HealthmdAgentExecutionReceipt,
}
impl ValidateShape for ExecutionReceiptSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExecutionReceiptStatus {
    #[serde(rename = "accepted")]
    Accepted,
    #[serde(rename = "paused")]
    Paused,
    #[serde(rename = "complete")]
    Complete,
    #[serde(rename = "complete_empty")]
    CompleteEmpty,
    #[serde(rename = "partial")]
    Partial,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "cancellation_pending")]
    CancellationPending,
    #[serde(rename = "cancelled")]
    Cancelled,
    #[serde(rename = "expired")]
    Expired,
}
impl ValidateShape for ExecutionReceiptStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExecutionReceipt {
    pub artifact_count: u64,
    pub binding: Binding,
    pub committed_partition_count: u64,
    pub expires_at: UtcTimestamp,
    pub frontier_sha256: Digest,
    pub job_id: ControlUuid,
    pub manifest_sha256: Digest,
    pub request_sha256: Digest,
    pub schema: ExecutionReceiptSchema,
    pub schema_version: u64,
    pub source_acknowledged: bool,
    pub status: ExecutionReceiptStatus,
}
impl ValidateShape for ExecutionReceipt {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.artifact_count <= 4096)?;
        self.binding.validate_shape()?;
        shape(self.committed_partition_count <= 2_147_483_647)?;
        self.expires_at.validate_shape()?;
        self.frontier_sha256.validate_shape()?;
        self.job_id.validate_shape()?;
        self.manifest_sha256.validate_shape()?;
        self.request_sha256.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        self.status.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum AuthorityConfigurationProtection {
    #[serde(rename = "not_applicable")]
    NotApplicable,
    #[serde(rename = "unlocked_native")]
    UnlockedNative,
    #[serde(rename = "locked")]
    Locked,
}
impl ValidateShape for AuthorityConfigurationProtection {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ControlReadScopeCreateDomainsItem {
    #[serde(rename = "local_recipe")]
    LocalRecipe,
    #[serde(rename = "native_profile")]
    NativeProfile,
    #[serde(rename = "host_schedule")]
    HostSchedule,
}
impl ValidateShape for ControlReadScopeCreateDomainsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ControlReadScopeListDomainsItem {
    #[serde(rename = "local_recipe")]
    LocalRecipe,
    #[serde(rename = "native_profile")]
    NativeProfile,
    #[serde(rename = "host_schedule")]
    HostSchedule,
    #[serde(rename = "native_schedule")]
    NativeSchedule,
    #[serde(rename = "native_destination")]
    NativeDestination,
}
impl ValidateShape for ControlReadScopeListDomainsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ControlReadScopeObjectsItem {
    pub domain: ControlReadScopeListDomainsItem,
    pub object_id: ControlUuid,
}
impl ValidateShape for ControlReadScopeObjectsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        self.domain.validate_shape()?;
        self.object_id.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ControlReadScope {
    pub create_domains: Vec<ControlReadScopeCreateDomainsItem>,
    pub list_domains: Vec<ControlReadScopeListDomainsItem>,
    pub objects: Vec<ControlReadScopeObjectsItem>,
}
impl ValidateShape for ControlReadScope {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(self.create_domains.len() <= 3)?;
        shape(unique(&self.create_domains))?;
        for item in &self.create_domains {
            item.validate_shape()?;
        }
        shape(self.list_domains.len() <= 5)?;
        shape(unique(&self.list_domains))?;
        for item in &self.list_domains {
            item.validate_shape()?;
        }
        shape(self.objects.len() <= 256)?;
        for item in &self.objects {
            item.validate_shape()?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum AuthorityRightsItem {
    #[serde(rename = "discover")]
    Discover,
    #[serde(rename = "plan")]
    Plan,
    #[serde(rename = "query_summary")]
    QuerySummary,
    #[serde(rename = "query_evidence")]
    QueryEvidence,
    #[serde(rename = "export_execute")]
    ExportExecute,
    #[serde(rename = "recipe_read")]
    RecipeRead,
    #[serde(rename = "recipe_mutate")]
    RecipeMutate,
    #[serde(rename = "recipe_run")]
    RecipeRun,
    #[serde(rename = "native_configuration_read")]
    NativeConfigurationRead,
    #[serde(rename = "native_configuration_mutate")]
    NativeConfigurationMutate,
    #[serde(rename = "host_schedule_read")]
    HostScheduleRead,
    #[serde(rename = "host_schedule_mutate")]
    HostScheduleMutate,
    #[serde(rename = "host_schedule_run")]
    HostScheduleRun,
    #[serde(rename = "native_schedule_mutate")]
    NativeScheduleMutate,
}
impl ValidateShape for AuthorityRightsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum AuthoritySchema {
    #[serde(rename = "healthmd.agent_authority")]
    HealthmdAgentAuthority,
}
impl ValidateShape for AuthoritySchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Authority {
    pub authority_id: ControlUuid,
    pub configuration_protection: AuthorityConfigurationProtection,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub control_read_scope: Option<ControlReadScope>,
    pub destination_binding_ids: Vec<ControlUuid>,
    pub entitlement: DiscoveryEntitlement,
    pub expires_at: UtcTimestamp,
    pub grant_revision: u64,
    pub issuer: AuthorityReferenceIssuer,
    pub native_consent: DiscoveryEntitlement,
    pub peer: Peer,
    pub rights: Vec<AuthorityRightsItem>,
    pub schema: AuthoritySchema,
    pub schema_version: u64,
    pub scope_sha256: Digest,
}
impl ValidateShape for Authority {
    fn validate_shape(&self) -> Result<(), Error> {
        self.authority_id.validate_shape()?;
        self.configuration_protection.validate_shape()?;
        if let Some(value) = &self.control_read_scope {
            (*value).validate_shape()?;
        }
        shape(self.destination_binding_ids.len() <= 32)?;
        shape(unique(&self.destination_binding_ids))?;
        for item in &self.destination_binding_ids {
            item.validate_shape()?;
        }
        self.entitlement.validate_shape()?;
        self.expires_at.validate_shape()?;
        shape(self.grant_revision >= 1)?;
        shape(self.grant_revision <= 2_147_483_647)?;
        self.issuer.validate_shape()?;
        self.native_consent.validate_shape()?;
        self.peer.validate_shape()?;
        shape(!self.rights.is_empty())?;
        shape(self.rights.len() <= 14)?;
        shape(unique(&self.rights))?;
        for item in &self.rights {
            item.validate_shape()?;
        }
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        self.scope_sha256.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum ExportDelegationBoundsDatePolicy {
    #[serde(rename = "bounded_exact")]
    BoundedExact { max_days: u64, range: Range },
    #[serde(rename = "authorized_history")]
    AuthorizedHistory {
        allow_all_available: bool,
        max_days: u64,
    },
}
impl ValidateShape for ExportDelegationBoundsDatePolicy {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::BoundedExact { max_days, range } => {
                shape((*max_days) >= 1)?;
                shape((*max_days) <= 366_000)?;
                (*range).validate_shape()?;
                Ok(())
            }
            Self::AuthorizedHistory {
                allow_all_available: _,
                max_days,
            } => {
                shape((*max_days) >= 1)?;
                shape((*max_days) <= 366_000)?;
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum ExportDelegationBoundsDestinationPolicy {
    #[serde(rename = "authenticated_host_bindings")]
    AuthenticatedHostBindings {},
    #[serde(rename = "registered_host_bindings")]
    RegisteredHostBindings { binding_ids: Vec<ControlUuid> },
}
impl ValidateShape for ExportDelegationBoundsDestinationPolicy {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::AuthenticatedHostBindings {} => Ok(()),
            Self::RegisteredHostBindings { binding_ids } => {
                shape(!(*binding_ids).is_empty())?;
                shape((*binding_ids).len() <= 32)?;
                shape(unique(binding_ids))?;
                for item in binding_ids {
                    item.validate_shape()?;
                }
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportDelegationBoundsProductsItem {
    #[serde(rename = "generated_files")]
    GeneratedFiles,
    #[serde(rename = "android_source_projection_v1")]
    AndroidSourceProjectionV1,
}
impl ValidateShape for ExportDelegationBoundsProductsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportDelegationBoundsProjectionDetailsItem {
    #[serde(rename = "summary")]
    Summary,
    #[serde(rename = "selected_time_series")]
    SelectedTimeSeries,
    #[serde(rename = "native_records")]
    NativeRecords,
}
impl ValidateShape for ExportDelegationBoundsProjectionDetailsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportDelegationBoundsProjectionObjectIdsItem {
    #[serde(rename = "daily_summary")]
    DailySummary,
    #[serde(rename = "selected_series")]
    SelectedSeries,
    #[serde(rename = "native_records")]
    NativeRecords,
    #[serde(rename = "capture_manifest")]
    CaptureManifest,
}
impl ValidateShape for ExportDelegationBoundsProjectionObjectIdsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportDelegationBounds {
    pub calendar_timezones: Vec<CalendarZone>,
    pub compatibility_detail: Vec<CaptureCompatibilityDetail>,
    pub date_policy: ExportDelegationBoundsDatePolicy,
    pub destination_policy: ExportDelegationBoundsDestinationPolicy,
    pub formats: Vec<OutputSettingsFormatsItem>,
    pub metric_ids: Vec<SemanticId>,
    pub native_archive_products: Vec<OutputSupportNativeArchiveProductsItem>,
    pub output_profiles: Vec<OutputSettingsOutputProfile>,
    pub products: Vec<ExportDelegationBoundsProductsItem>,
    pub projection_details: Vec<ExportDelegationBoundsProjectionDetailsItem>,
    pub projection_field_ids: Vec<SemanticId>,
    pub projection_object_ids: Vec<ExportDelegationBoundsProjectionObjectIdsItem>,
    pub write_modes: Vec<OutputSettingsWriteMode>,
}
impl ValidateShape for ExportDelegationBounds {
    fn validate_shape(&self) -> Result<(), Error> {
        shape(!self.calendar_timezones.is_empty())?;
        shape(self.calendar_timezones.len() <= 16)?;
        shape(unique(&self.calendar_timezones))?;
        for item in &self.calendar_timezones {
            item.validate_shape()?;
        }
        shape(!self.compatibility_detail.is_empty())?;
        shape(self.compatibility_detail.len() <= 2)?;
        shape(unique(&self.compatibility_detail))?;
        for item in &self.compatibility_detail {
            item.validate_shape()?;
        }
        self.date_policy.validate_shape()?;
        self.destination_policy.validate_shape()?;
        shape(!self.formats.is_empty())?;
        shape(self.formats.len() <= 4)?;
        shape(unique(&self.formats))?;
        for item in &self.formats {
            item.validate_shape()?;
        }
        shape(!self.metric_ids.is_empty())?;
        shape(self.metric_ids.len() <= 256)?;
        shape(unique(&self.metric_ids))?;
        for item in &self.metric_ids {
            item.validate_shape()?;
        }
        shape(!self.native_archive_products.is_empty())?;
        shape(self.native_archive_products.len() <= 3)?;
        shape(unique(&self.native_archive_products))?;
        for item in &self.native_archive_products {
            item.validate_shape()?;
        }
        shape(!self.output_profiles.is_empty())?;
        shape(self.output_profiles.len() <= 3)?;
        shape(unique(&self.output_profiles))?;
        for item in &self.output_profiles {
            item.validate_shape()?;
        }
        shape(!self.products.is_empty())?;
        shape(self.products.len() <= 2)?;
        shape(unique(&self.products))?;
        for item in &self.products {
            item.validate_shape()?;
        }
        shape(self.projection_details.len() <= 3)?;
        shape(unique(&self.projection_details))?;
        for item in &self.projection_details {
            item.validate_shape()?;
        }
        shape(self.projection_field_ids.len() <= 256)?;
        shape(unique(&self.projection_field_ids))?;
        for item in &self.projection_field_ids {
            item.validate_shape()?;
        }
        shape(self.projection_object_ids.len() <= 4)?;
        shape(unique(&self.projection_object_ids))?;
        for item in &self.projection_object_ids {
            item.validate_shape()?;
        }
        shape(!self.write_modes.is_empty())?;
        shape(self.write_modes.len() <= 4)?;
        shape(unique(&self.write_modes))?;
        for item in &self.write_modes {
            item.validate_shape()?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportDelegationRightsItem {
    #[serde(rename = "discover")]
    Discover,
    #[serde(rename = "plan")]
    Plan,
    #[serde(rename = "export_execute")]
    ExportExecute,
}
impl ValidateShape for ExportDelegationRightsItem {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ExportDelegationSchema {
    #[serde(rename = "healthmd.agent_export_delegation")]
    HealthmdAgentExportDelegation,
}
impl ValidateShape for ExportDelegationSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportDelegation {
    pub authority_id: ControlUuid,
    pub bounds: ExportDelegationBounds,
    pub expires_at: UtcTimestamp,
    pub grant_revision: u64,
    pub issuer: AuthorityReferenceIssuer,
    pub peer: Peer,
    pub rights: Vec<ExportDelegationRightsItem>,
    pub schema: ExportDelegationSchema,
    pub schema_version: u64,
}
impl ValidateShape for ExportDelegation {
    fn validate_shape(&self) -> Result<(), Error> {
        self.authority_id.validate_shape()?;
        self.bounds.validate_shape()?;
        self.expires_at.validate_shape()?;
        shape(self.grant_revision >= 1)?;
        shape(self.grant_revision <= 2_147_483_647)?;
        self.issuer.validate_shape()?;
        self.peer.validate_shape()?;
        shape(!self.rights.is_empty())?;
        shape(self.rights.len() <= 3)?;
        shape(unique(&self.rights))?;
        for item in &self.rights {
            item.validate_shape()?;
        }
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum AgentErrorCode {
    #[serde(rename = "invalid_request")]
    InvalidRequest,
    #[serde(rename = "unsupported_capability")]
    UnsupportedCapability,
    #[serde(rename = "unsupported_metric")]
    UnsupportedMetric,
    #[serde(rename = "permission_required")]
    PermissionRequired,
    #[serde(rename = "history_unverified")]
    HistoryUnverified,
    #[serde(rename = "configuration_protected")]
    ConfigurationProtected,
    #[serde(rename = "entitlement_required")]
    EntitlementRequired,
    #[serde(rename = "native_rebind_required")]
    NativeRebindRequired,
    #[serde(rename = "revision_conflict")]
    RevisionConflict,
    #[serde(rename = "approval_required")]
    ApprovalRequired,
    #[serde(rename = "binding_changed")]
    BindingChanged,
    #[serde(rename = "plan_expired")]
    PlanExpired,
    #[serde(rename = "unsafe_path")]
    UnsafePath,
    #[serde(rename = "path_collision")]
    PathCollision,
    #[serde(rename = "query_budget_exceeded")]
    QueryBudgetExceeded,
    #[serde(rename = "cursor_invalid")]
    CursorInvalid,
    #[serde(rename = "snapshot_expired")]
    SnapshotExpired,
    #[serde(rename = "busy")]
    Busy,
    #[serde(rename = "cancelled")]
    Cancelled,
    #[serde(rename = "spool_missing_restart_required")]
    SpoolMissingRestartRequired,
    #[serde(rename = "job_expired")]
    JobExpired,
}
impl ValidateShape for AgentErrorCode {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum AgentErrorSchema {
    #[serde(rename = "healthmd.agent_error")]
    HealthmdAgentError,
}
impl ValidateShape for AgentErrorSchema {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AgentError {
    pub code: AgentErrorCode,
    pub request_id: ControlUuid,
    pub retryable: bool,
    pub schema: AgentErrorSchema,
    pub schema_version: u64,
}
impl ValidateShape for AgentError {
    fn validate_shape(&self) -> Result<(), Error> {
        self.code.validate_shape()?;
        self.request_id.validate_shape()?;
        self.schema.validate_shape()?;
        shape(self.schema_version == 1)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "precision", deny_unknown_fields)]
pub enum ExactTime {
    #[serde(rename = "source_nanoseconds")]
    SourceNanoseconds {
        epoch_second: i64,
        nanosecond: u64,
        source_offset_seconds: NullableOffset,
    },
    #[serde(rename = "source_milliseconds")]
    SourceMilliseconds {
        epoch_second: i64,
        nanosecond: u64,
        source_offset_seconds: NullableOffset,
    },
    #[serde(rename = "source_seconds")]
    SourceSeconds {
        epoch_second: i64,
        nanosecond: u64,
        source_offset_seconds: NullableOffset,
    },
    #[serde(rename = "source_binary64_seconds")]
    SourceBinary64Seconds {
        epoch_second: i64,
        nanosecond: u64,
        source_binary64_bits: String,
        source_offset_seconds: NullableOffset,
    },
}
impl ValidateShape for ExactTime {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::SourceNanoseconds {
                epoch_second,
                nanosecond,
                source_offset_seconds,
            } => {
                shape((*epoch_second) >= -62_135_596_800)?;
                shape((*epoch_second) <= 253_402_300_799)?;
                shape((*nanosecond) <= 999_999_999)?;
                source_offset_seconds.validate_shape()?;
                Ok(())
            }
            Self::SourceMilliseconds {
                epoch_second,
                nanosecond,
                source_offset_seconds,
            } => {
                shape((*epoch_second) >= -62_135_596_800)?;
                shape((*epoch_second) <= 253_402_300_799)?;
                shape((*nanosecond) <= 999_999_999)?;
                source_offset_seconds.validate_shape()?;
                Ok(())
            }
            Self::SourceSeconds {
                epoch_second,
                nanosecond,
                source_offset_seconds,
            } => {
                shape((*epoch_second) >= -62_135_596_800)?;
                shape((*epoch_second) <= 253_402_300_799)?;
                shape((*nanosecond) <= 999_999_999)?;
                source_offset_seconds.validate_shape()?;
                Ok(())
            }
            Self::SourceBinary64Seconds {
                epoch_second,
                nanosecond,
                source_binary64_bits,
                source_offset_seconds,
            } => {
                shape((*epoch_second) >= -62_135_596_800)?;
                shape((*epoch_second) <= 253_402_300_799)?;
                shape((*nanosecond) <= 999_999_999)?;
                shape((*source_binary64_bits).chars().count() >= 16)?;
                shape((*source_binary64_bits).chars().count() <= 16)?;
                shape(valid_lower_hex(source_binary64_bits, 16))?;
                source_offset_seconds.validate_shape()?;
                Ok(())
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NativeIdentityAppleHealthIdentityKind {
    #[serde(rename = "native")]
    Native,
    #[serde(rename = "derived_child")]
    DerivedChild,
    #[serde(rename = "external")]
    External,
}
impl ValidateShape for NativeIdentityAppleHealthIdentityKind {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NativeIdentityAppleHealthMetadataStatusClientRecordId {
    #[serde(rename = "not_exposed_by_source")]
    NotExposedBySource,
}
impl ValidateShape for NativeIdentityAppleHealthMetadataStatusClientRecordId {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct NativeIdentityAppleHealthMetadataStatus {
    pub client_record_id: NativeIdentityAppleHealthMetadataStatusClientRecordId,
    pub client_record_version: NativeIdentityAppleHealthMetadataStatusClientRecordId,
    pub last_modified: NativeIdentityAppleHealthMetadataStatusClientRecordId,
}
impl ValidateShape for NativeIdentityAppleHealthMetadataStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        self.client_record_id.validate_shape()?;
        self.client_record_version.validate_shape()?;
        self.last_modified.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NativeIdentityAppleHealthProviderId {
    #[serde(rename = "apple_health")]
    AppleHealth,
}
impl ValidateShape for NativeIdentityAppleHealthProviderId {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NativeIdentityHealthConnectMetadataStatusClientRecordId {
    #[serde(rename = "available")]
    Available,
    #[serde(rename = "absent")]
    Absent,
    #[serde(rename = "not_captured")]
    NotCaptured,
    #[serde(rename = "not_exposed_by_source")]
    NotExposedBySource,
}
impl ValidateShape for NativeIdentityHealthConnectMetadataStatusClientRecordId {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NativeIdentityHealthConnectMetadataStatusClientRecordVersion {
    #[serde(rename = "available")]
    Available,
    #[serde(rename = "not_captured")]
    NotCaptured,
    #[serde(rename = "not_exposed_by_source")]
    NotExposedBySource,
}
impl ValidateShape for NativeIdentityHealthConnectMetadataStatusClientRecordVersion {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct NativeIdentityHealthConnectMetadataStatus {
    pub client_record_id: NativeIdentityHealthConnectMetadataStatusClientRecordId,
    pub client_record_version: NativeIdentityHealthConnectMetadataStatusClientRecordVersion,
    pub last_modified: NativeIdentityHealthConnectMetadataStatusClientRecordVersion,
}
impl ValidateShape for NativeIdentityHealthConnectMetadataStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        self.client_record_id.validate_shape()?;
        self.client_record_version.validate_shape()?;
        self.last_modified.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NativeIdentityHealthConnectProviderId {
    #[serde(rename = "health_connect")]
    HealthConnect,
}
impl ValidateShape for NativeIdentityHealthConnectProviderId {
    fn validate_shape(&self) -> Result<(), Error> {
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct NativeIdentityProviderNativeMetadataStatus {
    pub client_record_id: NativeIdentityHealthConnectMetadataStatusClientRecordId,
    pub client_record_version: NativeIdentityHealthConnectMetadataStatusClientRecordVersion,
    pub last_modified: NativeIdentityHealthConnectMetadataStatusClientRecordVersion,
}
impl ValidateShape for NativeIdentityProviderNativeMetadataStatus {
    fn validate_shape(&self) -> Result<(), Error> {
        self.client_record_id.validate_shape()?;
        self.client_record_version.validate_shape()?;
        self.last_modified.validate_shape()?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "source_id", deny_unknown_fields)]
pub enum NativeIdentity {
    #[serde(rename = "apple_health")]
    AppleHealth {
        identity_kind: NativeIdentityAppleHealthIdentityKind,
        metadata_status: NativeIdentityAppleHealthMetadataStatus,
        #[serde(skip_serializing_if = "Option::is_none")]
        origin: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        parent_record_id: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        parent_record_type: Option<NativeTypeId>,
        provider_id: NativeIdentityAppleHealthProviderId,
        record_id: String,
        record_type: NativeTypeId,
    },
    #[serde(rename = "health_connect")]
    HealthConnect {
        #[serde(skip_serializing_if = "Option::is_none")]
        client_record_id: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        client_record_version: Option<u64>,
        identity_kind: NativeIdentityAppleHealthIdentityKind,
        #[serde(skip_serializing_if = "Option::is_none")]
        last_modified: Option<ExactTime>,
        metadata_status: NativeIdentityHealthConnectMetadataStatus,
        #[serde(skip_serializing_if = "Option::is_none")]
        origin: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        parent_record_id: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        parent_record_type: Option<NativeTypeId>,
        provider_id: NativeIdentityHealthConnectProviderId,
        record_id: String,
        record_type: NativeTypeId,
    },
    #[serde(rename = "provider_native")]
    ProviderNative {
        #[serde(skip_serializing_if = "Option::is_none")]
        client_record_id: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        client_record_version: Option<u64>,
        identity_kind: NativeIdentityAppleHealthIdentityKind,
        #[serde(skip_serializing_if = "Option::is_none")]
        last_modified: Option<ExactTime>,
        metadata_status: NativeIdentityProviderNativeMetadataStatus,
        #[serde(skip_serializing_if = "Option::is_none")]
        origin: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        parent_record_id: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        parent_record_type: Option<NativeTypeId>,
        provider_id: SemanticId,
        record_id: String,
        record_type: NativeTypeId,
    },
}
// Keep the closed source-specific schema branches together for review.
#[allow(clippy::too_many_lines)]
impl ValidateShape for NativeIdentity {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::AppleHealth {
                identity_kind,
                metadata_status,
                origin,
                parent_record_id,
                parent_record_type,
                provider_id,
                record_id,
                record_type,
            } => {
                (*identity_kind).validate_shape()?;
                (*metadata_status).validate_shape()?;
                if let Some(value) = origin {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = parent_record_id {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = parent_record_type {
                    (*value).validate_shape()?;
                }
                (*provider_id).validate_shape()?;
                shape((*record_id).chars().count() >= 1)?;
                shape((*record_id).chars().count() <= 256)?;
                (*record_type).validate_shape()?;
                Ok(())
            }
            Self::HealthConnect {
                client_record_id,
                client_record_version,
                identity_kind,
                last_modified,
                metadata_status,
                origin,
                parent_record_id,
                parent_record_type,
                provider_id,
                record_id,
                record_type,
            } => {
                if let Some(value) = client_record_id {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = client_record_version {
                    shape((*value) <= 9_223_372_036_854_775_807)?;
                }
                (*identity_kind).validate_shape()?;
                if let Some(value) = last_modified {
                    (*value).validate_shape()?;
                }
                (*metadata_status).validate_shape()?;
                if let Some(value) = origin {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = parent_record_id {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = parent_record_type {
                    (*value).validate_shape()?;
                }
                (*provider_id).validate_shape()?;
                shape((*record_id).chars().count() >= 1)?;
                shape((*record_id).chars().count() <= 256)?;
                (*record_type).validate_shape()?;
                Ok(())
            }
            Self::ProviderNative {
                client_record_id,
                client_record_version,
                identity_kind,
                last_modified,
                metadata_status,
                origin,
                parent_record_id,
                parent_record_type,
                provider_id,
                record_id,
                record_type,
            } => {
                if let Some(value) = client_record_id {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = client_record_version {
                    shape((*value) <= 9_223_372_036_854_775_807)?;
                }
                (*identity_kind).validate_shape()?;
                if let Some(value) = last_modified {
                    (*value).validate_shape()?;
                }
                (*metadata_status).validate_shape()?;
                if let Some(value) = origin {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = parent_record_id {
                    shape((*value).chars().count() >= 1)?;
                    shape((*value).chars().count() <= 256)?;
                }
                if let Some(value) = parent_record_type {
                    (*value).validate_shape()?;
                }
                (*provider_id).validate_shape()?;
                shape((*record_id).chars().count() >= 1)?;
                shape((*record_id).chars().count() <= 256)?;
                (*record_type).validate_shape()?;
                Ok(())
            }
        }
    }
}
