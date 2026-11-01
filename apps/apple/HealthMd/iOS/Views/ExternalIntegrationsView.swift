import SwiftUI

struct ExternalIntegrationsView: View {
    @ObservedObject var manager: ExternalIntegrationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTroubleshootingExpanded = false
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.glassPalette) private var glassPalette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    glassContent
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(glassPalette.bg.ignoresSafeArea())
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

    /// ConnectedAppsG. Uses the same manager calls and lock checks as the cards below.
    @ViewBuilder private var glassContent: some View {
        ForEach(ConnectedAppsFeature.enabledProviders) { provider in
            GlassPanel { glassProvider(provider) }
        }
        GlassBanner(
            title: String(localized: "Private by design"),
            message: String(localized: "WHOOP data travels directly to this iPhone, and your tokens stay in Keychain. Health.md’s broker only completes secure sign-in and token refresh."),
            systemImage: "lock.shield"
        )
        Text("If data is missing, WHOOP may not have scored the day yet, a permission may be missing, or WHOOP may be rate limiting requests. Reconnect after revoked or missing access, then retry the export later.")
            .glassFont(.rowSubtitle)
            .foregroundStyle(glassPalette.muted)
    }

    private func glassProvider(_ provider: ExternalIntegrationProvider) -> some View {
        let connected = manager.isConnected(provider)
        let connecting = manager.isConnectingProvider == provider
        let disconnecting = manager.isDisconnectingProvider == provider
        let busy = manager.isConnectingProvider != nil || manager.isDisconnectingProvider != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                providerLogo(provider)
                Spacer(minLength: 8)
                connectionStatus(connected: connected)
            }
            Text(provider.summary).glassFont(.rowSubtitle).foregroundStyle(glassPalette.sec)
            if connected,
               let granted = manager.accounts[provider]?.scope,
               let missing = missingScopes(for: provider, grantedScope: granted),
               !missing.isEmpty {
                GlassBanner(
                    title: String(localized: "Permissions needed"),
                    message: String(localized: "Reconnect and approve: \(missing.joined(separator: ", "))."),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
            if connected {
                Button(role: .destructive) {
                    guard configurationProtection.performConfigurationChange({}) else { return }
                    Task {
                        await manager.disconnect(
                            provider: provider,
                            commitAllowed: { configurationProtection.performConfigurationChange({}) }
                        )
                    }
                } label: {
                    providerActionLabel(
                        title: disconnecting ? "Disconnecting…" : "Disconnect WHOOP",
                        isWorking: disconnecting
                    )
                }
                .tint(glassPalette.coral)
                .frame(minHeight: GlassMetrics.touchTarget)
                .disabled(busy)
            } else {
                Button {
                    guard configurationProtection.performConfigurationChange({}) else { return }
                    Task {
                        await manager.connect(
                            provider: provider,
                            commitAllowed: { configurationProtection.performConfigurationChange({}) }
                        )
                    }
                } label: {
                    providerActionLabel(
                        title: connecting ? "Connecting…" : "Connect WHOOP",
                        isWorking: connecting
                    )
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(busy)
            }
        }
        .padding(GlassMetrics.panelPadding)
    }

    private var intro: some View {
        Text("Connect WHOOP to include recovery, strain, sleep, and workout data alongside your Apple Health exports.")
            .font(.body)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var privacyNote: some View {
        SectionCard {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.accentSubtle))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Private by design")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    Text("WHOOP data travels directly to this iPhone, and your tokens stay in Keychain. Health.md’s broker only completes secure sign-in and token refresh.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.md)
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Provider")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            ForEach(ConnectedAppsFeature.enabledProviders) { provider in
                SectionCard {
                    providerCard(provider)
                }
            }
        }
    }

    private func providerCard(_ provider: ExternalIntegrationProvider) -> some View {
        let connected = manager.isConnected(provider)
        let connecting = manager.isConnectingProvider == provider
        let disconnecting = manager.isDisconnectingProvider == provider
        let actionDisabled = connecting
            || disconnecting
            || manager.isConnectingProvider != nil
            || manager.isDisconnectingProvider != nil

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                providerLogo(provider)

                Spacer(minLength: Spacing.sm)

                connectionStatus(connected: connected)
            }

            Text(provider.summary)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if connected,
               let granted = manager.accounts[provider]?.scope,
               let missing = missingScopes(for: provider, grantedScope: granted),
               !missing.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("Permissions needed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warning)
                    Text("Reconnect and approve: \(missing.joined(separator: ", ")).")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            }

            Divider()

            if connected {
                Button(role: .destructive) {
                    guard configurationProtection.performConfigurationChange({}) else { return }
                    Task {
                        await manager.disconnect(
                            provider: provider,
                            commitAllowed: { configurationProtection.performConfigurationChange({}) }
                        )
                    }
                } label: {
                    providerActionLabel(
                        title: disconnecting ? "Disconnecting…" : "Disconnect WHOOP",
                        isWorking: disconnecting
                    )
                }
                .buttonStyle(.bordered)
                .tint(Color.error)
                .controlSize(.large)
                .disabled(actionDisabled)
            } else {
                Button {
                    guard configurationProtection.performConfigurationChange({}) else { return }
                    Task {
                        await manager.connect(
                            provider: provider,
                            commitAllowed: { configurationProtection.performConfigurationChange({}) }
                        )
                    }
                } label: {
                    providerActionLabel(
                        title: connecting ? "Connecting…" : "Connect WHOOP",
                        isWorking: connecting
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .controlSize(.large)
                .disabled(actionDisabled)
            }
        }
        .padding(Spacing.md)
    }

    @ViewBuilder
    private func providerLogo(_ provider: ExternalIntegrationProvider) -> some View {
        if provider == .whoop {
            Image("WHOOPWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 24, alignment: .leading)
                .accessibilityLabel("WHOOP")
        } else {
            Label(provider.displayName, systemImage: provider.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func connectionStatus(connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.success : Color.textMuted)
                .frame(width: 6, height: 6)
            Text(LocalizedStringKey(connected ? "Connected" : "Not connected"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(connected ? Color.success : Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(connected ? Color.success.opacity(0.12) : Color.bgSecondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LocalizedStringKey(connected ? "Connected" : "Not connected"))
    }

    private func providerActionLabel(title: LocalizedStringKey, isWorking: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var troubleshootingSection: some View {
        SectionCard {
            DisclosureGroup(isExpanded: $isTroubleshootingExpanded) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("If data is missing, WHOOP may not have scored the day yet, a permission may be missing, or WHOOP may be rate limiting requests. Reconnect after revoked or missing access, then retry the export later.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text("Disconnecting also revokes Health.md’s WHOOP access before credentials are removed from this iPhone.")
                        .font(.caption)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.sm)
            } label: {
                Label("Help with WHOOP", systemImage: "questionmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.textSecondary)
            .padding(Spacing.md)
        }
    }

    private func missingScopes(for provider: ExternalIntegrationProvider, grantedScope: String) -> [String]? {
        let granted = Set(grantedScope.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        guard !granted.isEmpty else { return nil }
        return provider.defaultScopes.filter { $0 != "offline" && !granted.contains($0) }
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
            messageLineLimit: nil,
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
