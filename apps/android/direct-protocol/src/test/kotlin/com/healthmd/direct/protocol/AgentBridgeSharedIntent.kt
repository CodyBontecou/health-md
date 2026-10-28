package com.healthmd.direct.protocol

/** Shared agreement input, independently authored from primitive synthetic values.
 * No fixture/tree decoding, issued authority, provider reads, or runtime capability claims. */
internal object AgentBridgeSharedIntent {
    fun construct(): AgentBridgeGeneratedIntent = AgentBridgeGeneratedIntent(
        calendarTimezone = "Etc/UTC",
        captureScope = AgentBridgeCapture(
            compatibilityDetail = AgentBridgeCompatibilityDetail.SUMMARY,
            nativeArchive = AgentBridgeArchiveNone(type = "none"),
            selection = AgentBridgeSelection(
                allMetrics = false,
                categoryIds = emptyList(),
                metricIds = listOf("steps"),
                providerIds = emptyList(),
                sourceIds = listOf("health_connect"),
            ),
        ),
        dates = AgentBridgeDatesExact(
            range = AgentBridgeRange(startDate = "2000-01-01", endDate = "2000-01-02"),
            type = "exact",
        ),
        destination = AgentBridgeDestination(
            bindingId = "00000000-0000-4000-8000-000000000003",
            hostInstallationId = "00000000-0000-4000-8000-000000000002",
            identitySha256 = "1111111111111111111111111111111111111111111111111111111111111111",
            revision = 1,
        ),
        intentId = "00000000-0000-4000-8000-000000000004",
        peer = AgentBridgePeer(
            hostInstallationId = "00000000-0000-4000-8000-000000000002",
            platform = AgentBridgePlatform.ANDROID,
            sourceInstallationId = "00000000-0000-4000-8000-000000000001",
        ),
        product = AgentBridgeGeneratedIntentProduct(type = "generated_files"),
        schema = "healthmd.agent_export_intent",
        schemaVersion = 1,
        settingsPolicy = AgentBridgeSettingsPolicyExplicit(
            settings = AgentBridgeOutputSettings(
                dailyNotes = AgentBridgeDailyNotes(
                    createIfMissing = false, enabled = false, filenameTemplate = "{date}",
                    folderTemplate = "notes/{year}", only = false, sectionIds = emptyList(),
                ),
                dictionary = AgentBridgeDictionaryNone(type = "none"),
                filenameTemplate = "{date}",
                folderTemplate = "{year}",
                formats = listOf(AgentBridgeFormat.JSON),
                individualEntries = AgentBridgeIndividualEntries(
                    categoryFolders = false, enabled = false, filenameTemplate = "{date}-{record_id}",
                    folderTemplate = "entries/{year}", metricIds = emptyList(),
                ),
                outputProfile = AgentBridgeOutputProfile.ANDROID_ANALYTICAL_V5,
                packaging = AgentBridgePackagingLooseFiles(type = "loose_files"),
                presentation = AgentBridgePresentation(
                    displayUnits = AgentBridgePresentationDisplayUnits.METRIC,
                    frontmatter = AgentBridgeFrontmatter(
                        customFields = emptyList(), enabledFieldIds = emptyList(),
                        includeCaptureDiagnostics = true, includeUnits = true,
                    ),
                    groupByCategory = true,
                    includeMetadata = true,
                    locale = "en-US",
                    machineUnits = "canonical",
                    markdown = AgentBridgeMarkdown(
                        customTemplate = "", placeholderIds = emptyList(), style = AgentBridgeMarkdownStyle.TABLES,
                    ),
                ),
                subfolder = "",
                writeMode = AgentBridgeWriteMode.OVERWRITE,
            ),
            type = "explicit",
        ),
        timestampTimezone = "UTC",
    )
}
