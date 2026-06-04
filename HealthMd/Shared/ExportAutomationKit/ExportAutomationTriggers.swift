import Foundation

/// Domain-free trigger labels for export attempts across foreground,
/// background, retry, Shortcut, and connected-peer flows.
///
/// These values describe how an export attempt was initiated. Apps map them to
/// app-specific history labels and UI copy outside ExportAutomationKit.
enum ExportTriggerSource: String, Codable, CaseIterable, Equatable, Sendable {
    case manual = "manual"
    case scheduled = "scheduled"
    case shortcut = "shortcut"
    case silentPush = "silent_push"
    case backgroundTask = "background_task"
    case scheduledWake = "scheduled_wake"
    case dataSourceBackgroundDelivery = "data_source_background_delivery"
    case notificationTapRetry = "notification_tap_retry"
    case appActiveDrain = "app_active_drain"
    case connectedPeer = "connected_peer"
}

/// Stable source families used for app-level history/source labels.
///
/// Several triggers (silent push, BG task, notification retry, app-active drain)
/// are transports for the same scheduled or Shortcut export action. The source
/// family keeps persisted app history meaningful while trigger metadata remains
/// detailed and generic.
enum ExportTriggerSourceFamily: String, Codable, CaseIterable, Equatable, Sendable {
    case manual = "manual"
    case scheduled = "scheduled"
    case shortcut = "shortcut"
    case connectedPeer = "connected_peer"
}

enum ExportTriggerQuotaPolicy: String, Codable, Equatable, Sendable {
    case never = "never"
    case oncePerSuccessfulRun = "once_per_successful_run"

    func shouldRecordUsage(successCount: Int, alreadyRecorded: Bool = false) -> Bool {
        self == .oncePerSuccessfulRun && successCount > 0 && !alreadyRecorded
    }
}

enum ExportTriggerDestinationPolicy: String, Codable, Equatable, Sendable {
    /// Destination is selected by the app's foreground export UI.
    case appSelected = "app_selected"

    /// Destination must be the current device's local export destination.
    case localDevice = "local_device"

    /// Destination is a connected peer/device selected through a local handoff.
    case connectedPeer = "connected_peer"
}

enum ExportTriggerExecutionContext: String, Codable, Equatable, Sendable {
    case foreground = "foreground"
    case background = "background"
    case either = "either"
}

enum ExportTriggerScheduleUpdatePolicy: String, Codable, Equatable, Sendable {
    case never = "never"
    case afterSuccessfulRun = "after_successful_run"
    case whenPreviousCompleteDayWasIncluded = "when_previous_complete_day_was_included"

    func shouldUpdateLastExport(
        successCount: Int,
        exportedDates: [Date],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard successCount > 0 else { return false }

        switch self {
        case .never:
            return false
        case .afterSuccessfulRun:
            return true
        case .whenPreviousCompleteDayWasIncluded:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else {
                return false
            }
            return exportedDates.contains { calendar.isDate($0, inSameDayAs: yesterday) }
        }
    }
}

/// Testable source policy for reusable export automation flows.
///
/// The policy is intentionally domain-free: it does not know about app-specific
/// data stores, history UI labels, or purchase managers. Apps use the stable
/// `sourceFamily` and policy fields to perform app-specific side effects.
struct ExportTriggerSourcePolicy: Codable, Equatable, Sendable {
    var triggerSource: ExportTriggerSource
    var sourceFamily: ExportTriggerSourceFamily
    var quotaPolicy: ExportTriggerQuotaPolicy
    var destinationPolicy: ExportTriggerDestinationPolicy
    var executionContext: ExportTriggerExecutionContext
    var scheduleUpdatePolicy: ExportTriggerScheduleUpdatePolicy

    init(
        triggerSource: ExportTriggerSource,
        sourceFamily: ExportTriggerSourceFamily,
        quotaPolicy: ExportTriggerQuotaPolicy,
        destinationPolicy: ExportTriggerDestinationPolicy,
        executionContext: ExportTriggerExecutionContext,
        scheduleUpdatePolicy: ExportTriggerScheduleUpdatePolicy
    ) {
        self.triggerSource = triggerSource
        self.sourceFamily = sourceFamily
        self.quotaPolicy = quotaPolicy
        self.destinationPolicy = destinationPolicy
        self.executionContext = executionContext
        self.scheduleUpdatePolicy = scheduleUpdatePolicy
    }

    static func policy(
        for triggerSource: ExportTriggerSource,
        resolvedSourceFamily: ExportTriggerSourceFamily? = nil
    ) -> ExportTriggerSourcePolicy {
        switch triggerSource {
        case .manual:
            return ExportTriggerSourcePolicy(
                triggerSource: triggerSource,
                sourceFamily: .manual,
                quotaPolicy: .oncePerSuccessfulRun,
                destinationPolicy: .appSelected,
                executionContext: .foreground,
                scheduleUpdatePolicy: .never
            )
        case .scheduled:
            return scheduledPolicy(triggerSource: triggerSource, executionContext: .either)
        case .shortcut:
            return shortcutPolicy(triggerSource: triggerSource, executionContext: .foreground)
        case .silentPush, .backgroundTask, .scheduledWake, .dataSourceBackgroundDelivery:
            return scheduledPolicy(triggerSource: triggerSource, executionContext: .background)
        case .notificationTapRetry, .appActiveDrain:
            let family = resolvedSourceFamily ?? .scheduled
            switch family {
            case .shortcut:
                return shortcutPolicy(triggerSource: triggerSource, executionContext: .foreground)
            case .manual:
                return ExportTriggerSourcePolicy(
                    triggerSource: triggerSource,
                    sourceFamily: .manual,
                    quotaPolicy: .oncePerSuccessfulRun,
                    destinationPolicy: .appSelected,
                    executionContext: .foreground,
                    scheduleUpdatePolicy: .never
                )
            case .connectedPeer:
                return connectedPeerPolicy(triggerSource: triggerSource)
            case .scheduled:
                return scheduledPolicy(triggerSource: triggerSource, executionContext: .foreground)
            }
        case .connectedPeer:
            return connectedPeerPolicy(triggerSource: triggerSource)
        }
    }

    func shouldRecordQuota(successCount: Int, alreadyRecorded: Bool = false) -> Bool {
        quotaPolicy.shouldRecordUsage(successCount: successCount, alreadyRecorded: alreadyRecorded)
    }

    func shouldUpdateLastExport(
        successCount: Int,
        exportedDates: [Date],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        scheduleUpdatePolicy.shouldUpdateLastExport(
            successCount: successCount,
            exportedDates: exportedDates,
            now: now,
            calendar: calendar
        )
    }

    private static func scheduledPolicy(
        triggerSource: ExportTriggerSource,
        executionContext: ExportTriggerExecutionContext
    ) -> ExportTriggerSourcePolicy {
        ExportTriggerSourcePolicy(
            triggerSource: triggerSource,
            sourceFamily: .scheduled,
            quotaPolicy: .never,
            destinationPolicy: .localDevice,
            executionContext: executionContext,
            scheduleUpdatePolicy: .afterSuccessfulRun
        )
    }

    private static func shortcutPolicy(
        triggerSource: ExportTriggerSource,
        executionContext: ExportTriggerExecutionContext
    ) -> ExportTriggerSourcePolicy {
        ExportTriggerSourcePolicy(
            triggerSource: triggerSource,
            sourceFamily: .shortcut,
            quotaPolicy: .oncePerSuccessfulRun,
            destinationPolicy: .localDevice,
            executionContext: executionContext,
            scheduleUpdatePolicy: .whenPreviousCompleteDayWasIncluded
        )
    }

    private static func connectedPeerPolicy(triggerSource: ExportTriggerSource) -> ExportTriggerSourcePolicy {
        ExportTriggerSourcePolicy(
            triggerSource: triggerSource,
            sourceFamily: .connectedPeer,
            quotaPolicy: .oncePerSuccessfulRun,
            destinationPolicy: .connectedPeer,
            executionContext: .foreground,
            scheduleUpdatePolicy: .never
        )
    }
}

extension ExportTriggerSource {
    func policy(resolvedSourceFamily: ExportTriggerSourceFamily? = nil) -> ExportTriggerSourcePolicy {
        ExportTriggerSourcePolicy.policy(for: self, resolvedSourceFamily: resolvedSourceFamily)
    }
}

extension AutomationPendingExportSource {
    var exportTriggerSource: ExportTriggerSource {
        switch self {
        case .scheduled:
            return .scheduled
        case .shortcut:
            return .shortcut
        }
    }

    var exportTriggerSourceFamily: ExportTriggerSourceFamily {
        switch self {
        case .scheduled:
            return .scheduled
        case .shortcut:
            return .shortcut
        }
    }
}

extension AutomationBackgroundTrigger {
    var exportTriggerSource: ExportTriggerSource {
        switch self {
        case .silentPush:
            return .silentPush
        case .backgroundTask:
            return .backgroundTask
        case .scheduledWake:
            return .scheduledWake
        case .dataSourceBackgroundDelivery:
            return .dataSourceBackgroundDelivery
        }
    }
}

extension AutomationPendingExportRetryTrigger {
    var exportTriggerSource: ExportTriggerSource {
        switch self {
        case .notificationTap:
            return .notificationTapRetry
        case .appActiveDrain:
            return .appActiveDrain
        }
    }
}
