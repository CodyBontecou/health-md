import SwiftUI
import WidgetKit

struct HealthWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthWidgetSnapshot
}

struct HealthWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthWidgetEntry {
        HealthWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthWidgetEntry) -> Void) {
        if context.isPreview {
            completion(HealthWidgetEntry(date: .now, snapshot: .placeholder))
            return
        }

        Task {
            let snapshot = await resolvedSnapshot()
            completion(HealthWidgetEntry(date: .now, snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthWidgetEntry>) -> Void) {
        Task {
            let snapshot = await resolvedSnapshot()
            let entry = HealthWidgetEntry(date: .now, snapshot: snapshot)
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    private func resolvedSnapshot() async -> HealthWidgetSnapshot {
        let cached = HealthWidgetSnapshotStore.loadIfFresh()
        let fetched = await HealthWidgetSnapshotProvider.fetchRecentDays()
        if fetched.hasAnyData {
            HealthWidgetSnapshotStore.save(fetched)
            return fetched
        }
        return cached ?? fetched
    }
}

struct HealthSummaryWidget: Widget {
    static let kind = "HealthSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HealthWidgetTimelineProvider()) { entry in
            HealthSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Health Summary")
        .description("A daily Health.md dashboard with activity, sleep, heart, and recovery metrics.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryRectangular])
    }
}

struct ActivityRingsWidget: Widget {
    static let kind = "ActivityRingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HealthWidgetTimelineProvider()) { entry in
            ActivityRingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Activity Rings")
        .description("Move, exercise, and stand progress inspired by the Health.md activity-rings visualization.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct HeartRangeWidget: Widget {
    static let kind = "HeartRangeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HealthWidgetTimelineProvider()) { entry in
            HeartRangeWidgetView(entry: entry)
        }
        .configurationDisplayName("Heart Range")
        .description("Seven-day min, average, and max heart-rate range from Health.md.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryInline, .accessoryRectangular])
    }
}

struct SleepSummaryWidget: Widget {
    static let kind = "SleepSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HealthWidgetTimelineProvider()) { entry in
            SleepSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep and a seven-day sleep bar visualization.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryRectangular])
    }
}

private struct HealthSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HealthWidgetEntry

    var body: some View {
        Group {
            if !entry.snapshot.hasAnyData {
                EmptyHealthWidgetView(message: "Open Health.md to allow Health access.")
            } else {
                switch family {
                case .accessoryInline:
                    Text(summaryInlineText)
                case .accessoryRectangular:
                    SummaryAccessoryRectangular(day: entry.snapshot.today)
                case .systemLarge:
                    SummaryLargeView(snapshot: entry.snapshot)
                case .systemMedium:
                    SummaryMediumView(snapshot: entry.snapshot)
                default:
                    GlassSummaryWidgetTile(day: entry.snapshot.today)
                }
            }
        }
        .healthWidgetBackground()
        .privacySensitive()
    }

    private var summaryInlineText: String {
        let day = entry.snapshot.today
        return "Health.md: \(HealthWidgetFormat.steps(day.steps)) · \(HealthWidgetFormat.hours(day.sleepHours)) sleep"
    }
}

private struct ActivityRingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HealthWidgetEntry

    var body: some View {
        Group {
            if !entry.snapshot.hasAnyData {
                EmptyHealthWidgetView(message: "No activity data")
            } else {
                switch family {
                case .accessoryCircular:
                    ActivityCircularAccessory(day: entry.snapshot.today)
                case .accessoryInline:
                    Label("Move \(HealthWidgetFormat.whole(entry.snapshot.today.activeEnergyKilocalories)) kcal", systemImage: "flame.fill")
                case .accessoryRectangular:
                    ActivityRectangularAccessory(day: entry.snapshot.today)
                case .systemMedium:
                    ActivityMediumView(snapshot: entry.snapshot)
                default:
                    GlassActivityWidgetTile(day: entry.snapshot.today)
                }
            }
        }
        .healthWidgetBackground()
        .privacySensitive()
    }
}

private struct HeartRangeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HealthWidgetEntry

    var body: some View {
        Group {
            if !entry.snapshot.hasAnyData {
                EmptyHealthWidgetView(message: "No heart data")
            } else {
                switch family {
                case .accessoryInline:
                    Label("HR \(HealthWidgetFormat.bpm(entry.snapshot.today.averageHeartRate))", systemImage: "heart.fill")
                case .accessoryRectangular:
                    HeartRangeAccessory(day: entry.snapshot.today)
                case .systemLarge:
                    HeartRangeLargeView(snapshot: entry.snapshot)
                default:
                    GlassHeartWidgetTile(day: entry.snapshot.today)
                }
            }
        }
        .healthWidgetBackground()
        .privacySensitive()
    }
}

private struct SleepSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HealthWidgetEntry

    var body: some View {
        Group {
            if !entry.snapshot.hasAnyData {
                EmptyHealthWidgetView(message: "No sleep data")
            } else {
                switch family {
                case .accessoryInline:
                    Label("Sleep \(HealthWidgetFormat.hours(entry.snapshot.today.sleepHours))", systemImage: "bed.double.fill")
                case .accessoryRectangular:
                    SleepAccessory(day: entry.snapshot.today)
                case .systemLarge:
                    SleepLargeView(snapshot: entry.snapshot)
                case .systemMedium:
                    SleepMediumView(snapshot: entry.snapshot)
                default:
                    SleepSmallView(day: entry.snapshot.today)
                }
            }
        }
        .healthWidgetBackground()
        .privacySensitive()
    }
}

private struct EmptyHealthWidgetView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetCrystalHeart(size: 24)
            Text("Health.md")
                .font(.headline)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// WidgetSummaryG.
private struct GlassSummaryWidgetTile: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                WidgetCrystalHeart(size: 18)
                Text("Last night")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetGlass.secondaryText)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(HealthWidgetFormat.hours(day.sleepHours))
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                Text("sleep")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetGlass.muted)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(verbatim: "HRV \(HealthWidgetFormat.whole(day.heartRateVariabilityMS))")
                Spacer(minLength: 4)
                Text("\(HealthWidgetFormat.steps(day.steps)) steps")
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// WidgetActivityG.
private struct GlassActivityWidgetTile: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetGlass.secondaryText)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                TripleActivityRingView(day: day)
                    .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(HealthWidgetFormat.whole(day.activeEnergyKilocalories)) kcal")
                        .foregroundStyle(WidgetGlass.moveText)
                    Text(verbatim: "\(HealthWidgetFormat.whole(day.exerciseMinutes)) min")
                        .foregroundStyle(WidgetGlass.exercise)
                    Text(verbatim: "\(HealthWidgetFormat.whole(day.standHours.map(Double.init))) h")
                        .foregroundStyle(WidgetGlass.stand)
                }
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// WidgetHeartG: today's range beside twelve two-hour heart-rate bars.
private struct GlassHeartWidgetTile: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Heart range")
                    .font(.system(size: 13, weight: .bold))
                Spacer(minLength: 4)
                Text("Today")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetGlass.muted)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 18) {
                HeartRangeHeadline(day: day, valueSize: 30)
                    .fixedSize(horizontal: true, vertical: false)
                HeartRateBucketBars(buckets: day.heartRateBuckets, height: 54)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// "52–148" over "bpm · average 71".
private struct HeartRangeHeadline: View {
    let day: HealthWidgetDay
    let valueSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(HealthWidgetFormat.whole(day.heartRateMin))–\(HealthWidgetFormat.whole(day.heartRateMax))")
                .font(.system(size: valueSize, weight: .bold))
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            Text("bpm · average \(HealthWidgetFormat.bpm(day.averageHeartRate))")
                .font(.system(size: 12))
                .foregroundStyle(WidgetGlass.muted)
                .lineLimit(1)
        }
    }
}

/// Twelve bottom-aligned bars, one per two-hour slot of today's heart-rate samples. Height and
/// opacity follow the slot's average within the day's slot range; empty slots stay as stubs.
private struct HeartRateBucketBars: View {
    let buckets: [Double?]?
    let height: CGFloat

    var body: some View {
        let levels = HeartRateBarScale.levels(for: buckets ?? [])
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(WidgetGlass.accent.opacity(level.map { 0.45 + 0.45 * $0 } ?? 0.16))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, height * CGFloat(level ?? 0.06)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

enum HeartRateBarScale {
    /// Maps slot averages to 0.25…1 between the lowest and highest slot; `nil` stays empty.
    static func levels(for buckets: [Double?]) -> [Double?] {
        let values = buckets.compactMap { $0 }
        guard let low = values.min(), let high = values.max() else { return buckets.map { _ in nil } }
        let span = high - low
        return buckets.map { value in
            guard let value else { return nil }
            guard span > 0 else { return 0.6 }
            return 0.25 + 0.75 * (value - low) / span
        }
    }
}

private struct SummarySmallView: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Today", icon: "heart.text.square", tint: .pink)
            Spacer(minLength: 0)
            Text(HealthWidgetFormat.steps(day.steps))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text("steps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                MiniMetric(icon: "bed.double.fill", value: HealthWidgetFormat.hours(day.sleepHours), tint: WidgetGlass.accent)
                MiniMetric(icon: "heart.fill", value: HealthWidgetFormat.bpm(day.restingHeartRate), tint: .red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct SummaryMediumView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Health.md", icon: "heart.text.square", tint: WidgetGlass.accent)
                Text(HealthWidgetFormat.steps(snapshot.today.steps))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text("steps today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WidgetGlass.muted)
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                MetricRow(icon: "flame.fill", title: "Move", value: "\(HealthWidgetFormat.whole(snapshot.today.activeEnergyKilocalories)) kcal", tint: WidgetGlass.moveText)
                MetricRow(icon: "timer", title: "Exercise", value: "\(HealthWidgetFormat.whole(snapshot.today.exerciseMinutes)) min", tint: WidgetGlass.exercise)
                MetricRow(icon: "bed.double.fill", title: "Sleep", value: HealthWidgetFormat.hours(snapshot.today.sleepHours), tint: WidgetGlass.accent)
                MetricRow(icon: "waveform.path.ecg", title: "HRV", value: HealthWidgetFormat.milliseconds(snapshot.today.heartRateVariabilityMS), tint: WidgetGlass.hrv)
            }
        }
    }
}

private struct SummaryLargeView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetHeader(title: "Health.md", icon: "heart.text.square", tint: WidgetGlass.accent)
            HStack(alignment: .center, spacing: 18) {
                TripleActivityRingView(day: snapshot.today)
                    .frame(width: 106, height: 106)
                VStack(spacing: 8) {
                    MetricRow(icon: "figure.walk", title: "Steps", value: HealthWidgetFormat.steps(snapshot.today.steps), tint: WidgetGlass.exercise)
                    MetricRow(icon: "flame.fill", title: "Move", value: "\(HealthWidgetFormat.whole(snapshot.today.activeEnergyKilocalories)) kcal", tint: WidgetGlass.moveText)
                    MetricRow(icon: "heart.fill", title: "Resting", value: HealthWidgetFormat.bpm(snapshot.today.restingHeartRate), tint: WidgetGlass.moveText)
                }
            }
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("7-day sleep")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetGlass.muted)
                SleepBarChart(days: snapshot.recentSevenDays)
                    .frame(height: 54)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Heart range")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetGlass.muted)
                HeartRangeChart(days: snapshot.recentSevenDays)
                    .frame(height: 58)
            }
        }
    }
}

private struct ActivityMediumView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        HStack(spacing: 16) {
            TripleActivityRingView(day: snapshot.today)
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetGlass.secondaryText)
                MetricRow(icon: "flame.fill", title: "Move", value: "\(HealthWidgetFormat.whole(snapshot.today.activeEnergyKilocalories)) / 500 kcal", tint: WidgetGlass.moveText)
                MetricRow(icon: "timer", title: "Exercise", value: "\(HealthWidgetFormat.whole(snapshot.today.exerciseMinutes)) / 30 min", tint: WidgetGlass.exercise)
                MetricRow(icon: "figure.stand", title: "Stand", value: "\(HealthWidgetFormat.whole(snapshot.today.standHours.map(Double.init))) / 12 hr", tint: WidgetGlass.stand)
            }
        }
    }
}

private struct ActivityCircularAccessory: View {
    let day: HealthWidgetDay

    var body: some View {
        Gauge(value: min(day.steps ?? 0, 10_000), in: 0...10_000) {
            Image(systemName: "figure.walk")
        } currentValueLabel: {
            Text(HealthWidgetFormat.compactNumber(day.steps))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(WidgetGlass.exercise)
    }
}

private struct ActivityRectangularAccessory: View {
    let day: HealthWidgetDay

    var body: some View {
        HStack(spacing: 8) {
            TripleActivityRingView(day: day)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity")
                    .font(.caption2.weight(.semibold))
                Text("\(HealthWidgetFormat.steps(day.steps)) · \(HealthWidgetFormat.whole(day.activeEnergyKilocalories)) kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SummaryAccessoryRectangular: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                AppIconMark(size: 12)
                Text("Health.md")
                    .font(.caption2.weight(.semibold))
            }
            Text("\(HealthWidgetFormat.steps(day.steps)) · \(HealthWidgetFormat.hours(day.sleepHours)) sleep")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HeartRangeLargeView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heart range")
                    .font(.system(size: 13, weight: .bold))
                Spacer(minLength: 4)
                Text("Today")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetGlass.muted)
            }
            HStack(alignment: .bottom, spacing: 18) {
                HeartRangeHeadline(day: snapshot.today, valueSize: 30)
                    .fixedSize(horizontal: true, vertical: false)
                HeartRateBucketBars(buckets: snapshot.today.heartRateBuckets, height: 54)
            }
            Text("Last 7 days")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetGlass.muted)
            HeartRangeChart(days: snapshot.recentSevenDays)
                .frame(maxHeight: .infinity)
            HStack(spacing: 10) {
                MetricTile(title: "Resting", value: HealthWidgetFormat.bpm(snapshot.today.restingHeartRate), tint: WidgetGlass.moveText)
                MetricTile(title: "HRV", value: HealthWidgetFormat.milliseconds(snapshot.today.heartRateVariabilityMS), tint: WidgetGlass.hrv)
            }
        }
    }
}

private struct HeartRangeAccessory: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Heart", systemImage: "heart.fill")
                .font(.caption2.weight(.semibold))
            Text("\(HealthWidgetFormat.bpm(day.averageHeartRate)) avg · \(HealthWidgetFormat.bpm(day.heartRateMin))-\(HealthWidgetFormat.bpm(day.heartRateMax))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SleepSmallView: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Sleep", icon: "bed.double.fill", tint: WidgetGlass.accent)
            Spacer(minLength: 0)
            Text(HealthWidgetFormat.hours(day.sleepHours))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            Text(sleepWindowText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ProgressView(value: min(day.sleepHours ?? 0, 8), total: 8)
                .tint(WidgetGlass.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var sleepWindowText: String {
        guard let start = day.sleepStart, let end = day.sleepEnd else { return "last night" }
        return "\(HealthWidgetFormat.time(start)) – \(HealthWidgetFormat.time(end))"
    }
}

private struct SleepMediumView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetHeader(title: "Sleep", icon: "bed.double.fill", tint: WidgetGlass.accent)
                Spacer()
                Text(HealthWidgetFormat.hours(snapshot.today.sleepHours))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WidgetGlass.accent)
                    .monospacedDigit()
            }
            SleepBarChart(days: snapshot.recentSevenDays)
                .frame(height: 84)
            Text("Goal line: 8 hours")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SleepLargeView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetHeader(title: "Sleep", icon: "bed.double.fill", tint: WidgetGlass.accent)
            HStack(spacing: 10) {
                MetricTile(title: "Last night", value: HealthWidgetFormat.hours(snapshot.today.sleepHours), tint: WidgetGlass.accent)
                MetricTile(title: "Average", value: HealthWidgetFormat.hours(HealthWidgetMath.average(snapshot.recentSevenDays.compactMap(\.sleepHours))), tint: WidgetGlass.accent)
            }
            SleepBarChart(days: snapshot.recentSevenDays)
                .frame(height: 120)
            HStack {
                Text("Bedtime")
                Spacer()
                Text(snapshot.today.sleepStart.map(HealthWidgetFormat.time) ?? "—")
                Text("Wake")
                Text(snapshot.today.sleepEnd.map(HealthWidgetFormat.time) ?? "—")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }
}

private struct SleepAccessory: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Sleep", systemImage: "bed.double.fill")
                .font(.caption2.weight(.semibold))
            Text("\(HealthWidgetFormat.hours(day.sleepHours)) · woke \(day.sleepEnd.map(HealthWidgetFormat.time) ?? "—")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WidgetHeader: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        } icon: {
            if title == "Health.md" {
                WidgetCrystalHeart(size: 16)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

private struct AppIconMark: View {
    let size: CGFloat

    var body: some View {
        Image("WidgetAppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct MiniMetric: View {
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(value)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .minimumScaleFactor(0.7)
    }
}

private struct MetricRow: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(.caption2)
                .foregroundStyle(WidgetGlass.muted)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(WidgetGlass.rowFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(WidgetGlass.panelEdge, lineWidth: 1))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetGlass.muted)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(WidgetGlass.rowFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WidgetGlass.panelEdge, lineWidth: 1))
    }
}

/// WidgetActivityG's rings: radii 42/30/18 and a 9-unit stroke on a 100-unit square.
private struct TripleActivityRingView: View {
    let day: HealthWidgetDay

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.09
            ZStack {
                ActivityRing(progress: HealthWidgetMath.progress(day.activeEnergyKilocalories, goal: 500), color: WidgetGlass.moveRing, lineWidth: line)
                    .frame(width: side * 0.84, height: side * 0.84)
                ActivityRing(progress: HealthWidgetMath.progress(day.exerciseMinutes, goal: 30), color: WidgetGlass.exercise, lineWidth: line)
                    .frame(width: side * 0.60, height: side * 0.60)
                ActivityRing(progress: HealthWidgetMath.progress(day.standHours.map(Double.init), goal: 12), color: WidgetGlass.stand, lineWidth: line)
                    .frame(width: side * 0.36, height: side * 0.36)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Move \(HealthWidgetFormat.whole(day.activeEnergyKilocalories)) kcal, exercise \(HealthWidgetFormat.whole(day.exerciseMinutes)) min, stand \(HealthWidgetFormat.whole(day.standHours.map(Double.init))) h"))
    }
}

private struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

private struct HeartRangeChart: View {
    let days: [HealthWidgetDay]

    private struct Point {
        let index: Int
        let min: Double
        let avg: Double
        let max: Double
    }

    var body: some View {
        let points = days.enumerated().compactMap { item -> Point? in
            guard let avg = item.element.averageHeartRate else { return nil }
            return Point(
                index: item.offset,
                min: item.element.heartRateMin ?? avg,
                avg: avg,
                max: item.element.heartRateMax ?? avg
            )
        }

        Canvas { context, size in
            guard !points.isEmpty else { return }
            let minValue = max(0, (points.map(\.min).min() ?? 40) - 12)
            let maxValue = (points.map(\.max).max() ?? 140) + 12
            let range = max(1, maxValue - minValue)
            let plot = CGRect(x: 8, y: 4, width: max(1, size.width - 16), height: max(1, size.height - 12))

            func xPosition(_ index: Int) -> CGFloat {
                guard days.count > 1 else { return plot.midX }
                return plot.minX + CGFloat(index) / CGFloat(days.count - 1) * plot.width
            }

            func yPosition(_ value: Double) -> CGFloat {
                plot.maxY - CGFloat((value - minValue) / range) * plot.height
            }

            var line = Path()
            var didStartLine = false

            for point in points {
                let x = xPosition(point.index)
                let top = yPosition(point.max)
                let bottom = yPosition(point.min)
                let rect = CGRect(x: x - 3, y: top, width: 6, height: max(5, bottom - top))
                let capsule = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(capsule, with: .color(WidgetGlass.accent.opacity(0.28)))

                let avgY = yPosition(point.avg)
                if didStartLine {
                    line.addLine(to: CGPoint(x: x, y: avgY))
                } else {
                    line.move(to: CGPoint(x: x, y: avgY))
                    didStartLine = true
                }

                let dot = Path(ellipseIn: CGRect(x: x - 3.5, y: avgY - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(WidgetGlass.accent))
            }

            context.stroke(line, with: .color(WidgetGlass.accent), lineWidth: 2)
        }
    }
}

private struct SleepBarChart: View {
    let days: [HealthWidgetDay]

    var body: some View {
        GeometryReader { proxy in
            let maxHeight = max(1, proxy.size.height - 14)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days) { day in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(WidgetGlass.accent.opacity(0.14))
                                .frame(maxHeight: .infinity)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(WidgetGlass.accent.opacity(day.sleepHours ?? 0 >= 8 ? 1 : 0.7))
                                .frame(height: max(3, maxHeight * CGFloat(min(day.sleepHours ?? 0, 10) / 10)))
                        }
                        Text(String(Self.weekdayFormatter.string(from: day.date).prefix(1)))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(height: 1)
                    .offset(y: maxHeight * CGFloat(1 - 8.0 / 10.0))
            }
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()
}

/// Home-screen sizes sit on the dark glass panel in both appearances, as on the boards.
/// Accessory sizes keep the system's lock-screen rendering.
private struct HealthWidgetGlassBackground: ViewModifier {
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        switch family {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular:
            content.containerBackground(for: .widget) { Color.clear }
        default:
            content
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { WidgetGlassPanelBackground() }
        }
    }
}

private extension View {
    func healthWidgetBackground() -> some View {
        modifier(HealthWidgetGlassBackground())
    }
}

private enum HealthWidgetMath {
    static func progress(_ value: Double?, goal: Double) -> Double {
        guard let value, goal > 0 else { return 0 }
        return max(0, value / goal)
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private enum HealthWidgetFormat {
    static func whole(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(Int(value.rounded()))
    }

    static func steps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return NumberFormatter.healthInteger.string(from: NSNumber(value: Int(value.rounded()))) ?? "—"
    }

    static func compactNumber(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 10_000 {
            return String(format: "%.0fk", value / 1_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", value / 1_000)
        }
        return String(Int(value.rounded()))
    }

    static func hours(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        let hours = Int(value)
        let minutes = Int(((value - Double(hours)) * 60).rounded())
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    static func bpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))"
    }

    static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) ms"
    }

    static func time(_ date: Date) -> String {
        DateFormatter.healthWidgetTime.string(from: date)
    }
}

private extension NumberFormatter {
    static let healthInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private extension DateFormatter {
    static let healthWidgetTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview(as: .systemMedium) {
    HealthSummaryWidget()
} timeline: {
    HealthWidgetEntry(date: .now, snapshot: .placeholder)
}

/// Written by the app from the coverage ledger.
struct ArchiveWidgetSnapshot: Codable {
    let archivedCount: Int
    let gapCount: Int
    let nextRun: Date?
    /// Coverage status raw values for the 14 days before today, oldest first. Absent in older snapshots.
    let recentDays: [String]?

    static let key = "healthMdArchiveWidgetSnapshot.v1"

    static func load() -> ArchiveWidgetSnapshot? {
        UserDefaults(suiteName: "group.com.codybontecou.obsidianhealth")?
            .data(forKey: key)
            .flatMap { try? JSONDecoder().decode(ArchiveWidgetSnapshot.self, from: $0) }
    }
}

struct ArchiveWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ArchiveWidgetSnapshot?
}

struct ArchiveWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ArchiveWidgetEntry {
        ArchiveWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ArchiveWidgetEntry) -> Void) {
        completion(ArchiveWidgetEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ArchiveWidgetEntry>) -> Void) {
        let entry = ArchiveWidgetEntry(date: .now, snapshot: .load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3_600))))
    }
}

struct ArchiveWidget: Widget {
    static let kind = "ArchiveWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ArchiveWidgetProvider()) { entry in
            ArchiveWidgetView(entry: entry)
        }
        .configurationDisplayName("Archive")
        .description("Your archived days and gaps.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ArchiveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ArchiveWidgetEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { WidgetGlassPanelBackground() }
    }

    /// WidgetSmallGlass.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetCrystalHeart(size: 24)
                Spacer(minLength: 4)
                if let next = entry.snapshot?.nextRun {
                    Text(next, style: .time)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetGlass.secondaryText)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "\(entry.snapshot?.archivedCount ?? 0)")
                .font(.system(size: 50, weight: .bold))
                .kerning(-2)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            Text("days in \(entry.date.formatted(.dateTime.month(.wide)))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WidgetGlass.secondaryText)
        }
    }

    /// WidgetMediumGlass.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                WidgetCrystalHeart(size: 22)
                Text("Archive").font(.system(size: 14, weight: .bold))
                Spacer(minLength: 4)
                if let next = entry.snapshot?.nextRun {
                    Text("Next \(next, style: .time)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetGlass.secondaryText)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(entry.snapshot?.archivedCount ?? 0)")
                    .font(.system(size: 42, weight: .bold))
                    .kerning(-1.6)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                Text("days in \(entry.date.formatted(.dateTime.month(.wide)))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetGlass.secondaryText)
                Spacer(minLength: 4)
                if let gaps = entry.snapshot?.gapCount, gaps > 0 {
                    Text(gaps == 1 ? "1 gap" : "\(gaps) gaps")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetGlass.coral)
                }
            }
            Spacer(minLength: 0)
            if let days = entry.snapshot?.recentDays, !days.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, status in
                        ArchiveWidgetDayTile(status: status)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

/// One day in the medium Archive widget strip: filled when covered, dashed coral when missing.
private struct ArchiveWidgetDayTile: View {
    let status: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            switch status {
            case "complete":
                shape.fill(WidgetGlass.covered)
                    .overlay(shape.fill(Self.topHighlight))
            case "partial":
                shape.fill(WidgetGlass.covered)
                    .overlay(shape.fill(Self.topHighlight))
                    .overlay(shape.strokeBorder(WidgetGlass.amber, lineWidth: 1.5))
            case "missing":
                shape.strokeBorder(WidgetGlass.coral, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            default:
                shape.fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: 14, height: 14)
    }

    /// The board's `inset 0 1px 0 rgba(255,255,255,0.22)`: a 1 pt highlight along the top edge of a 14 pt tile.
    private static let topHighlight = LinearGradient(
        stops: [
            .init(color: Color.white.opacity(0.22), location: 0),
            .init(color: Color.white.opacity(0.22), location: 1.0 / 14.0),
            .init(color: .clear, location: 1.0 / 14.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
