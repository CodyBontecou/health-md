package com.healthmd.data.health

import com.healthmd.BuildConfig
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthTokenStore
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import kotlinx.coroutines.flow.first
import java.time.Instant
import java.time.ZoneId
import javax.inject.Inject

class HealthProviderDiagnosticsReporter @Inject constructor(
    private val settingsRepository: SettingsRepository,
    private val providerCatalog: HealthProviderCatalog,
    private val providerRegistry: HealthProviderRegistry,
    private val oauthConfigRegistry: OAuthConfigRegistry,
    private val oauthTokenStore: OAuthTokenStore,
    private val exportHistoryRepository: ExportHistoryRepository,
) {
    suspend fun buildReport(): RedactedHealthProviderDiagnosticsReport {
        val selectedProviderId = settingsRepository.getSelectedHealthProviderId()
        val connectedProviderIds = settingsRepository.getConnectedHealthProviderIds()
        val exportFolderConfigured = settingsRepository.getExportFolderUri()?.isNotBlank() == true
        val providerStates = providerCatalog.providerStates()
        val providerDiagnostics = providerStates.map { providerState ->
            val providerId = providerState.definition.id.wireId
            val provider = providerRegistry.providerFor(providerId)
            val oauthConfigured = oauthConfigRegistry.isConfigured(providerId)
            val tokenPresent = if (oauthConfigRegistry.get(providerId) != null) {
                safeBoolean { oauthTokenStore.getToken(providerId) != null }
            } else {
                DiagnosticValue.NotApplicable
            }

            RedactedHealthProviderDiagnostics(
                id = providerId,
                displayName = providerState.definition.displayName,
                integrationKind = providerState.definition.integrationKind.label,
                directExportStatus = providerState.definition.directExportStatus.label,
                installed = providerState.isInstalled,
                installedPackageName = providerState.installedPackageName,
                selected = selectedProviderId == providerId,
                connected = providerId in connectedProviderIds,
                oauthConfigured = if (oauthConfigRegistry.get(providerId) != null) {
                    DiagnosticValue.fromBoolean(oauthConfigured)
                } else {
                    DiagnosticValue.NotApplicable
                },
                oauthTokenPresent = tokenPresent,
                available = safeBoolean { provider.isAvailable() },
                permissions = if (oauthConfigRegistry.get(providerId) != null) {
                    tokenPresent
                } else {
                    safeBoolean { provider.hasPermissions() }
                },
                historicalReadPermission = if (providerId == "health_connect") {
                    safeBoolean { provider.hasHistoricalReadPermission() }
                } else {
                    DiagnosticValue.NotApplicable
                },
                backgroundReadPermission = if (providerId == "health_connect") {
                    safeBoolean { provider.hasBackgroundReadPermission() }
                } else {
                    DiagnosticValue.NotApplicable
                },
            )
        }

        return RedactedHealthProviderDiagnosticsReport(
            generatedAt = Instant.now(),
            appVersionName = BuildConfig.VERSION_NAME,
            appVersionCode = BuildConfig.VERSION_CODE,
            buildType = BuildConfig.BUILD_TYPE,
            exportFolderConfigured = exportFolderConfigured,
            selectedProviderId = selectedProviderId,
            connectedProviderIds = connectedProviderIds.sorted(),
            providers = providerDiagnostics,
            lastExport = exportHistoryRepository.getAllEntries().first().firstOrNull()?.toRedactedDiagnostics(),
        )
    }

    private suspend fun safeBoolean(block: suspend () -> Boolean): DiagnosticValue =
        runCatching { DiagnosticValue.fromBoolean(block()) }
            .getOrElse { DiagnosticValue.Error(it::class.java.simpleName ?: "UnknownError") }

    private fun ExportHistoryEntry.toRedactedDiagnostics(): RedactedExportDiagnostics {
        val failedGroups = failedDateDetails
            .groupBy { it.reason }
            .map { (reason, details) ->
                RedactedExportFailureGroup(
                    reason = reason,
                    count = details.size,
                    sampleDates = details.map { it.date.toString() }.sorted().take(5),
                )
            }
            .sortedWith(compareByDescending<RedactedExportFailureGroup> { it.count }.thenBy { it.reason.name })

        return RedactedExportDiagnostics(
            timestampEpochMillis = timestamp,
            source = source.name,
            dateRange = "${dateRangeStart}..${dateRangeEnd}",
            successCount = successCount,
            totalCount = totalCount,
            failureReason = failureReason,
            failedGroups = failedGroups,
            warningSummary = warningSummary,
        )
    }
}

data class RedactedHealthProviderDiagnosticsReport(
    val generatedAt: Instant,
    val appVersionName: String,
    val appVersionCode: Int,
    val buildType: String,
    val exportFolderConfigured: Boolean,
    val selectedProviderId: String,
    val connectedProviderIds: List<String>,
    val providers: List<RedactedHealthProviderDiagnostics>,
    val lastExport: RedactedExportDiagnostics?,
) {
    fun toShareText(zoneId: ZoneId = ZoneId.systemDefault()): String = buildString {
        appendLine("Health.md redacted provider diagnostics")
        appendLine("Generated: ${generatedAt.atZone(zoneId)}")
        appendLine("App: $appVersionName ($appVersionCode), $buildType")
        appendLine("Export folder configured: ${yesNo(exportFolderConfigured)}")
        appendLine("Selected provider: $selectedProviderId")
        appendLine("Connected providers: ${connectedProviderIds.ifEmpty { listOf("none") }.joinToString()}")
        appendLine()
        appendLine("Providers:")
        providers.forEach { provider ->
            appendLine("- ${provider.displayName} [${provider.id}]")
            appendLine("  integration: ${provider.integrationKind}")
            appendLine("  direct status: ${provider.directExportStatus}")
            appendLine("  installed: ${yesNo(provider.installed)}${provider.installedPackageName?.let { " ($it)" }.orEmpty()}")
            appendLine("  selected: ${yesNo(provider.selected)}")
            appendLine("  connected: ${yesNo(provider.connected)}")
            appendLine("  OAuth configured: ${provider.oauthConfigured.label}")
            appendLine("  OAuth token present: ${provider.oauthTokenPresent.label}")
            appendLine("  provider available: ${provider.available.label}")
            appendLine("  permissions/token ready: ${provider.permissions.label}")
            appendLine("  historical read permission: ${provider.historicalReadPermission.label}")
            appendLine("  background read permission: ${provider.backgroundReadPermission.label}")
        }
        appendLine()
        appendLine("Last export:")
        if (lastExport == null) {
            appendLine("- none recorded")
        } else {
            appendLine("- timestamp: ${Instant.ofEpochMilli(lastExport.timestampEpochMillis).atZone(zoneId)}")
            appendLine("- source: ${lastExport.source}")
            appendLine("- date range: ${lastExport.dateRange}")
            appendLine("- result: ${lastExport.successCount}/${lastExport.totalCount} days")
            appendLine("- failure reason: ${lastExport.failureReason?.name ?: "none"}")
            lastExport.warningSummary?.let { appendLine("- warning: $it") }
            if (lastExport.failedGroups.isEmpty()) {
                appendLine("- failed dates: none recorded")
            } else {
                appendLine("- failed date groups:")
                lastExport.failedGroups.forEach { group ->
                    appendLine("  - ${group.reason.name}: ${group.count} date(s), samples: ${group.sampleDates.joinToString()}")
                }
            }
        }
        appendLine()
        appendLine("Redaction: this report excludes health measurements, OAuth token values, provider client secrets, and raw file paths.")
    }

    private fun yesNo(value: Boolean): String = if (value) "yes" else "no"
}

data class RedactedHealthProviderDiagnostics(
    val id: String,
    val displayName: String,
    val integrationKind: String,
    val directExportStatus: String,
    val installed: Boolean,
    val installedPackageName: String?,
    val selected: Boolean,
    val connected: Boolean,
    val oauthConfigured: DiagnosticValue,
    val oauthTokenPresent: DiagnosticValue,
    val available: DiagnosticValue,
    val permissions: DiagnosticValue,
    val historicalReadPermission: DiagnosticValue,
    val backgroundReadPermission: DiagnosticValue,
)

data class RedactedExportDiagnostics(
    val timestampEpochMillis: Long,
    val source: String,
    val dateRange: String,
    val successCount: Int,
    val totalCount: Int,
    val failureReason: ExportFailureReason?,
    val failedGroups: List<RedactedExportFailureGroup>,
    val warningSummary: String?,
)

data class RedactedExportFailureGroup(
    val reason: ExportFailureReason,
    val count: Int,
    val sampleDates: List<String>,
)

sealed class DiagnosticValue(val label: String) {
    data object Yes : DiagnosticValue("yes")
    data object No : DiagnosticValue("no")
    data object NotApplicable : DiagnosticValue("n/a")
    data class Error(val type: String) : DiagnosticValue("error:$type")

    companion object {
        fun fromBoolean(value: Boolean): DiagnosticValue = if (value) Yes else No
    }
}
