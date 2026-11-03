"""Run the production Swift policy against the same fixtures as Android, without a device."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'packages/contracts/clinic-sponsorship/v1/authorization-fixtures.json'
SWIFT = ROOT / 'apps/apple/HealthMd/Shared/Models/ClinicExportAuthorization.swift'
VERIFIER = ROOT / 'apps/apple/HealthMd/Shared/Models/ClinicGrantVerifier.swift'
SESSION = ROOT / 'apps/apple/HealthMd/Shared/Models/ClinicSponsorshipSession.swift'
CLIENT = ROOT / 'apps/apple/HealthMd/Shared/Managers/ClinicLicensingClient.swift'
MANAGER = ROOT / 'apps/apple/HealthMd/Shared/Managers/ClinicSponsorshipManager.swift'


class ClinicExportAuthorizationTests(unittest.TestCase):
    def test_fixture_ids_are_unique_and_required_hazards_are_present(self):
        cases = json.loads(FIXTURES.read_text())['cases']
        ids = [c['id'] for c in cases]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue({'personal-survives-revocation', 'expired', 'download', 'no-consent',
                         'stale-policy', 'suffix-host', 'missing-binding', 'encoded-path'} <= set(ids))

    # The verifier and keychain seam import CryptoKit and Security, which only Apple SDKs ship.
    @unittest.skipUnless(shutil.which('xcrun'), 'Apple Swift toolchain required')
    def test_swift_production_policy_matches_shared_cases(self):
        harness = r'''
import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
func string(_ d: [String: Any], _ key: String) -> String? { d[key] as? String }
func number(_ d: [String: Any], _ key: String) -> Int64 { (d[key] as! NSNumber).int64Value }
for c in root["cases"] as! [[String: Any]] {
    let grant: ClinicExportGrant? = (c["grant"] as? [String: Any]).map { g in
        ClinicExportGrant(clinicID: string(g, "clinic_id")!, destinationID: string(g, "destination_id")!,
            policyVersion: Int(number(g, "policy_version")), endpoint: string(g, "endpoint")!,
            issuedAtMilliseconds: number(g, "issued_at_ms"), expiresAtMilliseconds: number(g, "expires_at_ms"),
            revoked: g["revoked"] as! Bool)
    }
    let r = c["request"] as! [String: Any]
    let request = ClinicExportRequest(isDirectClinicDelivery: r["direct_delivery"] as! Bool,
        clinicID: string(r, "clinic_id"), destinationID: string(r, "destination_id"),
        policyVersion: (r["policy_version"] as? NSNumber)?.intValue,
        endpoint: string(r, "endpoint"), sharingAuthorized: r["sharing_authorized"] as! Bool)
    let actual = ClinicExportAuthorization.decide(independentAccess: c["independent_access"] as! Bool,
        grant: grant, request: request, nowMilliseconds: number(c, "now_ms")).rawValue
    precondition(actual == c["expected"] as! String, "Failed fixture: \(c["id"]!) -> \(actual)")
}
for c in root["endpoints"] as! [[String: Any]] {
    let actual = ClinicExportAuthorization.canonicalClinicEndpoint(c["input"] as! String)
    precondition(actual == c["expected"] as? String, "Endpoint mismatch: \(c["input"]!)")
}
print("Shared clinic authorization fixtures passed")
let verificationData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let f = try JSONSerialization.jsonObject(with: verificationData) as! [String: Any]
let verifier = ClinicGrantVerifier(issuer: f["issuer"] as! String, audience: f["audience"] as! String,
    trustedKeys: [f["key_id"] as! String: Data(base64Encoded: f["public_key_der"] as! String)!])
for c in f["cases"] as! [[String: Any]] {
    let grant = verifier.verify(c["token"] as! String, installationID: f["installation_id"] as! String,
        nowMilliseconds: number(f, "now_ms"))
    precondition((grant != nil) == c["expected"] as! Bool, "Signature fixture failed: \(c["id"]!)")
}
print("Shared clinic signature fixtures passed")
var secureRecord = String(decoding: try JSONEncoder().encode(ClinicSponsorshipRecord(
    installationID: f["installation_id"] as! String)), as: UTF8.self)
var clock: Int64 = 1000000
@MainActor func session() throws -> ClinicSponsorshipSession {
    try ClinicSponsorshipSession(verifier: verifier, read: { secureRecord },
        write: { secureRecord = $0 }, clock: { clock })
}
let validToken = (f["cases"] as! [[String: Any]])[0]["token"] as! String
func check(_ condition: Bool) { precondition(condition) }
let endpoint = "https://intake.clinic.example/upload"
let active = try session()
try active.accept(grantToken: validToken, refreshToken: String(repeating: "x", count: 43), clinicName: "Fictional clinic")
try check(active.authorize(endpoint: endpoint) == .blockedSharingNotAuthorized)
try active.setSharingAuthorized(true)
try check(active.authorize(endpoint: endpoint) == .allowedClinicDestination)
try check(active.authorize(endpoint: "https://other.example/upload") == .blockedDestinationNotPermitted)
try active.setUploadAuthorization("Bearer synthetic-upload-token")
try check(active.uploadAuthorization(endpoint: endpoint) == "Bearer synthetic-upload-token")
try check(active.uploadAuthorization(endpoint: "https://other.example/upload") == nil)
try active.setSharingAuthorized(false)
try check(active.uploadAuthorization(endpoint: endpoint) == nil)
try active.setSharingAuthorized(true)
try check(session().authorize(endpoint: endpoint) == .allowedClinicDestination)
clock = 1600000
try check(active.grant() == nil)
clock = 1000000
let restarted = try session()
try check(restarted.grant() == nil)
try restarted.disconnect()
precondition(restarted.refreshToken == nil)
try check(session().grant() == nil)
print("Clinic session consent, restart, rollback and disconnection passed")
@MainActor final class RecoveryStorage: KeychainStoring {
    var value: String
    var fail = false
    init(_ value: String) { self.value = value }
    func readStringOrThrow(key: String) throws -> String? { value }
    func writeStringOrThrow(key: String, value: String) throws {
        if fail { throw ClinicSponsorshipError.inactive }
        self.value = value
    }
}
@MainActor final class RecoveryAPI: ClinicLicensingServing {
    let storage: RecoveryStorage
    let token: String
    var calls = 0
    var secret: String?
    init(storage: RecoveryStorage, token: String) { self.storage = storage; self.token = token }
    func redeem(code: String, installationID: String, enrollmentSecret: String) async throws -> ClinicLicensingReply {
        let record = try JSONDecoder().decode(ClinicSponsorshipRecord.self, from: Data(storage.value.utf8))
        precondition(record.pendingEnrollment?.enrollmentSecret == enrollmentSecret)
        precondition(record.pendingEnrollment?.invitationCode == code)
        if let secret { precondition(secret == enrollmentSecret) } else { secret = enrollmentSecret }
        calls += 1
        if calls == 1 { throw ClinicLicensingError.unavailable }
        if calls == 2 { storage.fail = true }
        return ClinicLicensingReply(grant: token, clinicName: "Synthetic clinic", sponsorshipID: "synthetic", refreshToken: nil)
    }
    func refresh(token: String, installationID: String) async throws -> ClinicLicensingReply { preconditionFailure("Pending enrollment must redeem") }
    func disconnect(token: String, installationID: String) async throws { }
}
let recoveryStorage = RecoveryStorage(String(decoding: try JSONEncoder().encode(ClinicSponsorshipRecord(
    installationID: f["installation_id"] as! String)), as: UTF8.self))
let config = try ClinicLicensingConfiguration(baseURL: URL(string: "https://licensing.clinic.example/")!,
    issuer: f["issuer"] as! String, audience: f["audience"] as! String,
    trustedKeys: [f["key_id"] as! String: Data(base64Encoded: f["public_key_der"] as! String)!])
let recoveryAPI = RecoveryAPI(storage: recoveryStorage, token: validToken)
let manager = ClinicSponsorshipManager(configuration: config, keychain: recoveryStorage, client: recoveryAPI, clock: { 1000000 })
do { try await manager.enroll(code: String(repeating: "c", count: 43)); preconditionFailure("Expected lost response") }
catch ClinicLicensingError.unavailable { }
precondition(manager.status.enrollmentPending && !manager.status.active)
do { try await manager.resumeEnrollment(); preconditionFailure("Expected failed commit") }
catch ClinicSponsorshipError.inactive { }
recoveryStorage.fail = false
let recovered = ClinicSponsorshipManager(configuration: config, keychain: recoveryStorage, client: recoveryAPI, clock: { 1000000 })
await recovered.refresh()
precondition(recoveryAPI.calls == 3 && recovered.status.active && !recovered.status.enrollmentPending && !recovered.status.sharingAuthorized)
let recoveredRecord = try JSONDecoder().decode(ClinicSponsorshipRecord.self, from: Data(recoveryStorage.value.utf8))
precondition(recoveredRecord.refreshToken == recoveryAPI.secret && recoveredRecord.pendingEnrollment == nil)
try await recovered.disconnect()
precondition(!recovered.status.active)
for (status, body, definitive) in [(403, "", false), (403, "<html>denied</html>", false),
    (403, #"{"error":"native_client_required"}"#, false),
    (403, #"{"error":"invitation_unavailable"}"#, true),
    (403, #"{"error":"sponsorship_inactive"}"#, true),
    (401, #"{"error":"unauthorized"}"#, true),
    (500, #"{"error":"sponsorship_inactive"}"#, false)] {
    precondition(ClinicLicensingClient.isDefinitiveDenial(statusCode: status, data: Data(body.utf8)) == definitive)
}
print("Native manager recovers lost response and failed commit across restart without restoring consent")

@MainActor final class ControlledAPI: ClinicLicensingServing {
    let token: String
    var denial: ClinicLicensingError?
    var wait = false
    var continuation: CheckedContinuation<Void, Never>?
    var revokedProof: String?
    init(token: String) { self.token = token }
    func redeem(code: String, installationID: String, enrollmentSecret: String) async throws -> ClinicLicensingReply {
        if let denial { throw denial }
        if wait { await withCheckedContinuation { continuation = $0 } }
        return ClinicLicensingReply(grant: token, clinicName: "Synthetic clinic", sponsorshipID: "synthetic", refreshToken: nil)
    }
    func refresh(token: String, installationID: String) async throws -> ClinicLicensingReply { preconditionFailure("unexpected refresh") }
    func disconnect(token: String, installationID: String) async throws { revokedProof = token }
}
@MainActor func emptyStorage() throws -> RecoveryStorage {
    RecoveryStorage(String(decoding: try JSONEncoder().encode(ClinicSponsorshipRecord(
        installationID: f["installation_id"] as! String)), as: UTF8.self))
}
for definitive in [false, true] {
    let storage = try emptyStorage()
    let api = ControlledAPI(token: validToken)
    api.denial = definitive ? .inactive : .unavailable
    let denied = ClinicSponsorshipManager(configuration: config, keychain: storage, client: api, clock: { 1000000 })
    do { try await denied.enroll(code: String(repeating: "c", count: 43)); preconditionFailure("Expected failure") }
    catch is ClinicLicensingError { }
    precondition(denied.status.enrollmentPending == !definitive && !denied.status.active)
    let restarted = ClinicSponsorshipManager(configuration: config, keychain: storage, client: api, clock: { 1000000 })
    precondition(restarted.status.enrollmentPending == !definitive && !restarted.status.active)
}
let raceStorage = try emptyStorage()
let raceAPI = ControlledAPI(token: validToken)
raceAPI.wait = true
let race = ClinicSponsorshipManager(configuration: config, keychain: raceStorage, client: raceAPI, clock: { 1000000 })
let enrollment = Task { @MainActor in
    do { try await race.enroll(code: String(repeating: "c", count: 43)); preconditionFailure("Late response restored enrollment") }
    catch is CancellationError { }
}
while raceAPI.continuation == nil { await Task.yield() }
let pending = try JSONDecoder().decode(ClinicSponsorshipRecord.self, from: Data(raceStorage.value.utf8)).pendingEnrollment!
try await race.disconnect()
raceAPI.continuation!.resume()
try await enrollment.value
precondition(raceAPI.revokedProof == pending.enrollmentSecret)
precondition(!race.status.active && !race.status.enrollmentPending && !race.status.sharingAuthorized)
let afterRace = ClinicSponsorshipManager(configuration: config, keychain: raceStorage, client: raceAPI, clock: { 1000000 })
precondition(!afterRace.status.active && !afterRace.status.enrollmentPending)
print("Definitive denial and disconnect during redemption cannot restore pending proof or access")


'''
        with tempfile.TemporaryDirectory(prefix='healthmd-clinic-policy-') as directory:
            main = Path(directory) / 'main.swift'
            main.write_text(harness)
            # Keychain is an injected native boundary. This host seam only supplies its type;
            # the actual Security adapter is qualified with the app's native build/device checks.
            keychain = Path(directory) / 'KeychainBoundary.swift'
            keychain.write_text('''import Foundation
import Security
@MainActor protocol KeychainStoring {
    func readStringOrThrow(key: String) throws -> String?
    func writeStringOrThrow(key: String, value: String) throws
}
struct SystemKeychainStore: KeychainStoring {
    init(service: String, accessibility: CFString) {}
    func readStringOrThrow(key: String) throws -> String? { throw ClinicSponsorshipError.inactive }
    func writeStringOrThrow(key: String, value: String) throws { throw ClinicSponsorshipError.inactive }
}
''')
            binary = Path(directory) / 'policy-tests'
            compilation = subprocess.run(['swiftc', '-swift-version', '6', '-module-cache-path',
                str(Path(directory) / 'modules'), str(SWIFT), str(VERIFIER), str(SESSION), str(CLIENT),
                str(MANAGER), str(keychain), str(main), '-o', str(binary)],
                cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(compilation.returncode, 0, compilation.stdout + compilation.stderr)
            result = subprocess.run([str(binary), str(FIXTURES), str(FIXTURES.with_name('verification-fixtures.json'))],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
