import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：ComicSourceDetailLoader 是 ComicSourceRuntime 的完整详情加载边界，只处理 SiteRule-backed source。

/// 中文注释：加载并编排单个 Library 条目的完整详情。
public struct ComicSourceDetailLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let defaultUserAgent: String

    public init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        defaultUserAgent: String = ""
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.defaultUserAgent = defaultUserAgent
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    public func execute(
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicDetailEntry,
        item: ContentItem
    ) async throws -> ComicRuleParsedDetail {
        let detailRule: ComicDetailRuleV2 = resolvedRule.detailRule(for: entry)

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
                "requestScope": entry.effectiveRequest?.scope?.rawValue ?? "nil",
                "needsWebView": entry.effectiveRequest?.needsWebView?.description ?? "nil",
                "autoScroll": entry.effectiveRequest?.autoScroll?.description ?? "nil"
            ]
        )

        if shouldTreatDetailURLAsChapter(
            resolvedRule: resolvedRule,
            entry: entry,
            item: item
        ) {
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

        if self.shouldPreferDetailAPI(detailRule: detailRule),
           self.requiresDetailDocument(detailRule: detailRule) == false,
           let apiDetail: ComicRuleParsedDetail = try await self.loadDetailAPI(
            source: source,
            resolvedRule: resolvedRule,
            entry: entry,
            item: item,
            detailRule: detailRule,
            fallbackRequest: entry.effectiveChapterAPIRequest
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
                requestConfig: entry.effectiveRequest,
                sourceContext: self.requestContext(source: source, refererURL: detailURL)
            )
        )
        let detailHTML = detailResponse.content
        var parsedDetail: ComicRuleParsedDetail
        parsedDetail = try self.comicRuleParser.parseDetail(
            html: detailHTML,
            source: source,
            resolvedRule: resolvedRule,
            entry: entry,
            item: item,
            pageURL: detailResponse.finalURL.absoluteString
        )
        let parsedChapters: [ChapterLink] = parsedDetail.chapters
        let validParsedChapters: [ChapterLink] = self.validChapters(parsedDetail.chapters)

        if self.shouldUseDetailAPI(detailRule: detailRule, parsedChapters: parsedChapters),
           let apiDetail: ComicRuleParsedDetail = try await self.loadDetailAPI(
            source: source,
            resolvedRule: resolvedRule,
            entry: entry,
            item: item,
            detailRule: detailRule,
            fallbackRequest: entry.effectiveChapterAPIRequest
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
                ruleID: entry.detailRuleID
            )
        }

        return parsedDetail
    }

    private func shouldUseDetailAPI(detailRule: ComicDetailRuleV2, parsedChapters: [ChapterLink]) -> Bool {
        guard let apiRule: DetailChapterAPIRule = detailRule.chapterAPI else {
            return false
        }

        return apiRule.preferAPI == true || parsedChapters.isEmpty || self.hasInvalidChapterURLs(parsedChapters)
    }

    private func shouldPreferDetailAPI(detailRule: ComicDetailRuleV2) -> Bool {
        return detailRule.chapterAPI?.preferAPI == true
    }

    /// 中文注释：chapterAPI 只拥有章节语义；存在详情字段时不能因为 preferAPI 而跳过详情文档。
    private func requiresDetailDocument(detailRule: ComicDetailRuleV2) -> Bool {
        return detailRule.fields != nil
    }

    private func loadDetailAPI(
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicDetailEntry,
        item: ContentItem,
        detailRule: ComicDetailRuleV2,
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
            resolvedRule: resolvedRule,
            entry: entry,
            item: item
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
        fallbackRequest: RequestConfig?,
        source: Source,
        item: ContentItem
    ) -> RequestConfig? {
        return ComicRuleAPIRequestResolver.request(
            base: fallbackRequest,
            override: nil,
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

func shouldTreatDetailURLAsChapter(
    resolvedRule: ResolvedComicSiteRuleV2,
    entry: ResolvedComicDetailEntry,
    item: ContentItem
) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return resolvedRule.detailRule(for: entry).treatDetailURLAsChapter
}
