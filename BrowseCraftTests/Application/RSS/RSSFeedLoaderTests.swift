import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：RSSFeedLoaderTests 固定 feed 加载、parser 串接以及来源上下文透传。
struct RSSFeedLoaderTests {
    @Test func loadsFeedXMLUsingRSSAcceptRequestConfig() async throws {
        let pageDataLoader: RecordingPageDataLoader = RecordingPageDataLoader(
            response: Self.rssXML
        )
        let loader: RSSFeedLoader = RSSFeedLoader(
            pageDataLoader: pageDataLoader
        )
        let url: URL = try #require(URL(string: "https://www.solidot.org/index.rss"))

        let feed: RSSFeed = try await loader.load(feedURL: url)

        #expect(pageDataLoader.requests.count == 1)
        #expect(pageDataLoader.requests.first?.url == url)
        #expect(pageDataLoader.requests.first?.request?.headers?["Accept"]?.contains("application/rss+xml") == true)
        #expect(feed.title == "Solidot")
        #expect(feed.items.first?.title == "奇客资讯")
    }

    @Test func rejectsHTMLAntiBotPageBeforeParsingXML() async throws {
        let pageDataLoader: RecordingPageDataLoader = RecordingPageDataLoader(
            response: Self.antiBotHTML
        )
        let loader: RSSFeedLoader = RSSFeedLoader(
            pageDataLoader: pageDataLoader
        )
        let url: URL = try #require(URL(string: "https://example.com/feed"))

        do {
            _ = try await loader.load(feedURL: url)
            Issue.record("Expected antiBot error")
        } catch let error as RuleExecutionError {
            #expect(error == .antiBot(url: url.absoluteString))
        }
    }

    @Test func forwardsSourceContextForProtectedFeedRequest() async throws {
        let pageDataLoader: RecordingPageDataLoader = RecordingPageDataLoader(
            response: Self.rssXML
        )
        let loader: RSSFeedLoader = RSSFeedLoader(pageDataLoader: pageDataLoader)
        let url: URL = try #require(URL(string: "https://example.test/member/feed.xml"))
        let context: SourceRequestContext = SourceRequestContext(
            sourceID: "rss.member",
            baseURL: try #require(URL(string: "https://example.test")),
            purpose: .rss,
            refererURL: url
        )

        _ = try await loader.load(feedURL: url, context: context)

        #expect(pageDataLoader.requests.first?.context == context)
    }

    private static let rssXML: String = """
    <rss version="2.0">
      <channel>
        <title>Solidot</title>
        <item>
          <title>奇客资讯</title>
          <link>https://www.solidot.org/story?sid=100001</link>
          <guid>solidot-100001</guid>
        </item>
      </channel>
    </rss>
    """

    private static let antiBotHTML: String = """
    <!DOCTYPE html>
    <html lang="zh-CN">
      <head><title>403 — 访问被拒绝</title></head>
      <body>安全策略拦截</body>
    </html>
    """
}

private final class RecordingPageDataLoader: PageDataLoader {
    struct Request {
        var url: URL
        var request: RequestConfig?
        var context: SourceRequestContext?
    }

    private let response: String
    private(set) var requests: [Request] = []

    init(response: String) {
        self.response = response
    }

    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        self.requests.append(
            Request(
                url: request.url,
                request: request.requestConfig,
                context: request.sourceContext
            )
        )
        return PageDataResponse(data: Data(self.response.utf8), finalURL: request.url)
    }
}
