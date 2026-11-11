package com.healthmd.presentation.archive

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportTarget
import java.net.URI

/** One live problem the Archive's Needs attention sheet lists with its fix (iOS `AttentionScreen.Item`). */
sealed interface ArchiveAttentionItem {
    val id: String

    /** Health Connect has granted nothing, so exports read no data. */
    data object HealthPermission : ArchiveAttentionItem {
        override val id: String = "health"
    }

    /** The chosen export folder lost its grant or moved; [waiting] are the automations that write there. */
    data class FolderUnavailable(val folderName: String?, val waiting: List<String>) : ArchiveAttentionItem {
        override val id: String = "folder"
    }

    /** The latest runs to an endpoint or gateway all failed. */
    data class EndpointFailing(
        val target: ExportTarget,
        /** The destination host; null falls back to the destination's name. */
        val host: String?,
        val failures: Int,
        /** The HTTP status every failure in the streak reported, if they agree. */
        val httpStatus: Int?,
        val reason: ExportFailureReason?,
        val profileId: String?,
        val profileName: String?,
        val retry: Retry?,
    ) : ArchiveAttentionItem {
        override val id: String = "endpoint.${target.name}"
    }

    enum class Retry { NEXT_REFRESH, NEXT_SCHEDULED_RUN }
}

/** What the attention items are derived from. */
data class ArchiveAttentionInputs(
    val entries: List<ExportHistoryEntry>,
    val sources: ArchiveLaneSources,
    /** Null until Health Connect has been checked: no item yet. */
    val healthConnected: Boolean?,
    /** Whether the app still holds a grant on [ArchiveLaneSources.appFolderUri]. */
    val appFolderAccessible: Boolean,
    val appFolderName: String?,
)

/**
 * The facts behind Needs attention, kept pure for tests. Mirrors the iOS shell's
 * `attentionItems`: the health permission, an unavailable folder and failing endpoints.
 * Apple-only items (Medications permission, an offline Mac) have no Android counterpart.
 */
object ArchiveAttention {
    fun items(inputs: ArchiveAttentionInputs): List<ArchiveAttentionItem> = buildList {
        if (inputs.healthConnected == false) add(ArchiveAttentionItem.HealthPermission)
        val sources = inputs.sources
        val folder = sources.appFolderUri
        if (!folder.isNullOrBlank() && !inputs.appFolderAccessible) {
            val waiting = sources.profiles
                .filter { it.target == ExportTarget.DEVICE_FOLDER && (it.folderUri.isNullOrBlank() || it.folderUri == folder) }
                .map { it.name }
            add(ArchiveAttentionItem.FolderUnavailable(inputs.appFolderName, waiting))
        }
        listOf(ExportTarget.API_ENDPOINT, ExportTarget.AGENT_DATA_GATEWAY).forEach { target ->
            endpointItem(target, inputs)?.let(::add)
        }
    }

    /** `HTTP 503` in a stored, status-only error description. */
    fun httpStatus(text: String?): Int? =
        text?.let { HTTP_STATUS.find(it) }?.groupValues?.get(1)?.toIntOrNull()

    /** Failed runs in a row, newest first, before the first run that wrote anything. */
    fun consecutiveFailures(runsNewestFirst: List<ExportHistoryEntry>): Int =
        runsNewestFirst.takeWhile(::isFailedRun).size

    /** The status repeated across the failure streak, if every failure reported the same one. */
    fun repeatedStatus(descriptions: List<String?>): Int? {
        val codes = descriptions.map(::httpStatus)
        val first = codes.firstOrNull() ?: return null
        return first.takeIf { codes.all { it == first } }
    }

    /** A run that wrote nothing: every date failed, or it stopped before covering any. */
    fun isFailedRun(entry: ExportHistoryEntry): Boolean =
        entry.isFailure || (entry.successCount == 0 && entry.failureReason != null)

    fun host(url: String?): String? = url?.trim()?.takeIf { it.isNotEmpty() }
        ?.let { runCatching { URI(it).host }.getOrNull() }
        ?.takeIf { it.isNotBlank() }

    private fun endpointItem(target: ExportTarget, inputs: ArchiveAttentionInputs): ArchiveAttentionItem.EndpointFailing? {
        val runs = inputs.entries.filter { it.target == target }.sortedByDescending { it.timestamp }
        val failures = consecutiveFailures(runs)
        val latest = runs.firstOrNull()
        if (failures == 0 || latest == null) return null
        val sources = inputs.sources
        val candidates = sources.profiles.filter { it.target == target }
        val profile = candidates.firstOrNull { it.name == latest.profileName } ?: candidates.singleOrNull()
        val url = when (target) {
            ExportTarget.AGENT_DATA_GATEWAY -> profile?.agentDataGatewayUrl ?: sources.settings?.agentDataGatewayUrl
            else -> profile?.apiEndpointUrl ?: sources.settings?.apiEndpointUrl
        }
        val statuses = runs.take(failures).map { run ->
            run.failedDateDetails.mapNotNull { it.errorDetails }.firstOrNull { httpStatus(it) != null }
        }
        val schedule = profile?.let { found -> sources.schedules.firstOrNull { it.profileId == found.id } }
        return ArchiveAttentionItem.EndpointFailing(
            target = target,
            host = host(url),
            failures = failures,
            httpStatus = repeatedStatus(statuses),
            reason = latest.failureReason ?: latest.failedDateDetails.firstOrNull()?.reason,
            profileId = profile?.id,
            profileName = profile?.name,
            retry = schedule?.takeIf { it.isEnabled }?.let {
                if (it.todayRefreshEnabled) ArchiveAttentionItem.Retry.NEXT_REFRESH else ArchiveAttentionItem.Retry.NEXT_SCHEDULED_RUN
            },
        )
    }

    private val HTTP_STATUS = Regex("""HTTP (\d{3})""")
}
