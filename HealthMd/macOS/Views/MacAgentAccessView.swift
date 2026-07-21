#if os(macOS)
import AppKit
import SwiftUI

struct MacAgentAccessView: View {
    @EnvironmentObject private var accessManager: MacAgentAccessManager
    @EnvironmentObject private var profileManager: HealthContextProfileManager

    @State private var newAgentName = ""
    @State private var selectedRegistrationID: UUID?
    @State private var selectedProfileID: UUID?
    @State private var grantPendingConfirmation: AgentAccessGrant?
    @State private var registrationPendingRevocation: AgentClientRegistration?
    @State private var grantPendingRevocation: AgentAccessGrant?
    @State private var showingClearActivityConfirmation = false

    var body: some View {
        Form {
            Section {
                Text("Register each local agent explicitly. Health Context Profiles and Apple Health permission remain separate from an agent grant.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    TextField("Agent name", text: $newAgentName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Local agent name")
                    Button("Register Local Agent") {
                        Task {
                            do {
                                let registration = try await accessManager.registerLocalAgent(
                                    displayName: newAgentName
                                )
                                newAgentName = ""
                                selectedRegistrationID = registration.id
                            } catch { }
                        }
                    }
                    .disabled(newAgentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accessManager.isWorking)
                }
            } header: {
                BrandLabel("Registered Local Agents")
            } footer: {
                Text("A random credential is stored in Keychain and shown once. Health.md cannot show the same credential again; rotate it if it is lost.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }

            if let error = accessManager.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.error)
                } header: {
                    BrandLabel("Agent Access Store")
                }
            }

            if !accessManager.isLoaded {
                Section { ProgressView("Loading agent access…") }
            } else if accessManager.registrations.isEmpty {
                Section {
                    Text("No registered agents. Profiles alone do not authorize access.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            } else {
                Section {
                    ForEach(accessManager.registrations) { registration in
                        registrationRow(registration)
                    }
                } header: {
                    BrandLabel("Clients and Grants")
                }
            }

            Section {
                Picker("Local Agent", selection: $selectedRegistrationID) {
                    Text("Select an agent").tag(nil as UUID?)
                    ForEach(activeRegistrations) { registration in
                        Text(registration.displayName).tag(registration.id as UUID?)
                    }
                }

                Picker("Exact Profile Revision", selection: $selectedProfileID) {
                    Text("Select a profile").tag(nil as UUID?)
                    ForEach(profileManager.profiles) { profile in
                        Text("\(profile.name) · revision \(profile.revision.rawValue)")
                            .tag(profile.id as UUID?)
                    }
                }

                if let profile = selectedProfile {
                    profileScopeSummary(profile)
                }

                Button("Create Pending Grant") {
                    createPendingGrant()
                }
                .disabled(selectedRegistrationID == nil || selectedProfile == nil || accessManager.isWorking)
                .accessibilityHint("Creates a grant pinned to the selected profile revision and digest, then asks for confirmation")
            } header: {
                BrandLabel("Grant an Exact Profile Revision")
            } footer: {
                Text("A grant is not active until you confirm it. Later profile edits create a different revision or digest and do not silently expand this grant.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }

            Section {
                if accessManager.activity.isEmpty {
                    Text("No agent activity recorded.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                } else {
                    ForEach(accessManager.activity) { record in
                        activityRow(record)
                    }
                }

                Button("Clear Activity History", role: .destructive) {
                    showingClearActivityConfirmation = true
                }
                .disabled(accessManager.activity.isEmpty || accessManager.isWorking)
            } header: {
                BrandLabel("PHI-Minimized Activity")
            } footer: {
                Text("History contains scope, operation, aggregate counts, outcome, and opaque identifiers. It never stores health values, prompts, paths, endpoint URLs, peer names, response bodies, or credentials. Clearing it does not change clients, grants, or Keychain credentials.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }
        }
        .formStyle(.grouped)
        .task {
            async let accessLoad: Void = accessManager.load()
            async let profileLoad: Void = profileManager.load()
            _ = await (accessLoad, profileLoad)
            repairSelections()
        }
        .onChange(of: accessManager.registrations) { _, _ in repairSelections() }
        .onChange(of: profileManager.profiles) { _, _ in repairSelections() }
        .sheet(
            isPresented: Binding(
                get: { accessManager.credentialReveal != nil },
                set: { if !$0 { accessManager.dismissCredentialReveal() } }
            )
        ) {
            credentialRevealSheet
        }
        .confirmationDialog(
            grantPendingConfirmation.map(grantConfirmationTitle) ?? "Confirm Agent Grant?",
            isPresented: Binding(
                get: { grantPendingConfirmation != nil },
                set: { if !$0 { grantPendingConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: grantPendingConfirmation
        ) { grant in
            Button("Confirm Grant") {
                Task {
                    try? await accessManager.confirmGrant(
                        grant.id,
                        broadScopeAcknowledged: true
                    )
                    grantPendingConfirmation = nil
                }
            }
            Button("Leave Pending", role: .cancel) { grantPendingConfirmation = nil }
        } message: { grant in
            Text(grantConfirmationMessage(grant))
        }
        .confirmationDialog(
            "Revoke this agent?",
            isPresented: Binding(
                get: { registrationPendingRevocation != nil },
                set: { if !$0 { registrationPendingRevocation = nil } }
            ),
            titleVisibility: .visible,
            presenting: registrationPendingRevocation
        ) { registration in
            Button("Revoke “\(registration.displayName)”", role: .destructive) {
                Task {
                    try? await accessManager.revokeRegistration(registration.id)
                    registrationPendingRevocation = nil
                }
            }
            Button("Cancel", role: .cancel) { registrationPendingRevocation = nil }
        } message: { _ in
            Text("Access stops immediately, the Keychain credential is deleted, and existing grants can no longer authorize requests.")
        }
        .confirmationDialog(
            "Revoke this grant?",
            isPresented: Binding(
                get: { grantPendingRevocation != nil },
                set: { if !$0 { grantPendingRevocation = nil } }
            ),
            titleVisibility: .visible,
            presenting: grantPendingRevocation
        ) { grant in
            Button("Revoke Grant", role: .destructive) {
                Task {
                    try? await accessManager.revokeGrant(grant.id)
                    grantPendingRevocation = nil
                }
            }
            Button("Cancel", role: .cancel) { grantPendingRevocation = nil }
        } message: { _ in
            Text("Revocation is immediate and cannot be resumed. Create and confirm a new grant to restore access.")
        }
        .confirmationDialog(
            "Clear agent activity history?",
            isPresented: $showingClearActivityConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Activity Only", role: .destructive) {
                Task { try? await accessManager.clearActivityHistory() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes only PHI-minimized activity records. Registrations, grants, revocations, profiles, and Keychain credentials are unchanged.")
        }
    }

    private var activeRegistrations: [AgentClientRegistration] {
        accessManager.registrations.filter { $0.state == .active }
    }

    private var selectedProfile: HealthContextProfile? {
        guard let selectedProfileID else { return nil }
        return profileManager.profile(id: selectedProfileID)
    }

    @ViewBuilder
    private func registrationRow(_ registration: AgentClientRegistration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(registration.displayName)
                        .font(BrandTypography.bodyMedium())
                    Text(registration.state == .active ? "Active local agent" : "Revoked")
                        .font(BrandTypography.caption())
                        .foregroundStyle(registration.state == .active ? Color.success : Color.textMuted)
                }
                Spacer()
                if registration.state == .active {
                    Button("Rotate Credential") {
                        Task { try? await accessManager.rotateCredential(for: registration.id) }
                    }
                    .buttonStyle(.borderless)
                    Button("Revoke", role: .destructive) {
                        registrationPendingRevocation = registration
                    }
                    .buttonStyle(.borderless)
                }
            }

            ForEach(accessManager.grants(for: registration.id)) { grant in
                grantRow(grant)
                    .padding(.leading, 12)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func grantRow(_ grant: AgentAccessGrant) -> some View {
        let status = grant.status(at: Date())
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profile revision \(grant.profileReference.revision.rawValue)")
                    .font(BrandTypography.body())
                Text("\(statusLabel(status)) · digest \(grant.profileReference.policyDigest.prefix(12))…")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
                    .textSelection(.enabled)
            }
            Spacer()
            switch status {
            case .pendingConfirmation:
                Button("Confirm") { grantPendingConfirmation = grant }
                    .buttonStyle(.borderless)
            case .active:
                Button("Pause") {
                    Task { try? await accessManager.pauseGrant(grant.id) }
                }
                .buttonStyle(.borderless)
            case .paused:
                Button("Resume") {
                    Task { try? await accessManager.resumeGrant(grant.id) }
                }
                .buttonStyle(.borderless)
            case .expired, .revoked:
                EmptyView()
            }
            if status != .revoked {
                Button("Revoke", role: .destructive) { grantPendingRevocation = grant }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func profileScopeSummary(_ profile: HealthContextProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pinned digest: \((try? profile.policyDigest())?.prefix(16) ?? "Unavailable")…")
                .font(Typography.monoCaption())
                .textSelection(.enabled)
            Text(profileScopeText(profile))
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func activityRow(_ record: AgentActivityRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(accessManager.registrationName(for: record.clientIdentity))
                    .font(BrandTypography.bodyMedium())
                Spacer()
                Text(record.timestamp, style: .relative)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }
            Text("\(operationLabel(record.operation)) · \(record.outcome.rawValue) · \(record.resultRecordCount) records · \(ByteCountFormatter.string(fromByteCount: Int64(record.resultByteCount), countStyle: .file))")
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textSecondary)
            Text("\(dateScopeLabel(record.dateScope)) · \(metricScopeLabel(record.metricScope)) · \(record.detailLevel.rawValue) · \(record.destinationClass.rawValue)")
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var credentialRevealSheet: some View {
        if let reveal = accessManager.credentialReveal {
            VStack(alignment: .leading, spacing: 16) {
                Text(reveal.isRotation ? "New Credential" : "Agent Registered")
                    .font(.title2.bold())
                Text("Copy this credential now. It is stored in Keychain and will never be displayed again after this window closes.")
                    .foregroundStyle(Color.textSecondary)
                Text(reveal.credential)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgTertiary, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Spacer()
                    Button("Close Without Copying") {
                        accessManager.dismissCredentialReveal()
                    }
                    Button("Copy Once and Close") {
                        guard let credential = accessManager.takeCredentialForCopy() else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(credential, forType: .string)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 560)
            .interactiveDismissDisabled()
        }
    }

    private func createPendingGrant() {
        guard let registrationID = selectedRegistrationID,
              let profile = selectedProfile else { return }
        Task {
            do {
                grantPendingConfirmation = try await accessManager.createGrant(
                    for: registrationID,
                    profile: profile
                )
            } catch { }
        }
    }

    private func repairSelections() {
        if selectedRegistrationID.flatMap({ selected in
            activeRegistrations.first(where: { $0.id == selected })
        }) == nil {
            selectedRegistrationID = activeRegistrations.first?.id
        }
        if selectedProfileID.flatMap({ profileManager.profile(id: $0) }) == nil {
            selectedProfileID = profileManager.profiles.first?.id
        }
    }

    private func grantConfirmationTitle(_ grant: AgentAccessGrant) -> String {
        accessManager.requiresBroadScopeConfirmation(grant)
            ? "Confirm Broad Health Data Access?"
            : "Confirm Agent Grant?"
    }

    private func grantConfirmationMessage(_ grant: AgentAccessGrant) -> String {
        let broad = accessManager.requiresBroadScopeConfirmation(grant)
        if broad {
            return "This grant allows the broad scope shown by the exact pinned profile, which can include all Health.md data, all available history, and lossless source records, including current and future metrics. Confirm only if this local agent should have that access. Apple Health permission remains separate."
        }
        return "Confirm the exact metric, date, detail, operation, and destination scope pinned by this profile revision and digest."
    }

    private func profileScopeText(_ profile: HealthContextProfile) -> String {
        let metrics: String
        switch profile.metricScope {
        case .allAvailable: metrics = "all current and future metrics"
        case .selected(let ids): metrics = "\(ids.count) exact metrics"
        }
        let dates: String
        switch profile.datePolicy {
        case .allHistory: dates = "all available history"
        case .explicit: dates = "an exact fixed date range"
        case .callerProvided: dates = "a caller-provided date range"
        case .relative: dates = "a relative date range"
        }
        let detail = profile.detailLevel == .lossless ? "lossless source records" : "summary detail"
        return "Allows \(metrics), \(dates), and \(detail) on \(profile.allowedSurfaces.count) exact surface(s)."
    }

    private func statusLabel(_ status: AgentAccessGrantStatus) -> String {
        switch status {
        case .pendingConfirmation: return "Pending confirmation"
        case .active: return "Active"
        case .paused: return "Paused"
        case .expired: return "Expired"
        case .revoked: return "Revoked"
        }
    }

    private func operationLabel(_ operation: AgentAccessOperation) -> String {
        switch operation {
        case .readHealthData: return "Read"
        case .exportHealthData: return "Export"
        case .streamHealthData: return "Stream"
        case .listAvailableMetrics: return "List metrics"
        }
    }

    private func dateScopeLabel(_ scope: AgentDateScope) -> String {
        switch scope {
        case .allHistory: return "All history"
        case .exactRange(let range):
            return "\(range.start.formatted(date: .abbreviated, time: .omitted))–\(range.end.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func metricScopeLabel(_ scope: AgentMetricScope) -> String {
        switch scope {
        case .allAvailable: return "All metrics"
        case .metricIDs(let ids): return "\(ids.count) metrics"
        }
    }
}
#endif
