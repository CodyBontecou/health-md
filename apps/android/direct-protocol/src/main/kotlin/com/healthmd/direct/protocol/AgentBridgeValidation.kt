package com.healthmd.direct.protocol

import java.math.BigInteger
import java.text.Normalizer
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Pure document checks only. Source/metric resolution, issued records, current revisions/consent,
 * root handles, artifact bytes, idempotency, cursor MAC/snapshot state, and authorization remain
 * separate native/host gates. Successfully decoded JSON never supplies those facts. */
object AgentBridgeValidation {
    private val invalid = AgentBridgeErrorCode.INVALID_REQUEST
    private val changed = AgentBridgeErrorCode.BINDING_CHANGED
    private val unsupported = AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY
    private val approval = AgentBridgeErrorCode.APPROVAL_REQUIRED
    private val billion = BigInteger.valueOf(1000000000L)
    private const val zeroDigest = "0000000000000000000000000000000000000000000000000000000000000000"
    private val queryOperations = setOf("metric_catalog", "metric_series", "coverage", "workout_listing",
        "source_record_listing", "sleep_session_listing", "workout_sleep_alignment", "period_comparison", "derive_packet")
    private val projectionFields = mapOf(
        "steps" to ProjectionField("daily_summary", "steps", "steps", "COUNT_TOTAL", "StepsRecord", "daily_aggregate"),
        "heart_rate_avg" to ProjectionField("daily_summary", "heart_rate_avg", "bpm", "BPM_AVG", "HeartRateRecord", "daily_aggregate"),
        "steps.count" to ProjectionField("selected_series", "steps", "steps", "count", "StepsRecord", "interval_total"),
        "heart_rate.samples.bpm" to ProjectionField("selected_series", "heart_rate_avg", "bpm", "beatsPerMinute", "HeartRateRecord\$Sample", "point", "HeartRateRecord"),
        "steps.record" to ProjectionField("native_records", "steps", "steps", "count", "StepsRecord", "native_record"),
    )
    private data class ProjectionField(val objectId: String, val metric: String, val unit: String,
        val valueKey: String, val recordType: String, val role: String, val parent: String? = null)
    private const val hcTypes = "androidx.health.connect.client.records."

    internal fun validate(document: AgentBridgeDocument) {
        when (document) {
            is AgentBridgeDiscovery -> discovery(document)
            is AgentBridgeIntent -> intent(document)
            is AgentBridgeGeneratedPlan -> generatedPlan(document)
            is AgentBridgeProjectionPlan -> projectionPlan(document)
            is AgentBridgePlanRequest -> {
                intent(document.intent)
                check(document.hostAuthorityReference.issuer == AgentBridgeIssuer.AUTHORIZED_HOST, approval)
            }
            is AgentBridgeApprovalRequest -> binding(document.binding)
            is AgentBridgeApproval -> { binding(document.binding); utc(document.approvedAt) }
            is AgentBridgeExecuteRequest -> {
                validate(document.plan)
                validate(document.approval)
                check(document.approval.binding == bindingFor(document.plan), changed)
                check(document.approval.authorityId == document.approval.binding.authorityReferences.native.authorityId, approval)
                val tree = AgentBridgeCodec.tree(document.plan)
                check(utc(document.approval.approvedAt) in utc(tree.text("issued_at"))..utc(tree.text("expires_at")), approval)
            }
            is AgentBridgeExecutionReceipt -> {
                binding(document.binding); utc(document.expiresAt)
                if (document.status in listOf(AgentBridgeExecutionReceiptStatus.COMPLETE,
                        AgentBridgeExecutionReceiptStatus.COMPLETE_EMPTY, AgentBridgeExecutionReceiptStatus.CANCELLED)) {
                    check(document.sourceAcknowledged)
                }
            }
            is AgentBridgeResumeRequest -> {
                binding(document.binding)
                check(document.peer == document.binding.peer && document.destination == document.binding.destination, changed)
            }
            is AgentBridgeArtifactManifest -> manifest(document)
            is AgentBridgeCommitReceipt -> {
                check(document.destination.hostInstallationId == document.peer.hostInstallationId, changed)
                safePath(document.relativePath, filename = false, templates = false, allowEmpty = false)
                val fields = setOf("job_id", "artifact_id", "destination", "request_sha256", "manifest_sha256",
                    "relative_path", "write_mode", "input_sha256", "before_sha256", "after_sha256")
                check(document.commitKey == AgentBridgeCodec.digest(JsonObject(AgentBridgeCodec.tree(document).filterKeys { it in fields })), changed)
            }
            is AgentBridgeAuthority -> { utc(document.expiresAt); sortedEnums(document.rights); sorted(document.destinationBindingIds) }
            is AgentBridgeExportDelegation -> delegation(document)
            is AgentBridgeQueryCatalog -> catalog(document)
            is AgentBridgeQueryRequest -> queryRequest(document)
            is AgentBridgeQueryResponse -> queryResponse(document)
            is AgentBridgeCursorClaims -> lifetime(document.issuedAt, document.expiresAt, 3600)
            is AgentBridgeProjectionRequest -> projectionRequest(document)
            is AgentBridgeProjectionCatalog -> projectionCatalog(document)
            is AgentBridgeProjection -> projection(document)
            is AgentBridgeDiscoveryRequest, is AgentBridgeCancelRequest, is AgentBridgeQueryCancel,
            is AgentBridgeQueryCancelled, is AgentBridgeError -> Unit
        }
        // This walks the canonical form of already closed DTOs, never a generic forwarded document.
        // Dates/time/identity may be nested inside typed operation-specific items.
        nestedChecks(AgentBridgeCodec.tree(document))
    }

    fun capabilityDigest(document: AgentBridgeDiscovery): String = AgentBridgeCodec.digest(
        JsonObject(AgentBridgeCodec.tree(document).filterKeys { it !in setOf("capability_sha256", "request_id", "issued_at", "expires_at") }),
    )

    fun planDigest(document: AgentBridgePlan): String = AgentBridgeCodec.digest(
        JsonObject(AgentBridgeCodec.tree(document).filterKeys { it != "plan_sha256" }),
    )

    fun bindingFor(plan: AgentBridgePlan): AgentBridgeBinding = when (plan) {
        is AgentBridgeGeneratedPlan -> AgentBridgeBinding(plan.authorityReferences, plan.capabilitySha256,
            plan.intent.destination, plan.expiresAt, plan.intent.peer, plan.planSha256, plan.revisions, plan.scopeSha256, plan.settingsSha256)
        is AgentBridgeProjectionPlan -> AgentBridgeBinding(plan.authorityReferences, plan.capabilitySha256,
            plan.intent.destination, plan.expiresAt, plan.intent.peer, plan.planSha256, plan.revisions, plan.scopeSha256, plan.settingsSha256)
    }

    /** Structural comparison only; the argument is NOT looked up or issued by this helper. */
    fun validateApprovalBinding(request: AgentBridgeApprovalRequest, plan: AgentBridgePlan) = AgentBridgeCodec.sanitized {
        validate(plan)
        val id = when (plan) { is AgentBridgeGeneratedPlan -> plan.planId; is AgentBridgeProjectionPlan -> plan.planId }
        check(request.planId == id && request.binding == bindingFor(plan), changed)
    }

    /** Pure bounded derivation from an issuer's ALREADY loaded private record. This helper neither
     * looks up nor issues permission: the source verifies only native_source, the host only its own
     * authorized_host record/root. The result keeps the parent identity and cannot grant controls.
     * Logical history max_days must additionally be checked after approved execution, not by reads here. */
    fun deriveExportAuthority(
        parent: AgentBridgeExportDelegation,
        plan: AgentBridgeGeneratedPlan,
        now: Instant,
        nativeConsent: AgentBridgeDiscoveryEntitlement,
        entitlement: AgentBridgeDiscoveryEntitlement,
    ): AgentBridgeAuthority = AgentBridgeCodec.sanitized {
        // Exercise strict typed checks even for mutable native constructors.
        AgentBridgeCodec.encode(parent); AgentBridgeCodec.encode(plan)
        val reference = if (parent.issuer == AgentBridgeIssuer.NATIVE_SOURCE) plan.authorityReferences.native
            else plan.authorityReferences.host
        check(reference == AgentBridgeAuthorityReference(parent.authorityId, parent.grantRevision,
            AgentBridgeCodec.fingerprint(parent), parent.issuer), approval)
        check(parent.peer == plan.intent.peer, approval)
        check(AgentBridgeExportDelegationRightsItem.PLAN in parent.rights, approval)
        check(now < utc(parent.expiresAt) && now < utc(plan.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
        val b = parent.bounds
        val capture = plan.intent.captureScope
        val output = plan.effectiveSettings
        check(AgentBridgeExportDelegationBoundsProductsItem.GENERATED_FILES in b.products, approval)
        check(b.metricIds.containsAll(plan.resolvedMetricIds) && plan.intent.calendarTimezone in b.calendarTimezones, approval)
        check(capture.compatibilityDetail in b.compatibilityDetail, approval)
        val archive = when (capture.nativeArchive) {
            is AgentBridgeArchiveNone -> AgentBridgeOutputSupportNativeArchiveProductsItem.NONE
            is AgentBridgeArchiveAppleHealthkitCanonicalV1 -> AgentBridgeOutputSupportNativeArchiveProductsItem.APPLE_HEALTHKIT_CANONICAL_V1
            is AgentBridgeArchiveAndroidProviderNativeSnapshotV1 -> AgentBridgeOutputSupportNativeArchiveProductsItem.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1
        }
        check(archive in b.nativeArchiveProducts && b.formats.containsAll(output.formats) &&
            output.outputProfile in b.outputProfiles && output.writeMode in b.writeModes, approval)
        when (val policy = b.destinationPolicy) {
            is AgentBridgeExportDelegationBoundsDestinationPolicyAuthenticatedHostBindings -> check(parent.issuer == AgentBridgeIssuer.NATIVE_SOURCE, approval)
            is AgentBridgeExportDelegationBoundsDestinationPolicyRegisteredHostBindings -> check(parent.issuer == AgentBridgeIssuer.AUTHORIZED_HOST &&
                plan.intent.destination.bindingId in policy.bindingIds, approval)
        }
        val datePolicy = b.datePolicy
        when (val dates = plan.resolvedDates) {
            is AgentBridgeDatesAllAvailable -> check(datePolicy is AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory && datePolicy.allowAllAvailable, approval)
            is AgentBridgeDatesExact -> {
                val count = java.time.temporal.ChronoUnit.DAYS.between(date(dates.range.startDate), date(dates.range.endDate)) + 1
                when (datePolicy) {
                    is AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory -> check(count <= datePolicy.maxDays, approval)
                    is AgentBridgeExportDelegationBoundsDatePolicyBoundedExact -> check(count <= datePolicy.maxDays &&
                        dates.range.startDate >= datePolicy.range.startDate && dates.range.endDate <= datePolicy.range.endDate, approval)
                }
            }
            is AgentBridgeDatesPastCompleteDays -> throw AgentBridgeException(invalid) // Plans must resolve anchors first.
        }
        val rights = parent.rights.map {
            when (it) {
                AgentBridgeExportDelegationRightsItem.DISCOVER -> AgentBridgeAuthorityRightsItem.DISCOVER
                AgentBridgeExportDelegationRightsItem.PLAN -> AgentBridgeAuthorityRightsItem.PLAN
                AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE -> AgentBridgeAuthorityRightsItem.EXPORT_EXECUTE
            }
        }
        AgentBridgeAuthority(parent.authorityId, AgentBridgeAuthorityConfigurationProtection.NOT_APPLICABLE,
            destinationBindingIds = listOf(plan.intent.destination.bindingId), entitlement = entitlement,
            expiresAt = minOf(utc(parent.expiresAt), utc(plan.expiresAt)).toString(), grantRevision = parent.grantRevision,
            issuer = parent.issuer, nativeConsent = nativeConsent, peer = parent.peer, rights = rights,
            schema = "healthmd.agent_authority", schemaVersion = 1, scopeSha256 = plan.scopeSha256)
    }

    /** Exact journal-value comparison, NOT native resume/revocation/spool authorization. */
    fun validateResumeAgainst(request: AgentBridgeResumeRequest, preserved: AgentBridgeResumeRequest) = AgentBridgeCodec.sanitized {
        validate(request); validate(preserved)
        check(request == preserved, changed)
    }

    private fun discovery(value: AgentBridgeDiscovery) {
        check(value.capabilitySha256 == capabilityDigest(value), changed)
        lifetime(value.issuedAt, value.expiresAt, 600)
        zone(value.sourceCalendarTimezone)
        sortedEnums(value.features); sortedEnums(value.settingsPolicies); sortedEnums(value.outputProfiles)
        sortedEnums(value.controlOperations); sortedEnums(value.projectionProducts); sorted(value.queryOperations)
        check(value.queryOperations.all { it in queryOperations })
        if (AgentBridgeDiscoveryFeaturesItem.SOURCE_QUERY !in value.features) {
            check(value.queryOperations.isEmpty() && value.queryCatalogSha256 == zeroDigest)
        }
        val sourceProjection = AgentBridgeDiscoveryFeaturesItem.SOURCE_PROJECTION in value.features
        check(value.projectionProducts.isNotEmpty() == sourceProjection)
        if (sourceProjection) {
            val catalog = value.projectionSourceCatalog ?: throw AgentBridgeException(invalid)
            catalog(catalog)
            check(catalog.peer == value.peer && catalog.sourceId == AgentBridgeQueryCatalogSourceId.HEALTH_CONNECT)
            check(value.projectionCatalogSha256 == reviewedProjectionCatalogDigest)
            check(catalog.history.daysConsidered == 0 && catalog.history.daysWithValues == 0 &&
                catalog.history.missingCount == 0 && catalog.history.missing.isEmpty())
        } else check(value.projectionCatalogSha256 == zeroDigest && value.projectionSourceCatalog == null)
        check(value.authorityReferences.all { it.issuer == AgentBridgeIssuer.NATIVE_SOURCE })
        check(value.authorityReferences.map { it.authorityId }.distinct().size == value.authorityReferences.size)
        val s = value.outputSupport
        sortedEnums(s.formats); sortedEnums(s.writeModes); sortedEnums(s.compatibilityDetail)
        sortedEnums(s.nativeArchiveProducts); sortedEnums(s.pathTokens); sorted(s.settingPointers)
    }

    private fun binding(value: AgentBridgeBinding) {
        check(value.peer.hostInstallationId == value.destination.hostInstallationId, changed)
        references(value.authorityReferences)
        revisions(value.revisions)
        utc(value.expiresAt)
    }

    private fun references(value: AgentBridgeAuthorityReferences) {
        check(value.native.issuer == AgentBridgeIssuer.NATIVE_SOURCE && value.host.issuer == AgentBridgeIssuer.AUTHORIZED_HOST, approval)
    }

    private fun revisions(value: List<AgentBridgeRevision>) {
        val keys = value.map { enumText(it.domain) + ":" + it.objectId }
        check(keys.distinct().size == keys.size)
        check(keys == keys.sorted())
    }

    private fun intent(value: AgentBridgeIntent) {
        val peer: AgentBridgePeer
        val destination: AgentBridgeDestination
        val dates: AgentBridgeDates
        val timezone: String
        val capture: AgentBridgeCapture
        when (value) {
            is AgentBridgeGeneratedIntent -> {
                peer = value.peer; destination = value.destination; dates = value.dates
                timezone = value.calendarTimezone; capture = value.captureScope
                when (val policy = value.settingsPolicy) {
                    is AgentBridgeSettingsPolicyExplicit -> outputSettings(policy.settings, peer.platform)
                    is AgentBridgeSettingsPolicyProfile, is AgentBridgeSettingsPolicySavedDeviceSettings -> Unit
                }
            }
            is AgentBridgeProjectionIntent -> {
                peer = value.peer; destination = value.destination; dates = value.dates
                timezone = value.calendarTimezone; capture = value.captureScope
                val request = value.product.request
                projectionRequest(request); projectionOutput(value.product.output)
                check(peer == request.peer && dates == request.dates && timezone == request.calendarTimezone && capture.selection == request.selection, changed)
                check(capture.nativeArchive is AgentBridgeArchiveNone, changed)
                val expected = if (request.detail == AgentBridgeProjectionRequestDetail.SUMMARY) AgentBridgeCompatibilityDetail.SUMMARY
                    else AgentBridgeCompatibilityDetail.SELECTED_TIME_SERIES
                check(capture.compatibilityDetail == expected, changed)
            }
        }
        check(destination.hostInstallationId == peer.hostInstallationId, changed)
        resolveDates(dates, timezone)
        selection(capture.selection)
        check(capture.selection.sourceIds == listOf(if (peer.platform == AgentBridgePlatform.APPLE) "apple_health" else "health_connect") && capture.selection.providerIds.isEmpty(), unsupported)
        check(capture.selection.allMetrics || capture.selection.metricIds.isNotEmpty() || capture.selection.categoryIds.isNotEmpty(), AgentBridgeErrorCode.UNSUPPORTED_METRIC)
        when (val archive = capture.nativeArchive) {
            is AgentBridgeArchiveAppleHealthkitCanonicalV1 -> check(peer.platform == AgentBridgePlatform.APPLE, unsupported)
            is AgentBridgeArchiveAndroidProviderNativeSnapshotV1 -> {
                check(peer.platform == AgentBridgePlatform.ANDROID && archive.providerId == "health_connect", unsupported)
                if (archive.recordScope == AgentBridgeArchiveAndroidProviderNativeSnapshotV1RecordScope.ALL_AUTHORIZED_SUPPORTED) {
                    check(capture.selection.allMetrics, changed)
                }
            }
            is AgentBridgeArchiveNone -> Unit
        }
    }

    private fun generatedPlan(p: AgentBridgeGeneratedPlan) {
        intent(p.intent); outputSettings(p.effectiveSettings, p.intent.peer.platform)
        check(p.planSha256 == planDigest(p), changed)
        val settings = p.effectiveSettings
        val policy = p.intent.settingsPolicy
        when (policy) {
            is AgentBridgeSettingsPolicyExplicit -> check(settings == policy.settings, changed)
            is AgentBridgeSettingsPolicySavedDeviceSettings -> {
                val pins = p.revisions.filter { it.domain == AgentBridgeRevisionDomain.DEVICE_SETTINGS }
                check(pins.size == 1 && pins.single().revision == policy.expectedRevision, AgentBridgeErrorCode.REVISION_CONFLICT)
            }
            is AgentBridgeSettingsPolicyProfile -> {
                val pins = p.revisions.filter { it.domain == AgentBridgeRevisionDomain.NATIVE_PROFILE }
                check(pins.size == 1 && pins.single().revision == policy.expectedRevision && pins.single().objectId == policy.profileId, AgentBridgeErrorCode.REVISION_CONFLICT)
            }
        }
        if (settings.individualEntries.enabled) {
            check(settings.individualEntries.metricIds.isNotEmpty() && p.resolvedMetricIds.containsAll(settings.individualEntries.metricIds), changed)
            check(p.intent.captureScope.nativeArchive !is AgentBridgeArchiveNone, unsupported)
        }
        val output = AgentBridgeCodec.tree(AgentBridgeOutputSettings.serializer(), settings)
        val origin = when (policy) {
            is AgentBridgeSettingsPolicyExplicit -> AgentBridgeOriginOrigin.REQUEST
            is AgentBridgeSettingsPolicyProfile -> AgentBridgeOriginOrigin.PROFILE
            is AgentBridgeSettingsPolicySavedDeviceSettings -> AgentBridgeOriginOrigin.SAVED_DEVICE_SETTINGS
        }
        val revision = when (policy) {
            is AgentBridgeSettingsPolicyExplicit -> 0
            is AgentBridgeSettingsPolicyProfile -> policy.expectedRevision
            is AgentBridgeSettingsPolicySavedDeviceSettings -> policy.expectedRevision
        }
        commonPlan(p, p.intent, p.resolvedDates, p.resolvedMetricIds, output, p.settingsSha256, p.scopeSha256,
            p.planSha256, p.authorityReferences, p.revisions, p.issuedAt, p.expiresAt, p.predictedPaths,
            p.pathPrediction, p.limitations, p.origins, "/effective_settings", origin, revision)
        check(p.predictedPaths == predictedPaths(p.intent, settings), changed)
        if (p.resolvedDates !is AgentBridgeDatesAllAvailable && settings.individualEntries.enabled) {
            check(p.pathPrediction == AgentBridgeGeneratedPlanPathPrediction.DEFERRED_NATIVE_ENTRIES && "entry_paths_unresolved" in p.limitations, changed)
        }
    }

    private fun projectionPlan(p: AgentBridgeProjectionPlan) {
        intent(p.intent)
        projectionOutput(p.effectiveProjectionOutput)
        check(p.effectiveProjectionOutput == p.intent.product.output, changed)
        check(p.revisions.isEmpty(), AgentBridgeErrorCode.REVISION_CONFLICT)
        commonPlan(p, p.intent, p.resolvedDates, p.resolvedMetricIds,
            AgentBridgeCodec.tree(AgentBridgeProjectionOutput.serializer(), p.effectiveProjectionOutput),
            p.settingsSha256, p.scopeSha256, p.planSha256, p.authorityReferences, p.revisions, p.issuedAt,
            p.expiresAt, p.predictedPaths, p.pathPrediction, p.limitations, p.origins, "/effective_projection_output",
            AgentBridgeOriginOrigin.REQUEST, 0)
        check(p.predictedPaths == projectionPaths(p.intent), changed)
        if (p.resolvedDates !is AgentBridgeDatesAllAvailable) check(p.pathPrediction == AgentBridgeGeneratedPlanPathPrediction.EXACT_REQUESTED_DAYS, changed)
    }

    private fun commonPlan(plan: AgentBridgePlan, intent: AgentBridgeIntent, resolved: AgentBridgeDates,
        metrics: List<String>, output: JsonElement, settingsDigest: String, scopeDigest: String,
        planDigest: String, refs: AgentBridgeAuthorityReferences, pins: List<AgentBridgeRevision>, issued: String,
        expires: String, paths: List<String>, prediction: AgentBridgeGeneratedPlanPathPrediction,
        limitations: List<String>, origins: List<AgentBridgeOrigin>, outputPointer: String,
        outputOrigin: AgentBridgeOriginOrigin, outputRevision: Int) {
        val value = AgentBridgeCodec.tree(intent)
        val capture = value.getValue("capture_scope")
        val selection = AgentBridgeCodec.json.decodeFromJsonElement(AgentBridgeSelection.serializer(), capture.jsonObject.getValue("selection"))
        sorted(metrics); references(refs); revisions(pins); sorted(limitations)
        val inputDates = when (intent) { is AgentBridgeGeneratedIntent -> intent.dates; is AgentBridgeProjectionIntent -> intent.dates }
        val timezone = when (intent) { is AgentBridgeGeneratedIntent -> intent.calendarTimezone; is AgentBridgeProjectionIntent -> intent.calendarTimezone }
        check(resolved == resolveDates(inputDates, timezone), changed)
        if (!selection.allMetrics && selection.categoryIds.isEmpty()) check(metrics == selection.metricIds, changed)
        check(settingsDigest == AgentBridgeCodec.digest(output), changed)
        val scope = JsonObject(mapOf("dates" to AgentBridgeCodec.tree(AgentBridgeDatesSerializer, resolved),
            "calendar_timezone" to JsonPrimitive(timezone), "capture_scope" to capture,
            "metric_ids" to JsonArray(metrics.map(::JsonPrimitive)), "product" to value.getValue("product")))
        check(scopeDigest == AgentBridgeCodec.digest(scope), changed)
        check(planDigest == planDigest(plan), changed)
        lifetime(issued, expires, 600)
        collisions(paths)
        if (resolved is AgentBridgeDatesAllAvailable) {
            check(paths.isEmpty() && prediction == AgentBridgeGeneratedPlanPathPrediction.TEMPLATE_ONLY_ALL_AVAILABLE && "history_bounds_unresolved" in limitations, changed)
        }
        val expected = leaves(output, outputPointer) + leaves(capture, "/capture_scope") + setOf("/resolved_dates", "/calendar_timezone") +
            if (intent is AgentBridgeProjectionIntent) leaves(value.getValue("product").jsonObject.getValue("request"), "/projection_request") else emptySet()
        check(origins.map { it.pointer }.toSet() == expected && origins.map { it.pointer }.distinct().size == origins.size)
        for (origin in origins) {
            val want = if (origin.pointer.startsWith("$outputPointer/")) outputOrigin else
                if (origin.pointer == "/resolved_dates") AgentBridgeOriginOrigin.RESOLVED_CALENDAR else AgentBridgeOriginOrigin.REQUEST
            check(origin.origin == want, changed)
            check(origin.revision == if (want == outputOrigin && origin.pointer.startsWith("$outputPointer/")) outputRevision else 0,
                AgentBridgeErrorCode.REVISION_CONFLICT)
        }
    }

    /** Configuration-only path prediction; no earliest-date/content/provider operation. */
    fun predictedPaths(intent: AgentBridgeGeneratedIntent, settings: AgentBridgeOutputSettings): List<String> =
        AgentBridgeCodec.sanitized { predictedPathsChecked(intent, settings) }

    private fun predictedPathsChecked(intent: AgentBridgeGeneratedIntent, settings: AgentBridgeOutputSettings): List<String> {
        val dates = resolveDates(intent.dates, intent.calendarTimezone)
        if (dates is AgentBridgeDatesAllAvailable) return emptyList()
        val range = (dates as AgentBridgeDatesExact).range
        val days = civilDays(range)
        check(days.size.toLong() * settings.formats.size <= 4096, AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        val result = mutableListOf<String>()
        for (day in days) {
            val parent = listOf(settings.subfolder, settings.folderTemplate).filter { it.isNotEmpty() }.joinToString("/") { expand(it, day) }
            val name = expand(settings.filenameTemplate, day)
            if (!settings.dailyNotes.only) for (format in settings.formats) {
                val ext = when (format) { AgentBridgeFormat.JSON -> "json"; AgentBridgeFormat.CSV -> "csv"; else -> "md" }
                val suffix = if (format == AgentBridgeFormat.OBSIDIAN_BASES && AgentBridgeFormat.MARKDOWN in settings.formats) "-bases" else ""
                result += join(parent, name + suffix + "." + ext)
            }
            val notes = settings.dailyNotes
            if (notes.enabled) result += join(expand(notes.folderTemplate, day), expand(notes.filenameTemplate, day) + ".md")
        }
        val anchor = date(range.endDate)
        val root = expand(settings.subfolder, anchor)
        val dictionary = settings.dictionary
        if (dictionary is AgentBridgeDictionaryProfileDictionaryV1) {
            val ext = if (dictionary.format == AgentBridgeDictionaryProfileDictionaryV1Format.JSON) ".json" else ".md"
            result += join(root, expand(dictionary.filenameTemplate, anchor) + ext)
        }
        collisions(result)
        val packaging = settings.packaging
        if (packaging is AgentBridgePackagingZip) {
            check(result.size <= packaging.maxEntries, AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
            val zip = join(root, expand(packaging.filenameTemplate, anchor) + ".zip")
            collisions(result + zip)
            if (!packaging.includeLooseFiles) return listOf(zip)
            result += zip
        }
        return result.sortedWith(AgentBridgeCodec::compareCodePoints)
    }

    private fun projectionPaths(intent: AgentBridgeProjectionIntent): List<String> {
        val dates = resolveDates(intent.dates, intent.calendarTimezone)
        if (dates is AgentBridgeDatesAllAvailable) return emptyList()
        val output = intent.product.output
        val paths = civilDays((dates as AgentBridgeDatesExact).range).map { day ->
            val parent = listOf(output.subfolder, output.folderTemplate).filter { it.isNotEmpty() }.joinToString("/") { expand(it, day) }
            join(parent, expand(output.filenameTemplate, day) + if (output.mediaType == AgentBridgeProjectionOutputMediaType.APPLICATION_JSON) ".json" else ".jsonl")
        }
        collisions(paths)
        return paths.sortedWith(AgentBridgeCodec::compareCodePoints)
    }

    private fun outputSettings(s: AgentBridgeOutputSettings, platform: AgentBridgePlatform) {
        sortedEnums(s.formats)
        check((s.outputProfile == AgentBridgeOutputProfile.APPLE_V8) == (platform == AgentBridgePlatform.APPLE), unsupported)
        dailyTemplates(s.subfolder, s.folderTemplate, s.filenameTemplate)
        dailyTemplates("", s.dailyNotes.folderTemplate, s.dailyNotes.filenameTemplate)
        safePath(s.individualEntries.folderTemplate, templates = true)
        safePath(s.individualEntries.filenameTemplate, filename = true, templates = true)
        if (s.dictionary is AgentBridgeDictionaryProfileDictionaryV1) dailyTemplates("", "", s.dictionary.filenameTemplate)
        if (s.packaging is AgentBridgePackagingZip) dailyTemplates("", "", s.packaging.filenameTemplate)
        if (s.writeMode in listOf(AgentBridgeWriteMode.MERGE_MARKDOWN, AgentBridgeWriteMode.MERGE_MARKDOWN_PRESERVING_PREAMBLE)) {
            check(s.formats == listOf(AgentBridgeFormat.MARKDOWN), unsupported)
        }
        check(!s.dailyNotes.only || s.dailyNotes.enabled)
        sorted(s.individualEntries.metricIds); sorted(s.dailyNotes.sectionIds)
        val custom = s.presentation.frontmatter.customFields
        check(custom.map { it.key }.distinct().size == custom.size)
        check(custom.none { it.key in setOf("schema", "schema_version", "units", "raw_capture_status", "time_context") })
    }

    private fun projectionOutput(value: AgentBridgeProjectionOutput) = dailyTemplates(value.subfolder, value.folderTemplate, value.filenameTemplate)

    private fun dailyTemplates(subfolder: String, folder: String, filename: String) {
        safePath(subfolder, templates = true, tokens = setOf("year", "month", "day", "date"))
        safePath(folder, templates = true, tokens = setOf("year", "month", "day", "date"))
        safePath(filename, filename = true, templates = true, tokens = setOf("year", "month", "day", "date"))
    }

    fun safePath(path: String, filename: Boolean = false, templates: Boolean = false,
        allowEmpty: Boolean = !filename, tokens: Set<String> = setOf("year", "month", "day", "date", "metric", "category", "record_id")) {
        val code = AgentBridgeErrorCode.UNSAFE_PATH
        check(path.toByteArray().size <= 4096 && path.none { it.code < 32 || it.code == 127 }, code)
        check(!path.startsWith("/") && !path.startsWith("~") && path.none { it in "\\:%\u0000" }, code)
        if (path.isEmpty()) { check(allowEmpty, code); return }
        check(!filename || '/' !in path, code)
        val components = path.split('/')
        check(components.size <= 16, code)
        for (component in components) {
            check(component.isNotEmpty() && component !in setOf(".", "..") && component == component.trim() && !component.endsWith('.') && component.toByteArray().size <= 255, code)
            check(component.none { it in "<>\"|?*" }, code)
            val found = Regex("\\{([^{}]*)}").findAll(component).map { it.groupValues[1] }.toList()
            check(found.isEmpty() || (templates && tokens.containsAll(found)), code)
            val stripped = Regex("\\{[^{}]*}").replace(component, "x")
            check('{' !in stripped && '}' !in stripped, code)
            check(!Regex("(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\\..*)?").matches(stripped), code)
        }
    }

    /** Lexical preflight only; output spelling and canonical JSON are never normalized or rewritten.
     * Successful collision validation is bounded to NFC-ASCII paths: the pinned dependency set has
     * no full Unicode case-fold API. Known Unicode aliases can be rejected, but unproven Unicode
     * paths fail closed until a reviewed native fold/filesystem gate exists. No filesystem is read. */
    fun collisions(paths: List<String>) {
        val keys = mutableSetOf<String>()
        var ascii = true
        for (path in paths) {
            safePath(path, allowEmpty = false)
            val normalized = Normalizer.normalize(path, Normalizer.Form.NFC)
            ascii = ascii && normalized.all { it.code < 128 }
            val key = normalized.uppercase(Locale.ROOT).lowercase(Locale.ROOT)
                .uppercase(Locale.ROOT).lowercase(Locale.ROOT)
            check(keys.add(key), AgentBridgeErrorCode.PATH_COLLISION)
        }
        check(ascii, unsupported)
    }

    fun resolveDates(value: AgentBridgeDates, timezone: String): AgentBridgeDates =
        AgentBridgeCodec.sanitized { resolveDatesChecked(value, timezone) }

    private fun resolveDatesChecked(value: AgentBridgeDates, timezone: String): AgentBridgeDates {
        zone(timezone)
        return when (value) {
            is AgentBridgeDatesAllAvailable -> value
            is AgentBridgeDatesExact -> { range(value.range); value }
            is AgentBridgeDatesPastCompleteDays -> {
                val anchor = date(value.anchorDate)
                val start = anchor.minusDays(value.days.toLong())
                check(start.year in 1..9999)
                AgentBridgeDatesExact(AgentBridgeRange(anchor.minusDays(1).toString(), start.toString()), "exact")
            }
        }
    }

    private fun civilDays(value: AgentBridgeRange): List<LocalDate> {
        range(value)
        val first = date(value.startDate)
        val last = date(value.endDate)
        val count = java.time.temporal.ChronoUnit.DAYS.between(first, last) + 1
        check(count <= 4096, AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        return (0 until count.toInt()).map { first.plusDays(it.toLong()) }
    }

    private fun expand(template: String, date: LocalDate): String = template
        .replace("{year}", "%04d".format(Locale.ROOT, date.year)).replace("{month}", "%02d".format(Locale.ROOT, date.monthValue))
        .replace("{day}", "%02d".format(Locale.ROOT, date.dayOfMonth)).replace("{date}", date.toString())
    private fun join(parent: String, name: String): String = if (parent.isEmpty()) name else "$parent/$name"
    private fun date(value: String): LocalDate = LocalDate.parse(value).also { check(it.year in 1..9999) }
    private fun range(value: AgentBridgeRange) { check(date(value.startDate) <= date(value.endDate)) }
    private fun zone(value: String) { check(value in ZoneId.getAvailableZoneIds()); ZoneId.of(value) }
    private fun utc(value: String): Instant = java.time.OffsetDateTime.parse(value).toInstant()
        .also { check(it.epochSecond in -62135596800L..253402300799L) }
    private fun lifetime(issued: String, expires: String, maximum: Long) {
        val seconds = Duration.between(utc(issued), utc(expires)).seconds
        check(seconds in 1..maximum, AgentBridgeErrorCode.PLAN_EXPIRED)
    }
    private fun selection(value: AgentBridgeSelection) {
        sorted(value.metricIds); sorted(value.categoryIds); sorted(value.sourceIds); sorted(value.providerIds)
    }
    private fun sorted(values: List<String>) { check(values == values.distinct().sortedWith(AgentBridgeCodec::compareCodePoints)) }
    private fun enumText(value: Enum<*>): String = value.javaClass.getField(value.name)
        .getAnnotation(kotlinx.serialization.SerialName::class.java)?.value ?: value.name.lowercase(Locale.ROOT)
    private fun sortedEnums(values: List<Enum<*>>) { sorted(values.map(::enumText)) }
    private fun leaves(value: JsonElement, prefix: String): Set<String> = if (value is JsonObject)
        value.flatMap { (key, child) -> leaves(child, "$prefix/$key") }.toSet() else setOf(prefix)
    private fun check(condition: Boolean, code: AgentBridgeErrorCode = invalid) = AgentBridgeChecks.require(condition, code)

    private fun manifest(value: AgentBridgeArtifactManifest) {
        binding(value.binding)
        collisions(value.artifacts.map { it.relativePath })
        check(value.artifacts.map { it.artifactId }.distinct().size == value.artifacts.size)
        check(value.branchStatuses.map { it.selectorId }.distinct().size == value.branchStatuses.size)
        if (value.captureStatus in listOf(AgentBridgeArtifactManifestCaptureStatus.COMPLETE, AgentBridgeArtifactManifestCaptureStatus.COMPLETE_EMPTY)) {
            check(value.branchStatuses.all { it.status == AgentBridgeArtifactManifestBranchStatusesItemStatus.SUCCESS })
        }
        if (value.captureStatus == AgentBridgeArtifactManifestCaptureStatus.COMPLETE_EMPTY) check(value.artifacts.isEmpty())
        check(value.artifacts.none { it.profile == AgentBridgeArtifactProfile.ANDROID_SOURCE_PROJECTION_V1 && value.binding.peer.platform != AgentBridgePlatform.ANDROID })
    }

    private fun delegation(value: AgentBridgeExportDelegation) {
        utc(value.expiresAt); sortedEnums(value.rights)
        val b = value.bounds
        sorted(b.calendarTimezones); b.calendarTimezones.forEach(::zone); sorted(b.metricIds)
        sortedEnums(b.compatibilityDetail); sortedEnums(b.formats); sortedEnums(b.nativeArchiveProducts)
        sortedEnums(b.outputProfiles); sortedEnums(b.products); sortedEnums(b.projectionDetails)
        sorted(b.projectionFieldIds); sortedEnums(b.projectionObjectIds); sortedEnums(b.writeModes)
        when (val destination = b.destinationPolicy) {
            is AgentBridgeExportDelegationBoundsDestinationPolicyAuthenticatedHostBindings -> check(value.issuer == AgentBridgeIssuer.NATIVE_SOURCE)
            is AgentBridgeExportDelegationBoundsDestinationPolicyRegisteredHostBindings -> {
                check(value.issuer == AgentBridgeIssuer.AUTHORIZED_HOST); sorted(destination.bindingIds)
            }
        }
        if (b.datePolicy is AgentBridgeExportDelegationBoundsDatePolicyBoundedExact) range(b.datePolicy.range)
    }

    private fun catalog(value: AgentBridgeQueryCatalog) {
        coverage(value.history)
        check(value.metrics.map { it.metricId }.distinct().size == value.metrics.size)
        for (metric in value.metrics) {
            sortedEnums(metric.statistics)
            if (metric.availability != AgentBridgeCatalogItemAvailability.UNAVAILABLE) check(metric.nativeRecordType != null)
            if (metric.nativeRecordType != null && value.sourceId == AgentBridgeQueryCatalogSourceId.HEALTH_CONNECT) check(metric.nativeRecordType.startsWith(hcTypes))
        }
        sorted(value.operations); check(value.operations.all { it in queryOperations })
    }

    private fun queryRequest(value: AgentBridgeQueryRequest) {
        resolveDates(value.dates, value.calendarTimezone); selection(value.selection)
        check(!value.selection.allMetrics && value.selection.categoryIds.isEmpty() && value.selection.metricIds.isNotEmpty(), AgentBridgeErrorCode.UNSUPPORTED_METRIC)
        check(value.selection.sourceIds == listOf(enumText(value.sourceId)) && value.selection.providerIds.isEmpty(), unsupported)
        if (value.includeEvidenceValues || value.operation is AgentBridgeQueryOperationSourceRecordListing) {
            check(value.detail == AgentBridgeQueryRequestDetail.NATIVE_EVIDENCE && value.includeEvidenceValues, approval)
        }
        if (value.operation is AgentBridgeQueryOperationSleepSessionListing || value.operation is AgentBridgeQueryOperationWorkoutSleepAlignment) check("sleep_total" in value.selection.metricIds, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
        if (value.operation is AgentBridgeQueryOperationWorkoutListing || value.operation is AgentBridgeQueryOperationWorkoutSleepAlignment) check("workouts" in value.selection.metricIds, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
        if (value.operation is AgentBridgeQueryOperationPeriodComparison) {
            val op = value.operation
            check(op.aggregations.map { it.metricId }.distinct().size == op.aggregations.size && value.selection.metricIds.containsAll(op.aggregations.map { it.metricId }), AgentBridgeErrorCode.UNSUPPORTED_METRIC)
            check(value.dates is AgentBridgeDatesExact)
            val outer = (value.dates as AgentBridgeDatesExact).range
            for (r in listOf(op.first, op.second)) {
                range(r)
                check(r.startDate >= outer.startDate && r.endDate <= outer.endDate)
            }
        }
        check(value.page.maxItems <= value.budgets.maxPageItems && value.page.maxBytes <= value.budgets.maxPageBytes, AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
    }

    /** Catalog/unit/budget comparison only. Does not verify a stored query grant or capture anything. */
    fun validateQueryCatalogBinding(request: AgentBridgeQueryRequest, catalog: AgentBridgeQueryCatalog) = AgentBridgeCodec.sanitized {
        queryRequest(request); catalog(catalog)
        check(request.catalogSha256 == AgentBridgeCodec.digest(AgentBridgeCodec.tree(catalog)) && request.peer == catalog.peer && request.sourceId == catalog.sourceId && request.providerId == catalog.providerId, changed)
        check(catalog.providerAvailability == AgentBridgeQueryCatalogProviderAvailability.AVAILABLE, unsupported)
        if (request.dates is AgentBridgeDatesAllAvailable) check(catalog.history.history.state in listOf(AgentBridgeCoverageHistoryState.FULL_GRANTED, AgentBridgeCoverageHistoryState.NOT_APPLICABLE), AgentBridgeErrorCode.HISTORY_UNVERIFIED)
        val rows = catalog.metrics.associateBy { it.metricId }
        for (id in request.selection.metricIds) {
            val row = rows[id] ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_METRIC)
            check(row.availability == AgentBridgeCatalogItemAvailability.SUPPORTED, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
            if (row.featureGate.isNotEmpty()) {
                val name = row.featureGate.removePrefix("FEATURE_").lowercase(Locale.ROOT)
                check(catalog.featureStatuses.any { it.feature == name && it.status == AgentBridgeQueryCatalogFeatureStatusesItemStatus.AVAILABLE }, unsupported)
            }
            check(!request.includeEvidenceValues || row.evidenceValueSupport, unsupported)
        }
        val operation = AgentBridgeCodec.tree(AgentBridgeQueryOperationSerializer, request.operation).jsonObject.text("type")
        check(operation in catalog.operations, unsupported)
        if (request.operation is AgentBridgeQueryOperationPeriodComparison) for (agg in request.operation.aggregations) {
            val row = rows.getValue(agg.metricId)
            check(agg.expectedUnit == row.unit && agg.kind in row.statistics, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
        }
        val requested = AgentBridgeCodec.tree(AgentBridgeBudgets.serializer(), request.budgets).jsonObject
        val allowed = AgentBridgeCodec.tree(AgentBridgeBudgets.serializer(), catalog.budgets).jsonObject
        check(requested.all { (k, v) -> v.jsonPrimitive.content.toLong() <= allowed.getValue(k).jsonPrimitive.content.toLong() }, AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
    }

    fun queryScopeDigest(request: AgentBridgeQueryRequest): String {
        val tree = AgentBridgeCodec.tree(request)
        val page = JsonObject(tree.getValue("page").jsonObject.filterKeys { it != "cursor" })
        return AgentBridgeCodec.digest(JsonObject(tree.filterKeys { it != "request_id" } + ("page" to page)))
    }

    /** Immutable supplied-document comparison, not cursor/snapshot/authority verification. */
    fun validateQueryResponseBinding(response: AgentBridgeQueryResponse, request: AgentBridgeQueryRequest,
        catalog: AgentBridgeQueryCatalog) = AgentBridgeCodec.sanitized {
        validate(response); validate(request); validate(catalog)
        validateQueryCatalogBinding(request, catalog)
        val value = AgentBridgeCodec.tree(response)
        val input = AgentBridgeCodec.tree(request)
        check(value.text("query_sha256") == queryScopeDigest(request), changed)
        check(listOf("peer", "source_id", "provider_id", "request_id", "calendar_timezone", "catalog_sha256").all { value[it] == input[it] }, changed)
        check(value.text("operation") == input.getValue("operation").jsonObject.text("type"), changed)
        if (response is AgentBridgeQueryResponseMetricCatalog) check(response.catalog == catalog, changed)
        check(value.getValue("items").jsonArray.size <= request.page.maxItems && AgentBridgeCodec.encode(response).size <= request.page.maxBytes,
            AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        val rows = catalog.metrics.associateBy { it.metricId }
        val expectedTypes = request.selection.metricIds.map { rows.getValue(it).nativeRecordType }.toSet()
        fun walk(element: JsonElement) {
            when (element) {
                is JsonArray -> element.forEach(::walk)
                is JsonObject -> {
                    if (element["type"] == JsonPrimitive("metric")) {
                        val row = rows[element.text("metric_id")] ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_METRIC)
                        check(element.text("unit") == row.unit && row.statistics.any { enumText(it) == element.text("statistic") }, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
                        check(element.text("metric_id") in request.selection.metricIds, changed)
                    }
                    if (element["type"] == JsonPrimitive("evidence")) check(request.includeEvidenceValues, approval)
                    element["identity"]?.jsonObject?.let { identity ->
                        val nativeType = identity.text(if (identity.text("identity_kind") == "derived_child") "parent_record_type" else "record_type")
                        check(nativeType in expectedTypes, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
                    }
                    element.values.forEach(::walk)
                }
                else -> Unit
            }
        }
        walk(value)
    }

    private fun coverage(value: AgentBridgeCoverage) {
        check(value.daysWithValues <= value.daysConsidered)
        check(value.missingCount >= value.missing.size && value.missingTruncated == (value.missingCount > value.missing.size))
        value.missing.forEach { range(it.range) }
        if (value.history.boundary != null) date(value.history.boundary)
        if (value.status in listOf(AgentBridgeCoverageStatus.COMPLETE, AgentBridgeCoverageStatus.COMPLETE_EMPTY)) {
            check(value.history.state != AgentBridgeCoverageHistoryState.UNVERIFIED && value.missing.all { it.reason == AgentBridgeCoverageMissingItemReason.NO_RECORDS })
        }
        if (value.status == AgentBridgeCoverageStatus.COMPLETE_EMPTY) check(value.daysWithValues == 0)
    }

    private fun queryResponse(value: AgentBridgeQueryResponse) {
        val tree = AgentBridgeCodec.tree(value)
        zone(tree.text("calendar_timezone")); utc(tree.text("expires_at"))
        val coverage = AgentBridgeCodec.json.decodeFromJsonElement(AgentBridgeCoverage.serializer(), tree.getValue("coverage"))
        coverage(coverage)
        val limits = listOf(Triple("limitation_count", "limitations", "limitations_truncated"), Triple("source_descriptor_count", "source_descriptors", "source_descriptors_truncated"))
        for ((count, items, truncated) in limits) {
            val total = tree.text(count).toInt(); val size = tree.getValue(items).jsonArray.size
            check(total >= size && tree.text(truncated).toBooleanStrict() == (total > size))
        }
        if (coverage.status == AgentBridgeCoverageStatus.COMPLETE_EMPTY) {
            check(tree.getValue("items").jsonArray.isEmpty() && tree["packet"]?.jsonObject?.get("facts")?.jsonArray?.isNotEmpty() != true)
        }
        val complete = coverage.status in listOf(AgentBridgeCoverageStatus.COMPLETE, AgentBridgeCoverageStatus.COMPLETE_EMPTY)
        sourceChecks(tree, tree.text("source_id"), tree.text("provider_id"), complete)
        if (value is AgentBridgeQueryResponseWorkoutListing) check(value.items.all { it.kind == AgentBridgeSessionItemKind.WORKOUT })
        if (value is AgentBridgeQueryResponseSleepSessionListing) check(value.items.all { it.kind == AgentBridgeSessionItemKind.SLEEP })
        if (value is AgentBridgeQueryResponseMetricCatalog) catalog(value.catalog)
    }

    private fun projectionRequest(value: AgentBridgeProjectionRequest) {
        resolveDates(value.dates, value.calendarTimezone); selection(value.selection)
        check(value.peer.platform == AgentBridgePlatform.ANDROID && value.sourceId == AgentBridgeProjectionRequestSourceId.HEALTH_CONNECT && value.providerId == "health_connect", unsupported)
        check(value.projectionCatalogSha256 == reviewedProjectionCatalogDigest, changed)
        sorted(value.fieldIds); sortedEnums(value.objectIds)
        check(!value.selection.allMetrics && value.selection.categoryIds.isEmpty(), AgentBridgeErrorCode.UNSUPPORTED_METRIC)
        check(value.selection.sourceIds == listOf("health_connect") && value.selection.providerIds.isEmpty(), unsupported)
        if (value.detail == AgentBridgeProjectionRequestDetail.SUMMARY) check(value.objectIds.none { it in listOf(AgentBridgeProjectionRequestObjectIdsItem.SELECTED_SERIES, AgentBridgeProjectionRequestObjectIdsItem.NATIVE_RECORDS) }, approval)
        if (AgentBridgeProjectionRequestObjectIdsItem.NATIVE_RECORDS in value.objectIds) check(value.detail == AgentBridgeProjectionRequestDetail.NATIVE_RECORDS, approval)
        val selected = value.fieldIds.map { projectionFields[it] ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_METRIC) }
        check(selected.all { f -> value.objectIds.any { enumText(it) == f.objectId } }, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
        check(selected.map { it.metric }.distinct().sorted() == value.selection.metricIds, changed)
        check(value.objectIds.all { enumText(it) == "capture_manifest" || selected.any { f -> enumText(it) == f.objectId } }, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
    }

    private fun projectionCatalog(value: AgentBridgeProjectionCatalog) {
        check(value.fields.size == projectionFields.size)
        check(value.fields.map { it.fieldId }.distinct().size == value.fields.size)
        check(value.fields.all { row ->
            val f = projectionFields[row.fieldId]
            f != null && enumText(row.objectId) == f.objectId && row.selectionMetricId == f.metric && row.unit == f.unit &&
                row.nativeRecordType == hcTypes + f.recordType && row.nativeValueKey == f.valueKey &&
                enumText(row.valueRole) == f.role && row.parentRecordType == f.parent?.let { hcTypes + it }
        })
        sorted(value.fields.map { it.fieldId })
    }

    // Exact compiled catalog pin is metadata only, never an installed support advertisement.
    private const val reviewedProjectionCatalogDigest = "a4571a3c578767ac9d72d5cf65938b94fd05cb1de8ae76908b857eae1f009ec9"

    private fun projection(value: AgentBridgeProjection) {
        zone(value.calendarTimezone); date(value.ownerDate); coverage(value.coverage)
        check(value.peer.platform == AgentBridgePlatform.ANDROID && value.sourceId == AgentBridgeProjectionRequestSourceId.HEALTH_CONNECT && value.providerId == "health_connect", unsupported)
        check(value.projectionCatalogSha256 == reviewedProjectionCatalogDigest, changed)
        if (value.detail == AgentBridgeProjectionRequestDetail.SUMMARY) check(value.selectedSeries.isEmpty() && value.nativeRecords.isEmpty(), approval)
        if (value.detail == AgentBridgeProjectionRequestDetail.SELECTED_TIME_SERIES) check(value.nativeRecords.isEmpty(), approval)
        val complete = value.coverage.status in listOf(AgentBridgeCoverageStatus.COMPLETE, AgentBridgeCoverageStatus.COMPLETE_EMPTY)
        sourceChecks(AgentBridgeCodec.tree(value), "health_connect", value.providerId, complete)
        check(value.selectedSeries.map { it.observationId }.distinct().size == value.selectedSeries.size)
        for (item in value.selectedSeries) {
            val f = projectionFields[item.fieldId] ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_METRIC)
            check(f.objectId == "selected_series" && item.selectionMetricId == f.metric && item.unit == f.unit && item.nativeValueKey == f.valueKey && enumText(item.observationKind) == f.role, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
            check(item.ownerDate == value.ownerDate, changed)
            val identity = AgentBridgeCodec.tree(AgentBridgeNativeIdentitySerializer, item.identity).jsonObject
            check(identity.text("record_type") == hcTypes + f.recordType && identity["parent_record_type"]?.jsonPrimitive?.content == f.parent?.let { hcTypes + it }, AgentBridgeErrorCode.UNSUPPORTED_METRIC)
            if (item.observationKind == AgentBridgeSourceObservationObservationKind.POINT) check(item.end == null)
            else check(item.end != null && exactNanoseconds(item.end) >= exactNanoseconds(item.start))
            val tree = AgentBridgeCodec.tree(AgentBridgeSourceObservation.serializer(), item).jsonObject
            check(item.observationId == AgentBridgeCodec.digest(JsonObject(tree.filterKeys { it != "observation_id" })), changed)
        }
    }

    private fun sourceChecks(value: JsonElement, source: String, provider: String, complete: Boolean) {
        when (value) {
            is JsonArray -> value.forEach { sourceChecks(it, source, provider, complete) }
            is JsonObject -> {
                if ("epoch_second" in value) {
                    val expected = when (source) { "apple_health" -> "source_binary64_seconds"; "health_connect" -> "source_nanoseconds"; else -> null }
                    if (expected != null) check(value.text("precision") == expected)
                }
                val identity = value["identity"]?.jsonObject
                if (identity != null) {
                    check(identity.text("source_id") == source && identity.text("provider_id") == provider, changed)
                    if (complete) check(identity.getValue("metadata_status").jsonObject.values.none { it.jsonPrimitive.content == "not_captured" })
                }
                value.values.forEach { sourceChecks(it, source, provider, complete) }
            }
            else -> Unit
        }
    }

    private fun nestedChecks(value: JsonElement) {
        when (value) {
            is JsonArray -> value.forEach(::nestedChecks)
            is JsonObject -> {
                if ("epoch_second" in value) exactTime(AgentBridgeCodec.json.decodeFromJsonElement(AgentBridgeExactTime.serializer(), value))
                if ("identity_kind" in value) identity(value)
                if (value["type"] == JsonPrimitive("metric")) {
                    check((value.text("availability") == "available") == ("value" in value))
                    date(value.text("owner_date"))
                }
                if (value["type"] == JsonPrimitive("session")) {
                    val start = timeNanos(value.getValue("start")); val end = timeNanos(value.getValue("end"))
                    check(end >= start && end - start == BigInteger(value.text("duration_nanoseconds")))
                    for (stage in value.getValue("stages").jsonArray) {
                        val s = stage.jsonObject
                        check(timeNanos(s.getValue("start")) >= start && timeNanos(s.getValue("end")) <= end && timeNanos(s.getValue("end")) >= timeNanos(s.getValue("start")))
                    }
                }
                if (value["type"] == JsonPrimitive("comparison")) {
                    val first = value.getValue("first").jsonObject; val second = value.getValue("second").jsonObject
                    for (child in listOf(first, second)) check(listOf("metric_id", "unit", "statistic").all { child[it] == value[it] })
                    val available = listOf(first, second).all { it.text("availability") == "available" }
                    check(available == ("delta" in value))
                    if (available && listOf(first, second).all { it.getValue("value").jsonObject.text("type") == "integer" }) {
                        val delta = BigInteger(second.getValue("value").jsonObject.text("value")) - BigInteger(first.getValue("value").jsonObject.text("value"))
                        check(value.getValue("delta").jsonObject.text("type") == "integer" &&
                            BigInteger(value.getValue("delta").jsonObject.text("value")) == delta)
                    }
                }
                if (value["type"] == JsonPrimitive("alignment") && "sleep" in value) {
                    val sleep = value.getValue("sleep").jsonObject; val workout = value.getValue("workout").jsonObject
                    check(sleep.text("kind") == "sleep" && workout.text("kind") == "workout")
                    val gap = timeNanos(sleep.getValue("start")) - timeNanos(workout.getValue("end"))
                    check(gap.signum() >= 0 && gap == BigInteger(value.text("gap_nanoseconds")))
                }
                value.values.forEach(::nestedChecks)
            }
            else -> Unit
        }
    }

    private fun identity(value: JsonObject) {
        val statuses = value.getValue("metadata_status").jsonObject
        check(statuses.all { (key, state) -> (state.jsonPrimitive.content == "available") == (key in value) })
        val child = value.text("identity_kind") == "derived_child"
        if (child) {
            check("parent_record_id" in value && "parent_record_type" in value)
            check(statuses.values.all { it == JsonPrimitive("not_exposed_by_source") })
        } else check("parent_record_id" !in value && "parent_record_type" !in value)
        if (value.text("source_id") == "apple_health" && value.text("identity_kind") == "native") {
            check(Regex("[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}").matches(value.text("record_id")))
        }
        if (value.text("source_id") == "health_connect" && value.text("identity_kind") == "native") {
            check(listOf("last_modified", "client_record_version").none { statuses[it] == JsonPrimitive("not_exposed_by_source") })
            if ("last_modified" in value) check(value.getValue("last_modified").jsonObject.text("precision") == "source_nanoseconds")
        }
    }

    fun exactNanoseconds(value: AgentBridgeExactTime): BigInteger = BigInteger.valueOf(value.epochSecond) * billion + BigInteger.valueOf(value.nanosecond.toLong())
    private fun timeNanos(value: JsonElement): BigInteger = exactNanoseconds(AgentBridgeCodec.json.decodeFromJsonElement(AgentBridgeExactTime.serializer(), value))

    /** Exact rational binary64 decoding with nearest/ties-even rounding; no floating round trip. */
    fun fromBinary64Bits(bits: String, sourceOffsetSeconds: Int? = null): AgentBridgeExactTime =
        AgentBridgeCodec.sanitized { binary64Time(bits, sourceOffsetSeconds) }

    private fun binary64Time(bits: String, sourceOffsetSeconds: Int?): AgentBridgeExactTime {
        AgentBridgeChecks.text(bits, 16, 16, "^[0-9a-f]{16}$")
        val raw = BigInteger(bits, 16)
        val exponent = raw.shiftRight(52).and(BigInteger.valueOf(2047)).toInt()
        check(exponent != 2047)
        val fraction = raw.and(BigInteger.ONE.shiftLeft(52) - BigInteger.ONE)
        val significand = if (exponent == 0) fraction else fraction + BigInteger.ONE.shiftLeft(52)
        val power = if (exponent == 0) -1074 else exponent - 1023 - 52
        var total = significand * billion
        if (power >= 0) total = total.shiftLeft(power) else {
            val denominator = BigInteger.ONE.shiftLeft(-power)
            val parts = total.divideAndRemainder(denominator)
            val cmp = (parts[1] * BigInteger.TWO).compareTo(denominator)
            total = parts[0] + if (cmp > 0 || (cmp == 0 && parts[0].testBit(0))) BigInteger.ONE else BigInteger.ZERO
        }
        if (raw.testBit(63)) total = -total
        val split = total.divideAndRemainder(billion)
        if (split[1].signum() < 0) { split[0] -= BigInteger.ONE; split[1] += billion }
        return AgentBridgeExactTime(split[0].longValueExact(), split[1].intValueExact(),
            AgentBridgeExactTimePrecision.SOURCE_BINARY64_SECONDS, sourceOffsetSeconds, bits)
    }

    fun exactTime(value: AgentBridgeExactTime) {
        when (value.precision) {
            AgentBridgeExactTimePrecision.SOURCE_BINARY64_SECONDS -> check(value == fromBinary64Bits(value.sourceBinary64Bits!!, value.sourceOffsetSeconds))
            AgentBridgeExactTimePrecision.SOURCE_MILLISECONDS -> check(value.nanosecond % 1000000 == 0)
            AgentBridgeExactTimePrecision.SOURCE_SECONDS -> check(value.nanosecond == 0)
            AgentBridgeExactTimePrecision.SOURCE_NANOSECONDS -> Unit
        }
    }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content
}
