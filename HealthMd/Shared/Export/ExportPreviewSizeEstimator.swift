import Foundation

/// A lightweight sample of the output bytes rendered for one populated export day.
/// Aggregate bytes may represent only the preview's representative formats, while
/// supplemental bytes include generated daily-note and individual-entry content.
struct ExportPreviewSizeSample: Equatable {
    let aggregateByteCount: Int
    let supplementalByteCount: Int

    init(aggregateByteCount: Int, supplementalByteCount: Int = 0) {
        self.aggregateByteCount = max(aggregateByteCount, 0)
        self.supplementalByteCount = max(supplementalByteCount, 0)
    }
}

struct ExportPreviewSizeEstimate: Equatable {
    let byteCount: Int64
    let sampledDataDayCount: Int
    let projectedDataDayCount: Int
    let isExtrapolated: Bool

    var sizeLabel: String {
        Self.sizeLabel(for: byteCount)
    }

    static func sizeLabel(for bytes: Int64) -> String {
        let safeBytes = max(bytes, 0)
        if safeBytes < 1_024 { return "\(safeBytes) B" }

        let kibibytes = Double(safeBytes) / 1_024
        if kibibytes < 1_024 { return String(format: "%.1f KB", kibibytes) }

        let mebibytes = kibibytes / 1_024
        if mebibytes < 1_024 { return String(format: "%.1f MB", mebibytes) }

        let gibibytes = mebibytes / 1_024
        if gibibytes < 1_024 { return String(format: "%.1f GB", gibibytes) }

        return String(format: "%.1f TB", gibibytes / 1_024)
    }
}

/// Projects a quick whole-range estimate from the populated days already fetched
/// for Export Preview. It intentionally avoids additional HealthKit queries.
enum ExportPreviewSizeEstimator {
    static func estimate(
        totalDateCount: Int,
        attemptedDateCount: Int,
        samples: [ExportPreviewSizeSample],
        renderedAggregateFormatCount: Int,
        selectedAggregateFormatCount: Int,
        sampledRollupByteCount: Int = 0,
        sampledRollupFileCount: Int = 0,
        projectedRollupFileCount: Int = 0,
        fixedByteCount: Int = 0
    ) -> ExportPreviewSizeEstimate? {
        let totalDates = max(totalDateCount, 0)
        let attemptedDates = min(max(attemptedDateCount, 0), totalDates)
        let sampledDays = samples.count

        guard totalDates > 0, attemptedDates > 0, sampledDays > 0 else { return nil }

        let projectedDays: Int
        if attemptedDates >= totalDates {
            projectedDays = min(sampledDays, totalDates)
        } else {
            let sampledDensity = Double(sampledDays) / Double(attemptedDates)
            let projected = Int((Double(totalDates) * sampledDensity).rounded())
            projectedDays = min(max(projected, sampledDays), totalDates)
        }

        let aggregateBytes = samples.reduce(Int64(0)) {
            $0 + Int64($1.aggregateByteCount)
        }
        let supplementalBytes = samples.reduce(Int64(0)) {
            $0 + Int64($1.supplementalByteCount)
        }

        let aggregateFormatScale: Double
        if renderedAggregateFormatCount > 0, selectedAggregateFormatCount > 0 {
            aggregateFormatScale = Double(selectedAggregateFormatCount)
                / Double(renderedAggregateFormatCount)
        } else {
            aggregateFormatScale = 0
        }

        let averageAggregateBytes = Double(aggregateBytes) / Double(sampledDays)
        let averageSupplementalBytes = Double(supplementalBytes) / Double(sampledDays)
        let projectedDailyBytes = (
            averageAggregateBytes * aggregateFormatScale + averageSupplementalBytes
        ) * Double(projectedDays)

        let projectedRollupBytes: Double
        if sampledRollupFileCount > 0, projectedRollupFileCount > 0 {
            projectedRollupBytes = Double(max(sampledRollupByteCount, 0))
                / Double(sampledRollupFileCount)
                * Double(projectedRollupFileCount)
        } else {
            projectedRollupBytes = 0
        }

        let estimatedBytes = projectedDailyBytes
            + projectedRollupBytes
            + Double(max(fixedByteCount, 0))
        guard estimatedBytes > 0 else { return nil }

        let byteCount = estimatedBytes >= Double(Int64.max)
            ? Int64.max
            : Int64(estimatedBytes.rounded())
        return ExportPreviewSizeEstimate(
            byteCount: byteCount,
            sampledDataDayCount: sampledDays,
            projectedDataDayCount: projectedDays,
            isExtrapolated: attemptedDates < totalDates
                || projectedDays != sampledDays
                || renderedAggregateFormatCount != selectedAggregateFormatCount
                || sampledRollupFileCount != projectedRollupFileCount
        )
    }
}
