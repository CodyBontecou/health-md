import Foundation

/// Centralized accessibility identifiers for UI test automation.
/// Keep in sync with `UITestLaunchHelper` in the UI test target.
enum AccessibilityID {

    // MARK: - Navigation Tabs
    enum Tab {
        static let export = "tab.export"
        static let schedule = "tab.schedule"
        static let sync = "tab.sync"
        static let settings = "tab.settings"
    }

    // MARK: - Export Tab
    enum Export {
        static let exportButton = "export.exportButton"
        static let previewButton = "export.previewButton"
        static let cancelExportButton = "export.cancelButton"
        static let healthBadge = "export.healthBadge"
        static let vaultBadge = "export.vaultBadge"
        static let freeExportsLabel = "export.freeExportsLabel"
        static let localTargetOption = "export.target.local"
        static let macTargetOption = "export.target.mac"
        static let apiTargetOption = "export.target.api"
        static let datePresetTodayButton = "export.dateRange.preset.today"
        static let datePresetYesterdayButton = "export.dateRange.preset.yesterday"
        static let datePresetAllTimeButton = "export.dateRange.preset.allTime"
        static let datePresetCustomButton = "export.dateRange.preset.custom"
        static let customStartDatePicker = "export.dateRange.custom.startDate"
        static let customEndDatePicker = "export.dateRange.custom.endDate"
        static let pathPreview = "export.pathPreview"
        static let activityBanner = "export.activityBanner"
        static let filenameEditorButton = "export.filenameEditorButton"
        static let outputEditorSaveButton = "export.outputEditorSaveButton"

        // Large interactive export confirmation (Export tab only).
        // SwiftUI alert titles cannot carry accessibility identifiers; the
        // `largeExportConfirmationTitle` constant documents the alert's stable
        // identifier while UI tests match the alert by its localized title text,
        // matching how the other Export tab alerts are located.
        static let largeExportConfirmationTitle = "export.confirmLargeExport.title"
        static let largeExportConfirmationMessage = "export.confirmLargeExport.message"
        static let largeExportConfirmationConfirmButton = "export.confirmLargeExport.confirmButton"
        static let largeExportConfirmationCancelButton = "export.confirmLargeExport.cancelButton"
    }

    // MARK: - Mac Destination
    enum Mac {
        static let exportActivity = "mac.exportActivity"
    }

    // MARK: - Export Profiles Management
    enum ExportProfiles {
        static let entry = "export.profiles.entry"
        static let makeActiveButton = "export.profiles.makeActive"
        static let copyIDButton = "export.profiles.copyID"
    }

    // MARK: - Clinician Report
    enum ClinicianReport {
        static let entry = "clinicianReport.entry"
        static let displayName = "clinicianReport.displayName"
        static let customStartDate = "clinicianReport.dateRange.custom.start"
        static let customEndDate = "clinicianReport.dateRange.custom.end"
        static let detail = "clinicianReport.detail"
        static let recommended = "clinicianReport.metrics.recommended"
        static let selectAll = "clinicianReport.metrics.selectAll"
        static let clear = "clinicianReport.metrics.clear"
        static let preview = "clinicianReport.preview"
        static let previewContent = "clinicianReport.preview.content"
        static let edit = "clinicianReport.edit"
        static let generate = "clinicianReport.generate"
        static let share = "clinicianReport.share"
        static let exportSuccess = "clinicianReport.exportSuccess"

        static func preset(_ preset: ReportDateRangePreset) -> String {
            "clinicianReport.dateRange.preset.\(preset.rawValue)"
        }

        static func metric(_ metric: ReportMetric) -> String {
            "clinicianReport.metric.\(metric.rawValue)"
        }
    }

    // MARK: - CLI Export Activity
    enum CLI {
        static let exportActivity = "cli.exportActivity"
    }

    // MARK: - Notification Export Activity
    enum Notification {
        static let exportActivity = "notification.exportActivity"
        static let cancelExportButton = "notification.cancelButton"
    }

    // MARK: - Export Modal
    enum ExportModal {
        static let subfolderButton = "exportModal.subfolder"
        static let datePresetTodayButton = "exportModal.dateRange.preset.today"
        static let datePresetYesterdayButton = "exportModal.dateRange.preset.yesterday"
        static let datePresetAllTimeButton = "exportModal.dateRange.preset.allTime"
        static let datePresetCustomButton = "exportModal.dateRange.preset.custom"
        static let startDatePicker = "exportModal.startDate"
        static let endDatePicker = "exportModal.endDate"
        static let exportButton = "exportModal.exportButton"
        static let cancelButton = "exportModal.cancelButton"
    }

    // MARK: - Paywall
    enum Paywall {
        static let view = "paywall.view"
        static let unlockButton = "paywall.unlockButton"
        static let familyUnlockButton = "paywall.familyUnlockButton"
        static let restoreButton = "paywall.restoreButton"
        static let dismissButton = "paywall.dismissButton"
        static let title = "paywall.title"
        static let subtitle = "paywall.subtitle"
        static let errorMessage = "paywall.errorMessage"
    }

    // MARK: - Schedule
    enum Schedule {
        static let enableToggle = "schedule.enableToggle"
        static let frequencyPicker = "schedule.frequencyPicker"
        static let customIntervalStepper = "schedule.custom.interval"
        static let customUnitPicker = "schedule.custom.unit"
        static let customStartDatePicker = "schedule.custom.startDate"
        static let hourPicker = "schedule.hourPicker"
        static let minutePicker = "schedule.minutePicker"
        static let periodPicker = "schedule.periodPicker"
        static let localTargetOption = "schedule.target.local"
        static let macTargetOption = "schedule.target.mac"
        static let apiTargetOption = "schedule.target.api"
    }

    // MARK: - Sync
    enum Sync {
        static let configurationTargetPicker = "sync.configurationTargetPicker"
        static let syncToggle = "sync.syncToggle"
        static let connectionStatus = "sync.connectionStatus"
        static let manualSyncButton = "sync.manualSyncButton"
        static let autoSyncToggle = "sync.autoSyncToggle"
        static let directCLIToggle = "sync.directCLIToggle"
        static let directCLIScanButton = "sync.directCLIScanButton"
    }

    // MARK: - Settings
    enum Settings {
        static let vaultRow = "settings.vaultRow"
        static let exportSettingsRow = "settings.exportSettingsRow"
        static let macSyncRow = "settings.macSyncRow"
    }

    // MARK: - Shared Setup
    enum SharedSetup {
        static let configurationCard = "sharedSetup.configurationCard"
        static let use = "sharedSetup.use"
        static let share = "sharedSetup.share"
        static let review = "sharedSetup.review"
        static let apply = "sharedSetup.apply"
        static let success = "sharedSetup.success"
        static let undo = "sharedSetup.undo"
        static let finish = "sharedSetup.finish"
    }

    // MARK: - Configuration Protection
    enum ConfigurationProtection {
        static let toggle = "configurationProtection.toggle"
        static let section = "configurationProtection.section"
        static let protectedRegion = "configurationProtection.protectedRegion"
        static let toast = "configurationProtection.toast"
    }

    // MARK: - Status Badge
    enum Status {
        static let exportStatusBadge = "status.exportBadge"
    }

    // MARK: - Exported File Viewer
    enum ExportedFile {
        static let viewer = "exportedFile.viewer"
        static let loading = "exportedFile.loading"
        static let rendered = "exportedFile.rendered"
        static let source = "exportedFile.source"
        static let displayMode = "exportedFile.displayMode"
        static let largeFileNotice = "exportedFile.largeFileNotice"
        static let retry = "exportedFile.retry"
        static let done = "exportedFile.done"
    }

    // MARK: - Export Preview
    enum ExportPreview {
        static let exportButton = "exportPreview.exportButton"
        static let markdownFileRow = "exportPreview.fileRow.Markdown"
        static let fileContent = "exportPreview.fileContent"
        static let permissionHelpButton = "exportPreview.permissionHelpButton"
    }
}
