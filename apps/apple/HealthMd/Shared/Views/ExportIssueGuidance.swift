import Foundation

/// User-facing guidance for HealthKit reads that have not been authorized yet.
struct ExportPermissionGuidance: Identifiable, Equatable {
    let healthDataNames: [String]
    let healthDataCount: Int

    var id: String { "\(healthDataCount):\(healthDataNames.joined(separator: "|"))" }

    var healthDataName: String {
        guard healthDataCount > 1 else {
            return healthDataNames.first ?? "the requested health data"
        }
        guard healthDataCount <= 3,
              healthDataNames.count == healthDataCount,
              !healthDataNames.contains("the requested health data") else {
            return "\(healthDataCount) additional health data types"
        }
        return ListFormatter.localizedString(byJoining: healthDataNames)
    }

    init(healthDataName: String) {
        healthDataNames = [healthDataName]
        healthDataCount = 1
    }

    init?(failure: ExportPartialFailure) {
        let normalizedError = failure.errorDescription.lowercased()
        guard normalizedError.contains("authorization"),
              normalizedError.contains("not determined") else {
            return nil
        }

        if let metricName = HealthMetrics.all.first(where: { metric in
            guard let identifier = metric.healthKitIdentifier else { return false }
            return failure.dataType.contains(identifier)
        })?.name {
            healthDataNames = [metricName]
        } else if failure.dataType.contains("HK"), failure.dataType.contains("Identifier") {
            healthDataNames = ["the requested health data"]
        } else {
            healthDataNames = [failure.dataType]
        }
        healthDataCount = 1
    }

    init?(failures: [ExportPartialFailure]) {
        var names: [String] = []
        var seenDataTypes: Set<String> = []
        for failure in failures where seenDataTypes.insert(failure.dataType).inserted {
            guard let name = Self(failure: failure)?.healthDataNames.first else { continue }
            if !names.contains(name) {
                names.append(name)
            }
        }

        guard !seenDataTypes.isEmpty else { return nil }
        healthDataNames = names
        healthDataCount = seenDataTypes.count
    }

    var iOSInstructions: String {
        let permissionTarget = healthDataCount <= 3
            ? healthDataName
            : "the additional data types you want to export"

        return "Health.md has not requested access to \(permissionTarget) on this device yet.\n\n"
            + "Tap \"Request Access\" to show Apple's permission sheet. New data types do not appear under Health → Apps → Health.md until Health.md requests them.\n\n"
            + "If Apple has already recorded a choice, Health.md will open the Health app so you can change it."
    }

    var macInstructions: String {
        "Health.md needs access to \(healthDataName). On your iPhone, open Health.md and tap the Health status on the Export screen to request additional access. New data types do not appear in the Apple Health app until Health.md requests them. After syncing, try again on your Mac."
    }
}

/// A compact, actionable summary of the issues from a partial export.
struct PartialExportNotice: Identifiable {
    let id = UUID()
    let issueCount: Int
    let permissionGuidance: ExportPermissionGuidance?
    private let otherIssueDetails: [String]

    init?(result: ExportOrchestrator.ExportResult) {
        guard result.isPartialSuccess else { return nil }

        let permissionFailures = result.partialFailures.filter {
            ExportPermissionGuidance(failure: $0) != nil
        }
        let otherWarnings = result.partialFailures.filter {
            ExportPermissionGuidance(failure: $0) == nil
        }
        let failedDates = result.failedDateDetails.map {
            "\($0.dateString): \($0.reason.shortDescription)"
        }

        let guidance = ExportPermissionGuidance(failures: permissionFailures)

        issueCount = result.partialFailures.count + result.failedDateDetails.count
        permissionGuidance = guidance
        otherIssueDetails = otherWarnings.map(\.summary) + failedDates
    }

    var toastMessage: String {
        if permissionGuidance != nil {
            return "Partial export: Health permissions need attention. Tap to fix."
        }

        let count = max(issueCount, 1)
        return "Partial export completed with \(count) issue\(count == 1 ? "" : "s"). Tap to review."
    }

    var genericAlertMessage: String {
        let count = max(issueCount, 1)
        let intro = "Some data was exported, but \(count) issue\(count == 1 ? "" : "s") occurred."
        let details = summarized(otherIssueDetails)
        return details.isEmpty ? intro : "\(intro)\n\n\(details)"
    }

    func permissionAlertMessage(instructions: String) -> String {
        var message = "Your export finished, but some health data was skipped.\n\n\(instructions)"
        let details = summarized(otherIssueDetails)
        if !details.isEmpty {
            message += "\n\nOther export issues:\n\(details)"
        }
        return message
    }

    private func summarized(_ details: [String]) -> String {
        guard !details.isEmpty else { return "" }

        let maximumVisibleIssues = 3
        var lines = details.prefix(maximumVisibleIssues).map { "• \($0)" }
        if details.count > maximumVisibleIssues {
            lines.append("• \(details.count - maximumVisibleIssues) more issue\(details.count - maximumVisibleIssues == 1 ? "" : "s")")
        }
        return lines.joined(separator: "\n")
    }
}
