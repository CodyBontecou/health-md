#if os(iOS)
import Foundation
import HealthMdConnectionCore
import SwiftUI
import UIKit

nonisolated private struct AgentGrantEditorContext: Identifiable, Sendable {
    let id = UUID()
    let trust: AgentBridgeExportNativeTrustSnapshot
    let generation: Int64
    var peer: AgentBridgePeer {
        get throws {
            try .init(sourceInstallationID: AgentBridgeUUID(trust.ownerInstallationID.uuidString.lowercased()),
                      hostInstallationID: AgentBridgeUUID(trust.trustedMacInstallationID.uuidString.lowercased()), platform: .apple)
        }
    }
    @MainActor func requireOriginalPairing() throws {
        guard let raw = UserDefaults.standard.string(forKey: IPhoneDirectCLIService.installationIDKey),
              UUID(uuidString: raw) == trust.ownerInstallationID else { throw AgentBridgeValidationError.approvalRequired }
        try AgentBridgeExportNativeTrust().requireCurrent(original: trust, nativeSourceInstallationID: trust.ownerInstallationID,
            authenticatedHostInstallationID: trust.trustedMacInstallationID, originalReconnectSecret: trust.reconnectSecret)
    }
}

private struct AgentGrantRevocation: Identifiable {
    let grant: AgentBridgeExportDelegation
    let generation: Int64
    var id: String { grant.authorityID.rawValue }
}

@MainActor
private enum AgentGrantNativePolicy {
    static func require(_ protection: ConfigurationProtectionManager) throws {
        guard UIApplication.shared.applicationState == .active, UIApplication.shared.isProtectedDataAvailable,
              !protection.isEnabled else { throw AgentBridgeValidationError.approvalRequired }
    }
}

struct AgentExportPermissionsManagementControls: View {
    @EnvironmentObject private var protection: ConfigurationProtectionManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var grants: [AgentBridgeExportDelegation] = []
    @State private var generation: Int64 = 0
    @State private var editor: AgentGrantEditorContext?
    @State private var revocation: AgentGrantRevocation?
    @State private var message: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let message { Text(message).font(.footnote).foregroundStyle(Color.textSecondary) }
            ForEach(grants, id: \.authorityID) { grant in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Computer").font(.headline)
                    Text(grant.peer.hostInstallationID.rawValue).font(.footnote.monospaced()).textSelection(.enabled)
                    Text(AgentGrantCopy.summary(grant)).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Button("Revoke permission", role: .destructive) {
                        protection.performConfigurationChange { revocation = .init(grant: grant, generation: generation) }
                    }
                    .accessibilityIdentifier("agentExportPermissions.revoke.\(grant.authorityID.rawValue)")
                }
            }
            Button("Add export permission", action: beginGrant)
                .accessibilityIdentifier("agentExportPermissions.add")
            Button("Refresh permissions", action: refresh)
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
            else { editor = nil; revocation = nil }
        }
        .sheet(item: $editor, onDismiss: refresh) { context in AgentGrantEditor(context: context) }
        .alert("Revoke this export permission?", isPresented: Binding(
            get: { revocation != nil }, set: { if !$0 { revocation = nil } }), presenting: revocation) { review in
            Button("Revoke permission", role: .destructive) { revoke(review) }
            Button("Cancel", role: .cancel) { revocation = nil }
        } message: { review in Text(AgentGrantCopy.summary(review.grant)) }
    }

    private func refresh() {
        do {
            let state = try AgentBridgeExportAuthorityStore(existingDirectory: AgentExportPermissionsStorage.directory(createParent: false)).snapshot()
            grants = try state.delegations.filter { !$0.revoked }.map { try $0.description() }
            generation = state.generation
            message = nil
        } catch { grants = []; message = "Permission status could not be verified. Reopen this screen before trying again." }
    }

    private func beginGrant() {
        protection.performConfigurationChange {
            do {
                try AgentGrantNativePolicy.require(protection)
                guard let raw = UserDefaults.standard.string(forKey: IPhoneDirectCLIService.installationIDKey),
                      let source = UUID(uuidString: raw),
                      let trust = try AgentBridgeExportNativeTrust().loadExistingTrust(ownerInstallationID: source) else {
                    message = "Pair a computer before adding export permission."; return
                }
                let state = try AgentBridgeExportAuthorityStore(existingDirectory: AgentExportPermissionsStorage.directory(createParent: false)).snapshot()
                editor = .init(trust: trust, generation: state.generation)
            } catch { message = "Permission status could not be verified. Reopen this screen before trying again." }
        }
    }

    private func revoke(_ review: AgentGrantRevocation) {
        guard revocation?.id == review.id else { return }
        revocation = nil
        let protection = protection
        do {
            let reference = try review.grant.reference()
            try AgentBridgeExportNativeConsent.withNativeConfirmation(for: .revokeDelegation(reference), requireCurrentNativePolicy: {
                guard Thread.isMainThread else { throw AgentBridgeValidationError.approvalRequired }
                try MainActor.assumeIsolated { try AgentGrantNativePolicy.require(protection) }
            }) { consent in
                // Revocation intentionally needs no current pairing: forgotten computers must remain revocable.
                let store = try AgentBridgeExportAuthorityStore(existingDirectory: AgentExportPermissionsStorage.directory(createParent: false))
                try store.revokeNativeDelegation(reference, expectedGeneration: review.generation, authorization: consent)
            }
            refresh()
        } catch { message = "Permission status could not be verified. Reopen this screen before trying again." }
    }
}

private struct AgentGrantEditor: View {
    let context: AgentGrantEditorContext
    @EnvironmentObject private var protection: ConfigurationProtectionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var metrics: Set<String> = []
    @State private var start = Date()
    @State private var end = Date()
    @State private var expiry = Date().addingTimeInterval(3600)
    @State private var review: AgentBridgeExportDelegation?
    @State private var failed = false
    @State private var invalid = false
    private let zone = TimeZone.current

    var body: some View {
        NavigationStack {
            Form {
                Section("Computer") {
                    Text(context.trust.displayName)
                    Text(context.trust.trustedMacInstallationID.uuidString.lowercased()).font(.footnote.monospaced())
                }
                Section("Metrics") {
                    ForEach(AgentBridgeExportNativeGrantDraft.metricIDs, id: \.self) { id in
                        Toggle(AgentGrantCopy.metricName(id), isOn: Binding(
                            get: { metrics.contains(id) }, set: { if $0 { metrics.insert(id) } else { metrics.remove(id) } }))
                    }
                }
                Section("Export scope") {
                    DatePicker("Start date", selection: $start, displayedComponents: .date)
                    DatePicker("End date", selection: $end, displayedComponents: .date)
                    LabeledContent("Time zone", value: zone.identifier)
                    LabeledContent("Format", value: "JSON")
                    DatePicker("Permission expires", selection: $expiry, displayedComponents: [.date, .hourAndMinute])
                    Text("Allow planning and separately approved exports within this scope. Files may replace existing files at locations approved on this computer.")
                        .font(.footnote)
                }
                if invalid { Text("Choose at least one metric, a valid date range, and a future expiry.") }
                if failed { Text("Permission status could not be verified. Reopen this screen before trying again.") }
                Button("Review permission", action: prepareReview).disabled(metrics.isEmpty || failed || review != nil)
                    .accessibilityIdentifier("agentExportPermissions.review")
            }
            .environment(\.timeZone, zone)
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .navigationTitle("Add export permission")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Allow this export permission?", isPresented: Binding(
                get: { review != nil }, set: { if !$0 { review = nil } }), titleVisibility: .visible) {
                if let candidate = review {
                    Button("Allow permission") { save(candidate) }
                        .accessibilityIdentifier("agentExportPermissions.allow")
                }
                Button("Cancel", role: .cancel) { review = nil }
            } message: { if let candidate = review { Text(context.trust.displayName + "\n" + AgentGrantCopy.summary(candidate)) } }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { review = nil; dismiss() } }
    }

    private func prepareReview() {
        protection.performConfigurationChange {
            do {
                try AgentGrantNativePolicy.require(protection)
                try context.requireOriginalPairing()
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
                review = try AgentBridgeExportNativeGrantDraft.make(peer: context.peer, metrics: metrics,
                    start: formatter.string(from: start), end: formatter.string(from: end), timezone: zone.identifier,
                    expiresAt: expiry, now: Date())
                invalid = false
            } catch { invalid = true }
        }
    }

    private func save(_ candidate: AgentBridgeExportDelegation) {
        guard review?.authorityID == candidate.authorityID else { return }
        review = nil
        let protection = protection
        let context = context
        do {
            try AgentBridgeExportNativeConsent.withNativeConfirmation(for: .storeDelegation(candidate), requireCurrentNativePolicy: {
                guard Thread.isMainThread else { throw AgentBridgeValidationError.approvalRequired }
                try MainActor.assumeIsolated {
                    try AgentGrantNativePolicy.require(protection)
                    try context.requireOriginalPairing()
                }
                guard ISO8601DateFormatter().date(from: candidate.expiresAt.rawValue).map({ $0 > Date() }) == true else {
                    throw AgentBridgeValidationError.approvalRequired
                }
            }) { consent in
                let store = try AgentBridgeExportAuthorityStore(existingDirectory: AgentExportPermissionsStorage.directory(createParent: false))
                try store.storeNativeDelegation(candidate, expectedGeneration: context.generation, authorization: consent)
            }
            dismiss()
        } catch { failed = true }
    }
}

private enum AgentGrantCopy {
    static func metricName(_ id: String) -> String {
        switch id {
        case "steps": String(localized: "Steps")
        case "heart_rate_avg": String(localized: "Average Heart Rate")
        case "heart_rate_min": String(localized: "Minimum Heart Rate")
        case "heart_rate_max": String(localized: "Maximum Heart Rate")
        case "resting_heart_rate": String(localized: "Resting Heart Rate")
        case "hrv": String(localized: "HRV (SDNN)")
        default: id
        }
    }
    static func summary(_ grant: AgentBridgeExportDelegation) -> String {
        let dateText: String
        switch grant.bounds.datePolicy {
        case .boundedExact(let range, _): dateText = range.startDate.rawValue + " – " + range.endDate.rawValue
        case .authorizedHistory(let days, _): dateText = String(localized: "Day limit") + ": " + String(days)
        }
        return [grant.peer.hostInstallationID.rawValue, dateText,
                grant.bounds.metricIDs.map { metricName($0.rawValue) }.joined(separator: ", "),
                grant.bounds.calendarTimezones.map(\.rawValue).joined(separator: ", "),
                grant.bounds.formats.map { $0.rawValue.uppercased() }.joined(separator: ", "),
                String(localized: "Permission expires") + ": " + grant.expiresAt.rawValue,
                String(localized: "Allow planning and separately approved exports within this scope. Files may replace existing files at locations approved on this computer.")].joined(separator: "\n")
    }
}
#endif
