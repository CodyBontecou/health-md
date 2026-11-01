#if os(iOS)
import SwiftUI

struct ArchiveScreen: View {
    let model: ArchiveModel
    let needsSetup: Bool
    let attentionCount: Int
    let onAction: (ArchiveProfile, ArchiveAggregation.DayAction, Date) -> Void
    let onResume: (ArchiveProfile) -> Void
    let onManageAutomations: () -> Void
    let onShowAttention: () -> Void
    let onSetUp: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var filter: UUID?
    @State private var month = Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { model.calendar }
    private var filteredProfile: ArchiveProfile? { model.profiles.first { $0.id == filter } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                HStack(alignment: .center) {
                    Text("Archive")
                        .glassFont(.largeTitle)
                        .foregroundStyle(palette.text)
                    Spacer(minLength: 8)
                    if !needsSetup && attentionCount > 0 { attentionButton }
                }

                if needsSetup {
                    EmptyArchiveCard(onSetUp: onSetUp)
                } else {
                    chips
                    statsPanel
                    if let profile = filteredProfile, profile.isPaused { pausedNote(profile) }
                    if horizontalSizeClass == .regular {
                        // Unfolded iPhone Duo and iPad: calendar beside its day.
                        HStack(alignment: .top, spacing: GlassMetrics.sectionGap) {
                            calendarPanel.frame(maxWidth: .infinity)
                            VStack(spacing: GlassMetrics.sectionGap) {
                                dayCard
                                sentenceCard
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        calendarPanel
                        dayCard
                        sentenceCard
                    }
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .background(palette.bg.ignoresSafeArea())
        .accessibilityIdentifier("glass.archive")
    }

    /// A compact header button; the full list opens in AttentionScreen.
    private var attentionButton: some View {
        Button(action: onShowAttention) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.coral)
                .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                .glassSurface(in: Circle(), isInteractive: true)
                .overlay(alignment: .topTrailing) {
                    Text(verbatim: "\(attentionCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.accentInk)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(palette.coral))
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Needs attention"))
        .accessibilityValue(String(localized: "\(attentionCount) item(s) need a look."))
        .accessibilityIdentifier("glass.archive.attention")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                GlassChip(title: String(localized: "All"), isSelected: filter == nil) { filter = nil }
                ForEach(model.profiles) { profile in
                    GlassChip(
                        title: profile.isPaused
                            ? String(localized: "\(profile.name) · paused")
                            : profile.name,
                        dotColor: palette.profileColor(at: profile.colorIndex),
                        isSelected: filter == profile.id
                    ) { filter = profile.id }
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
        }
        .padding(.horizontal, -GlassMetrics.screenMargin)
    }

    private var statsPanel: some View {
        let stats = model.stats(month: month, filter: filter)
        let isWeekly = model.isWeeklyFilter(filter)
        return HStack(spacing: 16) {
            Text(verbatim: "\(stats.archivedCount)")
                .glassFont(.heroNumber)
                .foregroundStyle(palette.text)
            VStack(alignment: .leading, spacing: 4) {
                Text(statsLabel(isWeekly: isWeekly))
                    .glassFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.text)
                HStack(spacing: 12) {
                    Text(isWeekly
                        ? String(localized: "\(stats.streak)-week streak")
                        : String(localized: "\(stats.streak)-day streak"))
                        .foregroundStyle(palette.sec)
                    Button {
                        guard let gap = stats.earliestGap else { return }
                        selectedDate = gap
                    } label: {
                        Text(stats.gapCount == 0
                            ? String(localized: "No gaps")
                            : String(localized: "\(stats.gapCount) gap(s)"))
                            .foregroundStyle(stats.gapCount == 0 ? palette.ok : palette.coral)
                    }
                    .buttonStyle(.plain)
                    .disabled(stats.gapCount == 0)
                }
                .glassFont(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassSurface()
    }

    private func statsLabel(isWeekly: Bool) -> String {
        let monthName = month.formatted(.dateTime.month(.wide))
        guard let profile = filteredProfile else {
            return String(localized: "days archived across automations")
        }
        if isWeekly { return String(localized: "weeks archived in \(monthName)") }
        if profile.hasTodayRefresh { return String(localized: "days fully or partly sent") }
        if profile.isPaused { return String(localized: "days archived before pausing") }
        return String(localized: "days archived in \(monthName)")
    }

    private func pausedNote(_ profile: ArchiveProfile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pause.circle")
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
            Text("\(profile.name) is paused. Days while paused are not counted as gaps.")
                .font(.system(size: 14))
                .foregroundStyle(palette.sec)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "Resume")) { onResume(profile) }
                .buttonStyle(.plain)
                .glassFont(.caption)
                .foregroundStyle(palette.accent)
                .frame(minHeight: GlassMetrics.touchTarget)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
    }

    private var calendarPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                monthButton(
                    String(localized: "Previous month"),
                    image: "chevron.left",
                    offset: -1,
                    isEnabled: canShowMonth(offset: -1)
                )
                monthButton(
                    String(localized: "Next month"),
                    image: "chevron.right",
                    offset: 1,
                    isEnabled: canShowMonth(offset: 1)
                )
            }
            MonthCalendarGrid(month: month, calendar: calendar) { date in
                tile(for: date)
            }
            legend
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .glassSurface()
    }

    private func tile(for date: Date) -> some View {
        let status = model.status(on: date, filter: filter)
        let issues = filter == nil
            ? ArchiveAggregation.issueDots(model.profileDays(on: date))
            : ArchiveAggregation.IssueDots(dots: [], hasOverflow: false)
        return CalendarDayTile(
            day: calendar.component(.day, from: date),
            status: status,
            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
            dots: issues.dots.map { dot in
                IssueDotsView.Dot(
                    id: dot.profileID,
                    color: palette.profileColor(
                        at: model.profiles.first { $0.id == dot.profileID }?.colorIndex ?? 0
                    ),
                    isFilled: dot.isFilled
                )
            },
            hasOverflow: issues.hasOverflow,
            accessibilityText: ArchiveCopy.tileAccessibility(
                date: date,
                status: status,
                model: model,
                showsIssues: filter == nil
            )
        ) {
            selectedDate = date
        }
    }

    private func canShowMonth(offset: Int) -> Bool {
        guard let target = calendar.date(byAdding: .month, value: offset, to: month) else { return false }
        if offset > 0 {
            return calendar.compare(target, to: model.now, toGranularity: .month) != .orderedDescending
        }
        guard let oldest = calendar.date(
            byAdding: .day,
            value: -CoverageLedger.retentionDays,
            to: model.now
        ) else { return false }
        return calendar.compare(target, to: oldest, toGranularity: .month) != .orderedAscending
    }

    private func monthButton(
        _ label: String,
        image: String,
        offset: Int,
        isEnabled: Bool
    ) -> some View {
        Button {
            month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
        } label: {
            Image(systemName: image)
                .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                .contentShape(Rectangle())
                .foregroundStyle(isEnabled ? palette.text : palette.muted.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.complete) { palette.fill }
            legendItem(.partial) { palette.partial }
            legendItem(.missing) { palette.coral.opacity(0.35) }
            legendItem(.notDue) { palette.line }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func legendItem(_ status: CoverageStatus, fill: () -> Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(fill()).frame(width: 10, height: 10)
            Text(ArchiveCopy.title(for: status)).lineLimit(1)
        }
    }

    private var dayCard: some View {
        let shown = filteredProfile.map { [$0] } ?? model.profiles
        let counts = ArchiveAggregation.onTrack(model.profileDays(on: selectedDate))
        return GlassPanel {
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .glassFont(.navTitle)
                    .foregroundStyle(palette.text)
                Spacer()
                if filter == nil {
                    Text(counts.due == 0
                        ? String(localized: "Nothing due")
                        : String(localized: "\(counts.onTrack) of \(counts.due) on track"))
                        .glassFont(.caption)
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .padding(.vertical, 14)

            ForEach(shown) { profile in
                Divider().overlay(palette.line)
                dayRow(profile)
            }
        }
    }

    private func dayRow(_ profile: ArchiveProfile) -> some View {
        let day = model.day(profile, on: selectedDate)
        let action = ArchiveAggregation.action(for: day.status, hasTodayRefresh: profile.hasTodayRefresh)
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(palette.profileColor(at: profile.colorIndex))
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(profile.name).glassFont(.body).fontWeight(.semibold).foregroundStyle(palette.text)
                    StatusBadge(title: ArchiveCopy.title(for: day.status), status: day.status)
                }
                Text(profile.destination)
                    .glassFont(.monoBody)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                Text(ArchiveCopy.note(for: day, profile: profile))
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.sec)
            }
            Spacer(minLength: 8)
            if let action {
                Button(ArchiveCopy.title(for: action.action)) {
                    onAction(profile, action.action, selectedDate)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(action.isProminent ? palette.accentInk : palette.text)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(action.isProminent ? palette.accent : palette.surface2))
                .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                .frame(minHeight: GlassMetrics.touchTarget)
            }
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 12)
    }

    private var sentenceCard: some View {
        let paused = model.profiles.filter(\.isPaused).count
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Automations"))
                    .glassFont(.caption)
                    .foregroundStyle(palette.muted)
                Text("\(model.profiles.count - paused) running and \(paused) paused. “All” counts a day complete when every running automation that was due covered it.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.sec)
            }
            Spacer(minLength: 8)
            Button(String(localized: "Manage"), action: onManageAutomations)
                .buttonStyle(.plain)
                .glassFont(.caption)
                .foregroundStyle(palette.accent)
                .frame(minHeight: GlassMetrics.touchTarget)
        }
        .padding(GlassMetrics.panelPadding)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
    }
}

/// EmptyArchiveG: shown until Health access and a destination exist.
struct EmptyArchiveCard: View {
    let onSetUp: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your archive starts here").glassFont(.screenTitle).foregroundStyle(palette.text)
            Text("Each day you export fills a square on the calendar.")
                .glassFont(.body)
                .foregroundStyle(palette.sec)
            Button(String(localized: "Choose folder"), action: onSetUp)
                .buttonStyle(GlassPrimaryButtonStyle())
                .padding(.top, 8)
        }
        .padding(GlassMetrics.panelPadding + 4)
        .glassSurface()
    }
}

/// AttentionG: one card per live problem, each with its fix.
struct AttentionScreen: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let message: String
        let actionTitle: String?
        let action: (() -> Void)?
    }

    let items: [Item]

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        // Fixable problems are coral; items that only explain a wait use the accent.
                        let tone = item.action == nil ? palette.accent : palette.coral
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.action == nil ? "info.circle" : "exclamationmark.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(tone)
                                .padding(.top, 1)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text(item.message)
                                    .font(.system(size: 14))
                                    .foregroundStyle(palette.sec)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let actionTitle = item.actionTitle, let action = item.action {
                                    Button(actionTitle) {
                                        dismiss()
                                        action()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                    .padding(.horizontal, 14)
                                    .frame(height: 32)
                                    .background(Capsule().fill(palette.surface2))
                                    .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                                    .frame(minHeight: GlassMetrics.touchTarget)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, GlassMetrics.panelPadding)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: GlassMetrics.panelSmallRadius, style: .continuous)
                                .strokeBorder(tone.opacity(0.8), lineWidth: 1)
                        )
                    }
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "Needs attention"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}
#endif
