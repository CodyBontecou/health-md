#if os(iOS)
import Combine
import Foundation
import UIKit

/// Handles Mac-initiated export requests while the iPhone app is open. The Mac
/// controls the date range, but the iPhone remains the HealthKit source of truth.
/// Requests may either use saved iPhone export settings exactly or apply a
/// temporary, non-persisted CLI policy that disables derived roll-up summaries.
@MainActor
final class IPhoneExportRequestHandler: ObservableObject {
    private struct PendingRequest {
        let request: IPhoneExportRequest
        let settings: AdvancedExportSettings
    }

    private var activeRequestID: UUID?
    private var pendingRequests: [UUID: PendingRequest] = [:]

    func handle(
        _ request: IPhoneExportRequest,
        syncService: SyncService,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil
    ) async {
        guard activeRequestID == nil else {
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .requestAlreadyInProgress,
                message: "The iPhone is already preparing another export."
            )))
            return
        }

        let settings = settings(for: request)
        let dates = ExportOrchestrator.dateRange(from: request.dateRangeStart, to: request.dateRangeEnd)
        guard !dates.isEmpty, dates.count <= 366 else {
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .invalidDateRange,
                message: "Choose a date range between 1 and 366 days."
            )))
            return
        }

        guard healthKitManager.isAuthorized else {
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .healthKitNotAuthorized,
                message: "HealthKit access has not been granted on iPhone."
            )))
            return
        }

        await PurchaseManager.shared.refreshStatus()
        guard PurchaseManager.shared.canExport else {
            PricingAnalyticsClient.shared.trackExportBlockedByQuota(
                context: .macTarget,
                targetType: .connectedMac,
                quotaState: PurchaseManager.shared.analyticsQuotaState
            )
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .exportLimitReached,
                message: "Export limit reached. Unlock Full Access on iPhone to export more."
            )))
            return
        }

        if request.responseMode == .writeFiles {
            guard syncService.canExportToConnectedMac(requiring: settings) else {
                syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                    jobID: request.jobID,
                    reason: .macDestinationUnavailable,
                    message: syncService.macExportReadinessMessage(requiring: settings)
                )))
                return
            }
        }

        activeRequestID = request.jobID
        pendingRequests[request.jobID] = PendingRequest(request: request, settings: settings)
        syncService.isSyncing = true
        syncService.send(.iphoneExportAccepted(IPhoneExportAcknowledgement(
            jobID: request.jobID,
            acceptedAt: Date(),
            message: "iPhone export request accepted."
        )))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let enabledExternalIntegrations: ExternalIntegrationDailyRecordProviding? = ConnectedAppsFeature.isEnabled ? externalIntegrations : nil
        let externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
        if let enabledExternalIntegrations, enabledExternalIntegrations.connectedProviderCount > 0 {
            externalRecordFetcher = { date in
                await enabledExternalIntegrations.fetchDailyRecords(for: date)
            }
        } else {
            externalRecordFetcher = nil
        }

        do {
            switch request.responseMode {
            case .writeFiles:
                let job = try await MacExportJobBuilder.build(
                    jobID: request.jobID,
                    sourceDeviceName: UIDevice.current.name,
                    startDate: request.dateRangeStart,
                    endDate: request.dateRangeEnd,
                    settings: settings,
                    destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                    fetchHealthData: { date, includeGranularData in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: settings.metricSelection
                        )
                    },
                    fetchExternalDailyRecords: externalRecordFetcher,
                    onProgress: { processed, total, date in
                        syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                            jobID: request.jobID,
                            processedDays: processed,
                            totalDays: total,
                            currentDate: date,
                            message: "Preparing \(dateFormatter.string(from: date)) on iPhone…"
                        )))
                    }
                )

                guard activeRequestID == request.jobID else { return }
                guard syncService.canExportToConnectedMac(requiring: settings) else {
                    failPreparation(
                        jobID: request.jobID,
                        syncService: syncService,
                        reason: .macDestinationUnavailable,
                        message: syncService.macExportReadinessMessage(requiring: settings)
                    )
                    return
                }

                syncService.sendLargePayload(.macExportRequest(job))
            case .rawJSON:
                let payload = try await buildRawDataPayload(
                    for: request,
                    dates: dates,
                    settings: settings,
                    healthKitManager: healthKitManager,
                    externalIntegrations: enabledExternalIntegrations,
                    syncService: syncService,
                    dateFormatter: dateFormatter
                )
                guard activeRequestID == request.jobID else { return }
                syncService.sendLargePayload(.iphoneExportRawData(payload))
                completeRawRequest(payload, settings: settings, syncService: syncService)
            }
        } catch is CancellationError {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: .cancelled,
                message: "iPhone export request was cancelled."
            )
        } catch let error as HealthKitManager.HealthKitError {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: .healthKitFetchFailed,
                message: message(for: error),
                underlyingError: String(describing: error)
            )
        } catch {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: .healthKitFetchFailed,
                message: "Failed to prepare HealthKit data on iPhone: \(error.localizedDescription)",
                underlyingError: error.localizedDescription
            )
        }
    }

    @discardableResult
    func complete(with payload: MacExportResultPayload) -> Bool {
        guard let pending = pendingRequests.removeValue(forKey: payload.jobID) else { return false }
        activeRequestID = nil

        let result = ExportOrchestrator.ExportResult(
            successCount: payload.successCount,
            totalCount: payload.totalCount,
            failedDateDetails: payload.failedDateDetails,
            formatsPerDate: payload.formatsPerDate,
            externalRecordFileCount: payload.externalRecordFileCount,
            wasCancelled: payload.status == .cancelled
        )

        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: pending.request.dateRangeStart,
            dateRangeEnd: pending.request.dateRangeEnd,
            targetLabel: payload.destinationDisplayName ?? "Mac",
            fileCount: payload.totalFilesWritten
        )

        if payload.successCount > 0 {
            PurchaseManager.shared.recordExportUse()
            PricingAnalyticsClient.shared.trackExportSucceeded(
                metadata: PricingAnalyticsExportMetadata(
                    targetType: .connectedMac,
                    formatCount: pending.settings.exportFormats.count,
                    metricCount: pending.settings.metricSelection.totalEnabledCount,
                    dateRangePreset: PricingAnalyticsDateRangePreset.custom,
                    startDate: pending.request.dateRangeStart,
                    endDate: pending.request.dateRangeEnd
                ),
                quotaState: PurchaseManager.shared.analyticsQuotaState
            )
        }
        return true
    }

    @discardableResult
    func complete(with failure: MacExportFailure) -> Bool {
        guard let jobID = failure.jobID,
              let pending = pendingRequests.removeValue(forKey: jobID) else { return false }
        activeRequestID = nil

        let failedDetail = FailedDateDetail(
            date: pending.request.dateRangeStart,
            reason: exportFailureReason(for: failure.reason),
            errorDetails: failure.underlyingError ?? failure.message
        )
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: max(ExportOrchestrator.dateRange(from: pending.request.dateRangeStart, to: pending.request.dateRangeEnd).count, 1),
            failedDateDetails: [failedDetail],
            formatsPerDate: max(pending.settings.exportFormats.count, 1),
            wasCancelled: failure.reason == .cancelled
        )
        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: pending.request.dateRangeStart,
            dateRangeEnd: pending.request.dateRangeEnd,
            targetLabel: "Mac",
            fileCount: 0
        )
        return true
    }

    func completeRejected(jobID: UUID?) {
        guard let jobID else { return }
        pendingRequests.removeValue(forKey: jobID)
        if activeRequestID == jobID { activeRequestID = nil }
    }

    private func buildRawDataPayload(
        for request: IPhoneExportRequest,
        dates: [Date],
        settings: AdvancedExportSettings,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?,
        syncService: SyncService,
        dateFormatter: DateFormatter
    ) async throws -> IPhoneExportRawDataPayload {
        var records: [HealthData] = []
        var externalDailyRecords: [ExternalDailyRecord] = []
        var failedDateDetails: [FailedDateDetail] = []

        for (index, date) in dates.enumerated() {
            try Task.checkCancellation()
            syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                jobID: request.jobID,
                processedDays: index + 1,
                totalDays: dates.count,
                currentDate: date,
                message: "Fetching raw data for \(dateFormatter.string(from: date)) on iPhone…"
            )))

            do {
                let record = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: settings.includeGranularData,
                    metricSelection: settings.metricSelection
                ).filtered(by: settings.metricSelection)
                if record.hasAnyData {
                    records.append(record)
                    if (externalIntegrations?.connectedProviderCount ?? 0) > 0 {
                        let providerRecords = await externalIntegrations?.fetchDailyRecords(for: date) ?? []
                        externalDailyRecords.append(contentsOf: providerRecords.filter(\.shouldExport))
                    }
                } else {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                }
            } catch let error as HealthKitManager.HealthKitError {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: failureReason(for: error),
                    errorDetails: message(for: error)
                ))
            } catch {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: .healthKitError,
                    errorDetails: error.localizedDescription
                ))
            }
        }

        return IPhoneExportRawDataPayload(
            jobID: request.jobID,
            createdAt: Date(),
            sourceDeviceName: UIDevice.current.name,
            dateRangeStart: dates.first ?? Calendar.current.startOfDay(for: request.dateRangeStart),
            dateRangeEnd: dates.last ?? Calendar.current.startOfDay(for: request.dateRangeEnd),
            totalDays: dates.count,
            records: records,
            externalDailyRecords: externalDailyRecords,
            failedDateDetails: failedDateDetails,
            settingsSnapshot: ExportSettingsSnapshot.from(settings)
        )
    }

    private func completeRawRequest(
        _ payload: IPhoneExportRawDataPayload,
        settings: AdvancedExportSettings,
        syncService: SyncService
    ) {
        guard let pending = pendingRequests.removeValue(forKey: payload.jobID) else { return }
        activeRequestID = nil
        syncService.isSyncing = false

        let result = ExportOrchestrator.ExportResult(
            successCount: payload.records.count,
            totalCount: payload.totalDays,
            failedDateDetails: payload.failedDateDetails,
            formatsPerDate: 0,
            externalRecordFileCount: payload.externalDailyRecords.filter(\.shouldExport).count
        )
        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: pending.request.dateRangeStart,
            dateRangeEnd: pending.request.dateRangeEnd,
            targetLabel: "CLI raw response",
            fileCount: 0
        )

        guard payload.records.count > 0 else { return }
        PurchaseManager.shared.recordExportUse()
        PricingAnalyticsClient.shared.trackExportSucceeded(
            metadata: PricingAnalyticsExportMetadata(
                targetType: .connectedMac,
                formatCount: 0,
                metricCount: settings.metricSelection.totalEnabledCount,
                dateRangePreset: PricingAnalyticsDateRangePreset.custom,
                startDate: pending.request.dateRangeStart,
                endDate: pending.request.dateRangeEnd
            ),
            quotaState: PurchaseManager.shared.analyticsQuotaState
        )
    }

    private func settings(for request: IPhoneExportRequest) -> AdvancedExportSettings {
        let savedSettings = AdvancedExportSettings()
        let settings = ExportSettingsSnapshot.from(savedSettings).makeAdvancedExportSettings()

        switch request.settingsPolicy {
        case .currentIPhoneSettings:
            break
        case .requestedDatesOnly:
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
            settings.summaryOnlyExport = false
        }

        return settings
    }

    private func failPreparation(
        jobID: UUID,
        syncService: SyncService,
        reason: IPhoneExportFailureReason,
        message: String,
        underlyingError: String? = nil
    ) {
        pendingRequests.removeValue(forKey: jobID)
        if activeRequestID == jobID { activeRequestID = nil }
        syncService.isSyncing = false
        syncService.send(.iphoneExportRejected(IPhoneExportFailure(
            jobID: jobID,
            reason: reason,
            message: message,
            underlyingError: underlyingError
        )))
    }

    private func message(for error: HealthKitManager.HealthKitError) -> String {
        switch error {
        case .dataProtectedWhileLocked:
            return "Health data is protected while the iPhone is locked. Unlock iPhone and try again."
        case .notAuthorized:
            return "HealthKit access has not been granted on iPhone."
        case .dataNotAvailable:
            return "HealthKit data is not available on this device."
        case .medicationAuthorizationUnsupported:
            return "Medication authorization is not supported on this device."
        }
    }

    private func failureReason(for error: HealthKitManager.HealthKitError) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked:
            return .deviceLocked
        case .notAuthorized:
            return .accessDenied
        case .dataNotAvailable, .medicationAuthorizationUnsupported:
            return .healthKitError
        }
    }

    private func exportFailureReason(for reason: MacExportFailureReason) -> ExportFailureReason {
        switch reason {
        case .noMacFolderSelected:
            return .noVaultSelected
        case .macFolderAccessDenied:
            return .accessDenied
        case .noHealthRecordsReceived:
            return .noHealthData
        case .noFormatsSelected, .payloadDecodeFailure, .exportWriteFailure:
            return .fileWriteError
        case .incompatibleProtocol, .macBusy:
            return .unknown
        case .cancelled:
            return .unknown
        }
    }
}
#endif
