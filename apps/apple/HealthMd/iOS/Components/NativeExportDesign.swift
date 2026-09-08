#if os(iOS)
import SwiftUI

/// Glass belongs to the controls above the content, never to export documents.
/// System styles also honor Reduce Transparency, Increase Contrast and Reduce Motion.
struct HealthGlassActionStyle: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(Color.actionAccent).buttonBorderShape(.capsule)
            } else {
                content.buttonStyle(.glass).buttonBorderShape(.capsule)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(Color.actionAccent).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

/// A compact, editable fact row. At accessibility sizes the value moves
/// below its label instead of squeezing the two columns.
struct ProfileSettingRow: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            Text(LocalizedStringKey(title))
                .foregroundStyle(.secondary)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 122, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value.isEmpty ? "—" : value)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this setting")
    }
}

struct ExportWorkspaceProfileHeader: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    var compact = false

    var body: some View {
        Text(coordinator.activeProfileName ?? String(localized: "Exports"))
            .font(compact ? .subheadline.weight(.semibold) : .largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

enum ExportWorkspaceRoute: String, Hashable {
    case profile, data, metrics, detail, files, notes, entries, formatting, destination, schedule, review
    case rollup, writeMode, archive, dictionary

    var title: String {
        switch self {
        case .profile: "Edit export"
        case .metrics: "Metrics"
        case .detail: "Data detail"
        case .rollup: "Roll-up summaries"
        case .writeMode: "When a file exists"
        case .archive: "Zip archive"
        case .dictionary: "Data dictionary"
        case .data: "Health data"
        case .files: "Health files"
        case .notes: "Daily notes"
        case .entries: "Individual entries"
        case .formatting: "Format & fields"
        case .destination: "Destination"
        case .schedule: "Schedule"
        case .review: "Review export"
        }
    }
}

enum HealthFileEditorSection: String, CaseIterable, Identifiable {
    case formats = "Formats"
    case paths = "Names & folders"
    case existing = "Existing files"
    var id: Self { self }
}
#endif
