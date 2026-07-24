import Foundation

// 中文注释：ComicSourceDetailLoader 是 ComicSourceRuntime 的完整详情加载边界，只处理 SiteRule-backed source。

/// 中文注释：加载并编排单个 Library 条目的完整详情。
struct ComicSourceDetailLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let defaultUserAgent: String

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        defaultUserAgent: String = ""
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.defaultUserAgent = defaultUserAgent
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

        let detailResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: detailURL,
                requestConfig: resolvedRule.primaryDetailRequest,
                sourceContext: self.requestContext(source: source, refererURL: detailURL)
            )
        )
        let detailHTML = detailResponse.content
        var parsedDetail: ComicRuleParsedDetail
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            parsedDetail = try self.comicRuleParser.parseDetail(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: detailResponse.finalURL.absoluteString,
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
            currentJSON: nil,
            defaultUserAgent: self.defaultUserAgent
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
        let response: PageContentResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: apiURL,
                requestConfig: request,
                sourceContext: self.requestContext(
                    source: source,
                    refererURL: URL(string: item.detailURL) ?? apiURL
                )
            )
        )
        let parsedDetail = try self.comicRuleParser.parseChapterAPIResponse(
            json: response.content,
            finalURL: response.finalURL,
            source: source,
            item: item,
            apiRule: apiRule,
            context: item.listContext
        )
        RuleExecutionLogger.log(
            stage: .detail,
            event: "detail-api-parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "parser": "core",
                "chapterCount": parsedDetail.chapters.count,
                "firstURL": parsedDetail.chapters.first?.url ?? "nil"
            ]
        )
        return parsedDetail.chapters.isEmpty ? nil : parsedDetail
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
            item: item,
            defaultUserAgent: self.defaultUserAgent
        )
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
