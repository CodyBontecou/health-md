#if os(iOS)
import SwiftUI

/// Reuses the schedule's native sheet and Form controls. Saving opts in only future occurrences;
/// pending work keeps its frozen scope, correction choice and destination authority.
struct ReceiverCoverageSettingsButton: View {
    enum Style { case form, glass }
    var profile: ExportProfile? = nil
    /// `.glass` matches the card rows of the Glass schedule screens; `.form` is a plain Form row.
    var style: Style = .form
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @Environment(\.glassPalette) private var palette
    @State private var showing = false
    var body: some View {
        trigger
            .configurationChangesProtected()
            .sheet(isPresented: $showing) {
                ReceiverCoverageSettingsEditor(scope: ReceiverCoverageSettings.scope(profile?.id),
                    uploadURL: schedulingManager.receiverCoverageUploadURL(for: profile) ?? "")
            }
    }

    @ViewBuilder private var trigger: some View {
        switch style {
        case .form:
            Button("Receiver-aware scheduling") { showing = true }
        case .glass:
            GlassPanel {
                Button { showing = true } label: {
                    GlassRow(
                        title: String(localized: "Receiver-aware scheduling"),
                        subtitle: String(localized: "Skip completed days your receiver already has")
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.muted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("receiverCoverage.open")
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
    private enum Failure { case load, save }
    @State private var failure: Failure?
    /// Bumped on every failure so a repeated, identical error is announced again.
    @State private var failedAttempts = 0
    var body: some View {
        NavigationStack {
            Form {
                // First in the form so a failed Save is visible without scrolling.
                if let failure {
                    Section { Text(Self.message(failure)).foregroundStyle(.red) }
                }
                Section {
                    Toggle("Skip retained completed days", isOn: $enabled)
                } footer: {
                    Text("Off resends the full lookback. Today Refresh remains independent. Changes apply to new occurrences; pending work keeps its original plan.")
                }
                if enabled {
                    Section {
                        // Explicit labels: placeholders vanish once typed and are not reliably spoken.
                        TextField("Explicit HTTPS preflight URL", text: $preflightURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityLabel("Explicit HTTPS preflight URL")
                            .accessibilityIdentifier("receiverCoverage.preflightURL")
                        TextField("Receiver scope ID", text: $scopeID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Receiver scope ID")
                            .accessibilityIdentifier("receiverCoverage.scopeID")
                        TextField("Correction window (0–30 days)", text: $correction).keyboardType(.numberPad)
                            .accessibilityLabel("Correction window (0–30 days)")
                            .accessibilityIdentifier("receiverCoverage.correction")
                    } header: {
                        Text("Receiver configuration")
                    } footer: {
                        Text("Use your receiver's documented same-origin preflight endpoint and a scope for this platform, account and output profile. Choose a new scope after changing output settings. Choose 0 explicitly to disable completed-day correction refresh.")
                    }
                    Section { Text(ReceiverCoverageConfiguration.warning) }
                    Section { Text("Personal compatibility API destinations only. Managed clinic credentials are not supported for receiver-aware scheduling.") }
                }
            }
            .onChange(of: failedAttempts) {
                if let failure { AccessibilityNotification.Announcement(Self.message(failure)).post() }
            }
            .navigationTitle("Receiver coverage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !protection.isEnabled else { protection.presentBlockedChangeToast(); return }
                        failure = nil
                        do {
                            let config: ReceiverCoverageConfiguration?
                            if enabled {
                                guard let count = Int(correction), (0...30).contains(count) else { fail(); return }
                                config = ReceiverCoverageConfiguration(preflightURL: preflightURL, scopeID: scopeID, refreshRecentDays: count)
                            } else { config = nil }
                            try ReceiverCoverageSettings.shared.save(config, scope: scope, uploadURL: uploadURL)
                            dismiss()
                        } catch { fail() }
                    }
                }
            }
            .task {
                do {
                    if let value = try ReceiverCoverageSettings.shared.configuration(scope) {
                        enabled = true; preflightURL = value.preflightURL; scopeID = value.scopeID; correction = String(value.refreshRecentDays)
                    }
                } catch { fail(.load) }
            }
        }
    }

    /// A corrupt saved setting is a read problem, not a failed save; the schedule treats it as off.
    private static func message(_ failure: Failure) -> String {
        switch failure {
        case .load: String(localized: "Couldn\u{2019}t read the saved receiver-aware setting, so scheduled exports treat it as off. Save to replace it.")
        case .save: String(localized: "Could not save receiver-aware scheduling. Check the endpoint, scope, correction choice and secure credential storage.")
        }
    }

    private func fail(_ kind: Failure = .save) {
        failure = kind
        failedAttempts += 1
    }
}
#endif
