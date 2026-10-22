//! Pure checks over issuer-owned immutable snapshots. No JSON store/enrollment API.
use super::semantics::scalars::civil;
use super::semantics::{digest, token};
use super::{
    ApprovalRequest, Archive, Authority, AuthorityConfigurationProtection, AuthorityReference,
    AuthorityReferenceIssuer, AuthorityReferences, AuthorityRightsItem, AuthoritySchema,
    ConfigurationContext, ControlUuid, Dates, Destination, Dictionary, Digest, Discovery,
    DiscoveryEntitlement, DiscoveryFeaturesItem, DiscoverySettingsPoliciesItem, Error,
    ExecuteRequest, ExportDelegation, ExportDelegationBoundsDatePolicy,
    ExportDelegationBoundsDestinationPolicy, ExportDelegationBoundsProductsItem,
    ExportDelegationRightsItem, ExportIntent, ExportPlan, OutputSettings,
    OutputSupportNativeArchiveProductsItem, Packaging, Peer, PlanRequest, Policy, Revision,
    RevisionDomain, SemanticId, UtcTimestamp, ValidateShape, approval_binding, ensure,
    resolve_dates, shape, sorted, validate_discovery, validate_export_intent, validate_export_plan,
    validate_output_settings,
};
use serde::Serialize;

/// Atomic accepted index supplied by the native journal, never decoded from a request.
#[derive(Clone, Debug)]
pub struct AcceptedExecution {
    pub peer: Peer,
    pub destination: Destination,
    pub job_id: ControlUuid,
    pub idempotency_key: ControlUuid,
    pub request_sha256: Digest,
}

/// Native/host private-store snapshots supplied by a trusted adapter. This type
/// intentionally has no serde implementation. Caller DTOs cannot populate stores.
/// Atomic acceptance/CAS, live revocation/trust/readiness, native gates, expiry and
/// retained spools are still adapter responsibilities, not implied by these checks.
pub struct ExportStoreContext<'a> {
    pub configuration: ConfigurationContext<'a>,
    pub now: &'a UtcTimestamp,
    pub capabilities: &'a Discovery,
    pub native_delegations: &'a [ExportDelegation],
    pub host_delegations: &'a [ExportDelegation],
    pub registered_destinations: &'a [Destination],
    pub issued_plans: &'a [(ControlUuid, Digest)],
    pub issued_approvals: &'a [(ControlUuid, Digest)],
    pub issued_approval_ids: &'a [ControlUuid],
    pub native_authority: &'a Authority,
    pub host_authority: &'a Authority,
    pub current_peer: &'a Peer,
    pub current_destination: &'a Destination,
    pub current_capability_sha256: &'a Digest,
    pub current_revisions: &'a [Revision],
    pub approved_binding_sha256: Option<&'a Digest>,
    pub accepted: Option<&'a AcceptedExecution>,
}

/// Pure sanitized reference derivation; does not issue/store authority.
/// # Errors
/// Returns a fixed encoding error.
pub fn delegation_reference(delegation: &ExportDelegation) -> Result<AuthorityReference, Error> {
    Ok(AuthorityReference {
        authority_id: delegation.authority_id.clone(),
        issuer: delegation.issuer.clone(),
        grant_revision: delegation.grant_revision,
        grant_sha256: digest(delegation)?,
    })
}

/// Bounded sanitized delegation grammar, not a grant-creation request.
/// # Errors
/// Rejects contradictory issuer policies, unsorted bounds and invalid zones/dates.
pub fn validate_export_delegation(
    delegation: &ExportDelegation,
    context: &ConfigurationContext<'_>,
) -> Result<(), Error> {
    delegation.validate_shape()?;
    sorted(&delegation.rights)?;
    let bounds = &delegation.bounds;
    sorted(&bounds.products)?;
    sorted(&bounds.projection_details)?;
    sorted(&bounds.projection_object_ids)?;
    sorted(&bounds.projection_field_ids)?;
    sorted(&bounds.metric_ids)?;
    sorted(&bounds.calendar_timezones)?;
    sorted(&bounds.formats)?;
    sorted(&bounds.output_profiles)?;
    sorted(&bounds.write_modes)?;
    sorted(&bounds.compatibility_detail)?;
    sorted(&bounds.native_archive_products)?;
    for zone in &bounds.calendar_timezones {
        shape(context.calendar_zones.contains(zone))?;
    }
    match (&delegation.issuer, &bounds.destination_policy) {
        (
            AuthorityReferenceIssuer::NativeSource,
            ExportDelegationBoundsDestinationPolicy::AuthenticatedHostBindings {},
        ) => (),
        (
            AuthorityReferenceIssuer::AuthorizedHost,
            ExportDelegationBoundsDestinationPolicy::RegisteredHostBindings { binding_ids },
        ) => sorted(binding_ids)?,
        _ => return Err(Error::InvalidRequest),
    }
    if let ExportDelegationBoundsDatePolicy::BoundedExact { range, .. } = &bounds.date_policy {
        shape(civil(&range.start_date.0)? <= civil(&range.end_date.0)?)?;
    }
    Ok(())
}

fn subset<T: PartialEq>(wanted: &[T], allowed: &[T]) -> bool {
    wanted.iter().all(|item| allowed.contains(item))
}
fn check_delegated_scope(
    delegation: &ExportDelegation,
    intent: &ExportIntent,
    effective: &OutputSettings,
    metrics: &[SemanticId],
    context: &ExportStoreContext<'_>,
    right: &ExportDelegationRightsItem,
) -> Result<(), Error> {
    validate_export_delegation(delegation, &context.configuration)?;
    ensure(delegation.peer == intent.peer, Error::BindingChanged)?;
    ensure(
        delegation.rights.contains(right)
            && delegation.expires_at.seconds()? > context.now.seconds()?,
        Error::ApprovalRequired,
    )?;
    let b = &delegation.bounds;
    ensure(
        subset(metrics, &b.metric_ids) && b.calendar_timezones.contains(&intent.calendar_timezone),
        Error::ApprovalRequired,
    )?;
    ensure(
        b.products
            .contains(&ExportDelegationBoundsProductsItem::GeneratedFiles)
            && subset(&effective.formats, &b.formats)
            && b.output_profiles.contains(&effective.output_profile)
            && b.write_modes.contains(&effective.write_mode),
        Error::ApprovalRequired,
    )?;
    let archive = match intent.capture_scope.native_archive {
        Archive::None {} => OutputSupportNativeArchiveProductsItem::None,
        Archive::AppleHealthkitCanonicalV1 {} => {
            OutputSupportNativeArchiveProductsItem::AppleHealthkitCanonicalV1
        }
        Archive::AndroidProviderNativeSnapshotV1 { .. } => {
            OutputSupportNativeArchiveProductsItem::AndroidProviderNativeSnapshotV1
        }
    };
    ensure(
        b.compatibility_detail
            .contains(&intent.capture_scope.compatibility_detail)
            && b.native_archive_products.contains(&archive),
        Error::ApprovalRequired,
    )?;
    match resolve_dates(&intent.dates)? {
        Dates::AllAvailable {} => ensure(
            matches!(
                b.date_policy,
                ExportDelegationBoundsDatePolicy::AuthorizedHistory {
                    allow_all_available: true,
                    ..
                }
            ),
            Error::ApprovalRequired,
        )?,
        Dates::Exact { range } => {
            let start = civil(&range.start_date.0)?;
            let end = civil(&range.end_date.0)?;
            let max_days = match &b.date_policy {
                ExportDelegationBoundsDatePolicy::BoundedExact {
                    range: allowed,
                    max_days,
                } => {
                    ensure(
                        civil(&allowed.start_date.0)? <= start
                            && end <= civil(&allowed.end_date.0)?,
                        Error::ApprovalRequired,
                    )?;
                    *max_days
                }
                ExportDelegationBoundsDatePolicy::AuthorizedHistory { max_days, .. } => *max_days,
            };
            ensure(
                u64::try_from((end - start).num_days() + 1).map_err(|_| Error::InvalidRequest)?
                    <= max_days,
                Error::ApprovalRequired,
            )?;
        }
        Dates::PastCompleteDays { .. } => return Err(Error::InvalidRequest),
    }
    if let ExportDelegationBoundsDestinationPolicy::RegisteredHostBindings { binding_ids } =
        &b.destination_policy
    {
        ensure(
            binding_ids.contains(&intent.destination.binding_id),
            Error::ApprovalRequired,
        )?;
    }
    Ok(())
}

fn stored_delegations<'a>(
    refs: &AuthorityReferences,
    intent: &ExportIntent,
    effective: &OutputSettings,
    metrics: &[SemanticId],
    context: &'a ExportStoreContext<'_>,
    right: &ExportDelegationRightsItem,
) -> Result<(&'a ExportDelegation, &'a ExportDelegation), Error> {
    let find = |reference: &AuthorityReference,
                rows: &'a [ExportDelegation],
                issuer|
     -> Result<&'a ExportDelegation, Error> {
        let rows: Vec<_> = rows
            .iter()
            .filter(|row| row.authority_id == reference.authority_id && row.issuer == issuer)
            .collect();
        ensure(
            rows.len() == 1 && reference.issuer == issuer,
            Error::ApprovalRequired,
        )?;
        let stored = rows[0];
        ensure(
            delegation_reference(stored)? == *reference,
            Error::ApprovalRequired,
        )?;
        check_delegated_scope(stored, intent, effective, metrics, context, right)?;
        Ok(stored)
    };
    let native = find(
        &refs.native,
        context.native_delegations,
        AuthorityReferenceIssuer::NativeSource,
    )?;
    let host = find(
        &refs.host,
        context.host_delegations,
        AuthorityReferenceIssuer::AuthorizedHost,
    )?;
    ensure(
        context
            .registered_destinations
            .iter()
            .any(|destination| destination == &intent.destination),
        Error::BindingChanged,
    )?;
    Ok((native, host))
}

/// Reuses parent ID/revision and clamps expiry. JSON output is not newly stored authority.
/// # Errors
/// Returns a fixed shape error; parent scope/bounds must be checked separately.
pub fn derived_export_authority(
    delegation: &ExportDelegation,
    plan: &ExportPlan,
    native_consent: DiscoveryEntitlement,
    entitlement: DiscoveryEntitlement,
) -> Result<Authority, Error> {
    delegation.validate_shape()?;
    plan.validate_shape()?;
    let rights = delegation
        .rights
        .iter()
        .map(|right| match right {
            ExportDelegationRightsItem::Discover => AuthorityRightsItem::Discover,
            ExportDelegationRightsItem::Plan => AuthorityRightsItem::Plan,
            ExportDelegationRightsItem::ExportExecute => AuthorityRightsItem::ExportExecute,
        })
        .collect();
    Ok(Authority {
        authority_id: delegation.authority_id.clone(),
        issuer: delegation.issuer.clone(),
        peer: delegation.peer.clone(),
        rights,
        scope_sha256: plan.scope_sha256.clone(),
        destination_binding_ids: vec![plan.intent.destination.binding_id.clone()],
        expires_at: std::cmp::min(delegation.expires_at.clone(), plan.expires_at.clone()),
        grant_revision: delegation.grant_revision,
        configuration_protection: AuthorityConfigurationProtection::NotApplicable,
        native_consent,
        entitlement,
        control_read_scope: None,
        schema: AuthoritySchema::HealthmdAgentAuthority,
        schema_version: 1,
    })
}

fn require_export_authority(
    authority: &Authority,
    plan: &ExportPlan,
    now: &UtcTimestamp,
) -> Result<(), Error> {
    authority.validate_shape()?;
    ensure(
        authority
            .rights
            .contains(&AuthorityRightsItem::ExportExecute),
        Error::ApprovalRequired,
    )?;
    ensure(
        authority.peer == plan.intent.peer && authority.scope_sha256 == plan.scope_sha256,
        Error::BindingChanged,
    )?;
    ensure(
        authority.expires_at.seconds()? > now.seconds()?
            && authority
                .destination_binding_ids
                .contains(&plan.intent.destination.binding_id),
        Error::ApprovalRequired,
    )?;
    ensure(
        authority.native_consent == DiscoveryEntitlement::Satisfied,
        Error::PermissionRequired,
    )?;
    ensure(
        authority.entitlement == DiscoveryEntitlement::Satisfied,
        Error::EntitlementRequired,
    )
}
fn current(plan: &ExportPlan, context: &ExportStoreContext<'_>) -> Result<(), Error> {
    ensure(
        context.current_peer == &plan.intent.peer
            && context.current_destination == &plan.intent.destination,
        Error::BindingChanged,
    )?;
    ensure(
        context.capabilities.capability_sha256 == plan.capability_sha256
            && context.current_capability_sha256 == &plan.capability_sha256,
        Error::BindingChanged,
    )?;
    ensure(
        context.current_revisions == plan.revisions,
        Error::RevisionConflict,
    )
}
fn issued_plan(plan: &ExportPlan, context: &ExportStoreContext<'_>) -> Result<(), Error> {
    ensure(
        context
            .issued_plans
            .iter()
            .any(|(id, sha)| id == &plan.plan_id && sha == &plan.plan_sha256),
        Error::BindingChanged,
    )
}
fn verify_parents(plan: &ExportPlan, context: &ExportStoreContext<'_>) -> Result<(), Error> {
    let (native, host) = stored_delegations(
        &plan.authority_references,
        &plan.intent,
        &plan.effective_settings,
        &plan.resolved_metric_ids,
        context,
        &ExportDelegationRightsItem::ExportExecute,
    )?;
    ensure(
        plan.expires_at.seconds()? <= native.expires_at.seconds()?.min(host.expires_at.seconds()?),
        Error::PlanExpired,
    )?;
    for (authority, parent) in [
        (context.native_authority, native),
        (context.host_authority, host),
    ] {
        require_export_authority(authority, plan, context.now)?;
        ensure(
            *authority
                == derived_export_authority(
                    parent,
                    plan,
                    authority.native_consent.clone(),
                    authority.entitlement.clone(),
                )?,
            Error::ApprovalRequired,
        )?;
    }
    Ok(())
}

/// First/future configuration-only request checks against two pre-existing private stores.
/// Saved/profile output is an externally frozen configuration snapshot, not inherited here.
/// # Errors
/// Unknown caller UUID/digest, stale/revoked/expired refs and out-of-bounds scope reject.
pub fn validate_plan_request(
    request: &PlanRequest,
    effective: &OutputSettings,
    context: &ExportStoreContext<'_>,
) -> Result<(), Error> {
    request.validate_shape()?;
    validate_discovery(context.capabilities, &context.configuration)?;
    ensure(
        request.capability_sha256 == context.capabilities.capability_sha256
            && request.intent.peer == context.capabilities.peer,
        Error::BindingChanged,
    )?;
    ensure(
        context.capabilities.expires_at.seconds()? > context.now.seconds()?,
        Error::PlanExpired,
    )?;
    ensure(
        context
            .capabilities
            .features
            .contains(&DiscoveryFeaturesItem::ZeroHealthPlan),
        Error::UnsupportedCapability,
    )?;
    let refs: Vec<_> = context
        .capabilities
        .authority_references
        .iter()
        .filter(|r| {
            r.authority_id == request.authority_id && r.grant_revision == request.authority_revision
        })
        .collect();
    ensure(refs.len() == 1, Error::ApprovalRequired)?;
    let metrics = validate_export_intent(&request.intent, &context.configuration)?;
    validate_output_settings(effective, &request.intent.peer.platform)?;
    match &request.intent.settings_policy {
        Policy::Explicit { settings } => {
            ensure(settings.as_ref() == effective, Error::BindingChanged)?;
        }
        Policy::SavedDeviceSettings { expected_revision }
        | Policy::Profile {
            expected_revision, ..
        } => {
            let domain = if matches!(request.intent.settings_policy, Policy::Profile { .. }) {
                RevisionDomain::NativeProfile
            } else {
                RevisionDomain::DeviceSettings
            };
            let pins: Vec<_> = context
                .current_revisions
                .iter()
                .filter(|r| r.domain == domain)
                .collect();
            ensure(
                pins.len() == 1 && pins[0].revision == *expected_revision,
                Error::RevisionConflict,
            )?;
            if let Policy::Profile { profile_id, .. } = &request.intent.settings_policy {
                ensure(pins[0].object_id == *profile_id, Error::RevisionConflict)?;
            }
        }
    }
    stored_delegations(
        &AuthorityReferences {
            native: refs[0].clone(),
            host: request.host_authority_reference.clone(),
        },
        &request.intent,
        effective,
        &metrics,
        context,
        &ExportDelegationRightsItem::Plan,
    )?;
    Ok(())
}

/// Relays a separately stored exact decision; receiving the request never approves it.
/// # Errors
/// Unissued plans or absent stored decisions cannot authorize export.
pub fn validate_approval_request(
    request: &ApprovalRequest,
    plan: &ExportPlan,
    context: &ExportStoreContext<'_>,
) -> Result<(), Error> {
    request.validate_shape()?;
    validate_export_plan(plan, &context.configuration)?;
    ensure(
        request.plan_id == plan.plan_id && request.binding == approval_binding(plan),
        Error::BindingChanged,
    )?;
    issued_plan(plan, context)?;
    ensure(
        plan.expires_at.seconds()? > context.now.seconds()?,
        Error::PlanExpired,
    )?;
    verify_parents(plan, context)?;
    ensure(
        context.approved_binding_sha256 == Some(&digest(&approval_binding(plan))?),
        Error::ApprovalRequired,
    )?;
    current(plan, context)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExecutionDisposition {
    /// Adapter must still atomically persist exact acceptance before any source read.
    RequiresNativeAcceptanceJournal,
    /// Return the stored job/receipt only. Never recapture or renew an expired approval.
    ReplayOnly,
}

/// Exact execute/fingerprint checks against immutable issued records and parent grants.
/// No capture/acceptance transaction is performed. All-available history max-day enforcement
/// is deferred until approved native capture; overflow must reject rather than clip.
/// # Errors
/// Changed bytes/bindings, caller-made approvals, missing gates and stale capabilities reject.
pub fn validate_execute(
    request: &ExecuteRequest,
    context: &ExportStoreContext<'_>,
) -> Result<ExecutionDisposition, Error> {
    request.validate_shape()?;
    let plan = &request.plan;
    validate_export_plan(plan, &context.configuration)?;
    issued_plan(plan, context)?;
    ensure(
        request.approval.binding == approval_binding(plan),
        Error::BindingChanged,
    )?;
    let fingerprint = digest(request)?;
    if let Some(previous) = context.accepted {
        ensure(
            previous.peer == plan.intent.peer
                && previous.destination == plan.intent.destination
                && previous.job_id == request.job_id
                && previous.idempotency_key == request.idempotency_key
                && previous.request_sha256 == fingerprint
                && context.current_peer == &previous.peer
                && context.current_destination == &previous.destination,
            Error::BindingChanged,
        )?;
        return Ok(ExecutionDisposition::ReplayOnly);
    }
    ensure(
        plan.expires_at.seconds()? > context.now.seconds()?,
        Error::PlanExpired,
    )?;
    ensure(
        request.approval.approved_at.seconds()? >= plan.issued_at.seconds()?
            && request.approval.approved_at.seconds()? <= context.now.seconds()?,
        Error::ApprovalRequired,
    )?;
    ensure(
        plan.required_actions.is_empty(),
        Error::NativeRebindRequired,
    )?;
    current(plan, context)?;
    let caps = context.capabilities;
    validate_discovery(caps, &context.configuration)?;
    ensure(caps.peer == plan.intent.peer, Error::BindingChanged)?;
    ensure(
        caps.expires_at.seconds()? > context.now.seconds()?,
        Error::PlanExpired,
    )?;
    check_output_capabilities(plan, caps)?;
    verify_issued_approval(request, context)?;
    ensure(
        caps.authority_references
            .contains(&plan.authority_references.native),
        Error::ApprovalRequired,
    )?;
    verify_parents(plan, context)?;
    Ok(ExecutionDisposition::RequiresNativeAcceptanceJournal)
}

fn check_output_capabilities(plan: &ExportPlan, caps: &Discovery) -> Result<(), Error> {
    ensure(
        caps.features
            .contains(&DiscoveryFeaturesItem::BoundExecution)
            && caps
                .features
                .contains(&DiscoveryFeaturesItem::ZeroHealthPlan),
        Error::UnsupportedCapability,
    )?;
    let settings = &plan.effective_settings;
    ensure(
        subset(&settings.formats, &caps.output_support.formats)
            && caps
                .output_support
                .write_modes
                .contains(&settings.write_mode)
            && caps.output_profiles.contains(&settings.output_profile),
        Error::UnsupportedCapability,
    )?;
    let policy = match plan.intent.settings_policy {
        Policy::Explicit { .. } => DiscoverySettingsPoliciesItem::Explicit,
        Policy::SavedDeviceSettings { .. } => DiscoverySettingsPoliciesItem::SavedDeviceSettings,
        Policy::Profile { .. } => DiscoverySettingsPoliciesItem::Profile,
    };
    ensure(
        caps.settings_policies.contains(&policy),
        Error::UnsupportedCapability,
    )?;
    ensure(
        caps.output_support
            .compatibility_detail
            .contains(&plan.intent.capture_scope.compatibility_detail),
        Error::UnsupportedCapability,
    )?;
    let archive_token = match plan.intent.capture_scope.native_archive {
        Archive::None {} => "none",
        Archive::AppleHealthkitCanonicalV1 {} => "apple_healthkit_canonical_v1",
        Archive::AndroidProviderNativeSnapshotV1 { .. } => "android_provider_native_snapshot_v1",
    };
    ensure(
        caps.output_support
            .native_archive_products
            .iter()
            .any(|p| token(p) == archive_token),
        Error::UnsupportedCapability,
    )?;
    if matches!(settings.packaging, Packaging::Zip { .. }) {
        ensure(
            caps.features.contains(&DiscoveryFeaturesItem::Zip),
            Error::UnsupportedCapability,
        )?;
    }
    if !matches!(settings.dictionary, Dictionary::None {}) {
        ensure(
            caps.features
                .contains(&DiscoveryFeaturesItem::ProfileDictionary),
            Error::UnsupportedCapability,
        )?;
    }
    Ok(())
}

fn verify_issued_approval(
    request: &ExecuteRequest,
    context: &ExportStoreContext<'_>,
) -> Result<(), Error> {
    ensure(
        context
            .issued_approval_ids
            .contains(&request.approval.approval_id)
            && context.issued_approvals.iter().any(|(id, sha)| {
                id == &request.approval.approval_id && digest(&request.approval).as_ref() == Ok(sha)
            })
            && request.approval.authority_id == context.native_authority.authority_id,
        Error::ApprovalRequired,
    )
}

/// Public digest utility for native journals/candidate constructors, no authorization.
/// # Errors
/// Returns a fixed codec error.
pub fn document_digest<T: Serialize + ?Sized>(value: &T) -> Result<Digest, Error> {
    digest(value)
}
