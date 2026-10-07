import AppKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    application.run()
  }
  private var factory: RCTReactNativeFactory?
  private var delegate: ProbeDelegate?
  func applicationDidFinishLaunching(_ notification: Notification) {
    URLProtocol.registerClass(OfflineProbeProtocol.self)
    let delegate = ProbeDelegate()
    delegate.dependencyProvider = RCTAppDependencyProvider()
    let factory = RCTReactNativeFactory(delegate: delegate)
    self.delegate = delegate; self.factory = factory
    factory.rootViewFactory.initializeReactHost(launchOptions: [:], devMenuConfiguration: RCTDevMenuConfiguration())
  }
}
final class OfflineProbeProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.scheme == "http" || request.url?.scheme == "https"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { client?.urlProtocol(self, didFailWithError: NSError(domain: "candidate_offline", code: 1)) }
  override func stopLoading() {}
}
final class ProbeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? { bundleURL() }
  override func bundleURL() -> URL? { Bundle.main.url(forResource: "main", withExtension: "jsbundle") }
}
