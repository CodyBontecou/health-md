import Foundation

/// What a scheduled automation does when a new occurrence fires while an
/// earlier occurrence of the same automation is still running.
///
/// Different automations never wait on each other through this policy; it
/// only orders runs of one profile. Local-folder runs are additionally
/// serialized across profiles by the scheduler's folder gate.
enum ProfileRunOverlapPolicy: String, Codable, CaseIterable, Sendable {
    /// Wait for the running occurrence to finish, then run.
    case queue
    /// Drop the new occurrence; the next due evaluation picks up any days it missed.
    case skip

    static let `default`: ProfileRunOverlapPolicy = .queue
}

/// Device-local overlap choices keyed by profile ID.
///
/// Kept outside `ExportProfile` so the shared-setup format and profile
/// encoding stay unchanged; a policy for a deleted profile is inert.
struct ProfileRunOverlapPolicyStore: Sendable {
    static let defaultsKey = "profileRunOverlapPolicies"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func policy(for profileID: UUID) -> ProfileRunOverlapPolicy {
        guard let raw = stored()[profileID.uuidString],
              let policy = ProfileRunOverlapPolicy(rawValue: raw) else {
            return .default
        }
        return policy
    }

    func setPolicy(_ policy: ProfileRunOverlapPolicy, for profileID: UUID) {
        var values = stored()
        if policy == .default {
            values.removeValue(forKey: profileID.uuidString)
        } else {
            values[profileID.uuidString] = policy.rawValue
        }
        defaults.set(values, forKey: Self.defaultsKey)
    }

    private func stored() -> [String: String] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }
}

/// Tracks which profiles have an occurrence running and applies the policy.
@MainActor
final class ProfileRunOverlapGate {
    enum Admission: Equatable {
        case run
        case skip
    }

    private var gates: [UUID: AsyncSemaphore] = [:]
    private var running: [UUID: Int] = [:]

    /// Admits a run for `profileID`. With `.queue` this suspends until earlier
    /// runs of the same profile finish. Pair every `.run` with `finish(_:)`.
    func admit(_ profileID: UUID, policy: ProfileRunOverlapPolicy) async -> Admission {
        if policy == .skip, running[profileID, default: 0] > 0 {
            return .skip
        }
        running[profileID, default: 0] += 1
        let gate = gates[profileID] ?? AsyncSemaphore()
        gates[profileID] = gate
        await gate.acquire()
        return .run
    }

    func finish(_ profileID: UUID) async {
        guard let gate = gates[profileID] else { return }
        let remaining = max(0, running[profileID, default: 1] - 1)
        running[profileID] = remaining == 0 ? nil : remaining
        await gate.release()
    }

    func isRunning(_ profileID: UUID) -> Bool {
        running[profileID, default: 0] > 0
    }
}
