#if os(macOS)
import SwiftUI
import AppKit

struct MacCLIView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var vaultManager: VaultManager

    @State private var copiedAlias = false
    @State private var copiedSymlink = false
    @State private var copiedAgentPrompt = false
    @State private var copiedRawExample = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    heroCard
                    quickStartGrid(width: proxy.size.width)
                    commandExamplesCard
                    agentPromptCard
                    troubleshootingCard
                }
                .padding(.horizontal, horizontalPadding(for: proxy.size.width))
                .padding(.vertical, Spacing.s8)
                .frame(maxWidth: 1_100, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(GeistMacBackdrop())
        }
        .foregroundStyle(Color.textPrimary)
        .tint(Color.accent)
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        if width < 720 { return Spacing.s4 }
        if width < 1_080 { return Spacing.s6 }
        return Spacing.s8
    }

    private var heroCard: some View {
        GeistMacCard(padding: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(alignment: .top, spacing: Spacing.s4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                            .fill(Color.accentSubtle)
                            .frame(width: 56, height: 56)
                        Image(systemName: "terminal.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accent)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Health.md CLI")
                            .font(Typography.displayLarge())
                            .foregroundStyle(Color.textPrimary)
                            .tracking(-0.9)
                            .accessibilityAddTraits(.isHeader)

                        Text("Trigger iPhone exports and request raw HealthKit JSON from terminal agents while the Mac app owns the connection, sandbox access, and localhost server.")
                            .font(Typography.body())
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 720, alignment: .leading)
                    }

                    Spacer(minLength: Spacing.s4)

                    GeistStatusPill(
                        title: syncService.connectionState == .connected ? "iPhone connected" : "Waiting for iPhone",
                        subtitle: cliReadinessSubtitle,
                        systemImage: syncService.connectionState == .connected ? "iphone" : "antenna.radiowaves.left.and.right",
                        color: syncService.connectionState == .connected ? Color.success : Color.warning
                    )
                }

                HStack(alignment: .top, spacing: Spacing.s3) {
                    infoTile(title: "Bundled path", value: bundledCLIPath, systemImage: "shippingbox")
                    infoTile(title: "Local server", value: "127.0.0.1:17645", systemImage: "network")
                    infoTile(title: "Raw mode", value: "No files written", systemImage: "curlybraces")
                }
            }
        }
    }

    @ViewBuilder
    private func quickStartGrid(width: CGFloat) -> some View {
        if width >= 960 {
            HStack(alignment: .top, spacing: Spacing.s6) {
                installCard
                appStoreSafeCard
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                installCard
                appStoreSafeCard
            }
        }
    }

    private var installCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Install for Terminal",
                    subtitle: "Create a shell alias or symlink to the CLI bundled inside this Mac app."
                )

                commandBlock(
                    title: "Alias for this shell",
                    command: aliasCommand,
                    copied: copiedAlias,
                    copyAction: {
                        copyToPasteboard(aliasCommand)
                        copiedAlias = true
                    }
                )

                commandBlock(
                    title: "Persistent symlink",
                    command: symlinkCommand,
                    copied: copiedSymlink,
                    copyAction: {
                        copyToPasteboard(symlinkCommand)
                        copiedSymlink = true
                    }
                )

                Text("If `~/.local/bin` is not on your PATH, add `export PATH=\"$HOME/.local/bin:$PATH\"` to your shell config.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appStoreSafeCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "How It Works",
                    subtitle: "App Store-safe by design."
                )

                setupStep(number: "1", title: "Mac app runs the service", detail: "Health.md listens only on localhost and owns iPhone connection state.")
                setupStep(number: "2", title: "CLI sends JSON", detail: "The `healthmd` command calls the Mac app; it does not read HealthKit directly.")
                setupStep(number: "3", title: "iPhone remains source of truth", detail: "HealthKit reads happen on your unlocked, connected iPhone.")
                setupStep(number: "4", title: "You opt into installation", detail: "The app never mutates `/usr/local/bin` or shell files without your action.")
            }
        }
    }

    private var commandExamplesCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Commands",
                    subtitle: "Run these after the Mac app is open and the iPhone app is connected."
                )

                commandRow("Check readiness", "healthmd status")
                commandRow("Export yesterday to Mac folder", "healthmd export --iphone --yesterday")
                commandRow("Export last 7 days", "healthmd export --iphone --last 7")
                commandRow("Return raw JSON without files", "healthmd export --iphone --yesterday --raw", copyAction: {
                    copyToPasteboard("healthmd export --iphone --yesterday --raw")
                    copiedRawExample = true
                }, copied: copiedRawExample)
                commandRow("Use iPhone settings exactly", "healthmd export --iphone --yesterday --use-iphone-settings")
            }
        }
    }

    private var agentPromptCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Agent Install Prompt",
                    subtitle: "Copy this into your coding agent to install and verify the CLI safely."
                ) {
                    Button {
                        copyToPasteboard(agentInstallPrompt)
                        copiedAgentPrompt = true
                    } label: {
                        Label(copiedAgentPrompt ? "Copied" : "Copy Prompt", systemImage: copiedAgentPrompt ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                }

                Text(agentInstallPrompt)
                    .font(Typography.mono())
                    .foregroundStyle(Color.textSecondary)
                    .padding(Spacing.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                            .strokeBorder(Color.borderSubtle, lineWidth: 1)
                    )
                    .textSelection(.enabled)
            }
        }
    }

    private var troubleshootingCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Troubleshooting",
                    subtitle: "What common JSON readiness states mean."
                )

                troubleshootingRow("mac_app_unreachable", "Open Health.md on Mac. The CLI talks to the running app, not directly to iPhone.")
                troubleshootingRow("iphone_not_connected", "Unlock iPhone, open Health.md, and wait for the Mac Destination connection.")
                troubleshootingRow("mac_destination_unavailable", "Choose or reselect a Mac folder, or use `--raw` when you only need JSON.")
                troubleshootingRow("can_trigger_raw_exports", "Raw JSON can work even when no Mac destination folder is selected.")
            }
        }
    }

    private func infoTile(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accent)
            Text(title)
                .font(Typography.caption())
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(Typography.monoCaption())
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private func commandBlock(title: String, command: String, copied: Bool, copyAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                Text(title)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Button {
                    copyAction()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
            }

            Text(command)
                .font(Typography.mono())
                .foregroundStyle(Color.textPrimary)
                .padding(Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .textSelection(.enabled)
        }
    }

    private func commandRow(_ title: String, _ command: String, copyAction: (() -> Void)? = nil, copied: Bool = false) -> some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(BrandTypography.bodyMedium())
                    .foregroundStyle(Color.textPrimary)
                Text(command)
                    .font(Typography.mono())
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: Spacing.s4)
            if let copyAction {
                Button {
                    copyAction()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
            }
        }
        .padding(.vertical, Spacing.s2)
    }

    private func setupStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Text(number)
                .font(Typography.caption().weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 24, height: 24)
                .background(Color.accentSubtle, in: Circle())
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(BrandTypography.bodyMedium())
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func troubleshootingRow(_ code: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(code)
                .font(Typography.mono())
                .foregroundStyle(Color.textPrimary)
            Text(detail)
                .font(Typography.caption())
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.s2)
    }

    private var bundledCLIPath: String {
        let helpersURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("healthmd")

        if FileManager.default.fileExists(atPath: helpersURL.path) {
            return helpersURL.path
        }

        return Bundle.main.url(forResource: "healthmd", withExtension: nil)?.path
            ?? "/Applications/Health.md.app/Contents/Helpers/healthmd"
    }

    private var aliasCommand: String {
        "alias healthmd=\"\(bundledCLIPath)\""
    }

    private var symlinkCommand: String {
        "mkdir -p ~/.local/bin && ln -sf \"\(bundledCLIPath)\" ~/.local/bin/healthmd"
    }

    private var agentInstallPrompt: String {
        """
        Install the Health.md CLI for my shell from the bundled Mac app. The CLI binary is at:

        \(bundledCLIPath)

        Please:
        1. Verify that file exists and runs with `--help`.
        2. Create `~/.local/bin` if needed.
        3. Create or replace a symlink at `~/.local/bin/healthmd` pointing to the bundled CLI.
        4. If `~/.local/bin` is not on PATH, tell me the exact shell config line to add, but do not edit shell config unless I explicitly approve.
        5. Run `healthmd status` or `~/.local/bin/healthmd status` and summarize the JSON readiness.

        Use bounded, non-interactive commands. Do not modify Health.md export files.
        """
    }

    private var cliReadinessSubtitle: String {
        if syncService.connectionState != .connected { return "Open iPhone app" }
        if vaultManager.vaultURL == nil { return "Raw mode available" }
        return "Exports ready"
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

// MARK: - Local CLI View Components

private struct GeistMacBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color.bgPrimary, Color.bgSecondary.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct GeistMacCard<Content: View>: View {
    var padding: CGFloat = Spacing.s6
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgPrimary, in: RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }
}

private struct GeistSectionHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var accessory: Accessory

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    init(title: String, subtitle: String? = nil) where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.accessory = EmptyView()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.s3)
            accessory
        }
    }
}

private struct GeistMacButtonStyle: ButtonStyle {
    enum Kind { case secondary }
    enum Size { case small }

    let kind: Kind
    let size: Size

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.caption())
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(configuration.isPressed ? Color.bgTertiary : Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }
}

private struct GeistStatusPill: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Typography.label())
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(Color.bgSecondary, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
    }
}
#endif
