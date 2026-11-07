import SwiftUI

/// ConnectedAppsG copy derived from stored connection state; never from health values.
enum ConnectedAppsStatusText {
    /// ConnectedAppsG chip order: one toggle per WHOOP resource the export can include.
    static let whoopSnapshotResources: [WHOOPResourceName] = [.recovery, .cycles, .sleep, .workouts, .body]

    /// What the WHOOP section of an export can contain, one chip per fetched resource.
    static var whoopSnapshots: [String] {
        whoopSnapshotResources.map(snapshotTitle)
    }

    static func snapshotTitle(_ resource: WHOOPResourceName) -> String {
        switch resource {
        case .recovery: return String(localized: "Recovery")
        case .cycles: return String(localized: "Strain")
        case .sleep: return String(localized: "Sleep")
        case .workouts: return String(localized: "Workouts")
        case .body: return String(localized: "Body snapshot")
        }
    }

    /// "Connected · last sync 7:31 AM". The last sync is the provider's last successful
    /// export; earlier days show the date too.
    static func status(
        connected: Bool,
        lastSync: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard connected else { return String(localized: "Not connected") }
        guard let lastSync else { return String(localized: "Connected") }
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        let time = calendar.isDate(lastSync, inSameDayAs: now)
            ? lastSync.formatted(style.hour().minute())
            : lastSync.formatted(style.month(.abbreviated).day().hour().minute())
        return String(localized: "Connected · last sync \(time)")
    }
}

/// Wraps chips onto as many lines as they need.
struct ConnectedAppsChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
