import AppIntents
import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

// Private, headless application: launch installs no engine, view, or operation.
@main
final class ColdHostDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
final class ColdBundleDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? { bundleURL() }
  override func bundleURL() -> URL? { Bundle.main.url(forResource: "main", withExtension: "jsbundle") }
}
@MainActor
final class ColdRuntime {
  static let shared = ColdRuntime()
  private var factory: RCTReactNativeFactory?
  private var delegate: ColdBundleDelegate?
  func configure() {
    ColdProbeBridge.configureStarter { [self] in
      if factory != nil { return }
      let delegate = ColdBundleDelegate()
      delegate.dependencyProvider = RCTAppDependencyProvider()
      let factory = RCTReactNativeFactory(delegate: delegate)
      self.delegate = delegate; self.factory = factory
      ColdProbeBridge.initializeAndSetHost(factory.rootViewFactory)
    }
  }
}
struct CandidateReadinessProbeIntent: AppIntent {
  static var title: LocalizedStringResource = "Private Cold Readiness Probe"
  static var description = IntentDescription("Health-free, private headless runtime probe.")
  static var openAppWhenRun: Bool { false }
  @available(iOS 26.0, *) static var supportedModes: IntentModes { .background }
  @Parameter(title: "Private request frame") var requestJSON: String
  init() {}
  init(requestJSON: String) { self.requestJSON = requestJSON }
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let startedAt = ProcessInfo.processInfo.systemUptime
    let ticket = UUID().uuidString // Private invocation ownership; never a source/grant identity.
    let result: NSDictionary = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let cancelled = Task.isCancelled
        Task { @MainActor in
          ColdRuntime.shared.configure()
          ColdProbeBridge.startRequest(requestJSON, ticket: ticket, startedAt: startedAt, cancelled: cancelled) { value in continuation.resume(returning: value as NSDictionary) }
        }
      }
    } onCancel: { ColdProbeBridge.cancelTicket(ticket) }
    // Only bridge-owned fixed code/counters; no request, arbitrary provider/error, or data echo.
    let code = result["safe_code"] as? String ?? "runtime_unavailable"
    let number: (String) -> Int = { (result[$0] as? NSNumber)?.intValue ?? -1 }
    let witness = result["invocation_witness"] as? String ?? "unavailable"
    let caseID = result["case_id"] as? String ?? "unknown_schema_before_acquire"
    let summary = "ColdProbe case=\(caseID) sequence=\(number("sequence")) witness=\(witness) \(code) acquired=\(number("acquired")) released=\(number("released")) active=\(number("active")) ack=\(number("ack_before_completion")) windows=\(number("window_count")) pid=\(number("pid")) cancel_check=\(number("incomplete_during_release")) credits=\(number("synthetic_credit_verified"))"
    return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
  }
}
struct ColdProbeShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: CandidateReadinessProbeIntent(requestJSON: "{\"schema\":\"healthmd.candidate_cold_intent\",\"version\":1,\"case_id\":\"actual_ingress_no_view\",\"sequence\":0,\"deadline_milliseconds\":5000}"), phrases: ["Run cold readiness in \(.applicationName)"], shortTitle: "Cold readiness", systemImageName: "checkmark.circle")
    AppShortcut(intent: CandidateReadinessProbeIntent(requestJSON: "{\"schema\":\"healthmd.candidate_cold_intent\",\"version\":2,\"case_id\":\"unknown_schema_before_acquire\",\"sequence\":1,\"deadline_milliseconds\":5000}"), phrases: ["Run cold invalid schema in \(.applicationName)"], shortTitle: "Cold invalid schema", systemImageName: "xmark.circle")
    AppShortcut(intent: CandidateReadinessProbeIntent(requestJSON: "{\"schema\":\"healthmd.candidate_cold_intent\",\"version\":1,\"case_id\":\"expiry_before_acquire\",\"sequence\":2,\"deadline_milliseconds\":0}"), phrases: ["Run cold expired in \(.applicationName)"], shortTitle: "Cold expired", systemImageName: "clock")
    AppShortcut(intent: CandidateReadinessProbeIntent(requestJSON: "{\"schema\":\"healthmd.candidate_cold_intent\",\"version\":1,\"case_id\":\"cancel_waits_native_ack\",\"sequence\":3,\"deadline_milliseconds\":5000}"), phrases: ["Run cold cancellation check in \(.applicationName)"], shortTitle: "Cold cancellation check", systemImageName: "stop.circle")
    AppShortcut(intent: CandidateReadinessProbeIntent(requestJSON: "{\"schema\":\"healthmd.candidate_cold_intent\",\"version\":1,\"case_id\":\"restart_no_grant_expansion\",\"sequence\":4,\"deadline_milliseconds\":5000}"), phrases: ["Run cold restart in \(.applicationName)"], shortTitle: "Cold restart", systemImageName: "arrow.clockwise")
  }
}
