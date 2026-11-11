#if os(macOS)
import SwiftUI

// MARK: - Settings Window (⌘,)

/// The ⌘, window shows the same MacSettingsG page as the sidebar's Settings destination.
/// CLI & MCP lives in the main window's sidebar.
struct MacSettingsWindow: View {
    var body: some View {
        MacGeneralSettingsView()
            .frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity, minHeight: 560, idealHeight: 680, maxHeight: .infinity)
            .glassTheme()
    }
}

// MARK: - Sidebar Settings View

/// MacSettingsG in the main window's sidebar; the ⌘, window shows the same page.
struct MacDetailSettingsView: View {
    var body: some View {
        MacGeneralSettingsView()
            .navigationTitle("Settings")
    }
}

// MARK: - General Settings

/// Keys for Mac-only presentation preferences.
enum MacPresentationPreferences {
    /// Read by the `MenuBarExtra` scene's `isInserted` binding.
    static let showsMenuBarExtraKey = "showsMenuBarExtra"
}

/// MacSettingsG: Exports, Storage, Privacy and General. Connection, folder and encrypted query
/// context live on the Mac destination and CLI & MCP pages.
struct MacGeneralSettingsView: View {
    @EnvironmentObject var healthDataStore: HealthDataStore
    @AppStorage(MacPresentationPreferences.showsMenuBarExtraKey) private var showsMenuBarExtra = true
    @State private var launchesAtLogin = SchedulingManager.shared.isLoginItemEnabled
    @State private var showClearConfirmation = false
    @State private var showDiagnostics = false

    var body: some View {
        MacGlassPage {
            MacGlassPageHeader(
                title: String(localized: "Settings"),
                subtitle: String(localized: "Health.md for Mac is a local export destination. Formats, metrics, date ranges, filenames, write modes and Data Detail are set on iPhone.")
            )

            MacGlassSection(title: String(localized: "Exports")) {
                MacGlassRow(String(localized: "Data Detail"), value: String(localized: "Set on iPhone"))
                MacGlassDivider()
                MacGlassRow(String(localized: "Detailed time series"), value: String(localized: "Timestamped samples, no canonical archive"))
                MacGlassDivider()
                MacGlassRow(String(localized: "Lossless health records"), value: String(localized: "Adds the HealthKit source · larger files"))
            }

            MacGlassSection(title: String(localized: "Storage")) {
                MacGlassRow(
                    String(localized: "Cached legacy records"),
                    value: String(localized: "\(healthDataStore.recordCount) · old manual sync only")
                )
                MacGlassDivider()
                MacGlassRow(title: String(localized: "Delete legacy synced data")) {
                    // MacSettingsG: "—" when nothing is cached, otherwise the delete action.
                    if healthDataStore.recordCount > 0 {
                        Button(String(localized: "Delete…")) {
                            showClearConfirmation = true
                        }
                        .buttonStyle(MacGlassRowButtonStyle(tone: .coral))
                        .accessibilityHint("Removes cached Health data from the old Mac sync flow")
                    } else {
                        MacGlassValue("—", tone: .coral)
                            .accessibilityLabel(String(localized: "Nothing to delete"))
                    }
                }
            }

            MacGlassSection(title: String(localized: "Privacy")) {
                MacGlassRow(String(localized: "Analytics"), value: String(localized: "None collected"))
                MacGlassDivider()
                MacGlassRow(title: String(localized: "Diagnostics")) {
                    Button(String(localized: "Inspect local events · no automatic uploads")) {
                        showDiagnostics = true
                    }
                    .buttonStyle(MacGlassRowButtonStyle())
                    .accessibilityIdentifier("diagnostics.entry")
                }
            }

            MacGlassSection(title: String(localized: "General")) {
                MacGlassRow(title: String(localized: "Launch at login")) {
                    MacGlassOnOffButton(title: String(localized: "Launch at login"), isOn: launchAtLoginBinding)
                }
                MacGlassDivider()
                MacGlassRow(title: String(localized: "Show in menu bar")) {
                    MacGlassOnOffButton(title: String(localized: "Show in menu bar"), isOn: $showsMenuBarExtra)
                }
            }
        }
        .onAppear { launchesAtLogin = SchedulingManager.shared.isLoginItemEnabled }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .geistDialog(
            isPresented: $showClearConfirmation,
            title: Text("Delete Legacy Synced Data?"),
            message: Text("This removes the old iPhone→Mac cache from this Mac. It does not affect Health data on iPhone or exported files."),
            actions: [
                .cancel(),
                .destructive("Delete") {
                    healthDataStore.deleteAll()
                }
            ]
        )
    }

    /// Registers or unregisters the app with `SMAppService`, then reads back the real status
    /// so a refused registration (for example, pending approval) is not shown as on.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchesAtLogin },
            set: { enabled in
                if enabled {
                    SchedulingManager.shared.enableLoginItem()
                } else {
                    SchedulingManager.shared.disableLoginItem()
                }
                launchesAtLogin = SchedulingManager.shared.isLoginItemEnabled
            }
        )
    }
}

#endif
