#if os(iOS)
import SwiftUI

/// Reuses the schedule's native sheet and Form controls. Saving opts in only future occurrences;
/// pending work keeps its frozen scope, correction choice and destination authority.
struct ReceiverCoverageSettingsButton: View {
    var profile: ExportProfile? = nil
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var showing = false
    var body: some View {
        Button("Receiver-aware scheduling") { showing = true }
            .configurationChangesProtected()
            .sheet(isPresented: $showing) {
                ReceiverCoverageSettingsEditor(scope: ReceiverCoverageSettings.scope(profile?.id),
                    uploadURL: schedulingManager.receiverCoverageUploadURL(for: profile) ?? "")
            }
    }
}

private struct ReceiverCoverageSettingsEditor: View {
    let scope: String
    let uploadURL: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var protection: ConfigurationProtectionManager
    @State private var enabled = false
    @State private var preflightURL = ""
    @State private var scopeID = ""
    @State private var correction = ""
    @State private var hasError = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Skip retained completed days", isOn: $enabled)
                } footer: {
                    Text("Off resends the full lookback. Today Refresh remains independent. Changes apply to new occurrences; pending work keeps its original plan.")
                }
                if enabled {
                    Section {
                        TextField("Explicit HTTPS preflight URL", text: $preflightURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        TextField("Receiver scope ID", text: $scopeID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Correction window (0–30 days)", text: $correction).keyboardType(.numberPad)
                    } header: {
                        Text("Receiver configuration")
                    } footer: {
                        Text("Use your receiver's documented same-origin preflight endpoint and a scope for this platform, account and output profile. Choose a new scope after changing output settings. Choose 0 explicitly to disable completed-day correction refresh.")
                    }
                    Section { Text(ReceiverCoverageConfiguration.warning) }
                    Section { Text("Personal compatibility API destinations only. Managed clinic credentials are not supported for receiver-aware scheduling.") }
                }
                if hasError { Text("Could not save receiver-aware scheduling. Check the endpoint, scope, correction choice and secure credential storage.").foregroundStyle(.red) }
            }
            .navigationTitle("Receiver coverage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !protection.isEnabled else { protection.presentBlockedChangeToast(); return }
                        do {
                            let config: ReceiverCoverageConfiguration?
                            if enabled {
                                guard let count = Int(correction), (0...30).contains(count) else { hasError = true; return }
                                config = ReceiverCoverageConfiguration(preflightURL: preflightURL, scopeID: scopeID, refreshRecentDays: count)
                            } else { config = nil }
                            try ReceiverCoverageSettings.shared.save(config, scope: scope, uploadURL: uploadURL)
                            dismiss()
                        } catch { hasError = true }
                    }
                }
            }
            .task {
                do {
                    if let value = try ReceiverCoverageSettings.shared.configuration(scope) {
                        enabled = true; preflightURL = value.preflightURL; scopeID = value.scopeID; correction = String(value.refreshRecentDays)
                    }
                } catch { hasError = true }
            }
        }
    }
}
#endif
