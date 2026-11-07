import Foundation

/// NotificationsG failure copy: the profile, the class of cause and what needs review.
/// Never health values, dates of records, system error text, or paths.
nonisolated enum ScheduledExportNotificationCopy {
    static func failureBody(
        profileName: String?,
        folderName: String?,
        reason: ExportFailureReason?
    ) -> String {
        let profile = profileName.flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "Scheduled export", comment: "Notification subject when no profile name is known")
        switch reason {
        case .noVaultSelected, .accessDenied, .fileWriteError:
            if let folderName, !folderName.isEmpty {
                return String(
                    localized: "\(profile) couldn’t write — the \(folderName) folder needs review.",
                    comment: "Scheduled export failure: profile name, then export folder name"
                )
            }
            return String(
                localized: "\(profile) couldn’t write — the export folder needs review.",
                comment: "Scheduled export failure when the folder name is unknown"
            )
        case .apiEndpointNotConfigured, .apiUploadFailed:
            return String(
                localized: "\(profile) couldn’t send — the API endpoint needs review.",
                comment: "Scheduled export failure for an API endpoint destination"
            )
        case .healthKitError:
            return String(
                localized: "\(profile) couldn’t read Apple Health — Health access needs review.",
                comment: "Scheduled export failure reading HealthKit"
            )
        case .noHealthData:
            return String(
                localized: "\(profile) found no Apple Health data for its dates.",
                comment: "Scheduled export found no data"
            )
        case .deviceLocked:
            return String(
                localized: "\(profile) needs your iPhone unlocked. Open Health.md to finish.",
                comment: "Scheduled export blocked because protected data was unavailable"
            )
        case .backgroundTaskExpired:
            return String(
                localized: "\(profile) ran out of background time. Open Health.md to finish.",
                comment: "Scheduled export interrupted by iOS"
            )
        case .unknown, .none:
            return String(
                localized: "\(profile) couldn’t finish. Open Health.md for details.",
                comment: "Scheduled export failure with an unknown cause"
            )
        }
    }
}
