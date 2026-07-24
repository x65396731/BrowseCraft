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
        let json: String = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: apiURL,
                requestConfig: request,
                sourceContext: self.requestContext(source: source, purpose: .list, refererURL: fallbackURL)
            )
        ).content
        let jsonObject: Any = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let responseEvaluation = ComicRuleAPIResponseEvaluator.evaluate(
            json: jsonObject,
            responsePolicy: apiRule.responsePolicy
        )
        switch responseEvaluation {
        case .allowParsing:
            break
        case .businessFailure(let message):
            throw RuleExecutionError.sourceAPI(
                stage: .list,
                sourceID: source.id,
                reason: "List API returned error: \(message)"
            )
        }
        let itemPathResolution = ComicRuleJSONResolver.jsonArrayResolution(
            at: apiRule.itemPath,
            in: jsonObject
        )
        guard itemPathResolution.state == .empty || itemPathResolution.state == .nonEmpty else {
            throw RuleExecutionError.apiResponseContract(
                stage: .list,
                sourceID: source.id,
                reason: "List API itemPath \(apiRule.itemPath) resolved as \(itemPathResolution.state.rawValue)"
            )
        }
        let itemObjects: [Any] = itemPathResolution.values
        let sortableItems: [(value: Any, order: Double?)] = itemObjects.map { itemObject in
            let order: Double? = apiRule.orderPath.flatMap { path in
                return ComicRuleJSONResolver.doubleValue(
                    ComicRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                )
            }
            return (value: itemObject, order: order)
        }
        let sortedObjects: [Any] = ComicRuleJSONResolver.sortedValues(sortableItems, sort: apiRule.sort)
        let outputObjects: [Any] = sortedObjects.isEmpty ? itemObjects : sortedObjects

        var items: [ContentItem] = []
        var seenDetailURLs: Set<String> = Set<String>()
        for itemObject: Any in outputObjects {
            guard let title: String = ComicRuleJSONResolver.stringValue(
                ComicRuleJSONResolver.firstJSONValue(at: apiRule.titlePath, in: itemObject)
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.isEmpty == false,
                  let detailURL: String = self.listItemURL(
                    apiRule: apiRule,
                    source: source,
                    templateItem: templateItem,
                    page: page,
                    rootJSON: jsonObject,
                    currentJSON: itemObject,
                    fallbackURL: fallbackURL
                  ),
                  detailURL.isEmpty == false,
                  seenDetailURLs.contains(detailURL) == false else {
                continue
            }

            seenDetailURLs.insert(detailURL)
            let coverURL: String? = self.listItemCoverURL(
                apiRule: apiRule,
                source: source,
                templateItem: templateItem,
                page: page,
                rootJSON: jsonObject,
                currentJSON: itemObject,
                fallbackURL: fallbackURL
            )
            let latestText: String? = apiRule.latestTextPath.flatMap { path in
                return ComicRuleJSONResolver.stringValue(
                    ComicRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            items.append(
                ContentItem(
                    id: Self.stableID(sourceId: source.id, urlString: detailURL),
                    sourceId: source.id,
                    title: title,
                    detailURL: detailURL,
                    coverURL: coverURL,
                    type: listRule.type,
                    latestText: latestText,
                    updatedAt: Date(),
                    listOrder: items.count,
                    listContext: listContext
                )
            )
        }

        RuleExecutionLogger.log(
            stage: .list,
            event: "list-api-parsed",
            fields: [
                "source": source.id,
                "tab": listContext.tabId ?? "nil",
                "listRule": listContext.listRuleId ?? "nil",
                "itemCount": itemObjects.count,
                "count": items.count,
                "firstItem": items.first?.id ?? "nil"
            ]
        )

        if itemObjects.isEmpty == false,
           items.isEmpty {
            throw RuleExecutionError.apiResponseContract(
                stage: .list,
                sourceID: source.id,
                reason: "List API itemPath returned \(itemObjects.count) values, but all item mappings failed"
            )
        }

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

    private func listItemURL(
        apiRule: ListAPIRule,
        source: Source,
        templateItem: ContentItem,
        page: Int,
        rootJSON: Any,
        currentJSON: Any,
        fallbackURL: URL
    ) -> String? {
        if let urlTemplate: String = apiRule.urlTemplate,
           urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let rawURL: String = ComicRuleAPITemplateResolver.replacingTemplatePlaceholders(
                in: urlTemplate,
                source: source,
                item: templateItem,
                page: page,
                rootJSON: rootJSON,
                currentJSON: currentJSON,
                defaultUserAgent: self.defaultUserAgent
            )
            return self.urlResolver.absoluteString(rawURL, baseURLString: fallbackURL.absoluteString)
        }

        guard let urlPath: String = apiRule.urlPath,
              let rawURL: String = ComicRuleJSONResolver.stringValue(
                ComicRuleJSONResolver.firstJSONValue(at: urlPath, in: currentJSON)
              ) else {
            return nil
        }

        return self.urlResolver.absoluteString(rawURL, baseURLString: fallbackURL.absoluteString)
    }

    private func listItemCoverURL(
        apiRule: ListAPIRule,
        source: Source,
        templateItem: ContentItem,
        page: Int,
        rootJSON: Any,
        currentJSON: Any,
        fallbackURL: URL
    ) -> String? {
        if let coverTemplate: String = apiRule.coverTemplate,
           coverTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let rawURL: String = ComicRuleAPITemplateResolver.replacingTemplatePlaceholders(
                in: coverTemplate,
                source: source,
                item: templateItem,
                page: page,
                rootJSON: rootJSON,
                currentJSON: currentJSON,
                defaultUserAgent: self.defaultUserAgent
            )
            return self.urlResolver.absoluteString(rawURL, baseURLString: fallbackURL.absoluteString)
        }

        guard let coverPath: String = apiRule.coverPath,
              let rawURL: String = ComicRuleJSONResolver.stringValue(
                ComicRuleJSONResolver.firstJSONValue(at: coverPath, in: currentJSON)
              ),
              rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return self.urlResolver.absoluteString(rawURL, baseURLString: fallbackURL.absoluteString)
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

    private static func stableID(sourceId: String, urlString: String) -> String {
        let rawID: String = "\(sourceId):\(urlString)"
        let data: Data? = rawID.data(using: .utf8)

        return data?.base64EncodedString() ?? UUID().uuidString
    }
}
