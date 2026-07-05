import Foundation

// 中文注释：RefreshSourceUseCase 是 Sources 页面使用的 App facade；真实 rule-only 实现在 RuleSourceListLoader。
struct RefreshSourceUseCase {
    private let ruleSourceLoader: RuleSourceListLoader

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService
    ) {
        self.ruleSourceLoader = RuleSourceListLoader(
            pageContentLoader: pageContentLoader,
            ruleParser: ruleParser,
            urlResolver: urlResolver
        )
    }

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser,
            urlResolver: urlResolver
        )
    }

    func execute(source: Source, page: Int = 1) async throws -> [ContentItem] {
        return try await self.ruleSourceLoader.execute(source: source, page: page)
    }

    func execute(source: Source, listTab: ListTabRule?, page: Int = 1) async throws -> [ContentItem] {
        return try await self.ruleSourceLoader.execute(
            source: source,
            listTab: listTab,
            page: page
        )
    }
}
