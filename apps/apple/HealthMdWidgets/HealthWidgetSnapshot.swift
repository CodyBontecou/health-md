import Foundation
import HealthKit

struct HealthWidgetDay: Codable, Hashable, Identifiable, Sendable {
    var id: Date { date }

    let date: Date

    var steps: Double?
    var activeEnergyKilocalories: Double?
    var exerciseMinutes: Double?
    var standHours: Int?

    var sleepHours: Double?
    var sleepStart: Date?
    var sleepEnd: Date?

    var restingHeartRate: Double?
    var averageHeartRate: Double?
    var heartRateMin: Double?
    var heartRateMax: Double?
    var heartRateVariabilityMS: Double?
    var bloodOxygenPercent: Double?

    var hasAnyData: Bool {
        steps != nil || activeEnergyKilocalories != nil || exerciseMinutes != nil || standHours != nil ||
        sleepHours != nil || restingHeartRate != nil || averageHeartRate != nil || heartRateVariabilityMS != nil ||
        bloodOxygenPercent != nil
    }

    static func placeholder(offsetFromToday offset: Int = 0, calendar: Calendar = .current) -> HealthWidgetDay {
        let base = calendar.startOfDay(for: .now)
        let date = calendar.date(byAdding: .day, value: offset, to: base) ?? base
        let wave = Double((offset + 14) % 7)
        return HealthWidgetDay(
            date: date,
            steps: 7_200 + wave * 520,
            activeEnergyKilocalories: 340 + wave * 24,
            exerciseMinutes: 22 + wave * 2,
            standHours: 8 + Int(wave.truncatingRemainder(dividingBy: 4)),
            sleepHours: 6.6 + wave * 0.16,
            sleepStart: calendar.date(byAdding: .hour, value: -9, to: date),
            sleepEnd: calendar.date(byAdding: .hour, value: -1, to: date),
            restingHeartRate: 58 + wave.truncatingRemainder(dividingBy: 4),
            averageHeartRate: 72 + wave,
            heartRateMin: 48 + wave.truncatingRemainder(dividingBy: 3),
            heartRateMax: 128 + wave * 4,
            heartRateVariabilityMS: 44 + wave * 1.7,
            bloodOxygenPercent: 96.3 + wave * 0.12
        )
    }
}

struct HealthWidgetSnapshot: Codable, Hashable, Sendable {
    let lastUpdated: Date
    let days: [HealthWidgetDay]

    var today: HealthWidgetDay {
        days.last ?? HealthWidgetDay.placeholder()
    }

    var hasAnyData: Bool {
        days.contains { $0.hasAnyData }
    }

    var recentSevenDays: [HealthWidgetDay] {
        Array(days.suffix(7))
    }

    static let placeholder = HealthWidgetSnapshot(
        lastUpdated: .now,
        days: (-13...0).map { HealthWidgetDay.placeholder(offsetFromToday: $0) }
    )
}

enum HealthWidgetSnapshotStore {
    private static let suiteName = "group.com.codybontecou.obsidianhealth"
    private static let key = "healthMdHomeWidgetSnapshot.v1"

    static func load() -> HealthWidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HealthWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: HealthWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func loadIfFresh(maxAge: TimeInterval = 60 * 60 * 4, now: Date = .now) -> HealthWidgetSnapshot? {
        guard let snapshot = load() else { return nil }
        return now.timeIntervalSince(snapshot.lastUpdated) <= maxAge ? snapshot : nil
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

struct QuantityRangeStats: Hashable, Sendable {
    var average: Double?
    var minimum: Double?
    var maximum: Double?
}

struct SleepSummary: Hashable, Sendable {
    var hours: Double?
    var start: Date?
    var end: Date?
}

enum HealthWidgetSnapshotProvider {
    private static let store = HKHealthStore()

    static func fetchRecentDays(dayCount: Int = 14, calendar: Calendar = .current) async -> HealthWidgetSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else {
            return HealthWidgetSnapshot(lastUpdated: .now, days: [])
        }

        let count = max(1, min(dayCount, 30))
        let today = calendar.startOfDay(for: .now)
        var days: [HealthWidgetDay] = []
        days.reserveCapacity(count)

        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            days.append(await fetchDay(date, calendar: calendar))
        }

        return HealthWidgetSnapshot(lastUpdated: .now, days: days)
    }

    private static func fetchDay(_ dayStart: Date, calendar: Calendar) async -> HealthWidgetDay {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: [.strictStartDate])

        async let steps = cumulativeQuantity(.stepCount, unit: .count(), predicate: predicate)
        async let activeEnergy = cumulativeQuantity(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let exerciseMinutes = cumulativeQuantity(.appleExerciseTime, unit: .minute(), predicate: predicate)
        async let standHours = stoodHours(predicate: predicate)
        async let sleep = sleepSummary(endingNear: dayStart, calendar: calendar)
        async let restingHeartRate = mostRecentQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: predicate)
        async let heartRate = discreteQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: predicate)
        async let hrv = averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: predicate)
        async let bloodOxygen = averageQuantity(.oxygenSaturation, unit: .percent(), predicate: predicate)

        let sleepResult = await sleep
        let heartRateResult = await heartRate
        return HealthWidgetDay(
            date: dayStart,
            steps: await steps,
            activeEnergyKilocalories: await activeEnergy,
            exerciseMinutes: await exerciseMinutes,
            standHours: await standHours,
            sleepHours: sleepResult.hours,
            sleepStart: sleepResult.start,
            sleepEnd: sleepResult.end,
            restingHeartRate: await restingHeartRate,
            averageHeartRate: heartRateResult.average,
            heartRateMin: heartRateResult.minimum,
            heartRateMax: heartRateResult.maximum,
            heartRateVariabilityMS: await hrv,
            bloodOxygenPercent: (await bloodOxygen).map { $0 * 100 }
        )
    }

    private static func cumulativeQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private static func averageQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private static func discreteQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> QuantityRangeStats {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return QuantityRangeStats() }

        return await withCheckedContinuation { continuation in
            let options: HKStatisticsOptions = [.discreteAverage, .discreteMin, .discreteMax]
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, statistics, _ in
                let stats = QuantityRangeStats(
                    average: statistics?.averageQuantity()?.doubleValue(for: unit),
                    minimum: statistics?.minimumQuantity()?.doubleValue(for: unit),
                    maximum: statistics?.maximumQuantity()?.doubleValue(for: unit)
                )
                continuation.resume(returning: stats)
            }
            store.execute(query)
        }
    }

    private static func mostRecentQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let quantity = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: quantity)
            }
            store.execute(query)
        }
    }

    private static func stoodHours(predicate: NSPredicate) async -> Int? {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return nil }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let count = samples?
                    .compactMap { $0 as? HKCategorySample }
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
                    .count
                continuation.resume(returning: count)
            }
            store.execute(query)
        }
    }

    private static func sleepSummary(endingNear date: Date, calendar: Calendar) async -> SleepSummary {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return SleepSummary() }

        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: -12, to: dayStart) ?? dayStart.addingTimeInterval(-43_200)
        let end = calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart.addingTimeInterval(43_200)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let sleepSamples = (samples ?? [])
                    .compactMap { $0 as? HKCategorySample }
                    .filter { isAsleep($0.value) }

                let totalSeconds = sleepSamples.reduce(0) { partial, sample in
                    let overlapStart = max(sample.startDate, start)
                    let overlapEnd = min(sample.endDate, end)
                    return partial + max(0, overlapEnd.timeIntervalSince(overlapStart))
                }

                guard totalSeconds > 0 else {
                    continuation.resume(returning: SleepSummary())
                    return
                }

                continuation.resume(returning: SleepSummary(
                    hours: totalSeconds / 3_600,
                    start: sleepSamples.map(\.startDate).min(),
                    end: sleepSamples.map(\.endDate).max()
                ))
            }
            store.execute(query)
        }
    }

    private static func isAsleep(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysis.asleep.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
    }
}
