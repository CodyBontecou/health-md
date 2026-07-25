package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFailureReason
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class HealthProviderDiagnosticsReportTest {

    @Test
    fun shareText_includesProviderStatusAndOmitsSensitiveValues() {
        val report = RedactedHealthProviderDiagnosticsReport(
            generatedAt = Instant.parse("2026-06-02T12:00:00Z"),
            appVersionName = "1.4.0",
            appVersionCode = 15,
            buildType = "debug",
            exportFolderConfigured = true,
            selectedProviderId = "oura",
            connectedProviderIds = listOf("health_connect", "oura"),
            providers = listOf(
                RedactedHealthProviderDiagnostics(
                    id = "oura",
                    displayName = "Oura",
                    integrationKind = "Cloud API",
                    directExportStatus = "Needs OAuth credentials",
                    installed = true,
                    installedPackageName = "com.ouraring.oura",
                    selected = true,
                    connected = true,
                    oauthConfigured = DiagnosticValue.Yes,
                    oauthTokenPresent = DiagnosticValue.Yes,
                    available = DiagnosticValue.Yes,
                    permissions = DiagnosticValue.Yes,
                    historicalReadPermission = DiagnosticValue.NotApplicable,
                    backgroundReadPermission = DiagnosticValue.NotApplicable,
                ),
            ),
            lastExport = RedactedExportDiagnostics(
                timestampEpochMillis = 1_780_403_200_000,
                source = "MANUAL",
                dateRange = "2026-06-01..2026-06-02",
                successCount = 1,
                totalCount = 2,
                failureReason = ExportFailureReason.RATE_LIMITED,
                failedGroups = listOf(
                    RedactedExportFailureGroup(
                        reason = ExportFailureReason.RATE_LIMITED,
                        count = 1,
                        sampleDates = listOf("2026-06-02"),
                    ),
                ),
                warningSummary = "1 failed date(s)",
            ),
        )

        val text = report.toShareText(ZoneId.of("UTC"))

        assertThat(text).contains("Health.md redacted provider diagnostics")
        assertThat(text).contains("Selected provider: oura")
        assertThat(text).contains("OAuth token present: yes")
        assertThat(text).contains("RATE_LIMITED")
        assertThat(text).doesNotContain("access_token")
        assertThat(text).doesNotContain("refresh_token")
        assertThat(text).doesNotContain("client_secret")
        assertThat(text).doesNotContain("/storage/emulated")
        assertThat(text).contains("Redaction: this report excludes health measurements")
    }
}
