import Foundation

/// Structured, write-free presentation facts for one profile imported by a
/// Shared Setup v2 transaction. The native identity is the fresh UUID the
/// transaction generated; the source identity and destination kind come from
/// the retained compatibility plan so review surfaces can explain exactly why
/// a generated profile is blocked without re-reading durable state.
struct SharedSetupV2ImportedProfileReview: Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceBundleID: String
    let sourceName: String
    let destinationKind: SharedSetupV2.DestinationKind
    let unsupportedSemanticIDCount: Int

    /// Rebuilds the ordered review list from one applied transaction result.
    ///
    /// The plan rows are filtered in source-document order, matching the
    /// transaction's own selection normalization, so `zip` pairs each selected
    /// plan row with its generated native identity. If the counts ever
    /// disagree, no structured claim is made at all rather than presenting a
    /// misaligned name/identity pairing.
    static func reviews(
        plan: SharedSetupV2ImportPlan,
        selectedBundleIDs: [String],
        result: SharedSetupV2TransactionResult
    ) -> [SharedSetupV2ImportedProfileReview] {
        let selected = Set(selectedBundleIDs)
        let selectedPlans = plan.profiles.filter { selected.contains($0.bundleID) }
        guard selectedPlans.count == result.importedProfileIDs.count else { return [] }
        return zip(selectedPlans, result.importedProfileIDs).map { profilePlan, nativeID in
            SharedSetupV2ImportedProfileReview(
                id: nativeID,
                sourceBundleID: profilePlan.bundleID,
                sourceName: profilePlan.name,
                destinationKind: profilePlan.destinationIntent.kind,
                unsupportedSemanticIDCount: profilePlan.unsupportedPreservedSemanticIDs.count
            )
        }
    }
}

/// Production Shared Setup v2 transaction service.
///
/// The class is intentionally pure Foundation over the SharedSetup types so
/// the synchronized Xcode project compiles it into both the iOS and macOS
/// app targets. It owns exactly two collaborators and adds no semantics of
/// its own:
///
/// - `SharedSetupV2ProfileTransaction` performs the durable, verified
///   Add/Replace apply and the one-shot exact Undo across the five-key
///   aggregate (profiles, active identity, schedules, sidecar, blocked IDs).
/// - `SharedSetupV2ExecutionGate` owns the fail-closed blocked-profile set
///   and the only verified path that can clear one blocked identity.
///
/// Both collaborators always run their production verified-persistence paths:
/// this adapter never installs a `verificationOverride` and never weakens,
/// duplicates, or bypasses the transaction's bounds, rollback, blocked, or
/// rebind-clearing behavior. Apply and Undo perform no schedule execution,
/// no destination access, no credential/Keychain read, and no network work.
@MainActor
final class SharedSetupV2TransactionAdapter {
    nonisolated deinit {}

    private let transaction: SharedSetupV2ProfileTransaction
    private let executionGate: SharedSetupV2ExecutionGate

    /// Injectable form used by tests and by any owner that must pin both
    /// collaborators to one isolated `UserDefaults` suite.
    init(
        transaction: SharedSetupV2ProfileTransaction,
        executionGate: SharedSetupV2ExecutionGate
    ) {
        self.transaction = transaction
        self.executionGate = executionGate
    }

    /// Production form: both collaborators share the supplied defaults
    /// (`.standard` by default), a common clock/calendar, and fresh identity
    /// makers, with no verification overrides.
    convenience init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        makeProfileID: @escaping () -> UUID = UUID.init,
        makeScheduleID: @escaping () -> UUID = UUID.init
    ) {
        self.init(
            transaction: SharedSetupV2ProfileTransaction(
                userDefaults: userDefaults,
                now: now,
                calendar: calendar,
                makeProfileID: makeProfileID,
                makeScheduleID: makeScheduleID
            ),
            executionGate: SharedSetupV2ExecutionGate(userDefaults: userDefaults)
        )
    }

    var canUndo: Bool { transaction.canUndo }

    @discardableResult
    func apply(
        _ plan: SharedSetupV2ImportPlan,
        selectedBundleIDs: [String],
        mode: SharedSetupV2TransactionMode
    ) throws -> SharedSetupV2TransactionResult {
        try transaction.apply(plan, selectedBundleIDs: selectedBundleIDs, mode: mode)
    }

    /// One-shot exact Undo. A second attempt fails with
    /// `SharedSetupV2TransactionError.noUndoSnapshot` and performs no writes;
    /// that honesty is preserved for callers of this adapter.
    @discardableResult
    func undo() throws -> SharedSetupV2UndoResult {
        try transaction.undo()
    }

    /// Side-effect-free blocked-profile query straight from the execution
    /// gate. Corrupt blocked state fails closed (every profile blocked).
    func isExecutionBlocked(profileID: UUID) -> Bool {
        executionGate.isExecutionBlocked(profileID: profileID)
    }

    /// The only verified path that clears one blocked imported profile. The
    /// gate checks the retained source destination kind against the typed
    /// confirmation and byte-verifies persistence; a failed verification
    /// leaves the profile blocked.
    @discardableResult
    func confirmRebind(
        profileID: UUID,
        confirmation: SharedSetupV2RebindConfirmation
    ) throws -> Bool {
        try executionGate.confirmRebind(profileID: profileID, confirmation: confirmation)
    }
}
