#if os(macOS)
import SwiftUI

struct MacHealthContextProfilesView: View {
    @EnvironmentObject private var profileManager: HealthContextProfileManager
    @State private var showingFullAccessConfirmation = false
    @State private var profilePendingDeletion: HealthContextProfile?

    var body: some View {
        Form {
            Section {
                Text("Health Context Profiles are reusable data-access policies for registered local agents. They are separate from Apple Health permission and export formatting.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showingFullAccessConfirmation = true
                } label: {
                    Label("Create Full Health Access Profile", systemImage: "plus.shield")
                }
                .accessibilityHint("Requires confirmation before allowing all metrics, providers, source records, and history")
            } header: {
                BrandLabel("Health Context Profiles")
            }

            if let error = profileManager.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.error)
                } header: {
                    BrandLabel("Profile Store")
                }
            } else if !profileManager.isLoaded {
                Section { ProgressView("Loading profiles…") }
            } else if profileManager.profiles.isEmpty {
                Section {
                    Text("No profiles. Agents cannot receive Health Context until you create a profile and grant it to a registered client.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            } else {
                Section {
                    ForEach(profileManager.profiles) { profile in
                        profileRow(profile)
                    }
                } header: {
                    BrandLabel("Saved Profiles")
                }
            }

            Section {
                Text("Full Health Access dynamically includes newly supported metrics and providers, preserves lossless source detail, and allows all available history. Query pages and transfer partitions bound memory and wire usage; they do not hide an inaccessible tail.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                BrandLabel("No Artificial Data Caps")
            }
        }
        .formStyle(.grouped)
        .task { await profileManager.load() }
        .confirmationDialog(
            "Create a Full Health Access Profile?",
            isPresented: $showingFullAccessConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create Full-Access Profile") {
                Task {
                    do {
                        try await profileManager.createFullAccessProfile()
                    } catch {
                        await profileManager.load()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This policy allows registered agents you later grant to request all current and future Health.md metrics, all providers, lossless source records, and all available history. It does not grant Apple Health permission by itself.")
        }
        .confirmationDialog(
            "Delete this Health Context Profile?",
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { if !$0 { profilePendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: profilePendingDeletion
        ) { profile in
            Button("Delete “\(profile.name)”", role: .destructive) {
                Task {
                    try? await profileManager.remove(profileID: profile.id)
                    profilePendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { profilePendingDeletion = nil }
        } message: { _ in
            Text("New requests using this profile will fail. Existing grants are checked against the pinned profile revision and digest.")
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: HealthContextProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(BrandTypography.bodyMedium())
                    Text("Revision \(profile.revision.rawValue) · \(profile.id.uuidString.lowercased())")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(role: .destructive) {
                    profilePendingDeletion = profile
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(profile.name)")
            }

            HStack(spacing: 6) {
                policyBadge(metricScopeLabel(profile.metricScope))
                policyBadge(sourceScopeLabel(profile.dataSourceScope))
                policyBadge(profile.detailLevel == .lossless ? "Lossless" : "Summary")
                policyBadge(datePolicyLabel(profile.datePolicy))
            }
        }
        .padding(.vertical, 4)
    }

    private func policyBadge(_ text: String) -> some View {
        Text(text)
            .font(BrandTypography.caption())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accent.opacity(0.12), in: Capsule())
    }

    private func metricScopeLabel(_ scope: HealthContextMetricScope) -> String {
        switch scope {
        case .allAvailable: return "All metrics"
        case .selected(let metricIDs): return "\(metricIDs.count) metrics"
        }
    }

    private func sourceScopeLabel(_ scope: HealthContextDataSourceScope) -> String {
        switch scope {
        case .allAvailable: return "All providers"
        case .selected(let sourceIDs): return "\(sourceIDs.count) providers"
        }
    }

    private func datePolicyLabel(_ policy: HealthContextDatePolicy) -> String {
        switch policy {
        case .allHistory: return "All history"
        case .explicit: return "Fixed range"
        case .callerProvided: return "Caller range"
        case .relative: return "Relative range"
        }
    }
}
#endif
