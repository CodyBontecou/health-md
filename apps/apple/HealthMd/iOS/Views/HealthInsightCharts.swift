#if os(iOS)
import SwiftUI
import Charts

struct InsightStatistics {
    let values: [Double]
    init(days: [HealthInsightDay], metric: HealthInsightMetric) {
        values = days.compactMap { $0.values[metric] }.filter { $0.isFinite && $0 >= 0 }
    }
    var average: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    var range: ClosedRange<Double>? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }
}

// Stable categorical identities keep every day distinct without DST spacing artifacts.
func insightDayKey(_ date: Date) -> String { String(date.timeIntervalSinceReferenceDate) }
func insightAxisLabel(_ date: Date, dayCount: Int) -> String {
    dayCount <= 7 ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.month(.abbreviated).day())
}
func insightAxisKeys(_ dates: [Date], compact: Bool) -> [String] {
    let maximumLabels = compact ? 3 : dates.count <= 7 ? 7 : 4
    let count = min(maximumLabels, dates.count)
    guard count > 1 else { return dates.map(insightDayKey) }
    return (0..<count).map { index in
        let offset = Int((Double(index) * Double(dates.count - 1) / Double(count - 1)).rounded())
        return insightDayKey(dates[offset])
    }
}

struct InsightCardHeading: View {
    let title: String
    let symbol: String
    let color: Color
    let dayCount: Int
    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(dayCount) \(dayCount == 1 ? "day" : "days")").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct InsightReading: View {
    let metric: HealthInsightMetric
    let day: HealthInsightDay?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { reading }
                VStack(alignment: .leading, spacing: 1) { reading }
            }
            if let day {
                Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.health.\(metric.rawValue).value")
    }
    @ViewBuilder private var reading: some View {
        Text(day?.values[metric].map(metric.formatted) ?? "No reading")
            .font(.largeTitle.bold()).monospacedDigit().contentTransition(.numericText())
        if day?.values[metric] != nil, metric != .sleep {
            Text(metric.unit).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Shared chart interactions keep a selected day visible, including a missing day.
struct InsightDayChart: View {
    let metric: HealthInsightMetric
    let days: [HealthInsightDay]
    @Binding var selection: String?
    var line = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var statistics: InsightStatistics { InsightStatistics(days: days, metric: metric) }
    private var selectedDate: Date? {
        selection.flatMap { label in days.first { insightDayKey($0.date) == label }?.date }
            ?? days.last { $0.values[metric] != nil }?.date
    }
    private var yDomain: ClosedRange<Double> {
        let range = statistics.range ?? 0...1
        if line {
            let padding = max(metric == .respiratoryRate ? 0.5 : 3, (range.upperBound - range.lowerBound) * 0.25)
            return max(0, range.lowerBound - padding)...max(1, range.upperBound + padding)
        }
        let step = pow(10, floor(log10(max(1, range.upperBound)))) / 2
        return 0...max(1, ceil(range.upperBound * 1.05 / step) * step)
    }
    var body: some View {
        Chart {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if let value = day.values[metric] {
                    if line {
                        LineMark(x: .value("Day", insightDayKey(day.date)), y: .value(metric.unit, value),
                                 series: .value("Recorded days", segment(index)))
                            .foregroundStyle(metric.color).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Day", insightDayKey(day.date)), y: .value(metric.unit, value))
                            .foregroundStyle(metric.color)
                            .symbolSize(day.date == selectedDate ? 60 : days.count > 30 ? 6 : 18)
                            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                    } else {
                        BarMark(x: .value("Day", insightDayKey(day.date)), y: .value(metric.unit, value), width: .ratio(0.6))
                            .cornerRadius(5)
                            .foregroundStyle(LinearGradient(colors: [metric.color.opacity(day.date == selectedDate ? 1 : 0.5),
                                                                      metric.color.opacity(day.date == selectedDate ? 0.65 : 0.2)],
                                                            startPoint: .top, endPoint: .bottom))
                            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                    }
                }
            }
            if let average = statistics.average {
                RuleMark(y: .value("Recorded-day average", average))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if let selection {
                RuleMark(x: .value("Selected day", selection)).foregroundStyle(Color(uiColor: .quaternaryLabel))
            }
        }
        .chartXScale(domain: days.map { insightDayKey($0.date) })
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selection)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .chartXAxis {
            AxisMarks(values: insightAxisKeys(days.map(\.date), compact: typeSize.isAccessibilitySize)) { value in
                AxisValueLabel(anchor: value.count == 1 ? .top : value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top) {
                    if let key = value.as(String.self), let day = days.first(where: { insightDayKey($0.date) == key }) {
                        Text(insightAxisLabel(day.date, dayCount: days.count)).fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [yDomain.lowerBound, yDomain.upperBound]) {
                AxisValueLabel()
            }
        }
        .frame(height: 145)
        .accessibilityLabel("\(metric.title), \(days.count) selected days; dashed line is the recorded-day average")
        .accessibilityIdentifier("home.health.\(metric.rawValue).chart")
        .accessibilityAdjustableAction { direction in
            let current = days.firstIndex { $0.date == selectedDate } ?? max(0, days.count - 1)
            let next = direction == .increment ? min(days.count - 1, current + 1) : max(0, current - 1)
            if days.indices.contains(next) { selection = insightDayKey(days[next].date) }
        }
    }
    private func segment(_ index: Int) -> Int {
        days.prefix(index + 1).filter { $0.values[metric] == nil }.count
    }
}

struct MovementInsightCard: View {
    let days: [HealthInsightDay]
    @State private var metric: HealthInsightMetric = .steps
    @State private var selection: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var day: HealthInsightDay? {
        if let selection { return days.first { insightDayKey($0.date) == selection } }
        return days.last { $0.values[metric] != nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InsightCardHeading(title: "Movement", symbol: "figure.walk", color: .orange, dayCount: days.count)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                ForEach(HealthInsightMetric.movement) { option in
                    Button {
                        metric = option
                    } label: {
                        Text(option == .activeEnergy ? "Energy" : option.title)
                            .font(.subheadline.weight(metric == option ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(metric == option ? option.color.opacity(0.15) : Color.clear, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(metric == option ? .isSelected : [])
                    .accessibilityIdentifier("home.movement.\(option.rawValue)")
                }
            }
            InsightReading(metric: metric, day: day)
            if days.contains(where: { $0.values[metric] != nil }) {
                InsightDayChart(metric: metric, days: days, selection: $selection)
                let stats = InsightStatistics(days: days, metric: metric)
                if let average = stats.average {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("\(metric.formatted(average)) \(metric.unit) average", systemImage: "line.diagonal")
                        Text("\(stats.values.count) of \(days.count) days recorded")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                InsightEmptyReading()
            }
            Text(metric.explanation).font(.caption).foregroundStyle(.secondary)
        }
        .feedSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.health.movement")
    }
}

struct HealthSignalsCard: View {
    let days: [HealthInsightDay]
    @State private var metric: HealthInsightMetric = .restingHeartRate
    @State private var selection: String?
    private var day: HealthInsightDay? {
        if let selection { return days.first { insightDayKey($0.date) == selection } }
        return days.last { $0.values[metric] != nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InsightCardHeading(title: "Health signals", symbol: "waveform.path.ecg", color: .teal, dayCount: days.count)
            VStack(spacing: 0) {
                ForEach(HealthInsightMetric.signals) { option in
                    Button { metric = option } label: {
                        SignalSummaryRow(metric: option, days: days, selected: option == metric)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == metric ? .isSelected : [])
                    .accessibilityIdentifier("home.signals.\(option.rawValue)")
                }
            }
            Divider()
            Text(metric.title).font(.subheadline.weight(.semibold))
            InsightReading(metric: metric, day: day)
            if days.contains(where: { $0.values[metric] != nil }) {
                InsightDayChart(metric: metric, days: days, selection: $selection, line: true)
                if let average = InsightStatistics(days: days, metric: metric).average {
                    Text("Dashed line · \(metric.formatted(average)) \(metric.unit) recorded-day average")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                InsightEmptyReading()
            }
            Text(metric.explanation).font(.caption).foregroundStyle(.secondary)
        }
        .feedSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.health.signals")
    }
}

private struct SignalSummaryRow: View {
    let metric: HealthInsightMetric
    let days: [HealthInsightDay]
    let selected: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var latest: HealthInsightDay? { days.last { $0.values[metric] != nil } }
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(selected ? metric.color : .clear).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                if let latest {
                    Text(latest.date, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("No reading in this range").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 2)
            if !typeSize.isAccessibilitySize {
                SignalSparkline(metric: metric, days: days).frame(width: 62, height: 30).accessibilityHidden(true)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(latest?.values[metric].map(metric.formatted) ?? "—")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text(metric.unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12).padding(.trailing, 8)
        .background(selected ? metric.color.opacity(0.07) : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Show trend for the selected dates")
    }
}

private struct SignalSparkline: View {
    let metric: HealthInsightMetric
    let days: [HealthInsightDay]
    var body: some View {
        let range = InsightStatistics(days: days, metric: metric).range ?? 0...1
        Chart {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if let value = day.values[metric] {
                    LineMark(x: .value("Day", index), y: .value("Reading", value),
                             series: .value("Segment", days.prefix(index + 1).filter { $0.values[metric] == nil }.count))
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    PointMark(x: .value("Day", index), y: .value("Reading", value)).symbolSize(9)
                }
            }
        }
        .foregroundStyle(metric.color)
        .chartXScale(domain: 0...max(1, days.count - 1))
        .chartYScale(domain: (range.lowerBound - 1)...(range.upperBound + 1))
        .chartXAxis(.hidden).chartYAxis(.hidden)
    }
}

struct InsightEmptyReading: View {
    var body: some View {
        Text("No readings in this date range. Health access and available data determine what appears here.")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    }
}
#endif
