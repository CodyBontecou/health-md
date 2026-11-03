import SwiftUI

/// Enrollment grants app access only. Sharing and selection of a clinic destination are explicit.
struct ClinicAccessView: View {
    @ObservedObject private var manager = ClinicSponsorshipManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var invitation = ""
    @State private var uploadToken = ""
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your clinic can sponsor delivery to its approved endpoint. You choose what to share. Other export destinations require your own Health.md access.")
                }
                if manager.status.storageUnavailable {
                    Section { Text("Unlock your phone and try again. Clinic access could not be read securely.") }
                } else if manager.status.active {
                    Section("Sponsored access") {
                        LabeledContent("Clinic", value: manager.status.clinicName ?? "Clinic")
                        if let endpoint = manager.status.endpoint {
                            Text(endpoint).font(.footnote.monospaced()).textSelection(.enabled)
                        }
                    }
                    Section {
                        Toggle("Allow sharing with this clinic", isOn: Binding(
                            get: { manager.status.sharingAuthorized },
                            set: { value in
                                do { try manager.setSharingAuthorized(value) }
                                catch { message = "Could not save your sharing choice. Please try again." }
                            }))
                            .accessibilityIdentifier("clinic-sharing-toggle")
                        Text("Only the metrics and dates you select in Health.md will be sent. Scheduling uses your saved selection. Turning sharing off stops future clinic uploads; it does not delete copies the clinic already received.")
                            .font(.footnote)
                    } header: { Text("Your sharing choice") }
                    Section {
                        SecureField("Clinic upload token (optional)", text: $uploadToken)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled().privacySensitive()
                            .accessibilityIdentifier("clinic-upload-token")
                        Button("Use clinic destination") {
                            do {
                                if !uploadToken.isEmpty { try manager.setUploadAuthorization("Bearer " + uploadToken) }
                                try manager.requestClinicDestination()
                                uploadToken = ""
                                dismiss()
                            } catch { message = "Could not configure the clinic connection. Please try again." }
                        }
                        .disabled(!manager.status.sharingAuthorized || busy)
                        .accessibilityIdentifier("clinic-use-destination")
                    } footer: {
                        Text("If your clinic supplies a personal upload token, enter it here. It is stored securely and used only for this clinic's approved endpoint.")
                    }
                } else if manager.status.configured && !manager.status.enrollmentPending {
                    Section("Clinic invitation") {
                        SecureField("Invitation code", text: $invitation)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled().privacySensitive()
                            .accessibilityIdentifier("clinic-invitation-code")
                        Button("Accept invitation") {
                            run {
                                try await manager.enroll(code: invitation.trimmingCharacters(in: .whitespacesAndNewlines))
                                invitation = ""
                            }
                        }
                        .disabled(busy || invitation.isEmpty)
                        .accessibilityIdentifier("clinic-accept-invitation")
                    }
                } else if !manager.status.configured {
                    Section { Text("Clinic access is not configured in this version of Health.md.") }
                }
                if manager.status.enrollmentPending {
                    Section("Enrollment recovery") {
                        Text("Your invitation is saved securely. Retry to finish enrollment; you do not need a new code.")
                        Button("Retry enrollment") { run { try await manager.resumeEnrollment() } }.disabled(busy)
                    }
                }
                if manager.status.clinicName != nil || manager.status.enrollmentPending {
                    Section {
                        Button("Refresh clinic access") { run { await manager.refresh() } }.disabled(busy)
                        Button("Disconnect clinic", role: .destructive) { confirmDisconnect = true }
                            .disabled(busy).accessibilityIdentifier("clinic-disconnect")
                    }
                }
                if busy { ProgressView("Updating clinic access…") }
                if let message { Section { Text(message).accessibilityIdentifier("clinic-access-message") } }
            }
            .navigationTitle("Clinic access")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Disconnect this clinic?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { run { try await manager.disconnect() } }
            } message: { Text("Clinic-sponsored sharing will stop. Your own purchased access and local health data remain available.") }
            .task { await manager.refresh() }
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; message = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await action() }
            catch is CancellationError { }
            catch { message = "Could not update clinic access. Check your connection, or retry your saved enrollment." }
        }
    }
}
