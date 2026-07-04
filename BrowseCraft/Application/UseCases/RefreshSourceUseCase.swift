import Foundation

// 中文注释：RefreshSourceUseCase 是 Sources 页面使用的 App facade；真实 rule-only 实现在 RuleSourceRefreshUseCase。
struct RefreshSourceUseCase {
    private let ruleSourceUseCase: RuleSourceRefreshUseCase

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        contentRepository: ContentRepository
    ) {
        self.ruleSourceUseCase = RuleSourceRefreshUseCase(
            pageContentLoader: pageContentLoader,
            ruleParser: ruleParser,
            urlResolver: urlResolver,
            contentRepository: contentRepository
        )
    }

    init(
        httpClient: HTTPClient,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        contentRepository: ContentRepository
    ) {
        self.init(
            pageContentLoader: httpClient,
            ruleParser: ruleParser,
            urlResolver: urlResolver,
            contentRepository: contentRepository
        )
    }

    func execute(source: Source, page: Int = 1) async throws -> [ContentItem] {
        return try await self.ruleSourceUseCase.execute(source: source, page: page)
    }

    func execute(source: Source, listTab: ListTabRule?, page: Int = 1) async throws -> [ContentItem] {
        return try await self.ruleSourceUseCase.execute(
            source: source,
            listTab: listTab,
            page: page
        )
    }
}
