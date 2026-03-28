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
        static let cancelExportButton = "export.cancelButton"
        static let healthBadge = "export.healthBadge"
        static let vaultBadge = "export.vaultBadge"
        static let freeExportsLabel = "export.freeExportsLabel"
        static let exportProgress = "export.progressView"
        static let statusMessage = "export.statusMessage"
    }

    // MARK: - Export Modal
    enum ExportModal {
        static let subfolderButton = "exportModal.subfolder"
        static let startDatePicker = "exportModal.startDate"
        static let endDatePicker = "exportModal.endDate"
        static let exportButton = "exportModal.exportButton"
        static let cancelButton = "exportModal.cancelButton"
    }

    // MARK: - Paywall
    enum Paywall {
        static let view = "paywall.view"
        static let unlockButton = "paywall.unlockButton"
        static let restoreButton = "paywall.restoreButton"
        static let dismissButton = "paywall.dismissButton"
        static let title = "paywall.title"
        static let subtitle = "paywall.subtitle"
        static let errorMessage = "paywall.errorMessage"
    }

    // MARK: - Schedule
    enum Schedule {
        static let setupButton = "schedule.setupButton"
        static let statusText = "schedule.statusText"
        static let enableToggle = "schedule.enableToggle"
        static let frequencyPicker = "schedule.frequencyPicker"
        static let hourPicker = "schedule.hourPicker"
        static let minutePicker = "schedule.minutePicker"
        static let saveButton = "schedule.saveButton"
        static let cancelButton = "schedule.cancelButton"
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
}
