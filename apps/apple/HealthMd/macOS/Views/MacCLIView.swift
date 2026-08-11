#if os(macOS)
import SwiftUI
import AppKit

private enum InstallTab: CaseIterable, Identifiable {
    case agentPrompt
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .agentPrompt: return String(localized: "Agent Prompt")
        case .manual: return String(localized: "Manual")
        }
    }

    var systemImage: String {
        switch self {
        case .agentPrompt: return "sparkles"
        case .manual: return "terminal"
        }
    }
}

struct MacCLIView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var vaultManager: VaultManager

    @State private var copiedAlias = false
    @State private var copiedSymlink = false
    @State private var copiedAgentPrompt = false
    @State private var copiedRawExample = false
    @State private var copiedSkillsPrompt = false
    @State private var copiedSkillManualCommand = false
    @State private var copiedCodexConfig = false
    @State private var copiedClaudeConfig = false
    @State private var selectedInstallTab: InstallTab = .agentPrompt
    @State private var selectedSkillInstallTab: InstallTab = .agentPrompt
    @State private var isAgentPromptExpanded = false
    @State private var isSkillsPromptExpanded = false
    @State private var isInstallingSkills = false
    @State private var skillInstallMessage: String?
    @State private var skillInstallSucceeded = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    heroCard
                    quickStartGrid(width: proxy.size.width)
                    commandExamplesCard
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
                    Image(systemName: "terminal.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Health.md CLI & MCP")
                            .font(Typography.displayLarge())
                            .foregroundStyle(Color.textPrimary)
                            .tracking(-0.9)
                            .accessibilityAddTraits(.isHeader)

                        Text("Connect Codex or Claude to analyze health context, render native charts, and run approved iPhone exports while Health.md owns the connection, sandbox access, and localhost server.")
                            .font(Typography.body())
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 720, alignment: .leading)
                    }

                    Spacer(minLength: Spacing.s4)

                    GeistStatusPill(
                        title: syncService.connectionState == .connected
                            ? String(localized: "iPhone connected")
                            : String(localized: "Waiting for iPhone"),
                        subtitle: cliReadinessSubtitle,
                        systemImage: syncService.connectionState == .connected ? "iphone" : "antenna.radiowaves.left.and.right",
                        color: syncService.connectionState == .connected ? Color.success : Color.warning
                    )
                }

                HStack(alignment: .top, spacing: Spacing.s3) {
                    infoTile(title: String(localized: "Bundled path"), value: bundledCLIPath, systemImage: "shippingbox")
                    infoTile(title: String(localized: "Local server"), value: "127.0.0.1:17645", systemImage: "network")
                    infoTile(title: String(localized: "Raw mode"), value: String(localized: "No files written"), systemImage: "curlybraces")
                }
            }
        }
    }

    @ViewBuilder
    private func quickStartGrid(width: CGFloat) -> some View {
        if width >= 960 {
            HStack(alignment: .top, spacing: Spacing.s6) {
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    installCard
                    agentSkillsCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Spacing.s6) {
                    mcpConfigurationCard
                    appStoreSafeCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                installCard
                mcpConfigurationCard
                agentSkillsCard
                appStoreSafeCard
            }
        }
    }

    private var installCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: String(localized: "Install for Terminal"),
                    subtitle: String(localized: "Choose agent-assisted setup or copy the manual shell commands.")
                )

                installTabBar(selection: $selectedInstallTab)

                switch selectedInstallTab {
                case .agentPrompt:
                    agentPromptInstallContent
                case .manual:
                    manualInstallContent
                }
            }
        }
    }

    private var mcpConfigurationCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: String(localized: "Connect Codex or Claude"),
                    subtitle: String(localized: "Add the local stdio server, restart the host, then call healthmd_doctor.")
                )

                commandBlock(
                    title: String(localized: "Codex · ~/.codex/config.toml"),
                    command: codexMCPConfig,
                    copied: copiedCodexConfig,
                    copyAction: {
                        copyToPasteboard(codexMCPConfig)
                        copiedCodexConfig = true
                    }
                )

                commandBlock(
                    title: String(localized: "Claude Desktop or trusted .mcp.json"),
                    command: claudeMCPConfig,
                    copied: copiedClaudeConfig,
                    copyAction: {
                        copyToPasteboard(claudeMCPConfig)
                        copiedClaudeConfig = true
                    }
                )

                Text("Compatible native hosts render the interactive MCP App inline. Other Codex and Claude surfaces keep exact JSON and receive a PNG metric-chart fallback. Fresh acquisition and export mutations require approval.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var agentSkillsCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: String(localized: "Install Agent Skill"),
                    subtitle: String(localized: "Choose agent-assisted setup or install the user-facing CLI skill yourself.")
                )

                installTabBar(selection: $selectedSkillInstallTab)

                switch selectedSkillInstallTab {
                case .agentPrompt:
                    agentSkillPromptInstallContent
                case .manual:
                    manualSkillInstallContent
                }
            }
        }
    }

    private func installTabBar(selection: Binding<InstallTab>) -> some View {
        HStack(spacing: Spacing.s2) {
            ForEach(InstallTab.allCases) { tab in
                Button {
                    selection.wrappedValue = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(InstallTabButtonStyle(isSelected: selection.wrappedValue == tab))
            }
        }
        .padding(Spacing.s1)
        .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private var agentPromptInstallContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .center, spacing: Spacing.s3) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isAgentPromptExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isAgentPromptExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.caption().weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isAgentPromptExpanded
                        ? String(localized: "Hide full prompt")
                        : String(localized: "Show full prompt")
                )

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Agent install prompt")
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)
                    Text("Copy the prompt now, or expand to preview it first.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }

                Spacer(minLength: Spacing.s3)

                Button {
                    copyToPasteboard(agentInstallPrompt)
                    copiedAgentPrompt = true
                } label: {
                    Label(
                        copiedAgentPrompt ? String(localized: "Copied") : String(localized: "Copy Prompt"),
                        systemImage: copiedAgentPrompt ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
            }
            .padding(Spacing.s3)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )

            if isAgentPromptExpanded {
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var agentSkillPromptInstallContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .center, spacing: Spacing.s3) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isSkillsPromptExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isSkillsPromptExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.caption().weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isSkillsPromptExpanded
                        ? String(localized: "Hide full prompt")
                        : String(localized: "Show full prompt")
                )

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Agent skill install prompt")
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)
                    Text("Copy the prompt now, or expand to preview it first.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }

                Spacer(minLength: Spacing.s3)

                Button {
                    copyToPasteboard(agentSkillsInstallPrompt)
                    copiedSkillsPrompt = true
                } label: {
                    Label(
                        copiedSkillsPrompt ? String(localized: "Copied") : String(localized: "Copy Prompt"),
                        systemImage: copiedSkillsPrompt ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
            }
            .padding(Spacing.s3)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )

            if isSkillsPromptExpanded {
                Text(agentSkillsInstallPrompt)
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var manualSkillInstallContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                ForEach(HealthMdAgentSkillBundle.skills) { skill in
                    HStack(alignment: .top, spacing: Spacing.s3) {
                        Image(systemName: skill.systemImage)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text(skill.title)
                                .font(BrandTypography.bodyMedium())
                                .foregroundStyle(Color.textPrimary)
                            Text(skill.summary)
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(Spacing.s3)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )

            HStack(alignment: .center, spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Install with file picker")
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)
                    Text("Choose your agent’s skills directory. Health.md creates `healthmd-cli/SKILL.md` there.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.s3)

                Button {
                    installAgentSkills()
                } label: {
                    Label(
                        isInstallingSkills ? String(localized: "Installing…") : String(localized: "Install…"),
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                .disabled(isInstallingSkills)
            }
            .padding(Spacing.s3)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )

            commandBlock(
                title: String(localized: "Manual shell command"),
                command: skillManualInstallCommand,
                copied: copiedSkillManualCommand,
                copyAction: {
                    copyToPasteboard(skillManualInstallCommand)
                    copiedSkillManualCommand = true
                }
            )

            Text("Edit `SKILLS_DIR` to match the folder your agent reads. The app installer replaces the Health.md skill folder; the shell command overwrites only `SKILL.md`.")
                .font(Typography.caption())
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let skillInstallMessage {
                Text(skillInstallMessage)
                    .font(Typography.caption())
                    .foregroundStyle(skillInstallSucceeded ? Color.success : Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var manualInstallContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            commandBlock(
                title: String(localized: "Aliases for this shell"),
                command: aliasCommand,
                copied: copiedAlias,
                copyAction: {
                    copyToPasteboard(aliasCommand)
                    copiedAlias = true
                }
            )

            commandBlock(
                title: String(localized: "Persistent symlink"),
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

    private var appStoreSafeCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: String(localized: "How It Works"),
                    subtitle: String(localized: "App Store-safe by design.")
                )

                setupStep(number: "1", title: String(localized: "Mac app runs the service"), detail: String(localized: "Health.md listens only on localhost and owns iPhone connection state."))
                setupStep(number: "2", title: String(localized: "Helpers send JSON"), detail: String(localized: "The sandboxed `healthmd` and `healthmd-mcp` helpers call fixed localhost routes; neither reads HealthKit directly."))
                setupStep(number: "3", title: String(localized: "iPhone remains source of truth"), detail: String(localized: "HealthKit reads happen on your unlocked, connected iPhone."))
                setupStep(number: "4", title: String(localized: "You opt into installation"), detail: String(localized: "The app never mutates `/usr/local/bin` or shell files without your action."))
            }
        }
    }

    private var commandExamplesCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: String(localized: "Commands"),
                    subtitle: String(localized: "Run these after the Mac app is open and the iPhone app is connected.")
                )

                commandRow(String(localized: "Check connection readiness"), "healthmd status")
                commandRow(String(localized: "Check CLI and iPhone readiness"), "healthmd doctor")
                commandRow(String(localized: "List queryable Sleep metrics"), "healthmd metrics list --category Sleep")
                commandRow(String(localized: "Extract canonical Sleep data without changing iPhone settings"), "healthmd extract --category Sleep --yesterday")
                commandRow(String(localized: "Run a derived Sleep metric query"), "healthmd query --category Sleep --yesterday")
                commandRow(String(localized: "Inspect the first four hours of recent sleep"), "healthmd sleep sessions --last-nights 14 --window first:4h")
                commandRow(String(localized: "Align runs with preceding and following sleep"), "healthmd training align --last 14 --workout running --sleep-window first:4h")
                commandRow(String(localized: "List recent workouts"), "healthmd workouts --last 14")
                commandRow(String(localized: "Inspect Sleep coverage"), "healthmd coverage --category Sleep --last 14")
                commandRow(String(localized: "Export yesterday to Mac folder"), "healthmd export --iphone --yesterday")
                commandRow(String(localized: "Export last 7 days"), "healthmd export --iphone --last 7")
                commandRow(String(localized: "Export selected Sleep summaries"), "healthmd export --iphone --last 7 --category Sleep --detail summary")
                commandRow(String(localized: "Return raw JSON without files"), "healthmd export --iphone --yesterday --raw", copyAction: {
                    copyToPasteboard("healthmd export --iphone --yesterday --raw")
                    copiedRawExample = true
                }, copied: copiedRawExample)
                commandRow(String(localized: "Use iPhone settings exactly"), "healthmd export --iphone --yesterday --use-iphone-settings")
            }
        }
    }

    private var troubleshootingCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: String(localized: "Troubleshooting"),
                    subtitle: String(localized: "What common JSON readiness states mean.")
                )

                troubleshootingRow("mac_app_unreachable", String(localized: "Open Health.md on Mac. The CLI talks to the running app, not directly to iPhone."))
                troubleshootingRow("iphone_not_connected", String(localized: "Unlock iPhone, open Health.md, and wait for the Mac Destination connection."))
                troubleshootingRow("mac_destination_unavailable", String(localized: "Choose or reselect a Mac folder, or use `--raw` when you only need JSON."))
                troubleshootingRow("can_trigger_raw_exports", String(localized: "Raw JSON can work even when no Mac destination folder is selected."))
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
                    Label(copied ? String(localized: "Copied") : String(localized: "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
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
                    Label(copied ? String(localized: "Copied") : String(localized: "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
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

    private var bundledMCPPath: String {
        URL(fileURLWithPath: bundledCLIPath)
            .deletingLastPathComponent()
            .appendingPathComponent("healthmd-mcp")
            .path
    }

    private var aliasCommand: String {
        """
        alias healthmd=\"\(bundledCLIPath)\"
        alias healthmd-mcp=\"\(bundledMCPPath)\"
        """
    }

    private var symlinkCommand: String {
        """
        mkdir -p ~/.local/bin
        ln -sf \"\(bundledCLIPath)\" ~/.local/bin/healthmd
        ln -sf \"\(bundledMCPPath)\" ~/.local/bin/healthmd-mcp
        """
    }

    private var codexMCPConfig: String {
        """
        [mcp_servers.healthmd]
        command = \(encodedMCPPath)
        args = []
        tool_timeout_sec = 1200
        default_tools_approval_mode = "prompt"
        """
    }

    private var claudeMCPConfig: String {
        let configuration: [String: Any] = [
            "mcpServers": [
                "healthmd": [
                    "command": bundledMCPPath,
                    "args": []
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private var encodedMCPPath: String {
        guard let data = try? JSONEncoder().encode(bundledMCPPath) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }

    private var bundledSkillsPath: String {
        HealthMdAgentSkillBundle.bundledResourceDirectoryURL?.path
            ?? "/Applications/Health.md.app/Contents/Resources"
    }

    private var bundledSkillFilePath: String {
        HealthMdAgentSkillBundle.skills.first.flatMap { HealthMdAgentSkillBundle.bundledFileURL(for: $0)?.path }
            ?? "/Applications/Health.md.app/Contents/Resources/healthmd-cli.skill.md"
    }

    private var skillManualInstallCommand: String {
        """
        SKILLS_DIR="$HOME/.agents/skills"
        mkdir -p "$SKILLS_DIR/healthmd-cli" && cp "\(bundledSkillFilePath)" "$SKILLS_DIR/healthmd-cli/SKILL.md"
        """
    }

    private var agentSkillsInstallPrompt: String {
        let skillList = HealthMdAgentSkillBundle.skills.map { "- \($0.directoryName): copy `\($0.resourceFileName)` to `\($0.directoryName)/SKILL.md`" }.joined(separator: "\n")
        return """
        Install the Health.md CLI agent skill from the bundled Mac app. The bundled skill file is in:

        \(bundledSkillsPath)

        Skill:
        \(skillList)

        Please:
        1. Verify the bundled `.skill.md` file exists.
        2. Ask me which agent skills directory to use if it is not obvious. Common choices include a project `.agents/skills` folder or a user-level skills folder supported by my agent.
        3. Create the destination skill folder and copy the bundled `.skill.md` file into it as `SKILL.md`.
        4. Replace an existing Health.md CLI skill folder with the same name only after confirming the destination path.
        5. Report the installed skill paths.

        Keep this agent-agnostic: do not assume a specific assistant product unless I name one.
        """
    }

    private var agentInstallPrompt: String {
        """
        Install the Health.md CLI and stdio MCP helper for my shell from the bundled Mac app. The signed sandboxed binaries are at:

        \(bundledCLIPath)
        \(bundledMCPPath)

        Please:
        1. Verify both files exist; run the CLI with `--help` (do not start the MCP stdio loop interactively).
        2. Create `~/.local/bin` if needed.
        3. Create or replace symlinks at `~/.local/bin/healthmd` and `~/.local/bin/healthmd-mcp` pointing to the bundled helpers.
        4. If `~/.local/bin` is not on PATH, tell me the exact shell config line to add, but do not edit shell config unless I explicitly approve.
        5. Run `healthmd status` or `~/.local/bin/healthmd status` and summarize the JSON readiness.

        Use bounded, non-interactive commands. Do not modify Health.md export files.
        """
    }

    private var cliReadinessSubtitle: String {
        if syncService.connectionState != .connected { return String(localized: "Open iPhone app") }
        if vaultManager.vaultURL == nil { return String(localized: "Raw mode available") }
        return String(localized: "Exports ready")
    }

    private func installAgentSkills() {
        guard !isInstallingSkills else { return }

        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Agent Skills Folder")
        panel.message = String(localized: "Choose the folder where your coding agent reads skills. Health.md will install or update its user-facing CLI skill there.")
        panel.prompt = String(localized: "Install Skills")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isInstallingSkills = true
        defer { isInstallingSkills = false }

        let didAccess = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let installed = try HealthMdAgentSkillBundle.install(to: destinationURL)
            let names = installed.map { $0.lastPathComponent }.joined(separator: ", ")
            skillInstallSucceeded = true
            skillInstallMessage = String(localized: "Installed \(installed.count) Health.md CLI skills to \(destinationURL.path): \(names).")
        } catch {
            skillInstallSucceeded = false
            skillInstallMessage = String(localized: "Could not install skills: \(error.localizedDescription)")
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct HealthMdAgentSkill: Identifiable {
    let directoryName: String
    let title: String
    let summary: String
    let systemImage: String

    var id: String { directoryName }
    var resourceName: String { "\(directoryName).skill" }
    var resourceFileName: String { "\(resourceName).md" }
}

private enum HealthMdAgentSkillBundle {
    static let skills: [HealthMdAgentSkill] = [
        HealthMdAgentSkill(
            directoryName: "healthmd-cli",
            title: String(localized: "Health.md CLI"),
            summary: String(localized: "Help users install the command, extract selected canonical data, run exports, read status output, and fix readiness issues."),
            systemImage: "terminal"
        )
    ]

    static var bundledResourceDirectoryURL: URL? {
        Bundle.main.resourceURL
    }

    static func bundledFileURL(for skill: HealthMdAgentSkill) -> URL? {
        if let url = Bundle.main.url(forResource: skill.resourceName, withExtension: "md") {
            return url
        }

        let nestedCandidate = Bundle.main.resourceURL?
            .appendingPathComponent("AgentSkills", isDirectory: true)
            .appendingPathComponent(skill.resourceFileName)
        if let nestedCandidate, FileManager.default.fileExists(atPath: nestedCandidate.path) {
            return nestedCandidate
        }

        return nil
    }

    static func install(to destinationURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        return try skills.map { skill in
            guard let sourceSkillFileURL = bundledFileURL(for: skill) else {
                throw NSError(
                    domain: "HealthMdAgentSkillBundle",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "Missing bundled skill file \(skill.resourceFileName).")
                    ]
                )
            }

            let targetURL = destinationURL.appendingPathComponent(skill.directoryName, isDirectory: true)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceSkillFileURL, to: targetURL.appendingPathComponent("SKILL.md"))
            return targetURL
        }
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

private struct InstallTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.caption().weight(.semibold))
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(
                isSelected ? Color.bgPrimary : (configuration.isPressed ? Color.bgTertiary : Color.clear),
                in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isSelected ? Color.borderSubtle : Color.clear, lineWidth: 1)
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
