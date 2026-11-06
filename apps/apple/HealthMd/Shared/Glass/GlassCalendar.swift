import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Calendar sizing per board. Phone windows (ArchiveGlass, split view, folded) keep the
/// 44 pt standard; a regular-width phone (DuoInnerArchiveG) uses 56 pt tiles and iPad at
/// regular width (iPadArchiveG) 64 pt tiles with the day number in the top corner.
enum CalendarDensity: Equatable {
    case standard
    /// DuoOuterG: the folded outer display's compact month (36 pt tiles).
    case folded
    case wide
    case pad

    /// Mirrors `GlassWindowClass`: regular width is `.pad` on iPad and `.unfolded` on a phone.
    static func resolve(isPad: Bool, isRegularWidth: Bool) -> CalendarDensity {
        guard isRegularWidth else { return .standard }
        return isPad ? .pad : .wide
    }

    var tileHeight: CGFloat {
        switch self {
        case .standard: return GlassMetrics.touchTarget
        case .folded: return 36
        case .wide: return 56
        case .pad: return 64
        }
    }

    var tileRadius: CGFloat {
        switch self {
        case .standard: return GlassMetrics.calendarTileRadius
        case .folded, .wide: return 11
        case .pad: return 14
        }
    }

    var dayFontSize: CGFloat {
        switch self {
        case .pad: return 15
        case .folded: return 12
        case .standard, .wide: return 14
        }
    }

    var gridSpacing: CGFloat {
        switch self {
        case .standard: return 6
        case .folded, .wide: return 5
        case .pad: return 8
        }
    }

    /// iPad spells weekdays ("Sun"); narrower layouts use initials ("S").
    var usesShortWeekdaySymbols: Bool { self == .pad }

    /// Day number placement: centered, or top-trailing with 8 pt insets on iPad.
    var numberAlignment: Alignment { self == .pad ? .topTrailing : .center }
}

private struct CalendarDensityOverrideKey: EnvironmentKey {
    static let defaultValue: CalendarDensity? = nil
}

extension EnvironmentValues {
    /// A layout that knows its board's density (the folded Duo display) sets it here.
    var calendarDensityOverride: CalendarDensity? {
        get { self[CalendarDensityOverrideKey.self] }
        set { self[CalendarDensityOverrideKey.self] = newValue }
    }
}

/// Resolves `CalendarDensity` from the window's size class and device idiom.
private struct CalendarDensityReader: DynamicProperty {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.calendarDensityOverride) private var override

    var density: CalendarDensity {
        if let override { return override }
        #if os(iOS)
        return CalendarDensity.resolve(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            isRegularWidth: horizontalSizeClass == .regular
        )
        #else
        return .standard
        #endif
    }
}

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
    /// Archive B's week strip: the weekday above a larger number on a 60 pt tile.
    var weekdayLabel: String?
    let accessibilityText: String
    let action: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    private var densityReader = CalendarDensityReader()

    private var density: CalendarDensity { densityReader.density }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: weekdayLabel == nil ? density.tileRadius : 14, style: .continuous)
    }

    private var tileHeight: CGFloat { weekdayLabel == nil ? density.tileHeight : 60 }

    private var breathes: Bool { status == .inProgress && !isSelected && !reduceMotion }

    var body: some View {
        Button(action: action) {
            content
            .foregroundStyle(numberColor)
            .frame(maxWidth: .infinity, minHeight: tileHeight)
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
        .accessibilityIdentifier("glass.calendar.day.\(day)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear(perform: updateBreathing)
        .onChange(of: breathes) { _, _ in updateBreathing() }
    }

    @ViewBuilder private var content: some View {
        let number = Text(verbatim: "\(day)")
            .font(.system(size: density.dayFontSize, weight: isSelected ? .bold : .semibold))
            .monospacedDigit()
        let issueDots = IssueDotsView(dots: dots, hasOverflow: hasOverflow, overflowColor: palette.muted)
        if let weekdayLabel {
            VStack(spacing: 3) {
                Text(weekdayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.75)
                Text(verbatim: "\(day)")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                if !dots.isEmpty { issueDots }
            }
        } else if density == .pad {
            // iPadArchiveG: the number sits in the top corner; issue dots along the bottom.
            number
                .frame(maxWidth: .infinity, minHeight: density.tileHeight - 16, alignment: density.numberAlignment)
                .overlay(alignment: .bottomLeading) {
                    if !dots.isEmpty { issueDots }
                }
                .padding(8)
        } else {
            VStack(spacing: 4) {
                number
                if !dots.isEmpty { issueDots }
            }
        }
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
    private var densityReader = CalendarDensityReader()

    var body: some View {
        let density = densityReader.density
        let symbols = Self.weekdaySymbols(calendar: calendar, short: density.usesShortWeekdaySymbols)
        let spacing = density.gridSpacing
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7),
            spacing: spacing
        ) {
            ForEach(symbols.indices, id: \.self) { index in
                weekdayHeader(symbols[index], density: density)
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

    @ViewBuilder private func weekdayHeader(_ symbol: String, density: CalendarDensity) -> some View {
        let header = Text(symbol).foregroundStyle(palette.muted).accessibilityHidden(true)
        switch density {
        case .standard: header.glassFont(.caption)
        case .folded, .wide: header.font(.system(size: 11, weight: .semibold))
        case .pad: header.font(.system(size: 12, weight: .semibold))
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

    static func weekdaySymbols(calendar: Calendar, short: Bool = false) -> [String] {
        let symbols = short
            ? calendar.shortStandaloneWeekdaySymbols
            : calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
