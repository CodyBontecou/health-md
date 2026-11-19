import Foundation

extension ExportSettingsSnapshot {
    /// 3.5 "Reset Export Configuration" for one automation: the same defaults as
    /// `AdvancedExportSettings.reset()`, applied to a profile's snapshot.
    ///
    /// Only export configuration changes. The profile's id, name, destination
    /// bindings and schedule live outside the snapshot and are untouched by the
    /// caller's save path. Within the snapshot, the destination subfolder and the
    /// operation authority (engine pin, calendar time zone, capture contexts) are
    /// kept, because they describe where and how this automation runs rather than
    /// what it exports.
    @MainActor
    func resettingExportConfiguration() -> ExportSettingsSnapshot {
        var reset = self
        reset.exportFormats = [.markdown]
        reset.includeMetadata = true
        reset.groupByCategory = true
        reset.filenameFormat = AdvancedExportSettings.defaultFilenameFormat
        reset.folderStructure = AdvancedExportSettings.defaultFolderStructure
        reset.organizeFormatsIntoFolders = false
        reset.archiveExportFiles = false
        reset.includeDataDictionary = true
        reset.summaryOnlyExport = false
        reset.writeMode = .overwrite
        reset.formatCustomization = .from(FormatCustomization())
        reset.individualTracking = .from(IndividualTrackingSettings())
        reset.dailyNoteInjection = .from(DailyNoteInjectionSettings())
        reset.detailPolicy = .summary
        reset.generateRangeSummary = false
        reset.metricSelection = .from(MetricSelectionState())
        return reset
    }
}
