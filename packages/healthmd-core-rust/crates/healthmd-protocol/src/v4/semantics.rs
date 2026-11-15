pub(crate) mod scalars;
pub use scalars::*;

use super::models::{
    AgentError, Approval, ApprovalRequest, Archive,
    ArchiveAndroidProviderNativeSnapshotV1RecordScope, Artifact, ArtifactManifest,
    ArtifactManifestBranchStatusesItemStatus, ArtifactManifestCaptureStatus, Authority,
    AuthorityReferenceIssuer, AuthorityReferences, Binding, CancelRequest, CommitReceipt, Dates,
    Dictionary, Discovery, DiscoveryFeaturesItem, DiscoveryRequest, ExecuteRequest,
    ExecutionReceipt, ExecutionReceiptStatus, ExportDelegation, ExportIntent, ExportPlan,
    ExportPlanPathPrediction, Origin, OriginOrigin, OutputSettings, OutputSettingsFormatsItem,
    OutputSettingsOutputProfile, OutputSettingsWriteMode, Packaging, PeerPlatform, PlanRequest,
    Policy, QueryCatalog, Range, ResumeRequest, Revision, RevisionDomain, Selection,
};
use super::paths::{DAILY_TOKENS, ENTRY_TOKENS};
use super::{
    Error, ValidateShape, canonical_json, decode_typed, ensure, parse_strict, sha256_hex, shape,
    sorted, unique,
};
use chrono::{Datelike as _, Duration};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;

/// Platform registry rows supplied by the native adapter, not caller JSON.
#[derive(Clone, Debug)]
pub struct MetricSupport {
    pub metric_id: SemanticId,
    pub category_id: SemanticId,
    pub platform: PeerPlatform,
}

/// Immutable, trusted installed configuration. Zones must be validated against the
/// native IANA database before supplying this context; no filesystem/env fallback.
pub struct ConfigurationContext<'a> {
    pub calendar_zones: &'a [CalendarZone],
    pub metrics: &'a [MetricSupport],
    pub projection_catalog_sha256: Option<&'a Digest>,
}

/// Explicit base and extension selections, not the old highest-version dispatcher.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Negotiation {
    pub base: u16,
    pub iphone_query_v3: bool,
    pub agent_v4: bool,
}

/// Pure opt-in negotiation; does not change installed hello version lists.
/// # Errors
/// Android without base 2 (Apple without base 1) fails closed.
pub fn negotiate(
    platform: &PeerPlatform,
    host: &[i32],
    source: &[i32],
    compatible_iphone_query: bool,
) -> Result<Negotiation, Error> {
    let base = if *platform == PeerPlatform::Apple {
        1
    } else {
        2
    };
    ensure(
        host.contains(&base) && source.contains(&base),
        Error::UnsupportedCapability,
    )?;
    Ok(Negotiation {
        base: u16::try_from(base).map_err(|_| Error::InvalidRequest)?,
        iphone_query_v3: *platform == PeerPlatform::Apple
            && compatible_iphone_query
            && host.contains(&3)
            && source.contains(&3),
        agent_v4: host.contains(&4) && source.contains(&4),
    })
}

macro_rules! documents {
    ($($variant:ident($ty:ident) => $schema:literal),+ $(,)?) => {
        /// Closed supported document boundary. JSON descriptions never create grants.
        #[derive(Clone, Debug, Eq, PartialEq, Serialize)]
        #[serde(untagged)]
        pub enum Document { $( $variant(Box<$ty>), )+ }
        impl ValidateShape for Document {
            fn validate_shape(&self) -> Result<(), Error> { match self { $( Self::$variant(value) => value.validate_shape(), )+ } }
        }
        /// Decode supported typed documents with raw rejection and schema bounds.
        /// Contextual semantics must be checked separately before native use.
        /// # Errors
        /// Unknown/unimplemented schemas reject; malformed supported schemas fail health-free.
        pub fn decode_document(raw: &[u8]) -> Result<Document, Error> {
            let tree = parse_strict(raw)?;
            match tree.get("schema").and_then(Value::as_str) {
                $(Some($schema) => Ok(Document::$variant(Box::new(decode_typed(raw)?))),)+
                Some(_) => Err(Error::UnsupportedCapability), None => Err(Error::InvalidRequest),
            }
        }
    };
}
documents! {
    Intent(ExportIntent) => "healthmd.agent_export_intent",
    Plan(ExportPlan) => "healthmd.agent_export_plan",
    DiscoveryRequest(DiscoveryRequest) => "healthmd.agent_discovery_request",
    Discovery(Discovery) => "healthmd.agent_discovery",
    PlanRequest(PlanRequest) => "healthmd.agent_plan_request",
    ApprovalRequest(ApprovalRequest) => "healthmd.agent_approval_request",
    Approval(Approval) => "healthmd.agent_approval",
    Execute(ExecuteRequest) => "healthmd.agent_execute_request",
    Cancel(CancelRequest) => "healthmd.agent_cancel_request",
    Resume(ResumeRequest) => "healthmd.agent_resume_request",
    Manifest(ArtifactManifest) => "healthmd.agent_artifact_manifest",
    Commit(CommitReceipt) => "healthmd.agent_commit_receipt",
    Receipt(ExecutionReceipt) => "healthmd.agent_execution_receipt",
    Authority(Authority) => "healthmd.agent_authority",
    Delegation(ExportDelegation) => "healthmd.agent_export_delegation",
    QueryCatalog(QueryCatalog) => "healthmd.source_query_catalog",
    Rejected(AgentError) => "healthmd.agent_error",
}

/// Only this coherent subset of envelopes is implemented. Other reviewed
/// discriminators reject as unsupported, never enter a generic forwarding map.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(
    tag = "type",
    content = "payload",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum Message {
    DiscoveryRequest(Box<DiscoveryRequest>),
    DiscoveryResponse(Box<Discovery>),
    PlanRequest(Box<PlanRequest>),
    PlanResponse(Box<ExportPlan>),
    ApprovalRequest(Box<ApprovalRequest>),
    ApprovalResponse(Box<Approval>),
    ExecuteRequest(Box<ExecuteRequest>),
    ExecutionReceipt(Box<ExecutionReceipt>),
    CancelRequest(Box<CancelRequest>),
    ResumeRequest(Box<ResumeRequest>),
    ArtifactManifest(Box<ArtifactManifest>),
    CommitReceipt(Box<CommitReceipt>),
    Rejected(Box<AgentError>),
}
impl ValidateShape for Message {
    fn validate_shape(&self) -> Result<(), Error> {
        match self {
            Self::DiscoveryRequest(v) => v.validate_shape(),
            Self::DiscoveryResponse(v) => v.validate_shape(),
            Self::PlanRequest(v) => v.validate_shape(),
            Self::PlanResponse(v) => v.validate_shape(),
            Self::ApprovalRequest(v) => v.validate_shape(),
            Self::ApprovalResponse(v) => v.validate_shape(),
            Self::ExecuteRequest(v) => v.validate_shape(),
            Self::ExecutionReceipt(v) => v.validate_shape(),
            Self::CancelRequest(v) => v.validate_shape(),
            Self::ResumeRequest(v) => v.validate_shape(),
            Self::ArtifactManifest(v) => v.validate_shape(),
            Self::CommitReceipt(v) => v.validate_shape(),
            Self::Rejected(v) => v.validate_shape(),
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Envelope {
    pub protocol_version: u64,
    #[serde(flatten)]
    pub message: Message,
}
impl Envelope {
    #[must_use]
    pub const fn new(message: Message) -> Self {
        Self {
            protocol_version: 4,
            message,
        }
    }
}

/// Decode only after independent v4 negotiation, with an exact outer field set.
/// # Errors
/// Old peers are rejected before even a discovery probe; unsupported branches fail closed.
pub fn decode_envelope(raw: &[u8], negotiation: Negotiation) -> Result<Envelope, Error> {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Raw {
        protocol_version: u64,
        #[serde(rename = "type")]
        kind: String,
        payload: Value,
    }
    ensure(negotiation.agent_v4, Error::UnsupportedCapability)?;
    let value = parse_strict(raw)?;
    super::reject_nulls(&value, None)?;
    let root: Raw = serde_json::from_value(value).map_err(|_| Error::InvalidRequest)?;
    shape(root.protocol_version == 4)?;
    if root.kind.starts_with("control_")
        || [
            "query_request",
            "query_response",
            "query_cancel",
            "query_cancelled",
        ]
        .contains(&root.kind.as_str())
    {
        return Err(Error::UnsupportedCapability);
    }
    let message: Message =
        serde_json::from_value(serde_json::json!({"type":root.kind,"payload":root.payload}))
            .map_err(|_| Error::InvalidRequest)?;
    message.validate_shape()?;
    Ok(Envelope::new(message))
}

pub(crate) fn digest<T: Serialize + ?Sized>(value: &T) -> Result<Digest, Error> {
    Ok(Digest(sha256_hex(&canonical_json(value)?)))
}
fn excluding<T: Serialize>(value: &T, fields: &[&str]) -> Result<Digest, Error> {
    let mut tree = serde_json::to_value(value).map_err(|_| Error::InvalidRequest)?;
    let object = tree.as_object_mut().ok_or(Error::InvalidRequest)?;
    for field in fields {
        object.remove(*field);
    }
    digest(&tree)
}

/// Discovery capability digest excludes only its four explicitly volatile fields.
/// # Errors
/// Returns a fixed encoding error.
pub fn capability_digest(discovery: &Discovery) -> Result<Digest, Error> {
    excluding(
        discovery,
        &["capability_sha256", "request_id", "issued_at", "expires_at"],
    )
}

fn lifetime(issued: &UtcTimestamp, expires: &UtcTimestamp) -> Result<(), Error> {
    let delta = expires.seconds()? - issued.seconds()?;
    ensure(delta > 0 && delta <= 600, Error::PlanExpired)
}
fn zone(zone: &CalendarZone, context: &ConfigurationContext<'_>) -> Result<(), Error> {
    zone.validate_shape()?;
    ensure(context.calendar_zones.contains(zone), Error::InvalidRequest)
}

/// Freeze relative dates from a configuration anchor; `all_available` remains logical.
/// # Errors
/// Rejects invalid/reversed/out-of-range Gregorian civil bounds.
pub fn resolve_dates(dates: &Dates) -> Result<Dates, Error> {
    dates.validate_shape()?;
    match dates {
        Dates::Exact { range } => {
            shape(civil(&range.start_date.0)? <= civil(&range.end_date.0)?)?;
            Ok(dates.clone())
        }
        Dates::AllAvailable {} => Ok(dates.clone()),
        Dates::PastCompleteDays { anchor_date, days } => {
            let anchor = civil(&anchor_date.0)?;
            let start = anchor
                .checked_sub_signed(Duration::days(
                    i64::try_from(*days).map_err(|_| Error::InvalidRequest)?,
                ))
                .ok_or(Error::InvalidRequest)?;
            let end = anchor
                .checked_sub_signed(Duration::days(1))
                .ok_or(Error::InvalidRequest)?;
            shape((1..=9999).contains(&start.year()))?;
            Ok(Dates::Exact {
                range: Range {
                    start_date: CivilDate(start.to_string()),
                    end_date: CivilDate(end.to_string()),
                },
            })
        }
    }
}

/// Resolve one exact installed platform registry union. Never widen provider/source scope.
/// # Errors
/// Unknown/unavailable metrics/categories reject before native reads.
pub fn resolve_selection(
    selection: &Selection,
    platform: &PeerPlatform,
    context: &ConfigurationContext<'_>,
) -> Result<Vec<SemanticId>, Error> {
    selection.validate_shape()?;
    for ids in [
        &selection.metric_ids,
        &selection.category_ids,
        &selection.source_ids,
        &selection.provider_ids,
    ] {
        sorted(ids)?;
    }
    let source = if *platform == PeerPlatform::Apple {
        "apple_health"
    } else {
        "health_connect"
    };
    ensure(
        selection.source_ids == [SemanticId(source.to_owned())]
            && selection.provider_ids.is_empty(),
        Error::UnsupportedCapability,
    )?;
    let rows: Vec<_> = context
        .metrics
        .iter()
        .filter(|row| row.platform == *platform)
        .collect();
    let mut metrics = BTreeSet::new();
    for id in &selection.metric_ids {
        ensure(
            rows.iter().any(|row| row.metric_id == *id),
            Error::UnsupportedMetric,
        )?;
        metrics.insert(id.clone());
    }
    for category in &selection.category_ids {
        let matches: Vec<_> = rows
            .iter()
            .filter(|row| row.category_id == *category)
            .collect();
        ensure(!matches.is_empty(), Error::UnsupportedMetric)?;
        metrics.extend(matches.into_iter().map(|row| row.metric_id.clone()));
    }
    if selection.all_metrics {
        metrics.extend(rows.into_iter().map(|row| row.metric_id.clone()));
    }
    ensure(
        !metrics.is_empty() && metrics.len() <= 256,
        Error::UnsupportedMetric,
    )?;
    Ok(metrics.into_iter().collect())
}

/// Explicit output dialect checks; no native saved preference is consulted or changed.
/// # Errors
/// Rejects platform/profile mismatch, unsafe paths, reserved machine fields and hidden modes.
pub fn validate_output_settings(
    settings: &OutputSettings,
    platform: &PeerPlatform,
) -> Result<(), Error> {
    use OutputSettingsOutputProfile as Profile;
    settings.validate_shape()?;
    sorted(&settings.formats)?;
    ensure(
        (settings.output_profile == Profile::AppleV8) == (*platform == PeerPlatform::Apple),
        Error::UnsupportedCapability,
    )?;
    for (path, filename) in [
        (&settings.subfolder.0, false),
        (&settings.folder_template.0, false),
        (&settings.filename_template.0, true),
        (&settings.daily_notes.folder_template.0, false),
        (&settings.daily_notes.filename_template.0, true),
    ] {
        super::validate_relative_path(path, filename, DAILY_TOKENS)?;
    }
    super::validate_relative_path(
        &settings.individual_entries.folder_template.0,
        false,
        ENTRY_TOKENS,
    )?;
    super::validate_relative_path(
        &settings.individual_entries.filename_template.0,
        true,
        ENTRY_TOKENS,
    )?;
    if let Packaging::Zip {
        filename_template, ..
    } = &settings.packaging
    {
        super::validate_relative_path(&filename_template.0, true, DAILY_TOKENS)?;
    }
    if let Dictionary::ProfileDictionaryV1 {
        filename_template, ..
    } = &settings.dictionary
    {
        super::validate_relative_path(&filename_template.0, true, DAILY_TOKENS)?;
    }
    if matches!(
        settings.write_mode,
        OutputSettingsWriteMode::MergeMarkdown
            | OutputSettingsWriteMode::MergeMarkdownPreservingPreamble
    ) {
        ensure(
            settings.formats == [OutputSettingsFormatsItem::Markdown],
            Error::UnsupportedCapability,
        )?;
    }
    shape(!settings.daily_notes.only || settings.daily_notes.enabled)?;
    sorted(&settings.individual_entries.metric_ids)?;
    sorted(&settings.daily_notes.section_ids)?;
    let fields = &settings.presentation.frontmatter.custom_fields;
    shape(unique(&fields.iter().map(|f| &f.key).collect::<Vec<_>>()))?;
    shape(fields.iter().all(|f| {
        ![
            "schema",
            "schema_version",
            "units",
            "raw_capture_status",
            "time_context",
        ]
        .contains(&f.key.0.as_str())
    }))?;
    Ok(())
}

/// Pure intent consistency against trusted compiled configuration.
/// # Errors
/// Rejects mismatched peer/root, unsupported archive and any unavailable selection.
pub fn validate_export_intent(
    intent: &ExportIntent,
    context: &ConfigurationContext<'_>,
) -> Result<Vec<SemanticId>, Error> {
    intent.validate_shape()?;
    ensure(
        intent.destination.host_installation_id == intent.peer.host_installation_id,
        Error::BindingChanged,
    )?;
    zone(&intent.calendar_timezone, context)?;
    resolve_dates(&intent.dates)?;
    let metrics = resolve_selection(
        &intent.capture_scope.selection,
        &intent.peer.platform,
        context,
    )?;
    match &intent.capture_scope.native_archive {
        Archive::None {} => (),
        Archive::AppleHealthkitCanonicalV1 {} => ensure(
            intent.peer.platform == PeerPlatform::Apple,
            Error::UnsupportedCapability,
        )?,
        Archive::AndroidProviderNativeSnapshotV1 {
            provider_id,
            record_scope,
            ..
        } => {
            ensure(
                intent.peer.platform == PeerPlatform::Android && provider_id.0 == "health_connect",
                Error::UnsupportedCapability,
            )?;
            if *record_scope
                == ArchiveAndroidProviderNativeSnapshotV1RecordScope::AllAuthorizedSupported
            {
                ensure(
                    intent.capture_scope.selection.all_metrics,
                    Error::BindingChanged,
                )?;
            }
        }
    }
    if let Policy::Explicit { settings } = &intent.settings_policy {
        validate_output_settings(settings, &intent.peer.platform)?;
    }
    Ok(metrics)
}

/// Full digest of immutable settings; scope contains dates/capture/metrics/product.
/// # Errors
/// Returns a fixed encoding error.
pub fn export_scope_digest(
    intent: &ExportIntent,
    dates: &Dates,
    metrics: &[SemanticId],
) -> Result<Digest, Error> {
    digest(
        &serde_json::json!({"dates":dates,"calendar_timezone":intent.calendar_timezone,
        "capture_scope":intent.capture_scope,"metric_ids":metrics,"product":intent.product}),
    )
}
/// Plan digest excludes only its own field.
/// # Errors
/// Returns a fixed encoding error.
pub fn plan_digest(plan: &ExportPlan) -> Result<Digest, Error> {
    excluding(plan, &["plan_sha256"])
}

/// Complete deterministic leaf origins, including disabled settings and capture axes.
/// Arrays preserve presentation order and have one origin each.
/// # Errors
/// Returns a fixed encoding/shape error.
pub fn setting_origins(
    intent: &ExportIntent,
    settings: &OutputSettings,
) -> Result<Vec<Origin>, Error> {
    let (origin, revision) = match &intent.settings_policy {
        Policy::Explicit { .. } => (OriginOrigin::Request, 0),
        Policy::SavedDeviceSettings { expected_revision } => {
            (OriginOrigin::SavedDeviceSettings, *expected_revision)
        }
        Policy::Profile {
            expected_revision, ..
        } => (OriginOrigin::Profile, *expected_revision),
    };
    let mut pointers = Vec::new();
    leaves(
        &serde_json::to_value(settings).map_err(|_| Error::InvalidRequest)?,
        "/effective_settings",
        &mut pointers,
    );
    let mut origins: Vec<_> = pointers
        .into_iter()
        .map(|pointer| Origin {
            pointer,
            origin: origin.clone(),
            revision,
        })
        .collect();
    let mut capture = Vec::new();
    leaves(
        &serde_json::to_value(&intent.capture_scope).map_err(|_| Error::InvalidRequest)?,
        "/capture_scope",
        &mut capture,
    );
    origins.extend(capture.into_iter().map(|pointer| Origin {
        pointer,
        origin: OriginOrigin::Request,
        revision: 0,
    }));
    origins.push(Origin {
        pointer: "/resolved_dates".to_owned(),
        origin: OriginOrigin::ResolvedCalendar,
        revision: 0,
    });
    origins.push(Origin {
        pointer: "/calendar_timezone".to_owned(),
        origin: OriginOrigin::Request,
        revision: 0,
    });
    origins.sort_by(|a, b| a.pointer.cmp(&b.pointer));
    Ok(origins)
}
fn leaves(value: &Value, prefix: &str, out: &mut Vec<String>) {
    if let Value::Object(object) = value {
        for (key, value) in object {
            leaves(value, &format!("{prefix}/{key}"), out);
        }
    } else {
        out.push(prefix.to_owned());
    }
}

/// Validate self-consistency only; a correct plan digest is not an issued plan.
/// # Errors
/// Rejects changed scope/settings/revisions/origins/paths and health-read claims.
pub fn validate_export_plan(
    plan: &ExportPlan,
    context: &ConfigurationContext<'_>,
) -> Result<(), Error> {
    plan.validate_shape()?;
    let metrics = validate_export_intent(&plan.intent, context)?;
    validate_output_settings(&plan.effective_settings, &plan.intent.peer.platform)?;
    ensure(
        plan.resolved_metric_ids == metrics
            && plan.resolved_dates == resolve_dates(&plan.intent.dates)?,
        Error::BindingChanged,
    )?;
    ensure(
        plan.settings_sha256 == digest(&plan.effective_settings)?
            && plan.scope_sha256
                == export_scope_digest(&plan.intent, &plan.resolved_dates, &metrics)?
            && plan.plan_sha256 == plan_digest(plan)?,
        Error::BindingChanged,
    )?;
    lifetime(&plan.issued_at, &plan.expires_at)?;
    validate_reference_issuers(&plan.authority_references)?;
    validate_revisions(&plan.revisions)?;
    let settings = &plan.effective_settings;
    if settings.individual_entries.enabled {
        ensure(
            !settings.individual_entries.metric_ids.is_empty()
                && settings
                    .individual_entries
                    .metric_ids
                    .iter()
                    .all(|id| metrics.contains(id)),
            Error::BindingChanged,
        )?;
        ensure(
            !matches!(plan.intent.capture_scope.native_archive, Archive::None {}),
            Error::UnsupportedCapability,
        )?;
    }
    ensure(
        plan.predicted_paths == super::predicted_paths(&plan.intent, settings)?,
        Error::BindingChanged,
    )?;
    if matches!(plan.resolved_dates, Dates::AllAvailable {}) {
        ensure(
            plan.path_prediction == ExportPlanPathPrediction::TemplateOnlyAllAvailable
                && plan
                    .limitations
                    .iter()
                    .any(|s| s.0 == "history_bounds_unresolved"),
            Error::BindingChanged,
        )?;
    } else if settings.individual_entries.enabled {
        ensure(
            plan.path_prediction == ExportPlanPathPrediction::DeferredNativeEntries
                && plan
                    .limitations
                    .iter()
                    .any(|s| s.0 == "entry_paths_unresolved"),
            Error::BindingChanged,
        )?;
    } else {
        ensure(
            plan.path_prediction == ExportPlanPathPrediction::ExactRequestedDays,
            Error::BindingChanged,
        )?;
    }
    validate_plan_origins_and_policy(plan)
}
fn validate_plan_origins_and_policy(plan: &ExportPlan) -> Result<(), Error> {
    let settings = &plan.effective_settings;
    match &plan.intent.settings_policy {
        Policy::Explicit { settings } => {
            ensure(plan.effective_settings == **settings, Error::BindingChanged)?;
        }
        Policy::SavedDeviceSettings { expected_revision } => policy_pin(
            plan,
            &RevisionDomain::DeviceSettings,
            *expected_revision,
            None,
        )?,
        Policy::Profile {
            expected_revision,
            profile_id,
        } => policy_pin(
            plan,
            &RevisionDomain::NativeProfile,
            *expected_revision,
            Some(profile_id),
        )?,
    }
    let mut origins = plan.origins.clone();
    origins.sort_by(|a, b| a.pointer.cmp(&b.pointer));
    let expected = setting_origins(&plan.intent, settings)?;
    shape(
        origins.iter().map(|o| &o.pointer).collect::<Vec<_>>()
            == expected.iter().map(|o| &o.pointer).collect::<Vec<_>>(),
    )?;
    for (got, want) in origins.iter().zip(expected) {
        ensure(got.origin == want.origin, Error::BindingChanged)?;
        if matches!(
            want.origin,
            OriginOrigin::Profile | OriginOrigin::SavedDeviceSettings
        ) {
            ensure(got.revision == want.revision, Error::RevisionConflict)?;
        } else {
            shape(got.revision == 0)?;
        }
    }
    Ok(())
}
fn policy_pin(
    plan: &ExportPlan,
    domain: &RevisionDomain,
    revision: u64,
    object: Option<&ControlUuid>,
) -> Result<(), Error> {
    let pins: Vec<_> = plan
        .revisions
        .iter()
        .filter(|pin| pin.domain == *domain)
        .collect();
    ensure(
        pins.len() == 1
            && pins[0].revision == revision
            && object.is_none_or(|id| pins[0].object_id == *id),
        Error::RevisionConflict,
    )
}
fn validate_revisions(revisions: &[Revision]) -> Result<(), Error> {
    let keys: Vec<_> = revisions
        .iter()
        .map(|pin| (token(&pin.domain), pin.object_id.0.clone()))
        .collect();
    shape(keys.windows(2).all(|pair| pair[0] < pair[1]))
}
fn validate_reference_issuers(refs: &AuthorityReferences) -> Result<(), Error> {
    shape(
        refs.native.issuer == AuthorityReferenceIssuer::NativeSource
            && refs.host.issuer == AuthorityReferenceIssuer::AuthorizedHost,
    )
}
pub(crate) fn token<T: Serialize>(value: &T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_default()
}

/// Exact approval binding; no ID, scope or expiry is widened.
#[must_use]
pub fn approval_binding(plan: &ExportPlan) -> Binding {
    Binding {
        peer: plan.intent.peer.clone(),
        destination: plan.intent.destination.clone(),
        authority_references: plan.authority_references.clone(),
        capability_sha256: plan.capability_sha256.clone(),
        expires_at: plan.expires_at.clone(),
        revisions: plan.revisions.clone(),
        plan_sha256: plan.plan_sha256.clone(),
        scope_sha256: plan.scope_sha256.clone(),
        settings_sha256: plan.settings_sha256.clone(),
    }
}

/// Health-free static catalog consistency, not installed provider qualification.
/// # Errors
/// Rejects missing/cross-platform native IDs and duplicate semantic IDs.
pub fn validate_query_catalog(catalog: &QueryCatalog) -> Result<(), Error> {
    catalog.validate_shape()?;
    shape(unique(
        &catalog
            .metrics
            .iter()
            .map(|row| &row.metric_id)
            .collect::<Vec<_>>(),
    ))?;
    for row in &catalog.metrics {
        if token(&row.availability) != "unavailable" {
            shape(row.native_record_type.is_some())?;
        }
        if token(&catalog.source_id) == "health_connect" {
            if let Some(native) = &row.native_record_type {
                shape(
                    native
                        .0
                        .starts_with("androidx.health.connect.client.records."),
                )?;
            }
            // Preserve the reviewed SDNN/RMSSD distinction, never convert aliases into evidence.
            if row.metric_id.0 == "hrv" {
                shape(token(&row.availability) == "unavailable")?;
            }
        }
    }
    Ok(())
}

/// Capability description consistency, including digest/expiry and no host-owned refs.
/// # Errors
/// Rejects changes, invalid feature/catalog combinations and unsupported IANA zones.
pub fn validate_discovery(
    discovery: &Discovery,
    context: &ConfigurationContext<'_>,
) -> Result<(), Error> {
    discovery.validate_shape()?;
    lifetime(&discovery.issued_at, &discovery.expires_at)?;
    zone(&discovery.source_calendar_timezone, context)?;
    ensure(
        discovery.capability_sha256 == capability_digest(discovery)?,
        Error::BindingChanged,
    )?;
    sorted(&discovery.features)?;
    sorted(&discovery.settings_policies)?;
    sorted(&discovery.output_profiles)?;
    sorted(&discovery.query_operations)?;
    sorted(&discovery.control_operations)?;
    sorted(&discovery.projection_products)?;
    let support = &discovery.output_support;
    sorted(&support.formats)?;
    sorted(&support.write_modes)?;
    sorted(&support.compatibility_detail)?;
    sorted(&support.native_archive_products)?;
    sorted(&support.setting_pointers)?;
    sorted(&support.path_tokens)?;
    shape(
        discovery
            .authority_references
            .iter()
            .all(|r| r.issuer == AuthorityReferenceIssuer::NativeSource),
    )?;
    shape(unique(
        &discovery
            .authority_references
            .iter()
            .map(|r| &r.authority_id)
            .collect::<Vec<_>>(),
    ))?;
    let projection = discovery
        .features
        .contains(&DiscoveryFeaturesItem::SourceProjection);
    shape(projection != discovery.projection_products.is_empty())?;
    if projection {
        let catalog = discovery
            .projection_source_catalog
            .as_ref()
            .ok_or(Error::InvalidRequest)?;
        validate_query_catalog(catalog)?;
        shape(catalog.peer == discovery.peer && token(&catalog.source_id) == "health_connect")?;
        shape(context.projection_catalog_sha256 == Some(&discovery.projection_catalog_sha256))?;
        let coverage = &catalog.history;
        shape(
            coverage.days_considered == 0
                && coverage.days_with_values == 0
                && coverage.missing_count == 0
                && coverage.missing.is_empty(),
        )?;
    } else {
        shape(
            discovery.projection_catalog_sha256.0 == "0".repeat(64)
                && discovery.projection_source_catalog.is_none(),
        )?;
    }
    if !discovery
        .features
        .contains(&DiscoveryFeaturesItem::SourceQuery)
    {
        shape(
            discovery.query_catalog_sha256.0 == "0".repeat(64)
                && discovery.query_operations.is_empty(),
        )?;
    }
    Ok(())
}

/// Digest-bound commit identity, excluding peer/schema/status exactly as specified.
/// # Errors
/// Returns a fixed encoding error.
pub fn commit_key(receipt: &CommitReceipt) -> Result<Digest, Error> {
    digest(
        &serde_json::json!({"job_id":receipt.job_id,"artifact_id":receipt.artifact_id,"destination":receipt.destination,
        "request_sha256":receipt.request_sha256,"manifest_sha256":receipt.manifest_sha256,"relative_path":receipt.relative_path,
        "write_mode":receipt.write_mode,"input_sha256":receipt.input_sha256,"before_sha256":receipt.before_sha256,"after_sha256":receipt.after_sha256}),
    )
}
/// Commit description/replay consistency only, not native atomic-write evidence.
/// # Errors
/// Changed identity/bytes reject; Unicode paths are fail-closed in this increment.
pub fn validate_commit_receipt(
    receipt: &CommitReceipt,
    persisted: Option<&CommitReceipt>,
) -> Result<(), Error> {
    receipt.validate_shape()?;
    super::validate_relative_path(&receipt.relative_path.0, false, &[])?;
    ensure(
        receipt.destination.host_installation_id == receipt.peer.host_installation_id,
        Error::BindingChanged,
    )?;
    ensure(
        receipt.commit_key == commit_key(receipt)?,
        Error::BindingChanged,
    )?;
    if let Some(previous) = persisted {
        ensure(
            receipt.peer == previous.peer
                && receipt.commit_key == previous.commit_key
                && commit_key(receipt)? == commit_key(previous)?,
            Error::BindingChanged,
        )?;
    }
    Ok(())
}
/// Manifest metadata consistency only; preserved artifact-byte validation is not implemented.
/// # Errors
/// Rejects contradictory completeness/collisions and unsupported projection artifacts.
pub fn validate_artifact_manifest(manifest: &ArtifactManifest) -> Result<(), Error> {
    manifest.validate_shape()?;
    validate_reference_issuers(&manifest.binding.authority_references)?;
    shape(unique(
        &manifest
            .branch_statuses
            .iter()
            .map(|b| &b.selector_id)
            .collect::<Vec<_>>(),
    ))?;
    let mut paths = Vec::new();
    let mut ids = Vec::new();
    for artifact in &manifest.artifacts {
        let Artifact::Branch1(artifact) = artifact else {
            return Err(Error::UnsupportedCapability);
        };
        paths.push(artifact.relative_path.clone());
        ids.push(&artifact.artifact_id);
        let profile = token(&artifact.profile);
        if profile == "apple-v8" || profile == "apple-healthkit-canonical-v1" {
            shape(manifest.binding.peer.platform == PeerPlatform::Apple)?;
        }
        if profile.starts_with("android-") {
            shape(manifest.binding.peer.platform == PeerPlatform::Android)?;
        }
    }
    shape(unique(&ids))?;
    super::validate_path_collisions(&paths)?;
    if matches!(
        manifest.capture_status,
        ArtifactManifestCaptureStatus::Complete | ArtifactManifestCaptureStatus::CompleteEmpty
    ) {
        shape(
            manifest
                .branch_statuses
                .iter()
                .all(|b| b.status == ArtifactManifestBranchStatusesItemStatus::Success),
        )?;
    }
    if manifest.capture_status == ArtifactManifestCaptureStatus::CompleteEmpty {
        shape(manifest.artifacts.is_empty())?;
    }
    Ok(())
}
/// Only source acknowledgement makes completion/cancellation terminal.
/// # Errors
/// Contradictory terminal states fail health-free.
pub fn validate_execution_receipt(receipt: &ExecutionReceipt) -> Result<(), Error> {
    receipt.validate_shape()?;
    validate_reference_issuers(&receipt.binding.authority_references)?;
    if matches!(
        receipt.status,
        ExecutionReceiptStatus::Complete
            | ExecutionReceiptStatus::CompleteEmpty
            | ExecutionReceiptStatus::Cancelled
    ) {
        shape(receipt.source_acknowledged)?;
    }
    if receipt.status == ExecutionReceiptStatus::CompleteEmpty {
        shape(receipt.artifact_count == 0)?;
    }
    Ok(())
}
/// Exact immutable-journal comparison; no spool regeneration or expiry renewal.
/// # Errors
/// Any changed field rejects. Spool/grant/expiry/transfer checks remain native obligations.
pub fn validate_resume(request: &ResumeRequest, journal: &ResumeRequest) -> Result<(), Error> {
    request.validate_shape()?;
    journal.validate_shape()?;
    ensure(request == journal, Error::BindingChanged)
}
