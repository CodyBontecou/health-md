#if os(macOS)
import AppKit
import SwiftUI

// MARK: - CLI & MCP reference window
//
// MacCLIG shows only Status, Agent skill and Encrypted query context. The terminal install
// commands, MCP host configuration, command examples and readiness troubleshooting it used to
// append live here, opened from Help ▸ CLI & MCP Reference.

/// Paths of the helpers and skill bundled in the app.
enum MacCLIBundlePaths {
    static var cli: String {
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

    static var mcp: String {
        URL(fileURLWithPath: cli)
            .deletingLastPathComponent()
            .appendingPathComponent("healthmd-mcp")
            .path
    }

    static var skillsDirectory: String {
        HealthMdAgentSkillBundle.bundledResourceDirectoryURL?.path
            ?? "/Applications/Health.md.app/Contents/Resources"
    }

    static var skillFile: String {
        HealthMdAgentSkillBundle.skills.first.flatMap { HealthMdAgentSkillBundle.bundledFileURL(for: $0)?.path }
            ?? "/Applications/Health.md.app/Contents/Resources/healthmd-cli.skill.md"
    }
}

struct MacCLIReferenceView: View {
    static let windowID = "cli-reference"

    @State private var copiedKey: String?

    var body: some View {
        MacGlassPage {
            MacGlassPageHeader(
                title: String(localized: "CLI & MCP Reference"),
                subtitle: String(localized: "Choose agent-assisted setup or copy the manual shell commands.")
            )

            MacGlassSection(title: String(localized: "Install for Terminal")) {
                commandBlock(String(localized: "Agent install prompt"), agentInstallPrompt, key: "prompt")
                MacGlassDivider()
                commandBlock(String(localized: "Aliases for this shell"), aliasCommand, key: "alias")
                MacGlassDivider()
                commandBlock(String(localized: "Persistent symlink"), symlinkCommand, key: "symlink")
            }
            MacGlassFootnote(text: String(localized: "If `~/.local/bin` is not on your PATH, add `export PATH=\"$HOME/.local/bin:$PATH\"` to your shell config."))

            MacGlassSection(title: String(localized: "Connect Codex or Claude")) {
                commandBlock(String(localized: "Codex · ~/.codex/config.toml"), codexMCPConfig, key: "codex")
                MacGlassDivider()
                commandBlock(String(localized: "Claude Desktop or trusted .mcp.json"), claudeMCPConfig, key: "claude")
            }
            MacGlassFootnote(text: String(localized: "Compatible native hosts render the interactive MCP App inline. Other Codex and Claude surfaces keep exact JSON and receive a PNG metric-chart fallback. Fresh acquisition and export mutations require approval."))

            MacGlassSection(title: String(localized: "Manual shell command")) {
                commandBlock(String(localized: "Agent skill"), skillManualInstallCommand, key: "skill")
            }
            MacGlassFootnote(text: String(localized: "Edit `SKILLS_DIR` to match the folder your agent reads. The app installer replaces the Health.md skill folder; the shell command overwrites only `SKILL.md`."))

            MacGlassSection(title: String(localized: "Commands")) {
                ForEach(Array(Self.commands.enumerated()), id: \.offset) { index, command in
                    if index > 0 { MacGlassDivider() }
                    commandRow(command.title, command.command)
                }
            }
            MacGlassFootnote(text: String(localized: "Run these after the Mac app is open and the iPhone app is connected."))

            MacGlassSection(title: String(localized: "Troubleshooting")) {
                ForEach(Array(Self.troubleshooting.enumerated()), id: \.offset) { index, item in
                    if index > 0 { MacGlassDivider() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.code)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.glassAdaptive(\.text))
                            .textSelection(.enabled)
                        Text(item.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.glassAdaptive(\.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                }
            }
            MacGlassFootnote(text: String(localized: "What common JSON readiness states mean."))
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 760)
        .glassTheme()
    }

    // MARK: - Rows

    private func commandBlock(_ title: String, _ command: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.glassAdaptive(\.text))
                Spacer(minLength: 12)
                copyButton(command, key: key)
            }
            Text(verbatim: command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.glassAdaptive(\.muted))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }

    private func commandRow(_ title: String, _ command: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.glassAdaptive(\.text))
                Text(verbatim: command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.glassAdaptive(\.muted))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            copyButton(command, key: command)
        }
        .padding(.vertical, 8)
    }

    private func copyButton(_ value: String, key: String) -> some View {
        Button(copiedKey == key ? String(localized: "Copied") : String(localized: "Copy")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copiedKey = key
        }
        .buttonStyle(MacGlassRowButtonStyle())
    }

    // MARK: - Content

    private struct CommandExample {
        let title: String
        let command: String
    }

    private static var commands: [CommandExample] {
        [
            CommandExample(title: String(localized: "Check connection readiness"), command: "healthmd status"),
            CommandExample(title: String(localized: "Check CLI and iPhone readiness"), command: "healthmd doctor"),
            CommandExample(title: String(localized: "List queryable Sleep metrics"), command: "healthmd metrics list --category Sleep"),
            CommandExample(title: String(localized: "Extract canonical Sleep data without changing iPhone settings"), command: "healthmd extract --category Sleep --yesterday"),
            CommandExample(title: String(localized: "Run a derived Sleep metric query"), command: "healthmd query --category Sleep --yesterday"),
            CommandExample(title: String(localized: "Inspect the first four hours of recent sleep"), command: "healthmd sleep sessions --last-nights 14 --window first:4h"),
            CommandExample(title: String(localized: "Align runs with preceding and following sleep"), command: "healthmd training align --last 14 --workout running --sleep-window first:4h"),
            CommandExample(title: String(localized: "List recent workouts"), command: "healthmd workouts --last 14"),
            CommandExample(title: String(localized: "Inspect Sleep coverage"), command: "healthmd coverage --category Sleep --last 14"),
            CommandExample(title: String(localized: "Export yesterday to Mac folder"), command: "healthmd export --iphone --yesterday"),
            CommandExample(title: String(localized: "Export last 7 days"), command: "healthmd export --iphone --last 7"),
            CommandExample(title: String(localized: "Export selected Sleep summaries"), command: "healthmd export --iphone --last 7 --category Sleep --detail summary"),
            CommandExample(title: String(localized: "Return raw JSON without files"), command: "healthmd export --iphone --yesterday --raw"),
            CommandExample(title: String(localized: "Use iPhone settings exactly"), command: "healthmd export --iphone --yesterday --use-iphone-settings")
        ]
    }

    private static var troubleshooting: [(code: String, detail: String)] {
        [
            ("mac_app_unreachable", String(localized: "Open Health.md on Mac. The CLI talks to the running app, not directly to iPhone.")),
            ("iphone_not_connected", String(localized: "Unlock iPhone, open Health.md, and wait for the Mac Destination connection.")),
            ("mac_destination_unavailable", String(localized: "Choose or reselect a Mac folder, or use `--raw` when you only need JSON.")),
            ("can_trigger_raw_exports", String(localized: "Raw JSON can work even when no Mac destination folder is selected."))
        ]
    }

    private var aliasCommand: String {
        """
        alias healthmd=\"\(MacCLIBundlePaths.cli)\"
        alias healthmd-mcp=\"\(MacCLIBundlePaths.mcp)\"
        """
    }

    private var symlinkCommand: String {
        """
        mkdir -p ~/.local/bin
        ln -sf \"\(MacCLIBundlePaths.cli)\" ~/.local/bin/healthmd
        ln -sf \"\(MacCLIBundlePaths.mcp)\" ~/.local/bin/healthmd-mcp
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
                    "command": MacCLIBundlePaths.mcp,
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
        guard let data = try? JSONEncoder().encode(MacCLIBundlePaths.mcp) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }

    private var skillManualInstallCommand: String {
        """
        SKILLS_DIR="$HOME/.agents/skills"
        mkdir -p "$SKILLS_DIR/healthmd-cli" && cp "\(MacCLIBundlePaths.skillFile)" "$SKILLS_DIR/healthmd-cli/SKILL.md"
        """
    }

    private var agentInstallPrompt: String {
        """
        Install the Health.md CLI and stdio MCP helper for my shell from the bundled Mac app. The signed sandboxed binaries are at:

        \(MacCLIBundlePaths.cli)
        \(MacCLIBundlePaths.mcp)

        Please:
        1. Verify both files exist; run the CLI with `--help` (do not start the MCP stdio loop interactively).
        2. Create `~/.local/bin` if needed.
        3. Create or replace symlinks at `~/.local/bin/healthmd` and `~/.local/bin/healthmd-mcp` pointing to the bundled helpers.
        4. If `~/.local/bin` is not on PATH, tell me the exact shell config line to add, but do not edit shell config unless I explicitly approve.
        5. Run `healthmd status` or `~/.local/bin/healthmd status` and summarize the JSON readiness.

        Use bounded, non-interactive commands. Do not modify Health.md export files.
        """
    }
}

// MARK: - Help menu

/// The app's shared feedback handoff, so Help menu items can show the copyable-report fallback
/// in the main window.
@MainActor
enum MacSupport {
    static let feedbackReporter = FeedbackReporter()
    static let privacyPolicyURL = URL(string: "https://healthmd.app/privacy-policy.html")!
}

/// Help ▸ feedback, bug report, privacy policy and the CLI & MCP reference. MacSettingsG has no
/// Support section, so these live in the standard macOS Help menu.
struct MacHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(String(localized: "CLI & MCP Reference")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: MacCLIReferenceView.windowID)
            }
            Divider()
            Button(String(localized: "Send Feedback")) {
                openFeedback(.email)
            }
            Button(String(localized: "Report a Bug on GitHub")) {
                openFeedback(.github)
            }
            Button(String(localized: "Privacy Policy")) {
                openURL(MacSupport.privacyPolicyURL)
            }
        }
    }

    /// Opens the main window first so a failed handoff can present its copyable report there.
    private func openFeedback(_ route: FeedbackReporter.Route) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main-window")
        MacSupport.feedbackReporter.open(route)
    }
}
#endif
