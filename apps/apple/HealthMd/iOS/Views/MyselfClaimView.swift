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
    /// MyselfClaimG is pushed from App & support (Back, no Done). The launch-time claim
    /// prompt is modal, so by default the page hosts itself with a Back-styled dismiss.
    var presentedModally = true
    @Environment(\.openURL) private var openURL
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var openedClaim = false
    @Environment(\.glassPalette) private var glassPalette

    /// MyselfClaimG.
    var body: some View {
        if presentedModally {
            GlassModalBackStack { page }
        } else {
            page
        }
    }

    private var page: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    HStack(spacing: 14) {
                        Image("AppIconImage")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Your purchase includes complimentary lifetime access to myself.md.")
                            .font(.system(size: 15))
                            .foregroundStyle(glassPalette.sec)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface()

                    GlassPanel {
                        step(String(localized: "1 · Verify purchase"),
                             String(localized: "App Store proof only — health and location stay here"),
                             done: openedClaim)
                        divider
                        step(String(localized: "2 · Choose the account"),
                             String(localized: "Each original purchase links to one account"),
                             done: false)
                        divider
                        step(String(localized: "3 · Open the myself.md app"),
                             String(localized: "Sign in with the same account"),
                             done: false)
                    }

                    Text("Family-shared access alone doesn’t qualify; the original purchaser can claim.")
                        .font(.system(size: 13))
                        .foregroundStyle(glassPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if openedClaim {
                        Text("Finish signing in on myself.md, then sign in with the same account in the myself.md app on iOS or Android.")
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(glassPalette.sec)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(glassPalette.coral)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    Task { await claim() }
                } label: {
                    if busy { ProgressView("Verifying purchase…") }
                    else { Text(LocalizedStringKey(openedClaim ? "Open claim again" : "Verify purchase")) }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(busy)
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background { Color.clear.glassSurface(in: Rectangle()).ignoresSafeArea(edges: .bottom) }
            }
            .background(glassPalette.bg.ignoresSafeArea())
            .navigationTitle("myself.md access")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var divider: some View {
        Rectangle().fill(glassPalette.line).frame(height: 1).padding(.horizontal, GlassMetrics.panelPadding)
    }

    private func step(_ title: String, _ subtitle: String, done: Bool) -> some View {
        GlassRow(title: title, subtitle: subtitle) {
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(glassPalette.ok)
                    .accessibilityLabel(String(localized: "Done"))
            }
        }
        .accessibilityElement(children: .combine)
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
