//! Configuration-only host planning against independently stored host authority and an
//! authenticated source. No capture/export/wake/output/credential-enrollment dependency exists.
use async_trait::async_trait;
use healthmd_protocol::v4::{
    Approval, ApprovalRequest, Archive, AuthorityReference, AuthorityReferenceIssuer,
    AuthorityReferences, CalendarZone, Capture, CaptureCompatibilityDetail, ConfigurationContext,
    ControlUuid, Dates, Discovery, DiscoveryEntitlement, DiscoveryFeaturesItem,
    DiscoverySettingsPoliciesItem, Error, ExecuteRequest, ExportDelegationRightsItem, ExportIntent,
    ExportIntentProduct, ExportIntentProductType, ExportIntentSchema,
    ExportIntentTimestampTimezone, ExportPlan, MetricSupport, OutputSettings,
    OutputSettingsFormatsItem, OutputSettingsWriteMode, OutputSupportNativeArchiveProductsItem,
    OutputSupportPathTokensItem, Peer, PeerPlatform, PlanRequest, PlanRequestSchema, Policy,
    Selection, SemanticId, UtcTimestamp, ValidateShape, approval_binding, derived_export_authority,
    predicted_paths, resolve_dates, setting_origins, validate_discovery, validate_export_intent,
    validate_export_plan,
};

use crate::{
    ClientError,
    agent_host::{HostAuthorityStore, HostAuthorization},
    agent_validation::{
        IssuerScopeContext, validate_issuer_plan_scope, validate_supported_settings,
    },
};

/// Source seam is fixed and typed. Source authority must be checked by its issuing native
/// module; the host never treats a received description/digest as a native grant.
#[async_trait]
pub trait PlanningSource: Send {
    /// Fresh authentication/selection revocation fence; cached peer identity is not authority.
    async fn require_current(&self) -> Result<(), ClientError>;
    fn peer(&self) -> &Peer;
    async fn discover(&mut self) -> Result<Discovery, ClientError>;
    async fn plan(&mut self, request: PlanRequest) -> Result<ExportPlan, ClientError>;
    async fn relay_approval(&mut self, request: ApprovalRequest) -> Result<Approval, ClientError>;
}

/// Non-Codable internal request, produced from the locally validated CLI/MCP DTO.
#[derive(Clone)]
pub struct HostPlanInput {
    pub dates: Dates,
    pub calendar_timezone: CalendarZone,
    pub metric_ids: Vec<SemanticId>,
    pub settings: OutputSettings,
    pub destination_binding_id: ControlUuid,
    pub native_authority_reference: Option<AuthorityReference>,
    pub host_authority_reference: Option<AuthorityReference>,
}

/// Injected configuration clock, sampled again after each bounded network round-trip.
pub trait PlanningClock: Send + Sync {
    fn now(&self) -> UtcTimestamp;
}
pub struct SystemPlanningClock;
impl PlanningClock for SystemPlanningClock {
    fn now(&self) -> UtcTimestamp {
        UtcTimestamp(chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true))
    }
}

pub struct HostPlanner {
    store: HostAuthorityStore,
}
impl HostPlanner {
    pub const fn new(store: HostAuthorityStore) -> Self {
        Self { store }
    }

    /// Validate exact peer/root/grant and supported intent before opening the listener.
    /// # Errors
    /// Unknown/expired/revoked authority, unsafe/substituted root or unsupported requests reject.
    pub async fn preflight(
        &self,
        peer: &Peer,
        input: &HostPlanInput,
        now: &UtcTimestamp,
    ) -> Result<(), ClientError> {
        self.prepare(peer, input, now).await?;
        Ok(())
    }

    async fn prepare(
        &self,
        peer: &Peer,
        input: &HostPlanInput,
        now: &UtcTimestamp,
    ) -> Result<(ExportIntent, HostAuthorization), ClientError> {
        peer.validate_shape()?;
        now.validate_shape()?;
        input.destination_binding_id.validate_shape()?;
        if let Some(reference) = &input.native_authority_reference {
            reference.validate_shape()?;
            if reference.issuer != AuthorityReferenceIssuer::NativeSource {
                return Err(Error::ApprovalRequired.into());
            }
        }
        let authorization = self
            .store
            .authorization(
                peer,
                &input.destination_binding_id,
                input.host_authority_reference.as_ref(),
                now,
            )
            .await?;
        let source = if peer.platform == PeerPlatform::Apple {
            "apple_health"
        } else {
            "health_connect"
        };
        let intent = ExportIntent {
            schema: ExportIntentSchema::HealthmdAgentExportIntent,
            schema_version: 1,
            intent_id: ControlUuid(uuid::Uuid::new_v4().to_string()),
            peer: peer.clone(),
            destination: authorization.destination.clone(),
            calendar_timezone: input.calendar_timezone.clone(),
            timestamp_timezone: ExportIntentTimestampTimezone::Utc,
            dates: input.dates.clone(),
            capture_scope: Capture {
                compatibility_detail: CaptureCompatibilityDetail::Summary,
                native_archive: Archive::None {},
                selection: Selection {
                    metric_ids: input.metric_ids.clone(),
                    category_ids: vec![],
                    source_ids: vec![SemanticId(source.into())],
                    provider_ids: vec![],
                    all_metrics: false,
                },
            },
            product: ExportIntentProduct {
                kind: ExportIntentProductType::GeneratedFiles,
            },
            settings_policy: Policy::Explicit {
                settings: Box::new(input.settings.clone()),
            },
        };
        let configuration = reviewed_configuration();
        let context = configuration.context();
        validate_export_intent(&intent, &context)?;
        validate_supported_settings(&input.settings)?;
        validate_issuer_plan_scope(
            &authorization.delegation,
            &authorization.reference,
            &intent,
            &input.settings,
            &ExportDelegationRightsItem::Plan,
            &IssuerScopeContext {
                configuration: &context,
                now,
                issuer: AuthorityReferenceIssuer::AuthorizedHost,
            },
        )?;
        Ok((intent, authorization))
    }

    /// Native discovery and exact plan round-trip. Only private issued-plan metadata is written.
    /// # Errors
    /// No permission is enrolled; any scope/settings/path/origin/ref/digest substitution rejects.
    pub async fn plan(
        &self,
        source: &mut dyn PlanningSource,
        input: HostPlanInput,
        clock: &dyn PlanningClock,
    ) -> Result<ExportPlan, ClientError> {
        source.require_current().await?;
        let peer = source.peer().clone();
        let (intent, host) = self.prepare(&peer, &input, &clock.now()).await?;
        let discovery = source.discover().await?;
        let configuration = reviewed_configuration();
        let context = configuration.context();
        validate_current_discovery(&discovery, &peer, &clock.now(), &context)?;
        check_capabilities(&intent, &discovery)?;
        let references: Vec<_> = discovery
            .authority_references
            .iter()
            .filter(|r| {
                input
                    .native_authority_reference
                    .as_ref()
                    .is_none_or(|requested| *requested == **r)
            })
            .collect();
        if references.len() != 1 {
            return Err(Error::ApprovalRequired.into());
        }
        let native = references[0].clone();
        let request = PlanRequest {
            schema: PlanRequestSchema::HealthmdAgentPlanRequest,
            schema_version: 1,
            request_id: ControlUuid(uuid::Uuid::new_v4().to_string()),
            authority_id: native.authority_id.clone(),
            authority_revision: native.grant_revision,
            host_authority_reference: host.reference.clone(),
            capability_sha256: discovery.capability_sha256.clone(),
            intent: intent.clone(),
        };
        let plan = source.plan(request).await?;
        let now = clock.now();
        validate_export_plan(&plan, &context)?;
        if plan.intent != intent
            || plan.authority_references
                != (AuthorityReferences {
                    host: host.reference.clone(),
                    native,
                })
            || plan.capability_sha256 != discovery.capability_sha256
            || !plan.revisions.is_empty()
            || plan.issued_at > now
            || plan.expires_at <= now
            || plan.expires_at > discovery.expires_at
            || plan.expires_at > host.delegation.expires_at
        {
            return Err(Error::BindingChanged.into());
        }
        // Reopen key, exact stored grant and root immediately before private CAS publication.
        let current = self
            .store
            .authorization(
                &peer,
                &input.destination_binding_id,
                Some(&host.reference),
                &now,
            )
            .await?;
        if current.store_revision != host.store_revision || current.destination != host.destination
        {
            return Err(Error::RevisionConflict.into());
        }
        source.require_current().await?;
        require_live_plan(&plan, clock)?;
        let host_authority = derived_export_authority(
            &host.delegation,
            &plan,
            DiscoveryEntitlement::Satisfied,
            DiscoveryEntitlement::Satisfied,
        )?;
        self.store
            .persist_plan(host.store_revision, plan.clone(), discovery, host_authority)
            .await?;
        source.require_current().await?;
        require_live_plan(&plan, clock)?;
        Ok(plan)
    }

    /// Local stored-decision preflight, before listener/network work.
    /// # Errors
    /// Unknown/mismatched/expired plans or missing separate host decision reject locally.
    pub async fn preflight_approval(
        &self,
        request: &ApprovalRequest,
        now: &UtcTimestamp,
    ) -> Result<Peer, ClientError> {
        request.validate_shape()?;
        let (_, plan, _, decision, _) = self.store.issued_plan(&request.plan_id).await?;
        let binding = approval_binding(&plan);
        if request.binding != binding {
            return Err(Error::BindingChanged.into());
        }
        if decision.as_ref() != Some(&binding) {
            return Err(Error::ApprovalRequired.into());
        }
        if plan.expires_at <= *now {
            return Err(Error::PlanExpired.into());
        }
        let host = self
            .store
            .authorization(
                &plan.intent.peer,
                &plan.intent.destination.binding_id,
                Some(&plan.authority_references.host),
                now,
            )
            .await?;
        if host.destination != plan.intent.destination {
            return Err(Error::BindingChanged.into());
        }
        Ok(plan.intent.peer)
    }

    /// Relay only a previously stored exact host decision and the exact native approval.
    /// # Errors
    /// Caller JSON/annotations cannot make a decision; unknown/changed/stale plans reject.
    pub async fn relay_approval(
        &self,
        source: &mut dyn PlanningSource,
        request: ApprovalRequest,
        clock: &dyn PlanningClock,
    ) -> Result<Approval, ClientError> {
        source.require_current().await?;
        let now = clock.now();
        self.preflight_approval(&request, &now).await?;
        request.validate_shape()?;
        let (_, plan, issued_discovery, decision, previous) =
            self.store.issued_plan(&request.plan_id).await?;
        let binding = approval_binding(&plan);
        if request.binding != binding || source.peer() != &plan.intent.peer {
            return Err(Error::BindingChanged.into());
        }
        if decision.as_ref() != Some(&binding) {
            return Err(Error::ApprovalRequired.into());
        }
        if plan.expires_at <= now {
            return Err(Error::PlanExpired.into());
        }
        let host = self
            .store
            .authorization(
                &plan.intent.peer,
                &plan.intent.destination.binding_id,
                Some(&plan.authority_references.host),
                &now,
            )
            .await?;
        if host.destination != plan.intent.destination {
            return Err(Error::BindingChanged.into());
        }
        let configuration = reviewed_configuration();
        let context = configuration.context();
        validate_export_plan(&plan, &context)?;
        validate_issuer_plan_scope(
            &host.delegation,
            &host.reference,
            &plan.intent,
            &plan.effective_settings,
            &ExportDelegationRightsItem::ExportExecute,
            &IssuerScopeContext {
                configuration: &context,
                now: &now,
                issuer: AuthorityReferenceIssuer::AuthorizedHost,
            },
        )?;
        let current = source.discover().await?;
        require_live_plan(&plan, clock)?;
        validate_current_discovery(&current, &plan.intent.peer, &clock.now(), &context)?;
        if current.capability_sha256 != plan.capability_sha256
            || current.capability_revision != issued_discovery.capability_revision
            || !current
                .authority_references
                .contains(&plan.authority_references.native)
        {
            return Err(Error::BindingChanged.into());
        }
        check_capabilities(&plan.intent, &current)?;
        if let Some(approval) = previous {
            source.require_current().await?;
            require_live_plan(&plan, clock)?;
            return Ok(approval);
        }
        let approval = source.relay_approval(request).await?;
        let now = clock.now();
        if plan.expires_at <= now {
            return Err(Error::PlanExpired.into());
        }
        approval.validate_shape()?;
        if approval.binding != binding
            || approval.authority_id != plan.authority_references.native.authority_id
            || approval.approved_at < plan.issued_at
            || approval.approved_at > now
        {
            return Err(Error::BindingChanged.into());
        }
        let rechecked = self
            .store
            .authorization(
                &plan.intent.peer,
                &plan.intent.destination.binding_id,
                Some(&host.reference),
                &now,
            )
            .await?;
        if rechecked.store_revision != host.store_revision
            || rechecked.destination != host.destination
        {
            return Err(Error::RevisionConflict.into());
        }
        source.require_current().await?;
        require_live_plan(&plan, clock)?;
        self.store
            .persist_approval(host.store_revision, &plan, approval.clone())
            .await?;
        source.require_current().await?;
        require_live_plan(&plan, clock)?;
        Ok(approval)
    }

    /// No accepted receipt, old export conversion or fake execution until a genuine source
    /// journal/capture adapter exists. This method never contacts the source.
    /// # Errors
    /// Always returns `unsupported_capability` in this planning-only implementation.
    pub fn execute(&self, _: &ExecuteRequest) -> Result<(), ClientError> {
        Err(Error::UnsupportedCapability.into())
    }
}

fn require_live_plan(plan: &ExportPlan, clock: &dyn PlanningClock) -> Result<(), ClientError> {
    if plan.expires_at <= clock.now() {
        return Err(Error::PlanExpired.into());
    }
    Ok(())
}

struct ReviewedConfiguration {
    zones: Vec<CalendarZone>,
    metrics: Vec<MetricSupport>,
}
impl ReviewedConfiguration {
    fn context(&self) -> ConfigurationContext<'_> {
        ConfigurationContext {
            calendar_zones: &self.zones,
            metrics: &self.metrics,
            projection_catalog_sha256: None,
        }
    }
}
fn reviewed_configuration() -> ReviewedConfiguration {
    let mut metrics = Vec::new();
    for platform in [PeerPlatform::Apple, PeerPlatform::Android] {
        for id in [
            "steps",
            "heart_rate_avg",
            "heart_rate_min",
            "heart_rate_max",
            "resting_heart_rate",
            if platform == PeerPlatform::Apple {
                "hrv"
            } else {
                "android.hrv_rmssd"
            },
        ] {
            metrics.push(MetricSupport {
                metric_id: SemanticId(id.into()),
                category_id: SemanticId(if id == "steps" { "activity" } else { "heart" }.into()),
                platform: platform.clone(),
            });
        }
    }
    ReviewedConfiguration {
        zones: chrono_tz::TZ_VARIANTS
            .iter()
            .map(|z| CalendarZone(z.to_string()))
            .collect(),
        metrics,
    }
}
fn validate_current_discovery(
    discovery: &Discovery,
    peer: &Peer,
    now: &UtcTimestamp,
    configuration: &ConfigurationContext<'_>,
) -> Result<(), ClientError> {
    validate_discovery(discovery, configuration)?;
    if discovery.peer != *peer || discovery.issued_at > *now || discovery.expires_at <= *now {
        return Err(Error::BindingChanged.into());
    }
    if !discovery
        .features
        .contains(&DiscoveryFeaturesItem::ZeroHealthPlan)
    {
        return Err(Error::UnsupportedCapability.into());
    }
    Ok(())
}
fn check_capabilities(intent: &ExportIntent, discovery: &Discovery) -> Result<(), ClientError> {
    let Policy::Explicit { settings } = &intent.settings_policy else {
        return Err(Error::UnsupportedCapability.into());
    };
    let support = &discovery.output_support;
    if !discovery
        .features
        .contains(&DiscoveryFeaturesItem::ExplicitSettings)
        || !discovery
            .settings_policies
            .contains(&DiscoverySettingsPoliciesItem::Explicit)
        || !discovery.output_profiles.contains(&settings.output_profile)
        || !support.formats.contains(&OutputSettingsFormatsItem::Json)
        || !support
            .write_modes
            .contains(&OutputSettingsWriteMode::Overwrite)
        || !support
            .compatibility_detail
            .contains(&CaptureCompatibilityDetail::Summary)
        || !support
            .native_archive_products
            .contains(&OutputSupportNativeArchiveProductsItem::None)
    {
        return Err(Error::UnsupportedCapability.into());
    }
    // Every settings leaf, including disabled outputs, must be advertised as supported.
    for origin in setting_origins(intent, settings)?
        .iter()
        .filter(|o| o.pointer.starts_with("/effective_settings/"))
    {
        let pointer = origin.pointer.replacen("/effective_settings", "", 1);
        if !support.setting_pointers.contains(&pointer) {
            return Err(Error::UnsupportedCapability.into());
        }
    }
    for (token, kind) in [
        ("{date}", OutputSupportPathTokensItem::Date),
        ("{day}", OutputSupportPathTokensItem::Day),
        ("{month}", OutputSupportPathTokensItem::Month),
        ("{year}", OutputSupportPathTokensItem::Year),
    ] {
        if [&settings.folder_template.0, &settings.filename_template.0]
            .iter()
            .any(|s| s.contains(token))
            && !support.path_tokens.contains(&kind)
        {
            return Err(Error::UnsupportedCapability.into());
        }
    }
    let paths = predicted_paths(intent, settings)?;
    if paths.len() as u64 > support.max_artifacts
        || paths
            .iter()
            .any(|p| p.0.len() as u64 > support.max_path_bytes)
    {
        return Err(Error::UnsupportedCapability.into());
    }
    if let Dates::Exact { range } = resolve_dates(&intent.dates)? {
        let start = chrono::NaiveDate::parse_from_str(&range.start_date.0, "%Y-%m-%d")
            .map_err(|_| Error::InvalidRequest)?;
        let end = chrono::NaiveDate::parse_from_str(&range.end_date.0, "%Y-%m-%d")
            .map_err(|_| Error::InvalidRequest)?;
        if u64::try_from((end - start).num_days()).map_err(|_| Error::InvalidRequest)? + 1
            > discovery.budgets.max_calendar_days
        {
            return Err(Error::UnsupportedCapability.into());
        }
    }
    Ok(())
}
