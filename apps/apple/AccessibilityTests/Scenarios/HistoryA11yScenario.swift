import SwiftUI

/// Actual history disclosure components with deterministic in-memory evidence.
/// No HealthKit permission, query, exporter, or production-service stand-in.
struct HistoryA11yScenario: View {
    @State private var reviews = 0
    @State private var execution = false

    private var assessment: HealthHistoryAssessment {
        let scope = HealthHistoryScope(metricIDs: ["steps"],
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400), timeZoneIdentifier: "UTC",
            allAvailable: true, profileID: nil)
        return HealthHistoryAssessment(id: UUID(), assessedAt: scope.endDate, scope: scope,
            types: [HealthHistoryTypeAssessment(id: "HKQuantityTypeIdentifierStepCount", directMetricIDs: ["steps"],
                dependencyMetricIDs: [], dependencyReasons: [], access: .unknown)], evidenceSource: "synthetic_ui_fixture")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Reviews: \(reviews)").accessibilityIdentifier("a11y.history.reviews")
                Button("Show execution disclosure") { execution = true }
                    .accessibilityIdentifier("a11y.history.showExecution")
                HealthHistoryDisclosureContent(assessment: assessment, isExecution: execution,
                    reviewAccess: { reviews += 1 })
                    .modifier(HealthHistoryWarningAccessibilityContainer())
            }
            .padding(Spacing.s4)
        }
        .background(Color.bgPrimary)
    }
}
