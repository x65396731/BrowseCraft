import Foundation

// 中文注释：RuleSourceSearchLoader 是 RuleSourceRuntime 内部搜索执行链路，只解释 SiteRule-backed source。
// 中文注释：它不写入 Library 列表缓存，RSS/Plugin 后续应走各自 runtime。

struct SearchSourceResult: Hashable {
    var items: [ContentItem]
    var pagination: PaginationResolution?
}

struct RuleSourceSearchLoader {
    private let pageContentLoader: PageContentLoader
    private let ruleParser: RuleParsingService
    private let paginationParser: RulePaginationParsingService?
    private let urlResolver: URLResolvingService

    init(
        pageContentLoader: PageContentLoader,
        ruleParser: RuleParsingService,
        urlResolver: URLResolvingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.ruleParser = ruleParser
        self.paginationParser = ruleParser as? RulePaginationParsingService
        self.urlResolver = urlResolver
    }

    /// 中文注释：兼容测试和旧装配入口；HTTPClient 本身也是 PageContentLoader。
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

    func execute(
        source: Source,
        keyword: String,
        page: Int = 1,
        urlOverride: String? = nil
    ) async throws -> [ContentItem] {
        let result: SearchSourceResult = try await self.executeWithPagination(
            source: source,
            keyword: keyword,
            page: page,
            urlOverride: urlOverride
        )

        return result.items
    }

    func executeWithPagination(
        source: Source,
        keyword: String,
        page: Int = 1,
        urlOverride: String? = nil
    ) async throws -> SearchSourceResult {
        let entry: SearchRuleEntry = try self.searchRuleEntry(source: source)
        let url: URL

        do {
            url = try self.searchURL(
                source: source,
                searchRule: entry.rule,
                keyword: keyword,
                page: page,
                urlOverride: urlOverride
            )
        } catch {
            throw RuleExecutionError.ruleConfiguration(
                stage: .search,
                sourceID: source.id,
                reason: error.localizedDescription
            )
        }

        let request: RequestConfig? = entry.effectiveRequest(sharedRequest: source.rule.sharedRequest)
        let context: ListContext = ListContext(
            pageId: entry.page?.id,
            tabId: nil,
            sectionId: nil,
            listRuleId: entry.rule.listRuleRef,
            sectionRole: nil
        )

        RuleExecutionLogger.log(
            stage: .search,
            event: "request",
            fields: [
                "source": source.id,
                "page": page,
                "searchPage": entry.page?.id ?? "nil",
                "searchRule": entry.rule.id ?? "nil",
                "keywordLength": keyword.count,
                "url": url.absoluteString
            ]
        )

        let html: String = try await self.pageContentLoader.getString(
            from: url,
            request: request
        )
        let items: [ContentItem] = try self.ruleParser.parseSearch(
            html: html,
            source: source,
            searchRule: entry.rule,
            context: context
        )

        RuleExecutionLogger.log(
            stage: .search,
            event: "parsed",
            fields: [
                "source": source.id,
                "searchPage": entry.page?.id ?? "nil",
                "searchRule": entry.rule.id ?? "nil",
                "count": items.count,
                "firstItem": items.first?.id ?? "nil"
            ]
        )

        if items.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .search,
                sourceID: source.id,
                url: url.absoluteString,
                ruleID: entry.rule.id
            )
        }

        let pagination: PaginationResolution? = try self.pagination(
            html: html,
            source: source,
            entry: entry,
            keyword: keyword,
            currentPage: page,
            currentURL: url,
            urlOverride: urlOverride
        )

        return SearchSourceResult(
            items: items,
            pagination: pagination
        )
    }

    private func searchRuleEntry(source: Source) throws -> SearchRuleEntry {
        guard let ruleSets: RuleSets = source.rule.ruleSets,
              let searchRules: [SearchRule] = ruleSets.searchRules,
              searchRules.isEmpty == false else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .search,
                sourceID: source.id,
                reason: "Missing search rule."
            )
        }

        if let page: PageRule = source.rule.pages?.first(where: { page in
            return page.type == .search
        }) {
            guard let rule: SearchRule = ruleSets.searchRule(id: page.ruleRefs?.search) else {
                throw RuleExecutionError.ruleConfiguration(
                    stage: .search,
                    sourceID: source.id,
                    reason: "Missing referenced search rule: \(page.ruleRefs?.search ?? "nil")"
                )
            }

            return SearchRuleEntry(page: page, rule: rule)
        }

        return SearchRuleEntry(page: nil, rule: searchRules[0])
    }

    private func searchURL(
        source: Source,
        searchRule: SearchRule,
        keyword: String,
        page: Int,
        urlOverride: String?
    ) throws -> URL {
        guard let urlOverride: String = self.nonEmpty(urlOverride) else {
            return try self.urlResolver.searchURL(
                for: source,
                searchRule: searchRule,
                keyword: keyword,
                page: page
            )
        }

        var overrideSource: Source = source
        overrideSource.rule.urlPatterns?.searchTemplate = nil
        var overrideRule: SearchRule = searchRule
        overrideRule.url = urlOverride

        return try self.urlResolver.searchURL(
            for: overrideSource,
            searchRule: overrideRule,
            keyword: keyword,
            page: page
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        return value
    }

    private func pagination(
        html: String,
        source: Source,
        entry: SearchRuleEntry,
        keyword: String,
        currentPage: Int,
        currentURL: URL,
        urlOverride: String?
    ) throws -> PaginationResolution? {
        guard let pagination: PaginationRule = entry.rule.pagination else {
            return nil
        }

        let normalizedPage: Int = max(currentPage, 1)
        if let maxPages: Int = pagination.maxPages,
           normalizedPage >= maxPages {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: nil,
                nextURL: nil,
                source: nil
            )
        }

        let placeholderURL: URL? = try self.placeholderNextPageURL(
            source: source,
            searchRule: entry.rule,
            keyword: keyword,
            currentPage: normalizedPage,
            pagination: pagination,
            urlOverride: urlOverride
        )
        let extractedURL: String? = try self.paginationParser?.parseNextPageURL(
            html: html,
            source: source,
            pagination: pagination,
            currentURL: currentURL
        )

        if let extractedURL: String = self.nonEmpty(extractedURL) {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: normalizedPage + 1,
                nextURL: self.urlResolver.absoluteString(
                    extractedURL,
                    baseURLString: currentURL.absoluteString
                ),
                source: .nextPageLink
            )
        }

        if let placeholderURL: URL = placeholderURL {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: normalizedPage + 1,
                nextURL: placeholderURL.absoluteString,
                source: .pagePlaceholder
            )
        }

        return PaginationResolution(
            currentPage: normalizedPage,
            nextPage: nil,
            nextURL: nil,
            source: nil
        )
    }

    private func placeholderNextPageURL(
        source: Source,
        searchRule: SearchRule,
        keyword: String,
        currentPage: Int,
        pagination: PaginationRule,
        urlOverride: String?
    ) throws -> URL? {
        guard self.canUsePagePlaceholder(
            source: source,
            searchRule: searchRule,
            pagination: pagination,
            urlOverride: urlOverride
        ) else {
            return nil
        }

        let nextPage: Int = currentPage + 1
        if let maxPages: Int = pagination.maxPages,
           nextPage > maxPages {
            return nil
        }

        return try self.searchURL(
            source: source,
            searchRule: searchRule,
            keyword: keyword,
            page: nextPage,
            urlOverride: urlOverride
        )
    }

    private func canUsePagePlaceholder(
        source: Source,
        searchRule: SearchRule,
        pagination: PaginationRule,
        urlOverride: String?
    ) -> Bool {
        let template: String

        if let urlOverride: String = self.nonEmpty(urlOverride) {
            template = urlOverride
        } else if let searchTemplate: URLTemplateRule = source.rule.urlPatterns?.searchTemplate {
            template = searchTemplate.template
        } else {
            template = searchRule.url
        }

        if let pagePlaceholder: String = self.nonEmpty(pagination.pagePlaceholder) {
            return template.contains(pagePlaceholder)
        }

        return template.contains("{page")
    }
}

private struct SearchRuleEntry {
    var page: PageRule?
    var rule: SearchRule

    func effectiveRequest(sharedRequest: RequestConfig?) -> RequestConfig? {
        return self.rule.request ?? self.page?.request ?? sharedRequest
    }
}
