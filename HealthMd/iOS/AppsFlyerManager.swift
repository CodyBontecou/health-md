#if os(iOS)
import Foundation
import os
import UIKit

#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

final class AppsFlyerManager: NSObject {
    static let shared = AppsFlyerManager()

    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "AppsFlyer")

    private let appStoreAppID = "6757763969"
    private let customerUserIDDefaultsKey = "appsflyer.customerUserID"
    private let infoPlistDevKey = "APPS_FLYER_DEV_KEY"

    private var isConfiguredAndEnabled = false

    private var isTrackingEnabledForCurrentBuild: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    private var customerUserID: String {
        if let existing = UserDefaults.standard.string(forKey: customerUserIDDefaultsKey), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: customerUserIDDefaultsKey)
        return generated
    }

    private override init() {
        super.init()
    }

    func configure() {
        guard isTrackingEnabledForCurrentBuild else {
            logger.info("AppsFlyer disabled for DEBUG/local build")
            return
        }

        #if canImport(AppsFlyerLib)
        guard let devKey = resolveDevKey() else {
            logger.error("AppsFlyer disabled: missing dev key. Add APPS_FLYER_DEV_KEY to Info.plist build settings or include AppsFlyerSecrets.plist in the app bundle.")
            return
        }

        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = devKey
        appsFlyer.appleAppID = appStoreAppID
        appsFlyer.customerUserID = customerUserID

        if #available(iOS 14, *) {
            appsFlyer.waitForATTUserAuthorization(timeoutInterval: 60)
        }

        appsFlyer.isDebug = false

        isConfiguredAndEnabled = true
        logger.debug("AppsFlyer configured with customerUserID=\(self.customerUserID, privacy: .public)")
        #else
        logger.error("AppsFlyer SDK is missing. Add package: https://github.com/AppsFlyerSDK/AppsFlyerFramework")
        #endif
    }

    func start() {
        guard isConfiguredAndEnabled else { return }

        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().start()
        #endif
    }

    @discardableResult
    func handleOpenURL(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        guard isConfiguredAndEnabled else { return false }

        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().handleOpen(url, options: options)
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    func continueUserActivity(_ userActivity: NSUserActivity) -> Bool {
        guard isConfiguredAndEnabled else { return false }

        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        return true
        #else
        return false
        #endif
    }

    /// Call this ONLY after a successful StoreKit purchase transaction.
    ///
    /// For a paid-upfront App Store app (no IAP), don't fire this on first launch;
    /// use install attribution from AppsFlyer instead.
    func logPurchase(revenue: Decimal, currency: String = "USD", orderID: String? = nil) {
        guard isConfiguredAndEnabled else { return }

        #if canImport(AppsFlyerLib)
        var values: [String: Any] = [
            "af_revenue": NSDecimalNumber(decimal: revenue),
            "af_currency": currency
        ]

        if let orderID, !orderID.isEmpty {
            values["af_order_id"] = orderID
        }

        AppsFlyerLib.shared().logEvent("af_purchase", withValues: values)
        logger.info("AppsFlyer af_purchase logged")
        #else
        logger.error("Cannot log af_purchase because AppsFlyer SDK is missing")
        #endif
    }

    private func resolveDevKey() -> String? {
        if let keyFromInfoPlist = Bundle.main.object(forInfoDictionaryKey: infoPlistDevKey) as? String,
           let sanitized = Self.sanitizeKey(keyFromInfoPlist) {
            return sanitized
        }

        if let url = Bundle.main.url(forResource: "AppsFlyerSecrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = raw as? [String: Any] {
            let key = (dict["devKey"] as? String) ?? (dict["appsFlyerDevKey"] as? String)
            if let sanitized = Self.sanitizeKey(key) {
                return sanitized
            }
        }

        return nil
    }

    static func sanitizeKey(_ key: String?) -> String? {
        guard let key else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("$(") else { return nil }
        guard trimmed != "YOUR_APPS_FLYER_DEV_KEY" else { return nil }
        return trimmed
    }
}
#endif
