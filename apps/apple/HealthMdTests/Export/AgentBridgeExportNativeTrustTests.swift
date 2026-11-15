import Foundation
import HealthMdConnectionCore
import LocalAuthentication
import Security
import XCTest
#if canImport(HealthMd)
@testable import HealthMd
#else
@testable import AgentBridgeRequestSettingsHarness
#endif

final class AgentBridgeExportNativeTrustTests: XCTestCase {
    func testLoadsExactLegacyWriterBytesFromOnlyTheFixedNoninteractivePairingRecord() throws {
        let data = try NativeTrustFixture.encoded()
        let lookup = NativeTrustLookup(data: data)
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let snapshot = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        XCTAssertEqual(snapshot.ownerInstallationID, NativeTrustFixture.owner)
        XCTAssertEqual(snapshot.trustedMacInstallationID, NativeTrustFixture.hostID)
        XCTAssertEqual(snapshot.host, "192.0.2.40")
        XCTAssertEqual(snapshot.port, 17647)
        XCTAssertEqual(snapshot.displayName, "Synthetic CLI")
        XCTAssertEqual(snapshot.reconnectSecret, Data(0..<32))
        XCTAssertEqual(snapshot.pairedAt.timeIntervalSinceReferenceDate.bitPattern, 0x41b0000000200000)
        XCTAssertEqual(lookup.calls, 1)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
        XCTAssertEqual(lookup.data, data)
    }

    func testDecodedDuplicateAndUnknownLegacyMembersCannotBecomeTypedTrust() throws {
        let text = String(decoding: try NativeTrustFixture.encoded(), as: UTF8.self)
        let cases = [
            text.replacingOccurrences(of: "\"ownerInstallationID\":", with: "\"ownerInstallationID\":\"00000000-0000-4000-8000-000000000001\",\"ownerInstallationID\":"),
            text.replacingOccurrences(of: "\"ownerInstallationID\":", with: "\"ownerInstalla\\u0074ionID\":\"00000000-0000-4000-8000-000000000001\",\"ownerInstallationID\":"),
            text.replacingOccurrences(of: "\"port\":", with: "\"port\":17647,\"po\\u0072t\":"),
            text.replacingOccurrences(of: "\"pairedAt\":", with: "\"pairedAt\":268435456.125,\"pairedAt\":"),
            text.replacingOccurrences(of: "\"trustedClients\":", with: "\"unknown\":{},\"trustedClients\":"),
            text.replacingOccurrences(of: "\"trustedClients\":", with: "\"un\\u006bnown\":0,\"trustedClients\":"),
            text.replacingOccurrences(of: "\"displayName\":", with: "\"unexpected\":true,\"displayName\":")
        ]
        for candidate in cases { assertRejected(Data(candidate.utf8)) }
    }

    func testCurrentMatchingReloadsTheOriginalAuthenticatedIdentitiesAndSecret() throws {
        let lookup = NativeTrustLookup(data: try NativeTrustFixture.encoded())
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let original = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        for _ in 0..<3 {
            XCTAssertNoThrow(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
                authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32)))
        }
        XCTAssertEqual(lookup.calls, 4)
        XCTAssertTrue(lookup.freshContexts)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
    }

    func testNativeFractionalExponentAndFiniteDateBinary64BitsArePreserved() throws {
        let values: [Double] = [-268435456.125, -0.0, 0.0, 0.125, 1.5, 5e-7, -5e-7,
                                .leastNonzeroMagnitude, .leastNormalMagnitude, .greatestFiniteMagnitude]
        for seconds in values {
            let bytes = try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner,
                trustedMac: NativeTrustFixture.mac(pairedAt: Date(timeIntervalSinceReferenceDate: seconds))))
            let lookup = NativeTrustLookup(data: bytes)
            let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
            let snapshot = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
            XCTAssertEqual(snapshot.pairedAt.timeIntervalSinceReferenceDate.bitPattern, seconds.bitPattern)
            XCTAssertEqual(lookup.data, bytes)
            XCTAssertEqual(lookup.calls, 1)
        }
    }

    func testCleanMissingAndExistingUnpairedStateReturnAbsenceWithoutFallback() throws {
        let lookup = NativeTrustLookup(data: try NativeTrustFixture.encoded())
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        lookup.respond(status: errSecItemNotFound, result: nil)
        XCTAssertNil(try reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        let unpaired = try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner))
        lookup.respond(result: [NativeTrustLookup.record(data: unpaired)] as CFArray)
        XCTAssertNil(try reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        XCTAssertEqual(lookup.calls, 2)
        XCTAssertTrue(lookup.freshContexts)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
    }

    func testNativeDenialAndContradictoryAbsenceHaveOnlyFixedSanitizedFailures() throws {
        let bytes = try NativeTrustFixture.encoded()
        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable, errSecDecode,
                       errSecDuplicateItem, errSecUserCanceled, errSecParam, OSStatus(-1), errSecItemNotFound] {
            assertSDKRejected(status: status, result: [NativeTrustLookup.record(data: bytes)] as CFArray)
        }
        assertSDKRejected(status: errSecNotAvailable, result: nil)
    }

    func testForeignPurposeClassProtectionAndSynchronizationCannotSupplyPairingTrust() throws {
        let bytes = try NativeTrustFixture.encoded()
        let changes: [(String, Any?)] = [
            (kSecClass as String, kSecClassInternetPassword), (kSecClass as String, nil),
            (kSecAttrService as String, "com.codybontecou.obsidianhealth.manual-ip-trust"),
            (kSecAttrService as String, "com.codybontecou.obsidianhealth.agent-bridge.native-export-authority"),
            (kSecAttrService as String, nil), (kSecAttrAccount as String, "integrity-key-v1"),
            (kSecAttrAccount as String, nil), (kSecAttrAccount as String, NSNumber(value: 1)),
            (kSecAttrAccessible as String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
            (kSecAttrAccessible as String, kSecAttrAccessibleWhenUnlocked),
            (kSecAttrAccessible as String, kSecAttrAccessibleAfterFirstUnlock),
            (kSecAttrAccessible as String, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly),
            (kSecAttrAccessible as String, "unknown"), (kSecAttrAccessible as String, nil),
            (kSecAttrSynchronizable as String, true), (kSecAttrSynchronizable as String, nil),
            (kSecAttrSynchronizable as String, NSNumber(value: 0)), (kSecAttrSynchronizable as String, "false"),
            (kSecAttrIsNegative as String, true), (kSecAttrIsNegative as String, NSNumber(value: 0))
        ]
        for (attribute, value) in changes {
            var record = NativeTrustLookup.record(data: bytes); record[attribute] = value
            assertSDKRejected(result: [record] as CFArray)
        }
    }

    func testAmbiguousMalformedAndNonDataSDKResultsFailClosed() throws {
        let bytes = try NativeTrustFixture.encoded(), record = NativeTrustLookup.record(data: try NativeTrustFixture.encoded())
        for result in [nil, bytes as CFData, record as CFDictionary, [] as CFArray,
                       [record, record] as CFArray, [record, record, record] as CFArray, ["invalid"] as CFArray] as [CFTypeRef?] {
            assertSDKRejected(result: result)
        }
        for value in [nil, "not-data", NSNumber(value: 32), Data(), Data(repeating: 0, count: 16 * 1024 + 1)] as [Any?] {
            var damaged = record; damaged[kSecValueData as String] = value
            assertSDKRejected(result: [damaged] as CFArray)
        }
    }

    func testForeignOwnerProvisionalPairingAndServerSideClientsNeverEstablishTrust() throws {
        assertRejected(try NativeTrustFixture.encoded(), owner: NativeTrustFixture.otherID)
        assertRejected(try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.otherID)))
        for committed in [nil, NativeTrustFixture.mac()] as [ManualIPTrustedMac?] {
            assertRejected(try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner,
                trustedMac: committed, provisionalTrustedMac: NativeTrustFixture.mac())))
        }
        let client = ManualIPTrustedClient(installationID: NativeTrustFixture.otherID, displayName: "Synthetic Client",
            reconnectSecret: Data(repeating: 11, count: 32), pairedAt: Date(timeIntervalSinceReferenceDate: 1),
            lastConnectedAt: Date(timeIntervalSinceReferenceDate: 2))
        assertRejected(try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner,
            trustedMac: NativeTrustFixture.mac(), trustedClients: [client])))
    }

    func testMissingNullBooleanAndWrongLegacyTypesAreRejected() throws {
        let text = String(decoding: try NativeTrustFixture.encoded(), as: UTF8.self)
        for field in ["ownerInstallationID", "trustedClients", "trustedMac", "installationID", "displayName", "host", "port", "reconnectSecret", "pairedAt"] {
            for replacement in ["null", "true", "false", "[]"] where field != "trustedClients" || replacement != "[]" {
                assertRejected(Data(try replacingField(field, in: text, with: replacement).utf8))
            }
        }
        for field in ["ownerInstallationID", "trustedClients", "installationID", "displayName", "host", "port", "reconnectSecret", "pairedAt"] {
            assertRejected(Data(try removingField(field, from: text).utf8))
        }
        for field in ["displayName", "host"] {
            for value in ["\"\"", "\"   \"", "\"bad\\u0000text\"", "17", "{}"] {
                assertRejected(Data(try replacingField(field, in: text, with: value).utf8))
            }
        }
        for field in ["ownerInstallationID", "installationID"] {
            assertRejected(Data(try replacingField(field, in: text, with: "\"not-a-native-uuid\"").utf8))
        }
    }

    func testInvalidUTF8UnpairedUnicodeAndNonObjectInputsCannotBecomeTrust() throws {
        let text = String(decoding: try NativeTrustFixture.encoded(), as: UTF8.self)
        for raw in ["\"\\uD800\"", "\"\\uDC00\"", "\"\\uD800\\u0041\"", "\"\\uD800x\"", "\"\\uZZZZ\"", "\"\\x20\""] {
            assertRejected(Data(try replacingField("displayName", in: text, with: raw).utf8))
        }
        for bytes in [[0xff], [0xc0, 0xaf], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80]] as [[UInt8]] {
            assertRejected(Data(bytes) + Data(text.utf8))
        }
        for raw in ["null", "true", "1", "\"state\"", "[]", "{}", text + "{}", String(text.dropLast()),
                    text.replacingOccurrences(of: "\"trustedClients\":[]", with: "\"trustedClients\":[{}]")] {
            assertRejected(Data(raw.utf8))
        }
    }

    func testValidEscapesUnicodeWhitespaceAndNativeExponentNumbersAreNotRewritten() throws {
        let text = String(decoding: try NativeTrustFixture.encoded(), as: UTF8.self)
        let escapedKeys = text.replacingOccurrences(of: "\"ownerInstallationID\"", with: "\"ownerInstalla\\u0074ionID\"")
            .replacingOccurrences(of: "\"port\"", with: "\"po\\u0072t\"")
        let named = try replacingField("displayName", in: escapedKeys, with: "\"CLI e\\u0301 / \\uD83D\\uDE80 \\\"quoted\\\" \\\\text\"")
        let bytes = Data((" \n\t" + (try replacingField("pairedAt", in: named, with: "2.68435456125e+8")) + "\r\n").utf8)
        let lookup = NativeTrustLookup(data: bytes)
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let snapshot = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        XCTAssertEqual(Array(snapshot.displayName.unicodeScalars).map(\.value),
                       [67, 76, 73, 32, 101, 769, 32, 47, 32, 128640, 32, 34, 113, 117, 111, 116, 101, 100, 34, 32, 92, 116, 101, 120, 116])
        XCTAssertEqual(snapshot.pairedAt.timeIntervalSinceReferenceDate.bitPattern, 0x41b0000000200000)
        XCTAssertEqual(lookup.data, bytes)
        XCTAssertEqual(lookup.calls, 1)
    }

    func testRecordStringNumericAndFixedShapeBoundsNeverClipOrNormalize() throws {
        let original = try NativeTrustFixture.encoded()
        let padded = original + Data(repeating: 0x20, count: 16 * 1024 - original.count)
        let lookup = NativeTrustLookup(data: padded)
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        XCTAssertNotNil(try reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        assertRejected(padded + Data([0x20]))
        let text = String(decoding: original, as: UTF8.self)
        for scalar in ["é", "🚀"] {
            let valid = try replacingField("displayName", in: text, with: "\"" + String(repeating: scalar, count: 1024) + "\"")
            let bounded = NativeTrustLookup(data: Data(valid.utf8))
            XCTAssertNotNil(try AgentBridgeExportNativeTrust(copyMatching: { bounded.copyMatching($0, $1) })
                .loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
            assertRejected(Data(try replacingField("displayName", in: text, with: "\"" + String(repeating: scalar, count: 1025) + "\"").utf8))
        }
        let exactNumber = "0." + String(repeating: "0", count: 62)
        let numeric = NativeTrustLookup(data: Data(try replacingField("pairedAt", in: text, with: exactNumber).utf8))
        XCTAssertEqual(try AgentBridgeExportNativeTrust(copyMatching: { numeric.copyMatching($0, $1) })
            .loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner)?.pairedAt.timeIntervalSinceReferenceDate, 0)
        assertRejected(Data(try replacingField("pairedAt", in: text, with: exactNumber + "0").utf8))
        assertRejected(Data(try replacingField("trustedMac", in: text, with: String(repeating: "[", count: 4000) + "0" + String(repeating: "]", count: 4000)).utf8))
    }

    func testNonfiniteMalformedDatesPortsAndCredentialEncodingsFailClosed() throws {
        let text = String(decoding: try NativeTrustFixture.encoded(), as: UTF8.self)
        for number in ["1e309", "-1e309", "NaN", "Infinity", "\"NaN\"", "\"268435456.125\"", "01", "+1", "1.", ".5", "1e", "1e+"] {
            assertRejected(Data(try replacingField("pairedAt", in: text, with: number).utf8))
        }
        for port in ["-1", "65536", "17647.0", "1.7647e4", "\"17647\""] {
            assertRejected(Data(try replacingField("port", in: text, with: port).utf8))
        }
        for size in [0, 16, 31, 33, 64] {
            assertRejected(try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner,
                trustedMac: NativeTrustFixture.mac(secret: Data(repeating: 7, count: size)))))
        }
        for base64 in ["!", "AA==", Data(0..<32).base64EncodedString() + "=",
                       Data(0..<32).base64EncodedString().replacingOccurrences(of: "Hh8=", with: "Hh9=")] {
            assertRejected(Data(try replacingField("reconnectSecret", in: text, with: "\"" + base64 + "\"").utf8))
        }
    }

    func testLegacyNearbyWriterEndpointSentinelIsNativeMetadataNotChannelAuthority() throws {
        // DirectNearbyClient uses this SAME iPhone store and authenticates with host nearby/port0.
        // Reader preserves the actual UInt16 writer shape; future adapters own transport admission.
        for port: UInt16 in [0, 65535] {
            var mac = NativeTrustFixture.mac(); mac.host = "nearby"; mac.port = port
            let bytes = try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner, trustedMac: mac))
            let lookup = NativeTrustLookup(data: bytes)
            let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
            let original = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
            XCTAssertEqual(original.host, "nearby")
            XCTAssertEqual(original.port, port)
            XCTAssertNoThrow(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
                authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32)))
            XCTAssertEqual(lookup.calls, 2)
        }
    }

    func testWrongAuthenticatedSourceHostOrOriginalSecretAlwaysRejectFreshMatching() throws {
        let lookup = NativeTrustLookup(data: try NativeTrustFixture.encoded())
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let original = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        for (source, host) in [(NativeTrustFixture.otherID, NativeTrustFixture.hostID),
                               (NativeTrustFixture.owner, NativeTrustFixture.otherID)] {
            XCTAssertThrowsError(try reader.requireCurrent(original: original, nativeSourceInstallationID: source,
                authenticatedHostInstallationID: host, originalReconnectSecret: Data(0..<32))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        }
        var firstWrong = Data(0..<32); firstWrong[0] ^= 1
        var lastWrong = Data(0..<32); lastWrong[31] ^= 1
        for secret in [firstWrong, lastWrong, Data(), Data(repeating: 7, count: 31), Data(repeating: 7, count: 33), Data(repeating: 7, count: 65536)] {
            XCTAssertThrowsError(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
                authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: secret)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        }
        XCTAssertEqual(lookup.calls, 9)
        XCTAssertTrue(lookup.freshContexts)
    }

    func testSameIDReplacementNewPairingDateAndRemovalCannotRetargetTheOriginal() throws {
        let bytes = try NativeTrustFixture.encoded(), lookup = NativeTrustLookup(data: bytes)
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let original = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        let replacements = [
            try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner,
                trustedMac: NativeTrustFixture.mac(secret: Data(repeating: 12, count: 32)))),
            try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner,
                trustedMac: NativeTrustFixture.mac(pairedAt: Date(timeIntervalSinceReferenceDate: 268435456.125.nextUp)))),
            try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner,
                trustedMac: .init(installationID: NativeTrustFixture.otherID, displayName: "Synthetic CLI", host: "192.0.2.40", port: 17647,
                                 reconnectSecret: Data(0..<32), pairedAt: Date(timeIntervalSinceReferenceDate: 268435456.125)))),
            try NativeTrustFixture.encoded(.init(ownerInstallationID: NativeTrustFixture.owner))
        ]
        for replacement in replacements {
            lookup.respond(result: [NativeTrustLookup.record(data: replacement)] as CFArray)
            XCTAssertThrowsError(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
                authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        }
        lookup.respond(result: [NativeTrustLookup.record(data: replacements[0])] as CFArray)
        XCTAssertThrowsError(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
            authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(repeating: 12, count: 32))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        lookup.respond(status: errSecItemNotFound, result: nil)
        XCTAssertThrowsError(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
            authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        lookup.respond(result: [NativeTrustLookup.record(data: bytes)] as CFArray)
        // Explicit limitation: restoring a valid old native record is NOT privileged anti-rollback.
        XCTAssertNoThrow(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
            authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32)))
        XCTAssertEqual(lookup.calls, 8)
        XCTAssertTrue(lookup.freshContexts)
    }

    func testOriginalSnapshotRejectsSameIdentityMetadataChangesAndByteOnlyRewrites() throws {
        let bytes = try NativeTrustFixture.encoded(), lookup = NativeTrustLookup(data: bytes)
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let original = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        let text = String(decoding: bytes, as: UTF8.self)
        let replacements = [
            Data(text.replacingOccurrences(of: "Synthetic CLI", with: "Another Synthetic CLI").utf8),
            Data(text.replacingOccurrences(of: "192.0.2.40", with: "192.0.2.41").utf8),
            Data(text.replacingOccurrences(of: "17647", with: "17648").utf8),
            bytes + Data([0x20]), // Semantically identical valid legacy JSON, DIFFERENT original bytes.
            Data(text.replacingOccurrences(of: "268435456.125", with: "2.68435456125e8").utf8)
        ]
        for replacement in replacements {
            XCTAssertNotEqual(replacement, bytes)
            lookup.respond(result: [NativeTrustLookup.record(data: replacement)] as CFArray)
            let newSnapshot = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
            XCTAssertEqual(newSnapshot.trustedMacInstallationID, original.trustedMacInstallationID)
            XCTAssertEqual(newSnapshot.reconnectSecret, original.reconnectSecret)
            XCTAssertEqual(newSnapshot.pairedAt.timeIntervalSinceReferenceDate.bitPattern, original.pairedAt.timeIntervalSinceReferenceDate.bitPattern)
            XCTAssertThrowsError(try reader.requireCurrent(original: original, nativeSourceInstallationID: NativeTrustFixture.owner,
                authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        }
        XCTAssertEqual(lookup.calls, 11)
        XCTAssertTrue(lookup.freshContexts)
    }

    func testSnapshotsDefensivelyCopyCredentialsAndNeverFormatOrReflectThem() throws {
        let lookup = NativeTrustLookup(data: try NativeTrustFixture.encoded())
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let snapshot = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        var exposed = snapshot.reconnectSecret; exposed[0] ^= 1
        XCTAssertEqual(snapshot.reconnectSecret, Data(0..<32))
        XCTAssertNotEqual(snapshot.reconnectSecret, exposed)
        XCTAssertEqual(String(describing: snapshot), "native_pairing_trust")
        XCTAssertEqual(String(reflecting: snapshot), "native_pairing_trust")
        XCTAssertTrue(Mirror(reflecting: snapshot).children.isEmpty)
        XCTAssertNoThrow(try reader.requireCurrent(original: snapshot, nativeSourceInstallationID: NativeTrustFixture.owner,
            authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32)))
    }

    func testDetachedFreshLookupsRemainNoninteractiveWithoutCachingAvailability() async throws {
        let lookup = NativeTrustLookup(data: try NativeTrustFixture.encoded())
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let snapshot = try await Task.detached {
            try reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner)
        }.value
        XCTAssertNotNil(snapshot)
        lookup.respond(status: errSecItemNotFound, result: nil)
        let missing = try await Task.detached { try reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner) }.value
        XCTAssertNil(missing)
        lookup.respond(status: errSecInteractionNotAllowed, result: nil)
        do {
            _ = try await Task.detached { try reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner) }.value
            XCTFail("denied lookup must fail")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(lookup.calls, 3)
        XCTAssertTrue(lookup.freshContexts)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
        XCTAssertTrue(lookup.onlyBackgroundLookups) // Synthetic SDK calls, NOT native lifecycle proof.
    }

    func testPairingNeverCreatesOrSuppliesIndependentIssuerAuthorityAndRights() throws {
        let lookup = NativeTrustLookup(data: try NativeTrustFixture.encoded())
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        let paired = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner))
        let peer = try AgentBridgePeer(sourceInstallationID: AgentBridgeUUID(paired.ownerInstallationID.uuidString.lowercased()),
            hostInstallationID: AgentBridgeUUID(paired.trustedMacInstallationID.uuidString.lowercased()), platform: .apple)
        // A DTO made from native IDs is NOT an installed authenticated channel/session context.
        let parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("healthmd-pairing-rights-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("authority"), integrityLookup = PairingIntegrityLookup()
        let integrity = AgentBridgeExportProtectedKey(copyMatching: { integrityLookup.copyMatching($0, $1) })
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore(existingDirectory: directory, protectedKeys: integrity))
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore.createPrivateStore(at: directory, protectedKeys: integrity,
            authorization: PairingNativeDecision(allowed: false))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(integrityLookup.calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        // A separately granted SYNTHETIC local initialization decision, not pairing, creates this
        // empty test ledger. Real store/files/CryptoKit execute; native human provisioning is unrun.
        let store = try AgentBridgeExportAuthorityStore.createPrivateStore(at: directory, protectedKeys: integrity,
            authorization: PairingNativeDecision(allowed: true))
        let before = try Data(contentsOf: directory.appendingPathComponent("state.json"))
        let state = try store.snapshot()
        XCTAssertEqual(state.generation, 0)
        XCTAssertTrue(state.delegations.isEmpty)
        XCTAssertTrue(state.plans.isEmpty)
        XCTAssertTrue(state.decisions.isEmpty)
        XCTAssertTrue(try state.references(peer: peer, now: AgentBridgeUTC("2026-03-09T00:00:00Z")).isEmpty)
        XCTAssertThrowsError(try state.delegation(id: AgentBridgeUUID("00000000-0000-4000-8000-000000000004"), revision: 1,
            peer: peer, now: AgentBridgeUTC("2026-03-09T00:00:00Z"))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .approvalRequired) }
        XCTAssertNoThrow(try reader.requireCurrent(original: paired, nativeSourceInstallationID: NativeTrustFixture.owner,
            authenticatedHostInstallationID: NativeTrustFixture.hostID, originalReconnectSecret: Data(0..<32)))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["lock", "state.json"])
        XCTAssertEqual(integrityLookup.calls, 2)
        XCTAssertTrue(integrityLookup.dedicatedPurpose)
    }

    func testPairingMaterialIsNotAnExportAuthorityKeyOrCrossPurposeFallback() throws {
        let lookup = NativeTrustLookup(data: try NativeTrustFixture.encoded())
        let integrity = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
        // The REAL key reader rejects the returned pairing record. No pairing-key HMAC reuse.
        XCTAssertThrowsError(try integrity.loadExistingExportAuthorityKey()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(lookup.calls, 1)
    }

    private func assertSDKRejected(status: OSStatus = errSecSuccess, result: CFTypeRef?) {
        let lookup = NativeTrustLookup(data: Data())
        lookup.respond(status: status, result: result)
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        XCTAssertThrowsError(try reader.loadExistingTrust(ownerInstallationID: NativeTrustFixture.owner)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            XCTAssertEqual(String(reflecting: $0), "permission_required")
        }
        XCTAssertEqual(lookup.calls, 1)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
    }

    private func replacingField(_ field: String, in text: String, with replacement: String) throws -> String {
        let pattern = "\"" + field + "\":" + #"(?:"(?:[^"\\]|\\.)*"|\[\]|[0-9.]+|\{[^{}]*\})"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let found = try XCTUnwrap(regex.firstMatch(in: text, range: range))
        let swiftRange = try XCTUnwrap(Range(found.range, in: text))
        return text.replacingCharacters(in: swiftRange, with: "\"" + field + "\":" + replacement)
    }
    private func removingField(_ field: String, from text: String) throws -> String {
        let replaced = try replacingField(field, in: text, with: "null")
        let token = "\"" + field + "\":null"
        if replaced.contains(token + ",") { return replaced.replacingOccurrences(of: token + ",", with: "") }
        return replaced.replacingOccurrences(of: "," + token, with: "")
    }

    private func assertRejected(_ data: Data, owner: UUID = NativeTrustFixture.owner) {
        let lookup = NativeTrustLookup(data: data)
        let reader = AgentBridgeExportNativeTrust(copyMatching: { lookup.copyMatching($0, $1) })
        XCTAssertThrowsError(try reader.loadExistingTrust(ownerInstallationID: owner)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            XCTAssertEqual(String(describing: $0), "permission_required")
        }
        XCTAssertEqual(lookup.calls, 1)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
        XCTAssertEqual(lookup.data, data)
    }
}

nonisolated private enum NativeTrustFixture {
    static let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let hostID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let otherID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static func mac(secret: Data = Data(0..<32), pairedAt: Date = Date(timeIntervalSinceReferenceDate: 268435456.125)) -> ManualIPTrustedMac {
        .init(installationID: hostID, displayName: "Synthetic CLI", host: "192.0.2.40", port: 17647,
              reconnectSecret: secret, pairedAt: pairedAt)
    }
    static func encoded(_ state: ManualIPTrustState = .init(ownerInstallationID: owner, trustedMac: mac())) throws -> Data {
        try JSONEncoder().encode(state) // EXACT legacy writer, not v4 canonicalization or a portable grant.
    }
}

nonisolated private struct PairingNativeDecision: AgentBridgeExportNativeAuthorizing {
    let allowed: Bool
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        guard allowed else { throw AgentBridgeValidationError.permissionRequired }
    }
}

/// The separate integrity-key SDK boundary; NEVER receives the pairing snapshot/credential.
nonisolated private final class PairingIntegrityLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var exactPurpose = true
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var dedicatedPurpose: Bool { lock.lock(); defer { lock.unlock() }; return exactPurpose }
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock(); defer { lock.unlock() }; count += 1
        let values = query as NSDictionary
        exactPurpose = exactPurpose
            && values[kSecAttrService] as? String == "com.codybontecou.obsidianhealth.agent-bridge.native-export-authority"
            && values[kSecAttrAccount] as? String == "integrity-key-v1"
            && (values[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == true
        result?.pointee = [[
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codybontecou.obsidianhealth.agent-bridge.native-export-authority",
            kSecAttrAccount as String: "integrity-key-v1",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: Data(repeating: 9, count: 32)
        ]] as CFArray
        return errSecSuccess
    }
}

/// SDK-signature lookup only. No credential writer, fake decoder or fake trust store on this seam.
nonisolated private final class NativeTrustLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var validQuery = true
    private var previousContext: LAContext?
    private var distinctContexts = true
    private var backgroundOnly = true
    private var status: OSStatus = errSecSuccess
    private var payload: CFTypeRef?
    let data: Data
    init(data: Data) {
        self.data = Data(Array(data))
        payload = [Self.record(data: data)] as CFArray
    }
    func respond(status: OSStatus = errSecSuccess, result: CFTypeRef?) {
        lock.lock(); defer { lock.unlock() }
        self.status = status; payload = result
    }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var exactReadOnlyQuery: Bool { lock.lock(); defer { lock.unlock() }; return validQuery }
    var freshContexts: Bool { lock.lock(); defer { lock.unlock() }; return distinctContexts }
    var onlyBackgroundLookups: Bool { lock.lock(); defer { lock.unlock() }; return backgroundOnly }
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        count += 1
        backgroundOnly = backgroundOnly && !Thread.isMainThread
        let values = query as NSDictionary
        let context = values[kSecUseAuthenticationContext] as? LAContext
        distinctContexts = distinctContexts && context != nil && context !== previousContext
        previousContext = context
        validQuery = validQuery && values.count == 9
            && values[kSecClass] as? String == kSecClassGenericPassword as String
            && values[kSecAttrService] as? String == "com.codybontecou.obsidianhealth.direct-cli-ios-trust"
            && values[kSecAttrAccount] as? String == "trust-state-v1"
            && values[kSecAttrSynchronizable] as? Bool == false
            && values[kSecUseDataProtectionKeychain] as? Bool == true
            && values[kSecReturnAttributes] as? Bool == true
            && values[kSecReturnData] as? Bool == true
            && values[kSecMatchLimit] as? Int == 2
            && context?.interactionNotAllowed == true
        result?.pointee = payload
        return status
    }
    static func record(data: Data) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codybontecou.obsidianhealth.direct-cli-ios-trust",
            kSecAttrAccount as String: "trust-state-v1",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data
        ]
    }
}
