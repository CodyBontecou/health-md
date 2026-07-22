#if os(macOS)
import SwiftUI
import AppKit

private enum InstallTab: CaseIterable, Identifiable {
    case agentPrompt
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .agentPrompt: return "Agent Prompt"
        case .manual: return "Manual"
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
    @State private var selectedInstallTab: InstallTab = .agentPrompt
    @State private var selectedSkillInstallTab: InstallTab = .agentPrompt
    @State private var isAgentPromptExpanded = false
    @State private var isSkillsPromptExpanded = false
    @State private var isInstallingSkills = false
    @State private var skillInstallMessage: String?

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
                        Text("Health.md CLI & MCP")
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
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    installCard
                    agentSkillsCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Spacing.s6) {
                    appStoreSafeCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                installCard
                agentSkillsCard
                appStoreSafeCard
            }
        }
    }

    private var installCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Install for Terminal",
                    subtitle: "Choose agent-assisted setup or copy the manual shell commands."
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

    private var agentSkillsCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Install Agent Skill",
                    subtitle: "Choose agent-assisted setup or install the user-facing CLI skill yourself."
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
                .accessibilityLabel(isAgentPromptExpanded ? "Hide full prompt" : "Show full prompt")

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
                    Label(copiedAgentPrompt ? "Copied" : "Copy Prompt", systemImage: copiedAgentPrompt ? "checkmark" : "doc.on.doc")
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
                .accessibilityLabel(isSkillsPromptExpanded ? "Hide full prompt" : "Show full prompt")

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
                    Label(copiedSkillsPrompt ? "Copied" : "Copy Prompt", systemImage: copiedSkillsPrompt ? "checkmark" : "doc.on.doc")
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
                    Label(isInstallingSkills ? "Installing…" : "Install…", systemImage: "square.and.arrow.down")
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
                title: "Manual shell command",
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
                    .foregroundStyle(skillInstallMessage.hasPrefix("Installed") ? Color.success : Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var manualInstallContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            commandBlock(
                title: "Aliases for this shell",
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

    private var appStoreSafeCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "How It Works",
                    subtitle: "App Store-safe by design."
                )

                setupStep(number: "1", title: "Mac app runs the service", detail: "Health.md listens only on localhost and owns iPhone connection state.")
                setupStep(number: "2", title: "Helpers send JSON", detail: "The sandboxed `healthmd` and `healthmd-mcp` helpers call fixed localhost routes; neither reads HealthKit directly.")
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
        if syncService.connectionState != .connected { return "Open iPhone app" }
        if vaultManager.vaultURL == nil { return "Raw mode available" }
        return "Exports ready"
    }

    private func installAgentSkills() {
        guard !isInstallingSkills else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Agent Skills Folder"
        panel.message = "Choose the folder where your coding agent reads skills. Health.md will install or update its user-facing CLI skill there."
        panel.prompt = "Install Skills"
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
            skillInstallMessage = "Installed \(installed.count) Health.md CLI skill to \(destinationURL.path): \(names)."
        } catch {
            skillInstallMessage = "Could not install skills: \(error.localizedDescription)"
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
            title: "Health.md CLI",
            summary: "Help users install the command, run exports, request raw JSON, read status output, and fix readiness issues.",
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
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled skill file \(skill.resourceFileName)."]
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
