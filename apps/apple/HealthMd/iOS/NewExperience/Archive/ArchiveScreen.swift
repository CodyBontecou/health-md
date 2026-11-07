#if os(iOS)
import SwiftUI

/// Which board the Archive follows for the current window.
enum ArchiveLayout: Equatable {
    /// ArchiveGlass: the iPhone column.
    case phone
    /// DuoOuterG: the outer display of a phone that unfolds.
    case folded
    /// DuoSplitViewG: a narrow window beside another app.
    case splitView
    /// DuoInnerArchiveG: calendar beside the day, profiles as chips.
    case wide
    /// iPadArchiveG: as wide, with profiles in the sidebar and Export now in the header.
    case pad

    init(_ window: GlassWindowClass) {
        switch window {
        case .phone: self = .phone
        case .folded: self = .folded
        case .splitView: self = .splitView
        case .unfolded: self = .wide
        case .pad: self = .pad
        }
    }

    var isWide: Bool { self == .wide || self == .pad }
}

/// Setup progress for EmptyArchiveG's checklist.
struct ArchiveSetupState: Equatable {
    let isHealthConnected: Bool
}

struct ArchiveScreen: View {
    let model: ArchiveModel
    var layout: ArchiveLayout = .phone
    @Binding var filter: UUID?
    let needsSetup: Bool
    let setup: ArchiveSetupState
    let attentionCount: Int
    let onAction: (ArchiveProfile, ArchiveAggregation.DayAction, Date) -> Void
    let onResume: (ArchiveProfile) -> Void
    let onManageAutomations: () -> Void
    let onEditAutomation: (ArchiveProfile) -> Void
    let onShowAttention: () -> Void
    let onConnectHealth: () -> Void
    let onSetUp: () -> Void
    let onBackfill: () -> Void
    let onExportNow: () -> Void
    /// Reads a day's written file for the readable day card; nil when it cannot be read.
    var loadDayFile: (ArchiveProfile, Date) async -> ArchiveDayFile? = { _, _ in nil }
    /// Pushes the day page for a date, on the given automation's tab.
    var onOpenDay: (Date, UUID?) -> Void = { _, _ in }

    @Environment(\.glassPalette) private var palette
    @State private var month = Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    /// Archive B: the iPhone leads with a week strip and a readable day; Month shows
    /// the full calendar. The choice is remembered.
    @AppStorage("glass.archive.showsMonth") private var showsMonth = false
    /// The scroll view's visible height, so the wide layouts can fill it.
    @State private var viewportHeight: CGFloat = 0
    @State private var dayFile: ArchiveDayFile?
    @State private var dayFileKey: DayFileKey?

    private var calendar: Calendar { model.calendar }
    private var filteredProfile: ArchiveProfile? { model.profiles.first { $0.id == filter } }
    private var shownProfiles: [ArchiveProfile] { filteredProfile.map { [$0] } ?? model.profiles }

    var body: some View {
        ScrollView {
            Group {
                if needsSetup {
                    VStack(alignment: .leading, spacing: 14) {
                        titleRow(String(localized: "Archive"), size: 34, showsHeart: true)
                        EmptyArchiveCard(
                            setup: setup,
                            onConnectHealth: onConnectHealth,
                            onChooseFolder: onSetUp,
                            onBackfill: onBackfill
                        )
                    }
                } else {
                    switch layout {
                    case .phone: phoneBody
                    case .folded: foldedBody
                    case .splitView: splitBody
                    case .wide, .pad: wideBody
                    }
                }
            }
            .padding(.horizontal, layout.isWide ? 22 : GlassMetrics.screenMargin)
            .padding(.top, layout == .splitView ? 20 : 12)
            .padding(.bottom, layout.isWide ? 22 : GlassMetrics.scrollBottomInset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .background(palette.bg.ignoresSafeArea())
        .accessibilityIdentifier("glass.archive")
    }

    // MARK: - Layouts

    /// ArchiveGlass (iPhone): Archive B's week strip and readable day, or the month.
    @ViewBuilder private var phoneBody: some View {
        if showsMonth {
            VStack(alignment: .leading, spacing: 14) {
                titleRow(String(localized: "Archive"), size: 34, showsHeart: true)
                chips(compact: false)
                pausedNoteIfNeeded
                calendarPanel
                dayCard
                sentenceCard
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                titleRow(String(localized: "Archive"), size: 34, showsHeart: true)
                if model.profiles.count > 1 { chips(compact: false) }
                nextRunCard
                pausedNoteIfNeeded
                weekPanel
                readableDayCard
                sentenceCard
            }
            .task(id: dayFileRequest) { await loadLeadFile() }
        }
    }

    /// DuoOuterG: the outer display keeps the month and says the inner one shows more.
    /// This layout only follows a phone that has been unfolded, so the day card and the
    /// automation sentence stay one unfold away (DuoInnerArchiveG), and the phone column
    /// keeps them for phones that do not fold.
    private var foldedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow(String(localized: "Archive"), size: 30, showsHeart: true)
            chips(compact: true)
            pausedNoteIfNeeded
            calendarPanel
                .environment(\.calendarDensityOverride, .folded)
            Text("Unfold for the calendar and day detail side by side.")
                .font(.system(size: 12))
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 4)
        }
    }

    /// DuoSplitViewG: chips, calendar and the selected day only.
    private var splitBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow(String(localized: "Archive"), size: 28, showsHeart: attentionCount > 0)
            chips(compact: true)
            pausedNoteIfNeeded
            calendarPanel
            compactDayPanel(showsSummary: false, fillsHeight: false)
        }
    }

    /// DuoInnerArchiveG and iPadArchiveG: the month beside its day. Both panels reach the
    /// bottom of the visible area, as on the boards, and grow past it (scrolling) when
    /// the month needs more room.
    private var wideBody: some View {
        FillVisibleHeightLayout(minHeight: max(0, viewportHeight - wideVerticalPadding)) {
            VStack(alignment: .leading, spacing: layout == .pad ? 16 : 12) {
                wideHeader
                if layout == .wide { chips(compact: true) }
                pausedNoteIfNeeded
                HStack(alignment: .top, spacing: layout == .pad ? 16 : 14) {
                    calendarPanel(fillsHeight: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    compactDayPanel(showsSummary: true, fillsHeight: true)
                        .frame(width: layout == .pad ? 320 : 250)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// The wide layouts' top and bottom scroll padding (see `body`).
    private var wideVerticalPadding: CGFloat { 12 + 22 }

    // MARK: - Header

    private func titleRow(_ title: String, size: CGFloat, showsHeart: Bool) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: size, weight: .bold))
                .tracking(size >= 34 ? -0.6 : 0)
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if showsHeart { heartButton }
        }
        .padding(.horizontal, layout == .phone ? 4 : 0)
    }

    /// The crystal-heart "Health.md" button. It opens Needs attention and carries its count.
    private var heartButton: some View {
        Button(action: onShowAttention) {
            Image("HealthCrystalHeart")
                .resizable()
                .scaledToFit()
                .frame(width: layout == .phone ? 24 : 22, height: layout == .phone ? 24 : 22)
                .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                .glassSurface(in: Circle(), style: .strong, isInteractive: true)
                .overlay(alignment: .topTrailing) {
                    if attentionCount > 0 {
                        Text(verbatim: "\(attentionCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.accentInk)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(palette.coral))
                            .offset(x: 4, y: -4)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Health.md"))
        .accessibilityValue(attentionCount > 0
            ? String(localized: "\(attentionCount) item(s) need a look.")
            : String(localized: "Nothing needs attention"))
        .accessibilityIdentifier("glass.archive.attention")
    }

    private var wideHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            monthTitle
            Spacer(minLength: 8)
            monthButton(String(localized: "Previous month"), image: "chevron.left", offset: -1)
            monthButton(String(localized: "Next month"), image: "chevron.right", offset: 1)
            if attentionCount > 0 { heartButton }
            if layout == .pad {
                Button(action: onExportNow) {
                    Text("Export now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accentInk)
                        .padding(.horizontal, 20)
                        .frame(height: GlassMetrics.touchTarget)
                        .background(Capsule().fill(palette.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("glass.exportNow")
            }
        }
    }

    private var monthTitle: some View {
        Text(month.formatted(.dateTime.month(.wide).year()))
            .font(.system(size: layout == .pad ? 34 : 30, weight: .bold))
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }

    private func gapButton(_ stats: ArchiveAggregation.Stats, weight: Font.Weight) -> some View {
        Button {
            guard let gap = stats.earliestGap else { return }
            select(gap)
        } label: {
            Text(stats.gapCount == 0
                ? String(localized: "No gaps")
                : String(localized: "\(stats.gapCount) gap(s)"))
                .fontWeight(weight)
                .foregroundStyle(stats.gapCount == 0 ? palette.ok : palette.coral)
        }
        .buttonStyle(.plain)
        .disabled(stats.gapCount == 0)
    }

    private func select(_ date: Date) {
        selectedDate = date
        if !calendar.isDate(date, equalTo: month, toGranularity: .month) { month = date }
    }

    // MARK: - Chips

    private func chips(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 6 : 8) {
                chip(String(localized: "All"), color: nil, id: nil, compact: compact)
                ForEach(model.profiles) { profile in
                    chip(
                        profile.isPaused && !compact
                            ? String(localized: "\(profile.name) · paused")
                            : profile.name,
                        color: palette.profileColor(at: profile.colorIndex),
                        id: profile.id,
                        compact: compact
                    )
                }
            }
            .padding(.horizontal, layout.isWide ? 22 : GlassMetrics.screenMargin)
        }
        .padding(.horizontal, layout.isWide ? -22 : -GlassMetrics.screenMargin)
    }

    @ViewBuilder
    private func chip(_ title: String, color: Color?, id: UUID?, compact: Bool) -> some View {
        if compact {
            CompactArchiveChip(title: title, dotColor: color, isSelected: filter == id) { filter = id }
        } else {
            GlassChip(title: title, dotColor: color, isSelected: filter == id) { filter = id }
        }
    }

    @ViewBuilder private var pausedNoteIfNeeded: some View {
        if let profile = filteredProfile, profile.isPaused { pausedNote(profile) }
    }

    private func pausedNote(_ profile: ArchiveProfile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pause.circle")
                .font(.system(size: 17))
                .foregroundStyle(palette.muted)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(ArchiveCopy.pausedNote(profile))
                .font(.system(size: 14))
                .foregroundStyle(palette.sec)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Resume")) { onResume(profile) }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(palette.surface2))
                .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                .frame(minHeight: GlassMetrics.touchTarget)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 18)
    }

    // MARK: - Calendar

    private var calendarPanel: some View { calendarPanel(fillsHeight: false) }

    /// `fillsHeight`: the wide boards stretch the calendar's glass to the day panel's
    /// height, with the month at the top.
    private func calendarPanel(fillsHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !layout.isWide {
                HStack {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.text)
                    Spacer()
                    monthButton(String(localized: "Previous month"), image: "chevron.left", offset: -1)
                    monthButton(String(localized: "Next month"), image: "chevron.right", offset: 1)
                    if layout == .phone {
                        viewModeButton(String(localized: "Week")) {
                            showsMonth = false
                            month = selectedDate
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            MonthCalendarGrid(month: month, calendar: calendar) { date in
                tile(for: date)
            }
            // Only the iPhone board carries a legend; the wide boards rely on the badges.
            if layout == .phone { legend }
        }
        .padding(.horizontal, layout == .splitView ? 10 : 12)
        .padding(.top, layout.isWide ? 12 : 16)
        .padding(.bottom, layout.isWide ? 12 : 14)
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
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

    private func monthButton(_ label: String, image: String, offset: Int) -> some View {
        let isEnabled = canShowMonth(offset: offset)
        return Button {
            month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
        } label: {
            Image(systemName: image)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(isEnabled ? palette.surface2 : palette.surface))
                .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                .contentShape(Rectangle())
                .foregroundStyle(isEnabled ? palette.text : palette.muted.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(offset < 0 ? "glass.archive.previousMonth" : "glass.archive.nextMonth")
    }

    /// ArchiveGlass's legend: each swatch draws its tile state (fill, accent underline,
    /// dashed coral outline, plain outline).
    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.complete) {
                RoundedRectangle(cornerRadius: 3).fill(palette.fill)
            }
            legendItem(.partial) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.partial)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.accent).frame(height: 3) }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            legendItem(.missing) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(palette.coral, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 1.5]))
            }
            legendItem(.notDue) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(palette.line, lineWidth: 1)
                    .opacity(0.6)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func legendItem<Swatch: View>(_ status: CoverageStatus, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 10, height: 10)
            Text(ArchiveCopy.title(for: status)).lineLimit(1)
        }
    }

    // MARK: - Day

    private var dayTitle: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var daySummary: String {
        let counts = ArchiveAggregation.onTrack(model.profileDays(on: selectedDate))
        return counts.due == 0
            ? String(localized: "Nothing due")
            : String(localized: "\(counts.onTrack) of \(counts.due) on track")
    }

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                if filter == nil {
                    Text(daySummary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.bottom, 6)

            ForEach(shownProfiles) { profile in
                dayRow(profile)
                    .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .glassSurface()
    }

    /// ArchiveGlass day row: name and badge, then the dated path, its note and the fix.
    private func dayRow(_ profile: ArchiveProfile) -> some View {
        let day = model.day(profile, on: selectedDate)
        let action = model.action(profile, day: day)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(palette.profileColor(at: profile.colorIndex))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(profile.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusBadge(title: ArchiveCopy.title(for: day.status), status: day.status)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.pathLine(profile, day: day))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.sec)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ArchiveCopy.note(for: day, profile: profile, calendar: calendar))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.leading, 18)
        }
        .padding(.vertical, 12)
    }

    /// The day as the Duo and iPad boards show it: name, badge and note, with one fix below.
    private func compactDayPanel(showsSummary: Bool, fillsHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dayTitle)
                .font(.system(size: layout == .pad ? 20 : (layout == .splitView ? 16 : 19), weight: .bold))
                .foregroundStyle(palette.text)
            if showsSummary && filter == nil {
                Text(daySummary)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 2)
            }
            Spacer().frame(height: showsSummary ? 8 : 4)
            ForEach(shownProfiles) { profile in
                compactDayRow(profile)
                    .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
            }
            if fillsHeight { Spacer(minLength: 10) }
            // DuoSplitViewG shows rows and badges only; the fix stays on the other layouts.
            if layout != .splitView, let primary = primaryDayAction {
                Button(String(localized: "\(ArchiveCopy.title(for: primary.action)) \(primary.profile.name)")) {
                    onAction(primary.profile, primary.action, selectedDate)
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, layout.isWide ? 16 : 16)
        .padding(.vertical, layout.isWide ? 16 : 12)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .glassSurface()
    }

    private func compactDayRow(_ profile: ArchiveProfile) -> some View {
        let day = model.day(profile, on: selectedDate)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.profileColor(at: profile.colorIndex))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(profile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusBadge(title: ArchiveCopy.title(for: day.status), status: day.status)
            }
            Text(ArchiveCopy.note(for: day, profile: profile, calendar: calendar))
                .font(.system(size: 13))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    /// The fix the wide boards put under the day: the first gap to close, or the
    /// selected automation's own action.
    private var primaryDayAction: (profile: ArchiveProfile, action: ArchiveAggregation.DayAction)? {
        let rows = shownProfiles.compactMap { profile -> (ArchiveProfile, ArchiveAggregation.DayRowAction)? in
            model.action(profile, day: model.day(profile, on: selectedDate)).map { (profile, $0) }
        }
        if let prominent = rows.first(where: { $0.1.isProminent }) { return (prominent.0, prominent.1.action) }
        if filter != nil, let only = rows.first { return (only.0, only.1.action) }
        return nil
    }

    // MARK: - Week (Archive B)

    private struct DayFileKey: Hashable {
        let profileID: UUID
        let date: Date
        let status: CoverageStatus
        let recordedAt: Date?
    }

    private var leadProfile: ArchiveProfile? { model.leadProfile(filter: filter) }

    /// What the readable day card should read: the lead automation's own file for
    /// the selected date, when it has one on this device.
    private var dayFileRequest: DayFileKey? {
        guard let lead = leadProfile else { return nil }
        let day = model.day(lead, on: selectedDate)
        guard day.status == .complete || day.status == .partial || day.status == .inProgress,
              model.canOpen(lead, on: selectedDate) else { return nil }
        return DayFileKey(profileID: lead.id, date: selectedDate, status: day.status, recordedAt: day.record?.updatedAt)
    }

    private func loadLeadFile() async {
        guard let request = dayFileRequest,
              let lead = model.profiles.first(where: { $0.id == request.profileID }) else {
            dayFile = nil
            dayFileKey = nil
            return
        }
        if dayFileKey != request { dayFile = nil }
        let file = await loadDayFile(lead, request.date)
        guard !Task.isCancelled else { return }
        dayFile = file
        dayFileKey = request
    }

    /// "Next run · Daily · tomorrow at 7:30", with the gap count.
    private var nextRunCard: some View {
        let stats = model.stats(month: month, filter: filter)
        let next = model.nextRun(filter: filter)
        return HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(palette.accent.opacity(0.30)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Next run")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.muted)
                Group {
                    if let next {
                        Text(verbatim: "\(next.profile.name) · \(ArchiveNextRun.whenText(next.date, now: model.now, calendar: calendar))")
                    } else {
                        Text("Nothing scheduled")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            gapButton(stats, weight: .semibold)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassSurface()
        .accessibilityIdentifier("glass.archive.nextRun")
    }

    private var weekDays: [Date] { model.week(containing: selectedDate) }

    private var weekTitle: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return (first..<last).formatted(.interval.month(.abbreviated).day())
    }

    private func canShowWeek(offset: Int) -> Bool {
        guard let target = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) else { return false }
        if offset > 0 {
            return calendar.compare(target, to: model.now, toGranularity: .weekOfYear) != .orderedDescending
        }
        guard let oldest = calendar.date(byAdding: .day, value: -CoverageLedger.retentionDays, to: model.now) else {
            return false
        }
        return calendar.compare(target, to: oldest, toGranularity: .weekOfYear) != .orderedAscending
    }

    /// Moves a week and keeps the same weekday selected, never past today.
    private func moveWeek(_ offset: Int) {
        guard let target = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) else { return }
        let today = calendar.startOfDay(for: model.now)
        select(min(calendar.startOfDay(for: target), today))
    }

    private func weekButton(_ label: String, image: String, offset: Int) -> some View {
        let isEnabled = canShowWeek(offset: offset)
        return Button { moveWeek(offset) } label: {
            Image(systemName: image)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(isEnabled ? palette.surface2 : palette.surface))
                .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                .contentShape(Rectangle())
                .foregroundStyle(isEnabled ? palette.text : palette.muted.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(offset < 0 ? "glass.archive.previousWeek" : "glass.archive.nextWeek")
    }

    /// The Month and Week switch beside the calendar's navigation.
    private func viewModeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.sec)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(palette.surface))
                .frame(minHeight: GlassMetrics.touchTarget)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("glass.archive.viewMode")
    }

    private var weekPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                Text(weekTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                weekButton(String(localized: "Previous week"), image: "chevron.left", offset: -1)
                weekButton(String(localized: "Next week"), image: "chevron.right", offset: 1)
                viewModeButton(String(localized: "Month")) {
                    month = selectedDate
                    showsMonth = true
                }
            }
            .padding(.horizontal, 6)
            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { date in
                    weekTile(for: date)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .glassSurface()
    }

    private func weekTile(for date: Date) -> some View {
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: model.now)
        let status: CoverageStatus = isFuture ? .notDue : model.status(on: date, filter: filter)
        let symbols = calendar.shortWeekdaySymbols
        let weekday = symbols[(calendar.component(.weekday, from: date) - 1) % symbols.count]
        return CalendarDayTile(
            day: calendar.component(.day, from: date),
            status: status,
            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
            weekdayLabel: weekday,
            accessibilityText: ArchiveCopy.tileAccessibility(
                date: date,
                status: status,
                model: model,
                showsIssues: filter == nil
            )
        ) {
            guard !isFuture else { return }
            select(calendar.startOfDay(for: date))
        }
    }

    /// Archive B's readable day: the lead automation's file with its headline values,
    /// a dashed card for a gap, then one line for every other automation.
    private var readableDayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lead = leadProfile {
                let day = model.day(lead, on: selectedDate)
                HStack(alignment: .firstTextBaseline) {
                    Text(dayTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.text)
                    Spacer()
                    StatusBadge(title: ArchiveCopy.title(for: day.status), status: day.status)
                }
                .padding(.horizontal, 2)
                leadDetail(lead, day: day)
                let others = model.profiles.filter { $0.id != lead.id && filter == nil }
                if !others.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(others) { otherRow($0) }
                    }
                }
            } else {
                Text(dayTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.text)
            }
        }
        .padding(16)
        .glassSurface()
        .accessibilityIdentifier("glass.archive.day")
    }

    @ViewBuilder
    private func leadDetail(_ lead: ArchiveProfile, day: CoverageDay) -> some View {
        let action = model.action(lead, day: day)
        if day.status == .missing {
            VStack(alignment: .leading, spacing: 12) {
                Text(ArchiveCopy.note(for: day, profile: lead, calendar: calendar))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(String(localized: "\(ArchiveCopy.title(for: action.action)) this day")) {
                        onAction(lead, action.action, selectedDate)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accentInk)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(palette.accent))
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .accessibilityIdentifier("glass.archive.day.fix")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(palette.coral, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: model.pathLine(lead, day: day))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.sec)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 2)
                let tiles = dayFileKey == dayFileRequest ? dayFile.map { ArchiveDayTiles.tiles(fromMarkdown: $0.source) } ?? [] : []
                if tiles.isEmpty {
                    HStack(spacing: 10) {
                        Text(ArchiveCopy.note(for: day, profile: lead, calendar: calendar))
                            .font(.system(size: 14))
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let action, action.action != .open {
                            Button(ArchiveCopy.title(for: action.action)) {
                                onAction(lead, action.action, selectedDate)
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
                    .padding(.horizontal, 2)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(tiles) { metricTile($0) }
                    }
                }
                if day.status != .notDue, day.status != .paused {
                    Button { onOpenDay(selectedDate, lead.id) } label: {
                        HStack(spacing: 8) {
                            Text(dayFile != nil && dayFileKey == dayFileRequest
                                ? String(localized: "Read the whole note")
                                : String(localized: "See this day"))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(palette.surface2))
                        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("glass.archive.day.read")
                }
            }
        }
    }

    private func metricTile(_ tile: ArchiveDayTile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: tile.value)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                if !tile.unit.isEmpty {
                    Text(verbatim: tile.unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(verbatim: tile.key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.edge, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(tile.label), \(tile.value) \(tile.unit)"))
    }

    /// One line per other automation; it opens the day page on that automation.
    private func otherRow(_ profile: ArchiveProfile) -> some View {
        let day = model.day(profile, on: selectedDate)
        return Button { onOpenDay(selectedDate, profile.id) } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(palette.profileColor(at: profile.colorIndex))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(profile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                // Wraps rather than cutting "Not due — covered by Sunday’s file." on a phone.
                Text(ArchiveCopy.note(for: day, profile: profile, calendar: calendar))
                    .font(.system(size: 13))
                    .foregroundStyle(day.status == .missing ? palette.coral : palette.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(profile.name), \(ArchiveCopy.title(for: day.status)), \(ArchiveCopy.note(for: day, profile: profile, calendar: calendar))"))
    }

    // MARK: - Sentence

    /// The automation's sentence, then "Paused since Oct 22." while it is paused.
    static func sentenceText(_ profile: ArchiveProfile) -> String {
        let sentence = profile.sentence ?? profile.destination
        guard profile.isPaused else { return sentence }
        guard let since = profile.pausedSince else { return sentence + " " + String(localized: "Paused.") }
        let date = since.formatted(.dateTime.month(.abbreviated).day())
        return sentence + " " + String(localized: "Paused since \(date).")
    }

    /// "Automations · Manage", or the selected automation's sentence with Edit.
    private var sentenceCard: some View {
        let paused = model.profiles.filter(\.isPaused).count
        let running = model.profiles.filter(\.isScheduled).count
        let profile = filteredProfile
        return Button {
            if let profile { onEditAutomation(profile) } else { onManageAutomations() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(profile.map { String(localized: "\($0.name) automation") }
                        ?? String(localized: "Automations"))
                        .foregroundStyle(palette.muted)
                    Spacer()
                    Text(profile == nil ? String(localized: "Manage") : String(localized: "Edit"))
                        .foregroundStyle(palette.accent)
                }
                .font(.system(size: 13, weight: .semibold))
                Group {
                    if let profile {
                        Text(verbatim: Self.sentenceText(profile))
                    } else if running + paused == 0 {
                        Text("Nothing runs on a schedule yet. Exports you run yourself still appear in the Archive.")
                    } else {
                        Text("\(running) running and \(paused) paused. “All” counts a day complete when every running automation that was due covered it.")
                    }
                }
                .font(.system(size: 17))
                .lineSpacing(4)
                .foregroundStyle(palette.sec)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .glassSurface()
            .contentShape(RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("glass.archive.sentence")
    }
}

/// iPadArchiveG's sidebar "Profiles" list. It picks the Archive filter, as the chips do.
struct ArchiveSidebarProfiles: View {
    let profiles: [ArchiveProfile]
    @Binding var filter: UUID?

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassSidebarHeading(title: String(localized: "Profiles"))
            GlassSidebarListRow(
                title: String(localized: "All"),
                dotColor: palette.text,
                isSelected: filter == nil
            ) { filter = nil }
            ForEach(profiles) { profile in
                GlassSidebarListRow(
                    title: profile.isPaused ? String(localized: "\(profile.name) · paused") : profile.name,
                    dotColor: palette.profileColor(at: profile.colorIndex),
                    isSelected: filter == profile.id
                ) { filter = profile.id }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("glass.sidebar.profiles")
    }
}

/// The 32 pt profile chip of the Duo boards.
private struct CompactArchiveChip: View {
    let title: String
    var dotColor: Color?
    var isSelected = false
    let action: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 7, height: 7).accessibilityHidden(true)
                }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? palette.accentInk : palette.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(isSelected ? palette.accent : palette.surface2))
            .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: GlassMetrics.touchTarget)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// EmptyArchiveG: shown until Health access and a destination exist.
struct EmptyArchiveCard: View {
    let setup: ArchiveSetupState
    let onConnectHealth: () -> Void
    let onChooseFolder: () -> Void
    let onBackfill: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Image("HealthCrystalHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("Your archive starts here")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.text)
                Text("Each day you export fills a square on the calendar. Two steps first:")
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(palette.sec)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .glassSurface()

            VStack(spacing: 0) {
                step(
                    String(localized: "Connect Apple Health"),
                    subtitle: String(localized: "Choose what Health.md may read"),
                    systemImage: "heart.fill",
                    tile: .glassHex(0xE5484D),
                    badge: setup.isHealthConnected ? .done : .next,
                    action: onConnectHealth
                )
                step(
                    String(localized: "Choose a folder"),
                    subtitle: String(localized: "Your Obsidian vault or any Files folder"),
                    systemImage: "folder.fill",
                    tile: .glassHex(0x6B3FE0),
                    badge: setup.isHealthConnected ? .next : nil,
                    showsDivider: true,
                    action: onChooseFolder
                )
                step(
                    String(localized: "Backfill history"),
                    subtitle: String(localized: "Optional — export past months in one go"),
                    systemImage: "bolt.fill",
                    tile: .glassHex(0x3D5BFF),
                    badge: nil,
                    showsDivider: true,
                    action: onBackfill
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .glassSurface()

            Button(
                setup.isHealthConnected
                    ? String(localized: "Choose folder")
                    : String(localized: "Connect Apple Health"),
                action: setup.isHealthConnected ? onChooseFolder : onConnectHealth
            )
            .buttonStyle(GlassPrimaryButtonStyle())
            .accessibilityIdentifier("glass.archive.setUp")
        }
    }

    private enum Badge { case done, next }

    private func step(
        _ title: String,
        subtitle: String,
        systemImage: String,
        tile: Color,
        badge: Badge?,
        showsDivider: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: GlassMetrics.iconTileRadius, style: .continuous).fill(tile))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16)).foregroundStyle(palette.text)
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let badge {
                    Text(badge == .done ? String(localized: "Done") : String(localized: "Next"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(badge == .done ? palette.ok : palette.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(palette.surface2))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .frame(minHeight: GlassMetrics.rowWithSubtitleMinHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if showsDivider { Rectangle().fill(palette.line).frame(height: 1) }
            }
        }
        .buttonStyle(.plain)
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
                    if items.isEmpty {
                        VStack(spacing: 10) {
                            Image("HealthCrystalHeart")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .accessibilityHidden(true)
                            Text("Nothing needs attention")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("Health.md will list problems here, each with its fix.")
                                .font(.system(size: 14))
                                .foregroundStyle(palette.sec)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
                    }
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
                                    .lineSpacing(3)
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
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(palette.bg.ignoresSafeArea())
            // AttentionG: the title alone; the sheet closes by its drag indicator.
            .navigationTitle(String(localized: "Needs attention"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}

/// Lays out its single child at its natural height, or at `minHeight` when that is
/// taller, proposing the final height so flexible children (`maxHeight: .infinity`)
/// stretch to it. Inside a scroll view this fills the visible area without capping
/// content that needs more room.
struct FillVisibleHeightLayout: Layout {
    var minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: max(natural.height, minHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
#endif
