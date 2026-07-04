import Foundation

// 中文注释：RuleSourceListLoader 是 RuleSourceRuntime 内部列表刷新实现，只处理 SiteRule-backed source。
struct RuleSourceListLoader {
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

    func execute(source: Source, page: Int = 1) async throws -> [ContentItem] {
        return try await self.execute(source: source, listTab: source.rule.availableListTabs.first, page: page)
    }

    func execute(source: Source, listTab: ListTabRule?, page: Int = 1) async throws -> [ContentItem] {
        let listRule: ListRule = listTab?.list ?? source.rule.list
        let url: URL
        do {
            url = try self.urlResolver.listURL(for: source, listRule: listRule, page: page)
        } catch {
            throw RuleExecutionError.ruleConfiguration(
                stage: .list,
                sourceID: source.id,
                reason: error.localizedDescription
            )
        }

        let listContext: ListContext = self.listContext(
            listTab: listTab,
            listRule: listRule
        )

        RuleExecutionLogger.log(
            stage: .list,
            event: "request",
            fields: [
                "source": source.id,
                "tab": listTab?.id ?? "default",
                "title": listTab?.title ?? "default",
                "listRule": listRule.id ?? "nil",
                "section": listContext.sectionId ?? "nil",
                "page": page,
                "url": url.absoluteString
            ]
        )

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

        RuleExecutionLogger.log(
            stage: .list,
            event: "parsed",
            fields: [
                "source": source.id,
                "tab": listTab?.id ?? "default",
                "listRule": listRule.id ?? "nil",
                "section": listContext.sectionId ?? "nil",
                "count": items.count,
                "firstItem": items.first?.id ?? "nil"
            ]
        )

        if items.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .list,
                sourceID: source.id,
                url: url.absoluteString,
                ruleID: listRule.id
            )
        }

        RuleExecutionLogger.log(
            stage: .list,
            event: "cache-replace",
            fields: [
                "source": source.id,
                "tab": listContext.tabId ?? "nil",
                "listRule": listContext.listRuleId ?? "nil",
                "count": items.count
            ]
        )

        try self.contentRepository.replaceItems(
            items,
            sourceId: source.id,
            context: listContext
        )
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
