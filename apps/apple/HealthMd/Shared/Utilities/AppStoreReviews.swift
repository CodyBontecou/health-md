import Foundation

struct AppStoreReview: Identifiable, Equatable, Sendable {
    let id: String
    let author: String
    let title: String
    let body: String
    let rating: Int

    /// Apple does not return individual review permalinks in the public feed.
    var sourceURL: URL {
        URL(string: "https://apps.apple.com/us/app/health-md/id6757763969?see-all=reviews")!
    }

    // Short verbatim excerpts, verified against Apple's US customer-review feed
    // on 2026-10-28. These are an offline fallback, not fabricated testimonials.
    static let verifiedExcerpts: [AppStoreReview] = [
        .init(id: "14710318843", author: "agent00111", title: "Impressive",
              body: "This is actually perfect for me…", rating: 5),
        .init(id: "14515130698", author: "🌲🌳", title: "Upsetting",
              body: "Be more upfront about this.", rating: 1),
        .init(id: "14459781765", author: "Paul, just Paul ...", title: "Amazing",
              body: "I’ve looked for a long time…", rating: 5),
    ]
}

/// Fetches public review text only. No health values, install ID, or analytics
/// are included in the request. The storefront is explicit in both URL and UI.
struct AppStoreReviewsClient {
    private let httpClient: any HTTPClientProtocol
    private static let maximumResponseBytes = 256 * 1024
    private static let endpoint = URL(string: "https://itunes.apple.com/us/rss/customerreviews/id=6757763969/sortBy=mostRecent/json")!

    init(httpClient: any HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetch() async throws -> [AppStoreReview] {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [AppStoreReview] {
        guard data.count <= maximumResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        var seen = Set<String>()
        return (envelope.feed.entry ?? []).compactMap { item in
            guard let entry = item.value,
                  let id = entry.id?.label, !id.isEmpty,
                  let author = entry.author?.name?.label, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let title = entry.title?.label, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let body = entry.content?.label, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rawRating = entry.rating?.label, let rating = Int(rawRating),
                  (1...5).contains(rating), seen.insert(id).inserted else { return nil }
            return AppStoreReview(
                id: id,
                author: String(author.prefix(150)),
                title: String(title.prefix(300)),
                body: String(body.prefix(8_000)),
                rating: rating
            )
        }
    }

    private struct Label: Decodable { let label: String }
    private struct Author: Decodable { let name: Label? }
    private struct Entry: Decodable {
        let id: Label?
        let author: Author?
        let title: Label?
        let content: Label?
        let rating: Label?

        enum CodingKeys: String, CodingKey {
            case id, author, title, content
            case rating = "im:rating"
        }
    }

    private struct LossyEntry: Decodable {
        let value: Entry?
        init(from decoder: any Decoder) throws {
            value = try? Entry(from: decoder)
        }
    }

    private struct Feed: Decodable { let entry: [LossyEntry]? }
    private struct Envelope: Decodable { let feed: Feed }
}
