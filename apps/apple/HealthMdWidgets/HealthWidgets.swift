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
                    SummarySmallView(day: entry.snapshot.today)
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
                    ActivitySmallView(day: entry.snapshot.today)
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
                    HeartRangeMediumView(snapshot: entry.snapshot)
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
            AppIconMark(size: 24)
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
                MiniMetric(icon: "bed.double.fill", value: HealthWidgetFormat.hours(day.sleepHours), tint: .indigo)
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
                WidgetHeader(title: "Health.md", icon: "heart.text.square", tint: .pink)
                Text(HealthWidgetFormat.steps(snapshot.today.steps))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text("steps today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                MetricRow(icon: "flame.fill", title: "Move", value: "\(HealthWidgetFormat.whole(snapshot.today.activeEnergyKilocalories)) kcal", tint: .orange)
                MetricRow(icon: "timer", title: "Exercise", value: "\(HealthWidgetFormat.whole(snapshot.today.exerciseMinutes)) min", tint: .green)
                MetricRow(icon: "bed.double.fill", title: "Sleep", value: HealthWidgetFormat.hours(snapshot.today.sleepHours), tint: .indigo)
                MetricRow(icon: "waveform.path.ecg", title: "HRV", value: HealthWidgetFormat.milliseconds(snapshot.today.heartRateVariabilityMS), tint: .cyan)
            }
        }
    }
}

private struct SummaryLargeView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetHeader(title: "Health.md", icon: "heart.text.square", tint: .pink)
            HStack(alignment: .center, spacing: 18) {
                TripleActivityRingView(day: snapshot.today, lineWidth: 10)
                    .frame(width: 106, height: 106)
                VStack(spacing: 8) {
                    MetricRow(icon: "figure.walk", title: "Steps", value: HealthWidgetFormat.steps(snapshot.today.steps), tint: .green)
                    MetricRow(icon: "flame.fill", title: "Move", value: "\(HealthWidgetFormat.whole(snapshot.today.activeEnergyKilocalories)) kcal", tint: .orange)
                    MetricRow(icon: "heart.fill", title: "Resting", value: HealthWidgetFormat.bpm(snapshot.today.restingHeartRate), tint: .red)
                }
            }
            Divider().opacity(0.35)
            VStack(alignment: .leading, spacing: 8) {
                Text("7-day sleep")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SleepBarChart(days: snapshot.recentSevenDays)
                    .frame(height: 54)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Heart range")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HeartRangeChart(days: snapshot.recentSevenDays)
                    .frame(height: 58)
            }
        }
    }
}

private struct ActivitySmallView: View {
    let day: HealthWidgetDay

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(title: "Rings", icon: "flame.fill", tint: .orange)
            TripleActivityRingView(day: day, lineWidth: 12)
                .padding(4)
            HStack(spacing: 8) {
                Text("\(HealthWidgetFormat.whole(day.activeEnergyKilocalories))")
                    .foregroundStyle(.orange)
                Text("/ \(HealthWidgetFormat.whole(day.exerciseMinutes))m")
                    .foregroundStyle(.green)
                Text("/ \(day.standHours ?? 0)h")
                    .foregroundStyle(.cyan)
            }
            .font(.caption2.weight(.bold))
            .monospacedDigit()
        }
    }
}

private struct ActivityMediumView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        HStack(spacing: 16) {
            TripleActivityRingView(day: snapshot.today, lineWidth: 11)
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "Activity", icon: "flame.fill", tint: .orange)
                MetricRow(icon: "flame.fill", title: "Move", value: "\(HealthWidgetFormat.whole(snapshot.today.activeEnergyKilocalories)) / 500 kcal", tint: .orange)
                MetricRow(icon: "timer", title: "Exercise", value: "\(HealthWidgetFormat.whole(snapshot.today.exerciseMinutes)) / 30 min", tint: .green)
                MetricRow(icon: "figure.stand", title: "Stand", value: "\(snapshot.today.standHours ?? 0) / 12 hr", tint: .cyan)
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
        .tint(.green)
    }
}

private struct ActivityRectangularAccessory: View {
    let day: HealthWidgetDay

    var body: some View {
        HStack(spacing: 8) {
            TripleActivityRingView(day: day, lineWidth: 4)
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

private struct HeartRangeMediumView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetHeader(title: "Heart Range", icon: "heart.fill", tint: .red)
                Spacer()
                Text(HealthWidgetFormat.bpm(snapshot.today.averageHeartRate))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.red)
                    .monospacedDigit()
            }
            HeartRangeChart(days: snapshot.recentSevenDays)
                .frame(height: 78)
            HStack {
                Text("Min \(HealthWidgetFormat.bpm(snapshot.today.heartRateMin))")
                Spacer()
                Text("Max \(HealthWidgetFormat.bpm(snapshot.today.heartRateMax))")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }
}

private struct HeartRangeLargeView: View {
    let snapshot: HealthWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "Heart Range", icon: "heart.fill", tint: .red)
            HeartRangeChart(days: snapshot.recentSevenDays)
                .frame(height: 150)
            HStack(spacing: 10) {
                MetricTile(title: "Avg", value: HealthWidgetFormat.bpm(snapshot.today.averageHeartRate), tint: .red)
                MetricTile(title: "Resting", value: HealthWidgetFormat.bpm(snapshot.today.restingHeartRate), tint: .pink)
                MetricTile(title: "HRV", value: HealthWidgetFormat.milliseconds(snapshot.today.heartRateVariabilityMS), tint: .cyan)
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
            WidgetHeader(title: "Sleep", icon: "bed.double.fill", tint: .indigo)
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
                .tint(.indigo)
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
                WidgetHeader(title: "Sleep", icon: "bed.double.fill", tint: .indigo)
                Spacer()
                Text(HealthWidgetFormat.hours(snapshot.today.sleepHours))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.indigo)
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
            WidgetHeader(title: "Sleep", icon: "bed.double.fill", tint: .indigo)
            HStack(spacing: 10) {
                MetricTile(title: "Last night", value: HealthWidgetFormat.hours(snapshot.today.sleepHours), tint: .indigo)
                MetricTile(title: "Average", value: HealthWidgetFormat.hours(HealthWidgetMath.average(snapshot.recentSevenDays.compactMap(\.sleepHours))), tint: .purple)
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
                AppIconMark(size: 14)
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
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TripleActivityRingView: View {
    let day: HealthWidgetDay
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            ActivityRing(progress: HealthWidgetMath.progress(day.activeEnergyKilocalories, goal: 500), color: .orange, lineWidth: lineWidth)
                .padding(0)
            ActivityRing(progress: HealthWidgetMath.progress(day.exerciseMinutes, goal: 30), color: .green, lineWidth: lineWidth)
                .padding(lineWidth * 1.45)
            ActivityRing(progress: HealthWidgetMath.progress(day.standHours.map(Double.init), goal: 12), color: .cyan, lineWidth: lineWidth)
                .padding(lineWidth * 2.9)
            VStack(spacing: 0) {
                Text(HealthWidgetFormat.compactNumber(day.steps))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Text("steps")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.7)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
                context.fill(capsule, with: .color(.red.opacity(0.28)))

                let avgY = yPosition(point.avg)
                if didStartLine {
                    line.addLine(to: CGPoint(x: x, y: avgY))
                } else {
                    line.move(to: CGPoint(x: x, y: avgY))
                    didStartLine = true
                }

                let dot = Path(ellipseIn: CGRect(x: x - 3.5, y: avgY - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(.red))
            }

            context.stroke(line, with: .color(.red), lineWidth: 2)
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
                                .fill(Color.indigo.opacity(0.14))
                                .frame(maxHeight: .infinity)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day.sleepHours ?? 0 >= 8 ? Color.indigo : Color.purple)
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

private extension View {
    func healthWidgetBackground() -> some View {
        self
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(.systemBackground), Color.pink.opacity(0.08), Color.indigo.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
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
