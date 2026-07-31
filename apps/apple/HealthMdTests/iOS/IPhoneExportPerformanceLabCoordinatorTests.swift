#if DEBUG && os(iOS)
import XCTest
@testable import HealthMd

final class IPhoneExportPerformanceLabCoordinatorTests: XCTestCase {
    func testParsesAllowlistedRunAndEndLinks() throws {
        let binding = String(repeating: "a", count: 64)
        let control = String(repeating: "b", count: 64)
        let runURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/run?run=direct-files-abc123&target=direct-files&scenario=saved-full&binding=\(binding)&mode=autonomous&control=\(control)"
        ))
        XCTAssertEqual(
            IPhoneExportPerformanceLabCoordinator.parse(url: runURL),
            .run(IPhoneExportPerformanceLabCoordinator.Request(
                runID: "direct-files-abc123",
                target: .directFiles,
                scenario: .savedFull,
                binding: binding,
                controlProof: control,
                proof: nil,
                expectedMacInstallationID: nil,
                isAutonomous: true
            ))
        )

        let setupURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/setup-api?binding=\(binding)"
        ))
        XCTAssertEqual(
            IPhoneExportPerformanceLabCoordinator.parse(url: setupURL),
            .setupAPI(binding: binding)
        )

        let endURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/end?run=direct-files-abc123"
        ))
        XCTAssertEqual(
            IPhoneExportPerformanceLabCoordinator.parse(url: endURL),
            .end(runID: "direct-files-abc123")
        )
        let cleanupURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/cleanup?run=direct-files-abc123&target=direct-files&binding=\(binding)"
        ))
        XCTAssertEqual(
            IPhoneExportPerformanceLabCoordinator.parse(url: cleanupURL),
            .cleanup(
                runID: "direct-files-abc123",
                target: .directFiles,
                binding: binding
            )
        )
    }

    func testThirtyDayScenarioIsDirectFilesOnly() throws {
        let binding = String(repeating: "a", count: 64)
        let control = String(repeating: "b", count: 64)
        let directURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/run?run=direct-files-thirty&target=direct-files&scenario=thirty-day&binding=\(binding)&mode=autonomous&control=\(control)"
        ))
        guard case .run(let request) = IPhoneExportPerformanceLabCoordinator.parse(url: directURL) else {
            return XCTFail("Expected the fixed direct-files thirty-day scenario")
        }
        XCTAssertEqual(request.scenario, .thirtyDay)
        XCTAssertEqual(request.target, .directFiles)

        let apiURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/run?run=api-thirty&target=api-endpoint&scenario=thirty-day&binding=\(binding)&mode=autonomous&control=\(control)&proof=\(control)"
        ))
        XCTAssertNil(IPhoneExportPerformanceLabCoordinator.parse(url: apiURL))

        for value in [
            "healthmd://export-lab/run?run=raw-wrong&target=direct-raw&scenario=lossless-dense&binding=\(binding)&mode=autonomous&control=\(control)",
            "healthmd://export-lab/run?run=files-wrong&target=direct-files&scenario=saved-full-provider-enabled&binding=\(binding)&mode=autonomous&control=\(control)",
            "healthmd://export-lab/run?run=local-wrong&target=local-iphone&scenario=raw-full&binding=\(binding)&mode=autonomous&control=\(control)",
        ] {
            XCTAssertNil(IPhoneExportPerformanceLabCoordinator.parse(
                url: try XCTUnwrap(URL(string: value))
            ))
        }
    }

    func testAPISetupRequiresExistingSecretMatchAfterInitialConfirmation() {
        XCTAssertEqual(
            IPhoneExportPerformanceLabCoordinator.apiSetupAuthenticationToken(
                existingToken: "",
                stagedToken: "initial-secret"
            ),
            "initial-secret"
        )
        XCTAssertEqual(
            IPhoneExportPerformanceLabCoordinator.apiSetupAuthenticationToken(
                existingToken: "existing-secret",
                stagedToken: "existing-secret"
            ),
            "existing-secret"
        )
        XCTAssertNil(
            IPhoneExportPerformanceLabCoordinator.apiSetupAuthenticationToken(
                existingToken: "existing-secret",
                stagedToken: "attacker-secret"
            )
        )
    }

    func testRejectsArbitraryCommandsPathsSettingsAndDuplicateKeys() throws {
        let invalidURLs = [
            "healthmd://export-lab/run?run=../../private&target=direct-files&scenario=saved-full",
            "healthmd://export-lab/run?run=safe&target=shell&scenario=saved-full",
            "healthmd://export-lab/run?run=safe&target=direct-files&scenario=private-date",
            "healthmd://export-lab/run?run=safe&target=direct-files&scenario=saved-full&binding=short",
            "healthmd://export-lab/run?run=safe&target=api-endpoint&scenario=saved-full&binding=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "healthmd://export-lab/setup-api?binding=short",
            "healthmd://export-lab/setup-local?binding=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&path=/tmp",
            "healthmd://export-lab/run?run=safe&target=direct-files&scenario=saved-full&binding=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&path=/tmp",
            "healthmd://export-lab/run?run=safe&run=other&target=direct-files&scenario=saved-full",
            "healthmd://export-lab/delete?run=safe",
            "healthmd://export-lab/cleanup?run=safe&target=shell",
            "healthmd://export-lab/cleanup?run=safe&target=local-iphone&path=/tmp"
        ]
        for value in invalidURLs {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(
                IPhoneExportPerformanceLabCoordinator.parse(url: url),
                "Unexpectedly accepted \(value)"
            )
        }
    }
}
#endif
