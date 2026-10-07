import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var factory: RCTReactNativeFactory?
  private var delegate: ProbeDelegate?
  func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    URLProtocol.registerClass(OfflineProbeProtocol.self)
    let delegate = ProbeDelegate()
    delegate.dependencyProvider = RCTAppDependencyProvider()
    let factory = RCTReactNativeFactory(delegate: delegate)
    self.delegate = delegate; self.factory = factory
    let window = UIWindow(frame: UIScreen.main.bounds)
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground
    window.rootViewController = controller; window.makeKeyAndVisible(); self.window = window
    factory.rootViewFactory.initializeReactHost(launchOptions: options ?? [:],
      bundleConfiguration: RCTBundleConfiguration.default(),
      devMenuConfiguration: RCTDevMenuConfiguration())
    return true
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
