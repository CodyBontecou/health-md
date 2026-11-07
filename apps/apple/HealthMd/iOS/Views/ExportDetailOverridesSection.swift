import SwiftUI

/// Per-category compatibility detail. "Default" follows the Data Detail preset; any other choice
/// stores an explicit override for that category only. HealthKit exposes sleep as category
/// intervals rather than source sessions, so Apple offers Summary or Detailed (stages) for sleep.
struct ExportDetailOverridesSection: View {
    @Binding var policy: AppleExportDetailPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Detail by Category")
                .font(.body.weight(.semibold))
            Text("Override the default for individual categories. Daily summaries never change.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(ExportDetailGroup.appleSupported, id: \.self) { group in
                HStack(spacing: Spacing.s2) {
                    Text(group.localizedTitle)
                    Spacer()
                    Picker(group.localizedTitle, selection: binding(for: group)) {
                        Text("Default").tag(ExportDetailChoice?.none)
                        ForEach(group.appleSupportedChoices, id: \.self) { choice in
                            Text(choice.localizedTitle).tag(ExportDetailChoice?.some(choice))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Color.accent)
                    .accessibilityIdentifier("export-detail-\(group.rawValue)")
                }
            }
            Text(ExportDetailGroup.appleV12Footnote)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.s3)
        .accessibilityElement(children: .contain)
    }

    private func binding(for group: ExportDetailGroup) -> Binding<ExportDetailChoice?> {
        Binding(
            get: { policy.compatibilityDetailOverrides[group] },
            set: { policy = policy.settingCompatibilityDetail($0, for: group) }
        )
    }
}

extension ExportDetailGroup {
    var localizedTitle: String {
        switch self {
        case .sleep: String(localized: "Sleep", comment: "Export detail category")
        case .activity: String(localized: "Activity", comment: "Export detail category")
        case .heart: String(localized: "Heart", comment: "Export detail category")
        case .vitals: String(localized: "Vitals", comment: "Export detail category")
        case .nutrition: String(localized: "Nutrition", comment: "Export detail category")
        case .mobility: String(localized: "Mobility", comment: "Export detail category")
        case .reproductiveHealth: String(localized: "Reproductive Health", comment: "Export detail category")
        case .mindfulness: String(localized: "Mindfulness", comment: "Export detail category")
        case .workouts: String(localized: "Workouts", comment: "Export detail category")
        case .body: String(localized: "Body", comment: "Export detail category")
        }
    }
}

extension ExportDetailGroup {
    /// Shown under the per-category pickers wherever they appear.
    static var appleV12Footnote: String {
        String(
            localized: "Detailed Sleep adds the source app or device of each sleep stage. Detailed Activity, Nutrition, Mobility, Reproductive Health, Mindfulness, Body, or Vitals adds individual samples. Either switches files to schema 12. Unavailable with Morning ends.",
            comment: "Footnote under per-category export detail pickers"
        )
    }
}

extension ExportDetailChoice {
    var localizedTitle: String {
        switch self {
        case .summary: String(localized: "Summary", comment: "Export detail choice")
        case .sessions: String(localized: "Sessions", comment: "Export detail choice")
        case .detailed: String(localized: "Detailed", comment: "Export detail choice")
        }
    }
}
