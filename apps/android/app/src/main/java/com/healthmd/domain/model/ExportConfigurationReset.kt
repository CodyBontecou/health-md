package com.healthmd.domain.model

/**
 * 3.5 "Reset to Defaults" for one automation's export configuration (Apple
 * `ExportSettingsSnapshot.resettingExportConfiguration()`).
 *
 * Every export choice returns to [ExportSettings.newInstallDefaults], the same defaults the 3.5
 * `resetSettings()` wrote: export type and raw snapshot options, data types, formats, metadata,
 * grouping, file names, folder organization and structure, write mode, format customization,
 * metric selection, daily notes, individual entries and detail level.
 *
 * Kept, because they describe where and when this automation runs rather than what it exports:
 * destinations and endpoints, the subfolder, the schedule and its pending retries, and the
 * operation-only authority (engine pin, sleep capture context, provider capture authority).
 * The profile's id, name and destination bindings live outside these settings and are
 * untouched by the caller's save path.
 */
fun ExportSettings.resettingExportConfiguration(): ExportSettings = ExportSettings.newInstallDefaults().copy(
    exportTarget = exportTarget,
    scheduledExportTarget = scheduledExportTarget,
    apiEndpointUrl = apiEndpointUrl,
    agentDataGatewayUrl = agentDataGatewayUrl,
    subfolder = subfolder,
    scheduleEnabled = scheduleEnabled,
    scheduleCadenceValue = scheduleCadenceValue,
    scheduleCadenceUnit = scheduleCadenceUnit,
    scheduleHour = scheduleHour,
    scheduleMinute = scheduleMinute,
    scheduleLookbackDays = scheduleLookbackDays,
    scheduleDateWindow = scheduleDateWindow,
    pendingScheduledRetryDates = pendingScheduledRetryDates,
    pendingScheduledExportRequests = pendingScheduledExportRequests,
    executionEnginePin = executionEnginePin,
    executionEngineAuthorityIsFrozen = executionEngineAuthorityIsFrozen,
    executionSleepCaptureContext = executionSleepCaptureContext,
    executionSleepCaptureAuthorityIsFrozen = executionSleepCaptureAuthorityIsFrozen,
    executionProviderCaptureAuthority = executionProviderCaptureAuthority,
    executionProviderCaptureAuthorityIsFrozen = executionProviderCaptureAuthorityIsFrozen,
)
