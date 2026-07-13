import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：RSSFeedLoaderTests 固定 P4.9.2 loader 只负责公开 feed 加载和 parser 串接。
struct RSSFeedLoaderTests {
    @Test func loadsFeedXMLUsingRSSAcceptRequestConfig() async throws {
        let pageContentLoader: RecordingPageContentLoader = RecordingPageContentLoader(
            response: Self.rssXML
        )
        let loader: RSSFeedLoader = RSSFeedLoader(
            pageContentLoader: pageContentLoader
        )
        let url: URL = try #require(URL(string: "https://www.solidot.org/index.rss"))

        let feed: RSSFeed = try await loader.load(feedURL: url)

        #expect(pageContentLoader.requests.count == 1)
        #expect(pageContentLoader.requests.first?.url == url)
        #expect(pageContentLoader.requests.first?.request?.headers?["Accept"]?.contains("application/rss+xml") == true)
        #expect(feed.title == "Solidot")
        #expect(feed.items.first?.title == "奇客资讯")
    }

    @Test func rejectsHTMLAntiBotPageBeforeParsingXML() async throws {
        let pageContentLoader: RecordingPageContentLoader = RecordingPageContentLoader(
            response: Self.antiBotHTML
        )
        let loader: RSSFeedLoader = RSSFeedLoader(
            pageContentLoader: pageContentLoader
        )
        let url: URL = try #require(URL(string: "https://example.com/feed"))

        do {
            _ = try await loader.load(feedURL: url)
            Issue.record("Expected antiBot error")
        } catch let error as RuleExecutionError {
            #expect(error == .antiBot(url: url.absoluteString))
        }
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

private final class RecordingPageContentLoader: PageContentLoader {
    struct Request {
        var url: URL
        var request: RequestConfig?
    }

    private let response: String
    private(set) var requests: [Request] = []

    init(response: String) {
        self.response = response
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.requests.append(
            Request(
                url: url,
                request: request
            )
        )
        return self.response
    }
}
