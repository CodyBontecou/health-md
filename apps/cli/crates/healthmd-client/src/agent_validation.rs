//! Client-owned runtime validators over the unchanged closed v4 DTOs. No protocol mutation,
//! dual-issuer synthetic context, store enrollment, or permission from received JSON.
use healthmd_protocol::v4::{
    Archive, AuthorityReference, AuthorityReferenceIssuer, CivilDate, ConfigurationContext, Dates,
    Dictionary, Error, ExportDelegation, ExportDelegationBoundsDatePolicy,
    ExportDelegationBoundsDestinationPolicy, ExportDelegationBoundsProductsItem,
    ExportDelegationRightsItem, ExportIntent, MarkdownStyle, OutputSettings,
    OutputSettingsFormatsItem, OutputSettingsOutputProfile, OutputSettingsWriteMode,
    OutputSupportNativeArchiveProductsItem, Packaging, PresentationDisplayUnits, UtcTimestamp,
    delegation_reference, resolve_dates, validate_export_delegation, validate_export_intent,
    validate_output_settings,
};

pub(crate) struct IssuerScopeContext<'a> {
    pub configuration: &'a ConfigurationContext<'a>,
    pub now: &'a UtcTimestamp,
    pub issuer: AuthorityReferenceIssuer,
}

pub(crate) fn validate_issuer_plan_scope(
    delegation: &ExportDelegation,
    reference: &AuthorityReference,
    intent: &ExportIntent,
    effective: &OutputSettings,
    right: &ExportDelegationRightsItem,
    context: &IssuerScopeContext<'_>,
) -> Result<(), Error> {
    validate_export_delegation(delegation, context.configuration)?;
    let metrics = validate_export_intent(intent, context.configuration)?;
    validate_output_settings(effective, &intent.peer.platform)?;
    require(
        delegation.issuer == context.issuer
            && reference.issuer == context.issuer
            && delegation_reference(delegation)? == *reference
            && delegation.peer == intent.peer,
        Error::ApprovalRequired,
    )?;
    require(
        delegation.rights.contains(right) && delegation.expires_at > *context.now,
        Error::ApprovalRequired,
    )?;
    let bounds = &delegation.bounds;
    require(
        metrics.iter().all(|m| bounds.metric_ids.contains(m))
            && bounds
                .calendar_timezones
                .contains(&intent.calendar_timezone)
            && bounds
                .products
                .contains(&ExportDelegationBoundsProductsItem::GeneratedFiles)
            && effective.formats.iter().all(|f| bounds.formats.contains(f))
            && bounds.output_profiles.contains(&effective.output_profile)
            && bounds.write_modes.contains(&effective.write_mode)
            && bounds
                .compatibility_detail
                .contains(&intent.capture_scope.compatibility_detail)
            && bounds
                .native_archive_products
                .contains(&OutputSupportNativeArchiveProductsItem::None)
            && matches!(intent.capture_scope.native_archive, Archive::None {}),
        Error::ApprovalRequired,
    )?;
    if let ExportDelegationBoundsDestinationPolicy::RegisteredHostBindings { binding_ids } =
        &bounds.destination_policy
    {
        require(
            binding_ids.contains(&intent.destination.binding_id),
            Error::ApprovalRequired,
        )?;
    }
    match resolve_dates(&intent.dates)? {
        Dates::AllAvailable {} => require(
            matches!(
                bounds.date_policy,
                ExportDelegationBoundsDatePolicy::AuthorizedHistory {
                    allow_all_available: true,
                    ..
                }
            ),
            Error::ApprovalRequired,
        )?,
        Dates::Exact { range } => {
            let start = civil(&range.start_date)?;
            let end = civil(&range.end_date)?;
            let max_days = match &bounds.date_policy {
                ExportDelegationBoundsDatePolicy::BoundedExact { range, max_days } => {
                    require(
                        civil(&range.start_date)? <= start && end <= civil(&range.end_date)?,
                        Error::ApprovalRequired,
                    )?;
                    *max_days
                }
                ExportDelegationBoundsDatePolicy::AuthorizedHistory { max_days, .. } => *max_days,
            };
            let days =
                u64::try_from((end - start).num_days() + 1).map_err(|_| Error::InvalidRequest)?;
            require(days <= max_days, Error::ApprovalRequired)?;
        }
        Dates::PastCompleteDays { .. } => return Err(Error::InvalidRequest),
    }
    Ok(())
}

fn civil(date: &CivilDate) -> Result<chrono::NaiveDate, Error> {
    chrono::NaiveDate::parse_from_str(&date.0, "%Y-%m-%d").map_err(|_| Error::InvalidRequest)
}
fn require(condition: bool, error: Error) -> Result<(), Error> {
    if condition { Ok(()) } else { Err(error) }
}

pub(crate) fn validate_supported_settings(settings: &OutputSettings) -> Result<(), Error> {
    let p = &settings.presentation;
    let entries = &settings.individual_entries;
    let notes = &settings.daily_notes;
    require(
        settings.formats == [OutputSettingsFormatsItem::Json]
            && settings.write_mode == OutputSettingsWriteMode::Overwrite
            && settings.output_profile != OutputSettingsOutputProfile::AndroidAnalyticalV5
            && p.display_units == PresentationDisplayUnits::Metric
            && p.locale == "en-US"
            && p.include_metadata
            && p.group_by_category
            && p.frontmatter.enabled_field_ids.is_empty()
            && p.frontmatter.custom_fields.is_empty()
            && p.frontmatter.include_units
            && !p.frontmatter.include_capture_diagnostics
            && p.markdown.style == MarkdownStyle::Lists
            && p.markdown.custom_template.is_empty()
            && p.markdown.placeholder_ids.is_empty()
            && !entries.enabled
            && !entries.category_folders
            && entries.metric_ids.is_empty()
            && entries.folder_template.0.is_empty()
            && entries.filename_template.0 == "{metric}-{date}"
            && !notes.enabled
            && !notes.only
            && !notes.create_if_missing
            && notes.folder_template.0.is_empty()
            && notes.filename_template.0 == "{date}"
            && notes.section_ids.is_empty()
            && matches!(settings.packaging, Packaging::LooseFiles {})
            && matches!(settings.dictionary, Dictionary::None {})
            && [
                &settings.subfolder.0,
                &settings.folder_template.0,
                &settings.filename_template.0,
            ]
            .iter()
            .all(|s| s.is_ascii())
            && !settings.subfolder.0.contains(['{', '}']),
        Error::UnsupportedCapability,
    )
}
