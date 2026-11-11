#if os(iOS)
import SwiftUI

/// ClinicAccessG, backed by `ClinicSponsorshipManager`. Enrollment grants app access only;
/// sharing, the clinic destination and clinic sync requests are separate explicit choices.
struct GlassClinicAccessScreen: View {
    let coordinator: ExportProfileCoordinator?

    @ObservedObject private var manager = ClinicSponsorshipManager.shared
    @ObservedObject private var syncRequests = ClinicSyncDoorbellManager.shared
    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var invitation = ""
    @State private var tokenDraft = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmingDisconnect = false

    private var status: ClinicSponsorshipStatus { manager.status }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                summaryPanel

                if !status.configured {
                    note(String(localized: "Clinic access is not configured in this version of Health.md."))
                } else if status.storageUnavailable {
                    // A Keychain read or write failure, not a locked phone: the record is
                    // readable after first unlock, so "unlock your phone" was misleading.
                    GlassBanner(title: String(localized: "Clinic access could not be read securely. Try again later."),
                                systemImage: "exclamationmark.triangle", tone: .warning)
                } else if status.active {
                    sharingSection
                    uploadTokenSection
                    syncRequestsSection
                } else if status.enrollmentPending {
                    recoverySection
                } else {
                    invitationSection
                }

                if status.clinicName != nil || status.enrollmentPending {
                    managementSection
                }

                if busy {
                    ProgressView(String(localized: "Updating clinic access…"))
                        .tint(palette.accent)
                        .frame(maxWidth: .infinity)
                }
                if let errorMessage {
                    GlassBanner(title: errorMessage, systemImage: "exclamationmark.triangle", tone: .warning)
                        .accessibilityIdentifier("clinic-access-message")
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Clinic access"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.clinicAccess")
        .task { await manager.refresh() }
        .confirmationDialog(
            String(localized: "Disconnect clinic"),
            isPresented: $confirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Disconnect clinic"), role: .destructive) {
                run { try await manager.disconnect() }
            }
        } message: {
            Text("Clinic-sponsored sharing will stop. Your own purchased access and local health data remain available.")
        }
    }

    // MARK: - Sections

    private var summaryPanel: some View {
        GlassPanel {
            GlassRow(
                title: status.clinicName ?? String(localized: "No clinic connected"),
                subtitle: status.active
                    ? (status.endpoint ?? String(localized: "Sponsored access · invitation accepted"))
                    : String(localized: "Your clinic sends an invitation when it offers access.")
            ) {
                GlassIconTile(systemImage: "cross.case", color: .settingsTileGreen)
            } trailing: {
                EmptyView()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var invitationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Clinic invitation"))
            GlassPanel {
                secureField(String(localized: "Invitation code"), text: $invitation)
                    .accessibilityIdentifier("clinic-invitation-code")
                Button(String(localized: "Accept invitation")) {
                    let code = invitation.trimmingCharacters(in: .whitespacesAndNewlines)
                    run {
                        try await manager.enroll(code: code)
                        invitation = ""
                    }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(busy || invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(GlassMetrics.panelPadding)
                .accessibilityIdentifier("clinic-accept-invitation")
            }
            note(String(localized: "Your clinic can sponsor delivery to its approved endpoint. You choose what to share. Other export destinations require your own Health.md access."))
        }
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Enrollment recovery"))
            GlassPanel {
                GlassSettingsRow(title: String(localized: "Retry enrollment")) {
                    run { try await manager.resumeEnrollment() }
                }
                .disabled(busy)
            }
            note(String(localized: "Your invitation is saved securely. Retry to finish enrollment; you do not need a new code."))
        }
    }

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Your sharing choice"))
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Share with this clinic"),
                    isOn: Binding(
                        get: { status.sharingAuthorized },
                        set: { value in
                            configurationProtection.performConfigurationChange {
                                do { try manager.setSharingAuthorized(value) }
                                catch { errorMessage = String(localized: "Could not save your sharing choice. Please try again.") }
                            }
                        })
                )
                .accessibilityIdentifier("clinic-sharing-toggle")
                Button {
                    configurationProtection.performConfigurationChange { useClinicDestination() }
                } label: {
                    GlassRow(title: String(localized: "Use clinic destination")) {
                        HStack(spacing: 8) {
                            Text(usesClinicDestination ? String(localized: "In profile") : String(localized: "Off"))
                                .glassFont(.body)
                                .foregroundStyle(palette.muted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.muted)
                                .accessibilityHidden(true)
                        }
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(palette.line).frame(height: 1)
                            .padding(.horizontal, GlassMetrics.panelPadding)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!status.sharingAuthorized || busy)
                .accessibilityIdentifier("clinic-use-destination")
            }
            note(String(localized: "Only metrics and dates you select are sent. Turning sharing off stops future uploads; it doesn’t delete what the clinic already has."))
        }
    }

    private var uploadTokenSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upload token").glassFont(.caption).foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
                secureField(String(localized: "Only if your clinic gave you one"), text: $tokenDraft, padded: false)
                    .accessibilityLabel(String(localized: "Upload token"))
                    .accessibilityIdentifier("clinic-upload-token")
                    .onSubmit(saveToken)
                Text("Stored securely, used only for this clinic’s endpoint.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .padding(.vertical, 10)
            if !tokenDraft.isEmpty {
                Button(String(localized: "Save"), action: saveToken)
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .padding(GlassMetrics.panelPadding)
            }
        }
        .configurationChangesProtected()
    }

    private var syncRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Sync requests"))
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Allow sync requests from this clinic"),
                    isOn: Binding(
                        get: { syncRequests.isEnabled },
                        set: { value in
                            Task { value ? await syncRequests.enable() : await syncRequests.disable() }
                        })
                )
                .disabled(syncRequests.state == .updating || (!syncRequests.isEnabled && !syncRequests.canEnable))
                .accessibilityIdentifier("clinic-sync-requests-toggle")
            }
            if case .unavailable(let reason) = syncRequests.state {
                GlassBanner(title: reason, systemImage: "bell.slash", tone: .warning)
                    .accessibilityIdentifier("clinic-sync-requests-message")
            }
            note(String(localized: "Your clinic can send a notification asking for your latest data. Nothing is sent until you tap it; then yesterday and today are shared with this clinic. Turning this off stops new requests."))
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassPanel {
                GlassSettingsRow(title: String(localized: "Refresh clinic access")) {
                    run { await manager.refresh() }
                }
                .disabled(busy)
                Button(role: .destructive) {
                    configurationProtection.performConfigurationChange { confirmingDisconnect = true }
                } label: {
                    Text("Disconnect clinic")
                        .glassFont(.body)
                        .foregroundStyle(palette.coral)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.line).frame(height: 1)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                }
                .accessibilityIdentifier("clinic-disconnect")
            }
            note(String(localized: "Your own purchased access and local data stay available."))
        }
    }

    // MARK: - Actions

    /// Whether an automation already sends to the approved clinic endpoint.
    private var usesClinicDestination: Bool {
        guard let endpoint = status.endpoint, let coordinator else { return false }
        let destinations = ProfileDestinationStore()
        return coordinator.profileStore.profiles.contains {
            $0.target == .apiEndpoint && destinations.apiEndpoint(id: $0.apiEndpointID)?.endpointURLString == endpoint
        }
    }

    /// The root view creates or activates the clinic automation for this request.
    private func useClinicDestination() {
        do {
            try saveTokenIfEntered()
            try manager.requestClinicDestination()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Could not configure the clinic connection. Please try again.")
        }
    }

    private func saveToken() {
        configurationProtection.performConfigurationChange {
            do {
                try saveTokenIfEntered()
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "Could not save the upload token. Please try again.")
            }
        }
    }

    private func saveTokenIfEntered() throws {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        try manager.setUploadAuthorization("Bearer " + token)
        tokenDraft = ""
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await action() }
            catch is CancellationError { }
            catch { errorMessage = String(localized: "Could not update clinic access. Check your connection, or retry your saved enrollment.") }
        }
    }

    // MARK: - Pieces

    private func secureField(_ prompt: String, text: Binding<String>, padded: Bool = true) -> some View {
        SecureField(prompt, text: text)
            .textFieldStyle(.plain)
            .glassFont(.body)
            .foregroundStyle(palette.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .privacySensitive()
            .frame(minHeight: padded ? GlassMetrics.rowMinHeight : 28)
            .padding(.horizontal, padded ? GlassMetrics.panelPadding : 0)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .glassFont(.rowSubtitle)
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
#endif
