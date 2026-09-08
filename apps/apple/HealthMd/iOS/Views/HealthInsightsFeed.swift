#if os(iOS)
import SwiftUI
import Charts
import Combine

/// The feed reuses the daily export reducers, with a bounded, summary-only read.
/// Missing HealthKit readings remain missing; the feed never persists health values.
enum HealthInsightMetric: String, CaseIterable, Identifiable {
    case steps, activeEnergy, exercise, sleep, restingHeartRate, hrv, respiratoryRate
    var id: Self { self }
    var metricID: String {
        switch self {
        case .steps: "steps"
        case .activeEnergy: "active_energy"
        case .exercise: "exercise_time"
        case .sleep: "sleep_total"
        case .restingHeartRate: "resting_heart_rate"
        case .hrv: "hrv"
        case .respiratoryRate: "respiratory_rate"
        }
    }
    var title: String {
        switch self {
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        case .exercise: "Exercise"
        case .sleep: "Sleep"
        case .restingHeartRate: "Resting heart rate"
        case .hrv: "HRV · SDNN"
        case .respiratoryRate: "Respiratory rate"
        }
    }
    var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .activeEnergy: "flame.fill"
        case .exercise: "figure.run"
        case .sleep: "moon.zzz.fill"
        case .restingHeartRate: "heart.fill"
        case .hrv: "waveform.path.ecg"
        case .respiratoryRate: "lungs.fill"
        }
    }
    var color: Color {
        switch self {
        case .steps: .orange
        case .activeEnergy: .pink
        case .exercise: .green
        case .sleep: .blue
        case .restingHeartRate: .red
        case .hrv: .teal
        case .respiratoryRate: .cyan
        }
    }
    var unit: String {
        switch self {
        case .steps: "steps"
        case .activeEnergy: "kcal"
        case .exercise: "min"
        case .sleep: "hours"
        case .restingHeartRate: "bpm"
        case .hrv: "ms"
        case .respiratoryRate: "breaths/min"
        }
    }
    var explanation: String {
        switch self {
        case .steps, .activeEnergy: "Daily totals · Apple Health"
        case .exercise: "Apple Exercise Time · Daily totals"
        case .sleep: "Time asleep · Apple Health"
        case .restingHeartRate: "Latest reading each day · Apple Health"
        case .hrv: "Daily average · Apple Health SDNN"
        case .respiratoryRate: "Daily average · Apple Health"
        }
    }
    func value(in data: HealthData) -> Double? {
        let value: Double? = switch self {
        case .steps: data.activity.steps.map(Double.init)
        case .activeEnergy: data.activity.activeCalories
        case .exercise: data.activity.exerciseMinutes
        case .sleep: data.sleep.totalDuration > 0 ? data.sleep.totalDuration / 3_600 : nil
        case .restingHeartRate: data.heart.restingHeartRate
        case .hrv: data.heart.hrv
        case .respiratoryRate: data.vitals.respiratoryRateAvg
        }
        return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    func formatted(_ value: Double) -> String {
        if self == .sleep {
            let minutes = Int((value * 60).rounded())
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return value.formatted(.number.precision(.fractionLength(self == .respiratoryRate ? 1 : 0)))
    }

    static let movement: [Self] = [.steps, .activeEnergy, .exercise]
    static let signals: [Self] = [.restingHeartRate, .hrv, .respiratoryRate]
    static var readMetricIDs: Set<String> {
        Set(allCases.map(\.metricID)).union(["sleep_core", "sleep_rem", "sleep_deep"])
    }
}

struct HealthInsightDay: Identifiable {
    let date: Date
    let values: [HealthInsightMetric: Double]
    var sleepComposition: SleepComposition? = nil
    var id: Date { date }
}

@MainActor
final class HealthInsightsModel: ObservableObject {
    typealias Fetch = (Date, MetricSelectionState, TimeZone) async throws -> HealthData
    @Published private(set) var loadedRange: InsightDateRange?
    @Published private(set) var days: [HealthInsightDay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failedDayCount = 0
    @Published private(set) var completedDayCount = 0
    private var lastLoadedAt: Date?
    private var requestID = UUID()
    private let fetch: Fetch

    init(fetch: @escaping Fetch) { self.fetch = fetch }

    convenience init(healthKitManager: HealthKitManager) {
        self.init { date, selection, timeZone in
            #if DEBUG
            if TestMode.useHealthKitExportPreviewFixtures {
                return UITestHealthKitFixtures.overviewHealthData(for: date)
            }
            #endif
            return try await healthKitManager.fetchHealthData(
                for: date, detailPolicy: .summary, metricSelection: selection, timeZone: timeZone
            )
        }
    }

    func load(authorized: Bool, range requestedRange: InsightDateRange? = nil, force: Bool = false,
              now: Date = .now, calendar: Calendar = .current) async {
        guard authorized else {
            requestID = UUID()
            days = []
            completedDayCount = 0
            failedDayCount = 0
            lastLoadedAt = nil
            loadedRange = nil
            isLoading = false
            return
        }
        let range = requestedRange ?? InsightDateRange(ending: now, now: now, calendar: calendar)
        let request = UUID()
        requestID = request
        if !force, loadedRange == range, let lastLoadedAt,
           (0..<300).contains(now.timeIntervalSince(lastLoadedAt)),
           range.calendar.isDate(lastLoadedAt, inSameDayAs: now) {
            isLoading = false
            return
        }
        if loadedRange != range {
            days = []
            completedDayCount = 0
            failedDayCount = 0
            loadedRange = nil
            lastLoadedAt = nil
        }
        isLoading = true
        completedDayCount = 0
        defer { if requestID == request { isLoading = false } }
        let selection = MetricSelectionState()
        selection.enabledMetrics = HealthInsightMetric.readMetricIDs
        selection.enabledCategories = []
        var loaded: [HealthInsightDay] = []
        var failures = 0
        for date in range.dates {
            guard !Task.isCancelled, requestID == request else { return }
            do {
                let data = try await fetch(date, selection, range.calendar.timeZone)
                let values = Dictionary(uniqueKeysWithValues: HealthInsightMetric.allCases.compactMap { metric in
                    metric.value(in: data).map { (metric, $0) }
                })
                loaded.append(HealthInsightDay(date: date, values: values,
                                               sleepComposition: SleepComposition(sleep: data.sleep)))
                if !data.partialFailures.isEmpty { failures += 1 }
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                loaded.append(HealthInsightDay(date: date, values: [:]))
            }
            guard !Task.isCancelled, requestID == request else { return }
            completedDayCount = loaded.count
        }
        guard !Task.isCancelled, requestID == request else { return }
        days = loaded
        loadedRange = range
        failedDayCount = failures
        lastLoadedAt = now
    }
}

struct HealthInsightsFeed: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @StateObject private var model: HealthInsightsModel
    @ObservedObject private var history = ExportHistoryManager.shared
    @Environment(\.scenePhase) private var scenePhase
    let refreshID: UUID
    @State private var sceneRefreshID = UUID()
    @State private var lastRefreshID: UUID?
    @State private var dateSelection = InsightDateSelection()
    @State private var referenceNow = Date.now
    @State private var localCalendar = Calendar.current
    private var range: InsightDateRange { dateSelection.range(now: referenceNow, calendar: localCalendar) }
    private struct LoadID: Hashable {
        let authorized: Bool
        let refresh: UUID
        let scene: UUID
        let range: InsightDateRange
    }
    let onConnectHealth: () -> Void
    let onViewActivity: () -> Void

    init(healthKitManager: HealthKitManager, refreshID: UUID, onConnectHealth: @escaping () -> Void,
         onViewActivity: @escaping () -> Void) {
        self.healthKitManager = healthKitManager
        self.refreshID = refreshID
        self.onConnectHealth = onConnectHealth
        self.onViewActivity = onViewActivity
        _model = StateObject(wrappedValue: HealthInsightsModel(healthKitManager: healthKitManager))
    }

    var body: some View {
        VStack(spacing: 16) {
            InsightDateControls(selection: $dateSelection, range: range, now: referenceNow)
            if !healthKitManager.isAuthorized {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "heart.text.clipboard").font(.largeTitle).foregroundStyle(Color.accent)
                    Text("Your health, at a glance").font(.title2.bold())
                    Text("Connect Apple Health to explore your movement, sleep stages, and heart and breathing trends.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Connect Apple Health", action: onConnectHealth)
                        .modifier(HealthGlassActionStyle(prominent: true))
                }
                .feedSurface()
            } else if model.loadedRange != range {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reading your health data…").font(.subheadline)
                        Text("\(model.completedDayCount) of \(range.dayCount) days").font(.caption).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
                .feedSurface()
                .accessibilityIdentifier("home.health.loading")
            } else {
                MovementInsightCard(days: model.days).id(range)
                SleepInsightCard(days: model.days).id(range)
                HealthSignalsCard(days: model.days).id(range)
                if model.failedDayCount > 0 {
                    Label("Some readings could not be loaded. Pull down to try again.", systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("home.health.partial")
                }
                if model.days.allSatisfy({ $0.values.isEmpty }) {
                    Button("Review Health access", action: onConnectHealth)
                        .modifier(HealthGlassActionStyle())
                }
            }
            ExportActivityChart(history: history.history, range: range, onViewActivity: onViewActivity)
        }
        .task(id: LoadID(authorized: healthKitManager.isAuthorized, refresh: refreshID, scene: sceneRefreshID, range: range)) {
            await model.load(authorized: healthKitManager.isAuthorized, range: range,
                             force: lastRefreshID != nil && lastRefreshID != refreshID)
            if !Task.isCancelled { lastRefreshID = refreshID }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateCalendarContext() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in updateCalendarContext() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in updateCalendarContext() }
    }

    private func updateCalendarContext() {
        referenceNow = .now
        dateSelection.rebase(from: localCalendar, to: .current)
        localCalendar = .current
        sceneRefreshID = UUID()
    }
}

struct ExportActivityDay: Identifiable {
    let date: Date
    let completed: Int
    let needsAttention: Int
    var id: Date { date }

    static func recent(_ history: [ExportHistoryEntry], range requestedRange: InsightDateRange? = nil,
                       now: Date = .now, calendar: Calendar = .current) -> [Self] {
        let range = requestedRange ?? InsightDateRange(ending: now, now: now, calendar: calendar)
        return range.dates.map { date in
            let runs = history.filter { range.calendar.isDate($0.timestamp, inSameDayAs: date) }
            return Self(date: date, completed: runs.filter(\.success).count,
                        needsAttention: runs.filter { !$0.success }.count)
        }
    }
}

private struct ExportActivityChart: View {
    let history: [ExportHistoryEntry]
    let range: InsightDateRange
    let onViewActivity: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var days: [ExportActivityDay] { ExportActivityDay.recent(history, range: range) }
    private var total: Int { days.reduce(0) { $0 + $1.completed + $1.needsAttention } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Export activity", systemImage: "arrow.up.document")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("History", systemImage: "arrow.up.right", action: onViewActivity)
                    .font(.caption.weight(.medium)).labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("home.export.history")
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(total, format: .number).font(.largeTitle.bold()).monospacedDigit()
                Text("\(total == 1 ? "run" : "runs") in \(range.dayCount) \(range.dayCount == 1 ? "day" : "days")").font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.export.activity.count")
            Chart(days) { day in
                BarMark(x: .value("Day", insightDayKey(day.date)), y: .value("Runs", day.completed), width: .ratio(0.6))
                    .foregroundStyle(by: .value("Result", "Completed")).cornerRadius(4)
                    .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), completed")
                BarMark(x: .value("Day", insightDayKey(day.date)), y: .value("Runs", day.needsAttention), width: .ratio(0.6))
                    .foregroundStyle(by: .value("Result", "Needs attention")).cornerRadius(4)
                    .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), needs attention")
            }
            .chartForegroundStyleScale(["Completed": Color.teal, "Needs attention": Color.orange])
            .chartXScale(domain: days.map { insightDayKey($0.date) })
            .chartYScale(domain: 0...max(1, days.map { $0.completed + $0.needsAttention }.max() ?? 1))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: insightAxisKeys(days.map(\.date), compact: typeSize.isAccessibilitySize)) { value in
                    AxisValueLabel(anchor: value.count == 1 ? .top : value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top) {
                        if let key = value.as(String.self), let day = days.first(where: { insightDayKey($0.date) == key }) {
                            Text(insightAxisLabel(day.date, dayCount: days.count)).fixedSize()
                        }
                    }
                }
            }
            .frame(height: 145)
            .accessibilityLabel("Export runs, \(range.label)")
            Text(total == 0 ? "No saved runs in this date range. History keeps the most recent 50 runs." : "Based on the most recent 50 saved runs.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .feedSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.export.activity")
    }
}

private struct FeedSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }
}

extension View {
    func feedSurface() -> some View { modifier(FeedSurface()) }
}

#endif
