import Foundation
import Combine
import StoreKit
import Security

/// Manages the one-time unlock IAP and free-trial export quota.
/// Relies entirely on Apple's StoreKit 2 infrastructure — no server required.
@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // MARK: - Configuration

    /// Product ID registered in App Store Connect.
    static let productID = "com.codybontecou.obsidianhealth.unlock"

    /// Number of free export actions before a purchase is required.
    static let freeExportLimit = 3

    /// First app version shipped as freemium (CFBundleShortVersionString).
    /// Any user whose `AppTransaction.originalAppVersion` is strictly less than
    /// this value downloaded the app when it was a paid upfront purchase and
    /// receives full access automatically — no action required from them.
    static let freemiumIntroVersion = "1.7.0"

    /// Base URL for the Cloudflare Worker that verifies legacy purchases.
    static let workerBaseURL = "https://healthmd-receipt-verifier.costream.workers.dev"

    /// Keychain service identifier.
    private static let keychainService = "com.codybontecou.obsidianhealth"

    // MARK: - Published State

    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var isLegacyUser: Bool = false
    @Published private(set) var product: Product? = nil
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published private(set) var purchaseError: String? = nil

    // MARK: - Free Export Quota
    //
    // Stored in the Keychain (not UserDefaults) so the count survives app
    // deletion and reinstallation, closing the "delete to get 3 more" exploit.

    private let freeExportsUsedKey             = "freeExportsUsed"
    private let serverVerifiedLegacyKey        = "serverVerifiedLegacy"
    private let serverVerificationAttemptedKey = "serverVerificationAttempted"

    /// Total number of free export actions the user has consumed.
    var freeExportsUsed: Int {
        keychainRead(key: freeExportsUsedKey)
    }

    /// How many free exports remain before a purchase is required.
    var freeExportsRemaining: Int {
        max(0, Self.freeExportLimit - freeExportsUsed)
    }

    /// True when the user still has free exports left.
    var canExportFree: Bool {
        freeExportsRemaining > 0
    }

    /// True when the user may perform an export (unlocked or within free quota).
    var canExport: Bool {
        isUnlocked || canExportFree
    }

    // MARK: - Init

    private init() {
        migrateUserDefaultsToKeychain()
        Task {
            await refreshStatus()
            await loadProduct()
            // Silently attempt server verification once in the background for any
            // user who isn't unlocked yet and hasn't been checked before. This
            // catches legacy paid users whose AppTransaction check failed without
            // requiring them to discover and tap "Restore Purchase" themselves.
            await attemptSilentServerVerification()
        }
        startTransactionListener()
    }

    // MARK: - Status Check

    /// Re-evaluates unlock status from StoreKit entitlements and AppTransaction.
    /// Called on init, after purchase, and after restore.
    func refreshStatus() async {
        #if DEBUG
        // Debug override: set "debugOriginalAppVersion" in UserDefaults to simulate
        // any install version without needing a real App Store receipt.
        // This runs first so it works on dev builds deployed via Xcode (which have
        // no receipt, causing AppTransaction to throw).
        //
        // Hardcode in init() temporarily:
        //   UserDefaults.standard.set("1.6.0", forKey: "debugOriginalAppVersion")
        // Remove by setting to nil or removing the key.
        if let debugVersion = UserDefaults.standard.string(forKey: "debugOriginalAppVersion") {
            if versionIsLessThan(debugVersion, Self.freemiumIntroVersion) {
                isLegacyUser = true
                isUnlocked = true
            } else {
                isLegacyUser = false
                isUnlocked = false
            }
            return
        }

        // Debug override: set "debugSkipToServerVerification" = true to bypass steps
        // 1–3 and jump straight to the server receipt check. Use this to test the
        // Cloudflare Worker integration end-to-end on a device that isn't a legacy user.
        //
        // Hardcode in init() temporarily:
        //   UserDefaults.standard.set(true, forKey: "debugSkipToServerVerification")
        if UserDefaults.standard.bool(forKey: "debugSkipToServerVerification") {
            if await verifyLegacyWithServer() {
                keychainWrite(key: serverVerifiedLegacyKey, value: 1)
                isLegacyUser = true
                isUnlocked = true
            } else {
                isUnlocked = false
            }
            return
        }
        #endif

        // 1. Fast path: the user already has an active entitlement for the IAP.
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productID {
                isUnlocked = true
                return
            }
        }

        // 2. Server-verified legacy path: a previous call to verifyLegacyWithServer()
        //    confirmed this device originally purchased before v1.7.0 and cached the
        //    result in the Keychain. This survives app reinstalls.
        if keychainRead(key: serverVerifiedLegacyKey) > 0 {
            isLegacyUser = true
            isUnlocked = true
            return
        }

        // 3. Local legacy paid-user path: check the version the app was first downloaded
        //    at via AppTransaction. Signed by Apple so it cannot be spoofed, but does
        //    not survive a delete-and-reinstall after v1.7.0. Step 2 above is the durable
        //    version of this check once the server has verified them at least once.
        do {
            let appTxResult = try await AppTransaction.shared
            switch appTxResult {
            case .verified(let appTx):
                if versionIsLessThan(appTx.originalAppVersion, Self.freemiumIntroVersion) {
                    isLegacyUser = true
                    isUnlocked = true
                    return
                }
            case .unverified(let appTx, _):
                // Local JWS verification failed (cert cache, clock skew, etc.) but the
                // data is still Apple-signed. Trust it for legacy detection — an attacker
                // who can forge AppTransaction responses already has device-level control
                // and could bypass any client-side check.
                if versionIsLessThan(appTx.originalAppVersion, Self.freemiumIntroVersion) {
                    isLegacyUser = true
                    isUnlocked = true
                    return
                }
            }
        } catch {
            // AppTransaction threw entirely — no data available. This happens on
            // sideloaded dev builds (no receipt) or after reinstall when StoreKit
            // hasn't synced yet. Fall through to server verification.
        }

        // 4. Automatic server verification — runs silently in the background for any
        //    user who reaches this point without being unlocked. This catches users who
        //    deleted and reinstalled after v1.7.0, breaking the local AppTransaction
        //    check (step 3). On success the result is cached in Keychain so the server
        //    is only ever called once per device regardless of future reinstalls.
        if await verifyLegacyWithServer() {
            keychainWrite(key: serverVerifiedLegacyKey, value: 1)
            isLegacyUser = true
            isUnlocked = true
            return
        }

        isUnlocked = false
    }

    // MARK: - Product Loading

    /// Fetches the IAP product from App Store Connect (or the local .storekit config
    /// during development). Populates `product` so the UI can show the live price.
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            // Silently ignore — the UI falls back to "Unlock Full Access" with no price.
        }
    }

    // MARK: - Purchase

    /// Initiates the StoreKit purchase flow. Sets `isUnlocked = true` on success.
    func purchase() async {
        guard let product else {
            purchaseError = String(
                localized: "Product unavailable. Please try again later.",
                comment: "IAP product unavailable error"
            )
            return
        }

        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseError = String(
                        localized: "Purchase verification failed.",
                        comment: "IAP verification error"
                    )
                    return
                }
                await tx.finish()
                isUnlocked = true

            case .pending:
                // Ask to Buy or parental approval pending — the transaction listener
                // will catch the approval and set isUnlocked when it arrives.
                break

            case .userCancelled:
                break

            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    /// Restores access for both IAP purchasers and legacy paid-app users.
    ///
    /// Resolution order:
    ///   1. `AppStore.sync()` — re-surfaces IAP entitlements and refreshes the receipt.
    ///   2. `refreshStatus()` — catches IAP entitlements, cached server result, and
    ///      local AppTransaction check.
    ///   3. `verifyLegacyWithServer()` — sends the receipt to the Cloudflare Worker for
    ///      server-side verification. This is the reliable path for users who deleted and
    ///      reinstalled after v1.7.0, breaking the local AppTransaction check. On success
    ///      the result is cached in the Keychain so the server is only ever called once.
    func restore() async {
        isRestoring = true
        purchaseError = nil
        defer { isRestoring = false }

        do {
            // Syncing also refreshes the on-device App Store receipt, which makes
            // the subsequent AppTransaction and server verification more reliable.
            try await AppStore.sync()
        } catch {
            purchaseError = error.localizedDescription
            return
        }

        // refreshStatus() now includes automatic server verification as its final
        // step, so a single call here covers all unlock paths including the server.
        // AppStore.sync() above also refreshes the on-device receipt first, which
        // improves the odds of the server call succeeding for reinstalled users.
        await refreshStatus()
        if isUnlocked { return }

        purchaseError = String(
            localized: "No purchase found on this Apple ID.\n\nIf you bought Health.md before v1.7.0, your access is restored automatically — try force-quitting and reopening the app. If the issue persists, contact us at cody@isolated.tech and we'll sort it out.",
            comment: "Restore purchase not found message"
        )
    }

    // MARK: - Silent Server Verification

    /// Called once on first launch. If the user isn't already unlocked and the
    /// server hasn't been consulted before, sends the receipt to the worker
    /// silently. No UI, no spinner — it just unlocks in the background if Apple
    /// confirms they're a legacy paid user.
    private func attemptSilentServerVerification() async {
        guard !isUnlocked,
              keychainRead(key: serverVerificationAttemptedKey) == 0 else { return }

        // Mark as attempted so this never runs again, even if the network call
        // fails — we don't want a network request on every launch indefinitely.
        keychainWrite(key: serverVerificationAttemptedKey, value: 1)

        let isLegacy = await verifyLegacyWithServer()
        if isLegacy {
            keychainWrite(key: serverVerifiedLegacyKey, value: 1)
            isLegacyUser = true
            isUnlocked = true
        }
    }

    // MARK: - Server Verification

    /// Attempts server-side legacy verification. Tries two approaches:
    /// 1. AppTransaction JWS token (works on TestFlight + App Store)
    /// 2. Legacy receipt file (works on App Store installs only)
    /// Returns `false` on any failure so the caller falls back gracefully.
    private func verifyLegacyWithServer() async -> Bool {
        // Approach 1: Send AppTransaction JWS to the worker.
        // Available on both TestFlight and App Store. The worker decodes the
        // signed payload and checks originalAppVersion without needing Apple's
        // deprecated verifyReceipt endpoint.
        if let jws = try? await AppTransaction.shared.jwsRepresentation {
            if await sendToWorker(path: "/verify-legacy-jws", body: ["jws": jws]) {
                return true
            }
        }

        // Approach 2: Legacy receipt file → Apple's verifyReceipt endpoint.
        // The receipt file exists on App Store installs but not TestFlight/dev.
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receiptURL.path),
           let receiptData = try? Data(contentsOf: receiptURL) {
            if await sendToWorker(path: "/verify-legacy", body: ["receipt": receiptData.base64EncodedString()]) {
                return true
            }
        }

        return false
    }

    /// Posts a JSON body to the worker and returns true if the response contains `isLegacy: true`.
    private func sendToWorker(path: String, body: [String: String]) async -> Bool {
        guard let url = URL(string: "\(Self.workerBaseURL)\(path)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["isLegacy"] as? Bool ?? false
        } catch {
            return false
        }
    }

    // MARK: - Free Export Tracking

    /// Resets the free-export counter to zero (debug/testing only).
    func resetFreeExports() {
        keychainWrite(key: freeExportsUsedKey, value: 0)
        objectWillChange.send()
    }

    /// Increments the free-export counter by one.
    /// Call once per successful export action (one button press = one use),
    /// regardless of how many files were written.
    /// No-op when the user is already unlocked.
    func recordExportUse() {
        guard !isUnlocked else { return }
        keychainWrite(key: freeExportsUsedKey, value: freeExportsUsed + 1)
        objectWillChange.send()
    }

    // MARK: - Transaction Listener

    /// Listens for incoming transactions in the background (deferred purchases,
    /// family sharing grants, etc.) and unlocks the app when one arrives.
    private func startTransactionListener() {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let tx) = result,
                      tx.productID == PurchaseManager.productID else { continue }
                await tx.finish()
                await MainActor.run { self?.isUnlocked = true }
            }
        }
    }

    // MARK: - UserDefaults → Keychain Migration

    /// One-time migration: copies any existing `freeExportsUsed` value from
    /// UserDefaults (pre-1.7.2) into the Keychain, then marks the migration done.
    /// This preserves the count for users who update rather than reinstall.
    private func migrateUserDefaultsToKeychain() {
        let migrationFlag = "freeExportsUsed_migratedToKeychain"
        guard !UserDefaults.standard.bool(forKey: migrationFlag) else { return }
        let existing = UserDefaults.standard.integer(forKey: freeExportsUsedKey)
        if existing > 0 {
            keychainWrite(key: freeExportsUsedKey, value: existing)
        }
        UserDefaults.standard.set(true, forKey: migrationFlag)
    }

    // MARK: - Debug

    /// Runs the full receipt → worker → Apple chain and returns a human-readable
    /// summary of every step. Only surfaced in the UI on DEBUG and TestFlight builds.
    func debugVerifyReceipt() async -> String {
        var lines: [String] = []

        lines.append("=== Purchase State ===")
        lines.append("isUnlocked:    \(isUnlocked)")
        lines.append("isLegacyUser:  \(isLegacyUser)")
        lines.append("serverCached:  \(keychainRead(key: serverVerifiedLegacyKey) > 0)")
        lines.append("")

        lines.append("=== Receipt ===")

        // Detailed receipt path diagnostics
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            lines.append("URL: \(receiptURL.lastPathComponent)")
            lines.append("Exists: \(FileManager.default.fileExists(atPath: receiptURL.path))")
        } else {
            lines.append("URL: nil")
        }

        // AppTransaction info (the StoreKit 2 way to get original version)
        lines.append("")
        lines.append("=== AppTransaction ===")
        do {
            let appTxResult = try await AppTransaction.shared
            switch appTxResult {
            case .verified(let appTx):
                lines.append("✅ Verified")
                lines.append("originalAppVersion: \(appTx.originalAppVersion)")
                lines.append("appVersion: \(appTx.appVersion)")
                lines.append("environment: \(appTx.environment.rawValue)")
            case .unverified(let appTx, let error):
                lines.append("⚠️ Unverified: \(error)")
                lines.append("originalAppVersion: \(appTx.originalAppVersion)")
            @unknown default:
                lines.append("❓ Unknown result")
            }
        } catch {
            lines.append("❌ \(error.localizedDescription)")
        }

        // Try refreshing receipt via AppStore.sync()
        lines.append("")
        lines.append("=== AppStore.sync() ===")
        do {
            try await AppStore.sync()
            lines.append("✅ Sync succeeded")
        } catch {
            lines.append("❌ Sync failed: \(error.localizedDescription)")
        }

        // Re-check receipt after sync
        let receiptExists: Bool
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receiptURL.path) {
            let receiptData = try? Data(contentsOf: receiptURL)
            lines.append("Receipt: ✅ \(receiptData?.count ?? 0) bytes")
            receiptExists = true
        } else {
            lines.append("Receipt file still not found after sync")
            receiptExists = false
        }
        lines.append("")

        // Test JWS server path (works on TestFlight + App Store)
        lines.append("=== Worker: JWS Path ===")
        do {
            let jws = try await AppTransaction.shared.jwsRepresentation
            lines.append("JWS: \(jws.prefix(40))…")
            let jwsResult = await sendToWorker(path: "/verify-legacy-jws", body: ["jws": jws])
            lines.append("isLegacy: \(jwsResult)")
        } catch {
            lines.append("❌ No JWS: \(error.localizedDescription)")
        }

        // Test receipt server path (App Store only)
        if receiptExists,
           let receiptURL = Bundle.main.appStoreReceiptURL,
           let receiptData = try? Data(contentsOf: receiptURL) {
            lines.append("")
            lines.append("=== Worker: Receipt Path ===")
            let receiptResult = await sendToWorker(path: "/verify-legacy", body: ["receipt": receiptData.base64EncodedString()])
            lines.append("isLegacy: \(receiptResult)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Keychain Helpers

    private func keychainRead(key: String) -> Int {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count >= MemoryLayout<Int32>.size else { return 0 }
        return Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
    }

    private func keychainWrite(key: String, value: Int) {
        var v = Int32(value)
        let data = Data(bytes: &v, count: MemoryLayout<Int32>.size)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // MARK: - Version Comparison

    /// Returns `true` if `v1` (e.g. "1.6.3") is strictly less than `v2` (e.g. "1.7.0").
    private func versionIsLessThan(_ v1: String, _ v2: String) -> Bool {
        let a = v1.split(separator: ".").compactMap { Int($0) }
        let b = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x < y { return true }
            if x > y { return false }
        }
        return false
    }
}
