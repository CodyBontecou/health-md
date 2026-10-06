import SwiftUI

struct ExternalIntegrationsView: View {
    @ObservedObject var manager: ExternalIntegrationManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    providersSection
                    privacyNote
                    troubleshootingSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Connected Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasBottomStatus {
                VStack(spacing: Spacing.s2) {
                    ConfigurationProtectionToast(configurationProtection: configurationProtection)
                    if let status = manager.connectionStatus {
                        connectionStatusBanner(status)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)
                .padding(.bottom, Spacing.s2)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : AnimationTimings.standard, value: hasBottomStatus)
        .task(id: manager.connectionStatus?.id) {
            guard let status = manager.connectionStatus else { return }
            UIAccessibility.post(notification: .announcement, argument: status.message)
            // Progress stays until the operation completes. Errors stay until
            // dismissed/retried, so there is time to read actionable guidance.
            guard status.kind != .progress, status.kind != .error, !TestMode.isUITesting else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            manager.dismissConnectionStatus(id: status.id)
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil {
                dismiss()
            }
        }
    }

    private var header: some View {
        Text("Export provider-native data into sidecar JSON files in your Health.md folder.")
            .font(Typography.body())
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var privacyNote: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Minimal OAuth broker", systemImage: "lock.shield.fill")
                    .font(Typography.headline())
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.textPrimary)
                Text("Health.md uses a small broker only to exchange OAuth codes and refresh tokens with providers that require a client secret. Provider tokens are stored in Keychain on this device. Health data is fetched directly from each provider to your iPhone and exported as sidecar records for local, Mac, or API exports.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Providers")
                .font(Typography.headline())
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(ConnectedAppsFeature.enabledProviders) { provider in
                SectionCard {
                    providerRow(provider)
                }
            }
        }
    }

    private func providerRow(_ provider: ExternalIntegrationProvider) -> some View {
        let connected = manager.isConnected(provider)
        let connecting = manager.isConnectingProvider == provider
        let disconnecting = manager.isDisconnectingProvider == provider

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: provider.iconName)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) {
                        providerLabels(provider, connected: connected)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        providerLabels(provider, connected: connected)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(provider.summary)
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if connected,
               let granted = manager.accounts[provider]?.scope,
               let missing = missingScopes(for: provider, grantedScope: granted),
               !missing.isEmpty {
                Text("Missing permissions: \(missing.joined(separator: ", ")). Reconnect to approve them.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                guard configurationProtection.performConfigurationChange({}) else { return }
                if connected {
                    Task {
                        await manager.disconnect(
                            provider: provider,
                            commitAllowed: { configurationProtection.performConfigurationChange({}) }
                        )
                    }
                } else {
                    Task {
                        await manager.connect(
                            provider: provider,
                            commitAllowed: { configurationProtection.performConfigurationChange({}) }
                        )
                    }
                }
            } label: {
                Text(connecting ? "Connecting…" : (disconnecting ? "Disconnecting…" : (connected ? "Disconnect" : "Connect")))
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.bgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(connected ? Color.textSecondary : Color.accent)
            .disabled(
                connecting
                    || disconnecting
                    || manager.isConnectingProvider != nil
                    || manager.isDisconnectingProvider != nil
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func providerLabels(_ provider: ExternalIntegrationProvider, connected: Bool) -> some View {
        Text(provider.displayName)
            .font(Typography.headline())
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

        Text(connected ? "Connected" : "Not Connected")
            .font(Typography.label())
            .foregroundStyle(connected ? Color.successText : Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(connected ? Color.success.opacity(0.12) : Color.geistGray100))
    }

    private var troubleshootingSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("WHOOP troubleshooting", systemImage: "questionmark.circle.fill")
                    .font(Typography.headline())
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.textPrimary)
                Text("Missing data can mean the requested day has no WHOOP score yet, a permission was not approved, or WHOOP is rate limiting requests. Reconnect after revoked or missing access. Rate-limited exports keep an error in the sidecar so you can retry later.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Disconnect revokes Health.md in WHOOP before removing the on-device Keychain credentials.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func missingScopes(for provider: ExternalIntegrationProvider, grantedScope: String) -> [String]? {
        let granted = Set(grantedScope.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        guard !granted.isEmpty else { return nil }
        return provider.defaultScopes.filter { !granted.contains($0) }
    }

    private var hasBottomStatus: Bool {
        manager.connectionStatus != nil || configurationProtection.blockedChangeToastID != nil
    }

    private func connectionStatusBanner(_ status: ExternalIntegrationConnectionStatus) -> some View {
        let title: String
        let icon: String
        let tint: Color
        switch status.kind {
        case .progress:
            title = String(localized: "Connection in progress")
            icon = "link"
            tint = .accent
        case .success:
            title = String(localized: "Connection updated")
            icon = "checkmark.circle.fill"
            tint = .success
        case .warning:
            title = String(localized: "Connection needs attention")
            icon = "exclamationmark.circle.fill"
            tint = .warning
        case .error:
            title = String(localized: "Connection failed")
            icon = "exclamationmark.triangle.fill"
            tint = .error
        }
        return ExportActivityBanner(
            title: title,
            systemImage: icon,
            tint: tint,
            message: status.message,
            progress: nil,
            showsIndeterminateProgress: status.kind == .progress,
            progressAccessibilityLabel: String(localized: "Connection progress"),
            details: [],
            trailingText: nil,
            accessibilityIdentifier: AccessibilityID.Status.connectionStatusBanner,
            onDismiss: status.kind == .progress ? nil : { manager.dismissConnectionStatus(id: status.id) }
        )
    }
}
