import Foundation

// 中文注释：ComicSourceSearchLoader 是 ComicSourceRuntime 内部搜索执行链路，只解释 SiteRule-backed source。
// 中文注释：它不写入 Library 列表缓存，RSS/Plugin 后续应走各自 runtime。

struct SearchSourceResult: Hashable {
    var items: [ContentItem]
    var pagination: PaginationResolution?
}

struct ComicSourceSearchLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let urlResolver: URLResolvingService

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        urlResolver: URLResolvingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.urlResolver = urlResolver
    }

    func execute(
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicSearchEntry,
        keyword: String,
        page: Int = 1,
        urlOverride: String? = nil
    ) async throws -> [ContentItem] {
        let result: SearchSourceResult = try await self.executeWithPagination(
            source: source,
            resolvedRule: resolvedRule,
            entry: entry,
            keyword: keyword,
            page: page,
            urlOverride: urlOverride
        )

        return result.items
    }

    func executeWithPagination(
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicSearchEntry,
        keyword: String,
        page: Int = 1,
        urlOverride: String? = nil
    ) async throws -> SearchSourceResult {
        let searchRule: ComicSearchRuleV2 = resolvedRule.searchRule(for: entry)
        let url: URL

        do {
            url = try self.searchURL(
                source: source,
                template: entry.effectiveURL,
                searchRule: searchRule,
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

        let request: RequestConfig? = entry.effectiveRequest
        let context: ListContext = ListContext(
            pageId: entry.pageID,
            tabId: nil,
            sectionId: nil,
            listRuleId: entry.referencedListRuleID,
            sectionRole: nil
        )

        RuleExecutionLogger.log(
            stage: .search,
            event: "request",
            fields: [
                "source": source.id,
                "page": page,
                "searchPage": entry.pageID,
                "searchRule": entry.searchRuleID,
                "keywordLength": keyword.count,
                "url": url.absoluteString
            ]
        )

        let response = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: url,
                requestConfig: request,
                sourceContext: SourceRequestContext(
                    sourceID: source.id,
                    baseURL: URL(string: source.baseURL),
                    purpose: .search,
                    refererURL: url
                )
            )
        )
        let parsedResult: ComicRuleParsedListResult = try self.comicRuleParser.parseSearchResult(
            html: response.content,
            source: source,
            resolvedRule: resolvedRule,
            entry: entry,
            pageURL: response.finalURL,
            currentPage: page
        )
        let items = parsedResult.items

        RuleExecutionLogger.log(
            stage: .search,
            event: "parsed",
            fields: [
                "source": source.id,
                "searchPage": entry.pageID,
                "searchRule": entry.searchRuleID,
                "count": items.count,
                "firstItem": items.first?.id ?? "nil"
            ]
        )

        if items.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .search,
                sourceID: source.id,
                url: url.absoluteString,
                ruleID: entry.searchRuleID
            )
        }

        let pagination: PaginationResolution? = try self.pagination(
            parsedPagination: parsedResult.pagination,
            source: source,
            template: entry.effectiveURL,
            searchRule: searchRule,
            keyword: keyword,
            currentPage: page,
            urlOverride: urlOverride
        )

        return SearchSourceResult(
            items: items,
            pagination: pagination
        )
    }

    private func searchURL(
        source: Source,
        template: String,
        searchRule: ComicSearchRuleV2,
        keyword: String,
        page: Int,
        urlOverride: String?
    ) throws -> URL {
        guard let urlOverride: String = self.nonEmpty(urlOverride) else {
            return try self.urlResolver.searchURL(
                for: source,
                template: template,
                keyword: keyword,
                keywordEncoding: searchRule.keywordEncoding,
                page: page
            )
        }

        return try self.urlResolver.searchURL(
            for: source,
            template: urlOverride,
            keyword: keyword,
            keywordEncoding: searchRule.keywordEncoding,
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
        parsedPagination: PaginationResolution?,
        source: Source,
        template: String,
        searchRule: ComicSearchRuleV2,
        keyword: String,
        currentPage: Int,
        urlOverride: String?
    ) throws -> PaginationResolution? {
        guard let pagination: PaginationRule = searchRule.pagination else {
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
            template: template,
            searchRule: searchRule,
            keyword: keyword,
            currentPage: normalizedPage,
            pagination: pagination,
            urlOverride: urlOverride
        )
        if let extractedURL: String = self.nonEmpty(parsedPagination?.nextURL) {
            return PaginationResolution(
                currentPage: normalizedPage,
                nextPage: parsedPagination?.nextPage ?? normalizedPage + 1,
                nextURL: extractedURL,
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
        template: String,
        searchRule: ComicSearchRuleV2,
        keyword: String,
        currentPage: Int,
        pagination: PaginationRule,
        urlOverride: String?
    ) throws -> URL? {
        guard self.canUsePagePlaceholder(
            template: template,
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
            template: template,
            searchRule: searchRule,
            keyword: keyword,
            page: nextPage,
            urlOverride: urlOverride
        )
    }

    private func canUsePagePlaceholder(
        template: String,
        pagination: PaginationRule,
        urlOverride: String?
    ) -> Bool {
        let template: String = self.nonEmpty(urlOverride) ?? template

        if let pagePlaceholder: String = self.nonEmpty(pagination.pagePlaceholder) {
            return template.contains(pagePlaceholder)
        }

        return template.contains("{page")
    }
}
