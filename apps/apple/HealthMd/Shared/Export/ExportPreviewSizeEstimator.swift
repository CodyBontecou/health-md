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

/// Provides a useful pre-export estimate before Preview has sampled real HealthKit
/// output. The estimate intentionally favors transparency over false precision:
/// it is based on the configured day, metric, and format counts, then replaced by
/// Export Preview's rendered-byte estimate when one is available.
enum ExportStatusSizeEstimator {
    static func estimate(
        totalDateCount: Int,
        selectedFormats: Set<ExportFormat>,
        enabledMetricCount: Int,
        includesLosslessRecords: Bool,
        includesIndividualEntries: Bool,
        updatesDailyNotes: Bool,
        dailyNotesOnly: Bool,
        summaryOnly: Bool,
        archiveMode: Bool,
        projectedRollupFileCount: Int,
        isAPIPayload: Bool
    ) -> ExportPreviewSizeEstimate? {
        let dayCount = max(totalDateCount, 0)
        guard dayCount > 0 else { return nil }

        let metricCount = max(enabledMetricCount, 1)
        let dailyBytes: Double

        if isAPIPayload {
            dailyBytes = estimatedBytes(
                for: .json,
                metricCount: metricCount,
                includesLosslessRecords: includesLosslessRecords
            )
        } else if dailyNotesOnly {
            dailyBytes = 1_500 + Double(metricCount * 90)
        } else if summaryOnly {
            dailyBytes = 0
        } else {
            dailyBytes = selectedFormats.reduce(0) { partial, format in
                partial + estimatedBytes(
                    for: format,
                    metricCount: metricCount,
                    includesLosslessRecords: includesLosslessRecords
                )
            }
        }

        var projectedBytes = dailyBytes * Double(dayCount)

        if !isAPIPayload, !dailyNotesOnly {
            if updatesDailyNotes {
                projectedBytes += Double(dayCount * (1_200 + metricCount * 70))
            }
            if includesIndividualEntries {
                // Individual-entry volume depends on source sample frequency. Use a
                // conservative fraction of the aggregate projection and keep the UI
                // explicitly labeled as a rough estimate.
                projectedBytes += dailyBytes * Double(dayCount) * 0.65
            }

            let rollupCount = max(projectedRollupFileCount, 0)
            if rollupCount > 0 {
                let averageRollupBytes = 3_500 + Double(metricCount * 125)
                projectedBytes += averageRollupBytes * Double(rollupCount)
            }

            // The data dictionary is written once for file exports.
            projectedBytes += 64 * 1_024

            if archiveMode {
                // Health.md ZIP archives contain text-heavy output, which generally
                // compresses well. This remains a projection, not a promised size.
                projectedBytes *= 0.4
            }
        }

        guard projectedBytes > 0 else { return nil }
        let byteCount = projectedBytes >= Double(Int64.max)
            ? Int64.max
            : Int64(projectedBytes.rounded())

        return ExportPreviewSizeEstimate(
            byteCount: byteCount,
            sampledDataDayCount: 0,
            projectedDataDayCount: dayCount,
            isExtrapolated: true
        )
    }

    private static func estimatedBytes(
        for format: ExportFormat,
        metricCount: Int,
        includesLosslessRecords: Bool
    ) -> Double {
        if includesLosslessRecords {
            // Canonical source records dominate lossless exports. Their exact volume
            // varies with sampling frequency, so metric count is only a rough proxy.
            let canonicalBytes = Double(metricCount * 32 * 1_024)
            switch format {
            case .markdown: return 8_000 + canonicalBytes
            case .obsidianBases: return 9_000 + canonicalBytes
            case .json: return 12_000 + canonicalBytes
            case .csv: return 5_000 + canonicalBytes
            }
        }

        switch format {
        case .markdown:
            return 4_000 + Double(metricCount * 90)
        case .obsidianBases:
            return 5_000 + Double(metricCount * 100)
        case .json:
            return 6_000 + Double(metricCount * 140)
        case .csv:
            return 1_500 + Double(metricCount * 65)
        }
    }
}
