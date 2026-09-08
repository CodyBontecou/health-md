#if os(iOS)
import SwiftUI
import Charts

enum InsightSleepStage: String, CaseIterable, Identifiable {
    case rem, core, deep, unspecified
    var id: Self { self }
    var title: String {
        switch self {
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .unspecified: "Unspecified"
        }
    }
    var color: Color {
        switch self {
        case .rem: .cyan
        case .core: .blue
        case .deep: .indigo
        case .unspecified: .gray
        }
    }
}

struct SleepComposition {
    struct Portion: Identifiable {
        let stage: InsightSleepStage
        let seconds: Double
        var id: InsightSleepStage { stage }
    }
    let portions: [Portion]
    let total: Double
    var hasStages: Bool { portions.contains { $0.stage != .unspecified } }

    /// Preserve the existing sleep reducer. Conflicting stage totals cannot be
    /// represented as parts of the total, so show total sleep alone in that case.
    init?(sleep: SleepData) {
        let total = sleep.totalDuration
        let durations = [sleep.remSleep, sleep.coreSleep, sleep.deepSleep]
        guard total.isFinite, total > 0,
              durations.allSatisfy({ $0.isFinite && $0 >= 0 }),
              durations.reduce(0, +) <= total else { return nil }
        self.total = total
        var portions = zip([InsightSleepStage.rem, .core, .deep], durations)
            .filter { $0.1 > 0 }.map { Portion(stage: $0.0, seconds: $0.1) }
        let unspecified = total - durations.reduce(0, +)
        if unspecified > 0 { portions.append(Portion(stage: .unspecified, seconds: unspecified)) }
        self.portions = portions
    }
}

struct SleepInsightCard: View {
    let days: [HealthInsightDay]
    @State private var selection: String?
    @State private var selectedStage: InsightSleepStage?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var day: HealthInsightDay? {
        if let selection { return days.first { insightDayKey($0.date) == selection } }
        return days.last { $0.values[.sleep] != nil }
    }
    private var composition: SleepComposition? { day?.sleepComposition }
    private var portion: SleepComposition.Portion? { composition?.portions.first { $0.stage == selectedStage } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InsightCardHeading(title: "Sleep", symbol: "moon.zzz.fill", color: .blue, dayCount: days.count)
            if let day {
                Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let composition, composition.hasStages {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(spacing: 20))
                layout {
                    sleepRing(composition)
                    stageLegend(composition)
                }
            } else {
                InsightReading(metric: .sleep, day: day)
                if day?.values[.sleep] != nil {
                    Text("Stage breakdown unavailable for this day.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if days.contains(where: { $0.values[.sleep] != nil }) {
                Divider()
                Text("Time asleep").font(.subheadline.weight(.medium))
                dailyChart
                Text("Tap a day to explore its sleep stages.").font(.caption).foregroundStyle(.secondary)
            } else {
                InsightEmptyReading()
            }
            Text("Apple Health · Noon to noon, including naps")
                .font(.caption).foregroundStyle(.secondary)
        }
        .feedSurface()
        .onChange(of: selection) { _, _ in selectedStage = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.health.sleep")
    }

    private func sleepRing(_ composition: SleepComposition) -> some View {
        Chart(composition.portions) { item in
            SectorMark(angle: .value("Time asleep", item.seconds), innerRadius: .ratio(0.79), angularInset: 2)
                .cornerRadius(4)
                .foregroundStyle(item.stage.color.opacity(selectedStage == nil || selectedStage == item.stage ? 1 : 0.2))
                .accessibilityLabel(item.stage.title)
                .accessibilityValue(HealthInsightMetric.sleep.formatted(item.seconds / 3_600))
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 5) {
                Text(portion?.stage.title ?? "Asleep").font(.caption).foregroundStyle(.secondary)
                Text(HealthInsightMetric.sleep.formatted((portion?.seconds ?? composition.total) / 3_600))
                    .font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                if let portion {
                    Text((portion.seconds / composition.total).formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center).padding(25)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.sleep.composition.value")
        }
        .frame(width: typeSize.isAccessibilitySize ? 240 : 155, height: typeSize.isAccessibilitySize ? 240 : 155)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.sleep.composition")
    }

    private func stageLegend(_ composition: SleepComposition) -> some View {
        VStack(spacing: 1) {
            ForEach(composition.portions) { item in
                Button {
                    selectedStage = selectedStage == item.stage ? nil : item.stage
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(item.stage.color).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.stage.title).font(.caption).foregroundStyle(.secondary)
                            Text(HealthInsightMetric.sleep.formatted(item.seconds / 3_600))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6).frame(minHeight: 44)
                    .background(selectedStage == item.stage ? item.stage.color.opacity(0.1) : .clear,
                                in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedStage == item.stage ? .isSelected : [])
                .accessibilityHint("Show share of time asleep. Tap again for total sleep.")
                .accessibilityIdentifier("home.sleep.stage.\(item.stage.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dailyChart: some View {
        Chart {
            ForEach(days) { day in
                if let composition = day.sleepComposition {
                    ForEach(composition.portions) { item in
                        BarMark(x: .value("Day", insightDayKey(day.date)),
                                y: .value("Hours asleep", item.seconds / 3_600), width: .ratio(0.6))
                            .foregroundStyle(item.stage.color.opacity(day.id == self.day?.id ? 1 : 0.55))
                            .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(item.stage.title)")
                            .accessibilityValue(HealthInsightMetric.sleep.formatted(item.seconds / 3_600))
                    }
                } else if let hours = day.values[.sleep] {
                    BarMark(x: .value("Day", insightDayKey(day.date)), y: .value("Hours asleep", hours), width: .ratio(0.6))
                        .foregroundStyle(.gray.opacity(0.4))
                }
            }
            if let selection {
                RuleMark(x: .value("Selected day", selection)).foregroundStyle(Color(uiColor: .quaternaryLabel))
            }
        }
        .chartXScale(domain: days.map { insightDayKey($0.date) })
        .chartYScale(domain: 0...max(1, (days.compactMap { $0.values[.sleep] }.max() ?? 1) * 1.1))
        .chartXSelection(value: $selection)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartXAxis {
            AxisMarks(values: insightAxisKeys(days.map(\.date), compact: typeSize.isAccessibilitySize)) { value in
                AxisValueLabel(anchor: value.count == 1 ? .top : value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top) {
                    if let key = value.as(String.self), let day = days.first(where: { insightDayKey($0.date) == key }) {
                        Text(insightAxisLabel(day.date, dayCount: days.count)).fixedSize()
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { AxisValueLabel() } }
        .frame(height: 115)
        .accessibilityLabel("Time asleep and recorded stages over \(days.count) selected days")
        .accessibilityIdentifier("home.health.sleep.chart")
        .accessibilityAdjustableAction { direction in
            let current = days.firstIndex { $0.id == day?.id } ?? max(0, days.count - 1)
            let next = direction == .increment ? min(days.count - 1, current + 1) : max(0, current - 1)
            if days.indices.contains(next) { selection = insightDayKey(days[next].date) }
        }
    }
}
#endif
