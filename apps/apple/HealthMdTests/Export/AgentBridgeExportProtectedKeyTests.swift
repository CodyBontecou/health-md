import CryptoKit
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

final class AgentBridgeExportProtectedKeyTests: XCTestCase {
    func testLoadsOnlyTheDedicatedDeviceLocalIntegrityRecordWithoutInteraction() throws {
        let lookup = ProtectedKeyLookup()
        let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
        let key = try XCTUnwrap(reader.loadExistingExportAuthorityKey())
        XCTAssertEqual(key.bitCount, 256)
        XCTAssertEqual(lookup.calls, 1)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
    }

    func testForeignPurposeAndRecordClassCannotSupplyIntegrityMaterial() throws {
        let changes: [(String, Any?)] = [
            (kSecClass as String, kSecClassInternetPassword),
            (kSecClass as String, nil),
            (kSecAttrService as String, "com.codybontecou.obsidianhealth.direct-cli-ios-trust"),
            (kSecAttrService as String, nil),
            (kSecAttrAccount as String, "cursor-key-v1"),
            (kSecAttrAccount as String, NSNumber(value: 1))
        ]
        for (attribute, value) in changes {
            var record = ProtectedKeyLookup.record()
            record[attribute] = value
            let lookup = ProtectedKeyLookup()
            lookup.respond(result: [record] as CFArray)
            let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
            XCTAssertThrowsError(try reader.loadExistingExportAuthorityKey()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            }
            XCTAssertEqual(lookup.calls, 1)
            XCTAssertTrue(lookup.exactReadOnlyQuery)
        }
    }

    func testOnlyExplicitNonsynchronizableWhenUnlockedDeviceLocalProtectionIsAccepted() throws {
        let changes: [(String, Any?)] = [
            (kSecAttrAccessible as String, kSecAttrAccessibleWhenUnlocked),
            (kSecAttrAccessible as String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly),
            (kSecAttrAccessible as String, kSecAttrAccessibleAfterFirstUnlock),
            (kSecAttrAccessible as String, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly),
            (kSecAttrAccessible as String, "unknown"),
            (kSecAttrAccessible as String, nil),
            (kSecAttrSynchronizable as String, true),
            (kSecAttrSynchronizable as String, nil),
            (kSecAttrSynchronizable as String, NSNumber(value: 0)),
            (kSecAttrSynchronizable as String, "false"),
            (kSecAttrIsNegative as String, true)
        ]
        for (attribute, value) in changes {
            var record = ProtectedKeyLookup.record()
            record[attribute] = value
            let lookup = ProtectedKeyLookup()
            lookup.respond(result: [record] as CFArray)
            let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
            XCTAssertThrowsError(try reader.loadExistingExportAuthorityKey()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            }
            XCTAssertEqual(lookup.calls, 1)
        }
    }

    func testMalformedAmbiguousAndWrongSizeResultsNeverSupplyAKey() throws {
        let record = ProtectedKeyLookup.record()
        var payloads: [CFTypeRef?] = [nil, Data(repeating: 7, count: 32) as CFData,
                                    record as CFDictionary, [] as CFArray,
                                    [record, record] as CFArray, ["wrong-type"] as CFArray]
        for size in [0, 16, 31, 33, 64] {
            var damaged = record
            damaged[kSecValueData as String] = Data(repeating: 7, count: size)
            payloads.append([damaged] as CFArray)
        }
        for data in [nil, "not-data", NSNumber(value: 32)] as [Any?] {
            var damaged = record
            damaged[kSecValueData as String] = data
            payloads.append([damaged] as CFArray)
        }
        for payload in payloads {
            let lookup = ProtectedKeyLookup()
            lookup.respond(result: payload)
            let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
            XCTAssertThrowsError(try reader.loadExistingExportAuthorityKey()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            }
            XCTAssertEqual(lookup.calls, 1)
        }
    }

    func testDeniedUnavailableAndUnexpectedSDKStatusesHaveOneFixedHealthFreeFailure() throws {
        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable,
                       errSecDecode, errSecDuplicateItem, errSecUserCanceled, errSecParam, OSStatus(-1)] {
            let lookup = ProtectedKeyLookup()
            // Even a populated result cannot override a denied/ambiguous SDK status.
            lookup.respond(status: status, result: [ProtectedKeyLookup.record()] as CFArray)
            let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
            XCTAssertThrowsError(try reader.loadExistingExportAuthorityKey()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
                XCTAssertEqual(String(describing: $0), "permission_required")
            }
            XCTAssertEqual(lookup.calls, 1)
            XCTAssertTrue(lookup.exactReadOnlyQuery)
        }
    }

    func testNotFoundWithUnexpectedMaterialFailsRatherThanMasqueradingAsCleanAbsence() throws {
        let lookup = ProtectedKeyLookup()
        lookup.respond(status: errSecItemNotFound, result: [ProtectedKeyLookup.record()] as CFArray)
        let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
        XCTAssertThrowsError(try reader.loadExistingExportAuthorityKey()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertEqual(lookup.calls, 1)
    }

    func testProductionReaderSupportsRealCryptoKitPrivateLedgerWithoutIssuingRights() throws {
        let rig = try ProtectedKeyStoreRig(); defer { rig.cleanup() }
        let bytes = try rig.privateBytes()
        let reopened = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.reader)
        let state = try reopened.snapshot()
        XCTAssertEqual(state.generation, 0)
        XCTAssertTrue(state.delegations.isEmpty)
        XCTAssertTrue(state.plans.isEmpty)
        XCTAssertTrue(state.decisions.isEmpty)
        XCTAssertEqual(try rig.store.snapshot().generation, 0)
        XCTAssertEqual(rig.lookup.calls, 3) // Independent creation + two real private MAC reads.
        XCTAssertEqual(try rig.privateBytes(), bytes)
        XCTAssertTrue(rig.lookup.exactReadOnlyQuery)
    }

    func testRejectedOrChangedMaterialCannotReadRepairOrReplaceTheRealPrivateLedger() throws {
        let rig = try ProtectedKeyStoreRig(); defer { rig.cleanup() }
        let before = try rig.privateBytes()
        let good = ProtectedKeyLookup.record()
        var foreign = good; foreign[kSecAttrService as String] = "com.codybontecou.obsidianhealth.direct-cli-ios-trust"
        var synchronized = good; synchronized[kSecAttrSynchronizable as String] = true
        var migratable = good; migratable[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        var afterUnlock = good; afterUnlock[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var short = good; short[kSecValueData as String] = Data(repeating: 7, count: 31)
        var changed = good; changed[kSecValueData as String] = Data(repeating: 8, count: 32)
        let failures: [(OSStatus, CFTypeRef?, AgentBridgeValidationError)] = [
            (errSecItemNotFound, nil, .permissionRequired),
            (errSecInteractionNotAllowed, [good] as CFArray, .permissionRequired),
            (errSecDecode, nil, .permissionRequired),
            (errSecSuccess, nil, .permissionRequired),
            (errSecSuccess, [good, good] as CFArray, .permissionRequired),
            (errSecSuccess, [foreign] as CFArray, .permissionRequired),
            (errSecSuccess, [synchronized] as CFArray, .permissionRequired),
            (errSecSuccess, [migratable] as CFArray, .permissionRequired),
            (errSecSuccess, [afterUnlock] as CFArray, .permissionRequired),
            (errSecSuccess, [short] as CFArray, .permissionRequired),
            // A different well-formed 32-byte key is detected by the REAL private-store MAC,
            // not by a fake reader/codec or a claimed native protected monotonic witness.
            (errSecSuccess, [changed] as CFArray, .bindingChanged)
        ]
        for (status, result, expected) in failures {
            rig.lookup.respond(status: status, result: result)
            XCTAssertThrowsError(try rig.store.snapshot()) { XCTAssertEqual($0 as? AgentBridgeValidationError, expected) }
            XCTAssertEqual(try rig.privateBytes(), before)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).sorted(), ["lock", "state.json"])
            rig.lookup.respond(result: [good] as CFArray)
            XCTAssertEqual(try rig.store.snapshot().generation, 0)
        }
        XCTAssertEqual(rig.lookup.calls, 23)
        XCTAssertTrue(rig.lookup.exactReadOnlyQuery)
    }

    func testEveryAccessRereadsCurrentAvailabilityWithAFreshNoninteractiveContextOffMainActor() throws {
        let lookup = ProtectedKeyLookup()
        let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
        XCTAssertEqual(try DispatchQueue.global().sync { try reader.loadExistingExportAuthorityKey()?.bitCount }, 256)
        lookup.respond(status: errSecItemNotFound, result: nil)
        XCTAssertNil(try DispatchQueue.global().sync { try reader.loadExistingExportAuthorityKey() })
        lookup.respond(status: errSecNotAvailable, result: nil)
        XCTAssertThrowsError(try DispatchQueue.global().sync { try reader.loadExistingExportAuthorityKey() }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        lookup.respond(result: [ProtectedKeyLookup.record()] as CFArray)
        XCTAssertEqual(try DispatchQueue.global().sync { try reader.loadExistingExportAuthorityKey()?.bitCount }, 256)
        XCTAssertEqual(lookup.calls, 4)
        XCTAssertTrue(lookup.freshContexts)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
    }

    func testAnAvailableProtectedKeyDoesNotBypassTheSeparateNativeInitializationDecision() throws {
        let rig = try ProtectedKeyStoreRig(); defer { rig.cleanup() }
        let before = try rig.privateBytes(), calls = rig.lookup.calls
        let denied = rig.parent.appendingPathComponent("denied-authority")
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore.createPrivateStore(
            at: denied, protectedKeys: rig.reader, authorization: ProtectedKeyNativeAuthorization(allowed: false))) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            }
        XCTAssertEqual(rig.lookup.calls, calls) // Native decision rejects before any OS key lookup.
        XCTAssertFalse(FileManager.default.fileExists(atPath: denied.path))
        XCTAssertEqual(try rig.privateBytes(), before)
    }

    func testExactCurrentLookupDataDrivesTheCryptoKitMACRatherThanAnySameSizeKey() throws {
        // Independent HMAC-SHA256 synthetic vectors, not recomputed expected values.
        let vectors: [(UInt8, String)] = [
            (7, "4d113e8847b5f0f49972599a2fc767ddd8fa4756c6ddceebcd8be156faf3851c"),
            (8, "029ec765b86efa429fdb282e81c573a1eb4979ead6d3700b5ceac2a2fff7dcf0")
        ]
        let lookup = ProtectedKeyLookup()
        let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
        for (syntheticByte, expectedMAC) in vectors {
            var record = ProtectedKeyLookup.record()
            record[kSecValueData as String] = Data(repeating: syntheticByte, count: 32)
            lookup.respond(result: [record] as CFArray)
            let key = try XCTUnwrap(reader.loadExistingExportAuthorityKey())
            let mac = HMAC<SHA256>.authenticationCode(for: Data("protected-key-probe".utf8), using: key)
            XCTAssertEqual(mac.map { String(format: "%02x", $0) }.joined(), expectedMAC)
        }
        XCTAssertEqual(lookup.calls, 2)
    }

    func testMissingDedicatedItemReturnsNoKeyWithoutAnotherLookupOrFallback() throws {
        let lookup = ProtectedKeyLookup()
        lookup.respond(status: errSecItemNotFound, result: nil)
        let reader = AgentBridgeExportProtectedKey(copyMatching: { lookup.copyMatching($0, $1) })
        XCTAssertNil(try reader.loadExistingExportAuthorityKey())
        XCTAssertEqual(lookup.calls, 1)
        XCTAssertTrue(lookup.exactReadOnlyQuery)
    }
}

/// All SDK credential access is intercepted here. No Security writer exists on this seam.
nonisolated private final class ProtectedKeyLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var validQuery = true
    private var previousContext: LAContext?
    private var distinctContexts = true
    private var status: OSStatus = errSecSuccess
    private var payload: CFTypeRef? = [ProtectedKeyLookup.record()] as CFArray
    func respond(status: OSStatus = errSecSuccess, result: CFTypeRef?) {
        lock.lock(); defer { lock.unlock() }
        self.status = status
        payload = result
    }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var exactReadOnlyQuery: Bool { lock.lock(); defer { lock.unlock() }; return validQuery }
    var freshContexts: Bool { lock.lock(); defer { lock.unlock() }; return distinctContexts }

    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        count += 1
        let values = query as NSDictionary
        let context = values[kSecUseAuthenticationContext] as? LAContext
        distinctContexts = distinctContexts && context != nil && context !== previousContext
        previousContext = context
        validQuery = validQuery && values.count == 9
            && values[kSecClass] as? String == kSecClassGenericPassword as String
            && values[kSecAttrService] as? String == "com.codybontecou.obsidianhealth.agent-bridge.native-export-authority"
            && values[kSecAttrAccount] as? String == "integrity-key-v1"
            && values[kSecAttrSynchronizable] as? Bool == false
            && values[kSecUseDataProtectionKeychain] as? Bool == true
            && values[kSecReturnAttributes] as? Bool == true
            && values[kSecReturnData] as? Bool == true
            && values[kSecMatchLimit] as? Int == 2
            && context?.interactionNotAllowed == true
        result?.pointee = payload
        return status
    }

    static func record() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codybontecou.obsidianhealth.agent-bridge.native-export-authority",
            kSecAttrAccount as String: "integrity-key-v1",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: Data(repeating: 7, count: 32)
        ]
    }
}

/// Synthetic separate human decision only; key possession itself never authorizes initialization.
nonisolated private struct ProtectedKeyNativeAuthorization: AgentBridgeExportNativeAuthorizing {
    let allowed: Bool
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        guard allowed else { throw AgentBridgeValidationError.permissionRequired }
    }
}

nonisolated private final class ProtectedKeyStoreRig {
    let parent: URL
    let directory: URL
    let lookup = ProtectedKeyLookup()
    let reader: AgentBridgeExportProtectedKey
    let store: AgentBridgeExportAuthorityStore
    init() throws {
        parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("healthmd-protected-key-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = parent.appendingPathComponent("authority")
        let boundary = lookup
        reader = AgentBridgeExportProtectedKey(copyMatching: { boundary.copyMatching($0, $1) })
        store = try .createPrivateStore(at: directory, protectedKeys: reader,
                                       authorization: ProtectedKeyNativeAuthorization(allowed: true))
    }
    func privateBytes() throws -> Data { try Data(contentsOf: directory.appendingPathComponent("state.json")) }
    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}
