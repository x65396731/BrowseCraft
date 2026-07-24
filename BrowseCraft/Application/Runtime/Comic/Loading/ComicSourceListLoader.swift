import Foundation

// 中文注释：ComicSourceListLoader 是 ComicSourceRuntime 内部列表刷新实现，只处理 SiteRule-backed source。
struct ComicSourceListLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let urlResolver: URLResolvingService
    private let defaultUserAgent: String

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        urlResolver: URLResolvingService,
        defaultUserAgent: String = ""
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.urlResolver = urlResolver
        self.defaultUserAgent = defaultUserAgent
    }

    func execute(source: Source, page: Int = 1) async throws -> [ContentItem] {
        return try await self.execute(source: source, listTab: source.rule.availableListTabs.first, page: page)
    }

    func execute(source: Source, listTab: ListTabRule?, page: Int = 1) async throws -> [ContentItem] {
        let listRule: ListRule = listTab?.list ?? source.rule.list
        let pageRequest: RequestConfig? = source.rule.request(for: listTab)
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
                "url": url.absoluteString,
                "requestScope": pageRequest?.scope?.rawValue ?? "nil",
                "needsWebView": pageRequest?.needsWebView?.description ?? "nil",
                "autoScroll": pageRequest?.autoScroll?.description ?? "nil"
            ]
        )

        if listRule.listAPI?.preferAPI == true {
            do {
                let apiItems: [ContentItem] = try await self.loadListAPI(
                    source: source,
                    listTab: listTab,
                    listRule: listRule,
                    listContext: listContext,
                    page: page,
                    fallbackURL: url
                )

                if apiItems.isEmpty == false {
                    RuleExecutionLogger.log(
                        stage: .list,
                        event: "list-output",
                        fields: [
                            "source": source.id,
                            "tab": listContext.tabId ?? "nil",
                            "listRule": listContext.listRuleId ?? "nil",
                            "count": apiItems.count
                        ]
                    )
                    return apiItems
                }

                RuleExecutionLogger.log(
                    stage: .list,
                    event: "list-api-fallback",
                    fields: [
                        "source": source.id,
                        "tab": listContext.tabId ?? "nil",
                        "listRule": listContext.listRuleId ?? "nil",
                        "reason": "empty"
                    ]
                )
            } catch let error as RuleExecutionError {
                if case .ruleConfiguration = error {
                    throw error
                }
                if case .sourceAPI = error {
                    throw error
                }
                if case .apiResponseContract = error {
                    throw error
                }

                RuleExecutionLogger.log(
                    stage: .list,
                    event: "list-api-fallback",
                    fields: [
                        "source": source.id,
                        "tab": listContext.tabId ?? "nil",
                        "listRule": listContext.listRuleId ?? "nil",
                        "reason": error.localizedDescription
                    ]
                )
            } catch {
                RuleExecutionLogger.log(
                    stage: .list,
                    event: "list-api-fallback",
                    fields: [
                        "source": source.id,
                        "tab": listContext.tabId ?? "nil",
                        "listRule": listContext.listRuleId ?? "nil",
                        "reason": error.localizedDescription
                    ]
                )
            }
        }

        let response = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: url,
                requestConfig: pageRequest,
                sourceContext: self.requestContext(source: source, purpose: .list, refererURL: url)
            )
        )
        let html = response.content
        let items: [ContentItem]
        do {
            items = try self.comicRuleParser.parseList(
                html: html,
                source: source,
                listRule: listRule,
                context: listContext,
                sections: listTab?.sections,
                pageURL: response.finalURL,
                currentPage: page
            )
        } catch {
            throw RuleExecutionError.parserDiagnostics(
                stage: .list,
                sourceID: source.id,
                ruleID: listRule.id,
                url: url.absoluteString,
                operation: "parseList",
                selector: listRule.item,
                htmlPreview: Self.htmlPreview(from: html),
                underlyingDescription: error.localizedDescription
            )
        }

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
            event: "list-output",
            fields: [
                "source": source.id,
                "tab": listContext.tabId ?? "nil",
                "listRule": listContext.listRuleId ?? "nil",
                "count": items.count
            ]
        )
        return items
    }

    private func loadListAPI(
        source: Source,
        listTab: ListTabRule?,
        listRule: ListRule,
        listContext: ListContext,
        page: Int,
        fallbackURL: URL
    ) async throws -> [ContentItem] {
        guard let apiRule: ListAPIRule = listRule.listAPI else {
            return []
        }

        let templateItem: ContentItem = self.templateItem(
            source: source,
            listTab: listTab,
            listRule: listRule,
            fallbackURL: fallbackURL
        )
        let apiURLString: String = ComicRuleAPITemplateResolver.replacingTemplatePlaceholders(
            in: apiRule.url,
            source: source,
            item: templateItem,
            page: page,
            defaultUserAgent: self.defaultUserAgent
        )

        guard let apiURL: URL = URL(string: apiURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .list,
                sourceID: source.id,
                reason: "Invalid list API URL: \(apiURLString)"
            )
        }

        let request: RequestConfig? = ComicRuleAPIRequestResolver.request(
            base: source.rule.request(for: listTab),
            override: apiRule.request,
            source: source,
            item: templateItem,
            page: page,
            defaultUserAgent: self.defaultUserAgent
        )

        RuleExecutionLogger.log(
            stage: .list,
            event: "list-api-request",
            fields: [
                "source": source.id,
                "tab": listContext.tabId ?? "nil",
                "listRule": listContext.listRuleId ?? "nil",
                "apiURL": apiURL.absoluteString,
                "itemPath": apiRule.itemPath,
                "responsePolicyMode": apiRule.responsePolicy?.mode.rawValue ?? "legacy",
                "requestScope": request?.scope?.rawValue ?? "nil",
                "requestMergePolicy": request?.mergePolicy?.rawValue ?? "nil",
                "headerCount": request?.headers?.count ?? 0,
                "headerNames": self.safeHeaderNames(request?.headers)
            ]
        )
        let response: PageContentResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: apiURL,
                requestConfig: request,
                sourceContext: self.requestContext(source: source, purpose: .list, refererURL: fallbackURL)
            )
        )
        let items: [ContentItem] = try self.comicRuleParser.parseListAPIResponse(
            json: response.content,
            finalURL: response.finalURL,
            source: source,
            templateItem: templateItem,
            apiRule: apiRule,
            listPageURL: fallbackURL,
            currentPage: page,
            context: listContext
        )

        RuleExecutionLogger.log(
            stage: .list,
            event: "list-api-parsed",
            fields: [
                "source": source.id,
                "tab": listContext.tabId ?? "nil",
                "listRule": listContext.listRuleId ?? "nil",
                "count": items.count,
                "firstItem": items.first?.id ?? "nil"
            ]
        )

        return items
    }

    private func requestContext(
        source: Source,
        purpose: SourceRequestPurpose,
        refererURL: URL
    ) -> SourceRequestContext {
        return SourceRequestContext(
            sourceID: source.id,
            baseURL: URL(string: source.baseURL),
            purpose: purpose,
            refererURL: refererURL
        )
    }

    private func templateItem(
        source: Source,
        listTab: ListTabRule?,
        listRule: ListRule,
        fallbackURL: URL
    ) -> ContentItem {
        let title: String = listTab?.title ?? listRule.id ?? source.name
        return ContentItem(
            id: "\(source.id):\(listRule.id ?? "list")",
            sourceId: source.id,
            title: title,
            detailURL: fallbackURL.absoluteString,
            coverURL: nil,
            type: listRule.type,
            latestText: nil,
            updatedAt: nil,
            listContext: self.listContext(listTab: listTab, listRule: listRule)
        )
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

    private func safeHeaderNames(_ headers: [String: String]?) -> String {
        guard let headers: [String: String], headers.isEmpty == false else {
            return "none"
        }

        return headers.keys
            .sorted { lhs, rhs in lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending }
            .joined(separator: ",")
    }

    private static func htmlPreview(from html: String) -> String {
        return String(html.prefix(240))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
