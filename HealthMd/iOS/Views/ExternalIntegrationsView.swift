import SwiftUI

struct ExternalIntegrationsView: View {
    @ObservedObject var manager: ExternalIntegrationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    privacyNote
                    providersSection
                    troubleshootingSection
                    if let status = manager.statusMessage {
                        statusCard(status)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Connected Apps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HealthMdPageHeader(
            title: "Connected Apps",
            subtitle: "Export provider-native data into sidecar JSON files in your Health.md folder."
        ) {
            Text(manager.connectedProviderCount == 0 ? "None" : "\(manager.connectedProviderCount) Connected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(manager.connectedProviderCount == 0 ? Color.textMuted : Color.success)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(manager.connectedProviderCount == 0 ? Color.bgSecondary : Color.success.opacity(0.12))
                )
        }
    }

    private var privacyNote: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Minimal OAuth broker", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("Health.md uses a small broker only to exchange OAuth codes and refresh tokens with providers that require a client secret. Provider tokens are stored in Keychain on this device. Health data is fetched directly from each provider to your iPhone and exported as sidecar records for local, Mac, or API exports.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Providers")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            SectionCard {
                ForEach(Array(ConnectedAppsFeature.enabledProviders.enumerated()), id: \.element.id) { index, provider in
                    providerRow(provider)
                    if index < ConnectedAppsFeature.enabledProviders.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
        }
    }

    private func providerRow(_ provider: ExternalIntegrationProvider) -> some View {
        let connected = manager.isConnected(provider)
        let connecting = manager.isConnectingProvider == provider
        let disconnecting = manager.isDisconnectingProvider == provider

        return HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: provider.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(connected ? Color.accent : Color.textMuted)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(connected ? Color.accentSubtle : Color.bgSecondary)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.sm) {
                    Text(provider.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(connected ? "Connected" : "Not Connected")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(connected ? Color.success : Color.textMuted)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(connected ? Color.success.opacity(0.12) : Color.bgSecondary))
                }

                Text(provider.summary)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if connected,
                   let granted = manager.accounts[provider]?.scope,
                   let missing = missingScopes(for: provider, grantedScope: granted),
                   !missing.isEmpty {
                    Text("Missing permissions: \(missing.joined(separator: ", ")). Reconnect to approve them.")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Spacing.sm)

            Button {
                if connected {
                    Task { await manager.disconnect(provider: provider) }
                } else {
                    Task { await manager.connect(provider: provider) }
                }
            } label: {
                Text(connecting ? "Connecting…" : (disconnecting ? "Disconnecting…" : (connected ? "Disconnect" : "Connect")))
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(connected ? Color.textMuted : Color.accent)
            .disabled(
                connecting
                    || disconnecting
                    || manager.isConnectingProvider != nil
                    || manager.isDisconnectingProvider != nil
            )
        }
        .padding(Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.displayName), \(connected ? "connected" : "not connected")")
    }

    private var troubleshootingSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("WHOOP troubleshooting", systemImage: "questionmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("Missing data can mean the requested day has no WHOOP score yet, a permission was not approved, or WHOOP is rate limiting requests. Reconnect after revoked or missing access. Rate-limited exports keep an error in the sidecar so you can retry later.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Disconnect revokes Health.md in WHOOP before removing the on-device Keychain credentials.")
                    .font(.caption)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(Spacing.md)
        }
    }

    private func missingScopes(for provider: ExternalIntegrationProvider, grantedScope: String) -> [String]? {
        let granted = Set(grantedScope.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        guard !granted.isEmpty else { return nil }
        return provider.defaultScopes.filter { !granted.contains($0) }
    }

    private func statusCard(_ status: String) -> some View {
        SectionCard {
            Text(status)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
