#if DEBUG && os(macOS)
import AppKit
import Foundation

/// Arms health-free telemetry in the exact Debug Mac process through a private,
/// fixed-shape file inbox. It does not change connected-export wire messages or
/// expose an arbitrary command/network server.
@MainActor
final class MacExportPerformanceLabController {
    static let shared = MacExportPerformanceLabController()

    private let vaultVerifier: (String) -> Bool
    private let inboxDirectory: URL
    private var monitorTask: Task<Void, Never>?

    init() {
        self.vaultVerifier = { binding in
            MacExportPerformanceLabController.verifyMacVault(binding: binding)
        }
        self.inboxDirectory = Self.defaultInboxDirectory
    }

    init(
        vaultVerifier: @escaping (String) -> Bool,
        inboxDirectory: URL? = nil
    ) {
        self.vaultVerifier = vaultVerifier
        self.inboxDirectory = inboxDirectory ?? Self.defaultInboxDirectory
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: inboxDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: inboxDirectory.path
            )
        } catch {
            return
        }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.processInbox()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "healthmd",
              url.host?.lowercased() == "export-lab",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        let items = components.queryItems ?? []
        let grouped = Dictionary(grouping: items, by: \.name)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { return false }
        let values = grouped.compactMapValues(\.first?.value)
        switch url.path {
        case "/setup-mac":
            guard Set(values.keys) == Set(["binding"]),
                  let binding = values["binding"],
                  Self.isBinding(binding) else { return false }
            presentMacVaultSetup(binding: binding)
            return true
        case "/mac-arm":
            guard Set(values.keys) == Set(["run", "binding"]),
                  let runID = values["run"],
                  ExportPerformanceLabTelemetryStore.isSafeRunID(runID),
                  let binding = values["binding"] else { return false }
            arm(runID: runID, binding: binding)
            return true
        case "/mac-end":
            guard Set(values.keys) == Set(["run"]),
                  let runID = values["run"],
                  ExportPerformanceLabTelemetryStore.isSafeRunID(runID) else { return false }
            ExportPerformanceInstrumentation.endLabRun(runID: runID)
            return true
        default:
            return false
        }
    }

    private func presentMacVaultSetup(binding: String) {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("HealthMdPerformanceLab/MacVault", isDirectory: true)
        let panel = NSOpenPanel()
        panel.title = "Select the Health.md Performance Lab Mac Vault"
        panel.message = "Choose the prepared MacVault folder. Ordinary health vaults are rejected."
        panel.prompt = "Choose MacVault"
        panel.directoryURL = expected
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK,
                  let selected = panel.url,
                  selected.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath() else {
                return
            }
            let vault = VaultManager()
            vault.setVaultFolder(selected)
            guard Self.verifyMacVault(binding: binding) else {
                vault.clearVaultFolder()
                return
            }
        }
    }

    private func processInbox() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: inboxDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            let action = file.pathExtension
            let runID = file.deletingPathExtension().lastPathComponent
            guard ExportPerformanceLabTelemetryStore.isSafeRunID(runID),
                  action == "arm" || action == "end" else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            if action == "arm" {
                guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                      data.count <= 128 else {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                let binding = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                arm(runID: runID, binding: binding)
            } else {
                ExportPerformanceInstrumentation.endLabRun(runID: runID)
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func arm(runID: String, binding: String) {
        guard Self.isBinding(binding) else { return }
        guard vaultVerifier(binding) else {
            let rejection = Self.macVaultRejection(binding: binding) ?? "verifier"
            Self.writeRejection(runID: runID, reason: rejection)
            return
        }
        let current = ExportPerformanceLabTelemetryStore.shared.activeContext
        guard current == nil || current?.runID == runID else { return }
        if current == nil {
            do {
                let telemetryURL = try ExportPerformanceInstrumentation.beginLabRun(
                    runID: runID,
                    target: .connectedMac
                )
                let peerURL = telemetryURL.deletingLastPathComponent()
                    .appendingPathComponent("mac-peer-id")
                let peerID = SyncInstallationIdentity.persisted()
                    .uuidString.lowercased()
                guard FileManager.default.createFile(
                    atPath: peerURL.path,
                    contents: Data("\(peerID)\n".utf8),
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    ExportPerformanceInstrumentation.endLabRun(runID: runID)
                    return
                }
            } catch {
                return
            }
        }
        let span = ExportPerformanceInstrumentation.beginSpan(
            pipeline: "export-lab",
            phase: "mac-arm"
        )
        span.finish(outcome: .success)
    }

    private static func verifyMacVault(binding: String) -> Bool {
        macVaultRejection(binding: binding) == nil
    }

    private static func macVaultRejection(binding: String) -> String? {
        let vault = VaultManager()
        vault.refreshVaultAccess()
        guard let root = vault.vaultURL else { return "bookmark" }
        guard let accessLease = vault.beginVaultAccess() else { return "access" }
        defer { accessLease.stop() }
        guard root.lastPathComponent == "MacVault" else { return "path" }
        let rootValues = try? root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues?.isDirectory == true,
              rootValues?.isSymbolicLink != true else { return "path" }
        let marker = root.appendingPathComponent(".healthmd-performance-lab")
        let values = try? marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let data = try? Data(contentsOf: marker, options: .mappedIfSafe),
              data.count <= 128 else { return "marker" }
        let persisted = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return persisted == binding ? nil : "binding"
    }

    private static func writeRejection(runID: String, reason: String) {
        guard ExportPerformanceLabTelemetryStore.isSafeRunID(runID),
              ["bookmark", "access", "path", "marker", "binding", "verifier"]
                .contains(reason) else { return }
        let url = defaultInboxDirectory.appendingPathComponent("\(runID).reject")
        _ = FileManager.default.createFile(
            atPath: url.path,
            contents: Data("\(reason)\n".utf8),
            attributes: [.posixPermissions: 0o600]
        )
    }

    private static func isBinding(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static var defaultInboxDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("HealthMdPerformanceLab", isDirectory: true)
        .appendingPathComponent("MacInbox", isDirectory: true)
    }
}
#endif
