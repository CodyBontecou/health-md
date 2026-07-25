import Foundation
import SwiftUI
import WidgetKit

struct WatchHealthEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchHealthSnapshot
}

struct WatchHealthTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchHealthEntry {
        WatchHealthEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchHealthEntry) -> Void) {
        if context.isPreview {
            completion(WatchHealthEntry(date: .now, snapshot: .placeholder))
            return
        }

        Task {
            let cached = WatchHealthSnapshotStore.loadIfFresh()
            let fetched = await WatchHealthSnapshotProvider.fetchToday()
            if fetched.hasAnyData {
                WatchHealthSnapshotStore.save(fetched)
            }
            let snapshot = fetched.hasAnyData ? fetched : (cached ?? .placeholder)
            completion(WatchHealthEntry(date: .now, snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchHealthEntry>) -> Void) {
        Task {
            let cached = WatchHealthSnapshotStore.loadIfFresh()
            let fetched = await WatchHealthSnapshotProvider.fetchToday()
            if fetched.hasAnyData {
                WatchHealthSnapshotStore.save(fetched)
            }
            let snapshot = fetched.hasAnyData ? fetched : (cached ?? fetched)
            let entry = WatchHealthEntry(date: .now, snapshot: snapshot)
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }
}

private enum WatchHealthWidgetFamilies {
    static var supported: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner]
        #else
        [.accessoryRectangular, .accessoryCircular, .accessoryInline]
        #endif
    }
}

struct DailyActivityWidget: Widget {
    static let kind = "DailyActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            DailyActivityWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Activity")
        .description("Glance at today's steps, active energy, exercise minutes, and stand hours.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct RecoveryWidget: Widget {
    static let kind = "RecoveryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            RecoveryWidgetView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("Track sleep, resting heart rate, HRV, and blood oxygen from Apple Health.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct StepsWidget: Widget {
    static let kind = "StepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .steps)
        }
        .configurationDisplayName("Steps")
        .description("Track today's step count as a focused watch face widget.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct MoveEnergyWidget: Widget {
    static let kind = "MoveEnergyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .activeEnergy)
        }
        .configurationDisplayName("Move Energy")
        .description("See today's active energy burn at a glance.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct ExerciseMinutesWidget: Widget {
    static let kind = "ExerciseMinutesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .exerciseMinutes)
        }
        .configurationDisplayName("Exercise Minutes")
        .description("Keep an eye on today's Apple Exercise minutes.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct StandHoursWidget: Widget {
    static let kind = "StandHoursWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .standHours)
        }
        .configurationDisplayName("Stand Hours")
        .description("Check how many hours you stood today.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct SleepWidget: Widget {
    static let kind = "SleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .sleep)
        }
        .configurationDisplayName("Sleep")
        .description("Show last night's sleep duration from Apple Health.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct RestingHeartRateWidget: Widget {
    static let kind = "RestingHeartRateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .restingHeartRate)
        }
        .configurationDisplayName("Resting Heart Rate")
        .description("Show today's latest resting heart rate.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct HeartRateVariabilityWidget: Widget {
    static let kind = "HeartRateVariabilityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .heartRateVariability)
        }
        .configurationDisplayName("Heart Rate Variability")
        .description("Track today's average HRV from Apple Health.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

struct BloodOxygenWidget: Widget {
    static let kind = "BloodOxygenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            FocusedMetricWidgetView(entry: entry, metric: .bloodOxygen)
        }
        .configurationDisplayName("Blood Oxygen")
        .description("Show today's average blood oxygen reading.")
        .supportedFamilies(WatchHealthWidgetFamilies.supported)
    }
}

private struct DailyActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchHealthEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ActivityCircularView(snapshot: entry.snapshot)
        case .accessoryInline:
            Label("\(WatchHealthFormatter.steps(entry.snapshot.steps)) steps", systemImage: "figure.walk")
        #if os(watchOS)
        case .accessoryCorner:
            ActivityCornerView(snapshot: entry.snapshot)
        #endif
        default:
            ActivityRectangularView(snapshot: entry.snapshot)
        }
    }
}

private struct RecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchHealthEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            RecoveryCircularView(snapshot: entry.snapshot)
        case .accessoryInline:
            Label("Sleep \(WatchHealthFormatter.hours(entry.snapshot.sleepHours)) · HRV \(WatchHealthFormatter.milliseconds(entry.snapshot.heartRateVariabilityMS))", systemImage: "bed.double.fill")
        #if os(watchOS)
        case .accessoryCorner:
            RecoveryCornerView(snapshot: entry.snapshot)
        #endif
        default:
            RecoveryRectangularView(snapshot: entry.snapshot)
        }
    }
}

private struct FocusedMetricWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchHealthEntry
    let metric: FocusedHealthMetric

    var body: some View {
        switch family {
        case .accessoryCircular:
            FocusedMetricCircularView(snapshot: entry.snapshot, metric: metric)
        case .accessoryInline:
            Label(metric.inlineText(from: entry.snapshot), systemImage: metric.icon)
        #if os(watchOS)
        case .accessoryCorner:
            FocusedMetricCornerView(snapshot: entry.snapshot, metric: metric)
        #endif
        default:
            FocusedMetricRectangularView(snapshot: entry.snapshot, metric: metric)
        }
    }
}

private enum FocusedHealthMetric {
    case steps
    case activeEnergy
    case exerciseMinutes
    case standHours
    case sleep
    case restingHeartRate
    case heartRateVariability
    case bloodOxygen

    var displayName: String {
        switch self {
        case .steps:
            return "Steps"
        case .activeEnergy:
            return "Move Energy"
        case .exerciseMinutes:
            return "Exercise Minutes"
        case .standHours:
            return "Stand Hours"
        case .sleep:
            return "Sleep"
        case .restingHeartRate:
            return "Resting Heart Rate"
        case .heartRateVariability:
            return "Heart Rate Variability"
        case .bloodOxygen:
            return "Blood Oxygen"
        }
    }

    var shortTitle: String {
        switch self {
        case .activeEnergy:
            return "Move"
        case .exerciseMinutes:
            return "Exercise"
        case .standHours:
            return "Stand"
        case .restingHeartRate:
            return "RHR"
        case .heartRateVariability:
            return "HRV"
        case .bloodOxygen:
            return "O₂"
        default:
            return displayName
        }
    }

    var widgetDescription: String {
        switch self {
        case .steps:
            return "Track today's step count as a focused watch face widget."
        case .activeEnergy:
            return "See today's active energy burn at a glance."
        case .exerciseMinutes:
            return "Keep an eye on today's Apple Exercise minutes."
        case .standHours:
            return "Check how many hours you stood today."
        case .sleep:
            return "Show last night's sleep duration from Apple Health."
        case .restingHeartRate:
            return "Show today's latest resting heart rate."
        case .heartRateVariability:
            return "Track today's average HRV from Apple Health."
        case .bloodOxygen:
            return "Show today's average blood oxygen reading."
        }
    }

    var icon: String {
        switch self {
        case .steps:
            return "figure.walk"
        case .activeEnergy:
            return "flame.fill"
        case .exerciseMinutes:
            return "timer"
        case .standHours:
            return "figure.stand"
        case .sleep:
            return "bed.double.fill"
        case .restingHeartRate:
            return "heart.fill"
        case .heartRateVariability:
            return "waveform.path.ecg"
        case .bloodOxygen:
            return "lungs.fill"
        }
    }

    var tint: Color {
        switch self {
        case .steps:
            return .green
        case .activeEnergy:
            return .orange
        case .exerciseMinutes:
            return .yellow
        case .standHours:
            return .blue
        case .sleep:
            return .indigo
        case .restingHeartRate:
            return .red
        case .heartRateVariability:
            return .cyan
        case .bloodOxygen:
            return .mint
        }
    }

    var gaugeRange: ClosedRange<Double> {
        switch self {
        case .steps:
            return 0...10_000
        case .activeEnergy:
            return 0...500
        case .exerciseMinutes:
            return 0...30
        case .standHours:
            return 0...12
        case .sleep:
            return 0...8
        case .restingHeartRate:
            return 40...120
        case .heartRateVariability:
            return 0...100
        case .bloodOxygen:
            return 90...100
        }
    }

    func value(from snapshot: WatchHealthSnapshot) -> Double? {
        switch self {
        case .steps:
            return snapshot.steps
        case .activeEnergy:
            return snapshot.activeEnergyKilocalories
        case .exerciseMinutes:
            return snapshot.exerciseMinutes
        case .standHours:
            return snapshot.standHours.map(Double.init)
        case .sleep:
            return snapshot.sleepHours
        case .restingHeartRate:
            return snapshot.restingHeartRate
        case .heartRateVariability:
            return snapshot.heartRateVariabilityMS
        case .bloodOxygen:
            return snapshot.bloodOxygenPercent
        }
    }

    func formattedValue(from snapshot: WatchHealthSnapshot) -> String {
        switch self {
        case .steps:
            return "\(WatchHealthFormatter.steps(snapshot.steps)) steps"
        case .activeEnergy:
            return "\(WatchHealthFormatter.wholeNumber(snapshot.activeEnergyKilocalories)) kcal"
        case .exerciseMinutes:
            return "\(WatchHealthFormatter.wholeNumber(snapshot.exerciseMinutes)) min"
        case .standHours:
            return WatchHealthFormatter.standHours(snapshot.standHours)
        case .sleep:
            return WatchHealthFormatter.hours(snapshot.sleepHours)
        case .restingHeartRate:
            return WatchHealthFormatter.bpm(snapshot.restingHeartRate)
        case .heartRateVariability:
            return WatchHealthFormatter.milliseconds(snapshot.heartRateVariabilityMS)
        case .bloodOxygen:
            return WatchHealthFormatter.percent(snapshot.bloodOxygenPercent)
        }
    }

    func compactValue(from snapshot: WatchHealthSnapshot) -> String {
        switch self {
        case .steps:
            return compactNumber(snapshot.steps)
        case .activeEnergy:
            return WatchHealthFormatter.wholeNumber(snapshot.activeEnergyKilocalories)
        case .exerciseMinutes:
            return WatchHealthFormatter.wholeNumber(snapshot.exerciseMinutes)
        case .standHours:
            return snapshot.standHours.map(String.init) ?? "—"
        case .sleep:
            guard let sleepHours = snapshot.sleepHours else { return "—" }
            return String(format: "%.1fh", sleepHours)
        case .restingHeartRate:
            return WatchHealthFormatter.wholeNumber(snapshot.restingHeartRate)
        case .heartRateVariability:
            return WatchHealthFormatter.wholeNumber(snapshot.heartRateVariabilityMS)
        case .bloodOxygen:
            return WatchHealthFormatter.percent(snapshot.bloodOxygenPercent)
        }
    }

    func inlineText(from snapshot: WatchHealthSnapshot) -> String {
        switch self {
        case .steps:
            return "\(WatchHealthFormatter.steps(snapshot.steps)) steps"
        case .activeEnergy:
            return "\(WatchHealthFormatter.wholeNumber(snapshot.activeEnergyKilocalories)) kcal"
        case .exerciseMinutes:
            return "\(WatchHealthFormatter.wholeNumber(snapshot.exerciseMinutes)) min"
        case .standHours:
            return WatchHealthFormatter.standHours(snapshot.standHours)
        case .sleep:
            return "\(WatchHealthFormatter.hours(snapshot.sleepHours)) sleep"
        case .restingHeartRate:
            return "RHR \(WatchHealthFormatter.bpm(snapshot.restingHeartRate))"
        case .heartRateVariability:
            return "HRV \(WatchHealthFormatter.milliseconds(snapshot.heartRateVariabilityMS))"
        case .bloodOxygen:
            return "O₂ \(WatchHealthFormatter.percent(snapshot.bloodOxygenPercent))"
        }
    }

    func detailText(from snapshot: WatchHealthSnapshot) -> String {
        guard value(from: snapshot) != nil else { return "No data yet" }

        switch self {
        case .steps:
            return "10k step reference"
        case .activeEnergy:
            return "500 kcal reference"
        case .exerciseMinutes:
            return "30 min reference"
        case .standHours:
            return "12 hr reference"
        case .sleep:
            return "8h sleep reference"
        case .restingHeartRate:
            return "Latest today"
        case .heartRateVariability:
            return "Average today"
        case .bloodOxygen:
            return "Average today"
        }
    }

    func gaugeValue(from snapshot: WatchHealthSnapshot) -> Double {
        let range = gaugeRange
        let value = value(from: snapshot) ?? range.lowerBound
        return min(max(value, range.lowerBound), range.upperBound)
    }

    func progress(from snapshot: WatchHealthSnapshot) -> Double {
        let range = gaugeRange
        guard range.upperBound > range.lowerBound else { return 0 }
        return (gaugeValue(from: snapshot) - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

private struct FocusedMetricRectangularView: View {
    let snapshot: WatchHealthSnapshot
    let metric: FocusedHealthMetric

    var body: some View {
        HStack(spacing: 8) {
            FocusedMetricIcon(metric: metric, snapshot: snapshot)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .widgetAccentable()
                Text(metric.formattedValue(from: snapshot))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(metric.detailText(from: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .minimumScaleFactor(0.75)
        }
        .containerBackground(Color.black.opacity(0.12), for: .widget)
    }
}

private struct FocusedMetricCircularView: View {
    let snapshot: WatchHealthSnapshot
    let metric: FocusedHealthMetric

    var body: some View {
        Gauge(value: metric.gaugeValue(from: snapshot), in: metric.gaugeRange) {
            Image(systemName: metric.icon)
        } currentValueLabel: {
            Text(metric.compactValue(from: snapshot))
                .minimumScaleFactor(0.65)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(metric.tint)
        .containerBackground(Color.black.opacity(0.12), for: .widget)
    }
}

#if os(watchOS)
private struct FocusedMetricCornerView: View {
    let snapshot: WatchHealthSnapshot
    let metric: FocusedHealthMetric

    var body: some View {
        Gauge(value: metric.gaugeValue(from: snapshot), in: metric.gaugeRange) {
            Text(metric.shortTitle)
        } currentValueLabel: {
            Text(metric.compactValue(from: snapshot))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(metric.tint)
        .widgetLabel(metric.shortTitle)
    }
}
#endif

private struct FocusedMetricIcon: View {
    let metric: FocusedHealthMetric
    let snapshot: WatchHealthSnapshot

    var body: some View {
        ZStack {
            Circle()
                .stroke(metric.tint.opacity(0.18), lineWidth: 4)

            Circle()
                .trim(from: 0, to: metric.progress(from: snapshot))
                .stroke(metric.tint.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: metric.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(metric.tint)
        }
    }
}

private struct ActivityRectangularView: View {
    let snapshot: WatchHealthSnapshot

    var body: some View {
        HStack(spacing: 8) {
            ActivityRingsMiniView(snapshot: snapshot)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Activity")
                    .font(.headline)
                    .widgetAccentable()
                MetricLine(icon: "figure.walk", text: "\(WatchHealthFormatter.steps(snapshot.steps)) steps")
                MetricLine(icon: "flame.fill", text: "\(WatchHealthFormatter.wholeNumber(snapshot.activeEnergyKilocalories)) kcal")
                MetricLine(icon: "timer", text: "\(WatchHealthFormatter.wholeNumber(snapshot.exerciseMinutes)) min exercise")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .minimumScaleFactor(0.75)
        }
        .containerBackground(Color.black.opacity(0.12), for: .widget)
    }
}

private struct RecoveryRectangularView: View {
    let snapshot: WatchHealthSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(.red.gradient)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery")
                    .font(.headline)
                    .widgetAccentable()
                MetricLine(icon: "bed.double.fill", text: "\(WatchHealthFormatter.hours(snapshot.sleepHours)) sleep")
                MetricLine(icon: "heart.fill", text: WatchHealthFormatter.bpm(snapshot.restingHeartRate))
                MetricLine(icon: "waveform.path.ecg", text: "HRV \(WatchHealthFormatter.milliseconds(snapshot.heartRateVariabilityMS))")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .minimumScaleFactor(0.75)
        }
        .containerBackground(Color.black.opacity(0.12), for: .widget)
    }
}

private struct ActivityCircularView: View {
    let snapshot: WatchHealthSnapshot

    var body: some View {
        Gauge(value: min(snapshot.steps ?? 0, 10_000), in: 0...10_000) {
            Image(systemName: "figure.walk")
        } currentValueLabel: {
            Text(WatchHealthFormatter.steps(snapshot.steps))
                .minimumScaleFactor(0.7)
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(Color.black.opacity(0.12), for: .widget)
    }
}

private struct RecoveryCircularView: View {
    let snapshot: WatchHealthSnapshot

    var body: some View {
        Gauge(value: min(snapshot.sleepHours ?? 0, 8), in: 0...8) {
            Image(systemName: "bed.double.fill")
        } currentValueLabel: {
            Text(WatchHealthFormatter.hours(snapshot.sleepHours))
                .minimumScaleFactor(0.7)
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(Color.black.opacity(0.12), for: .widget)
    }
}

#if os(watchOS)
private struct ActivityCornerView: View {
    let snapshot: WatchHealthSnapshot

    var body: some View {
        Gauge(value: min(snapshot.steps ?? 0, 10_000), in: 0...10_000) {
            Text("Steps")
        } currentValueLabel: {
            Text(WatchHealthFormatter.steps(snapshot.steps))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetLabel("Steps")
    }
}

private struct RecoveryCornerView: View {
    let snapshot: WatchHealthSnapshot

    var body: some View {
        Gauge(value: min(snapshot.heartRateVariabilityMS ?? 0, 100), in: 0...100) {
            Text("HRV")
        } currentValueLabel: {
            Text(WatchHealthFormatter.wholeNumber(snapshot.heartRateVariabilityMS))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetLabel("HRV")
    }
}

#endif

private struct ActivityRingsMiniView: View {
    let snapshot: WatchHealthSnapshot

    var body: some View {
        ZStack {
            Ring(progress: progress(snapshot.steps, goal: 10_000), color: .green, lineWidth: 5, size: 40)
            Ring(progress: progress(snapshot.activeEnergyKilocalories, goal: 500), color: .orange, lineWidth: 5, size: 29)
            Ring(progress: progress(snapshot.exerciseMinutes, goal: 30), color: .yellow, lineWidth: 5, size: 18)
        }
    }

    private func progress(_ value: Double?, goal: Double) -> Double {
        guard let value, goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }
}

private struct Ring: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: size, height: size)
            .background {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: lineWidth)
                    .frame(width: size, height: size)
            }
    }
}

private struct MetricLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .imageScale(.small)
                .frame(width: 11)
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }
}

private func compactNumber(_ value: Double?) -> String {
    guard let value else { return "—" }

    if abs(value) >= 1_000 {
        let format = abs(value) >= 10_000 ? "%.0fk" : "%.1fk"
        return String(format: format, value / 1_000)
            .replacingOccurrences(of: ".0k", with: "k")
    }

    return WatchHealthFormatter.wholeNumber(value)
}

#Preview(as: .accessoryRectangular) {
    DailyActivityWidget()
} timeline: {
    WatchHealthEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryCircular) {
    RecoveryWidget()
} timeline: {
    WatchHealthEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryRectangular) {
    StepsWidget()
} timeline: {
    WatchHealthEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryCircular) {
    BloodOxygenWidget()
} timeline: {
    WatchHealthEntry(date: .now, snapshot: .placeholder)
}
