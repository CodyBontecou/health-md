//! Synthetic source, explicit local fake consent, and independent DTO constructors only.
//! No Swift/Kotlin runtime, provider, preferences, native credentials, or capture support.
#![allow(dead_code)]
use super::client_crate::{
    ClientError,
    agent_host::{
        HostAuthorityStore, LocalEnrollment, LocalHostConsent, ProtectedHostKey,
        ProtectedHostSecret as SecretString,
    },
    agent_planning::{HostPlanInput, PlanningClock, PlanningSource},
};
use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_protocol::v4::*;
use std::sync::Arc;

pub fn id(number: u64) -> ControlUuid {
    ControlUuid(format!("00000000-0000-4000-8000-{number:012x}"))
}
pub fn now() -> UtcTimestamp {
    UtcTimestamp("2026-01-03T00:00:00Z".into())
}
pub struct FixedClock(pub UtcTimestamp);
impl PlanningClock for FixedClock {
    fn now(&self) -> UtcTimestamp {
        self.0.clone()
    }
}
pub fn later(time: &UtcTimestamp, seconds: i64) -> UtcTimestamp {
    let parsed: chrono::DateTime<chrono::Utc> = time.0.parse().unwrap();
    UtcTimestamp(
        (parsed + chrono::Duration::seconds(seconds))
            .to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
    )
}
pub fn peer(platform: PeerPlatform) -> Peer {
    Peer {
        source_installation_id: id(1),
        host_installation_id: id(2),
        platform,
    }
}
pub struct FakeProtectedKey;
#[async_trait]
impl ProtectedHostKey for FakeProtectedKey {
    async fn load_existing(&self, _: &ControlUuid) -> Result<SecretString, ClientError> {
        Ok(SecretString::from(STANDARD.encode([41; 32])))
    }
}
pub struct ExplicitFakeLocalConsent;
#[async_trait]
impl LocalHostConsent for ExplicitFakeLocalConsent {
    async fn enroll(&self, _: &LocalEnrollment) -> Result<(), ClientError> {
        Ok(())
    }
    async fn decide(&self, _: &ExportPlan) -> Result<(), ClientError> {
        Ok(())
    }
}
pub fn profile(peer: &Peer) -> OutputSettingsOutputProfile {
    if peer.platform == PeerPlatform::Apple {
        OutputSettingsOutputProfile::AppleV8
    } else {
        OutputSettingsOutputProfile::AndroidFrozenV4
    }
}
pub fn settings(peer: &Peer) -> OutputSettings {
    OutputSettings {
        daily_notes: DailyNotes {
            create_if_missing: false,
            enabled: false,
            filename_template: FilenameTemplate("{date}".into()),
            folder_template: RelativePath(String::new()),
            only: false,
            section_ids: vec![],
        },
        dictionary: Dictionary::None {},
        filename_template: FilenameTemplate("{date}".into()),
        folder_template: RelativePath("{year}".into()),
        formats: vec![OutputSettingsFormatsItem::Json],
        individual_entries: IndividualEntries {
            category_folders: false,
            enabled: false,
            filename_template: FilenameTemplate("{metric}-{date}".into()),
            folder_template: RelativePath(String::new()),
            metric_ids: vec![],
        },
        output_profile: profile(peer),
        packaging: Packaging::LooseFiles {},
        presentation: Presentation {
            display_units: PresentationDisplayUnits::Metric,
            frontmatter: Frontmatter {
                custom_fields: vec![],
                enabled_field_ids: vec![],
                include_capture_diagnostics: false,
                include_units: true,
            },
            group_by_category: true,
            include_metadata: true,
            locale: "en-US".into(),
            machine_units: PresentationMachineUnits::Canonical,
            markdown: Markdown {
                custom_template: String::new(),
                placeholder_ids: vec![],
                style: MarkdownStyle::Lists,
            },
        },
        subfolder: RelativePath(String::new()),
        write_mode: OutputSettingsWriteMode::Overwrite,
    }
}
pub fn delegation(
    peer: &Peer,
    issuer: AuthorityReferenceIssuer,
    time: &UtcTimestamp,
) -> ExportDelegation {
    let host = issuer == AuthorityReferenceIssuer::AuthorizedHost;
    ExportDelegation {
        schema: ExportDelegationSchema::HealthmdAgentExportDelegation,
        schema_version: 1,
        authority_id: id(if host { 5 } else { 4 }),
        issuer,
        peer: peer.clone(),
        grant_revision: 1,
        expires_at: later(time, 1800),
        rights: vec![
            ExportDelegationRightsItem::Discover,
            ExportDelegationRightsItem::ExportExecute,
            ExportDelegationRightsItem::Plan,
        ],
        bounds: ExportDelegationBounds {
            calendar_timezones: vec![CalendarZone("UTC".into())],
            compatibility_detail: vec![CaptureCompatibilityDetail::Summary],
            date_policy: ExportDelegationBoundsDatePolicy::AuthorizedHistory {
                allow_all_available: true,
                max_days: 31,
            },
            destination_policy: if host {
                ExportDelegationBoundsDestinationPolicy::RegisteredHostBindings {
                    binding_ids: vec![id(3)],
                }
            } else {
                ExportDelegationBoundsDestinationPolicy::AuthenticatedHostBindings {}
            },
            formats: vec![OutputSettingsFormatsItem::Json],
            metric_ids: vec![SemanticId("steps".into())],
            native_archive_products: vec![OutputSupportNativeArchiveProductsItem::None],
            output_profiles: vec![profile(peer)],
            products: vec![ExportDelegationBoundsProductsItem::GeneratedFiles],
            projection_details: vec![],
            projection_field_ids: vec![],
            projection_object_ids: vec![],
            write_modes: vec![OutputSettingsWriteMode::Overwrite],
        },
    }
}
pub fn input(peer: &Peer) -> HostPlanInput {
    HostPlanInput {
        dates: Dates::Exact {
            range: Range {
                start_date: CivilDate("2026-01-01".into()),
                end_date: CivilDate("2026-01-02".into()),
            },
        },
        calendar_timezone: CalendarZone("UTC".into()),
        metric_ids: vec![SemanticId("steps".into())],
        settings: settings(peer),
        destination_binding_id: id(3),
        native_authority_reference: None,
        host_authority_reference: None,
    }
}
pub async fn enroll(
    base: &std::path::Path,
    peer: &Peer,
    time: &UtcTimestamp,
) -> (HostAuthorityStore, std::path::PathBuf) {
    let base = std::fs::canonicalize(base).unwrap();
    let private = base.join("agent-host-v1");
    let output = base.join("output");
    std::fs::create_dir(&private).unwrap();
    std::fs::create_dir(&output).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        std::fs::set_permissions(&private, std::fs::Permissions::from_mode(0o700)).unwrap();
    }
    let store = HostAuthorityStore::enroll_local(
        private,
        peer.host_installation_id.clone(),
        Arc::new(FakeProtectedKey),
        LocalEnrollment {
            delegation: delegation(peer, AuthorityReferenceIssuer::AuthorizedHost, time),
            binding_id: id(3),
            root: output.clone(),
        },
        &ExplicitFakeLocalConsent,
    )
    .await
    .unwrap();
    (store, output)
}

pub struct NativeFake {
    pub peer: Peer,
    pub time: UtcTimestamp,
    pub stored_native: Option<ExportDelegation>,
    pub issued: Option<ExportPlan>,
    pub decision: Option<Binding>,
    pub capability_revision: u64,
    pub plan_mutation: Option<fn(&mut ExportPlan)>,
}
impl NativeFake {
    pub fn new(peer: Peer, time: UtcTimestamp) -> Self {
        Self {
            stored_native: Some(delegation(
                &peer,
                AuthorityReferenceIssuer::NativeSource,
                &time,
            )),
            peer,
            time,
            issued: None,
            decision: None,
            capability_revision: 1,
            plan_mutation: None,
        }
    }
    pub fn store_exact_native_decision(&mut self) {
        self.decision = Some(approval_binding(self.issued.as_ref().unwrap()));
    }
    // Keep the complete independent synthetic document constructor visible for audit.
    #[allow(clippy::too_many_lines)]
    pub fn discovery(&self, request_id: ControlUuid) -> Discovery {
        let dummy = ExportIntent {
            schema: ExportIntentSchema::HealthmdAgentExportIntent,
            schema_version: 1,
            intent_id: id(9),
            peer: self.peer.clone(),
            destination: Destination {
                binding_id: id(3),
                host_installation_id: self.peer.host_installation_id.clone(),
                identity_sha256: Digest("0".repeat(64)),
                revision: 1,
            },
            calendar_timezone: CalendarZone("UTC".into()),
            timestamp_timezone: ExportIntentTimestampTimezone::Utc,
            dates: input(&self.peer).dates,
            capture_scope: Capture {
                compatibility_detail: CaptureCompatibilityDetail::Summary,
                native_archive: Archive::None {},
                selection: Selection {
                    all_metrics: false,
                    category_ids: vec![],
                    metric_ids: vec![SemanticId("steps".into())],
                    provider_ids: vec![],
                    source_ids: vec![SemanticId(
                        if self.peer.platform == PeerPlatform::Apple {
                            "apple_health"
                        } else {
                            "health_connect"
                        }
                        .into(),
                    )],
                },
            },
            product: ExportIntentProduct {
                kind: ExportIntentProductType::GeneratedFiles,
            },
            settings_policy: Policy::Explicit {
                settings: Box::new(settings(&self.peer)),
            },
        };
        let mut discovery = Discovery {
            schema: DiscoverySchema::HealthmdAgentDiscovery,
            schema_version: 1,
            request_id,
            peer: self.peer.clone(),
            issued_at: self.time.clone(),
            expires_at: later(&self.time, 600),
            authority_references: self
                .stored_native
                .iter()
                .map(|g| delegation_reference(g).unwrap())
                .collect(),
            budgets: Budgets {
                cursor_idle_seconds: 600,
                cursor_lifetime_seconds: 3600,
                max_calendar_days: 31,
                max_capture_seconds: 120,
                max_page_bytes: 1_048_576,
                max_page_items: 1000,
                max_snapshot_bytes: 67_108_864,
            },
            capability_revision: self.capability_revision,
            capability_sha256: Digest("0".repeat(64)),
            configuration_protection: DiscoveryConfigurationProtection::Locked,
            control_operations: vec![],
            entitlement: DiscoveryEntitlement::Satisfied,
            features: vec![
                DiscoveryFeaturesItem::ExplicitSettings,
                DiscoveryFeaturesItem::ZeroHealthPlan,
            ],
            lifecycle: if self.peer.platform == PeerPlatform::Apple {
                DiscoveryLifecycle::IphoneForegroundProtectedData
            } else {
                DiscoveryLifecycle::AndroidUserStartedServiceAfterFirstUnlock
            },
            native_grants: DiscoveryNativeGrants::Satisfied,
            output_profiles: vec![profile(&self.peer)],
            output_support: OutputSupport {
                compatibility_detail: vec![CaptureCompatibilityDetail::Summary],
                formats: vec![OutputSettingsFormatsItem::Json],
                max_artifacts: 31,
                max_path_bytes: 4096,
                native_archive_products: vec![OutputSupportNativeArchiveProductsItem::None],
                path_tokens: vec![
                    OutputSupportPathTokensItem::Date,
                    OutputSupportPathTokensItem::Day,
                    OutputSupportPathTokensItem::Month,
                    OutputSupportPathTokensItem::Year,
                ],
                setting_pointers: setting_origins(&dummy, &settings(&self.peer))
                    .unwrap()
                    .into_iter()
                    .filter_map(|o| {
                        o.pointer
                            .strip_prefix("/effective_settings")
                            .map(str::to_owned)
                    })
                    .collect(),
                write_modes: vec![OutputSettingsWriteMode::Overwrite],
            },
            projection_catalog_sha256: Digest("0".repeat(64)),
            projection_products: vec![],
            projection_source_catalog: None,
            query_catalog_sha256: Digest("0".repeat(64)),
            query_operations: vec![],
            required_actions: vec![],
            settings_policies: vec![DiscoverySettingsPoliciesItem::Explicit],
            source_calendar_timezone: CalendarZone("UTC".into()),
        };
        discovery.capability_sha256 = capability_digest(&discovery).unwrap();
        discovery
    }
}
#[async_trait]
impl PlanningSource for NativeFake {
    async fn require_current(&self) -> Result<(), ClientError> {
        Ok(())
    }
    fn peer(&self) -> &Peer {
        &self.peer
    }
    async fn discover(&mut self) -> Result<Discovery, ClientError> {
        Ok(self.discovery(id(10)))
    }
    async fn plan(&mut self, request: PlanRequest) -> Result<ExportPlan, ClientError> {
        let stored = self.stored_native.as_ref().ok_or(Error::ApprovalRequired)?;
        let reference = delegation_reference(stored)?;
        if request.authority_id != reference.authority_id
            || request.authority_revision != reference.grant_revision
            || stored.peer != request.intent.peer
            || request.intent.peer != self.peer
            || !stored.rights.contains(&ExportDelegationRightsItem::Plan)
            || stored.expires_at <= self.time
            || request
                .intent
                .capture_scope
                .selection
                .metric_ids
                .iter()
                .any(|id| !stored.bounds.metric_ids.contains(id))
        {
            return Err(Error::ApprovalRequired.into());
        }
        if request.capability_sha256 != self.discovery(id(10)).capability_sha256 {
            return Err(Error::BindingChanged.into());
        }
        let Policy::Explicit { settings } = request.intent.settings_policy.clone() else {
            return Err(Error::UnsupportedCapability.into());
        };
        let dates = resolve_dates(&request.intent.dates)?;
        let all = matches!(dates, Dates::AllAvailable {});
        let mut plan = ExportPlan {
            schema: ExportPlanSchema::HealthmdAgentExportPlan,
            schema_version: 1,
            authority_references: AuthorityReferences {
                native: reference,
                host: request.host_authority_reference,
            },
            capability_sha256: request.capability_sha256,
            effective_settings: *settings.clone(),
            expires_at: later(&self.time, 300),
            issued_at: self.time.clone(),
            limitations: if all {
                vec![SemanticId("history_bounds_unresolved".into())]
            } else {
                vec![]
            },
            origins: setting_origins(&request.intent, &settings)?,
            path_prediction: if all {
                ExportPlanPathPrediction::TemplateOnlyAllAvailable
            } else {
                ExportPlanPathPrediction::ExactRequestedDays
            },
            plan_id: ControlUuid(uuid::Uuid::new_v4().to_string()),
            plan_sha256: Digest("0".repeat(64)),
            predicted_paths: predicted_paths(&request.intent, &settings)?,
            required_actions: vec![],
            resolved_dates: dates.clone(),
            resolved_metric_ids: request.intent.capture_scope.selection.metric_ids.clone(),
            revisions: vec![],
            scope_sha256: export_scope_digest(
                &request.intent,
                &dates,
                &request.intent.capture_scope.selection.metric_ids,
            )?,
            settings_sha256: document_digest(&settings)?,
            intent: request.intent,
            side_effects: ZeroSideEffects {
                content_preview_reads: 0,
                credential_enrollments: 0,
                earliest_date_reads: 0,
                health_reads: 0,
                output_writes: 0,
                quota_consumed: 0,
                settings_mutations: 0,
                wake_enrollments: 0,
            },
        };
        if let Some(mutate) = self.plan_mutation {
            mutate(&mut plan);
        }
        plan.plan_sha256 = plan_digest(&plan)?;
        self.issued = Some(plan.clone());
        Ok(plan)
    }
    async fn relay_approval(&mut self, request: ApprovalRequest) -> Result<Approval, ClientError> {
        let issued = self.issued.as_ref().ok_or(Error::ApprovalRequired)?;
        if issued.plan_id != request.plan_id
            || approval_binding(issued) != request.binding
            || self.decision.as_ref() != Some(&request.binding)
        {
            return Err(Error::ApprovalRequired.into());
        }
        Ok(Approval {
            schema: ApprovalSchema::HealthmdAgentApproval,
            schema_version: 1,
            approval_id: id(12),
            approved_at: self.time.clone(),
            authority_id: issued.authority_references.native.authority_id.clone(),
            binding: request.binding,
            rights: vec![ApprovalRightsItem::ExportExecute],
        })
    }
}
