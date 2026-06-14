//
//  PricingAnalyticsFunnel.swift
//  HealthMd
//
//  Typed helpers for privacy-safe pricing funnel instrumentation.
//

import Foundation

nonisolated struct PricingAnalyticsQuotaState: Equatable, Sendable {
    let freeExportsUsed: Int
    let freeExportsRemaining: Int
}

nonisolated struct PricingAnalyticsExportMetadata: Equatable, Sendable {
    let targetType: PricingAnalyticsExportTargetType
    let formatCount: Int
    let metricCountBucket: PricingAnalyticsMetricCountBucket
    let dateRangePreset: PricingAnalyticsDateRangePreset
    let dateSpanBucket: PricingAnalyticsDateSpanBucket

    init(
        targetType: PricingAnalyticsExportTargetType,
        formatCount: Int,
        metricCount: Int,
        dateRangePreset: ExportDateRangePreset,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) {
        self.init(
            targetType: targetType,
            formatCount: formatCount,
            metricCount: metricCount,
            dateRangePreset: PricingAnalyticsDateRangePreset(dateRangePreset),
            startDate: startDate,
            endDate: endDate,
            calendar: calendar
        )
    }

    init(
        targetType: PricingAnalyticsExportTargetType,
        formatCount: Int,
        metricCount: Int,
        dateRangePreset: PricingAnalyticsDateRangePreset,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) {
        self.targetType = targetType
        self.formatCount = formatCount
        self.metricCountBucket = Self.metricCountBucket(for: metricCount)
        self.dateRangePreset = dateRangePreset
        self.dateSpanBucket = Self.dateSpanBucket(
            startDate: startDate,
            endDate: endDate,
            calendar: calendar
        )
    }

    static func metricCountBucket(for metricCount: Int) -> PricingAnalyticsMetricCountBucket {
        switch max(0, metricCount) {
        case 0:
            return .zero
        case 1...5:
            return .oneToFive
        case 6...10:
            return .sixToTen
        case 11...20:
            return .elevenToTwenty
        default:
            return .twentyOnePlus
        }
    }

    static func dateSpanBucket(
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) -> PricingAnalyticsDateSpanBucket {
        let normalizedStartDate = calendar.startOfDay(for: min(startDate, endDate))
        let normalizedEndDate = calendar.startOfDay(for: max(startDate, endDate))
        let dayDelta = calendar.dateComponents(
            [.day],
            from: normalizedStartDate,
            to: normalizedEndDate
        ).day ?? 0
        let inclusiveDayCount = max(1, dayDelta + 1)

        switch inclusiveDayCount {
        case 1:
            return .sameDay
        case 2...7:
            return .oneToSevenDays
        case 8...30:
            return .eightToThirtyDays
        case 31...90:
            return .thirtyOneToNinetyDays
        default:
            return .ninetyOnePlusDays
        }
    }
}

extension PricingAnalyticsDateRangePreset {
    nonisolated init(_ preset: ExportDateRangePreset) {
        switch preset {
        case .today:
            self = .today
        case .yesterday:
            self = .yesterday
        case .allTime:
            self = .allTime
        case .custom:
            self = .custom
        }
    }
}

extension PricingAnalyticsClient {
    func trackOnboardingCompleted(quotaState: PricingAnalyticsQuotaState) {
        track(PricingAnalyticsEvent(
            name: .onboardingCompleted,
            properties: properties(quotaState: quotaState)
        ))
    }

    func trackHealthAuthorizationCompleted(status: PricingAnalyticsAuthorizationStatus) {
        track(PricingAnalyticsEvent(
            name: .healthAuthorizationCompleted,
            properties: PricingAnalyticsProperties(authorizationStatus: status)
        ))
    }

    func trackExportPreviewOpened(metadata: PricingAnalyticsExportMetadata) {
        track(PricingAnalyticsEvent(
            name: .exportPreviewOpened,
            properties: properties(metadata: metadata)
        ))
    }

    func trackExportPreviewGenerated(metadata: PricingAnalyticsExportMetadata) {
        track(PricingAnalyticsEvent(
            name: .exportPreviewGenerated,
            properties: properties(metadata: metadata)
        ))
    }

    func trackExportPreviewFailed(
        metadata: PricingAnalyticsExportMetadata,
        errorCategory: PricingAnalyticsErrorCategory
    ) {
        track(PricingAnalyticsEvent(
            name: .exportPreviewFailed,
            properties: properties(
                metadata: metadata,
                errorCategory: errorCategory
            )
        ))
    }

    func trackExportSucceeded(
        metadata: PricingAnalyticsExportMetadata,
        quotaState: PricingAnalyticsQuotaState
    ) {
        track(PricingAnalyticsEvent(
            name: .exportSucceeded,
            properties: properties(
                metadata: metadata,
                quotaState: quotaState
            )
        ))
    }

    func trackFreeExportUsed(quotaState: PricingAnalyticsQuotaState) {
        track(PricingAnalyticsEvent(
            name: .freeExportUsed,
            properties: properties(quotaState: quotaState)
        ))
    }

    func trackPaywallShown(
        context: PricingAnalyticsPaywallContext,
        quotaState: PricingAnalyticsQuotaState
    ) {
        track(PricingAnalyticsEvent(
            name: .paywallShown,
            properties: properties(
                quotaState: quotaState,
                paywallContext: context
            )
        ))
    }

    func trackExportBlockedByQuota(
        context: PricingAnalyticsPaywallContext,
        targetType: PricingAnalyticsExportTargetType,
        quotaState: PricingAnalyticsQuotaState
    ) {
        track(PricingAnalyticsEvent(
            name: .exportBlockedByQuota,
            properties: properties(
                quotaState: quotaState,
                paywallContext: context,
                targetType: targetType
            )
        ))
    }

    func trackPurchaseStarted(
        productId: PricingAnalyticsProductID = .lifetimeUnlock,
        quotaState: PricingAnalyticsQuotaState
    ) {
        track(PricingAnalyticsEvent(
            name: .purchaseStarted,
            properties: properties(
                quotaState: quotaState,
                productId: productId,
                purchaseOutcome: .started
            )
        ))
    }

    func trackPurchaseFinished(
        outcome: PricingAnalyticsPurchaseOutcome,
        errorCategory: PricingAnalyticsErrorCategory? = nil,
        productId: PricingAnalyticsProductID = .lifetimeUnlock,
        quotaState: PricingAnalyticsQuotaState
    ) {
        track(PricingAnalyticsEvent(
            name: .purchaseFinished,
            properties: properties(
                quotaState: quotaState,
                productId: productId,
                purchaseOutcome: outcome,
                errorCategory: errorCategory
            )
        ))
    }

    func trackRestoreStarted(
        productId: PricingAnalyticsProductID? = nil,
        quotaState: PricingAnalyticsQuotaState
    ) {
        track(PricingAnalyticsEvent(
            name: .restoreStarted,
            properties: properties(
                quotaState: quotaState,
                productId: productId,
                purchaseOutcome: .started
            )
        ))
    }

    func trackRestoreFinished(
        outcome: PricingAnalyticsPurchaseOutcome,
        errorCategory: PricingAnalyticsErrorCategory? = nil,
        productId: PricingAnalyticsProductID? = nil,
        quotaState: PricingAnalyticsQuotaState
    ) {
        track(PricingAnalyticsEvent(
            name: .restoreFinished,
            properties: properties(
                quotaState: quotaState,
                productId: productId,
                purchaseOutcome: outcome,
                errorCategory: errorCategory
            )
        ))
    }

    func trackScheduleEnableBlocked(quotaState: PricingAnalyticsQuotaState) {
        track(PricingAnalyticsEvent(
            name: .scheduleEnableBlocked,
            properties: properties(
                quotaState: quotaState,
                paywallContext: .schedule,
                errorCategory: .notUnlocked
            )
        ))
    }

    func trackScheduleEnableUnblocked(quotaState: PricingAnalyticsQuotaState) {
        track(PricingAnalyticsEvent(
            name: .scheduleEnableUnblocked,
            properties: properties(
                quotaState: quotaState,
                paywallContext: .schedule
            )
        ))
    }

    private func properties(
        metadata: PricingAnalyticsExportMetadata? = nil,
        quotaState: PricingAnalyticsQuotaState? = nil,
        paywallContext: PricingAnalyticsPaywallContext? = nil,
        targetType: PricingAnalyticsExportTargetType? = nil,
        productId: PricingAnalyticsProductID? = nil,
        purchaseOutcome: PricingAnalyticsPurchaseOutcome? = nil,
        errorCategory: PricingAnalyticsErrorCategory? = nil
    ) -> PricingAnalyticsProperties {
        PricingAnalyticsProperties(
            paywallContext: paywallContext,
            freeExportsUsed: quotaState?.freeExportsUsed,
            freeExportsRemaining: quotaState?.freeExportsRemaining,
            exportTargetType: metadata?.targetType ?? targetType,
            formatCount: metadata?.formatCount,
            metricCountBucket: metadata?.metricCountBucket,
            dateRangePreset: metadata?.dateRangePreset,
            dateSpanBucket: metadata?.dateSpanBucket,
            productId: productId,
            purchaseOutcome: purchaseOutcome,
            errorCategory: errorCategory
        )
    }
}
