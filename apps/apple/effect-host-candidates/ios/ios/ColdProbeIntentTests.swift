import XCTest

// UI runner sends actual system Siri ingress; no app.launch/direct perform/URL substitution.
final class ColdProbeIntentTests: XCTestCase {
  private let bundleID = "com.healthmd.effecthost.ioscandidate.cold"
  private static var seenWitnesses = Set<String>()
  private static var seenProcesses = Set<Int>()
  private func attachFailureDiagnostics(app: XCUIApplication, siri: XCUIApplication, waiterResult: String, priorExists: Bool) {
    // Only candidate-fixed response prefix; never export the broader UI hierarchy.
    let candidates = siri.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ColdProbe case="))
    let count = candidates.count
    let labels = (0..<min(count, 4)).map { index in
      var bounded = String(decoding: candidates.element(boundBy: index).label.utf8.prefix(256), as: UTF8.self)
      while bounded.utf8.count > 256 { bounded.removeLast() }
      return bounded
    }
    var fields: [String: Any] = ["app_state": app.state.rawValue, "siri_state": siri.state.rawValue,
      "waiter_result": waiterResult, "prior_exists": priorExists, "fixed_prefix_match_count": count,
      "label_count_cap": 4, "label_utf8_byte_cap": 256, "attachment_byte_cap": 8192,
      "labels": labels, "labels_truncated_by_count": count > 4]
    guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
    if data.count > 8192 {
      fields["labels"] = []; fields["labels_omitted_byte_cap"] = true
      guard let bounded = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), bounded.count <= 8192 else { return }
      data = bounded
    }
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    attachment.name = "Bounded private ColdProbe ingress failure diagnostics"
    attachment.lifetime = .keepAlways; add(attachment)
  }
  private func ingress(_ phrase: String, caseID: String, sequence: Int, code: String, acquired: Int, cancellationCheck: Bool = false) throws -> Int {
    let app = XCUIApplication(bundleIdentifier: bundleID)
    if app.state != .notRunning { app.terminate() }
    XCTAssertEqual(app.state, .notRunning, "candidate_must_be_cold_before_OS_ingress")
    let siri = XCUIApplication(bundleIdentifier: "com.apple.siri")
    // Dismiss prior system response, then prove no old private response remains observable.
    XCUIDevice.shared.press(.home)
    let prior = siri.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ColdProbe case=")).firstMatch
    let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: prior)
    let absentResult = XCTWaiter.wait(for: [absent], timeout: 5)
    guard absentResult == .completed else {
      let priorExists = prior.exists
      attachFailureDiagnostics(app: app, siri: siri, waiterResult: "prior_absence_\(absentResult.rawValue)", priorExists: priorExists)
      XCTFail(priorExists ? "actual_prior_private_Siri_response_exists" : "prior_private_Siri_absence_wait_unavailable")
      throw NSError(domain: "ingress_unavailable", code: 1)
    }
    XCTAssertFalse(prior.exists)
    XCTAssertEqual(app.state, .notRunning)
    XCUIDevice.shared.siriService.activate(voiceRecognitionText: phrase)
    let prefix = "ColdProbe case=\(caseID) sequence=\(sequence) witness="
    let answer = siri.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    guard answer.waitForExistence(timeout: 15) else {
      attachFailureDiagnostics(app: app, siri: siri, waiterResult: "expected_response_wait_timeout", priorExists: prior.exists)
      XCTFail("ingress_unavailable_or_unverified: no actual case/sequence-bound ColdProbe Siri response")
      throw NSError(domain: "ingress_unavailable", code: 1)
    }
    let label = answer.label
    let pattern = "^ColdProbe case=\(caseID) sequence=\(sequence) witness=([A-Fa-f0-9-]{36}) \(code) acquired=\(acquired) released=\(acquired) active=0 ack=1 windows=0 pid=([0-9]+) cancel_check=([01]) credits=([01])$"
    let regex = try NSRegularExpression(pattern: pattern)
    guard let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)), let witnessRange = Range(match.range(at: 1), in: label), let pidRange = Range(match.range(at: 2), in: label), let pid = Int(label[pidRange]), UUID(uuidString: String(label[witnessRange])) != nil else {
      attachFailureDiagnostics(app: app, siri: siri, waiterResult: "response_binding_invalid", priorExists: prior.exists)
      XCTFail("fresh_case_sequence_invocation_process_binding_missing"); throw NSError(domain: "ingress_unavailable", code: 2)
    }
    let witness = String(label[witnessRange])
    XCTAssertTrue(Self.seenWitnesses.insert(witness).inserted, "reused_native_invocation_witness")
    XCTAssertTrue(Self.seenProcesses.insert(pid).inserted, "reused_process_in_fresh_process_case")
    let attachment = XCTAttachment(string: label); attachment.name = "Actual fresh case/sequence/native invocation/process response"; attachment.lifetime = .keepAlways; add(attachment)
    XCTAssertNotEqual(app.state, .runningForeground)
    if cancellationCheck { XCTAssertTrue(label.hasSuffix("cancel_check=1 credits=1"), "synthetic_cancel_credit_evidence_only") }
    return pid
  }
  func testActualColdIngressNoView() throws { _ = try ingress("Run cold readiness in ColdHostProbe", caseID: "actual_ingress_no_view", sequence: 0, code: "ready", acquired: 1) }
  func testUnknownSchemaBeforeAcquire() throws { _ = try ingress("Run cold invalid schema in ColdHostProbe", caseID: "unknown_schema_before_acquire", sequence: 1, code: "schema_invalid", acquired: 0) }
  func testExpiryBeforeAcquire() throws { _ = try ingress("Run cold expired in ColdHostProbe", caseID: "expiry_before_acquire", sequence: 2, code: "expired", acquired: 0) }
  func testSyntheticCancelWithinRealIngress() throws { _ = try ingress("Run cold cancellation check in ColdHostProbe", caseID: "cancel_waits_native_ack", sequence: 3, code: "cancelled", acquired: 1, cancellationCheck: true) }
  func testRestartNoGrantExpansion() throws {
    let first = try ingress("Run cold restart in ColdHostProbe", caseID: "restart_no_grant_expansion", sequence: 4, code: "ready", acquired: 1)
    let second = try ingress("Run cold restart in ColdHostProbe", caseID: "restart_no_grant_expansion", sequence: 4, code: "ready", acquired: 1)
    XCTAssertNotEqual(first, second)
  }
}
