package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.time.Instant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Test

/** Pure intrinsic checks ONLY. Real issuer lookup/MAC/native authorization are app-service tests. */
class AgentBridgeExportDelegationTest {
    private val now = Instant.parse("2000-01-03T00:00:00Z")

    @Test
    fun nativeDerivationKeepsParentIdentityAndCannotGrantControlsOrQueries() {
        val parent = parent()
        val derived = derive(parent, plan(parent))
        assertThat(derived.authorityId).isEqualTo(parent.authorityId)
        assertThat(derived.grantRevision).isEqualTo(1)
        assertThat(derived.issuer).isEqualTo(AgentBridgeIssuer.NATIVE_SOURCE)
        assertThat(derived.destinationBindingIds).containsExactly(AgentBridgeSynthetic.destination.bindingId)
        assertThat(derived.rights).containsExactly(AgentBridgeAuthorityRightsItem.DISCOVER, AgentBridgeAuthorityRightsItem.EXPORT_EXECUTE, AgentBridgeAuthorityRightsItem.PLAN)
        assertThat(derived.controlReadScope).isNull()
        assertThat(derived.configurationProtection).isEqualTo(AgentBridgeAuthorityConfigurationProtection.NOT_APPLICABLE)
        assertThat(AgentBridgeCodec.decode(AgentBridgeCodec.encode(derived))).isEqualTo(derived)
    }

    @Test
    fun wrongPeerIssuerRevisionAndGrantDigestRejectEvenForValidPlanBytes() {
        val parent = parent()
        val original = plan(parent)
        val refs = original.authorityReferences
        val variants = listOf(
            refs.copy(native = refs.native.copy(grantSha256 = "e".repeat(64))),
            refs.copy(native = refs.native.copy(grantRevision = 2)),
            refs.copy(native = refs.native.copy(authorityId = AgentBridgeSynthetic.id(99))),
            refs.copy(native = refs.native.copy(issuer = AgentBridgeIssuer.AUTHORIZED_HOST)),
        )
        for (reference in variants) expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(parent, seal(original.copy(authorityReferences = reference))) }
        val otherPeer = parent.copy(peer = parent.peer.copy(hostInstallationId = AgentBridgeSynthetic.id(90)))
        expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(otherPeer, plan(otherPeer)) }
    }

    @Test
    fun everyBoundedCaptureOutputProductAndCalendarAxisIsEnforced() {
        val bounds = parent().bounds
        val variants = listOf(
            bounds.copy(metricIds = listOf("heart_rate_avg")),
            bounds.copy(calendarTimezones = listOf("Etc/GMT")),
            bounds.copy(compatibilityDetail = listOf(AgentBridgeCompatibilityDetail.SELECTED_TIME_SERIES)),
            bounds.copy(nativeArchiveProducts = listOf(AgentBridgeOutputSupportNativeArchiveProductsItem.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1)),
            bounds.copy(formats = listOf(AgentBridgeFormat.CSV)),
            bounds.copy(outputProfiles = listOf(AgentBridgeOutputProfile.ANDROID_FROZEN_V4)),
            bounds.copy(writeModes = listOf(AgentBridgeWriteMode.APPEND)),
            bounds.copy(products = listOf(AgentBridgeExportDelegationBoundsProductsItem.ANDROID_SOURCE_PROJECTION_V1),
                projectionDetails = listOf(AgentBridgeProjectionRequestDetail.SUMMARY), projectionFieldIds = listOf("steps"),
                projectionObjectIds = listOf(AgentBridgeProjectionRequestObjectIdsItem.DAILY_SUMMARY)),
        )
        for (variant in variants) {
            val narrowed = parent().copy(bounds = variant)
            expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(narrowed, plan(narrowed)) }
        }
    }

    @Test
    fun exactDatesEnforceInclusiveLimitsAndMaxDaysWithoutClipping() {
        val policy = AgentBridgeExportDelegationBoundsDatePolicyBoundedExact(2, AgentBridgeSynthetic.dates.range, "bounded_exact")
        val bounded = parent().copy(bounds = parent().bounds.copy(datePolicy = policy))
        derive(bounded, plan(bounded))
        val oneDay = bounded.copy(bounds = bounded.bounds.copy(datePolicy = policy.copy(maxDays = 1)))
        expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(oneDay, plan(oneDay)) }
        val outside = bounded.copy(bounds = bounded.bounds.copy(datePolicy = policy.copy(range = AgentBridgeRange("1999-12-31", "1999-12-30"))))
        expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(outside, plan(outside)) }
    }

    @Test
    fun logicalHistoryRequiresExplicitHistoryPermissionButNeverInventsEarliestDates() {
        val history = parent().copy(bounds = parent().bounds.copy(datePolicy = AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory(true, 1, "authorized_history")))
        val logical = logicalPlan(history)
        assertThat(derive(history, logical).scopeSha256).isEqualTo(logical.scopeSha256)
        assertThat(logical.predictedPaths).isEmpty()
        assertThat(logical.resolvedDates).isEqualTo(AgentBridgeDatesAllAvailable("all_available"))
        val disallowed = history.copy(bounds = history.bounds.copy(datePolicy = AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory(false, 1, "authorized_history")))
        expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(disallowed, logicalPlan(disallowed)) }
        expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(parent(), logicalPlan(parent())) }
    }

    @Test
    fun hostDerivationChecksOnlyItsOwnPreviouslyRegisteredBindingIds() {
        val host = parent().copy(authorityId = AgentBridgeSynthetic.host.authorityId, issuer = AgentBridgeIssuer.AUTHORIZED_HOST,
            bounds = parent().bounds.copy(destinationPolicy = AgentBridgeExportDelegationBoundsDestinationPolicyRegisteredHostBindings(listOf(AgentBridgeSynthetic.destination.bindingId), "registered_host_bindings")))
        val authority = derive(host, plan(host))
        assertThat(authority.issuer).isEqualTo(AgentBridgeIssuer.AUTHORIZED_HOST)
        val wrong = host.copy(bounds = host.bounds.copy(destinationPolicy = AgentBridgeExportDelegationBoundsDestinationPolicyRegisteredHostBindings(listOf(AgentBridgeSynthetic.id(91)), "registered_host_bindings")))
        expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(wrong, plan(wrong)) }
    }

    @Test
    fun absentPlanRightAndExpiredParentsCannotDeriveAuthorityAndExpiryIsClamped() {
        val without = parent().copy(rights = listOf(AgentBridgeExportDelegationRightsItem.DISCOVER))
        expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { derive(without, plan(without)) }
        val expired = parent().copy(expiresAt = "2000-01-03T00:00:00Z")
        expect(AgentBridgeErrorCode.PLAN_EXPIRED) { derive(expired, plan(expired)) }
        val short = parent().copy(expiresAt = "2000-01-03T00:02:00Z")
        assertThat(derive(short, plan(short)).expiresAt).isEqualTo("2000-01-03T00:02:00Z")
    }

    private fun parent() = AgentBridgeExportDelegation(AgentBridgeSynthetic.native.authorityId,
        AgentBridgeExportDelegationBounds(listOf("Etc/UTC"), listOf(AgentBridgeCompatibilityDetail.SUMMARY),
            AgentBridgeExportDelegationBoundsDatePolicyBoundedExact(2, AgentBridgeSynthetic.dates.range, "bounded_exact"),
            AgentBridgeExportDelegationBoundsDestinationPolicyAuthenticatedHostBindings("authenticated_host_bindings"), listOf(AgentBridgeFormat.JSON), listOf("steps"),
            listOf(AgentBridgeOutputSupportNativeArchiveProductsItem.NONE), listOf(AgentBridgeOutputProfile.ANDROID_ANALYTICAL_V5),
            listOf(AgentBridgeExportDelegationBoundsProductsItem.GENERATED_FILES), emptyList(), emptyList(), emptyList(), listOf(AgentBridgeWriteMode.OVERWRITE)),
        "2000-01-03T01:00:00Z", 1, AgentBridgeIssuer.NATIVE_SOURCE, AgentBridgeSynthetic.peer,
        listOf(AgentBridgeExportDelegationRightsItem.DISCOVER, AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE, AgentBridgeExportDelegationRightsItem.PLAN),
        "healthmd.agent_export_delegation", 1)
    private fun plan(parent: AgentBridgeExportDelegation): AgentBridgeGeneratedPlan {
        val ref = AgentBridgeAuthorityReference(parent.authorityId, parent.grantRevision, AgentBridgeCodec.fingerprint(parent), parent.issuer)
        val refs = if (parent.issuer == AgentBridgeIssuer.NATIVE_SOURCE) AgentBridgeSynthetic.refs.copy(native = ref) else AgentBridgeSynthetic.refs.copy(host = ref)
        return seal(AgentBridgeSynthetic.plan.copy(authorityReferences = refs))
    }
    private fun logicalPlan(parent: AgentBridgeExportDelegation): AgentBridgeGeneratedPlan {
        val plan = plan(parent)
        val dates = AgentBridgeDatesAllAvailable("all_available")
        val intent = plan.intent.copy(dates = dates)
        val scope = JsonObject(mapOf("dates" to AgentBridgeCodec.tree(AgentBridgeDatesSerializer, dates), "calendar_timezone" to JsonPrimitive(intent.calendarTimezone),
            "capture_scope" to AgentBridgeCodec.tree(AgentBridgeCapture.serializer(), intent.captureScope),
            "metric_ids" to JsonArray(plan.resolvedMetricIds.map(::JsonPrimitive)), "product" to AgentBridgeCodec.tree(AgentBridgeGeneratedIntentProduct.serializer(), intent.product)))
        return seal(plan.copy(intent = intent, resolvedDates = dates, predictedPaths = emptyList(), scopeSha256 = AgentBridgeCodec.digest(scope),
            limitations = listOf("history_bounds_unresolved"), pathPrediction = AgentBridgeGeneratedPlanPathPrediction.TEMPLATE_ONLY_ALL_AVAILABLE))
    }
    private fun seal(plan: AgentBridgeGeneratedPlan) = plan.copy(planSha256 = AgentBridgeValidation.planDigest(plan))
    private fun derive(parent: AgentBridgeExportDelegation, plan: AgentBridgeGeneratedPlan) = AgentBridgeValidation.deriveExportAuthority(parent, plan, now,
        AgentBridgeDiscoveryEntitlement.SATISFIED, AgentBridgeDiscoveryEntitlement.SATISFIED)
    private fun expect(code: AgentBridgeErrorCode, block: () -> Any?) {
        try { block(); throw AssertionError("Expected fixed failure") } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(code); assertThat(e.cause).isNull() }
    }
}
