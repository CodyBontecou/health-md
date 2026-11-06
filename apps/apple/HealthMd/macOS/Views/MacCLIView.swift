#if os(macOS)
import SwiftUI
import AppKit

struct MacCLIView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var controlServer: HealthMdControlServer
    @EnvironmentObject var encryptedHealthContextManager: MacEncryptedHealthContextManager

    @State private var isInstallingSkills = false
    @State private var skillInstallMessage: String?
    @State private var skillInstallSucceeded = false
    @State private var copiedSkillInstallPrompt = false
    @State private var retentionBoundary = Date()
    @State private var showRetentionPicker = false
    @State private var showEncryptedContextDeleteConfirmation = false
    @State private var showRetentionConfirmation = false

    /// MacCLIG: Status, Agent skill and Encrypted query context. The setup reference (terminal
    /// install, host configuration, commands, troubleshooting) opens from Help ▸ CLI & MCP Reference.
    var body: some View {
        MacGlassPage {
            MacGlassPageHeader(
                title: String(localized: "CLI & MCP"),
                subtitle: String(localized: "Connect Codex or Claude to analyze health context, render charts, and run approved iPhone exports. Health.md owns the connection, sandbox access and localhost server.")
            )
            statusSection
            agentSkillSection
            encryptedContextSection
        }
        .geistDialog(
            isPresented: $showEncryptedContextDeleteConfirmation,
            title: Text("Delete All Encrypted Query Context?"),
            message: Text("This removes every compact context day and its dedicated Keychain key. Exported files and Apple Health remain unchanged."),
            actions: [
                .cancel(),
                .destructive("Delete All") {
                    Task { await encryptedHealthContextManager.deleteAll() }
                }
            ]
        )
        .geistDialog(
            isPresented: $showRetentionConfirmation,
            title: Text("Delete Context Before \(retentionOwnerDate)?"),
            message: Text("Every encrypted owner day earlier than this date will be permanently removed. The boundary date and newer days remain."),
            actions: [
                .cancel(),
                .destructive("Delete Older Days") {
                    let boundary = retentionOwnerDate
                    Task { await encryptedHealthContextManager.delete(before: boundary) }
                }
            ]
        )
    }

    // MARK: - MacCLIG sections

    private var statusSection: some View {
        MacGlassSection(title: String(localized: "Status")) {
            MacGlassRow(
                String(localized: "healthmd CLI"),
                value: isBundledCLIPresent
                    ? String(localized: "Installed · \(appVersion)")
                    : String(localized: "Not found in this app"),
                tone: isBundledCLIPresent ? .ok : .warning
            )
            MacGlassDivider()
            MacGlassRow(
                String(localized: "MCP server"),
                value: controlServer.isRunning
                    ? String(localized: "Running on localhost")
                    : String(localized: "Not running"),
                tone: controlServer.isRunning ? .ok : .warning
            )
            MacGlassDivider()
            MacGlassRow(
                String(localized: "Paired iPhone"),
                value: displayPairedIPhone ?? String(localized: "Not connected"),
                tone: displayPairedIPhone != nil ? .muted : .warning
            )
        }
    }

    private var agentSkillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent skill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.glassAdaptive(\.muted))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose your agent’s skills directory. Health.md creates `healthmd-cli/SKILL.md` there.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Color.glassAdaptive(\.text))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(isInstallingSkills ? String(localized: "Installing…") : String(localized: "Install with file picker")) {
                        installAgentSkills()
                    }
                    .buttonStyle(MacGlassCapsuleButtonStyle(prominent: true))
                    .disabled(isInstallingSkills)

                    Button(copiedSkillInstallPrompt ? String(localized: "Copied") : String(localized: "Copy install prompt")) {
                        copyToPasteboard(agentSkillsInstallPrompt)
                        copiedSkillInstallPrompt = true
                    }
                    .buttonStyle(MacGlassCapsuleButtonStyle())
                }

                if let skillInstallMessage {
                    Text(skillInstallMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(skillInstallSucceeded ? Color.glassAdaptive(\.ok) : Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 16)
        }
    }

    private var encryptedContextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            MacGlassSection(title: String(localized: "Encrypted query context")) {
                if displayContextStatusLoaded {
                    MacGlassRow(
                        String(localized: "Encrypted context days"),
                        value: "\(displayContextDayCount)"
                    )
                    if let earliest = displayContextEarliestOwnerDate,
                       let latest = displayContextLatestOwnerDate {
                        MacGlassDivider()
                        MacGlassRow(
                            String(localized: "Owner-date range"),
                            value: earliest == latest ? earliest : "\(earliest) – \(latest)",
                            monospaced: true
                        )
                    }
                    MacGlassDivider()
                    // MacCLIG: each delete row shows "—" when there is nothing to delete.
                    MacGlassRow(title: String(localized: "Delete context before…")) {
                        if hasDeletableContext {
                            Button(String(localized: "Choose date")) {
                                showRetentionPicker = true
                            }
                            .buttonStyle(MacGlassRowButtonStyle(tone: .muted))
                            .disabled(encryptedHealthContextManager.isWorking)
                            .popover(isPresented: $showRetentionPicker, arrowEdge: .bottom) {
                                retentionPicker
                            }
                        } else {
                            MacGlassValue("—")
                                .accessibilityLabel(String(localized: "Nothing to delete"))
                        }
                    }
                    MacGlassDivider()
                    MacGlassRow(title: String(localized: "Delete all encrypted context")) {
                        if hasDeletableContext {
                            Button(String(localized: "Delete…")) {
                                showEncryptedContextDeleteConfirmation = true
                            }
                            .buttonStyle(MacGlassRowButtonStyle(tone: .coral))
                            .disabled(encryptedHealthContextManager.isWorking)
                        } else {
                            MacGlassValue("—", tone: .coral)
                                .accessibilityLabel(String(localized: "Nothing to delete"))
                        }
                    }
                } else {
                    MacGlassRow(title: String(localized: "Encrypted context days")) {
                        Button(String(localized: "Load Encrypted Context Status…")) {
                            Task { await encryptedHealthContextManager.refresh() }
                        }
                        .buttonStyle(MacGlassRowButtonStyle())
                        .disabled(encryptedHealthContextManager.isWorking)
                    }
                }
            }

            if let error = encryptedHealthContextManager.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.error)
                    .padding(.horizontal, 4)
            }

            MacGlassFootnote(text: displayContextStatusLoaded
                ? String(localized: "This Keychain-encrypted store is independent from exported files. Retention is never automatic; deleting it does not change Apple Health on iPhone.")
                : String(localized: "Context status is not loaded automatically, so ordinary Mac app use does not access Keychain."))
        }
    }

    private var hasDeletableContext: Bool {
        displayContextDayCount > 0
    }

    /// The connected iPhone's name, or nil when none is connected. The capture fixture's
    /// session can be reset by a late callback, so capture shows its fixed peer name.
    private var displayPairedIPhone: String? {
        #if DEBUG
        if MacMarketingCapture.isActive { return MacMarketingCapture.peerName }
        #endif
        guard syncService.connectionState == .connected else { return nil }
        return syncService.connectedPeerName ?? String(localized: "iPhone")
    }

    // MARK: Encrypted context display state (the capture fixture never opens the Keychain store)

    private var displayContextStatusLoaded: Bool {
        #if DEBUG
        if MacMarketingCapture.isActive { return true }
        #endif
        return encryptedHealthContextManager.hasLoadedStatus
    }

    private var displayContextDayCount: Int {
        #if DEBUG
        if MacMarketingCapture.isActive { return MacMarketingCapture.encryptedContextDayCount }
        #endif
        return encryptedHealthContextManager.ownerDateCount
    }

    /// MacCLIG has no owner-date range row, so the capture shows none.
    private var displayContextEarliestOwnerDate: String? {
        #if DEBUG
        if MacMarketingCapture.isActive { return nil }
        #endif
        return encryptedHealthContextManager.earliestOwnerDate
    }

    private var displayContextLatestOwnerDate: String? {
        #if DEBUG
        if MacMarketingCapture.isActive { return nil }
        #endif
        return encryptedHealthContextManager.latestOwnerDate
    }

    /// The "Choose date" popover: pick the boundary, then confirm deleting older days.
    private var retentionPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                String(localized: "Choose date"),
                selection: $retentionBoundary,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            Button(String(localized: "Delete Older Days")) {
                showRetentionPicker = false
                showRetentionConfirmation = true
            }
            .buttonStyle(MacGlassCapsuleButtonStyle(prominent: true))
        }
        .padding(16)
    }

    private var retentionOwnerDate: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: retentionBoundary)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private var isBundledCLIPresent: Bool {
        FileManager.default.isExecutableFile(atPath: bundledCLIPath)
    }

    /// The CLI ships inside the app bundle, so its version is the app's version.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var bundledCLIPath: String { MacCLIBundlePaths.cli }

    private var bundledSkillsPath: String { MacCLIBundlePaths.skillsDirectory }

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

struct HealthMdAgentSkill: Identifiable {
    let directoryName: String
    let title: String
    let summary: String
    let systemImage: String

    var id: String { directoryName }
    var resourceName: String { "\(directoryName).skill" }
    var resourceFileName: String { "\(resourceName).md" }
}

enum HealthMdAgentSkillBundle {
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

#endif
