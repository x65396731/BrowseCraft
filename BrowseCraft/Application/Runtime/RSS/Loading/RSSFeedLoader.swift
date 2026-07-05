import Foundation

// 中文注释：RSSFeedLoading 是 RSS runtime 对 feed loader 的最小依赖，便于 runtime 测试替换。
protocol RSSFeedLoading {
    func load(feedURL: URL) async throws -> RSSFeed
}

// 中文注释：RSSFeedLoader 负责公开 RSS feed 的字符串加载与解析，不处理登录、Cookie 或 Token。
struct RSSFeedLoader: RSSFeedLoading {
    private let pageContentLoader: PageContentLoader
    private let parser: RSSFeedParser

    init(
        pageContentLoader: PageContentLoader,
        parser: RSSFeedParser = RSSFeedParser()
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
    }

    func load(feedURL: URL) async throws -> RSSFeed {
        let xml: String = try await self.pageContentLoader.getString(
            from: feedURL,
            request: nil
        )
        return try self.parser.parse(xml)
    }
}
