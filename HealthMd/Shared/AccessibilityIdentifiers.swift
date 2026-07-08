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
        static let exportProgress = "export.progressView"
        static let statusMessage = "export.statusMessage"
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
        static let hourPicker = "schedule.hourPicker"
        static let minutePicker = "schedule.minutePicker"
        static let periodPicker = "schedule.periodPicker"
        static let localTargetOption = "schedule.target.local"
        static let macTargetOption = "schedule.target.mac"
        static let apiTargetOption = "schedule.target.api"
    }

    // MARK: - Sync
    enum Sync {
        static let syncToggle = "sync.syncToggle"
        static let connectionStatus = "sync.connectionStatus"
        static let manualSyncButton = "sync.manualSyncButton"
        static let autoSyncToggle = "sync.autoSyncToggle"
    }

    // MARK: - Settings
    enum Settings {
        static let vaultRow = "settings.vaultRow"
        static let exportSettingsRow = "settings.exportSettingsRow"
        static let macSyncRow = "settings.macSyncRow"
    }

    // MARK: - Status Badge
    enum Status {
        static let exportStatusBadge = "status.exportBadge"
    }

    // MARK: - Export Preview
    enum ExportPreview {
        static let markdownFileRow = "exportPreview.fileRow.Markdown"
        static let fileContent = "exportPreview.fileContent"
    }
}
