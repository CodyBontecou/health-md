#if os(iOS)
import SwiftUI

/// What the running moment shows, derived from the export's progress callback. Pure.
struct ExportMomentProgress: Equatable {
    /// Days already written.
    let completed: Int
    let total: Int
    /// The day being written, when known.
    let currentDay: Date?

    /// The local exporter reports "Exporting yyyy-MM-dd... (done/total)". Other targets
    /// only report a fraction, so the counter falls back to the selected range.
    static func make(
        message: String,
        progress: Double,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> ExportMomentProgress {
        if let parsed = parse(message) {
            return ExportMomentProgress(completed: parsed.done, total: parsed.total, currentDay: parsed.day)
        }
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let total = max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)
        let done = min(total, max(0, Int((min(max(progress, 0), 1) * Double(total)).rounded(.down))))
        let current = done < total ? calendar.date(byAdding: .day, value: done, to: first) : nil
        return ExportMomentProgress(completed: done, total: total, currentDay: current)
    }

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    private static func parse(_ message: String) -> (day: Date?, done: Int, total: Int)? {
        guard message.hasPrefix("Exporting "),
              let open = message.lastIndex(of: "("),
              let close = message.lastIndex(of: ")"),
              open < close else { return nil }
        let counts = message[message.index(after: open)..<close].split(separator: "/")
        guard counts.count == 2, let done = Int(counts[0]), let total = Int(counts[1]), total > 0 else { return nil }
        let dayText = message.dropFirst("Exporting ".count).prefix(10)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.date(from: String(dayText)), done, total)
    }
}

/// The done line under the crystal: "Oct 24 – 30 · 14 files · daily notes updated".
enum ExportMomentSummary {
    static func title(_ entry: ExportHistoryEntry) -> String {
        entry.successCount == 1
            ? String(localized: "1 day written")
            : String(localized: "\(entry.successCount) days written")
    }

    static func subtitle(_ entry: ExportHistoryEntry) -> String {
        var parts = [rangeText(entry.dateRangeStart, entry.dateRangeEnd)]
        if let files = entry.fileCount {
            parts.append(files == 1 ? String(localized: "1 file") : String(localized: "\(files) files"))
        }
        if entry.dailyNoteUpdateCount > 0 {
            parts.append(String(localized: "daily notes updated"))
        }
        return parts.joined(separator: " · ")
    }

    static func rangeText(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.month(.abbreviated).day())
        }
        let lower = min(start, end)
        let upper = max(start, end)
        return (lower..<upper).formatted(.interval.month(.abbreviated).day())
    }
}

/// The crystal heart from MomentGlass: ten facets light up as days are written.
struct CrystalFacets: View {
    /// 0…10 facets filled.
    let filled: Int

    private static let facets: [[CGPoint]] = [
        [CGPoint(x: 45, y: 55), CGPoint(x: 60, y: 20), CGPoint(x: 95, y: 55)],
        [CGPoint(x: 60, y: 20), CGPoint(x: 95, y: 8), CGPoint(x: 95, y: 55)],
        [CGPoint(x: 95, y: 8), CGPoint(x: 120, y: 30), CGPoint(x: 95, y: 55)],
        [CGPoint(x: 95, y: 55), CGPoint(x: 120, y: 30), CGPoint(x: 145, y: 55)],
        [CGPoint(x: 120, y: 30), CGPoint(x: 145, y: 8), CGPoint(x: 145, y: 55)],
        [CGPoint(x: 145, y: 8), CGPoint(x: 180, y: 20), CGPoint(x: 145, y: 55)],
        [CGPoint(x: 180, y: 20), CGPoint(x: 195, y: 55), CGPoint(x: 145, y: 55)],
        [CGPoint(x: 45, y: 55), CGPoint(x: 95, y: 55), CGPoint(x: 120, y: 150)],
        [CGPoint(x: 95, y: 55), CGPoint(x: 145, y: 55), CGPoint(x: 120, y: 150)],
        [CGPoint(x: 145, y: 55), CGPoint(x: 195, y: 55), CGPoint(x: 120, y: 150)]
    ]

    private static let colors: [Color] = [
        0x8B6BE8, 0xB9A0FF, 0xE6DCFF, 0x9F82F0, 0xF4EFFF, 0xFFFFFF, 0xC7B2FF, 0x5A3FB0, 0x7A5BD6, 0x3F2B86
    ].map { hex in
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    var body: some View {
        // The board's viewBox is 40 4 160 150.
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 160, geometry.size.height / 150)
            let offset = CGPoint(
                x: (geometry.size.width - 160 * scale) / 2 - 40 * scale,
                y: (geometry.size.height - 150 * scale) / 2 - 4 * scale
            )
            ZStack {
                ForEach(Self.facets.indices, id: \.self) { index in
                    let path = Path { path in
                        let points = Self.facets[index].map {
                            CGPoint(x: $0.x * scale + offset.x, y: $0.y * scale + offset.y)
                        }
                        path.addLines(points)
                        path.closeSubpath()
                    }
                    let isOn = index < filled
                    path.fill(isOn ? Self.colors[index] : Color.white)
                        .opacity(isOn ? 0.92 : 0.06)
                    path.stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 0.8 * scale, lineJoin: .round))
                }
            }
        }
        .aspectRatio(270 / 220, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Crystal heart filling as days are written"))
    }
}

/// MomentGlass: covers the app while an interactive export runs, then says what it wrote.
struct ExportMomentView: View {
    enum Phase: Equatable {
        case running(ExportMomentProgress)
        case done(title: String, subtitle: String)
    }

    let phase: Phase
    let onCancel: () -> Void
    let onSeeArchive: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = 0
    @State private var replay: Task<Void, Never>?

    private var targetFill: Int {
        switch phase {
        case .running(let progress): return min(10, Int((progress.fraction * 10).rounded(.down)))
        case .done: return 10
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CrystalFacets(filled: filled)
                .frame(maxWidth: 270, maxHeight: 220)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
                .padding(.horizontal, 20)
            card
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.bottom, 34)
        }
        .background(palette.bg.ignoresSafeArea())
        .onAppear { filled = targetFill }
        .onChange(of: targetFill) { _, value in
            replay?.cancel()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { filled = value }
        }
        .onDisappear { replay?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("glass.exportMoment")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                if case .running(let progress) = phase {
                    Text(verbatim: "\(progress.completed) / \(progress.total)")
                        .font(.system(size: 15, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.sec)
                        .accessibilityLabel(String(localized: "\(progress.completed) of \(progress.total) days"))
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule().fill(palette.accent).frame(width: geometry.size.width * barFraction)
                }
            }
            .frame(height: 6)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: barFraction)
            .accessibilityHidden(true)
            Text(subline)
                .font(.system(size: 14))
                .foregroundStyle(palette.muted)
            switch phase {
            case .running:
                Button(action: onCancel) {
                    Text(String(localized: "Cancel"))
                        .font(.system(size: 16))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(palette.surface2))
                        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("glass.exportMoment.cancel")
            case .done:
                HStack(spacing: 8) {
                    Button(String(localized: "See in archive"), action: onSeeArchive)
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .accessibilityIdentifier("glass.exportMoment.archive")
                    Button(action: replayFacets) {
                        Text(String(localized: "Replay"))
                            .font(.system(size: 15))
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 50)
                            .background(Capsule().fill(palette.surface2))
                            .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Plays the crystal animation again"))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .glassSurface(cornerRadius: 32)
    }

    private var barFraction: CGFloat {
        switch phase {
        case .running(let progress): return CGFloat(progress.fraction)
        case .done: return CGFloat(filled) / 10
        }
    }

    private var headline: String {
        switch phase {
        case .running(let progress):
            guard let day = progress.currentDay else { return String(localized: "Exporting…") }
            return String(localized: "Writing \(day.formatted(.dateTime.month(.abbreviated).day()))…")
        case .done(let title, _):
            return title
        }
    }

    private var subline: String {
        switch phase {
        case .running: return String(localized: "Keep Health.md open until it finishes.")
        case .done(_, let subtitle): return subtitle
        }
    }

    /// Board behaviour: refill the facets. Reduce Motion shows the filled heart at once.
    private func replayFacets() {
        replay?.cancel()
        guard !reduceMotion else {
            filled = 10
            return
        }
        filled = 0
        replay = Task { @MainActor in
            for step in 1...10 {
                try? await Task.sleep(for: .milliseconds(380))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { filled = step }
            }
        }
    }
}

/// ExportResultG: which days were written, with a retry for exactly the failed ones.
struct ExportResultDays {
    enum Row: Equatable, Identifiable {
        case complete(start: Date, end: Date)
        case failed(date: Date, reason: String)

        var id: Date {
            switch self {
            case .complete(_, let end): return end
            case .failed(let date, _): return date
            }
        }
    }

    /// Newest first. Runs of three or more complete days collapse into one range row;
    /// shorter runs list each day.
    static func rows(
        start: Date,
        end: Date,
        failed: [(date: Date, reason: String)],
        calendar: Calendar
    ) -> [Row] {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        var failures: [Date: String] = [:]
        for failure in failed { failures[calendar.startOfDay(for: failure.date)] = failure.reason }
        var rows: [Row] = []
        var run: [Date] = []
        func closeRun() {
            if run.count >= 3, let newest = run.first, let oldest = run.last {
                rows.append(.complete(start: oldest, end: newest))
            } else {
                rows.append(contentsOf: run.map { .complete(start: $0, end: $0) })
            }
            run = []
        }
        var day = last
        while day >= first {
            if let reason = failures[day] {
                closeRun()
                rows.append(.failed(date: day, reason: reason))
            } else {
                run.append(day)
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        closeRun()
        return rows
    }
}

/// ExportResultG, shown when a run did not fully succeed. For a local export each written
/// day links to its file in the viewer, and a collapsed range to the export folder.
struct ExportResultScreen: View {
    let entry: ExportHistoryEntry
    let onRetry: (Date, Date) -> Void
    var onShowInFiles: (() -> Void)?
    /// Finds a written day's file. Nil when the export has no local files to open.
    var dayFile: ((Date) -> ExportPresentationTarget?)?

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var openedFile: ExportedMarkdownPresentation?
    /// The failed day whose explanation is open.
    @State private var explainedFailure: FailedDateDetail?

    private var calendar: Calendar { .current }

    private var failedDates: [Date] {
        entry.failedDateDetails.map { calendar.startOfDay(for: $0.date) }.sorted()
    }

    private var rows: [ExportResultDays.Row] {
        ExportResultDays.rows(
            start: entry.dateRangeStart,
            end: entry.dateRangeEnd,
            failed: entry.failedDateDetails.map { ($0.date, $0.reason.shortDescription) },
            calendar: calendar
        )
    }

    private func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var retryRangeText: String? {
        guard let first = failedDates.first, let last = failedDates.last else { return nil }
        return ExportMomentSummary.rangeText(first, last, calendar: calendar)
    }

    private var subtitle: String {
        var parts = [ExportMomentSummary.rangeText(entry.dateRangeStart, entry.dateRangeEnd, calendar: calendar)]
        if let profile = entry.profileName, !profile.isEmpty { parts.append(profile) }
        if let files = entry.fileCount {
            parts.append(files == 1 ? String(localized: "1 file") : String(localized: "\(files) files"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // ExportResultG has no header buttons: the sheet closes by its drag indicator.
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "\(entry.successCount) of \(entry.totalCount) days written"))
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(palette.text)
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(palette.muted)
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 6) {
                    GlassSectionLabel(title: String(localized: "Days")).padding(.horizontal, 20)
                    GlassPanel {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, 16) }
                            dayRow(row)
                        }
                    }
                }

                if let range = retryRangeText {
                    GlassBanner(
                        title: failedDates.count == 1
                            ? String(localized: "Completed dates stay completed. Retry writes only \(range).")
                            : String(localized: "Completed dates stay completed. Retry writes \(range)."),
                        systemImage: "info.circle",
                        tone: .info
                    )
                }
                if let suggestion = entry.failureRecoverySuggestion {
                    GlassBanner(title: suggestion, systemImage: "lightbulb", tone: .info)
                }
            }
            .padding(GlassMetrics.screenMargin)
        }
        .safeAreaInset(edge: .bottom) { actions }
        .background(palette.bg.ignoresSafeArea())
        .glassSheet(palette: palette)
        .presentationDragIndicator(.visible)
        .sheet(item: $openedFile) { ExportedMarkdownViewer(target: $0.target) }
        .alert(
            explainedFailure.map { dayText($0.date) } ?? "",
            isPresented: Binding(get: { explainedFailure != nil }, set: { if !$0 { explainedFailure = nil } }),
            presenting: explainedFailure
        ) { failure in
            Button(String(localized: "Retry \(dayText(failure.date))")) {
                let day = calendar.startOfDay(for: failure.date)
                dismiss()
                onRetry(day, day)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { failure in
            Text(verbatim: "\(failure.detailedMessage)\n\n\(failure.reason.recoverySuggestion)")
        }
    }

    @ViewBuilder private func dayRow(_ row: ExportResultDays.Row) -> some View {
        switch row {
        case .complete(let start, let end):
            let title = ExportMomentSummary.rangeText(start, end, calendar: calendar)
            if let open = openAction(start: start, end: end) {
                Button(action: open) {
                    GlassRow(title: title) {
                        StatusBadge(title: String(localized: "Complete"), status: .complete)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.muted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
                .accessibilityIdentifier("glass.exportResult.day")
            } else {
                GlassRow(title: title) {
                    StatusBadge(title: String(localized: "Complete"), status: .complete)
                }
            }
        case .failed(let date, let reason):
            // Nothing was written for a failed day, so its link explains the failure
            // and offers a retry of that day alone.
            Button {
                explainedFailure = entry.failedDateDetails.first { calendar.isDate($0.date, inSameDayAs: date) }
            } label: {
                GlassRow(title: dayText(date), subtitle: reason) {
                    StatusBadge(title: String(localized: "Failed"), status: .missing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isLink)
            .accessibilityIdentifier("glass.exportResult.failedDay")
        }
    }

    /// One day opens its file in the viewer; a range, or a day whose file can't be found
    /// (a custom filename without the date), opens the export folder.
    private func openAction(start: Date, end: Date) -> (() -> Void)? {
        guard let dayFile else { return nil }
        var showFolder: (() -> Void)?
        if let onShowInFiles {
            showFolder = {
                dismiss()
                onShowInFiles()
            }
        }
        guard calendar.isDate(start, inSameDayAs: end) else { return showFolder }
        return {
            if let target = dayFile(end) {
                openedFile = ExportedMarkdownPresentation(target: target)
            } else {
                showFolder?()
            }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            if let first = failedDates.first, let last = failedDates.last, let range = retryRangeText {
                Button(String(localized: "Retry \(range)")) {
                    dismiss()
                    onRetry(first, last)
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .accessibilityIdentifier("glass.exportResult.retry")
            }
            if let onShowInFiles {
                Button {
                    dismiss()
                    onShowInFiles()
                } label: {
                    Text(String(localized: "Show in Files"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.primaryButtonHeight)
                        .background(Capsule().fill(palette.surface2))
                        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, GlassMetrics.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(palette.bg.opacity(0.9))
    }
}
#endif
