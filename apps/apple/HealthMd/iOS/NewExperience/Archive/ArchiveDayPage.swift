#if os(iOS)
import SwiftUI

/// A date opened from the Archive.
struct ArchiveDayRoute: Hashable {
    let date: Date
    let profileID: UUID?
}

/// DayPage: the file itself. One tab per automation, its status for the date, and the
/// written file line by line, with the date's fix and the full viewer below.
struct ArchiveDayPage: View {
    let model: ArchiveModel
    let date: Date
    let loadDayFile: (ArchiveProfile, Date) async -> ArchiveDayFile?
    let onAction: (ArchiveProfile, ArchiveAggregation.DayAction, Date) -> Void

    @Environment(\.glassPalette) private var palette
    @State private var selection: UUID?
    @State private var file: ArchiveDayFile?
    @State private var loadedKey: LoadKey?
    @State private var isLoading = false

    init(
        model: ArchiveModel,
        date: Date,
        profileID: UUID?,
        loadDayFile: @escaping (ArchiveProfile, Date) async -> ArchiveDayFile?,
        onAction: @escaping (ArchiveProfile, ArchiveAggregation.DayAction, Date) -> Void
    ) {
        self.model = model
        self.date = date
        self.loadDayFile = loadDayFile
        self.onAction = onAction
        _selection = State(initialValue: profileID ?? model.leadProfile(filter: nil)?.id)
    }

    private struct LoadKey: Hashable {
        let profileID: UUID
        let status: CoverageStatus
        let updatedAt: Date?
    }

    private var calendar: Calendar { model.calendar }
    private var profile: ArchiveProfile? {
        model.profiles.first { $0.id == selection } ?? model.profiles.first
    }

    private var title: String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func loadKey(for profile: ArchiveProfile) -> LoadKey? {
        let day = model.day(profile, on: date)
        guard day.status == .complete || day.status == .partial || day.status == .inProgress,
              model.canOpen(profile, on: date) else { return nil }
        return LoadKey(profileID: profile.id, status: day.status, updatedAt: day.record?.updatedAt)
    }

    private var currentKey: LoadKey? { profile.flatMap(loadKey(for:)) }
    private var shownFile: ArchiveDayFile? { loadedKey == currentKey ? file : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.profiles.count > 1 { tabs }
                if let profile {
                    status(profile)
                    fileCard(profile)
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shownFile {
                ToolbarItem(placement: .confirmationAction) {
                    let item = ExportedMarkdownShareItem(name: shownFile.fileURL.lastPathComponent, source: shownFile.source)
                    ShareLink(item: item, preview: SharePreview(item.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share file"))
                    .accessibilityIdentifier("glass.dayPage.share")
                }
            }
        }
        .task(id: currentKey) { await load() }
        .accessibilityIdentifier("glass.dayPage")
    }

    private func load() async {
        guard let key = currentKey, let profile else {
            file = nil
            loadedKey = nil
            return
        }
        isLoading = true
        let loaded = await loadDayFile(profile, date)
        guard !Task.isCancelled else { return }
        file = loaded
        loadedKey = key
        isLoading = false
    }

    // MARK: - Tabs

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.profiles) { item in
                    GlassChip(
                        title: item.name,
                        dotColor: palette.profileColor(at: item.colorIndex),
                        isSelected: item.id == profile?.id
                    ) { selection = item.id }
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -GlassMetrics.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Automation"))
    }

    // MARK: - Status

    private func status(_ profile: ArchiveProfile) -> some View {
        let day = model.day(profile, on: date)
        return VStack(alignment: .leading, spacing: 6) {
            StatusBadge(title: ArchiveCopy.title(for: day.status), status: day.status)
            Text(ArchiveCopy.note(for: day, profile: profile, calendar: calendar))
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - File

    private func fileCard(_ profile: ArchiveProfile) -> some View {
        let day = model.day(profile, on: date)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(verbatim: model.pathLine(profile, day: day))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.sec)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let shownFile {
                    Text(verbatim: shownFile.sizeText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if let shownFile {
                lines(shownFile)
            } else {
                Text(emptyMessage(profile, day: day))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier("glass.dayPage.noFile")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private func emptyMessage(_ profile: ArchiveProfile, day: CoverageDay) -> String {
        if isLoading && currentKey != nil { return String(localized: "Reading the file…") }
        if !profile.writesFilesOnDevice {
            return String(localized: "This automation writes somewhere this iPhone can’t read, so the file isn’t shown here.")
        }
        switch day.status {
        case .complete, .partial, .inProgress:
            return model.canOpen(profile, on: date)
                ? String(localized: "The file for this date isn’t in the folder any more.")
                : String(localized: "This automation doesn’t write a file of its own for each date.")
        case .missing:
            return String(localized: "No file was written for this date.")
        case .notDue, .paused:
            return String(localized: "Nothing was due on this date.")
        }
    }

    private func lines(_ file: ArchiveDayFile) -> some View {
        let lines = file.lines
        let digits = max(2, String(lines.count).count)
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(verbatim: "\(index + 1)")
                                .foregroundStyle(palette.muted.opacity(0.6))
                                .frame(width: CGFloat(digits) * 9 + 8, alignment: .trailing)
                                .padding(.trailing, 12)
                                .accessibilityHidden(true)
                            Text(verbatim: line.isEmpty ? " " : line)
                                .foregroundStyle(color(for: line))
                                .fontWeight(line.hasPrefix("#") ? .medium : .regular)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 22.75, alignment: .leading)
                    }
                }
                .padding(.trailing, 18)
                .textSelection(.enabled)
            }
            if file.isTruncated {
                Text("Long file: the first lines are shown. Open it to read the rest.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: file.source))
        .accessibilityIdentifier("glass.dayPage.file")
    }

    private func color(for line: String) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "{" || trimmed == "}" { return palette.muted }
        if trimmed.hasPrefix("#") { return palette.text }
        return palette.sec
    }

    // MARK: - Actions

    /// The date's fix (Backfill, Retry, Refresh), or Re-export for a written day.
    private func secondaryAction(_ profile: ArchiveProfile) -> ArchiveAggregation.DayAction? {
        let day = model.day(profile, on: date)
        if let action = model.action(profile, day: day)?.action, action != .open { return action }
        switch day.status {
        case .complete, .partial: return .reExport
        default: return nil
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if let profile {
            let secondary = secondaryAction(profile)
            let canOpen = shownFile != nil
            if secondary != nil || canOpen {
                HStack(spacing: 10) {
                    if let secondary {
                        Button(ArchiveCopy.title(for: secondary)) { onAction(profile, secondary, date) }
                            .buttonStyle(.plain)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(canOpen ? palette.text : palette.accentInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: GlassMetrics.primaryButtonHeight)
                            .background {
                                if canOpen {
                                    Capsule().fill(.clear).glassSurface(in: Capsule(), style: .strong, isInteractive: true)
                                } else {
                                    Capsule().fill(palette.accent)
                                }
                            }
                            .contentShape(Capsule())
                            .accessibilityIdentifier("glass.dayPage.fix")
                    }
                    if canOpen {
                        Button(String(localized: "Open file")) { onAction(profile, .open, date) }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .layoutPriority(1)
                            .accessibilityIdentifier("glass.dayPage.open")
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.bottom, 8)
            }
        }
    }
}
#endif
