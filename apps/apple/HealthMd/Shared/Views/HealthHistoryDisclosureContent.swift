import SwiftUI

/// Shared native content for phone/tablet cards. These observations are advisory,
/// independently of capture coverage; they never claim complete permission.
struct HealthHistoryDisclosureContent: View {
    let assessment: HealthHistoryAssessment
    let isExecution: Bool
    let reviewAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(assessment.warningMessage)
                .accessibilityIdentifier("export.historyWarning.message")
            if isExecution {
                Text(assessment.evidenceSource == "assessment_not_completed"
                    ? "Continued without a completed history assessment. History remains unverified."
                    : "Rechecked for this export. Query completion is not proof of full history.")
                    .accessibilityIdentifier("export.historyWarning.execution")
            }
            Button("Review Health Access", action: reviewAccess)
                .accessibilityIdentifier("export.historyWarning.reviewAccess")
                .accessibilityHint("Shows instructions for reviewing Health.md access in Apple Health")
            DisclosureGroup("History access details") {
                ForEach(assessment.types) { type in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        typeDetail(type)
                        Text("Selected metrics: \(type.directMetricIDs.joined(separator: ", ")). Dependencies for: \(type.dependencyMetricIDs.joined(separator: ", ")). Reasons: \(type.dependencyReasons.joined(separator: ", ")).")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("export.historyWarning.details")
        }
        .font(.footnote)
    }

    @ViewBuilder private func typeDetail(_ type: HealthHistoryTypeAssessment) -> some View {
        switch type.access {
        case .limited(let boundary):
            Text("\(type.id): sample end boundary \(assessment.boundaryDescription(boundary)). Earlier starts are preserved.")
        case .apiUnavailable:
            Text("\(type.id): history assessment requires OS 27. This does not mean health data is unavailable.")
        case .assessmentFailed:
            Text("\(type.id): history assessment failed; readable data may still be available.")
        case .unknown:
            Text("\(type.id): no authorization boundary returned; history access is unknown.")
        case .unassessed(let reason):
            Text("\(type.id): not assessed (\(reason)).")
        }
    }
}

struct HealthHistoryPendingContent: View {
    let continueUnverified: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("This check is advisory. If it takes too long, continue with unverified history or cancel the check. Cancelling does not prove the framework stopped its work.")
            Button("Continue without history verification", action: continueUnverified)
                .accessibilityIdentifier("export.historyWarning.continueUnverified")
            Button("Cancel history check", action: cancel)
                .accessibilityIdentifier("export.historyWarning.cancelCheck")
        }
        .font(.footnote)
    }
}
