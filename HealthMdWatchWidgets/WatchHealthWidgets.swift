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

struct DailyActivityWidget: Widget {
    static let kind = "DailyActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHealthTimelineProvider()) { entry in
            DailyActivityWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Activity")
        .description("Glance at today's steps, active energy, exercise minutes, and stand hours.")
        .supportedFamilies(Self.supportedFamilies)
    }

    private static var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner]
        #else
        [.accessoryRectangular, .accessoryCircular, .accessoryInline]
        #endif
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
        .supportedFamilies(Self.supportedFamilies)
    }

    private static var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner]
        #else
        [.accessoryRectangular, .accessoryCircular, .accessoryInline]
        #endif
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
