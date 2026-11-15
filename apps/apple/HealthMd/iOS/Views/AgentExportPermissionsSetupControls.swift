#if os(iOS)
import Darwin
import HealthMdConnectionCore
import SwiftUI
import UIKit

/// Local native setup and grant controls. No wire request or export route invokes this view.
struct AgentExportPermissionsSetupControls: View {
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: SetupStatus = .checking
    @State private var confirming = false

    private enum SetupStatus { case checking, notSetUp, ready, unavailable }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("agentExportPermissions.status")
            if status == .ready { AgentExportPermissionsManagementControls() }
            if status == .notSetUp {
                Button("Set up agent export permissions") {
                    configurationProtection.performConfigurationChange { confirming = true }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("agentExportPermissions.setup")
            }
        }
        .confirmationDialog("Set up agent export permissions on this device?", isPresented: $confirming,
                            titleVisibility: .visible) {
            Button("Set up permissions", action: confirmSetup)
                .accessibilityIdentifier("agentExportPermissions.confirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Each agent will need separate export permission. Setting this up does not approve an export or give any agent access.")
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { confirming = false }
            else { refresh() }
        }
    }

    private var statusText: LocalizedStringKey {
        switch status {
        case .checking: "Checking agent export permissions…"
        case .notSetUp: "Keep agent export permissions on this device. Each agent needs your separate approval before it can export health data."
        case .ready: "Agent export permissions are set up on this device. Setup alone does not give an agent access."
        case .unavailable: "Agent export permissions are unavailable. No new export access was granted."
        }
    }

    private func refresh() {
        do {
            let root = try AgentExportPermissionsStorage.directory(createParent: false)
            var attributes = stat()
            if lstat(root.path, &attributes) != 0 {
                status = errno == ENOENT ? .notSetUp : .unavailable
                return
            }
            _ = try AgentBridgeExportAuthorityStore(existingDirectory: root).snapshot()
            status = .ready
        } catch { status = .unavailable }
    }

    private func confirmSetup() {
        guard status == .notSetUp else { return }
        configurationProtection.performConfigurationChange {
            let protection = configurationProtection
            do {
                try AgentBridgeExportNativeSetupConsent.withNativeConfirmation(requireCurrentNativePolicy: {
                    guard Thread.isMainThread else { throw AgentBridgeValidationError.approvalRequired }
                    try MainActor.assumeIsolated {
                        guard UIApplication.shared.applicationState == .active,
                              UIApplication.shared.isProtectedDataAvailable,
                              !protection.isEnabled else { throw AgentBridgeValidationError.approvalRequired }
                    }
                }) { consent in
                    let root = try AgentExportPermissionsStorage.directory(createParent: true)
                    let store = try AgentBridgeExportAuthorityStore.createNativePrivateStore(at: root, authorization: consent)
                    _ = try store.snapshot()
                }
                status = .ready
            } catch { status = .unavailable }
        }
    }
}
enum AgentExportPermissionsStorage {
    static func directory(createParent: Bool) throws -> URL {
        let parent: URL
        if createParent {
            parent = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true).resolvingSymlinksInPath()
        } else {
            guard let existingLocation = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw AgentBridgeValidationError.permissionRequired
            }
            parent = existingLocation.resolvingSymlinksInPath()
        }
        return parent.appendingPathComponent("agent-bridge-export-authority-v1", isDirectory: true)
    }

}
#endif
