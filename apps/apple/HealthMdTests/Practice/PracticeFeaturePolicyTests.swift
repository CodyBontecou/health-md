import XCTest
@testable import HealthMd

final class PracticeFeaturePolicyTests: XCTestCase {
    func testDefaultProductionPolicyIsDisabled() {
        XCTAssertFalse(PracticeFeaturePolicy.current.isEnabled)
    }

    func testMissingUnknownOrPartialGateInputsFailClosed() {
        let inputs: [(String?, String?)] = [
            (nil, nil),
            ("included", nil),
            (nil, PracticeFeaturePolicy.qualificationVersion),
            ("true", PracticeFeaturePolicy.qualificationVersion),
            ("included", "approved"),
            ("INCLUDED", PracticeFeaturePolicy.qualificationVersion),
        ]

        for (compiled, qualification) in inputs {
            XCTAssertFalse(
                PracticeFeaturePolicy.resolve(
                    compiledInValue: compiled,
                    qualificationValue: qualification
                ).isEnabled
            )
        }
    }

    func testBothExactGatesAreRequired() {
        XCTAssertTrue(
            PracticeFeaturePolicy.resolve(
                compiledInValue: "included",
                qualificationValue: PracticeFeaturePolicy.qualificationVersion
            ).isEnabled
        )
    }
}
