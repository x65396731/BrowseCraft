import Foundation

// 中文注释：RefreshSourceUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：抓取源站列表页，解析为标准条目，保存后返回结果。
/// 中文注释：核心流程是 Source + Rule -> Fetch -> Parse -> Normalize -> Store -> Display。
struct RefreshSourceUseCase {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let urlResolver: URLResolvingService
    private let contentRepository: ContentRepository

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService,
        contentRepository: ContentRepository
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.urlResolver = urlResolver
        self.contentRepository = contentRepository
    }

    /// 中文注释：兼容旧测试和旧装配入口；HTTPClient 本身也是 PageContentLoader 的一种实现。
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

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(source: Source, page: Int = 1) async throws -> [ContentItem] {
        return try await self.execute(source: source, listTab: source.rule.availableListTabs.first, page: page)
    }

    func execute(source: Source, listTab: ListTabRule?, page: Int = 1) async throws -> [ContentItem] {
        let listRule: ListRule = listTab?.list ?? source.rule.list
        let url: URL = try self.urlResolver.listURL(for: source, listRule: listRule, page: page)
        let listContext: ListContext = self.listContext(
            listTab: listTab,
            listRule: listRule
        )

        #if DEBUG
        print(
            "[BrowseCraftNavigation] Refresh list " +
            "source=\(source.id) " +
            "tab=\(listTab?.id ?? "default") " +
            "title=\(listTab?.title ?? "default") " +
            "url=\(url.absoluteString)"
        )
        #endif

        let html: String = try await self.pageContentLoader.getString(
            from: url,
            request: source.rule.request(for: listTab)
        )
        let items: [ContentItem] = try self.ruleParser.parseList(
            html: html,
            source: source,
            listRule: listRule,
            context: listContext,
            sections: listTab?.sections
        )

        try self.contentRepository.saveItems(items)
        return items
    }

    private func listContext(listTab: ListTabRule?, listRule: ListRule) -> ListContext {
        if var context: ListContext = listTab?.context {
            if context.listRuleId == nil {
                context.listRuleId = listRule.id
            }

            return context
        }

        // 中文注释：旧 listTabs 没有 PageRule 上下文时，先把 tab id 作为最小入口标识保存下来。
        return ListContext(
            pageId: listTab?.id,
            tabId: listTab?.id,
            sectionId: nil,
            listRuleId: listRule.id,
            sectionRole: .main
        )
    }
}
