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
    /// Daily HealthKit aggregate snapshots the export must process. Roll-ups can
    /// expand a short selected range to complete weekly, monthly, or yearly windows.
    let projectedProcessingDayCount: Int
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

struct ExportRollupOutputProjection: Equatable {
    let byteCount: Int64
    let fileCount: Int
    let sourceDateCount: Int
}

/// Estimates roll-up output with format-specific structural costs. It assumes
/// every selected daily-summary key is present, avoiding the severe undercount
/// caused by applying one small average byte size to every file format.
enum ExportRollupOutputSizeEstimator {
    static func estimate(
        selectedDates: [Date],
        rollupsEnabled: Bool,
        formats: Set<ExportFormat>,
        metricSelection: MetricSelectionState,
        customization: FormatCustomization,
        latestAllowedDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ExportRollupOutputProjection {
        guard rollupsEnabled,
              !selectedDates.isEmpty,
              !formats.isEmpty else {
            return ExportRollupOutputProjection(byteCount: 0, fileCount: 0, sourceDateCount: 0)
        }

        let latestAllowedDay = calendar.startOfDay(for: latestAllowedDate)
        let requestedDays = Set(selectedDates.map { calendar.startOfDay(for: $0) })
        guard let firstDay = requestedDays.min(), let lastDay = requestedDays.max() else {
            return ExportRollupOutputProjection(byteCount: 0, fileCount: 0, sourceDateCount: 0)
        }
        guard firstDay <= latestAllowedDay else {
            return ExportRollupOutputProjection(byteCount: 0, fileCount: 0, sourceDateCount: 0)
        }

        let window = HealthRollupPeriodWindow.rangeWindow(
            from: firstDay,
            to: min(lastDay, latestAllowedDay),
            calendar: calendar
        )
        let sourceDates = requestedDays.filter { $0 <= latestAllowedDay }

        let metricCount = HealthMetricDataDictionary.entries(using: customization)
            .count { entry in
                metricSelection.isMetricEnabled(entry.metricId)
                    && customization.frontmatterConfig.isFieldEnabled(entry.canonicalKey)
            }

        var projectedBytes: Int64 = 0
        for format in formats {
            projectedBytes = addingClamped(
                projectedBytes,
                estimatedBytes(
                    for: format,
                    metricCount: metricCount,
                    sourceDateCount: sourceDates.count
                )
            )
        }

        return ExportRollupOutputProjection(
            byteCount: projectedBytes,
            fileCount: formats.count,
            sourceDateCount: sourceDates.count
        )
    }

    /// Constants model each renderer's fixed envelope, per-metric rows, repeated
    /// statistics/categories, and source-date representation. They are calibrated
    /// against the generated roll-up reference files; JSON and CSV are intentionally
    /// much larger per metric than Markdown and Bases.
    private static func estimatedBytes(
        for format: ExportFormat,
        metricCount: Int,
        sourceDateCount: Int
    ) -> Int64 {
        let metrics = Int64(max(metricCount, 0))
        let sourceDates = Int64(max(sourceDateCount, 0))

        switch format {
        case .markdown:
            // Source dates appear in YAML and again in the readable coverage line.
            return 1_000 + metrics * 350 + sourceDates * 27
        case .obsidianBases:
            return 700 + metrics * 450 + sourceDates * 15
        case .json:
            // JSON repeats metric objects in both `metrics` and `categories`.
            return 1_000 + metrics * 1_600 + sourceDates * 15
        case .csv:
            // Each metric produces a primary row plus one row per statistic.
            return 500 + metrics * 1_220
        }
    }

    private static func addingClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : max(0, result)
    }
}

enum ExportDataDictionarySizeEstimator {
    static func byteCount(using customization: FormatCustomization) -> Int {
        let entries = HealthMetricDataDictionary.entries(using: customization)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return ((try? encoder.encode(entries).count) ?? 0) + 1
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
        minimumProjectedRollupByteCount: Int64 = 0,
        fixedByteCount: Int = 0,
        projectedProcessingDayCount: Int? = nil,
        archiveMode: Bool = false
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

        let sampledProjectedRollupBytes: Double
        if sampledRollupFileCount > 0, projectedRollupFileCount > 0 {
            sampledProjectedRollupBytes = Double(max(sampledRollupByteCount, 0))
                / Double(sampledRollupFileCount)
                * Double(projectedRollupFileCount)
        } else {
            sampledProjectedRollupBytes = 0
        }
        let configuredRollupFloor = Double(max(minimumProjectedRollupByteCount, 0))
        let projectedRollupBytes = max(sampledProjectedRollupBytes, configuredRollupFloor)

        var estimatedBytes = projectedDailyBytes
            + projectedRollupBytes
            + Double(max(fixedByteCount, 0))
        if archiveMode {
            // Match the rough status estimate for the final ZIP rather than
            // replacing it with the uncompressed preview contents.
            estimatedBytes *= 0.4
        }
        guard estimatedBytes > 0 else { return nil }

        let byteCount = estimatedBytes >= Double(Int64.max)
            ? Int64.max
            : Int64(estimatedBytes.rounded())
        let processingDays = max(projectedProcessingDayCount ?? projectedDays, projectedDays)
        return ExportPreviewSizeEstimate(
            byteCount: byteCount,
            sampledDataDayCount: sampledDays,
            projectedDataDayCount: projectedDays,
            projectedProcessingDayCount: processingDays,
            isExtrapolated: attemptedDates < totalDates
                || projectedDays != sampledDays
                || processingDays != projectedDays
                || renderedAggregateFormatCount != selectedAggregateFormatCount
                || sampledRollupFileCount != projectedRollupFileCount
                || configuredRollupFloor > sampledProjectedRollupBytes
                || archiveMode
        )
    }
}

/// Provides a useful pre-export estimate before Preview has sampled real HealthKit
/// output. The estimate intentionally favors transparency over false precision:
/// it is based on configured dates, metrics, formats, and complete roll-up windows,
/// then combined with Export Preview's sampled rendered bytes when available.
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
        projectedRollupByteCount: Int64? = nil,
        fixedByteCount: Int? = nil,
        projectedProcessingDayCount: Int? = nil,
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

            if let projectedRollupByteCount {
                projectedBytes += Double(max(projectedRollupByteCount, 0))
            } else {
                let rollupCount = max(projectedRollupFileCount, 0)
                if rollupCount > 0 {
                    let averageRollupBytes = 3_500 + Double(metricCount * 125)
                    projectedBytes += averageRollupBytes * Double(rollupCount)
                }
            }

            // The data dictionary is written once for file exports. Callers with
            // current settings can supply its exact encoded size.
            projectedBytes += Double(max(fixedByteCount ?? (64 * 1_024), 0))

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
            projectedProcessingDayCount: max(projectedProcessingDayCount ?? dayCount, dayCount),
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
