import Foundation
import XCTest
@testable import HealthMd

final class SharedSetupV2CanonicalIOTests: XCTestCase {
    func testCanonicalEncodingIsCompactSortedUTF8WithExactlyOneTrailingLFAndRoundTrips() throws {
        let document = try SharedSetupV2Codec.decode(
            Data(contentsOf: fixtureURL("apple-shared-setup-v2.json"))
        )

        let encoded = try SharedSetupV2Codec.encode(document)
        let body = encoded.dropLast()

        XCTAssertEqual(encoded.last, 0x0A)
        XCTAssertNotEqual(body.last, 0x0A)
        XCTAssertFalse(body.contains(0x0A))
        XCTAssertFalse(body.contains(0x0D))
        XCTAssertEqual(try SharedSetupV2Codec.decode(encoded), document)
        XCTAssertEqual(try SharedSetupV2Codec.encode(document), encoded)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var canonical = try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        canonical.append(0x0A)
        XCTAssertEqual(encoded, canonical)
        XCTAssertEqual(root["schema_version"] as? Int, 2)
    }

    func testVersionedDecodeRetainsExactV1AndV2ByteLimits() throws {
        let v1 = try Data(contentsOf: v1FixtureURL())
        let v1AtMaximum = padded(v1, to: SharedSetupV1.maximumEncodedBytes)

        guard case .v1 = try SharedSetupVersionedCodec.decode(v1AtMaximum) else {
            return XCTFail("Expected v1 at its exact byte limit")
        }
        var v1OverMaximum = v1AtMaximum
        v1OverMaximum.append(0x20)
        XCTAssertThrowsError(try SharedSetupVersionedCodec.decode(v1OverMaximum)) { error in
            XCTAssertEqual(error as? SharedSetupError, .oversized)
        }

        let v2 = try Data(contentsOf: fixtureURL("apple-shared-setup-v2.json"))
        let v2NearMaximum = padded(v2, to: SharedSetupV2.maximumEncodedBytes - 1)
        let v2AtMaximum = padded(v2, to: SharedSetupV2.maximumEncodedBytes)

        guard case .v2 = try SharedSetupVersionedCodec.decode(v2NearMaximum) else {
            return XCTFail("Expected v2 immediately below its byte limit")
        }
        guard case .v2 = try SharedSetupVersionedCodec.decode(v2AtMaximum) else {
            return XCTFail("Expected v2 at its exact byte limit")
        }
        var v2OverMaximum = v2AtMaximum
        v2OverMaximum.append(0x20)
        XCTAssertThrowsError(try SharedSetupVersionedCodec.decode(v2OverMaximum)) { error in
            XCTAssertEqual(
                error as? SharedSetupV2Error,
                .oversized(maximumBytes: SharedSetupV2.maximumEncodedBytes)
            )
        }
    }

    func testV2CanonicalEncoderCountsTrailingLFInsideFourMiBBound() throws {
        var document = try SharedSetupV2Codec.decode(
            Data(contentsOf: fixtureURL("apple-shared-setup-v2.json"))
        )
        let sourceProfiles = document.profiles
        document.profiles = (0..<72).map { offset in
            var profile = sourceProfiles[offset % sourceProfiles.count]
            profile.bundleID = String(format: "profile-%03d", offset + 1)
            profile.name = "Boundary Profile \(offset + 1)"
            profile.presentation.markdown.customText = ""
            return profile
        }
        document.activeProfile = "profile-001"

        let targetJSONBytes = SharedSetupV2.maximumEncodedBytes - 1
        let baselineBytes = try canonicalJSONWithoutLF(document).count
        XCTAssertLessThan(baselineBytes, targetJSONBytes)

        var remaining = targetJSONBytes - baselineBytes
        for index in document.profiles.indices where remaining > 0 {
            let count = min(65_536, remaining)
            document.profiles[index].presentation.markdown.customText = String(
                repeating: "x",
                count: count
            )
            remaining -= count
        }
        XCTAssertEqual(remaining, 0, "The synthetic profiles must have enough bounded text capacity")
        XCTAssertEqual(try canonicalJSONWithoutLF(document).count, targetJSONBytes)

        let encoded = try SharedSetupV2Codec.encode(document)
        XCTAssertEqual(encoded.count, SharedSetupV2.maximumEncodedBytes)
        XCTAssertEqual(encoded.last, 0x0A)
        XCTAssertEqual(try SharedSetupV2Codec.decode(encoded), document)

        var overflow = document
        let expandableIndex = try XCTUnwrap(
            overflow.profiles.firstIndex {
                $0.presentation.markdown.customText.unicodeScalars.count < 65_536
            }
        )
        overflow.profiles[expandableIndex].presentation.markdown.customText.append("x")
        XCTAssertEqual(
            try canonicalJSONWithoutLF(overflow).count,
            SharedSetupV2.maximumEncodedBytes
        )
        XCTAssertThrowsError(try SharedSetupV2Codec.encode(overflow)) { error in
            XCTAssertEqual(
                error as? SharedSetupV2Error,
                .oversized(maximumBytes: SharedSetupV2.maximumEncodedBytes)
            )
        }
    }

    func testVersionedEncoderDelegatesWithoutChangingV1Bytes() throws {
        let source = try SharedSetupCodec.decode(Data(contentsOf: v1FixtureURL()))

        XCTAssertEqual(
            try SharedSetupVersionedCodec.encode(.v1(source)),
            try SharedSetupCodec.encode(source)
        )
    }

    private func canonicalJSONWithoutLF(_ document: SharedSetupV2) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    private func padded(_ data: Data, to byteCount: Int) -> Data {
        precondition(data.count <= byteCount)
        var result = data
        result.append(Data(repeating: 0x20, count: byteCount - data.count))
        return result
    }

    private func fixtureURL(_ name: String) throws -> URL {
        try repositoryFileURL("packages/contracts/shared-setup/v2/fixtures/\(name)")
    }

    private func v1FixtureURL() throws -> URL {
        try repositoryFileURL(
            "packages/contracts/shared-setup/v1/fixtures/shared-setup-v1.json"
        )
    }

    private func repositoryFileURL(_ relativePath: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate \(relativePath)")
    }
}
