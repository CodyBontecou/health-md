package com.healthmd.direct

import com.healthmd.direct.protocol.*
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

/** Native review description only. Does not enroll, read health data, or change settings. */
internal object AgentBridgeExportNativeGrantDraft {
    val metricIds = listOf("android.hrv_rmssd", "heart_rate_avg", "heart_rate_max", "heart_rate_min", "resting_heart_rate", "steps")

    fun make(peer: AgentBridgePeer, metrics: Set<String>, start: LocalDate, end: LocalDate,
        timezone: String, expiresAt: Instant, now: Instant, id: String = UUID.randomUUID().toString()): AgentBridgeExportDelegation {
        if (peer.platform != AgentBridgePlatform.ANDROID || metrics.isEmpty() || !metricIds.containsAll(metrics) ||
            !expiresAt.isAfter(now) || start.isAfter(end)) throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
        ZoneId.of(timezone)
        val days = ChronoUnit.DAYS.between(start, end) + 1
        if (days !in 1L..366000L) throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
        val canonicalExpiry = expiresAt.truncatedTo(ChronoUnit.SECONDS)
        if (!canonicalExpiry.isAfter(now)) throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
        val value = AgentBridgeExportDelegation(id, AgentBridgeExportDelegationBounds(
            listOf(timezone), listOf(AgentBridgeCompatibilityDetail.SUMMARY),
            AgentBridgeExportDelegationBoundsDatePolicyBoundedExact(days.toInt(), AgentBridgeRange(end.toString(), start.toString()), "bounded_exact"),
            AgentBridgeExportDelegationBoundsDestinationPolicyAuthenticatedHostBindings("authenticated_host_bindings"),
            listOf(AgentBridgeFormat.JSON), metrics.sorted(), listOf(AgentBridgeOutputSupportNativeArchiveProductsItem.NONE),
            listOf(AgentBridgeOutputProfile.ANDROID_FROZEN_V4), listOf(AgentBridgeExportDelegationBoundsProductsItem.GENERATED_FILES),
            emptyList(), emptyList(), emptyList(), listOf(AgentBridgeWriteMode.OVERWRITE)),
            canonicalExpiry.toString(), 1, AgentBridgeIssuer.NATIVE_SOURCE, peer,
            listOf(AgentBridgeExportDelegationRightsItem.DISCOVER, AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE, AgentBridgeExportDelegationRightsItem.PLAN),
            "healthmd.agent_export_delegation", 1)
        return AgentBridgeCodec.decode(AgentBridgeCodec.encode(value)) as AgentBridgeExportDelegation
    }
}
