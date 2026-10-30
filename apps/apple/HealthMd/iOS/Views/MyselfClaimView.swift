#if os(iOS)
import SwiftUI
import StoreKit

/// Claims remain unavailable in this release.
enum MyselfClaimFeature {
    static let isEnabled = false
}

/// Sends purchase proof only after the user chooses to claim access. No health or location data is sent.
struct MyselfClaimView: View {
    let app: String
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var openedClaim = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your existing purchase includes complimentary lifetime access to myself.md.")
                    Text("We’ll send your App Store purchase proof to myself.md to verify eligibility. Your health and location data stay on your device.")
                    Text("Then sign in to choose the myself.md account that receives access. Each original purchase can be linked to one account. Family-shared access alone does not qualify; the purchaser can claim.")
                } header: {
                    Text("Claim free myself.md access")
                }
                Section {
                    Button {
                        Task { await claim() }
                    } label: {
                        if busy { ProgressView("Verifying purchase…") }
                        else { Text(openedClaim ? "Open claim again" : "Verify purchase and continue") }
                    }
                    .disabled(busy)
                    if openedClaim {
                        Text("Finish signing in on myself.md, then sign in with the same account in the myself.md app on iOS or Android.")
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                }
            }
            .navigationTitle("myself.md access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    @MainActor
    private func claim() async {
        guard MyselfClaimFeature.isEnabled else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            // Explicit user action may ask the App Store to authenticate; background launches never do.
            try await AppStore.sync()
            let proof = try await Self.purchaseProof(app: app)
            let configured = Bundle.main.object(forInfoDictionaryKey: "MyselfClaimServerURL") as? String ?? "https://myself.md"
            guard let server = URL(string: configured), server.scheme == "https", server.user == nil,
                  server.password == nil, server.path.isEmpty || server.path == "/", server.query == nil, server.fragment == nil else {
                throw ClaimError.message("The myself.md claim service is not configured correctly.")
            }
            var request = URLRequest(url: server.appendingPathComponent("api/migration/proof"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30
            request.httpBody = try JSONEncoder().encode(proof)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ClaimError.message("The claim service did not respond.") }
            let result = try JSONDecoder().decode(ClaimResponse.self, from: data)
            guard response.statusCode == 200, let raw = result.claimUrl, let url = URL(string: raw),
                  url.scheme == server.scheme, url.host == server.host, url.port == server.port,
                  url.user == nil, url.password == nil, url.path == "/claim", url.query == nil,
                  let ticket = url.fragment, ticket.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
                throw ClaimError.message(result.error ?? "Your purchase could not be verified. Please try again.")
            }
            openURL(url)
            openedClaim = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private static func purchaseProof(app: String) async throws -> PurchaseProof {
        let products: Set<String> = app == "health.md"
            ? ["com.codybontecou.obsidianhealth.unlock", "com.codybontecou.obsidianhealth.unlock.family"]
            : ["com.bontecou.isome.lifetime.individual", "com.bontecou.isome.lifetime"]
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               products.contains(transaction.productID), transaction.revocationDate == nil,
               transaction.ownershipType == .purchased {
                return PurchaseProof(app: app, kind: "iap", proof: result.jwsRepresentation)
            }
        }
        if app == "health.md" {
            let result = try await AppTransaction.refresh()
            if case .verified(let transaction) = result,
               transaction.originalPurchaseDate < Date(timeIntervalSince1970: 1777161600) {
                return PurchaseProof(app: app, kind: "app", proof: result.jwsRepresentation)
            }
        }
        throw ClaimError.message("No qualifying purchase was found. Use the Apple Account that bought this app or its lifetime unlock, then try again.")
    }

    private struct PurchaseProof: Encodable {
        let app: String
        let store = "ios"
        let kind: String
        let proof: String
    }
    private struct ClaimResponse: Decodable {
        var claimUrl: String?
        var error: String?
    }
    private enum ClaimError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}

#endif
