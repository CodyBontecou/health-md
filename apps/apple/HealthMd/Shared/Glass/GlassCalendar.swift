import SwiftUI

struct IssueDotsView: View {
    struct Dot: Identifiable {
        let id: UUID
        let color: Color
        let isFilled: Bool
    }

    let dots: [Dot]
    let hasOverflow: Bool
    var overflowColor: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(dots) { dot in
                Circle()
                    .fill(dot.isFilled ? dot.color : Color.clear)
                    .overlay {
                        if !dot.isFilled { Circle().strokeBorder(dot.color, lineWidth: 1.5) }
                    }
                    .frame(width: GlassMetrics.issueDotSize, height: GlassMetrics.issueDotSize)
            }
            if hasOverflow {
                Text(verbatim: "+")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(overflowColor)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One calendar day. The caller supplies the VoiceOver label, because it carries
/// localized month and per-profile issue text.
struct CalendarDayTile: View {
    let day: Int
    let status: CoverageStatus
    var isSelected = false
    var dots: [IssueDotsView.Dot] = []
    var hasOverflow = false
    let accessibilityText: String
    let action: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: GlassMetrics.calendarTileRadius, style: .continuous)
    }

    private var breathes: Bool { status == .inProgress && !isSelected && !reduceMotion }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(verbatim: "\(day)")
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                    .monospacedDigit()
                if !dots.isEmpty {
                    IssueDotsView(dots: dots, hasOverflow: hasOverflow, overflowColor: palette.muted)
                }
            }
            .foregroundStyle(numberColor)
            .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
            .background(background)
            .overlay(alignment: .bottom) { partialBar }
            .clipShape(shape)
            .overlay(border)
            .opacity(status == .notDue || status == .paused ? 0.4 : 1)
            .overlay {
                if isSelected {
                    shape.inset(by: -2).strokeBorder(palette.bg, lineWidth: 2)
                    shape.inset(by: -4).strokeBorder(palette.text, lineWidth: 2)
                }
            }
            .opacity(isBreathing ? 0.55 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear(perform: updateBreathing)
        .onChange(of: breathes) { _, _ in updateBreathing() }
    }

    private func updateBreathing() {
        guard breathes else {
            isBreathing = false
            return
        }
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }

    private var numberColor: Color {
        switch status {
        case .missing: return palette.coral
        case .complete: return palette.fillText
        default: return palette.text
        }
    }

    @ViewBuilder private var background: some View {
        switch status {
        case .complete:
            palette.fill.overlay(alignment: .top) {
                Color.glassWhite(0.22).frame(height: 1)
            }
        case .partial:
            palette.partial
        case .paused:
            PausedHatch(color: palette.line)
        default:
            Color.clear
        }
    }

    @ViewBuilder private var partialBar: some View {
        if status == .partial {
            palette.accent.frame(height: 3)
        }
    }

    @ViewBuilder private var border: some View {
        switch status {
        case .missing:
            shape.strokeBorder(palette.coral, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        case .inProgress:
            shape.strokeBorder(palette.accent, lineWidth: 2)
        default:
            shape.strokeBorder(palette.line, lineWidth: 1)
        }
    }
}

/// The 135° hatch on paused days: 2 pt stripes every 7 pt.
private struct PausedHatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7 * 2.squareRoot()
            }
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
    }
}

/// Seven-column month layout. It places days and leaves their content to the caller.
struct MonthCalendarGrid<Tile: View>: View {
    let month: Date
    var calendar: Calendar = .current
    @ViewBuilder let tile: (Date) -> Tile

    @Environment(\.glassPalette) private var palette

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Self.weekdaySymbols(calendar: calendar).indices, id: \.self) { index in
                Text(Self.weekdaySymbols(calendar: calendar)[index])
                    .glassFont(.caption)
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            ForEach(Self.cells(month: month, calendar: calendar).indices, id: \.self) { index in
                if let date = Self.cells(month: month, calendar: calendar)[index] {
                    tile(date)
                } else {
                    Color.clear.frame(height: 1).accessibilityHidden(true)
                }
            }
        }
    }

    /// Leading blanks, then each day of the month, honouring the locale's first weekday.
    static func cells(month: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else {
            return []
        }
        let weekday = calendar.component(.weekday, from: interval.start)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        let days: [Date?] = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: blanks) + days
    }

    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
