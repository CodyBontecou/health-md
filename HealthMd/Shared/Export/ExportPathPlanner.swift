import Foundation

/// Shared path construction for aggregate exports and Daily Note Injection.
///
/// Aggregate exports live under the configured Health.md export subfolder.
/// Daily Note Injection targets are resolved from the selected vault/root
/// destination so users can export generated files to `Health/` while merging
/// into existing notes like `Daily/YYYY-MM-DD.md` at the vault root.
enum ExportPathPlanner {
    struct AggregateOutputTarget {
        let format: ExportFormat
        let filename: String
        let url: URL
        let relativePath: String
    }

    struct DailyNoteCollision {
        let dailyNoteURL: URL
        let dailyNoteRelativePath: String
        let exportTarget: AggregateOutputTarget

        var message: String {
            "Daily Note Injection target conflicts with export output: \(dailyNoteRelativePath). Change Output folder/filename or Daily Note Injection folder/filename."
        }
    }

    static func healthSubfolderURL(vaultURL: URL, healthSubfolder: String) -> URL {
        appendingRelativePath(healthSubfolder, to: vaultURL, isDirectory: true)
    }

    static func aggregateFolderURL(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> URL {
        var url = healthSubfolderURL(vaultURL: vaultURL, healthSubfolder: healthSubfolder)
        if let folderPath = settings.formatFolderPath(for: date) {
            url = appendingRelativePath(folderPath, to: url, isDirectory: true)
        }
        return url
    }

    static func aggregateFileURL(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        format: ExportFormat
    ) -> URL {
        let folderURL = aggregateFolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        )
        return fileURL(in: folderURL, filename: settings.filename(for: date, format: format))
    }

    static func aggregateOutputTargets(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> [AggregateOutputTarget] {
        settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }).map { format in
            let filename = settings.filename(for: date, format: format)
            return AggregateOutputTarget(
                format: format,
                filename: filename,
                url: aggregateFileURL(
                    vaultURL: vaultURL,
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                ),
                relativePath: aggregateRelativePath(
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                )
            )
        }
    }

    static func aggregateFolderRelativePath(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> String {
        relativePath([
            healthSubfolder,
            settings.formatFolderPath(for: date) ?? ""
        ])
    }

    static func aggregateRelativePath(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        format: ExportFormat
    ) -> String {
        relativePath([
            healthSubfolder,
            settings.formatFolderPath(for: date) ?? "",
            settings.filename(for: date, format: format)
        ])
    }

    static func dailyNoteURL(
        vaultURL: URL,
        settings: DailyNoteInjectionSettings,
        date: Date
    ) -> URL {
        var url = appendingRelativePath(settings.folderPath, to: vaultURL, isDirectory: true)
        url = fileURL(in: url, filename: settings.formatFilename(for: date) + ".md")
        return url
    }

    static func dailyNoteRelativePath(
        settings: DailyNoteInjectionSettings,
        date: Date
    ) -> String {
        relativePath([
            settings.folderPath,
            settings.formatFilename(for: date) + ".md"
        ])
    }

    static func dailyNoteFolderRelativePath(
        settings: DailyNoteInjectionSettings,
        date: Date
    ) -> String {
        let relativePath = dailyNoteRelativePath(settings: settings, date: date)
        return Self.relativePath(relativePath.split(separator: "/").dropLast().map(String.init))
    }

    static func dailyNoteExportCollision(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> DailyNoteCollision? {
        guard settings.dailyNoteInjection.enabled else { return nil }

        let dailyNoteURL = dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: date
        )
        let dailyNoteRelativePath = dailyNoteRelativePath(
            settings: settings.dailyNoteInjection,
            date: date
        )

        guard let exportTarget = aggregateOutputTargets(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        ).first(where: { sameFile($0.url, dailyNoteURL) }) else {
            return nil
        }

        return DailyNoteCollision(
            dailyNoteURL: dailyNoteURL,
            dailyNoteRelativePath: dailyNoteRelativePath,
            exportTarget: exportTarget
        )
    }

    /// Relative-path collision check for previews that may not have a local vault URL.
    static func dailyNoteExportCollision(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> DailyNoteCollision? {
        dailyNoteExportCollision(
            vaultURL: URL(fileURLWithPath: "/__HealthMdVaultRoot__", isDirectory: true),
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        )
    }

    static func fileURL(in folderURL: URL, filename: String) -> URL {
        appendingRelativePath(filename, to: folderURL, isDirectory: false)
    }

    static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    static func appendingRelativePath(_ relativePath: String, to baseURL: URL, isDirectory: Bool) -> URL {
        let segments = pathSegments(relativePath)
        guard !segments.isEmpty else { return baseURL }

        var url = baseURL
        for (index, segment) in segments.enumerated() {
            let segmentIsDirectory = isDirectory || index < segments.count - 1
            url = url.appendingPathComponent(segment, isDirectory: segmentIsDirectory)
        }
        return url
    }

    private static func relativePath(_ rawComponents: [String]) -> String {
        rawComponents.flatMap(pathSegments).joined(separator: "/")
    }

    private static func pathSegments(_ rawPath: String) -> [String] {
        rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
