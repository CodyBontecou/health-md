import Foundation

// MARK: - Health Roll-up Export Facade

enum HealthRollupExporter {
    static func isEnabled(settings: AdvancedExportSettings) -> Bool {
        settings.rollupSummariesEnabled && !settings.enabledRollupPeriods.isEmpty && !settings.exportFormats.isEmpty
    }

    static func makeSummaries(
        from healthData: [HealthData],
        settings: AdvancedExportSettings,
        periods: [HealthRollupPeriod]? = nil,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> [HealthRollupSummary] {
        guard !settings.exportFormats.isEmpty else { return [] }

        let selectedPeriods = periods ?? settings.enabledRollupPeriods
        guard !selectedPeriods.isEmpty else { return [] }
        if periods == nil, !settings.rollupSummariesEnabled { return [] }

        return HealthRollupGenerator.generate(
            from: healthData,
            settings: settings,
            periods: selectedPeriods,
            generatedAt: generatedAt,
            calendar: calendar
        )
    }

    static func outputTargets(
        for summaries: [HealthRollupSummary],
        healthSubfolder: String,
        settings: AdvancedExportSettings
    ) -> [HealthRollupWriteResult] {
        summaries.flatMap { summary in
            settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }).map { format in
                let filename = rollupFilename(for: summary, format: format, settings: settings)
                let relativeFolderPath = relativeFolderPath(
                    healthSubfolder: healthSubfolder,
                    period: summary.period,
                    format: format,
                    settings: settings
                )
                return HealthRollupWriteResult(
                    summary: summary,
                    format: format,
                    filename: filename,
                    relativeFolderPath: relativeFolderPath,
                    relativePath: relativePath(
                        healthSubfolder: healthSubfolder,
                        summary: summary,
                        format: format,
                        settings: settings
                    ),
                    content: content(for: summary, format: format)
                )
            }
        }
    }

    static func content(for summary: HealthRollupSummary, format: ExportFormat) -> String {
        switch format {
        case .markdown:
            return summary.toRollupMarkdown()
        case .obsidianBases:
            return summary.toRollupObsidianBases()
        case .json:
            return summary.toRollupJSON()
        case .csv:
            return summary.toRollupCSV()
        }
    }

    static func rollupFilename(
        for summary: HealthRollupSummary,
        format: ExportFormat,
        settings: AdvancedExportSettings
    ) -> String {
        let suffix: String
        if format == .obsidianBases && !settings.organizeFormatsIntoFolders {
            suffix = "-bases"
        } else {
            suffix = ""
        }
        return "\(summary.periodID)\(suffix).\(format.fileExtension)"
    }

    static func relativeFolderPath(healthSubfolder: String, period: HealthRollupPeriod) -> String {
        relativeFolderPath(healthSubfolder: healthSubfolder, period: period, format: nil, settings: nil)
    }

    static func relativeFolderPath(
        healthSubfolder: String,
        period: HealthRollupPeriod,
        format: ExportFormat?,
        settings: AdvancedExportSettings?
    ) -> String {
        var components = [healthSubfolder, "Rollups"]
        if let settings, settings.organizeFormatsIntoFolders, let format {
            components.append(format.formatFolderName)
        }
        components.append(period.folderName)
        return relativePath(components)
    }

    static func relativePath(
        healthSubfolder: String,
        summary: HealthRollupSummary,
        format: ExportFormat,
        settings: AdvancedExportSettings
    ) -> String {
        relativePath([
            relativeFolderPath(
                healthSubfolder: healthSubfolder,
                period: summary.period,
                format: format,
                settings: settings
            ),
            rollupFilename(for: summary, format: format, settings: settings)
        ])
    }

    static func folderURL(
        vaultURL: URL,
        healthSubfolder: String,
        period: HealthRollupPeriod,
        format: ExportFormat? = nil,
        settings: AdvancedExportSettings? = nil
    ) -> URL {
        ExportPathPlanner.appendingRelativePath(
            relativeFolderPath(
                healthSubfolder: healthSubfolder,
                period: period,
                format: format,
                settings: settings
            ),
            to: vaultURL,
            isDirectory: true
        )
    }

    private static func relativePath(_ components: [String]) -> String {
        components
            .flatMap { $0.split(separator: "/").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }
}
