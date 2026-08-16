import Foundation

/// Fail-closed rollout boundary for additive Health.md Practice functionality.
///
/// Compiling future Practice code into an app is necessary but never sufficient to expose it.
/// A separately governed qualification attestation must also match the reviewed gate version.
/// The production app intentionally supplies no attestation today, so existing local-first,
/// account-free behavior is unchanged.
nonisolated struct PracticeFeaturePolicy: Equatable, Sendable {
    static let qualificationVersion = "practice-v1-qualified"

    let compiledIn: Bool
    let qualificationAttested: Bool

    var isEnabled: Bool { compiledIn && qualificationAttested }

    static var current: PracticeFeaturePolicy {
        PracticeFeaturePolicy(
            compiledIn: compileTimeIncluded,
            qualificationAttested: qualificationIsValid(nil)
        )
    }

    static func resolve(
        compiledInValue: String?,
        qualificationValue: String?
    ) -> PracticeFeaturePolicy {
        PracticeFeaturePolicy(
            compiledIn: compiledInValue == "included",
            qualificationAttested: qualificationIsValid(qualificationValue)
        )
    }

    private static func qualificationIsValid(_ value: String?) -> Bool {
        value == qualificationVersion
    }

    private static var compileTimeIncluded: Bool {
#if HEALTHMD_PRACTICE_COMPILED_IN
        true
#else
        false
#endif
    }
}
