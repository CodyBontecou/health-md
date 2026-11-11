#if os(iOS)
import SwiftUI

/// The old "Schedule & history" screen's Clear History, which no board shows. It sits in
/// App & support (SettingsMoreG) so the capability stays reachable now that the Archive
/// carries history and retry. Clearing also empties the Archive's coverage, as before,
/// so it asks first; the configuration lock still intercepts it.
struct GlassClearExportHistoryRow: View {
    @ObservedObject private var history = ExportHistoryManager.shared
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var confirming = false

    var body: some View {
        GlassSettingsRow(
            title: String(localized: "Clear export history"),
            subtitle: String(localized: "Removes past runs and the Archive calendar. Files already written stay."),
            systemImage: "clock.arrow.circlepath",
            tile: .settingsTileGray
        ) {
            configurationProtection.performConfigurationChange { confirming = true }
        }
        .disabled(history.history.isEmpty)
        .accessibilityIdentifier("schedule.history.clear")
        .confirmationDialog(
            String(localized: "Clear export history?"),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear History"), role: .destructive) {
                history.clearHistory()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Removes past runs and the Archive calendar. Files already written stay."))
        }
    }
}
#endif
