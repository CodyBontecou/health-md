import Foundation
import Testing
@testable import HealthMd

@MainActor
struct AppStoreReviewsTests {
    private func entry(id: String = "review-1", rating: String = "5") -> [String: Any] {
        [
            "id": ["label": id],
            "author": ["name": ["label": "Test reviewer"]],
            "title": ["label": "Test title"],
            "content": ["label": "Synthetic review text for parser testing."],
            "im:rating": ["label": rating],
        ]
    }

    private func feed(_ entries: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["feed": ["entry": entries]])
    }

    @Test func preservesRealRatingsAndFeedOrderWithoutSentimentFiltering() throws {
        let reviews = try AppStoreReviewsClient.decode(feed([
            entry(id: "newest", rating: "1"), entry(id: "older", rating: "5"),
        ]))
        #expect(reviews.map(\.id) == ["newest", "older"])
        #expect(reviews.map(\.rating) == [1, 5])
        #expect(reviews.first?.author == "Test reviewer")
        #expect(reviews.first?.body == "Synthetic review text for parser testing.")
        #expect(reviews.first?.sourceURL.host == "apps.apple.com")
    }

    @Test func skipsMetadataMalformedEntriesAndDuplicates() throws {
        var malformed = entry(id: "bad")
        malformed["author"] = "wrong shape"
        var blank = entry(id: "blank")
        blank["content"] = ["label": "  \n "]
        let reviews = try AppStoreReviewsClient.decode(feed([
            ["id": ["label": "app-metadata"]], malformed, blank,
            entry(rating: "6"), entry(rating: "0"), entry(rating: "unknown"),
            entry(), entry(), entry(id: "review-2", rating: "2"),
        ]))
        #expect(reviews.map(\.id) == ["review-1", "review-2"])
    }

    @Test func acceptsAnEmptyStorefrontWithoutInventingReviews() throws {
        #expect(try AppStoreReviewsClient.decode(Data(#"{"feed":{}}"#.utf8)).isEmpty)
        #expect(try AppStoreReviewsClient.decode(feed([])).isEmpty)
    }

    @Test func rejectsInvalidAndOversizedResponses() {
        #expect(throws: (any Error).self) {
            try AppStoreReviewsClient.decode(Data("not json".utf8))
        }
        #expect(throws: URLError.self) {
            try AppStoreReviewsClient.decode(Data(repeating: 32, count: 256 * 1024 + 1))
        }
    }

    @Test func fetchUsesOnlyThePublicAppleEndpoint() async throws {
        let client = FakeHTTPClient()
        let url = URL(string: "https://itunes.apple.com")!
        client.responses = [(try feed([entry()]), HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: nil
        )!)]
        let reviews = try await AppStoreReviewsClient(httpClient: client).fetch()
        #expect(reviews.count == 1)
        let request = try #require(client.requestsMade.first)
        #expect(request.url?.absoluteString == "https://itunes.apple.com/us/rss/customerreviews/id=6757763969/sortBy=mostRecent/json")
        #expect(request.httpBody == nil)
        #expect(request.allHTTPHeaderFields?.isEmpty != false)
        #expect(request.timeoutInterval == 10)
    }

    @Test func serverAndNetworkFailuresDoNotBecomeEmptySuccessfulFeeds() async {
        let client = FakeHTTPClient()
        client.responses = [(Data(#"{"feed":{}}"#.utf8), HTTPURLResponse(
            url: URL(string: "https://itunes.apple.com")!,
            statusCode: 503, httpVersion: nil, headerFields: nil
        )!)]
        await #expect(throws: URLError.self) {
            try await AppStoreReviewsClient(httpClient: client).fetch()
        }
        client.shouldThrow = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) {
            try await AppStoreReviewsClient(httpClient: client).fetch()
        }
    }

    @Test func offlineExcerptsHaveStableAttributionAndActualRatings() {
        #expect(AppStoreReview.verifiedExcerpts.map(\.id) == ["14710318843", "14515130698", "14459781765"])
        #expect(AppStoreReview.verifiedExcerpts.map(\.rating) == [5, 1, 5])
        #expect(Set(AppStoreReview.verifiedExcerpts.map(\.id)).count == 3)
    }
}
