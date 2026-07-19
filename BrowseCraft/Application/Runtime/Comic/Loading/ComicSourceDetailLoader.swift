import Foundation

// 中文注释：ComicSourceDetailLoader 是 ComicSourceRuntime 的完整详情加载边界，只处理 SiteRule-backed source。

/// 中文注释：加载并编排单个 Library 条目的完整详情。
struct ComicSourceDetailLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
    }

    /// 中文注释：兼容旧测试和旧装配入口；普通 HTTP 客户端继续可直接作为页面内容加载器使用。
    init(
        httpClient: HTTPClient,
        comicRuleParser: ComicRuleSourceParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            comicRuleParser: comicRuleParser
        )
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(source: Source, item: ContentItem) async throws -> ComicRuleParsedDetail {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)

        RuleExecutionLogger.log(
            stage: .detail,
            event: "request",
            fields: [
                "source": source.id,
                "item": item.id,
                "tab": item.listContext?.tabId ?? "nil",
                "section": item.listContext?.sectionId ?? "nil",
                "listRule": item.listContext?.listRuleId ?? "nil",
                "detailURL": item.detailURL,
                "latestText": item.latestText ?? "nil",
                "requestScope": resolvedRule.primaryDetailRequest?.scope?.rawValue ?? "nil",
                "needsWebView": resolvedRule.primaryDetailRequest?.needsWebView?.description ?? "nil",
                "autoScroll": resolvedRule.primaryDetailRequest?.autoScroll?.description ?? "nil"
            ]
        )

        if shouldTreatDetailURLAsChapter(resolvedRule: resolvedRule, item: item) {
            RuleExecutionLogger.log(
                stage: .detail,
                event: "direct-chapter",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL
                ]
            )

            return ComicRuleParsedDetail(
                metadata: self.fallbackMetadata(item: item),
                chapters: [
                    ChapterLink(
                        title: item.latestText ?? item.title,
                        url: item.detailURL
                    )
                ]
            )
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Invalid detail URL: \(item.detailURL)"
            )
        }

        if let detailRule: DetailRule = resolvedRule.primaryDetailRule,
           self.shouldPreferDetailAPI(detailRule: detailRule),
           self.requiresDetailDocument(detailRule: detailRule) == false,
           let apiDetail: ComicRuleParsedDetail = try await self.loadDetailAPI(
            source: source,
            item: item,
            detailRule: detailRule,
            fallbackRequest: resolvedRule.primaryDetailRequest
           ) {
            RuleExecutionLogger.log(
                stage: .detail,
                event: "preferred-detail-api-output",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL,
                    "count": apiDetail.chapters.count,
                    "firstURL": apiDetail.chapters.first?.url ?? "nil"
                ]
            )

            return self.withItemFallback(apiDetail, item: item)
        }

        let detailHTML: String = try await self.pageContentLoader.getString(
            from: detailURL,
            request: resolvedRule.primaryDetailRequest,
            context: self.requestContext(source: source, refererURL: detailURL)
        )
        var parsedDetail: ComicRuleParsedDetail
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            parsedDetail = try self.comicRuleParser.parseDetail(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
            let parsedChapters: [ChapterLink] = parsedDetail.chapters
            let validParsedChapters: [ChapterLink] = self.validChapters(parsedDetail.chapters)

            if self.shouldUseDetailAPI(detailRule: detailRule, parsedChapters: parsedChapters),
               let apiDetail: ComicRuleParsedDetail = try await self.loadDetailAPI(
                source: source,
                item: item,
                detailRule: detailRule,
                fallbackRequest: resolvedRule.primaryDetailRequest
               ) {
                parsedDetail.chapters = apiDetail.chapters
            } else {
                parsedDetail.chapters = validParsedChapters
                if parsedChapters.isEmpty == false,
                   validParsedChapters.isEmpty,
                   detailRule.chapterAPI == nil {
                    RuleExecutionLogger.log(
                        stage: .detail,
                        event: "detail-api-missing",
                        fields: [
                            "source": source.id,
                            "item": item.id,
                            "detailURL": item.detailURL,
                            "invalidChapterCount": parsedChapters.count,
                            "firstInvalidURL": parsedChapters.first?.url ?? "nil"
                        ]
                    )
                }
            }
        } else {
            parsedDetail = ComicRuleParsedDetail(chapters: [], description: nil)
        }
        parsedDetail = self.withItemFallback(parsedDetail, item: item)

        RuleExecutionLogger.log(
            stage: .detail,
            event: "parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "detailURL": item.detailURL,
                "count": parsedDetail.chapters.count,
                "firstURL": parsedDetail.chapters.first?.url ?? "nil",
                "hasTitle": parsedDetail.metadata.title != nil,
                "hasCover": parsedDetail.metadata.coverURL != nil,
                "hasDescription": parsedDetail.metadata.description != nil
            ]
        )

        if parsedDetail.chapters.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .detail,
                sourceID: source.id,
                url: item.detailURL,
                ruleID: resolvedRule.detailEntry?.ruleID
            )
        }

        return parsedDetail
    }

    private func shouldUseDetailAPI(detailRule: DetailRule, parsedChapters: [ChapterLink]) -> Bool {
        guard let apiRule: DetailChapterAPIRule = detailRule.chapterAPI else {
            return false
        }

        return apiRule.preferAPI == true || parsedChapters.isEmpty || self.hasInvalidChapterURLs(parsedChapters)
    }

    private func shouldPreferDetailAPI(detailRule: DetailRule) -> Bool {
        return detailRule.chapterAPI?.preferAPI == true
    }

    /// 中文注释：chapterAPI 只拥有章节语义；存在详情字段时不能因为 preferAPI 而跳过详情文档。
    private func requiresDetailDocument(detailRule: DetailRule) -> Bool {
        return detailRule.fields != nil
            || self.isNonEmpty(detailRule.title)
            || self.isNonEmpty(detailRule.cover)
    }

    private func isNonEmpty(_ value: String?) -> Bool {
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func loadDetailAPI(
        source: Source,
        item: ContentItem,
        detailRule: DetailRule,
        fallbackRequest: RequestConfig?
    ) async throws -> ComicRuleParsedDetail? {
        guard let apiRule: DetailChapterAPIRule = detailRule.chapterAPI else {
            return nil
        }

        let apiURLString: String = ComicRuleAPITemplateResolver.replacingTemplatePlaceholders(
            in: apiRule.url,
            source: source,
            item: item,
            rootJSON: nil,
            currentJSON: nil
        )

        guard let apiURL: URL = URL(string: apiURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Invalid detail API URL: \(apiURLString)"
            )
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "detail-api-request",
            fields: [
                "source": source.id,
                "item": item.id,
                "apiURL": apiURL.absoluteString,
                "itemPath": apiRule.itemPath,
                "responsePolicyMode": apiRule.responsePolicy?.mode.rawValue ?? "legacy"
            ]
        )

        let request: RequestConfig? = self.detailAPIRequest(
            apiRule: apiRule,
            detailRule: detailRule,
            fallbackRequest: fallbackRequest,
            source: source,
            item: item
        )
        let json: String = try await self.pageContentLoader.getString(
            from: apiURL,
            request: request,
            context: self.requestContext(
                source: source,
                refererURL: URL(string: item.detailURL) ?? apiURL
            )
        )
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
                stage: .detail,
                sourceID: source.id,
                reason: "Detail API returned error: \(message)"
            )
        }
        let itemPathResolution = ComicRuleJSONResolver.jsonArrayResolution(
            at: apiRule.itemPath,
            in: jsonObject
        )
        guard itemPathResolution.state == .empty || itemPathResolution.state == .nonEmpty else {
            throw RuleExecutionError.apiResponseContract(
                stage: .detail,
                sourceID: source.id,
                reason: "Detail API itemPath \(apiRule.itemPath) resolved as \(itemPathResolution.state.rawValue)"
            )
        }
        let itemObjects: [Any] = itemPathResolution.values

        var chapters: [ChapterLink] = []
        var sortableChapters: [(chapter: ChapterLink, order: Double?)] = []
        var seenURLs: Set<String> = Set<String>()

        for itemObject: Any in itemObjects {
            guard let title: String = ComicRuleJSONResolver.stringValue(
                ComicRuleJSONResolver.firstJSONValue(at: apiRule.titlePath, in: itemObject)
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.isEmpty == false,
                  let chapterURL: String = self.chapterURL(
                    apiRule: apiRule,
                    source: source,
                    item: item,
                    rootJSON: jsonObject,
                    currentJSON: itemObject
                  ),
                  chapterURL.isEmpty == false,
                  seenURLs.contains(chapterURL) == false else {
                continue
            }

            seenURLs.insert(chapterURL)
            let subtitle: String? = apiRule.descriptionPath.flatMap { path in
                ComicRuleJSONResolver.stringValue(
                    ComicRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let isRestricted: Bool? = self.chapterFlag(
                path: apiRule.restrictionPath,
                matching: apiRule.restrictedValues,
                in: itemObject
            )
            let isPaid: Bool? = self.chapterFlag(
                path: apiRule.paidPath,
                matching: apiRule.paidValues,
                in: itemObject
            )
            let chapter: ChapterLink = ChapterLink(
                title: title,
                subtitle: subtitle?.isEmpty == false ? subtitle : nil,
                url: chapterURL,
                isRestricted: isRestricted,
                isPaid: isPaid
            )
            let order: Double? = apiRule.orderPath.flatMap { path in
                return ComicRuleJSONResolver.doubleValue(
                    ComicRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                )
            }
            chapters.append(chapter)
            sortableChapters.append((chapter: chapter, order: order))
        }

        let sortedChapters: [ChapterLink] = self.sortedAPIChapters(sortableChapters, sort: apiRule.sort)
        let outputChapters: [ChapterLink] = sortedChapters.isEmpty ? chapters : sortedChapters
        RuleExecutionLogger.log(
            stage: .detail,
            event: "detail-api-parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "itemCount": itemObjects.count,
                "chapterCount": outputChapters.count,
                "firstURL": outputChapters.first?.url ?? "nil"
            ]
        )

        if itemObjects.isEmpty == false,
           outputChapters.isEmpty {
            throw RuleExecutionError.apiResponseContract(
                stage: .detail,
                sourceID: source.id,
                reason: "Detail API itemPath returned \(itemObjects.count) values, but all chapter mappings failed"
            )
        }
        guard outputChapters.isEmpty == false else {
            return nil
        }

        return ComicRuleParsedDetail(
            chapters: outputChapters,
            description: nil
        )
    }

    /// 中文注释：字段缺失或类型不是标量时保留 unknown；只有真实标量才与规则声明值比较。
    private func chapterFlag(
        path: String?,
        matching values: [APIResponseScalar]?,
        in itemObject: Any
    ) -> Bool? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              path.isEmpty == false,
              let values,
              values.isEmpty == false,
              let rawValue = ComicRuleJSONResolver.firstJSONValue(at: path, in: itemObject),
              let scalar = ComicRuleJSONResolver.responseScalar(rawValue) else {
            return nil
        }
        return values.contains(scalar)
    }

    private func fallbackMetadata(item: ContentItem) -> ComicRuleParsedDetailMetadata {
        return ComicRuleParsedDetailMetadata(
            title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : item.title,
            coverURL: item.coverURL
        )
    }

    private func withItemFallback(
        _ detail: ComicRuleParsedDetail,
        item: ContentItem
    ) -> ComicRuleParsedDetail {
        var output: ComicRuleParsedDetail = detail
        let fallback: ComicRuleParsedDetailMetadata = self.fallbackMetadata(item: item)
        output.metadata.title = output.metadata.title ?? fallback.title
        output.metadata.coverURL = output.metadata.coverURL ?? fallback.coverURL
        return output
    }

    private func requestContext(source: Source, refererURL: URL) -> SourceRequestContext {
        return SourceRequestContext(
            sourceID: source.id,
            baseURL: URL(string: source.baseURL),
            purpose: .detail,
            refererURL: refererURL
        )
    }

    private func detailAPIRequest(
        apiRule: DetailChapterAPIRule,
        detailRule: DetailRule,
        fallbackRequest: RequestConfig?,
        source: Source,
        item: ContentItem
    ) -> RequestConfig? {
        return ComicRuleAPIRequestResolver.request(
            base: fallbackRequest ?? detailRule.request,
            override: apiRule.request,
            source: source,
            item: item
        )
    }

    private func chapterURL(
        apiRule: DetailChapterAPIRule,
        source: Source,
        item: ContentItem,
        rootJSON: Any,
        currentJSON: Any
    ) -> String? {
        if let urlTemplate: String = apiRule.urlTemplate,
           urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return ComicRuleAPITemplateResolver.replacingTemplatePlaceholders(
                in: urlTemplate,
                source: source,
                item: item,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
        }

        guard let urlPath: String = apiRule.urlPath,
              let rawURL: String = ComicRuleJSONResolver.stringValue(
                ComicRuleJSONResolver.firstJSONValue(at: urlPath, in: currentJSON)
              ) else {
            return nil
        }

        return URLResolvingService().absoluteString(rawURL, baseURLString: item.detailURL)
    }

    private func sortedAPIChapters(
        _ chapters: [(chapter: ChapterLink, order: Double?)],
        sort: ChapterSort?
    ) -> [ChapterLink] {
        guard let sort: ChapterSort = sort,
              sort != .none,
              chapters.contains(where: { pair in pair.order != nil }) else {
            return []
        }

        return chapters.sorted { lhs, rhs in
            let lhsOrder: Double = lhs.order ?? 0
            let rhsOrder: Double = rhs.order ?? 0

            switch sort {
            case .ascending:
                return lhsOrder < rhsOrder
            case .descending:
                return lhsOrder > rhsOrder
            case .none:
                return false
            }
        }
        .map(\.chapter)
    }

    private func hasInvalidChapterURLs(_ chapters: [ChapterLink]) -> Bool {
        return chapters.contains { chapter in
            return self.isInvalidChapterURL(chapter.url)
        }
    }

    private func validChapters(_ chapters: [ChapterLink]) -> [ChapterLink] {
        return chapters.filter { chapter in
            return self.isInvalidChapterURL(chapter.url) == false
        }
    }

    private func isInvalidChapterURL(_ url: String) -> Bool {
        let lowercasedURL: String = url.lowercased()
        return lowercasedURL.contains("undefined")
            || lowercasedURL.contains("null")
            || lowercasedURL.hasSuffix("/0")
    }

}

func shouldTreatDetailURLAsChapter(resolvedRule: ResolvedSiteRule, item: ContentItem) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return resolvedRule.treatsDetailURLAsChapter
}
