import Foundation
import HealthKit

struct WatchHealthSnapshot: Codable, Hashable, Sendable {
    var date: Date
    var lastUpdated: Date

    var steps: Double?
    var activeEnergyKilocalories: Double?
    var exerciseMinutes: Double?
    var standHours: Int?

    var sleepHours: Double?
    var restingHeartRate: Double?
    var heartRateVariabilityMS: Double?
    var bloodOxygenPercent: Double?

    static let placeholder = WatchHealthSnapshot(
        date: .now,
        lastUpdated: .now,
        steps: 8_420,
        activeEnergyKilocalories: 410,
        exerciseMinutes: 32,
        standHours: 9,
        sleepHours: 7.4,
        restingHeartRate: 58,
        heartRateVariabilityMS: 46,
        bloodOxygenPercent: 97
    )

    var hasAnyData: Bool {
        steps != nil || activeEnergyKilocalories != nil || exerciseMinutes != nil || standHours != nil ||
        sleepHours != nil || restingHeartRate != nil || heartRateVariabilityMS != nil || bloodOxygenPercent != nil
    }
}

enum WatchHealthSnapshotError: LocalizedError {
    case healthDataUnavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this Apple Watch."
        case .authorizationDenied:
            return "Health access was not granted. Open Health.md on Apple Watch and allow Health access."
        }
    }
}

enum WatchHealthAuthorizationStatus: Sendable, Equatable {
    case shouldRequest
    case alreadyHandled
    case unknown
}

enum WatchHealthAuthorizationRequestResult: Sendable {
    case promptPresented
    case alreadyHandled
}

enum WatchHealthSnapshotProvider {
    private static let store = HKHealthStore()

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let exerciseTime = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseTime)
        }
        if let standHour = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(standHour)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let restingHeartRate = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHeartRate)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let oxygenSaturation = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(oxygenSaturation)
        }

        return types
    }

    static func authorizationStatus() async throws -> WatchHealthAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WatchHealthSnapshotError.healthDataUnavailable
        }

        let requestStatus = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        switch requestStatus {
        case .shouldRequest:
            return .shouldRequest
        case .unnecessary:
            return .alreadyHandled
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func requestAuthorization() async throws -> WatchHealthAuthorizationRequestResult {
        let requestStatus = try await authorizationStatus()

        // HealthKit only shows its permission sheet once. Check first so the
        // watch app can show useful feedback instead of appearing to do nothing.
        guard requestStatus != .alreadyHandled else {
            return .alreadyHandled
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: WatchHealthSnapshotError.authorizationDenied)
                }
            }
        }

        return .promptPresented
    }

    static func fetchToday(calendar: Calendar = .current) async -> WatchHealthSnapshot {
        await fetch(for: Date(), calendar: calendar)
    }

    static func fetch(for date: Date, calendar: Calendar = .current) async -> WatchHealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else {
            return WatchHealthSnapshot(date: date, lastUpdated: .now)
        }

        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let dayPredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        async let steps = cumulativeQuantity(.stepCount, unit: .count(), predicate: dayPredicate)
        async let activeEnergy = cumulativeQuantity(.activeEnergyBurned, unit: .kilocalorie(), predicate: dayPredicate)
        async let exerciseMinutes = cumulativeQuantity(.appleExerciseTime, unit: .minute(), predicate: dayPredicate)
        async let standHours = stoodHours(predicate: dayPredicate)
        async let sleepHours = sleepDurationHours(around: date, calendar: calendar)
        async let restingHeartRate = mostRecentQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: dayPredicate)
        async let hrv = averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: dayPredicate)
        async let bloodOxygen = averageQuantity(.oxygenSaturation, unit: .percent(), predicate: dayPredicate)

        return WatchHealthSnapshot(
            date: start,
            lastUpdated: .now,
            steps: await steps,
            activeEnergyKilocalories: await activeEnergy,
            exerciseMinutes: await exerciseMinutes,
            standHours: await standHours,
            sleepHours: await sleepHours,
            restingHeartRate: await restingHeartRate,
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

    private static func sleepDurationHours(around date: Date, calendar: Calendar) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        let startOfDay = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: -12, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let totalSeconds = samples?
                    .compactMap { $0 as? HKCategorySample }
                    .filter { isAsleep($0.value) }
                    .reduce(0) { partial, sample in
                        let overlapStart = max(sample.startDate, start)
                        let overlapEnd = min(sample.endDate, end)
                        return partial + max(0, overlapEnd.timeIntervalSince(overlapStart))
                    }

                if let totalSeconds, totalSeconds > 0 {
                    continuation.resume(returning: totalSeconds / 3_600)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    private static func isAsleep(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
    }
}

enum WatchHealthFormatter {
    static func steps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 10_000 ? String(format: "%.1fk", value / 1_000) : NumberFormatter.integer.string(from: NSNumber(value: Int(value.rounded()))) ?? "—"
    }

    static func wholeNumber(_ value: Double?, fallback: String = "—") -> String {
        guard let value else { return fallback }
        return NumberFormatter.integer.string(from: NSNumber(value: Int(value.rounded()))) ?? fallback
    }

    static func hours(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1fh", value)
    }

    static func bpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) bpm"
    }

    static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) ms"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func standHours(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value == 1 ? "1 hr" : "\(value) hrs"
    }
}

private extension NumberFormatter {
    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
