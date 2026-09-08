#if os(iOS)
import SwiftUI

/// Inclusive local calendar days. Calendar arithmetic preserves days across DST.
struct InsightDateRange: Hashable, Identifiable {
    static let maximumDays = 90
    let end: Date
    let dayCount: Int
    let calendar: Calendar
    var id: Self { self }
    var start: Date { calendar.date(byAdding: .day, value: 1 - dayCount, to: end)! }
    var dates: [Date] {
        (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    init(ending end: Date = .now, days: Int = 7, now: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        self.end = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now))
        self.dayCount = min(Self.maximumDays, max(1, days))
    }

    var label: String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        if dayCount == 1 { return start.formatted(style) }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        var startStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()
        startStyle.calendar = calendar
        startStyle.timeZone = calendar.timeZone
        return "\(start.formatted(sameYear ? startStyle : style)) – \(end.formatted(style))"
    }

    func shifted(by periods: Int, now: Date = .now) -> Self {
        Self(ending: calendar.date(byAdding: .day, value: periods * dayCount, to: end)!,
             days: dayCount, now: now, calendar: calendar)
    }
}

struct InsightDateSelection: Equatable {
    enum Period: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days", custom = "Custom"
        var id: Self { self }
    }
    var period: Period = .week
    /// nil follows today, including when the app returns from the background.
    var end: Date?
    var customDayCount = 7

    func range(now: Date = .now, calendar: Calendar = .current) -> InsightDateRange {
        InsightDateRange(ending: end ?? now, days: period == .week ? 7 : period == .month ? 30 : customDayCount,
                         now: now, calendar: calendar)
    }

    mutating func rebase(from oldCalendar: Calendar, to newCalendar: Calendar) {
        guard let end, oldCalendar != newCalendar else { return }
        // An explicitly chosen day stays that calendar day when the time zone changes.
        self.end = oldCalendar.identifier == newCalendar.identifier
            ? newCalendar.date(from: oldCalendar.dateComponents([.era, .year, .month, .day], from: end))
            : newCalendar.startOfDay(for: end)
    }

    mutating func apply(_ range: InsightDateRange) {
        period = .custom
        end = range.end
        customDayCount = range.dayCount
    }
}

struct InsightDateControls: View {
    @Binding var selection: InsightDateSelection
    let range: InsightDateRange
    let now: Date
    @State private var editingRange: InsightDateRange?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var isLatest: Bool { range.calendar.isDate(range.end, inSameDayAs: now) }

    var body: some View {
        VStack(spacing: 10) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 4))
            layout {
                ForEach(InsightDateSelection.Period.allCases) { period in
                    Button {
                        if period == .custom { editingRange = range }
                        else { selection.period = period }
                    } label: {
                        Text(period.rawValue)
                            .font(.subheadline.weight(selection.period == period ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selection.period == period ? Color(uiColor: .secondarySystemGroupedBackground) : .clear,
                                        in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.period == period ? .isSelected : [])
                    .accessibilityIdentifier("home.dates.\(period)")
                }
            }
            .padding(4)
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 26))

            HStack(spacing: 4) {
                Button { selection.end = range.shifted(by: -1, now: now).end } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous \(range.dayCount) days")
                .accessibilityIdentifier("home.dates.previous")
                Button { editingRange = range } label: {
                    VStack(spacing: 4) {
                        Text(range.label).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text("Change dates")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 4)
                }
                .accessibilityLabel("Visualization dates")
                .accessibilityValue(range.label)
                .accessibilityHint("Choose start and end dates for all charts")
                .accessibilityIdentifier("home.dates.range")
                Button {
                    let next = range.shifted(by: 1, now: now)
                    selection.end = range.calendar.isDate(next.end, inSameDayAs: now) ? nil : next.end
                } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(isLatest)
                .accessibilityLabel("Next \(range.dayCount) days")
                .accessibilityIdentifier("home.dates.next")
            }
            .buttonStyle(.plain)
            if !isLatest {
                Button("Back to latest") { selection.end = nil }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("home.dates.latest")
            }
        }
        .sheet(item: $editingRange) { range in
            InsightDateRangeEditor(range: range, selection: $selection, now: now, onClose: { editingRange = nil })
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.dates")
    }
}

private struct InsightDateRangeEditor: View {
    @Binding var selection: InsightDateSelection
    let now: Date
    let calendar: Calendar
    @State private var start: Date
    @State private var end: Date
    let onClose: () -> Void
    private var dayCount: Int { (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }
    private var valid: Bool { (1...InsightDateRange.maximumDays).contains(dayCount) }

    init(range: InsightDateRange, selection: Binding<InsightDateSelection>, now: Date, onClose: @escaping () -> Void) {
        _selection = selection
        self.now = now
        self.onClose = onClose
        calendar = range.calendar
        _start = State(initialValue: range.start)
        _end = State(initialValue: range.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start date", selection: $start, in: ...end, displayedComponents: .date)
                        .accessibilityIdentifier("home.dates.start")
                    DatePicker("End date", selection: $end, in: start...max(start, now), displayedComponents: .date)
                        .accessibilityIdentifier("home.dates.end")
                } header: {
                    Text("Date range")
                } footer: {
                    Text("Choose up to 90 days. All health charts and export activity follow these dates.")
                }
                Section {
                    Label("\(dayCount) \(dayCount == 1 ? "day" : "days") selected",
                          systemImage: valid ? "calendar" : "exclamationmark.circle")
                        .foregroundStyle(valid ? Color.secondary : .orange)
                        .accessibilityIdentifier("home.dates.count")
                    if !valid { Text("Choose a shorter range to view up to 90 days at a time.").font(.subheadline) }
                }
            }
            .navigationTitle("Chart dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose).accessibilityIdentifier("home.dates.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        selection.apply(InsightDateRange(ending: end, days: dayCount, now: now, calendar: calendar))
                        onClose()
                    }
                    .disabled(!valid)
                    .accessibilityIdentifier("home.dates.apply")
                }
            }
        }
    }
}
#endif
