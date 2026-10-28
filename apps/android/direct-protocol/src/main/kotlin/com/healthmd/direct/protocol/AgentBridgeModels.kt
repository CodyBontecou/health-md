package com.healthmd.direct.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.JsonContentPolymorphicSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Closed agent/source DTO foundation. No source adapters, storage, or authorization is installed.
 * All trust boundaries use AgentBridgeCodec, including raw UTF-8 and scalar-shape preflight.
 * Required fields intentionally have no defaults; only absent schema-optionals default to null. */
@Serializable(with = AgentBridgeDocumentSerializer::class)
sealed interface AgentBridgeDocument { val schema: String; val schemaVersion: Int }

@Serializable
enum class AgentBridgePlatform {
    @SerialName("apple") APPLE,
    @SerialName("android") ANDROID,
}

@Serializable
enum class AgentBridgeIssuer {
    @SerialName("native_source") NATIVE_SOURCE,
    @SerialName("authorized_host") AUTHORIZED_HOST,
}

@Serializable
enum class AgentBridgeDiscoveryConfigurationProtection {
    @SerialName("locked") LOCKED,
    @SerialName("unlocked_native") UNLOCKED_NATIVE,
}

@Serializable
enum class AgentBridgeDiscoveryControlOperationsItem {
    @SerialName("local_recipe.list") LOCAL_RECIPE_LIST,
    @SerialName("local_recipe.get") LOCAL_RECIPE_GET,
    @SerialName("local_recipe.create") LOCAL_RECIPE_CREATE,
    @SerialName("local_recipe.update") LOCAL_RECIPE_UPDATE,
    @SerialName("local_recipe.delete") LOCAL_RECIPE_DELETE,
    @SerialName("local_recipe.run") LOCAL_RECIPE_RUN,
    @SerialName("local_recipe.plan") LOCAL_RECIPE_PLAN,
    @SerialName("native_profile.list") NATIVE_PROFILE_LIST,
    @SerialName("native_profile.get") NATIVE_PROFILE_GET,
    @SerialName("native_profile.create") NATIVE_PROFILE_CREATE,
    @SerialName("native_profile.update") NATIVE_PROFILE_UPDATE,
    @SerialName("native_profile.activate") NATIVE_PROFILE_ACTIVATE,
    @SerialName("native_profile.delete") NATIVE_PROFILE_DELETE,
    @SerialName("native_profile.plan") NATIVE_PROFILE_PLAN,
    @SerialName("host_schedule.list") HOST_SCHEDULE_LIST,
    @SerialName("host_schedule.get") HOST_SCHEDULE_GET,
    @SerialName("host_schedule.create") HOST_SCHEDULE_CREATE,
    @SerialName("host_schedule.update") HOST_SCHEDULE_UPDATE,
    @SerialName("host_schedule.pause") HOST_SCHEDULE_PAUSE,
    @SerialName("host_schedule.delete") HOST_SCHEDULE_DELETE,
    @SerialName("host_schedule.run_now") HOST_SCHEDULE_RUN_NOW,
    @SerialName("host_schedule.plan") HOST_SCHEDULE_PLAN,
    @SerialName("native_schedule.inspect") NATIVE_SCHEDULE_INSPECT,
    @SerialName("native_schedule.update") NATIVE_SCHEDULE_UPDATE,
    @SerialName("native_schedule.enable") NATIVE_SCHEDULE_ENABLE,
    @SerialName("native_schedule.disable") NATIVE_SCHEDULE_DISABLE,
    @SerialName("native_schedule.inspect_pending") NATIVE_SCHEDULE_INSPECT_PENDING,
    @SerialName("native_schedule.discard_pending") NATIVE_SCHEDULE_DISCARD_PENDING,
    @SerialName("native_schedule.plan") NATIVE_SCHEDULE_PLAN,
    @SerialName("native_destination.inspect") NATIVE_DESTINATION_INSPECT,
    @SerialName("native_destination.update") NATIVE_DESTINATION_UPDATE,
    @SerialName("native_destination.plan") NATIVE_DESTINATION_PLAN,
}

@Serializable
enum class AgentBridgeDiscoveryEntitlement {
    @SerialName("satisfied") SATISFIED,
    @SerialName("required") REQUIRED,
}

@Serializable
enum class AgentBridgeDiscoveryFeaturesItem {
    @SerialName("explicit_settings") EXPLICIT_SETTINGS,
    @SerialName("zero_health_plan") ZERO_HEALTH_PLAN,
    @SerialName("bound_execution") BOUND_EXECUTION,
    @SerialName("source_query") SOURCE_QUERY,
    @SerialName("source_projection") SOURCE_PROJECTION,
    @SerialName("native_profile_control") NATIVE_PROFILE_CONTROL,
    @SerialName("native_schedule_control") NATIVE_SCHEDULE_CONTROL,
    @SerialName("native_destination_control") NATIVE_DESTINATION_CONTROL,
    @SerialName("control_plan") CONTROL_PLAN,
    @SerialName("zip") ZIP,
    @SerialName("profile_dictionary") PROFILE_DICTIONARY,
}

@Serializable
enum class AgentBridgeDiscoveryLifecycle {
    @SerialName("iphone_foreground_protected_data") IPHONE_FOREGROUND_PROTECTED_DATA,
    @SerialName("android_user_started_service_after_first_unlock") ANDROID_USER_STARTED_SERVICE_AFTER_FIRST_UNLOCK,
}

@Serializable
enum class AgentBridgeDiscoveryNativeGrants {
    @SerialName("satisfied") SATISFIED,
    @SerialName("required") REQUIRED,
    @SerialName("unverified") UNVERIFIED,
}

@Serializable
enum class AgentBridgeOutputProfile {
    @SerialName("apple-v8") APPLE_V8,
    @SerialName("android-frozen-v4") ANDROID_FROZEN_V4,
    @SerialName("android-analytical-v5") ANDROID_ANALYTICAL_V5,
}

@Serializable
enum class AgentBridgeCompatibilityDetail {
    @SerialName("summary") SUMMARY,
    @SerialName("selected_time_series") SELECTED_TIME_SERIES,
}

@Serializable
enum class AgentBridgeFormat {
    @SerialName("csv") CSV,
    @SerialName("json") JSON,
    @SerialName("markdown") MARKDOWN,
    @SerialName("obsidian_bases") OBSIDIAN_BASES,
}

@Serializable
enum class AgentBridgeOutputSupportNativeArchiveProductsItem {
    @SerialName("none") NONE,
    @SerialName("apple_healthkit_canonical_v1") APPLE_HEALTHKIT_CANONICAL_V1,
    @SerialName("android_provider_native_snapshot_v1") ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1,
}

@Serializable
enum class AgentBridgeOutputSupportPathTokensItem {
    @SerialName("year") YEAR,
    @SerialName("month") MONTH,
    @SerialName("day") DAY,
    @SerialName("date") DATE,
    @SerialName("metric") METRIC,
    @SerialName("category") CATEGORY,
    @SerialName("record_id") RECORD_ID,
}

@Serializable
enum class AgentBridgeWriteMode {
    @SerialName("overwrite") OVERWRITE,
    @SerialName("append") APPEND,
    @SerialName("merge_markdown") MERGE_MARKDOWN,
    @SerialName("merge_markdown_preserving_preamble") MERGE_MARKDOWN_PRESERVING_PREAMBLE,
}

@Serializable
enum class AgentBridgeDiscoveryProjectionProductsItem {
    @SerialName("android_source_projection_v1") ANDROID_SOURCE_PROJECTION_V1,
}

@Serializable
enum class AgentBridgeQueryCatalogFeatureStatusesItemStatus {
    @SerialName("available") AVAILABLE,
    @SerialName("unavailable") UNAVAILABLE,
    @SerialName("error") ERROR,
    @SerialName("unverified") UNVERIFIED,
}

@Serializable
enum class AgentBridgeCoverageHistoryFeatureStatus {
    @SerialName("available") AVAILABLE,
    @SerialName("unavailable") UNAVAILABLE,
    @SerialName("error") ERROR,
    @SerialName("not_applicable") NOT_APPLICABLE,
}

@Serializable
enum class AgentBridgeCoverageHistoryState {
    @SerialName("full_granted") FULL_GRANTED,
    @SerialName("bounded") BOUNDED,
    @SerialName("unverified") UNVERIFIED,
    @SerialName("not_applicable") NOT_APPLICABLE,
}

@Serializable
enum class AgentBridgeCoverageMissingItemReason {
    @SerialName("no_records") NO_RECORDS,
    @SerialName("unsupported") UNSUPPORTED,
    @SerialName("permission_required") PERMISSION_REQUIRED,
    @SerialName("history_limited") HISTORY_LIMITED,
    @SerialName("history_unverified") HISTORY_UNVERIFIED,
    @SerialName("failure") FAILURE,
    @SerialName("skipped") SKIPPED,
    @SerialName("cancelled") CANCELLED,
}

@Serializable
enum class AgentBridgeCoverageStatus {
    @SerialName("complete") COMPLETE,
    @SerialName("complete_empty") COMPLETE_EMPTY,
    @SerialName("partial") PARTIAL,
    @SerialName("unavailable") UNAVAILABLE,
    @SerialName("failed") FAILED,
    @SerialName("cancelled") CANCELLED,
}

@Serializable
enum class AgentBridgeCatalogItemAvailability {
    @SerialName("planned") PLANNED,
    @SerialName("unavailable") UNAVAILABLE,
    @SerialName("supported") SUPPORTED,
    @SerialName("permission_required") PERMISSION_REQUIRED,
    @SerialName("feature_unavailable") FEATURE_UNAVAILABLE,
    @SerialName("history_unverified") HISTORY_UNVERIFIED,
}

@Serializable
enum class AgentBridgeCatalogItemOwnerRule {
    @SerialName("civil_day_aggregate") CIVIL_DAY_AGGREGATE,
    @SerialName("source_start_civil_day") SOURCE_START_CIVIL_DAY,
    @SerialName("noon_to_noon_additive_native") NOON_TO_NOON_ADDITIVE_NATIVE,
    @SerialName("source_start_noon_journal") SOURCE_START_NOON_JOURNAL,
}

@Serializable
enum class AgentBridgeCatalogItemRegistryEquivalence {
    @SerialName("platform_exact_or_unavailable") PLATFORM_EXACT_OR_UNAVAILABLE,
    @SerialName("mapped_alias") MAPPED_ALIAS,
    @SerialName("platform_distinct") PLATFORM_DISTINCT,
}

@Serializable
enum class AgentBridgeCatalogItemStatisticsItem {
    @SerialName("sum") SUM,
    @SerialName("average") AVERAGE,
    @SerialName("minimum") MINIMUM,
    @SerialName("maximum") MAXIMUM,
    @SerialName("latest") LATEST,
    @SerialName("count") COUNT,
    @SerialName("duration_sum") DURATION_SUM,
}

@Serializable
enum class AgentBridgeQueryCatalogProviderAvailability {
    @SerialName("available") AVAILABLE,
    @SerialName("unavailable") UNAVAILABLE,
    @SerialName("update_required") UPDATE_REQUIRED,
    @SerialName("unverified") UNVERIFIED,
}

@Serializable
enum class AgentBridgeQueryCatalogSourceId {
    @SerialName("apple_health") APPLE_HEALTH,
    @SerialName("health_connect") HEALTH_CONNECT,
    @SerialName("provider_native") PROVIDER_NATIVE,
}

@Serializable
enum class AgentBridgeDiscoveryRequiredActionsItem {
    @SerialName("open_mobile_app") OPEN_MOBILE_APP,
    @SerialName("unlock_mobile") UNLOCK_MOBILE,
    @SerialName("grant_health_access") GRANT_HEALTH_ACCESS,
    @SerialName("grant_history_access") GRANT_HISTORY_ACCESS,
    @SerialName("native_configuration_unlock") NATIVE_CONFIGURATION_UNLOCK,
    @SerialName("native_destination_rebind") NATIVE_DESTINATION_REBIND,
    @SerialName("purchase_required") PURCHASE_REQUIRED,
}

@Serializable
enum class AgentBridgeDiscoverySettingsPoliciesItem {
    @SerialName("explicit") EXPLICIT,
    @SerialName("saved_device_settings") SAVED_DEVICE_SETTINGS,
    @SerialName("profile") PROFILE,
}

@Serializable
enum class AgentBridgeArchiveAndroidProviderNativeSnapshotV1Format {
    @SerialName("json") JSON,
    @SerialName("ndjson") NDJSON,
}

@Serializable
enum class AgentBridgeArchiveAndroidProviderNativeSnapshotV1RecordScope {
    @SerialName("selected") SELECTED,
    @SerialName("all_authorized_supported") ALL_AUTHORIZED_SUPPORTED,
}

@Serializable
enum class AgentBridgeDictionaryProfileDictionaryV1Format {
    @SerialName("json") JSON,
    @SerialName("markdown") MARKDOWN,
}

@Serializable
enum class AgentBridgePresentationDisplayUnits {
    @SerialName("metric") METRIC,
    @SerialName("imperial") IMPERIAL,
}

@Serializable
enum class AgentBridgeMarkdownStyle {
    @SerialName("tables") TABLES,
    @SerialName("lists") LISTS,
}

@Serializable
enum class AgentBridgeProjectionOutputMediaType {
    @SerialName("application/json") APPLICATION_JSON,
    @SerialName("application/x-ndjson") APPLICATION_X_NDJSON,
}

@Serializable
enum class AgentBridgeProjectionOutputWriteMode {
    @SerialName("overwrite") OVERWRITE,
    @SerialName("append") APPEND,
}

@Serializable
enum class AgentBridgeProjectionRequestDetail {
    @SerialName("summary") SUMMARY,
    @SerialName("selected_time_series") SELECTED_TIME_SERIES,
    @SerialName("native_records") NATIVE_RECORDS,
}

@Serializable
enum class AgentBridgeProjectionRequestObjectIdsItem {
    @SerialName("daily_summary") DAILY_SUMMARY,
    @SerialName("selected_series") SELECTED_SERIES,
    @SerialName("native_records") NATIVE_RECORDS,
    @SerialName("capture_manifest") CAPTURE_MANIFEST,
}

@Serializable
enum class AgentBridgeProjectionRequestSourceId {
    @SerialName("health_connect") HEALTH_CONNECT,
    @SerialName("provider_native") PROVIDER_NATIVE,
}

@Serializable
enum class AgentBridgeOriginOrigin {
    @SerialName("request") REQUEST,
    @SerialName("saved_device_settings") SAVED_DEVICE_SETTINGS,
    @SerialName("profile") PROFILE,
    @SerialName("resolved_calendar") RESOLVED_CALENDAR,
    @SerialName("catalog") CATALOG,
}

@Serializable
enum class AgentBridgeGeneratedPlanPathPrediction {
    @SerialName("exact_requested_days") EXACT_REQUESTED_DAYS,
    @SerialName("template_only_all_available") TEMPLATE_ONLY_ALL_AVAILABLE,
    @SerialName("deferred_native_entries") DEFERRED_NATIVE_ENTRIES,
}

@Serializable
enum class AgentBridgeRevisionDomain {
    @SerialName("device_settings") DEVICE_SETTINGS,
    @SerialName("native_profile") NATIVE_PROFILE,
    @SerialName("local_recipe") LOCAL_RECIPE,
    @SerialName("host_schedule") HOST_SCHEDULE,
    @SerialName("native_schedule") NATIVE_SCHEDULE,
    @SerialName("native_destination") NATIVE_DESTINATION,
    @SerialName("native_credential_reference") NATIVE_CREDENTIAL_REFERENCE,
}

@Serializable
enum class AgentBridgeApprovalRightsItem {
    @SerialName("export_execute") EXPORT_EXECUTE,
}

@Serializable
enum class AgentBridgeExecutionReceiptStatus {
    @SerialName("accepted") ACCEPTED,
    @SerialName("paused") PAUSED,
    @SerialName("complete") COMPLETE,
    @SerialName("complete_empty") COMPLETE_EMPTY,
    @SerialName("partial") PARTIAL,
    @SerialName("failed") FAILED,
    @SerialName("cancellation_pending") CANCELLATION_PENDING,
    @SerialName("cancelled") CANCELLED,
    @SerialName("expired") EXPIRED,
}

@Serializable
enum class AgentBridgeArtifactMediaType {
    @SerialName("application/json") APPLICATION_JSON,
    @SerialName("application/x-ndjson") APPLICATION_X_NDJSON,
    @SerialName("text/csv") TEXT_CSV,
    @SerialName("text/markdown") TEXT_MARKDOWN,
    @SerialName("application/zip") APPLICATION_ZIP,
}

@Serializable
enum class AgentBridgeArtifactProfile {
    @SerialName("apple-v8") APPLE_V8,
    @SerialName("android-frozen-v4") ANDROID_FROZEN_V4,
    @SerialName("android-analytical-v5") ANDROID_ANALYTICAL_V5,
    @SerialName("apple-healthkit-canonical-v1") APPLE_HEALTHKIT_CANONICAL_V1,
    @SerialName("android-provider-native-snapshot-v1") ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1,
    @SerialName("profile-dictionary-v1") PROFILE_DICTIONARY_V1,
    @SerialName("zip-container-v1") ZIP_CONTAINER_V1,
    @SerialName("android-source-projection-v1") ANDROID_SOURCE_PROJECTION_V1,
}

@Serializable
enum class AgentBridgeArtifactManifestBranchStatusesItemStatus {
    @SerialName("success") SUCCESS,
    @SerialName("unsupported") UNSUPPORTED,
    @SerialName("skipped") SKIPPED,
    @SerialName("failure") FAILURE,
    @SerialName("cancelled") CANCELLED,
}

@Serializable
enum class AgentBridgeArtifactManifestCaptureStatus {
    @SerialName("complete") COMPLETE,
    @SerialName("complete_empty") COMPLETE_EMPTY,
    @SerialName("partial") PARTIAL,
    @SerialName("failed") FAILED,
    @SerialName("cancelled") CANCELLED,
}

@Serializable
enum class AgentBridgeCommitReceiptStatus {
    @SerialName("committed") COMMITTED,
    @SerialName("already_committed") ALREADY_COMMITTED,
    @SerialName("conflict") CONFLICT,
}

@Serializable
enum class AgentBridgeAuthorityConfigurationProtection {
    @SerialName("not_applicable") NOT_APPLICABLE,
    @SerialName("unlocked_native") UNLOCKED_NATIVE,
    @SerialName("locked") LOCKED,
}

@Serializable
enum class AgentBridgeControlReadScopeCreateDomainsItem {
    @SerialName("local_recipe") LOCAL_RECIPE,
    @SerialName("native_profile") NATIVE_PROFILE,
    @SerialName("host_schedule") HOST_SCHEDULE,
}

@Serializable
enum class AgentBridgeControlReadScopeListDomainsItem {
    @SerialName("local_recipe") LOCAL_RECIPE,
    @SerialName("native_profile") NATIVE_PROFILE,
    @SerialName("host_schedule") HOST_SCHEDULE,
    @SerialName("native_schedule") NATIVE_SCHEDULE,
    @SerialName("native_destination") NATIVE_DESTINATION,
}

@Serializable
enum class AgentBridgeAuthorityRightsItem {
    @SerialName("discover") DISCOVER,
    @SerialName("plan") PLAN,
    @SerialName("query_summary") QUERY_SUMMARY,
    @SerialName("query_evidence") QUERY_EVIDENCE,
    @SerialName("export_execute") EXPORT_EXECUTE,
    @SerialName("recipe_read") RECIPE_READ,
    @SerialName("recipe_mutate") RECIPE_MUTATE,
    @SerialName("recipe_run") RECIPE_RUN,
    @SerialName("native_configuration_read") NATIVE_CONFIGURATION_READ,
    @SerialName("native_configuration_mutate") NATIVE_CONFIGURATION_MUTATE,
    @SerialName("host_schedule_read") HOST_SCHEDULE_READ,
    @SerialName("host_schedule_mutate") HOST_SCHEDULE_MUTATE,
    @SerialName("host_schedule_run") HOST_SCHEDULE_RUN,
    @SerialName("native_schedule_mutate") NATIVE_SCHEDULE_MUTATE,
}

@Serializable
enum class AgentBridgeExportDelegationBoundsProductsItem {
    @SerialName("generated_files") GENERATED_FILES,
    @SerialName("android_source_projection_v1") ANDROID_SOURCE_PROJECTION_V1,
}

@Serializable
enum class AgentBridgeExportDelegationRightsItem {
    @SerialName("discover") DISCOVER,
    @SerialName("plan") PLAN,
    @SerialName("export_execute") EXPORT_EXECUTE,
}

@Serializable
enum class AgentBridgeErrorCode {
    @SerialName("invalid_request") INVALID_REQUEST,
    @SerialName("unsupported_capability") UNSUPPORTED_CAPABILITY,
    @SerialName("unsupported_metric") UNSUPPORTED_METRIC,
    @SerialName("permission_required") PERMISSION_REQUIRED,
    @SerialName("history_unverified") HISTORY_UNVERIFIED,
    @SerialName("configuration_protected") CONFIGURATION_PROTECTED,
    @SerialName("entitlement_required") ENTITLEMENT_REQUIRED,
    @SerialName("native_rebind_required") NATIVE_REBIND_REQUIRED,
    @SerialName("revision_conflict") REVISION_CONFLICT,
    @SerialName("approval_required") APPROVAL_REQUIRED,
    @SerialName("binding_changed") BINDING_CHANGED,
    @SerialName("plan_expired") PLAN_EXPIRED,
    @SerialName("unsafe_path") UNSAFE_PATH,
    @SerialName("path_collision") PATH_COLLISION,
    @SerialName("query_budget_exceeded") QUERY_BUDGET_EXCEEDED,
    @SerialName("cursor_invalid") CURSOR_INVALID,
    @SerialName("snapshot_expired") SNAPSHOT_EXPIRED,
    @SerialName("busy") BUSY,
    @SerialName("cancelled") CANCELLED,
    @SerialName("spool_missing_restart_required") SPOOL_MISSING_RESTART_REQUIRED,
    @SerialName("job_expired") JOB_EXPIRED,
}

@Serializable
enum class AgentBridgeQueryRequestDetail {
    @SerialName("summary") SUMMARY,
    @SerialName("native_evidence") NATIVE_EVIDENCE,
}

@Serializable
enum class AgentBridgeQueryOperationDerivePacketKind {
    @SerialName("daily_wellness") DAILY_WELLNESS,
    @SerialName("training") TRAINING,
    @SerialName("doctor_visit") DOCTOR_VISIT,
}

@Serializable
enum class AgentBridgeMetricItemAvailability {
    @SerialName("available") AVAILABLE,
    @SerialName("missing") MISSING,
    @SerialName("unsupported") UNSUPPORTED,
    @SerialName("permission_required") PERMISSION_REQUIRED,
    @SerialName("history_limited") HISTORY_LIMITED,
    @SerialName("failed") FAILED,
    @SerialName("skipped") SKIPPED,
}

@Serializable
enum class AgentBridgeSessionItemClassification {
    @SerialName("principal") PRINCIPAL,
    @SerialName("nap") NAP,
    @SerialName("unclassified") UNCLASSIFIED,
    @SerialName("completed_workout") COMPLETED_WORKOUT,
}

@Serializable
enum class AgentBridgeExactTimePrecision {
    @SerialName("source_nanoseconds") SOURCE_NANOSECONDS,
    @SerialName("source_milliseconds") SOURCE_MILLISECONDS,
    @SerialName("source_seconds") SOURCE_SECONDS,
    @SerialName("source_binary64_seconds") SOURCE_BINARY64_SECONDS,
}

@Serializable
enum class AgentBridgeNativeIdentityAppleHealthIdentityKind {
    @SerialName("native") NATIVE,
    @SerialName("derived_child") DERIVED_CHILD,
    @SerialName("external") EXTERNAL,
}

@Serializable
enum class AgentBridgeClientIdAvailability {
    @SerialName("available") AVAILABLE,
    @SerialName("absent") ABSENT,
    @SerialName("not_captured") NOT_CAPTURED,
    @SerialName("not_exposed_by_source") NOT_EXPOSED_BY_SOURCE,
}

@Serializable
enum class AgentBridgeMetadataAvailability {
    @SerialName("available") AVAILABLE,
    @SerialName("not_captured") NOT_CAPTURED,
    @SerialName("not_exposed_by_source") NOT_EXPOSED_BY_SOURCE,
}

@Serializable
enum class AgentBridgeSessionItemKind {
    @SerialName("sleep") SLEEP,
    @SerialName("workout") WORKOUT,
}

@Serializable
enum class AgentBridgeAlignmentItemStatus {
    @SerialName("complete") COMPLETE,
    @SerialName("partial") PARTIAL,
    @SerialName("unavailable") UNAVAILABLE,
}

@Serializable
enum class AgentBridgeProjectionCatalogFieldsItemObjectId {
    @SerialName("daily_summary") DAILY_SUMMARY,
    @SerialName("selected_series") SELECTED_SERIES,
    @SerialName("native_records") NATIVE_RECORDS,
}

@Serializable
enum class AgentBridgeProjectionCatalogFieldsItemValueRole {
    @SerialName("daily_aggregate") DAILY_AGGREGATE,
    @SerialName("point") POINT,
    @SerialName("interval_total") INTERVAL_TOTAL,
    @SerialName("native_record") NATIVE_RECORD,
}

@Serializable
enum class AgentBridgeSourceObservationObservationKind {
    @SerialName("point") POINT,
    @SerialName("interval_total") INTERVAL_TOTAL,
}

@Serializable(with = AgentBridgeArchiveSerializer::class)
sealed interface AgentBridgeArchive

object AgentBridgeArchiveSerializer : JsonContentPolymorphicSerializer<AgentBridgeArchive>(AgentBridgeArchive::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeArchive> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.archive(element))
}

@Serializable(with = AgentBridgeDatesSerializer::class)
sealed interface AgentBridgeDates

object AgentBridgeDatesSerializer : JsonContentPolymorphicSerializer<AgentBridgeDates>(AgentBridgeDates::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeDates> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.dates(element))
}

@Serializable(with = AgentBridgeDictionarySerializer::class)
sealed interface AgentBridgeDictionary

object AgentBridgeDictionarySerializer : JsonContentPolymorphicSerializer<AgentBridgeDictionary>(AgentBridgeDictionary::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeDictionary> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.dictionary(element))
}

@Serializable(with = AgentBridgePackagingSerializer::class)
sealed interface AgentBridgePackaging

object AgentBridgePackagingSerializer : JsonContentPolymorphicSerializer<AgentBridgePackaging>(AgentBridgePackaging::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgePackaging> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.packaging(element))
}

@Serializable(with = AgentBridgeSettingsPolicySerializer::class)
sealed interface AgentBridgeSettingsPolicy

object AgentBridgeSettingsPolicySerializer : JsonContentPolymorphicSerializer<AgentBridgeSettingsPolicy>(AgentBridgeSettingsPolicy::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeSettingsPolicy> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.settingsPolicy(element))
}

@Serializable(with = AgentBridgeIntentSerializer::class)
sealed interface AgentBridgeIntent : AgentBridgeDocument

object AgentBridgeIntentSerializer : JsonContentPolymorphicSerializer<AgentBridgeIntent>(AgentBridgeIntent::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeIntent> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.intent(element))
}

@Serializable(with = AgentBridgePlanSerializer::class)
sealed interface AgentBridgePlan : AgentBridgeDocument

object AgentBridgePlanSerializer : JsonContentPolymorphicSerializer<AgentBridgePlan>(AgentBridgePlan::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgePlan> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.plan(element))
}

@Serializable(with = AgentBridgeExportDelegationBoundsDatePolicySerializer::class)
sealed interface AgentBridgeExportDelegationBoundsDatePolicy

object AgentBridgeExportDelegationBoundsDatePolicySerializer : JsonContentPolymorphicSerializer<AgentBridgeExportDelegationBoundsDatePolicy>(AgentBridgeExportDelegationBoundsDatePolicy::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeExportDelegationBoundsDatePolicy> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.exportDelegationBoundsDatePolicy(element))
}

@Serializable(with = AgentBridgeExportDelegationBoundsDestinationPolicySerializer::class)
sealed interface AgentBridgeExportDelegationBoundsDestinationPolicy

object AgentBridgeExportDelegationBoundsDestinationPolicySerializer : JsonContentPolymorphicSerializer<AgentBridgeExportDelegationBoundsDestinationPolicy>(AgentBridgeExportDelegationBoundsDestinationPolicy::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeExportDelegationBoundsDestinationPolicy> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.exportDelegationBoundsDestinationPolicy(element))
}

@Serializable(with = AgentBridgeQueryOperationSerializer::class)
sealed interface AgentBridgeQueryOperation

object AgentBridgeQueryOperationSerializer : JsonContentPolymorphicSerializer<AgentBridgeQueryOperation>(AgentBridgeQueryOperation::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeQueryOperation> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.queryOperation(element))
}

@Serializable(with = AgentBridgeValueSerializer::class)
sealed interface AgentBridgeValue

object AgentBridgeValueSerializer : JsonContentPolymorphicSerializer<AgentBridgeValue>(AgentBridgeValue::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeValue> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.value(element))
}

@Serializable(with = AgentBridgeNativeIdentitySerializer::class)
sealed interface AgentBridgeNativeIdentity

object AgentBridgeNativeIdentitySerializer : JsonContentPolymorphicSerializer<AgentBridgeNativeIdentity>(AgentBridgeNativeIdentity::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeNativeIdentity> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.nativeIdentity(element))
}

@Serializable(with = AgentBridgeQueryResponseSerializer::class)
sealed interface AgentBridgeQueryResponse : AgentBridgeDocument

object AgentBridgeQueryResponseSerializer : JsonContentPolymorphicSerializer<AgentBridgeQueryResponse>(AgentBridgeQueryResponse::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeQueryResponse> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.queryResponse(element))
}

@Serializable
data class AgentBridgeDiscoveryRequest(
    val peer: AgentBridgePeer,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_discovery_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgePeer(
    @SerialName("host_installation_id") val hostInstallationId: String,
    val platform: AgentBridgePlatform,
    @SerialName("source_installation_id") val sourceInstallationId: String,
) {
    init {
        AgentBridgeChecks.text(hostInstallationId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(sourceInstallationId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
    }
}

@Serializable
data class AgentBridgeDiscovery(
    @SerialName("authority_references") val authorityReferences: List<AgentBridgeAuthorityReference>,
    val budgets: AgentBridgeBudgets,
    @SerialName("capability_revision") val capabilityRevision: Int,
    @SerialName("capability_sha256") val capabilitySha256: String,
    @SerialName("configuration_protection") val configurationProtection: AgentBridgeDiscoveryConfigurationProtection,
    @SerialName("control_operations") val controlOperations: List<AgentBridgeDiscoveryControlOperationsItem>,
    val entitlement: AgentBridgeDiscoveryEntitlement,
    @SerialName("expires_at") val expiresAt: String,
    val features: List<AgentBridgeDiscoveryFeaturesItem>,
    @SerialName("issued_at") val issuedAt: String,
    val lifecycle: AgentBridgeDiscoveryLifecycle,
    @SerialName("native_grants") val nativeGrants: AgentBridgeDiscoveryNativeGrants,
    @SerialName("output_profiles") val outputProfiles: List<AgentBridgeOutputProfile>,
    @SerialName("output_support") val outputSupport: AgentBridgeOutputSupport,
    val peer: AgentBridgePeer,
    @SerialName("projection_catalog_sha256") val projectionCatalogSha256: String,
    @SerialName("projection_products") val projectionProducts: List<AgentBridgeDiscoveryProjectionProductsItem>,
    @SerialName("projection_source_catalog") val projectionSourceCatalog: AgentBridgeQueryCatalog? = null,
    @SerialName("query_catalog_sha256") val queryCatalogSha256: String,
    @SerialName("query_operations") val queryOperations: List<String>,
    @SerialName("request_id") val requestId: String,
    @SerialName("required_actions") val requiredActions: List<AgentBridgeDiscoveryRequiredActionsItem>,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("settings_policies") val settingsPolicies: List<AgentBridgeDiscoverySettingsPoliciesItem>,
    @SerialName("source_calendar_timezone") val sourceCalendarTimezone: String,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.require(authorityReferences.size in 0..32)
        AgentBridgeChecks.require(capabilityRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.text(capabilitySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(controlOperations.size in 0..64)
        AgentBridgeChecks.require(controlOperations.distinct().size == controlOperations.size)
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(features.size in 0..11)
        AgentBridgeChecks.require(features.distinct().size == features.size)
        AgentBridgeChecks.text(issuedAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(outputProfiles.size in 0..3)
        AgentBridgeChecks.require(outputProfiles.distinct().size == outputProfiles.size)
        AgentBridgeChecks.text(projectionCatalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(projectionProducts.size in 0..1)
        AgentBridgeChecks.require(projectionProducts.distinct().size == projectionProducts.size)
        AgentBridgeChecks.text(queryCatalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(queryOperations.size in 0..9)
        AgentBridgeChecks.require(queryOperations.distinct().size == queryOperations.size)
        queryOperations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(requiredActions.size in 0..16)
        AgentBridgeChecks.require(requiredActions.distinct().size == requiredActions.size)
        AgentBridgeChecks.require(schema == "healthmd.agent_discovery")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(settingsPolicies.size in 0..3)
        AgentBridgeChecks.require(settingsPolicies.distinct().size == settingsPolicies.size)
        AgentBridgeChecks.text(sourceCalendarTimezone, 1, 128)
    }
}

@Serializable
data class AgentBridgeAuthorityReference(
    @SerialName("authority_id") val authorityId: String,
    @SerialName("grant_revision") val grantRevision: Int,
    @SerialName("grant_sha256") val grantSha256: String,
    val issuer: AgentBridgeIssuer,
) {
    init {
        AgentBridgeChecks.text(authorityId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(grantRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.text(grantSha256, 64, 64, "^[0-9a-f]{64}\$")
    }
}

@Serializable
data class AgentBridgeBudgets(
    @SerialName("cursor_idle_seconds") val cursorIdleSeconds: Int,
    @SerialName("cursor_lifetime_seconds") val cursorLifetimeSeconds: Int,
    @SerialName("max_calendar_days") val maxCalendarDays: Int,
    @SerialName("max_capture_seconds") val maxCaptureSeconds: Int,
    @SerialName("max_page_bytes") val maxPageBytes: Int,
    @SerialName("max_page_items") val maxPageItems: Int,
    @SerialName("max_snapshot_bytes") val maxSnapshotBytes: Int,
) {
    init {
        AgentBridgeChecks.require(cursorIdleSeconds.toLong() in 1L..600L)
        AgentBridgeChecks.require(cursorLifetimeSeconds.toLong() in 1L..3600L)
        AgentBridgeChecks.require(maxCalendarDays.toLong() in 1L..366000L)
        AgentBridgeChecks.require(maxCaptureSeconds.toLong() in 1L..120L)
        AgentBridgeChecks.require(maxPageBytes.toLong() in 1024L..1048576L)
        AgentBridgeChecks.require(maxPageItems.toLong() in 1L..1000L)
        AgentBridgeChecks.require(maxSnapshotBytes.toLong() in 1024L..67108864L)
    }
}

@Serializable
data class AgentBridgeOutputSupport(
    @SerialName("compatibility_detail") val compatibilityDetail: List<AgentBridgeCompatibilityDetail>,
    val formats: List<AgentBridgeFormat>,
    @SerialName("max_artifacts") val maxArtifacts: Int,
    @SerialName("max_path_bytes") val maxPathBytes: Int,
    @SerialName("native_archive_products") val nativeArchiveProducts: List<AgentBridgeOutputSupportNativeArchiveProductsItem>,
    @SerialName("path_tokens") val pathTokens: List<AgentBridgeOutputSupportPathTokensItem>,
    @SerialName("setting_pointers") val settingPointers: List<String>,
    @SerialName("write_modes") val writeModes: List<AgentBridgeWriteMode>,
) {
    init {
        AgentBridgeChecks.require(compatibilityDetail.size in 0..2)
        AgentBridgeChecks.require(compatibilityDetail.distinct().size == compatibilityDetail.size)
        AgentBridgeChecks.require(formats.size in 0..4)
        AgentBridgeChecks.require(formats.distinct().size == formats.size)
        AgentBridgeChecks.require(maxArtifacts.toLong() in 1L..4096L)
        AgentBridgeChecks.require(maxPathBytes.toLong() in 1L..4096L)
        AgentBridgeChecks.require(nativeArchiveProducts.size in 0..3)
        AgentBridgeChecks.require(nativeArchiveProducts.distinct().size == nativeArchiveProducts.size)
        AgentBridgeChecks.require(pathTokens.size in 0..7)
        AgentBridgeChecks.require(pathTokens.distinct().size == pathTokens.size)
        AgentBridgeChecks.require(settingPointers.size in 0..512)
        AgentBridgeChecks.require(settingPointers.distinct().size == settingPointers.size)
        settingPointers.forEach { AgentBridgeChecks.text(it, 1, 256, "^/[a-z0-9_/]+\$") }
        AgentBridgeChecks.require(writeModes.size in 0..4)
        AgentBridgeChecks.require(writeModes.distinct().size == writeModes.size)
    }
}

@Serializable
data class AgentBridgeQueryCatalog(
    val budgets: AgentBridgeBudgets,
    @SerialName("feature_statuses") val featureStatuses: List<AgentBridgeQueryCatalogFeatureStatusesItem>,
    val history: AgentBridgeCoverage,
    val metrics: List<AgentBridgeCatalogItem>,
    val operations: List<String>,
    val peer: AgentBridgePeer,
    @SerialName("provider_availability") val providerAvailability: AgentBridgeQueryCatalogProviderAvailability,
    @SerialName("provider_id") val providerId: String,
    @SerialName("provider_version") val providerVersion: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("sdk_version") val sdkVersion: String,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.require(featureStatuses.size in 0..32)
        AgentBridgeChecks.require(metrics.size in 0..256)
        AgentBridgeChecks.require(operations.size in 0..9)
        AgentBridgeChecks.require(operations.distinct().size == operations.size)
        operations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(providerVersion, 1, 128)
        AgentBridgeChecks.require(schema == "healthmd.source_query_catalog")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.text(sdkVersion, 1, 64)
    }
}

@Serializable
data class AgentBridgeQueryCatalogFeatureStatusesItem(
    val feature: String,
    val status: AgentBridgeQueryCatalogFeatureStatusesItemStatus,
) {
    init {
        AgentBridgeChecks.text(feature, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeCoverage(
    @SerialName("days_considered") val daysConsidered: Int,
    @SerialName("days_with_values") val daysWithValues: Int,
    val history: AgentBridgeCoverageHistory,
    val missing: List<AgentBridgeCoverageMissingItem>,
    @SerialName("missing_count") val missingCount: Int,
    @SerialName("missing_truncated") val missingTruncated: Boolean,
    val status: AgentBridgeCoverageStatus,
) {
    init {
        AgentBridgeChecks.require(daysConsidered.toLong() in 0L..366000L)
        AgentBridgeChecks.require(daysWithValues.toLong() in 0L..366000L)
        AgentBridgeChecks.require(missing.size in 0..64)
        AgentBridgeChecks.require(missingCount.toLong() in 0L..2147483647L)
    }
}

@Serializable
data class AgentBridgeCoverageHistory(
    val boundary: String? = null,
    @SerialName("feature_status") val featureStatus: AgentBridgeCoverageHistoryFeatureStatus,
    val state: AgentBridgeCoverageHistoryState,
) {
    init {
        boundary?.let {
            AgentBridgeChecks.text(it, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
        }
    }
}

@Serializable
data class AgentBridgeCoverageMissingItem(
    @SerialName("metric_id") val metricId: String,
    val range: AgentBridgeRange,
    val reason: AgentBridgeCoverageMissingItemReason,
) {
    init {
        AgentBridgeChecks.text(metricId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeRange(
    @SerialName("end_date") val endDate: String,
    @SerialName("start_date") val startDate: String,
) {
    init {
        AgentBridgeChecks.text(endDate, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
        AgentBridgeChecks.text(startDate, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
    }
}

@Serializable
data class AgentBridgeCatalogItem(
    val availability: AgentBridgeCatalogItemAvailability,
    @SerialName("evidence_value_support") val evidenceValueSupport: Boolean,
    @SerialName("feature_gate") val featureGate: String,
    @SerialName("metric_id") val metricId: String,
    @SerialName("native_record_type") val nativeRecordType: String? = null,
    @SerialName("owner_rule") val ownerRule: AgentBridgeCatalogItemOwnerRule,
    @SerialName("registry_equivalence") val registryEquivalence: AgentBridgeCatalogItemRegistryEquivalence,
    @SerialName("source_statistic") val sourceStatistic: String,
    val statistics: List<AgentBridgeCatalogItemStatisticsItem>,
    @SerialName("target_or_reason") val targetOrReason: String,
    val type: String,
    val unit: String,
) {
    init {
        AgentBridgeChecks.text(featureGate, 0, 128)
        AgentBridgeChecks.text(metricId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        nativeRecordType?.let {
            AgentBridgeChecks.text(it, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        }
        AgentBridgeChecks.text(sourceStatistic, 1, 128)
        AgentBridgeChecks.require(statistics.size in 1..7)
        AgentBridgeChecks.require(statistics.distinct().size == statistics.size)
        AgentBridgeChecks.text(targetOrReason, 1, 256)
        AgentBridgeChecks.require(type == "catalog_metric")
        AgentBridgeChecks.text(unit, 1, 32)
    }
}

@Serializable
data class AgentBridgeGeneratedIntent(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("capture_scope") val captureScope: AgentBridgeCapture,
    val dates: AgentBridgeDates,
    val destination: AgentBridgeDestination,
    @SerialName("intent_id") val intentId: String,
    val peer: AgentBridgePeer,
    val product: AgentBridgeGeneratedIntentProduct,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("settings_policy") val settingsPolicy: AgentBridgeSettingsPolicy,
    @SerialName("timestamp_timezone") val timestampTimezone: String,
) : AgentBridgeIntent {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(intentId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_export_intent")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(timestampTimezone == "UTC")
    }
}

@Serializable
data class AgentBridgeCapture(
    @SerialName("compatibility_detail") val compatibilityDetail: AgentBridgeCompatibilityDetail,
    @SerialName("native_archive") val nativeArchive: AgentBridgeArchive,
    val selection: AgentBridgeSelection,
) {
    init {
    }
}

@Serializable
data class AgentBridgeArchiveNone(
    val type: String,
) : AgentBridgeArchive {
    init {
        AgentBridgeChecks.require(type == "none")
    }
}

@Serializable
data class AgentBridgeArchiveAppleHealthkitCanonicalV1(
    val type: String,
) : AgentBridgeArchive {
    init {
        AgentBridgeChecks.require(type == "apple_healthkit_canonical_v1")
    }
}

@Serializable
data class AgentBridgeArchiveAndroidProviderNativeSnapshotV1(
    val format: AgentBridgeArchiveAndroidProviderNativeSnapshotV1Format,
    @SerialName("include_exercise_routes") val includeExerciseRoutes: Boolean,
    @SerialName("provider_id") val providerId: String,
    @SerialName("record_scope") val recordScope: AgentBridgeArchiveAndroidProviderNativeSnapshotV1RecordScope,
    val type: String,
) : AgentBridgeArchive {
    init {
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.require(type == "android_provider_native_snapshot_v1")
    }
}

@Serializable
data class AgentBridgeSelection(
    @SerialName("all_metrics") val allMetrics: Boolean,
    @SerialName("category_ids") val categoryIds: List<String>,
    @SerialName("metric_ids") val metricIds: List<String>,
    @SerialName("provider_ids") val providerIds: List<String>,
    @SerialName("source_ids") val sourceIds: List<String>,
) {
    init {
        AgentBridgeChecks.require(categoryIds.size in 0..32)
        AgentBridgeChecks.require(categoryIds.distinct().size == categoryIds.size)
        categoryIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(metricIds.size in 0..256)
        AgentBridgeChecks.require(metricIds.distinct().size == metricIds.size)
        metricIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(providerIds.size in 0..16)
        AgentBridgeChecks.require(providerIds.distinct().size == providerIds.size)
        providerIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(sourceIds.size in 1..16)
        AgentBridgeChecks.require(sourceIds.distinct().size == sourceIds.size)
        sourceIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
    }
}

@Serializable
data class AgentBridgeDatesExact(
    val range: AgentBridgeRange,
    val type: String,
) : AgentBridgeDates {
    init {
        AgentBridgeChecks.require(type == "exact")
    }
}

@Serializable
data class AgentBridgeDatesAllAvailable(
    val type: String,
) : AgentBridgeDates {
    init {
        AgentBridgeChecks.require(type == "all_available")
    }
}

@Serializable
data class AgentBridgeDatesPastCompleteDays(
    @SerialName("anchor_date") val anchorDate: String,
    val days: Int,
    val type: String,
) : AgentBridgeDates {
    init {
        AgentBridgeChecks.text(anchorDate, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
        AgentBridgeChecks.require(days.toLong() in 1L..3650L)
        AgentBridgeChecks.require(type == "past_complete_days")
    }
}

@Serializable
data class AgentBridgeDestination(
    @SerialName("binding_id") val bindingId: String,
    @SerialName("host_installation_id") val hostInstallationId: String,
    @SerialName("identity_sha256") val identitySha256: String,
    val revision: Int,
) {
    init {
        AgentBridgeChecks.text(bindingId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(hostInstallationId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(identitySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(revision.toLong() in 1L..2147483647L)
    }
}

@Serializable
data class AgentBridgeGeneratedIntentProduct(
    val type: String,
) {
    init {
        AgentBridgeChecks.require(type == "generated_files")
    }
}

@Serializable
data class AgentBridgeSettingsPolicyExplicit(
    val settings: AgentBridgeOutputSettings,
    val type: String,
) : AgentBridgeSettingsPolicy {
    init {
        AgentBridgeChecks.require(type == "explicit")
    }
}

@Serializable
data class AgentBridgeOutputSettings(
    @SerialName("daily_notes") val dailyNotes: AgentBridgeDailyNotes,
    val dictionary: AgentBridgeDictionary,
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("folder_template") val folderTemplate: String,
    val formats: List<AgentBridgeFormat>,
    @SerialName("individual_entries") val individualEntries: AgentBridgeIndividualEntries,
    @SerialName("output_profile") val outputProfile: AgentBridgeOutputProfile,
    val packaging: AgentBridgePackaging,
    val presentation: AgentBridgePresentation,
    val subfolder: String,
    @SerialName("write_mode") val writeMode: AgentBridgeWriteMode,
) {
    init {
        AgentBridgeChecks.text(filenameTemplate, 1, 255)
        AgentBridgeChecks.text(folderTemplate, 0, 4096)
        AgentBridgeChecks.require(formats.size in 1..4)
        AgentBridgeChecks.require(formats.distinct().size == formats.size)
        AgentBridgeChecks.text(subfolder, 0, 4096)
    }
}

@Serializable
data class AgentBridgeDailyNotes(
    @SerialName("create_if_missing") val createIfMissing: Boolean,
    val enabled: Boolean,
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("folder_template") val folderTemplate: String,
    val only: Boolean,
    @SerialName("section_ids") val sectionIds: List<String>,
) {
    init {
        AgentBridgeChecks.text(filenameTemplate, 1, 255)
        AgentBridgeChecks.text(folderTemplate, 0, 4096)
        AgentBridgeChecks.require(sectionIds.size in 0..64)
        AgentBridgeChecks.require(sectionIds.distinct().size == sectionIds.size)
        sectionIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
    }
}

@Serializable
data class AgentBridgeDictionaryNone(
    val type: String,
) : AgentBridgeDictionary {
    init {
        AgentBridgeChecks.require(type == "none")
    }
}

@Serializable
data class AgentBridgeDictionaryProfileDictionaryV1(
    @SerialName("filename_template") val filenameTemplate: String,
    val format: AgentBridgeDictionaryProfileDictionaryV1Format,
    val type: String,
) : AgentBridgeDictionary {
    init {
        AgentBridgeChecks.text(filenameTemplate, 1, 255)
        AgentBridgeChecks.require(type == "profile_dictionary_v1")
    }
}

@Serializable
data class AgentBridgeIndividualEntries(
    @SerialName("category_folders") val categoryFolders: Boolean,
    val enabled: Boolean,
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("folder_template") val folderTemplate: String,
    @SerialName("metric_ids") val metricIds: List<String>,
) {
    init {
        AgentBridgeChecks.text(filenameTemplate, 1, 255)
        AgentBridgeChecks.text(folderTemplate, 0, 4096)
        AgentBridgeChecks.require(metricIds.size in 0..256)
        AgentBridgeChecks.require(metricIds.distinct().size == metricIds.size)
        metricIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
    }
}

@Serializable
data class AgentBridgePackagingLooseFiles(
    val type: String,
) : AgentBridgePackaging {
    init {
        AgentBridgeChecks.require(type == "loose_files")
    }
}

@Serializable
data class AgentBridgePackagingZip(
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("include_loose_files") val includeLooseFiles: Boolean,
    val manifest: String,
    @SerialName("max_entries") val maxEntries: Int,
    @SerialName("max_uncompressed_bytes") val maxUncompressedBytes: Int,
    val type: String,
) : AgentBridgePackaging {
    init {
        AgentBridgeChecks.text(filenameTemplate, 1, 255)
        AgentBridgeChecks.require(manifest == "healthmd.agent_artifact_manifest/1")
        AgentBridgeChecks.require(maxEntries.toLong() in 1L..4096L)
        AgentBridgeChecks.require(maxUncompressedBytes.toLong() in 1L..1073741824L)
        AgentBridgeChecks.require(type == "zip")
    }
}

@Serializable
data class AgentBridgePresentation(
    @SerialName("display_units") val displayUnits: AgentBridgePresentationDisplayUnits,
    val frontmatter: AgentBridgeFrontmatter,
    @SerialName("group_by_category") val groupByCategory: Boolean,
    @SerialName("include_metadata") val includeMetadata: Boolean,
    val locale: String,
    @SerialName("machine_units") val machineUnits: String,
    val markdown: AgentBridgeMarkdown,
) {
    init {
        AgentBridgeChecks.text(locale, 1, 64)
        AgentBridgeChecks.require(machineUnits == "canonical")
    }
}

@Serializable
data class AgentBridgeFrontmatter(
    @SerialName("custom_fields") val customFields: List<AgentBridgeFrontmatterCustomFieldsItem>,
    @SerialName("enabled_field_ids") val enabledFieldIds: List<String>,
    @SerialName("include_capture_diagnostics") val includeCaptureDiagnostics: Boolean,
    @SerialName("include_units") val includeUnits: Boolean,
) {
    init {
        AgentBridgeChecks.require(customFields.size in 0..128)
        AgentBridgeChecks.require(enabledFieldIds.size in 0..256)
        AgentBridgeChecks.require(enabledFieldIds.distinct().size == enabledFieldIds.size)
        enabledFieldIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
    }
}

@Serializable
data class AgentBridgeFrontmatterCustomFieldsItem(
    val key: String,
    val value: String,
) {
    init {
        AgentBridgeChecks.text(key, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(value, 0, 4096)
    }
}

@Serializable
data class AgentBridgeMarkdown(
    @SerialName("custom_template") val customTemplate: String,
    @SerialName("placeholder_ids") val placeholderIds: List<String>,
    val style: AgentBridgeMarkdownStyle,
) {
    init {
        AgentBridgeChecks.text(customTemplate, 0, 65536)
        AgentBridgeChecks.require(placeholderIds.size in 0..128)
        AgentBridgeChecks.require(placeholderIds.distinct().size == placeholderIds.size)
        placeholderIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
    }
}

@Serializable
data class AgentBridgeSettingsPolicySavedDeviceSettings(
    @SerialName("expected_revision") val expectedRevision: Int,
    val type: String,
) : AgentBridgeSettingsPolicy {
    init {
        AgentBridgeChecks.require(expectedRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.require(type == "saved_device_settings")
    }
}

@Serializable
data class AgentBridgeSettingsPolicyProfile(
    @SerialName("expected_revision") val expectedRevision: Int,
    @SerialName("profile_id") val profileId: String,
    val type: String,
) : AgentBridgeSettingsPolicy {
    init {
        AgentBridgeChecks.require(expectedRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.text(profileId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(type == "profile")
    }
}

@Serializable
data class AgentBridgeProjectionIntent(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("capture_scope") val captureScope: AgentBridgeCapture,
    val dates: AgentBridgeDates,
    val destination: AgentBridgeDestination,
    @SerialName("intent_id") val intentId: String,
    val peer: AgentBridgePeer,
    val product: AgentBridgeProjectionProduct,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("timestamp_timezone") val timestampTimezone: String,
) : AgentBridgeIntent {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(intentId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_export_intent")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(timestampTimezone == "UTC")
    }
}

@Serializable
data class AgentBridgeProjectionProduct(
    val output: AgentBridgeProjectionOutput,
    @SerialName("product_id") val productId: String,
    val request: AgentBridgeProjectionRequest,
    val type: String,
) {
    init {
        AgentBridgeChecks.require(productId == "android_source_projection_v1")
        AgentBridgeChecks.require(type == "source_projection")
    }
}

@Serializable
data class AgentBridgeProjectionOutput(
    @SerialName("filename_template") val filenameTemplate: String,
    @SerialName("folder_template") val folderTemplate: String,
    val layout: String,
    @SerialName("media_type") val mediaType: AgentBridgeProjectionOutputMediaType,
    val profile: String,
    val subfolder: String,
    @SerialName("write_mode") val writeMode: AgentBridgeProjectionOutputWriteMode,
) {
    init {
        AgentBridgeChecks.text(filenameTemplate, 1, 255)
        AgentBridgeChecks.text(folderTemplate, 0, 4096)
        AgentBridgeChecks.require(layout == "per_day")
        AgentBridgeChecks.require(profile == "android-source-projection-v1")
        AgentBridgeChecks.text(subfolder, 0, 4096)
        AgentBridgeChecks.require(mediaType == AgentBridgeProjectionOutputMediaType.APPLICATION_X_NDJSON || writeMode == AgentBridgeProjectionOutputWriteMode.OVERWRITE)
    }
}

@Serializable
data class AgentBridgeProjectionRequest(
    @SerialName("allow_partial") val allowPartial: Boolean,
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val dates: AgentBridgeDates,
    val detail: AgentBridgeProjectionRequestDetail,
    @SerialName("field_ids") val fieldIds: List<String>,
    @SerialName("object_ids") val objectIds: List<AgentBridgeProjectionRequestObjectIdsItem>,
    val peer: AgentBridgePeer,
    @SerialName("projection_catalog_sha256") val projectionCatalogSha256: String,
    @SerialName("provider_id") val providerId: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    val selection: AgentBridgeSelection,
    @SerialName("source_id") val sourceId: AgentBridgeProjectionRequestSourceId,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(fieldIds.size in 1..256)
        AgentBridgeChecks.require(fieldIds.distinct().size == fieldIds.size)
        fieldIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(objectIds.size in 1..4)
        AgentBridgeChecks.require(objectIds.distinct().size == objectIds.size)
        AgentBridgeChecks.text(projectionCatalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_projection_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgePlanRequest(
    @SerialName("authority_id") val authorityId: String,
    @SerialName("authority_revision") val authorityRevision: Int,
    @SerialName("capability_sha256") val capabilitySha256: String,
    @SerialName("host_authority_reference") val hostAuthorityReference: AgentBridgeAuthorityReference,
    val intent: AgentBridgeIntent,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(authorityId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(authorityRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.text(capabilitySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_plan_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeGeneratedPlan(
    @SerialName("authority_references") val authorityReferences: AgentBridgeAuthorityReferences,
    @SerialName("capability_sha256") val capabilitySha256: String,
    @SerialName("effective_settings") val effectiveSettings: AgentBridgeOutputSettings,
    @SerialName("expires_at") val expiresAt: String,
    val intent: AgentBridgeGeneratedIntent,
    @SerialName("issued_at") val issuedAt: String,
    val limitations: List<String>,
    val origins: List<AgentBridgeOrigin>,
    @SerialName("path_prediction") val pathPrediction: AgentBridgeGeneratedPlanPathPrediction,
    @SerialName("plan_id") val planId: String,
    @SerialName("plan_sha256") val planSha256: String,
    @SerialName("predicted_paths") val predictedPaths: List<String>,
    @SerialName("required_actions") val requiredActions: List<String>,
    @SerialName("resolved_dates") val resolvedDates: AgentBridgeDates,
    @SerialName("resolved_metric_ids") val resolvedMetricIds: List<String>,
    val revisions: List<AgentBridgeRevision>,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("scope_sha256") val scopeSha256: String,
    @SerialName("settings_sha256") val settingsSha256: String,
    @SerialName("side_effects") val sideEffects: AgentBridgeZeroControlEffects,
) : AgentBridgePlan {
    init {
        AgentBridgeChecks.text(capabilitySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.text(issuedAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(origins.size in 1..512)
        AgentBridgeChecks.text(planId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(planSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(predictedPaths.size in 0..4096)
        AgentBridgeChecks.require(predictedPaths.distinct().size == predictedPaths.size)
        predictedPaths.forEach { AgentBridgeChecks.text(it, 0, 4096) }
        AgentBridgeChecks.require(requiredActions.size in 0..16)
        AgentBridgeChecks.require(requiredActions.distinct().size == requiredActions.size)
        requiredActions.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(resolvedMetricIds.size in 1..256)
        AgentBridgeChecks.require(resolvedMetricIds.distinct().size == resolvedMetricIds.size)
        resolvedMetricIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(revisions.size in 0..16)
        AgentBridgeChecks.require(schema == "healthmd.agent_export_plan")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.text(scopeSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(settingsSha256, 64, 64, "^[0-9a-f]{64}\$")
    }
}

@Serializable
data class AgentBridgeAuthorityReferences(
    val host: AgentBridgeAuthorityReference,
    val native: AgentBridgeAuthorityReference,
) {
    init {
    }
}

@Serializable
data class AgentBridgeOrigin(
    val origin: AgentBridgeOriginOrigin,
    val pointer: String,
    val revision: Int,
) {
    init {
        AgentBridgeChecks.text(pointer, 1, 256)
        AgentBridgeChecks.require(revision.toLong() in 0L..2147483647L)
    }
}

@Serializable
data class AgentBridgeRevision(
    val domain: AgentBridgeRevisionDomain,
    @SerialName("object_id") val objectId: String,
    val revision: Int,
    val sha256: String,
) {
    init {
        AgentBridgeChecks.text(objectId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(revision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
    }
}

@Serializable
data class AgentBridgeZeroControlEffects(
    @SerialName("content_preview_reads") val contentPreviewReads: Int,
    @SerialName("credential_enrollments") val credentialEnrollments: Int,
    @SerialName("earliest_date_reads") val earliestDateReads: Int,
    @SerialName("health_reads") val healthReads: Int,
    @SerialName("output_writes") val outputWrites: Int,
    @SerialName("quota_consumed") val quotaConsumed: Int,
    @SerialName("settings_mutations") val settingsMutations: Int,
    @SerialName("wake_enrollments") val wakeEnrollments: Int,
) {
    init {
        AgentBridgeChecks.require(contentPreviewReads == 0)
        AgentBridgeChecks.require(credentialEnrollments == 0)
        AgentBridgeChecks.require(earliestDateReads == 0)
        AgentBridgeChecks.require(healthReads == 0)
        AgentBridgeChecks.require(outputWrites == 0)
        AgentBridgeChecks.require(quotaConsumed == 0)
        AgentBridgeChecks.require(settingsMutations == 0)
        AgentBridgeChecks.require(wakeEnrollments == 0)
    }
}

@Serializable
data class AgentBridgeProjectionPlan(
    @SerialName("authority_references") val authorityReferences: AgentBridgeAuthorityReferences,
    @SerialName("capability_sha256") val capabilitySha256: String,
    @SerialName("effective_projection_output") val effectiveProjectionOutput: AgentBridgeProjectionOutput,
    @SerialName("expires_at") val expiresAt: String,
    val intent: AgentBridgeProjectionIntent,
    @SerialName("issued_at") val issuedAt: String,
    val limitations: List<String>,
    val origins: List<AgentBridgeOrigin>,
    @SerialName("path_prediction") val pathPrediction: AgentBridgeGeneratedPlanPathPrediction,
    @SerialName("plan_id") val planId: String,
    @SerialName("plan_sha256") val planSha256: String,
    @SerialName("predicted_paths") val predictedPaths: List<String>,
    @SerialName("required_actions") val requiredActions: List<String>,
    @SerialName("resolved_dates") val resolvedDates: AgentBridgeDates,
    @SerialName("resolved_metric_ids") val resolvedMetricIds: List<String>,
    val revisions: List<AgentBridgeRevision>,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("scope_sha256") val scopeSha256: String,
    @SerialName("settings_sha256") val settingsSha256: String,
    @SerialName("side_effects") val sideEffects: AgentBridgeZeroControlEffects,
) : AgentBridgePlan {
    init {
        AgentBridgeChecks.text(capabilitySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.text(issuedAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(origins.size in 1..512)
        AgentBridgeChecks.text(planId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(planSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(predictedPaths.size in 0..4096)
        AgentBridgeChecks.require(predictedPaths.distinct().size == predictedPaths.size)
        predictedPaths.forEach { AgentBridgeChecks.text(it, 0, 4096) }
        AgentBridgeChecks.require(requiredActions.size in 0..16)
        AgentBridgeChecks.require(requiredActions.distinct().size == requiredActions.size)
        requiredActions.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(resolvedMetricIds.size in 1..256)
        AgentBridgeChecks.require(resolvedMetricIds.distinct().size == resolvedMetricIds.size)
        resolvedMetricIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(revisions.size in 0..16)
        AgentBridgeChecks.require(schema == "healthmd.agent_export_plan")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.text(scopeSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(settingsSha256, 64, 64, "^[0-9a-f]{64}\$")
    }
}

@Serializable
data class AgentBridgeApprovalRequest(
    val binding: AgentBridgeBinding,
    @SerialName("plan_id") val planId: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(planId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_approval_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeBinding(
    @SerialName("authority_references") val authorityReferences: AgentBridgeAuthorityReferences,
    @SerialName("capability_sha256") val capabilitySha256: String,
    val destination: AgentBridgeDestination,
    @SerialName("expires_at") val expiresAt: String,
    val peer: AgentBridgePeer,
    @SerialName("plan_sha256") val planSha256: String,
    val revisions: List<AgentBridgeRevision>,
    @SerialName("scope_sha256") val scopeSha256: String,
    @SerialName("settings_sha256") val settingsSha256: String,
) {
    init {
        AgentBridgeChecks.text(capabilitySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.text(planSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(revisions.size in 0..16)
        AgentBridgeChecks.text(scopeSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(settingsSha256, 64, 64, "^[0-9a-f]{64}\$")
    }
}

@Serializable
data class AgentBridgeApproval(
    @SerialName("approval_id") val approvalId: String,
    @SerialName("approved_at") val approvedAt: String,
    @SerialName("authority_id") val authorityId: String,
    val binding: AgentBridgeBinding,
    val rights: List<AgentBridgeApprovalRightsItem>,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(approvalId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(approvedAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.text(authorityId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(rights.size in 1..1)
        AgentBridgeChecks.require(rights.distinct().size == rights.size)
        AgentBridgeChecks.require(schema == "healthmd.agent_approval")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeExecuteRequest(
    val approval: AgentBridgeApproval,
    @SerialName("idempotency_key") val idempotencyKey: String,
    @SerialName("job_id") val jobId: String,
    val plan: AgentBridgePlan,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(idempotencyKey, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(jobId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_execute_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeExecutionReceipt(
    @SerialName("artifact_count") val artifactCount: Int,
    val binding: AgentBridgeBinding,
    @SerialName("committed_partition_count") val committedPartitionCount: Int,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("frontier_sha256") val frontierSha256: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("manifest_sha256") val manifestSha256: String,
    @SerialName("request_sha256") val requestSha256: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_acknowledged") val sourceAcknowledged: Boolean,
    val status: AgentBridgeExecutionReceiptStatus,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.require(artifactCount.toLong() in 0L..4096L)
        AgentBridgeChecks.require(committedPartitionCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.text(frontierSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(jobId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(manifestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_execution_receipt")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeCancelRequest(
    @SerialName("approval_id") val approvalId: String,
    @SerialName("authority_id") val authorityId: String,
    @SerialName("job_id") val jobId: String,
    val peer: AgentBridgePeer,
    @SerialName("request_sha256") val requestSha256: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(approvalId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(authorityId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(jobId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(requestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_cancel_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeResumeRequest(
    val binding: AgentBridgeBinding,
    @SerialName("committed_partition_count") val committedPartitionCount: Int,
    val destination: AgentBridgeDestination,
    @SerialName("frontier_sha256") val frontierSha256: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("manifest_sha256") val manifestSha256: String,
    val peer: AgentBridgePeer,
    @SerialName("request_sha256") val requestSha256: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.require(committedPartitionCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.text(frontierSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(jobId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(manifestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_resume_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeArtifactManifest(
    val artifacts: List<AgentBridgeArtifact>,
    val binding: AgentBridgeBinding,
    @SerialName("branch_statuses") val branchStatuses: List<AgentBridgeArtifactManifestBranchStatusesItem>,
    @SerialName("capture_status") val captureStatus: AgentBridgeArtifactManifestCaptureStatus,
    @SerialName("job_id") val jobId: String,
    @SerialName("request_sha256") val requestSha256: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.require(artifacts.size in 0..4096)
        AgentBridgeChecks.require(branchStatuses.size in 0..256)
        AgentBridgeChecks.text(jobId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(requestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_artifact_manifest")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeArtifact(
    @SerialName("artifact_id") val artifactId: String,
    @SerialName("byte_count") val byteCount: Long,
    @SerialName("media_type") val mediaType: AgentBridgeArtifactMediaType,
    val profile: AgentBridgeArtifactProfile,
    @SerialName("relative_path") val relativePath: String,
    val sha256: String,
    @SerialName("write_mode") val writeMode: AgentBridgeWriteMode,
) {
    init {
        AgentBridgeChecks.text(artifactId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(byteCount.toLong() in 0L..1099511627776L)
        AgentBridgeChecks.text(relativePath, 0, 4096)
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        if (profile == AgentBridgeArtifactProfile.ANDROID_SOURCE_PROJECTION_V1) {
            AgentBridgeChecks.require(mediaType in listOf(AgentBridgeArtifactMediaType.APPLICATION_JSON, AgentBridgeArtifactMediaType.APPLICATION_X_NDJSON))
            AgentBridgeChecks.require(writeMode == AgentBridgeWriteMode.OVERWRITE || (mediaType == AgentBridgeArtifactMediaType.APPLICATION_X_NDJSON && writeMode == AgentBridgeWriteMode.APPEND))
        }
    }
}

@Serializable
data class AgentBridgeArtifactManifestBranchStatusesItem(
    @SerialName("record_count") val recordCount: Int,
    @SerialName("selector_id") val selectorId: String,
    val status: AgentBridgeArtifactManifestBranchStatusesItemStatus,
) {
    init {
        AgentBridgeChecks.require(recordCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.text(selectorId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeCommitReceipt(
    @SerialName("after_sha256") val afterSha256: String,
    @SerialName("artifact_id") val artifactId: String,
    @SerialName("before_sha256") val beforeSha256: String,
    @SerialName("commit_key") val commitKey: String,
    val destination: AgentBridgeDestination,
    @SerialName("input_sha256") val inputSha256: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("manifest_sha256") val manifestSha256: String,
    val peer: AgentBridgePeer,
    @SerialName("relative_path") val relativePath: String,
    @SerialName("request_sha256") val requestSha256: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    val status: AgentBridgeCommitReceiptStatus,
    @SerialName("write_mode") val writeMode: AgentBridgeWriteMode,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(afterSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(artifactId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(beforeSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(commitKey, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(inputSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(jobId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(manifestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(relativePath, 0, 4096)
        AgentBridgeChecks.text(requestSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_commit_receipt")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeAuthority(
    @SerialName("authority_id") val authorityId: String,
    @SerialName("configuration_protection") val configurationProtection: AgentBridgeAuthorityConfigurationProtection,
    @SerialName("control_read_scope") val controlReadScope: AgentBridgeControlReadScope? = null,
    @SerialName("destination_binding_ids") val destinationBindingIds: List<String>,
    val entitlement: AgentBridgeDiscoveryEntitlement,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("grant_revision") val grantRevision: Int,
    val issuer: AgentBridgeIssuer,
    @SerialName("native_consent") val nativeConsent: AgentBridgeDiscoveryEntitlement,
    val peer: AgentBridgePeer,
    val rights: List<AgentBridgeAuthorityRightsItem>,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("scope_sha256") val scopeSha256: String,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(authorityId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(destinationBindingIds.size in 0..32)
        AgentBridgeChecks.require(destinationBindingIds.distinct().size == destinationBindingIds.size)
        destinationBindingIds.forEach { AgentBridgeChecks.text(it, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$") }
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(grantRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.require(rights.size in 1..14)
        AgentBridgeChecks.require(rights.distinct().size == rights.size)
        AgentBridgeChecks.require(schema == "healthmd.agent_authority")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.text(scopeSha256, 64, 64, "^[0-9a-f]{64}\$")
    }
}

@Serializable
data class AgentBridgeControlReadScope(
    @SerialName("create_domains") val createDomains: List<AgentBridgeControlReadScopeCreateDomainsItem>,
    @SerialName("list_domains") val listDomains: List<AgentBridgeControlReadScopeListDomainsItem>,
    val objects: List<AgentBridgeControlReadScopeObjectsItem>,
) {
    init {
        AgentBridgeChecks.require(createDomains.size in 0..3)
        AgentBridgeChecks.require(createDomains.distinct().size == createDomains.size)
        AgentBridgeChecks.require(listDomains.size in 0..5)
        AgentBridgeChecks.require(listDomains.distinct().size == listDomains.size)
        AgentBridgeChecks.require(objects.size in 0..256)
    }
}

@Serializable
data class AgentBridgeControlReadScopeObjectsItem(
    val domain: AgentBridgeControlReadScopeListDomainsItem,
    @SerialName("object_id") val objectId: String,
) {
    init {
        AgentBridgeChecks.text(objectId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
    }
}

@Serializable
data class AgentBridgeExportDelegation(
    @SerialName("authority_id") val authorityId: String,
    val bounds: AgentBridgeExportDelegationBounds,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("grant_revision") val grantRevision: Int,
    val issuer: AgentBridgeIssuer,
    val peer: AgentBridgePeer,
    val rights: List<AgentBridgeExportDelegationRightsItem>,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(authorityId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(grantRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.require(rights.size in 1..3)
        AgentBridgeChecks.require(rights.distinct().size == rights.size)
        AgentBridgeChecks.require(schema == "healthmd.agent_export_delegation")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeExportDelegationBounds(
    @SerialName("calendar_timezones") val calendarTimezones: List<String>,
    @SerialName("compatibility_detail") val compatibilityDetail: List<AgentBridgeCompatibilityDetail>,
    @SerialName("date_policy") val datePolicy: AgentBridgeExportDelegationBoundsDatePolicy,
    @SerialName("destination_policy") val destinationPolicy: AgentBridgeExportDelegationBoundsDestinationPolicy,
    val formats: List<AgentBridgeFormat>,
    @SerialName("metric_ids") val metricIds: List<String>,
    @SerialName("native_archive_products") val nativeArchiveProducts: List<AgentBridgeOutputSupportNativeArchiveProductsItem>,
    @SerialName("output_profiles") val outputProfiles: List<AgentBridgeOutputProfile>,
    val products: List<AgentBridgeExportDelegationBoundsProductsItem>,
    @SerialName("projection_details") val projectionDetails: List<AgentBridgeProjectionRequestDetail>,
    @SerialName("projection_field_ids") val projectionFieldIds: List<String>,
    @SerialName("projection_object_ids") val projectionObjectIds: List<AgentBridgeProjectionRequestObjectIdsItem>,
    @SerialName("write_modes") val writeModes: List<AgentBridgeWriteMode>,
) {
    init {
        AgentBridgeChecks.require(calendarTimezones.size in 1..16)
        AgentBridgeChecks.require(calendarTimezones.distinct().size == calendarTimezones.size)
        calendarTimezones.forEach { AgentBridgeChecks.text(it, 1, 128) }
        AgentBridgeChecks.require(compatibilityDetail.size in 1..2)
        AgentBridgeChecks.require(compatibilityDetail.distinct().size == compatibilityDetail.size)
        AgentBridgeChecks.require(formats.size in 1..4)
        AgentBridgeChecks.require(formats.distinct().size == formats.size)
        AgentBridgeChecks.require(metricIds.size in 1..256)
        AgentBridgeChecks.require(metricIds.distinct().size == metricIds.size)
        metricIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(nativeArchiveProducts.size in 1..3)
        AgentBridgeChecks.require(nativeArchiveProducts.distinct().size == nativeArchiveProducts.size)
        AgentBridgeChecks.require(outputProfiles.size in 1..3)
        AgentBridgeChecks.require(outputProfiles.distinct().size == outputProfiles.size)
        AgentBridgeChecks.require(products.size in 1..2)
        AgentBridgeChecks.require(products.distinct().size == products.size)
        AgentBridgeChecks.require(projectionDetails.size in 0..3)
        AgentBridgeChecks.require(projectionDetails.distinct().size == projectionDetails.size)
        AgentBridgeChecks.require(projectionFieldIds.size in 0..256)
        AgentBridgeChecks.require(projectionFieldIds.distinct().size == projectionFieldIds.size)
        projectionFieldIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(projectionObjectIds.size in 0..4)
        AgentBridgeChecks.require(projectionObjectIds.distinct().size == projectionObjectIds.size)
        AgentBridgeChecks.require(writeModes.size in 1..4)
        AgentBridgeChecks.require(writeModes.distinct().size == writeModes.size)
    }
}

@Serializable
data class AgentBridgeExportDelegationBoundsDatePolicyBoundedExact(
    @SerialName("max_days") val maxDays: Int,
    val range: AgentBridgeRange,
    val type: String,
) : AgentBridgeExportDelegationBoundsDatePolicy {
    init {
        AgentBridgeChecks.require(maxDays.toLong() in 1L..366000L)
        AgentBridgeChecks.require(type == "bounded_exact")
    }
}

@Serializable
data class AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory(
    @SerialName("allow_all_available") val allowAllAvailable: Boolean,
    @SerialName("max_days") val maxDays: Int,
    val type: String,
) : AgentBridgeExportDelegationBoundsDatePolicy {
    init {
        AgentBridgeChecks.require(maxDays.toLong() in 1L..366000L)
        AgentBridgeChecks.require(type == "authorized_history")
    }
}

@Serializable
data class AgentBridgeExportDelegationBoundsDestinationPolicyAuthenticatedHostBindings(
    val type: String,
) : AgentBridgeExportDelegationBoundsDestinationPolicy {
    init {
        AgentBridgeChecks.require(type == "authenticated_host_bindings")
    }
}

@Serializable
data class AgentBridgeExportDelegationBoundsDestinationPolicyRegisteredHostBindings(
    @SerialName("binding_ids") val bindingIds: List<String>,
    val type: String,
) : AgentBridgeExportDelegationBoundsDestinationPolicy {
    init {
        AgentBridgeChecks.require(bindingIds.size in 1..32)
        AgentBridgeChecks.require(bindingIds.distinct().size == bindingIds.size)
        bindingIds.forEach { AgentBridgeChecks.text(it, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$") }
        AgentBridgeChecks.require(type == "registered_host_bindings")
    }
}

@Serializable
data class AgentBridgeError(
    val code: AgentBridgeErrorCode,
    @SerialName("request_id") val requestId: String,
    val retryable: Boolean,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.agent_error")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeQueryRequest(
    @SerialName("authority_id") val authorityId: String,
    @SerialName("authority_revision") val authorityRevision: Int,
    val budgets: AgentBridgeBudgets,
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val dates: AgentBridgeDates,
    val detail: AgentBridgeQueryRequestDetail,
    @SerialName("include_evidence_values") val includeEvidenceValues: Boolean,
    val operation: AgentBridgeQueryOperation,
    val page: AgentBridgeQueryPage,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    val selection: AgentBridgeSelection,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(authorityId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(authorityRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_request")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeQueryOperationMetricCatalog(
    val type: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(type == "metric_catalog")
    }
}

@Serializable
data class AgentBridgeQueryOperationMetricSeries(
    val type: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(type == "metric_series")
    }
}

@Serializable
data class AgentBridgeQueryOperationCoverage(
    val type: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(type == "coverage")
    }
}

@Serializable
data class AgentBridgeQueryOperationWorkoutListing(
    val type: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(type == "workout_listing")
    }
}

@Serializable
data class AgentBridgeQueryOperationSourceRecordListing(
    val type: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(type == "source_record_listing")
    }
}

@Serializable
data class AgentBridgeQueryOperationSleepSessionListing(
    @SerialName("include_naps") val includeNaps: Boolean,
    val type: String,
    val window: AgentBridgeQueryOperationSleepSessionListingWindow,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(type == "sleep_session_listing")
    }
}

@Serializable
data class AgentBridgeQueryOperationSleepSessionListingWindow(
    @SerialName("duration_seconds") val durationSeconds: Int,
    @SerialName("start_offset_seconds") val startOffsetSeconds: Int,
) {
    init {
        AgentBridgeChecks.require(durationSeconds.toLong() in 1L..86400L)
        AgentBridgeChecks.require(startOffsetSeconds.toLong() in -86400L..86400L)
    }
}

@Serializable
data class AgentBridgeQueryOperationWorkoutSleepAlignment(
    @SerialName("include_naps") val includeNaps: Boolean,
    val type: String,
    val window: AgentBridgeQueryOperationWorkoutSleepAlignmentWindow,
    @SerialName("workout_activity") val workoutActivity: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(type == "workout_sleep_alignment")
        AgentBridgeChecks.text(workoutActivity, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryOperationWorkoutSleepAlignmentWindow(
    @SerialName("duration_seconds") val durationSeconds: Int,
    @SerialName("start_offset_seconds") val startOffsetSeconds: Int,
) {
    init {
        AgentBridgeChecks.require(durationSeconds.toLong() in 1L..86400L)
        AgentBridgeChecks.require(startOffsetSeconds.toLong() in -86400L..86400L)
    }
}

@Serializable
data class AgentBridgeQueryOperationPeriodComparison(
    val aggregations: List<AgentBridgeQueryOperationPeriodComparisonAggregationsItem>,
    val first: AgentBridgeRange,
    val second: AgentBridgeRange,
    val type: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(aggregations.size in 1..256)
        AgentBridgeChecks.require(type == "period_comparison")
    }
}

@Serializable
data class AgentBridgeQueryOperationPeriodComparisonAggregationsItem(
    @SerialName("expected_unit") val expectedUnit: String,
    val kind: AgentBridgeCatalogItemStatisticsItem,
    @SerialName("metric_id") val metricId: String,
) {
    init {
        AgentBridgeChecks.text(expectedUnit, 1, 32)
        AgentBridgeChecks.text(metricId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryOperationDerivePacket(
    @SerialName("detail_ids") val detailIds: List<String>,
    val kind: AgentBridgeQueryOperationDerivePacketKind,
    val type: String,
) : AgentBridgeQueryOperation {
    init {
        AgentBridgeChecks.require(detailIds.size in 0..64)
        AgentBridgeChecks.require(detailIds.distinct().size == detailIds.size)
        detailIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(type == "derive_packet")
    }
}

@Serializable
data class AgentBridgeQueryPage(
    val cursor: String? = null,
    @SerialName("max_bytes") val maxBytes: Int,
    @SerialName("max_items") val maxItems: Int,
) {
    init {
        cursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(maxBytes.toLong() in 1024L..1048576L)
        AgentBridgeChecks.require(maxItems.toLong() in 1L..1000L)
    }
}

@Serializable
data class AgentBridgeQueryResponseMetricCatalog(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    val catalog: AgentBridgeQueryCatalog,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeCatalogItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseMetricCatalogSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..1000)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "metric_catalog")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeQueryResponseMetricCatalogSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseMetricSeries(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeMetricItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseMetricSeriesSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..1000)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "metric_series")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeMetricItem(
    val availability: AgentBridgeMetricItemAvailability,
    @SerialName("evidence_ids") val evidenceIds: List<String>,
    @SerialName("metric_id") val metricId: String,
    @SerialName("owner_date") val ownerDate: String,
    val statistic: AgentBridgeCatalogItemStatisticsItem,
    val type: String,
    val unit: String,
    val value: AgentBridgeValue? = null,
) {
    init {
        AgentBridgeChecks.require(evidenceIds.size in 0..64)
        AgentBridgeChecks.require(evidenceIds.distinct().size == evidenceIds.size)
        evidenceIds.forEach { AgentBridgeChecks.text(it, 64, 64, "^[0-9a-f]{64}\$") }
        AgentBridgeChecks.text(metricId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(ownerDate, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
        AgentBridgeChecks.require(type == "metric")
        AgentBridgeChecks.text(unit, 1, 32)
    }
}

@Serializable
data class AgentBridgeValueInteger(
    val type: String,
    val value: Long,
) : AgentBridgeValue {
    init {
        AgentBridgeChecks.require(type == "integer")
        AgentBridgeChecks.require(value.toLong() in -9007199254740991L..9007199254740991L)
    }
}

@Serializable
data class AgentBridgeValueDecimal(
    val type: String,
    val value: String,
) : AgentBridgeValue {
    init {
        AgentBridgeChecks.require(type == "decimal")
        AgentBridgeChecks.text(value, 1, 80, "^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?\$")
    }
}

@Serializable
data class AgentBridgeValueText(
    val type: String,
    val value: String,
) : AgentBridgeValue {
    init {
        AgentBridgeChecks.require(type == "text")
        AgentBridgeChecks.text(value, 0, 1024)
    }
}

@Serializable
data class AgentBridgeQueryResponseMetricSeriesSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseCoverage(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeMetricItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseCoverageSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..0)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "coverage")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeQueryResponseCoverageSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseWorkoutListing(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeSessionItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseWorkoutListingSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..1000)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "workout_listing")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeSessionItem(
    @SerialName("activity_or_stage") val activityOrStage: String,
    val classification: AgentBridgeSessionItemClassification,
    @SerialName("duration_nanoseconds") val durationNanoseconds: String,
    val end: AgentBridgeExactTime,
    @SerialName("evidence_ids") val evidenceIds: List<String>,
    val identity: AgentBridgeNativeIdentity,
    val kind: AgentBridgeSessionItemKind,
    @SerialName("owner_date") val ownerDate: String,
    val stages: List<AgentBridgeSessionItemStagesItem>,
    val start: AgentBridgeExactTime,
    val type: String,
) {
    init {
        AgentBridgeChecks.text(activityOrStage, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(durationNanoseconds, 1, 32, "^[0-9]+\$")
        AgentBridgeChecks.require(evidenceIds.size in 0..64)
        AgentBridgeChecks.require(evidenceIds.distinct().size == evidenceIds.size)
        evidenceIds.forEach { AgentBridgeChecks.text(it, 64, 64, "^[0-9a-f]{64}\$") }
        AgentBridgeChecks.text(ownerDate, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
        AgentBridgeChecks.require(stages.size in 0..1000)
        AgentBridgeChecks.require(type == "session")
    }
}

@Serializable
data class AgentBridgeExactTime(
    @SerialName("epoch_second") val epochSecond: Long,
    val nanosecond: Int,
    val precision: AgentBridgeExactTimePrecision,
    @SerialName("source_offset_seconds") val sourceOffsetSeconds: Int?,
    @SerialName("source_binary64_bits") val sourceBinary64Bits: String? = null,
) {
    init {
        AgentBridgeChecks.require(epochSecond.toLong() in -62135596800L..253402300799L)
        AgentBridgeChecks.require(nanosecond.toLong() in 0L..999999999L)
        sourceOffsetSeconds?.let {
            AgentBridgeChecks.require(it.toLong() in -64800L..64800L)
        }
        sourceBinary64Bits?.let {
            AgentBridgeChecks.text(it, 16, 16, "^[0-9a-f]{16}\$")
        }
        AgentBridgeChecks.require((precision == AgentBridgeExactTimePrecision.SOURCE_BINARY64_SECONDS) == (sourceBinary64Bits != null))
    }
}

@Serializable
data class AgentBridgeNativeIdentityAppleHealth(
    @SerialName("identity_kind") val identityKind: AgentBridgeNativeIdentityAppleHealthIdentityKind,
    @SerialName("metadata_status") val metadataStatus: AgentBridgeNativeIdentityAppleHealthMetadataStatus,
    val origin: String? = null,
    @SerialName("parent_record_id") val parentRecordId: String? = null,
    @SerialName("parent_record_type") val parentRecordType: String? = null,
    @SerialName("provider_id") val providerId: String,
    @SerialName("record_id") val recordId: String,
    @SerialName("record_type") val recordType: String,
    @SerialName("source_id") val sourceId: String,
) : AgentBridgeNativeIdentity {
    init {
        origin?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        parentRecordId?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        parentRecordType?.let {
            AgentBridgeChecks.text(it, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        }
        AgentBridgeChecks.require(providerId == "apple_health")
        AgentBridgeChecks.text(recordId, 1, 256)
        AgentBridgeChecks.text(recordType, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        AgentBridgeChecks.require(sourceId == "apple_health")
    }
}

@Serializable
data class AgentBridgeNativeIdentityAppleHealthMetadataStatus(
    @SerialName("client_record_id") val clientRecordId: String,
    @SerialName("client_record_version") val clientRecordVersion: String,
    @SerialName("last_modified") val lastModified: String,
) {
    init {
        AgentBridgeChecks.require(clientRecordId == "not_exposed_by_source")
        AgentBridgeChecks.require(clientRecordVersion == "not_exposed_by_source")
        AgentBridgeChecks.require(lastModified == "not_exposed_by_source")
    }
}

@Serializable
data class AgentBridgeNativeIdentityHealthConnect(
    @SerialName("client_record_id") val clientRecordId: String? = null,
    @SerialName("client_record_version") val clientRecordVersion: Long? = null,
    @SerialName("identity_kind") val identityKind: AgentBridgeNativeIdentityAppleHealthIdentityKind,
    @SerialName("last_modified") val lastModified: AgentBridgeExactTime? = null,
    @SerialName("metadata_status") val metadataStatus: AgentBridgeNativeIdentityHealthConnectMetadataStatus,
    val origin: String? = null,
    @SerialName("parent_record_id") val parentRecordId: String? = null,
    @SerialName("parent_record_type") val parentRecordType: String? = null,
    @SerialName("provider_id") val providerId: String,
    @SerialName("record_id") val recordId: String,
    @SerialName("record_type") val recordType: String,
    @SerialName("source_id") val sourceId: String,
) : AgentBridgeNativeIdentity {
    init {
        clientRecordId?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        clientRecordVersion?.let {
            AgentBridgeChecks.require(it.toLong() in 0L..9223372036854775807L)
        }
        origin?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        parentRecordId?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        parentRecordType?.let {
            AgentBridgeChecks.text(it, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        }
        AgentBridgeChecks.require(providerId == "health_connect")
        AgentBridgeChecks.text(recordId, 1, 256)
        AgentBridgeChecks.text(recordType, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        AgentBridgeChecks.require(sourceId == "health_connect")
    }
}

@Serializable
data class AgentBridgeNativeIdentityHealthConnectMetadataStatus(
    @SerialName("client_record_id") val clientRecordId: AgentBridgeClientIdAvailability,
    @SerialName("client_record_version") val clientRecordVersion: AgentBridgeMetadataAvailability,
    @SerialName("last_modified") val lastModified: AgentBridgeMetadataAvailability,
) {
    init {
    }
}

@Serializable
data class AgentBridgeNativeIdentityProviderNative(
    @SerialName("client_record_id") val clientRecordId: String? = null,
    @SerialName("client_record_version") val clientRecordVersion: Long? = null,
    @SerialName("identity_kind") val identityKind: AgentBridgeNativeIdentityAppleHealthIdentityKind,
    @SerialName("last_modified") val lastModified: AgentBridgeExactTime? = null,
    @SerialName("metadata_status") val metadataStatus: AgentBridgeNativeIdentityProviderNativeMetadataStatus,
    val origin: String? = null,
    @SerialName("parent_record_id") val parentRecordId: String? = null,
    @SerialName("parent_record_type") val parentRecordType: String? = null,
    @SerialName("provider_id") val providerId: String,
    @SerialName("record_id") val recordId: String,
    @SerialName("record_type") val recordType: String,
    @SerialName("source_id") val sourceId: String,
) : AgentBridgeNativeIdentity {
    init {
        clientRecordId?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        clientRecordVersion?.let {
            AgentBridgeChecks.require(it.toLong() in 0L..9223372036854775807L)
        }
        origin?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        parentRecordId?.let {
            AgentBridgeChecks.text(it, 1, 256)
        }
        parentRecordType?.let {
            AgentBridgeChecks.text(it, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        }
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(recordId, 1, 256)
        AgentBridgeChecks.text(recordType, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        AgentBridgeChecks.require(sourceId == "provider_native")
    }
}

@Serializable
data class AgentBridgeNativeIdentityProviderNativeMetadataStatus(
    @SerialName("client_record_id") val clientRecordId: AgentBridgeClientIdAvailability,
    @SerialName("client_record_version") val clientRecordVersion: AgentBridgeMetadataAvailability,
    @SerialName("last_modified") val lastModified: AgentBridgeMetadataAvailability,
) {
    init {
    }
}

@Serializable
data class AgentBridgeSessionItemStagesItem(
    val end: AgentBridgeExactTime,
    @SerialName("raw_type") val rawType: Int,
    val start: AgentBridgeExactTime,
    val symbol: String,
) {
    init {
        AgentBridgeChecks.require(rawType.toLong() in -2147483648L..2147483647L)
        AgentBridgeChecks.text(symbol, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseWorkoutListingSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseSleepSessionListing(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeSessionItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseSleepSessionListingSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..1000)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "sleep_session_listing")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeQueryResponseSleepSessionListingSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponsePeriodComparison(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeComparisonItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponsePeriodComparisonSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..1000)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "period_comparison")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeComparisonItem(
    val delta: AgentBridgeValue? = null,
    val first: AgentBridgeMetricItem,
    @SerialName("metric_id") val metricId: String,
    val second: AgentBridgeMetricItem,
    val statistic: AgentBridgeCatalogItemStatisticsItem,
    val type: String,
    val unit: String,
) {
    init {
        AgentBridgeChecks.text(metricId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.require(type == "comparison")
        AgentBridgeChecks.text(unit, 1, 32)
    }
}

@Serializable
data class AgentBridgeQueryResponsePeriodComparisonSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseWorkoutSleepAlignment(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeAlignmentItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseWorkoutSleepAlignmentSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..1000)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "workout_sleep_alignment")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeAlignmentItem(
    @SerialName("gap_nanoseconds") val gapNanoseconds: String,
    val physiology: List<AgentBridgeMetricItem>,
    val relation: String,
    val sleep: AgentBridgeSessionItem? = null,
    val status: AgentBridgeAlignmentItemStatus,
    val type: String,
    val workout: AgentBridgeSessionItem,
) {
    init {
        AgentBridgeChecks.text(gapNanoseconds, 1, 32, "^[0-9]+\$")
        AgentBridgeChecks.require(physiology.size in 0..256)
        AgentBridgeChecks.require(relation == "first_following_sleep_start")
        AgentBridgeChecks.require(type == "alignment")
    }
}

@Serializable
data class AgentBridgeQueryResponseWorkoutSleepAlignmentSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseSourceRecordListing(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeEvidenceItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseSourceRecordListingSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..1000)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "source_record_listing")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgeEvidenceItem(
    val end: AgentBridgeExactTime,
    @SerialName("evidence_id") val evidenceId: String,
    val identity: AgentBridgeNativeIdentity,
    @SerialName("metric_ids") val metricIds: List<String>,
    val start: AgentBridgeExactTime,
    val type: String,
    val values: List<AgentBridgeMetricItem>,
) {
    init {
        AgentBridgeChecks.text(evidenceId, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(metricIds.size in 1..256)
        AgentBridgeChecks.require(metricIds.distinct().size == metricIds.size)
        metricIds.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        AgentBridgeChecks.require(type == "evidence")
        AgentBridgeChecks.require(values.size in 0..256)
    }
}

@Serializable
data class AgentBridgeQueryResponseSourceRecordListingSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeQueryResponseDerivePacket(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    val items: List<AgentBridgeMetricItem>,
    @SerialName("limitation_count") val limitationCount: Int,
    val limitations: List<String>,
    @SerialName("limitations_truncated") val limitationsTruncated: Boolean,
    @SerialName("next_cursor") val nextCursor: String? = null,
    val operation: String,
    val packet: AgentBridgePacket,
    val peer: AgentBridgePeer,
    @SerialName("provider_id") val providerId: String,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_descriptor_count") val sourceDescriptorCount: Int,
    @SerialName("source_descriptors") val sourceDescriptors: List<AgentBridgeQueryResponseDerivePacketSourceDescriptorsItem>,
    @SerialName("source_descriptors_truncated") val sourceDescriptorsTruncated: Boolean,
    @SerialName("source_id") val sourceId: AgentBridgeQueryCatalogSourceId,
) : AgentBridgeQueryResponse {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.require(items.size in 0..0)
        AgentBridgeChecks.require(limitationCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(limitations.size in 0..64)
        AgentBridgeChecks.require(limitations.distinct().size == limitations.size)
        limitations.forEach { AgentBridgeChecks.text(it, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$") }
        nextCursor?.let {
            AgentBridgeChecks.text(it, 1, 4096)
        }
        AgentBridgeChecks.require(operation == "derive_packet")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_response")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceDescriptorCount.toLong() in 0L..2147483647L)
        AgentBridgeChecks.require(sourceDescriptors.size in 0..64)
    }
}

@Serializable
data class AgentBridgePacket(
    val facts: List<AgentBridgeMetricItem>,
    val kind: AgentBridgeQueryOperationDerivePacketKind,
    @SerialName("medical_interpretation") val medicalInterpretation: Boolean,
) {
    init {
        AgentBridgeChecks.require(facts.size in 0..1000)
        AgentBridgeChecks.require(medicalInterpretation == false)
    }
}

@Serializable
data class AgentBridgeQueryResponseDerivePacketSourceDescriptorsItem(
    val origin: String,
    @SerialName("provider_id") val providerId: String,
    val sha256: String,
    @SerialName("source_id") val sourceId: String,
) {
    init {
        AgentBridgeChecks.text(origin, 1, 256)
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(sha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(sourceId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
    }
}

@Serializable
data class AgentBridgeCursorClaims(
    @SerialName("authority_revision") val authorityRevision: Int,
    @SerialName("catalog_sha256") val catalogSha256: String,
    @SerialName("dataset_sha256") val datasetSha256: String,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("issued_at") val issuedAt: String,
    val nonce: String,
    val peer: AgentBridgePeer,
    val position: Int,
    @SerialName("query_sha256") val querySha256: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.require(authorityRevision.toLong() in 1L..2147483647L)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(expiresAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.text(issuedAt, 20, 20, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$")
        AgentBridgeChecks.text(nonce, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(position.toLong() in 0L..2147483647L)
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_cursor_claims")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeQueryCancel(
    @SerialName("dataset_sha256") val datasetSha256: String,
    val peer: AgentBridgePeer,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_cancel")
        AgentBridgeChecks.require(schemaVersion == 1)
    }
}

@Serializable
data class AgentBridgeQueryCancelled(
    @SerialName("dataset_sha256") val datasetSha256: String,
    val peer: AgentBridgePeer,
    @SerialName("query_sha256") val querySha256: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("source_acknowledged") val sourceAcknowledged: Boolean,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(datasetSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(querySha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_query_cancelled")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sourceAcknowledged == true)
    }
}

@Serializable
data class AgentBridgeProjectionCatalog(
    @SerialName("artifact_profile") val artifactProfile: String,
    @SerialName("contains_health_values") val containsHealthValues: Boolean,
    val fields: List<AgentBridgeProjectionCatalogFieldsItem>,
    @SerialName("implementation_state") val implementationState: String,
    @SerialName("product_id") val productId: String,
    @SerialName("provider_id") val providerId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("sdk_version") val sdkVersion: String,
    @SerialName("source_id") val sourceId: String,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.require(artifactProfile == "android-source-projection-v1")
        AgentBridgeChecks.require(containsHealthValues == false)
        AgentBridgeChecks.require(fields.size in 1..256)
        AgentBridgeChecks.require(implementationState == "planned")
        AgentBridgeChecks.require(productId == "android_source_projection_v1")
        AgentBridgeChecks.require(providerId == "health_connect")
        AgentBridgeChecks.require(schema == "healthmd.source_projection_catalog")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.require(sdkVersion == "1.2.0-alpha02")
        AgentBridgeChecks.require(sourceId == "health_connect")
    }
}

@Serializable
data class AgentBridgeProjectionCatalogFieldsItem(
    @SerialName("field_id") val fieldId: String,
    @SerialName("native_record_type") val nativeRecordType: String,
    @SerialName("native_value_key") val nativeValueKey: String,
    @SerialName("object_id") val objectId: AgentBridgeProjectionCatalogFieldsItemObjectId,
    @SerialName("parent_record_type") val parentRecordType: String? = null,
    @SerialName("selection_metric_id") val selectionMetricId: String,
    val unit: String,
    @SerialName("value_role") val valueRole: AgentBridgeProjectionCatalogFieldsItemValueRole,
) {
    init {
        AgentBridgeChecks.text(fieldId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(nativeRecordType, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        AgentBridgeChecks.text(nativeValueKey, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        parentRecordType?.let {
            AgentBridgeChecks.text(it, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        }
        AgentBridgeChecks.text(selectionMetricId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(unit, 1, 32)
    }
}

@Serializable
data class AgentBridgeProjection(
    @SerialName("calendar_timezone") val calendarTimezone: String,
    @SerialName("catalog_sha256") val catalogSha256: String,
    val coverage: AgentBridgeCoverage,
    val detail: AgentBridgeProjectionRequestDetail,
    @SerialName("is_complete_daily_document") val isCompleteDailyDocument: Boolean,
    @SerialName("native_records") val nativeRecords: List<AgentBridgeEvidenceItem>,
    @SerialName("owner_date") val ownerDate: String,
    val peer: AgentBridgePeer,
    @SerialName("projection_catalog_sha256") val projectionCatalogSha256: String,
    @SerialName("provider_id") val providerId: String,
    @SerialName("request_id") val requestId: String,
    override val schema: String,
    @SerialName("schema_version") override val schemaVersion: Int,
    @SerialName("scope_sha256") val scopeSha256: String,
    @SerialName("selected_series") val selectedSeries: List<AgentBridgeSourceObservation>,
    @SerialName("source_id") val sourceId: AgentBridgeProjectionRequestSourceId,
    val summary: List<AgentBridgeMetricItem>,
) : AgentBridgeDocument {
    init {
        AgentBridgeChecks.text(calendarTimezone, 1, 128)
        AgentBridgeChecks.text(catalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(isCompleteDailyDocument == false)
        AgentBridgeChecks.require(nativeRecords.size in 0..1000)
        AgentBridgeChecks.text(ownerDate, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
        AgentBridgeChecks.text(projectionCatalogSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(providerId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(requestId, 36, 36, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$")
        AgentBridgeChecks.require(schema == "healthmd.source_data_projection")
        AgentBridgeChecks.require(schemaVersion == 1)
        AgentBridgeChecks.text(scopeSha256, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.require(selectedSeries.size in 0..1000)
        AgentBridgeChecks.require(summary.size in 0..256)
    }
}

@Serializable
data class AgentBridgeSourceObservation(
    val end: AgentBridgeExactTime? = null,
    @SerialName("field_id") val fieldId: String,
    val identity: AgentBridgeNativeIdentity,
    @SerialName("native_value_key") val nativeValueKey: String,
    @SerialName("observation_id") val observationId: String,
    @SerialName("observation_kind") val observationKind: AgentBridgeSourceObservationObservationKind,
    @SerialName("owner_date") val ownerDate: String,
    @SerialName("selection_metric_id") val selectionMetricId: String,
    val start: AgentBridgeExactTime,
    val type: String,
    val unit: String,
    val value: AgentBridgeSourceObservationValue,
) {
    init {
        AgentBridgeChecks.text(fieldId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.text(nativeValueKey, 1, 256, "^[A-Za-z_][A-Za-z0-9_.:\$-]{0,255}\$")
        AgentBridgeChecks.text(observationId, 64, 64, "^[0-9a-f]{64}\$")
        AgentBridgeChecks.text(ownerDate, 10, 10, "^[0-9]{4}-[0-9]{2}-[0-9]{2}\$")
        AgentBridgeChecks.text(selectionMetricId, 1, 128, "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\$")
        AgentBridgeChecks.require(type == "source_observation")
        AgentBridgeChecks.text(unit, 1, 32)
    }
}

@Serializable
data class AgentBridgeSourceObservationValue(
    val type: String,
    val value: Long,
) {
    init {
        AgentBridgeChecks.require(type == "integer")
        AgentBridgeChecks.require(value.toLong() in 0L..9223372036854775807L)
    }
}

internal object AgentBridgeSerializers {
    fun archive(element: JsonElement): DeserializationStrategy<AgentBridgeArchive> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "none" -> AgentBridgeArchiveNone.serializer()
            "apple_healthkit_canonical_v1" -> AgentBridgeArchiveAppleHealthkitCanonicalV1.serializer()
            "android_provider_native_snapshot_v1" -> AgentBridgeArchiveAndroidProviderNativeSnapshotV1.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun dates(element: JsonElement): DeserializationStrategy<AgentBridgeDates> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "exact" -> AgentBridgeDatesExact.serializer()
            "all_available" -> AgentBridgeDatesAllAvailable.serializer()
            "past_complete_days" -> AgentBridgeDatesPastCompleteDays.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun dictionary(element: JsonElement): DeserializationStrategy<AgentBridgeDictionary> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "none" -> AgentBridgeDictionaryNone.serializer()
            "profile_dictionary_v1" -> AgentBridgeDictionaryProfileDictionaryV1.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun packaging(element: JsonElement): DeserializationStrategy<AgentBridgePackaging> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "loose_files" -> AgentBridgePackagingLooseFiles.serializer()
            "zip" -> AgentBridgePackagingZip.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun settingsPolicy(element: JsonElement): DeserializationStrategy<AgentBridgeSettingsPolicy> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "explicit" -> AgentBridgeSettingsPolicyExplicit.serializer()
            "saved_device_settings" -> AgentBridgeSettingsPolicySavedDeviceSettings.serializer()
            "profile" -> AgentBridgeSettingsPolicyProfile.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun intent(element: JsonElement): DeserializationStrategy<AgentBridgeIntent> {
        val obj = element.jsonObject
        return when (obj.getValue("product").jsonObject.getValue("type").jsonPrimitive.content) {
            "generated_files" -> AgentBridgeGeneratedIntent.serializer()
            "source_projection" -> AgentBridgeProjectionIntent.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun plan(element: JsonElement): DeserializationStrategy<AgentBridgePlan> {
        val obj = element.jsonObject
        return when (obj.getValue("intent").jsonObject.getValue("product").jsonObject.getValue("type").jsonPrimitive.content) {
            "generated_files" -> AgentBridgeGeneratedPlan.serializer()
            "source_projection" -> AgentBridgeProjectionPlan.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun exportDelegationBoundsDatePolicy(element: JsonElement): DeserializationStrategy<AgentBridgeExportDelegationBoundsDatePolicy> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "bounded_exact" -> AgentBridgeExportDelegationBoundsDatePolicyBoundedExact.serializer()
            "authorized_history" -> AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun exportDelegationBoundsDestinationPolicy(element: JsonElement): DeserializationStrategy<AgentBridgeExportDelegationBoundsDestinationPolicy> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "authenticated_host_bindings" -> AgentBridgeExportDelegationBoundsDestinationPolicyAuthenticatedHostBindings.serializer()
            "registered_host_bindings" -> AgentBridgeExportDelegationBoundsDestinationPolicyRegisteredHostBindings.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun queryOperation(element: JsonElement): DeserializationStrategy<AgentBridgeQueryOperation> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "metric_catalog" -> AgentBridgeQueryOperationMetricCatalog.serializer()
            "metric_series" -> AgentBridgeQueryOperationMetricSeries.serializer()
            "coverage" -> AgentBridgeQueryOperationCoverage.serializer()
            "workout_listing" -> AgentBridgeQueryOperationWorkoutListing.serializer()
            "source_record_listing" -> AgentBridgeQueryOperationSourceRecordListing.serializer()
            "sleep_session_listing" -> AgentBridgeQueryOperationSleepSessionListing.serializer()
            "workout_sleep_alignment" -> AgentBridgeQueryOperationWorkoutSleepAlignment.serializer()
            "period_comparison" -> AgentBridgeQueryOperationPeriodComparison.serializer()
            "derive_packet" -> AgentBridgeQueryOperationDerivePacket.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun value(element: JsonElement): DeserializationStrategy<AgentBridgeValue> {
        val obj = element.jsonObject
        return when (obj.getValue("type").jsonPrimitive.content) {
            "integer" -> AgentBridgeValueInteger.serializer()
            "decimal" -> AgentBridgeValueDecimal.serializer()
            "text" -> AgentBridgeValueText.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun nativeIdentity(element: JsonElement): DeserializationStrategy<AgentBridgeNativeIdentity> {
        val obj = element.jsonObject
        return when (obj.getValue("source_id").jsonPrimitive.content) {
            "apple_health" -> AgentBridgeNativeIdentityAppleHealth.serializer()
            "health_connect" -> AgentBridgeNativeIdentityHealthConnect.serializer()
            "provider_native" -> AgentBridgeNativeIdentityProviderNative.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun queryResponse(element: JsonElement): DeserializationStrategy<AgentBridgeQueryResponse> {
        val obj = element.jsonObject
        return when (obj.getValue("operation").jsonPrimitive.content) {
            "metric_catalog" -> AgentBridgeQueryResponseMetricCatalog.serializer()
            "metric_series" -> AgentBridgeQueryResponseMetricSeries.serializer()
            "coverage" -> AgentBridgeQueryResponseCoverage.serializer()
            "workout_listing" -> AgentBridgeQueryResponseWorkoutListing.serializer()
            "sleep_session_listing" -> AgentBridgeQueryResponseSleepSessionListing.serializer()
            "period_comparison" -> AgentBridgeQueryResponsePeriodComparison.serializer()
            "workout_sleep_alignment" -> AgentBridgeQueryResponseWorkoutSleepAlignment.serializer()
            "source_record_listing" -> AgentBridgeQueryResponseSourceRecordListing.serializer()
            "derive_packet" -> AgentBridgeQueryResponseDerivePacket.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }
    fun document(element: JsonElement): DeserializationStrategy<AgentBridgeDocument> =
        when (element.jsonObject.getValue("schema").jsonPrimitive.content) {
            "healthmd.agent_discovery_request" -> AgentBridgeDiscoveryRequest.serializer()
            "healthmd.agent_discovery" -> AgentBridgeDiscovery.serializer()
            "healthmd.agent_export_intent" -> AgentBridgeIntentSerializer
            "healthmd.agent_plan_request" -> AgentBridgePlanRequest.serializer()
            "healthmd.agent_export_plan" -> AgentBridgePlanSerializer
            "healthmd.agent_approval_request" -> AgentBridgeApprovalRequest.serializer()
            "healthmd.agent_approval" -> AgentBridgeApproval.serializer()
            "healthmd.agent_execute_request" -> AgentBridgeExecuteRequest.serializer()
            "healthmd.agent_execution_receipt" -> AgentBridgeExecutionReceipt.serializer()
            "healthmd.agent_cancel_request" -> AgentBridgeCancelRequest.serializer()
            "healthmd.agent_resume_request" -> AgentBridgeResumeRequest.serializer()
            "healthmd.agent_artifact_manifest" -> AgentBridgeArtifactManifest.serializer()
            "healthmd.agent_commit_receipt" -> AgentBridgeCommitReceipt.serializer()
            "healthmd.agent_authority" -> AgentBridgeAuthority.serializer()
            "healthmd.agent_export_delegation" -> AgentBridgeExportDelegation.serializer()
            "healthmd.agent_error" -> AgentBridgeError.serializer()
            "healthmd.source_query_catalog" -> AgentBridgeQueryCatalog.serializer()
            "healthmd.source_query_request" -> AgentBridgeQueryRequest.serializer()
            "healthmd.source_query_response" -> AgentBridgeQueryResponseSerializer
            "healthmd.source_query_cursor_claims" -> AgentBridgeCursorClaims.serializer()
            "healthmd.source_query_cancel" -> AgentBridgeQueryCancel.serializer()
            "healthmd.source_query_cancelled" -> AgentBridgeQueryCancelled.serializer()
            "healthmd.source_projection_catalog" -> AgentBridgeProjectionCatalog.serializer()
            "healthmd.source_projection_request" -> AgentBridgeProjectionRequest.serializer()
            "healthmd.source_data_projection" -> AgentBridgeProjection.serializer()
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
}

object AgentBridgeDocumentSerializer : JsonContentPolymorphicSerializer<AgentBridgeDocument>(AgentBridgeDocument::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<AgentBridgeDocument> =
        AgentBridgeShapes.checked(element, AgentBridgeSerializers.document(element))
}
