import Foundation

// 中文注释：ComicRuleSourceListLoader 是 ComicRuleSourceRuntime 内部列表刷新实现，只处理 SiteRule-backed source。
struct ComicRuleSourceListLoader {
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

    /// 中文注释：兼容旧测试和旧装配入口；HTTPClient 本身也是 PageContentLoader 的一种实现。
    init(
        httpClient: HTTPClient,
        comicRuleParser: ComicRuleSourceParsingService,
        urlResolver: URLResolvingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            comicRuleParser: comicRuleParser,
            urlResolver: urlResolver
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

        let html: String = try await self.pageContentLoader.getString(
            from: url,
            request: source.rule.request(for: listTab)
        )
        let items: [ContentItem]
        do {
            items = try self.comicRuleParser.parseList(
                html: html,
                source: source,
                listRule: listRule,
                context: listContext,
                sections: listTab?.sections
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
        let apiURLString: String = ComicRuleAPIResolver.replacingTemplatePlaceholders(
            in: apiRule.url,
            source: source,
            item: templateItem,
            page: page
        )

        guard let apiURL: URL = URL(string: apiURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .list,
                sourceID: source.id,
                reason: "Invalid list API URL: \(apiURLString)"
            )
        }

        RuleExecutionLogger.log(
            stage: .list,
            event: "list-api-request",
            fields: [
                "source": source.id,
                "tab": listContext.tabId ?? "nil",
                "listRule": listContext.listRuleId ?? "nil",
                "apiURL": apiURL.absoluteString,
                "itemPath": apiRule.itemPath
            ]
        )

        let request: RequestConfig? = ComicRuleAPIResolver.request(
            from: apiRule.request ?? source.rule.request(for: listTab),
            source: source,
            item: templateItem,
            page: page
        )
        let json: String = try await self.pageContentLoader.getString(from: apiURL, request: request)
        let jsonObject: Any = try JSONSerialization.jsonObject(with: Data(json.utf8))
        if let apiErrorMessage: String = ComicRuleAPIResolver.apiErrorMessage(in: jsonObject) {
            throw RuleExecutionError.sourceAPI(
                stage: .list,
                sourceID: source.id,
                reason: "List API returned error: \(apiErrorMessage)"
            )
        }
        let itemObjects: [Any] = ComicRuleAPIResolver.jsonValues(at: apiRule.itemPath, in: jsonObject)
        let sortableItems: [(value: Any, order: Double?)] = itemObjects.map { itemObject in
            let order: Double? = apiRule.orderPath.flatMap { path in
                return ComicRuleAPIResolver.doubleValue(
                    ComicRuleAPIResolver.firstJSONValue(at: path, in: itemObject)
                )
            }
            return (value: itemObject, order: order)
        }
        let sortedObjects: [Any] = ComicRuleAPIResolver.sortedValues(sortableItems, sort: apiRule.sort)
        let outputObjects: [Any] = sortedObjects.isEmpty ? itemObjects : sortedObjects

        var items: [ContentItem] = []
        var seenDetailURLs: Set<String> = Set<String>()
        for itemObject: Any in outputObjects {
            guard let title: String = ComicRuleAPIResolver.stringValue(
                ComicRuleAPIResolver.firstJSONValue(at: apiRule.titlePath, in: itemObject)
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
                return ComicRuleAPIResolver.stringValue(
                    ComicRuleAPIResolver.firstJSONValue(at: path, in: itemObject)
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

        return items
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
            let rawURL: String = ComicRuleAPIResolver.replacingTemplatePlaceholders(
                in: urlTemplate,
                source: source,
                item: templateItem,
                page: page,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
            return self.urlResolver.absoluteString(rawURL, baseURLString: fallbackURL.absoluteString)
        }

        guard let urlPath: String = apiRule.urlPath,
              let rawURL: String = ComicRuleAPIResolver.stringValue(
                ComicRuleAPIResolver.firstJSONValue(at: urlPath, in: currentJSON)
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
            let rawURL: String = ComicRuleAPIResolver.replacingTemplatePlaceholders(
                in: coverTemplate,
                source: source,
                item: templateItem,
                page: page,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
            return self.urlResolver.absoluteString(rawURL, baseURLString: fallbackURL.absoluteString)
        }

        guard let coverPath: String = apiRule.coverPath,
              let rawURL: String = ComicRuleAPIResolver.stringValue(
                ComicRuleAPIResolver.firstJSONValue(at: coverPath, in: currentJSON)
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
