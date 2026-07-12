import Foundation

// 中文注释：RSSFeedLoading 是 RSS runtime 对 feed loader 的最小依赖，便于 runtime 测试替换。
protocol RSSFeedLoading {
    func load(feedURL: URL) async throws -> RSSFeed
}

// 中文注释：RSSFeedLoader 负责公开 RSS feed 的原始 XML 加载与映射，不处理登录、Cookie 或 Token。
struct RSSFeedLoader: RSSFeedLoading {
    private let pageContentLoader: PageContentLoader
    private let mapper: RSSFeedMapper

    init(
        pageContentLoader: PageContentLoader,
        mapper: RSSFeedMapper = RSSFeedMapper()
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
    }

    func load(feedURL: URL) async throws -> RSSFeed {
        let requestConfig: RequestConfig = RequestConfig(
            mergePolicy: .override,
            headers: APIRequestHeaders.rssFeedHeaders()
        )

        if let dataLoader: PageDataLoader = self.pageContentLoader as? PageDataLoader {
            let data: Data = try await dataLoader.getData(from: feedURL, request: requestConfig)
            return try self.mapper.map(data)
        }

        let xml: String = try await self.pageContentLoader.getString(from: feedURL, request: requestConfig)
        return try self.mapper.map(xml)
    }
}
