import Foundation

@MainActor
protocol SharedSetupScheduling: AnyObject {
    var schedule: ExportSchedule { get set }
    func cancelSharedSetupAutomation()
}

extension SchedulingManager: SharedSetupScheduling {
    func cancelSharedSetupAutomation() {
        #if os(iOS)
        cancelBackgroundTask()
        #elseif os(macOS)
        // Assigning the disabled schedule already invalidates the macOS timer in didSet.
        #endif
    }
}

struct SharedSetupUndoSnapshot: Codable {
    var settings: SharedSetupPortableSnapshot
    var schedule: ExportSchedule
    var pendingEndpointHint: String?
    var preservedAndroidExtension: SharedSetupV1.AndroidExtension?
    /// Endpoint URLs are non-secret rollback state. Credentials are never encoded in Undo data.
    var apiEndpointURLString: String?
}

struct SharedSetupApplyResult: Equatable, Sendable {
    var appliedItems: [String]
    var attentionItems: [String]
}

@MainActor
final class SharedSetupTransaction {
    // Keep deallocation on the releasing thread. Avoid Swift 6.2+'s crashing
    // isolated-deinit executor hop (swiftlang/swift#85663), which aborted CI
    // test processes when the last release happened off the main actor.
    nonisolated deinit {}
    static let undoKey = "sharedSetup.apple.undo.v1"
    static let pendingEndpointKey = "sharedSetup.apple.pendingEndpoint.v1"
    static let preservedAndroidExtensionKey = "sharedSetup.apple.preservedAndroidExtension.v1"

    private let settings: AdvancedExportSettings
    private let apiExportSettings: APIExportSettings
    private let schedulingManager: any SharedSetupScheduling
    private let userDefaults: UserDefaults
    private let verificationOverride: (() -> Bool)?

    init(
        settings: AdvancedExportSettings,
        apiExportSettings: APIExportSettings,
        schedulingManager: any SharedSetupScheduling,
        userDefaults: UserDefaults = .standard,
        verificationOverride: (() -> Bool)? = nil
    ) {
        self.settings = settings
        self.apiExportSettings = apiExportSettings
        self.schedulingManager = schedulingManager
        self.userDefaults = userDefaults
        self.verificationOverride = verificationOverride
    }

    var canUndo: Bool { decodeUndo() != nil }
    var pendingEndpointHint: String? { userDefaults.string(forKey: Self.pendingEndpointKey) }
    var preservedAndroidExtension: SharedSetupV1.AndroidExtension? {
        guard let data = userDefaults.data(forKey: Self.preservedAndroidExtensionKey),
              data.count <= SharedSetupV1.maximumEncodedBytes else { return nil }
        return try? JSONDecoder().decode(SharedSetupV1.AndroidExtension.self, from: data)
    }

    func apply(_ preview: SharedSetupPreview) throws -> SharedSetupApplyResult {
        guard !preview.hasInvalidItems else { throw SharedSetupError.invalid("This setup contains invalid items and cannot be applied.") }
        let candidate = SharedSetupMapper.portableSnapshot(from: preview, preservingTemplateFrom: settings)
        let previous = SharedSetupUndoSnapshot(
            settings: .capture(settings),
            schedule: schedulingManager.schedule,
            pendingEndpointHint: pendingEndpointHint,
            preservedAndroidExtension: preservedAndroidExtension,
            apiEndpointURLString: apiExportSettings.endpointURLString.isEmpty
                ? nil
                : apiExportSettings.endpointURLString
        )
        let previousUndo = userDefaults.data(forKey: Self.undoKey)
        let previousSchedule = schedulingManager.schedule
        let undoData = try internalEncoder().encode(previous)
        guard undoData.count <= SharedSetupV1.maximumEncodedBytes else { throw SharedSetupError.oversized }

        var disabled = previousSchedule
        disabled.isEnabled = false
        disabled.enabledAt = nil
        disabled.lastExportDate = nil
        disabled.lastTodayRefreshDate = nil
        let appliedSchedule = SharedSetupMapper.exactAppleSchedule(preview.document) ?? disabled
        do {
            // Cancel automation first. If any later persistence verification fails, rollback below
            // restores and verifies the exact prior portable profile and scheduler configuration.
            schedulingManager.schedule = disabled
            schedulingManager.cancelSharedSetupAutomation()

            try settings.applySharedSetupBatch(candidate, verificationOverride: verificationOverride)
            schedulingManager.schedule = appliedSchedule
            if let endpoint = preview.document.profile.apiEndpoint?.validatedURLString {
                userDefaults.set(endpoint, forKey: Self.pendingEndpointKey)
            } else {
                userDefaults.removeObject(forKey: Self.pendingEndpointKey)
            }
            try persistAndroidExtension(preview.document.platformExtensions.android)
            userDefaults.set(undoData, forKey: Self.undoKey)
            guard SharedSetupPortableSnapshot.capture(settings) == candidate,
                  userDefaults.data(forKey: Self.undoKey) == undoData,
                  schedulingManager.schedule == appliedSchedule,
                  appliedSchedule.isEnabled == false,
                  pendingEndpointHint == preview.document.profile.apiEndpoint?.validatedURLString,
                  preservedAndroidExtension == preview.document.platformExtensions.android,
                  apiExportSettings.endpointURLString == (previous.apiEndpointURLString ?? "") else {
                throw SharedSetupError.persistenceVerificationFailed
            }
        } catch {
            let originalError = error
            do { try restore(previous, undoData: previousUndo) }
            catch { throw SharedSetupError.persistenceVerificationFailed }
            throw originalError
        }

        return SharedSetupApplyResult(
            appliedItems: preview.items.filter { $0.status == .applied }.map(\.title),
            attentionItems: preview.items.filter { $0.status == .requiresAction || $0.status == .unsupported }.map { "\($0.title): \($0.detail)" }
        )
    }

    func confirmPendingEndpoint(authorization: String) throws {
        guard let endpoint = pendingEndpointHint else {
            throw SharedSetupError.invalid("There is no imported endpoint waiting for confirmation.")
        }
        let credential = authorization.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty, credential.count <= 8_192,
              !credential.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }) else {
            throw SharedSetupError.invalid("Enter a valid local endpoint credential.")
        }
        let previousEndpoint = apiExportSettings.endpointURLString
        let previousCredential = try apiExportSettings.sharedSetupPersistedBearerToken()
        guard previousCredential == apiExportSettings.bearerToken else {
            throw SharedSetupError.persistenceVerificationFailed
        }
        do {
            // Clear and verify first so an existing credential can never become attached to the
            // imported hint, even when Keychain deletion or replacement fails.
            try apiExportSettings.replaceBearerTokenVerifiably("")
            try apiExportSettings.replaceEndpointURLVerifiably(endpoint)
            try apiExportSettings.replaceBearerTokenVerifiably(credential)
            userDefaults.removeObject(forKey: Self.pendingEndpointKey)
            guard apiExportSettings.endpointURL?.absoluteString == endpoint,
                  apiExportSettings.bearerToken == credential,
                  try apiExportSettings.sharedSetupPersistedBearerToken() == credential,
                  pendingEndpointHint == nil else {
                throw SharedSetupError.persistenceVerificationFailed
            }
        } catch {
            let originalError = error
            // Retain the unconfirmed hint even if restoring the previous local destination fails.
            userDefaults.set(endpoint, forKey: Self.pendingEndpointKey)
            do {
                try apiExportSettings.replaceBearerTokenVerifiably("")
                try apiExportSettings.replaceEndpointURLVerifiably(previousEndpoint)
                try apiExportSettings.replaceBearerTokenVerifiably(previousCredential)
                guard apiExportSettings.endpointURLString == previousEndpoint,
                      apiExportSettings.bearerToken == previousCredential,
                      try apiExportSettings.sharedSetupPersistedBearerToken() == previousCredential,
                      pendingEndpointHint == endpoint else {
                    throw SharedSetupError.persistenceVerificationFailed
                }
            } catch {
                throw SharedSetupError.persistenceVerificationFailed
            }
            throw originalError
        }
    }

    func undo() throws -> SharedSetupApplyResult {
        guard let undoData = userDefaults.data(forKey: Self.undoKey),
              undoData.count <= SharedSetupV1.maximumEncodedBytes,
              let snapshot = try? internalDecoder().decode(SharedSetupUndoSnapshot.self, from: undoData) else {
            throw SharedSetupError.noUndoSnapshot
        }
        let current = SharedSetupUndoSnapshot(
            settings: .capture(settings),
            schedule: schedulingManager.schedule,
            pendingEndpointHint: pendingEndpointHint,
            preservedAndroidExtension: preservedAndroidExtension,
            apiEndpointURLString: apiExportSettings.endpointURLString.isEmpty
                ? nil
                : apiExportSettings.endpointURLString
        )
        let restoredEndpoint = snapshot.apiEndpointURLString ?? ""
        let endpointChanges = apiExportSettings.endpointURLString != restoredEndpoint
        var credentialBeforeUndo: String?
        do {
            if endpointChanges {
                credentialBeforeUndo = try apiExportSettings.sharedSetupPersistedBearerToken()
                guard credentialBeforeUndo == apiExportSettings.bearerToken else {
                    throw SharedSetupError.persistenceVerificationFailed
                }
                // Undo data is non-secret. Clear and verify the current endpoint credential before
                // restoring the prior non-secret URL rather than ever serializing that credential.
                try apiExportSettings.replaceBearerTokenVerifiably("")
            }
            try settings.applySharedSetupBatch(snapshot.settings)
            schedulingManager.schedule = snapshot.schedule
            try apiExportSettings.replaceEndpointURLVerifiably(restoredEndpoint)
            if let endpoint = snapshot.pendingEndpointHint { userDefaults.set(endpoint, forKey: Self.pendingEndpointKey) }
            else { userDefaults.removeObject(forKey: Self.pendingEndpointKey) }
            restoreAndroidExtension(snapshot.preservedAndroidExtension)
            let persistedCredentialAfterUndo = try apiExportSettings.sharedSetupPersistedBearerToken()
            let credentialIsSafe = !endpointChanges ||
                (apiExportSettings.bearerToken.isEmpty && persistedCredentialAfterUndo.isEmpty)
            guard SharedSetupPortableSnapshot.capture(settings) == snapshot.settings,
                  schedulingManager.schedule == snapshot.schedule,
                  pendingEndpointHint == snapshot.pendingEndpointHint,
                  preservedAndroidExtension == snapshot.preservedAndroidExtension,
                  apiExportSettings.endpointURLString == restoredEndpoint,
                  credentialIsSafe else {
                throw SharedSetupError.persistenceVerificationFailed
            }
            userDefaults.removeObject(forKey: Self.undoKey)
            guard userDefaults.data(forKey: Self.undoKey) == nil else {
                throw SharedSetupError.persistenceVerificationFailed
            }
        } catch {
            let originalError = error
            do {
                try restore(current, undoData: undoData)
                if let credentialBeforeUndo {
                    try apiExportSettings.replaceBearerTokenVerifiably(credentialBeforeUndo)
                }
                guard apiExportSettings.endpointURLString == (current.apiEndpointURLString ?? "") else {
                    throw SharedSetupError.persistenceVerificationFailed
                }
                if let credentialBeforeUndo {
                    guard apiExportSettings.bearerToken == credentialBeforeUndo,
                          try apiExportSettings.sharedSetupPersistedBearerToken() == credentialBeforeUndo else {
                        throw SharedSetupError.persistenceVerificationFailed
                    }
                }
            } catch {
                // Never leave a credential bound to an endpoint whose rollback cannot be attested.
                try? apiExportSettings.replaceBearerTokenVerifiably("")
                throw SharedSetupError.persistenceVerificationFailed
            }
            throw originalError
        }
        var attention = ["Folder access, permissions, purchases, and device permissions were unchanged."]
        if endpointChanges {
            attention.append("The previous API endpoint was restored. Endpoint credentials were cleared and must be entered again locally.")
        } else {
            attention.append("Endpoint credentials were unchanged.")
        }
        return SharedSetupApplyResult(
            appliedItems: ["Previous portable setup restored"],
            attentionItems: attention
        )
    }

    private func decodeUndo() -> SharedSetupUndoSnapshot? {
        guard let data = userDefaults.data(forKey: Self.undoKey),
              data.count <= SharedSetupV1.maximumEncodedBytes else { return nil }
        return try? internalDecoder().decode(SharedSetupUndoSnapshot.self, from: data)
    }

    private func internalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.userInfo[.includeSharedSetupExactFrontmatter] = true
        return encoder
    }

    private func internalDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.includeSharedSetupExactFrontmatter] = true
        return decoder
    }

    private func restore(_ snapshot: SharedSetupUndoSnapshot, undoData: Data?) throws {
        try settings.applySharedSetupBatch(snapshot.settings)
        schedulingManager.schedule = snapshot.schedule
        try apiExportSettings.replaceEndpointURLVerifiably(snapshot.apiEndpointURLString ?? "")
        if let endpoint = snapshot.pendingEndpointHint { userDefaults.set(endpoint, forKey: Self.pendingEndpointKey) }
        else { userDefaults.removeObject(forKey: Self.pendingEndpointKey) }
        restoreAndroidExtension(snapshot.preservedAndroidExtension)
        if let undoData { userDefaults.set(undoData, forKey: Self.undoKey) }
        else { userDefaults.removeObject(forKey: Self.undoKey) }
        guard SharedSetupPortableSnapshot.capture(settings) == snapshot.settings,
              schedulingManager.schedule == snapshot.schedule,
              pendingEndpointHint == snapshot.pendingEndpointHint,
              preservedAndroidExtension == snapshot.preservedAndroidExtension,
              apiExportSettings.endpointURLString == (snapshot.apiEndpointURLString ?? ""),
              userDefaults.data(forKey: Self.undoKey) == undoData else {
            throw SharedSetupError.persistenceVerificationFailed
        }
    }

    private func persistAndroidExtension(_ value: SharedSetupV1.AndroidExtension?) throws {
        guard let value else {
            userDefaults.removeObject(forKey: Self.preservedAndroidExtensionKey)
            return
        }
        let data = try JSONEncoder().encode(value)
        guard data.count <= SharedSetupV1.maximumEncodedBytes else { throw SharedSetupError.oversized }
        userDefaults.set(data, forKey: Self.preservedAndroidExtensionKey)
    }

    private func restoreAndroidExtension(_ value: SharedSetupV1.AndroidExtension?) {
        guard let value, let data = try? JSONEncoder().encode(value),
              data.count <= SharedSetupV1.maximumEncodedBytes else {
            userDefaults.removeObject(forKey: Self.preservedAndroidExtensionKey)
            return
        }
        userDefaults.set(data, forKey: Self.preservedAndroidExtensionKey)
    }
}
