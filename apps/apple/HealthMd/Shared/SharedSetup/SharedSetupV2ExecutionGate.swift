import Foundation

enum SharedSetupV2RebindConfirmation: Equatable, Sendable {
    case deviceFolder(destinationID: UUID)
    case apiEndpoint(endpointID: UUID, credentialsConfirmed: Bool)
    case connectedMac(pairingConfirmed: Bool)
}

enum SharedSetupV2ExecutionGateError: LocalizedError, Equatable {
    case profileRequiresRebind
    case invalidState
    case rebindNotConfirmed
    case cloudUnsupported
    case persistenceVerificationFailed

    var errorDescription: String? {
        switch self {
        case .profileRequiresRebind:
            SharedSetupV2ExecutionGate.blockedExecutionMessage
        case .invalidState:
            "Shared Setup destination state could not be verified. This profile remains blocked."
        case .rebindNotConfirmed:
            "Confirm a concrete local destination before using this imported profile."
        case .cloudUnsupported:
            "Cloud destination intent is not supported on Apple. This imported profile remains blocked."
        case .persistenceVerificationFailed:
            "Health.md could not verify the local destination rebind. This imported profile remains blocked."
        }
    }
}

/// Fail-closed gate shared by profile activation and every profile-scoped
/// execution surface. Reading is side-effect free; only an explicit typed
/// local rebind confirmation can remove a native profile ID.
@MainActor
final class SharedSetupV2ExecutionGate {
    nonisolated deinit {}

    nonisolated static let blockedExecutionMessage =
        "This imported profile is blocked until its destination is explicitly rebound in Health.md."

    private let userDefaults: UserDefaults
    private let verificationOverride: (() -> Bool)?

    init(
        userDefaults: UserDefaults = .standard,
        verificationOverride: (() -> Bool)? = nil
    ) {
        self.userDefaults = userDefaults
        self.verificationOverride = verificationOverride
    }

    /// Corrupt blocked-ID storage denies every profile rather than treating
    /// the gate as empty. A valid absent key means no v2 profiles are blocked.
    func isExecutionBlocked(profileID: UUID) -> Bool {
        switch blockedIDsResult() {
        case .success(let ids):
            return ids.contains(profileID)
        case .failure:
            return userDefaults.object(
                forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
            ) != nil
        }
    }

    func requireExecutionAllowed(profileID: UUID) throws {
        guard !isExecutionBlocked(profileID: profileID) else {
            throw SharedSetupV2ExecutionGateError.profileRequiresRebind
        }
    }

    /// Removes one blocked ID only after the confirmation type exactly agrees
    /// with the retained source destination. Concrete binding existence and
    /// credential/pairing proof are checked by the native coordinator before
    /// this low-level commit.
    @discardableResult
    func confirmRebind(
        profileID: UUID,
        confirmation: SharedSetupV2RebindConfirmation
    ) throws -> Bool {
        let oldData: Data?
        let blocked: [UUID]
        do {
            oldData = try rawDataOrAbsence(
                forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
            )
            blocked = try oldData.map(
                SharedSetupV2ProfileTransaction.decodeBlockedProfileIDs
            ) ?? []
        } catch {
            throw SharedSetupV2ExecutionGateError.invalidState
        }
        guard blocked.contains(profileID) else { return false }

        let sidecar: SharedSetupV2AppleProfileState
        do {
            guard let sidecarData = try rawDataOrAbsence(
                forKey: SharedSetupV2ProfileTransaction.profileStateKey
            ) else {
                throw SharedSetupV2ExecutionGateError.invalidState
            }
            sidecar = try SharedSetupV2ProfileTransaction.decodeProfileState(sidecarData)
        } catch let error as SharedSetupV2ExecutionGateError {
            throw error
        } catch {
            throw SharedSetupV2ExecutionGateError.invalidState
        }
        guard let row = sidecar.profiles.first(where: { $0.profileID == profileID }) else {
            throw SharedSetupV2ExecutionGateError.invalidState
        }

        switch (row.sourceProfile.destination.kind, confirmation) {
        case (.deviceFolder, .deviceFolder):
            break
        case (.apiEndpoint, .apiEndpoint(_, let credentialsConfirmed)):
            guard credentialsConfirmed else {
                throw SharedSetupV2ExecutionGateError.rebindNotConfirmed
            }
        case (.connectedMac, .connectedMac(let pairingConfirmed)):
            guard pairingConfirmed else {
                throw SharedSetupV2ExecutionGateError.rebindNotConfirmed
            }
        case (.cloud, _):
            throw SharedSetupV2ExecutionGateError.cloudUnsupported
        default:
            throw SharedSetupV2ExecutionGateError.rebindNotConfirmed
        }

        let remainingSet = Set(blocked).subtracting([profileID])
        let remaining = sidecar.profiles.map(\.profileID).filter(remainingSet.contains)
        let encoded: Data
        do {
            encoded = try SharedSetupV2ProfileTransaction.encodeBlockedProfileIDs(remaining)
        } catch {
            throw SharedSetupV2ExecutionGateError.persistenceVerificationFailed
        }

        userDefaults.set(
            encoded,
            forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
        )
        _ = userDefaults.synchronize()
        let didVerify = userDefaults.data(
            forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
        ) == encoded && (verificationOverride?() ?? true)
        guard didVerify else {
            if let oldData {
                userDefaults.set(
                    oldData,
                    forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
                )
            } else {
                userDefaults.removeObject(
                    forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
                )
            }
            _ = userDefaults.synchronize()
            guard rawDataOrNil(
                forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
            ) == oldData else {
                throw SharedSetupV2ExecutionGateError.invalidState
            }
            throw SharedSetupV2ExecutionGateError.persistenceVerificationFailed
        }
        return true
    }

    private func blockedIDsResult() -> Result<Set<UUID>, Error> {
        do {
            guard let data = try rawDataOrAbsence(
                forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
            ) else {
                return .success([])
            }
            return .success(Set(
                try SharedSetupV2ProfileTransaction.decodeBlockedProfileIDs(data)
            ))
        } catch {
            return .failure(error)
        }
    }

    private func rawDataOrAbsence(forKey key: String) throws -> Data? {
        guard let object = userDefaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else {
            throw SharedSetupV2ExecutionGateError.invalidState
        }
        return data
    }

    private func rawDataOrNil(forKey key: String) -> Data? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.data(forKey: key)
    }
}
